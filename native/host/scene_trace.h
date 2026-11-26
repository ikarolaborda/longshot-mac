#pragma once
#include <stdint.h>

/* Times use the same monotonic uptime as Metal's presentedTime. Durations
   from different worker threads overlap and must not be added to wall time. */
enum scene_work { SCENE_FILE_READ, SCENE_ZSTD };
#ifdef __APPLE__
uint64_t hos_scene_begin(void);
void hos_scene_end(enum scene_work kind, uint64_t start, uint64_t bytes);
void hos_scene_state(const char *map, int flags);
void hos_scene_submit(uint64_t frame);
void hos_scene_display(uint64_t frame, double shown);
#else
static inline uint64_t hos_scene_begin(void) { return 0; }
static inline void hos_scene_end(enum scene_work kind, uint64_t start, uint64_t bytes) {
    (void)kind; (void)start; (void)bytes;
}
#endif
