/* clang scene_timing.c ../../../host/scene_trace.c -o /tmp/scene-timing
   Exercise the same scene-state and presentation callbacks used by Metal. */
#include "../../../host/scene_trace.h"
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned states, displays;
static char last_state[1024];

void hos_log(const char *format, ...) {
    if (strstr(format, "Scene presentation")) displays++;
    if (strstr(format, "Scene phase")) {
        states++;
        va_list args;
        va_start(args, format);
        vsnprintf(last_state, sizeof last_state, format, args);
        va_end(args);
    }
}

int main(int argc, char **argv) {
    int enabled = argc == 2 && !strcmp(argv[1], "on");
    setenv("HOS_SCENE_TRACE", enabled ? "1" : "0", 1);
    uint64_t start = hos_scene_begin();
    assert((start != 0) == enabled);
    hos_scene_end(SCENE_FILE_READ, start, 67);
    hos_scene_end(SCENE_ZSTD, start, 249);
    hos_scene_state("village", 2);
    hos_scene_submit(15);
    hos_scene_state("field", 0);
    hos_scene_state("field", 4);  /* Age changes alone do not open a new phase. */
    double now = hos_scene_begin()/1e9;
    hos_scene_display(15, now);   /* In flight before the transition. */
    assert(displays == 0);
    hos_scene_submit(16);
    hos_scene_display(16, now);
    hos_scene_display(16, now);
    assert(states == 2u * (unsigned)enabled && displays == (unsigned)enabled);
    if (enabled) {
        assert(strstr(last_state, "map=field") && strstr(last_state, "read_bytes=67 "));
        assert(strstr(last_state, "decode_bytes=249 "));
    }
    hos_scene_state("village", 0);
    hos_scene_submit(17);
    hos_scene_state("village", 1);  /* A new event cancels a pending ready marker. */
    hos_scene_display(17, hos_scene_begin()/1e9);
    assert(displays == (unsigned)enabled);
    puts("PASS: scene I/O, decode, state and first displayed game frame");
}
