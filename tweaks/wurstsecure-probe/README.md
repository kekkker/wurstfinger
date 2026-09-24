# WurstSecure

WurstSecure is a rootless Dopamine tweak for iOS 16.3 that forces the
Wurstfinger keyboard extension (`de.akator.wurstfinger.keyboard`) for every
text responder across UIKit apps, including secure and custom login fields.
For ordinary prose fields it also enables UIKit's native spell checking so host
apps can underline misspellings. Secure, email, URL, username, telephone,
one-time-code, credit-card, and numeric inputs remain excluded.

## What it does

### Forces Wurstfinger on focus

Hooks UIKit's responder-to-input-mode resolution
(`textInputModeForResponder:`) and the final input-mode switch validators
(`shouldSwitchInputMode:`, `shouldSwitchFromInputManagerMode:toInputMode:`),
plus `setKeyboardInputMode:userInitiated:`, so any attempt to select another
keyboard is redirected back to Wurstfinger. After each switch it validates
100 ms later that Wurstfinger actually became current and retries once if the
system reverted it. The resolved Wurstfinger input mode is cached on first
discovery to avoid re-scanning the mode list on every focus.

### Removes the bottom keyboard strip

By default iOS reserves a band of space below a third-party keyboard for the
home indicator. Wurstfinger renders shorter than the region iOS gives it, so
that band shows through as a gray strip a third-party keyboard cannot recolour.
WurstSecure zeroes the bottom `safeAreaInsets`,
`_viewSafeAreaInsetsFromScene`, and `deviceSpecificPadding…` so no band is
reserved, and hides `UIKeyboardDockView` (the globe/dictation dock iOS overlays
in that band). The visible gap above the home indicator is supplied *inside*
Wurstfinger instead — see the keyboard-side notes below — so it takes the
keyboard's own black background rather than the system gray.

### Bridges Messages one-time codes

When iOS produces a Messages one-time-code candidate, WurstSecure forwards the
numeric code to the active Wurstfinger extension without changing input modes.
Wurstfinger temporarily shows it in the same 32-point strip used for spelling
status and suggestions. Tapping the item inserts it through the keyboard's own
text-document proxy; codes expire after five minutes. See `OTPCandidateOverlay.xm`
(host side, captures the candidate) and `OTPKeyboardBridge.xm` (extension side,
renders and inserts it).

### Runs text commands for the keyboard

Keyboard extensions cannot select text, select all, undo or redo through
`UITextDocumentProxy`. Wurstfinger posts these as a Darwin notification
(`de.akator.wurstfinger.text-command.v1`) whose 64-bit state carries the
command, and WurstSecure runs it on the first responder of the app in front:
select all, undo, redo, slide-to-select from an anchor, select the current
line, and jumps to line and document boundaries. In the keyboard's own process
it sets `WURSTSECURE_TEXT_BRIDGE=1` so Wurstfinger knows a receiver exists and
falls back to context-based behavior otherwise.

Password fields keep their original `secureTextEntry` value, so masking remains
enabled. SpringBoard, passcode, lock-screen, pre-boot, CoreAuth, and Setup
Assistant processes are explicitly excluded.

## Source layout

| File | Role |
| --- | --- |
| `Tweak.xm` | Keyboard forcing, spell-check enablement, bottom-strip removal, dock hiding. |
| `OTPCandidateOverlay.xm` | Host-side: intercepts the Messages OTP candidate and publishes the code to the extension. |
| `OTPKeyboardBridge.xm` | Extension-side: receives the code, shows it in the suggestion strip, inserts on tap. |
| `TextCommandBridge.xm` | Host-side: runs the keyboard's select-all, undo/redo and selection commands on the focused input. |
| `WurstSecure.plist` | MobileSubstrate filter — loads into UIKit apps and the Wurstfinger extension. |

## Keyboard-side companion changes

Two behaviours live in the Wurstfinger extension itself
(`wurstfingerKeyboard/KeyboardViewController.swift`), not in this tweak, because
they cannot be reached from the host process:

- The extension's root view background is `.black` (not `.clear`) so the region
  iOS hands the extension is never transparent to the system's gray backdrop.
- A `bottomContentGap` constant (currently 20 pt) reserves breathing room below
  the keys *inside* the extension's own black view. The height constraint grows
  by the gap so the keys are not squeezed, and the content is pinned that far
  off the bottom edge. This is what gives the keyboard a gap above the home
  indicator without reintroducing the gray strip.

## Build with Docker

```sh
./build.sh
```

The first build downloads Theos, its Linux iOS toolchain, an SDK, and the
`allemande` arm64e ABI converter into the Docker image. Nothing is installed
directly on the host. The rootless package is written to `packages/`.

## Install

ElleKit must be installed on the Dopamine device. Then copy and install the
package:

```sh
scp packages/de.akator.wurstsecureprobe_1.7.0_iphoneos-arm64.deb mobile@PHONE_IP:/tmp/
ssh mobile@PHONE_IP
sudo dpkg -i /tmp/de.akator.wurstsecureprobe_1.7.0_iphoneos-arm64.deb
sudo sbreload
```

## Remove

```sh
ssh mobile@PHONE_IP 'sudo dpkg -r de.akator.wurstsecureprobe && sudo sbreload'
```

Removing WurstSecure does not remove ElleKit because other jailbreak tweaks
may depend on it.

## Security scope

WurstSecure intentionally overrides iOS's keyboard selection for every text
responder, including fields where third-party keyboards are normally blocked.
Only Wurstfinger is selected by the tweak; other keyboard extensions are not
enabled by it. Because Wurstfinger is forced on focus, manually selecting a
different keyboard may not persist between fields. Treat the Wurstfinger build
and any future changes to it as security-sensitive code.
