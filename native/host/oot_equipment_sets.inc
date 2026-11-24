/* Equipment presets run at Link's update on the game thread. Use the same GameData
   setters as the game's equipment UI, so observers get the ordinary change notice. */
#include "posix/mac_equipment.h"

static const uint32_t set_gear_fields[MAC_EQUIP_FIELDS] = {
    0xa95a3521u, 0xee463235u, 0x3615e379u, 0x59d9c7b3u,
    0x008d7f0cu, 0xd107a85du, 0xb72cd3fcu
};
static const struct { uint32_t key; const char *label, *actor; } set_items[] = {
#include "oot_assignable_items.inc"
};

static int oot_set_item_index(uint32_t key) {
    for (size_t i = 0; i < sizeof set_items / sizeof *set_items; ++i)
        if (set_items[i].key == key) return (int)i;
    return -1;
}
void hos_mac_set_item_label(uint32_t item, char *out, unsigned cap) {
    const int row = oot_set_item_index(item);
    const char *label = row < 0 ? "Item" : set_items[row].label;
    if (strncmp(label, "Bottle", 6) || label[6] < 'A' || label[6] > 'E') {
        snprintf(out, cap, "%s", label);
        return;
    }
    const uint32_t fields[] = {0x7d48df76u, 0x1edd164au, 0xb80c70a8u, 0xe4c1b1fcu, 0x365e1953u};
    const char *content = "Contents unavailable";
    uint32_t value;
    if (hos_oot_gamedata_enum(fields[label[6] - 'A'], &value)) {
        switch (value) {
        case 0xbe69de49u: content = "Empty"; break;
        case 0xeaba6067u: content = "Red Potion"; break;
        case 0x049d37c1u: content = "Green Potion"; break;
        case 0xf383d6e5u: content = "Blue Potion"; break;
        case 0x1c293517u: content = "Blue Fire"; break;
        case 0x1e834ef8u: content = "Fish"; break;
        case 0x0f24e808u: content = "Ruto's Letter"; break;
        case 0xcdc21471u: content = "Big Poe"; break;
        case 0x02084f9eu: content = "Poe"; break;
        case 0x74d62ecbu: content = "Bugs"; break;
        case 0x6f49e357u: content = "Fairy"; break;
        case 0x73356827u: content = "Milk"; break;
        case 0xeef6e4b0u: content = "Half-full Milk"; break;
        }
    }
    snprintf(out, cap, "Bottle %c · %s", label[6], content);
}
static int oot_set_available(Ctx *c, const char *name) {
    return !*name || hos_oot_equipment_available(name) || oot_pouch_count(c, name) > 0;
}
static int oot_set_apply(Ctx *c, uint32_t field, const MacEquipmentSet *current, const MacEquipmentSet *wanted) {
    uint64_t mgr = oot_singleton(c, OOT_GAMEDATA_SLOT);
    A64Fn set_enum = a64_lookup(0x80400980), set_text = a64_lookup(0x80d44e50);
    if (!mgr || !set_enum || !set_text) return 0;
    if (current->item != wanted->item) {
        const int row = oot_set_item_index(wanted->item);
        if (row < 0 || !oot_set_available(c, set_items[row].actor)) return 0;
    }
    for (int i = 0; i < MAC_EQUIP_FIELDS; ++i)
        if (strcmp(current->gear[i], wanted->gear[i]) && !oot_set_available(c, wanted->gear[i])) return 0;

    const Ctx saved = *c;
    uint64_t frame = (saved.x[31] - 0xa0) & ~15ULL;
    for (int i = 0; i < MAC_EQUIP_FIELDS; ++i) {
        if (!strcmp(current->gear[i], wanted->gear[i])) continue;
        *c = saved;
        memcpy(A64_PTR(frame + 0x40), wanted->gear[i], 64);
        recomp_store64_sp(c, frame, frame + 0x40);
        c->x[31] = frame;
        c->x[0] = mgr, c->x[1] = frame, c->x[2] = set_gear_fields[i], c->x[3] = UINT32_MAX;
        set_text(c);
    }
    if (current->item != wanted->item) {
        *c = saved;
        c->x[0] = mgr, c->x[1] = wanted->item, c->x[2] = field, c->x[3] = UINT32_MAX;
        set_enum(c);
    }
    *c = saved;
    return 1;
}
static void oot_equipment_request(Ctx *c) {
    int slot, capture;
    if (!hos_mac_take_set_request(&slot, &capture)) return;
    int child = 0, loading = 1;
    if (!oot_gamedata_bool(c, 0xcea220d3, &child) || !oot_gamedata_bool(c, 0xef2b60c2, &loading) ||
        loading || hos_oot_event_playing(c)) {
        hos_mac_set_feedback("Equipment sets are available in gameplay.");
        return;
    }
    MacEquipmentSet current = {0};
    const uint32_t field = child ? 0xa0029837u : 0xbc32ce24u;
    if (!hos_oot_gamedata_enum(field, &current.item)) return;
    for (int i = 0; i < MAC_EQUIP_FIELDS; i++)
        if (!oot_gamedata_string(c, set_gear_fields[i], current.gear[i], sizeof current.gear[i])) return;
    MacEquipmentSet wanted;
    char message[128];
    if (capture) {
        snprintf(message, sizeof message, hos_mac_write_set(child, slot, &current) ? "Saved equipment set %d." :
                 "Could not save equipment set %d.", slot + 1);
    } else if (!hos_mac_read_set(child, slot, &wanted)) {
        snprintf(message, sizeof message, "Save equipment set %d for %s Link first.", slot + 1, child ? "child" : "adult");
    } else if (!oot_set_apply(c, field, &current, &wanted)) {
        snprintf(message, sizeof message, "Equipment set %d contains an unavailable item.", slot + 1);
    } else {
        char item[64];
        hos_mac_set_item_label(wanted.item, item, sizeof item);
        snprintf(message, sizeof message, "Equipped set %d · %s", slot + 1, item);
    }
    hos_mac_set_feedback(message);
    if (getenv("HOS_EQUIPMENT_TRACE")) hos_log("equipment: %s current item %08x", message, current.item);
}
