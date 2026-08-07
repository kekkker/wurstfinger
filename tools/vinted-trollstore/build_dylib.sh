#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output_dir="${1:-/out}"

compiler=/opt/theos/toolchain/linux/iphone/bin/clang
signer=/opt/theos/toolchain/linux/iphone/bin/ldid
sdk=/opt/theos/sdks/iPhoneOS16.5.sdk

mkdir -p "$output_dir"
"$compiler" \
    -target arm64-apple-ios15.0 \
    -isysroot "$sdk" \
    -fobjc-arc \
    -fblocks \
    -O2 \
    -Wall \
    -Wextra \
    -dynamiclib \
    -install_name @executable_path/Frameworks/WurstVinted.dylib \
    -framework Foundation \
    -framework UIKit \
    "$script_dir/WurstVinted.m" \
    -o "$output_dir/WurstVinted.dylib"
"$signer" -S "$output_dir/WurstVinted.dylib"

printf 'Built %s/WurstVinted.dylib\n' "$output_dir"
