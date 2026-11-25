#pragma once
#include <stdint.h>

void hos_mac_collection_focus(uint64_t screen);
void hos_mac_collection_tick(uint64_t screen);
int hos_mac_collection_toggle(void);
int hos_mac_collection_stick(int down);
void hos_mac_collection_overlay(void *layer);
