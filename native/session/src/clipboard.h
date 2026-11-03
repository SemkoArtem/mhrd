/* Буфер обміну сеансу (канал cliprdr): текст і зображення в обидва боки (Windows — clipboard_win.c,
 * Linux — clipboard_sdl.c).
 * mhrd-session — звичайна програма в сеансі користувача, тож працює з системним буфером
 * напряму. Дані передаються лише тоді, коли на іншому боці натиснули «Вставити» (SPEC). */
#pragma once

#include <freerdp/client/cliprdr.h>

typedef struct MhrdClipboard MhrdClipboard;

/* Починає стежити за системним буфером (Windows — потік із прихованим вікном, Linux — події SDL). */
MhrdClipboard* clipboard_new(void);

/* Канал cliprdr підключився / відключився. */
void clipboard_attach(MhrdClipboard* cb, CliprdrClientContext* cliprdr);
void clipboard_detach(MhrdClipboard* cb);

void clipboard_free(MhrdClipboard* cb);

/* Android (clipboard_proto.c): текст із буфера телефона, який надіслав застосунок (MSG_CLIP_TEXT). */
void clipboard_set_text(MhrdClipboard* cb, const char* utf8, size_t len);
