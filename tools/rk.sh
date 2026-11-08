#!/usr/bin/env bash
# rkdeveloptool 래퍼. 기기는 Loader 모드(리셋 누른 채 전원) 또는 MaskROM(BOOT-GND 쇼트).
#   tools/rk.sh backup [loader.bin]          eMMC 전체 -> backup/emmc-full.img
#   tools/rk.sh flash <armbian.img> [loader]  이미지를 LBA 0 부터 기록 (Android 지워짐)
#   tools/rk.sh restore [loader.bin]          backup/emmc-full.img 를 통째로 복구
# MaskROM 이면 rk3399_loader_*.bin 을 마지막 인자로.
set -euo pipefail
cd "$(dirname "$0")/.."
BACKUP=backup/emmc-full.img

connect() {
	local out
	out=$(rkdeveloptool ld) || true
	echo "$out"
	case "$out" in
	*Mode=Maskrom*)
		[[ -n "${1:-}" ]] || { echo "MaskROM 모드: 로더(rk3399_loader_*.bin) 인자 필요" >&2; exit 1; }
		rkdeveloptool db "$1"
		sleep 1 ;;
	*Mode=Loader*) ;;
	*) echo "Rockusb 장치 없음" >&2; exit 1 ;;
	esac
}

sectors() {
	rkdeveloptool rfi | sed -n 's/.*Flash Size:[[:space:]]*\([0-9]*\)[[:space:]]*Sectors.*/\1/p'
}

case "${1:-}" in
backup)
	connect "${2:-}"
	n=$(sectors)
	[[ -n "$n" ]] || { echo "플래시 크기 확인 실패" >&2; exit 1; }
	mkdir -p backup
	echo "eMMC 전체 백업: $n sectors ($((n / 2048)) MiB)"
	rkdeveloptool rl 0 "$n" "$BACKUP"
	[[ $(wc -c <"$BACKUP") -eq $((n * 512)) ]] || { echo "백업 크기 불일치" >&2; exit 1; }
	echo "완료 -> $BACKUP" ;;
flash)
	img=${2:?armbian 이미지 경로}
	[[ -f "$BACKUP" ]] || { echo "$BACKUP 없음. backup 먼저 (복구 불가해짐)" >&2; exit 1; }
	connect "${3:-}"
	rkdeveloptool wl 0 "$img"
	rkdeveloptool rd ;;
restore)
	[[ -f "$BACKUP" ]] || { echo "$BACKUP 없음" >&2; exit 1; }
	connect "${2:-}"
	rkdeveloptool wl 0 "$BACKUP"
	rkdeveloptool rd ;;
*)
	sed -n '2,6p' "$0"; exit 1 ;;
esac
