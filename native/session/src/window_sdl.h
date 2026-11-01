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
	/* Плашку перетягнули або змінили довжину (див. barEdge/barPos/barLength). */
	void (*barMoved)(void* ctx, int edge, int pos, int length);
	/* Дотик на віддалений ПК (FREERDP_TOUCH_*, координати віддаленого екрана). FALSE — сервер
	 * дотику не підтримує, тоді вікно імітує мишу саме. */
	BOOL (*touch)(void* ctx, uint32_t flags, int finger, int x, int y);
	/* Символ без клавіші (сенсорна клавіатура, автозаповнення паролів, емодзі): одиниця UTF-16. */
	void (*unicode)(void* ctx, uint16_t code);
	/* Кнопка «Екранна клавіатура»: osk.exe запускає головна програма (сеансу запускати процеси не можна). */
	void (*openKeyboard)(void* ctx);
} WindowHost;

/* Налаштування з MSG_CONNECT. Рядки належать викликачу до window_run включно. */
typedef struct
{
	const char* title;          /* «Офіс — MHRD» */
	const char* barTitle;       /* підпис на плашці: «Офіс · 10.0.0.5» або лише адреса */
	const char* fontPath;       /* TTF для назви й підказок плашки (необов'язково) */
	/* Підказки кнопок плашки (з'являються через пів секунди наведення) */
	const char* labelPin;
	const char* labelUnpin;
	const char* labelMinimize;
	const char* labelExitFullscreen;
	const char* labelFullscreen;
	const char* labelKeyboard;
	const char* labelDisconnect;
	/* Піктограми кнопок: шрифт піктограм і коди символів у ньому (0 — немає, тоді текст) */
	const char* iconFontPath;
	uint32_t iconPin, iconUnpin, iconKeyboard, iconMinimize, iconFullscreen, iconExitFullscreen, iconDisconnect,
	    iconCtrlAltDel;
	const char* labelCtrlAltDel;
	const char* labelReconnectAttempt; /* «спроба {n} з {max}» */
	const char* labelCancel;           /* кнопка під «Перепідключення…» */
	const char* labelLatency;          /* «{n} мс» */
	int reconnectMax;
	const char* menuFullscreen; /* пункти системного меню вікна (Windows) */
	const char* menuKeyboard;
	const char* labelReconnecting; /* поверх картинки, поки зв'язок відновлюється */
	uint32_t colorSurface, colorBorder, colorText, colorAccent, colorError, colorOk, colorWarn; /* 0xRRGGBB */
	BOOL startFullscreen;
	int keyboardCapture; /* 0 — лише на весь екран, 1 — завжди, 2 — ніколи */
	int resizeMode;      /* 0 — змінювати роздільність, 1 — масштабувати, 2 — без змін */
	BOOL swapMouseButtons;
	BOOL logicalResolution; /* економія трафіку: роздільність у логічних пікселях (вікно збільшує картинку) */
	BOOL keepAwake;         /* не давати Windows гасити екран і засинати, поки відкрите вікно сеансу */
	BOOL allMonitors;       /* сеанс на всі монітори (MonitorDefArray), вікно — на весь віртуальний екран */
	/* Для allMonitors (заповнює main.c, коли моніторів справді кілька): віртуальний екран і основний
	 * монітор у пікселях Windows. */
	int virtX, virtY, virtW, virtH, primX, primY, primW, primH;
	/* Плашка: край вікна (0 верх, 1 низ, 2 ліво, 3 право), центр уздовж краю (0..10000),
	 * довжина в одиницях інтерфейсу (0 — типова); радіус заокруглення, як у темі MHRD. */
	int barEdge, barPos, barLength, radius;
	const char* thumbnailPath; /* куди зберігати мініатюру екрана для плитки ПК (BMP); NULL — не треба */
} WindowConfig;

BOOL window_init(const WindowConfig* cfg, const WindowHost* host);

/* Головний потік: цикл подій до window_post_quit. */
void window_run(void);

void window_shutdown(void);

/* З потоку FreeRDP / каналу: */
void window_post_surface(void);                         /* новий буфер (перший кадр чи нова роздільність) */
void window_post_frame(int x, int y, int w, int h);     /* ділянка оновилась */
void window_post_focus(void);                           /* застосунок просить показати вікно */
void window_post_reconnecting(int attempt);             /* спроба перепідключення N; 0 — зв'язок відновився */
void window_post_latency(int ms);                       /* затримка до ПК (−1 — не відповів) */
void window_post_quit(void);                            /* сеанс завершився */
