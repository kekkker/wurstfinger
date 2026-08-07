# Wurst Vinted Bridge

A rootless LaunchDaemon that lets the Wurstfinger keyboard run inside the
Vinted app. Vinted refuses third-party keyboards; this daemon flips that
decision in the running Vinted process without modifying the Vinted bundle,
injecting a dylib, or touching any other app.

This is the lighter of the two approaches in this repo. The heavier one,
[`tools/vinted-trollstore`](../../tools/vinted-trollstore/README.md), repackages
a decrypted Vinted with an embedded dylib and is what you want if you also need
to defeat Incognia/FaceTec tamper checks. The bridge only addresses the keyboard
gate.

## How it works

When an app first focuses a text field, UIKit calls
`-[UIKeyboardInputModeController verifyKeyboardExtensionsWithApp]` to decide
whether third-party keyboard extensions are allowed for that app. For Vinted it
returns `NO`, so iOS falls back to the system keyboard.

`Bridge.c` runs as a background root daemon that:

1. Polls the process list (one `proc_listpids` every 20 ms) for a new
   `/Vinted.app/Vinted` process. PIDs are monotonic during a userspace boot, so
   it only scans PIDs above the highest one already seen — cheap enough to catch
   Vinted before UIKit first asks the gate.
2. Opens the target with `task_for_pid`, reads the dyld shared-cache slide from
   `TASK_DYLD_INFO`, and computes the runtime address of the gate function.
3. Verifies the first 8 bytes match the expected prologue
   (`pacibsp; stp x20, x19, [sp, #-0x20]!`), then overwrites them with
   `mov w0, #1; ret` so the function returns `YES`.
4. Reprotects the page, flushes the instruction cache, and reads the bytes back
   to confirm the patch landed. Already-patched processes are detected and
   skipped.

The daemon refuses to write if the bytes at the target don't match the expected
prologue, so an OS update that moves or changes the function is a no-op rather
than a crash. All activity is logged to
`/var/mobile/Library/Logs/WurstVintedBridge.log`.

## Version pinning

The gate address is hardcoded and valid **only** for the exact build it was
derived from:

- iOS 16.3 (20D47)
- UIKitCore 6304.1.100.0.0
- `verifyKeyboardExtensionsWithApp` at unslid `0x1893cd480`

On any other iOS/UIKit build this address is wrong. Re-derive it in a
disassembler (find the selector `verifyKeyboardExtensionsWithApp`, take its
unslid implementation address) and update `kVerifyKeyboardExtensionsAddress` and
`kExpectedCode` in `Bridge.c`.

## Files

| File | Role |
| --- | --- |
| `Bridge.c` | The shipping daemon (only file built by the Makefile). |
| `WurstVintedBridge.plist` | LaunchDaemon definition — `RunAtLoad`, `KeepAlive`, background priority. |
| `Entitlements.plist` | `task_for_pid`-allow + platform entitlements the daemon needs to read/write another process. |
| `control` | Package metadata. |
| `layout/DEBIAN/{postinst,prerm}` | Bootstrap/bootout the daemon on install/remove. |
| `DumpMain.c` | Research tool, not built. Reads a target's FairPlay-encrypted page (`0xc000`, size `0x1000`) over a task port — this is the dumper referenced by the `vinted-trollstore` rebuild flow. |
| `TaskPortProbe.c` | Research spike, not built. Explores asking launchd (via XPC) to permit writes to foreign/invalid code pages; kept as a reference for the memory-patching approach. |

## Build

Requires the `wurstfinger-theos:latest` Docker image (see
`tweaks/wurstsecure-probe` for how that image is produced) and a `THEOS`
environment pointing at it.

```sh
make package
```

The rootless `.deb` is written to `packages/`. `.theos/` and `packages/` are
build output and are gitignored.

## Install

ElleKit + a rootless jailbreak (Dopamine) required.

```sh
scp packages/de.akator.wurstvintedbridge_0.1.0_iphoneos-arm64.deb mobile@PHONE_IP:/tmp/
ssh mobile@PHONE_IP 'sudo dpkg -i /tmp/de.akator.wurstvintedbridge_0.1.0_iphoneos-arm64.deb'
```

`postinst` bootstraps the daemon immediately; no respring needed. Launch Vinted,
tap a text field, and Wurstfinger should be selectable.

## Remove

```sh
ssh mobile@PHONE_IP 'sudo dpkg -r de.akator.wurstvintedbridge'
```

`prerm` boots the daemon out first. The patch is applied to Vinted's running
memory only, so it disappears the next time Vinted is relaunched without the
daemon.

## Scope

This daemon reads and writes another process's memory with `task_for_pid` and is
security-sensitive by nature. It only ever patches processes whose executable
path ends in `/Vinted.app/Vinted`, only writes when the bytes match the pinned
prologue, and enables the Wurstfinger keyboard gate — nothing else. Treat any
change to the target selection or the patched bytes as security-relevant.
