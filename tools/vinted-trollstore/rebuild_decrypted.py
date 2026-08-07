#!/usr/bin/env python3
"""Rebuild a thin arm64 Mach-O from its FairPlay-decrypted memory range."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


MH_MAGIC_64 = 0xFEEDFACF
LC_ENCRYPTION_INFO_64 = 0x2C
MACH_HEADER_64_SIZE = 32


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("original", type=Path)
    parser.add_argument("decrypted_range", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    binary = bytearray(args.original.read_bytes())
    if len(binary) < MACH_HEADER_64_SIZE:
        raise SystemExit("input is smaller than a Mach-O header")

    magic, _, _, _, command_count, command_bytes, _, _ = struct.unpack_from(
        "<IIIIIIII", binary, 0
    )
    if magic != MH_MAGIC_64:
        raise SystemExit(f"unsupported Mach-O magic: 0x{magic:08x}")

    command_offset = MACH_HEADER_64_SIZE
    command_end = command_offset + command_bytes
    encryption_command_offset: int | None = None
    crypt_offset = crypt_size = crypt_id = 0

    for _ in range(command_count):
        if command_offset + 8 > command_end:
            raise SystemExit("truncated Mach-O load commands")
        command, command_size = struct.unpack_from("<II", binary, command_offset)
        if command_size < 8 or command_offset + command_size > command_end:
            raise SystemExit("invalid Mach-O load command size")
        if command == LC_ENCRYPTION_INFO_64:
            if command_size < 24:
                raise SystemExit("truncated LC_ENCRYPTION_INFO_64")
            encryption_command_offset = command_offset
            crypt_offset, crypt_size, crypt_id = struct.unpack_from(
                "<III", binary, command_offset + 8
            )
            break
        command_offset += command_size

    if encryption_command_offset is None:
        raise SystemExit("LC_ENCRYPTION_INFO_64 was not found")
    if crypt_id != 1:
        raise SystemExit(f"expected cryptid 1, found {crypt_id}")

    decrypted = args.decrypted_range.read_bytes()
    if len(decrypted) != crypt_size:
        raise SystemExit(
            f"decrypted range is {len(decrypted)} bytes; expected {crypt_size}"
        )
    if crypt_offset + crypt_size > len(binary):
        raise SystemExit("encrypted range extends past end of input")

    binary[crypt_offset : crypt_offset + crypt_size] = decrypted
    struct.pack_into("<I", binary, encryption_command_offset + 16, 0)
    args.output.write_bytes(binary)

    print(
        f"rebuilt {args.output}: replaced 0x{crypt_size:x} bytes at "
        f"0x{crypt_offset:x} and set cryptid to 0"
    )


if __name__ == "__main__":
    main()
