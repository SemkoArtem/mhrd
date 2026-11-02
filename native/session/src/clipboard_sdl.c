/* Буфер обміну сеансу на Linux (і далі macOS) — через SDL3, тож однаково для X11 і Wayland.
 *
 * Тут скопіювали → SDL_EVENT_CLIPBOARD_UPDATE чи фокус на вікні сеансу → серверу список форматів
 * (без даних).
 * Сервер просить дані → у головному потоці читаємо буфер SDL і відповідаємо.
 * Там скопіювали → у буфер SDL кладемо «обіцянку» (SDL_SetClipboardData з функцією): дані
 * просимо в сервера лише тоді, коли тут натиснули «Вставити».
 *
 * Буфер SDL — лише з головного потоку, а канал cliprdr працює в потоці FreeRDP, тому все, що
 * торкається буфера, передається в головний потік через SDL_RunOnMainThread без очікування
 * (головний потік сам може чекати на відповідь сервера — тоді очікування з потоку FreeRDP дало б
 * взаємне блокування).
 *
 * Текст: CF_UNICODETEXT (UTF-16, CRLF) ↔ UTF-8 з LF. Картинки: CF_DIB ↔ image/png і image/bmp.
 */
#include "clipboard.h"

#include <stdlib.h>
#include <string.h>

#include <SDL3/SDL.h>
#include <winpr/string.h>
#include <winpr/synch.h>
#include <winpr/user.h>

#define RENDER_TIMEOUT_MS 5000
#define CLIP_MAX (64u * 1024 * 1024) /* запобіжник: більше не просимо й не віддаємо */

static const char* const TEXT_MIMES[] = { "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT",
	                                      "STRING" };
static const char* const IMAGE_MIMES[] = { "image/png", "image/bmp" };

struct MhrdClipboard
{
	CRITICAL_SECTION lock;
	CliprdrClientContext* cliprdr; /* NULL, поки канал не підключено */

	/* Що є в буфері сервера */
	BOOL serverText;
	BOOL serverDib;

	/* Відповідь сервера на наш запит даних */
	HANDLE responseEvent;
	BYTE* response;
	UINT32 responseLen;
	BOOL responseOk;

	/* Те, що ми віддали SDL у функції даних (живе до наступного запиту) — лише головний потік */
	void* served;

	/* У системному буфері — «обіцянка» сервера (ми її поклали, ніхто не перезаписав): тоді наш буфер
	 * серверу не пересилаємо — це його ж дані. */
	BOOL owned;
	/* Перевірка буфера вже запланована (не плодимо таймери на кожну подію). */
	BOOL checkQueued;

	/* Завдання для головного потоку ще в черзі: тоді clipboard_free лише позначає «закрито», а пам'ять
	 * звільняє останнє завдання. */
	int pending;
	BOOL closed;
};

static CliprdrClientContext* get_cliprdr(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	CliprdrClientContext* c = cb->closed ? NULL : cb->cliprdr;
	LeaveCriticalSection(&cb->lock);
	return c;
}

static void destroy(MhrdClipboard* cb)
{
	CloseHandle(cb->responseEvent);
	free(cb->response);
	SDL_free(cb->served);
	DeleteCriticalSection(&cb->lock);
	free(cb);
}

/* ── Завдання для головного потоку ────────────────────────────── */

typedef struct
{
	MhrdClipboard* cb;
	void (*fn)(MhrdClipboard* cb, UINT32 arg);
	UINT32 arg;
} MainJob;

/* Завдання (чи таймер) закінчилось: останнє після clipboard_free звільняє пам'ять. */
static void release(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	const BOOL last = --cb->pending == 0 && cb->closed;
	LeaveCriticalSection(&cb->lock);
	if (last)
		destroy(cb);
}

static void SDLCALL run_job(void* p)
{
	MainJob* job = (MainJob*)p;
	MhrdClipboard* cb = job->cb;
	EnterCriticalSection(&cb->lock);
	const BOOL closed = cb->closed;
	LeaveCriticalSection(&cb->lock);
	if (!closed)
		job->fn(cb, job->arg);
	release(cb);
	free(job);
}

static void post_main(MhrdClipboard* cb, void (*fn)(MhrdClipboard*, UINT32), UINT32 arg)
{
	MainJob* job = malloc(sizeof(MainJob));
	if (!job)
		return;
	job->cb = cb;
	job->fn = fn;
	job->arg = arg;
	EnterCriticalSection(&cb->lock);
	cb->pending++;
	LeaveCriticalSection(&cb->lock);
	if (!SDL_RunOnMainThread(run_job, job, false))
	{
		EnterCriticalSection(&cb->lock);
		cb->pending--;
		LeaveCriticalSection(&cb->lock);
		free(job);
	}
}

/* ── Перетворення ─────────────────────────────────────────────── */

/* UTF-8 з LF → UTF-16LE з CRLF і нулем у кінці (як чекає Windows). */
static BYTE* utf8_to_unicodetext(const char* text, UINT32* outLen)
{
	const size_t n = strlen(text);
	size_t lf = 0;
	for (size_t i = 0; i < n; i++)
		lf += text[i] == '\n' && (i == 0 || text[i - 1] != '\r');
	char* crlf = malloc(n + lf + 1);
	if (!crlf)
		return NULL;
	size_t o = 0;
	for (size_t i = 0; i < n; i++)
	{
		if (text[i] == '\n' && (i == 0 || text[i - 1] != '\r'))
			crlf[o++] = '\r';
		crlf[o++] = text[i];
	}
	crlf[o] = 0;
	size_t wlen = 0;
	WCHAR* w = ConvertUtf8ToWCharAlloc(crlf, &wlen);
	free(crlf);
	if (!w)
		return NULL;
	*outLen = (UINT32)((wlen + 1) * sizeof(WCHAR));
	return (BYTE*)w;
}

/* UTF-16LE від сервера (до першого нуля) → UTF-8 з LF; пам'ять — SDL_malloc. */
static char* unicodetext_to_utf8(const BYTE* data, UINT32 len, size_t* outLen)
{
	const size_t chars = _wcsnlen((const WCHAR*)data, len / sizeof(WCHAR));
	size_t n = 0;
	char* utf8 = ConvertWCharNToUtf8Alloc((const WCHAR*)data, chars, &n);
	if (!utf8)
		return NULL;
	char* out = SDL_malloc(n + 1);
	if (out)
	{
		size_t o = 0;
		for (size_t i = 0; i < n; i++)
		{
			if (utf8[i] == '\r' && i + 1 < n && utf8[i + 1] == '\n')
				continue;
			out[o++] = utf8[i];
		}
		out[o] = 0;
		*outLen = o;
	}
	free(utf8);
	return out;
}

static UINT32 rd32(const BYTE* p)
{
	return p[0] | (p[1] << 8) | (p[2] << 16) | ((UINT32)p[3] << 24);
}

static void wr32(BYTE* p, UINT32 v)
{
	p[0] = (BYTE)v;
	p[1] = (BYTE)(v >> 8);
	p[2] = (BYTE)(v >> 16);
	p[3] = (BYTE)(v >> 24);
}

/* CF_DIB (BITMAPINFO + пікселі) → файл BMP: попереду 14 байт BITMAPFILEHEADER. */
static SDL_Surface* dib_to_surface(const BYTE* dib, UINT32 len)
{
	if (len < 40)
		return NULL;
	const UINT32 hdr = rd32(dib);
	if (hdr < 40 || hdr > len)
		return NULL;
	const UINT32 bpp = dib[14] | (dib[15] << 8);
	const UINT32 compression = rd32(dib + 16);
	UINT32 colors = rd32(dib + 32);
	if (colors == 0 && bpp <= 8)
		colors = 1u << bpp;
	UINT32 offset = 14 + hdr + colors * 4;
	if (hdr == 40 && compression == 3 /* BI_BITFIELDS */)
		offset += 12;
	if (offset - 14 > len)
		return NULL;
	BYTE* bmp = malloc((size_t)len + 14);
	if (!bmp)
		return NULL;
	bmp[0] = 'B';
	bmp[1] = 'M';
	wr32(bmp + 2, len + 14);
	wr32(bmp + 6, 0);
	wr32(bmp + 10, offset);
	memcpy(bmp + 14, dib, len);
	SDL_Surface* s = SDL_LoadBMP_IO(SDL_IOFromConstMem(bmp, (size_t)len + 14), true);
	free(bmp);
	return s;
}

/* Поверхня → записаний у пам'ять файл (BMP чи PNG); пам'ять — SDL_malloc. */
static void* surface_to_file(SDL_Surface* s, BOOL png, size_t* outLen)
{
	SDL_IOStream* io = SDL_IOFromDynamicMem();
	if (!io)
		return NULL;
	const bool ok = png ? SDL_SavePNG_IO(s, io, false) : SDL_SaveBMP_IO(s, io, false);
	void* data = NULL;
	if (ok)
	{
		const SDL_PropertiesID props = SDL_GetIOProperties(io);
		*outLen = (size_t)SDL_GetIOSize(io);
		data = SDL_GetPointerProperty(props, SDL_PROP_IOSTREAM_DYNAMIC_MEMORY_POINTER, NULL);
		/* Забираємо пам'ять собі: інакше SDL_CloseIO звільнить її. */
		SDL_SetPointerProperty(props, SDL_PROP_IOSTREAM_DYNAMIC_MEMORY_POINTER, NULL);
	}
	SDL_CloseIO(io);
	return data;
}

/* Картинка з нашого буфера → CF_DIB (24 біти, BITMAPINFOHEADER — так розуміють усі програми Windows). */
static BYTE* local_image_to_dib(UINT32* outLen)
{
	SDL_Surface* s = NULL;
	for (size_t i = 0; i < SDL_arraysize(IMAGE_MIMES) && !s; i++)
	{
		size_t n = 0;
		void* file = SDL_HasClipboardData(IMAGE_MIMES[i]) ? SDL_GetClipboardData(IMAGE_MIMES[i], &n) : NULL;
		if (file && n > 0 && n <= CLIP_MAX)
		{
			SDL_IOStream* io = SDL_IOFromConstMem(file, n);
			s = i == 0 ? SDL_LoadPNG_IO(io, true) : SDL_LoadBMP_IO(io, true);
		}
		SDL_free(file);
	}
	if (!s)
		return NULL;
	SDL_Surface* rgb = SDL_ConvertSurface(s, SDL_PIXELFORMAT_BGR24);
	SDL_DestroySurface(s);
	if (!rgb)
		return NULL;
	size_t n = 0;
	BYTE* bmp = surface_to_file(rgb, FALSE, &n);
	SDL_DestroySurface(rgb);
	BYTE* dib = NULL;
	if (bmp && n > 14 && n - 14 <= CLIP_MAX)
	{
		dib = malloc(n - 14);
		if (dib)
		{
			memcpy(dib, bmp + 14, n - 14);
			*outLen = (UINT32)(n - 14);
		}
	}
	SDL_free(bmp);
	return dib;
}

/* ── Наш буфер → сервер ───────────────────────────────────────── */

static void send_client_format_list(MhrdClipboard* cb, UINT32 unused)
{
	(void)unused;
	CliprdrClientContext* c = get_cliprdr(cb);
	EnterCriticalSection(&cb->lock);
	const BOOL owned = cb->owned;
	cb->checkQueued = FALSE;
	LeaveCriticalSection(&cb->lock);
	if (!c || owned)
		return;
	CLIPRDR_FORMAT formats[2] = { 0 };
	UINT32 n = 0;
	if (SDL_HasClipboardText())
		formats[n++].formatId = CF_UNICODETEXT;
	for (size_t i = 0; i < SDL_arraysize(IMAGE_MIMES); i++)
	{
		if (SDL_HasClipboardData(IMAGE_MIMES[i]))
		{
			formats[n++].formatId = CF_DIB;
			break;
		}
	}
	CLIPRDR_FORMAT_LIST list = { 0 };
	list.common.msgType = CB_FORMAT_LIST;
	list.numFormats = n;
	list.formats = formats;
	c->ClientFormatList(c, &list);
}

/* Сервер попросив дані — відповідаємо з головного потоку (там читається буфер SDL). */
static void answer_data_request(MhrdClipboard* cb, UINT32 fmt)
{
	CliprdrClientContext* c = get_cliprdr(cb);
	if (!c)
		return;
	CLIPRDR_FORMAT_DATA_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_FAIL;
	BYTE* data = NULL;
	UINT32 len = 0;
	if (fmt == CF_UNICODETEXT)
	{
		char* text = SDL_GetClipboardText();
		if (text && *text)
			data = utf8_to_unicodetext(text, &len);
		SDL_free(text);
	}
	else if (fmt == CF_DIB)
		data = local_image_to_dib(&len);
	if (data && len <= CLIP_MAX)
	{
		resp.common.msgFlags = CB_RESPONSE_OK;
		resp.common.dataLen = len;
		resp.requestedFormatData = data;
	}
	c->ClientFormatDataResponse(c, &resp);
	free(data);
}

static UINT on_server_format_data_request(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_REQUEST* req)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	post_main(cb, answer_data_request, req->requestedFormatId);
	return CHANNEL_RC_OK;
}

static Uint32 SDLCALL check_timer(void* userdata, SDL_TimerID id, Uint32 interval)
{
	(void)id;
	(void)interval;
	MhrdClipboard* cb = (MhrdClipboard*)userdata;
	post_main(cb, send_client_format_list, 0);
	release(cb);
	return 0; /* один раз */
}

/* Перевірити буфер і повідомити сервер — трохи згодом і поза обробкою подій SDL: читання буфера X11
 * саме чекає подій, а вкладена обробка ламається; на Wayland вміст буфера приходить разом із фокусом. */
static void schedule_check(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	const BOOL skip = cb->checkQueued || cb->closed;
	if (!skip)
	{
		cb->checkQueued = TRUE;
		cb->pending++;
	}
	LeaveCriticalSection(&cb->lock);
	if (!skip && !SDL_AddTimer(150, check_timer, cb))
	{
		EnterCriticalSection(&cb->lock);
		cb->checkQueued = FALSE;
		LeaveCriticalSection(&cb->lock);
		release(cb);
	}
}

/* Хтось у системі скопіював — повідомити сервер. SDL на X11 не завжди повідомляє про чужі зміни
 * буфера (без XFixes), тож перевіряємо ще й щоразу, як вікно сеансу отримує фокус: скопіювали в
 * іншій програмі й повернулись у сеанс. Свої ж зміни (owner) не пересилаємо. */
static bool SDLCALL on_sdl_event(void* userdata, SDL_Event* e)
{
	MhrdClipboard* cb = (MhrdClipboard*)userdata;
	if (e->type == SDL_EVENT_CLIPBOARD_UPDATE && !e->clipboard.owner)
	{
		EnterCriticalSection(&cb->lock);
		cb->owned = FALSE; /* нашу «обіцянку» сервера в буфері замінили */
		LeaveCriticalSection(&cb->lock);
		schedule_check(cb);
	}
	else if (e->type == SDL_EVENT_WINDOW_FOCUS_GAINED)
		schedule_check(cb);
	return true;
}

/* ── Буфер сервера → наш ──────────────────────────────────────── */

static UINT on_server_format_data_response(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_RESPONSE* resp)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	EnterCriticalSection(&cb->lock);
	free(cb->response);
	cb->response = NULL;
	cb->responseLen = 0;
	cb->responseOk = (resp->common.msgFlags & CB_RESPONSE_OK) && resp->requestedFormatData &&
	                 resp->common.dataLen <= CLIP_MAX;
	if (cb->responseOk && resp->common.dataLen > 0)
	{
		cb->response = malloc(resp->common.dataLen);
		if (cb->response)
		{
			memcpy(cb->response, resp->requestedFormatData, resp->common.dataLen);
			cb->responseLen = resp->common.dataLen;
		}
		else
			cb->responseOk = FALSE;
	}
	LeaveCriticalSection(&cb->lock);
	SetEvent(cb->responseEvent);
	return CHANNEL_RC_OK;
}

/* Просить у сервера дані формату й чекає відповіді (головний потік). Пам'ять — malloc. */
static BYTE* request_server_data(MhrdClipboard* cb, UINT32 fmt, UINT32* outLen)
{
	CliprdrClientContext* c = get_cliprdr(cb);
	if (!c)
		return NULL;
	ResetEvent(cb->responseEvent);
	CLIPRDR_FORMAT_DATA_REQUEST req = { 0 };
	req.common.msgType = CB_FORMAT_DATA_REQUEST;
	req.requestedFormatId = fmt;
	if (c->ClientFormatDataRequest(c, &req) != CHANNEL_RC_OK)
		return NULL;
	if (WaitForSingleObject(cb->responseEvent, RENDER_TIMEOUT_MS) != WAIT_OBJECT_0)
		return NULL;
	EnterCriticalSection(&cb->lock);
	BYTE* data = cb->responseOk ? cb->response : NULL;
	*outLen = data ? cb->responseLen : 0;
	if (!data)
		free(cb->response);
	cb->response = NULL;
	cb->responseLen = 0;
	LeaveCriticalSection(&cb->lock);
	return data;
}

static BOOL is_text_mime(const char* mime)
{
	for (size_t i = 0; i < SDL_arraysize(TEXT_MIMES); i++)
	{
		if (SDL_strcmp(mime, TEXT_MIMES[i]) == 0)
			return TRUE;
	}
	return FALSE;
}

/* Тут вставляють те, що скопійовано на сервері: лише тепер просимо дані. */
static const void* SDLCALL provide_data(void* userdata, const char* mime, size_t* size)
{
	MhrdClipboard* cb = (MhrdClipboard*)userdata;
	*size = 0;
	SDL_free(cb->served);
	cb->served = NULL;
	if (!mime)
		return NULL;
	UINT32 len = 0;
	if (is_text_mime(mime))
	{
		BYTE* data = request_server_data(cb, CF_UNICODETEXT, &len);
		if (data)
			cb->served = unicodetext_to_utf8(data, len, size);
		free(data);
	}
	else if (SDL_strcmp(mime, "image/png") == 0 || SDL_strcmp(mime, "image/bmp") == 0)
	{
		BYTE* data = request_server_data(cb, CF_DIB, &len);
		SDL_Surface* s = data ? dib_to_surface(data, len) : NULL;
		free(data);
		if (s)
		{
			cb->served = surface_to_file(s, SDL_strcmp(mime, "image/png") == 0, size);
			SDL_DestroySurface(s);
		}
	}
	if (!cb->served)
		*size = 0;
	return cb->served;
}

/* SDL прибрав нашу «обіцянку» (її замінили) — дані звільняються при наступному запиті чи в clipboard_free. */
static void SDLCALL cleanup_data(void* userdata)
{
	MhrdClipboard* cb = (MhrdClipboard*)userdata;
	EnterCriticalSection(&cb->lock);
	cb->owned = FALSE;
	LeaveCriticalSection(&cb->lock);
}

static void take_ownership(MhrdClipboard* cb, UINT32 unused)
{
	(void)unused;
	EnterCriticalSection(&cb->lock);
	const BOOL text = cb->serverText, dib = cb->serverDib;
	LeaveCriticalSection(&cb->lock);
	const char* mimes[SDL_arraysize(TEXT_MIMES) + SDL_arraysize(IMAGE_MIMES)];
	size_t n = 0;
	for (size_t i = 0; text && i < SDL_arraysize(TEXT_MIMES); i++)
		mimes[n++] = TEXT_MIMES[i];
	for (size_t i = 0; dib && i < SDL_arraysize(IMAGE_MIMES); i++)
		mimes[n++] = IMAGE_MIMES[i];
	/* Попередня «обіцянка» прибирається з cleanup_data (owned = FALSE) — тому позначка після виклику. */
	if (n > 0 && SDL_SetClipboardData(provide_data, cleanup_data, cb, mimes, n))
	{
		EnterCriticalSection(&cb->lock);
		cb->owned = TRUE;
		LeaveCriticalSection(&cb->lock);
	}
}

static UINT on_server_format_list(CliprdrClientContext* c, const CLIPRDR_FORMAT_LIST* list)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	BOOL text = FALSE, dib = FALSE;
	for (UINT32 i = 0; i < list->numFormats; i++)
	{
		text |= list->formats[i].formatId == CF_UNICODETEXT;
		dib |= list->formats[i].formatId == CF_DIB;
	}
	EnterCriticalSection(&cb->lock);
	cb->serverText = text;
	cb->serverDib = dib;
	LeaveCriticalSection(&cb->lock);

	CLIPRDR_FORMAT_LIST_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_LIST_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	const UINT rc = c->ClientFormatListResponse(c, &resp);
	if (text || dib)
		post_main(cb, take_ownership, 0);
	return rc;
}

/* ── Канал ────────────────────────────────────────────────────── */

static UINT on_monitor_ready(CliprdrClientContext* c, const CLIPRDR_MONITOR_READY* ready)
{
	(void)ready;
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	CLIPRDR_GENERAL_CAPABILITY_SET general = { 0 };
	general.capabilitySetType = CB_CAPSTYPE_GENERAL;
	general.capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN;
	general.version = CB_CAPS_VERSION_2;
	general.generalFlags = CB_USE_LONG_FORMAT_NAMES;
	CLIPRDR_CAPABILITIES caps = { 0 };
	caps.cCapabilitiesSets = 1;
	caps.capabilitySets = (CLIPRDR_CAPABILITY_SET*)&general;
	const UINT rc = c->ClientCapabilities(c, &caps);
	if (rc != CHANNEL_RC_OK)
		return rc;
	post_main(cb, send_client_format_list, 0); /* що вже скопійовано до підключення */
	return CHANNEL_RC_OK;
}

static UINT on_server_capabilities(CliprdrClientContext* c, const CLIPRDR_CAPABILITIES* caps)
{
	(void)c;
	(void)caps;
	return CHANNEL_RC_OK;
}

static UINT on_server_format_list_response(CliprdrClientContext* c, const CLIPRDR_FORMAT_LIST_RESPONSE* resp)
{
	(void)c;
	(void)resp;
	return CHANNEL_RC_OK;
}

MhrdClipboard* clipboard_new(void)
{
	/* Без вікна SDL (режим без вікна) буфера SDL немає. */
	if (!SDL_WasInit(SDL_INIT_VIDEO))
		return NULL;
	MhrdClipboard* cb = calloc(1, sizeof(MhrdClipboard));
	if (!cb)
		return NULL;
	InitializeCriticalSection(&cb->lock);
	cb->responseEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	if (!cb->responseEvent || !SDL_AddEventWatch(on_sdl_event, cb))
	{
		destroy(cb);
		return NULL;
	}
	return cb;
}

void clipboard_attach(MhrdClipboard* cb, CliprdrClientContext* cliprdr)
{
	cliprdr->custom = cb;
	cliprdr->MonitorReady = on_monitor_ready;
	cliprdr->ServerCapabilities = on_server_capabilities;
	cliprdr->ServerFormatList = on_server_format_list;
	cliprdr->ServerFormatListResponse = on_server_format_list_response;
	cliprdr->ServerFormatDataRequest = on_server_format_data_request;
	cliprdr->ServerFormatDataResponse = on_server_format_data_response;
	EnterCriticalSection(&cb->lock);
	cb->cliprdr = cliprdr;
	LeaveCriticalSection(&cb->lock);
}

void clipboard_detach(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	cb->cliprdr = NULL;
	LeaveCriticalSection(&cb->lock);
	SetEvent(cb->responseEvent); /* розбудити «Вставити», якщо чекає */
}

void clipboard_free(MhrdClipboard* cb)
{
	if (!cb)
		return;
	clipboard_detach(cb);
	SDL_RemoveEventWatch(on_sdl_event, cb);
	EnterCriticalSection(&cb->lock);
	cb->closed = TRUE;
	const BOOL now = cb->pending == 0;
	LeaveCriticalSection(&cb->lock);
	if (now)
		destroy(cb);
}
