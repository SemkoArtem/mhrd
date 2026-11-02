/* Спільна пам'ять для кадру: mhrd-session малює сюди (буфер GDI FreeRDP),
 * застосунок відкриває її за іменем і читає змінені ділянки. */
#pragma once

#include <stddef.h>
#include <winpr/wtypes.h>

typedef struct
{
	void* data;
	size_t size;
	char name[64];
	void* handle; /* Windows: HANDLE відображення; Android: дескриптор memfd; інші POSIX: не використовується */
} ShmBuffer;

/* Створює новий буфер з унікальним іменем. */
BOOL shm_create(ShmBuffer* b, size_t size);

void shm_free(ShmBuffer* b);
