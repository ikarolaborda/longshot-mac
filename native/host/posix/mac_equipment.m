#include "mac_collection.h"
#import "mac_equipment.h"
#import "../../gpu/vk/oot_cheat_items.h"
#import "../oot_trainer.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdatomic.h>
#include <string.h>

static NSString *path;
static NSMutableDictionary *sets;
static NSObject *guard;
static NSString *feedback;
static NSString *inventorySelection;
static double feedbackUntil;
static atomic_int request;
static atomic_llong requestTime, inventoryScreen, inventoryBeat;
extern int64_t hos_now_ns(void);
extern int hos_oot_gamedata_bool(uint32_t, int64_t *);

void hos_mac_sets_load(const char *dir) {
  @autoreleasepool {
    guard = [NSObject new];
    path = [[[NSString stringWithUTF8String:dir]
        stringByAppendingPathComponent:@"equipment-sets.plist"] copy];
    sets = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!sets)
      sets = [NSMutableDictionary new];
  }
}
static NSString *slotKey(int child, int slot) {
  return [NSString
      stringWithFormat:@"%@-%d", child ? @"child" : @"adult", slot + 1];
}
static NSDictionary *recordForKey(NSString *key) {
  id record = sets[key];
  return [record isKindOfClass:NSDictionary.class] ? record : nil;
}
static NSString *recordName(NSString *key) {
  id name = recordForKey(key)[@"name"];
  return [name isKindOfClass:NSString.class] ? name : @"";
}
static int putRecord(NSString *key, NSDictionary *record) {
  NSMutableDictionary *next = [sets mutableCopy];
  next[key] = record;
  if (![next writeToURL:[NSURL fileURLWithPath:path] error:nil])
    return 0;
  sets = next;
  return 1;
}
int hos_mac_write_set(int child, int slot, const MacEquipmentSet *in) {
  @autoreleasepool {
    @synchronized(guard) {
      NSString *key = slotKey(child, slot);
      NSMutableArray *gear = [NSMutableArray array];
      for (int i = 0; i < MAC_EQUIP_FIELDS; i++)
        [gear addObject:[NSString stringWithUTF8String:in->gear[i]]];
      return putRecord(
          key,
          @{@"name" : recordName(key),
            @"item" : @(in->item),
            @"gear" : gear});
    }
  }
}
int hos_mac_read_set(int child, int slot, MacEquipmentSet *out) {
  @autoreleasepool {
    @synchronized(guard) {
      NSDictionary *d = sets[slotKey(child, slot)];
      if (![d isKindOfClass:NSDictionary.class] ||
          ![d[@"item"] isKindOfClass:NSNumber.class])
        return 0;
      NSArray *gear = d[@"gear"];
      if (![gear isKindOfClass:NSArray.class] || gear.count != MAC_EQUIP_FIELDS)
        return 0;
      *out = (MacEquipmentSet){.item = [d[@"item"] unsignedIntValue]};
      for (int i = 0; i < MAC_EQUIP_FIELDS; i++)
        if (![gear[i] isKindOfClass:NSString.class] ||
            ![gear[i] getCString:out->gear[i]
                       maxLength:64
                        encoding:NSUTF8StringEncoding])
          return 0;
      return 1;
    }
  }
}
void hos_mac_set_feedback(const char *message) {
  @autoreleasepool {
    @synchronized(guard) {
      feedback = [[NSString stringWithUTF8String:message] copy];
      feedbackUntil = CACurrentMediaTime() + 2.5;
    }
  }
}
void hos_mac_set_request(int slot, int capture) {
  if ((unsigned)slot >= MAC_SET_COUNT)
    return;
  atomic_store(&requestTime, hos_now_ns());
  atomic_store(&request, 1 + slot + MAC_SET_COUNT * !!capture);
}
int hos_mac_take_set_request(int *slot, int *capture) {
  int cmd = atomic_exchange(&request, 0);
  if (!cmd || hos_now_ns() - atomic_load(&requestTime) > 750000000LL)
    return 0;
  *slot = (cmd - 1) % MAC_SET_COUNT;
  *capture = (cmd - 1) / MAC_SET_COUNT;
  return 1;
}
static NSString *displayName(const char *actor) {
#define OOT_NAME(label, name, kind) {name, label},
#define OOT_SECTION(name)
  static const struct {
    const char *actor, *label;
  } names[] = {OOT_CHEAT_ITEMS(OOT_SECTION, OOT_NAME)};
#undef OOT_NAME
#undef OOT_SECTION
  for (unsigned i = 0; i < sizeof names / sizeof *names; i++)
    if (!strcmp(actor, names[i].actor))
      return [NSString stringWithUTF8String:names[i].label];
  NSString *name = [NSString stringWithUTF8String:actor];
  NSArray *parts = [name componentsSeparatedByString:@"_"];
  if ([name hasPrefix:@"Bottle"] && name.length == 7)
    return [@"Bottle " stringByAppendingString:[name substringFromIndex:6]];
  NSMutableArray *words = [NSMutableArray array];
  for (NSString *part in parts)
    if (![@[ @"Item", @"Weapon", @"Armor", @"Obj", @"Pouch", @"Range" ]
            containsObject:part])
      [words addObject:part];
  return [words componentsJoinedByString:@" "];
}
@interface LongshotSets : NSObject <NSMenuDelegate>
@end
@implementation LongshotSets
- (void)save:(NSMenuItem *)sender {
  hos_mac_set_request((int)sender.tag, 1);
}
- (void)use:(NSMenuItem *)sender {
  hos_mac_set_request((int)sender.tag, 0);
}
- (void)rename:(NSMenuItem *)sender {
  int64_t child;
  if (!hos_oot_gamedata_bool(0xcea220d3u, &child))
    return;
  NSString *key = slotKey((int)child, (int)sender.tag);
  NSAlert *alert = [NSAlert new];
  alert.messageText = @"Name equipment set";
  NSTextField *field =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 26)];
  @synchronized(guard) {
    field.stringValue = recordName(key);
  }
  alert.accessoryView = field;
  [alert addButtonWithTitle:@"Save"];
  [alert addButtonWithTitle:@"Cancel"];
  [alert.window setInitialFirstResponder:field];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;
  @synchronized(guard) {
    NSMutableDictionary *d =
        [recordForKey(key) mutableCopy] ?: [NSMutableDictionary dictionary];
    d[@"name"] = field.stringValue;
    if (!putRecord(key, d))
      hos_mac_set_feedback("Could not save equipment set name.");
  }
}
- (void)menuNeedsUpdate:(NSMenu *)menu {
  [menu removeAllItems];
  if ([menu.title isEqualToString:@"Inventory status"]) {
    const char *name;
    for (int i = 0;; i++) {
      int status = hos_oot_equipment_status(i, &name);
      if (status < 0)
        break;
      if (!status)
        continue;
      NSString *line =
          [NSString stringWithFormat:@"%@  ·  %@", displayName(name),
                                     status == 2 ? @"Earned" : @"Borrowed"];
      [menu addItemWithTitle:line action:nil keyEquivalent:@""];
    }
    if (!menu.numberOfItems)
      [menu addItemWithTitle:@"Load a save to view equipment"
                      action:nil
               keyEquivalent:@""];
    return;
  }
  int64_t child = 0;
  int ready = hos_oot_gamedata_bool(0xcea220d3u, &child);
  for (int i = 0; i < MAC_SET_COUNT; i++) {
    NSString *label;
    @synchronized(guard) {
      label = recordName(slotKey((int)child, i));
    }
    NSMenuItem *root = [menu
        addItemWithTitle:label.length
                             ? label
                             : [NSString stringWithFormat:@"Set %d", i + 1]
                  action:nil
           keyEquivalent:@""];
    NSMenu *items = [[NSMenu alloc] initWithTitle:root.title];
    root.submenu = items;
    MacEquipmentSet s;
    BOOL saved = ready && hos_mac_read_set((int)child, i, &s);
    char description[96];
    if (saved) {
      hos_mac_set_item_label(s.item, description, sizeof description);
      [items addItemWithTitle:[NSString stringWithUTF8String:description]
                       action:nil
                keyEquivalent:@""];
      [items addItem:NSMenuItem.separatorItem];
    }
    NSArray *actions = @[ @"Equip", @"Save current equipment", @"Rename…" ];
    SEL handlers[] = {@selector(use:), @selector(save:), @selector(rename:)};
    items.autoenablesItems = NO;
    for (int k = 0; k < 3; k++) {
      NSMenuItem *item = [items addItemWithTitle:actions[k]
                                          action:handlers[k]
                                   keyEquivalent:@""];
      item.target = self;
      item.tag = i;
      item.enabled = k == 0 ? saved : ready;
    }
  }
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *inv = [menu addItemWithTitle:@"Inventory status"
                                    action:nil
                             keyEquivalent:@""];
  inv.submenu = [[NSMenu alloc] initWithTitle:inv.title];
  inv.submenu.delegate = self;
}
@end
void hos_mac_sets_install_menu(void) {
  static LongshotSets *target;
  target = [LongshotSets new];
  NSMenuItem *item = [NSApp.mainMenu addItemWithTitle:@"Equipment"
                                               action:nil
                                        keyEquivalent:@""];
  item.submenu = [[NSMenu alloc] initWithTitle:item.title];
  item.submenu.delegate = target;
}

void hos_mac_inventory_focus(const char *page, const char *button,
                             uint64_t screen) {
  BOOL inventory =
      !strcmp(page, "PaEquipmentMenu_00") || !strcmp(page, "PaItemMenu_00");
  hos_mac_collection_focus(!strcmp(page, "PaCollectMenu_00") ? screen : 0);
  atomic_store(&inventoryScreen, inventory ? screen : 0);
  if (getenv("HOS_EQUIPMENT_TRACE"))
    NSLog(@"Inventory focus %s %s", page, button);
}
void hos_mac_inventory_selection(const char *actor) {
  @autoreleasepool {
    @synchronized(guard) {
      static char previous[64];
      static int previousStatus;
      const int status = actor[0] ? hos_oot_equipment_status_named(actor) : 0;
      if (previousStatus == status && !strcmp(previous, actor))
        return;
      strlcpy(previous, actor, sizeof previous);
      previousStatus = status;
      inventorySelection =
          status ? [NSString
                       stringWithFormat:@"%@  ·  %@", displayName(actor),
                                        status == 2 ? @"Earned" : @"Borrowed"]
                 : nil;
      if (getenv("HOS_EQUIPMENT_TRACE"))
        NSLog(@"Equipment selection %s %@", actor, inventorySelection);
    }
  }
}
void hos_mac_inventory_tick(uint64_t screen) {
  hos_mac_collection_tick(screen);
  if (screen && screen == (uint64_t)atomic_load(&inventoryScreen))
    atomic_store(&inventoryBeat, hos_now_ns());
}
void hos_mac_equipment_overlay(void *layer) {
  hos_mac_collection_overlay(layer);
  @autoreleasepool {
    static CATextLayer *label;
    static double next;
    double now = CACurrentMediaTime();
    if (now < next)
      return;
    next = now + .15;
    CALayer *game = (__bridge CALayer *)layer;
    NSString *line = nil;
    @synchronized(guard) {
      if (now < feedbackUntil)
        line = feedback;
    }
    if (!line && hos_now_ns() - atomic_load(&inventoryBeat) < 220000000LL &&
        hos_trainer_enabled(OOT_TRAINER_EQUIPMENT)) {
      @synchronized(guard) {
        line = inventorySelection;
      }
      if (!line) {
        int borrowed = 0, earned = 0;
        for (int i = 0;; i++) {
          const char *name;
          int s = hos_oot_equipment_status(i, &name);
          if (s < 0)
            break;
          if (s == 1)
            borrowed++;
          else if (s == 2)
            earned++;
        }
        line = [NSString stringWithFormat:@"%d borrowed  ·  %d earned    |    "
                                          @"Equipment → Inventory status",
                                          borrowed, earned];
      }
    }
    if (!line) {
      label.hidden = YES;
      return;
    }
    if (!label) {
      label = [CATextLayer layer];
      label.alignmentMode = kCAAlignmentCenter;
      label.backgroundColor = [NSColor colorWithWhite:.06 alpha:.88].CGColor;
      label.foregroundColor = NSColor.whiteColor.CGColor;
      label.cornerRadius = 5;
      label.actions = @{
        @"string" : NSNull.null,
        @"hidden" : NSNull.null,
        @"position" : NSNull.null,
        @"bounds" : NSNull.null
      };
    }
    if (label.superlayer != game)
      [game addSublayer:label];
    label.contentsScale = game.contentsScale;
    label.fontSize = 14;
    label.string = line;
    label.hidden = NO;
    CGFloat w = MIN(game.bounds.size.width - 12,
                    [line sizeWithAttributes:@{
                      NSFontAttributeName : [NSFont systemFontOfSize:14]
                    }]
                            .width +
                        28);
    label.frame = CGRectMake((game.bounds.size.width - w) / 2, 8, w, 23);
  }
}
