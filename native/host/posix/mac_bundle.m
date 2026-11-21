#import <AppKit/AppKit.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#import <QuartzCore/CAMetalLayer.h>

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
        if (![app.bundleIdentifier isEqual:@"dev.longshot.game"]) return 1;
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *support = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Longshot"];
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
        if ([fm fileExistsAtPath:[metalDir stringByAppendingPathComponent:@"shader-service"]])
            setenv("RX_RENDERER", "metal", 0);
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
