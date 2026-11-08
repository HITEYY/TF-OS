# TF-OS

토스 프론트 **1 / 1.5세대**(SUNMI, Rockchip RK3399)용 Armbian 기반 커스텀 OS.
2세대(Qualcomm)는 메인라인 지원이 없어 대상 아님.

기기 진입/백업 방식은 [TF-Flasher](https://github.com/HITEYY/TF-Flasher) 와 같음 (rkdeveloptool, Loader/MaskROM).
이 저장소의 DTS/PMIC/레귤레이터 값은 **실기기 백업의 벤더 DTB를 디컴파일해서** 얻은 것이다
(추측 아님). 어떤 근거인지는 아래 [하드웨어](#하드웨어-벤더-dtb-분석-결과) 절에 표로 정리했다.

## 구조
```
build.sh                                   armbian/build 고정 커밋 clone → userpatches 복사 → compile.sh
userpatches/config/boards/tossfront.csc    보드 정의 (rockchip64, evb-rk3399 U-Boot)
userpatches/kernel/archive/rockchip64-6.18/dt/rk3399-tossfront.dts   보드 DTS (벤더 DTB 기반)
tools/extract_dtb.py                       백업 이미지에서 벤더 DTB 추출/디컴파일 (중복 블롭 제거)
tools/rk.sh                                모드 확인 / MaskROM 진입 / 전체 백업 / 플래시 / 복구
tools/repo.sh                              OTA APT 저장소 서명키 생성 / 저장소(repo/) 빌드
userpatches/customize-image.sh             이미지에 tf-os-app 설치 (overlay 를 .deb 으로 빌드)
userpatches/overlay/tf-os-app/             터치 UI(Qt/QML, eglfs) + 시스템 데몬(OTA/설정/Wi-Fi/오디오) 패키지 소스
tests/test_ota.py                          데몬 로직 점검
```

## 터치 GUI / OTA
- UI: `tf-ui.service` 가 `qml6 main.qml` 을 eglfs(KMS)로 전체화면 실행. 홈 / 업데이트 화면. 방향·터치 보정은 `/etc/tf-os/ui.env`.
- OTA: `tf-ota.service`(127.0.0.1:8765, python 표준 라이브러리)가 tf-os 전용 APT 저장소만 갱신하고 `tf-os-app` 만 업그레이드. UI 가 호출. 적용은 재부팅 후. 커널/DTB 는 apt hold (Armbian 저장소 커널엔 tossfront DTB 없음).
- 배포 절차
  ```sh
  tools/repo.sh keygen                          # 1회. 공개키가 이미지에 들어감
  TFOS_OTA_URL=https://내서버/tf-os ./build.sh  # 이미지 빌드 (URL 은 기기의 /etc/tf-os/tfos.list 에서도 수정 가능)
  # 새 버전: overlay/tf-os-app/DEBIAN/control Version 올림 → tools/repo.sh publish → repo/ 업로드
  ```
- 커널·부트로더·DTS 는 OTA 대상 아님 (재플래시).
- Wi-Fi: 홈 → Wi-Fi. 검색/선택, 비밀번호(화상 키보드), 저장된 망(★) 재연결·끊기·잊기, 숨김 SSID, WPA-Enterprise(PEAP/TTLS + MSCHAPv2/PAP). NetworkManager(`nmcli`). 비밀번호는 stdin 또는 0600 키파일로만 다룸(argv 노출 없음). 미지원: EAP-TLS(인증서), 서버 인증서 검증(기업망은 CA 미검증), 고정 IP. 숨김/기업망 SSID 에 `;` 불가.
- 하드웨어(홈 → 하드웨어): 카메라 미리보기(QtMultimedia, V4L2), IC 리더(PC/SC `pcscd`+`libccid`, `opensc-tool`), NFC(`libnfc`, PN532 등 지원 칩) 상태 표시. **표준 인터페이스로 보일 때만 동작** — 센서/리더 DTS 와 인터페이스(USB CCID 여부 등)는 벤더 DTB 확인 필요. 카드리더/프린터는 별도 보안 MCU(독자 프로토콜)면 지원 불가. 스피커: ALSA(`alsa-utils`) 볼륨 슬라이더 + 테스트음 (코덱 컨트롤 이름은 Speaker→Master→PCM 순으로 자동 탐색, 사운드 카드 DTS(I2S+코덱, 앰프 enable GPIO) 필요, 없으면 "없음" 표시). MST 는 리눅스 표준 인터페이스가 없어 미지원.
- 최초 부팅: 터치 화면에 "처음 설정"(사용자·비밀번호·SSH 켜기, 화상 키보드)이 뜸. 완료 전엔 root 잠금 + SSH 꺼짐(Armbian 콘솔 first-login 비활성). 완료 후 SSH `PermitRootLogin no`, 사용자는 sudo 그룹. 설정 완료 표시: `/var/lib/tf-os/setup-done` (지우면 마법사 재실행 가능, 이미 만든 사용자는 그대로).

## 기기 진입 (실기기에서 확인한 절차)

```sh
# 1) Loader 모드: 초기화(RECOV) 버튼을 누른 채 USB 연결
tools/rk.sh status            # mode: Loader

# 2) MaskROM 진입 — 버튼/쇼트 아님. rd 3 리셋
tools/rk.sh maskrom           # rkdeveloptool rd 3 → mode: Maskrom

# 3) 순정 로더를 RAM에 적재 (이 상태에서만 전 영역 접근 가능)
tools/rk.sh backup rk3399_loader_v1.30.130.bin
```

**중요 — 순정 Loader 모드의 32 MiB 제한**

토스 프론트의 순정 로더는 LBA `0x10000`(32 MiB) 이후를 읽으면 전부 `0xCC` 로 돌려준다.
고장이 아니라 로더의 보호 동작이고, `rkdeveloptool`(RCU1)·`upgrade_tool` 모두 동일하다.
따라서

- Loader 모드에서 뜬 백업은 **앞 32 MiB만 유효**하다 (`boot`까지는 정상, `recovery`·`super`는 0xCC).
- 전체 백업/플래시는 반드시 **MaskROM + `db`로 올린 순정 로더** 상태에서 한다.
- `db` 직후 기기는 USB에서 **재열거**된다. 곧바로 다음 명령을 보내면
  `Did not find any rockusb device` 로 실패하므로 `tools/rk.sh` 는 인식될 때까지 대기한다.

MaskROM에서 공용 로더(`rk3399_loader_v1.30.130.bin`)가 멈추는 개체도 보고되어 있다.
그 경우는 기기 자체 U-Boot로 RAM 리더를 만드는 경로가 필요하다(문서 하단 참고 링크).

## 하드웨어 (벤더 DTB 분석 결과)

`backup/boot.img` 안의 FDT를 `tools/extract_dtb.py` 로 뽑아 확인한 값.

| 항목 | 값 |
|---|---|
| SoC / RAM | RK3399, 2 GiB (벤더 root compatible: `rockchip,rk3399-evb-ind-lpddr4-android`) |
| PMIC | RK808 @ i2c0 `0x1b` (vdd_center, vdd_cpu_l, vcc_ddr, vcc_1v8, vcc_sd, …) |
| 추가 DC-DC | FAN53555 @ i2c0 `0x40`=vdd_cpu_b, `0x41`=vdd_gpu (712.5 mV–1.5 V) |
| eMMC | sdhci `fe330000`, 8 bit, 벤더는 HS400(1.8 V, enhanced-strobe) |
| SD | dwmmc `fe320000`, 4 bit, vmmc/vqmmc = `vcc_sd` (RK808 LDO4 1.8–3.0 V) |
| Wi-Fi | AP6354 (BCM4354) SDIO dwmmc `fe310000`, pwrseq reset = `gpio0 PB2`, `sd-uhs-sdr104` |
| 터치 | GSL3673 @ i2c1 `0x40`, IRQ `gpio1 PC4`, RST `gpio1 PA1`, 좌표계 1536×2048 |
| 백라이트 | PWM0 (`ff420000`), 주기 40 µs, 0–255 레벨, 기본 200 |
| 디스플레이 | MIPI-DSI0, 아래 패널 변형 중 하나 |
| 오디오 | ES8316 (I2S) |
| 배터리 게이지 | cw201x |
| 카메라 | OV5675 (+ TC358749X HDMI-in) |
| 기타 | 4G 모뎀 플랫폼 노드, SAM 슬롯 4개, 프린터/카드리더는 별도 보안 MCU |

### 패널 변형 (벤더 DTB의 `lcd-compatible`)

같은 이름의 기기에도 패널이 여러 종류이고, 부트로더가 보드 ID(`M13`/`M14`/`M15`)를 읽어 고른다.
DTS 기본값은 `mipi_lcd_23`(800×1280, 3 lane)이다. 화면이 안 뜨면 아래 표에서 골라
`dsi,lanes` 와 `timing0` 을 교체한다.

| 변형 | 해상도 | lanes | clock | hbp/hfp/hsw | vbp/vfp/vsw |
|---|---|---|---|---|---|
| mipi_lcd_23 (M13) | 800×1280 | 3 | 60.0 MHz | 20/40/20 | 16/30/4 |
| mipi_lcd_24 (M14) | 800×1280 | 3 | 60.0 MHz | 32/32/4 | 12/15/4 |
| mipi_lcd_25 (M15) | 800×1280 | 3 | 60.0 MHz | 32/32/4 | 12/15/4 |
| mipi_lcd_10 | 1024×600 | 4 | 66.6 MHz | 40/200/40 | 150/100/20 |
| mipi_lcd_13 | 1024×600 | 4 | 68.0 MHz | 160/160/10 | 23/12/1 |
| mipi_lcd_16 | 1024×600 | 4 | 51.2 MHz | 160/160/10 | 23/12/1 |
| mipi_lcd_21/22 | 1920×1080 | 4 | 160.9 MHz | 60/180/40 | 10/30/5 |

## TF-OS 앱 ↔ DTS 매핑

`userpatches/overlay/tf-os-app` 의 터치 UI가 쓰는 하드웨어와 DTS 상태:

| 앱 기능 | 필요한 DTS | 상태 |
|---|---|---|
| 화면(qml eglfs/KMS) | `&mipi_dsi` + `backlight` | 타이밍/시퀀스 있음, **패널 드라이버 이식 필요** (`disabled`) |
| 터치 입력 | `touchscreen@40` (GSL3673) | **silead 드라이버에 ID 없음** (`disabled`) |
| 스피커 페이지 (ALSA) | `&i2s1` + `es8316@10` + `sound` | 작성 완료. `aplay -l` 에 `Toss Front` 로 나와야 정상 |
| 카메라 미리보기 (V4L2) | `ov5675@10` → `isp0` + `mipi_dphy_rx0` | 작성 완료. `/dev/video*` 생성 여부로 확인 |
| Wi-Fi | `&sdio0` + `sdio_pwrseq` | 작성 완료 (AP6354, `brcmfmac` 펌웨어 필요) |
| IC 리더 (PC/SC) | — | 벤더 DTB에 노드 없음 → **USB CCID 여부 실기기 확인 필요** |
| NFC | — | 벤더 DTB에 노드 없음 → USB/SPI 모듈 여부 확인 필요 |

회전/터치 보정은 DTS가 아니라 `/etc/tf-os/ui.env`(`QT_QPA_EGLFS_ROTATION`, `QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS`)에서 한다.
패널 방향이 세로(800×1280)라면 `QT_QPA_EGLFS_ROTATION=90` 부터 시도.

## 빌드

```sh
./build.sh                 # → build/output/images/Armbian-*_Tossfront_*.img
                           # macOS는 Docker 필요, 인자는 compile.sh 로 전달됨
```

DTS 문법 검사(커널 트리 없이):

```sh
git clone --filter=blob:none --depth 1 --sparse https://github.com/torvalds/linux /tmp/linux
cd /tmp/linux && git sparse-checkout set include/dt-bindings arch/arm64/boot/dts/rockchip
D=arch/arm64/boot/dts/rockchip
gcc -E -P -x assembler-with-cpp -I $D -I include $D/rk3399-tossfront.dts -o /tmp/pp.dts
dtc -I dts -O dtb -o /tmp/tossfront.dtb /tmp/pp.dts
```

## 백업 · 플래시 · 복구

```sh
tools/rk.sh maskrom                                  # Loader → MaskROM
tools/rk.sh backup rk3399_loader_v1.30.130.bin        # 전체 eMMC (0xCC 검사 포함)
tools/rk.sh flash build/output/images/Armbian-*.img rk3399_loader_v1.30.130.bin
tools/rk.sh restore rk3399_loader_v1.30.130.bin       # Android로 되돌리기
```

`backup/emmc-full.img` 는 LBA 0부터 양쪽 GPT까지 포함한 원본이다. TF-Flasher 백업(userdata 제외,
`_head` 미포함)만으로는 Android로 완전 복구가 안 되므로 이 백업을 먼저 뜬다.

UART2(1500000 8N1) 시리얼 콘솔 연결을 강하게 권장.

## 현재 상태

| 항목 | 상태 |
|---|---|
| DTS 컴파일 (Linux 6.18) | 통과 (cpp + dtc, 경고는 SoC dtsi 것) |
| PMIC/레귤레이터 | 벤더 DTB 값으로 작성 (RK808 + FAN53555 ×2) |
| eMMC 부팅 | HS200로 설정 (벤더 HS400은 주석으로 남김) — **실기기 미검증** |
| 시리얼 콘솔 | DTS 작성, 미검증 |
| Wi-Fi (AP6354) | 노드 작성, 펌웨어/`brcmfmac` 확인 필요 |
| USB (dwc3 ×2, ehci/ohci ×2) | 노드 작성, 미검증 |
| 터치 (GSL3673) | 노드 작성했지만 **메인라인 silead 드라이버에 항목 없음** → disabled |
| 디스플레이 | 타이밍/시퀀스 확보. 벤더 init-sequence 방식이라 **드라이버 이식 필요** → disabled |
| 오디오 (ES8316 + I2S1) | **작성 완료** — `Toss Front` 사운드 카드, mclk `SCLK_I2S_8CH_OUT`, spk-con `gpio0 PB4`. 실기기 미검증 |
| 카메라 (OV5675) | **작성 완료** — i2c2 `0x10` → MIPI DPHY RX0 → ISP0(rkisp1), 2 lane, 벤더 레귤레이터/GPIO 그대로. 실기기 미검증 |
| 배터리 게이지 (cw201x) | 미작성 (벤더 DTB 기준 i2c 연결, 노드 없음) |
| CPU/GPU DVFS | 꺼짐 (OPP 미적용, U-Boot 클럭으로 동작) |
| 카드리더·프린터 | 별도 보안 MCU, 지원 예정 없음 |

### 다음 작업 후보
1. 실기기에서 eMMC/시리얼 부팅 확인 → 실패 시 U-Boot `BOOTCONFIG`/DDR 설정 점검
2. **패널 드라이버**: 벤더 init-sequence를 `panel-simple` 규약으로 옮기거나 Rockchip BSP 드라이버 이식
   — TF-OS 터치 UI가 뜨려면 이게 먼저다
3. **터치**: silead 드라이버에 GSL3673 ID 추가(+ 벤더 펌웨어 blob 필요 여부 확인)
4. 오디오/카메라 실기기 검증 (`aplay -l`, `v4l2-ctl --list-devices`)
5. cw201x 게이지 노드

## 참고 자료
- 기기 진입/백업: 디시 SFF 갤 가이드 #1·#2·#3, [PLF 계열 상세 가이드(gist)](https://gist.github.com/luftaquila/f15c2db7a4a81bde3f6d7ba9b983d71c)
  — gist에 "순정 Loader에서 32 MiB 이후 0xCC" 사례와 `rd 3` → MaskROM 절차가 정리되어 있다.

## 주의
- 렌탈 기기는 토스 소유일 수 있음. 본인 소유 기기에만 사용.
- 백업/펌웨어 이미지는 공유 금지 (`.gitignore` 로 제외).
- Armbian을 플래시하면 Android와 userdata가 지워진다. `tools/rk.sh backup` 을 먼저.
