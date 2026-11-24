#pragma once
#include <stdint.h>

enum { MAC_RATE, MAC_INTERPOLATION, MAC_ADAPTIVE, MAC_CAN_INTERPOLATE, MAC_RESPONSIVE };

#ifdef __cplusplus
extern "C" {
#endif
int hos_mac_graphics_get(int setting);
void hos_mac_graphics_set(int setting, int value);
void hos_mac_response_reset(int enabled);
void hos_mac_response_discard_window(void);
int hos_mac_response_active(void);
int hos_mac_response_wants_fill(void);
int hos_mac_response_allows_fill(double now);
int hos_mac_response_waiting(void);
int hos_mac_response_target(int displayHz);
void hos_mac_response_input(uint64_t buttons, const int32_t axes[4]);
void hos_mac_response_submit(uint64_t frame);
void hos_mac_response_present(uint64_t frame, double shown, int generated);
int hos_mac_response_open_pixels(void);
void hos_mac_response_record_pixels(uint64_t frame, int generated, const uint8_t *bgra);
void hos_mac_response_evaluate(double now, int displayHz, int gameplay, int canInterpolate);
#ifdef __cplusplus
}
#endif
