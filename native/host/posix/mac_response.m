#include "../scene_trace.h"
#import <QuartzCore/QuartzCore.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "mac_response.h"

extern void hos_log(const char *, ...);

// A submission keeps the latest guest input at that point. The drawable may be
// presented much later, on a different thread, or superseded by a newer frame.
typedef struct {
    uint64_t frame;
    uint64_t inputSerial;
} InputFrame;

typedef struct {
    double first, last;
    double ages[256], gaps[512];
    unsigned frames, generated, agesUsed, gapsUsed;
} Window;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic int active, trace, target, fill;
static InputFrame submitted[256];
static Window window;
static double inputTimes[256], retryAt, baselineAge, baselineFPS, baselineGap;
static uint64_t latest, reported;
static double lastFillFrame, fillCredit;
static double fillRetryAt, nativeFPS, nativeGap, nativeAge;
static int fillMisses, trialIdleWindows;
static uint64_t lastButtons;
static int lastAxes[4], screenHz, inputInitialized;
enum RateState { AT_120, TRY_144, AT_144 };
static enum RateState rateState;

void hos_mac_response_reset(int enabled) {
    pthread_mutex_lock(&lock);
    const char *value = getenv("HOS_METAL_TIMING");
    atomic_store(&trace, value ? atoi(value) : 0);
    atomic_store(&active, enabled);
    atomic_store(&target, 120);
    memset(submitted, 0, sizeof submitted);
    window = (Window){0};
    latest = reported = 0;
    lastFillFrame = fillCredit = 0;
    atomic_store(&fill, 0);
    fillMisses = 0;
    fillRetryAt = 0;
    retryAt = 0;
    rateState = AT_120;
    screenHz = inputInitialized = 0;
    pthread_mutex_unlock(&lock);
}

void hos_mac_response_discard_window(void) {
    pthread_mutex_lock(&lock);
    lastFillFrame = fillCredit = 0;
    window = (Window){0};
    pthread_mutex_unlock(&lock);
}

int hos_mac_response_active(void) {
    return atomic_load(&active);
}

int hos_mac_response_wants_fill(void) {
    return atomic_load(&fill);
}

/* Spend only the part of the display budget left over after real frames.
 * A control already sampled by the game takes priority through the first
 * displayed game frame that carries it, including over older work in flight. */
int hos_mac_response_allows_fill(double now) {
    pthread_mutex_lock(&lock);
    double elapsed = now - lastFillFrame;
    int hz = hos_mac_response_target(screenHz);
    if (latest != reported || !lastFillFrame || elapsed <= 0 || elapsed > .1) {
        fillCredit = 0;
    } else {
        fillCredit += elapsed * hz - 1;
        if (fillCredit < 0) fillCredit = 0;
        if (fillCredit > 2) fillCredit = 2;
    }
    lastFillFrame = now;
    int allow = fillCredit >= 1;
    if (allow) fillCredit -= 1;
    pthread_mutex_unlock(&lock);
    return allow;
}

int hos_mac_response_waiting(void) {
    pthread_mutex_lock(&lock);
    int waiting = latest != reported;
    pthread_mutex_unlock(&lock);
    return waiting;
}

int hos_mac_response_target(int hz) {
    int cap = atomic_load(&target);
    return hz < cap ? hz : cap;
}

void hos_mac_response_input(uint64_t buttons, const int32_t axes[4]) {
    if (!atomic_load(&active) && !atomic_load(&trace)) return;
    int quantized[4];
    for (int i = 0; i < 4; ++i) quantized[i] = axes[i] / 4096;
    pthread_mutex_lock(&lock);
    if (inputInitialized && (buttons != lastButtons || memcmp(quantized, lastAxes, sizeof lastAxes))) {
        double now = CACurrentMediaTime();
        inputTimes[++latest % 256] = now;
    }
    inputInitialized = 1;
    lastButtons = buttons;
    memcpy(lastAxes, quantized, sizeof lastAxes);
    pthread_mutex_unlock(&lock);
}

void hos_mac_response_submit(uint64_t frame) {
    hos_scene_submit(frame);
    if (!atomic_load(&active) && !atomic_load(&trace)) return;
    pthread_mutex_lock(&lock);
    submitted[frame % 256] = (InputFrame){frame, latest};
    pthread_mutex_unlock(&lock);
}

void hos_mac_response_present(uint64_t frame, double shown, int generated) {
    if (shown > 0 && !generated) hos_scene_display(frame, shown);
    if (shown <= 0 || (!atomic_load(&active) && !atomic_load(&trace))) return;
    double matched[256];
    unsigned matches = 0;
    const int logInputs = atomic_load(&trace);
    pthread_mutex_lock(&lock);
    InputFrame input = submitted[frame % 256];
    if (frame && input.frame == frame && shown > window.last) {
        if (!window.frames) window.first = shown;
        if (window.frames && window.gapsUsed < 512)
            window.gaps[window.gapsUsed++] = (shown - window.last) * 1000;
        window.last = shown;
        ++window.frames;
        window.generated += !!generated;
        if (!generated && input.inputSerial > reported) {
            // A long frame can span both a press and its release. Count both
            // against the first real drawable that follows them.
            uint64_t first = reported + 1;
            if (latest >= 256 && first <= latest - 256) first = latest - 255;
            for (uint64_t serial = first; serial <= input.inputSerial; ++serial) {
                double time = inputTimes[serial % 256];
                if (time > shown) break;
                if (window.agesUsed < 256)
                    window.ages[window.agesUsed++] = (shown - time) * 1000;
                if (logInputs) matched[matches++] = time;
                reported = serial;
            }
        }
    }
    pthread_mutex_unlock(&lock);
    if (atomic_load(&trace) >= 2)
        hos_log("Metal timing display: shown=%.9f frame=%llu generated=%d", shown, (unsigned long long)frame, generated);
    for (unsigned i = 0; i < matches; ++i)
        hos_log("Metal response sample: guest=%.9f shown=%.9f frame=%llu", matched[i], shown, (unsigned long long)frame);
}

// Optional drawable sampling for on-display benchmarks. A record contains two
// uint64 values (guest frame and generated flag) followed by a 32 x 32 luma tile.
// Match those keys to presentedTime in the timing log to exclude dropped frames.
static FILE *pixelTrace;
int hos_mac_response_open_pixels(void) {
    const char *path = getenv("HOS_METAL_PIXEL_TRACE");
    const char *timing = getenv("HOS_METAL_TIMING");
    if (path && *path && timing && atoi(timing) >= 2) {
        pixelTrace = fopen(path, "wbx");
        if (!pixelTrace) hos_log("Metal timing: could not create the pixel trace");
    }
    return pixelTrace != NULL;
}

void hos_mac_response_record_pixels(uint64_t frame, int generated, const uint8_t *bgra) {
    struct { uint64_t frame, generated; uint8_t luma[32 * 32]; } record = {frame, !!generated, {0}};
    for (unsigned y = 0; y < 32; ++y) {
        for (unsigned x = 0; x < 32; ++x) {
            const uint8_t *p = bgra + 4 * ((4 * y + 2) * 128 + 4 * x + 2);
            record.luma[y * 32 + x] = (29 * p[0] + 150 * p[1] + 77 * p[2]) >> 8;
        }
    }
    fwrite(&record, sizeof record, 1, pixelTrace);
}

static int compareTime(const void *a, const void *b) {
    const double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static double percentile95(double *samples, unsigned count) {
    qsort(samples, count, sizeof *samples, compareTime);
    return samples[(95 * count + 99) / 100 - 1];
}

// Compare generated frames with the native cadence from this display and scene.
// Two poor windows prevent a single shader compilation from switching modes.
static int updateFill(double now, int hz, int canInterpolate, double fps, double gap, double age) {
    if (!canInterpolate || hz < 100) return 0;
    if (!atomic_load(&fill)) {
        if (now < fillRetryAt || fps >= hos_mac_response_target(hz) * .94) return 0;
        nativeFPS = fps;
        nativeGap = gap;
        nativeAge = age;
        fillMisses = 0;
        atomic_store(&fill, 1);
        return 1;
    }
    const int improved = window.generated && fps >= nativeFPS + 4 && gap <= nativeGap + 1;
    const int responsive = !age || !nativeAge || age <= nativeAge + 8;
    fillMisses = improved && responsive ? 0 : fillMisses + 1;
    if (fillMisses < 2) return 0;
    atomic_store(&fill, 0);
    fillRetryAt = now + 30;
    return 1;
}

void hos_mac_response_evaluate(double now, int hz, int gameplay, int canInterpolate) {
    if (!atomic_load(&active)) return;
    pthread_mutex_lock(&lock);
    if (hz != screenHz || !gameplay) {
        window = (Window){0};
        screenHz = hz;
        lastFillFrame = fillCredit = 0;
        atomic_store(&fill, 0);
        fillMisses = 0;
        fillRetryAt = now + 3;
        rateState = AT_120;
        atomic_store(&target, 120);
        retryAt = now + 3;
    } else if (window.gapsUsed && window.last - window.first >= 3) {
        const double fps = (window.frames - 1) / (window.last - window.first);
        const double gap = percentile95(window.gaps, window.gapsUsed);
        const int enoughInput = window.agesUsed >= 4;
        const double age = enoughInput ? percentile95(window.ages, window.agesUsed) : 0;
        if (updateFill(now, hz, canInterpolate, fps, gap, age)) {
            rateState = AT_120;
            atomic_store(&target, 120);
            retryAt = now + 3;
        } else if (hz >= 144) {
            if (rateState == AT_120) {
                if (enoughInput && fps >= 112 && now >= retryAt) {
                    trialIdleWindows = 0;
                    baselineAge = age;
                    baselineFPS = fps;
                    baselineGap = gap;
                    atomic_store(&target, 144);
                    rateState = TRY_144;
                }
            } else if (fps < 120 || gap > baselineGap + 1 || (enoughInput && age > baselineAge + 500.0 / hz) ||
                       (rateState == TRY_144 && (fps < baselineFPS + 5 || (!enoughInput && ++trialIdleWindows >= 3)))) {
                atomic_store(&target, 120);
                rateState = AT_120;
                retryAt = now + 30;
            } else if (rateState == TRY_144 && enoughInput) {
                rateState = AT_144;
            }
        }
        window = (Window){0};
    }
    pthread_mutex_unlock(&lock);
}
