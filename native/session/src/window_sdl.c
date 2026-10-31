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
#define BAR_W 720
#define BAR_H 40
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
	int hoverButton;
	SDL_FRect buttons[BTN_COUNT];
	SDL_FRect barRect, handleRect;

	Uint64 resizeAt; /* коли просити нову роздільність (0 — не треба) */
	uint32_t lastRequestedW, lastRequestedH;
	BOOL pressed[SDL_SCANCODE_COUNT];
	float wheelRest;

	TTF_Font* font;
	SDL_Texture* labels[BTN_COUNT + 1]; /* + назва ПК; BTN_PIN — «закріпити», окремо «відкріпити» */
	SDL_Texture* unpinLabel;
	SDL_Texture* fullscreenLabel; /* BTN_FULLSCREEN у вікні; labels[BTN_FULLSCREEN] — «у вікно» */
	float titleRight;             /* де закінчується місце для назви ПК на плашці */
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

static void load_labels(void)
{
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
}

static BOOL bar_visible(void)
{
	return W.barPinned || W.barHover;
}

static BOOL button_shown(int i)
{
	return i != BTN_MINIMIZE || W.fullscreen;
}

static SDL_Texture* button_label(int i)
{
	if (i == BTN_PIN && W.barPinned && W.unpinLabel)
		return W.unpinLabel;
	if (i == BTN_FULLSCREEN && !W.fullscreen)
		return W.fullscreenLabel;
	return W.labels[i];
}

/* Розкладка плашки й кнопок у пікселях вікна. */
static void layout_bar(void)
{
	int pw = 0, ph = 0;
	SDL_GetWindowSizeInPixels(W.window, &pw, &ph);
	const float s = ui_scale();
	const float bw = SDL_min(BAR_W * s, (float)pw), bh = BAR_H * s;
	W.barRect = (SDL_FRect){ ((float)pw - bw) / 2.0f, 0, bw, bh };
	W.handleRect = (SDL_FRect){ ((float)pw - HANDLE_W * s) / 2.0f, 0, HANDLE_W * s, HANDLE_H * s };
	/* Справа наліво: «Відключитись», «На весь екран»/«У вікно», «Згорнути», «Клавіатура»;
	 * зліва — «Закріпити», між ними — назва ПК. */
	float x = W.barRect.x + W.barRect.w - 8 * s;
	const int order[] = { BTN_DISCONNECT, BTN_FULLSCREEN, BTN_MINIMIZE, BTN_KEYBOARD };
	for (size_t i = 0; i < SDL_arraysize(order); i++)
	{
		if (!button_shown(order[i]))
		{
			W.buttons[order[i]] = (SDL_FRect){ 0, 0, 0, 0 };
			continue;
		}
		float tw = 0, th = 0;
		SDL_Texture* t = button_label(order[i]);
		if (t)
			SDL_GetTextureSize(t, &tw, &th);
		const float w = (tw > 0 ? tw : 60 * s) + 20 * s;
		x -= w;
		W.buttons[order[i]] = (SDL_FRect){ x, 6 * s, w, bh - 12 * s };
		x -= 4 * s;
	}
	W.titleRight = x;
	float tw = 0, th = 0;
	SDL_Texture* pin = button_label(BTN_PIN);
	if (pin)
		SDL_GetTextureSize(pin, &tw, &th);
	W.buttons[BTN_PIN] = (SDL_FRect){ W.barRect.x + 8 * s, 6 * s, (tw > 0 ? tw : 60 * s) + 20 * s, bh - 12 * s };
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

static void draw_bar(void)
{
	layout_bar();
	set_color(W.cfg.colorSurface, 255);
	if (!bar_visible())
	{
		SDL_RenderFillRect(W.renderer, &W.handleRect); /* тонка плашка вгорі по центру */
		set_color(W.cfg.colorBorder, 255);
		SDL_RenderRect(W.renderer, &W.handleRect);
		return;
	}
	SDL_RenderFillRect(W.renderer, &W.barRect);
	set_color(W.cfg.colorBorder, 255);
	SDL_RenderRect(W.renderer, &W.barRect);
	for (int i = 0; i < BTN_COUNT; i++)
	{
		if (!button_shown(i))
			continue;
		const BOOL accent = i == BTN_DISCONNECT || (i == BTN_PIN && W.barPinned);
		if (W.hoverButton == i || accent)
		{
			set_color(i == BTN_DISCONNECT ? W.cfg.colorError : W.cfg.colorAccent, W.hoverButton == i ? 90 : 40);
			SDL_SetRenderDrawBlendMode(W.renderer, SDL_BLENDMODE_BLEND);
			SDL_RenderFillRect(W.renderer, &W.buttons[i]);
		}
		draw_label(button_label(i), &W.buttons[i], FALSE);
	}
	/* Назва ПК — між «Закріпити» і правими кнопками. */
	const float s = ui_scale();
	const float nameX = W.buttons[BTN_PIN].x + W.buttons[BTN_PIN].w + 12 * s;
	SDL_FRect name = { nameX, 0, W.titleRight - nameX - 8 * s, W.barRect.h };
	if (name.w > 0 && W.labels[BTN_COUNT])
	{
		SDL_Rect clip = { (int)name.x, (int)name.y, (int)name.w, (int)name.h };
		SDL_SetRenderClipRect(W.renderer, &clip);
		draw_label(W.labels[BTN_COUNT], &name, TRUE);
		SDL_SetRenderClipRect(W.renderer, NULL);
	}
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

/* Плашка вгорі по центру: повертає TRUE, якщо подія миші — її (на ПК не йде). */
static BOOL bar_mouse(float x, float y, BOOL click)
{
	const float k = pixel_ratio();
	const float px = x * k, py = y * k;
	layout_bar();
	const BOOL over = bar_visible() ? in_rect(&W.barRect, px, py) : in_rect(&W.handleRect, px, py);
	const BOOL wasHover = W.barHover;
	const int wasButton = W.hoverButton;
	W.barHover = over || (W.barHover && in_rect(&W.barRect, px, py));
	W.hoverButton = W.barHover ? hit_button(px, py) : BTN_NONE;
	if (click && W.barHover)
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
	return W.barHover || W.barPinned ? (bar_visible() && in_rect(&W.barRect, px, py)) : FALSE;
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
	if (bar_mouse(e->x, e->y, e->down))
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
	if (bar_mouse(e->x, e->y, FALSE))
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
		if (W.resizeAt)
		{
			const Uint64 now = SDL_GetTicks();
			timeout = W.resizeAt > now ? (Sint32)(W.resizeAt - now) : 0;
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
						if (W.barHover)
						{
							W.barHover = FALSE;
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
