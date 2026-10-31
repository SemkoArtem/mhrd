/* Власне вікно сеансу (SDL3): картинка — прямо на відеокарту, ввід — прямо в FreeRDP.
 * Головне вікно MHRD лишається списком ПК; кожен сеанс — окреме вікно окремого процесу.
 *
 * Потоки: вікно й цикл подій SDL — у головному потоці процесу, FreeRDP — у своєму.
 * FreeRDP повідомляє вікно через window_post_* (безпечно з будь-якого потоку).
 */
#pragma once

#include <stdint.h>
#include <winpr/wtypes.h>

/* Що вікно просить у сеансу. Усі виклики — з головного потоку. */
typedef struct
{
	void* ctx;
	/* Буфер кадру BGRX під замком (FreeRDP може замінити його при зміні роздільності). */
	void (*lock)(void* ctx);
	void (*unlock)(void* ctx);
	const uint8_t* (*buffer)(void* ctx, uint32_t* width, uint32_t* height, uint32_t* stride);
	void (*key)(void* ctx, uint16_t rdpScancode, BOOL down, BOOL repeat);
	void (*mouse)(void* ctx, uint16_t rdpFlags, uint16_t x, uint16_t y);
	void (*wheel)(void* ctx, int delta, BOOL horizontal, uint16_t x, uint16_t y);
	void (*resize)(void* ctx, uint32_t width, uint32_t height);
	void (*close)(void* ctx); /* користувач закрив вікно / «Відключитись» */
} WindowHost;

/* Налаштування з MSG_CONNECT. Рядки належать викликачу до window_run включно. */
typedef struct
{
	const char* title;          /* «Офіс — MHRD» */
	const char* fontPath;       /* TTF для плашки (необов'язково) */
	const char* labelPin;
	const char* labelUnpin;
	const char* labelMinimize;
	const char* labelExitFullscreen;
	const char* labelFullscreen;
	const char* labelKeyboard;
	const char* labelDisconnect;
	const char* menuFullscreen; /* пункти системного меню вікна (Windows) */
	const char* menuKeyboard;
	uint32_t colorSurface, colorBorder, colorText, colorAccent, colorError; /* 0xRRGGBB */
	BOOL startFullscreen;
	int keyboardCapture; /* 0 — лише на весь екран, 1 — завжди, 2 — ніколи */
	int resizeMode;      /* 0 — змінювати роздільність, 1 — масштабувати, 2 — без змін */
	BOOL swapMouseButtons;
} WindowConfig;

BOOL window_init(const WindowConfig* cfg, const WindowHost* host);

/* Головний потік: цикл подій до window_post_quit. */
void window_run(void);

void window_shutdown(void);

/* З потоку FreeRDP / каналу: */
void window_post_surface(void);                         /* новий буфер (перший кадр чи нова роздільність) */
void window_post_frame(int x, int y, int w, int h);     /* ділянка оновилась */
void window_post_focus(void);                           /* застосунок просить показати вікно */
void window_post_quit(void);                            /* сеанс завершився */
