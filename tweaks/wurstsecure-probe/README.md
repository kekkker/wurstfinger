# WurstSecure

WurstSecure is a rootless Dopamine tweak for iOS 16.3 that forces the
Wurstfinger keyboard extension (`de.akator.wurstfinger.keyboard`) for every
text responder across UIKit apps, including secure and custom login fields.
It also removes UIKit's device-specific bottom keyboard padding for Wurstfinger
so the keyboard sits against the bottom edge instead of floating above an empty
home-indicator dock.

It hooks UIKit's responder-to-input-mode resolution and final input-mode
switch validators. Password fields keep their original `secureTextEntry`
value, so masking remains enabled. SpringBoard, passcode, lock-screen,
pre-boot, CoreAuth, and Setup Assistant processes are explicitly excluded.

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
scp packages/de.akator.wurstsecureprobe_1.2.2_iphoneos-arm64.deb mobile@PHONE_IP:/tmp/
ssh mobile@PHONE_IP
sudo dpkg -i /tmp/de.akator.wurstsecureprobe_1.2.2_iphoneos-arm64.deb
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
