#include "hos.h"
#include "oot_trainer.h"
#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>

static atomic_int enabled[OOT_TRAINER_OPTION_COUNT];

int hos_trainer_enabled(enum OotTrainerOption option) {
    return atomic_load_explicit(&enabled[option], memory_order_relaxed);
}

void hos_trainer_set(enum OotTrainerOption option, int on) {
    atomic_store_explicit(&enabled[option], !!on, memory_order_relaxed);
    hos_log("trainer: option %d %s", option, on ? "on" : "off");
}

void hos_oot_trainer_horse(Ctx *c) {
    if (!hos_trainer_enabled(OOT_TRAINER_CARROTS)) return;
    uint32_t maximum = (uint32_t)c->x[23];
    if (maximum && maximum <= INT16_MAX)
        recomp_store16(c, c->x[21] + 0x27c, (uint16_t)maximum);
}

void hos_oot_trainer_clock(Ctx *c) {
    if (hos_trainer_enabled(OOT_TRAINER_CLOCK)) a64_vset64(c->vreg[9], 0);
}

/* The player's accessory factory resolves the instrument (13) and its holder
   (16) from PlayerStatus.EquipOcarina. A borrowed item has no saved selection.
   Supply the model to this call only, including when the player is in a lesson. */
void hos_oot_trainer_ocarina(Ctx *c) {
    const unsigned slot = (unsigned)c->x[20];
    if ((slot != 13 && slot != 16) || !(c->x[0] & 1) ||
        !hos_trainer_enabled(OOT_TRAINER_EQUIPMENT)) return;
    const char *equipped = hos_guest_range(c->x[1], 1);
    if (!equipped || *equipped) return;
    const uint64_t fairy = 0x83f33e21ULL;  /* Actor-name literal in the supported build. */
    const char *name = hos_guest_range(fairy, sizeof "Item_Ocarina_Fairy");
    if (name && !memcmp(name, "Item_Ocarina_Fairy", sizeof "Item_Ocarina_Fairy"))
        c->x[1] = fairy;
}

int hos_oot_event_playing(Ctx *c);

static int loan_equipment_ability(Ctx *c) {
    return hos_trainer_enabled(OOT_TRAINER_EQUIPMENT) && !hos_oot_event_playing(c);
}

/* Bomb Flowers without a recorded bracelet apply an extra approach-angle test.
   This node initializes its answer to false and can only set it true thereafter. */
void hos_oot_loan_bomb_flower_prompt(Ctx *c, A64Fn set) {
    if (loan_equipment_ability(c)) c->x[1] = 1;
    set(c);
}

/* These reads supply the player action and its HUD. The award code writes the
   same fields independently. The lifter still clamps this grade to Link's
   current actor limit (bracelet for a child, golden gauntlets for an adult). */
void hos_oot_loan_strength(Ctx *c, A64Fn get) {
    const uint64_t out = c->x[1];
    get(c);
    if ((c->x[0] & 1) && loan_equipment_ability(c))
        recomp_store32(c, out, 0x165af889u);  /* PlayerStatus.LiftGrade: High */
}

void hos_oot_loan_dive_depth(Ctx *c, A64Fn get) {
    const uint64_t out = c->x[1];
    get(c);
    if (!(c->x[0] & 1) || !loan_equipment_ability(c)) return;
    const uint32_t bits = recomp_load32(c, out);
    float depth;
    memcpy(&depth, &bits, sizeof depth);
    if (depth < 9.0f) recomp_store32(c, out, 0x41100000u);  /* Gold Scale: nine metres */
}

/* Only map presentation reads are redirected here. The original getter must
   resolve a real boolean before we change the result in the caller's scratch
   byte. The saved location, dungeon ownership and chest flags stay authoritative. */
void hos_oot_map_item(Ctx *c, A64Fn get) {
    const uint64_t out = c->x[1];
    get(c);
    if ((c->x[0] & 1) && hos_trainer_enabled(OOT_TRAINER_MAPS))
        recomp_store8(c, out, 1);
}

/* The location getter is also used outside the map. Its caller's return
   address is saved at x29+8 by the supported game's frame prologue. */
void hos_oot_map_visit(Ctx *c, A64Fn get) {
    switch (recomp_load64(c, c->x[29] + 8)) {
        case 0x8022a1a0:  /* location marker */
        case 0x805a413c:  /* local map */
        case 0x80b47ce8:  /* choose field or unavailable map */
        case 0x80b47eb4:  /* world map availability */
        case 0x80b48084:  /* list of maps */
        case 0x80dbb3ac:  /* local map availability */
        case 0x83401b50:  /* map panes and labels */
        case 0x83402144:
        case 0x834024ac:
        case 0x8340475c:
        case 0x83404798:
            hos_oot_map_item(c, get);
            return;
    }
    get(c);
}

/* The lifter enters these scopes only around the supported build's inventory
   widgets and player equipment methods. A grant is an answer to a read, never
   a write to GameData. Threads running an event or autosave have their own scope. */
static _Thread_local unsigned loan_depth;
struct LoanItem { const char *name; uint32_t stock, acquired; };
static const struct LoanItem loans[] = {
#include "oot_loan_items.inc"
};

void hos_oot_loan_enter(void) { ++loan_depth; }
void hos_oot_loan_leave(void) { --loan_depth; }

/* A story event can call a player or inventory helper while awarding an item. */
static int loan_view(Ctx *c) { return loan_depth && !hos_oot_event_playing(c); }

static int tracing_inventory(void) {
    static _Thread_local int mode;
    if (!mode) mode = getenv("HOS_TRACE_INVENTORY") ? 1 : -1;
    return mode > 0;
}
static void trace_read(Ctx *c, uint32_t key, const char *name) {
    static _Thread_local uint64_t seen[256];
    static _Thread_local unsigned count;
    if (!tracing_inventory() || count == 256) return;
    uint64_t signature = c->x[30] ^ ((uint64_t)key << 32) ^ (loan_depth ? 1 : 0);
    for (unsigned i = 0; i < count; i++) if (seen[i] == signature) return;
    seen[count++] = signature;
    hos_log("inventory read: caller 0x%llx scope %u key %08x %s", (unsigned long long)c->x[30], loan_depth, key, name);
}
int hos_oot_loan_count(Ctx *c) {
    if (!loan_depth && !tracing_inventory()) return 0;
    uint64_t string_ref = c->x[1];
    if (!hos_guest_range(string_ref, 8)) return 0;
    uint64_t addr = recomp_load64(c, string_ref);
    const char *name = hos_guest_range(addr, 96);
    if (!name || !memchr(name, 0, 96)) return 0;
    if (tracing_inventory()) {
        uint32_t hash = 5381; for (const char *p = name; *p; ++p) hash = hash * 33 + (unsigned char)*p;
        trace_read(c, hash, name);
    }
    if (!loan_view(c)) return 0;
    if (hos_trainer_enabled(OOT_TRAINER_SKULLTULAS) && !strcmp(name, "Item_Token_Gold")) {
        c->x[0] = 100;
        return 1;
    }
    if (!hos_trainer_enabled(OOT_TRAINER_EQUIPMENT)) return 0;
    for (size_t i = 0; i < sizeof loans / sizeof *loans; ++i) {
        if (!strcmp(name, loans[i].name)) { c->x[0] = 1; return 1; }
    }
    return 0;
}


static int loan_scalar(Ctx *c, uint32_t key, int integer) {
    if (integer && loan_depth) {
        static const struct { uint32_t key; int amount; enum OotTrainerOption option; } values[] = {
            {0x31ab5580u, 80, OOT_TRAINER_HEALTH}, {0xfbe01da1u, 80, OOT_TRAINER_HEALTH},
            {0x76b18200u, 480, OOT_TRAINER_MAGIC}, {0x12d63a97u, 480, OOT_TRAINER_MAGIC},
            {0xe0010a50u, OOT_TRAINER_FULL_WALLET, OOT_TRAINER_MAX_RUPEES},
            {0x457616b0u, 30, OOT_TRAINER_MAX_AMMO}, {0x735b00f7u, 40, OOT_TRAINER_MAX_AMMO},
            {0xe753508bu, 40, OOT_TRAINER_MAX_AMMO}, {0xae8cc742u, 50, OOT_TRAINER_MAX_AMMO},
            {0x418db791u, 50, OOT_TRAINER_MAX_AMMO}, {0x04735978u, 100, OOT_TRAINER_SKULLTULAS},
        };
        for (size_t i = 0; i < sizeof values / sizeof *values; ++i) {
            if (key != values[i].key || !hos_trainer_enabled(values[i].option) || !loan_view(c)) continue;
            recomp_store32(c, c->x[1], values[i].amount);
            c->x[0] = 1;
            return 1;
        }
    }
    if (!hos_trainer_enabled(OOT_TRAINER_EQUIPMENT)) return 0;
    if (!integer && key == 0x1106b082u && loan_view(c)) {  /* IsGet.Item_Bottle */
        recomp_store8(c, c->x[1], 1);
        c->x[0] = 1;
        return 1;
    }
    for (size_t i = 0; i < sizeof loans / sizeof *loans; ++i) {
        if (key != (integer ? loans[i].stock : loans[i].acquired)) continue;
        trace_read(c, key, loans[i].name);
        if (!loan_view(c)) return 0;
        if (integer) recomp_store32(c, c->x[1], 1);
        else recomp_store8(c, c->x[1], 1);
        c->x[0] = 1;
        return 1;
    }
    return 0;
}

int hos_oot_loan_flag(Ctx *c, int integer) {
    if (!loan_depth && !tracing_inventory()) return 0;
    return loan_scalar(c, (uint32_t)c->x[2], integer);
}

/* Struct-member reads resolve the member's hash to its scalar GameData key.
   The supported build uses eight-byte lookup buckets and linear probing. */
int hos_oot_loan_member(Ctx *c, int integer) {
    if (!loan_depth && !tracing_inventory()) return 0;
    const uint32_t member = (uint32_t)c->x[3];
    if (member != (integer ? 0x22344481u : 0xe1754905u)) return 0;  /* StockNum, IsValid */
    const uint64_t handle = c->x[2];
    if (!hos_guest_range(handle,16) || (recomp_load8(c, handle + 12) & 1)) return 0;
    const uint64_t desc = recomp_load64(c, handle);
    if (!hos_guest_range(desc,24)) return 0;
    const uint32_t size = recomp_load32(c,desc + 20);
    const uint64_t table = recomp_load64(c,desc + 8);
    if (!size || size > (1u << 16) || !hos_guest_range(table,(size_t)size * 8)) return 0;
    uint32_t slot = member % size;
    for (uint32_t i = 0; i < size; ++i) {
        const uint64_t at = table + (uint64_t)slot * 8;
        uint32_t field = recomp_load32(c, at);
        if (!field) break;
        if (field == member) return loan_scalar(c, recomp_load32(c, at + 4), integer);
        if (++slot == size) slot = 0;
    }
    return 0;
}
