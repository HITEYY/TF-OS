#!/usr/bin/env bash
# Armbian 빌드: build/ 에 armbian/build 를 받아 userpatches 를 덮어쓰고 compile.sh 실행.
# 추가 인자는 compile.sh 로 그대로 전달 (예: ./build.sh BUILD_DESKTOP=yes ...)
set -euo pipefail
cd "$(dirname "$0")"

ARMBIAN_REPO=https://github.com/armbian/build
ARMBIAN_REF=39ce059e2126836054c94c043a2669d1161d751b # main, 2026-10-14

if [[ ! -d build/.git ]]; then
	git clone --filter=blob:none "$ARMBIAN_REPO" build
fi
git -C build fetch --quiet origin "$ARMBIAN_REF" || true
git -C build checkout --quiet "$ARMBIAN_REF"

# Docker 빌드는 build/ 만 마운트하므로 symlink 대신 복사
rm -rf build/userpatches
cp -R userpatches build/userpatches

cd build
exec ./compile.sh build \
	BOARD=tossfront \
	BRANCH=current \
	RELEASE=trixie \
	BUILD_MINIMAL=yes \
	BUILD_DESKTOP=no \
	KERNEL_CONFIGURE=no \
	"$@"
