#!/bin/bash
# Armbian chroot 안에서 실행됨 (인자: RELEASE LINUXFAMILY BOARD BUILD_DESKTOP). overlay 는 /tmp/overlay.
set -euo pipefail

# tf-os-app 은 overlay 디렉터리를 그대로 .deb 으로 빌드 (OTA 저장소 패키지와 동일 소스)
work=$(mktemp -d)
cp -a /tmp/overlay/tf-os-app "$work/"
chmod 755 "$work/tf-os-app/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$work/tf-os-app" "$work/tf-os-app.deb"

install -D -m 644 /tmp/overlay/tf-os.gpg /usr/share/keyrings/tf-os.gpg
apt-get update
apt-get install -y "$work/tf-os-app.deb"
rm -rf "$work"

# 커스텀 DTB 는 userpatches 커널에만 있음 → Armbian 저장소 커널로 덮어쓰이지 않게 고정
apt-mark hold "linux-image-current-$2" "linux-dtb-current-$2" || true

# 최초 설정은 터치 UI 마법사(tf-os-app)가 담당: Armbian 콘솔 first-login 끄고,
# 기본 root 비밀번호(1234)·SSH 는 설정 완료 전까지 막음.
rm -f /root/.not_logged_in_yet
passwd -l root
systemctl disable ssh
