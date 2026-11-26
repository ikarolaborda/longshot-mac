#pragma once
/* Shared with the settings renderer in longshot_mtl.dylib. The host keeps ownership
   of the window, the game display, and the persistent Metal settings. */
typedef struct {
    void (*tick)(void *layer, int toggle);
    int (*option)(int);
    void (*option_set)(int, int);
    int (*setting)(int, MkwVkSetting *);
    int (*setting_set)(const char *, int, MkwVkSetting *);
} LongshotMetalMenu;
