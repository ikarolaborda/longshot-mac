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

int hos_oot_event_playing(Ctx *c);

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
    if (integer && key == 0x04735978u && hos_trainer_enabled(OOT_TRAINER_SKULLTULAS) && loan_view(c)) {
        recomp_store32(c, c->x[1], 100); c->x[0] = 1; return 1;
    }
    if (!hos_trainer_enabled(OOT_TRAINER_EQUIPMENT)) return 0;
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
