/* Заглушка буфера обміну для Linux і macOS: канал не підключається, доки немає реалізації. */
#include "clipboard.h"

#include <stddef.h>

MhrdClipboard* clipboard_new(void)
{
	return NULL;
}

void clipboard_attach(MhrdClipboard* cb, CliprdrClientContext* cliprdr)
{
	(void)cb;
	(void)cliprdr;
}

void clipboard_detach(MhrdClipboard* cb)
{
	(void)cb;
}

void clipboard_free(MhrdClipboard* cb)
{
	(void)cb;
}
