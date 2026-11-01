/* mhrd-session — один сеанс RDP в окремому процесі (SPEC → «Архітектура»).
 *
 * Застосунок запускає цей процес і надсилає MSG_CONNECT (налаштування + пароль) у stdin.
 * Падіння тут не зачіпає застосунок і інші сеанси.
 *
 * Два режими показу:
 *  - nativeWindow (десктоп): процес сам відкриває вікно (window_sdl.c) — картинка прямо на
 *    відеокарту, ввід прямо в FreeRDP. FreeRDP працює в окремому потоці, вікно — в головному.
 *    Таке вікно живе незалежно від застосунку: закрили MHRD — сеанс працює далі.
 *  - без вікна (Android): картинка у спільній пам'яті, ділянки — подіями в stdout, ввід — з stdin.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/addin.h>
#include <freerdp/channels/cliprdr.h>
#include <freerdp/client.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/client/disp.h>
#include <freerdp/codec/h264.h>
#include <freerdp/error.h>
#include <freerdp/event.h>
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>
#include <winpr/path.h>
#include <winpr/string.h>
#include <winpr/synch.h>
#include <winpr/winsock.h>
#include <winpr/wlog.h>

#include <cjson/cJSON.h>

#include "clipboard.h"
#include "proto.h"
#include "shm.h"
#include "window_sdl.h"

#define RECONNECT_MAX 5 /* спроб перепідключення, далі — відключення */

typedef struct
{
	rdpClientContext common;
	char* certPin;          /* відбиток, якому користувач уже довіряє (з налаштувань ПК) */
	BOOL certRejected;      /* користувач відмовився довіряти сертифікату */
	BOOL noCredentials;     /* пароля немає — застосунок має спитати сам */
	BOOL userDisconnect;    /* застосунок попросив відключитись */
	ShmBuffer shm;
	MhrdClipboard* clipboard; /* NULL — буфер обміну для цього ПК вимкнено */
	DispClientContext* disp;  /* канал Display Control; NULL — сервер не вміє міняти роздільність */
	BOOL dispReady;           /* сервер надіслав свої можливості — можна просити нову роздільність */
	BOOL painted;             /* сервер уже намалював перший кадр: раніше запити на зміну роздільності
	                           * Windows ігнорує (так само чекають клієнти FreeRDP) */
	UINT32 wantWidth, wantHeight; /* запит, що прийшов раніше, ніж канал був готовий */
	UINT32 desktopScale;          /* масштаб інтерфейсу на ПК, % (як у ОС клієнта) */
	UINT32 deviceScale;           /* 100 / 140 / 180 — MS-RDPBCGR */

	BOOL nativeWindow;            /* власне вікно сеансу (десктоп) */
	WindowConfig win;
	char* winStrings[19];      /* копії рядків для win (живуть до кінця процесу) */
	volatile LONG reconnecting;   /* зв'язок відновлюється — ввід із вікна не надсилаємо */
	CRITICAL_SECTION bufLock;     /* буфер кадру: FreeRDP замінює, вікно читає */
	/* Ввід із вікна (свій потік) іде у FreeRDP лише під цим замком і лише коли [online]: потік FreeRDP
	 * знімає [online] під ним же перед перепідключенням і відключенням — тож ввід ніколи не потрапить
	 * у транспорт чи канал, які саме перестворюються або звільняються. */
	CRITICAL_SECTION inputLock;
	BOOL online;
} MhrdContext;

static void set_online(MhrdContext* m, BOOL on)
{
	EnterCriticalSection(&m->inputLock);
	m->online = on;
	LeaveCriticalSection(&m->inputLock);
}

static void send_monitor_layout(MhrdContext* m, UINT32 width, UINT32 height);
static SSIZE_T mhrd_retry_dialog(freerdp* instance, const char* what, size_t current, void* userarg);

/* ── Події до застосунку ───────────────────────────────────────── */

static void send_state(uint8_t state)
{
	proto_send(EVT_STATE, &state, 1);
}

static void send_surface(MhrdContext* m, UINT32 width, UINT32 height, UINT32 stride)
{
	uint8_t buf[12 + sizeof(m->shm.name)];
	put_u32(buf, width);
	put_u32(buf + 4, height);
	put_u32(buf + 8, stride);
	const size_t n = strlen(m->shm.name);
	memcpy(buf + 12, m->shm.name, n);
	proto_send(EVT_SURFACE, buf, (uint32_t)(12 + n));
}

static uint8_t classify(MhrdContext* m, UINT32 code, UINT32 errInfo)
{
	if (m->userDisconnect)
		return DISC_USER_REQUEST;
	if (m->certRejected)
		return DISC_CERT_REJECTED;
	if (m->noCredentials)
		return DISC_NO_CREDENTIALS;
	switch (code)
	{
		case FREERDP_ERROR_AUTHENTICATION_FAILED:
		case FREERDP_ERROR_CONNECT_LOGON_FAILURE:
		case FREERDP_ERROR_CONNECT_WRONG_PASSWORD:
			return DISC_AUTH_FAILED;
		case FREERDP_ERROR_CONNECT_ACCOUNT_LOCKED_OUT:
		case FREERDP_ERROR_CONNECT_ACCOUNT_DISABLED:
		case FREERDP_ERROR_CONNECT_ACCOUNT_RESTRICTION:
		case FREERDP_ERROR_CONNECT_ACCOUNT_EXPIRED:
			return DISC_ACCOUNT_LOCKED;
		case FREERDP_ERROR_CONNECT_PASSWORD_EXPIRED:
		case FREERDP_ERROR_CONNECT_PASSWORD_CERTAINLY_EXPIRED:
		case FREERDP_ERROR_CONNECT_PASSWORD_MUST_CHANGE:
			return DISC_PASSWORD_EXPIRED;
		case FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS:
			return DISC_NO_CREDENTIALS;
		case FREERDP_ERROR_DNS_ERROR:
		case FREERDP_ERROR_DNS_NAME_NOT_FOUND:
		case FREERDP_ERROR_CONNECT_FAILED:
		case FREERDP_ERROR_CONNECT_TRANSPORT_FAILED:
			return DISC_NETWORK;
		case FREERDP_ERROR_TLS_CONNECT_FAILED:
			return DISC_TLS;
		case FREERDP_ERROR_SERVER_DENIED_CONNECTION:
			return DISC_SERVER_DENIED;
		default:
			break;
	}
	switch (errInfo)
	{
		case ERRINFO_LOGOFF_BY_USER:
		case ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER:
		case ERRINFO_RPC_INITIATED_LOGOFF:
		case ERRINFO_RPC_INITIATED_DISCONNECT:
			return DISC_SERVER_LOGOFF;
		case ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION:
			return DISC_OTHER_CONNECTION;
		case ERRINFO_SUCCESS:
			return code == FREERDP_ERROR_SUCCESS ? DISC_SERVER_LOGOFF : DISC_OTHER;
		default:
			return DISC_OTHER;
	}
}

static void send_disconnected(MhrdContext* m)
{
	rdpContext* ctx = &m->common.context;
	const UINT32 code = freerdp_get_last_error(ctx);
	const UINT32 errInfo = freerdp_error_info(ctx->instance);
	const char* text = freerdp_get_last_error_string(code);
	if (!text)
		text = "";
	const size_t n = strlen(text);
	uint8_t* buf = malloc(5 + n);
	if (!buf)
		return;
	buf[0] = classify(m, code, errInfo);
	put_u32(buf + 1, code);
	memcpy(buf + 5, text, n);
	proto_send(EVT_DISCONNECTED, buf, (uint32_t)(5 + n));
	free(buf);
}

/* ── Колбеки FreeRDP ───────────────────────────────────────────── */

static BOOL mhrd_begin_paint(rdpContext* ctx)
{
	rdpGdi* gdi = ctx->gdi;
	gdi->primary->hdc->hwnd->invalid->null = TRUE;
	gdi->primary->hdc->hwnd->ninvalid = 0;
	return TRUE;
}

static BOOL mhrd_end_paint(rdpContext* ctx)
{
	MhrdContext* m = (MhrdContext*)ctx;
	rdpGdi* gdi = ctx->gdi;
	const HGDI_RGN inv = gdi->primary->hdc->hwnd->invalid;
	if (inv->null || inv->w <= 0 || inv->h <= 0)
		return TRUE;

	if (m->nativeWindow)
		window_post_frame(inv->x, inv->y, inv->w, inv->h); /* альфу вікно ігнорує (XRGB) */
	else
	{
		/* Сервер не завжди заповнює альфа-канал, а Flutter малює BGRA з прозорістю. */
		uint8_t* base = (uint8_t*)m->shm.data;
		for (INT32 y = inv->y; y < inv->y + inv->h; y++)
		{
			uint8_t* p = base + (size_t)y * gdi->stride + (size_t)inv->x * 4 + 3;
			for (INT32 x = 0; x < inv->w; x++, p += 4)
				*p = 0xFF;
		}

		uint8_t buf[16];
		put_u32(buf, (uint32_t)inv->x);
		put_u32(buf + 4, (uint32_t)inv->y);
		put_u32(buf + 8, (uint32_t)inv->w);
		put_u32(buf + 12, (uint32_t)inv->h);
		proto_send(EVT_FRAME, buf, sizeof(buf));
	}

	/* Перший кадр — сеанс готовий; відкладений запит на зміну роздільності надсилаємо зараз. */
	if (!m->painted)
	{
		m->painted = TRUE;
		if (m->wantWidth && m->wantHeight)
			send_monitor_layout(m, m->wantWidth, m->wantHeight);
	}
	return TRUE;
}

/* Нова спільна пам'ять під розмір екрана; стара звільняється після перемикання GDI. */
static BOOL alloc_surface(MhrdContext* m, UINT32 width, UINT32 height, BOOL resize)
{
	rdpContext* ctx = &m->common.context;
	const UINT32 stride = width * 4;
	ShmBuffer next;
	if (!shm_create(&next, (size_t)stride * height))
		return FALSE;
	/* Під замком: вікно не має читати старий буфер, поки його звільняємо. */
	EnterCriticalSection(&m->bufLock);
	BOOL ok = resize ? gdi_resize_ex(ctx->gdi, width, height, stride, PIXEL_FORMAT_BGRA32, next.data, NULL)
	                 : gdi_init_ex(ctx->instance, PIXEL_FORMAT_BGRA32, stride, next.data, NULL);
	if (ok)
	{
		ShmBuffer old = m->shm;
		m->shm = next;
		shm_free(&old);
	}
	LeaveCriticalSection(&m->bufLock);
	if (!ok)
	{
		shm_free(&next);
		return FALSE;
	}
	if (m->nativeWindow)
		window_post_surface();
	else
		send_surface(m, width, height, stride);
	return TRUE;
}

static BOOL mhrd_desktop_resize(rdpContext* ctx)
{
	rdpSettings* s = ctx->settings;
	return alloc_surface((MhrdContext*)ctx, freerdp_settings_get_uint32(s, FreeRDP_DesktopWidth),
	                     freerdp_settings_get_uint32(s, FreeRDP_DesktopHeight), TRUE);
}

/* ── Зміна роздільності (Display Control) ─────────────────────── */

/* Просить сервер змінити роздільність. Ширина — парна, обидва розміри 200–8192 (MS-RDPEDISP). */
static void send_monitor_layout(MhrdContext* m, UINT32 width, UINT32 height)
{
	if (width < DISPLAY_CONTROL_MIN_MONITOR_WIDTH)
		width = DISPLAY_CONTROL_MIN_MONITOR_WIDTH;
	if (width > DISPLAY_CONTROL_MAX_MONITOR_WIDTH)
		width = DISPLAY_CONTROL_MAX_MONITOR_WIDTH;
	if (height < DISPLAY_CONTROL_MIN_MONITOR_HEIGHT)
		height = DISPLAY_CONTROL_MIN_MONITOR_HEIGHT;
	if (height > DISPLAY_CONTROL_MAX_MONITOR_HEIGHT)
		height = DISPLAY_CONTROL_MAX_MONITOR_HEIGHT;
	width &= ~1u;

	/* Кличуть і потік FreeRDP, і вікно — канал і запит під inputLock (замок повторно входимий). */
	EnterCriticalSection(&m->inputLock);
	if (!m->online || !m->disp || !m->dispReady || !m->painted)
	{
		m->wantWidth = width; /* надішлемо, щойно канал буде готовий і сеанс намалює перший кадр */
		m->wantHeight = height;
		LeaveCriticalSection(&m->inputLock);
		return;
	}
	m->wantWidth = m->wantHeight = 0;
	DISPLAY_CONTROL_MONITOR_LAYOUT layout = { 0 };
	layout.Flags = DISPLAY_CONTROL_MONITOR_PRIMARY;
	layout.Width = width;
	layout.Height = height;
	/* Фізичний розмір у мм для 96 DPI — сервер використовує його для масштабу. */
	layout.PhysicalWidth = width * 254 / 960;
	layout.PhysicalHeight = height * 254 / 960;
	layout.DesktopScaleFactor = m->desktopScale;
	layout.DeviceScaleFactor = m->deviceScale;
	UINT rc = m->disp->SendMonitorLayout(m->disp, 1, &layout);
	(void)rc;
	LeaveCriticalSection(&m->inputLock);
}

static UINT mhrd_disp_caps(DispClientContext* disp, UINT32 maxMonitors, UINT32 factorA, UINT32 factorB)
{
	(void)maxMonitors;
	(void)factorA;
	(void)factorB;
	MhrdContext* m = (MhrdContext*)disp->custom;
	m->dispReady = TRUE;
	if (m->painted && m->wantWidth && m->wantHeight)
		send_monitor_layout(m, m->wantWidth, m->wantHeight);
	return CHANNEL_RC_OK;
}

/* Буфер обміну й Display Control — наші; решту (GFX → малювання в GDI тощо) робить
 * стандартний обробник. */
static void mhrd_channel_connected(void* context, const ChannelConnectedEventArgs* e)
{
	MhrdContext* m = (MhrdContext*)context;
	WLog_INFO("mhrd", "channel connected: %s", e->name);
	if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
	{
		if (m->clipboard)
			clipboard_attach(m->clipboard, (CliprdrClientContext*)e->pInterface);
	}
	else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
	{
		EnterCriticalSection(&m->inputLock); /* вікно може саме просити нову роздільність */
		m->disp = (DispClientContext*)e->pInterface;
		m->disp->custom = m;
		m->disp->DisplayControlCaps = mhrd_disp_caps;
		LeaveCriticalSection(&m->inputLock);
	}
	else
		freerdp_client_OnChannelConnectedEventHandler(context, e);
}

static void mhrd_channel_disconnected(void* context, const ChannelDisconnectedEventArgs* e)
{
	MhrdContext* m = (MhrdContext*)context;
	if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
	{
		if (m->clipboard)
			clipboard_detach(m->clipboard);
	}
	else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
	{
		EnterCriticalSection(&m->inputLock);
		m->disp = NULL;
		m->dispReady = FALSE;
		LeaveCriticalSection(&m->inputLock);
	}
	else
		freerdp_client_OnChannelDisconnectedEventHandler(context, e);
}

/* Чи є робочий декодер H.264 (у FreeRDP він вибирає підсистему сам; немає жодної — NULL). */
static BOOL h264_available(void)
{
	H264_CONTEXT* h = h264_context_new(FALSE);
	if (!h)
		return FALSE;
	h264_context_free(h);
	return TRUE;
}

static BOOL mhrd_pre_connect(freerdp* instance)
{
	rdpContext* ctx = instance->context;
	rdpSettings* s = ctx->settings;
	/* Графічний конвеєр (GFX): RemoteFX progressive, planar, ClearCodec — у рази менше трафіку,
	 * ніж класичні бітмапи. H.264 — лише якщо декодер справді запускається на цьому ПК
	 * (Media Foundation; у Windows N його може не бути) — інакше сервер слав би кадри, які
	 * нічим показати. AVC444 — повний колір без розмиття тексту, AVC420 — запасний. */
	freerdp_settings_set_bool(s, FreeRDP_SupportGraphicsPipeline, TRUE);
	const BOOL h264 = h264_available();
	WLog_INFO("mhrd", "video: h264=%d", h264);
	freerdp_settings_set_bool(s, FreeRDP_GfxH264, h264);
	freerdp_settings_set_bool(s, FreeRDP_GfxAVC444, h264);
	freerdp_settings_set_bool(s, FreeRDP_GfxAVC444v2, h264);
	freerdp_settings_set_bool(s, FreeRDP_GfxProgressive, TRUE);
	freerdp_settings_set_bool(s, FreeRDP_GfxProgressiveV2, TRUE);
	freerdp_settings_set_bool(s, FreeRDP_GfxPlanar, TRUE);
	freerdp_settings_set_bool(s, FreeRDP_RemoteFxCodec, TRUE);
	/* Зміна роздільності на льоту під розмір вікна (канал Display Control). */
	freerdp_settings_set_bool(s, FreeRDP_SupportDisplayControl, TRUE);
	freerdp_settings_set_bool(s, FreeRDP_DynamicResolutionUpdate, TRUE);
	/* Сервер сам міряє канал і на повільному вимикає шпалери, анімації тощо. */
	freerdp_set_connection_type(s, CONNECTION_TYPE_AUTODETECT);
	freerdp_settings_set_bool(s, FreeRDP_NetworkAutoDetect, TRUE);
	freerdp_settings_set_uint32(s, FreeRDP_OsMajorType, OSMAJORTYPE_WINDOWS);
	freerdp_settings_set_uint32(s, FreeRDP_OsMinorType, OSMINORTYPE_WINDOWS_NT);

	/* Що пропонуємо серверу: якщо мікрофон тут увімкнено, а канал AUDIO_INPUT у журналі так і не
	 * з'явився — сервер сам відмовився. Так буває в адміністративному сеансі (ConsoleSession:
	 * Windows туди мікрофон не передає) або коли запис заборонено політикою сервера. */
	WLog_INFO("mhrd", "route: proxyType=%" PRIu32 " proxy=%s:%" PRIu16 " gateway=%d",
	          freerdp_settings_get_uint32(s, FreeRDP_ProxyType),
	          freerdp_settings_get_string(s, FreeRDP_ProxyHostname)
	              ? freerdp_settings_get_string(s, FreeRDP_ProxyHostname)
	              : "-",
	          freerdp_settings_get_uint16(s, FreeRDP_ProxyPort), freerdp_settings_get_bool(s, FreeRDP_GatewayEnabled));
	WLog_INFO("mhrd", "audio: playback=%d remoteConsole=%d capture=%d",
	          freerdp_settings_get_bool(s, FreeRDP_AudioPlayback),
	          freerdp_settings_get_bool(s, FreeRDP_RemoteConsoleAudio),
	          freerdp_settings_get_bool(s, FreeRDP_AudioCapture));

	MhrdContext* m = (MhrdContext*)ctx;
	if (freerdp_settings_get_bool(s, FreeRDP_RedirectClipboard))
		m->clipboard = clipboard_new();
	if (!m->clipboard)
		freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, FALSE);

	/* Самі канали (cliprdr, rdpsnd, audin, rdpgfx — за налаштуваннями) завантажує FreeRDP
	 * після PreConnect через instance->LoadChannels; тут лише підписка на їхнє підключення. */
	PubSub_SubscribeChannelConnected(ctx->pubSub, mhrd_channel_connected);
	PubSub_SubscribeChannelDisconnected(ctx->pubSub, mhrd_channel_disconnected);
	return TRUE;
}

static BOOL mhrd_post_connect(freerdp* instance)
{
	rdpContext* ctx = instance->context;
	rdpSettings* s = ctx->settings;
	if (!alloc_surface((MhrdContext*)ctx, freerdp_settings_get_uint32(s, FreeRDP_DesktopWidth),
	                   freerdp_settings_get_uint32(s, FreeRDP_DesktopHeight), FALSE))
		return FALSE;
	ctx->update->BeginPaint = mhrd_begin_paint;
	ctx->update->EndPaint = mhrd_end_paint;
	ctx->update->DesktopResize = mhrd_desktop_resize;
	send_state(2);
	return TRUE;
}

static void mhrd_post_disconnect(freerdp* instance)
{
	gdi_free(instance);
}

/* Облікові дані приходять лише з MSG_CONNECT. Питати в консолі не можна: stdin — це канал. */
static BOOL mhrd_authenticate(freerdp* instance, char** username, char** password, char** domain,
                              rdp_auth_reason reason)
{
	(void)username;
	(void)domain;
	(void)reason;
	if (password && *password && **password)
		return TRUE;
	((MhrdContext*)instance->context)->noCredentials = TRUE;
	return FALSE;
}

/* Сертифікат сервера: збігається з certPin — продовжуємо; інакше питаємо застосунок і чекаємо.
 * Повертаємо 2 («довіряти в цьому сеансі»), бо пам'ятає довіру сам застосунок (certPin),
 * а не сховище FreeRDP. */
static DWORD mhrd_verify_certificate(freerdp* instance, const char* host, UINT16 port, const char* common_name,
                                     const char* subject, const char* issuer, const char* fingerprint, DWORD flags)
{
	MhrdContext* m = (MhrdContext*)instance->context;
	if (m->certPin && fingerprint && strcmp(m->certPin, fingerprint) == 0)
		return 2;

	cJSON* j = cJSON_CreateObject();
	cJSON_AddStringToObject(j, "host", host ? host : "");
	cJSON_AddNumberToObject(j, "port", port);
	cJSON_AddStringToObject(j, "commonName", common_name ? common_name : "");
	cJSON_AddStringToObject(j, "subject", subject ? subject : "");
	cJSON_AddStringToObject(j, "issuer", issuer ? issuer : "");
	cJSON_AddStringToObject(j, "fingerprint", fingerprint ? fingerprint : "");
	cJSON_AddNumberToObject(j, "flags", flags);
	cJSON_AddBoolToObject(j, "changed", m->certPin != NULL);
	char* text = cJSON_PrintUnformatted(j);
	cJSON_Delete(j);
	if (!text)
		return 0;
	proto_send(EVT_CERTIFICATE, text, (uint32_t)strlen(text));
	cJSON_free(text);

	for (;;)
	{
		ProtoMsg* msg = proto_wait(INFINITE);
		if (!msg)
			break; /* застосунок закрився — спитати нікого, не довіряємо */
		const uint8_t type = msg->type;
		const BOOL accept = msg->len >= 1 && msg->data[0] != 0;
		free(msg);
		if (type == MSG_CERT_ANSWER)
		{
			m->certRejected = !accept;
			return accept ? 2 : 0;
		}
		if (type == MSG_DISCONNECT)
		{
			m->userDisconnect = TRUE;
			return 0;
		}
		/* ввід до підключення ігноруємо */
	}
	return 0;
}

static DWORD mhrd_verify_changed_certificate(freerdp* instance, const char* host, UINT16 port,
                                             const char* common_name, const char* subject, const char* issuer,
                                             const char* fingerprint, const char* old_subject,
                                             const char* old_issuer, const char* old_fingerprint, DWORD flags)
{
	(void)old_subject;
	(void)old_issuer;
	(void)old_fingerprint;
	return mhrd_verify_certificate(instance, host, port, common_name, subject, issuer, fingerprint, flags);
}

static int mhrd_logon_error_info(freerdp* instance, UINT32 data, UINT32 type)
{
	(void)instance;
	(void)data;
	(void)type;
	return 1;
}

static BOOL mhrd_client_new(freerdp* instance, rdpContext* context)
{
	(void)context;
	instance->PreConnect = mhrd_pre_connect;
	instance->PostConnect = mhrd_post_connect;
	instance->PostDisconnect = mhrd_post_disconnect;
	instance->AuthenticateEx = mhrd_authenticate;
	instance->VerifyCertificateEx = mhrd_verify_certificate;
	instance->VerifyChangedCertificateEx = mhrd_verify_changed_certificate;
	instance->LogonErrorInfo = mhrd_logon_error_info;
	instance->RetryDialog = mhrd_retry_dialog;
	return TRUE;
}

static void mhrd_client_free(freerdp* instance, rdpContext* context)
{
	(void)instance;
	MhrdContext* m = (MhrdContext*)context;
	free(m->certPin);
	m->certPin = NULL;
	clipboard_free(m->clipboard);
	m->clipboard = NULL;
	shm_free(&m->shm);
}

/* ── Налаштування з MSG_CONNECT ────────────────────────────────── */

static const char* jstr(const cJSON* j, const char* key)
{
	const cJSON* v = cJSON_GetObjectItemCaseSensitive(j, key);
	return cJSON_IsString(v) && v->valuestring[0] ? v->valuestring : NULL;
}

static int jint(const cJSON* j, const char* key, int fallback)
{
	const cJSON* v = cJSON_GetObjectItemCaseSensitive(j, key);
	return cJSON_IsNumber(v) ? v->valueint : fallback;
}

static BOOL jbool(const cJSON* j, const char* key, BOOL fallback)
{
	const cJSON* v = cJSON_GetObjectItemCaseSensitive(j, key);
	return cJSON_IsBool(v) ? cJSON_IsTrue(v) : fallback;
}

/* Затирає пароль у розібраному JSON перед звільненням. */
static void wipe_string(cJSON* j, const char* key)
{
	cJSON* v = cJSON_GetObjectItemCaseSensitive(j, key);
	if (cJSON_IsString(v))
		memset(v->valuestring, 0, strlen(v->valuestring));
}

/* Проксі (SPEC → «Інші маршрути»): {type: "socks5"|"http", host, port, username?, password?}.
 * Немає об'єкта — напряму. FreeRDP сам іде через проксі на рівні TCP. */
static BOOL apply_proxy(rdpSettings* s, const cJSON* p)
{
	if (!p)
		return TRUE;
	const char* type = jstr(p, "type");
	const char* host = jstr(p, "host");
	if (!host || !host[0])
		return FALSE;
	const char* user = jstr(p, "username");
	const char* pass = jstr(p, "password");
	return freerdp_settings_set_uint32(s, FreeRDP_ProxyType,
	                                   type && strcmp(type, "http") == 0 ? PROXY_TYPE_HTTP : PROXY_TYPE_SOCKS) &&
	       freerdp_settings_set_string(s, FreeRDP_ProxyHostname, host) &&
	       freerdp_settings_set_uint16(s, FreeRDP_ProxyPort, (UINT16)jint(p, "port", 1080)) &&
	       freerdp_settings_set_string(s, FreeRDP_ProxyUsername, user && user[0] ? user : NULL) &&
	       freerdp_settings_set_string(s, FreeRDP_ProxyPassword, pass && pass[0] ? pass : NULL);
}

/* RD Gateway: {host, port, sameCredentials, username?, password?, bypassLocal}. HTTP і RPC —
 * обидва транспорти, FreeRDP сам вибере, що підтримує шлюз. */
static BOOL apply_gateway(rdpSettings* s, const cJSON* g)
{
	if (!g)
		return TRUE;
	const char* host = jstr(g, "host");
	if (!host || !host[0])
		return FALSE;
	const BOOL same = jbool(g, "sameCredentials", TRUE);
	BOOL ok = freerdp_settings_set_bool(s, FreeRDP_GatewayEnabled, TRUE) &&
	          freerdp_settings_set_string(s, FreeRDP_GatewayHostname, host) &&
	          freerdp_settings_set_uint32(s, FreeRDP_GatewayPort, (UINT32)jint(g, "port", 443)) &&
	          freerdp_settings_set_bool(s, FreeRDP_GatewayHttpTransport, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_GatewayRpcTransport, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_GatewayUseSameCredentials, same) &&
	          freerdp_settings_set_bool(s, FreeRDP_GatewayBypassLocal, jbool(g, "bypassLocal", FALSE)) &&
	          freerdp_settings_set_uint32(s, FreeRDP_GatewayUsageMethod,
	                                      jbool(g, "bypassLocal", FALSE) ? TSC_PROXY_MODE_DETECT
	                                                                     : TSC_PROXY_MODE_DIRECT);
	if (ok && !same)
	{
		char* user = NULL;
		char* domain = NULL;
		const char* account = jstr(g, "username");
		if (account && !freerdp_parse_username(account, &user, &domain))
			return FALSE;
		ok = freerdp_settings_set_string(s, FreeRDP_GatewayUsername, user) &&
		     freerdp_settings_set_string(s, FreeRDP_GatewayDomain, domain) &&
		     freerdp_settings_set_string(s, FreeRDP_GatewayPassword, jstr(g, "password"));
		free(user);
		free(domain);
	}
	return ok;
}

static BOOL apply_config(MhrdContext* m, const uint8_t* data, uint32_t len)
{
	rdpSettings* s = m->common.context.settings;
	cJSON* j = cJSON_ParseWithLength((const char*)data, len);
	if (!j)
		return FALSE;
	BOOL ok = FALSE;
	const char* host = jstr(j, "host");
	if (!host)
		goto out;

	char* user = NULL;
	char* domain = NULL;
	const char* account = jstr(j, "username");
	if (account && !freerdp_parse_username(account, &user, &domain))
		goto out;

	ok = freerdp_settings_set_string(s, FreeRDP_ServerHostname, host) &&
	     freerdp_settings_set_uint32(s, FreeRDP_ServerPort, (UINT32)jint(j, "port", 3389)) &&
	     freerdp_settings_set_string(s, FreeRDP_Username, user) &&
	     freerdp_settings_set_string(s, FreeRDP_Domain, domain) &&
	     freerdp_settings_set_string(s, FreeRDP_Password, jstr(j, "password")) &&
	     freerdp_settings_set_uint32(s, FreeRDP_DesktopWidth, (UINT32)jint(j, "width", 1280)) &&
	     freerdp_settings_set_uint32(s, FreeRDP_DesktopHeight, (UINT32)jint(j, "height", 800)) &&
	     freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, (UINT32)jint(j, "colorDepth", 32)) &&
	     freerdp_settings_set_bool(s, FreeRDP_ConsoleSession, jbool(j, "adminSession", FALSE)) &&
	     freerdp_settings_set_bool(s, FreeRDP_AutoReconnectionEnabled, jbool(j, "reconnect", TRUE)) &&
	     /* 5 спроб, далі — відключення з «Підключитись знову» (SPEC → «Сеанс»). */
	     freerdp_settings_set_uint32(s, FreeRDP_AutoReconnectMaxRetries, RECONNECT_MAX) &&
	     /* Канал rdpei: дотики сенсорного екрана — справжніми дотиками на віддалений ПК. */
	     freerdp_settings_set_bool(s, FreeRDP_MultiTouchInput, TRUE) &&
	     freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, jbool(j, "clipboard", TRUE)) &&
	     freerdp_settings_set_bool(s, FreeRDP_AudioCapture, jbool(j, "microphone", FALSE));
	/* Масштаб: картинка у фізичних пікселях, а інтерфейс ПК збільшено як у ОС клієнта —
	 * чітко й звичного розміру. DesktopScaleFactor 100–500 %, DeviceScaleFactor лише 100/140/180. */
	int scale = jint(j, "scale", 100);
	if (scale < 100)
		scale = 100;
	if (scale > 500)
		scale = 500;
	m->desktopScale = (UINT32)scale;
	m->deviceScale = scale < 134 ? 100 : scale < 174 ? 140 : 180;
	if (ok)
		ok = freerdp_settings_set_uint32(s, FreeRDP_DesktopScaleFactor, m->desktopScale) &&
		     freerdp_settings_set_uint32(s, FreeRDP_DeviceScaleFactor, m->deviceScale);
	/* Звук: "local" — тут, "remote" — на віддаленому ПК, "off" — ніде. */
	const char* sound = jstr(j, "sound");
	if (ok && sound && strcmp(sound, "remote") == 0)
		ok = freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, FALSE) &&
		     freerdp_settings_set_bool(s, FreeRDP_RemoteConsoleAudio, TRUE);
	else if (ok)
		ok = freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, !(sound && strcmp(sound, "off") == 0));
	/* Довіру сертифікатам пам'ятає застосунок (certPin): колбек повертає 2 («лише цей сеанс»),
	 * тож власне сховище відомих сертифікатів FreeRDP ніколи не заповнюється. */
	free(user);
	free(domain);

	/* Спільні папки: кожна — мережевий диск у «Цей ПК» на віддаленому ПК (канал rdpdr).
	 * Режим доступу передається префіксом шляху, який розуміє наш drive_main.c
	 * (vcpkg-overlay/freerdp/mhrd): "|add|" — додавання без видалення, "|ro|" — лише читання.
	 * Невідомий режим — найсуворіший («лише читання»), а не повний. */
	const cJSON* folders = cJSON_GetObjectItemCaseSensitive(j, "folders");
	const cJSON* f = NULL;
	cJSON_ArrayForEach(f, folders)
	{
		const char* name = jstr(f, "name");
		const char* path = jstr(f, "path");
		const char* access = jstr(f, "access");
		if (!ok || !name || !path)
			continue;
		if (!winpr_PathFileExists(path))
		{
			WLog_WARN("mhrd", "shared folder does not exist, skipping: %s", path);
			continue; /* папку видалили — сеанс працює без неї (SPEC → «Помилки») */
		}
		const char* prefix = "|ro|";
		if (access && strcmp(access, "full") == 0)
			prefix = "";
		else if (access && strcmp(access, "addOnly") == 0)
			prefix = "|add|";
		char* drivePath = NULL;
		size_t n = 0;
		if (winpr_asprintf(&drivePath, &n, "%s%s", prefix, path) < 0 || !drivePath)
		{
			ok = FALSE;
			continue;
		}
		/* Напряму, а не freerdp_client_add_device_channel: той перевіряє існування шляху
		 * разом із префіксом режиму і пропустив би папку. */
		const char* args[] = { name, drivePath };
		RDPDR_DEVICE* dev = freerdp_device_new(RDPDR_DTYP_FILESYSTEM, ARRAYSIZE(args), args);
		free(drivePath);
		if (!dev || !freerdp_device_collection_add(s, dev))
		{
			freerdp_device_free(dev);
			ok = FALSE;
			continue;
		}
		ok = freerdp_settings_set_bool(s, FreeRDP_DeviceRedirection, TRUE);
	}

	const char* pin = jstr(j, "certPin");
	m->certPin = pin ? _strdup(pin) : NULL;

	if (ok)
		ok = apply_proxy(s, cJSON_GetObjectItemCaseSensitive(j, "proxy")) &&
		     apply_gateway(s, cJSON_GetObjectItemCaseSensitive(j, "gateway"));

	/* Власне вікно сеансу (десктоп): заголовок, шрифт і тексти плашки, кольори теми MHRD. */
	m->nativeWindow = jbool(j, "nativeWindow", FALSE);
	if (m->nativeWindow)
	{
		const cJSON* labels = cJSON_GetObjectItemCaseSensitive(j, "labels");
		const cJSON* colors = cJSON_GetObjectItemCaseSensitive(j, "colors");
		const char* src[ARRAYSIZE(m->winStrings)] = {
			jstr(j, "title"),          jstr(j, "fontPath"),          jstr(labels, "pin"),
			jstr(labels, "unpin"),     jstr(labels, "minimize"),     jstr(labels, "exitFullscreen"),
			jstr(labels, "disconnect"), jstr(labels, "fullscreen"),  jstr(labels, "keyboard"),
			jstr(labels, "menuFullscreen"), jstr(labels, "menuKeyboard"), jstr(j, "iconFontPath"),
			jstr(labels, "reconnecting"), jstr(j, "barTitle"), jstr(labels, "ctrlAltDel"),
			jstr(labels, "reconnectAttempt"), jstr(labels, "cancel"), jstr(labels, "latency"),
			jstr(j, "thumbnailPath")
		};
		for (size_t i = 0; i < ARRAYSIZE(src); i++)
			m->winStrings[i] = _strdup(src[i] ? src[i] : "");
		m->win.title = m->winStrings[0][0] ? m->winStrings[0] : "MHRD";
		m->win.fontPath = m->winStrings[1];
		m->win.labelPin = m->winStrings[2];
		m->win.labelUnpin = m->winStrings[3];
		m->win.labelMinimize = m->winStrings[4];
		m->win.labelExitFullscreen = m->winStrings[5];
		m->win.labelDisconnect = m->winStrings[6];
		m->win.labelFullscreen = m->winStrings[7];
		m->win.labelKeyboard = m->winStrings[8];
		m->win.menuFullscreen = m->winStrings[9];
		m->win.menuKeyboard = m->winStrings[10];
		m->win.iconFontPath = m->winStrings[11];
		m->win.labelReconnecting = m->winStrings[12];
		m->win.barTitle = m->winStrings[13][0] ? m->winStrings[13] : m->win.title;
		m->win.labelCtrlAltDel = m->winStrings[14];
		m->win.labelReconnectAttempt = m->winStrings[15];
		m->win.labelCancel = m->winStrings[16];
		m->win.labelLatency = m->winStrings[17];
		m->win.reconnectMax = RECONNECT_MAX;
		m->win.thumbnailPath = m->winStrings[18][0] ? m->winStrings[18] : NULL;
		const cJSON* icons = cJSON_GetObjectItemCaseSensitive(j, "icons");
		m->win.iconPin = (uint32_t)jint(icons, "pin", 0);
		m->win.iconUnpin = (uint32_t)jint(icons, "unpin", 0);
		m->win.iconKeyboard = (uint32_t)jint(icons, "keyboard", 0);
		m->win.iconMinimize = (uint32_t)jint(icons, "minimize", 0);
		m->win.iconFullscreen = (uint32_t)jint(icons, "fullscreen", 0);
		m->win.iconExitFullscreen = (uint32_t)jint(icons, "exitFullscreen", 0);
		m->win.iconDisconnect = (uint32_t)jint(icons, "disconnect", 0);
		m->win.iconCtrlAltDel = (uint32_t)jint(icons, "ctrlAltDel", 0);
		m->win.colorSurface = (uint32_t)jint(colors, "surface", 0x141619);
		m->win.colorBorder = (uint32_t)jint(colors, "border", 0x2C3036);
		m->win.colorText = (uint32_t)jint(colors, "text", 0xE8EAED);
		m->win.colorAccent = (uint32_t)jint(colors, "accent", 0xC6F432);
		m->win.colorError = (uint32_t)jint(colors, "error", 0xFF8A7A);
		m->win.colorOk = (uint32_t)jint(colors, "ok", 0x7BD88F);
		m->win.colorWarn = (uint32_t)jint(colors, "warn", 0xF2C14E);
		m->win.startFullscreen = jbool(j, "startFullscreen", FALSE);
		m->win.keyboardCapture = jint(j, "keyboardCapture", 0);
		m->win.resizeMode = jint(j, "resizeMode", 0);
		m->win.swapMouseButtons = jbool(j, "swapMouse", FALSE);
		const cJSON* bar = cJSON_GetObjectItemCaseSensitive(j, "bar");
		m->win.barEdge = jint(bar, "edge", 0);
		m->win.barPos = jint(bar, "pos", 5000);
		m->win.barLength = jint(bar, "length", 0);
		m->win.radius = jint(j, "radius", 8);
	}
out:
	wipe_string(j, "password");
	wipe_string(cJSON_GetObjectItemCaseSensitive(j, "proxy"), "password");
	wipe_string(cJSON_GetObjectItemCaseSensitive(j, "gateway"), "password");
	cJSON_Delete(j);
	return ok;
}

/* ── Ввід ──────────────────────────────────────────────────────── */

/* Коліщатко: 9-бітне значення з доповненням до двох (MS-RDPBCGR 2.2.8.1.1.3.1.1.3). */
static void send_wheel(rdpInput* input, int delta, BOOL horizontal, UINT16 x, UINT16 y)
{
	if (delta > 255)
		delta = 255;
	if (delta < -255)
		delta = -255;
	UINT16 flags = horizontal ? PTR_FLAGS_HWHEEL : PTR_FLAGS_WHEEL;
	if (delta < 0)
		flags |= PTR_FLAGS_WHEEL_NEGATIVE | (UINT16)((0x100 + delta) & 0xFF);
	else
		flags |= (UINT16)delta;
	freerdp_input_send_mouse_event(input, flags, x, y);
}

/* Що просить власне вікно сеансу (головний потік). */
static void host_lock(void* ctx)
{
	EnterCriticalSection(&((MhrdContext*)ctx)->bufLock);
}

static void host_unlock(void* ctx)
{
	LeaveCriticalSection(&((MhrdContext*)ctx)->bufLock);
}

static const uint8_t* host_buffer(void* ctx, uint32_t* width, uint32_t* height, uint32_t* stride)
{
	MhrdContext* m = (MhrdContext*)ctx;
	rdpGdi* gdi = m->common.context.gdi;
	if (!gdi || !m->shm.data)
	{
		*width = *height = *stride = 0;
		return NULL;
	}
	*width = gdi->width;
	*height = gdi->height;
	*stride = gdi->stride;
	return (const uint8_t*)m->shm.data;
}

/* Ввід із вікна — під inputLock і лише поки сеанс на зв'язку (див. MhrdContext.inputLock). */
static BOOL input_begin(void* ctx)
{
	MhrdContext* m = (MhrdContext*)ctx;
	EnterCriticalSection(&m->inputLock);
	if (m->online)
		return TRUE;
	LeaveCriticalSection(&m->inputLock);
	return FALSE;
}

static void input_end(void* ctx)
{
	LeaveCriticalSection(&((MhrdContext*)ctx)->inputLock);
}

static void host_key(void* ctx, uint16_t code, BOOL down, BOOL repeat)
{
	if (!input_begin(ctx))
		return;
	freerdp_input_send_keyboard_event_ex(((MhrdContext*)ctx)->common.context.input, down, repeat, code);
	input_end(ctx);
}

static void host_mouse(void* ctx, uint16_t flags, uint16_t x, uint16_t y)
{
	if (!input_begin(ctx))
		return;
	freerdp_input_send_mouse_event(((MhrdContext*)ctx)->common.context.input, flags, x, y);
	input_end(ctx);
}

static void host_wheel(void* ctx, int delta, BOOL horizontal, uint16_t x, uint16_t y)
{
	if (!input_begin(ctx))
		return;
	send_wheel(((MhrdContext*)ctx)->common.context.input, delta, horizontal, x, y);
	input_end(ctx);
}

static void host_resize(void* ctx, uint32_t width, uint32_t height)
{
	send_monitor_layout((MhrdContext*)ctx, width, height);
}

static void host_close(void* ctx)
{
	MhrdContext* m = (MhrdContext*)ctx;
	m->userDisconnect = TRUE;
	freerdp_abort_connect_context(&m->common.context);
}

/* Дотик пальцем — справжнім дотиком на віддалений ПК (канал rdpei), щоб Windows там сама робила
 * жести: гортання пальцем, щипок, довге натискання. FALSE — сервер дотику не підтримує. */
static BOOL host_touch(void* ctx, uint32_t flags, int finger, int x, int y)
{
	MhrdContext* m = (MhrdContext*)ctx;
	if (!input_begin(ctx))
		return (flags & FREERDP_TOUCH_DOWN) == 0; /* немає зв'язку: новий дотик — мишею, решту — ковтаємо */
	const BOOL ok = m->common.rdpei && freerdp_client_handle_touch(&m->common, flags, finger, 0, x, y);
	input_end(ctx);
	return ok;
}

/* Плашку перетягнули чи змінили її довжину — застосунок запам'ятає для наступних сеансів. */
static void host_bar_moved(void* ctx, int edge, int pos, int length)
{
	WINPR_UNUSED(ctx);
	uint8_t buf[5] = { (uint8_t)edge, (uint8_t)pos, (uint8_t)(pos >> 8), (uint8_t)length, (uint8_t)(length >> 8) };
	proto_send(EVT_BAR, buf, sizeof(buf));
}

/* Повідомлення від застосунку (режим без вікна — увесь ввід; з вікном — лише керування). */
static void handle_input(MhrdContext* m)
{
	rdpInput* input = m->common.context.input;
	ProtoMsg* msg;
	while ((msg = proto_pop()) != NULL)
	{
		const uint8_t* d = msg->data;
		switch (msg->type)
		{
			case MSG_KEY:
				if (msg->len >= 3)
					freerdp_input_send_keyboard_event_ex(input, d[2] != 0, FALSE, get_u16(d));
				break;
			case MSG_MOUSE_MOVE:
				if (msg->len >= 4)
					freerdp_input_send_mouse_event(input, PTR_FLAGS_MOVE, get_u16(d), get_u16(d + 2));
				break;
			case MSG_MOUSE_BUTTON:
				if (msg->len >= 6)
				{
					UINT16 flags = d[0] == 1 ? PTR_FLAGS_BUTTON1 : d[0] == 2 ? PTR_FLAGS_BUTTON2 : PTR_FLAGS_BUTTON3;
					if (d[1])
						flags |= PTR_FLAGS_DOWN;
					freerdp_input_send_mouse_event(input, flags, get_u16(d + 2), get_u16(d + 4));
				}
				break;
			case MSG_MOUSE_WHEEL:
				if (msg->len >= 7)
					send_wheel(input, (int16_t)get_u16(d), d[2] != 0, get_u16(d + 3), get_u16(d + 5));
				break;
			case MSG_RESIZE:
				if (msg->len >= 4)
					send_monitor_layout(m, get_u16(d), get_u16(d + 2));
				break;
			case MSG_FOCUS:
				if (m->nativeWindow)
					window_post_focus();
				break;
			case MSG_LATENCY:
				if (m->nativeWindow && msg->len >= 4)
					window_post_latency((int32_t)(d[0] | (d[1] << 8) | (d[2] << 16) | ((uint32_t)d[3] << 24)));
				break;
			case MSG_DISCONNECT:
				m->userDisconnect = TRUE;
				freerdp_abort_connect_context(&m->common.context);
				break;
			default:
				break;
		}
		free(msg);
	}
}

/* ── Головний цикл ─────────────────────────────────────────────── */

static void configure_logging(void)
{
	/* stdout зайнятий каналом — журнал FreeRDP лише в stderr і лише попередження. */
	wLog* root = WLog_GetRoot();
	WLog_SetLogAppenderType(root, WLOG_APPENDER_CONSOLE);
	wLogAppender* appender = WLog_GetLogAppender(root);
	WLog_ConfigureAppender(appender, "outputstream", "stderr");
	WLog_SetLogLevel(root, WLOG_WARN);
	/* Для журналу сеансів: які канали піднялись, що зі звуком і мікрофоном. */
	WLog_SetLogLevel(WLog_Get("mhrd"), WLOG_INFO);
	WLog_SetLogLevel(WLog_Get("com.freerdp.channels.rdpsnd.client"), WLOG_INFO);
	WLog_SetLogLevel(WLog_Get("com.freerdp.channels.audin.client"), WLOG_INFO);
}

/* Між спробами перепідключення; користувач закрив вікно чи натиснув «Відключитись» — досить. */
static SSIZE_T mhrd_retry_dialog(freerdp* instance, const char* what, size_t current, void* userarg)
{
	(void)what;
	(void)userarg;
	MhrdContext* m = (MhrdContext*)instance->context;
	/* Цикл сеансу зараз стоїть — повідомлення застосунку розбираємо тут. Ввід відкидаємо:
	 * після відновлення він був би вже не до місця. */
	ProtoMsg* msg;
	while ((msg = proto_pop()) != NULL)
	{
		if (msg->type == MSG_DISCONNECT)
			m->userDisconnect = TRUE;
		else if (msg->type == MSG_FOCUS && m->nativeWindow)
			window_post_focus();
		free(msg);
	}
	if (proto_closed() && !m->nativeWindow)
		m->userDisconnect = TRUE; /* без вікна сеанс без застосунку не має сенсу */
	if (m->userDisconnect)
		return -1;
	WLog_INFO("mhrd", "reconnect attempt %" PRIuz, current + 1);
	if (m->nativeWindow)
		window_post_reconnecting((int)current + 1); /* «спроба 2 з 5» */
	return 3000; /* мс до наступної спроби, якщо ця не вдасться */
}

/* Зв'язок обірвався (SPEC → «Стани сесії» → reconnecting). FreeRDP сам вирішує, чи варто:
 * не перепідключається, якщо сервер навмисно завершив сеанс чи пароль більше не підходить. */
static BOOL reconnect(MhrdContext* m)
{
	freerdp* instance = m->common.context.instance;
	set_online(m, FALSE); /* транспорт і канали перестворюються — ввід із вікна чекає */
	InterlockedExchange(&m->reconnecting, 1);
	send_state(3);
	if (m->nativeWindow)
		window_post_reconnecting(1);
	const BOOL ok = client_auto_reconnect_ex(instance, NULL);
	InterlockedExchange(&m->reconnecting, 0);
	if (ok)
	{
		set_online(m, TRUE);
		if (m->wantWidth && m->wantHeight) /* вікно змінило розмір, поки зв'язку не було */
			send_monitor_layout(m, m->wantWidth, m->wantHeight);
	}
	if (m->nativeWindow)
		window_post_reconnecting(0);
	WLog_INFO("mhrd", "reconnect %s", ok ? "succeeded" : "gave up");
	if (ok)
		send_state(2);
	return ok;
}

static void run_session(MhrdContext* m)
{
	rdpContext* ctx = &m->common.context;
	HANDLE handles[MAXIMUM_WAIT_OBJECTS];
	while (!freerdp_shall_disconnect_context(ctx))
	{
		DWORD n = freerdp_get_event_handles(ctx, handles, ARRAYSIZE(handles) - 1);
		if (n == 0)
			break;
		const BOOL closed = proto_closed();
		if (!closed)
			handles[n++] = proto_event(); /* після закриття подія лишається ввімкненою — не чекаємо її */
		if (WaitForMultipleObjects(n, handles, FALSE, 100) == WAIT_FAILED)
			break;
		if (!freerdp_check_event_handles(ctx))
		{
			if (!m->userDisconnect && reconnect(m))
				continue;
			break;
		}
		handle_input(m);
		/* Застосунок закрився. Без вікна сеанс без нього не має сенсу; власне вікно живе
		 * незалежно — його закриває лише користувач. */
		if (closed && !m->nativeWindow)
		{
			m->userDisconnect = TRUE;
			break;
		}
	}
}

/* Підключення, сеанс, відключення. З вікном — у власному потоці. */
static void rdp_run(MhrdContext* m)
{
	freerdp* instance = m->common.context.instance;
	send_state(1);
	if (freerdp_connect(instance))
	{
		set_online(m, TRUE);
		run_session(m);
		set_online(m, FALSE); /* до відключення: вікно більше нічого не надсилає */
		freerdp_disconnect(instance);
	}
	send_disconnected(m);
	if (m->nativeWindow)
		window_post_quit();
}

static DWORD WINAPI rdp_thread(LPVOID arg)
{
	rdp_run((MhrdContext*)arg);
	return 0;
}

int main(void)
{
	configure_logging();
	/* Без WSAStartup на Windows не працює жоден мережевий виклик — навіть розбір IP-адреси
	 * (FreeRDP тоді повідомляє «DNS-ім'я не знайдено»). Клієнти FreeRDP роблять це самі. */
	WSADATA wsa;
	if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
		return 1;
	if (!proto_init())
		return 1;
	/* Канали FreeRDP вбудовані в цей .exe (статична збірка). */
	freerdp_register_addin_provider(freerdp_channels_load_static_addin_entry, 0);

	ProtoMsg* connect = NULL;
	while (!connect)
	{
		ProtoMsg* msg = proto_wait(INFINITE);
		if (!msg)
			return 0; /* застосунок закрився, так і не попросивши підключитись */
		if (msg->type == MSG_CONNECT)
			connect = msg;
		else
			free(msg);
	}

	RDP_CLIENT_ENTRY_POINTS ep = { 0 };
	ep.Version = RDP_CLIENT_INTERFACE_VERSION;
	ep.Size = sizeof(ep);
	ep.ContextSize = sizeof(MhrdContext);
	ep.ClientNew = mhrd_client_new;
	ep.ClientFree = mhrd_client_free;

	rdpContext* ctx = freerdp_client_context_new(&ep);
	if (!ctx)
		return 1;
	MhrdContext* m = (MhrdContext*)ctx;

	InitializeCriticalSection(&m->bufLock);
	InitializeCriticalSection(&m->inputLock);
	const BOOL configured = apply_config(m, connect->data, connect->len);
	memset(connect->data, 0, connect->len); /* у JSON був пароль */
	free(connect);

	int rc = 0;
	if (!configured)
	{
		rc = 2;
		send_disconnected(m);
	}
	else if (m->nativeWindow)
	{
		/* Вікно — у головному потоці (вимога SDL), FreeRDP — у своєму. */
		const WindowHost host = { m, host_lock, host_unlock, host_buffer, host_key,
			                      host_mouse, host_wheel, host_resize, host_close, host_bar_moved, host_touch };
		if (window_init(&m->win, &host))
		{
			HANDLE t = CreateThread(NULL, 0, rdp_thread, m, 0, NULL);
			if (t)
			{
				window_run();
				WaitForSingleObject(t, INFINITE);
				CloseHandle(t);
			}
			else
				rc = 1;
		}
		else
		{
			WLog_ERR("mhrd", "window init failed, running without a window");
			m->nativeWindow = FALSE;
			rdp_run(m);
		}
		window_shutdown();
	}
	else
		rdp_run(m);

	freerdp_client_context_free(ctx);
	for (size_t i = 0; i < ARRAYSIZE(m->winStrings); i++)
		free(m->winStrings[i]);
	DeleteCriticalSection(&m->bufLock);
	return rc;
}
