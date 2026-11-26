// Device information and services consumed by the shared Longshot settings UI.
#include "vk_paths.h"
#include "menu_metal_services.h"
#include "vk_fsr4.h"
#include "vk_menu.h"
#include <cstdarg>
extern "C" const char *longshot_menu_device_name();
extern "C" uint64_t longshot_menu_device_budget();

extern "C" void mtl_pipeline_archive_quit(void);
extern "C" int hos_metal_request_shot(const char *, int64_t, void (*)(void *, int64_t, int), void *);
namespace mkwvk {
const MkwVkHost *host;
static HWND window;

MenuDevice dev{};
std::vector<std::string> gpu_device_names;
std::vector<gpu_choice::Card> gpu_device_cards;
std::atomic<bool> present_native_pq{false};

void mac_menu_host(const MkwVkHost *callbacks, void *hwnd) {
    host = callbacks;
    window = (HWND)hwnd;
    gpu_device_names = {longshot_menu_device_name()};
}
HWND app_window() { return window; }
void logf(const char *format, ...) {
    char line[2048];
    va_list args;
    va_start(args, format);
    vsnprintf(line, sizeof line, format, args);
    va_end(args);
    if (host && host->log) host->log(line);
}
std::string options_path() {
    const char *path = host && host->options_path ? host->options_path() : nullptr;
    return path ? path : game_folder_path() + "longshot_options.ini";
}
std::string driver_text() { return "Metal"; }
std::string device_report_text() { return longshot_menu_device_name(); }
uint64_t device_vram_bytes() { return longshot_menu_device_budget(); }
int shot_ask_next(const char *path, void (*done)(void *, int64_t, int), void *context) {
    return hos_metal_request_shot(path, 0, done, context);
}
void pipeline_cache_save(bool) { mtl_pipeline_archive_quit(); }

// The Mac's Graphics tab supplies MetalFX and drawable controls. The shared menu
// consults these capabilities while loading an existing cross-platform options file.
bool dlss_built() { return false; }
DlssWhy dlss_why() { return DLSS_NOT_BUILT; }
void dlss_probe() {}
void dlss_fg_probe() {}
int dlss_fg_skip(unsigned *most) { if (most) *most = 0; return FG_SKIP_NOT_BUILT; }
int dlss_fg_unavailable() { return FG_SKIP_NOT_BUILT; }
int dlss_fg_most() { return 0; }
bool dlss_fg_forced() { return false; }
int framegen_capped(int multiplier, int) { return multiplier; }
FgMaker framegen_maker() { return FgMaker::None; }
bool fsr4_built() { return false; }
void fsr4_probe() {}
FsrWhy fsr4_why() { return FSR_NOT_BUILT; }
int fsr4_model_env() { return -1; }
bool fsr4_lite_available() { return false; }
void fsr4_set_model(Fsr4Model) {}
bool fsr3_wanted() { return false; }
namespace fsr3 { bool supported() { return false; } }
namespace fsr3fi { uint32_t frames_wanted() { return 0; } }
bool xess_built() { return false; }
void xess_probe() {}
XessWhy xess_why() { return XESS_NOT_BUILT; }
bool reflex_available() { return false; }
bool antilag_available() { return false; }
int temporal_mode() { return 0; }
bool temporal_off() { return true; }
void temporal_reset_failure() {}
void samplers_changed() {}
void menu_debug_rows(int, int) {}
bool output_preview_request(uint32_t, uint32_t) { return false; }
int output_preview_seconds() { return 0; }
bool output_preview_answer(bool) { return false; }
uint64_t output_preview_take_rebuilt_size() { return 0; }
std::string state_list_snapshot(bool *present) { if (present) *present = false; return {}; }
namespace reshade {
void preview_end(int) {}
void preview_bypass(bool) {}
void select(int) {}
void select_user(std::string) {}
void preview_select(int, std::string) {}
std::vector<std::string> user_presets() { return {}; }
std::string user_selection() { return {}; }
std::string status() { return {}; }
}
}
