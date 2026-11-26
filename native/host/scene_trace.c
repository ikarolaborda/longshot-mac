#ifdef __APPLE__
#include "scene_trace.h"
#include "../gpu/vk/compat/longshot_env.h"
#include <stdatomic.h>
#include <pthread.h>
#include <os/signpost.h>
#include <time.h>
#include <stdio.h>
#include <string.h>

extern void hos_log(const char *, ...);
static pthread_once_t once = PTHREAD_ONCE_INIT;
static int enabled;
static os_log_t log_handle;
static struct { _Atomic uint64_t ns, bytes, last; } work[2];
static _Atomic uint64_t since_ready, latest_submitted, first_eligible;

static void configure(void) {
    enabled = env_on("HOS_SCENE_TRACE");
    if (enabled) log_handle = os_log_create("dev.longshot.metal", OS_LOG_CATEGORY_POINTS_OF_INTEREST);
}
uint64_t hos_scene_begin(void) {
    pthread_once(&once, configure);
    return enabled ? clock_gettime_nsec_np(CLOCK_UPTIME_RAW) : 0;
}
void hos_scene_end(enum scene_work kind, uint64_t start, uint64_t bytes) {
    if (!start) return;
    uint64_t end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    atomic_fetch_add_explicit(&work[kind].bytes, bytes, memory_order_relaxed);
    atomic_fetch_add_explicit(&work[kind].ns, end - start, memory_order_relaxed);
    uint64_t prev = atomic_load_explicit(&work[kind].last, memory_order_relaxed);
    while (prev < end && !atomic_compare_exchange_weak_explicit(&work[kind].last, &prev, end,
            memory_order_relaxed, memory_order_relaxed)) {}
    if (end - start >= 1000000 && os_signpost_enabled(log_handle))
        os_signpost_event_emit(log_handle, OS_SIGNPOST_ID_EXCLUSIVE, "Completed asset work",
            "kind=%d bytes=%llu duration_us=%llu", kind, bytes, (end-start)/1000);
}
/* Called on the player update thread. Capture totals even if this scene did no I/O. */
void hos_scene_state(const char *map, int flags) {
    uint64_t now = hos_scene_begin();
    if (!now) return;
    static char previous[80];
    static int last_flags = -1;
    int phase = flags & 3;
    if (phase == last_flags && !strcmp(map, previous)) return;
    last_flags = phase;
    snprintf(previous, sizeof previous, "%s", map);
    atomic_store(&first_eligible, atomic_load(&latest_submitted) + 1);
    atomic_store(&since_ready, phase ? 0 : now);
    os_signpost_event_emit(log_handle, OS_SIGNPOST_ID_EXCLUSIVE, "Scene state", "%{public}s flags=%d", map, phase);
    hos_log("Scene phase: at=%.9f map=%s event=%d loading=%d read_bytes=%llu read_ms=%.3f last_read=%.9f decode_bytes=%llu decode_ms=%.3f last_decode=%.9f",
        now/1e9,map,phase&1,phase>>1,atomic_load(&work[0].bytes),atomic_load(&work[0].ns)/1e6,
        atomic_load(&work[0].last)/1e9,atomic_load(&work[1].bytes),atomic_load(&work[1].ns)/1e6,atomic_load(&work[1].last)/1e9);
}
void hos_scene_submit(uint64_t frame) {
    pthread_once(&once, configure);
    if (enabled) atomic_store(&latest_submitted, frame);
}
void hos_scene_display(uint64_t frame, double shown) {
    uint64_t ready = atomic_load_explicit(&since_ready, memory_order_relaxed);
    if (ready && frame >= atomic_load(&first_eligible) && shown >= ready/1e9 && atomic_compare_exchange_strong(&since_ready, &ready, 0)) {
        os_signpost_event_emit(log_handle, OS_SIGNPOST_ID_EXCLUSIVE, "First game presentation after ready", "frame=%llu", frame);
        hos_log("Scene presentation: ready=%.9f shown=%.9f frame=%llu",ready/1e9,shown,frame);
    }
}
#endif
