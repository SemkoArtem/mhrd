/* mhrd-session — один сеанс RDP в окремому процесі (SPEC → «Архітектура»).
 *
 * Застосунок запускає цей процес, надсилає MSG_CONNECT (налаштування + пароль) у stdin,
 * далі — ввід. Картинку FreeRDP малює прямо в спільну пам'ять, про змінені ділянки
 * процес повідомляє через stdout. Падіння тут не зачіпає застосунок і інші сеанси.
 *
 * Етап 2: підключення, NLA, сертифікат, картинка (без GFX), клавіатура, миша.
 * Канали (буфер, звук, диски, зміна роздільності) — наступні етапи.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/client.h>
#include <freerdp/error.h>
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>
#include <winpr/string.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>

#include <cjson/cJSON.h>

#include "proto.h"
#include "shm.h"

typedef struct
{
	rdpClientContext common;
	char* certPin;          /* відбиток, якому користувач уже довіряє (з налаштувань ПК) */
	BOOL certRejected;      /* користувач відмовився довіряти сертифікату */
	BOOL noCredentials;     /* пароля немає — застосунок має спитати сам */
	BOOL userDisconnect;    /* застосунок попросив відключитись */
	ShmBuffer shm;
} MhrdContext;

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
	BOOL ok = resize ? gdi_resize_ex(ctx->gdi, width, height, stride, PIXEL_FORMAT_BGRA32, next.data, NULL)
	                 : gdi_init_ex(ctx->instance, PIXEL_FORMAT_BGRA32, stride, next.data, NULL);
	if (!ok)
	{
		shm_free(&next);
		return FALSE;
	}
	ShmBuffer old = m->shm;
	m->shm = next;
	shm_free(&old);
	send_surface(m, width, height, stride);
	return TRUE;
}

static BOOL mhrd_desktop_resize(rdpContext* ctx)
{
	rdpSettings* s = ctx->settings;
	return alloc_surface((MhrdContext*)ctx, freerdp_settings_get_uint32(s, FreeRDP_DesktopWidth),
	                     freerdp_settings_get_uint32(s, FreeRDP_DesktopHeight), TRUE);
}

static BOOL mhrd_pre_connect(freerdp* instance)
{
	rdpSettings* s = instance->context->settings;
	/* Без каналів на етапі 2: класичні оновлення картинки, без GFX. */
	freerdp_settings_set_bool(s, FreeRDP_SupportGraphicsPipeline, FALSE);
	freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, FALSE);
	freerdp_settings_set_uint32(s, FreeRDP_OsMajorType, OSMAJORTYPE_WINDOWS);
	freerdp_settings_set_uint32(s, FreeRDP_OsMinorType, OSMINORTYPE_WINDOWS_NT);
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
			break; /* застосунок закрився */
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
	return TRUE;
}

static void mhrd_client_free(freerdp* instance, rdpContext* context)
{
	(void)instance;
	MhrdContext* m = (MhrdContext*)context;
	free(m->certPin);
	m->certPin = NULL;
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
	     freerdp_settings_set_bool(s, FreeRDP_AutoReconnectionEnabled, jbool(j, "reconnect", TRUE));
	/* Довіру сертифікатам пам'ятає застосунок (certPin): колбек повертає 2 («лише цей сеанс»),
	 * тож власне сховище відомих сертифікатів FreeRDP ніколи не заповнюється. */
	free(user);
	free(domain);

	const char* pin = jstr(j, "certPin");
	m->certPin = pin ? _strdup(pin) : NULL;
out:
	wipe_string(j, "password");
	cJSON_Delete(j);
	return ok;
}

/* ── Ввід від застосунку ───────────────────────────────────────── */

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
				{
					int delta = (int16_t)get_u16(d);
					if (delta > 255)
						delta = 255;
					if (delta < -255)
						delta = -255;
					/* 9-бітне значення з доповненням до двох (MS-RDPBCGR 2.2.8.1.1.3.1.1.3). */
					UINT16 flags = d[2] ? PTR_FLAGS_HWHEEL : PTR_FLAGS_WHEEL;
					if (delta < 0)
						flags |= PTR_FLAGS_WHEEL_NEGATIVE | (UINT16)((0x100 + delta) & 0xFF);
					else
						flags |= (UINT16)delta;
					freerdp_input_send_mouse_event(input, flags, get_u16(d + 3), get_u16(d + 5));
				}
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
		handles[n++] = proto_event();
		if (WaitForMultipleObjects(n, handles, FALSE, 100) == WAIT_FAILED)
			break;
		if (!freerdp_check_event_handles(ctx))
			break;
		handle_input(m);
		if (proto_closed())
		{
			m->userDisconnect = TRUE;
			break;
		}
	}
}

int main(void)
{
	configure_logging();
	if (!proto_init())
		return 1;

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

	const BOOL configured = apply_config(m, connect->data, connect->len);
	memset(connect->data, 0, connect->len); /* у JSON був пароль */
	free(connect);

	int rc = 0;
	if (!configured)
	{
		rc = 2;
		send_disconnected(m);
	}
	else
	{
		send_state(1);
		if (freerdp_connect(ctx->instance))
		{
			run_session(m);
			freerdp_disconnect(ctx->instance);
		}
		send_disconnected(m);
	}
	freerdp_client_context_free(ctx);
	return rc;
}
