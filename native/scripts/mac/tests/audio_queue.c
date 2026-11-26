/* Compile with -I host/posix -Wno-implicit-function-declaration -Wl,-dead_strip
   and host/posix/win32_posix.c on macOS. The SDL mock
   pulls the real waveOut queue with the same 10 ms buffers the game's mixer writes. */
#include <mmsystem.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void (*pull)(void *, uint8_t *, int);
static void *context;

void *hos_sdl_audio_open(unsigned device, int freq, int channels, int s16, int frames,
                         void (*callback)(void *, uint8_t *, int), void *user) {
    (void)device; (void)frames;
    assert(freq == 48000 && (channels == 2 || channels == 6) && s16);
    pull = callback;
    return context = user;
}
void hos_sdl_audio_close(void *audio) { assert(audio == context); }
int hos_sdl_audio_alive(void *audio) { return audio == context; }

static void take(int bytes, int value) {
    uint8_t data[5760];
    assert(bytes <= (int)sizeof data);
    memset(data, 0xff, bytes);
    pull(context, data, bytes);
    for (int i = 0; i < bytes; i++) assert(data[i] == value);
}
static void run(int channels) {
    WAVEFORMATEX format = { .nChannels = channels, .nSamplesPerSec = 48000, .wBitsPerSample = 16 };
    const int size = 480 * channels * 2;
    HWAVEOUT wave;
    uint8_t samples[6][5760];
    WAVEHDR h[6] = {0};
    assert(!waveOutOpen(&wave, WAVE_MAPPER, &format, 0, 0, 0));
    for (int i = 0; i < 6; i++) {
        memset(samples[i], i+1, size);
        h[i].lpData = (LPSTR)samples[i];
        h[i].dwBufferLength = size;
        assert(!waveOutPrepareHeader(wave, h+i, sizeof *h));
    }
    take(size, 0);
    assert(!waveOutWrite(wave, h, sizeof *h));
    take(size / 2, 1);
    assert(h[0].dwFlags & WHDR_INQUEUE);
    assert(!waveOutWrite(wave, h+1, sizeof *h));
    assert(!waveOutWrite(wave, h+2, sizeof *h));
    take(size / 2, 1);
    assert(h[0].dwFlags & WHDR_DONE);
    /* Two more callback bursts before the producer runs. */
    take(size, 2);
    take(size, 3);
    take(size, 0);
    assert(!waveOutWrite(wave, h+3, sizeof *h));
    take(size, 0);
    assert(!waveOutWrite(wave, h+4, sizeof *h));
    assert(!waveOutWrite(wave, h+5, sizeof *h));
    take(size, 4);
    assert(!waveOutReset(wave));
    assert((h[4].dwFlags & WHDR_DONE) && (h[5].dwFlags & WHDR_DONE));
    take(size, 0);
    assert(!waveOutClose(wave));
}
int main(void) {
    run(2);
    run(6);
    puts("Stereo and surround queue start, burst, underrun recovery and reset passed.");
    return 0;
}
