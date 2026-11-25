#import <AppKit/AppKit.h>
#include "../oot_trainer.h"
#import "mac_equipment.h"

static NSString *trainerPath;
static NSArray<NSString *> *settingKeys(void) {
    return @[@"health", @"magic", @"carrots", @"timers", @"rupees", @"ammunition", @"equipment", @"skulltulas", @"maps", @"targetScore", @"songs", @"attackDamage", @"dungeonKeys"];
}

void hos_mac_trainer_load(const char *directory) {
    @autoreleasepool {
        hos_mac_sets_load(directory);
        trainerPath = [[[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:@"trainer.json"] copy];
        NSData *data = [NSData dataWithContentsOfFile:trainerPath];
        if (!data) return;
        NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![settings isKindOfClass:NSDictionary.class]) return;
        NSArray *keys = settingKeys();
        for (NSUInteger i = 0; i < keys.count; ++i)
            if ([settings[keys[i]] isKindOfClass:NSNumber.class])
                hos_trainer_set((enum OotTrainerOption)i, [settings[keys[i]] boolValue]);
    }
}

static BOOL saveSettings(void) {
    NSArray *keys = settingKeys();
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < keys.count; ++i)
        settings[keys[i]] = @(hos_trainer_enabled((enum OotTrainerOption)i) != 0);
    NSData *data = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted error:nil];
    return trainerPath && [data writeToFile:trainerPath options:NSDataWritingAtomic error:nil];
}

@interface LongshotCheats : NSPanel <NSWindowDelegate>
@property(nonatomic, assign) NSWindow *game;
@property(nonatomic, retain) NSResponder *gameResponder;
@end

@implementation LongshotCheats {
    NSButton *_switches[OOT_TRAINER_OPTION_COUNT];
    BOOL _saveFailed;
    NSTextField *_status;
    NSTimer *_refresh;
}

- (instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0, 0, 338, 116 + 30 * OOT_TRAINER_OPTION_COUNT)
                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                              backing:NSBackingStoreBuffered defer:NO];
    if (!self) return nil;
    self.title = @"Longshot Cheats";
    self.releasedWhenClosed = NO;
    self.delegate = self;
    self.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorMoveToActiveSpace;
    NSArray *names = @[@"20 hearts and infinite health", @"Infinite magic (double meter)", @"Infinite Epona carrots",
                       @"Freeze challenge timers", @"Infinite rupees (1,000)", @"Full ammunition and bags",
                       @"All equipment", @"All 100 Gold Skulltulas", @"Hyrule map, dungeon maps and compasses",
                       @"Perfect score after one target hit", @"All ocarina songs", @"100× attack damage",
                       @"Collect dungeon keys and open their chests"];
    for (int i = 0; i < OOT_TRAINER_OPTION_COUNT; ++i) {
        NSButton *button = [NSButton checkboxWithTitle:names[i] target:self action:@selector(changeOption:)];
        if (i == OOT_TRAINER_DUNGEON_KEYS)
            button.toolTip = @"Claims the current dungeon’s remaining keys. Opened key chests and spent keys persist when you save.";
        button.tag = i;
        button.frame = NSMakeRect(20, 104 + (OOT_TRAINER_OPTION_COUNT - 1 - i) * 30, 306, 24);
        [self.contentView addSubview:button];
        _switches[i] = button;
    }
    _status = [NSTextField wrappingLabelWithString:@""];
    _status.frame = NSMakeRect(22, 14, 294, 64);
    _status.textColor = NSColor.secondaryLabelColor;
    [self.contentView addSubview:_status];
    [self center];
    return self;
}

- (void)changeOption:(NSButton *)sender {
    hos_trainer_set((enum OotTrainerOption)sender.tag, sender.state == NSControlStateValueOn);
    _saveFailed = !saveSettings();
    [self refresh:nil];
}

- (void)refresh:(NSTimer *)timer {
    if (_saveFailed) {
        _status.stringValue = @"Active for this session. Could not save cheat preferences.";
        return;
    }
    if (!hos_oot_player_seen()) {
        _status.stringValue = @"Checked cheats apply when gameplay starts or resumes. Selections carry across loads.";
        return;
    }
    _status.stringValue = @"Your cheat selections carry across loads. You can still collect borrowed equipment in the story.";
}

- (void)openForGame:(NSWindow *)game {
    self.game = game;
    self.gameResponder = game.firstResponder;
    for (int i = 0; i < OOT_TRAINER_OPTION_COUNT; ++i)
        _switches[i].state = hos_trainer_enabled((enum OotTrainerOption)i) ? NSControlStateValueOn : NSControlStateValueOff;
    [self refresh:nil];
    [game addChildWindow:self ordered:NSWindowAbove];
    [self makeKeyAndOrderFront:nil];
    _refresh = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (BOOL)canBecomeKeyWindow { return YES; }

- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown && (event.keyCode == 87 || event.keyCode == 53)) {
        if (!event.isARepeat) [self close];
        return;
    }
    [super sendEvent:event];
}

- (void)close {
    NSWindow *game = self.game;
    NSResponder *responder = self.gameResponder;
    [_refresh invalidate];
    _refresh = nil;
    [game removeChildWindow:self];
    [super close];
    if (NSApp.isActive && game.isVisible) {
        [game makeKeyAndOrderFront:nil];
        if (responder) [game makeFirstResponder:responder];
    }
    self.game = nil;
    self.gameResponder = nil;
}
@end

void hos_mac_cheat_menu(void) {
    static LongshotCheats *panel;
    if (!panel) panel = [[LongshotCheats alloc] init];
    if (!panel.isVisible) [panel openForGame:NSApp.keyWindow];
}
