#include "shm.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <unistd.h>
#endif
#ifdef __ANDROID__
#include <linux/memfd.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#endif

static unsigned g_counter;

#ifdef __ANDROID__
/* Дескриптор пам'яті кадру → застосунку: дейтаграма з міткою на його абстрактний сокет
 * (ім'я — у MHRD_FRAME_SOCKET, без початкового нуля), сам дескриптор — у SCM_RIGHTS. */
static BOOL send_fd(int fd, const char* tag)
{
	const char* name = getenv("MHRD_FRAME_SOCKET");
	if (!name || !*name)
		return FALSE;
	struct sockaddr_un addr = { 0 };
	addr.sun_family = AF_UNIX;
	const size_t n = strlen(name);
	if (n + 1 > sizeof(addr.sun_path))
		return FALSE;
	memcpy(addr.sun_path + 1, name, n); /* абстрактне ім'я: sun_path[0] == 0 */
	const int s = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (s < 0)
		return FALSE;
	struct iovec iov = { (void*)tag, strlen(tag) };
	union
	{
		struct cmsghdr align;
		char buf[CMSG_SPACE(sizeof(int))];
	} control;
	memset(&control, 0, sizeof(control));
	struct msghdr msg = { 0 };
	msg.msg_name = &addr;
	msg.msg_namelen = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + n);
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	msg.msg_control = control.buf;
	msg.msg_controllen = sizeof(control.buf);
	struct cmsghdr* c = CMSG_FIRSTHDR(&msg);
	c->cmsg_level = SOL_SOCKET;
	c->cmsg_type = SCM_RIGHTS;
	c->cmsg_len = CMSG_LEN(sizeof(int));
	memcpy(CMSG_DATA(c), &fd, sizeof(int));
	const BOOL ok = sendmsg(s, &msg, 0) >= 0;
	close(s);
	return ok;
}
#endif

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
#elif defined(__ANDROID__)
	/* POSIX shm на Android немає, а відкрити чужий memfd за шляхом (/proc/<pid>/fd) не дає SELinux.
	 * Тож анонімна пам'ять (memfd) передається застосунку самим дескриптором (SCM_RIGHTS) через
	 * його локальний сокет (MHRD_FRAME_SOCKET); «ім'я» — fd:<мітка>, за нею застосунок знаходить
	 * отриманий дескриптор (lib/sessions/frame_buffer.dart). */
	snprintf(b->name, sizeof(b->name), "fd:%ld-%u", (long)getpid(), ++g_counter);
	const int fd = (int)syscall(__NR_memfd_create, "mhrd-frame", MFD_CLOEXEC);
	if (fd < 0)
		return FALSE;
	if (ftruncate(fd, (off_t)size) != 0)
	{
		close(fd);
		return FALSE;
	}
	b->data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	const BOOL sent = b->data != MAP_FAILED && send_fd(fd, b->name + 3);
	close(fd); /* відображення живе й без дескриптора */
	if (!sent)
	{
		if (b->data != MAP_FAILED)
			munmap(b->data, size);
		b->data = NULL;
		return FALSE;
	}
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
#elif defined(__ANDROID__)
	munmap(b->data, b->size);
#else
	munmap(b->data, b->size);
	shm_unlink(b->name);
#endif
	memset(b, 0, sizeof(*b));
}
