/* SPDX-License-Identifier: GPL-3.0-or-later
   (longshot-mac) The Metal renderer's NVN layer (third_party/d2r_gfx, from MacNativeGames) behind Longshot's lifted code.

   d2r_gfx was written for a runtime that runs the game at its own addresses: its NVN functions take host pointers
   and are called with the AArch64 calling convention. Lifted code calls through a Ctx of guest registers and
   reaches guest memory at A64_MEM + address. Each NVN function handed to the game is therefore a hos_hostcall whose
   target is mtl_nvn_call below: it reads x0-x7 and d0-d7 from the Ctx, moves the arguments its row in
   mtl_nvn_sigs.h marks as pointers into host memory, calls the d2r_gfx function, and moves a pointer result back.
   No NVN function takes more than 8 integer or 8 floating-point arguments (gen_nvn_glue.py checks), so nothing is
   read from the guest stack. The host functions d2r_gfx expects of its runtime follow: the ones this port uses are
   built on Longshot's own, the VR, HDR, survey and shader-warming hooks are empty. */
#include "hos.h"
#ifdef __APPLE__
#include <pthread.h>
#include <setjmp.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { MTL_RET_VOID, MTL_RET_INT, MTL_RET_FP, MTL_RET_PTR, MTL_RET_RAW };
typedef struct { const char *name; uint32_t ptr, fn, arr; uint8_t nint, ret; } MtlNvnSig;
#include "mtl_nvn_sigs.h"

uint64_t hos_hostcall(const char *name, void (*fn)(Ctx *, void *), void *user);
void hos_vi_native_acquire(int active);
void hos_vi_native_presented(const int64_t phases[4]);
int hos_vi_native_interval(Ctx *c, int requested);
extern volatile int64_t hos_present_count;
void hos_metal_before_present(int64_t frame);

typedef struct { void *fn; MtlNvnSig sig; const struct MtlNvnStructArrayT *sas; int pace; } MtlNvnProc;

/* (the guest window: 1 TB above A64_MEM covers the image, heap and every pool; a host pointer outside it is handed
   back unchanged and logged, since the game cannot use it) */
static const uint64_t kGuestSpan = 1ull << 40;
static inline uint64_t g2h(uint64_t a) { return a ? (uint64_t)(uintptr_t)(A64_MEM + a) : 0; }
static uint64_t h2g(uint64_t p, const char *name) {
    const uint64_t base = (uint64_t)(uintptr_t)A64_MEM;
    if (!p) return 0;
    if (p >= base && p - base < kGuestSpan) return p - base;
    static atomic_int logged;
    if (atomic_fetch_add(&logged, 1) < 20) hos_log("mtl: %s returned host pointer %#llx outside guest memory", name, (unsigned long long)p);
    return p;
}

typedef uint64_t (*CallInt)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, double,
                            double, double, double, double, double, double, double);
typedef double (*CallFp)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, double,
                         double, double, double, double, double, double, double);

/* Arrays of structs that hold a guest pointer: the copy the call gets has each translated. The count is the argument
   before the array; the Metal layer copies the entries before it returns (its MapVirtual applies them at once,
   ProgramSetShaders keeps them by value), so the copy lives for the call only. */
typedef struct MtlNvnStructArrayT { const char *name; int arg; uint32_t stride, ptr_off; int keep; } MtlNvnStructArray;
static const MtlNvnStructArray kStructArrays[] = {
    {"nvnMemoryPoolMapVirtual", 2, 0x28, 0x00, 0},     /* NVNmappingRequest: the physical pool (gfx/nvn/totk_vpool.h) */
    {"nvnProgramSetShaders", 2, 0x10, 0x08, 0},        /* NVNshaderData: the control section, after the data address */
    {"nvnProgramSetShadersExt", 2, 0x18, 0x08, 0},     /* NVNshaderDataExt: data, control, reserved (hle_nvn.c) */
    /* (NVN2) the builder keeps the array until nvnProgramInitializeFromBuilder: the copy is kept per builder */
    {"nvnProgramBuilderSetShaders", 2, 0x10, 0x08, 1},
};
static const MtlNvnStructArray *struct_array_of(const char *name) {
    for (size_t i = 0; i < sizeof kStructArrays / sizeof *kStructArrays; i++)
        if (!strcmp(kStructArrays[i].name, name)) return &kStructArrays[i];
    return NULL;
}

static struct { uint64_t obj; void *copy; } *kept;
static size_t nkept;
static pthread_mutex_t kept_lock = PTHREAD_MUTEX_INITIALIZER;
static void kept_swap(uint64_t obj, void *copy) {
    pthread_mutex_lock(&kept_lock);
    size_t i;
    for (i = 0; i < nkept && kept[i].obj != obj; i++) {}
    if (i == nkept) {
        kept = realloc(kept, (nkept + 1) * sizeof *kept);
        kept[nkept].obj = obj, kept[nkept].copy = NULL;
        nkept++;
    }
    free(kept[i].copy);
    kept[i].copy = copy;
    pthread_mutex_unlock(&kept_lock);
}

static void mtl_nvn_call(Ctx *c, void *user) {
    const MtlNvnProc *p = (const MtlNvnProc *)user;
    uint64_t x[8];
    double d[8];
    uint64_t arrays[2][16];   /* (nvnWindowBuilderSetTextures, nvnCommandBufferSetRenderTargets: both copy the elements before returning) */
    int narrays = 0;
    for (int i = 0; i < 8; i++) {
        uint64_t v = c->x[i];
        if (p->sig.arr >> i & 1 && v && i > 0 && narrays < 2) {
            int j = i - 1;   /* (the count: the nearest argument before that is not itself an array) */
            while (j > 0 && p->sig.arr >> j & 1) j--;
            const int64_t n = (int64_t)(int32_t)c->x[j];
            const uint64_t *src = (const uint64_t *)(uintptr_t)g2h(v);
            uint64_t *dst = arrays[narrays++];
            for (int64_t k = 0; k < n && k < 16; k++) dst[k] = g2h(src[k]);
            v = (uint64_t)(uintptr_t)dst;
        } else if (p->sig.ptr >> i & 1) v = g2h(v);
        else if (p->sig.fn >> i & 1 && v) {   /* (a guest callback: not called back yet; dropped and logged) */
            static atomic_int logged;
            if (atomic_fetch_add(&logged, 1) < 20) hos_log("mtl: %s: guest callback %#llx not passed to the Metal layer", p->sig.name, (unsigned long long)v);
            v = 0;
        }
        x[i] = v;
        memcpy(&d[i], &c->vreg[i][0], 8);   /* (raw bits: a float argument is read from the low 32 by the callee) */
    }
    /* Longshot's frame pacing and time step (host/nn_vi.c), as host/nvn_native.c calls them: the frame-rate cap holds
       the acquire, and each present is timed so that game speed follows real time at any frame rate */
    if (p->pace == 4 && (c->x[1] & 0x3fff) && c->x[2] >= 0x10000)   /* (diagnostic) pool storage off the host's 16 KB pages */
        hos_log("mtl: pool storage %#llx size %#llx is not 16 KB aligned (lr %#llx)", (unsigned long long)c->x[1], (unsigned long long)c->x[2], (unsigned long long)c->x[30]), hos_backtrace();
    if (p->pace == 1) hos_vi_native_acquire(3);
    else if (p->pace == 2) hos_metal_before_present(__atomic_load_n(&hos_present_count, __ATOMIC_RELAXED) + 1);
    else if (p->pace == 3) c->x[1] = (uint64_t)hos_vi_native_interval(c, (int)c->x[1]), x[1] = c->x[1];
    void *struct_copy = NULL;
    if (p->sas && c->x[p->sas->arg]) {
        const int64_t n = (int64_t)(int32_t)c->x[p->sas->arg - 1];
        if (n > 0 && n < (1 << 20)) {
            struct_copy = malloc((size_t)n * p->sas->stride);
            memcpy(struct_copy, (const void *)(uintptr_t)x[p->sas->arg], (size_t)n * p->sas->stride);
            for (int64_t k = 0; k < n; k++) {
                uint64_t *f = (uint64_t *)((uint8_t *)struct_copy + k * p->sas->stride + p->sas->ptr_off);
                *f = g2h(*f);
            }
            x[p->sas->arg] = (uint64_t)(uintptr_t)struct_copy;
            if (p->sas->keep) {   /* (one copy per object, x0: the one it replaces is freed) */
                kept_swap(x[0], struct_copy);
                struct_copy = NULL;
            }
        }
    }
    if (p->sig.ret == MTL_RET_FP) {
        const double r = ((CallFp)p->fn)(x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]);
        memcpy(&c->vreg[0][0], &r, 8);
        c->vreg[0][1] = 0;
        free(struct_copy);
        return;
    }
    const uint64_t r = ((CallInt)p->fn)(x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]);
    if (p->pace == 2) {
        __atomic_add_fetch(&hos_present_count, 1, __ATOMIC_RELAXED);
        hos_vi_native_presented((const int64_t[4]){0, 0, 0, 0});
    }
    free(struct_copy);
    if (p->sig.ret == MTL_RET_PTR) c->x[0] = h2g(r, p->sig.name);
    else if (p->sig.ret != MTL_RET_VOID) c->x[0] = r;
}

static int cmp_sig(const void *a, const void *b) { return strcmp(((const MtlNvnSig *)a)->name, ((const MtlNvnSig *)b)->name); }

/* d2r_gfx's nvnBootstrapLoader and nvnDeviceGetProcAddress hand each NVN function to the game through this: the
   result is a guest address lifted code can call. One per name, kept for the process. */
void *runtime_hle_wrap_named(void *fn, const char *name) {
    static struct { const char *name; void *fn; uint64_t addr; } *made;
    static size_t nmade;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    if (!fn) return NULL;
    pthread_mutex_lock(&lock);
    for (size_t i = 0; i < nmade; i++)
        if (made[i].fn == fn && !strcmp(made[i].name, name)) {
            const uint64_t a = made[i].addr;
            pthread_mutex_unlock(&lock);
            return (void *)(uintptr_t)a;
        }
    MtlNvnProc *p = (MtlNvnProc *)calloc(1, sizeof *p);
    p->fn = fn;
    const MtlNvnSig key = {name, 0, 0, 0, 0, 0};
    const MtlNvnSig *s = (const MtlNvnSig *)bsearch(&key, mtl_nvn_sigs, sizeof mtl_nvn_sigs / sizeof *mtl_nvn_sigs,
                                                    sizeof *mtl_nvn_sigs, cmp_sig);
    if (s) p->sig = *s;
    else if (!strcmp(name, "nvnBootstrapLoader")) p->sig = (MtlNvnSig){"nvnBootstrapLoader", 0x1, 0, 0, 1, MTL_RET_RAW};
    else {   /* (a name with no prototype: d2r_gfx answers it with its unimplemented entry, which stops the game) */
        p->sig = (MtlNvnSig){strdup(name), 0x1, 0, 0, 8, MTL_RET_RAW};   /* (NVN's first argument is always its object) */
        hos_log("mtl: %s has no prototype: its arguments pass unchanged", name);
    }
    if (!p->sig.name) p->sig.name = strdup(name);
    p->sas = struct_array_of(p->sig.name);
    p->pace = !strcmp(name, "nvnWindowAcquireTexture") ? 1 : !strcmp(name, "nvnQueuePresentTexture") ? 2
            : !strcmp(name, "nvnWindowSetPresentInterval") ? 3 : !strcmp(name, "nvnMemoryPoolBuilderSetStorage") ? 4 : 0;
    const uint64_t a = hos_hostcall(p->sig.name, mtl_nvn_call, p);
    made = realloc(made, (nmade + 1) * sizeof *made);
    made[nmade].name = p->sig.name, made[nmade].fn = fn, made[nmade].addr = a;
    nmade++;
    pthread_mutex_unlock(&lock);
    return (void *)(uintptr_t)a;
}

/* ---- the host d2r_gfx expects (third_party/d2r_gfx/host/*.h and its weak imports) ---- */
typedef struct { const char *name; uint8_t *base; size_t size; } module_t;

uint64_t g_t0_ns;
__attribute__((constructor)) static void mtl_t0(void) { g_t0_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
uint64_t guest_ns(void) { return now_ns(); }

void *display_metal_layer(void);   /* host/posix/display_sdl.c: made on the main thread with the window */
void *front_metal_layer(void) { return display_metal_layer(); }
void front_frame_presented(void) {}
uint64_t front_game_res(int docked) { (void)docked; return (uint64_t)720 << 32 | 1280; }   /* (height << 32 | width, as MacNativeGames' frontend: OoT's default 3D size) */

/* (one module, the game's main image: d2r_gfx names a caller by its offset in "main") */
module_t *module_of(const void *p) {
    static module_t main_mod = {"main", NULL, 0};
    const uint64_t a = (uint64_t)(uintptr_t)p - (uint64_t)(uintptr_t)A64_MEM;
    if (a >= 0x80000000ull && a < 0x100000000ull) {
        main_mod.base = A64_MEM + 0x80000000ull, main_mod.size = 0x80000000ull;
        return &main_mod;
    }
    return NULL;
}
int runtime_module_offset(uint64_t pc, const char **name, uint64_t *off) {
    module_t *m = module_of((const void *)(uintptr_t)pc);
    if (!m) return 0;
    *name = m->name, *off = pc - (uint64_t)(uintptr_t)m->base;
    return 1;
}
void runtime_describe_address(uint64_t a, char *out, size_t n) { snprintf(out, n, "%#llx", (unsigned long long)a); }

static void (*guest_write_prep)(void *, size_t);
void dm_guest_write_prep_register(void (*fn)(void *, size_t)) { guest_write_prep = fn; }
void dm_guest_write_prepare(void *addr, size_t n) { if (guest_write_prep) guest_write_prep(addr, n); }
/* The layer write-protects the memory of textures and buffers it has uploaded and learns of the game's writes from
   the faults (gfx/nvn/nvn_dirty.c). mtl_fault is called first by the signal handler (host/posix/win32_posix.c):
   1 when the layer took the fault (the access is run again), or its guarded read of guest memory is left through
   runtime_fault_guard. */
static int (*fault_hook)(void *, int, void *);
void dm_fault_hook_register(int (*fn)(void *, int, void *)) { fault_hook = fn; }
void dm_res_report_register(void (*fn)(uint32_t, const char *)) { (void)fn; }
void crash_set_wait_dump(void (*fn)(void)) { (void)fn; }
int dm_detclock_enabled(void) { return 0; }
void dm_guest_frame_tick(void) {}
void dm_shot_written(const char *path, int ok) { (void)path, (void)ok; }

__thread sigjmp_buf *runtime_fault_guard;
int mtl_fault(void *addr, int is_write, void *uc) {
    if (fault_hook && fault_hook(addr, is_write, uc)) return 1;
    if (runtime_fault_guard) siglongjmp(*runtime_fault_guard, 1);
    return 0;
}
void (*runtime_abort_hook)(void);
uintptr_t runtime_frame_controller_return_pc(void) { return 0; }
/* NVN_BLOCKING surrounds submit, acquire, fence and presentation waits.
   Let the other game threads load the next area while Metal finishes its work. */
int runtime_core_away(void) { return hos_vcore_away(); }
void runtime_core_back(int *away) { if (*away) hos_vcore_back(); }
int runtime_setting_word(const char *name, char *word, size_t size) { (void)name, (void)word, (void)size; return 0; }
void runtime_settings_toggle(void) {}
void runtime_watch_set(uintptr_t addr, size_t len) { (void)addr, (void)len; }
void runtime_watch_tick(void) {}

/* (the VR, HDR, survey, shader-warming and movie hooks of MacNativeGames' runtime: not part of this port) */
int front_hdr_enabled(void) { return 0; }
float front_hdr_headroom(void) { return 1.0f; }
void front_hdr_parameters(float *values) { (void)values; }
void front_hdr_present_mode(int enabled) { (void)enabled; }
int front_hdr_supported(void) { return 0; }
void movie_host_tick(void) {}
float runtime_aspect_now(void) { return 16.0f / 9.0f; }
void runtime_audio_hold(int on) { (void)on; }
void (*runtime_audio_tap)(float *out, unsigned frames, int rate);
void runtime_boot_count(const char *what, uint64_t done, uint64_t total) { (void)what, (void)done, (void)total; }
void runtime_boot_status(const char *title, const char *detail) { hos_log("mtl: %s: %s", title, detail); }
void runtime_frame_step_update(uint64_t now) { (void)now; }
void runtime_frametrace_event(int kind) { (void)kind; }
uintptr_t runtime_player_pos_address(void) { return 0; }
_Atomic int runtime_survey_pending;
const int32_t runtime_survey_sync[2];
void runtime_survey_tick(uint64_t frame) { (void)frame; }
void (*runtime_vr_haptic)(int, float, float);
int (*runtime_vr_pad)(int, uint64_t *, int32_t *, int32_t *, int32_t *, int32_t *);
void (*runtime_vr_recenter)(void);
void runtime_warm_done(void) {}
void runtime_warm_progress(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f) { (void)a, (void)b, (void)c, (void)d, (void)e, (void)f; }
void runtime_warm_title(void) {}
#endif   /* __APPLE__ */

/* nx2/oot_patches.py patch_texture_pool_align: f_809de920's entry, w3 the alignment of the texture pool's storage */
void hos_texture_pool_align(Ctx *c) {
#ifdef __APPLE__
    int hos_renderer_metal(void);
    const int32_t a = (int32_t)c->x[3];
    if (hos_renderer_metal() && a >= 0 && a < 0x4000) c->x[3] = 0x4000;
#else
    (void)c;
#endif
}
