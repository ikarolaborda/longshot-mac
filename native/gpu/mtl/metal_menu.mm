// The upstream menu supplies the layout, input and options. Composite its ImGui
// draw lists in a transparent sublayer, outside the game's interpolation history.
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import "backends/imgui_impl_metal.h"
#include "imgui.h"
#include <climits>
#include "../vk/vk_api.h"
#include "metal_menu.h"

namespace mkwvk {
void mac_menu_host(const MkwVkHost *, void *);
void mac_draw_menu(uint32_t, uint32_t, float);
void mac_menu_poll(uint32_t, uint32_t, bool);
int menu_host_option(int, int);
void menu_option_set(int, int);
int menu_setting(int, MkwVkSetting *);
int menu_setting_set(const char *, int, MkwVkSetting *);
void menu_init();
bool menu_is_open();
namespace ui { bool begin_metal(uint32_t, uint32_t, float); }
}
extern "C" int hos_mac_resolution_option(int);
static bool active;
extern "C" int longshot_mac_overlay_active() { return active; }

static void tick(void *gameLayer, int toggle) {
    @autoreleasepool {
        CAMetalLayer *game = (__bridge CAMetalLayer *)gameLayer;
        static CAMetalLayer *overlay;
        static id<MTLCommandQueue> queue;
        static double last;
        CGSize size = game.drawableSize;
        if (size.width < 1 || size.height < 1) return;
        // Keep polling input on the SDL thread even when no overlay needs drawing.
        mkwvk::mac_menu_poll(size.width, size.height, toggle);
        if (!mkwvk::menu_is_open()) { if (overlay && !overlay.hidden) overlay.hidden = YES; return; }
        double now = CACurrentMediaTime();
        if (overlay && !overlay.hidden && now - last < 1.0/60) return;
        float dt = last ? now-last : 1.0/60;
        last = now;
        if (!overlay) {
            if (!game.device) return;
            ImGui::CreateContext();
            ImGui::GetIO().IniFilename = nullptr;
            ImGui::GetIO().LogFilename = nullptr;
            if (!ImGui_ImplMetal_Init(game.device)) { ImGui::DestroyContext(); return; }
            queue = [game.device newCommandQueue];
            overlay = [CAMetalLayer layer];
            overlay.actions = @{@"hidden":NSNull.null, @"bounds":NSNull.null, @"position":NSNull.null};
            overlay.device = game.device;
            overlay.opaque = NO;
            overlay.pixelFormat = MTLPixelFormatBGRA8Unorm;
            [game addSublayer:overlay];
        }
        overlay.hidden = NO;
        overlay.frame = game.bounds;
        if (!CGSizeEqualToSize(overlay.drawableSize,size)) overlay.drawableSize = size;
        id<CAMetalDrawable> drawable = [overlay nextDrawable];
        if (!drawable) return;
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0);
        ImGui_ImplMetal_NewFrame(pass);
        mkwvk::ui::begin_metal(size.width,size.height,dt);
        mkwvk::mac_draw_menu(size.width,size.height,dt);
        ImGui::Render();
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),cb,enc);
        [enc endEncoding];
        [cb presentDrawable:drawable];
        [cb commit];
    }
}
static int option(int id) {
    if (id == 2 || id == 3) return hos_mac_resolution_option(id);
    // The Metal renderer and the game supply the defaults for backend-specific options.
    switch (id) {
    case HOS_OPT_RENDER_THREAD:
    case HOS_OPT_NATIVE_ZSTD:
    case HOS_OPT_HDR_NATIVE:
    case HOS_OPT_HDR_TONEMAP:
    case HOS_OPT_DLSS_JITTER_W:
    case HOS_OPT_DLSS_JITTER_H:
    case HOS_OPT_DLSS_JITTER_PHASES:
        return INT_MIN;
    default:
        return mkwvk::menu_host_option(id, INT_MIN);
    }
}
extern "C" __attribute__((visibility("default"))) const LongshotMetalMenu *
longshot_mac_menu_start(const MkwVkHost *host, void *window) {
    active = true;
    mkwvk::mac_menu_host(host,window);
    mkwvk::menu_init();
    static const LongshotMetalMenu menu{tick,option,mkwvk::menu_option_set,mkwvk::menu_setting,mkwvk::menu_setting_set};
    return &menu;
}
