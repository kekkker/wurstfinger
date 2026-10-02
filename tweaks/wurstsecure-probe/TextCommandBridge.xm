#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>

// Host side of Wurstfinger's text command bridge. Keyboard extensions cannot
// select text, select all, undo or redo through UITextDocumentProxy, so the
// extension posts these commands as a Darwin notification and this code runs
// them on the focused text input of the app in front.
//
// Payload (the notification's 64-bit state), shared with
// wurstfingerKeyboard/Runtime/Pipeline/TextCommandBridge.swift:
//   bits 0-7   opcode
//   bits 8-15  sequence number
//   bits 16-39 first argument  (24-bit two's complement)
//   bits 40-63 second argument (24-bit two's complement)

static const char *WFTextCommandNotification = "de.akator.wurstfinger.text-command.v1";
static NSString *const WFTextCommandKeyboardBundleID = @"de.akator.wurstfinger.keyboard";
static const char *WFTextCommandPresenceVariable = "WURSTSECURE_TEXT_BRIDGE";

typedef NS_ENUM(uint8_t, WFTextCommandOpcode) {
    WFTextCommandSelectAll = 1,
    WFTextCommandUndo = 2,
    WFTextCommandRedo = 3,
    WFTextCommandBeginSelection = 4,
    WFTextCommandExtendSelection = 5,
    WFTextCommandCollapseSelection = 6,
    WFTextCommandSelectRelative = 7,
    WFTextCommandLineStart = 8,
    WFTextCommandLineEnd = 9,
    WFTextCommandDocumentStart = 10,
    WFTextCommandDocumentEnd = 11,
};

static int WFTextCommandToken = -1;
static __weak UIResponder *WFTextCommandFoundResponder = nil;
static __weak id<UITextInput> WFTextCommandAnchorInput = nil;
static UITextPosition *WFTextCommandAnchor = nil;

static int32_t WFTextCommandSignExtend24(uint64_t value) {
    int32_t raw = (int32_t)(value & 0xFFFFFF);
    return (raw & 0x800000) ? raw - 0x1000000 : raw;
}

%hook UIResponder

%new
- (void)wf_captureTextCommandResponder:(id)sender {
    WFTextCommandFoundResponder = self;
}

%end

/// The focused text input of this process, if it is in front.
static UIResponder<UITextInput> *WFTextCommandFocusedInput(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (!application || application.applicationState != UIApplicationStateActive) return nil;

    WFTextCommandFoundResponder = nil;
    [application sendAction:@selector(wf_captureTextCommandResponder:) to:nil from:nil forEvent:nil];
    UIResponder *responder = WFTextCommandFoundResponder;
    if (!responder.isFirstResponder || ![responder conformsToProtocol:@protocol(UITextInput)]) return nil;
    return (UIResponder<UITextInput> *)responder;
}

static void WFTextCommandSelect(id<UITextInput> input, UITextPosition *from, UITextPosition *to) {
    if (!from || !to) return;
    if ([input comparePosition:from toPosition:to] == NSOrderedDescending) {
        UITextPosition *swap = from;
        from = to;
        to = swap;
    }
    UITextRange *range = [input textRangeFromPosition:from toPosition:to];
    if (range) input.selectedTextRange = range;
}

/// Moves the cursor to a line boundary unless it is already there.
static void WFTextCommandMoveToLineBoundary(id<UITextInput> input, UITextPosition *cursor, UITextDirection direction) {
    id<UITextInputTokenizer> tokenizer = input.tokenizer;
    UITextPosition *target = cursor;
    if (![tokenizer isPosition:cursor atBoundary:UITextGranularityLine inDirection:direction]) {
        target = [tokenizer positionFromPosition:cursor toBoundary:UITextGranularityLine inDirection:direction];
    }
    WFTextCommandSelect(input, target, target);
}

static void WFTextCommandHandle(uint64_t payload) {
    UIResponder<UITextInput> *input = WFTextCommandFocusedInput();
    if (!input) return;

    WFTextCommandOpcode opcode = (WFTextCommandOpcode)(payload & 0xFF);
    int32_t first = WFTextCommandSignExtend24(payload >> 16);
    int32_t second = WFTextCommandSignExtend24(payload >> 40);
    UITextRange *selection = input.selectedTextRange;

    switch (opcode) {
        case WFTextCommandSelectAll:
            if ([input respondsToSelector:@selector(selectAll:)]) [input selectAll:nil];
            break;
        case WFTextCommandUndo:
            if (input.undoManager.canUndo) [input.undoManager undo];
            break;
        case WFTextCommandRedo:
            if (input.undoManager.canRedo) [input.undoManager redo];
            break;
        case WFTextCommandBeginSelection:
            WFTextCommandAnchorInput = input;
            WFTextCommandAnchor = selection.start;
            break;
        case WFTextCommandExtendSelection: {
            if (WFTextCommandAnchorInput != input || !WFTextCommandAnchor) break;
            UITextPosition *end = [input positionFromPosition:WFTextCommandAnchor offset:first]
                ?: (first < 0 ? input.beginningOfDocument : input.endOfDocument);
            WFTextCommandSelect(input, WFTextCommandAnchor, end);
            break;
        }
        case WFTextCommandCollapseSelection: {
            UITextPosition *position = first ? selection.end : selection.start;
            WFTextCommandSelect(input, position, position);
            WFTextCommandAnchor = nil;
            break;
        }
        case WFTextCommandSelectRelative: {
            UITextPosition *start = [input positionFromPosition:selection.start offset:first] ?: input.beginningOfDocument;
            UITextPosition *end = [input positionFromPosition:start offset:second] ?: input.endOfDocument;
            WFTextCommandSelect(input, start, end);
            break;
        }
        case WFTextCommandLineStart:
            if (selection) WFTextCommandMoveToLineBoundary(input, selection.start, UITextStorageDirectionBackward);
            break;
        case WFTextCommandLineEnd:
            if (selection) WFTextCommandMoveToLineBoundary(input, selection.end, UITextStorageDirectionForward);
            break;
        case WFTextCommandDocumentStart:
            WFTextCommandSelect(input, input.beginningOfDocument, input.beginningOfDocument);
            break;
        case WFTextCommandDocumentEnd:
            WFTextCommandSelect(input, input.endOfDocument, input.endOfDocument);
            break;
    }
}

%ctor {
    @autoreleasepool {
        %init;
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([bundleID isEqualToString:WFTextCommandKeyboardBundleID]) {
            // Tells the keyboard a receiver is installed.
            setenv(WFTextCommandPresenceVariable, "1", 1);
            return;
        }
        notify_register_dispatch(WFTextCommandNotification, &WFTextCommandToken, dispatch_get_main_queue(), ^(int token) {
            uint64_t payload = 0;
            if (notify_get_state(token, &payload) == NOTIFY_STATUS_OK) {
                WFTextCommandHandle(payload);
            }
        });
    }
}
