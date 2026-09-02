#include "webkit_multi_view_plugin.h"
#include <webkit2/webkit2.h>
#include <map>
#include <set>
#include <string>
#include <malloc.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <unistd.h>
#include <sys/types.h>

#define WEBKIT_MULTI_VIEW_METHOD_CHANNEL "multi_whatsapp_web/webkit_view"

// Berapa lama akun harus tersembunyi sebelum benar-benar kita "suspend"
// (unload) ke about:blank. Delay ini mencegah reload penuh setiap kali
// user pindah-pindah akun dengan cepat.
#define SUSPEND_DELAY_SECONDS 30

// Interval pengecekan RSS asli tiap WebProcess lewat /proc.
#define MEMORY_WATCHDOG_INTERVAL_SECONDS 60

// Ambang RSS per akun (WebProcess) yang memicu auto-reload dari SISI LUAR
// (via /proc, dicek tiap MEMORY_WATCHDOG_INTERVAL_SECONDS). Sekarang ini
// cuma jaring pengaman KEDUA — pertahanan utama ada di
// WEB_PROCESS_MEMORY_LIMIT_MB / *_THRESHOLD di bawah, yang membuat WebKit
// SENDIRI membunuh WebProcess-nya begitu lewat batas (lebih presisi &
// lebih cepat daripada polling /proc setiap 60 detik).
#define MEMORY_RELOAD_THRESHOLD_BYTES (600LL * 1024 * 1024)

// Jangan reload akun yang sama dua kali dalam jendela waktu ini, supaya
// tidak terjadi reload berulang selagi proses lama masih benar-benar exit.
#define MEMORY_RELOAD_COOLDOWN_SECONDS 300

// --- Hard cap asli WebKit, per WebProcess ---
// Ini pagar utama untuk menekan total RAM. WebKit punya monitor memori
// INTERNAL (WebKitMemoryPressureSettings) yang jauh lebih akurat & lebih
// cepat daripada kita polling /proc dari luar. Begitu WebProcess lewat
// WEB_PROCESS_KILL_THRESHOLD_FRACTION * WEB_PROCESS_MEMORY_LIMIT_MB,
// WebKit akan membunuh WebProcess itu sendiri (reason:
// WEBKIT_WEB_PROCESS_EXCEEDED_MEMORY_LIMIT), lalu kita tangkap sinyal
// "web-process-terminated" dan langsung load_uri ulang untuk spawn
// WebProcess baru yang bersih. Efeknya: RAM per akun praktis TIDAK PERNAH
// jauh melewati angka ini, bukan cuma "biasanya segini".
//
// Turunkan angka ini kalau mau RAM lebih hemat lagi (dengan konsekuensi
// akun akan lebih sering "kick & reload" saat dipakai berat — chat besar,
// banyak media, panggilan suara/video).
#define WEB_PROCESS_MEMORY_LIMIT_MB 300
#define WEB_PROCESS_CONSERVATIVE_THRESHOLD 0.5   // mulai buang cache non-kritis
#define WEB_PROCESS_STRICT_THRESHOLD 0.75         // mulai buang memori kritis
#define WEB_PROCESS_KILL_THRESHOLD 1.0            // >= 300MB -> proses dibunuh & di-respawn
#define WEB_PROCESS_MEMORY_POLL_INTERVAL_SECONDS 10.0 // WebKit cek RSS internal tiap 10 detik

struct ViewGeometry {
    gint x = 0;
    gint y = 0;
    gint w = 0;
    gint h = 0;
    bool visible = true;
    bool has_geometry = false;

    // --- Ditambahkan untuk fix RAM ---
    std::string url;              // URL asli, dipakai untuk reload saat resume
    bool suspended = false;       // true kalau WebView sedang di-unload ke about:blank
    guint suspend_timeout_id = 0; // id g_timeout_add yang menunda proses suspend

    // --- Watchdog RSS asli per akun ---
    pid_t web_process_pid = 0;     // PID WebKitWebProcess milik view ini, 0 = belum ketemu
    gint64 last_reload_unix = 0;   // waktu (detik) reload otomatis terakhir, untuk cooldown
};

struct _WebkitMultiViewPlugin {
    GObject parent_instance;
    FlMethodChannel* channel;
    GtkFixed* container;
    std::map<std::string, WebKitWebView*>* views;
    std::map<std::string, ViewGeometry>* geometry;
    std::set<pid_t>* assigned_pids;   // PID WebProcess yang sudah "diklaim" oleh sebuah view
    guint memory_watchdog_id = 0;
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

    // Data yang dibawa oleh callback g_timeout_add untuk suspend tertunda.
    struct PendingSuspend {
        WebkitMultiViewPlugin* self;
        std::string view_id;
    };

    void CancelPendingSuspend(WebkitMultiViewPlugin* self, const std::string& view_id) {
        auto git = self->geometry->find(view_id);
        if (git != self->geometry->end() && git->second.suspend_timeout_id != 0) {
            g_source_remove(git->second.suspend_timeout_id);
            git->second.suspend_timeout_id = 0;
        }
    }

    // Baca "/proc/<pid>/status" untuk mendapatkan Name: dan PPid:.
    bool ReadProcStatus(pid_t pid, std::string* name, pid_t* ppid) {
        char path[64];
        snprintf(path, sizeof(path), "/proc/%d/status", pid);
        FILE* f = fopen(path, "r");
        if (!f) return false;
        char line[256];
        bool got_name = false, got_ppid = false;
        while (fgets(line, sizeof(line), f)) {
            if (!got_name && strncmp(line, "Name:", 5) == 0) {
                char buf[128] = {0};
                sscanf(line + 5, "%127s", buf);
                *name = buf;
                got_name = true;
            } else if (!got_ppid && strncmp(line, "PPid:", 5) == 0) {
                *ppid = static_cast<pid_t>(atoi(line + 5));
                got_ppid = true;
            }
            if (got_name && got_ppid) break;
        }
        fclose(f);
        return got_name && got_ppid;
    }

    // Baca VmRSS (KB) dari "/proc/<pid>/status".
    long ReadProcRssKb(pid_t pid) {
        char path[64];
        snprintf(path, sizeof(path), "/proc/%d/status", pid);
        FILE* f = fopen(path, "r");
        if (!f) return -1;
        long rss_kb = -1;
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "VmRSS:", 6) == 0) {
                sscanf(line + 6, "%ld", &rss_kb);
                break;
            }
        }
        fclose(f);
        return rss_kb;
    }

    // Cari PID WebKitWebProcess baru yang anak dari proses kita sendiri dan
    // belum "diklaim" view lain. Dipanggil sesaat setelah create/load_uri,
    // saat WebProcess untuk view tersebut baru saja spawn. WebKitGTK tidak
    // punya API publik untuk memetakan WebView -> pid secara langsung, jadi
    // ini heuristik "yang terbaru & belum diklaim" — cukup andal selama
    // pembuatan akun tidak terjadi race dalam hitungan milidetik yang sama.
    pid_t FindUnclaimedWebProcessPid(std::set<pid_t>* assigned_pids) {
        pid_t my_pid = getpid();
        DIR* proc = opendir("/proc");
        if (!proc) return 0;
        pid_t best = 0;
        struct dirent* entry;
        while ((entry = readdir(proc)) != nullptr) {
            if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
            pid_t pid = static_cast<pid_t>(atoi(entry->d_name));
            if (pid <= 0 || assigned_pids->count(pid)) continue;
            std::string name;
            pid_t ppid = 0;
            if (!ReadProcStatus(pid, &name, &ppid)) continue;
            if (ppid != my_pid) continue;
            // Nama proses di /proc dipotong ~15 char: "WebKitWebProce".
            if (name.rfind("WebKitWebProce", 0) == 0) {
                if (pid > best) best = pid; // ambil yang PID-nya terbesar (paling baru)
            }
        }
        closedir(proc);
        return best;
    }

    gboolean SuspendCallback(gpointer data) {
        PendingSuspend* pending = static_cast<PendingSuspend*>(data);
        WebkitMultiViewPlugin* self = pending->self;

        auto vit = self->views->find(pending->view_id);
        auto git = self->geometry->find(pending->view_id);
        if (vit != self->views->end() && git != self->geometry->end()) {
            ViewGeometry& geo = git->second;
            geo.suspend_timeout_id = 0;
            if (!geo.suspended) {
                // Ini fix intinya: benar-benar lepaskan JS heap / DOM WhatsApp
                // Web dengan menavigasi ke halaman kosong. Menyembunyikan
                // widget saja (gtk_widget_set_visible) TIDAK membebaskan
                // memori WebProcess sama sekali.
                webkit_web_view_load_uri(vit->second, "about:blank");
                geo.suspended = true;
            }
        }
        delete pending;
        return G_SOURCE_REMOVE;
    }

    struct PendingPidResolve {
        WebkitMultiViewPlugin* self;
        std::string view_id;
        int attempts_left;
    };

    // Dipakai untuk callback sinyal "web-process-terminated" milik tiap view.
    struct TerminationCallbackData {
        WebkitMultiViewPlugin* self;
        std::string view_id;
    };

    gboolean ResolvePidCallback(gpointer data); // forward decl, dipakai di OnWebProcessTerminated

    void FreeTerminationData(gpointer data, GClosure*) {
        delete static_cast<TerminationCallbackData*>(data);
    }

    // Dipanggil WebKit saat WebProcess mati abnormal — termasuk saat WebKit
    // SENDIRI membunuhnya karena lewat WEB_PROCESS_KILL_THRESHOLD (lihat
    // OnWebProcessTerminated). Ini yang membuat batas RAM di atas benar-benar
    // "keras": begitu proses lama mati, kita langsung load_uri lagi supaya
    // akun tetap terasa nyambung (bukan cuma diam menampilkan halaman kosong).
    void OnWebProcessTerminated(WebKitWebView* web_view,
                                 WebKitWebProcessTerminationReason reason,
                                 gpointer user_data) {
        TerminationCallbackData* data = static_cast<TerminationCallbackData*>(user_data);
        WebkitMultiViewPlugin* self = data->self;
        auto git = self->geometry->find(data->view_id);
        if (git == self->geometry->end()) return;
        ViewGeometry& geo = git->second;

        if (reason == WEBKIT_WEB_PROCESS_EXCEEDED_MEMORY_LIMIT ||
            reason == WEBKIT_WEB_PROCESS_CRASHED) {
            // Proses lama sudah mati total — kalau view ini sedang disembunyikan
            // (suspended ke about:blank), biarkan saja, tidak perlu buru-buru
            // memuat ulang WhatsApp Web di background. Kalau sedang dipakai
            // (tidak suspended), reconnect langsung supaya user tidak melihat
            // halaman kosong.
            if (!geo.suspended) {
                webkit_web_view_load_uri(web_view, geo.url.c_str());
            }
            // PID lama sudah tidak valid, watchdog /proc perlu mencari ulang.
            if (geo.web_process_pid > 0) {
                self->assigned_pids->erase(geo.web_process_pid);
                geo.web_process_pid = 0;
            }
            PendingPidResolve* pending = new PendingPidResolve{self, data->view_id, 10};
            g_timeout_add(300, ResolvePidCallback, pending);
        }
    }

    gboolean ResolvePidCallback(gpointer data) {
        PendingPidResolve* pending = static_cast<PendingPidResolve*>(data);
        WebkitMultiViewPlugin* self = pending->self;
        auto git = self->geometry->find(pending->view_id);
        if (git == self->geometry->end()) {
            delete pending;
            return G_SOURCE_REMOVE;
        }
        pid_t pid = FindUnclaimedWebProcessPid(self->assigned_pids);
        if (pid > 0) {
            git->second.web_process_pid = pid;
            self->assigned_pids->insert(pid);
            delete pending;
            return G_SOURCE_REMOVE;
        }
        // WebProcess kadang belum sempat spawn saat pertama dicek — coba lagi
        // beberapa kali dengan jeda pendek sebelum menyerah.
        pending->attempts_left--;
        if (pending->attempts_left <= 0) {
            delete pending;
            return G_SOURCE_REMOVE;
        }
        return G_SOURCE_CONTINUE;
    }

    // Dipanggil tiap MEMORY_WATCHDOG_INTERVAL_SECONDS untuk semua view: baca
    // VmRSS asli WebProcess-nya, dan kalau sudah lewat ambang, reload akun
    // itu (bukan tebak-tebakan timer tetap seperti sebelumnya).
    gboolean MemoryWatchdogCallback(gpointer data) {
        WebkitMultiViewPlugin* self = static_cast<WebkitMultiViewPlugin*>(data);
        gint64 now = static_cast<gint64>(g_get_real_time() / G_USEC_PER_SEC);

        for (auto& kv : *self->views) {
            const std::string& view_id = kv.first;
            WebKitWebView* view = kv.second;
            auto git = self->geometry->find(view_id);
            if (git == self->geometry->end()) continue;
            ViewGeometry& geo = git->second;

            if (geo.suspended || geo.web_process_pid <= 0) continue;
            if (webkit_web_view_is_loading(view)) continue;
            if (now - geo.last_reload_unix < MEMORY_RELOAD_COOLDOWN_SECONDS) continue;

            long rss_kb = ReadProcRssKb(geo.web_process_pid);
            if (rss_kb < 0) {
                // PID sudah tidak ada (proses ganti karena reload/crash) —
                // lepaskan supaya ResolvePidCallback berikutnya bisa dipanggil
                // ulang lewat create/reload.
                self->assigned_pids->erase(geo.web_process_pid);
                geo.web_process_pid = 0;
                continue;
            }
            if (static_cast<gint64>(rss_kb) * 1024 >= MEMORY_RELOAD_THRESHOLD_BYTES) {
                // webkit_web_view_reload() menavigasi ulang di WebProcess yang
                // SAMA (bukan proses baru), jadi pid yang sudah kita catat
                // tetap valid — cukup catat waktu reload untuk cooldown.
                webkit_web_view_reload(view);
                geo.last_reload_unix = now;
            }
        }
        return G_SOURCE_CONTINUE;
    }
}

// --- FUNGSI DESTROY HARUS DI ATAS ---
static FlMethodResponse* HandleDestroy(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    CancelPendingSuspend(self, view_id);
    auto it = self->views->find(view_id);
    if (it != self->views->end()) {
        WebKitWebView* webview = it->second;

        // Paksa hentikan proses WebProcess milik view ini (ini yang benar-benar
        // membebaskan RAM, karena WebProcess adalah proses OS terpisah).
        webkit_web_view_terminate_web_process(webview);

        auto git = self->geometry->find(view_id);
        if (git != self->geometry->end() && git->second.web_process_pid > 0) {
            self->assigned_pids->erase(git->second.web_process_pid);
        }

        gtk_widget_destroy(GTK_WIDGET(webview));
        self->views->erase(it);
        self->geometry->erase(view_id);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* HandleCreate(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    const std::string data_dir = GetString(args, "dataDir");
    const std::string url = GetString(args, "url");

    if (self->views->count(view_id)) {
        HandleDestroy(self, args);
    }

    // Hard cap RAM per WebProcess, ditegakkan oleh WebKit sendiri (bukan
    // cuma "saran buang cache" seperti versi sebelumnya). Begitu WebProcess
    // lewat WEB_PROCESS_KILL_THRESHOLD * WEB_PROCESS_MEMORY_LIMIT_MB, WebKit
    // membunuh proses itu -> ditangkap di OnWebProcessTerminated -> di-reload.
    WebKitMemoryPressureSettings* mem_settings = webkit_memory_pressure_settings_new();
    webkit_memory_pressure_settings_set_memory_limit(mem_settings, WEB_PROCESS_MEMORY_LIMIT_MB);
    webkit_memory_pressure_settings_set_conservative_threshold(mem_settings, WEB_PROCESS_CONSERVATIVE_THRESHOLD);
    webkit_memory_pressure_settings_set_strict_threshold(mem_settings, WEB_PROCESS_STRICT_THRESHOLD);
    webkit_memory_pressure_settings_set_kill_threshold(mem_settings, WEB_PROCESS_KILL_THRESHOLD);
    webkit_memory_pressure_settings_set_poll_interval(mem_settings, WEB_PROCESS_MEMORY_POLL_INTERVAL_SECONDS);
    webkit_website_data_manager_set_memory_pressure_settings(mem_settings);
    webkit_memory_pressure_settings_free(mem_settings);

    WebKitWebsiteDataManager* data_manager = webkit_website_data_manager_new(
            "base-data-directory", data_dir.c_str(),
            "base-cache-directory", data_dir.c_str(),
            nullptr);

    WebKitWebContext* web_context = webkit_web_context_new_with_website_data_manager(data_manager);

    // DOCUMENT_VIEWER paling hemat: tidak menyimpan riwayat back/forward di RAM.
    webkit_web_context_set_cache_model(web_context, WEBKIT_CACHE_MODEL_DOCUMENT_VIEWER);

    // Matikan spell-checking: proses enchant/hunspell yang dipakai WebKit
    // untuk ini punya overhead memori sendiri dan tidak dibutuhkan untuk
    // WhatsApp Web.
    webkit_web_context_set_spell_checking_enabled(web_context, FALSE);

    GtkWidget* webview_widget = webkit_web_view_new_with_context(web_context);
    WebKitWebView* webview = WEBKIT_WEB_VIEW(webview_widget);
    WebKitSettings* webkit_settings = webkit_web_view_get_settings(webview);

    webkit_settings_set_enable_javascript(webkit_settings, TRUE);
    g_object_set(G_OBJECT(webkit_settings), "enable-javascript-jit", TRUE, NULL);

    // PENTING: ON_DEMAND, bukan NEVER. NEVER memaksa software compositing,
    // yang justru menyimpan semua layer/surface di RAM sistem (bukan VRAM),
    // sering kali membuat RAM per-view LEBIH besar, bukan lebih kecil.
    // ON_DEMAND membiarkan GPU menangani compositing saat tersedia.
    webkit_settings_set_hardware_acceleration_policy(
        webkit_settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_ON_DEMAND);

    webkit_settings_set_enable_page_cache(webkit_settings, FALSE);

    // Fitur yang tidak dipakai WhatsApp Web tapi tetap makan memori kalau aktif.
    webkit_settings_set_enable_webgl(webkit_settings, FALSE);
    webkit_settings_set_enable_media_stream(webkit_settings, TRUE); // perlu untuk voice/video call
    webkit_settings_set_media_playback_requires_user_gesture(webkit_settings, TRUE);
    webkit_settings_set_enable_developer_extras(webkit_settings, FALSE);

    // NOTE: "enable-page-query-minimizing" pada versi sebelumnya BUKAN
    // properti WebKitSettings yang valid — g_object_set untuk itu hanya
    // memicu g_warning di log dan tidak melakukan apa pun. Dihapus.

    gtk_fixed_put(self->container, webview_widget, 0, 0);
    gtk_widget_show(webview_widget);
    webkit_web_view_load_uri(webview, url.c_str());

    // Tangkap sinyal saat WebKit membunuh WebProcess ini (baik karena lewat
    // batas RAM di atas, maupun crash biasa) supaya kita bisa reconnect
    // otomatis alih-alih membiarkan akun tampil blank/mati.
    TerminationCallbackData* term_data = new TerminationCallbackData{self, view_id};
    g_signal_connect_data(webview, "web-process-terminated",
                           G_CALLBACK(OnWebProcessTerminated), term_data,
                           FreeTerminationData, static_cast<GConnectFlags>(0));

    (*self->views)[view_id] = webview;
    ViewGeometry geo{};
    geo.url = url;
    (*self->geometry)[view_id] = geo;

    // Coba temukan PID WebProcess-nya sesaat setelah spawn, supaya watchdog
    // RSS bisa mulai memantau akun ini.
    PendingPidResolve* pending = new PendingPidResolve{self, view_id, 10};
    g_timeout_add(300, ResolvePidCallback, pending);

    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

static FlMethodResponse* HandleSetGeometry(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    auto it = self->views->find(view_id);
    if (it == self->views->end()) return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

    const gint x = static_cast<gint>(GetNumber(args, "x"));
    const gint y = static_cast<gint>(GetNumber(args, "y"));
    const gint w = static_cast<gint>(GetNumber(args, "width"));
    const gint h = static_cast<gint>(GetNumber(args, "height"));

    auto& geo = (*self->geometry)[view_id];
    if (geo.has_geometry && geo.x == x && geo.y == y && geo.w == w && geo.h == h) {
        return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    geo.x = x; geo.y = y; geo.w = w; geo.h = h; geo.has_geometry = true;

    GtkWidget* widget = GTK_WIDGET(it->second);
    gtk_fixed_move(self->container, widget, x, y);
    gtk_widget_set_size_request(widget, w, h);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* HandleSetVisible(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    FlValue* visible_value = fl_value_lookup_string(args, "visible");
    const bool visible = visible_value != nullptr && fl_value_get_bool(visible_value);

    auto vit = self->views->find(view_id);
    auto git = self->geometry->find(view_id);
    if (vit == self->views->end() || git == self->geometry->end()) {
        return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }

    WebKitWebView* view = vit->second;
    ViewGeometry& geo = git->second;
    gtk_widget_set_visible(GTK_WIDGET(view), visible);

    if (!visible) {
        webkit_web_view_set_is_muted(view, TRUE);

        // Jangan langsung suspend — tunda beberapa detik supaya switch cepat
        // antar akun tidak memicu reload penuh tiap kali.
        if (geo.suspend_timeout_id == 0 && !geo.suspended) {
            PendingSuspend* pending = new PendingSuspend{self, view_id};
            geo.suspend_timeout_id =
                g_timeout_add_seconds(SUSPEND_DELAY_SECONDS, SuspendCallback, pending);
        }
    } else {
        // Batalkan suspend yang masih tertunda.
        if (geo.suspend_timeout_id != 0) {
            g_source_remove(geo.suspend_timeout_id);
            geo.suspend_timeout_id = 0;
        }
        // Kalau sudah benar-benar ter-suspend (di about:blank), muat ulang
        // URL aslinya. Sesi WhatsApp Web tetap nyambung karena cookie/
        // localStorage/IndexedDB tersimpan di data_dir per-akun di disk.
        if (geo.suspended) {
            webkit_web_view_load_uri(view, geo.url.c_str());
            geo.suspended = false;
        }
        webkit_web_view_set_is_muted(view, FALSE);
        gtk_widget_grab_focus(GTK_WIDGET(view));
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* HandleReload(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    auto it = self->views->find(view_id);
    if (it != self->views->end()) {
        auto git = self->geometry->find(view_id);
        if (git != self->geometry->end()) git->second.suspended = false;
        webkit_web_view_reload(it->second);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

// --- BOILERPLATE INFRASTRUCTURE ---

static void MethodCallCb(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
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

    fl_method_call_respond(method_call, response, nullptr);
}

static void webkit_multi_view_plugin_dispose(GObject* object) {
    WebkitMultiViewPlugin* self = WEBKIT_MULTI_VIEW_PLUGIN(object);
    if (self->memory_watchdog_id != 0) {
        g_source_remove(self->memory_watchdog_id);
        self->memory_watchdog_id = 0;
    }
    if (self->geometry) {
        for (auto& kv : *self->geometry) {
            if (kv.second.suspend_timeout_id != 0) {
                g_source_remove(kv.second.suspend_timeout_id);
            }
        }
    }
    g_clear_object(&self->channel);
    delete self->views;
    delete self->geometry;
    delete self->assigned_pids;
    G_OBJECT_CLASS(webkit_multi_view_plugin_parent_class)->dispose(object);
}

static void webkit_multi_view_plugin_class_init(WebkitMultiViewPluginClass* klass) {
    G_OBJECT_CLASS(klass)->dispose = webkit_multi_view_plugin_dispose;
}

static void webkit_multi_view_plugin_init(WebkitMultiViewPlugin* self) {
    self->views = new std::map<std::string, WebKitWebView*>();
    self->geometry = new std::map<std::string, ViewGeometry>();
    self->assigned_pids = new std::set<pid_t>();
    self->memory_watchdog_id = g_timeout_add_seconds(
        MEMORY_WATCHDOG_INTERVAL_SECONDS, MemoryWatchdogCallback, self);
}

WebkitMultiViewPlugin* webkit_multi_view_plugin_new(FlPluginRegistrar* registrar, GtkFixed* container) {
    WebkitMultiViewPlugin* self = WEBKIT_MULTI_VIEW_PLUGIN(g_object_new(webkit_multi_view_plugin_get_type(), nullptr));
    self->container = container;
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    self->channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar), WEBKIT_MULTI_VIEW_METHOD_CHANNEL, FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(self->channel, MethodCallCb, g_object_ref(self), g_object_unref);
    return self;
}