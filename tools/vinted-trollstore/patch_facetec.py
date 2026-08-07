#!/usr/bin/env python3
"""Disable FaceTec 9.7.92's startup anti-tamper initializer in Vinted 26.27.0."""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path


EXPECTED_SHA256 = "687e5f7c1a8d05a10399f5dbb4107c4b7fbd298692df6a9aaeb651f8ebc0a8ce"
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
MACH_HEADER_64_SIZE = 32
SECTION_64_SIZE = 80
RETURN_STUB_OFFSET = 0x1912E4
EXPECTED_RETURN_STUB_CODE = bytes.fromhex("fc6fbaa9")
RETURN_CODE = bytes.fromhex("c0035fd6")
EXPECTED_INITIALIZER_OFFSET = 0x6284D0
EXPECTED_INITIALIZER_SIZE = 0x278


def find_initializer_section(binary: bytes) -> tuple[int, int]:
    magic, _, _, _, command_count, command_bytes, _, _ = struct.unpack_from(
        "<IIIIIIII", binary, 0
    )
    if magic != MH_MAGIC_64:
        raise SystemExit(f"unsupported Mach-O magic: 0x{magic:08x}")

    command_offset = MACH_HEADER_64_SIZE
    command_end = command_offset + command_bytes
    for _ in range(command_count):
        command, command_size = struct.unpack_from("<II", binary, command_offset)
        if command_size < 8 or command_offset + command_size > command_end:
            raise SystemExit("invalid Mach-O load command")
        if command == LC_SEGMENT_64:
            section_count = struct.unpack_from("<I", binary, command_offset + 64)[0]
            section_offset = command_offset + 72
            for section_index in range(section_count):
                current = section_offset + section_index * SECTION_64_SIZE
                section_name = binary[current : current + 16].split(b"\0", 1)[0]
                segment_name = binary[current + 16 : current + 32].split(b"\0", 1)[0]
                if section_name == b"__mod_init_func" and segment_name == b"__DATA":
                    size = struct.unpack_from("<Q", binary, current + 40)[0]
                    offset = struct.unpack_from("<I", binary, current + 48)[0]
                    return offset, size
        command_offset += command_size
    raise SystemExit("FaceTec __DATA.__mod_init_func section was not found")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    binary = bytearray(args.input.read_bytes())
    digest = hashlib.sha256(binary).hexdigest()
    if digest != EXPECTED_SHA256:
        raise SystemExit(
            f"refusing unknown FaceTecSDK: sha256 {digest}, expected {EXPECTED_SHA256}"
        )

    initializer_offset, initializer_size = find_initializer_section(binary)
    if (initializer_offset, initializer_size) != (
        EXPECTED_INITIALIZER_OFFSET,
        EXPECTED_INITIALIZER_SIZE,
    ):
        raise SystemExit(
            "unexpected initializer section: "
            f"offset=0x{initializer_offset:x}, size=0x{initializer_size:x}"
        )
    if initializer_size % 8 != 0:
        raise SystemExit("initializer section is not pointer-aligned")

    initializer_count = initializer_size // 8
    initializers = struct.unpack_from(
        f"<{initializer_count}Q", binary, initializer_offset
    )
    if initializer_count != 79 or RETURN_STUB_OFFSET not in initializers or 0x1AABA0 not in initializers:
        raise SystemExit("unexpected FaceTec initializer table")

    current_stub = bytes(
        binary[RETURN_STUB_OFFSET : RETURN_STUB_OFFSET + len(EXPECTED_RETURN_STUB_CODE)]
    )
    if current_stub != EXPECTED_RETURN_STUB_CODE:
        raise SystemExit(
            f"unexpected return-stub bytes at 0x{RETURN_STUB_OFFSET:x}: "
            f"{current_stub.hex()}"
        )

    binary[RETURN_STUB_OFFSET : RETURN_STUB_OFFSET + len(RETURN_CODE)] = RETURN_CODE
    for index in range(initializer_count):
        struct.pack_into(
            "<Q", binary, initializer_offset + index * 8, RETURN_STUB_OFFSET
        )

    args.output.write_bytes(binary)
    print(
        f"redirected {initializer_count} FaceTec startup initializers to "
        f"return stub 0x{RETURN_STUB_OFFSET:x}"
    )


if __name__ == "__main__":
    main()
