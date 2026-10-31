/* Буфер обміну для Windows: CF_UNICODETEXT і CF_DIB у обидва боки.
 *
 * Локальна копія → WM_CLIPBOARDUPDATE → серверу список форматів (без даних).
 * Сервер просить дані (ServerFormatDataRequest) → читаємо системний буфер і відповідаємо.
 * Копія на сервері → ServerFormatList → займаємо буфер Windows з відкладеним заповненням;
 * коли програма вставляє (WM_RENDERFORMAT) — просимо дані в сервера й чекаємо відповіді.
 * Вікно живе у власному потоці: поки воно чекає відповіді, головний потік читає мережу.
 */
#include "clipboard.h"

#include <stdlib.h>
#include <string.h>

#include <windows.h>

#define WM_MHRD_SERVER_FORMATS (WM_APP + 1)
#define RENDER_TIMEOUT_MS 5000

struct MhrdClipboard
{
	CRITICAL_SECTION lock;
	CliprdrClientContext* cliprdr; /* NULL, поки канал не підключено */
	HANDLE thread;
	HWND hwnd;
	HANDLE ready;

	/* Що є в буфері сервера */
	BOOL serverText;
	BOOL serverDib;

	/* Відповідь сервера на наш запит даних */
	HANDLE responseEvent;
	BYTE* response;
	UINT32 responseLen;
	BOOL responseOk;
};

static CliprdrClientContext* get_cliprdr(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	CliprdrClientContext* c = cb->cliprdr;
	LeaveCriticalSection(&cb->lock);
	return c;
}

/* Буфер Windows буває тимчасово зайнятий іншою програмою — кілька спроб. */
static BOOL open_clipboard(HWND owner)
{
	for (int i = 0; i < 10; i++)
	{
		if (OpenClipboard(owner))
			return TRUE;
		Sleep(20);
	}
	return FALSE;
}

/* ── Наш буфер → сервер ───────────────────────────────────────── */

static void send_client_format_list(MhrdClipboard* cb)
{
	CliprdrClientContext* c = get_cliprdr(cb);
	if (!c)
		return;
	CLIPRDR_FORMAT formats[2] = { 0 };
	UINT32 n = 0;
	/* Windows сам синтезує CF_UNICODETEXT з CF_TEXT і CF_DIB з бітмапа. */
	if (IsClipboardFormatAvailable(CF_UNICODETEXT))
		formats[n++].formatId = CF_UNICODETEXT;
	if (IsClipboardFormatAvailable(CF_DIB))
		formats[n++].formatId = CF_DIB;
	CLIPRDR_FORMAT_LIST list = { 0 };
	list.common.msgType = CB_FORMAT_LIST;
	list.numFormats = n;
	list.formats = formats;
	UINT rc = c->ClientFormatList(c, &list);
	(void)rc;
}

static UINT on_server_format_data_request(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_REQUEST* req)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	CLIPRDR_FORMAT_DATA_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_FAIL;

	const UINT fmt = req->requestedFormatId;
	BYTE* copy = NULL;
	(void)cb;
	/* Потік каналу, не потік вікна, — відкриваємо буфер без власника. */
	if ((fmt == CF_UNICODETEXT || fmt == CF_DIB) && open_clipboard(NULL))
	{
		HANDLE h = GetClipboardData(fmt);
		const void* p = h ? GlobalLock(h) : NULL;
		if (p)
		{
			SIZE_T size = GlobalSize(h);
			if (fmt == CF_UNICODETEXT)
			{
				/* Лише до нульового символу (GlobalSize буває більшим за рядок). */
				const SIZE_T chars = wcsnlen((const WCHAR*)p, size / sizeof(WCHAR));
				size = (chars + 1) * sizeof(WCHAR);
			}
			copy = malloc(size);
			if (copy)
			{
				memcpy(copy, p, size);
				if (fmt == CF_UNICODETEXT)
					((WCHAR*)copy)[size / sizeof(WCHAR) - 1] = 0;
				resp.common.msgFlags = CB_RESPONSE_OK;
				resp.common.dataLen = (UINT32)size;
				resp.requestedFormatData = copy;
			}
			GlobalUnlock(h);
		}
		CloseClipboard();
	}
	UINT rc = c->ClientFormatDataResponse(c, &resp);
	free(copy);
	return rc;
}

/* ── Буфер сервера → наш ──────────────────────────────────────── */

static UINT on_server_format_list(CliprdrClientContext* c, const CLIPRDR_FORMAT_LIST* list)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	BOOL text = FALSE, dib = FALSE;
	for (UINT32 i = 0; i < list->numFormats; i++)
	{
		const UINT32 id = list->formats[i].formatId;
		text |= id == CF_UNICODETEXT;
		dib |= id == CF_DIB;
	}
	EnterCriticalSection(&cb->lock);
	cb->serverText = text;
	cb->serverDib = dib;
	LeaveCriticalSection(&cb->lock);

	CLIPRDR_FORMAT_LIST_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_LIST_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	UINT rc = c->ClientFormatListResponse(c, &resp);
	PostMessage(cb->hwnd, WM_MHRD_SERVER_FORMATS, 0, 0);
	return rc;
}

static UINT on_server_format_data_response(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_RESPONSE* resp)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	EnterCriticalSection(&cb->lock);
	free(cb->response);
	cb->response = NULL;
	cb->responseLen = 0;
	cb->responseOk = (resp->common.msgFlags & CB_RESPONSE_OK) && resp->requestedFormatData;
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

/* Просить у сервера дані формату й чекає відповіді. Повертає HGLOBAL для SetClipboardData. */
static HGLOBAL request_server_data(MhrdClipboard* cb, UINT fmt, DWORD timeoutMs)
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
	if (WaitForSingleObject(cb->responseEvent, timeoutMs) != WAIT_OBJECT_0)
		return NULL;

	HGLOBAL h = NULL;
	EnterCriticalSection(&cb->lock);
	if (cb->responseOk && cb->response && cb->responseLen)
	{
		h = GlobalAlloc(GMEM_MOVEABLE, cb->responseLen);
		void* p = h ? GlobalLock(h) : NULL;
		if (p)
		{
			memcpy(p, cb->response, cb->responseLen);
			GlobalUnlock(h);
		}
		else if (h)
		{
			GlobalFree(h);
			h = NULL;
		}
	}
	free(cb->response);
	cb->response = NULL;
	cb->responseLen = 0;
	LeaveCriticalSection(&cb->lock);
	return h;
}

/* Займаємо буфер Windows: формати є, дані — потім (WM_RENDERFORMAT). */
static void take_ownership(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	const BOOL text = cb->serverText, dib = cb->serverDib;
	LeaveCriticalSection(&cb->lock);
	if (!open_clipboard(cb->hwnd))
		return;
	EmptyClipboard();
	if (text)
		SetClipboardData(CF_UNICODETEXT, NULL);
	if (dib)
		SetClipboardData(CF_DIB, NULL);
	CloseClipboard();
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
	UINT rc = c->ClientCapabilities(c, &caps);
	if (rc != CHANNEL_RC_OK)
		return rc;
	send_client_format_list(cb); /* що вже скопійовано до підключення */
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
	SetEvent(cb->responseEvent); /* розбудити WM_RENDERFORMAT, якщо чекає */
}

/* ── Приховане вікно ──────────────────────────────────────────── */

static LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	MhrdClipboard* cb = (MhrdClipboard*)GetWindowLongPtr(hwnd, GWLP_USERDATA);
	switch (msg)
	{
		case WM_CREATE:
			SetWindowLongPtr(hwnd, GWLP_USERDATA, (LONG_PTR)((CREATESTRUCT*)lParam)->lpCreateParams);
			return 0;
		case WM_CLIPBOARDUPDATE:
			/* Зміни, які зробили ми самі (take_ownership), серверу не пересилаємо. */
			if (cb && GetClipboardOwner() != hwnd)
				send_client_format_list(cb);
			return 0;
		case WM_MHRD_SERVER_FORMATS:
			if (cb)
				take_ownership(cb);
			return 0;
		case WM_RENDERFORMAT:
			if (cb)
			{
				HGLOBAL h = request_server_data(cb, (UINT)wParam, RENDER_TIMEOUT_MS);
				if (h && !SetClipboardData((UINT)wParam, h))
					GlobalFree(h);
			}
			return 0;
		case WM_RENDERALLFORMATS:
			/* Сеанс закривається, а скопійоване з сервера ще не вставляли — зберегти зараз. */
			if (cb && open_clipboard(hwnd))
			{
				if (GetClipboardOwner() == hwnd)
				{
					const UINT fmts[] = { CF_UNICODETEXT, CF_DIB };
					for (size_t i = 0; i < ARRAYSIZE(fmts); i++)
					{
						HGLOBAL h = request_server_data(cb, fmts[i], 2000);
						if (h && !SetClipboardData(fmts[i], h))
							GlobalFree(h);
					}
				}
				CloseClipboard();
			}
			return 0;
		case WM_DESTROY:
			RemoveClipboardFormatListener(hwnd);
			PostQuitMessage(0);
			return 0;
		default:
			return DefWindowProc(hwnd, msg, wParam, lParam);
	}
}

static DWORD WINAPI window_thread(LPVOID arg)
{
	MhrdClipboard* cb = (MhrdClipboard*)arg;
	WNDCLASSW wc = { 0 };
	wc.lpfnWndProc = wnd_proc;
	wc.hInstance = GetModuleHandle(NULL);
	wc.lpszClassName = L"MhrdSessionClipboard";
	RegisterClassW(&wc);
	cb->hwnd = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, wc.hInstance, cb);
	if (cb->hwnd)
		AddClipboardFormatListener(cb->hwnd);
	SetEvent(cb->ready);
	if (!cb->hwnd)
		return 1;
	MSG msg;
	while (GetMessage(&msg, NULL, 0, 0) > 0)
	{
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}
	return 0;
}

MhrdClipboard* clipboard_new(void)
{
	MhrdClipboard* cb = calloc(1, sizeof(MhrdClipboard));
	if (!cb)
		return NULL;
	InitializeCriticalSection(&cb->lock);
	cb->ready = CreateEvent(NULL, TRUE, FALSE, NULL);
	cb->responseEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	cb->thread = CreateThread(NULL, 0, window_thread, cb, 0, NULL);
	if (!cb->ready || !cb->responseEvent || !cb->thread)
	{
		clipboard_free(cb);
		return NULL;
	}
	WaitForSingleObject(cb->ready, 5000);
	if (!cb->hwnd)
	{
		clipboard_free(cb);
		return NULL;
	}
	return cb;
}

void clipboard_free(MhrdClipboard* cb)
{
	if (!cb)
		return;
	clipboard_detach(cb);
	if (cb->hwnd)
		SendMessage(cb->hwnd, WM_CLOSE, 0, 0); /* DefWindowProc → DestroyWindow → WM_QUIT */
	if (cb->thread)
	{
		WaitForSingleObject(cb->thread, 5000);
		CloseHandle(cb->thread);
	}
	if (cb->ready)
		CloseHandle(cb->ready);
	if (cb->responseEvent)
		CloseHandle(cb->responseEvent);
	free(cb->response);
	DeleteCriticalSection(&cb->lock);
	free(cb);
}
