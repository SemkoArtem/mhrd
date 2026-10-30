#include "shm.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

static unsigned g_counter;

BOOL shm_create(ShmBuffer* b, size_t size)
{
	memset(b, 0, sizeof(*b));
	b->size = size;
#ifdef _WIN32
	/* Local\ — лише в сеансі входу цього користувача. */
	snprintf(b->name, sizeof(b->name), "Local\\mhrd-%lu-%u", GetCurrentProcessId(), ++g_counter);
	HANDLE h = CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, (DWORD)((unsigned long long)size >> 32),
	                              (DWORD)size, b->name);
	if (!h)
		return FALSE;
	b->data = MapViewOfFile(h, FILE_MAP_ALL_ACCESS, 0, 0, size);
	if (!b->data)
	{
		CloseHandle(h);
		return FALSE;
	}
	b->handle = h;
#else
	snprintf(b->name, sizeof(b->name), "/mhrd-%ld-%u", (long)getpid(), ++g_counter);
	int fd = shm_open(b->name, O_CREAT | O_EXCL | O_RDWR, 0600);
	if (fd < 0)
		return FALSE;
	if (ftruncate(fd, (off_t)size) != 0)
	{
		close(fd);
		shm_unlink(b->name);
		return FALSE;
	}
	b->data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	close(fd);
	if (b->data == MAP_FAILED)
	{
		b->data = NULL;
		shm_unlink(b->name);
		return FALSE;
	}
#endif
	return TRUE;
}

void shm_free(ShmBuffer* b)
{
	if (!b->data)
		return;
#ifdef _WIN32
	UnmapViewOfFile(b->data);
	CloseHandle((HANDLE)b->handle);
#else
	munmap(b->data, b->size);
	shm_unlink(b->name);
#endif
	memset(b, 0, sizeof(*b));
}
