#!/usr/bin/env bash
# Armbian 이미지 → 실기기 eMMC 기록 (사전 점검 포함)
#
#   tools/flash-image.sh                 build/output/images 의 최신 .img 로 플래시
#   tools/flash-image.sh <img>           지정 이미지로 플래시
#   tools/flash-image.sh <img> --check   점검만 하고 쓰지 않음 (기본 첫 단계로 권장)
#   tools/flash-image.sh <img> --force   백업 sha256 불일치 등 경고 무시
#   tools/flash-image.sh --wait 300      300초까지 기기(rockusb) 연결 대기 후 점검/기록
#
# 전제 (실기기에서 확인된 사실):
#   - 쓰기는 반드시 MaskROM + 순정 로더(db) 상태에서. 순정 Loader 모드에서 32MiB 이후는 0xCC.
#   - rk.sh 가 db/재열거 대기/백업 검사를 담당한다.
set -euo pipefail
cd "$(dirname "$0")/.."

LOADER=${LOADER:-$HOME/TF-Flasher/loaders/rk3399_loader_v1.30.130.bin}
BACKUP=backup/emmc-full.img
IMG=""
CHECK_ONLY=0
FORCE=0
WAIT=0
for a in "$@"; do
	case "$a" in
	--check) CHECK_ONLY=1 ;;
	--force) FORCE=1 ;;
	--wait) WAIT_ARG=1 ;;
	-h | --help)
		sed -n '2,12p' "$0"
		exit 0
		;;
	[0-9]*) WAIT=$a ;;     # --wait 뒤에 오는 초
	*) IMG=$a ;;
	esac
done

if [[ -z "$IMG" ]]; then
	IMG=$(ls -t build/output/images/*.img 2>/dev/null | head -1 || true)
fi
[[ -n "$IMG" && -f "$IMG" ]] || {
	echo "이미지 없음: ${IMG:-build/output/images/*.img}" >&2
	exit 1
}

if ((WAIT > 0)); then
	echo "rockusb 장치 대기 (최대 ${WAIT}s): 기기 전원 인가 시 BOOT/RECOV 버튼 조합으로 Loader 진입"
	tools/rk.sh wait "$WAIT"
fi

echo "이미지: $IMG"
echo "크기  : $(du -h "$IMG" | cut -f1) ($(stat -c %s "$IMG") bytes)"
echo "sha256: $(sha256sum "$IMG" | cut -d' ' -f1)"

# 1) 구조 점검: MBR 시그니처 + idbloader(0x8000) 대조
#    RK33/RK35 매직은 rkbin 계열 로더에만 있다. u-boot v2022.07 binman으로 만든
#    idbloader는 0x3b8cdcfc 등 다른 매직을 쓰므로, 빌드 산출 deb의 idbloader.bin과
#    해시를 대조하는 쪽을 우선한다(매직은 보조 판정).
IDB_SHA=""
deb=$(ls -t build/output/debs/linux-u-boot-*.deb 2>/dev/null | head -1 || true)
if [[ -n "$deb" ]]; then
	IDB_SHA=$(dpkg-deb --fsys-tarfile "$deb" 2>/dev/null | tar -xO --wildcards '*/idbloader.bin' 2>/dev/null | head -c 65536 | sha256sum | cut -d' ' -f1) || true
fi
IMG_IDB_SHA=$(dd if="$IMG" bs=32768 skip=1 count=2 2>/dev/null | sha256sum | cut -d' ' -f1) || true

python3 - "$IMG" "$IDB_SHA" "$IMG_IDB_SHA" <<'PY'
import os
import sys

path, idb_sha, img_sha = sys.argv[1], (sys.argv[2] or ""), (sys.argv[3] or "")
size = os.path.getsize(path)
with open(path, "rb") as f:
    f.seek(0x1FE)
    mbr = f.read(2)
    f.seek(0x8000)
    magic = f.read(4)

ok = True
if mbr != b"\x55\xaa":
    print(f"FAIL: MBR 시그니처 없음 (0x1FE={mbr.hex()})")
    ok = False
else:
    print("OK  : MBR 시그니처 55aa")
if idb_sha and img_sha == idb_sha:
    print("OK  : idbloader 0x8000 = 빌드 산출 idbloader.bin (해시 일치)")
elif magic in (b"RK33", b"RK35"):
    print(f"OK  : idbloader 매직 {magic.decode()}")
else:
    print(f"FAIL: idbloader 없음 (0x8000={magic!r}, deb idbloader={idb_sha[:12] or 'n/a'}, img={img_sha[:12] or 'n/a'})")
    ok = False
print(f"     이미지 섹터: {(size + 511) // 512:,}")
sys.exit(0 if ok else 1)
PY

# 2) eMMC 용량 대비 크기 점검
sectors=$(rkdeveloptool rfi 2>/dev/null | sed -n 's/.*Flash Size:[[:space:]]*\([0-9]*\)[[:space:]]*Sectors.*/\1/p' | head -1)
if [[ -n "$sectors" ]]; then
	img_sectors=$((($(stat -c %s "$IMG") + 511) / 512))
	echo "eMMC  : $sectors sectors ($((sectors / 2048)) MiB)"
	((img_sectors <= sectors)) || {
		echo "FAIL: 이미지가 eMMC 보다 큼 ($img_sectors > $sectors)" >&2
		exit 1
	}
	echo "OK  : 이미지가 eMMC 용량 안에 들어감 (여유 $((sectors - img_sectors)) sectors)"
else
	echo "WARN: eMMC 크기 확인 실패 (기기 미연결?)"
fi

# 2.5) 현재 접근 상태 (8MiB = 0xCC 이면 보호 상태)
if rkdeveloptool ld 2>/dev/null | grep -q .; then
	rkdeveloptool rl 16384 1 /tmp/.flash-probe.img >/dev/null 2>&1 || true
	probe_hex=$(od -An -tx1 -N16 /tmp/.flash-probe.img 2>/dev/null | tr -d ' \n')
	rm -f /tmp/.flash-probe.img
	if [[ "$probe_hex" == "cccccccccccccccccccccccccccccccc" ]]; then
		echo "WARN: 현재 0xCC 보호 상태 → rk.sh 가 rd 3 + db 로 자동 해제 시도"
	else
		echo "OK  : 전체 접근 가능 (8MiB 영역 정상 읽기)"
	fi
else
	echo "WARN: rockusb 장치 없음 (--wait <초> 로 대기 가능)"
fi

# 3) 복구용 전체 백업 확인
[[ -f "$LOADER" ]] && echo "OK  : 로더 $LOADER" || {
	echo "FAIL: 로더 없음 $LOADER" >&2
	exit 1
}
if [[ -f "$BACKUP" ]]; then
	echo "OK  : 전체 백업 $(du -h "$BACKUP" | cut -f1) $BACKUP"
	if [[ -f "$BACKUP.sha256" ]]; then
		if sha256sum -c "$BACKUP.sha256" >/dev/null 2>&1; then
			echo "OK  : 백업 sha256 일치"
		else
			echo "WARN: 백업 sha256 불일치 (백업이 손상/변경됨)" >&2
			((FORCE)) || {
				echo "      계속하려면 --force" >&2
				exit 1
			}
		fi
	fi
else
	echo "FAIL: 전체 백업 없음 ($BACKUP). tools/rk.sh backup <loader> 먼저 실행" >&2
	exit 1
fi

if ((CHECK_ONLY)); then
	echo
	echo "점검 완료 (--check). 실제 기록은 --check 없이 다시 실행하세요."
	exit 0
fi

echo
echo "=== eMMC 기록 시작 (Android/기존 OS 삭제됨) ==="
tools/rk.sh flash "$IMG" "$LOADER"
echo
echo "기록 완료. UART2 로 부팅 로그 확인 (1500000 8N1, 1.8V USB-TTL):"
echo "  screen /dev/ttyUSB0 1500000"
