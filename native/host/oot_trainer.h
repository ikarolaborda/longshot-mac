#ifndef HOS_OOT_TRAINER_H
#define HOS_OOT_TRAINER_H

enum { OOT_TRAINER_FULL_WALLET = 1000 };

enum OotTrainerOption {
    OOT_TRAINER_HEALTH, OOT_TRAINER_MAGIC, OOT_TRAINER_CARROTS, OOT_TRAINER_CLOCK,
    OOT_TRAINER_MAX_RUPEES, OOT_TRAINER_MAX_AMMO, OOT_TRAINER_EQUIPMENT, OOT_TRAINER_SKULLTULAS,
    OOT_TRAINER_MAPS, OOT_TRAINER_OPTION_COUNT
};
int hos_trainer_enabled(enum OotTrainerOption option);
void hos_trainer_set(enum OotTrainerOption option, int enabled);
void hos_mac_trainer_load(const char *directory);
int hos_oot_player_seen(void);
void hos_mac_cheat_menu(void);
#endif
