#include "proto.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <winpr/synch.h>
#include <winpr/thread.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#else
#include <errno.h>
#include <unistd.h>
#endif

/* Найбільше повідомлення від застосунку: JSON підключення — кілька КБ. */
#define PROTO_MAX_LEN (1u << 20)

static CRITICAL_SECTION g_queueLock;
static CRITICAL_SECTION g_writeLock;
static HANDLE g_event;
static ProtoMsg* g_head;
static ProtoMsg* g_tail;
static volatile BOOL g_closed;

#ifdef _WIN32
static BOOL read_exact(void* buf, size_t len)
{
	return len == 0 || fread(buf, 1, len, stdin) == len;
}
#else
/* Напряму read(), не fread: потік stdio, заблокований у fread, тримає замок stdin, і exit()
 * у glibc (скидання всіх потоків stdio) чекав би на нього вічно — процес не завершувався б,
 * поки застосунок не закриє канал. */
static BOOL read_exact(void* buf, size_t len)
{
	uint8_t* p = buf;
	while (len > 0)
	{
		const ssize_t n = read(STDIN_FILENO, p, len);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			return FALSE;
		p += n;
		len -= (size_t)n;
	}
	return TRUE;
}
#endif

static DWORD WINAPI reader_thread(LPVOID arg)
{
	(void)arg;
	for (;;)
	{
		uint8_t hdr[5];
		if (!read_exact(hdr, sizeof(hdr)))
			break;
		const uint32_t total = hdr[0] | (hdr[1] << 8) | (hdr[2] << 16) | ((uint32_t)hdr[3] << 24);
		if (total == 0 || total > PROTO_MAX_LEN)
			break; /* зламаний потік — далі читати не можна */
		ProtoMsg* m = calloc(1, sizeof(ProtoMsg) + total - 1);
		if (!m)
			break;
		m->type = hdr[4];
		m->len = total - 1;
		if (!read_exact(m->data, m->len))
		{
			free(m);
			break;
		}
		EnterCriticalSection(&g_queueLock);
		if (g_tail)
			g_tail->next = m;
		else
			g_head = m;
		g_tail = m;
		SetEvent(g_event);
		LeaveCriticalSection(&g_queueLock);
	}
	g_closed = TRUE;
	SetEvent(g_event);
	return 0;
}

BOOL proto_init(void)
{
#ifdef _WIN32
	_setmode(_fileno(stdin), _O_BINARY);
	_setmode(_fileno(stdout), _O_BINARY);
#endif
	InitializeCriticalSection(&g_queueLock);
	InitializeCriticalSection(&g_writeLock);
	g_event = CreateEvent(NULL, TRUE, FALSE, NULL);
	if (!g_event)
		return FALSE;
	HANDLE t = CreateThread(NULL, 0, reader_thread, NULL, 0, NULL);
	if (!t)
		return FALSE;
	CloseHandle(t);
	return TRUE;
}

HANDLE proto_event(void)
{
	return g_event;
}

BOOL proto_closed(void)
{
	return g_closed;
}

ProtoMsg* proto_pop(void)
{
	EnterCriticalSection(&g_queueLock);
	ProtoMsg* m = g_head;
	if (m)
	{
		g_head = m->next;
		if (!g_head)
			g_tail = NULL;
		m->next = NULL;
	}
	if (!g_head && !g_closed)
		ResetEvent(g_event);
	LeaveCriticalSection(&g_queueLock);
	return m;
}

ProtoMsg* proto_wait(DWORD timeoutMs)
{
	for (;;)
	{
		ProtoMsg* m = proto_pop();
		if (m || g_closed)
			return m;
		if (WaitForSingleObject(g_event, timeoutMs) != WAIT_OBJECT_0)
			return NULL;
	}
}

void proto_send(uint8_t type, const void* data, uint32_t len)
{
	uint8_t hdr[5];
	put_u32(hdr, len + 1);
	hdr[4] = type;
	EnterCriticalSection(&g_writeLock);
	fwrite(hdr, 1, sizeof(hdr), stdout);
	if (len)
		fwrite(data, 1, len, stdout);
	fflush(stdout);
	LeaveCriticalSection(&g_writeLock);
}
