// Services the shared settings UI can ask of the native Mac renderer.
#pragma once
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>
#include <windows.h>
#include "vk_api.h"
#include "gpu_choice.h"
#include "longshot_env.h"
#include "vk_ui_fonts.h"
#include "menu_upscale_types.h"

struct ImTextureData;
namespace mkwvk {
extern const MkwVkHost *host;
extern std::vector<std::string> gpu_device_names;
extern std::vector<gpu_choice::Card> gpu_device_cards;
extern std::atomic<bool> present_native_pq;
struct MenuDevice {
    struct { uint32_t width, height; } swap_extent{};
    bool hdr = false;
};
extern MenuDevice dev;
void logf(const char *, ...);
inline int64_t prof_now() {
    using namespace std::chrono;
    return duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count();
}
int shot_ask_next(const char *, void (*)(void *, int64_t, int), void *);
void pipeline_cache_save(bool);
void menu_debug_rows(int, int);
void samplers_changed();
std::string device_report_text();
uint64_t device_vram_bytes();
std::string state_list_snapshot(bool *);
unsigned usable_cpus();
unsigned usable_cores();
bool pools_mirrored();
void dlss_probe();
void dlss_fg_probe();
void xess_probe();
namespace reshade {
void select(int);
void preview_bypass(bool);
void preview_select(int, std::string);
void preview_end(int);
void select_user(std::string);
std::vector<std::string> user_presets();
std::string user_selection();
std::string status();
}
bool dlss_built();
DlssWhy dlss_why();
int dlss_fg_skip(unsigned *);
int dlss_fg_unavailable();
int dlss_fg_most();
bool dlss_fg_forced();
int framegen_capped(int, int);
FgMaker framegen_maker();
bool fsr3_wanted();
namespace fsr3 { bool supported(); }
namespace fsr3fi { uint32_t frames_wanted(); }
bool xess_built();
XessWhy xess_why();
bool reflex_available();
bool antilag_available();
int temporal_mode();
bool temporal_off();
void temporal_reset_failure();
namespace ui {
const Fonts& fonts();
void prebake(const float *, int);
ImTextureData *logo(float *);
}
}
