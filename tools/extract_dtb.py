#!/usr/bin/env python3
"""백업 이미지(resource/boot/dtbo/... .img)에서 FDT 블롭을 찾아 vendor-dt/ 에 .dtb/.dts 로 저장.

Rockchip resource.img(RSCE)든 Android boot.img든 FDT magic 으로 스캔하므로 포맷 무관.
같은 내용의 블롭(boot.img 에 중복으로 들어있는 경우 등)은 한 번만 저장한다.

사용:
    python3 tools/extract_dtb.py backup/boot.img backup/dtbo.img

결과:
    vendor-dt/<stem>-<offset>.dtb
    vendor-dt/<stem>-<offset>.dts   (dtc 가 있을 때)
"""
import hashlib
import mmap
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
        # 헤더 sanity: 크기 범위, 버전 16/17 (FDT + FDT with overlay)
        if 0x40 <= size <= 8 << 20 and version in (16, 17) and i + size <= len(data):
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
    seen = {}
    for p in map(Path, paths):
        if not p.is_file():
            print(f"{p.name}: 파일 없음")
            continue
        found = 0
        with p.open("rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
            for off, blob in blobs(data):
                digest = hashlib.sha256(blob).hexdigest()
                if digest in seen:
                    print(f"{p.name} @ {off:#x}: 중복 ({seen[digest]} 와 동일)")
                    found += 1
                    continue
                name = f"{p.stem}-{off:#x}"
                seen[digest] = name
                dtb = OUT / f"{name}.dtb"
                dtb.write_bytes(blob)
                found += 1
                print(f"{p.name} @ {off:#x}: {len(blob)} bytes  sha256={digest[:16]}… -> {dtb.name}")
                if dtc:
                    subprocess.run([dtc, "-q", "-I", "dtb", "-O", "dts",
                                    "-o", str(dtb.with_suffix(".dts")), str(dtb)], check=False)
        if not found:
            print(f"{p.name}: FDT 없음")
    print(f"\n출력: {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:])
