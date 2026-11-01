/* Буфер обміну для Windows: CF_UNICODETEXT і CF_DIB у обидва боки; файли — звідси на сервер.
 *
 * Файли (CF_HDROP у нашому буфері): серверу оголошуємо формат FileGroupDescriptorW. На «Вставити»
 * сервер просить список (FILEDESCRIPTORW з розмірами, теки — рекурсивно), потім вміст кожного
 * файлу частинами (FileContentsRequest). Провідник на ПК сам показує прогрес.
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

#include <ole2.h>
#include <shellapi.h>
#include <shlobj.h>

#define WM_MHRD_SERVER_FORMATS (WM_APP + 1)
#define RENDER_TIMEOUT_MS 5000
#define MAX_CLIP_FILES 100000 /* запобіжник від «скопіював увесь диск» */
#define FILE_CHUNK_MAX (16u * 1024 * 1024) /* найбільший шматок файлу на один запит сервера */

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

	/* Файли з нашого буфера на момент запиту списку сервером (індекс = listIndex) */
	UINT fileFormat; /* id формату FileGroupDescriptorW у цій системі */
	UINT contentsFormat; /* id формату FileContents */
	WCHAR** files;
	UINT32 fileCount;
	HANDLE openFile; /* відкритий для читання файл (сервер читає послідовно) */
	UINT32 openIndex;

	/* Файли сервера → нам (OLE IDataObject у буфері Windows) */
	UINT32 serverFiles;        /* id формату FileGroupDescriptorW у сервера; 0 — файлів немає */
	IDataObject* dataObject;   /* наш об'єкт у буфері Windows */
	HANDLE fcEvent;            /* відповідь на FileContentsRequest */
	BYTE* fcData;
	UINT32 fcLen;
	BOOL fcOk;
	UINT32 nextStreamId;
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
	CLIPRDR_FORMAT formats[3] = { 0 };
	UINT32 n = 0;
	/* Windows сам синтезує CF_UNICODETEXT з CF_TEXT і CF_DIB з бітмапа. */
	if (IsClipboardFormatAvailable(CF_UNICODETEXT))
		formats[n++].formatId = CF_UNICODETEXT;
	if (IsClipboardFormatAvailable(CF_DIB))
		formats[n++].formatId = CF_DIB;
	if (IsClipboardFormatAvailable(CF_HDROP))
	{
		formats[n].formatId = cb->fileFormat;
		formats[n++].formatName = (char*)"FileGroupDescriptorW";
	}
	CLIPRDR_FORMAT_LIST list = { 0 };
	list.common.msgType = CB_FORMAT_LIST;
	list.numFormats = n;
	list.formats = formats;
	UINT rc = c->ClientFormatList(c, &list);
	(void)rc;
}

/* ── Файли: наш буфер → сервер ────────────────────────────────── */

static void free_files(MhrdClipboard* cb)
{
	if (cb->openFile != INVALID_HANDLE_VALUE)
		CloseHandle(cb->openFile);
	cb->openFile = INVALID_HANDLE_VALUE;
	for (UINT32 i = 0; i < cb->fileCount; i++)
		free(cb->files[i]);
	free(cb->files);
	cb->files = NULL;
	cb->fileCount = 0;
}

typedef struct
{
	FILEDESCRIPTORW* desc;
	WCHAR** paths;
	UINT32 count;
	UINT32 cap;
} FileList;

/* Додає файл або теку (з усім вмістом). rel — ім'я, як його побачить сервер ("Тека\файл.txt"). */
static void add_file(FileList* list, const WCHAR* abs, const WCHAR* rel)
{
	WIN32_FILE_ATTRIBUTE_DATA a;
	if (list->count >= MAX_CLIP_FILES || wcslen(rel) >= MAX_PATH ||
	    !GetFileAttributesExW(abs, GetFileExInfoStandard, &a))
		return;
	if (list->count == list->cap)
	{
		const UINT32 cap = list->cap ? list->cap * 2 : 16;
		FILEDESCRIPTORW* d = realloc(list->desc, cap * sizeof(FILEDESCRIPTORW));
		if (d)
			list->desc = d;
		WCHAR** p = realloc(list->paths, cap * sizeof(WCHAR*));
		if (p)
			list->paths = p;
		if (!d || !p)
			return;
		list->cap = cap;
	}
	WCHAR* dup = _wcsdup(abs);
	if (!dup)
		return;
	FILEDESCRIPTORW* d = &list->desc[list->count];
	memset(d, 0, sizeof(*d));
	d->dwFlags = FD_ATTRIBUTES | FD_FILESIZE | FD_WRITESTIME | FD_PROGRESSUI;
	d->dwFileAttributes = a.dwFileAttributes;
	d->ftLastWriteTime = a.ftLastWriteTime;
	d->nFileSizeHigh = a.nFileSizeHigh;
	d->nFileSizeLow = a.nFileSizeLow;
	wcsncpy_s(d->cFileName, MAX_PATH, rel, _TRUNCATE);
	list->paths[list->count++] = dup;

	if (!(a.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
		return;
	/* Тека: вміст рекурсивно, імена — відносно скопійованого. */
	const size_t absLen = wcslen(abs), relLen = wcslen(rel);
	WCHAR* pattern = malloc((absLen + 3) * sizeof(WCHAR));
	if (!pattern)
		return;
	swprintf(pattern, absLen + 3, L"%s\\*", abs);
	WIN32_FIND_DATAW fd;
	HANDLE h = FindFirstFileW(pattern, &fd);
	free(pattern);
	if (h == INVALID_HANDLE_VALUE)
		return;
	do
	{
		if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0)
			continue;
		const size_t nameLen = wcslen(fd.cFileName);
		WCHAR* childAbs = malloc((absLen + nameLen + 2) * sizeof(WCHAR));
		WCHAR* childRel = malloc((relLen + nameLen + 2) * sizeof(WCHAR));
		if (childAbs && childRel)
		{
			swprintf(childAbs, absLen + nameLen + 2, L"%s\\%s", abs, fd.cFileName);
			swprintf(childRel, relLen + nameLen + 2, L"%s\\%s", rel, fd.cFileName);
			add_file(list, childAbs, childRel);
		}
		free(childAbs);
		free(childRel);
	} while (FindNextFileW(h, &fd));
	FindClose(h);
}

/* Знімок файлів із CF_HDROP → FILEGROUPDESCRIPTORW (u32 кількість + FILEDESCRIPTORW[]). */
static BYTE* build_file_list(MhrdClipboard* cb, UINT32* outLen)
{
	FileList list = { 0 };
	if (open_clipboard(NULL))
	{
		HDROP drop = (HDROP)GetClipboardData(CF_HDROP);
		const UINT n = drop ? DragQueryFileW(drop, 0xFFFFFFFF, NULL, 0) : 0;
		for (UINT i = 0; i < n; i++)
		{
			WCHAR path[MAX_PATH * 4];
			if (!DragQueryFileW(drop, i, path, ARRAYSIZE(path)))
				continue;
			const WCHAR* slash = wcsrchr(path, L'\\');
			add_file(&list, path, slash ? slash + 1 : path); /* верхній рівень — лише ім'я */
		}
		CloseClipboard();
	}

	EnterCriticalSection(&cb->lock);
	free_files(cb);
	cb->files = list.paths;
	cb->fileCount = list.count;
	LeaveCriticalSection(&cb->lock);

	const UINT32 len = (UINT32)(sizeof(UINT32) + (size_t)list.count * sizeof(FILEDESCRIPTORW));
	BYTE* buf = malloc(len);
	if (buf)
	{
		memcpy(buf, &list.count, sizeof(UINT32));
		if (list.count)
			memcpy(buf + sizeof(UINT32), list.desc, (size_t)list.count * sizeof(FILEDESCRIPTORW));
		*outLen = len;
	}
	free(list.desc);
	return buf;
}

/* Сервер просить розмір файлу або шматок його вмісту. */
static UINT on_server_file_contents_request(CliprdrClientContext* c, const CLIPRDR_FILE_CONTENTS_REQUEST* req)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	CLIPRDR_FILE_CONTENTS_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FILECONTENTS_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_FAIL;
	resp.streamId = req->streamId;
	BYTE* data = NULL;
	UINT32 len = 0;

	EnterCriticalSection(&cb->lock);
	const WCHAR* path = req->listIndex < cb->fileCount ? cb->files[req->listIndex] : NULL;
	if (path && (req->dwFlags & FILECONTENTS_SIZE))
	{
		WIN32_FILE_ATTRIBUTE_DATA a;
		if (GetFileAttributesExW(path, GetFileExInfoStandard, &a) && (data = malloc(8)) != NULL)
		{
			const UINT64 size = ((UINT64)a.nFileSizeHigh << 32) | a.nFileSizeLow;
			memcpy(data, &size, 8);
			len = 8;
			resp.common.msgFlags = CB_RESPONSE_OK;
		}
	}
	else if (path && (req->dwFlags & FILECONTENTS_RANGE))
	{
		/* Сервер читає файл послідовно — тримаємо його відкритим між запитами. */
		if (cb->openFile == INVALID_HANDLE_VALUE || cb->openIndex != req->listIndex)
		{
			if (cb->openFile != INVALID_HANDLE_VALUE)
				CloseHandle(cb->openFile);
			cb->openFile = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
			                           FILE_FLAG_SEQUENTIAL_SCAN, NULL);
			cb->openIndex = req->listIndex;
		}
		LARGE_INTEGER pos;
		pos.LowPart = req->nPositionLow;
		pos.HighPart = (LONG)req->nPositionHigh;
		DWORD got = 0;
		/* Розмір задає сервер (до 4 ГБ на запит) — без межі зловмисний сервер міг би вичерпати пам'ять.
		 * Коротша відповідь дозволена (як у кінці файлу): сервер попросить наступний шматок. */
		const DWORD want = req->cbRequested < FILE_CHUNK_MAX ? req->cbRequested : FILE_CHUNK_MAX;
		if (cb->openFile != INVALID_HANDLE_VALUE && SetFilePointerEx(cb->openFile, pos, NULL, FILE_BEGIN) &&
		    (data = malloc(want ? want : 1)) != NULL && ReadFile(cb->openFile, data, want, &got, NULL))
		{
			len = got; /* у кінці файлу — менше, ніж просили */
			resp.common.msgFlags = CB_RESPONSE_OK;
		}
	}
	LeaveCriticalSection(&cb->lock);

	resp.common.dataLen = len;
	resp.cbRequested = len;
	resp.requestedData = data;
	UINT rc = c->ClientFileContentsResponse(c, &resp);
	free(data);
	return rc;
}

static UINT on_server_format_data_request(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_REQUEST* req)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	CLIPRDR_FORMAT_DATA_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_FAIL;

	const UINT fmt = req->requestedFormatId;
	if (fmt == cb->fileFormat)
	{
		UINT32 len = 0;
		BYTE* list = build_file_list(cb, &len);
		if (list)
		{
			resp.common.msgFlags = CB_RESPONSE_OK;
			resp.common.dataLen = len;
			resp.requestedFormatData = list;
		}
		UINT rc = c->ClientFormatDataResponse(c, &resp);
		free(list);
		return rc;
	}

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
	UINT32 files = 0;
	for (UINT32 i = 0; i < list->numFormats; i++)
	{
		const UINT32 id = list->formats[i].formatId;
		const char* name = list->formats[i].formatName;
		text |= id == CF_UNICODETEXT;
		dib |= id == CF_DIB;
		if (name && strcmp(name, "FileGroupDescriptorW") == 0)
			files = id;
	}
	EnterCriticalSection(&cb->lock);
	cb->serverText = text;
	cb->serverDib = dib;
	cb->serverFiles = files;
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

/* ── Файли: сервер → наш буфер (OLE) ──────────────────────────── */

static UINT on_server_file_contents_response(CliprdrClientContext* c, const CLIPRDR_FILE_CONTENTS_RESPONSE* resp)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	EnterCriticalSection(&cb->lock);
	free(cb->fcData);
	cb->fcData = NULL;
	cb->fcLen = 0;
	cb->fcOk = (resp->common.msgFlags & CB_RESPONSE_OK) != 0;
	if (cb->fcOk && resp->cbRequested && resp->requestedData)
	{
		cb->fcData = malloc(resp->cbRequested);
		if (cb->fcData)
		{
			memcpy(cb->fcData, resp->requestedData, resp->cbRequested);
			cb->fcLen = resp->cbRequested;
		}
		else
			cb->fcOk = FALSE;
	}
	LeaveCriticalSection(&cb->lock);
	SetEvent(cb->fcEvent);
	return CHANNEL_RC_OK;
}

/* Розмір файлу (sizeOnly) або шматок вмісту з сервера. Блокує до відповіді (до 60 с). */
static BOOL request_file_contents(MhrdClipboard* cb, UINT32 index, BOOL sizeOnly, UINT64 pos, UINT32 want, BYTE* out,
                                  UINT32* got)
{
	*got = 0;
	CliprdrClientContext* c = get_cliprdr(cb);
	if (!c)
		return FALSE;
	ResetEvent(cb->fcEvent);
	CLIPRDR_FILE_CONTENTS_REQUEST req = { 0 };
	req.common.msgType = CB_FILECONTENTS_REQUEST;
	req.streamId = ++cb->nextStreamId;
	req.listIndex = index;
	req.dwFlags = sizeOnly ? FILECONTENTS_SIZE : FILECONTENTS_RANGE;
	req.nPositionLow = (UINT32)pos;
	req.nPositionHigh = (UINT32)(pos >> 32);
	req.cbRequested = sizeOnly ? 8 : want;
	if (c->ClientFileContentsRequest(c, &req) != CHANNEL_RC_OK)
		return FALSE;
	if (WaitForSingleObject(cb->fcEvent, 60000) != WAIT_OBJECT_0)
		return FALSE;
	EnterCriticalSection(&cb->lock);
	const BOOL ok = cb->fcOk;
	UINT32 n = cb->fcLen;
	if (n > req.cbRequested)
		n = req.cbRequested;
	if (ok && n)
		memcpy(out, cb->fcData, n);
	*got = ok ? n : 0;
	free(cb->fcData);
	cb->fcData = NULL;
	cb->fcLen = 0;
	LeaveCriticalSection(&cb->lock);
	return ok;
}

/* IStream: файл сервера, який Провідник читає частинами під час «Вставити». */
typedef struct
{
	IStream iface;
	LONG refs;
	MhrdClipboard* cb;
	UINT32 index;
	ULONGLONG size;
	ULONGLONG pos;
} FileStream;

static HRESULT STDMETHODCALLTYPE fs_QueryInterface(IStream* This, REFIID riid, void** ppv)
{
	if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IStream) ||
	    IsEqualIID(riid, &IID_ISequentialStream))
	{
		*ppv = This;
		This->lpVtbl->AddRef(This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE fs_AddRef(IStream* This)
{
	return (ULONG)InterlockedIncrement(&((FileStream*)This)->refs);
}

static ULONG STDMETHODCALLTYPE fs_Release(IStream* This)
{
	FileStream* s = (FileStream*)This;
	const LONG n = InterlockedDecrement(&s->refs);
	if (n == 0)
		free(s);
	return (ULONG)n;
}

static HRESULT STDMETHODCALLTYPE fs_Read(IStream* This, void* pv, ULONG cb, ULONG* pcbRead)
{
	FileStream* s = (FileStream*)This;
	ULONG done = 0;
	while (done < cb && s->pos < s->size)
	{
		ULONGLONG left = s->size - s->pos;
		UINT32 want = (UINT32)min((ULONGLONG)(cb - done), min(left, (ULONGLONG)(1u << 20)));
		UINT32 got = 0;
		if (!request_file_contents(s->cb, s->index, FALSE, s->pos, want, (BYTE*)pv + done, &got))
			return done ? S_OK : STG_E_READFAULT;
		if (got == 0)
			break;
		done += got;
		s->pos += got;
	}
	if (pcbRead)
		*pcbRead = done;
	return done < cb ? S_FALSE : S_OK;
}

static HRESULT STDMETHODCALLTYPE fs_Write(IStream* This, const void* pv, ULONG cb, ULONG* written)
{
	(void)This;
	(void)pv;
	(void)cb;
	(void)written;
	return STG_E_ACCESSDENIED;
}

static HRESULT STDMETHODCALLTYPE fs_Seek(IStream* This, LARGE_INTEGER move, DWORD origin, ULARGE_INTEGER* newPos)
{
	FileStream* s = (FileStream*)This;
	LONGLONG base = origin == STREAM_SEEK_SET ? 0 : origin == STREAM_SEEK_CUR ? (LONGLONG)s->pos : (LONGLONG)s->size;
	const LONGLONG p = base + move.QuadPart;
	if (p < 0)
		return STG_E_INVALIDFUNCTION;
	s->pos = (ULONGLONG)p;
	if (newPos)
		newPos->QuadPart = s->pos;
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE fs_SetSize(IStream* This, ULARGE_INTEGER size)
{
	(void)This;
	(void)size;
	return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE fs_CopyTo(IStream* This, IStream* dst, ULARGE_INTEGER cb, ULARGE_INTEGER* read,
                                           ULARGE_INTEGER* written)
{
	(void)This;
	(void)dst;
	(void)cb;
	(void)read;
	(void)written;
	return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE fs_Commit(IStream* This, DWORD flags)
{
	(void)This;
	(void)flags;
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE fs_Revert(IStream* This)
{
	(void)This;
	return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE fs_LockRegion(IStream* This, ULARGE_INTEGER off, ULARGE_INTEGER cb, DWORD type)
{
	(void)This;
	(void)off;
	(void)cb;
	(void)type;
	return STG_E_INVALIDFUNCTION;
}

static HRESULT STDMETHODCALLTYPE fs_Stat(IStream* This, STATSTG* st, DWORD flags)
{
	(void)flags;
	FileStream* s = (FileStream*)This;
	memset(st, 0, sizeof(*st));
	st->type = STGTY_STREAM;
	st->cbSize.QuadPart = s->size;
	st->grfMode = STGM_READ;
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE fs_Clone(IStream* This, IStream** out)
{
	(void)This;
	*out = NULL;
	return E_NOTIMPL;
}

static IStreamVtbl g_fileStreamVtbl = {
	.QueryInterface = fs_QueryInterface,
	.AddRef = fs_AddRef,
	.Release = fs_Release,
	.Read = fs_Read,
	.Write = fs_Write,
	.Seek = fs_Seek,
	.SetSize = fs_SetSize,
	.CopyTo = fs_CopyTo,
	.Commit = fs_Commit,
	.Revert = fs_Revert,
	.LockRegion = fs_LockRegion,
	.UnlockRegion = fs_LockRegion,
	.Stat = fs_Stat,
	.Clone = fs_Clone,
};

/* IDataObject у буфері Windows: FileGroupDescriptorW (список) і FileContents (потоки). */
typedef struct
{
	IDataObject iface;
	LONG refs;
	MhrdClipboard* cb;
	UINT32 serverFormat;
	BYTE* desc; /* FILEGROUPDESCRIPTORW із сервера (кешується після першого запиту) */
	UINT32 descLen;
	FORMATETC fmts[2];
} FileDataObject;

/* Ім'я файлу від сервера — лише відносний шлях усередині місця вставки: без літери диска, початкового
 * «\», частин «.»/«..» і двокрапок (потоки NTFS). Провідник чистить сам, але не покладаємось. */
static void sanitize_server_name(WCHAR* name)
{
	name[MAX_PATH - 1] = 0;
	WCHAR out[MAX_PATH] = { 0 };
	size_t n = 0;
	const WCHAR* p = name;
	while (*p)
	{
		while (*p == L'\\' || *p == L'/')
			p++;
		const WCHAR* start = p;
		while (*p && *p != L'\\' && *p != L'/')
			p++;
		const size_t len = (size_t)(p - start);
		if (len == 0 || (len == 1 && start[0] == L'.') || (len == 2 && start[0] == L'.' && start[1] == L'.'))
			continue;
		if (n > 0 && n < MAX_PATH - 1)
			out[n++] = L'\\';
		for (size_t i = 0; i < len && n < MAX_PATH - 1; i++)
			out[n++] = start[i] == L':' ? L'_' : start[i];
	}
	out[n] = 0;
	memcpy(name, out, sizeof(out));
}

static BOOL fdo_load_desc(FileDataObject* o)
{
	if (o->desc)
		return TRUE;
	HGLOBAL h = request_server_data(o->cb, o->serverFormat, 30000);
	if (!h)
		return FALSE;
	const SIZE_T size = GlobalSize(h);
	const void* p = GlobalLock(h);
	if (p && size >= sizeof(UINT32))
	{
		o->desc = malloc(size);
		if (o->desc)
		{
			memcpy(o->desc, p, size);
			o->descLen = (UINT32)size;
			UINT32 count = 0;
			memcpy(&count, o->desc, sizeof(UINT32));
			const size_t fit = (size - sizeof(UINT32)) / sizeof(FILEDESCRIPTORW);
			FILEDESCRIPTORW* d = (FILEDESCRIPTORW*)(o->desc + sizeof(UINT32));
			for (size_t i = 0; i < count && i < fit; i++)
				sanitize_server_name(d[i].cFileName);
		}
	}
	if (p)
		GlobalUnlock(h);
	GlobalFree(h);
	return o->desc != NULL;
}

static HRESULT STDMETHODCALLTYPE fdo_QueryInterface(IDataObject* This, REFIID riid, void** ppv)
{
	if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDataObject))
	{
		*ppv = This;
		This->lpVtbl->AddRef(This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE fdo_AddRef(IDataObject* This)
{
	return (ULONG)InterlockedIncrement(&((FileDataObject*)This)->refs);
}

static ULONG STDMETHODCALLTYPE fdo_Release(IDataObject* This)
{
	FileDataObject* o = (FileDataObject*)This;
	const LONG n = InterlockedDecrement(&o->refs);
	if (n == 0)
	{
		free(o->desc);
		free(o);
	}
	return (ULONG)n;
}

static HRESULT STDMETHODCALLTYPE fdo_GetData(IDataObject* This, FORMATETC* fmt, STGMEDIUM* med)
{
	FileDataObject* o = (FileDataObject*)This;
	memset(med, 0, sizeof(*med));
	if (fmt->cfFormat == o->cb->fileFormat && (fmt->tymed & TYMED_HGLOBAL))
	{
		if (!fdo_load_desc(o))
			return E_FAIL;
		HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, o->descLen);
		void* p = h ? GlobalLock(h) : NULL;
		if (!p)
		{
			if (h)
				GlobalFree(h);
			return E_OUTOFMEMORY;
		}
		memcpy(p, o->desc, o->descLen);
		GlobalUnlock(h);
		med->tymed = TYMED_HGLOBAL;
		med->hGlobal = h;
		return S_OK;
	}
	if (fmt->cfFormat == o->cb->contentsFormat && (fmt->tymed & TYMED_ISTREAM))
	{
		if (!fdo_load_desc(o))
			return E_FAIL;
		UINT32 count = 0;
		memcpy(&count, o->desc, sizeof(UINT32));
		if (fmt->lindex < 0 || (UINT32)fmt->lindex >= count ||
		    sizeof(UINT32) + ((size_t)fmt->lindex + 1) * sizeof(FILEDESCRIPTORW) > o->descLen)
			return DV_E_LINDEX;
		const FILEDESCRIPTORW* d = (const FILEDESCRIPTORW*)(o->desc + sizeof(UINT32)) + fmt->lindex;
		ULONGLONG size = ((ULONGLONG)d->nFileSizeHigh << 32) | d->nFileSizeLow;
		if (!(d->dwFlags & FD_FILESIZE))
		{
			BYTE buf[8] = { 0 };
			UINT32 got = 0;
			if (!request_file_contents(o->cb, (UINT32)fmt->lindex, TRUE, 0, 8, buf, &got) || got < 8)
				return E_FAIL;
			memcpy(&size, buf, 8);
		}
		FileStream* s = calloc(1, sizeof(FileStream));
		if (!s)
			return E_OUTOFMEMORY;
		s->iface.lpVtbl = &g_fileStreamVtbl;
		s->refs = 1;
		s->cb = o->cb;
		s->index = (UINT32)fmt->lindex;
		s->size = size;
		med->tymed = TYMED_ISTREAM;
		med->pstm = &s->iface;
		return S_OK;
	}
	return DV_E_FORMATETC;
}

static HRESULT STDMETHODCALLTYPE fdo_GetDataHere(IDataObject* This, FORMATETC* fmt, STGMEDIUM* med)
{
	(void)This;
	(void)fmt;
	(void)med;
	return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE fdo_QueryGetData(IDataObject* This, FORMATETC* fmt)
{
	FileDataObject* o = (FileDataObject*)This;
	if (fmt->cfFormat == o->cb->fileFormat && (fmt->tymed & TYMED_HGLOBAL))
		return S_OK;
	if (fmt->cfFormat == o->cb->contentsFormat && (fmt->tymed & TYMED_ISTREAM))
		return S_OK;
	return DV_E_FORMATETC;
}

static HRESULT STDMETHODCALLTYPE fdo_GetCanonicalFormatEtc(IDataObject* This, FORMATETC* in, FORMATETC* out)
{
	(void)This;
	*out = *in;
	out->ptd = NULL;
	return DATA_S_SAMEFORMATETC;
}

static HRESULT STDMETHODCALLTYPE fdo_SetData(IDataObject* This, FORMATETC* fmt, STGMEDIUM* med, BOOL release)
{
	(void)This;
	(void)fmt;
	(void)med;
	(void)release;
	return E_NOTIMPL; /* «Preferred/Performed DropEffect» тощо нам не потрібні */
}

static HRESULT STDMETHODCALLTYPE fdo_EnumFormatEtc(IDataObject* This, DWORD dir, IEnumFORMATETC** out)
{
	FileDataObject* o = (FileDataObject*)This;
	if (dir != DATADIR_GET)
		return E_NOTIMPL;
	return SHCreateStdEnumFmtEtc(ARRAYSIZE(o->fmts), o->fmts, out);
}

static HRESULT STDMETHODCALLTYPE fdo_DAdvise(IDataObject* This, FORMATETC* fmt, DWORD advf, IAdviseSink* sink,
                                             DWORD* conn)
{
	(void)This;
	(void)fmt;
	(void)advf;
	(void)sink;
	(void)conn;
	return OLE_E_ADVISENOTSUPPORTED;
}

static HRESULT STDMETHODCALLTYPE fdo_DUnadvise(IDataObject* This, DWORD conn)
{
	(void)This;
	(void)conn;
	return OLE_E_ADVISENOTSUPPORTED;
}

static HRESULT STDMETHODCALLTYPE fdo_EnumDAdvise(IDataObject* This, IEnumSTATDATA** out)
{
	(void)This;
	*out = NULL;
	return OLE_E_ADVISENOTSUPPORTED;
}

static IDataObjectVtbl g_fileDataObjectVtbl = {
	.QueryInterface = fdo_QueryInterface,
	.AddRef = fdo_AddRef,
	.Release = fdo_Release,
	.GetData = fdo_GetData,
	.GetDataHere = fdo_GetDataHere,
	.QueryGetData = fdo_QueryGetData,
	.GetCanonicalFormatEtc = fdo_GetCanonicalFormatEtc,
	.SetData = fdo_SetData,
	.EnumFormatEtc = fdo_EnumFormatEtc,
	.DAdvise = fdo_DAdvise,
	.DUnadvise = fdo_DUnadvise,
	.EnumDAdvise = fdo_EnumDAdvise,
};

static IDataObject* file_data_object_new(MhrdClipboard* cb, UINT32 serverFormat)
{
	FileDataObject* o = calloc(1, sizeof(FileDataObject));
	if (!o)
		return NULL;
	o->iface.lpVtbl = &g_fileDataObjectVtbl;
	o->refs = 1;
	o->cb = cb;
	o->serverFormat = serverFormat;
	o->fmts[0].cfFormat = (CLIPFORMAT)cb->fileFormat;
	o->fmts[0].dwAspect = DVASPECT_CONTENT;
	o->fmts[0].lindex = -1;
	o->fmts[0].tymed = TYMED_HGLOBAL;
	o->fmts[1].cfFormat = (CLIPFORMAT)cb->contentsFormat;
	o->fmts[1].dwAspect = DVASPECT_CONTENT;
	o->fmts[1].lindex = -1;
	o->fmts[1].tymed = TYMED_ISTREAM;
	return &o->iface;
}

/* Буфер Windows уже наш (OLE) — прибрати, щоб вставляння після кінця сеансу не зависало. */
static void release_ole_clipboard(MhrdClipboard* cb)
{
	if (cb->dataObject)
	{
		if (OleIsCurrentClipboard(cb->dataObject) == S_OK)
			OleSetClipboard(NULL);
		cb->dataObject->lpVtbl->Release(cb->dataObject);
		cb->dataObject = NULL;
	}
}

/* Займаємо буфер Windows: файли — OLE-об'єктом (Провідник читає потоки); текст і картинки —
 * форматами з відкладеним заповненням (дані — на WM_RENDERFORMAT). */
static void take_ownership(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	const BOOL text = cb->serverText, dib = cb->serverDib;
	const UINT32 files = cb->serverFiles;
	LeaveCriticalSection(&cb->lock);
	release_ole_clipboard(cb);
	if (files)
	{
		cb->dataObject = file_data_object_new(cb, files);
		if (cb->dataObject && OleSetClipboard(cb->dataObject) == S_OK)
			return;
		release_ole_clipboard(cb);
	}
	if (!open_clipboard(cb->hwnd))
		return;
	EmptyClipboard();
	if (text)
		SetClipboardData(CF_UNICODETEXT, NULL);
	if (dib)
		SetClipboardData(CF_DIB, NULL);
	CloseClipboard();
}

/* Буфер змінили ми самі (наше вікно або OLE-вікно нашого процесу) — серверу не пересилаємо. */
static BOOL clipboard_is_ours(HWND hwnd)
{
	HWND owner = GetClipboardOwner();
	if (!owner)
		return FALSE;
	if (owner == hwnd)
		return TRUE;
	DWORD pid = 0;
	GetWindowThreadProcessId(owner, &pid);
	return pid == GetCurrentProcessId();
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
	/* Файли — потоками за запитом сервера, без шляхів нашого диска, і більші за 4 ГБ. */
	general.generalFlags =
	    CB_USE_LONG_FORMAT_NAMES | CB_STREAM_FILECLIP_ENABLED | CB_FILECLIP_NO_FILE_PATHS | CB_HUGE_FILE_SUPPORT_ENABLED;
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
	cliprdr->ServerFileContentsRequest = on_server_file_contents_request;
	cliprdr->ServerFileContentsResponse = on_server_file_contents_response;
	EnterCriticalSection(&cb->lock);
	cb->cliprdr = cliprdr;
	LeaveCriticalSection(&cb->lock);
}

void clipboard_detach(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	cb->cliprdr = NULL;
	cb->fcOk = FALSE;
	LeaveCriticalSection(&cb->lock);
	SetEvent(cb->responseEvent); /* розбудити WM_RENDERFORMAT, якщо чекає */
	SetEvent(cb->fcEvent);       /* і читання файлу Провідником */
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
			/* Зміни, які зробили ми самі (take_ownership, OLE), серверу не пересилаємо. */
			if (cb && !clipboard_is_ours(hwnd))
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
			if (cb)
				release_ole_clipboard(cb);
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
	/* OLE-буфер (файли з сервера) працює лише в STA-потоці з циклом повідомлень — тут. */
	const BOOL ole = SUCCEEDED(OleInitialize(NULL));
	WNDCLASSW wc = { 0 };
	wc.lpfnWndProc = wnd_proc;
	wc.hInstance = GetModuleHandle(NULL);
	wc.lpszClassName = L"MhrdSessionClipboard";
	RegisterClassW(&wc);
	cb->hwnd = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, wc.hInstance, cb);
	if (cb->hwnd)
		AddClipboardFormatListener(cb->hwnd);
	SetEvent(cb->ready);
	if (cb->hwnd)
	{
		MSG msg;
		while (GetMessage(&msg, NULL, 0, 0) > 0)
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}
	if (ole)
		OleUninitialize();
	return cb->hwnd ? 0 : 1;
}

MhrdClipboard* clipboard_new(void)
{
	MhrdClipboard* cb = calloc(1, sizeof(MhrdClipboard));
	if (!cb)
		return NULL;
	InitializeCriticalSection(&cb->lock);
	cb->openFile = INVALID_HANDLE_VALUE;
	cb->fileFormat = RegisterClipboardFormatW(L"FileGroupDescriptorW");
	cb->contentsFormat = RegisterClipboardFormatW(L"FileContents");
	cb->ready = CreateEvent(NULL, TRUE, FALSE, NULL);
	cb->responseEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	cb->fcEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	cb->thread = CreateThread(NULL, 0, window_thread, cb, 0, NULL);
	if (!cb->ready || !cb->responseEvent || !cb->fcEvent || !cb->thread)
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
	if (cb->fcEvent)
		CloseHandle(cb->fcEvent);
	free(cb->response);
	free(cb->fcData);
	free_files(cb);
	DeleteCriticalSection(&cb->lock);
	free(cb);
}
