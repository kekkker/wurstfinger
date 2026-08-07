#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdarg.h>
#import <string.h>
#import <sys/param.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <unistd.h>

static NSString *const WFWurstfingerBundleID = @"de.akator.wurstfinger.keyboard";
static __strong id WFCachedWurstfingerInputMode = nil;

static BOOL WFStringContainsAny(NSString *value, NSArray<NSString *> *needles) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *lower = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) return YES;
    }
    return NO;
}

static BOOL WFIsJailbreakNSString(id path) {
    if (![path isKindOfClass:NSString.class]) return NO;
    return WFStringContainsAny((NSString *)path, @[
        @"/var/jb", @"/private/preboot/", @"/applications/cydia.app",
        @"/applications/sileo.app", @"/applications/zebra.app",
        @"/applications/filza.app", @"/library/mobilesubstrate",
        @"/library/substrate", @"/usr/lib/libsubstrate",
        @"/usr/lib/substitute", @"/usr/lib/ellekit", @"/etc/apt",
        @"/var/lib/apt", @"/var/lib/dpkg", @"/usr/sbin/sshd",
        @"/.installed_dopamine", @"/.installed_unc0ver", @"/jb/"
    ]);
}

static BOOL WFIsJailbreakPath(const char *path) {
    if (!path) return NO;
    NSString *value = [NSString stringWithUTF8String:path];
    return WFIsJailbreakNSString(value);
}

static BOOL WFIsJailbreakURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return NO;
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    return [@[@"cydia", @"sileo", @"zbra", @"filza", @"activator",
              @"undecimus", @"dopamine"] containsObject:scheme];
}

static void WFDenyPath(void) {
    errno = ENOENT;
}

static int WFAccess(const char *path, int mode) {
    if (WFIsJailbreakPath(path)) {
        WFDenyPath();
        return -1;
    }
    return access(path, mode);
}

static int WFStat(const char *path, struct stat *buffer) {
    if (WFIsJailbreakPath(path)) {
        WFDenyPath();
        return -1;
    }
    return stat(path, buffer);
}

static int WFLstat(const char *path, struct stat *buffer) {
    if (WFIsJailbreakPath(path)) {
        WFDenyPath();
        return -1;
    }
    return lstat(path, buffer);
}

static FILE *WFFopen(const char *path, const char *mode) {
    if (WFIsJailbreakPath(path)) {
        WFDenyPath();
        return NULL;
    }
    return fopen(path, mode);
}

static int WFOpen(const char *path, int flags, ...) {
    if (WFIsJailbreakPath(path)) {
        WFDenyPath();
        return -1;
    }
    if ((flags & O_CREAT) != 0) {
        va_list arguments;
        va_start(arguments, flags);
        mode_t mode = (mode_t)va_arg(arguments, int);
        va_end(arguments);
        return open(path, flags, mode);
    }
    return open(path, flags);
}

static int WFStatfs(const char *path, struct statfs *buffer) {
    if (WFIsJailbreakPath(path)) {
        WFDenyPath();
        return -1;
    }
    return statfs(path, buffer);
}

static pid_t WFFork(void) {
    errno = EPERM;
    return -1;
}

static char *WFGetenv(const char *name) {
    if (name) {
        NSString *value = [NSString stringWithUTF8String:name];
        if (WFStringContainsAny(value, @[
                @"dyld_insert_libraries", @"_mssafemode", @"substrate",
                @"ellekit", @"frida"
            ])) {
            return NULL;
        }
    }
    return getenv(name);
}

static int WFSysctl(int *name, u_int nameLength, void *oldValue,
                    size_t *oldLength, void *newValue, size_t newLength) {
    int result = sysctl(name, nameLength, oldValue, oldLength, newValue, newLength);
    if (result == 0 && oldValue && oldLength && nameLength == 4 &&
        name[0] == CTL_KERN && name[1] == KERN_PROC &&
        name[2] == KERN_PROC_PID && *oldLength >= sizeof(struct kinfo_proc)) {
        struct kinfo_proc *process = oldValue;
        process->kp_proc.p_flag &= ~P_TRACED;
    }
    return result;
}

static int WFSysctlByName(const char *name, void *oldValue, size_t *oldLength,
                          void *newValue, size_t newLength) {
    if (name) {
        NSString *value = [NSString stringWithUTF8String:name];
        if (WFStringContainsAny(value, @[
                @"security.mac.proc_enforce", @"security.mac.vnode_enforce",
                @"kern.bootargs"
            ])) {
            errno = ENOENT;
            return -1;
        }
    }
    return sysctlbyname(name, oldValue, oldLength, newValue, newLength);
}

static void *WFDlopen(const char *path, int mode) {
    if (WFIsJailbreakPath(path)) {
        WFDenyPath();
        return NULL;
    }
    return dlopen(path, mode);
}

static int WFPtrace(int request, pid_t pid, void *address, int data) {
    (void)request;
    (void)pid;
    (void)address;
    (void)data;
    return 0;
}

static const char *WFDyldGetImageName(uint32_t index);

static void *WFDlsym(void *handle, const char *symbol) {
    if (symbol) {
        if (strcmp(symbol, "ptrace") == 0) return (void *)&WFPtrace;
        if (strcmp(symbol, "sysctl") == 0) return (void *)&WFSysctl;
        if (strcmp(symbol, "sysctlbyname") == 0) return (void *)&WFSysctlByName;
        if (strcmp(symbol, "access") == 0) return (void *)&WFAccess;
        if (strcmp(symbol, "stat") == 0) return (void *)&WFStat;
        if (strcmp(symbol, "lstat") == 0) return (void *)&WFLstat;
        if (strcmp(symbol, "fopen") == 0) return (void *)&WFFopen;
        if (strcmp(symbol, "open") == 0) return (void *)&WFOpen;
        if (strcmp(symbol, "statfs") == 0) return (void *)&WFStatfs;
        if (strcmp(symbol, "fork") == 0) return (void *)&WFFork;
        if (strcmp(symbol, "getenv") == 0) return (void *)&WFGetenv;
        if (strcmp(symbol, "dlopen") == 0) return (void *)&WFDlopen;
        if (strcmp(symbol, "_dyld_get_image_name") == 0) {
            return (void *)&WFDyldGetImageName;
        }
    }
    return dlsym(handle, symbol);
}

static const char *WFDyldGetImageName(uint32_t index) {
    const char *name = _dyld_get_image_name(index);
    if (!name) return NULL;
    NSString *value = [NSString stringWithUTF8String:name];
    if (WFStringContainsAny(value, @[
            @"/var/jb/", @"/library/mobilesubstrate/", @"/usr/lib/ellekit/",
            @"wurstvinted.dylib", @"wurstsecure.dylib"
        ])) {
        return "/System/Library/Frameworks/UIKit.framework/UIKit";
    }
    return name;
}

#define WF_ENABLE_DYLD_INTERPOSE 0

#if WF_ENABLE_DYLD_INTERPOSE
#define WF_INTERPOSE(replacement, replacee)                                    \
    __attribute__((used)) static struct {                                      \
        const void *replacement;                                               \
        const void *replacee;                                                  \
    } _wf_interpose_##replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(uintptr_t)&replacement,                                 \
        (const void *)(uintptr_t)&replacee                                     \
    }

WF_INTERPOSE(WFAccess, access);
WF_INTERPOSE(WFStat, stat);
WF_INTERPOSE(WFLstat, lstat);
WF_INTERPOSE(WFFopen, fopen);
WF_INTERPOSE(WFOpen, open);
WF_INTERPOSE(WFStatfs, statfs);
WF_INTERPOSE(WFFork, fork);
WF_INTERPOSE(WFGetenv, getenv);
WF_INTERPOSE(WFSysctl, sysctl);
WF_INTERPOSE(WFSysctlByName, sysctlbyname);
WF_INTERPOSE(WFDlopen, dlopen);
WF_INTERPOSE(WFDlsym, dlsym);
WF_INTERPOSE(WFDyldGetImageName, _dyld_get_image_name);
#endif

static BOOL (*WFOriginalFileExists)(id, SEL, NSString *) = NULL;
static BOOL WFFileExists(id object, SEL selector, NSString *path) {
    if (WFIsJailbreakNSString(path)) return NO;
    return WFOriginalFileExists(object, selector, path);
}

static BOOL (*WFOriginalFileExistsDirectory)(id, SEL, NSString *, BOOL *) = NULL;
static BOOL WFFileExistsDirectory(id object, SEL selector, NSString *path,
                                  BOOL *isDirectory) {
    if (WFIsJailbreakNSString(path)) {
        if (isDirectory) *isDirectory = NO;
        return NO;
    }
    return WFOriginalFileExistsDirectory(object, selector, path, isDirectory);
}

static BOOL (*WFOriginalCanOpenURL)(id, SEL, NSURL *) = NULL;
static BOOL WFCanOpenURL(id object, SEL selector, NSURL *url) {
    if (WFIsJailbreakURL(url)) return NO;
    return WFOriginalCanOpenURL(object, selector, url);
}

static BOOL WFReturnYes(id object, SEL selector, ...) {
    (void)object;
    (void)selector;
    return YES;
}

static id WFSendObject(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL WFIsWurstfingerInputMode(id mode) {
    id extension = WFSendObject(mode, NSSelectorFromString(@"extension"));
    id identifier = WFSendObject(extension, NSSelectorFromString(@"identifier"));
    return [identifier isKindOfClass:NSString.class] &&
           [(NSString *)identifier isEqualToString:WFWurstfingerBundleID];
}

static id WFFindWurstfingerInputMode(id controller) {
    for (NSString *selectorName in @[
             @"extensionInputModes", @"activeInputModes", @"enabledInputModes",
             @"keyboardInputModes", @"userSelectableKeyboardInputModes"
         ]) {
        id collection = WFSendObject(controller, NSSelectorFromString(selectorName));
        if (![collection isKindOfClass:NSArray.class]) continue;
        for (id mode in (NSArray *)collection) {
            if (WFIsWurstfingerInputMode(mode)) {
                WFCachedWurstfingerInputMode = mode;
                return mode;
            }
        }
    }
    return nil;
}

static id (*WFOriginalTextInputMode)(id, SEL, id) = NULL;
static id WFTextInputMode(id controller, SEL selector, id responder) {
    id original = WFOriginalTextInputMode(controller, selector, responder);
    id wurstfinger = WFFindWurstfingerInputMode(controller);
    if (!wurstfinger) return original;

    Class implementationClass = NSClassFromString(@"UIKeyboardImpl");
    id implementation = WFSendObject(implementationClass,
                                     NSSelectorFromString(@"sharedInstance"));
    SEL setMode = NSSelectorFromString(@"setKeyboardInputMode:userInitiated:");
    if (implementation && [implementation respondsToSelector:setMode]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                implementation, setMode, wurstfinger, YES);
        });
    }
    return wurstfinger;
}

static void (*WFOriginalSetInputMode)(id, SEL, id, BOOL) = NULL;
static void WFSetInputMode(id object, SEL selector, id mode, BOOL userInitiated) {
    id forced = WFCachedWurstfingerInputMode;
    if (forced && mode && !WFIsWurstfingerInputMode(mode)) {
        mode = forced;
        userInitiated = YES;
    }
    WFOriginalSetInputMode(object, selector, mode, userInitiated);
}

static UIEdgeInsets (*WFOriginalSafeArea)(id, SEL) = NULL;
static UIEdgeInsets WFSafeArea(id object, SEL selector) {
    UIEdgeInsets insets = WFOriginalSafeArea(object, selector);
    if (WFCachedWurstfingerInputMode) insets.bottom = 0.0;
    return insets;
}

static void WFReplaceInstanceMethod(Class cls, SEL selector, IMP replacement,
                                    IMP *original) {
    if (!cls) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP previous = method_setImplementation(method, replacement);
    if (original) *original = previous;
}

__attribute__((constructor)) static void WFInitialize(void) {
    @autoreleasepool {
        WFReplaceInstanceMethod(NSFileManager.class,
            @selector(fileExistsAtPath:), (IMP)WFFileExists,
            (IMP *)&WFOriginalFileExists);
        WFReplaceInstanceMethod(NSFileManager.class,
            @selector(fileExistsAtPath:isDirectory:), (IMP)WFFileExistsDirectory,
            (IMP *)&WFOriginalFileExistsDirectory);
        WFReplaceInstanceMethod(UIApplication.class, @selector(canOpenURL:),
            (IMP)WFCanOpenURL, (IMP *)&WFOriginalCanOpenURL);

        Class controller = NSClassFromString(@"UIKeyboardInputModeController");
        WFReplaceInstanceMethod(controller,
            NSSelectorFromString(@"verifyKeyboardExtensionsWithApp"),
            (IMP)WFReturnYes, NULL);
        WFReplaceInstanceMethod(controller,
            NSSelectorFromString(@"textInputModeForResponder:"),
            (IMP)WFTextInputMode, (IMP *)&WFOriginalTextInputMode);

        Class extensionMode = NSClassFromString(@"UIKeyboardExtensionInputMode");
        WFReplaceInstanceMethod(extensionMode,
            NSSelectorFromString(@"isDesiredForTraits:"),
            (IMP)WFReturnYes, NULL);
        WFReplaceInstanceMethod(extensionMode,
            NSSelectorFromString(@"isAllowedForTraits:"),
            (IMP)WFReturnYes, NULL);

        Class implementation = NSClassFromString(@"UIKeyboardImpl");
        WFReplaceInstanceMethod(implementation,
            NSSelectorFromString(@"setKeyboardInputMode:userInitiated:"),
            (IMP)WFSetInputMode, (IMP *)&WFOriginalSetInputMode);

        Class inputController = NSClassFromString(@"UIInputWindowController");
        WFReplaceInstanceMethod(inputController,
            NSSelectorFromString(@"_viewSafeAreaInsetsFromScene"),
            (IMP)WFSafeArea, (IMP *)&WFOriginalSafeArea);
    }
}
