#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
image_name="wurstfinger-theos:latest"

docker build --tag "$image_name" "$script_dir"
docker run --rm \
    --volume "$script_dir:/work" \
    --workdir /work \
    "$image_name"

printf 'Package written to %s/packages/\n' "$script_dir"
