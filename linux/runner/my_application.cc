#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// MHRD: одна копія програми на користувача (GApplication через D-Bus). Повторний запуск, зокрема
// ярлик ПК `mhrd --connect <id>`, передає аргументи вже відкритій копії, а вона — у Dart каналом
// «mhrd/shell» (метод `connect`), як на Windows. Портативна версія (portable.txt поруч із програмою
// чи з файлом AppImage) має свій ідентифікатор для кожного шляху — і свою окрему копію.

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* shell;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "MHRD");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "MHRD");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // Піктограма — mhrd.png поруч із програмою (кладе linux/CMakeLists.txt).
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    g_autofree gchar* icon = g_build_filename(dir, "mhrd.png", nullptr);
    gtk_window_set_icon_from_file(window, icon, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->shell = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "mhrd/shell",
      FL_METHOD_CODEC(codec));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::command_line — і перший запуск, і аргументи від повторних запусків.
static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  gint argc = 0;
  g_auto(GStrv) argv = g_application_command_line_get_arguments(command_line, &argc);
  if (self->window == nullptr) {
    // Перший запуск: аргументи (без імені програми) бачить main() у Dart.
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    self->dart_entrypoint_arguments = g_strdupv(argc > 0 ? argv + 1 : argv);
    g_application_activate(application);
    return 0;
  }
  gtk_window_present(self->window);
  for (gint i = 1; i + 1 < argc; i++) {
    if (g_strcmp0(argv[i], "--connect") == 0 && self->shell != nullptr) {
      g_autoptr(FlValue) id = fl_value_new_string(argv[i + 1]);
      fl_method_channel_invoke_method(self->shell, "connect", id, nullptr,
                                      nullptr, nullptr);
      break;
    }
  }
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->shell);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

// Портативна версія: portable.txt поруч із файлом AppImage (змінна APPIMAGE) або з програмою.
// Повертає шлях, за яким її розпізнали (для окремого ідентифікатора), або nullptr.
static gchar* portable_path() {
  const gchar* appimage = g_getenv("APPIMAGE");
  g_autofree gchar* exe = appimage != nullptr
                              ? g_strdup(appimage)
                              : g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return nullptr;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* marker = g_build_filename(dir, "portable.txt", nullptr);
  return g_file_test(marker, G_FILE_TEST_EXISTS) ? g_steal_pointer(&exe) : nullptr;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  g_autofree gchar* app_id = g_strdup(APPLICATION_ID);
  g_autofree gchar* portable = portable_path();
  if (portable != nullptr) {
    // Ідентифікатор D-Bus: частина не може починатися з цифри — тому «p» попереду.
    guint32 hash = 2166136261u;  // FNV-1a
    for (const guchar* p = reinterpret_cast<const guchar*>(portable); *p; p++) {
      hash = (hash ^ *p) * 16777619u;
    }
    g_free(app_id);
    app_id = g_strdup_printf("%s.p%08x", APPLICATION_ID, hash);
  }

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", app_id, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE, nullptr));
}
