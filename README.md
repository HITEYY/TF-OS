# TF-OS

토스 프론트 **1 / 1.5세대**(SUNMI, Rockchip RK3399)용 Armbian 기반 커스텀 OS.
2세대(Qualcomm)는 메인라인 지원이 없어 대상 아님.

기기 진입/백업 방식은 [TF-Flasher](https://github.com/HITEYY/TF-Flasher) 와 같음 (rkdeveloptool, Loader/MaskROM).

## 구조
```
build.sh                                   armbian/build 고정 커밋 clone → userpatches 복사 → compile.sh
userpatches/config/boards/tossfront.csc    보드 정의 (rockchip64, evb-rk3399 U-Boot)
userpatches/kernel/archive/rockchip64-6.18/dt/rk3399-tossfront.dts   bring-up DTS
tools/extract_dtb.py                       백업 이미지에서 벤더 DTB 추출/디컴파일
tools/rk.sh                                eMMC 전체 백업 / Armbian 플래시 / 복구
```

## 진행 순서
1. **벤더 DTB 확보** — TF-Flasher로 백업 후
   ```sh
   brew install dtc
   python3 tools/extract_dtb.py ../TF-Flasher/backup/resource.img ../TF-Flasher/backup/boot.img
   ```
   `vendor-dt/*.dts` 에서 PMIC, 디스플레이 패널, 터치, USB, Wi-Fi 정보를 찾아 `rk3399-tossfront.dts` 에 옮긴다.
2. **빌드** (macOS는 Docker 필요)
   ```sh
   ./build.sh            # → build/output/images/Armbian-*_Tossfront_*.img
   ```
3. **eMMC 전체 백업** — 반드시 먼저. TF-Flasher 백업은 userdata를 빼고, 복구할 때 로더 영역(`_head`)을 쓰지 않아서 Armbian에서 Android로 되돌릴 때 부족함.
   ```sh
   tools/rk.sh backup [rk3399_loader.bin]
   ```
4. **플래시** — Android가 지워짐
   ```sh
   tools/rk.sh flash build/output/images/Armbian-*.img [rk3399_loader.bin]
   ```
5. **복구** — 부팅 실패 시 BOOT-GND 쇼트로 MaskROM에 진입한 뒤 `tools/rk.sh restore rk3399_loader.bin`.

UART2(1500000 8N1) 시리얼 콘솔을 연결해 두는 것을 강하게 권장.

## 현재 상태
| 항목 | 상태 |
|---|---|
| DTS 컴파일 (Linux 6.18) | 확인됨 |
| U-Boot (evb-rk3399 + Rockchip DDR/miniloader blob) | 실기기 미검증 |
| eMMC, 시리얼 콘솔 | DTS 작성됨, 미검증 |
| CPU DVFS | 꺼짐 (PMIC 확인 전까지는 부트로더 클럭으로 동작) |
| PMIC, 디스플레이, 터치, USB, Wi-Fi | TODO (벤더 DTB 필요) |
| 카드리더, 프린터 | 별도 보안 MCU라 지원 예정 없음 |

## 주의
- 렌탈 기기는 토스 소유일 수 있음. 본인 소유 기기에만 사용.
- 백업/펌웨어 이미지는 공유 금지 (`.gitignore` 로 제외).
