/* Буфер обміну сеансу (канал cliprdr): текст і зображення в обидва боки.
 * mhrd-session — звичайна програма в сеансі користувача, тож працює з системним буфером
 * напряму. Дані передаються лише тоді, коли на іншому боці натиснули «Вставити» (SPEC). */
#pragma once

#include <freerdp/client/cliprdr.h>

typedef struct MhrdClipboard MhrdClipboard;

/* Запускає потік із прихованим вікном, що стежить за системним буфером. */
MhrdClipboard* clipboard_new(void);

/* Канал cliprdr підключився / відключився. */
void clipboard_attach(MhrdClipboard* cb, CliprdrClientContext* cliprdr);
void clipboard_detach(MhrdClipboard* cb);

void clipboard_free(MhrdClipboard* cb);
