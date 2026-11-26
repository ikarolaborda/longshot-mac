#import <AppKit/AppKit.h>
#import "mac_equipment.h"
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#include "mac_response.h"
#include "../../gpu/vk/compat/longshot_env.h"
#import <QuartzCore/CAMetalLayer.h>
#import <MetalFX/MetalFX.h>
#import "../../third_party/d2r_gfx/gfx/nvn/totk_mfx.h"

/* The installed app owns immutable resources. The renderer writes logs, options
   and caches into the per-user runtime. Loose developer builds keep their layout. */
static BOOL linkResource(NSString *source, NSString *target) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *old = [fm destinationOfSymbolicLinkAtPath:target error:nil];
    if ([old isEqual:source]) return YES;
    if (!old && [fm fileExistsAtPath:target]) return NO;
    NSString *tmp = [target stringByAppendingFormat:@".%@", NSUUID.UUID.UUIDString];
    if (![fm createSymbolicLinkAtPath:tmp withDestinationPath:source error:nil]) return NO;
    if (!rename(tmp.fileSystemRepresentation, target.fileSystemRepresentation)) return YES;
    unlink(tmp.fileSystemRepresentation);
    return NO;
}

int hos_mac_bundle_setup(void) {
    @autoreleasepool {
        NSBundle *app = NSBundle.mainBundle;
        BOOL preview = [app.bundleIdentifier isEqual:@"dev.longshot.game.preview"];
        BOOL experimental = [app.bundleIdentifier isEqual:@"dev.longshot.game.experimental"];
        if (!preview && !experimental && ![app.bundleIdentifier isEqual:@"dev.longshot.game"]) return 1;
        NSString *channel = experimental ? @"Longshot Experimental" : preview ? @"Longshot Metal Preview" : @"Longshot";
        if (experimental) setenv("HOS_WINDOW_TITLE", channel.UTF8String, 0);
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *support = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:channel];
        NSString *runtime = [support stringByAppendingPathComponent:@"Runtime"];
        NSString *dataName = [app objectForInfoDictionaryKey:@"LongshotDataDirectory"];
        NSString *assets = dataName ? [[support stringByAppendingPathComponent:@"GameData"] stringByAppendingPathComponent:dataName]
                                    : [app.resourcePath stringByAppendingPathComponent:@"Game"];
        NSString *metal = @"metal/build";
        NSString *metalDir = [runtime stringByAppendingPathComponent:metal];
        if (![fm createDirectoryAtPath:metalDir withIntermediateDirectories:YES attributes:nil error:nil]) return 0;
        for (NSString *dir in @[@"", metal]) {
            NSString *from = [assets stringByAppendingPathComponent:dir];
            NSArray *names = [fm contentsOfDirectoryAtPath:from error:nil];
            if (!names && !dir.length) return 0;
            for (NSString *name in names) {
                if ([name isEqual:@"metal"] || [name isEqual:@"longshot_options.ini"]) continue;
                NSString *rel = [dir stringByAppendingPathComponent:name];
                if (!linkResource([assets stringByAppendingPathComponent:rel], [runtime stringByAppendingPathComponent:rel])) return 0;
            }
        }
        NSString *sealedMetal = [app.resourcePath stringByAppendingPathComponent:@"Metal"];
        for (NSString *name in [fm contentsOfDirectoryAtPath:sealedMetal error:nil]) {
            if (!linkResource([sealedMetal stringByAppendingPathComponent:name], [metalDir stringByAppendingPathComponent:name])) return 0;
        }
        NSString *options = [runtime stringByAppendingPathComponent:@"longshot_options.ini"];
        if (![fm fileExistsAtPath:options]) {
            NSData *data = [NSData dataWithContentsOfFile:[assets stringByAppendingPathComponent:@"longshot_options.ini"]];
            if (data && ![data writeToFile:options options:NSDataWritingWithoutOverwriting error:nil] && ![fm fileExistsAtPath:options]) return 0;
        }
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[support stringByAppendingPathComponent:@"installation.plist"]];
        NSString *profile = prefs[@"DataHome"] ?: [support stringByAppendingPathComponent:@"UserData"];
        if (![profile isKindOfClass:NSString.class] || !profile.isAbsolutePath) return 0;
        setenv("XDG_DATA_HOME", profile.fileSystemRepresentation, 0);
        setenv("LONGSHOT_BUNDLE_RUNTIME", runtime.fileSystemRepresentation, 1);
        setenv("TOTK_NATIVE_DIR", metalDir.fileSystemRepresentation, 0);
        setenv("TOTK_UNCAPPED_HZ", "display", 0);
        setenv("RX_RENDERER", "metal", 1);
        return chdir(runtime.fileSystemRepresentation) == 0;
    }
}

extern void mtl_grab_next_present(void (^capture)(CGImageRef));
extern void *display_metal_layer(void);
extern void mtl_stats(uint64_t *passes, uint64_t *draws);
extern volatile int64_t hos_present_count;

typedef void (*ShotDone)(void *, int64_t, int);
static pthread_mutex_t shotLock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic bool pending;
static NSString *shotPath;
static int64_t shotAfter;
static ShotDone shotDone;
static void *shotContext;
static _Atomic int64_t presentedDraws;
static _Atomic int drawableWidth, drawableHeight;

int hos_metal_request_shot(const char *path, int64_t after, ShotDone done, void *context) {
    if (!path || !done) return 0;
    pthread_mutex_lock(&shotLock);
    int accepted = shotPath == nil;
    if (accepted) {
        shotPath = [[NSString alloc] initWithUTF8String:path];
        accepted = shotPath != nil;
        shotAfter = after;
        shotDone = done;
        shotContext = context;
        atomic_store(&pending, accepted);
    }
    pthread_mutex_unlock(&shotLock);
    return accepted;
}

void hos_metal_before_present(int64_t frame) {
    uint64_t passes, draws;
    mtl_stats(&passes, &draws);
    atomic_store(&presentedDraws, draws);
    CAMetalLayer *layer = (__bridge CAMetalLayer *)display_metal_layer();
    CGSize size = layer.drawableSize;
    atomic_store(&drawableWidth, (int)size.width);
    atomic_store(&drawableHeight, (int)size.height);
    if (!atomic_load(&pending)) return;
    pthread_mutex_lock(&shotLock);
    if (atomic_load(&pending) && frame >= shotAfter) {
        atomic_store(&pending, false);
        NSString *destination = shotPath;
        ShotDone done = shotDone;
        void *context = shotContext;
        mtl_grab_next_present(^(CGImageRef image) {
            @autoreleasepool {
                BOOL ok = NO;
                if (image) {
                    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
                    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                    ok = [png writeToFile:destination options:NSDataWritingAtomic error:nil];
#if !__has_feature(objc_arc)
                    [rep release];
#endif
                }
                pthread_mutex_lock(&shotLock);
#if !__has_feature(objc_arc)
                [shotPath release];
#endif
                shotPath = nil;
                pthread_mutex_unlock(&shotLock);
                done(context, frame, ok);
            }
        });
    }
    pthread_mutex_unlock(&shotLock);
}

int hos_metal_frame_info(int64_t *p, int64_t *d, int *w, int *h) {
    *p = __atomic_load_n(&hos_present_count, __ATOMIC_RELAXED);
    *d = atomic_load(&presentedDraws);
    *w = atomic_load(&drawableWidth);
    *h = atomic_load(&drawableHeight);
    return *w > 0 && *h > 0;
}

/* The SDL event thread owns the game window. The render and pacing threads
   only read the last published rate, including when the window changes screens. */
static _Atomic int displayHz;
static _Atomic int selectedHz = -1, adaptive, supported, manualInterpolation, adaptiveInterpolation;
static _Atomic int scalePercent, gameActive;
int hos_mac_stream_policy(void) {
    static dispatch_once_t once;
    static int enabled;
    dispatch_once(&once, ^{ enabled = env_on_or("LONGSHOT_STREAM_REUSE", 1); });
    return enabled;
}
static int adaptiveTarget(int display) {
    if (hos_mac_response_active()) return hos_mac_response_target(display);
    return MIN(144, display);
}
static pthread_mutex_t graphicsLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned graphicsRevision;
static const int rates[] = {0,30,60,90,120,144,165,240};
extern void hos_log(const char *, ...);
int hos_mac_graphics_get(int setting) {
    if (setting == MAC_INTERPOLATION) return atomic_load(&adaptive) ? atomic_load(&adaptiveInterpolation) : atomic_load(&manualInterpolation);
    if (setting == MAC_ADAPTIVE) return atomic_load(&adaptive) == 1;
    if (setting == MAC_RESPONSIVE) return hos_mac_response_active();
    if (setting == MAC_CAN_INTERPOLATE) return atomic_load(&supported);
    for (int i=1; i<8; ++i) if (rates[i] == atomic_load(&selectedHz)) return i;
    return 0;
}
void hos_mac_graphics_set(int setting, int value) {
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    if (setting < 0 || (setting > MAC_ADAPTIVE && setting != MAC_RESPONSIVE) || (setting == MAC_RATE && (unsigned)value >= 8)) return;
    if (setting == MAC_INTERPOLATION && !atomic_load(&supported)) return;
    pthread_mutex_lock(&graphicsLock);
    ++graphicsRevision;
    if (setting == MAC_RATE) { atomic_store(&selectedHz,rates[value]); [prefs setInteger:rates[value] forKey:@"MetalFrameRate"]; }
    if (setting == MAC_INTERPOLATION) { atomic_store(&manualInterpolation,!!value); [prefs setBool:value forKey:@"MetalFrameInterpolation"]; }
    int automatic = 0;
    if (value && setting == MAC_ADAPTIVE) automatic = 1;
    if (value && setting == MAC_RESPONSIVE) automatic = 2;
    hos_mac_response_reset(automatic == 2);
    atomic_store(&adaptive, automatic);
    [prefs setBool:automatic == 1 forKey:@"MetalAdaptive144"];
    [prefs setBool:automatic == 2 forKey:@"MetalPreferResponsiveness"];
    atomic_store(&scalePercent,0);
    atomic_store(&adaptiveInterpolation,0);
    if (atomic_load(&supported)) mfx_set(!automatic && atomic_load(&manualInterpolation) ? MFX_MAX : MFX_OFF);
    pthread_mutex_unlock(&graphicsLock);
}
int hos_mac_resolution_option(int id) {
    int scale = atomic_load(&adaptive) ? atomic_load(&scalePercent) : 0;
    return id == 2 ? scale == 0 : scale * 100;
}
// Only the renderer samples frames and owns these consecutive-window counts.
static int slow, heavy, spare;
static void updateAdaptiveMode(double fps, double gpu, int hz) {
    const int interp = atomic_load(&adaptiveInterpolation);
    slow = fps < hz*.90 ? slow+1 : 0;
    const int responsive = hos_mac_response_active();
    const int wantFill = responsive ? hos_mac_response_wants_fill() : slow >= 2;
    if (!interp && hz >= 100 && wantFill && atomic_load(&supported)) {
        mfx_set(MFX_MAX); atomic_store(&adaptiveInterpolation,1);
        hos_log("Metal adaptive: %.1f base FPS, enabling interpolation for %d Hz",fps,hz);
        slow=heavy=spare=0;
        return;
    } else if (interp && (hz < 100 || (responsive && !wantFill))) {
        mfx_set(MFX_OFF); atomic_store(&adaptiveInterpolation,0);
        slow=heavy=spare=0;
        return;
    }
    double target = interp ? hz/2.0 : hz, budget = 1000/target;
    heavy = fps < target*.96 && gpu > budget*.85 ? heavy+1 : 0;
    spare = fps >= target*.96 && gpu > 0 && gpu < budget*.64 ? spare+1 : 0;
    int scale = atomic_load(&scalePercent);
    // The first override starts below the game's current scale.
    extern float hos_mac_live_scale(void);
    int next = scale;
    if (heavy >= 2) {
        int current = scale ? scale : (int)lround(hos_mac_live_scale()*100);
        next = current > 83 ? 83 : current > 67 ? 67 : current > 50 ? 50 : scale;
        heavy=spare=0;
    } else if (scale && spare >= 4) {
        next = scale == 50 ? 67 : scale == 67 ? 83 : 0;
        heavy=spare=0;
    }
    if (next != scale) {
        atomic_store(&scalePercent,next);
        hos_log("Metal adaptive: %.1f base FPS, %.2f ms GPU, 3D scale %d%% (0 = game controlled)",fps,gpu,next);
    }
}

/* Sample steady gameplay only. A scene load or background stall starts a new
   window. A CPU-limited scene keeps its image quality. */
void hos_mac_adapt_frame(double now, double gpuMS) {
    static double last, elapsed, gpuSum;
    static int frames, gpuSamples, lastHz;
    const int display = atomic_load(&displayHz);
    const int hz = adaptiveTarget(display);
    const double delta = now-last;
    last = now;
    if (!atomic_load(&adaptive) || hz < 30 || delta <= 0 || delta > .10 || hz != lastHz) {
        if (delta > .10 && hos_mac_response_active()) hos_mac_response_discard_window();
        frames = gpuSamples = 0;
        slow = heavy = spare = 0;
        elapsed = gpuSum = 0;
        lastHz = hz;
        return;
    }
    if (gpuMS > 0 && gpuMS < 100) { gpuSum += gpuMS; gpuSamples++; }
    elapsed += delta;
    if (++frames < 32 || elapsed < 1.0) return;
    int event, loading, child;
    extern int hos_oot_state(int *,int *,int *);
    const double fps = frames/elapsed, gpu = gpuSamples ? gpuSum/gpuSamples : 0;
    frames=gpuSamples=0; elapsed=gpuSum=0;
    int gameplay = hos_oot_state(&event,&loading,&child) && !event && !loading && atomic_load(&gameActive);
    hos_mac_response_evaluate(now, display, gameplay, atomic_load(&supported));
    if (!gameplay) {
        slow=heavy=spare=0;
        return;
    }
    static unsigned sampledRevision;
    pthread_mutex_lock(&graphicsLock);
    if (!atomic_load(&adaptive) || sampledRevision != graphicsRevision) {
        sampledRevision = graphicsRevision;
        slow = heavy = spare = 0;
    } else {
        updateAdaptiveMode(fps, gpu, hz);
    }
    pthread_mutex_unlock(&graphicsLock);
}
int front_display_hz(void) { return atomic_load(&displayHz); }

double hos_mac_pair_period(double gamePeriod) {
    int display = front_display_hz();
    int hz = adaptiveTarget(display);
    if (hz >= 100 && atomic_load(&adaptive) && atomic_load(&adaptiveInterpolation))
        return 2.0 / hz;
    return gamePeriod;
}

int hos_mac_frame_cap(int configured) {
    int display = front_display_hz();
    if (display < 30) display = 60;
    if (atomic_load(&adaptive)) {
        int target = adaptiveTarget(display);
        if (!hos_mac_response_active() && atomic_load(&adaptiveInterpolation) && target >= 100)
            return (target+1)/2;
        return target;
    }
    int choice = atomic_load(&selectedHz);
    if (choice < 0) choice = configured == 60 ? 0 : configured;
    return choice > 0 && choice < display ? choice : display;
}

@interface LongshotFrameRate : NSObject
- (void)choose:(NSMenuItem *)sender;
@end
@implementation LongshotFrameRate
- (void)choose:(NSMenuItem *)sender {
    hos_mac_graphics_set(MAC_RATE,(int)sender.tag);
}
- (void)toggleInterpolation:(NSMenuItem *)sender { hos_mac_graphics_set(MAC_INTERPOLATION,!hos_mac_graphics_get(MAC_INTERPOLATION)); }
- (void)toggleAdaptive:(NSMenuItem *)sender { hos_mac_graphics_set(MAC_ADAPTIVE,!hos_mac_graphics_get(MAC_ADAPTIVE)); }
- (void)toggleResponsive:(NSMenuItem *)sender { hos_mac_graphics_set(MAC_RESPONSIVE,!hos_mac_response_active()); }
- (void)openSettings:(NSMenuItem *)sender { extern void hos_mac_request_settings(void); hos_mac_request_settings(); }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(choose:)) item.state = !atomic_load(&adaptive) && item.tag == hos_mac_graphics_get(MAC_RATE);
    if (item.action == @selector(toggleInterpolation:)) item.state = hos_mac_graphics_get(MAC_INTERPOLATION);
    if (item.action == @selector(toggleAdaptive:)) item.state = hos_mac_graphics_get(MAC_ADAPTIVE);
    if (item.action == @selector(toggleResponsive:)) item.state = hos_mac_response_active();
    return YES;
}
@end

void hos_mac_refresh_screen(void *metalLayer, int sdlMillihertz) {
    if (!metalLayer) return;
    @autoreleasepool {
        CAMetalLayer *layer = (__bridge CAMetalLayer *)metalLayer;
        NSWindow *window = nil;
        for (CALayer *l = layer; l && !window; l = l.superlayer) {
            if ([l.delegate isKindOfClass:NSView.class]) window = [(NSView *)l.delegate window];
        }
        // An opt-in, scripted timing run may keep its visible window on a second
        // screen while the player uses another app. Hidden windows never qualify.
        static int visibleTest = -1;
        if (visibleTest < 0) {
            const char *test = getenv("HOS_METAL_BENCH_VISIBLE");
            visibleTest = test && !strcmp(test, "1") && getenv("HOS_CONTROL") && getenv("HOS_METAL_TIMING");
        }
        if (!window && visibleTest) {
            for (NSWindow *candidate in NSApp.windows)
                if (candidate.contentView && candidate.visible && candidate.canBecomeKeyWindow) { window = candidate; break; }
        }
        atomic_store(&gameActive, NSApp.active || (visibleTest && (window.occlusionState & NSWindowOcclusionStateVisible)));
        NSScreen *screen = window.screen;
        if (!screen) screen = NSApp.mainWindow.screen ?: NSScreen.mainScreen;
        int hz = (sdlMillihertz + 500) / 1000;
        if (screen) {
            CGDirectDisplayID display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
            double fixed = mode ? CGDisplayModeGetRefreshRate(mode) : 0;
            if (mode) CGDisplayModeRelease(mode);
            hz = fixed > 1 ? (int)lround(fixed) : (int)screen.maximumFramesPerSecond;
        }
        atomic_store(&displayHz, hz > 240 ? 240 : hz >= 30 ? hz : 60);
        static NSMenuItem *root;
        static LongshotFrameRate *target;
        if (!root && NSApp.mainMenu) {
            target = [LongshotFrameRate new];
            hos_mac_sets_install_menu();
            NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Frame Rate"];
            root = [[NSMenuItem alloc] initWithTitle:menu.title action:nil keyEquivalent:@""];
            root.submenu = menu;
            [NSApp.mainMenu addItem:root];
            NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:@"MetalFrameRate"];
            extern int hos_ini_option(const char *, int);
            static const int legacy[] = {0,90,120,144,165,240,0};
            int row = hos_ini_option("frame_rate_cap",0);
            int choice = saved ? saved.intValue : row == -1 ? 30 : row >= 0 && row < 7 ? legacy[row] : 0;
            NSArray<NSNumber *> *choices = @[@0,@30,@60,@90,@120,@144,@165,@240];
            if (![choices containsObject:@(choice)]) choice = 0;
            atomic_store(&selectedHz, choice);
            NSMenu *appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;
            // SDL can install a placeholder Settings item which already owns Command-comma.
            NSMenuItem *settings = nil;
            for (NSMenuItem *item in appMenu.itemArray) {
                if ([item.keyEquivalent isEqualToString:@","] && item.keyEquivalentModifierMask == NSEventModifierFlagCommand) {
                    settings = item;
                    break;
                }
            }
            if (!settings)
                settings = [appMenu insertItemWithTitle:@"Longshot Settings…" action:nil keyEquivalent:@"," atIndex:MIN((NSInteger)2,appMenu.numberOfItems)];
            settings.action = @selector(openSettings:);
            settings.target = target;
            NSMenuItem *autoItem = [menu addItemWithTitle:@"Adaptive 144 FPS" action:@selector(toggleAdaptive:) keyEquivalent:@""];
            autoItem.target = target;
            NSMenuItem *responseItem = [menu addItemWithTitle:@"Prefer responsiveness" action:@selector(toggleResponsive:) keyEquivalent:@""];
            responseItem.target = target;
            [menu addItem:NSMenuItem.separatorItem];
            NSNumber *priorAuto = [NSUserDefaults.standardUserDefaults objectForKey:@"MetalAdaptive144"];
            atomic_store(&adaptive,priorAuto ? priorAuto.boolValue : !saved && !row && ![NSUserDefaults.standardUserDefaults objectForKey:@"MetalFrameInterpolation"] && !getenv("TOTK_MFX") && !getenv("HOS_FPS_MAX"));
            BOOL responsive = [NSUserDefaults.standardUserDefaults boolForKey:@"MetalPreferResponsiveness"];
            if (responsive) atomic_store(&adaptive,2);
            hos_mac_response_reset(responsive);
            for (NSNumber *rate in choices) {
                NSString *title = rate.intValue ? [NSString stringWithFormat:@"%@ FPS",rate] : @"Match Display";
                NSMenuItem *item = [menu addItemWithTitle:title action:@selector(choose:) keyEquivalent:@""];
                item.target = target;
                item.tag = [choices indexOfObject:rate];
                item.state = rate.intValue == choice ? NSControlStateValueOn : NSControlStateValueOff;
            }
            if (@available(macOS 26.0, *)) {
                if ([MTLFXFrameInterpolatorDescriptor supportsMetal4FX:MTLCreateSystemDefaultDevice()]) {
                    atomic_store(&supported,1);
                    [menu addItem:NSMenuItem.separatorItem];
                    NSMenuItem *item = [menu addItemWithTitle:@"MetalFX Frame Interpolation" action:@selector(toggleInterpolation:) keyEquivalent:@""];
                    item.target = target;
                    atomic_store(&manualInterpolation, getenv("TOTK_MFX") ? mfx_requested() != MFX_OFF : [NSUserDefaults.standardUserDefaults boolForKey:@"MetalFrameInterpolation"]);
                    if (responsive) mfx_set(MFX_OFF);
                    else if (!atomic_load(&adaptive) && atomic_load(&manualInterpolation) && !getenv("TOTK_MFX")) mfx_set(MFX_MAX);
                    item.state = mfx_requested() == MFX_OFF ? NSControlStateValueOff : NSControlStateValueOn;
                }
            }
        }
    }
}
