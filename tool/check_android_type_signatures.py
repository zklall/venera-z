#!/usr/bin/env python3
"""Check Injekt's reflection metadata in the APK that will be published."""

import argparse
from pathlib import Path
import struct
import sys
import zipfile


REFERENCE = "Luy/kohesive/injekt/api/FullTypeReference;"
SIGNATURE = "Ldalvik/annotation/Signature;"


class Dex:
    def __init__(self, data: bytes):
        self.data = data
        if not data.startswith(b"dex\n"):
            raise ValueError("Unsupported DEX file")
        self.strings = []
        for index in range(self.u32(56)):
            offset = self.u32(self.u32(60) + 4 * index)
            _, offset = self.uleb(offset)
            end = data.index(0, offset)
            self.strings.append(data[offset:end].decode("utf-8", "replace"))
        self.types = [
            self.strings[self.u32(self.u32(68) + 4 * index)]
            for index in range(self.u32(64))
        ]

    def u32(self, offset: int) -> int:
        return struct.unpack_from("<I", self.data, offset)[0]

    def uleb(self, offset: int) -> tuple[int, int]:
        value = 0
        for shift in range(0, 35, 7):
            byte = self.data[offset]
            offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value, offset
        raise ValueError("Invalid DEX integer")

    def signature(self, directory: int) -> str:
        annotation_set = self.u32(directory) if directory else 0
        if not annotation_set:
            return ""
        for index in range(self.u32(annotation_set)):
            offset = self.u32(annotation_set + 4 + 4 * index) + 1
            annotation_type, offset = self.uleb(offset)
            if self.types[annotation_type] != SIGNATURE:
                continue
            count, offset = self.uleb(offset)
            if count != 1:
                raise ValueError("Invalid signature annotation")
            name, offset = self.uleb(offset)
            if self.strings[name] != "value" or self.data[offset] != 0x1C:
                raise ValueError("Invalid signature value")
            count, offset = self.uleb(offset + 1)
            chunks = []
            for _ in range(count):
                tag = self.data[offset]
                offset += 1
                if tag & 31 != 0x17:
                    raise ValueError("Invalid signature string")
                length = (tag >> 5) + 1
                reference = int.from_bytes(self.data[offset:offset + length], "little")
                offset += length
                chunks.append(self.strings[reference])
            return "".join(chunks)
        return ""

    def tokens(self):
        for index in range(self.u32(96)):
            offset = self.u32(100) + 32 * index
            superclass = self.u32(offset + 8)
            if superclass == 0xFFFFFFFF or self.types[superclass] != REFERENCE:
                continue
            name = self.types[self.u32(offset)]
            signature = self.signature(self.u32(offset + 20))
            yield name, REFERENCE[:-1] + "<" in signature


def verify(apk: Path) -> None:
    tokens = []
    with zipfile.ZipFile(apk) as archive:
        for name in archive.namelist():
            if name.startswith("classes") and name.endswith(".dex"):
                tokens.extend(Dex(archive.read(name)).tokens())
    if not tokens:
        raise ValueError("No Injekt type tokens found")
    missing = [name for name, preserved in tokens if not preserved]
    if missing:
        raise ValueError("Missing generic type information: " + ", ".join(missing))
    print(f"Verified {len(tokens)} Injekt type signatures in {apk.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apks", type=Path, nargs="+")
    args = parser.parse_args()
    for apk in args.apks:
        try:
            verify(apk)
        except (ValueError, IndexError, struct.error, zipfile.BadZipFile, OSError) as error:
            print(f"{apk.name}: {error}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
