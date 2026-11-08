#!/usr/bin/env bash
# rkdeveloptool 래퍼 (Toss Front RK3399)
#
#   tools/rk.sh status                      현재 모드 출력 (Loader/Maskrom/none)
#   tools/rk.sh maskrom                     Loader → MaskROM 재진입 (rd 3)
#   tools/rk.sh backup [loader.bin]         eMMC 전체(+양쪽 GPT) → backup/emmc-full.img
#   tools/rk.sh flash <armbian.img> [loader] LBA 0부터 기록 (Android 지워짐)
#   tools/rk.sh restore [loader.bin]        backup/emmc-full.img 로 통째 복구
#
# 중요 (실기기에서 확인한 사실):
#   - 순정 Loader 모드에서는 LBA 0x10000(32MiB) 이후를 읽으면 전부 0xCC로 온다.
#     이건 고장이 아니라 토스 로더의 보호 동작이고, rkdeveloptool/upgrade_tool 모두 같다.
#     → 전체 백업/플래시는 반드시 MaskROM + 순정 로더(db) 상태에서 해야 한다.
#   - Loader → MaskROM 은 버튼/쇼트가 아니라 `rkdeveloptool rd 3` 로 들어간다.
#   - db 직후 기기는 USB에서 재열거된다. 곧바로 다음 명령을 보내면 실패하므로 대기 필요.
set -euo pipefail
cd "$(dirname "$0")/.."

BACKUP=backup/emmc-full.img
RK=${RK:-rkdeveloptool}

rk() { "$RK" "$@"; }

mode() {
	local out
	out=$(rk ld 2>/dev/null || true)
	case "$out" in
	*Maskrom*) echo Maskrom ;;
	*Loader*) echo Loader ;;
	*) echo none ;;
	esac
}

# 기기가 다시 보일 때까지 대기 (db 후 재열거 대응)
wait_device() {
	local limit=${1:-15} i=0
	while ((i < limit)); do
		[[ "$(mode)" != none ]] && return 0
		sleep 1
		((i++))
	done
	return 1
}

connect() {
	wait_device 10 || {
		echo "Rockusb 장치 없음: 초기화 버튼을 누른 채 전원을 연결 (또는 MaskROM 진입)" >&2
		exit 1
	}
	[[ "$(mode)" == Maskrom ]] || return 0
	[[ -n "${1:-}" ]] || {
		echo "MaskROM 모드: 로더 인자가 필요합니다 (예: rk3399_loader_v1.30.130.bin)" >&2
		exit 1
	}
	echo "로더 다운로드: $1"
	rk db "$1"
	wait_device 20 || {
		echo "로더 다운로드 후 재열거 대기 실패" >&2
		exit 1
	}
}

sectors() {
	rk rfi | sed -n 's/.*Flash Size:[[:space:]]*\([0-9]*\)[[:space:]]*Sectors.*/\1/p' | head -1
}

# 백업이 0xCC 로 채워지지 않았는지 확인 (Loader 모드 제한 회피 실패 감지)
check_not_cc() {
	local f=$1
	local tail_hex
	tail_hex=$(tail -c 65536 "$f" | od -An -tx1 | tr -d ' \n')
	if [[ "$tail_hex" == *"$(printf 'cc%.0s' $(seq 1 64))"* ]]; then
		echo "경고: 백업 끝부분이 0xCC 입니다. Loader 모드 제한에 걸렸을 수 있습니다." >&2
		echo "      MaskROM + 순정 로더(db) 상태에서 다시 백업하세요." >&2
		return 1
	fi
	return 0
}

case "${1:-}" in
status)
	echo "mode: $(mode)" ;;
maskrom)
	[[ "$(mode)" == Loader ]] || {
		echo "Loader 모드에서만 사용합니다 (현재: $(mode))" >&2
		exit 1
	}
	rk rd 3
	wait_device 15 || {
		echo "MaskROM 진입 실패" >&2
		exit 1
	}
	[[ "$(mode)" == Maskrom ]] || {
		echo "MaskROM 아님: $(mode)" >&2
		exit 1
	}
	echo "MaskROM 진입 완료" ;;
backup)
	connect "${2:-}"
	n=$(sectors)
	[[ -n "$n" ]] || {
		echo "플래시 크기 확인 실패" >&2
		exit 1
	}
	mkdir -p backup
	echo "eMMC 전체 백업: $n sectors ($((n / 2048)) MiB)"
	rm -f "$BACKUP"
	rk rl 0 "$n" "$BACKUP"
	[[ $(wc -c <"$BACKUP") -eq $((n * 512)) ]] || {
		echo "백업 크기 불일치" >&2
		exit 1
	}
	check_not_cc "$BACKUP" || exit 1
	sha256sum "$BACKUP" >"$BACKUP.sha256"
	echo "완료 -> $BACKUP" ;;
flash)
	img=${2:?armbian 이미지 경로}
	[[ -f "$BACKUP" ]] || {
		echo "$BACKUP 없음. backup 먼저 (복구 불가해짐)" >&2
		exit 1
	}
	connect "${3:-}"
	echo "기록: $img (Android 파티션은 지워집니다)"
	rk wl 0 "$img"
	rk rd
	echo "완료. UART2(1500000 8N1)로 부팅 로그를 확인하세요." ;;
restore)
	[[ -f "$BACKUP" ]] || {
		echo "$BACKUP 없음" >&2
		exit 1
	}
	connect "${2:-}"
	echo "복구: $BACKUP"
	rk wl 0 "$BACKUP"
	rk rd
	echo "완료" ;;
*)
	sed -n '2,10p' "$0"
	exit 1 ;;
esac
