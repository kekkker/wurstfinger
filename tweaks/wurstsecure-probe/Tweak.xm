#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <os/log.h>

static NSString *const WFWurstfingerBundleID = @"de.akator.wurstfinger.keyboard";
static __strong id WFCachedWurstfingerInputMode = nil;
static BOOL WFProcessIsSafeForOverride(void);
static os_log_t WFLog = NULL;

#define WFLogInfo(fmt, ...) if (WFLog) os_log(WFLog, fmt, ##__VA_ARGS__)
#define WFLogError(fmt, ...) if (WFLog) os_log_error(WFLog, fmt, ##__VA_ARGS__)

BOOL WFWurstfingerIsExpectedForCurrentResponder(void) {
    return WFProcessIsSafeForOverride() && WFCachedWurstfingerInputMode != nil;
}

static id WFSendObject(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL WFIsKeyboardExtension(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    return [bundleID isEqualToString:@"de.akator.wurstfinger.keyboard"];
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

static BOOL WFTextInputAllowsSpellChecking(id input) {
    if (!WFProcessIsSafeForOverride() || !input) {
        return NO;
    }

    SEL secureSelector = NSSelectorFromString(@"isSecureTextEntry");
    if ([input respondsToSelector:secureSelector] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(input, secureSelector)) {
        return NO;
    }

    SEL keyboardTypeSelector = NSSelectorFromString(@"keyboardType");
    if ([input respondsToSelector:keyboardTypeSelector]) {
        NSInteger keyboardType =
            ((NSInteger (*)(id, SEL))objc_msgSend)(input, keyboardTypeSelector);
        switch (keyboardType) {
            case UIKeyboardTypeDefault:
            case UIKeyboardTypeASCIICapable:
            case UIKeyboardTypeNamePhonePad:
            case UIKeyboardTypeWebSearch:
                break;
            default:
                return NO;
        }
    }

    id contentType = WFSendObject(input, NSSelectorFromString(@"textContentType"));
    NSArray *excludedContentTypes = @[
        UITextContentTypeEmailAddress, UITextContentTypeURL,
        UITextContentTypeTelephoneNumber, UITextContentTypeUsername,
        UITextContentTypePassword, UITextContentTypeNewPassword,
        UITextContentTypeOneTimeCode, UITextContentTypeCreditCardNumber
    ];
    return !contentType || ![excludedContentTypes containsObject:contentType];
}

static BOOL WFIsWurstfingerInputMode(id mode) {
    id extension = WFSendObject(mode, NSSelectorFromString(@"extension"));
    id identifier = WFSendObject(extension, NSSelectorFromString(@"identifier"));
    return [identifier isKindOfClass:NSString.class] &&
           [(NSString *)identifier isEqualToString:WFWurstfingerBundleID];
}

static id WFFindWurstfingerInputMode(id controller) {
    if (WFCachedWurstfingerInputMode && WFIsWurstfingerInputMode(WFCachedWurstfingerInputMode)) {
        return WFCachedWurstfingerInputMode;
    }

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
                WFCachedWurstfingerInputMode = mode;
                WFLogInfo("Cached wurstfinger input mode from %{public}@", selectorName);
                return mode;
            }
        }
    }

    WFLogError("Failed to find wurstfinger input mode in any collection");
    return nil;
}

static void WFSetKeyboardInputMode(id inputMode, BOOL force) {
    if (!inputMode) {
        WFLogError("Attempted to set nil input mode");
        return;
    }

    Class implClass = NSClassFromString(@"UIKeyboardImpl");
    id impl = WFSendObject(implClass, NSSelectorFromString(@"sharedInstance"));
    SEL selector = NSSelectorFromString(@"setKeyboardInputMode:userInitiated:");
    if (impl && [impl respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(impl, selector, inputMode, YES);
        WFLogInfo("Set keyboard input mode (force=%d)", force);

        if (force) {
            SEL activateSelector = NSSelectorFromString(@"updateLayout");
            if ([impl respondsToSelector:activateSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(impl, activateSelector);
            }
        }
    } else {
        WFLogError("Failed to get UIKeyboardImpl or selector not found");
    }
}

static void WFValidateAndRetryKeyboardSwitch(void) {
    if (!WFProcessIsSafeForOverride() || !WFCachedWurstfingerInputMode) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        Class implClass = NSClassFromString(@"UIKeyboardImpl");
        id impl = WFSendObject(implClass, NSSelectorFromString(@"sharedInstance"));
        id currentMode = WFSendObject(impl, NSSelectorFromString(@"currentInputMode"));

        if (!WFIsWurstfingerInputMode(currentMode)) {
            WFLogError("Keyboard validation failed, retrying wurstfinger switch");
            WFSetKeyboardInputMode(WFCachedWurstfingerInputMode, YES);
        }
    });
}

%hook UIKeyboardInputModeController

- (id)textInputModeForResponder:(id)responder {
    id originalMode = %orig;
    if (!WFProcessIsSafeForOverride() || !responder) {
        return originalMode;
    }

    id wurstfingerMode = WFFindWurstfingerInputMode(self);
    if (!wurstfingerMode) {
        WFLogError("Wurstfinger mode not found for responder");
        return originalMode;
    }

    WFSetKeyboardInputMode(wurstfingerMode, NO);
    WFValidateAndRetryKeyboardSwitch();
    return wurstfingerMode;
}

%end


%hook UITextField

- (UITextSpellCheckingType)spellCheckingType {
    if (WFProcessIsSafeForOverride()) {
        return WFTextInputAllowsSpellChecking(self)
            ? UITextSpellCheckingTypeYes : UITextSpellCheckingTypeNo;
    }
    return %orig;
}

- (void)setSpellCheckingType:(UITextSpellCheckingType)type {
    if (WFProcessIsSafeForOverride()) {
        type = WFTextInputAllowsSpellChecking(self)
            ? UITextSpellCheckingTypeYes : UITextSpellCheckingTypeNo;
    }
    %orig(type);
}

%end


%hook UITextView

- (UITextSpellCheckingType)spellCheckingType {
    if (WFProcessIsSafeForOverride()) {
        return WFTextInputAllowsSpellChecking(self)
            ? UITextSpellCheckingTypeYes : UITextSpellCheckingTypeNo;
    }
    return %orig;
}

- (void)setSpellCheckingType:(UITextSpellCheckingType)type {
    if (WFProcessIsSafeForOverride()) {
        type = WFTextInputAllowsSpellChecking(self)
            ? UITextSpellCheckingTypeYes : UITextSpellCheckingTypeNo;
    }
    %orig(type);
}

%end


// Zeroing the bottom insets is what keeps the keyboard flush against the
// screen edge. Leaving iOS's natural spacing in place re-exposes the
// home-indicator band below the keyboard, which renders as a gray strip.
%hook UIRemoteKeyboardWindowHosted

- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = %orig;
    if (WFProcessIsSafeForOverride() && WFCachedWurstfingerInputMode) {
        insets.bottom = 0.0;
    }
    return insets;
}

%end


%hook UIInputWindowController

- (UIEdgeInsets)_viewSafeAreaInsetsFromScene {
    UIEdgeInsets insets = %orig;
    if (WFProcessIsSafeForOverride() && WFCachedWurstfingerInputMode) {
        insets.bottom = 0.0;
    }
    return insets;
}

%end


// The gray strip under the keyboard holding the globe and dictation buttons.
// Confirmed by view-hierarchy dump: UIKeyboardDockView with two
// UIKeyboardDockItemButton children, living in UITextEffectsWindow. Hiding it
// and zeroing its height drops the strip without touching UIInputSetHostView,
// the shared container whose removal takes the whole keyboard with it.
%hook UIKeyboardDockView

- (void)setHidden:(BOOL)hidden {
    if (WFProcessIsSafeForOverride()) {
        hidden = YES;
    }
    %orig(hidden);
}

// Hiding alone leaves the dock's 75pt reserved, and the out-of-process
// keyboard layer fills that band — which is the strip. Collapse the size
// through every path the layout may use, not just setFrame:.
- (void)setFrame:(CGRect)frame {
    if (WFProcessIsSafeForOverride()) {
        frame.size.height = 0.0;
    }
    %orig(frame);
}

- (void)setBounds:(CGRect)bounds {
    if (WFProcessIsSafeForOverride()) {
        bounds.size.height = 0.0;
    }
    %orig(bounds);
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fitted = %orig;
    if (WFProcessIsSafeForOverride()) {
        fitted.height = 0.0;
    }
    return fitted;
}

- (CGSize)intrinsicContentSize {
    CGSize intrinsic = %orig;
    if (WFProcessIsSafeForOverride()) {
        intrinsic.height = 0.0;
    }
    return intrinsic;
}

- (void)layoutSubviews {
    %orig;
    if (WFProcessIsSafeForOverride()) {
        ((UIView *)self).hidden = YES;
    }
}

%end


%hook UIKeyboardImpl

+ (UIEdgeInsets)deviceSpecificPaddingForInterfaceOrientation:(NSInteger)orientation
                                                   inputMode:(id)inputMode {
    UIEdgeInsets padding = %orig;
    if (WFProcessIsSafeForOverride() &&
        (WFIsWurstfingerInputMode(inputMode) || WFCachedWurstfingerInputMode)) {
        padding.bottom = 0.0;
    }
    return padding;
}

- (void)setKeyboardInputMode:(id)inputMode userInitiated:(BOOL)userInitiated {
    id forcedMode = WFCachedWurstfingerInputMode;
    if (WFProcessIsSafeForOverride() && forcedMode && inputMode &&
        !WFIsWurstfingerInputMode(inputMode)) {
        WFLogInfo("Intercepting keyboard switch to %{public}@, forcing wurstfinger",
                  [inputMode description]);
        inputMode = forcedMode;
        userInitiated = YES;
    }
    %orig(inputMode, userInitiated);
}

- (BOOL)shouldSwitchInputMode:(id)inputMode {
    if (WFProcessIsSafeForOverride() && WFIsWurstfingerInputMode(inputMode)) {
        return YES;
    }
    BOOL result = %orig;
    if (WFProcessIsSafeForOverride() && !result && WFIsWurstfingerInputMode(inputMode)) {
        WFLogError("System denied wurstfinger switch, overriding");
        return YES;
    }
    return result;
}

- (BOOL)shouldSwitchFromInputManagerMode:(id)managerMode toInputMode:(id)inputMode {
    if (WFProcessIsSafeForOverride() && WFIsWurstfingerInputMode(inputMode)) {
        return YES;
    }
    BOOL result = %orig;
    if (WFProcessIsSafeForOverride() && !result && WFIsWurstfingerInputMode(inputMode)) {
        WFLogError("System denied wurstfinger manager switch, overriding");
        return YES;
    }
    return result;
}

%end


%hook UIView

- (void)didMoveToSuperview {
    %orig;
    if (WFIsKeyboardExtension() && self.superview) {
        NSString *className = NSStringFromClass([self class]);
        CGRect frame = self.frame;

        // Hide any view that looks like the accessory bar
        if ([className containsString:@"Toolbar"] ||
            [className containsString:@"ToolBar"] ||
            [className containsString:@"Accessory"] ||
            [className containsString:@"ButtonBar"] ||
            [className containsString:@"ShortcutBar"] ||
            [className isEqualToString:@"UIView"]) {

            // Check if it's in the top area and has reasonable height for a toolbar
            if (frame.origin.y < 100 && frame.size.height > 30 && frame.size.height < 100) {
                self.hidden = YES;
                self.alpha = 0.0;
            }
        }
    }
}

%end

%ctor {
    @autoreleasepool {
        if (WFProcessIsSafeForOverride()) {
            WFLog = os_log_create("de.akator.wurstsecure", "keyboard");
            WFLogInfo("WurstSecure loaded in process %{public}@",
                      NSProcessInfo.processInfo.processName);
        }
    }
}
