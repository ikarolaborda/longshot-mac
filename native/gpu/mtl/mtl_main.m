/* (longshot-mac) The native Metal back end, longshot_mtl.dylib: the same one export as the Vulkan back end (mkwvk_init,
   gpu/vk/vk_api.h), loaded by host/rx_backend.c when RX_RENDERER=metal. docs/macos-metal.md has the plan.

   Milestone 1 (this file): the Metal device, the window's CAMetalLayer (host/posix/display_sdl.c makes it on the main
   thread), presents paced by the display (up to its refresh: 120 Hz on ProMotion), and the recordings walked in submit
   order. What a recording does that the CPU can see is done here, in order, before its fence completes: events, counter
   reports, buffer copies, updates and fills (the same values the Vulkan back end writes, gpu/vk/vk_replay.cpp). Draws and
   dispatches are counted, not drawn: the picture is a clear colour until the replay into Metal lands (milestone 2, from
   MacNativeGames' NVN-on-Metal layer, MIT). Whatever a shader would have written (a compute pass's buffers) is missing,
   and said so in the log, not faked. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <limits.h>
#include <stdatomic.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MKWVK_BUILDING 1
#include "../vk/vk_api.h"

static const MkwVkHost *host;
static MkwVkRenderer table;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static CAMetalLayer *layer;
static char described[256];

/* fences: submits are walked synchronously, so a submit's fence is complete when nvn_submit returns */
static _Atomic uint64_t pushed, completed;
static _Atomic int64_t presents, draws, skipped;
static _Atomic int64_t op_counts[NOP_COUNT_ + 1];
static pthread_mutex_t submit_lock = PTHREAD_MUTEX_INITIALIZER;   /* (submit order across the game's queues) */
static int options[128];   /* (option_set: what the game's side changed; option answers these, else the defaults) */
static unsigned char option_known[128];
static volatile int width = 1280, height = 720;

static void logf_(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void logf_(const char *fmt, ...) {
    char line[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (host && host->log) host->log(line);
    else fprintf(stderr, "%s\n", line);
}

/* ---- the recordings: BEGIN .. END, contiguous (host/nvn_native.c flatten) ---- */
static int gpu_copy(uint64_t dst, uint64_t src, uint64_t n) {
    uint64_t da = 0, sa = 0;
    uint8_t *d = host->gpu_ptr(dst, &da), *s = host->gpu_ptr(src, &sa);
    if (!d || !s || da < n || sa < n) return 0;
    memmove(d, s, n);
    host->mark_written(d, n);
    return 1;
}
static void walk(const uint8_t *p) {
    for (;;) {
        nvn_op_hdr h;
        memcpy(&h, p, sizeof h);
        const uint8_t *a = p + sizeof h;
        const uint32_t avail = h.size > sizeof h ? h.size - (uint32_t)sizeof h : 0;
        if (h.op <= NOP_COUNT_) atomic_fetch_add_explicit(&op_counts[h.op], 1, memory_order_relaxed);
        switch (h.op) {
        case NOP_END: return;
        case NOP_SIGNAL_EVENT: {
            nvn_p_signal e = {0};
            memcpy(&e, a, avail < sizeof e ? avail : sizeof e);
            uint32_t v = e.value;
            if (e.mode == NVN_EVENT_SIGNAL_MODE_ADD) {
                uint32_t old = 0;
                host->gpu_read(e.gpu, &old, 4);
                v = old + e.value;
            }
            host->gpu_write(e.gpu, &v, 4);
            break;
        }
        case NOP_REPORT_COUNTER: {   /* (vk_replay.cpp's values: samples passed read 4096, everything visible; timestamps on
                                        the counter clock, 19.2 MHz, from the guest tick) */
            nvn_p_counter c = {0};
            memcpy(&c, a, avail < sizeof c ? avail : sizeof c);
            const int samples = (uint32_t)c.type == NVN_COUNTER_TYPE_SAMPLES_PASSED;
            const uint64_t ns = host->ticks() * 32;
            const uint64_t rec[2] = {samples ? 4096u : 0u, ns * 12 / 625};
            if (c.type & NVN_COUNTER_WRITTEN) host->gpu_write(c.addr + 8, rec + 1, 8);
            else host->gpu_write(c.addr, rec, sizeof rec);
            break;
        }
        case NOP_COPY_B2B: {
            nvn_p_copy_bb c = {0};
            memcpy(&c, a, avail < sizeof c ? avail : sizeof c);
            if (c.size && !gpu_copy(c.dst, c.src, c.size)) atomic_fetch_add_explicit(&skipped, 1, memory_order_relaxed);
            break;
        }
        case NOP_UPDATE_UB: {
            nvn_p_update_ub u = {0};
            memcpy(&u, a, avail < sizeof u ? avail : sizeof u);
            if (u.size && sizeof u + u.size <= avail) host->gpu_write(u.dst, a + sizeof u, u.size);
            break;
        }
        case NOP_CLEAR_BUF: {
            nvn_p_clear_buf c = {0};
            memcpy(&c, a, avail < sizeof c ? avail : sizeof c);
            uint64_t n = 0;
            uint8_t *d = host->gpu_ptr(c.dst, &n);
            if (d && n >= c.size) {
                for (uint64_t i = 0; i + 4 <= c.size; i += 4) memcpy(d + i, &c.value, 4);
                host->mark_written(d, c.size);
            }
            break;
        }
        case NOP_DRAW: case NOP_DRAW_IDX: case NOP_DRAW_INDIRECT: case NOP_DRAW_MESH:
            atomic_fetch_add_explicit(&draws, 1, memory_order_relaxed);
            atomic_fetch_add_explicit(&skipped, 1, memory_order_relaxed);
            break;
        case NOP_DISPATCH: case NOP_DISPATCH_INDIRECT: {   /* (a compute pass's writes are not made: said once) */
            static int said;
            if (!said++) logf_("mtl: dispatches are not run yet (milestone 1): what compute writes stays as it was");
            atomic_fetch_add_explicit(&skipped, 1, memory_order_relaxed);
            break;
        }
        default: break;   /* (state, binds, render targets: the replay's, milestone 2) */
        }
        if (h.size < sizeof h) {   /* (a broken record: stop rather than spin) */
            logf_("mtl: a record of op %u with size %u: the rest of the recording is left", h.op, h.size);
            return;
        }
        p += h.size;
    }
}

static void submit_q(const uint64_t *handles, int n, uint64_t q) {
    (void)q;
    pthread_mutex_lock(&submit_lock);
    for (int i = 0; i < n; i++)
        if (handles[i]) walk((const uint8_t *)(uintptr_t)handles[i]);
    const uint64_t v = atomic_fetch_add(&pushed, 1) + 1;
    atomic_store(&completed, v);
    pthread_mutex_unlock(&submit_lock);
}
static void submit(const uint64_t *handles, int n) { submit_q(handles, n, 0); }
static uint64_t fence(void) { return atomic_load(&pushed); }
static uint64_t fence_q(uint64_t q) { (void)q; return atomic_load(&pushed); }
static uint64_t get_pushed(void) { return atomic_load(&pushed); }
static uint64_t get_replayed(void) { return atomic_load(&completed); }
static int fence_wait(uint64_t f, uint64_t timeout_ns) { (void)timeout_ns; return atomic_load(&completed) >= f; }
static void wait_writebacks_reading(const void *p, uint64_t n) { (void)p, (void)n; }
static void finish(void) {}

/* ---- presenting: the clear colour, paced by the layer's drawables (the display's refresh) ---- */
static void op_report(void) {
    static const char *names[] = {"END", "JUMP", "BEGIN", "CALL", "SIGNAL_EVENT", "REPORT_COUNTER", "COPY_B2B", "UPDATE_UB",
        "SET_RT", "CLEAR_COLOR", "CLEAR_DS", "VIEWPORTS", "SCISSOR", "DEPTH_RANGE", "BIND_PROGRAM", "BIND_STATE",
        "BIND_VATTR", "BIND_VSTREAM", "BIND_VBUF", "BIND_UBO", "BIND_SSBO", "BIND_TEX", "BIND_SAMP", "STENCIL", "POLY_OFFSET",
        "DRAW", "DRAW_IDX", "DISPATCH", "BARRIER", "SET_TEX_POOL", "SET_SAMP_POOL", "COPY_B2T", "COPY_STRIDE", "BLEND_COLOR",
        "COPY_T2B", "BIND_IMG", "COPY_T2T", "RESET_COUNTER", "CLEAR_TEX", "DEPTH_CLAMP", "RENDER_ENABLE", "RASTER_DISCARD",
        "RENDER_COND", "PRIMITIVE_RESTART", "BIND_BUFS", "DRAW_INDIRECT", "DISPATCH_INDIRECT", "DRAW_MESH", "WAIT_EVENT",
        "PUSH_CONST", "CLEAR_BUF"};
    char line[2048];
    int k = snprintf(line, sizeof line, "mtl: ops so far:");
    for (int i = 0; i < NOP_COUNT_ && k < (int)sizeof line - 40; i++) {
        const int64_t c = atomic_load_explicit(&op_counts[i], memory_order_relaxed);
        if (c) k += snprintf(line + k, sizeof line - k, " %s %lld", i < (int)(sizeof names / sizeof *names) ? names[i] : "?",
                             (long long)c);
    }
    logf_("%s", line);
}
static void present(const nvn_tex *t, const int crop[4]) {
    (void)t, (void)crop;
    const int64_t n = atomic_fetch_add(&presents, 1) + 1;
    static int64_t window_start_ns, window_presents;
    const int64_t now = host->now_ns();
    if (!window_start_ns) window_start_ns = now;
    window_presents++;
    if (now - window_start_ns >= 2000000000LL) {
        logf_("mtl: %.1f presents/s (%lld so far, %lld draws recorded)", window_presents * 1e9 / (double)(now - window_start_ns),
              (long long)n, (long long)atomic_load(&draws));
        if (n < 2000 || n % 6000 < 300) op_report();
        window_start_ns = now, window_presents = 0;
    }
    if (!layer) return;
    @autoreleasepool {
        id<CAMetalDrawable> d = [layer nextDrawable];   /* (blocks while every drawable is in flight: the display's pace) */
        if (!d) return;
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = d.texture;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0.05, 0.09, 0.07, 1.0);
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        [cb presentDrawable:d];
        [cb commit];
    }
}

static int start(void *hwnd) {
    if (!hwnd) return 1;   /* (longshot --prepare-shaders: nothing to prepare yet) */
    const MkwVkWindow *w = (const MkwVkWindow *)hwnd;
    if (w->version < 4 || !w->metal_layer || !(layer = (__bridge CAMetalLayer *)w->metal_layer(w->window))) {
        logf_("mtl: the window has no Metal layer (window bridge version %u): nothing is drawn", w->version);
        return 0;
    }
    layer.device = device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = NO;   /* (the NVN layer, third_party/d2r_gfx, copies and upscales into the drawable: MacNativeGames' frontend sets the same) */
    layer.displaySyncEnabled = YES;
    int pw = 0, ph = 0;
    if (w->drawable_size) w->drawable_size(w->window, &pw, &ph);
    if (pw > 0 && ph > 0) width = pw, height = ph, layer.drawableSize = CGSizeMake(pw, ph);
    const int mhz = w->refresh_mhz ? w->refresh_mhz(w->window) : 0;
    logf_("mtl: presenting into the window's layer, %dx%d, display %.2f Hz", width, height, mhz / 1000.0);
    return 1;
}
static void resize(int w, int h) {
    if (w <= 0 || h <= 0) return;
    width = w, height = h;
    CAMetalLayer *l = layer;
    if (l) dispatch_async(dispatch_get_main_queue(), ^{ l.drawableSize = CGSizeMake(w, h); });
}
static const char *describe(void) { return described; }
static void stats(int64_t *d, int64_t *s, int64_t *pipelines) {
    *d = atomic_load(&draws), *s = atomic_load(&skipped), *pipelines = 0;
}

/* ---- the rest: nothing to keep yet (textures, samplers and programs are the replay's, milestone 2) ---- */
static void register_texture(int id, const nvn_tex *t, const nvn_view *v) { (void)id, (void)t, (void)v; }
static void register_sampler(int id, const nvn_samp_par *p) { (void)id, (void)p; }
static void set_texture_pool_size(int n) { (void)n; }
static void texture_released(const nvn_tex *t) { (void)t; }
static void program_released(const nvn_prog *p) { (void)p; }
static void program_created(const nvn_prog *p) { (void)p; }
static void texture_created(const nvn_tex *t) { (void)t; }
static void read_texels(const nvn_tex *t, unsigned level, unsigned layer0, const NVNcopyRegion *r, uint8_t *dst,
                        uint64_t row_pitch, uint64_t image_pitch) {
    (void)t, (void)level, (void)layer0, (void)r, (void)dst, (void)row_pitch, (void)image_pitch;
    static int said;
    if (!said++) logf_("mtl: texel reads are not answered yet (milestone 1): the game reads zeros");
}
static void write_texels(const nvn_tex *t, unsigned level, unsigned layer0, const NVNcopyRegion *r, const uint8_t *src,
                         uint64_t row_pitch, uint64_t image_pitch) {
    (void)t, (void)level, (void)layer0, (void)r, (void)src, (void)row_pitch, (void)image_pitch;
}
static void invalidate(uint64_t gpu, uint64_t size) { (void)gpu, (void)size; }
static int invalidate_quick(uint64_t gpu, uint64_t size) { (void)gpu, (void)size; return 1; }
static void pool_created(uint64_t gpu, uint64_t size) { (void)gpu, (void)size; }
static int guest_imported(uint64_t lo, uint64_t hi) { (void)lo, (void)hi; return 0; }
static void vmap_changing(uint64_t gpu, uint64_t size) { (void)gpu, (void)size; }
static void event_signal(uint64_t gpu, uint32_t value) { (void)gpu, (void)value; }   /* (the host wrote it: in order already) */
static int option(int id) {
    /* Flight uses -1 for disabled. Zero arms double-tap Jump. Metal does not
       offer the debug flight control, so this option is always disabled. */
    if (id == HOS_OPT_CHEAT_FLIGHT) return -1;
    if (id >= 0 && id < 128 && option_known[id]) return options[id];
    switch (id) {
    case 0: return 1;              /* game time follows the clock */
    case 6: return 1;              /* Mouse camera: native mouse look (shooter-style controls) */
    case 7: return 100;            /* mouse sensitivity, percent */
    case HOS_OPT_VOLUME: return 100;
    case 48: return 100;           /* camera turn speed, percent */
    default: return INT_MIN;   /* The caller supplies the game default for options outside this renderer. */
    }
}
static void option_set(int id, int value) {
    if (id == HOS_OPT_CHEAT_FLIGHT) return;
    if (id >= 0 && id < 128) options[id] = value, option_known[id] = 1;
}
static void jitter_sample(MkwVkJitter *out) { memset(out, 0, sizeof *out); }
static void frame_info(int64_t *p, int64_t *d, int *w, int *h) {
    *p = atomic_load(&presents), *d = atomic_load(&draws), *w = width, *h = height;
}
static int shot(const char *path, int64_t after, void (*done)(void *, int64_t, int), void *ctx) {
    (void)path, (void)after, (void)done, (void)ctx;
    return 0;
}
static int setting(int index, MkwVkSetting *out) { (void)index, (void)out; return 0; }
static int setting_set(const char *key, int value, MkwVkSetting *out) { (void)key, (void)value, (void)out; return 0; }

__attribute__((visibility("default"))) const MkwVkRenderer *mkwvk_init(const MkwVkHost *h) {
    if (!h || h->version != MKWVK_API_VERSION) {
        fprintf(stderr, "mtl: host version %u, this back end is %u\n", h ? h->version : 0, MKWVK_API_VERSION);
        return NULL;
    }
    host = h;
    device = MTLCreateSystemDefaultDevice();
    if (!device) {
        logf_("mtl: no Metal device");
        return NULL;
    }
    queue = [device newCommandQueue];
    snprintf(described, sizeof described, "%s (Metal)", device.name.UTF8String);
    logf_("mtl: %s; unified memory %s, Apple GPU family 9 %s, Metal 4 %s, mesh shaders %s", device.name.UTF8String,
          device.hasUnifiedMemory ? "yes" : "no", [device supportsFamily:MTLGPUFamilyApple9] ? "yes" : "no",
          [device supportsFamily:MTLGPUFamilyMetal4] ? "yes" : "no",
          [device supportsFamily:MTLGPUFamilyApple7] ? "yes" : "no");
    logf_("report: gpu %s (Metal)", device.name.UTF8String);
    memset(&table, 0, sizeof table);
    table.version = h->version;
    table.start = start;
    table.resize = resize;
    table.describe = describe;
    table.stats = stats;
    table.nvn_submit = submit;
    table.nvn_fence = fence;
    table.nvn_pushed = get_pushed;
    table.nvn_replayed = get_replayed;
    table.nvn_wait = fence_wait;
    table.wait_writebacks_reading = wait_writebacks_reading;
    table.nvn_finish = finish;
    table.nvn_present = present;
    table.nvn_register_texture = register_texture;
    table.nvn_register_sampler = register_sampler;
    table.nvn_set_texture_pool_size = set_texture_pool_size;
    table.nvn_texture_released = texture_released;
    table.nvn_program_released = program_released;
    table.nvn_read_texels = read_texels;
    table.nvn_write_texels = write_texels;
    table.nvn_invalidate = invalidate;
    table.nvn_pool_created = pool_created;
    table.guest_imported = guest_imported;
    table.nvn_vmap_changing = vmap_changing;
    table.nvn_texture_created = texture_created;
    table.nvn_event_signal = event_signal;
    table.option = option;
    table.nvn_submit_q = submit_q;
    table.nvn_fence_q = fence_q;
    table.option_set = option_set;
    table.jitter_sample = jitter_sample;
    table.frame_info = frame_info;
    table.shot = shot;
    table.setting = setting;
    table.setting_set = setting_set;
    table.nvn_program_created = program_created;
    table.nvn_invalidate_quick = invalidate_quick;
    return &table;
}
