#import <AppKit/AppKit.h>
#import <mach-o/getsect.h>
#import <mach-o/ldsyms.h>

static int execute(NSString *program, NSArray *args, NSURL *directory) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:program];
    task.arguments = args;
    task.currentDirectoryURL = directory;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    [task waitUntilExit];
    return task.terminationStatus;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc > 2 || (argc == 2 && !strcmp(argv[1], "--help"))) {
            puts("Usage: Longshot-Mac-Installer [previously-built-game-folder]\nBuild and install /Applications/Longshot.app using your own local game files.");
            return argc > 2;
        }
        NSString *game;
        if (argc == 2) game = [[NSString stringWithUTF8String:argv[1]] stringByStandardizingPath];
        else {
            [NSApplication sharedApplication];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [NSApp activateIgnoringOtherApps:YES];
            NSOpenPanel *panel = [NSOpenPanel openPanel];
            panel.message = @"Choose the game folder containing your Longshot build.";
            panel.canChooseDirectories = YES;
            panel.canChooseFiles = NO;
            if ([panel runModal] != NSModalResponseOK) return 0;
            game = panel.URL.path;
        }
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![game isAbsolutePath]) game = [fm.currentDirectoryPath stringByAppendingPathComponent:game];
        if (![fm fileExistsAtPath:[game stringByAppendingPathComponent:@".longshot_exefs/main"]]) {
            fputs("This folder does not contain an updatable game build.\n", stderr);
            return 2;
        }
        NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        if (![fm createDirectoryAtPath:work withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]) return 1;
        NSURL *dir = [NSURL fileURLWithPath:work];
        unsigned long size = 0;
        const uint8_t *bytes = getsectiondata(&_mh_execute_header, "__DATA_CONST", "__builder", &size);
        NSString *archive = [work stringByAppendingPathComponent:@"source.tar.gz"];
        int rc = 1;
        if (bytes && size && [[NSData dataWithBytesNoCopy:(void *)bytes length:size freeWhenDone:NO] writeToFile:archive atomically:YES]) {
            rc = execute(@"/usr/bin/tar", @[@"-xzf", archive], dir);
            /* Finder launches with a system-only PATH, while the builder and its tools use Homebrew. */
            NSString *path = [NSString stringWithFormat:@"/opt/homebrew/bin:/usr/local/bin:%s", getenv("PATH") ?: "/usr/bin:/bin"];
            setenv("PATH", path.UTF8String, 1);
            if (!rc) rc = execute(@"/usr/bin/env", @[@"python3", @"-I", @"nx2/make_game.py", @"--update", game, @"--no-prepare-shaders"], dir);
            if (!rc) rc = execute(@"/usr/bin/env", @[@"python3", @"scripts/mac/package_app.py", game], dir);
        }
        [fm removeItemAtPath:work error:nil];
        if (argc == 1) {
            NSAlert *notice = [[NSAlert alloc] init];
            notice.messageText = rc ? @"Longshot installation did not finish" : @"Longshot is installed in Applications";
            notice.informativeText = rc ? @"Run the installer from Terminal with the game folder to see the build diagnostics." : @"/Applications/Longshot.app";
            [notice runModal];
        }
        return rc;
    }
}
