#ifndef WEBKIT_MULTI_VIEW_PLUGIN_H_
#define WEBKIT_MULTI_VIEW_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

#define WEBKIT_MULTI_VIEW_TYPE_PLUGIN (webkit_multi_view_plugin_get_type())
G_DECLARE_FINAL_TYPE(WebkitMultiViewPlugin, webkit_multi_view_plugin,
                      WEBKIT_MULTI_VIEW, PLUGIN, GObject)

// `registrar` gives us the method channel (see
// multiwhatsappweb/webkit_view in linux_webkit_platform_view.dart).
// `container` is a GtkFixed layered ON TOP of the FlView (via a
// GtkOverlay — see my_application.cc) that every account's WebKitWebView
// gets placed into at whatever x/y/width/height Flutter reports its
// content pane occupies.
// `flutter_view` is the FlView widget itself — needed so HandleSetVisible
// can explicitly hand keyboard focus back to Flutter when a native
// WebKitWebView is hidden (see .cc for why this matters: hiding a
// GTK widget that currently holds keyboard focus does NOT automatically
// return focus to anything else, so Flutter TextFields in dialogs shown
// right after pauseRendering() would otherwise never receive keystrokes).
WebkitMultiViewPlugin* webkit_multi_view_plugin_new(FlPluginRegistrar* registrar,
                                                     GtkFixed* container,
                                                     GtkWidget* flutter_view);

G_END_DECLS

#endif  // WEBKIT_MULTI_VIEW_PLUGIN_H_