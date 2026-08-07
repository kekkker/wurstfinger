#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/runtime.h>

static NSString *const WFOTPKeyboardBundleID = @"de.akator.wurstfinger.keyboard";
static const char *WFOTPKeyboardBridgeNotification =
    "de.akator.wurstsecure.keyboard-otp.v1";
static const NSTimeInterval WFOTPKeyboardLifetime = 5.0 * 60.0;

static __strong NSString *WFOTPKeyboardCode = nil;
static NSTimeInterval WFOTPKeyboardExpiry = 0;
static __weak UIInputViewController *WFOTPKeyboardController = nil;
static int WFOTPKeyboardBridgeToken = -1;

static BOOL WFOTPIsKeyboardExtensionProcess(void) {
    return [NSBundle.mainBundle.bundleIdentifier
        isEqualToString:WFOTPKeyboardBundleID];
}

static UIButton *WFOTPKeyboardButton(UIInputViewController *controller) {
    static char associationKey;
    UIButton *button = objc_getAssociatedObject(controller, &associationKey);
    if (button) return button;

    button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.hidden = YES;
    button.alpha = 0.0;
    button.layer.zPosition = CGFLOAT_MAX;
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCallout];

    UIButtonConfiguration *configuration =
        [UIButtonConfiguration plainButtonConfiguration];
    configuration.baseForegroundColor = UIColor.systemBlueColor;
    configuration.background.backgroundColor =
        [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.98];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(2.0, 10.0, 2.0, 10.0);
    button.configuration = configuration;

    [button addTarget:controller action:NSSelectorFromString(@"wfotp_acceptKeyboardCode:")
      forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:button];
    objc_setAssociatedObject(controller, &associationKey, button,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return button;
}

static NSString *WFOTPKeyboardDecodePayload(uint64_t payload) {
    NSUInteger length = (NSUInteger)((payload >> 40) & 0xFULL);
    uint64_t value = payload & 0xFFFFFFFFFFULL;
    uint64_t stamp = (payload >> 44) & 0xFFFFFULL;
    uint64_t now = ((uint64_t)(NSDate.date.timeIntervalSince1970 / 60.0)) & 0xFFFFFULL;
    uint64_t age = (now - stamp) & 0xFFFFFULL;
    if (length < 3 || length > 12 || age > 5) return nil;

    NSString *code = [NSString stringWithFormat:@"%0*llu",
        (int)length, (unsigned long long)value];
    return code.length == length ? code : nil;
}

static void WFOTPKeyboardRefresh(void) {
    UIInputViewController *controller = WFOTPKeyboardController;
    if (!controller || !controller.view) return;

    if (WFOTPKeyboardExpiry <= NSDate.date.timeIntervalSince1970) {
        WFOTPKeyboardCode = nil;
    }

    UIButton *button = WFOTPKeyboardButton(controller);
    BOOL shouldShow = WFOTPKeyboardCode.length > 0;

    if (!shouldShow) {
        button.hidden = YES;
        button.alpha = 0.0;
        return;
    }

    CGFloat availableWidth = MAX(0.0, CGRectGetWidth(controller.view.bounds) - 16.0);
    CGFloat width = MIN(250.0, availableWidth);
    button.frame = CGRectMake(
        floor((CGRectGetWidth(controller.view.bounds) - width) / 2.0),
        0.0, width, 32.0
    );
    [button setTitle:[NSString stringWithFormat:@"From Messages  %@", WFOTPKeyboardCode]
            forState:UIControlStateNormal];
    button.accessibilityLabel = [NSString stringWithFormat:
        @"One-time code %@ from Messages", WFOTPKeyboardCode];

    if (button.hidden) {
        button.hidden = NO;
        [UIView animateWithDuration:0.2 animations:^{
            button.alpha = 1.0;
        }];
    }

    [controller.view bringSubviewToFront:button];
}

static void WFOTPKeyboardReceivePayload(int token) {
    uint64_t payload = 0;
    if (notify_get_state(token, &payload) != NOTIFY_STATUS_OK) return;
    NSString *code = WFOTPKeyboardDecodePayload(payload);
    if (!code) return;
    WFOTPKeyboardCode = code;
    WFOTPKeyboardExpiry = NSDate.date.timeIntervalSince1970 + WFOTPKeyboardLifetime;
    WFOTPKeyboardRefresh();
}

static void WFOTPKeyboardStartBridge(void) {
    if (!WFOTPIsKeyboardExtensionProcess() || WFOTPKeyboardBridgeToken >= 0) return;
    if (notify_register_dispatch(WFOTPKeyboardBridgeNotification,
                                 &WFOTPKeyboardBridgeToken,
                                 dispatch_get_main_queue(), ^(int token) {
        WFOTPKeyboardReceivePayload(token);
    }) != NOTIFY_STATUS_OK) {
        WFOTPKeyboardBridgeToken = -1;
        return;
    }

    // Pick up a still-fresh code if the extension was relaunched after capture.
    WFOTPKeyboardReceivePayload(WFOTPKeyboardBridgeToken);
}

%hook UIInputViewController

- (void)viewDidLoad {
    %orig;
    if (!WFOTPIsKeyboardExtensionProcess()) return;
    WFOTPKeyboardController = self;
    WFOTPKeyboardStartBridge();
    WFOTPKeyboardRefresh();
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!WFOTPIsKeyboardExtensionProcess()) return;
    WFOTPKeyboardController = self;
    WFOTPKeyboardRefresh();
}

%new
- (void)wfotp_acceptKeyboardCode:(UIButton *)sender {
    if (!WFOTPIsKeyboardExtensionProcess() || WFOTPKeyboardCode.length == 0) return;
    [self.textDocumentProxy insertText:WFOTPKeyboardCode];

    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];

    WFOTPKeyboardCode = nil;
    WFOTPKeyboardExpiry = 0;

    [UIView animateWithDuration:0.15 animations:^{
        sender.alpha = 0.0;
    } completion:^(BOOL finished) {
        sender.hidden = YES;
    }];

    if (WFOTPKeyboardBridgeToken >= 0) {
        notify_set_state(WFOTPKeyboardBridgeToken, 0);
    }
}

%end

