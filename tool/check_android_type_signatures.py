#!/usr/bin/env python3
"""Check reflection metadata and source API fields in the published APK."""

import argparse
from pathlib import Path
import struct
import sys
import zipfile


REFERENCE = "Luy/kohesive/injekt/api/FullTypeReference;"
SIGNATURE = "Ldalvik/annotation/Signature;"
REFLECTED_FIELDS = {
    "Leu/kanade/tachiyomi/source/online/HttpSource;": {
        "headers$delegate", "id$delegate", "network$delegate",
    },
    "Lokhttp3/zstd/Zstd;": {"INSTANCE"},
}
REQUIRED_METHODS = {
    "Lcom/squareup/zstd/okio/OkioZstd;": {"zstdCompress", "zstdDecompress"},
}


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

    def reflected_fields(self):
        for index in range(self.u32(96)):
            offset = self.u32(100) + 32 * index
            name = self.types[self.u32(offset)]
            if name not in REFLECTED_FIELDS:
                continue
            position = self.u32(offset + 24)
            fields = set()
            if position:
                counts = []
                for _ in range(4):
                    count, position = self.uleb(position)
                    counts.append(count)
                for count in counts[:2]:
                    field_index = 0
                    for _ in range(count):
                        delta, position = self.uleb(position)
                        _, position = self.uleb(position)
                        field_index += delta
                        fields.add(self.strings[self.u32(self.u32(84) + 8 * field_index + 4)])
            yield name, fields

    def required_methods(self):
        for index in range(self.u32(96)):
            offset = self.u32(100) + 32 * index
            name = self.types[self.u32(offset)]
            if name not in REQUIRED_METHODS:
                continue
            position = self.u32(offset + 24)
            methods = set()
            if position:
                counts = []
                for _ in range(4):
                    count, position = self.uleb(position)
                    counts.append(count)
                for count in counts[:2]:
                    for _ in range(count):
                        _, position = self.uleb(position)
                        _, position = self.uleb(position)
                for count in counts[2:]:
                    method_index = 0
                    for _ in range(count):
                        delta, position = self.uleb(position)
                        _, position = self.uleb(position)
                        _, position = self.uleb(position)
                        method_index += delta
                        methods.add(self.strings[self.u32(self.u32(92) + 8 * method_index + 4)])
            yield name, methods


def verify(apk: Path) -> None:
    tokens = []
    fields = {}
    methods = {}
    default_package_classes = []
    with zipfile.ZipFile(apk) as archive:
        for name in archive.namelist():
            if name.startswith("classes") and name.endswith(".dex"):
                dex = Dex(archive.read(name))
                for index in range(dex.u32(96)):
                    name = dex.types[dex.u32(dex.u32(100) + 32 * index)]
                    if "/" not in name:
                        default_package_classes.append(name)
                tokens.extend(dex.tokens())
                fields.update(dex.reflected_fields())
                methods.update(dex.required_methods())
    if default_package_classes:
        raise ValueError("Host classes in the default package may collide with extensions: " + ", ".join(default_package_classes[:10]))
    if not tokens:
        raise ValueError("No Injekt type tokens found")
    missing = [name for name, preserved in tokens if not preserved]
    if missing:
        raise ValueError("Missing generic type information: " + ", ".join(missing))
    for name, required in REFLECTED_FIELDS.items():
        missing_fields = required - fields.get(name, set())
        if missing_fields:
            raise ValueError(f"Missing reflected source API fields in {name}: " + ", ".join(sorted(missing_fields)))
    for name, required in REQUIRED_METHODS.items():
        missing_methods = required - methods.get(name, set())
        if missing_methods:
            raise ValueError(f"Missing source API methods in {name}: " + ", ".join(sorted(missing_methods)))
    print(f"Verified {len(tokens)} Injekt type signatures in {apk.name}")
    print("Verified source compatibility fields and host class namespace")


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
