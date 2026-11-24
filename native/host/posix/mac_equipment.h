#pragma once
#include <stdint.h>

/* The assignable item is an enum identifying a slot. Bottle contents and acquisition
   flags are deliberately absent from this format. Equipment strings are actor names. */
enum { MAC_EQUIP_FIELDS = 7, MAC_SET_COUNT = 3 };
typedef struct {
    uint32_t item;
    char gear[MAC_EQUIP_FIELDS][64];
} MacEquipmentSet;
void hos_mac_sets_load(const char *profile);
void hos_mac_set_request(int slot, int capture);
int hos_mac_take_set_request(int *slot, int *capture);
int hos_mac_read_set(int child, int slot, MacEquipmentSet *out);
int hos_mac_write_set(int child, int slot, const MacEquipmentSet *in);
void hos_mac_set_item_label(uint32_t item, char *out, unsigned cap);
void hos_mac_inventory_selection(const char *actor);
void hos_mac_set_feedback(const char *message);
void hos_mac_sets_install_menu(void);
int hos_oot_gamedata_enum(uint32_t hash, uint32_t *value);
int hos_oot_equipment_available(const char *name);
int hos_oot_equipment_status(int index, const char **name);
int hos_oot_equipment_status_named(const char *name);
void hos_mac_inventory_focus(const char *page, const char *button, uint64_t screen);
void hos_mac_inventory_tick(uint64_t screen);
void hos_mac_equipment_overlay(void *layer);
