#include "webkit_multi_view_plugin.h"

#include <webkit2/webkit2.h>

#include <map>
#include <string>

// PRD §24 — the real Linux isolation primitive lives here:
// webkit_website_data_manager_new() with a distinct base-data-directory
// per account gives each WebKitWebView its own cookies, localStorage,
// IndexedDB, service workers, etc. — a completely separate on-disk
// profile, the same guarantee the earlier external-Chrome-process
// approach had, but now actually embedded in the app window instead of
// opening a separate OS window.
//
// This plugin is intentionally NOT a generic "webview" abstraction (no
// JS bridge, no navigation-delegate callbacks beyond load/reload) —
// only what LinuxWebViewAdapter (Dart side) actually needs:
// create / setGeometry / setVisible / reload / destroy.

#define WEBKIT_MULTI_VIEW_METHOD_CHANNEL "multi_whatsapp_web/webkit_view"

// Cached last-applied geometry/visibility per view, so redundant
// setGeometry/setVisible calls (e.g. the Dart-side poll firing every
// 200ms even though nothing moved) turn into no-ops here too instead of
// forcing GTK to re-run gtk_fixed_move()/gtk_widget_set_size_request()
// on the WebKitWebView every time. Those two GTK calls queue a resize
// unconditionally regardless of whether the values changed, and a
// WebKitWebView resize forces the page (including any focused
// contenteditable, like WhatsApp Web's message box) to re-layout — doing
// that continuously while the user types is what caused the reported
// typing lag. This is defense-in-depth on top of the Dart-side diff in
// webview_container.dart, in case any other caller is added later.
struct ViewGeometry {
    gint x = 0;
    gint y = 0;
    gint w = 0;
    gint h = 0;
    bool visible = true;
    bool has_geometry = false;
};

struct _WebkitMultiViewPlugin {
    GObject parent_instance;
    FlMethodChannel* channel;
    GtkFixed* container;  // unowned — owned by my_application.cc's overlay
    std::map<std::string, WebKitWebView*>* views;
    std::map<std::string, ViewGeometry>* geometry;
};

G_DEFINE_TYPE(WebkitMultiViewPlugin, webkit_multi_view_plugin, G_TYPE_OBJECT)

namespace {

    std::string GetString(FlValue* args, const char* key) {
        FlValue* v = fl_value_lookup_string(args, key);
        if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return "";
        return std::string(fl_value_get_string(v));
    }

    double GetNumber(FlValue* args, const char* key) {
        FlValue* v = fl_value_lookup_string(args, key);
        if (v == nullptr) return 0.0;
        if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
        if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(v));
        return 0.0;
    }

}  // namespace

static FlMethodResponse* HandleCreate(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    const std::string data_dir = GetString(args, "dataDir");
    const std::string url = GetString(args, "url");

    if (self->views->count(view_id)) {
        // Already created (e.g. app hot-restarted the Dart side but the
        // native widget survived) — just (re)navigate instead of duplicating.
        webkit_web_view_load_uri((*self->views)[view_id], url.c_str());
        return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }

    // REVERTED: a webkit_website_data_manager_set_memory_pressure_settings()
    // call with a 320MB memory_limit was tried here to rein in
    // WebKitWebProcess memory. Measured result on real usage: memory went
    // UP (1.1GB -> 1.4GB), not down, with the same accounts open. Best
    // explanation: `memory_limit` isn't a hard cap — it's the baseline
    // WebKit's internal conservative/strict/kill thresholds are computed
    // against, and WhatsApp Web's own JS/DOM footprint legitimately needs
    // more than 320MB just to run. Set too low, the WebProcess likely hit
    // "conservative"/"strict" pressure constantly and kept evicting +
    // immediately re-decoding/re-allocating the same resources — that
    // repeated churn fragments the heap and can push RSS higher than just
    // leaving the cache alone. Not re-adding this without being able to
    // tune the limit against real, measured steady-state usage on the
    // actual machine.

    g_autoptr(WebKitWebsiteDataManager) data_manager = webkit_website_data_manager_new(
            "base-data-directory", data_dir.c_str(),
            "base-cache-directory", data_dir.c_str(),
            nullptr);
    WebKitWebContext* web_context =
            webkit_web_context_new_with_website_data_manager(data_manager);

    // FINAL: disabled. Confirmed by testing on this machine — sandbox
    // enabled (TRUE) breaks outbound networking here both at initial load
    // ("Network is unreachable") and later at message-send time (Enter
    // silently not sending, almost certainly the WhatsApp Web WebSocket
    // failing under the same broken sandbox networking). Sandbox disabled
    // (FALSE) loads and sends normally. The earlier GObject
    // `invalid (NULL) pointer instance` / freeze-after-send issue this
    // was toggled to help isolate turned out to be a separate, unrelated
    // problem — missing GStreamer audio plugins (autoaudiosink) on the
    // system, now fixed at the OS level — so there's no remaining reason
    // to keep the sandbox on for this machine. Does not affect the
    // per-account cookie/storage isolation above, which is a completely
    // separate mechanism (WebKitWebsiteDataManager).
    webkit_web_context_set_sandbox_enabled(web_context, FALSE);

    // FIX (bug: WebKitWebProcess ballooning to ~1GB per account): no
    // cache model was ever set, so WebKitGTK defaulted to
    // WEBKIT_CACHE_MODEL_WEB_BROWSER — a cache budget sized for someone
    // browsing many different sites/tabs (large in-memory object cache,
    // large page-cache budget, etc). This WebView only ever shows ONE
    // page (web.whatsapp.com) for the life of the process —
    // WEBKIT_CACHE_MODEL_DOCUMENT_VIEWER is the model WebKit itself
    // recommends for exactly that shape of usage, and cuts the in-memory
    // cache footprint dramatically. (See the memory-pressure-settings
    // block above for the other big contributor to the same bug.)
    webkit_web_context_set_cache_model(web_context,
            WEBKIT_CACHE_MODEL_DOCUMENT_VIEWER);

    GtkWidget* webview = webkit_web_view_new_with_context(web_context);

    // IMPORTANT: settings — especially hardware_acceleration_policy — are
    // configured here, BEFORE gtk_widget_show()/gtk_fixed_put() realize
    // this widget. Realizing it is what makes WebKitGTK actually spawn
    // the WebProcess and set up its compositor; configuring settings
    // afterward let the WebProcess start under the OLD policy and then
    // get reconfigured mid-init, which left it in an inconsistent
    // internal state — that mismatch is the likely cause of the
    // `GLib-GObject-CRITICAL: invalid (NULL) pointer instance` /
    // `g_signal_connect_data` crash seen in WebKitWebProcess. Doing this
    // before realize means the WebProcess is spawned with the final
    // policy from the start, no reconfiguration involved.
    //
    // Perf/stability history on hardware_acceleration_policy (kept here
    // so the next person doesn't re-try the same two things):
    //  - ALWAYS: forces GPU compositing inside a plain Cairo-composited
    //    GtkOverlay (see my_application.cc) — causes an expensive
    //    GPU->CPU readback on every repaint, most visible right after
    //    sending a message (chat list updates + auto-scrolls).
    //  - ON_DEMAND: lets WebKitGTK create/tear down its OWN EGL context
    //    dynamically mid-session — that new context contends with the
    //    Flutter Linux embedder's own EGL/GLES context in the same
    //    process and crashed the whole app (`eglMakeCurrent failed` ->
    //    `FlutterEngineRemoveView` -> lost connection to device).
    //  - ON_DEMAND (current — being retried specifically for memory):
    //    NEVER forces ALL rendering, including every image/thumbnail/
    //    video-frame WhatsApp Web decodes, through software (CPU)
    //    rasterization — meaning every one of those has to sit in system
    //    RAM as a raw decoded bitmap instead of a compact GPU texture.
    //    For a media-heavy page like WhatsApp Web, this is a very
    //    plausible major contributor to the ~1GB-per-account
    //    WebKitWebProcess memory that prompted this investigation. Per
    //    the note above, the ordering bug (not ON_DEMAND itself) is
    //    believed to have been the real cause of the earlier
    //    `eglMakeCurrent failed` crash, and that bug is now fixed
    //    (settings applied before widget realize). If that crash message
    //    reappears in the terminal (or the whole app loses its connection
    //    to the display), revert this single line back to
    //    WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER immediately — that
    //    would mean the ordering theory was wrong, not just incomplete.
    WebKitSettings* webkit_settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview));
    webkit_settings_set_hardware_acceleration_policy(
            webkit_settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_ON_DEMAND);
    webkit_settings_set_enable_smooth_scrolling(webkit_settings, TRUE);
    // FIX (memory): was TRUE. Page/back-forward cache exists to make
    // switching BETWEEN distinct pages instant by keeping fully-rendered
    // previous pages resident in memory. WhatsApp Web is a single-page
    // app that never navigates to a different page for the life of the
    // session, so this was pure overhead with no benefit here — one more
    // contributor to the ~1GB-per-account WebKitWebProcess memory usage.
    webkit_settings_set_enable_page_cache(webkit_settings, FALSE);
    // DIAGNOSTIC flag from an earlier attachment-upload-speed investigation
    // — turned back OFF now that it's done. Left TRUE, this keeps Web
    // Inspector's supporting structures resident in every WebProcess for
    // no reason, which was also feeding the high per-account memory usage
    // reported via system monitor. Re-enable only temporarily, per-account,
    // when actually debugging with Inspect Element.
    webkit_settings_set_enable_developer_extras(webkit_settings, FALSE);
    webkit_settings_set_enable_write_console_messages_to_stdout(webkit_settings, FALSE);
    // NOTE (reverted — do not re-add): a Chrome-spoofed User-Agent was
    // tried here to stop WhatsApp Web's UA sniffing from reporting
    // "Safari", but that caused WA Web's JS to assume genuine
    // Chromium/V8-only capabilities that this engine
    // (WebKitGTK/JavaScriptCore) doesn't actually have, which froze the
    // WA Web content permanently once it hit a Chrome-only code path.
    // WhatsApp Web officially supports Safari, and the default WebKitGTK
    // UA genuinely matches the engine underneath it (real WebKit), so
    // leaving the UA at its default is correct here.

    gtk_widget_set_size_request(webview, 1, 1);
    gtk_fixed_put(self->container, webview, 0, 0);
    gtk_widget_show(webview);

    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(webview), url.c_str());

    (*self->views)[view_id] = WEBKIT_WEB_VIEW(webview);
    (*self->geometry)[view_id] = ViewGeometry{};
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

static FlMethodResponse* HandleSetGeometry(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    auto it = self->views->find(view_id);
    if (it == self->views->end()) {
        return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    const gint x = static_cast<gint>(GetNumber(args, "x"));
    const gint y = static_cast<gint>(GetNumber(args, "y"));
    const gint w = static_cast<gint>(GetNumber(args, "width"));
    const gint h = static_cast<gint>(GetNumber(args, "height"));

    // Skip the GTK calls entirely if nothing actually changed. gtk_fixed_move
    // and gtk_widget_set_size_request both unconditionally queue a resize —
    // calling them with identical values still forces WebKitGTK to re-run
    // page layout, which is what produced visible lag while typing when this
    // was being invoked on every geometry-poll tick regardless of change.
    auto& geo = (*self->geometry)[view_id];
    if (geo.has_geometry && geo.x == x && geo.y == y && geo.w == w && geo.h == h) {
        return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    geo.x = x;
    geo.y = y;
    geo.w = w;
    geo.h = h;
    geo.has_geometry = true;

    GtkWidget* widget = GTK_WIDGET(it->second);
    gtk_fixed_move(self->container, widget, x, y);
    gtk_widget_set_size_request(widget, w, h);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* HandleSetVisible(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    FlValue* visible_value = fl_value_lookup_string(args, "visible");
    const bool visible = visible_value != nullptr && fl_value_get_bool(visible_value);
    auto it = self->views->find(view_id);
    if (it != self->views->end()) {
        auto geo_it = self->geometry->find(view_id);
        if (geo_it != self->geometry->end() && geo_it->second.visible == visible) {
            return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        }
        if (geo_it != self->geometry->end()) geo_it->second.visible = visible;
        gtk_widget_set_visible(GTK_WIDGET(it->second), visible);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* HandleReload(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    auto it = self->views->find(view_id);
    if (it != self->views->end()) {
        // Extra memory-reclaim step alongside the reload itself: clear only
        // the on-disk/in-memory HTTP cache (WEBKIT_WEBSITE_DATA_DISK_CACHE).
        // This deliberately does NOT touch cookies, localStorage, IndexedDB,
        // or service workers — WhatsApp Web's login/session state lives in
        // those, not in the HTTP cache, so this never logs the account out.
        // Fire-and-forget (NULL callback) is intentional: this is routine
        // cleanup piggybacked on a reload the user/timer already triggered,
        // not an operation anything needs to block on or react to finishing.
        WebKitWebContext* context = webkit_web_view_get_context(it->second);
        WebKitWebsiteDataManager* data_manager =
                webkit_web_context_get_website_data_manager(context);
        webkit_website_data_manager_clear(data_manager, WEBKIT_WEBSITE_DATA_DISK_CACHE,
                0, nullptr, nullptr, nullptr);
        webkit_web_view_reload(it->second);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* HandleDestroy(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    auto it = self->views->find(view_id);
    if (it != self->views->end()) {
        gtk_widget_destroy(GTK_WIDGET(it->second));
        self->views->erase(it);
        self->geometry->erase(view_id);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void MethodCallCb(FlMethodChannel* /*channel*/, FlMethodCall* method_call,
        gpointer user_data) {
    WebkitMultiViewPlugin* self = WEBKIT_MULTI_VIEW_PLUGIN(user_data);
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    g_autoptr(FlMethodResponse) response = nullptr;
    if (g_strcmp0(method, "create") == 0) {
        response = HandleCreate(self, args);
    } else if (g_strcmp0(method, "setGeometry") == 0) {
        response = HandleSetGeometry(self, args);
    } else if (g_strcmp0(method, "setVisible") == 0) {
        response = HandleSetVisible(self, args);
    } else if (g_strcmp0(method, "reload") == 0) {
        response = HandleReload(self, args);
    } else if (g_strcmp0(method, "destroy") == 0) {
        response = HandleDestroy(self, args);
    } else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    g_autoptr(GError) error = nullptr;
    if (!fl_method_call_respond(method_call, response, &error)) {
        g_warning("Failed to send webkit_view method response: %s", error->message);
    }
}

static void webkit_multi_view_plugin_dispose(GObject* object) {
    WebkitMultiViewPlugin* self = WEBKIT_MULTI_VIEW_PLUGIN(object);
    g_clear_object(&self->channel);
    delete self->views;
    delete self->geometry;
    G_OBJECT_CLASS(webkit_multi_view_plugin_parent_class)->dispose(object);
}

static void webkit_multi_view_plugin_class_init(WebkitMultiViewPluginClass* klass) {
    G_OBJECT_CLASS(klass)->dispose = webkit_multi_view_plugin_dispose;
}

static void webkit_multi_view_plugin_init(WebkitMultiViewPlugin* self) {
    self->views = new std::map<std::string, WebKitWebView*>();
    self->geometry = new std::map<std::string, ViewGeometry>();
}

WebkitMultiViewPlugin* webkit_multi_view_plugin_new(FlPluginRegistrar* registrar,
        GtkFixed* container) {
    WebkitMultiViewPlugin* self = WEBKIT_MULTI_VIEW_PLUGIN(
            g_object_new(webkit_multi_view_plugin_get_type(), nullptr));
    self->container = container;

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    self->channel = fl_method_channel_new(
            fl_plugin_registrar_get_messenger(registrar),
            WEBKIT_MULTI_VIEW_METHOD_CHANNEL,
            FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(self->channel, MethodCallCb,
            g_object_ref(self), g_object_unref);

    return self;
}