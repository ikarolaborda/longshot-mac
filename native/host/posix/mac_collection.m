#include "mac_collection.h"
#include "../../gpu/vk/vk_api.h"
#include "../oot_trainer.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdatomic.h>

extern int64_t hos_now_ns(void);
extern int hos_oot_gamedata_bool(uint32_t hash, int64_t *value);
extern int hos_prompts_face(void);

/* The first nine texture indices follow the game's save-preview order. The twelve
   others follow the ocarina songbook. Each key is the saved IsGet flag. */
static const struct QuestItem {
    const char *name;
    uint32_t flag;
} items[] = {
    {"Kokiri's Emerald", 0x110b83ecu},  {"Goron's Ruby", 0x8908d6adu},
    {"Zora's Sapphire", 0xeec383f5u},   {"Light Medallion", 0x9026c187u},
    {"Forest Medallion", 0xfcd8d653u},  {"Fire Medallion", 0x103a0dc7u},
    {"Water Medallion", 0xcf64e780u},   {"Spirit Medallion", 0xe269df38u},
    {"Shadow Medallion", 0x12d63ac6u},  {"Zelda's Lullaby", 0x01c20002u},
    {"Epona's Song", 0xb492ac33u},      {"Saria's Song", 0xd3f8bfccu},
    {"Sun's Song", 0x165dd1adu},        {"Song of Time", 0x03b3450eu},
    {"Song of Storms", 0x2b39dd4fu},    {"Minuet of Forest", 0xdc0a0b54u},
    {"Bolero of Fire", 0x49041ab9u},    {"Serenade of Water", 0x3fa63986u},
    {"Requiem of Spirit", 0x802a36a8u}, {"Nocturne of Shadow", 0xc2fb95f4u},
    {"Prelude of Light", 0xd6320ba4u},
};
enum { STONES = 3, RELICS = 9, COUNT = sizeof items / sizeof *items };
static atomic_ullong page;
static atomic_llong beat;
static atomic_int expanded;

void hos_mac_collection_focus(uint64_t screen) {
    if (atomic_exchange(&page, screen) != screen) {
        atomic_store(&beat, 0);
        atomic_store(&expanded, 0);
    }
}
void hos_mac_collection_tick(uint64_t screen) {
    if (screen && screen == atomic_load(&page))
        atomic_store(&beat, hos_now_ns());
}
static int visible(void) {
    int64_t last = atomic_load(&beat);
    return last && hos_now_ns() - last < 220000000LL;
}
int hos_mac_collection_toggle(void) {
    if (!visible())
        return 0;
    atomic_fetch_xor(&expanded, 1);
    return 1;
}
int hos_mac_collection_stick(int down) {
    static atomic_int held;
    int was = atomic_exchange(&held, down);
    if (!visible())
        return 0;
    if (down && !was)
        hos_mac_collection_toggle();
    return down;
}

static NSColor *gold(void) { return [NSColor colorWithRed:.96 green:.82 blue:.53 alpha:1]; }
static void caption(NSString *text, CGFloat x, CGFloat y, NSFont *font, NSColor *color) {
    [text drawAtPoint:NSMakePoint(x, y)
        withAttributes:@{NSFontAttributeName : font, NSForegroundColorAttributeName : color}];
}
static NSImage *icon(int index) {
    static NSMutableDictionary *cache;
    if (!cache)
        cache = [NSMutableDictionary dictionary];
    NSNumber *key = @(index);
    if (!cache[key]) {
        NSString *name = index < RELICS ? [NSString stringWithFormat:@"DataFileImportantIcon_%02d", index]
                                        : [NSString stringWithFormat:@"OcarinaMelodyIcon_%02d",
                                                                     index == COUNT ? 6 : index - RELICS + (index >= RELICS + 6)];
        NSString *base = [NSFileManager.defaultManager currentDirectoryPath];
        NSString *path = [base
            stringByAppendingPathComponent:[NSString stringWithFormat:@"prompts/collection/%@.png", name]];
        cache[key] = [[NSImage alloc] initWithContentsOfFile:path] ?: NSNull.null;
    }
    return cache[key] == NSNull.null ? nil : cache[key];
}
/* Keep the item model, its description, and the selectable inventory to the
   right visible. The two rows share the lower left of the Collection tab. */
static void inlineIcon(int index, BOOL shown, CGFloat x, CGFloat y) {
    NSRect rect = NSMakeRect(x, y, 23, 23);
    if (shown) {
        [icon(index) drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                      fraction:1 respectFlipped:YES hints:nil];
    } else {
        [[gold() colorWithAlphaComponent:.35] setStroke];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 5, 5)] stroke];
    }
}
static void overview(uint32_t available, BOOL custom, NSString *hint) {
    NSFont *font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    caption(@"Stones", 10, 10, font, gold());
    for (int i = 0; i < STONES; ++i)
        inlineIcon(i, (available >> i) & 1u, 56 + 23 * i, 4);
    caption(@"Medallions", 136, 10, font, gold());
    for (int i = STONES; i < RELICS; ++i)
        inlineIcon(i, (available >> i) & 1u, 207 + 23 * (i - STONES), 4);
    NSString *shortcut = [hint isEqualToString:@"⌘J"] ? hint : @"RS click";
    CGFloat width = [shortcut sizeWithAttributes:@{NSFontAttributeName : font}].width;
    caption(shortcut, 410 - width, 10, font, NSColor.whiteColor);
    caption(@"Songs", 10, 39, font, gold());
    for (int i = RELICS; i < COUNT; ++i)
        inlineIcon(i, (available >> i) & 1u, 56 + 24 * (i - RELICS), 33);
    inlineIcon(COUNT, custom, 357, 33);
}
static void section(NSString *name, int start, int end, uint32_t available, CGFloat x, CGFloat y) {
    int count = 0;
    for (int i = start; i < end; i++)
        count += (available >> i) & 1u;
    caption([NSString stringWithFormat:@"%@   %d/%d", name, count, end - start], x, y,
            [NSFont boldSystemFontOfSize:15], gold());
}
static void paint(CGSize size, BOOL open, NSString *hint, uint32_t earned, uint32_t available,
                  BOOL recorded, BOOL customEarned) {
    [[NSColor colorWithRed:.105 green:.085 blue:.07 alpha:.97] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:(NSRect){NSZeroPoint, size} xRadius:8 yRadius:8] fill];
    NSColor *white = NSColor.whiteColor;
    if (!open) {
        overview(available, recorded || customEarned, hint);
        return;
    }
    caption(@"Quest collection", 22, 13,
            [NSFont fontWithName:@"Georgia-Bold" size:25] ?: [NSFont boldSystemFontOfSize:25], white);
    NSFont *small = [NSFont systemFontOfSize:12];
    NSString *back = [hint stringByAppendingString:@" to return"];
    caption(back, size.width - 22 - [back sizeWithAttributes:@{NSFontAttributeName : small}].width, 22, small,
            gold());
    section(@"Spiritual stones", 0, STONES, available, 22, 56);
    section(@"Medallions", STONES, RELICS, available, 22, 183);
    section(@"Ocarina songs", RELICS, COUNT, available, 332, 56);
    caption(@"Custom song", 22, 373, [NSFont boldSystemFontOfSize:15], gold());
    caption(@"Scarecrow's Song", 53, 405, [NSFont systemFontOfSize:15], white);
    caption(customEarned ? @"Earned" : recorded ? @"Recorded" : @"Unrecorded", 246, 407, small, gold());
    if (recorded || customEarned)
        [icon(COUNT) drawInRect:NSMakeRect(22, 402, 23, 23) fromRect:NSZeroRect
                      operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    for (int i = 0; i < COUNT; i++) {
        CGFloat x = i < RELICS ? 22 : 332;
        CGFloat y = i < STONES ? 85 + i * 25 : i < RELICS ? 212 + (i - STONES) * 25 : 85 + (i - RELICS) * 25;
        BOOL show = (available >> i) & 1u;
        if (show)
            [icon(i) drawInRect:NSMakeRect(x, y, 23, 23)
                       fromRect:NSZeroRect
                      operation:NSCompositingOperationSourceOver
                       fraction:1
                 respectFlipped:YES
                          hints:nil];
        caption(show ? [NSString stringWithUTF8String:items[i].name] : @"Undiscovered", x + 31, y + 2,
                [NSFont systemFontOfSize:15], white);
        NSString *status = (earned >> i) & 1u ? @"Earned" : show ? @"Borrowed" : @"";
        caption(status, x + 224, y + 4, small, gold());
    }
}

void hos_mac_collection_overlay(void *layer) {
    @autoreleasepool {
        static CALayer *panel;
        static double next;
        double now = CACurrentMediaTime();
        if (now < next)
            return;
        next = now + .10;
        if (!visible()) {
            panel.hidden = YES;
            atomic_store(&expanded, 0);
            return;
        }
        CALayer *game = (__bridge CALayer *)layer;
        BOOL open = atomic_load(&expanded);
        uint32_t earned = 0, available = 0;
        int relics = hos_trainer_enabled(OOT_TRAINER_EQUIPMENT),
            songs = hos_trainer_enabled(OOT_TRAINER_SONGS);
        for (int i = 0; i < COUNT; i++) {
            int64_t owned = 0;
            if (hos_oot_gamedata_bool(items[i].flag, &owned) && owned)
                earned |= 1u << i;
            if (i < RELICS ? relics : songs)
                available |= 1u << i;
        }
        available |= earned;
        int64_t recording = 0, award = 0;
        hos_oot_gamedata_bool(0xfdf0f4b8u, &recording); /* Bonooru accepted the player's tune. */
        hos_oot_gamedata_bool(0x5e86fb4du, &award);     /* IsGet.Item_Melody_ScarecrowSong */
        BOOL recorded = !!recording, customEarned = !!award;
        BOOL keyboard = hos_prompts_face() == HOS_PROMPT_KEYBOARD;
        NSString *hint = keyboard ? @"⌘J" : @"Right stick click";
        CGSize art = open ? CGSizeMake(646, 442) : CGSizeMake(420, 60);
        CGSize bounds = game.bounds.size;
        CGFloat safeWidth = MIN(bounds.width, bounds.height * (16.0 / 9.0));
        CGFloat fit = open ? MIN(1.0, MIN((bounds.width - 12) / art.width, (bounds.height - 18) / art.height))
                           : MIN(safeWidth * .405 / art.width, bounds.height * .12 / art.height);
        if (fit <= 0)
            return;
        CGSize display = CGSizeMake(art.width * fit, art.height * fit);
        CGRect frame = open ? CGRectMake((bounds.width - display.width) / 2,
                                         (bounds.height - display.height) / 2, display.width, display.height)
                            : CGRectMake((bounds.width - safeWidth) / 2 + safeWidth * .018,
                                         bounds.height * .012, display.width, display.height);
        CGFloat density = MAX(1, game.contentsScale * fit);
        static uint32_t oldEarned, oldAvailable;
        static BOOL oldOpen, oldKeyboard, oldRecorded, oldCustomEarned;
        static CGFloat oldDensity;
        if (!panel) {
            panel = [CALayer layer];
            panel.actions = @{
                @"bounds" : NSNull.null,
                @"position" : NSNull.null,
                @"contents" : NSNull.null,
                @"hidden" : NSNull.null
            };
        }
        if (panel.superlayer != game)
            [game addSublayer:panel];
        panel.hidden = NO;
        panel.frame = frame;
        if (panel.contents && oldOpen == open && oldKeyboard == keyboard && oldEarned == earned &&
            oldAvailable == available && oldDensity == density && oldRecorded == recorded &&
            oldCustomEarned == customEarned)
            return;
        size_t w = ceil(art.width * density), h = ceil(art.height * density);
        CGColorSpaceRef colors = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, colors, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colors);
        if (!ctx)
            return;
        CGContextTranslateCTM(ctx, 0, h);
        CGContextScaleCTM(ctx, density, -density);
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
        paint(art, open, hint, earned, available, recorded, customEarned);
        [NSGraphicsContext restoreGraphicsState];
        CGImageRef picture = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        if (!picture)
            return;
        panel.contents = (__bridge id)picture;
        CGImageRelease(picture);
        oldOpen = open;
        oldKeyboard = keyboard;
        oldRecorded = recorded;
        oldCustomEarned = customEarned;
        oldEarned = earned;
        oldAvailable = available;
        oldDensity = density;
    }
}
