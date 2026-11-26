#pragma once

namespace mkwvk {
enum DlssWhy { DLSS_OK, DLSS_NOT_BUILT, DLSS_ENV_OFF, DLSS_NEEDS_RTX, DLSS_NEEDS_DRIVER, DLSS_NO_RUNTIME,
               DLSS_RUNTIME_NOT_ASCII, DLSS_WHY_COUNT };

enum FgSkip {
    FG_SKIP_NONE,
    FG_SKIP_OFF,        // (RX_VK_DLSS_FG=0 for the run)
    FG_SKIP_DEVICE,     // (DLSS does not run on this GPU)
    FG_SKIP_START,      // (NGX did not start it: no runtime, an older GPU)
    FG_SKIP_TOO_MANY,   // (more made frames than its runtime makes)
    FG_SKIP_INPUTS,     // (no picture from a temporal Upscaler this frame)
    FG_SKIP_REFUSED,    // (NGX refused the set)
    FG_SKIP_NOT_BUILT,  // (a build without NVIDIA's SDK)
    FG_SKIP_COUNT
};

enum XessWhy { XESS_OK, XESS_NOT_BUILT, XESS_ENV_OFF, XESS_NO_LIBRARY, XESS_NO_VULKAN, XESS_UNSUPPORTED, XESS_WHY_COUNT };

enum class FgMaker { None, BuiltIn, Dlss, Fsr3, DlssPaused };
}
