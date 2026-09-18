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

#define WEBKIT_MULTI_VIEW_METHOD_CHANNEL "multiwhatsappweb/webkit_view"

// Berapa lama akun harus tersembunyi sebelum benar-benar kita "suspend"
// (unload) ke about:blank. Delay ini mencegah reload penuh setiap kali
// user pindah-pindah akun dengan cepat.
#define SUSPEND_DELAY_SECONDS 30

// Interval pengecekan RSS asli tiap WebProcess lewat /proc.
//
// FIX (log kill masih muncul walau MemoryWatchdogCallback sudah pakai
// terminate_web_process(), 900MB limit, 800MB ambang recycle — kill
// berikutnya di 995MB): interval ini SEBELUMNYA 60 detik, 6x lebih jarang
// daripada WEB_PROCESS_MEMORY_POLL_INTERVAL_SECONDS (10 detik) di bawah,
// yaitu seberapa sering WebKit SENDIRI mengecek RSS internal-nya. Kalau
// RSS naik cepat (chat berat/banyak media), gampang melompat dari di
// bawah ambang recycle kita ke atas kill_threshold WebKit DALAM SATU
// jendela 60 detik itu — kita belum sempat cek, WebKit sudah lebih dulu
// membunuhnya sendiri.
//
// FIX #2 (kill WebKit "(918 MB) below the kill thresold (900 MB)" masih
// muncul walau interval sudah 8 detik): 8 detik masih cukup lebar untuk
// kalah balapan lawan poll internal WebKit (10 detik) kalau RSS naik
// sangat cepat (voice/video call, banyak media besar berurutan) DAN
// kebetulan tick kita baru saja lewat saat lonjakan terjadi — dalam kasus
// terburuk itu berarti hampir 8 detik penuh WebKit "unggul duluan".
// Diturunkan lagi supaya jaring pengaman dari luar ini nyaris selalu
// dapat giliran cek sebelum WebKit sempat menghitung 900MB-nya sendiri.
#define MEMORY_WATCHDOG_INTERVAL_SECONDS 5

// Ambang RSS per akun (WebProcess) yang memicu recycle proaktif dari SISI
// LUAR (via /proc, dicek tiap MEMORY_WATCHDOG_INTERVAL_SECONDS = 8 detik
// — sengaja lebih cepat daripada WEB_PROCESS_MEMORY_POLL_INTERVAL_SECONDS
// di bawah, supaya jaring pengaman ini yang menang duluan, bukan WebKit).
//
// FIX (webview "restart sendiri" terus-menerus, walau WEB_PROCESS_
// MEMORY_LIMIT_MB / kill_threshold WebKit sudah diperbaiki di atas):
// nilai sebelumnya (650MB) masih PERSIS di DALAM rentang pemakaian
// NORMAL WhatsApp Web sendiri (500-800MB, chat besar/media terbuka —
// lihat komentar WEB_PROCESS_MEMORY_LIMIT_MB di bawah). Artinya ambang
// recycle proaktif INI SENDIRI kena bug yang sama persis yang sudah
// diperbaiki untuk kill_threshold WebKit: hampir setiap akun yang
// dipakai wajar cepat atau lambat melewati 650MB, memicu
// webkit_web_view_terminate_web_process() -> OnWebProcessTerminated
// (reason TERMINATED_BY_API) -> reload LANGSUNG tanpa backoff sama
// sekali (lihat blok TERMINATED_BY_API di OnWebProcessTerminated — tidak
// seperti blok EXCEEDED_MEMORY_LIMIT/CRASHED, blok ini sebelumnya tidak
// memakai kWebProcessKillBackoffDelaysSeconds). Karena cooldown-nya cuma
// 20 detik, begitu WebProcess baru kembali ke pemakaian normalnya
// (>650MB lagi dalam hitungan puluhan detik saat chat aktif), watchdog
// men-terminate lagi — inilah yang terlihat dari luar sebagai
// "webview restart sendiri terus".
//
// Dinaikkan ke atas rentang pemakaian normal (bukan di tengahnya),
// selaras dengan filosofi yang sama seperti WEB_PROCESS_MEMORY_LIMIT_MB:
// ambang ini sekarang jadi jaring pengaman untuk pertumbuhan RSS yang
// TIDAK WAJAR (leak/anomali), bukan trigger yang pasti kena di pemakaian
// sehari-hari.
//
// FIX (kill WebKit "(918 MB) below the kill thresold (900 MB)" masih
// terjadi walau ambang ini sempat dinaikkan ke 850MB): jarak 850MB ->
// 900MB (hard kill) cuma 50MB — terlalu tipis. Kombinasi dengan
// MEMORY_RELOAD_COOLDOWN_SECONDS yang sempat dinaikkan jauh (lihat
// perbaikan di bawah) membuat ada jendela waktu watchdog kita SAMA
// SEKALI TIDAK memeriksa RSS akun yang baru saja di-recycle — kalau akun
// itu langsung dipakai berat lagi (panggilan video, kirim banyak media)
// dalam jendela itu, RSS-nya bisa tembus 900MB tanpa sempat kita
// tangkap, dan WebKit sendiri yang membunuhnya duluan. Diturunkan ke
// 780MB supaya marginnya ke hard-kill (900MB) jadi 120MB — jauh lebih
// longgar untuk poll 5 detik di atas menangkapnya lebih dulu.
//
// FIX LAGI (kill "(931 MB)" lalu "(966 MB)" masih terjadi walau margin
// sudah 120MB & poll 5 detik): ternyata bukan lagi soal margin/kecepatan
// watchdog — ini lonjakan RSS yang genuinely cepat & besar (lihat
// penjelasan panjang di WEB_PROCESS_MEMORY_LIMIT_MB di atas, yang
// dinaikkan ke 1100MB). Ambang proaktif ini ikut disesuaikan supaya tetap
// proporsional: dulu ~87% dari limit lama (780/900), sekarang dipasang di
// 900MB, yaitu ~82% dari limit baru (1100MB) — sedikit lebih longgar
// secara relatif, memberi lebih banyak ruang bagi lonjakan sesaat untuk
// turun sendiri sebelum kita ikut campur, sekaligus masih menyisakan
// 200MB margin ke hard-kill WebKit untuk kasus yang benar-benar leak.
#define MEMORY_RELOAD_THRESHOLD_BYTES (900LL * 1024 * 1024)

// Jangan recycle akun yang sama dua kali dalam jendela waktu ini, supaya
// tidak terjadi recycle berulang selagi proses lama masih benar-benar
// exit dan proses baru masih resolve PID-nya (lihat ResolvePidCallback).
//
// FIX (webview "restart sendiri" - versi lama, 20 detik): dinaikkan ke 90
// detik untuk mencegah loop reload rapat.
//
// FIX LAGI (kill WebKit "918 MB ... Killed" muncul SETELAH fix di atas):
// 90 detik ternyata salah alat untuk masalah "restart terus" — nilai itu
// membuat watchdog BERHENTI TOTAL memantau RSS akun ini selama 90 detik
// penuh setiap kali kita baru saja me-recycle-nya (lihat `continue` di
// bawah), termasuk kalau proses barunya langsung dibebani berat lagi.
// Itu justru membuka celah: RSS boleh naik bebas tanpa pengawasan kita
// selama 90 detik, dan WebKit sendiri (poll independen, 10 detik) yang
// akhirnya menangkap & membunuhnya lebih dulu begitu lewat 900MB — persis
// yang terlihat di log.
//
// Perlindungan anti-loop yang SEBENARNYA sudah ada di tempat lain:
// backoff bertingkat (kWebProcessKillBackoffDelaysSeconds, dipakai baik
// untuk kill di luar kendali kita maupun recycle proaktif kita sendiri —
// lihat OnWebProcessTerminated) menunda RELOAD SETELAH terminate, makin
// lama kalau terjadi berulang. Cooldown di sini cuma perlu cukup untuk
// mencegah kita memanggil terminate_web_process() dua kali pada proses
// yang sama sebelum sinyal "web-process-terminated"-nya benar-benar
// tiba (biasanya kurang dari satu detik, beri jarak aman beberapa detik
// saja) — bukan untuk menahan pemantauan RSS dalam waktu lama.
// Dikembalikan ke nilai pendek.
#define MEMORY_RELOAD_COOLDOWN_SECONDS 15

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
// FIX (log "Unable to shrink memory footprint of process (618/691/727 MB)
// below the kill thresold (600 MB). Killed" berulang terus):
// Nilai sebelumnya (600MB) sama persis dengan pemakaian NORMAL WhatsApp
// Web sendiri (500-800MB dengan chat besar/media terbuka, ditulis di
// komentar lama di bawah). Artinya kill_threshold selalu tercapai lambat
// atau cepat walau tidak ada leak sama sekali, lalu OnWebProcessTerminated
// langsung load_uri ulang TANPA jeda sama sekali — WebProcess baru memuat
// ulang WhatsApp Web dari nol (yang sendirinya sempat menaikkan RSS saat
// loading), lalu balik lagi ke pemakaian normalnya yang notabene sudah di
// atas 600MB, kena limit lagi dalam hitungan detik/menit. Itulah loop
// "restart terus" yang terlihat dari luar.
//
// Sekarang limit dinaikkan jauh di atas pemakaian normal (bukan pas-pasan
// dengannya), supaya kill_threshold betul-betul jadi *backstop* untuk
// leak/anomali sungguhan, bukan ambang yang pasti kena di pemakaian wajar.
// Reclaim dini tetap jalan lebih awal (lihat threshold fraction di bawah)
// supaya WebKit sempat membuang cache sebelum mendekati limit ini, dan
// OnWebProcessTerminated sekarang punya backoff (lihat WEB_PROCESS_KILL_
// BACKOFF_* di bawah) untuk kill yang berturut-turut, jadi walau limit ini
// suatu saat tetap kena, tidak langsung disusul reload instan yang memicu
// loop lagi.
//
// Turunkan angka ini kalau mau RAM lebih hemat (dengan konsekuensi akun
// akan lebih sering "kick & reload" saat dipakai berat — chat besar,
// banyak media, panggilan suara/video) — tapi jaga tetap di ATAS pemakaian
// normal WhatsApp Web (500-800MB), jangan dipasang pas-pasan dengannya
// seperti sebelumnya.
//
// FIX (kill "(931 MB)" lalu "(966 MB)" masih terjadi walau bug pelacakan
// PID sudah diperbaiki, ambang proaktif sudah 780MB, watchdog sudah poll
// tiap 5 detik): dua kejadian ini BUKAN lagi kasus watchdog salah/tidak
// memantau — ini genuinely LONJAKAN RSS yang cepat & besar (media berat
// dibuka sekaligus, panggilan suara/video, dsb). WebKit sendiri baru cek
// RSS internalnya tiap WEB_PROCESS_MEMORY_POLL_INTERVAL_SECONDS = 10
// detik — kalau dalam jendela 10 detik itu RSS melonjak lebih dari
// beberapa puluh MB (966MB berarti sudah 66MB DI ATAS limit saat baru
// sempat dicek), tidak ada watchdog dari luar (secepat apa pun) yang bisa
// menjamin selalu menangkapnya SEBELUM WebKit sendiri — satu-satunya
// jaminan sungguhan adalah punya cukup RUANG (headroom) di atas pemakaian
// normal untuk menyerap lonjakan sesaat itu tanpa langsung kena kill,
// supaya dia sempat turun lagi sendiri (WhatsApp Web biasanya melepas
// blob media setelah viewer ditutup) alih-alih dipotong di tengah jalan.
//
// Dinaikkan dari 900MB -> 1100MB (bukan 1.4GB seperti dikira sebelumnya —
// itu jauh lebih besar dari yang dibutuhkan berdasarkan bukti di lapangan:
// dua kill terakhir di 931MB & 966MB, jadi headroom sekitar 200-250MB di
// atas kejadian nyata sudah cukup longgar) dan poll internal WebKit
// dipercepat 10 -> 5 detik supaya jendela "buta" WebKit sendiri (sumber
// overshoot di atas) ikut menyempit, bukan cuma sisi watchdog kita.
#define WEB_PROCESS_MEMORY_LIMIT_MB 1100
#define WEB_PROCESS_CONSERVATIVE_THRESHOLD 0.40  // mulai buang cache non-kritis lebih awal (~440MB)
#define WEB_PROCESS_STRICT_THRESHOLD 0.65         // mulai buang memori kritis (~715MB)
#define WEB_PROCESS_KILL_THRESHOLD 1.0            // >= 1100MB -> proses dibunuh & di-respawn (backstop, bukan ambang normal)
#define WEB_PROCESS_MEMORY_POLL_INTERVAL_SECONDS 5.0 // WebKit cek RSS internal tiap 5 detik (sebelumnya 10)

// --- Backoff untuk reload setelah WebProcess dibunuh WebKit sendiri ---
// FIX (bagian kedua dari death-spiral di atas): OnWebProcessTerminated
// sebelumnya selalu langsung webkit_web_view_load_uri() tanpa jeda begitu
// EXCEEDED_MEMORY_LIMIT/CRASHED terjadi, tidak peduli ini kill pertama
// atau yang kelima kalinya beruntun. Kalau akun memang secara konsisten
// lewat limit (bukan cuma sesekali), reload instan berulang hanya
// mempercepat siklusnya. Sekarang tiap view punya hitungan "kill
// beruntun" (reset kalau sudah tenang > KILL_BACKOFF_RESET_WINDOW_SECONDS)
// dan reload berikutnya ditunda makin lama tiap kali terjadi lagi dalam
// jendela waktu itu.
#define WEB_PROCESS_KILL_BACKOFF_RESET_WINDOW_SECONDS 120
// Delay (detik) sebelum reload, diindeks oleh (consecutive_kills - 1).
// Kill pertama: hampir instan (biar akun terasa tetap nyambung). Kill
// berikutnya yang masih dalam jendela reset di atas: makin lama, supaya
// WebProcess baru sempat "istirahat" alih-alih langsung diberi beban
// penuh WhatsApp Web lagi.
static const int kWebProcessKillBackoffDelaysSeconds[] = {1, 5, 15, 30, 60};
#define WEB_PROCESS_KILL_BACKOFF_MAX_INDEX \
    (static_cast<int>(sizeof(kWebProcessKillBackoffDelaysSeconds) / sizeof(int)) - 1)

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

    // --- Backoff reload setelah WebProcess dibunuh WebKit sendiri ---
    int consecutive_kills = 0;         // di-reset kalau sudah tenang > KILL_BACKOFF_RESET_WINDOW
    gint64 last_kill_unix = 0;         // waktu (detik) kill terakhir, dasar perhitungan reset window
    guint pending_reload_timeout_id = 0; // id g_timeout_add untuk reload yang ditunda, 0 = tidak ada

    // FIX (kill WebKit masih muncul tepat saat akun LAIN dibuat, walau
    // threshold/poll watchdog sudah dikencangkan — lihat FindUnclaimedWeb
    // ProcessPid & SnapshotWebProcessPids): PID-PID "WebKitWebProce" yang
    // SUDAH ADA di /proc sesaat SEBELUM kita memicu load_uri yang
    // menyebabkan proses baru untuk VIEW INI spawn. Dipakai supaya resolve
    // PID untuk view ini tidak pernah ikut mengklaim proses milik view lain
    // yang kebetulan juga sedang menunggu resolve di waktu yang berdekatan
    // (mis. saat user membuat akun baru sementara akun lain masih dalam
    // proses respawn) — tanpa ini, heuristik lama ("PID unclaimed terbesar")
    // bisa salah tebak, dan akibatnya akun yang SALAH assign PID-nya jadi
    // TIDAK PERNAH dipantau watchdog RSS sama sekali (celah yang persis
    // cocok dengan gejala "kill terjadi tepat saat sesi baru dibuat").
    std::set<pid_t> pid_resolve_baseline;
};

struct _WebkitMultiViewPlugin {
    GObject parent_instance;
    FlMethodChannel* channel;
    GtkFixed* container;
    GtkWidget* flutter_view;  // FlView — target focus balik saat webview di-hide
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

    // Ambil snapshot SEMUA PID "WebKitWebProce" yang jadi anak proses kita
    // saat ini (diklaim ataupun belum). Dipanggil TEPAT SEBELUM kita memicu
    // load_uri yang akan menyebabkan sebuah proses BARU spawn, supaya
    // resolve PID untuk proses baru itu nanti bisa membedakan "sudah ada
    // dari tadi" (punya view lain / sisa proses lama) vs "benar-benar baru
    // muncul setelah ini" — lihat pid_resolve_baseline di ViewGeometry.
    std::set<pid_t> SnapshotWebProcessPids() {
        pid_t my_pid = getpid();
        std::set<pid_t> result;
        DIR* proc = opendir("/proc");
        if (!proc) return result;
        struct dirent* entry;
        while ((entry = readdir(proc)) != nullptr) {
            if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
            pid_t pid = static_cast<pid_t>(atoi(entry->d_name));
            if (pid <= 0) continue;
            std::string name;
            pid_t ppid = 0;
            if (!ReadProcStatus(pid, &name, &ppid)) continue;
            if (ppid != my_pid) continue;
            if (name.rfind("WebKitWebProce", 0) == 0) result.insert(pid);
        }
        closedir(proc);
        return result;
    }

    // Cari PID WebKitWebProcess baru yang anak dari proses kita sendiri dan
    // belum "diklaim" view lain. Dipanggil sesaat setelah create/load_uri,
    // saat WebProcess untuk view tersebut baru saja spawn. WebKitGTK tidak
    // punya API publik untuk memetakan WebView -> pid secara langsung, jadi
    // ini heuristik — cukup andal SELAMA kandidatnya benar-benar dibatasi ke
    // proses yang baru muncul.
    //
    // FIX (kill WebKit "(903 MB) ... Killed" masih terjadi tepat saat akun
    // LAIN dibuat, walau threshold & interval watchdog sudah dikencangkan):
    // versi sebelumnya memilih PID TERBESAR di antara SEMUA yang belum
    // diklaim, tanpa peduli sudah berapa lama proses itu berjalan. Kalau
    // dua view sedang menunggu resolve PID di waktu yang berdekatan (mis.
    // view A baru saja direspawn oleh OnWebProcessTerminated, dan tepat
    // saat itu user membuat view B), resolve untuk B bisa saja berjalan
    // duluan dan salah mengklaim proses A (yang kebetulan PID-nya lebih
    // besar dari proses B yang belum sempat spawn) — akibatnya A TIDAK
    // PERNAH mendapat PID yang benar, dan watchdog RSS tidak pernah
    // memeriksanya sampai WebKit sendiri yang membunuhnya.
    //
    // `exclude_baseline` (lihat SnapshotWebProcessPids, diambil tepat
    // sebelum load_uir dipicu) berisi semua PID yang SUDAH ADA sebelum
    // proses baru untuk view ini mulai spawn — PID mana pun di dalam set
    // ini otomatis bukan kandidat (dia milik view lain, atau sisa proses
    // lama). Di antara sisanya (yang benar-benar baru), pilih yang PALING
    // KECIL — PID pada Linux dialokasikan naik secara umum, jadi yang
    // paling kecil di antara kandidat baru adalah yang paling dulu spawn,
    // konsisten dengan urutan permintaan resolve yang juga FIFO (dipicu
    // berurutan lewat g_timeout_add).
    pid_t FindUnclaimedWebProcessPid(std::set<pid_t>* assigned_pids,
                                      const std::set<pid_t>& exclude_baseline) {
        pid_t my_pid = getpid();
        DIR* proc = opendir("/proc");
        if (!proc) return 0;
        pid_t best = 0;
        struct dirent* entry;
        while ((entry = readdir(proc)) != nullptr) {
            if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
            pid_t pid = static_cast<pid_t>(atoi(entry->d_name));
            if (pid <= 0 || assigned_pids->count(pid) || exclude_baseline.count(pid)) continue;
            std::string name;
            pid_t ppid = 0;
            if (!ReadProcStatus(pid, &name, &ppid)) continue;
            if (ppid != my_pid) continue;
            // Nama proses di /proc dipotong ~15 char: "WebKitWebProce".
            if (name.rfind("WebKitWebProce", 0) == 0) {
                if (best == 0 || pid < best) best = pid; // ambil yang PID-nya PALING KECIL (paling dulu muncul)
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

    // --- Drag & drop file dari luar aplikasi (mis. file manager) ke atas
    // sebuah WebKitWebView ---
    //
    // FIX (drag & drop tidak berjalan sama sekali di Linux): setiap
    // WebKitWebView di sini adalah widget GTK NATIVE yang diletakkan
    // langsung di atas FlView lewat GtkFixed di dalam GtkOverlay (lihat
    // my_application.cc) — BUKAN Flutter texture/platform-view yang ikut
    // masuk ke render tree Flutter seperti webview_windows di Windows.
    // Akibatnya seluruh event drag-and-drop level GTK/X11-Wayland yang
    // terjadi persis di atas area webview jatuh ke widget native ini
    // duluan; plugin desktop_drop (dipakai lewat DropTarget di Dart, lihat
    // webview_container.dart) mendaftarkan drag-dest-nya sendiri di FlView
    // / window Flutter, yang di area itu SUDAH TERTUTUP widget native ini
    // dan tidak pernah menerima apa pun. Ini kenapa DropTarget di Windows
    // ( _WindowsEngineSurface ) bekerja tapi padanannya tidak pernah
    // dipasang sama sekali untuk _LinuxEngineSurface — dipasang pun tidak
    // akan menerima event.
    //
    // Solusinya: daftarkan drag-dest GTK langsung pada widget WebKitWebView
    // itu sendiri (di HandleCreate), lalu saat file benar-benar di-drop,
    // teruskan daftar path file-nya ke Dart lewat method channel yang sama
    // ("filesDropped"), supaya alur upload berbasis JS injection yang sudah
    // ada (lihat file_drop_injection.dart, sudah dipakai untuk Windows)
    // bisa dipakai ulang persis sama di Linux.
    struct DropCallbackData {
        WebkitMultiViewPlugin* self;
        std::string view_id;
    };

    void FreeDropData(gpointer data, GClosure*) {
        delete static_cast<DropCallbackData*>(data);
    }

    void InvokeMethodIgnoreResponse(FlMethodChannel* channel, const char* method, FlValue* args) {
        fl_method_channel_invoke_method(channel, method, args, nullptr, nullptr, nullptr);
    }

    // Dipanggil GTK setelah gtk_drag_get_data() (lihat OnDragDrop di bawah)
    // selesai mengambil data drop dalam format "text/uri-list".
    void OnDragDataReceived(GtkWidget*, GdkDragContext* context, gint, gint,
                             GtkSelectionData* selection_data, guint, guint time,
                             gpointer user_data) {
        DropCallbackData* data = static_cast<DropCallbackData*>(user_data);

        gchar** uris = gtk_selection_data_get_uris(selection_data);
        bool ok = uris != nullptr;
        if (uris != nullptr) {
            g_autoptr(FlValue) paths = fl_value_new_list();
            for (int i = 0; uris[i] != nullptr; i++) {
                // "file:///home/user/foto.jpg" -> "/home/user/foto.jpg".
                // Drop dari sumber non-file (mis. link dari browser lain)
                // menghasilkan nullptr di sini dan cukup dilewati.
                g_autoptr(GError) error = nullptr;
                gchar* path = g_filename_from_uri(uris[i], nullptr, &error);
                if (path != nullptr) {
                    fl_value_append_take(paths, fl_value_new_string(path));
                    g_free(path);
                }
            }
            g_strfreev(uris);

            if (fl_value_get_length(paths) > 0) {
                g_autoptr(FlValue) args = fl_value_new_map();
                fl_value_set_string_take(args, "viewId", fl_value_new_string(data->view_id.c_str()));
                fl_value_set_string_take(args, "paths", fl_value_ref(paths));
                InvokeMethodIgnoreResponse(data->self->channel, "filesDropped", args);
            }
        }
        gtk_drag_finish(context, ok, FALSE, time);
    }

    // GTK_DEST_DEFAULT_DROP sengaja TIDAK dipakai di gtk_drag_dest_set
    // (lihat HandleCreate) supaya kita yang eksplisit memutuskan target
    // mana yang diminta dan eksplisit memanggil gtk_drag_finish() persis
    // sekali di OnDragDataReceived, tanpa bergantung pada perilaku
    // "otomatis" GTK yang berbeda-beda antar versi.
    gboolean OnDragDrop(GtkWidget* widget, GdkDragContext* context, gint, gint, guint time, gpointer) {
        GdkAtom target = gtk_drag_dest_find_target(widget, context, nullptr);
        if (target == GDK_NONE) {
            gtk_drag_finish(context, FALSE, FALSE, time);
            return TRUE;
        }
        gtk_drag_get_data(widget, context, target, time);
        return TRUE;
    }

    // "dragEntered"/"dragExited" diteruskan ke Dart supaya _LinuxEngineSurface
    // bisa menampilkan overlay hover yang sama seperti versi Windows
    // (_WindowsEngineSurface, lihat _dragging di webview_container.dart).
    // "dragEntered" dikirim di tiap tick drag-motion (murah & idempotent —
    // sisi Dart cuma set bool ke true), bukan cuma sekali di awal, supaya
    // tidak perlu state tambahan di sisi native untuk melacak "sudah pernah
    // masuk atau belum" per sesi drag.
    gboolean OnDragMotion(GtkWidget*, GdkDragContext* context, gint, gint, guint time, gpointer user_data) {
        gdk_drag_status(context, GDK_ACTION_COPY, time);
        DropCallbackData* data = static_cast<DropCallbackData*>(user_data);
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "viewId", fl_value_new_string(data->view_id.c_str()));
        InvokeMethodIgnoreResponse(data->self->channel, "dragEntered", args);
        return TRUE;
    }

    void OnDragLeave(GtkWidget*, GdkDragContext*, guint, gpointer user_data) {
        DropCallbackData* data = static_cast<DropCallbackData*>(user_data);
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "viewId", fl_value_new_string(data->view_id.c_str()));
        InvokeMethodIgnoreResponse(data->self->channel, "dragExited", args);
    }

    // Data yang dibawa g_timeout_add untuk reload yang ditunda (backoff).
    struct PendingReload {
        WebkitMultiViewPlugin* self;
        std::string view_id;
    };

    void CancelPendingReload(WebkitMultiViewPlugin* self, const std::string& view_id) {
        auto git = self->geometry->find(view_id);
        if (git != self->geometry->end() && git->second.pending_reload_timeout_id != 0) {
            g_source_remove(git->second.pending_reload_timeout_id);
            git->second.pending_reload_timeout_id = 0;
        }
    }

    gboolean PendingReloadCallback(gpointer data) {
        PendingReload* pending = static_cast<PendingReload*>(data);
        WebkitMultiViewPlugin* self = pending->self;
        auto vit = self->views->find(pending->view_id);
        auto git = self->geometry->find(pending->view_id);
        if (vit != self->views->end() && git != self->geometry->end()) {
            ViewGeometry& geo = git->second;
            geo.pending_reload_timeout_id = 0;
            // Kalau view sempat disembunyikan (di-suspend) selagi menunggu
            // backoff, jangan buru-buru muat ulang WhatsApp Web di
            // background — sama seperti alasan di OnWebProcessTerminated.
            if (!geo.suspended) {
                webkit_web_view_load_uri(vit->second, geo.url.c_str());
            }
        }
        delete pending;
        return G_SOURCE_REMOVE;
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
            // FIX (death spiral): sebelumnya baris di bawah ini langsung
            // dipanggil tanpa jeda sama sekali, kill keberapa pun. Kalau
            // sebuah akun memang konsisten lewat WEB_PROCESS_MEMORY_LIMIT_MB
            // (bukan cuma sesekali), reload instan hanya mempercepat siklus
            // "load penuh -> naik lagi -> kena limit lagi" — persis yang
            // terlihat sebagai log kill berturut-turut dalam hitungan
            // detik/menit. Sekarang kill yang beruntun (dalam jendela reset
            // di bawah) ditunda makin lama tiap kali terjadi lagi, supaya
            // WebProcess baru sempat "istirahat" alih-alih langsung
            // dibebani penuh lagi.
            gint64 now = static_cast<gint64>(g_get_real_time() / G_USEC_PER_SEC);
            if (geo.last_kill_unix == 0 ||
                now - geo.last_kill_unix > WEB_PROCESS_KILL_BACKOFF_RESET_WINDOW_SECONDS) {
                geo.consecutive_kills = 0;
            }
            geo.consecutive_kills++;
            geo.last_kill_unix = now;

            int backoff_index = geo.consecutive_kills - 1;
            if (backoff_index > WEB_PROCESS_KILL_BACKOFF_MAX_INDEX) {
                backoff_index = WEB_PROCESS_KILL_BACKOFF_MAX_INDEX;
            }
            int delay_seconds = kWebProcessKillBackoffDelaysSeconds[backoff_index];

            // Proses lama sudah mati total — kalau view ini sedang disembunyikan
            // (suspended ke about:blank), biarkan saja, tidak perlu buru-buru
            // memuat ulang WhatsApp Web di background. Kalau sedang dipakai
            // (tidak suspended), reconnect setelah jeda backoff di atas supaya
            // user tidak melihat halaman kosong terlalu lama, tapi juga tidak
            // langsung disusul kill berikutnya kalau akun ini memang berat.
            CancelPendingReload(self, data->view_id);
            if (!geo.suspended) {
                if (delay_seconds <= 1) {
                    webkit_web_view_load_uri(web_view, geo.url.c_str());
                } else {
                    PendingReload* pending = new PendingReload{self, data->view_id};
                    geo.pending_reload_timeout_id =
                        g_timeout_add_seconds(delay_seconds, PendingReloadCallback, pending);
                }
            }
            // PID lama sudah tidak valid, watchdog /proc perlu mencari ulang.
            // Snapshot baseline di SINI (sebelum load_uri manapun di atas
            // benar-benar memicu proses baru spawn — baik yang instan
            // maupun yang masih menunggu backoff/suspend) supaya resolve
            // untuk view ini nanti tidak salah mengklaim proses view lain
            // yang kebetulan sedang berjalan (lihat pid_resolve_baseline).
            if (geo.web_process_pid > 0) {
                self->assigned_pids->erase(geo.web_process_pid);
                geo.web_process_pid = 0;
            }
            geo.pid_resolve_baseline = SnapshotWebProcessPids();
            PendingPidResolve* pending = new PendingPidResolve{self, data->view_id, 10};
            g_timeout_add(300, ResolvePidCallback, pending);
            return;
        }

        if (reason == WEBKIT_WEB_PROCESS_TERMINATED_BY_API) {
            // FIX (death spiral bagian ketiga — "webview restart sendiri
            // terus" masih terjadi walau backoff sudah ada di atas untuk
            // EXCEEDED_MEMORY_LIMIT/CRASHED): recycle proaktif kita sendiri
            // (MemoryWatchdogCallback memanggil webkit_web_view_
            // terminate_web_process() saat RSS lewat
            // MEMORY_RELOAD_THRESHOLD_BYTES) berakhir di SINI dengan reason
            // TERMINATED_BY_API. Baris di bawah SEBELUMNYA langsung
            // webkit_web_view_load_uri() tanpa jeda sama sekali, kill
            // keberapa pun — persis pola yang sama yang menyebabkan death
            // spiral EXCEEDED_MEMORY_LIMIT/CRASHED (lihat blok di atas),
            // hanya lewat jalur yang berbeda (kita men-terminate diri
            // sendiri, bukan WebKit). Kalau MEMORY_RELOAD_THRESHOLD_BYTES
            // tercapai lagi dengan cepat (akun memang dipakai berat terus-
            // menerus), reload instan berulang inilah yang membuat webview
            // terlihat "restart sendiri" tanpa henti dari luar.
            //
            // Sekarang jalur ini memakai hitungan "kill beruntun" yang SAMA
            // dengan blok EXCEEDED_MEMORY_LIMIT/CRASHED di atas (bukan
            // hitungan terpisah) — recycle proaktif dan kill di luar kendali
            // kita sama-sama berkontribusi ke satu penanda "akun ini sedang
            // berat", dan sama-sama kena backoff makin lama kalau terjadi
            // berulang dalam jendela waktu WEB_PROCESS_KILL_BACKOFF_RESET_
            // WINDOW_SECONDS ini.
            gint64 now = static_cast<gint64>(g_get_real_time() / G_USEC_PER_SEC);
            if (geo.last_kill_unix == 0 ||
                now - geo.last_kill_unix > WEB_PROCESS_KILL_BACKOFF_RESET_WINDOW_SECONDS) {
                geo.consecutive_kills = 0;
            }
            geo.consecutive_kills++;
            geo.last_kill_unix = now;

            int backoff_index = geo.consecutive_kills - 1;
            if (backoff_index > WEB_PROCESS_KILL_BACKOFF_MAX_INDEX) {
                backoff_index = WEB_PROCESS_KILL_BACKOFF_MAX_INDEX;
            }
            int delay_seconds = kWebProcessKillBackoffDelaysSeconds[backoff_index];

            CancelPendingReload(self, data->view_id);
            if (!geo.suspended) {
                if (delay_seconds <= 1) {
                    webkit_web_view_load_uri(web_view, geo.url.c_str());
                } else {
                    PendingReload* pending = new PendingReload{self, data->view_id};
                    geo.pending_reload_timeout_id =
                        g_timeout_add_seconds(delay_seconds, PendingReloadCallback, pending);
                }
            }
            if (geo.web_process_pid > 0) {
                self->assigned_pids->erase(geo.web_process_pid);
                geo.web_process_pid = 0;
            }
            // Sama seperti blok EXCEEDED_MEMORY_LIMIT/CRASHED di atas — lihat
            // komentar di sana.
            geo.pid_resolve_baseline = SnapshotWebProcessPids();
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
        pid_t pid = FindUnclaimedWebProcessPid(self->assigned_pids, git->second.pid_resolve_baseline);
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
    // VmRSS asli WebProcess-nya, dan kalau sudah lewat ambang, RECYCLE akun
    // itu (hentikan proses lamanya sepenuhnya, bukan cuma navigasi ulang).
    //
    // FIX: sebelumnya baris ini memanggil webkit_web_view_reload(), yang
    // menavigasi ulang di WebProcess yang SAMA. Itu cukup untuk mengosongkan
    // DOM/JS heap kalau pertumbuhannya murni cache, tapi terbukti tidak
    // cukup di lapangan (limit dinaikkan 600MB -> 900MB, tetap kena di
    // 967MB) — pertumbuhannya termasuk sesuatu yang tidak dilepas balik ke
    // OS hanya dengan navigasi ulang (fragmentasi allocator glibc, atau
    // referensi yang perlu satu siklus GC penuh + proses baru untuk benar-
    // benar hilang). webkit_web_view_terminate_web_process() di bawah
    // benar-benar mengakhiri proses OS-nya — sama seperti yang sudah
    // terbukti berhasil untuk suspend akun latar (about:blank) dan untuk
    // HandleDestroy — lalu OnWebProcessTerminated (reason TERMINATED_BY_API)
    // yang memuat ulang di proses BARU yang bersih.
    gboolean MemoryWatchdogCallback(gpointer data) {
        WebkitMultiViewPlugin* self = static_cast<WebkitMultiViewPlugin*>(data);
        gint64 now = static_cast<gint64>(g_get_real_time() / G_USEC_PER_SEC);

        for (auto& kv : *self->views) {
            const std::string& view_id = kv.first;
            WebKitWebView* view = kv.second;
            auto git = self->geometry->find(view_id);
            if (git == self->geometry->end()) continue;
            ViewGeometry& geo = git->second;

            if (geo.suspended) continue;

            // FIX (log kill terus muncul walau threshold sudah diturunkan
            // & poll dipercepat — kill berikutnya di 976MB): akar masalah
            // di sini ternyata bukan kecepatan watchdog, tapi watchdog
            // TIDAK PERNAH mendapat PID akun ini sama sekali. Rantai
            // ResolvePidCallback (dipicu dari HandleCreate & dari
            // OnWebProcessTerminated) hanya mencoba selama ~3 detik (10x,
            // 300ms) lalu MENYERAH PERMANEN kalau belum ketemu —
            // web_process_pid tetap 0 selamanya, dan baris `continue` di
            // bawah membuat akun itu tidak pernah dipantau lagi oleh kita.
            // Ini gampang terjadi justru saat sistem sedang tertekan
            // memori (spawn proses baru jadi lebih lambat dari 3 detik),
            // yaitu tepat saat pemantauan ini paling dibutuhkan.
            //
            // Sekarang watchdog ini sendiri juga mencoba resolve PID yang
            // masih 0 di SETIAP tick (tiap MEMORY_WATCHDOG_INTERVAL_SECONDS
            // = 8 detik), bukan cuma mengandalkan rantai awal yang bisa
            // habis masa percobaannya. Ini membuat resolusi PID "self-
            // healing" — selama view-nya masih hidup, cepat atau lambat
            // akan tertangkap di sini walau rantai awalnya gagal.
            if (geo.web_process_pid <= 0) {
                pid_t pid = FindUnclaimedWebProcessPid(self->assigned_pids, geo.pid_resolve_baseline);
                if (pid > 0) {
                    geo.web_process_pid = pid;
                    self->assigned_pids->insert(pid);
                }
                // Baik dapat maupun belum, lewati RSS check tick ini —
                // kalau baru dapat, angkanya belum representatif; kalau
                // belum dapat, memang belum ada yang bisa dibaca.
                continue;
            }

            if (webkit_web_view_is_loading(view)) continue;
            if (now - geo.last_reload_unix < MEMORY_RELOAD_COOLDOWN_SECONDS) continue;

            long rss_kb = ReadProcRssKb(geo.web_process_pid);
            if (rss_kb < 0) {
                // PID sudah tidak ada (proses ganti karena reload/crash) —
                // lepaskan supaya blok resolve di atas bisa mencari ulang
                // pada tick berikutnya.
                self->assigned_pids->erase(geo.web_process_pid);
                geo.web_process_pid = 0;
                continue;
            }
            if (static_cast<gint64>(rss_kb) * 1024 >= MEMORY_RELOAD_THRESHOLD_BYTES) {
                // Catat waktu SEKARANG untuk cooldown, sebelum memanggil
                // terminate — sinyal "web-process-terminated" (yang memuat
                // ulang & mereset web_process_pid) baru datang belakangan
                // lewat main loop, jadi cooldown harus sudah aktif dari
                // titik ini supaya iterasi watchdog berikutnya (yang bisa
                // saja jalan sebelum sinyal itu tiba) tidak mencoba
                // men-terminate proses yang sama dua kali.
                geo.last_reload_unix = now;
                webkit_web_view_terminate_web_process(view);
            }
        }
        return G_SOURCE_CONTINUE;
    }
}

// --- FUNGSI DESTROY HARUS DI ATAS ---
static FlMethodResponse* HandleDestroy(WebkitMultiViewPlugin* self, FlValue* args) {
    const std::string view_id = GetString(args, "viewId");
    CancelPendingSuspend(self, view_id);
    CancelPendingReload(self, view_id);
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
    //
    // PENTING: settings ini HARUS di-pass sebagai construct-property
    // "memory-pressure-settings" saat WebKitWebContext dibuat lewat
    // g_object_new. webkit_website_data_manager_set_memory_pressure_settings()
    // (dipakai versi sebelumnya) TIDAK menyentuh WebProcess sama sekali --
    // itu cuma berlaku untuk NetworkProcess (HTTP fetch/cookies/disk cache).
    // Perbedaan ini gampang kelewat karena nama fungsinya mirip dan
    // sama-sama tidak error/warning kalau salah pakai.
    WebKitMemoryPressureSettings* mem_settings = webkit_memory_pressure_settings_new();
    webkit_memory_pressure_settings_set_memory_limit(mem_settings, WEB_PROCESS_MEMORY_LIMIT_MB);
    // PENTING: urutan setter di bawah ini tidak boleh diubah bebas.
    // Tiap setter memvalidasi nilainya terhadap nilai threshold tetangga
    // yang TERSIMPAN SAAT ITU (bukan nilai akhir yang akan kita pasang),
    // yaitu kira-kira:
    //   conservative harus <  strict (yang sudah tersimpan)
    //   strict        harus >  conservative (yang sudah tersimpan) dan < kill (yang sudah tersimpan)
    //   kill          harus >  strict (yang sudah tersimpan)
    // Default internal WebKit untuk strict/kill cukup rendah, jadi kalau
    // conservative (0.5) dipasang duluan -- SEBELUM strict dinaikkan --
    // assertion "value < settings->configuration.strictThresholdFraction"
    // langsung gagal dan proses abort (persis CRITICAL yang muncul di log).
    // Solusinya: pasang dari batas paling tinggi ke paling rendah (kill ->
    // strict -> conservative) supaya setiap perbandingan selalu terhadap
    // nilai yang SUDAH benar, bukan default bawaan.
    webkit_memory_pressure_settings_set_kill_threshold(mem_settings, WEB_PROCESS_KILL_THRESHOLD);
    webkit_memory_pressure_settings_set_strict_threshold(mem_settings, WEB_PROCESS_STRICT_THRESHOLD);
    webkit_memory_pressure_settings_set_conservative_threshold(mem_settings, WEB_PROCESS_CONSERVATIVE_THRESHOLD);
    webkit_memory_pressure_settings_set_poll_interval(mem_settings, WEB_PROCESS_MEMORY_POLL_INTERVAL_SECONDS);

    WebKitWebsiteDataManager* data_manager = webkit_website_data_manager_new(
            "base-data-directory", data_dir.c_str(),
            "base-cache-directory", data_dir.c_str(),
            nullptr);

    WebKitWebContext* web_context = WEBKIT_WEB_CONTEXT(g_object_new(
        WEBKIT_TYPE_WEB_CONTEXT,
        "website-data-manager", data_manager,
        "memory-pressure-settings", mem_settings,
        nullptr));

    webkit_memory_pressure_settings_free(mem_settings);

    // DIAGNOSTIK: versi RUNTIME webkit2gtk yang benar-benar dimuat (beda
    // dari versi saat compile) -- berguna untuk membandingkan build
    // AppImage vs build langsung kalau ada gejala yang beda antara
    // keduanya.
    //
    // KOREKSI (log sebelumnya menunjukkan "property 'memory-pressure-
    // settings' of object class 'WebKitWebContext' is not readable" dan
    // warning "TIDAK TERPASANG" yang tadinya dicetak di sini): dugaan
    // awal SALAH. Kode sebelumnya membaca balik property ini lewat
    // g_object_get() untuk memverifikasi apakah tersimpan -- ternyata
    // "memory-pressure-settings" pada webkit2gtk versi ini memang
    // WRITE-ONLY (bisa di-set construct-time lewat g_object_new, tapi
    // sengaja TIDAK didesain untuk dibaca balik lewat g_object_get).
    // "Tidak bisa dibaca" BUKAN berarti "tidak tersimpan" -- kalau
    // property-nya benar-benar tidak dikenali WebKitWebContext, GLib akan
    // mencetak warning "has no property named 'memory-pressure-settings'"
    // saat g_object_new() di atas dipanggil, BUKAN "is not readable" saat
    // dibaca balik. Karena warning "has no property named" itu TIDAK
    // pernah muncul, pengaturan batas RAM di atas kemungkinan besar SUDAH
    // benar terpasang sejak awal -- verifikasi lewat baca-balik di sini
    // dihapus karena memang tidak bisa diandalkan untuk property ini.
    static bool logged_webkit_version = false;
    if (!logged_webkit_version) {
        logged_webkit_version = true;
        g_message(
            "[webkit_multi_view] webkit2gtk RUNTIME version terpakai: %u.%u.%u",
            webkit_get_major_version(), webkit_get_minor_version(),
            webkit_get_micro_version());
    }

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
    // NOTE: "enable-javascript-jit" BUKAN properti WebKitSettings yang
    // valid pada WebKitGTK -- tidak pernah ada properti dengan nama ini.
    // g_object_set di atas hanya memicu GLib-GObject-CRITICAL
    // ("has no property named 'enable-javascript-jit'") dan tidak
    // melakukan apa pun; JIT JavaScriptCore sudah aktif secara default.
    // Dihapus.

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
    // Snapshot baseline SEBELUM load_uri memicu WebProcess baru spawn (lihat
    // pid_resolve_baseline di ViewGeometry & FindUnclaimedWebProcessPid) —
    // supaya resolve PID untuk view ini nanti tidak salah mengklaim proses
    // milik view lain yang kebetulan sedang berjalan/direspawn bersamaan.
    std::set<pid_t> pid_resolve_baseline = SnapshotWebProcessPids();
    webkit_web_view_load_uri(webview, url.c_str());

    // Tangkap sinyal saat WebKit membunuh WebProcess ini (baik karena lewat
    // batas RAM di atas, maupun crash biasa) supaya kita bisa reconnect
    // otomatis alih-alih membiarkan akun tampil blank/mati.
    TerminationCallbackData* term_data = new TerminationCallbackData{self, view_id};
    g_signal_connect_data(webview, "web-process-terminated",
                           G_CALLBACK(OnWebProcessTerminated), term_data,
                           FreeTerminationData, static_cast<GConnectFlags>(0));

    // Daftarkan widget ini sebagai drag-dest supaya file yang di-drag dari
    // luar aplikasi (file manager, dsb.) bisa ditangkap dan diteruskan ke
    // Dart (lihat DropCallbackData & OnDragDataReceived di atas untuk
    // alasan kenapa ini perlu ditangani manual, bukan lewat DropTarget
    // Flutter). GTK_DEST_DEFAULT_MOTION | HIGHLIGHT saja (bukan DROP) —
    // sinyal "drag-drop" ditangani manual lewat OnDragDrop di bawah.
    static GtkTargetEntry kDropTargets[] = {
        {const_cast<gchar*>("text/uri-list"), 0, 0},
    };
    gtk_drag_dest_set(webview_widget,
                       static_cast<GtkDestDefaults>(GTK_DEST_DEFAULT_MOTION | GTK_DEST_DEFAULT_HIGHLIGHT),
                       kDropTargets, 1, GDK_ACTION_COPY);
    DropCallbackData* drop_data = new DropCallbackData{self, view_id};
    g_signal_connect_data(webview_widget, "drag-drop", G_CALLBACK(OnDragDrop),
                           drop_data, nullptr, static_cast<GConnectFlags>(0));
    g_signal_connect_data(webview_widget, "drag-motion", G_CALLBACK(OnDragMotion),
                           drop_data, nullptr, static_cast<GConnectFlags>(0));
    g_signal_connect_data(webview_widget, "drag-leave", G_CALLBACK(OnDragLeave),
                           drop_data, nullptr, static_cast<GConnectFlags>(0));
    // Hanya SATU dari koneksi sinyal drop_data ini yang perlu punya
    // destroy-notify (di-free tepat sekali saat widget dihancurkan) —
    // dipasang di sini karena "drag-data-received" adalah yang paling
    // sering benar-benar dipakai.
    g_signal_connect_data(webview_widget, "drag-data-received", G_CALLBACK(OnDragDataReceived),
                           drop_data, FreeDropData, static_cast<GConnectFlags>(0));

    (*self->views)[view_id] = webview;
    ViewGeometry geo{};
    geo.url = url;
    geo.pid_resolve_baseline = pid_resolve_baseline;
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

        // FIX: gtk_widget_set_visible(FALSE) di atas TIDAK otomatis
        // mengembalikan keyboard focus ke FlView. Kalau view ini sedang
        // memegang focus saat di-hide (mis. user habis mengetik di chat),
        // keystroke berikutnya (mis. di dialog password Flutter yang baru
        // ditampilkan lewat showOverlaySafely) tidak akan sampai ke mana
        // pun. Kembalikan fokus secara eksplisit ke Flutter di sini.
        if (self->flutter_view != nullptr) {
            gtk_widget_grab_focus(self->flutter_view);
        }

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

// Injects arbitrary JS into the loaded page — used by the chat-privacy
// blur feature (see chat_blur_css.dart on the Dart side) to install a
// <style> tag, AND (FIX, see below) by the Linux drag-and-drop file-attach
// flow (webview_container.dart / file_drop_injection.dart), which needs
// the script's *return value* to decide what to do next (e.g. did the
// "Document" menu item actually get found and clicked, at which DOM index
// is the target <input type="file">).
//
// SEBELUMNYA: fire-and-forget dengan callback nullptr, jadi respons method
// channel ini SELALU null — cukup untuk chat-blur (cuma butuh efek
// sampingnya), tapi berarti alur drop yang butuh hasil skrip (dipakai
// sudah lebih dulu untuk Windows lewat webview_windows'
// controller.executeScript, yang memang mengembalikan hasil) tidak bisa
// jalan sama sekali di Linux — selalu mendapat null dan langsung dianggap
// gagal di setiap langkah.
//
// SEKARANG: async lewat webkit_web_view_evaluate_javascript_finish(),
// hasilnya diserialisasi ke JSON (jsc_value_to_json) dan dikembalikan
// sebagai string lewat method channel; sisi Dart men-decode JSON itu
// sendiri (lihat runJavaScript di linux_webkit_platform_view.dart), meniru
// persis bentuk nilai balik (Map/num/bool/null) yang sudah dipakai untuk
// Windows.
namespace {
    void OnJsEvalFinished(GObject* source, GAsyncResult* result, gpointer user_data) {
        FlMethodCall* method_call = FL_METHOD_CALL(user_data);
        WebKitWebView* view = WEBKIT_WEB_VIEW(source);

        g_autoptr(GError) error = nullptr;
        JSCValue* value = webkit_web_view_evaluate_javascript_finish(view, result, &error);

        g_autoptr(FlValue) result_value = nullptr;
        if (error != nullptr || value == nullptr) {
            result_value = fl_value_new_null();
        } else {
            g_autofree gchar* json = jsc_value_to_json(value, 0);
            result_value = json != nullptr ? fl_value_new_string(json) : fl_value_new_null();
        }
        if (value != nullptr) g_object_unref(value);

        g_autoptr(FlMethodResponse) response =
            FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
        fl_method_call_respond(method_call, response, nullptr);
        g_object_unref(method_call);
    }
}

static void HandleRunJavaScriptAsync(WebkitMultiViewPlugin* self, FlMethodCall* method_call) {
    FlValue* args = fl_method_call_get_args(method_call);
    const std::string view_id = GetString(args, "viewId");
    const std::string script = GetString(args, "script");
    auto it = self->views->find(view_id);
    if (it == self->views->end() || script.empty()) {
        g_autoptr(FlMethodResponse) response =
            FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
        fl_method_call_respond(method_call, response, nullptr);
        return;
    }
    webkit_web_view_evaluate_javascript(
        it->second,
        script.c_str(),
        -1,        // length: -1 = script null-terminated, WebKit hitung sendiri panjangnya
        nullptr,   // world_name: nullptr = default world
        nullptr,   // source_uri: tidak relevan untuk kita, aman nullptr
        nullptr,   // cancellable
        OnJsEvalFinished,
        g_object_ref(method_call));  // dilepas lagi di OnJsEvalFinished
}

// --- BOILERPLATE INFRASTRUCTURE ---

static void MethodCallCb(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
    WebkitMultiViewPlugin* self = WEBKIT_MULTI_VIEW_PLUGIN(user_data);
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    // "runJavaScript" merespons secara ASYNC (lihat HandleRunJavaScriptAsync
    // / OnJsEvalFinished) sekarang supaya bisa mengembalikan hasil evaluasi
    // JS yang sesungguhnya, bukan langsung null seperti sebelumnya — jadi
    // sengaja di-return lebih awal di sini, TIDAK ikut fl_method_call_respond
    // di bawah (kalau ikut, method call ini akan direspons dua kali, yang
    // menyebabkan CRITICAL dari flutter_linux).
    if (g_strcmp0(method, "runJavaScript") == 0) {
        HandleRunJavaScriptAsync(self, method_call);
        return;
    }

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

WebkitMultiViewPlugin* webkit_multi_view_plugin_new(FlPluginRegistrar* registrar, GtkFixed* container, GtkWidget* flutter_view) {
    WebkitMultiViewPlugin* self = WEBKIT_MULTI_VIEW_PLUGIN(g_object_new(webkit_multi_view_plugin_get_type(), nullptr));
    self->container = container;
    self->flutter_view = flutter_view;
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    self->channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar), WEBKIT_MULTI_VIEW_METHOD_CHANNEL, FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(self->channel, MethodCallCb, g_object_ref(self), g_object_unref);
    return self;
}