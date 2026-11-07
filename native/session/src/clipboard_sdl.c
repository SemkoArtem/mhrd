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
 *
 * Файли, як на Windows, — форматом FileGroupDescriptorW (список FILEDESCRIPTORW, теки рекурсивно) і
 * вмістом частинами (FileContentsRequest):
 * - тут → сервер: файлові менеджери кладуть у буфер text/uri-list (file://…); сервер на «Вставити»
 *   бере список, потім читає кожен файл частинами;
 * - сервер → тут: файлові менеджери вставляють text/uri-list чи x-special/gnome-copied-files, тобто
 *   шляхи до готових файлів. Тож файли сервера завантажуються в ~/.cache/mhrd/clipboard (окремий
 *   потік), а буфер віддає їхні шляхи. Завантаження починається, щойно вікно сеансу втратило фокус
 *   (пішли вставляти в іншу програму) або на «Вставити»; тека прибирається з кінцем сеансу чи з
 *   новою копією на сервері.
 */
#define _GNU_SOURCE /* asprintf */
#include "clipboard.h"

#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <SDL3/SDL.h>
#include <winpr/file.h>
#include <winpr/shell.h>
#include <winpr/string.h>
#include <winpr/synch.h>
#include <winpr/user.h>

#define RENDER_TIMEOUT_MS 5000
#define FILE_LIST_TIMEOUT_MS 30000
#define FILE_CHUNK_TIMEOUT_MS 60000
/* Скільки «Вставити» чекає на завантаження файлів сервера: довше програми самі кидають запит буфера —
 * тоді вставляють удруге, коли файли вже завантажено. */
#define FILE_PASTE_WAIT_MS 25000
#define CLIP_MAX (64u * 1024 * 1024) /* запобіжник: більше не просимо й не віддаємо */
#define MAX_CLIP_FILES 100000 /* запобіжник від «скопіював увесь диск» */
#define FILE_CHUNK_MAX (16u * 1024 * 1024) /* найбільший шматок файлу на один запит сервера */
#define FILE_FETCH_CHUNK (4u * 1024 * 1024) /* шматок, який просимо в сервера */
/* id, під яким оголошуємо серверу FileGroupDescriptorW (сервер зіставляє формат за назвою). */
#define FILE_FORMAT_ID 0xC0F0

/* FILEDESCRIPTORW у протоколі — рівно 592 байти. */
typedef char check_filedescriptor_size[sizeof(FILEDESCRIPTORW) == 592 ? 1 : -1];

static const char* const TEXT_MIMES[] = { "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT",
	                                      "STRING" };
static const char* const IMAGE_MIMES[] = { "image/png", "image/bmp" };
static const char* const URI_MIME = "text/uri-list";
static const char* const GNOME_FILES_MIME = "x-special/gnome-copied-files";

struct MhrdClipboard
{
	CRITICAL_SECTION lock;
	CliprdrClientContext* cliprdr; /* NULL, поки канал не підключено */

	/* Що є в буфері сервера */
	BOOL serverText;
	BOOL serverDib;
	UINT32 serverFiles; /* id формату FileGroupDescriptorW у сервера; 0 — файлів немає */

	/* Відповідь сервера на наш запит даних (запити — по одному: reqLock) */
	CRITICAL_SECTION reqLock;
	HANDLE responseEvent;
	BYTE* response;
	UINT32 responseLen;
	BOOL responseOk;
	/* Запити, на які не дочекались відповіді (тайм-аут): сервер відповідає на кожен по черзі, тож
	 * стільки наступних відповідей — запізнілі, і їх не можна віддати новому запиту. */
	UINT32 lateResponses;

	/* Те, що ми віддали SDL у функції даних (живе до наступного запиту) — лише головний потік */
	void* served;

	/* У системному буфері — «обіцянка» сервера (ми її поклали, ніхто не перезаписав): тоді наш буфер
	 * серверу не пересилаємо — це його ж дані. */
	BOOL owned;
	/* Перевірка буфера вже запланована (не плодимо таймери на кожну подію). */
	BOOL checkQueued;
	/* Серверу оголошено файли нашого буфера: лише тоді віддаємо їхній список (інакше сервер міг би
	 * попросити його будь-коли, навіть якщо тут файлів не пропонували). */
	BOOL filesAnnounced;

	/* Завдання для головного потоку чи потік завантаження ще живі: тоді clipboard_free лише позначає
	 * «закрито», а пам'ять звільняє останній. */
	int pending;
	BOOL closed;

	/* Файли з нашого буфера на момент запиту списку сервером (індекс = listIndex) */
	char** files;
	UINT32 fileCount;
	int openFd; /* відкритий для читання файл (сервер читає послідовно) */
	UINT32 openIndex;

	/* Файли сервера → тут */
	HANDLE fcEvent; /* відповідь на FileContentsRequest */
	BYTE* fcData;
	UINT32 fcLen;
	BOOL fcOk;
	UINT32 nextStreamId;
	UINT32 fcStream; /* streamId запиту, на який чекаємо: запізнілі відповіді на старі — ігноруємо */
	UINT32 serial;       /* номер копії на сервері: нова копія скасовує завантаження старої */
	UINT32 fetchSerial;  /* для якої копії вже запущено завантаження (0 — ні для якої) */
	BOOL fetchDone;      /* завантаження fetchSerial закінчилось (fetchUris — результат) */
	HANDLE fetchEvent;   /* сигналить, коли fetchDone */
	char* fetchUris;     /* «file:///…\r\n» верхнього рівня; NULL — не вдалось */
	char* fetchDir;      /* тека завантаження fetchSerial */
};

static CliprdrClientContext* get_cliprdr(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	CliprdrClientContext* c = cb->closed ? NULL : cb->cliprdr;
	LeaveCriticalSection(&cb->lock);
	return c;
}

static void free_files(MhrdClipboard* cb)
{
	if (cb->openFd >= 0)
		close(cb->openFd);
	cb->openFd = -1;
	for (UINT32 i = 0; i < cb->fileCount; i++)
		free(cb->files[i]);
	free(cb->files);
	cb->files = NULL;
	cb->fileCount = 0;
}

static int remove_entry(const char* path, const struct stat* st, int flag, struct FTW* ftw)
{
	(void)st;
	(void)flag;
	(void)ftw;
	remove(path);
	return 0;
}

/* Тека завантажених файлів сервера — геть разом із вмістом (без переходу за посиланнями). */
static void remove_tree(const char* dir)
{
	if (dir && *dir)
		nftw(dir, remove_entry, 16, FTW_DEPTH | FTW_PHYS);
}

static void destroy(MhrdClipboard* cb)
{
	CloseHandle(cb->responseEvent);
	CloseHandle(cb->fcEvent);
	CloseHandle(cb->fetchEvent);
	free(cb->response);
	free(cb->fcData);
	free(cb->fetchUris);
	remove_tree(cb->fetchDir);
	free(cb->fetchDir);
	free_files(cb);
	SDL_free(cb->served);
	DeleteCriticalSection(&cb->reqLock);
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

/* Завдання (таймер, потік) закінчилось: останнє після clipboard_free звільняє пам'ять. */
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

/* ── Файли: наш буфер → сервер ────────────────────────────────── */

static int hexval(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

/* «file:///шлях» чи «file://вузол/шлях» (з %XX) → абсолютний шлях; NULL — не локальний файл. */
static char* uri_to_path(const char* uri, size_t len)
{
	static const char prefix[] = "file://";
	if (len < sizeof(prefix) - 1 || strncmp(uri, prefix, sizeof(prefix) - 1) != 0)
		return NULL;
	const char* p = uri + sizeof(prefix) - 1;
	const char* end = uri + len;
	while (p < end && *p != '/') /* вузол (зазвичай порожній чи localhost) */
		p++;
	if (p >= end)
		return NULL;
	char* out = malloc((size_t)(end - p) + 1);
	if (!out)
		return NULL;
	size_t o = 0;
	for (; p < end; p++)
	{
		int hi, lo;
		if (*p == '%' && p + 2 < end && (hi = hexval(p[1])) >= 0 && (lo = hexval(p[2])) >= 0)
		{
			out[o++] = (char)(hi * 16 + lo);
			p += 2;
		}
		else
			out[o++] = *p;
	}
	out[o] = 0;
	if (o == 0 || memchr(out, 0, o) != NULL)
	{
		free(out);
		return NULL;
	}
	return out;
}

typedef struct
{
	FILEDESCRIPTORW* desc;
	char** paths;
	UINT32 count;
	UINT32 cap;
} FileList;

/* Час зміни файлу → FILETIME (сотні наносекунд від 1601 року). */
static FILETIME to_filetime(const struct stat* st)
{
	const UINT64 t = ((UINT64)st->st_mtim.tv_sec + 11644473600ull) * 10000000ull + (UINT64)st->st_mtim.tv_nsec / 100;
	FILETIME ft;
	ft.dwLowDateTime = (DWORD)t;
	ft.dwHighDateTime = (DWORD)(t >> 32);
	return ft;
}

/* Додає файл або теку (з усім вмістом). rel — ім'я, як його побачить сервер ("Тека\файл.txt").
 * top — те, що скопіювали (посилання на нього проходимо); усередині тек посилання на теки пропускаємо —
 * щоб не зациклитись. */
static void add_file(FileList* list, const char* abs, const char* rel, BOOL top)
{
	struct stat st;
	if (list->count >= MAX_CLIP_FILES || lstat(abs, &st) != 0)
		return;
	if (S_ISLNK(st.st_mode))
	{
		if (stat(abs, &st) != 0 || (!top && S_ISDIR(st.st_mode)))
			return;
	}
	if (!S_ISDIR(st.st_mode) && !S_ISREG(st.st_mode))
		return;
	size_t wlen = 0;
	WCHAR* wrel = ConvertUtf8ToWCharAlloc(rel, &wlen);
	if (!wrel || wlen >= 260)
	{
		free(wrel);
		return;
	}
	if (list->count == list->cap)
	{
		const UINT32 cap = list->cap ? list->cap * 2 : 16;
		FILEDESCRIPTORW* d = realloc(list->desc, cap * sizeof(FILEDESCRIPTORW));
		if (d)
			list->desc = d;
		char** p = realloc(list->paths, cap * sizeof(char*));
		if (p)
			list->paths = p;
		if (!d || !p)
		{
			free(wrel);
			return;
		}
		list->cap = cap;
	}
	char* dup = strdup(abs);
	if (!dup)
	{
		free(wrel);
		return;
	}
	FILEDESCRIPTORW* d = &list->desc[list->count];
	memset(d, 0, sizeof(*d));
	d->dwFlags = FD_ATTRIBUTES | FD_FILESIZE | FD_WRITESTIME | FD_PROGRESSUI;
	d->dwFileAttributes = S_ISDIR(st.st_mode) ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
	d->ftLastWriteTime = to_filetime(&st);
	const UINT64 size = S_ISDIR(st.st_mode) ? 0 : (UINT64)st.st_size;
	d->nFileSizeHigh = (DWORD)(size >> 32);
	d->nFileSizeLow = (DWORD)size;
	memcpy(d->cFileName, wrel, wlen * sizeof(WCHAR));
	free(wrel);
	list->paths[list->count++] = dup;

	if (!S_ISDIR(st.st_mode))
		return;
	/* Тека: вміст рекурсивно, імена — відносно скопійованого. */
	DIR* dir = opendir(abs);
	if (!dir)
		return;
	struct dirent* e;
	while ((e = readdir(dir)) != NULL)
	{
		if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0)
			continue;
		char* childAbs = NULL;
		char* childRel = NULL;
		if (asprintf(&childAbs, "%s/%s", abs, e->d_name) >= 0 && asprintf(&childRel, "%s\\%s", rel, e->d_name) >= 0)
			add_file(list, childAbs, childRel, FALSE);
		free(childAbs);
		free(childRel);
	}
	closedir(dir);
}

/* Знімок файлів із text/uri-list нашого буфера → FILEGROUPDESCRIPTORW (u32 кількість + FILEDESCRIPTORW[]).
 * Головний потік (буфер SDL). */
static BYTE* build_file_list(MhrdClipboard* cb, UINT32* outLen)
{
	FileList list = { 0 };
	size_t n = 0;
	char* uris = SDL_HasClipboardData(URI_MIME) ? SDL_GetClipboardData(URI_MIME, &n) : NULL;
	for (size_t i = 0; uris && i < n;)
	{
		size_t j = i;
		while (j < n && uris[j] != '\n' && uris[j] != '\r' && uris[j] != 0)
			j++;
		if (j > i && uris[i] != '#')
		{
			char* path = uri_to_path(uris + i, j - i);
			if (path && path[0] == '/')
			{
				const char* slash = strrchr(path, '/');
				const char* name = slash[1] ? slash + 1 : path; /* верхній рівень — лише ім'я */
				if (*name && strcmp(name, "/") != 0)
					add_file(&list, path, name, TRUE);
			}
			free(path);
		}
		i = j + 1;
	}
	SDL_free(uris);

	EnterCriticalSection(&cb->lock);
	free_files(cb);
	cb->files = list.paths;
	cb->fileCount = list.count;
	LeaveCriticalSection(&cb->lock);

	const UINT32 len = (UINT32)(sizeof(UINT32) + (size_t)list.count * sizeof(FILEDESCRIPTORW));
	BYTE* buf = malloc(len);
	if (buf)
	{
		wr32(buf, list.count);
		if (list.count)
			memcpy(buf + sizeof(UINT32), list.desc, (size_t)list.count * sizeof(FILEDESCRIPTORW));
		*outLen = len;
	}
	free(list.desc);
	return buf;
}

/* Сервер просить розмір файлу або шматок його вмісту (потік FreeRDP; буфер SDL не потрібен). */
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
	const char* path = req->listIndex < cb->fileCount ? cb->files[req->listIndex] : NULL;
	struct stat st;
	if (path && (req->dwFlags & FILECONTENTS_SIZE))
	{
		if (stat(path, &st) == 0 && S_ISREG(st.st_mode) && (data = malloc(8)) != NULL)
		{
			const UINT64 size = (UINT64)st.st_size;
			memcpy(data, &size, 8);
			len = 8;
			resp.common.msgFlags = CB_RESPONSE_OK;
		}
	}
	else if (path && (req->dwFlags & FILECONTENTS_RANGE))
	{
		/* Сервер читає файл послідовно — тримаємо його відкритим між запитами. */
		if (cb->openFd < 0 || cb->openIndex != req->listIndex)
		{
			if (cb->openFd >= 0)
				close(cb->openFd);
			cb->openFd = open(path, O_RDONLY | O_CLOEXEC);
			cb->openIndex = req->listIndex;
		}
		const UINT64 pos = ((UINT64)req->nPositionHigh << 32) | req->nPositionLow;
		/* Розмір задає сервер (до 4 ГБ на запит) — без межі зловмисний сервер міг би вичерпати пам'ять.
		 * Коротша відповідь дозволена (як у кінці файлу): сервер попросить наступний шматок. */
		const UINT32 want = req->cbRequested < FILE_CHUNK_MAX ? req->cbRequested : FILE_CHUNK_MAX;
		if (cb->openFd >= 0 && (data = malloc(want ? want : 1)) != NULL)
		{
			UINT32 got = 0;
			while (got < want)
			{
				const ssize_t r = pread(cb->openFd, data + got, want - got, (off_t)(pos + got));
				if (r < 0 && errno == EINTR)
					continue;
				if (r <= 0)
					break;
				got += (UINT32)r;
			}
			len = got; /* у кінці файлу — менше, ніж просили */
			resp.common.msgFlags = CB_RESPONSE_OK;
		}
	}
	LeaveCriticalSection(&cb->lock);

	resp.common.dataLen = len;
	resp.cbRequested = len;
	resp.requestedData = data;
	const UINT rc = c->ClientFileContentsResponse(c, &resp);
	free(data);
	return rc;
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
	CLIPRDR_FORMAT formats[3] = { 0 };
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
	const BOOL files = SDL_HasClipboardData(URI_MIME);
	if (files)
	{
		formats[n].formatId = FILE_FORMAT_ID;
		formats[n++].formatName = (char*)"FileGroupDescriptorW";
	}
	EnterCriticalSection(&cb->lock);
	cb->filesAnnounced = files;
	LeaveCriticalSection(&cb->lock);
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
	else if (fmt == FILE_FORMAT_ID)
	{
		EnterCriticalSection(&cb->lock);
		const BOOL announced = cb->filesAnnounced;
		LeaveCriticalSection(&cb->lock);
		if (announced)
			data = build_file_list(cb, &len);
	}
	if (data && (len <= CLIP_MAX || fmt == FILE_FORMAT_ID))
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

static void start_fetch(MhrdClipboard* cb);

/* Хтось у системі скопіював — повідомити сервер (SDL повідомляє й про чужі зміни, на X11 — через
 * XFixes; про всяк випадок перевіряємо й щоразу, як вікно сеансу отримує фокус). Свої ж зміни (owner)
 * не пересилаємо. Вікно втратило фокус — певно, вставлятимуть деінде: файли сервера починаємо
 * завантажувати заздалегідь. */
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
	else if (e->type == SDL_EVENT_WINDOW_FOCUS_LOST)
		start_fetch(cb);
	return true;
}

/* ── Буфер сервера → наш ──────────────────────────────────────── */

static UINT on_server_format_data_response(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_RESPONSE* resp)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	EnterCriticalSection(&cb->lock);
	if (cb->lateResponses > 0)
	{
		cb->lateResponses--; /* відповідь на запит, якого вже не дочекались */
		LeaveCriticalSection(&cb->lock);
		return CHANNEL_RC_OK;
	}
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

/* Просить у сервера дані формату й чекає відповіді (головний потік чи потік завантаження — по одному
 * запиту). Пам'ять — malloc. */
static BYTE* request_server_data(MhrdClipboard* cb, UINT32 fmt, UINT32* outLen, DWORD timeoutMs)
{
	CliprdrClientContext* c = get_cliprdr(cb);
	if (!c)
		return NULL;
	EnterCriticalSection(&cb->reqLock);
	ResetEvent(cb->responseEvent);
	CLIPRDR_FORMAT_DATA_REQUEST req = { 0 };
	req.common.msgType = CB_FORMAT_DATA_REQUEST;
	req.requestedFormatId = fmt;
	BYTE* data = NULL;
	if (c->ClientFormatDataRequest(c, &req) != CHANNEL_RC_OK)
	{
		LeaveCriticalSection(&cb->reqLock);
		return NULL;
	}
	if (WaitForSingleObject(cb->responseEvent, timeoutMs) != WAIT_OBJECT_0)
	{
		EnterCriticalSection(&cb->lock);
		cb->lateResponses++; /* відповідь ще прийде — і її не можна віддати наступному запиту */
		LeaveCriticalSection(&cb->lock);
	}
	else
	{
		EnterCriticalSection(&cb->lock);
		data = cb->responseOk ? cb->response : NULL;
		*outLen = data ? cb->responseLen : 0;
		if (!data)
			free(cb->response);
		cb->response = NULL;
		cb->responseLen = 0;
		LeaveCriticalSection(&cb->lock);
	}
	LeaveCriticalSection(&cb->reqLock);
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

/* ── Файли: сервер → тут ──────────────────────────────────────── */

static UINT on_server_file_contents_response(CliprdrClientContext* c, const CLIPRDR_FILE_CONTENTS_RESPONSE* resp)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	EnterCriticalSection(&cb->lock);
	if (resp->streamId != cb->fcStream)
	{
		LeaveCriticalSection(&cb->lock); /* відповідь на запит, якого вже не чекаємо */
		return CHANNEL_RC_OK;
	}
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

/* Розмір файлу (sizeOnly) або шматок вмісту з сервера. Потік завантаження; блокує до відповіді. */
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
	EnterCriticalSection(&cb->lock);
	cb->fcStream = req.streamId;
	LeaveCriticalSection(&cb->lock);
	req.listIndex = index;
	req.dwFlags = sizeOnly ? FILECONTENTS_SIZE : FILECONTENTS_RANGE;
	req.nPositionLow = (UINT32)pos;
	req.nPositionHigh = (UINT32)(pos >> 32);
	req.cbRequested = sizeOnly ? 8 : want;
	if (c->ClientFileContentsRequest(c, &req) != CHANNEL_RC_OK)
		return FALSE;
	if (WaitForSingleObject(cb->fcEvent, FILE_CHUNK_TIMEOUT_MS) != WAIT_OBJECT_0)
		return FALSE;
	EnterCriticalSection(&cb->lock);
	const BOOL ok = cb->fcOk && !cb->closed;
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

/* Ім'я файлу від сервера → відносний шлях усередині теки завантаження: частини між «\» чи «/», без
 * порожніх, «.» і «..». NULL — нічого не лишилось. */
static char* sanitize_server_name(const WCHAR* name)
{
	size_t n = 0;
	char* utf8 = ConvertWCharNToUtf8Alloc(name, _wcsnlen(name, 260), &n);
	if (!utf8)
		return NULL;
	char* out = malloc(n + 1);
	size_t o = 0;
	for (size_t i = 0; out && i < n;)
	{
		while (i < n && (utf8[i] == '\\' || utf8[i] == '/'))
			i++;
		const size_t start = i;
		while (i < n && utf8[i] != '\\' && utf8[i] != '/')
			i++;
		const size_t len = i - start;
		if (len == 0 || (len == 1 && utf8[start] == '.') || (len == 2 && utf8[start] == '.' && utf8[start + 1] == '.'))
			continue;
		if (o > 0)
			out[o++] = '/';
		memcpy(out + o, utf8 + start, len);
		o += len;
	}
	free(utf8);
	if (out)
		out[o] = 0;
	if (out && o == 0)
	{
		free(out);
		out = NULL;
	}
	return out;
}

/* mkdir -p для тек усередині теки завантаження (rel — відносний, уже очищений шлях). */
static BOOL make_dirs(const char* base, const char* rel, BOOL last)
{
	char* path = NULL;
	if (asprintf(&path, "%s/%s", base, rel) < 0)
		return FALSE;
	const size_t baseLen = strlen(base);
	for (char* p = path + baseLen + 1; *p; p++)
	{
		if (*p != '/')
			continue;
		*p = 0;
		if (mkdir(path, 0700) != 0 && errno != EEXIST)
		{
			free(path);
			return FALSE;
		}
		*p = '/';
	}
	const BOOL ok = !last || mkdir(path, 0700) == 0 || errno == EEXIST;
	free(path);
	return ok;
}

/* Шлях → «file:///…» з %XX для всього, крім безпечних символів. */
static BOOL append_uri(char** list, size_t* len, const char* path)
{
	static const char hex[] = "0123456789ABCDEF";
	const size_t n = strlen(path);
	char* uri = malloc(n * 3 + 10);
	if (!uri)
		return FALSE;
	size_t o = 0;
	memcpy(uri, "file://", 7);
	o = 7;
	for (size_t i = 0; i < n; i++)
	{
		const unsigned char ch = (unsigned char)path[i];
		if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || strchr("/-._~", ch))
			uri[o++] = (char)ch;
		else
		{
			uri[o++] = '%';
			uri[o++] = hex[ch >> 4];
			uri[o++] = hex[ch & 15];
		}
	}
	uri[o++] = '\r';
	uri[o++] = '\n';
	char* grown = realloc(*list, *len + o + 1);
	if (!grown)
	{
		free(uri);
		return FALSE;
	}
	memcpy(grown + *len, uri, o);
	*len += o;
	grown[*len] = 0;
	*list = grown;
	free(uri);
	return TRUE;
}

/* Тека для файлів сервера: ~/.cache/mhrd/clipboard (XDG_CACHE_HOME), лише для нас (0700). */
static char* cache_root(void)
{
	const char* xdg = getenv("XDG_CACHE_HOME");
	const char* home = getenv("HOME");
	char* root = NULL;
	if (xdg && xdg[0] == '/')
	{
		if (asprintf(&root, "%s/mhrd/clipboard", xdg) < 0)
			return NULL;
	}
	else if (home && home[0] == '/')
	{
		if (asprintf(&root, "%s/.cache/mhrd/clipboard", home) < 0)
			return NULL;
	}
	else
		return NULL;
	for (char* p = root + 1; *p; p++)
	{
		if (*p == '/')
		{
			*p = 0;
			mkdir(root, 0700);
			*p = '/';
		}
	}
	mkdir(root, 0700);
	struct stat st;
	if (lstat(root, &st) != 0 || !S_ISDIR(st.st_mode) || st.st_uid != getuid())
	{
		free(root);
		return NULL;
	}
	chmod(root, 0700);
	return root;
}

/* Теки сеансів, яких уже немає (впав процес, вимкнули ПК), — геть. Тека сеансу зветься «<pid>-<n>». */
static void remove_stale_dirs(const char* root)
{
	DIR* d = opendir(root);
	if (!d)
		return;
	struct dirent* e;
	while ((e = readdir(d)) != NULL)
	{
		char* end = NULL;
		const long pid = strtol(e->d_name, &end, 10);
		if (pid <= 0 || !end || *end != '-' || (kill((pid_t)pid, 0) == 0 || errno != ESRCH))
			continue;
		char* path = NULL;
		if (asprintf(&path, "%s/%s", root, e->d_name) >= 0)
			remove_tree(path);
		free(path);
	}
	closedir(d);
}

/* Завантаження файлів однієї копії на сервері (serial). */
static void fetch_files(MhrdClipboard* cb, UINT32 serial, UINT32 format, const char* dir, char** outUris)
{
	*outUris = NULL;
	UINT32 len = 0;
	BYTE* desc = request_server_data(cb, format, &len, FILE_LIST_TIMEOUT_MS);
	if (!desc || len < sizeof(UINT32))
	{
		free(desc);
		return;
	}
	if (mkdir(dir, 0700) != 0)
	{
		free(desc);
		return;
	}
	UINT32 count = rd32(desc);
	const size_t fit = (len - sizeof(UINT32)) / sizeof(FILEDESCRIPTORW);
	if (count > fit)
		count = (UINT32)fit;
	if (count > MAX_CLIP_FILES)
		count = MAX_CLIP_FILES;
	BYTE* chunk = malloc(FILE_FETCH_CHUNK);
	char* uris = NULL;
	size_t urisLen = 0;
	BOOL ok = chunk != NULL;
	for (UINT32 i = 0; ok && i < count; i++)
	{
		EnterCriticalSection(&cb->lock);
		const BOOL stale = cb->closed || cb->serial != serial;
		LeaveCriticalSection(&cb->lock);
		if (stale)
		{
			ok = FALSE;
			break;
		}
		FILEDESCRIPTORW d;
		memcpy(&d, desc + sizeof(UINT32) + (size_t)i * sizeof(FILEDESCRIPTORW), sizeof(d));
		char* rel = sanitize_server_name(d.cFileName);
		if (!rel)
			continue;
		const BOOL isDir = (d.dwFlags & FD_ATTRIBUTES) && (d.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY);
		char* path = NULL;
		if (!make_dirs(dir, rel, isDir) || asprintf(&path, "%s/%s", dir, rel) < 0)
		{
			free(rel);
			continue;
		}
		if (!isDir)
		{
			UINT64 size = ((UINT64)d.nFileSizeHigh << 32) | d.nFileSizeLow;
			UINT32 got = 0;
			if (!(d.dwFlags & FD_FILESIZE))
			{
				ok = request_file_contents(cb, i, TRUE, 0, 8, chunk, &got) && got == 8;
				if (ok)
					memcpy(&size, chunk, 8);
			}
			const int fd = ok ? open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0666) : -1;
			for (UINT64 pos = 0; fd >= 0 && ok && pos < size; pos += got)
			{
				const UINT64 left = size - pos;
				ok = request_file_contents(cb, i, FALSE, pos, left < FILE_FETCH_CHUNK ? (UINT32)left : FILE_FETCH_CHUNK,
				                           chunk, &got) &&
				     got > 0;
				for (UINT32 w = 0; ok && w < got;)
				{
					const ssize_t r = write(fd, chunk + w, got - w);
					if (r < 0 && errno == EINTR)
						continue;
					ok = r > 0;
					w += r > 0 ? (UINT32)r : 0;
				}
			}
			if (fd >= 0)
				close(fd);
			else
				ok = FALSE;
		}
		if (ok && !strchr(rel, '/')) /* у буфер — лише верхній рівень; теки несуть свій вміст */
			ok = append_uri(&uris, &urisLen, path);
		free(path);
		free(rel);
	}
	free(chunk);
	free(desc);
	if (ok && uris)
		*outUris = uris;
	else
		free(uris);
}

typedef struct
{
	MhrdClipboard* cb;
	UINT32 serial;
	UINT32 format;
	char* dir;
} FetchJob;

static void* fetch_thread(void* p)
{
	FetchJob* job = (FetchJob*)p;
	MhrdClipboard* cb = job->cb;
	char* uris = NULL;
	fetch_files(cb, job->serial, job->format, job->dir, &uris);
	EnterCriticalSection(&cb->lock);
	if (cb->fetchSerial == job->serial)
	{
		free(cb->fetchUris);
		cb->fetchUris = uris;
		cb->fetchDone = TRUE;
		SetEvent(cb->fetchEvent);
		uris = NULL;
	}
	LeaveCriticalSection(&cb->lock);
	free(uris);
	free(job->dir);
	free(job);
	release(cb);
	return NULL;
}

/* Почати завантаження файлів поточної копії на сервері (якщо є і ще не почали). */
static void start_fetch(MhrdClipboard* cb)
{
	char* root = NULL;
	EnterCriticalSection(&cb->lock);
	const BOOL need = !cb->closed && cb->serverFiles && cb->owned && cb->fetchSerial != cb->serial;
	LeaveCriticalSection(&cb->lock);
	if (!need || (root = cache_root()) == NULL)
		return;
	FetchJob* job = calloc(1, sizeof(FetchJob));
	if (!job)
	{
		free(root);
		return;
	}
	EnterCriticalSection(&cb->lock);
	if (cb->closed || cb->fetchSerial == cb->serial)
	{
		LeaveCriticalSection(&cb->lock);
		free(job);
		free(root);
		return;
	}
	/* Попередня копія вже не в буфері — її файли не потрібні. */
	remove_tree(cb->fetchDir);
	free(cb->fetchDir);
	cb->fetchDir = NULL;
	free(cb->fetchUris);
	cb->fetchUris = NULL;
	cb->fetchDone = FALSE;
	ResetEvent(cb->fetchEvent);
	cb->fetchSerial = cb->serial;
	job->cb = cb;
	job->serial = cb->serial;
	job->format = cb->serverFiles;
	if (asprintf(&job->dir, "%s/%ld-%u", root, (long)getpid(), (unsigned)cb->serial) < 0)
		job->dir = NULL;
	cb->fetchDir = job->dir ? strdup(job->dir) : NULL;
	cb->pending++;
	LeaveCriticalSection(&cb->lock);
	free(root);

	pthread_t t;
	if (!job->dir || pthread_create(&t, NULL, fetch_thread, job) != 0)
	{
		EnterCriticalSection(&cb->lock);
		cb->fetchDone = TRUE; /* вставляти нічого — не чекати */
		SetEvent(cb->fetchEvent);
		LeaveCriticalSection(&cb->lock);
		free(job->dir);
		free(job);
		release(cb);
		return;
	}
	pthread_detach(t);
}

/* Вставляють файли сервера: шляхи завантажених (чекаємо завершення до FILE_PASTE_WAIT_MS). */
static char* provide_files(MhrdClipboard* cb, BOOL gnome, size_t* size)
{
	start_fetch(cb);
	if (WaitForSingleObject(cb->fetchEvent, FILE_PASTE_WAIT_MS) != WAIT_OBJECT_0)
		return NULL;
	EnterCriticalSection(&cb->lock);
	char* out = NULL;
	if (cb->fetchDone && cb->fetchUris)
	{
		const size_t n = strlen(cb->fetchUris);
		out = SDL_malloc(n + 6);
		if (out && gnome)
		{
			/* «copy» і шляхи рядками, без кінцевого переведення рядка */
			size_t o = 0;
			memcpy(out, "copy\n", 5);
			o = 5;
			for (size_t i = 0; i < n; i++)
			{
				if (cb->fetchUris[i] != '\r')
					out[o++] = cb->fetchUris[i];
			}
			while (o > 0 && out[o - 1] == '\n')
				o--;
			out[o] = 0;
			*size = o;
		}
		else if (out)
		{
			memcpy(out, cb->fetchUris, n + 1);
			*size = n;
		}
	}
	LeaveCriticalSection(&cb->lock);
	return out;
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
		BYTE* data = request_server_data(cb, CF_UNICODETEXT, &len, RENDER_TIMEOUT_MS);
		if (data)
			cb->served = unicodetext_to_utf8(data, len, size);
		free(data);
	}
	else if (SDL_strcmp(mime, "image/png") == 0 || SDL_strcmp(mime, "image/bmp") == 0)
	{
		BYTE* data = request_server_data(cb, CF_DIB, &len, RENDER_TIMEOUT_MS);
		SDL_Surface* s = data ? dib_to_surface(data, len) : NULL;
		free(data);
		if (s)
		{
			cb->served = surface_to_file(s, SDL_strcmp(mime, "image/png") == 0, size);
			SDL_DestroySurface(s);
		}
	}
	else if (SDL_strcmp(mime, URI_MIME) == 0 || SDL_strcmp(mime, GNOME_FILES_MIME) == 0)
		cb->served = provide_files(cb, SDL_strcmp(mime, GNOME_FILES_MIME) == 0, size);
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
	const BOOL text = cb->serverText, dib = cb->serverDib, files = cb->serverFiles != 0;
	LeaveCriticalSection(&cb->lock);
	const char* mimes[SDL_arraysize(TEXT_MIMES) + SDL_arraysize(IMAGE_MIMES) + 2];
	size_t n = 0;
	if (files)
	{
		mimes[n++] = URI_MIME;
		mimes[n++] = GNOME_FILES_MIME;
	}
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
	UINT32 files = 0;
	for (UINT32 i = 0; i < list->numFormats; i++)
	{
		const char* name = list->formats[i].formatName;
		text |= list->formats[i].formatId == CF_UNICODETEXT;
		dib |= list->formats[i].formatId == CF_DIB;
		if (name && strcmp(name, "FileGroupDescriptorW") == 0)
			files = list->formats[i].formatId;
	}
	EnterCriticalSection(&cb->lock);
	cb->serverText = text;
	cb->serverDib = dib;
	cb->serverFiles = files;
	cb->serial++; /* нова копія на сервері — завантаження старої вже не потрібне */
	LeaveCriticalSection(&cb->lock);

	CLIPRDR_FORMAT_LIST_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_LIST_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	const UINT rc = c->ClientFormatListResponse(c, &resp);
	if (text || dib || files)
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
	/* Файли — потоками за запитом сервера, без шляхів нашого диска, і більші за 4 ГБ. */
	general.generalFlags =
	    CB_USE_LONG_FORMAT_NAMES | CB_STREAM_FILECLIP_ENABLED | CB_FILECLIP_NO_FILE_PATHS | CB_HUGE_FILE_SUPPORT_ENABLED;
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
	InitializeCriticalSection(&cb->reqLock);
	cb->openFd = -1;
	cb->responseEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	cb->fcEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	cb->fetchEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	if (!cb->responseEvent || !cb->fcEvent || !cb->fetchEvent || !SDL_AddEventWatch(on_sdl_event, cb))
	{
		destroy(cb);
		return NULL;
	}
	char* root = cache_root();
	if (root)
		remove_stale_dirs(root);
	free(root);
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
	LeaveCriticalSection(&cb->lock);
	SetEvent(cb->responseEvent); /* розбудити «Вставити», якщо чекає */
	SetEvent(cb->fcEvent);       /* і завантаження файлів */
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
	SetEvent(cb->fetchEvent);
	if (now)
		destroy(cb);
}
