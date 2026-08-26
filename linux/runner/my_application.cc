#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "webkit_multi_view_plugin.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// FIX (window/taskbar icon never changes): nothing in this file ever
// called gtk_window_set_icon*() — the AppImage's icon.png only affects
// the .desktop launcher entry (app grid / file manager), completely
// separate from what GTK shows for the actual RUNNING window (title
// bar, taskbar/dock, Alt-Tab), which was falling back to a generic
// default. This resolves the icon relative to the running executable's
// own location (via /proc/self/exe) rather than a hardcoded install
// path, so it works the same way whether launched via `flutter run`,
// the raw `build/linux/x64/*/bundle` binary, or from inside an
// AppImage's temporary mount — see the matching CMakeLists.txt change
// that installs icon.png into the bundle's `data/` directory right
// next to where this looks for it.
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return;
  g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
  g_autofree gchar* icon_path =
      g_build_filename(exe_dir, "data", "icon.png", nullptr);

  g_autoptr(GError) error = nullptr;
  if (!gtk_window_set_icon_from_file(window, icon_path, &error)) {
    g_warning("Could not load app icon from %s: %s", icon_path,
              error ? error->message : "unknown error");
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  set_window_icon(window);

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
    gtk_header_bar_set_title(header_bar, "multi_whatsapp_web");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "multi_whatsapp_web");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  // PRD §24 Linux embedding: a GtkOverlay lets us layer native
  // WebKitWebViews ON TOP of the FlView, positioned/sized to exactly
  // match wherever Flutter's own layout says the active account's
  // content pane currently is (see linux_webkit_platform_view.dart on
  // the Dart side, which keeps this in sync every frame). The FlView
  // itself still renders 100% of the Flutter UI (sidebar, chrome,
  // placeholders) underneath/around it — only the specific rectangle
  // Flutter reserves for the webview gets visually covered by the real
  // WebKitWebView sitting in the fixed_layer below.
  GtkOverlay* overlay = GTK_OVERLAY(gtk_overlay_new());
  gtk_widget_show(GTK_WIDGET(overlay));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(overlay));

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));

  GtkFixed* fixed_layer = GTK_FIXED(gtk_fixed_new());
  gtk_widget_show(GTK_WIDGET(fixed_layer));
  gtk_overlay_add_overlay(overlay, GTK_WIDGET(fixed_layer));
  // GtkOverlay by default has its overlay children capture ALL pointer
  // events across their entire allocation (which, for fixed_layer, is
  // the whole window — GtkFixed has no intrinsic size so it's stretched
  // to fill the overlay). Without pass-through, every click anywhere —
  // including over the Flutter sidebar, buttons, dialogs, etc. — is
  // swallowed by this empty layer before it ever reaches the FlView
  // underneath. Setting pass-through TRUE makes GTK only route events to
  // fixed_layer's actual children (the WebKitWebViews placed via
  // gtk_fixed_put below); everywhere else, events fall through to FlView.
  gtk_overlay_set_overlay_pass_through(overlay, GTK_WIDGET(fixed_layer), TRUE);

  // The desktop shell intentionally runs a single native WebKit runtime
  // (linux/webkit_multi_view_plugin.cc). The generic
  // flutter_inappwebview_linux plugin is not compatible with that setup, so
  // disable its Linux registration before Flutter registers the rest of the
  // plugins.
  g_setenv("MULTI_WHATSAPP_WEB_DISABLE_INAPPWEBVIEW_LINUX", "1", TRUE);
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // webkit_multi_view_plugin isn't a pub.dev package (no entry in
  // generated_plugin_registrant.cc), so it's registered manually here,
  // same mechanism real plugins use under the hood.
  FlPluginRegistrar* webkit_registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(view),
                                                   "WebkitMultiViewPlugin");
  webkit_multi_view_plugin_new(webkit_registrar, fixed_layer);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
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
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}