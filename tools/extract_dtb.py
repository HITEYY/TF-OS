#!/usr/bin/env python3
"""백업 이미지(resource/boot/... .img)에서 FDT 블롭을 찾아 vendor-dt/ 에 .dtb/.dts 로 저장.

Rockchip resource.img(RSCE)든 Android boot.img든 FDT magic 으로 스캔하므로 포맷 무관.
사용: python3 tools/extract_dtb.py backup/resource.img backup/boot.img ...
"""
import shutil
import struct
import subprocess
import sys
from pathlib import Path

MAGIC = b"\xd0\x0d\xfe\xed"
OUT = Path(__file__).resolve().parent.parent / "vendor-dt"


def blobs(data):
    i = data.find(MAGIC)
    while i != -1:
        size, = struct.unpack_from(">I", data, i + 4)
        version, = struct.unpack_from(">I", data, i + 20)
        # 헤더 sanity: 크기 범위, 버전 16/17
        if 0x40 <= size <= 4 << 20 and version in (16, 17) and i + size <= len(data):
            yield i, data[i:i + size]
            i = data.find(MAGIC, i + size)
        else:
            i = data.find(MAGIC, i + 1)


def main(paths):
    if not paths:
        sys.exit(__doc__)
    OUT.mkdir(exist_ok=True)
    dtc = shutil.which("dtc")
    if not dtc:
        print("dtc 없음 -> .dtb 만 저장 (macOS: brew install dtc / Linux: apt install device-tree-compiler)")
    for p in map(Path, paths):
        found = 0
        for off, blob in blobs(p.read_bytes()):
            dtb = OUT / f"{p.stem}-{off:#x}.dtb"
            dtb.write_bytes(blob)
            found += 1
            print(f"{p.name} @ {off:#x}: {len(blob)} bytes -> {dtb.name}")
            if dtc:
                subprocess.run([dtc, "-q", "-I", "dtb", "-O", "dts", "-o", dtb.with_suffix(".dts"), dtb], check=False)
        if not found:
            print(f"{p.name}: FDT 없음")


if __name__ == "__main__":
    main(sys.argv[1:])
