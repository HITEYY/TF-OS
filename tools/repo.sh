#!/usr/bin/env bash
# OTA APT 저장소 생성 (Docker 사용, macOS 가능).
#   tools/repo.sh keygen    서명키 생성(.gnupg/) + 공개키를 userpatches/overlay/tf-os.gpg 로 내보냄 (이미지 빌드 전 1회)
#   tools/repo.sh publish   tf-os-app 을 .deb 로 빌드 → repo/ (서명된 정적 저장소). repo/ 를 OTA URL 에 올리면 끝.
# 새 버전 배포: userpatches/overlay/tf-os-app/DEBIAN/control 의 Version 올리고 publish 후 업로드.
set -euo pipefail
cd "$(dirname "$0")/.."

in_docker() {
	docker run --rm -v "$PWD":/w -w /w -e GNUPGHOME=/w/.gnupg debian:trixie bash -euc \
		"apt-get update -qq && apt-get install -y -qq apt-utils gnupg dpkg-dev >/dev/null; mkdir -p -m700 .gnupg; $1"
}

case "${1:-}" in
keygen)
	[[ ! -d .gnupg/private-keys-v1.d ]] || { echo ".gnupg 이미 있음 (키 교체 시 기기 전부 재플래시 필요)" >&2; exit 1; }
	in_docker 'gpg --batch --passphrase "" --quick-generate-key "TF-OS OTA" ed25519 sign never
		gpg --export > userpatches/overlay/tf-os.gpg'
	echo "공개키 -> userpatches/overlay/tf-os.gpg  (.gnupg/ 는 비밀키: 백업, 커밋 금지)" ;;
publish)
	[[ -d .gnupg ]] || { echo "keygen 먼저" >&2; exit 1; }
	rm -rf repo
	in_docker '
		d=dists/trixie/main/binary-arm64
		mkdir -p repo/pool/main repo/$d
		cp -a userpatches/overlay/tf-os-app /tmp/pkg && chmod 755 /tmp/pkg/DEBIAN/postinst
		v=$(sed -n "s/^Version: //p" /tmp/pkg/DEBIAN/control)
		dpkg-deb --root-owner-group --build /tmp/pkg repo/pool/main/tf-os-app_${v}_arm64.deb
		cd repo
		apt-ftparchive packages pool > $d/Packages && gzip -k $d/Packages
		apt-ftparchive -o APT::FTPArchive::Release::Codename=trixie -o APT::FTPArchive::Release::Suite=trixie \
			-o APT::FTPArchive::Release::Components=main -o APT::FTPArchive::Release::Architectures=arm64 \
			release dists/trixie > dists/trixie/Release
		gpg --batch --yes --clearsign -o dists/trixie/InRelease dists/trixie/Release
		gpg --batch --yes -abs -o dists/trixie/Release.gpg dists/trixie/Release'
	echo "repo/ 생성 완료 -> OTA URL 로 업로드" ;;
*)
	sed -n '2,5p' "$0"; exit 1 ;;
esac
