/* Android: власного вікна немає — сеанс показує застосунок (екран сеансу у Flutter), картинка йде
 * через спільну пам'ять (shm.c). window_init відмовляє, і main.c працює в режимі без вікна. */
#include "window_sdl.h"

BOOL window_init(const WindowConfig* cfg, const WindowHost* host)
{
	(void)cfg;
	(void)host;
	return FALSE;
}

uint32_t window_monitors(WindowMonitor* out, uint32_t max)
{
	(void)out;
	(void)max;
	return 0;
}

void window_run(void)
{
}

void window_shutdown(void)
{
}

void window_post_surface(void)
{
}

void window_post_frame(int x, int y, int w, int h)
{
	(void)x;
	(void)y;
	(void)w;
	(void)h;
}

void window_post_focus(void)
{
}

void window_post_reconnecting(int attempt)
{
	(void)attempt;
}

void window_post_latency(int ms)
{
	(void)ms;
}

void window_post_quit(void)
{
}
