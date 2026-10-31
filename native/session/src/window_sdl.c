/* Власне вікно сеансу на SDL3 — див. window_sdl.h. */
#include "window_sdl.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <freerdp/input.h>

#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#endif

#define RESIZE_DELAY_MS 300 /* SPEC: нова роздільність — через 300 мс після останньої зміни розміру */
#define BAR_W 520            /* типова довжина плашки (одиниці інтерфейсу; × масштаб ОС = пікселі) */
#define BAR_H 40             /* товщина плашки */
#define BAR_MARGIN 6         /* відступ плашки від краю вікна */
#define BAR_PAD 6            /* поле на кінцях плашки — за нього тягнуть, щоб змінити довжину */
#define GRIP_W 14            /* «ручка» на початку плашки — за неї (і за назву ПК) перетягують */
#define ICON_PX 20           /* розмір піктограм кнопок плашки */
#define TOOLTIP_DELAY_MS 500 /* підказка кнопки — через пів секунди наведення */
#define BAR_HIDE_DELAY_MS 3500 /* плашка ховається через 3,5 с після того, як мишу прибрали */
#define HANDLE_W 120
#define HANDLE_H 8
#define RDP_EXT 0x100 /* скан-код із префіксом E0 */

enum
{
	EV_SURFACE,
	EV_FRAME,
	EV_FOCUS,
	EV_QUIT,
	EV_MENU_FULLSCREEN, /* пункти системного меню вікна */
	EV_MENU_KEYBOARD,
	EV_RECONNECTING, /* стан — у W.reconnecting */
	EV_COUNT
};

/* Кнопки плашки (і в повному екрані, і у вікні) */
enum
{
	BTN_PIN,
	BTN_KEYBOARD,
	BTN_MINIMIZE, /* лише в повному екрані: у вікні є кнопка в заголовку */
	BTN_FULLSCREEN,
	BTN_DISCONNECT,
	BTN_COUNT,
	BTN_NONE = -1
};

/* Край вікна, до якого притулена плашка (номери — як у barEdge і EVT_BAR). */
enum
{
	EDGE_TOP,
	EDGE_BOTTOM,
	EDGE_LEFT,
	EDGE_RIGHT
};

/* Що робить миша з плашкою: нічого, перетягує, змінює довжину. */
enum
{
	DRAG_NONE,
	DRAG_MOVE,
	DRAG_RESIZE
};

/* Подія миші для плашки. */
enum
{
	MOUSE_MOVE,
	MOUSE_DOWN,
	MOUSE_UP
};

static struct
{
	WindowConfig cfg;
	WindowHost host;
	Uint32 evBase;

	SDL_Window* window;
	SDL_Renderer* renderer;
	SDL_Texture* texture;
	uint32_t texW, texH;

	/* Змінені ділянки від FreeRDP — об'єднуються до одного прямокутника між кадрами вікна. */
	SDL_Mutex* dirtyLock;
	int dx0, dy0, dx1, dy1;
	SDL_AtomicInt framePending;

	BOOL fullscreen;
	BOOL barPinned, barHover;
	Uint64 barHideAt; /* коли сховати плашку (0 — не ховати) */
	int hoverButton;
	SDL_FRect buttons[BTN_COUNT];
	SDL_FRect barRect, handleRect, gripRect, titleRect;
	SDL_FRect hotRect; /* плашка разом зі смужкою між нею й краєм вікна — тут миша «на плашці» */

	/* Де плашка: край, центр уздовж краю (0..1), довжина в одиницях інтерфейсу. */
	int barEdge;
	float barPos, barLen;
	int drag;              /* DRAG_* */
	float dragFrom, dragLen, dragSign; /* зміна довжини: звідки тягнуть, довжина на старті, кінець */
	SDL_Cursor* cursors[SDL_SYSTEM_CURSOR_COUNT];
	SDL_SystemCursor cursorShown;

	Uint64 resizeAt; /* коли просити нову роздільність (0 — не треба) */
	uint32_t lastRequestedW, lastRequestedH;
	BOOL pressed[SDL_SCANCODE_COUNT];
	float wheelRest;

	TTF_Font* font;
	SDL_Texture* labels[BTN_COUNT + 1]; /* + назва ПК; BTN_PIN — «закріпити», окремо «відкріпити» */
	SDL_Texture* unpinLabel;
	SDL_Texture* fullscreenLabel; /* BTN_FULLSCREEN у вікні; labels[BTN_FULLSCREEN] — «у вікно» */

	/* Піктограми (білі; колір задається при малюванні). Як і з підписами: окремо «відкріпити»
	 * і «на весь екран» (icons[BTN_FULLSCREEN] — «у вікно»). */
	TTF_Font* iconFont;
	SDL_Texture* icons[BTN_COUNT];
	SDL_Texture* unpinIcon;
	SDL_Texture* fullscreenIcon;

	Uint64 hoverSince; /* коли мишу навели на поточну кнопку */
	BOOL tooltipShown;

	SDL_AtomicInt reconnecting; /* 1 — зв'язок обірвався, FreeRDP відновлює (пише потік FreeRDP) */
	SDL_Texture* reconnectLabel;
} W;

/* ── Клавіші: SDL_Scancode (= USB HID usage) → скан-код RDP (PC/AT, набір 1) ── */

static uint16_t g_scan[SDL_SCANCODE_COUNT];

static void init_scancodes(void)
{
	static const struct
	{
		SDL_Scancode sdl;
		uint16_t rdp;
	} map[] = {
		{ SDL_SCANCODE_A, 0x1E }, { SDL_SCANCODE_B, 0x30 }, { SDL_SCANCODE_C, 0x2E }, { SDL_SCANCODE_D, 0x20 },
		{ SDL_SCANCODE_E, 0x12 }, { SDL_SCANCODE_F, 0x21 }, { SDL_SCANCODE_G, 0x22 }, { SDL_SCANCODE_H, 0x23 },
		{ SDL_SCANCODE_I, 0x17 }, { SDL_SCANCODE_J, 0x24 }, { SDL_SCANCODE_K, 0x25 }, { SDL_SCANCODE_L, 0x26 },
		{ SDL_SCANCODE_M, 0x32 }, { SDL_SCANCODE_N, 0x31 }, { SDL_SCANCODE_O, 0x18 }, { SDL_SCANCODE_P, 0x19 },
		{ SDL_SCANCODE_Q, 0x10 }, { SDL_SCANCODE_R, 0x13 }, { SDL_SCANCODE_S, 0x1F }, { SDL_SCANCODE_T, 0x14 },
		{ SDL_SCANCODE_U, 0x16 }, { SDL_SCANCODE_V, 0x2F }, { SDL_SCANCODE_W, 0x11 }, { SDL_SCANCODE_X, 0x2D },
		{ SDL_SCANCODE_Y, 0x15 }, { SDL_SCANCODE_Z, 0x2C },
		{ SDL_SCANCODE_1, 0x02 }, { SDL_SCANCODE_2, 0x03 }, { SDL_SCANCODE_3, 0x04 }, { SDL_SCANCODE_4, 0x05 },
		{ SDL_SCANCODE_5, 0x06 }, { SDL_SCANCODE_6, 0x07 }, { SDL_SCANCODE_7, 0x08 }, { SDL_SCANCODE_8, 0x09 },
		{ SDL_SCANCODE_9, 0x0A }, { SDL_SCANCODE_0, 0x0B },
		{ SDL_SCANCODE_RETURN, 0x1C }, { SDL_SCANCODE_ESCAPE, 0x01 }, { SDL_SCANCODE_BACKSPACE, 0x0E },
		{ SDL_SCANCODE_TAB, 0x0F }, { SDL_SCANCODE_SPACE, 0x39 }, { SDL_SCANCODE_MINUS, 0x0C },
		{ SDL_SCANCODE_EQUALS, 0x0D }, { SDL_SCANCODE_LEFTBRACKET, 0x1A }, { SDL_SCANCODE_RIGHTBRACKET, 0x1B },
		{ SDL_SCANCODE_BACKSLASH, 0x2B }, { SDL_SCANCODE_NONUSHASH, 0x2B }, { SDL_SCANCODE_SEMICOLON, 0x27 },
		{ SDL_SCANCODE_APOSTROPHE, 0x28 }, { SDL_SCANCODE_GRAVE, 0x29 }, { SDL_SCANCODE_COMMA, 0x33 },
		{ SDL_SCANCODE_PERIOD, 0x34 }, { SDL_SCANCODE_SLASH, 0x35 }, { SDL_SCANCODE_CAPSLOCK, 0x3A },
		{ SDL_SCANCODE_F1, 0x3B }, { SDL_SCANCODE_F2, 0x3C }, { SDL_SCANCODE_F3, 0x3D }, { SDL_SCANCODE_F4, 0x3E },
		{ SDL_SCANCODE_F5, 0x3F }, { SDL_SCANCODE_F6, 0x40 }, { SDL_SCANCODE_F7, 0x41 }, { SDL_SCANCODE_F8, 0x42 },
		{ SDL_SCANCODE_F9, 0x43 }, { SDL_SCANCODE_F10, 0x44 }, { SDL_SCANCODE_F11, 0x57 }, { SDL_SCANCODE_F12, 0x58 },
		{ SDL_SCANCODE_PRINTSCREEN, RDP_EXT | 0x37 }, { SDL_SCANCODE_SCROLLLOCK, 0x46 },
		{ SDL_SCANCODE_INSERT, RDP_EXT | 0x52 }, { SDL_SCANCODE_HOME, RDP_EXT | 0x47 },
		{ SDL_SCANCODE_PAGEUP, RDP_EXT | 0x49 }, { SDL_SCANCODE_DELETE, RDP_EXT | 0x53 },
		{ SDL_SCANCODE_END, RDP_EXT | 0x4F }, { SDL_SCANCODE_PAGEDOWN, RDP_EXT | 0x51 },
		{ SDL_SCANCODE_RIGHT, RDP_EXT | 0x4D }, { SDL_SCANCODE_LEFT, RDP_EXT | 0x4B },
		{ SDL_SCANCODE_DOWN, RDP_EXT | 0x50 }, { SDL_SCANCODE_UP, RDP_EXT | 0x48 },
		{ SDL_SCANCODE_NUMLOCKCLEAR, 0x45 }, { SDL_SCANCODE_KP_DIVIDE, RDP_EXT | 0x35 },
		{ SDL_SCANCODE_KP_MULTIPLY, 0x37 }, { SDL_SCANCODE_KP_MINUS, 0x4A }, { SDL_SCANCODE_KP_PLUS, 0x4E },
		{ SDL_SCANCODE_KP_ENTER, RDP_EXT | 0x1C }, { SDL_SCANCODE_KP_1, 0x4F }, { SDL_SCANCODE_KP_2, 0x50 },
		{ SDL_SCANCODE_KP_3, 0x51 }, { SDL_SCANCODE_KP_4, 0x4B }, { SDL_SCANCODE_KP_5, 0x4C },
		{ SDL_SCANCODE_KP_6, 0x4D }, { SDL_SCANCODE_KP_7, 0x47 }, { SDL_SCANCODE_KP_8, 0x48 },
		{ SDL_SCANCODE_KP_9, 0x49 }, { SDL_SCANCODE_KP_0, 0x52 }, { SDL_SCANCODE_KP_PERIOD, 0x53 },
		{ SDL_SCANCODE_KP_EQUALS, 0x59 }, { SDL_SCANCODE_NONUSBACKSLASH, 0x56 },
		{ SDL_SCANCODE_APPLICATION, RDP_EXT | 0x5D }, { SDL_SCANCODE_INTERNATIONAL1, 0x73 },
		{ SDL_SCANCODE_INTERNATIONAL2, 0x70 }, { SDL_SCANCODE_INTERNATIONAL3, 0x7D },
		{ SDL_SCANCODE_INTERNATIONAL4, 0x79 }, { SDL_SCANCODE_INTERNATIONAL5, 0x7B },
		{ SDL_SCANCODE_F13, 0x64 }, { SDL_SCANCODE_F14, 0x65 }, { SDL_SCANCODE_F15, 0x66 },
		{ SDL_SCANCODE_F16, 0x67 }, { SDL_SCANCODE_F17, 0x68 }, { SDL_SCANCODE_F18, 0x69 },
		{ SDL_SCANCODE_F19, 0x6A }, { SDL_SCANCODE_F20, 0x6B }, { SDL_SCANCODE_F21, 0x6C },
		{ SDL_SCANCODE_F22, 0x6D }, { SDL_SCANCODE_F23, 0x6E }, { SDL_SCANCODE_F24, 0x76 },
		{ SDL_SCANCODE_LCTRL, 0x1D }, { SDL_SCANCODE_LSHIFT, 0x2A }, { SDL_SCANCODE_LALT, 0x38 },
		{ SDL_SCANCODE_LGUI, RDP_EXT | 0x5B }, { SDL_SCANCODE_RCTRL, RDP_EXT | 0x1D },
		{ SDL_SCANCODE_RSHIFT, 0x36 }, { SDL_SCANCODE_RALT, RDP_EXT | 0x38 }, { SDL_SCANCODE_RGUI, RDP_EXT | 0x5C },
	};
	for (size_t i = 0; i < SDL_arraysize(map); i++)
		g_scan[map[i].sdl] = map[i].rdp;
}

/* ── Події від потоку FreeRDP ─────────────────────────────────── */

static void push(int ev)
{
	SDL_Event e;
	SDL_zero(e);
	e.type = W.evBase + (Uint32)ev;
	SDL_PushEvent(&e);
}

void window_post_surface(void)
{
	push(EV_SURFACE);
}

void window_post_frame(int x, int y, int w, int h)
{
	SDL_LockMutex(W.dirtyLock);
	if (W.dx1 <= W.dx0)
	{
		W.dx0 = x;
		W.dy0 = y;
		W.dx1 = x + w;
		W.dy1 = y + h;
	}
	else
	{
		W.dx0 = SDL_min(W.dx0, x);
		W.dy0 = SDL_min(W.dy0, y);
		W.dx1 = SDL_max(W.dx1, x + w);
		W.dy1 = SDL_max(W.dy1, y + h);
	}
	SDL_UnlockMutex(W.dirtyLock);
	/* Одна подія на кадр вікна: решта ділянок просто доєднується до прямокутника. */
	if (SDL_CompareAndSwapAtomicInt(&W.framePending, 0, 1))
		push(EV_FRAME);
}

void window_post_focus(void)
{
	push(EV_FOCUS);
}

void window_post_quit(void)
{
	push(EV_QUIT);
}

void window_post_reconnecting(BOOL on)
{
	SDL_SetAtomicInt(&W.reconnecting, on ? 1 : 0);
	push(EV_RECONNECTING);
}

/* ── Геометрія ────────────────────────────────────────────────── */

/* Масштаб інтерфейсу вікна (плашка, шрифт): 1.5 при масштабі ОС 150 %. */
static float ui_scale(void)
{
	const float s = W.window ? SDL_GetWindowDisplayScale(W.window) : 1.0f;
	return s > 0.0f ? s : 1.0f;
}

/* Пікселів вікна на одиницю координат подій миші. */
static float pixel_ratio(void)
{
	int w = 0, h = 0, pw = 0, ph = 0;
	SDL_GetWindowSize(W.window, &w, &h);
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	return w > 0 ? (float)pw / (float)w : 1.0f;
}

/* Де на вікні малюється віддалений екран. */
static SDL_FRect image_rect(void)
{
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	SDL_FRect r = { 0, 0, (float)W.texW, (float)W.texH };
	if (!W.texW || !W.texH || pw <= 0 || ph <= 0)
		return r;
	float scale = 1.0f;
	if (W.cfg.resizeMode != 2 || W.fullscreen) /* «без змін» — 1:1, решта — вписати */
		scale = SDL_min((float)pw / (float)W.texW, (float)ph / (float)W.texH);
	r.w = floorf((float)W.texW * scale + 0.5f);
	r.h = floorf((float)W.texH * scale + 0.5f);
	r.x = floorf(((float)pw - r.w) / 2.0f);
	r.y = floorf(((float)ph - r.h) / 2.0f);
	if (W.cfg.resizeMode == 2 && !W.fullscreen)
		r.x = r.y = 0;
	return r;
}

/* Точка вікна (координати подій) → піксель віддаленого екрана. */
static BOOL to_remote(float x, float y, uint16_t* rx, uint16_t* ry)
{
	const float k = pixel_ratio();
	const SDL_FRect r = image_rect();
	if (r.w <= 0 || r.h <= 0)
		return FALSE;
	float fx = (x * k - r.x) * (float)W.texW / r.w;
	float fy = (y * k - r.y) * (float)W.texH / r.h;
	fx = SDL_clamp(fx, 0.0f, (float)W.texW - 1.0f);
	fy = SDL_clamp(fy, 0.0f, (float)W.texH - 1.0f);
	*rx = (uint16_t)fx;
	*ry = (uint16_t)fy;
	return TRUE;
}

/* ── Рендер ───────────────────────────────────────────────────── */

static void set_color(uint32_t rgb, Uint8 a)
{
	SDL_SetRenderDrawColor(W.renderer, (Uint8)(rgb >> 16), (Uint8)(rgb >> 8), (Uint8)rgb, a);
}

/* Контур прямокутника із заокругленими кутами: 4 дуги по ROUND_STEPS відрізків. */
#define ROUND_STEPS 8
#define ROUND_POINTS (4 * (ROUND_STEPS + 1))

static float round_outline(const SDL_FRect* r, float radius, SDL_FPoint* out)
{
	radius = SDL_min(radius, SDL_min(r->w, r->h) / 2.0f);
	const float cx[4] = { r->x + radius, r->x + r->w - radius, r->x + r->w - radius, r->x + radius };
	const float cy[4] = { r->y + radius, r->y + radius, r->y + r->h - radius, r->y + r->h - radius };
	int n = 0;
	for (int c = 0; c < 4; c++)
	{
		const float a0 = SDL_PI_F * (1.0f + 0.5f * (float)c); /* лівий верхній кут починається з 180° */
		for (int i = 0; i <= ROUND_STEPS; i++)
		{
			const float a = a0 + 0.5f * SDL_PI_F * (float)i / (float)ROUND_STEPS;
			out[n++] = (SDL_FPoint){ cx[c] + radius * SDL_cosf(a), cy[c] + radius * SDL_sinf(a) };
		}
	}
	return radius;
}

static void fill_round(const SDL_FRect* r, float radius, uint32_t rgb, Uint8 alpha)
{
	SDL_FPoint p[ROUND_POINTS];
	round_outline(r, radius, p);
	SDL_Vertex v[ROUND_POINTS + 1];
	int idx[ROUND_POINTS * 3];
	const SDL_FColor c = { (float)((rgb >> 16) & 0xFF) / 255.0f, (float)((rgb >> 8) & 0xFF) / 255.0f,
		                   (float)(rgb & 0xFF) / 255.0f, (float)alpha / 255.0f };
	v[0] = (SDL_Vertex){ { r->x + r->w / 2.0f, r->y + r->h / 2.0f }, c, { 0, 0 } };
	for (int i = 0; i < ROUND_POINTS; i++)
	{
		v[i + 1] = (SDL_Vertex){ p[i], c, { 0, 0 } };
		idx[i * 3] = 0;
		idx[i * 3 + 1] = i + 1;
		idx[i * 3 + 2] = (i + 1) % ROUND_POINTS + 1;
	}
	SDL_SetRenderDrawBlendMode(W.renderer, SDL_BLENDMODE_BLEND);
	SDL_RenderGeometry(W.renderer, NULL, v, ROUND_POINTS + 1, idx, ROUND_POINTS * 3);
}

static void stroke_round(const SDL_FRect* r, float radius, uint32_t rgb)
{
	/* Лінія — по центру крайнього ряду пікселів, щоб не розмивалась. */
	const SDL_FRect in = { r->x + 0.5f, r->y + 0.5f, r->w - 1.0f, r->h - 1.0f };
	SDL_FPoint p[ROUND_POINTS + 1];
	round_outline(&in, radius, p);
	p[ROUND_POINTS] = p[0];
	set_color(rgb, 255);
	SDL_RenderLines(W.renderer, p, ROUND_POINTS + 1);
}

/* Панель у стилі MHRD: заливка, рамка, кути як у темі. */
static void draw_panel(const SDL_FRect* r, float radius)
{
	fill_round(r, radius, W.cfg.colorSurface, 255);
	stroke_round(r, radius, W.cfg.colorBorder);
}

static SDL_Texture* make_label(const char* text)
{
	if (!W.font || !text || !text[0])
		return NULL;
	const SDL_Color c = { (Uint8)(W.cfg.colorText >> 16), (Uint8)(W.cfg.colorText >> 8), (Uint8)W.cfg.colorText, 255 };
	SDL_Surface* s = TTF_RenderText_Blended(W.font, text, 0, c);
	if (!s)
		return NULL;
	SDL_Texture* t = SDL_CreateTextureFromSurface(W.renderer, s);
	SDL_DestroySurface(s);
	return t;
}

static SDL_Texture* make_icon(uint32_t codepoint)
{
	if (!W.iconFont || !codepoint)
		return NULL;
	const SDL_Color white = { 255, 255, 255, 255 };
	SDL_Surface* s = TTF_RenderGlyph_Blended(W.iconFont, codepoint, white);
	if (!s)
		return NULL;
	SDL_Texture* t = SDL_CreateTextureFromSurface(W.renderer, s);
	SDL_DestroySurface(s);
	return t;
}

static void load_icons(void)
{
	if (!W.cfg.iconFontPath || !W.cfg.iconFontPath[0])
		return;
	W.iconFont = TTF_OpenFont(W.cfg.iconFontPath, ICON_PX * ui_scale());
	if (!W.iconFont)
		return;
	W.icons[BTN_PIN] = make_icon(W.cfg.iconPin);
	W.unpinIcon = make_icon(W.cfg.iconUnpin);
	W.icons[BTN_KEYBOARD] = make_icon(W.cfg.iconKeyboard);
	W.icons[BTN_MINIMIZE] = make_icon(W.cfg.iconMinimize);
	W.icons[BTN_FULLSCREEN] = make_icon(W.cfg.iconExitFullscreen);
	W.fullscreenIcon = make_icon(W.cfg.iconFullscreen);
	W.icons[BTN_DISCONNECT] = make_icon(W.cfg.iconDisconnect);
}

static void load_labels(void)
{
	load_icons();
	if (!W.cfg.fontPath || !W.cfg.fontPath[0])
		return;
	W.font = TTF_OpenFont(W.cfg.fontPath, 14.0f * ui_scale());
	if (!W.font)
		return;
	W.labels[BTN_PIN] = make_label(W.cfg.labelPin);
	W.unpinLabel = make_label(W.cfg.labelUnpin);
	W.labels[BTN_KEYBOARD] = make_label(W.cfg.labelKeyboard);
	W.labels[BTN_MINIMIZE] = make_label(W.cfg.labelMinimize);
	W.labels[BTN_FULLSCREEN] = make_label(W.cfg.labelExitFullscreen);
	W.fullscreenLabel = make_label(W.cfg.labelFullscreen);
	W.labels[BTN_DISCONNECT] = make_label(W.cfg.labelDisconnect);
	W.labels[BTN_COUNT] = make_label(W.cfg.title);
	W.reconnectLabel = make_label(W.cfg.labelReconnecting);
}

static BOOL bar_visible(void)
{
	return W.barPinned || W.barHover;
}

static BOOL button_shown(int i)
{
	return i != BTN_MINIMIZE || W.fullscreen;
}

/* Підпис кнопки — для підказки (або замість піктограми, якщо шрифту піктограм немає). */
static SDL_Texture* button_label(int i)
{
	if (i == BTN_PIN && W.barPinned && W.unpinLabel)
		return W.unpinLabel;
	if (i == BTN_FULLSCREEN && !W.fullscreen)
		return W.fullscreenLabel;
	return W.labels[i];
}

static SDL_Texture* button_icon(int i)
{
	if (i == BTN_PIN && W.barPinned && W.unpinIcon)
		return W.unpinIcon;
	if (i == BTN_FULLSCREEN && !W.fullscreen)
		return W.fullscreenIcon;
	return W.icons[i];
}

/* Ширина кнопки: квадрат під піктограму або підпис із полями. */
static float button_width(int i, float s)
{
	float tw = 0, th = 0;
	SDL_Texture* icon = button_icon(i);
	if (icon)
		return ICON_PX * s + 16 * s;
	SDL_Texture* label = button_label(i);
	if (label)
		SDL_GetTextureSize(label, &tw, &th);
	return (tw > 0 ? tw : 60 * s) + 20 * s;
}

static BOOL bar_vertical(void)
{
	return W.barEdge == EDGE_LEFT || W.barEdge == EDGE_RIGHT;
}

/* Прямокутник у координатах плашки (уздовж краю, впоперек) → пікселі вікна. */
static SDL_FRect place(float along, float across, float length, float thickness)
{
	return bar_vertical() ? (SDL_FRect){ across, along, thickness, length } : (SDL_FRect){ along, across, length, thickness };
}

/* Розкладка плашки й кнопок у пікселях вікна. Уздовж плашки: ручка, «Закріпити», назва ПК
 * (лише на горизонтальній і якщо вміщається), «Клавіатура», «Згорнути», «На весь екран»/«У вікно»,
 * «Відключитись». Найкоротша плашка — самі піктограми. */
static void layout_bar(void)
{
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	const float s = ui_scale();
	const BOOL vertical = bar_vertical();
	const float extent = (float)(vertical ? ph : pw), cross = (float)(vertical ? pw : ph);
	const float thick = BAR_H * s, margin = BAR_MARGIN * s, pad = BAR_PAD * s, gap = 2 * s;
	const int order[] = { BTN_DISCONNECT, BTN_FULLSCREEN, BTN_MINIMIZE, BTN_KEYBOARD };

	float minLen = 2 * pad + GRIP_W * s + gap + button_width(BTN_PIN, s);
	for (size_t i = 0; i < SDL_arraysize(order); i++)
	{
		if (button_shown(order[i]))
			minLen += gap + button_width(order[i], s);
	}
	const float maxLen = SDL_max(minLen, extent - 2 * margin);
	const float len = SDL_clamp(W.barLen * s, minLen, maxLen);
	const float start = SDL_clamp(W.barPos * extent - len / 2.0f, margin, SDL_max(margin, extent - margin - len));
	const BOOL nearSide = W.barEdge == EDGE_TOP || W.barEdge == EDGE_LEFT;
	const float across = nearSide ? margin : cross - margin - thick;

	W.barRect = place(start, across, len, thick);
	W.hotRect = place(start, nearSide ? 0 : across, len, thick + margin);
	W.handleRect = place(start + (len - HANDLE_W * s) / 2.0f, nearSide ? 0 : cross - HANDLE_H * s, HANDLE_W * s,
	                     HANDLE_H * s);

	const float bAcross = across + 4 * s, bThick = thick - 8 * s;
	float a = start + pad;
	W.gripRect = place(a, bAcross, GRIP_W * s, bThick);
	a += GRIP_W * s + gap;
	const float pinLen = button_width(BTN_PIN, s);
	W.buttons[BTN_PIN] = place(a, bAcross, pinLen, bThick);
	a += pinLen;
	float b = start + len - pad;
	for (size_t i = 0; i < SDL_arraysize(order); i++)
	{
		if (!button_shown(order[i]))
		{
			W.buttons[order[i]] = (SDL_FRect){ 0, 0, 0, 0 };
			continue;
		}
		const float w = button_width(order[i], s);
		b -= w;
		W.buttons[order[i]] = place(b, bAcross, w, bThick);
		b -= gap;
	}
	const float titleLen = vertical ? 0 : b - a - 18 * s;
	W.titleRect = titleLen >= 24 * s ? place(a + 10 * s, across, titleLen, thick) : (SDL_FRect){ 0, 0, 0, 0 };
}

static void draw_label(SDL_Texture* t, const SDL_FRect* box, BOOL left)
{
	if (!t)
		return;
	float tw = 0, th = 0;
	SDL_GetTextureSize(t, &tw, &th);
	const SDL_FRect dst = { left ? box->x : box->x + (box->w - tw) / 2.0f, box->y + (box->h - th) / 2.0f, tw, th };
	SDL_RenderTexture(W.renderer, t, NULL, &dst);
}

static void draw_icon(SDL_Texture* t, const SDL_FRect* box, uint32_t rgb)
{
	float tw = 0, th = 0;
	SDL_GetTextureSize(t, &tw, &th);
	SDL_SetTextureColorMod(t, (Uint8)(rgb >> 16), (Uint8)(rgb >> 8), (Uint8)rgb);
	const SDL_FRect dst = { floorf(box->x + (box->w - tw) / 2.0f), floorf(box->y + (box->h - th) / 2.0f), tw, th };
	SDL_RenderTexture(W.renderer, t, NULL, &dst);
}

/* Підказка під кнопкою, на яку мишу навели щонайменше пів секунди. */
static void draw_tooltip(void)
{
	if (!W.tooltipShown || W.hoverButton == BTN_NONE || !bar_visible())
		return;
	SDL_Texture* t = button_label(W.hoverButton);
	if (!t)
		return;
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	const float s = ui_scale();
	float tw = 0, th = 0;
	SDL_GetTextureSize(t, &tw, &th);
	const SDL_FRect* b = &W.buttons[W.hoverButton];
	const SDL_FRect* bar = &W.barRect;
	SDL_FRect box = { 0, 0, tw + 16 * s, th + 10 * s };
	/* Підказка — з боку вікна, протилежного краю плашки. */
	switch (W.barEdge)
	{
		case EDGE_BOTTOM:
			box.x = b->x + (b->w - box.w) / 2.0f;
			box.y = bar->y - box.h - 6 * s;
			break;
		case EDGE_LEFT:
			box.x = bar->x + bar->w + 6 * s;
			box.y = b->y + (b->h - box.h) / 2.0f;
			break;
		case EDGE_RIGHT:
			box.x = bar->x - box.w - 6 * s;
			box.y = b->y + (b->h - box.h) / 2.0f;
			break;
		default:
			box.x = b->x + (b->w - box.w) / 2.0f;
			box.y = bar->y + bar->h + 6 * s;
			break;
	}
	box.x = SDL_clamp(box.x, 4 * s, SDL_max(4 * s, (float)pw - box.w - 4 * s));
	box.y = SDL_clamp(box.y, 4 * s, SDL_max(4 * s, (float)ph - box.h - 4 * s));
	draw_panel(&box, (float)W.cfg.radius * 0.7f * s);
	draw_label(t, &box, FALSE);
}

/* Ручка для перетягування: 2×3 крапки (на вертикальній плашці — 3×2). */
static void draw_grip(void)
{
	const float s = ui_scale(), dot = SDL_max(2.0f, floorf(2 * s)), step = floorf(5 * s);
	const SDL_FRect* g = &W.gripRect;
	const int cols = bar_vertical() ? 3 : 2, rows = bar_vertical() ? 2 : 3;
	const float x0 = floorf(g->x + (g->w - (float)(cols - 1) * step - dot) / 2.0f);
	const float y0 = floorf(g->y + (g->h - (float)(rows - 1) * step - dot) / 2.0f);
	set_color(W.cfg.colorText, W.drag == DRAG_MOVE ? 230 : 120);
	SDL_SetRenderDrawBlendMode(W.renderer, SDL_BLENDMODE_BLEND);
	for (int r = 0; r < rows; r++)
	{
		for (int c = 0; c < cols; c++)
		{
			const SDL_FRect d = { x0 + (float)c * step, y0 + (float)r * step, dot, dot };
			SDL_RenderFillRect(W.renderer, &d);
		}
	}
}

static void draw_bar(void)
{
	layout_bar();
	const float s = ui_scale(), radius = (float)W.cfg.radius * s;
	if (!bar_visible())
	{
		draw_panel(&W.handleRect, radius); /* тонка смужка біля краю */
		return;
	}
	draw_panel(&W.barRect, radius);
	draw_grip();
	for (int i = 0; i < BTN_COUNT; i++)
	{
		if (!button_shown(i))
			continue;
		const BOOL accent = i == BTN_DISCONNECT || (i == BTN_PIN && W.barPinned);
		if (W.hoverButton == i || accent)
			fill_round(&W.buttons[i], radius * 0.6f, i == BTN_DISCONNECT ? W.cfg.colorError : W.cfg.colorAccent,
			           W.hoverButton == i ? 90 : 40);
		SDL_Texture* icon = button_icon(i);
		if (icon)
			draw_icon(icon, &W.buttons[i],
			          i == BTN_DISCONNECT                ? W.cfg.colorError
			          : i == BTN_PIN && W.barPinned ? W.cfg.colorAccent
			                                        : W.cfg.colorText);
		else
			draw_label(button_label(i), &W.buttons[i], FALSE);
	}
	/* Назва ПК — між «Закріпити» і правими кнопками, якщо вміщається. */
	const SDL_FRect* name = &W.titleRect;
	if (name->w > 0 && W.labels[BTN_COUNT])
	{
		SDL_Rect clip = { (int)name->x, (int)name->y, (int)name->w, (int)name->h };
		SDL_SetRenderClipRect(W.renderer, &clip);
		draw_label(W.labels[BTN_COUNT], name, TRUE);
		SDL_SetRenderClipRect(W.renderer, NULL);
	}
	draw_tooltip();
}

/* Зв'язок обірвався: картинку притемнюємо, по центру — «Перепідключення…». */
static void draw_reconnecting(void)
{
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	SDL_SetRenderDrawBlendMode(W.renderer, SDL_BLENDMODE_BLEND);
	SDL_SetRenderDrawColor(W.renderer, 0, 0, 0, 150);
	const SDL_FRect all = { 0, 0, (float)pw, (float)ph };
	SDL_RenderFillRect(W.renderer, &all);
	if (!W.reconnectLabel)
		return;
	const float s = ui_scale();
	float tw = 0, th = 0;
	SDL_GetTextureSize(W.reconnectLabel, &tw, &th);
	const SDL_FRect box = { floorf(((float)pw - tw) / 2.0f - 20 * s), floorf(((float)ph - th) / 2.0f - 12 * s),
		                    tw + 40 * s, th + 24 * s };
	fill_round(&box, (float)W.cfg.radius * s, W.cfg.colorSurface, 255);
	stroke_round(&box, (float)W.cfg.radius * s, W.cfg.colorAccent);
	draw_label(W.reconnectLabel, &box, FALSE);
}

static void render(void)
{
	SDL_SetRenderDrawColor(W.renderer, 0, 0, 0, 255);
	SDL_RenderClear(W.renderer);
	if (W.texture)
	{
		const SDL_FRect dst = image_rect();
		/* Піксель у піксель — без згладжування (воно розмиває); масштаб — зі згладжуванням. */
		const BOOL exact = dst.w == (float)W.texW && dst.h == (float)W.texH;
		SDL_SetTextureScaleMode(W.texture, exact ? SDL_SCALEMODE_NEAREST : SDL_SCALEMODE_LINEAR);
		SDL_RenderTexture(W.renderer, W.texture, NULL, &dst);
	}
	if (SDL_GetAtomicInt(&W.reconnecting))
		draw_reconnecting();
	draw_bar();
	SDL_RenderPresent(W.renderer);
}

/* Копіює змінену ділянку буфера FreeRDP у текстуру на відеокарті. */
static void upload(BOOL whole)
{
	SDL_LockMutex(W.dirtyLock);
	int x0 = W.dx0, y0 = W.dy0, x1 = W.dx1, y1 = W.dy1;
	W.dx0 = W.dy0 = W.dx1 = W.dy1 = 0;
	SDL_UnlockMutex(W.dirtyLock);
	SDL_SetAtomicInt(&W.framePending, 0);

	W.host.lock(W.host.ctx);
	uint32_t bw = 0, bh = 0, stride = 0;
	const uint8_t* buf = W.host.buffer(W.host.ctx, &bw, &bh, &stride);
	if (buf && bw && bh)
	{
		if (!W.texture || W.texW != bw || W.texH != bh)
		{
			if (W.texture)
				SDL_DestroyTexture(W.texture);
			/* XRGB8888 на little-endian = байти B,G,R,X — як PIXEL_FORMAT_BGRA32 у FreeRDP. */
			W.texture = SDL_CreateTexture(W.renderer, SDL_PIXELFORMAT_XRGB8888, SDL_TEXTUREACCESS_STREAMING, (int)bw,
			                              (int)bh);
			W.texW = bw;
			W.texH = bh;
			whole = TRUE;
		}
		if (whole)
		{
			x0 = y0 = 0;
			x1 = (int)bw;
			y1 = (int)bh;
		}
		x0 = SDL_clamp(x0, 0, (int)bw);
		x1 = SDL_clamp(x1, 0, (int)bw);
		y0 = SDL_clamp(y0, 0, (int)bh);
		y1 = SDL_clamp(y1, 0, (int)bh);
		if (W.texture && x1 > x0 && y1 > y0)
		{
			const SDL_Rect r = { x0, y0, x1 - x0, y1 - y0 };
			SDL_UpdateTexture(W.texture, &r, buf + (size_t)y0 * stride + (size_t)x0 * 4, (int)stride);
		}
	}
	W.host.unlock(W.host.ctx);
}

/* ── Вікно ────────────────────────────────────────────────────── */

static void apply_keyboard_grab(void)
{
	const BOOL grab = W.cfg.keyboardCapture == 1 || (W.cfg.keyboardCapture == 0 && W.fullscreen);
	SDL_SetWindowKeyboardGrab(W.window, grab);
}

static void release_keys(void)
{
	for (int i = 0; i < SDL_SCANCODE_COUNT; i++)
	{
		if (W.pressed[i] && g_scan[i])
			W.host.key(W.host.ctx, g_scan[i], FALSE, FALSE);
		W.pressed[i] = FALSE;
	}
}

static void set_fullscreen(BOOL on)
{
	release_keys();
	W.fullscreen = on;
	W.barHover = FALSE;
	W.barHideAt = 0;
	W.hoverButton = BTN_NONE;
	SDL_SetWindowFullscreen(W.window, on);
	apply_keyboard_grab();
}

/* Екранна клавіатура ОС: її натискання йдуть у це вікно, а звідси — на віддалений ПК. */
static void open_keyboard(void)
{
#ifdef _WIN32
	/* osk.exe вимагає uiAccess — CreateProcess відмовить, ShellExecute запускає правильно. */
	ShellExecuteW(NULL, L"open", L"osk.exe", NULL, NULL, SW_SHOWNORMAL);
#endif
}

#ifdef _WIN32
/* Системне меню вікна (клік по іконці в заголовку, Alt+Пробіл): «На весь екран», «Екранна клавіатура».
 * Ідентифікатори — кратні 16 і менші за 0xF000, як вимагає WM_SYSCOMMAND. */
#define IDM_FULLSCREEN 0x1010
#define IDM_KEYBOARD 0x1020

static WNDPROC g_sdlWndProc;

static LRESULT CALLBACK menu_wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
	if (msg == WM_SYSCOMMAND)
	{
		switch (wp & 0xFFF0)
		{
			case IDM_FULLSCREEN:
				push(EV_MENU_FULLSCREEN);
				return 0;
			case IDM_KEYBOARD:
				push(EV_MENU_KEYBOARD);
				return 0;
			default:
				break;
		}
	}
	return CallWindowProcW(g_sdlWndProc, hwnd, msg, wp, lp);
}

static void append_menu_item(HMENU menu, UINT id, const char* utf8)
{
	if (!utf8 || !utf8[0])
		return;
	wchar_t text[256];
	if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, text, (int)SDL_arraysize(text)) > 0)
		AppendMenuW(menu, MF_STRING, id, text);
}

static void add_system_menu(void)
{
	HWND hwnd = (HWND)SDL_GetPointerProperty(SDL_GetWindowProperties(W.window), SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
	HMENU menu = hwnd ? GetSystemMenu(hwnd, FALSE) : NULL;
	if (!menu)
		return;
	AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
	append_menu_item(menu, IDM_FULLSCREEN, W.cfg.menuFullscreen);
	append_menu_item(menu, IDM_KEYBOARD, W.cfg.menuKeyboard);
	g_sdlWndProc = (WNDPROC)SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)menu_wndproc);
}
#endif

static void create_window(void)
{
	uint32_t bw = 0, bh = 0, stride = 0;
	W.host.lock(W.host.ctx);
	W.host.buffer(W.host.ctx, &bw, &bh, &stride);
	W.host.unlock(W.host.ctx);
	if (!bw || !bh)
		bw = 1280, bh = 800;

	W.window = SDL_CreateWindow(W.cfg.title, (int)bw, (int)bh,
	                            SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_HIDDEN);
	if (!W.window)
		return;
	W.renderer = SDL_CreateRenderer(W.window, NULL);
	/* Розмір вікна в його координатах: віддалений екран у фізичних пікселях / пікселів на одиницю. */
	const float k = pixel_ratio();
	int w = (int)((float)bw / k), h = (int)((float)bh / k);
	SDL_Rect usable;
	if (SDL_GetDisplayUsableBounds(SDL_GetDisplayForWindow(W.window), &usable))
	{
		w = SDL_min(w, usable.w);
		h = SDL_min(h, usable.h);
	}
	SDL_SetWindowSize(W.window, w, h);
	SDL_SetWindowPosition(W.window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
	load_labels();
#ifdef _WIN32
	add_system_menu();
#endif
	SDL_ShowWindow(W.window);
	SDL_RaiseWindow(W.window);
	if (W.cfg.startFullscreen)
		set_fullscreen(TRUE);
	else
		apply_keyboard_grab();
	W.resizeAt = SDL_GetTicks() + RESIZE_DELAY_MS; /* підігнати роздільність під реальне вікно */
}

static void request_resize_now(void)
{
	W.resizeAt = 0;
	const BOOL follow = W.fullscreen || W.cfg.resizeMode == 0;
	if (!follow)
		return;
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	if (pw <= 0 || ph <= 0)
		return;
	if ((uint32_t)pw == W.texW && (uint32_t)ph == W.texH)
		return;
	if ((uint32_t)pw == W.lastRequestedW && (uint32_t)ph == W.lastRequestedH)
		return;
	W.lastRequestedW = (uint32_t)pw;
	W.lastRequestedH = (uint32_t)ph;
	W.host.resize(W.host.ctx, (uint32_t)pw, (uint32_t)ph);
}

/* ── Ввід ─────────────────────────────────────────────────────── */

static int hit_button(float px, float py)
{
	if (!bar_visible())
		return BTN_NONE;
	for (int i = 0; i < BTN_COUNT; i++)
	{
		const SDL_FRect* b = &W.buttons[i];
		if (px >= b->x && px < b->x + b->w && py >= b->y && py < b->y + b->h)
			return i;
	}
	return BTN_NONE;
}

static BOOL in_rect(const SDL_FRect* r, float px, float py)
{
	return px >= r->x && px < r->x + r->w && py >= r->y && py < r->y + r->h;
}

static void set_cursor(SDL_SystemCursor c)
{
	if (W.cursorShown == c)
		return;
	if (!W.cursors[c])
		W.cursors[c] = SDL_CreateSystemCursor(c);
	if (W.cursors[c])
		SDL_SetCursor(W.cursors[c]);
	W.cursorShown = c;
}

/* Поле на кінці плашки (за нього змінюють довжину): -1 — початок, 1 — кінець, 0 — ні. */
static int resize_end(float px, float py)
{
	if (!in_rect(&W.barRect, px, py))
		return 0;
	const float pad = BAR_PAD * ui_scale();
	const float along = bar_vertical() ? py : px;
	const float start = bar_vertical() ? W.barRect.y : W.barRect.x;
	const float len = bar_vertical() ? W.barRect.h : W.barRect.w;
	return along < start + pad ? -1 : along >= start + len - pad ? 1 : 0;
}

/* Перетягування: плашка липне до найближчого краю вікна, центр — під мишею. */
static void drag_move(float px, float py)
{
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	if (pw <= 0 || ph <= 0)
		return;
	const float d[4] = { py, (float)ph - py, px, (float)pw - px }; /* до верху, низу, лівого, правого */
	int edge = EDGE_TOP;
	for (int i = 1; i < 4; i++)
	{
		if (d[i] < d[edge])
			edge = i;
	}
	W.barEdge = edge;
	W.barPos = SDL_clamp(bar_vertical() ? py / (float)ph : px / (float)pw, 0.0f, 1.0f);
}

/* Зміна довжини: плашка росте в обидва боки від центру. */
static void drag_resize(float px, float py)
{
	const float along = bar_vertical() ? py : px;
	const float len = W.dragLen + 2.0f * W.dragSign * (along - W.dragFrom);
	W.barLen = SDL_max(0.0f, len) / ui_scale();
}

/* Плашку відпустили — застосунок запам'ятає, де вона. */
static void drag_end(void)
{
	if (W.drag == DRAG_RESIZE)
	{
		layout_bar(); /* запам'ятовуємо довжину, що реально вмістилась */
		W.barLen = (bar_vertical() ? W.barRect.h : W.barRect.w) / ui_scale();
	}
	W.drag = DRAG_NONE;
	if (W.host.barMoved)
		W.host.barMoved(W.host.ctx, W.barEdge, (int)(W.barPos * 10000.0f + 0.5f), (int)(W.barLen + 0.5f));
}

/* Плашка: повертає TRUE, якщо подія миші — її (на ПК не йде). [action] — MOUSE_*. */
static BOOL bar_mouse(float x, float y, int action, Uint8 button)
{
	const float k = pixel_ratio();
	const float px = x * k, py = y * k;
	const BOOL click = action == MOUSE_DOWN;
	if (W.drag != DRAG_NONE)
	{
		if (action == MOUSE_UP && button == SDL_BUTTON_LEFT)
			drag_end();
		else if (action == MOUSE_MOVE && W.drag == DRAG_MOVE)
			drag_move(px, py);
		else if (action == MOUSE_MOVE)
			drag_resize(px, py);
		render();
		return TRUE;
	}
	layout_bar();
	const BOOL inside = bar_visible() ? in_rect(&W.hotRect, px, py) : in_rect(&W.handleRect, px, py);
	const BOOL wasHover = W.barHover;
	const int wasButton = W.hoverButton;
	if (inside)
	{
		W.barHover = TRUE;
		W.barHideAt = 0;
	}
	else if (W.barHover && !W.barHideAt)
		W.barHideAt = SDL_GetTicks() + BAR_HIDE_DELAY_MS; /* мишу прибрали — ховаємо не одразу */
	W.hoverButton = inside ? hit_button(px, py) : BTN_NONE;
	if (W.hoverButton != wasButton)
	{
		W.hoverSince = SDL_GetTicks();
		W.tooltipShown = FALSE;
	}
	if (click)
	{
		W.tooltipShown = FALSE; /* натиснули — підказка знову лише після паузи */
		W.hoverSince = SDL_GetTicks();
	}
	/* Курсор: на кінцях — змінити довжину, на ручці й назві — перетягнути. */
	const int end = bar_visible() ? resize_end(px, py) : 0;
	const BOOL movable = bar_visible() && W.hoverButton == BTN_NONE && in_rect(&W.barRect, px, py) && !end;
	set_cursor(end ? (bar_vertical() ? SDL_SYSTEM_CURSOR_NS_RESIZE : SDL_SYSTEM_CURSOR_EW_RESIZE)
	           : movable ? SDL_SYSTEM_CURSOR_MOVE
	                     : SDL_SYSTEM_CURSOR_DEFAULT);
	if (click && button == SDL_BUTTON_LEFT && (end || movable))
	{
		W.drag = end ? DRAG_RESIZE : DRAG_MOVE;
		W.dragFrom = bar_vertical() ? py : px;
		W.dragLen = bar_vertical() ? W.barRect.h : W.barRect.w;
		W.dragSign = (float)end;
		render();
		return TRUE;
	}
	if (click && inside)
	{
		switch (W.hoverButton)
		{
			case BTN_PIN:
				W.barPinned = !W.barPinned;
				break;
			case BTN_KEYBOARD:
				open_keyboard();
				break;
			case BTN_MINIMIZE:
				SDL_MinimizeWindow(W.window);
				break;
			case BTN_FULLSCREEN:
				set_fullscreen(!W.fullscreen);
				break;
			case BTN_DISCONNECT:
				W.host.close(W.host.ctx);
				break;
			default:
				break;
		}
	}
	if (wasHover != W.barHover || wasButton != W.hoverButton || click)
		render();
	return bar_visible() && in_rect(&W.hotRect, px, py);
}

/* Час сховати плашку настав (мишу прибрали кілька секунд тому). */
static void hide_bar_if_due(void)
{
	if (!W.barHideAt || SDL_GetTicks() < W.barHideAt || W.drag != DRAG_NONE)
		return;
	W.barHideAt = 0;
	W.barHover = FALSE;
	W.hoverButton = BTN_NONE;
	if (W.window)
		render();
}

static void on_key(const SDL_KeyboardEvent* e)
{
	/* Ctrl+Alt+Enter — повний екран і назад (на ПК не йде). */
	if (e->down && (e->mod & SDL_KMOD_CTRL) && (e->mod & SDL_KMOD_ALT) &&
	    (e->scancode == SDL_SCANCODE_RETURN || e->scancode == SDL_SCANCODE_KP_ENTER))
	{
		set_fullscreen(!W.fullscreen);
		render();
		return;
	}
	if (e->scancode >= SDL_SCANCODE_COUNT)
		return;
	const uint16_t code = g_scan[e->scancode];
	if (!code)
		return;
	W.pressed[e->scancode] = e->down;
	W.host.key(W.host.ctx, code, e->down, e->repeat);
}

static void on_button(const SDL_MouseButtonEvent* e)
{
	if (bar_mouse(e->x, e->y, e->down ? MOUSE_DOWN : MOUSE_UP, e->button))
		return;
	uint16_t x = 0, y = 0;
	if (!to_remote(e->x, e->y, &x, &y))
		return;
	Uint8 b = e->button;
	if (W.cfg.swapMouseButtons && (b == SDL_BUTTON_LEFT || b == SDL_BUTTON_RIGHT))
		b = b == SDL_BUTTON_LEFT ? SDL_BUTTON_RIGHT : SDL_BUTTON_LEFT;
	uint16_t flags = 0;
	switch (b)
	{
		case SDL_BUTTON_LEFT:
			flags = PTR_FLAGS_BUTTON1;
			break;
		case SDL_BUTTON_RIGHT:
			flags = PTR_FLAGS_BUTTON2;
			break;
		case SDL_BUTTON_MIDDLE:
			flags = PTR_FLAGS_BUTTON3;
			break;
		default:
			return;
	}
	if (e->down)
		flags |= PTR_FLAGS_DOWN;
	W.host.mouse(W.host.ctx, flags, x, y);
}

static void on_motion(const SDL_MouseMotionEvent* e)
{
	if (bar_mouse(e->x, e->y, MOUSE_MOVE, 0))
		return;
	uint16_t x = 0, y = 0;
	if (to_remote(e->x, e->y, &x, &y))
		W.host.mouse(W.host.ctx, PTR_FLAGS_MOVE, x, y);
}

static void on_wheel(const SDL_MouseWheelEvent* e)
{
	uint16_t x = 0, y = 0;
	if (!to_remote(e->mouse_x, e->mouse_y, &x, &y))
		return;
	const float dir = e->direction == SDL_MOUSEWHEEL_FLIPPED ? -1.0f : 1.0f;
	/* SDL: 1.0 — один крок; RDP: 120 на крок (MS-RDPBCGR). Дробові кроки тачпада накопичуємо. */
	W.wheelRest += e->y * dir * 120.0f;
	const int delta = (int)SDL_clamp(W.wheelRest, -255.0f, 255.0f);
	W.wheelRest -= (float)delta;
	if (delta)
		W.host.wheel(W.host.ctx, delta, FALSE, x, y);
	if (e->x != 0.0f)
		W.host.wheel(W.host.ctx, (int)SDL_clamp(e->x * dir * 120.0f, -255.0f, 255.0f), TRUE, x, y);
}

/* ── Публічне ─────────────────────────────────────────────────── */

BOOL window_init(const WindowConfig* cfg, const WindowHost* host)
{
	W.cfg = *cfg;
	W.host = *host;
	W.hoverButton = BTN_NONE;
	W.barEdge = SDL_clamp(cfg->barEdge, EDGE_TOP, EDGE_RIGHT);
	W.barPos = (float)SDL_clamp(cfg->barPos, 0, 10000) / 10000.0f;
	W.barLen = cfg->barLength > 0 ? (float)cfg->barLength : (float)BAR_W;
	W.cursorShown = SDL_SYSTEM_CURSOR_DEFAULT;
	init_scancodes();
	/* Іконка вікна — з ресурсів mhrd-session.exe (mhrd-session.rc). */
	SDL_SetHint(SDL_HINT_WINDOWS_INTRESOURCE_ICON, "1");
	SDL_SetHint(SDL_HINT_WINDOWS_INTRESOURCE_ICON_SMALL, "1");
	/* У повному екрані Alt+Tab має йти на віддалений ПК, а не перемикати вікна тут. */
	SDL_SetHint(SDL_HINT_ALLOW_ALT_TAB_WHILE_GRABBED, "0");
	if (!SDL_Init(SDL_INIT_VIDEO))
		return FALSE;
	TTF_Init();
	W.dirtyLock = SDL_CreateMutex();
	W.evBase = SDL_RegisterEvents(EV_COUNT);
	return W.dirtyLock && W.evBase != 0;
}

void window_run(void)
{
	BOOL quit = FALSE;
	while (!quit)
	{
		SDL_Event e;
		Sint32 timeout = 100;
		const Uint64 now = SDL_GetTicks();
		if (W.resizeAt)
			timeout = W.resizeAt > now ? (Sint32)(W.resizeAt - now) : 0;
		if (W.barHideAt)
			timeout = SDL_min(timeout, W.barHideAt > now ? (Sint32)(W.barHideAt - now) : 0);
		const BOOL tooltipPending = W.hoverButton != BTN_NONE && !W.tooltipShown;
		if (tooltipPending)
		{
			const Uint64 at = W.hoverSince + TOOLTIP_DELAY_MS;
			timeout = SDL_min(timeout, at > now ? (Sint32)(at - now) : 0);
		}
		BOOL got = SDL_WaitEventTimeout(&e, timeout);
		while (got)
		{
			if (e.type >= W.evBase && e.type < W.evBase + EV_COUNT)
			{
				switch (e.type - W.evBase)
				{
					case EV_SURFACE:
						if (!W.window)
							create_window();
						if (W.window)
						{
							upload(TRUE);
							W.lastRequestedW = W.lastRequestedH = 0;
							W.resizeAt = SDL_GetTicks() + RESIZE_DELAY_MS; /* сервер міг дати не той розмір */
							render();
						}
						break;
					case EV_FRAME:
						if (W.window)
						{
							upload(FALSE);
							render();
						}
						else
							SDL_SetAtomicInt(&W.framePending, 0);
						break;
					case EV_FOCUS:
						if (W.window)
						{
							SDL_RestoreWindow(W.window);
							SDL_RaiseWindow(W.window);
						}
						break;
					case EV_QUIT:
						quit = TRUE;
						break;
					case EV_MENU_FULLSCREEN:
						if (W.window)
						{
							set_fullscreen(!W.fullscreen);
							render();
						}
						break;
					case EV_MENU_KEYBOARD:
						open_keyboard();
						break;
					case EV_RECONNECTING:
						release_keys(); /* після відновлення на ПК не має лишитись натиснутих клавіш */
						if (W.window)
							render();
						break;
					default:
						break;
				}
			}
			else
			{
				switch (e.type)
				{
					case SDL_EVENT_QUIT:
					case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
						W.host.close(W.host.ctx); /* сеанс відключиться й надішле EV_QUIT */
						break;
					case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
						W.resizeAt = SDL_GetTicks() + RESIZE_DELAY_MS;
						render();
						break;
					case SDL_EVENT_WINDOW_EXPOSED:
						render();
						break;
					case SDL_EVENT_WINDOW_FOCUS_LOST:
						release_keys(); /* щоб на ПК не «залип» Ctrl чи Alt */
						break;
					case SDL_EVENT_WINDOW_MOUSE_LEAVE:
						/* Миша вийшла з вікна — підказку прибираємо одразу, плашку ховаємо із затримкою. */
						if (W.barHover && !W.barHideAt)
							W.barHideAt = SDL_GetTicks() + BAR_HIDE_DELAY_MS;
						if (W.hoverButton != BTN_NONE)
						{
							W.hoverButton = BTN_NONE;
							render();
						}
						break;
					case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:
						if (W.fullscreen)
						{
							W.fullscreen = FALSE;
							apply_keyboard_grab();
						}
						break;
					case SDL_EVENT_KEY_DOWN:
					case SDL_EVENT_KEY_UP:
						on_key(&e.key);
						break;
					case SDL_EVENT_MOUSE_MOTION:
						on_motion(&e.motion);
						break;
					case SDL_EVENT_MOUSE_BUTTON_DOWN:
					case SDL_EVENT_MOUSE_BUTTON_UP:
						on_button(&e.button);
						break;
					case SDL_EVENT_MOUSE_WHEEL:
						on_wheel(&e.wheel);
						break;
					default:
						break;
				}
			}
			got = SDL_PollEvent(&e);
		}
		if (W.resizeAt && SDL_GetTicks() >= W.resizeAt && W.window)
			request_resize_now();
		hide_bar_if_due();
		if (W.window && W.hoverButton != BTN_NONE && !W.tooltipShown &&
		    SDL_GetTicks() >= W.hoverSince + TOOLTIP_DELAY_MS)
		{
			W.tooltipShown = TRUE;
			render();
		}
	}
}

void window_shutdown(void)
{
	for (int i = 0; i <= BTN_COUNT; i++)
	{
		if (W.labels[i])
			SDL_DestroyTexture(W.labels[i]);
	}
	if (W.unpinLabel)
		SDL_DestroyTexture(W.unpinLabel);
	if (W.fullscreenLabel)
		SDL_DestroyTexture(W.fullscreenLabel);
	if (W.reconnectLabel)
		SDL_DestroyTexture(W.reconnectLabel);
	for (int i = 0; i < BTN_COUNT; i++)
	{
		if (W.icons[i])
			SDL_DestroyTexture(W.icons[i]);
	}
	if (W.unpinIcon)
		SDL_DestroyTexture(W.unpinIcon);
	if (W.fullscreenIcon)
		SDL_DestroyTexture(W.fullscreenIcon);
	for (int i = 0; i < SDL_SYSTEM_CURSOR_COUNT; i++)
	{
		if (W.cursors[i])
			SDL_DestroyCursor(W.cursors[i]);
	}
	if (W.iconFont)
		TTF_CloseFont(W.iconFont);
	if (W.font)
		TTF_CloseFont(W.font);
	if (W.texture)
		SDL_DestroyTexture(W.texture);
	if (W.renderer)
		SDL_DestroyRenderer(W.renderer);
	if (W.window)
		SDL_DestroyWindow(W.window);
	if (W.dirtyLock)
		SDL_DestroyMutex(W.dirtyLock);
	TTF_Quit();
	SDL_Quit();
}
