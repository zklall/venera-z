#!/usr/bin/env python3
"""Compare the shipped DEX with every class and member in the host source API."""
import struct
import sys
import zipfile
from pathlib import Path

import check_android_type_signatures as mod
if len(sys.argv) != 3:
    raise SystemExit('usage: check_mihon_api.py API_CLASSES.jar RELEASE.apk')
jar = Path(sys.argv[1])

def class_members(b):
    u1 = lambda p: b[p]
    u2 = lambda p: struct.unpack_from('>H', b, p)[0]
    u4 = lambda p: struct.unpack_from('>I', b, p)[0]
    n = u2(8)
    p = 10
    cp = [None] * n
    i = 1
    while i < n:
        tag = u1(p)
        p += 1
        if tag == 1:
            k = u2(p)
            p += 2
            cp[i] = b[p:p + k].decode('utf-8', 'replace')
            p += k
        elif tag in (3, 4):
            p += 4
        elif tag in (5, 6):
            p += 8
            i += 1
        elif tag in (7, 8, 16, 19, 20):
            p += 2
        elif tag in (9, 10, 11, 12, 17, 18):
            p += 4
        elif tag == 15:
            p += 3
        else:
            raise ValueError(f'constant pool tag {tag}')
        i += 1
    p += 6
    p += 2 + 2 * u2(p)
    groups = []
    for _ in range(2):
        count = u2(p)
        p += 2
        found = set()
        for _ in range(count):
            name = cp[u2(p + 2)]
            desc = cp[u2(p + 4)]
            attrs = u2(p + 6)
            p += 8
            if name != '<clinit>':
                found.add((name, desc))
            for _ in range(attrs):
                length = u4(p + 2)
                p += 6 + length
        groups.append(found)
    return groups
expected = {}
with zipfile.ZipFile(jar) as z:
    for n in z.namelist():
        if n.endswith('.class') and n.startswith(('eu/kanade/tachiyomi/', 'mihon/core/common/', 'tachiyomi/core/common/', 'tachiyomi/decoder/')):
            expected['L' + n[:-6] + ';'] = class_members(z.read(n))
if not expected:
    raise SystemExit('No host source API classes found in the provided JAR')
found = {}
with zipfile.ZipFile(sys.argv[2]) as z:
    for n in z.namelist():
        if not (n.startswith('classes') and n.endswith('.dex')):
            continue
        d = mod.Dex(z.read(n))
        b = d.data
        for i in range(d.u32(96)):
            off = d.u32(100) + 32 * i
            name = d.types[d.u32(off)]
            if name not in expected:
                continue
            p = d.u32(off + 24)
            groups = [set(), set()]
            if p:
                counts = []
                for _ in range(4):
                    v, p = d.uleb(p)
                    counts.append(v)
                for group, count in enumerate(counts):
                    idx = 0
                    for _ in range(count):
                        delta, p = d.uleb(p)
                        _, p = d.uleb(p)
                        idx += delta
                        if group < 2:
                            f = d.u32(84) + idx * 8
                            typeidx = struct.unpack_from('<H', b, f + 2)[0]
                            groups[0].add((d.strings[d.u32(f + 4)], d.types[typeidx]))
                        else:
                            method = d.u32(92) + idx * 8
                            proto = struct.unpack_from('<H', b, method + 2)[0]
                            item = d.u32(76) + proto * 12
                            params = d.u32(item + 8)
                            parts = []
                            if params:
                                for j in range(d.u32(params)):
                                    parts.append(d.types[struct.unpack_from('<H', b, params + 4 + 2 * j)[0]])
                            desc = '(' + ''.join(parts) + ')' + d.types[d.u32(item + 4)]
                            methodname = d.strings[d.u32(method + 4)]
                            if methodname != '<clinit>':
                                groups[1].add((methodname, desc))
                            _, p = d.uleb(p)
            found[name] = groups
missing = []
for name, groups in expected.items():
    if name not in found:
        missing.append((name, 'class'))
        continue
    for label, e, a in zip(('field', 'method'), groups, found[name]):
        for x in sorted(e - a):
            missing.append((name, label, *x))
print(f'Compared {len(expected)} classes: {len(missing)} missing members/classes')
for entry in missing[:100]:
    print(*entry)
sys.exit(bool(missing))
