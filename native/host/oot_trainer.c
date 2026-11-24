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

enum { OOT_DOUBLE_MAGIC = 480 };  /* 48 units, tracked in tenths */

void hos_oot_trainer_magic(Ctx *c) {
    if (!hos_trainer_enabled(OOT_TRAINER_MAGIC)) return;
    /* f_801839b0 commits both continuous drains and one-shot costs. The same
       balance feeds spell eligibility, the HUD and the GameData MP write.
       The Great Fairy owns MPMax and the blessing flags. */
    if ((uint32_t)c->x[2] != 0x76b18200u) return;  /* PlayerStatus.MP */
    const uint64_t meter = c->x[19];
    const int32_t delta = (int32_t)recomp_load32(c, meter + 0x18);
    if (delta < 0 && getenv("HOS_TRACE_MAGIC"))
        hos_log("trainer magic: meter=%llx delta=%d balance=%u", (unsigned long long)meter,
                delta, (unsigned)c->x[1]);
    c->x[1] = OOT_DOUBLE_MAGIC;
    recomp_store32(c, meter + 0x48, 0);  /* The HUD's pending charge for the equipped item. */
}

void hos_oot_trainer_horse(Ctx *c) {
    if (!hos_trainer_enabled(OOT_TRAINER_CARROTS)) return;
    uint32_t maximum = (uint32_t)c->x[23];
    if (maximum && maximum <= INT16_MAX)
        recomp_store16(c, c->x[21] + 0x27c, (uint16_t)maximum);
}

int hos_oot_target_score_max(uint64_t mgr);

/* Before the game applies this score record, turn a scored hit into an absolute
   maximum. Several horseback hits can arrive in the same batch as additions. */
void hos_oot_trainer_target_score(Ctx *c) {
    if ((uint32_t)c->x[12] != 0x3340e10cu || !hos_trainer_enabled(OOT_TRAINER_TARGET_SCORE))
        return;
    const uint64_t record = c->x[9];
    if ((int32_t)recomp_load32(c, record) <= 0 || recomp_load32(c, record + 8) > 1)
        return;
    const int maximum = hos_oot_target_score_max(c->x[20]);
    if (maximum) {
        recomp_store32(c, record, (uint32_t)maximum);
        recomp_store32(c, record + 8, 0);  /* Set, including when the actor queued Add. */
    }
}

int hos_oot_gamedata_bool(uint32_t hash, int64_t *value);

/* Bonooru accepts the recording in childhood. The melody item itself is a
   later quest reward. Read the eight saved pitches, not the current take,
   which may be incomplete after canceling a replacement recording. */
static int has_recorded_scarecrow_song(Ctx *c) {
    int64_t accepted = 0;
    if (!hos_oot_gamedata_bool(0xfdf0f4b8u, &accepted) || !accepted) return 0;  /* AskBonooru_listentothesong */
    A64Fn read_note = a64_lookup(0x8377b980);  /* GameDataMgr::getUIntArray by hash and index */
    const uint64_t holder = recomp_load64(c, 0x84c9e180);
    const uint64_t manager = holder ? recomp_load64(c, holder) : 0;
    if (!read_note || !manager) return 0;
    Ctx query = *c;
    const uint64_t scratch = (c->x[31] - 0x40) & ~UINT64_C(15);
    for (unsigned i = 0; i < 8; ++i) {
        query.x[31] = scratch;
        query.x[0] = manager;
        query.x[1] = scratch;
        query.x[2] = 0xcc535536u;  /* Bonooru's saved score */
        query.x[3] = i;
        read_note(&query);
        if (!(query.x[0] & 1) || !recomp_load32(c, scratch)) return 0;
    }
    return 1;
}

/* Free play (modes 1 and 3) has just cached the game's own repertoire.
   Only this instrument session borrows songs. Lessons and rewards use the
   original ownership checks. */
void hos_oot_trainer_songs(Ctx *c) {
    if (!hos_trainer_enabled(OOT_TRAINER_SONGS)) return;
    const uint64_t repertoire = c->x[19] + 0x264;
    for (unsigned song = 0; song < 12; ++song)
        recomp_store8(c, repertoire + song, 1);
    if (!recomp_load8(c, repertoire + 12) && has_recorded_scarecrow_song(c))
        recomp_store8(c, repertoire + 12, 1);
}

int hos_oot_is_player(Ctx *c, uint64_t life);

/* The contact record still belongs to one hit here. A thrown or reflected
   weapon can have a last user of its own. Enemy hits and self-damage use the
   game's original amount, including when Link is caught in his own blast. */
void hos_oot_trainer_attack(Ctx *c) {
    const int32_t damage = (int32_t)c->x[8];
    if (damage <= 0 || !hos_trainer_enabled(OOT_TRAINER_ATTACK_DAMAGE)) return;
    const uint64_t hit = c->x[19];
    enum { none = 0, player = 3, unknown = 6 };
    uint32_t source = recomp_load32(c, hit + 0xd0);  /* last user's affiliation */
    if (source == none || source == unknown)
        source = recomp_load32(c, hit + 0xc8);       /* attacker's affiliation */
    if (source != player) return;

    const uint64_t victim = recomp_load64(c, c->x[20] + 8);
    const uint64_t parts = victim ? recomp_load64(c, victim + 0x270) : 0;
    const uint64_t life = parts ? recomp_load64(c, parts + 0x2b8) : 0;
    if (!life || hos_oot_is_player(c, life)) return;

    const int64_t scaled = (int64_t)damage * 100;
    c->x[8] = scaled > INT32_MAX ? INT32_MAX : (uint32_t)scaled;
    if (getenv("HOS_TRACE_ATTACK"))
        hos_log("trainer attack: life=%llx damage=%d scaled=%u",
                (unsigned long long)life, damage, (unsigned)c->x[8]);
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

#ifdef __APPLE__
/* A direct read outside the inventory hooks. A quest award thus changes the badge even with the loan active. */
int hos_oot_equipment_status(int index, const char **name) {
    if ((unsigned)index >= sizeof loans / sizeof *loans) return -1;
    const struct LoanItem *item = &loans[index];
    *name = item->name;
    int64_t acquired;
    extern int hos_oot_gamedata_bool(uint32_t, int64_t *);
    if (!hos_oot_gamedata_bool(item->acquired, &acquired)) return 0;
    return acquired ? 2 : hos_trainer_enabled(OOT_TRAINER_EQUIPMENT);
}
int hos_oot_equipment_status_named(const char *name) {
    for (unsigned i = 0; i < sizeof loans / sizeof *loans; ++i) {
        if (!strcmp(name, loans[i].name)) {
            const char *ignored;
            return hos_oot_equipment_status(i, &ignored);
        }
    }
    return 0;
}
int hos_oot_equipment_available(const char *name) {
    for (unsigned i = 0; i < sizeof loans / sizeof *loans; ++i) {
        if (strcmp(name, loans[i].name)) continue;
        const char *ignored;
        /* Acquisition can stay set after a shield breaks. With loans disabled the
           pouch decides whether equipment is still available. Bottles have a slot-valid bit. */
        if (hos_trainer_enabled(OOT_TRAINER_EQUIPMENT)) return 1;
        return !strncmp(name, "Bottle", 6) && hos_oot_equipment_status(i, &ignored) == 2;
    }
    return 0;
}
#endif
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
            {0x76b18200u, OOT_DOUBLE_MAGIC, OOT_TRAINER_MAGIC}, {0x12d63a97u, OOT_DOUBLE_MAGIC, OOT_TRAINER_MAGIC},
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
    /* The magic gauge reads PlayerStatus.MPMax at creation and in the HUD's
       change detector. A loan here also refreshes the gauge when toggled
       during play, without granting either saved Great Fairy upgrade. */
    if (integer && (uint32_t)c->x[3] == 0x39e8a20du &&
        (c->x[30] == 0x833ddfb0 || c->x[30] == 0x8019a674) &&
        hos_trainer_enabled(OOT_TRAINER_MAGIC)) {
        recomp_store32(c, c->x[1], OOT_DOUBLE_MAGIC);
        c->x[0] = 1;
        return 1;
    }
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
