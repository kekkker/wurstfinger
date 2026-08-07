# Vinted TrollStore patch

> Persistent recovery note: this document records the working July 2026 setup.
> Do not commit Vinted binaries, decrypted pages, generated IPAs, device
> credentials, or signing material. The offsets below are valid only for the
> exact versions and hashes stated here.

This tooling targets exactly:

- Vinted `26.27.0` (`CFBundleVersion` `30239`)
- bundle identifier `lt.manodrabuziai.fr`
- FaceTecSDK `9.7.92`
- iOS 16.3 on arm64

It produces an app-local compatibility build with three pieces:

1. `rebuild_decrypted.py` replaces the main executable's FairPlay-encrypted
   range with bytes dumped from the running process and sets `cryptid` to 0.
2. `patch_facetec.py` redirects FaceTec's 79 startup constructors to a verified
   `ret` stub. This avoids its launch-time TrollStore/tamper traps without
   overwriting the constructor functions themselves.
3. `WurstVinted.m` is embedded as `Frameworks/WurstVinted.dylib`. It masks the
   Incognia jailbreak URL/file probes inside Vinted and allows/selects the
   Wurstfinger keyboard through UIKit's extension and input-traits gates.

`build_dylib.sh` builds the compatibility dylib inside the existing
`wurstfinger-theos:latest` Docker image. The resulting dylib is loaded by adding
this command to the decrypted Vinted executable:

```text
LC_LOAD_DYLIB @executable_path/Frameworks/WurstVinted.dylib 1.0.0 1.0.0
```

The proprietary Vinted bundle, decrypted bytes, and generated IPAs must not be
committed. The patch scripts validate exact source hashes/bytes and refuse an
unknown Vinted or FaceTec build.

## What finally worked

The successful design was deliberately app-local. Dopamine remains visible and
Wurstfinger is not injected into Vinted by ElleKit. Instead, the decrypted
Vinted executable loads `Frameworks/WurstVinted.dylib` itself. TrollStore then
installs the modified bundle while preserving Vinted's existing data container.

The complete chain was:

1. Copy the installed Vinted app bundle to the Linux workstation.
2. Launch Vinted on the phone and dump its one decrypted FairPlay page from the
   live process using a root task-port dumper.
3. Rebuild the main executable with `rebuild_decrypted.py`.
4. Build `WurstVinted.dylib` in Docker with `build_dylib.sh` and place it in the
   app's `Frameworks` directory.
5. Add this load command to the main executable:

   ```text
   LC_LOAD_DYLIB @executable_path/Frameworks/WurstVinted.dylib 1.0.0 1.0.0
   ```

6. Patch the exact FaceTec binary with `patch_facetec.py`.
7. Sign the modified Mach-O files, package the `Payload` directory as an IPA,
   and install it with TrollStore's root helper using `install force`.

The result was confirmed working on an iPhone 14 Pro Max running iOS 16.3
(`20D47`) and Dopamine 2.4.9: native Vinted launches with `/var/jb` visible and
Wurstfinger appears in Vinted fields without vnodebypass or a global jailbreak
hide.

## FairPlay detail

Vinted's main executable had only one encrypted range:

```text
file offset: 0x0000c000
size:        0x00001000
cryptid:     1 before rebuilding, 0 afterward
```

`rebuild_decrypted.py` intentionally does not perform process dumping. It takes
the original executable plus the exactly `0x1000`-byte page dumped from the same
executable mapped in a live Vinted process. It replaces the range and changes
`LC_ENCRYPTION_INFO_64.cryptid` from `1` to `0`. A page from another build must
not be reused.

## App-local keyboard bridge

`WurstVinted.m` applies Objective-C method replacements inside Vinted only. The
important UIKit gates are:

```text
UIKeyboardInputModeController
  verifyKeyboardExtensionsWithApp              -> YES
  textInputModeForResponder:                    -> select Wurstfinger

UIKeyboardExtensionInputMode
  isDesiredForTraits:                           -> YES
  isAllowedForTraits:                           -> YES

UIKeyboardImpl
  setKeyboardInputMode:userInitiated:           -> retain Wurstfinger choice
```

The target keyboard extension identifier is:

```text
de.akator.wurstfinger.keyboard
```

The dylib also masks the Incognia checks observed in this Vinted build through
the app's `NSFileManager` and `UIApplication canOpenURL:` paths. It does not
hide the jailbreak globally.

The broad dyld/C-function interposition experiment is intentionally disabled:

```c
#define WF_ENABLE_DYLD_INTERPOSE 0
```

Enabling it caused allocator recursion during process startup and made Vinted
crash. Keep it disabled unless the wrappers are redesigned to avoid Foundation,
Objective-C allocation, and recursive calls from every interposed primitive.

## FaceTec anti-tamper finding

FaceTecSDK 9.7.92 contains 79 entries in `__DATA.__mod_init_func`. Modifying the
TrollStore-installed bundle caused deliberate startup failures before Vinted
could finish launching. Two useful signatures were:

```text
bad dereference: FaceTec file offset 0x191384
initializer:     FaceTec file offset 0x1912e4

BRK:             FaceTec file offset 0x1ac428
initializer:     FaceTec file offset 0x1aaba0
```

Later failures destroyed useful state, ending with a wiped stack and `PC=0x28`.
Patching one constructor at a time only exposed the next trap.

The stable patch therefore uses one verified location as a harmless return
stub and redirects the constructor table to it:

```text
FaceTec input SHA-256:
687e5f7c1a8d05a10399f5dbb4107c4b7fbd298692df6a9aaeb651f8ebc0a8ce

__DATA.__mod_init_func file offset: 0x6284d0
__DATA.__mod_init_func size:        0x278
initializer count:                  79
return-stub file offset:            0x1912e4
replacement instruction:           c0 03 5f d6    (arm64 `ret`)
```

`patch_facetec.py` refuses to operate unless the complete input hash, section
offset and size, initializer count, known initializer pointers, and original
stub bytes all match. It patches the stub and rewrites all 79 table pointers;
the constructor function bodies otherwise remain intact.

## Rebuild skeleton

The inputs and output names below are illustrative. Keep all proprietary inputs
and generated artifacts outside Git.

```bash
# Build the app-local dylib without installing an iOS toolchain on the host.
docker run --rm \
  -v "$PWD/tools/vinted-trollstore:/src:ro" \
  -v "$PWD/.local-vinted-build:/out" \
  wurstfinger-theos:latest \
  /src/build_dylib.sh /out

# Replace the live-decrypted page and clear cryptid.
python3 tools/vinted-trollstore/rebuild_decrypted.py \
  /private/work/Vinted.original \
  /private/work/Vinted.page-0xc000-0x1000.bin \
  /private/work/Vinted.decrypted

# Disable the exact known FaceTec startup initializer table.
python3 tools/vinted-trollstore/patch_facetec.py \
  /private/work/FaceTecSDK.original \
  /private/work/FaceTecSDK.patched
```

After rebuilding, verify at minimum:

- the Vinted main executable reports `cryptid 0`;
- its new load command resolves to the embedded dylib;
- the embedded dylib is arm64 and signed;
- FaceTec's SHA-256 matched before patching and all 79 constructor pointers now
  target `0x1912e4`;
- the IPA contains `Payload/Vinted.app`, not an extra directory level;
- Vinted remains alive for several minutes with `/var/jb` visible;
- Wurstfinger works in both ordinary and authentication-related text fields.

## Failed approaches worth remembering

- Choicy/no-tweak launch made Vinted run, but removed the systemwide keyboard
  compatibility hooks, so only the stock keyboard appeared.
- vnodebypass could make Vinted run, but was global, fragile, and not acceptable
  as the permanent setup.
- Hiding only common jailbreak paths was insufficient because FaceTec also
  validated the modified app at startup.
- Broad C/dyld interposition inside the embedded dylib caused recursive startup
  crashes. The narrow Objective-C hooks are the known-good configuration.
- Disabling only the first crashing FaceTec constructor was insufficient; there
  were 79 startup entries and additional deliberate traps.

## Post-login crash and fix

After the first successful login, Vinted began initializing Unity Ads storage
and crashed repeatedly with `SIGABRT`. The useful exception frames were:

```text
-[NSFileManager fileSystemRepresentationWithPath:]
WFFileExists + 60
-[USRVStorage storageFileExists]
-[USRVStorageManager setupStorage:]
```

The cause was the first app-local file-manager hook calling
`path.fileSystemRepresentation` before deciding whether the path was a
jailbreak artifact. That conversion can raise for values encountered in the
post-login SDK initialization path.

The fixed bridge never converts Objective-C paths to C paths. It checks that
the argument is an `NSString`, performs the case-insensitive match directly on
the string, and otherwise passes the argument unchanged to the original
`NSFileManager` implementation. `WFStringContainsAny` and the URL check also
have defensive class guards. The C-string helper remains only for the disabled
C interposition implementation.

The fixed dylib was validated by launching the already-authenticated app with
the existing data container. The process remained alive and no newer Vinted
crash report was created. During the live repair, the original dylib was backed
up on the test phone at:

```text
/var/mobile/Media/WurstVinted-pre-postlogin-fix.dylib
```

## Device rollback

The known-good decrypted rollback IPA is staged on the test phone at:

```text
/var/mobile/Media/Vinted-26.27.0-TrollStore-rollback.ipa
```

Install it with TrollStore's root helper using `install force`. This replaces
only the app bundle; Vinted's existing data container remains in place.

The patched IPA was staged at:

```text
/var/mobile/Media/Vinted-26.27.0-WurstPatched.ipa
```

At the time of the successful test, TrollStore preserved these containers:

```text
bundle:
/var/containers/Bundle/Application/39A73F4C-09AF-4ABA-9D49-817E6FCDED23/Vinted.app

data:
/var/mobile/Containers/Data/Application/406AB005-9F73-4615-B225-68AE4165E453
```

Container UUIDs can change after reinstalling, so discover them again rather
than hard-coding them in automation.

## Known limitation

Vinted's two notification extensions remain FairPlay-encrypted. TrollStore
therefore returns nonfatal status `184`; the main app still installs and runs,
but rich notification handling may not work. FaceTec identity-verification
flows may also be unavailable because its startup constructors are disabled.

The encrypted extensions observed in this build were:

```text
NotificationServiceExtension
NotificationContentExtension
```

An App Store update will replace the patched bundle. Keep Vinted automatic
updates disabled until the newer build has been separately decrypted, audited,
and patched; never assume these offsets survive an update.
