#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <stdatomic.h>

static NSString *const WFWurstfingerBundleID = @"de.akator.wurstfinger.keyboard";
static atomic_bool WFSwitchScheduled = false;

static id WFSendObject(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL WFProcessIsSafeForOverride(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier.lowercaseString ?: @"";
    NSString *process = NSProcessInfo.processInfo.processName.lowercaseString ?: @"";

    if ([bundle isEqualToString:WFWurstfingerBundleID.lowercaseString]) {
        return NO;
    }

    NSArray<NSString *> *blocked = @[
        @"springboard", @"preboard", @"passcodeviewservice", @"coreauthui",
        @"lockscreen", @"setupassistant"
    ];
    for (NSString *needle in blocked) {
        if ([bundle containsString:needle] || [process containsString:needle]) {
            return NO;
        }
    }
    return YES;
}

static BOOL WFResponderNeedsOverride(id responder) {
    return responder != nil;
}

static BOOL WFIsWurstfingerInputMode(id mode) {
    id extension = WFSendObject(mode, NSSelectorFromString(@"extension"));
    id identifier = WFSendObject(extension, NSSelectorFromString(@"identifier"));
    return [identifier isKindOfClass:NSString.class] &&
           [(NSString *)identifier isEqualToString:WFWurstfingerBundleID];
}

static id WFFindWurstfingerInputMode(id controller) {
    NSArray<NSString *> *selectorNames = @[
        @"extensionInputModes", @"activeInputModes", @"enabledInputModes",
        @"keyboardInputModes", @"userSelectableKeyboardInputModes"
    ];
    for (NSString *selectorName in selectorNames) {
        id collection = WFSendObject(controller, NSSelectorFromString(selectorName));
        if (![collection isKindOfClass:NSArray.class]) {
            continue;
        }
        for (id mode in (NSArray *)collection) {
            if (WFIsWurstfingerInputMode(mode)) {
                return mode;
            }
        }
    }
    return nil;
}

static void WFForceKeyboardSwitch(id inputMode) {
    if (atomic_exchange(&WFSwitchScheduled, true)) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        Class implClass = NSClassFromString(@"UIKeyboardImpl");
        id impl = WFSendObject(implClass, NSSelectorFromString(@"sharedInstance"));
        SEL selector = NSSelectorFromString(@"setKeyboardInputMode:userInitiated:");
        if (impl && [impl respondsToSelector:selector]) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(impl, selector, inputMode, YES);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            atomic_store(&WFSwitchScheduled, false);
        });
    });
}

%hook UIKeyboardInputModeController

- (id)textInputModeForResponder:(id)responder {
    id originalMode = %orig;
    if (!WFProcessIsSafeForOverride() || !WFResponderNeedsOverride(responder)) {
        return originalMode;
    }

    id wurstfingerMode = WFFindWurstfingerInputMode(self);
    if (!wurstfingerMode) {
        return originalMode;
    }

    WFForceKeyboardSwitch(wurstfingerMode);
    return wurstfingerMode;
}

%end


%hook UIKeyboardImpl

- (BOOL)shouldSwitchInputMode:(id)inputMode {
    if (WFProcessIsSafeForOverride() && WFIsWurstfingerInputMode(inputMode)) {
        return YES;
    }
    return %orig;
}

- (BOOL)shouldSwitchFromInputManagerMode:(id)managerMode toInputMode:(id)inputMode {
    if (WFProcessIsSafeForOverride() && WFIsWurstfingerInputMode(inputMode)) {
        return YES;
    }
    return %orig;
}

%end
