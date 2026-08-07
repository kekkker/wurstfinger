#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>

extern BOOL WFWurstfingerIsExpectedForCurrentResponder(void);

static const char *WFOTPKeyboardBridgeNotification =
    "de.akator.wurstsecure.keyboard-otp.v1";

static __weak UIResponder *WFOTPFirstResponder = nil;
static int WFOTPBridgePublisherToken = -1;

static id WFOTPObject(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL WFOTPBool(id object, SEL selector) {
    return object && [object respondsToSelector:selector] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL WFOTPProcessIsAllowed(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier.lowercaseString ?: @"";
    NSString *process = NSProcessInfo.processInfo.processName.lowercaseString ?: @"";
    if ([bundle isEqualToString:@"de.akator.wurstfinger.keyboard"]) return NO;

    for (NSString *needle in @[
             @"springboard", @"preboard", @"passcodeviewservice", @"coreauthui",
             @"lockscreen", @"setupassistant"
         ]) {
        if ([bundle containsString:needle] || [process containsString:needle]) {
            return NO;
        }
    }
    return YES;
}

static NSString *WFOTPNumericCode(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *raw = (NSString *)value;
    NSMutableString *digits = [NSMutableString stringWithCapacity:raw.length];
    NSCharacterSet *allowedSeparators = [NSCharacterSet characterSetWithCharactersInString:
        @" -\u00a0\u202f"];

    for (NSUInteger index = 0; index < raw.length; index++) {
        unichar character = [raw characterAtIndex:index];
        if (character >= '0' && character <= '9') {
            [digits appendFormat:@"%C", character];
        } else if (![allowedSeparators characterIsMember:character]) {
            return nil;
        }
    }
    return digits.length >= 3 && digits.length <= 12 ? digits : nil;
}

static BOOL WFOTPResponderWantsOneTimeCode(void) {
    WFOTPFirstResponder = nil;
    [UIApplication.sharedApplication sendAction:
        NSSelectorFromString(@"wfotp_captureFirstResponder:")
        to:nil from:nil forEvent:nil];
    UIResponder *responder = WFOTPFirstResponder;

    id contentType = WFOTPObject(responder, NSSelectorFromString(@"textContentType"));
    if ([contentType isEqual:UITextContentTypeOneTimeCode]) return YES;

    id traits = WFOTPObject(responder, NSSelectorFromString(@"textInputTraits"));
    contentType = WFOTPObject(traits, NSSelectorFromString(@"textContentType"));
    return [contentType isEqual:UITextContentTypeOneTimeCode];
}

static BOOL WFOTPIsSecureCandidate(id candidate) {
    if (!candidate) return NO;
    return [NSStringFromClass([candidate class]) containsString:@"SecureCandidate"] ||
        WFOTPBool(candidate, NSSelectorFromString(@"isSecureContentCandidate"));
}

static NSString *WFOTPCodeFromCandidate(id candidate) {
    if (!candidate) return nil;
    BOOL secure = WFOTPIsSecureCandidate(candidate);
    BOOL autofill = WFOTPBool(candidate, NSSelectorFromString(@"isAutofillCandidate"));
    if (!secure && !autofill) return nil;

    for (NSString *selectorName in @[
             @"input", @"candidate", @"inputWithoutSupplementalItemPrefix"
         ]) {
        NSString *code = WFOTPNumericCode(
            WFOTPObject(candidate, NSSelectorFromString(selectorName))
        );
        if (code) return code;
    }
    return nil;
}

static NSArray *WFOTPFilteredCandidates(id value, NSString **codeOut,
                                        BOOL *secureOut) {
    if (![value isKindOfClass:NSArray.class]) return nil;
    NSArray *candidates = (NSArray *)value;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:candidates.count];
    NSString *foundCode = nil;
    BOOL foundSecure = NO;

    for (id candidate in candidates) {
        NSString *code = WFOTPCodeFromCandidate(candidate);
        if (!foundCode && code) {
            foundCode = code;
            foundSecure = WFOTPIsSecureCandidate(candidate);
        }
        if (!code) [filtered addObject:candidate];
    }

    if (codeOut) *codeOut = foundCode;
    if (secureOut) *secureOut = foundSecure;
    return foundCode ? filtered : candidates;
}

static BOOL WFOTPShouldHandle(NSString *code, BOOL secureCandidate) {
    if (!code || !WFOTPProcessIsAllowed() ||
        !WFWurstfingerIsExpectedForCurrentResponder()) {
        return NO;
    }
    return secureCandidate || WFOTPResponderWantsOneTimeCode();
}

static void WFOTPPublishCodeToKeyboard(NSString *code) {
    if (code.length < 3 || code.length > 12) return;
    if (WFOTPBridgePublisherToken < 0 &&
        notify_register_check(WFOTPKeyboardBridgeNotification,
                              &WFOTPBridgePublisherToken) != NOTIFY_STATUS_OK) {
        return;
    }

    uint64_t value = code.longLongValue;
    uint64_t length = code.length;
    uint64_t minute =
        ((uint64_t)(NSDate.date.timeIntervalSince1970 / 60.0)) & 0xFFFFF;
    uint64_t payload = (value & 0xFFFFFFFFFFULL) |
        ((length & 0xFULL) << 40) | (minute << 44);
    if (notify_set_state(WFOTPBridgePublisherToken, payload) == NOTIFY_STATUS_OK) {
        notify_post(WFOTPKeyboardBridgeNotification);
    }
}

static id WFOTPFilteredResultSet(id resultSet) {
    NSArray *candidates = WFOTPObject(resultSet, NSSelectorFromString(@"candidates"));
    NSString *code = nil;
    BOOL secureCandidate = NO;
    NSArray *filtered = WFOTPFilteredCandidates(candidates, &code, &secureCandidate);
    if (!WFOTPShouldHandle(code, secureCandidate)) return resultSet;

    WFOTPPublishCodeToKeyboard(code);
    id copy = [resultSet copy];
    SEL setter = NSSelectorFromString(@"setCandidates:");
    if (copy && [copy respondsToSelector:setter]) {
        ((void (*)(id, SEL, id))objc_msgSend)(copy, setter, filtered);
        return copy;
    }
    return resultSet;
}

static NSArray *WFOTPHandleCandidateArray(id candidates) {
    NSString *code = nil;
    BOOL secureCandidate = NO;
    NSArray *filtered = WFOTPFilteredCandidates(candidates, &code, &secureCandidate);
    if (!WFOTPShouldHandle(code, secureCandidate)) return candidates;

    WFOTPPublishCodeToKeyboard(code);
    return filtered;
}

%hook UIResponder

%new
- (void)wfotp_captureFirstResponder:(id)sender {
    (void)sender;
    WFOTPFirstResponder = self;
}

%end

%hook UIKeyboardCandidateController

- (void)setCandidateResultSet:(id)resultSet {
    %orig(WFOTPFilteredResultSet(resultSet));
}

- (void)setCandidates:(id)candidates
                  type:(int)type
            inlineText:(id)inlineText
            inlineRect:(CGRect)inlineRect
                  maxX:(double)maxX
                 layout:(BOOL)layout {
    %orig(WFOTPHandleCandidateArray(candidates), type, inlineText,
          inlineRect, maxX, layout);
}

- (void)setCandidates:(id)candidates
            inlineText:(id)inlineText
            inlineRect:(CGRect)inlineRect
                  maxX:(double)maxX
                 layout:(BOOL)layout {
    %orig(WFOTPHandleCandidateArray(candidates), inlineText,
          inlineRect, maxX, layout);
}

%end
