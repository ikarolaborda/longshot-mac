// Run on macOS with clang -fobjc-arc response_timing.m -framework QuartzCore -o /tmp/response-test
#import <QuartzCore/QuartzCore.h>
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>

static double sampleTime;
static double testClock(void) { return sampleTime; }
#define CACurrentMediaTime testClock
#import "../../../host/posix/mac_response.m"
#undef CACurrentMediaTime

// Scene tracing has its own clock and game-state tests.
void hos_scene_submit(uint64_t id) { (void)id; }
void hos_scene_display(uint64_t id, double when) { (void)id; (void)when; }

static unsigned reports;
void hos_log(const char *format, ...) {
    if (strstr(format, "response sample")) reports++;
}

static uint64_t frame;
static int canFill, simulateFill;
static const int32_t sticks[4] = {0};

// Model completed displays using a monotonic clock. Input is observed every
// twentieth game frame, with a known delay between guest sampling and display.
static void play(double *now, int fps, double lag, int withInput) {
    for (int i = 0; i <= 3 * fps + 2; ++i) {
        ++frame;
        *now += 1.0 / fps;
        sampleTime = *now - lag;
        if (withInput) hos_mac_response_input((frame / 20) % 2, sticks);
        hos_mac_response_submit(frame);
        hos_mac_response_present(frame, *now, simulateFill && frame % 2);
    }
    hos_mac_response_evaluate(*now, 240, 1, canFill);
}

int main(void) {
    setenv("HOS_METAL_TIMING", "1", 1);
    hos_mac_response_reset(1);
    hos_mac_response_input(0, sticks);
    sampleTime = 1;
    hos_mac_response_input(1, sticks);
    hos_mac_response_submit(1);
    assert(hos_mac_response_waiting());
    assert(!hos_mac_response_allows_fill(1.01));
    hos_mac_response_present(1, 1.02, 1);
    hos_mac_response_present(1, 0, 0);
    assert(reports == 0);
    hos_mac_response_present(1, 1.03, 0);
    hos_mac_response_present(1, 1.04, 0);
    assert(reports == 1);
    assert(!hos_mac_response_waiting());
    hos_mac_response_evaluate(1.05, 240, 1, 1);
    sampleTime = 1.10;
    unsigned extras = 0;
    for (int i = 0; i < 81; ++i)
        extras += hos_mac_response_allows_fill(1.06 + i/80.0);
    assert(extras >= 39 && extras <= 40);  // 80 real frames leave room for 40 generated
    sampleTime = 2;
    hos_mac_response_input(0, sticks);
    hos_mac_response_submit(2);
    hos_mac_response_submit(258);
    hos_mac_response_present(2, 2.03, 0);
    assert(reports == 1);
    hos_mac_response_present(258, 2.04, 0);
    assert(reports == 2);
    hos_mac_response_reset(1);
    hos_mac_response_present(258, 2.05, 0);
    assert(reports == 2);

    sampleTime = 3;
    hos_mac_response_input(0, sticks);
    hos_mac_response_input(1, sticks);
    sampleTime += .01;
    hos_mac_response_input(0, sticks);
    hos_mac_response_submit(259);
    hos_mac_response_present(259, 3.05, 0);
    assert(reports == 4);
    hos_mac_response_reset(1);

    double now = 4;
    hos_mac_response_evaluate(now, 240, 1, canFill);
    play(&now, 120, .030, 0);
    assert(hos_mac_response_target(240) == 120);
    play(&now, 120, .030, 1);
    assert(hos_mac_response_target(240) == 144);
    play(&now, 144, .020, 1);
    assert(hos_mac_response_target(240) == 144);
    play(&now, 144, .050, 1);
    assert(hos_mac_response_target(240) == 120);
    play(&now, 120, .030, 1);
    assert(hos_mac_response_target(240) == 120);
    now += 31;
    play(&now, 120, .030, 1);
    assert(hos_mac_response_target(240) == 144);
    for (int i = 0; i < 2; ++i) {
        play(&now, 144, .020, 0);
        assert(hos_mac_response_target(240) == 144);
    }
    play(&now, 144, .020, 0);
    assert(hos_mac_response_target(240) == 120);
    hos_mac_response_evaluate(now, 60, 1, canFill);
    assert(hos_mac_response_target(60) == 60);
    hos_mac_response_evaluate(now, 240, 0, canFill);
    assert(hos_mac_response_target(240) == 120);
    canFill = 1;
    play(&now, 85, .030, 1);
    assert(hos_mac_response_wants_fill());
    simulateFill = 1;
    play(&now, 122, .020, 1);
    assert(hos_mac_response_wants_fill());
    play(&now, 82, .040, 1);
    play(&now, 82, .040, 1);
    assert(!hos_mac_response_wants_fill());
    play(&now, 85, .030, 1);
    assert(!hos_mac_response_wants_fill());
    hos_mac_response_reset(0);
    assert(!hos_mac_response_active());
    puts("PASS: input correlation, real-frame priority, display and loading resets, rate selection, interpolation and cooldown");
}
