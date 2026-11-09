# TF-OS 브링업 현재 상태 (2026-11-09)

> 대상 기기: Toss Front 1/1.5세대 (SUNMI, Rockchip RK3399, eMMC 14.9GiB)
> 담당: 서연 / 유찬님 지시로 진행

## 한 줄 요약

**이미지 빌드·플래시는 성공했지만, 기기가 부팅하지 않는다. 원인은 커널/화면이 아니라
부트로더의 LPDDR4 트레이닝 실패이며, 현재 eMMC 물리 접근이 불가해 MaskROM 재진입도 막혀 있다.**

---

## 1. 지금 기기 상태

| 항목 | 상태 |
|---|---|
| 화면 | 꺼짐 (백라이트도 안 들어옴) |
| USB (MaskROM/rockusb) | 인식 안 됨 (`2207:330c` 없음) |
| UART 콘솔 | **동작함** — 기기 `TX_3V0`/`RX_3V0` → OPI UART7, 1500000 8N1 |
| 네트워크 | 없음 (WiFi 펌웨어 미포함, 이더넷 없음) |
| SD 슬롯 | 없음 |
| 부팅 진행도 | **bootrom → miniloader(DDR 초기화) 단계에서 정지** |

## 2. 확정된 원인

UART로 잡은 부팅 로그:

```
DDR Version 1.25 20210517
Channel 0: LPDDR4,416MHz
Bus Width=32 Col=10 Bank=8 Row=16 CS=1 Die Bus-Width=16 Size=2048MB
channel 0 training pass!
channel 1 training failed!
channel 1, cs 97..253 dq 0..31 RISK!!! TdiVW_total violate spec   (무한 재시도)
```

- Armbian 기본 rkbin DDR blob(`rk3399_ddr_933MHz_v1.25.bin`)의 LPDDR4 파라미터가 이 보드와 맞지 않아
  **channel 1 트레이닝이 실패**하고, 그 상태로 무한 루프에 빠진다.
- u-boot proper 이전 단계이므로 **커널·DSI·화면 문제가 아니다.** 화면이 안 켜지는 것은 결과일 뿐이다.
- 벤더 부트로더는 **DDR Version 1.26 20210628** (rkbin 공개본에 없는 커스텀 빌드)을 사용한다.
  → 벤더는 자체 LPDDR4 파라미터를 쓴다.

## 3. 왜 복구가 막혔나

| 경로 | 결과 |
|---|---|
| `BOOT` 패드 + GND 쇼트 | 무효 — 그 패드는 **벤더 u-boot이 읽는 GPIO 복구키**이고, 지금 u-boot이 실행되지 않음 |
| eMMC CLK/DAT/CMD 쇼트 | **eMMC 신호가 전부 PCB 내부(비노출)** |
| SD 부팅 (u-boot boot_targets: mmc1→mmc0→usb0) | **SD 슬롯 없음** |
| USB 시리얼 콘솔 | UART 어댑터 없음 → OPI GPIO UART로 대체 성공 |
| . 순정 Loader에서 `rd 3` | 벤더 Loader 자체가 이미 지워짐 |

## 4. 진행 이력

1. **01:04** 1차 빌드 실패 → 커널 6.18 `vsi-iommu` `attach_dev` 시그니처 변경 대응 userpatch 추가 (`e6904cf`)
2. **10:35** 2차 빌드를 강제 종료한 여파로 증분 빌드 오염(`.cmd`/`.o.d` 손상) → 4차 재실행
3. **13:54** 이미지 빌드 성공 (2.57GB, `sha256 f23d94fe…`)
4. **15:2x** eMMC 플래시 100% 완료 (`Reset Device OK`)
5. **16:10** 화면 안 켜짐 확인 → DTS상 `mipi_dsi`가 disabled 인 것 확인(설계상 정상)
6. **17–19시** UART 콘솔 확보(OPI `uart7` overlay) → **DDR 트레이닝 실패** 진단
7. **19시~** MaskROM 진입 시도 전부 실패 → 하드웨어 개입 필요 판정

## 5. 지금 빌드 중인 이미지 (재플래시용)

MaskROM만 확보되면 바로 쓸 수 있도록 준비 중:

- **DDR blob 교체**: `DDR_BLOB="rk33/rk3399_ddr_800MHz_v1.27.bin"` (기본 933MHz v1.25 → 낮은 주파수·최신)
- **rockusb 활성화**: `userpatches/u-boot/u-boot-rockchip64/0010-enable-rockusb.patch`
  (`CMD_ROCKUSB`, `USB_FUNCTION_ROCKUSB`, `USB_GADGET`, `DWC3_GADGET`)
  → 앞으로 u-boot 단계에서 `rockusb 0 mmc 0`으로 복구 가능
- 커널/루트fs는 기존과 동일 (kernel 6.18.62, trixie minimal)
- 디스플레이는 여전히 disabled — 패널 드라이버 이식은 별도 작업(6절)

## 6. 디스플레이 작업 (다음 단계, 근거 확보됨)

벤더 DTB(`vendor-dt/boot-0x255a000.dts`)에서 확인한 패널 변형:

| variant | 해상도 | lane | 클럭 | 컨트롤러 추정 |
|---|---|---|---|---|
| `mipi_lcd_23` (M13) | 1920x1080 | 3 | ~161MHz | ILI9881C (`0xff 98 81 03`) |
| `mipi_lcd_24` (M14) | 800x1280 | 3 | 60MHz | ILI9881C |
| `mipi_lcd_25` (M15) | 800x1280 | 3 | 60MHz | JD9365 계열 (`0xE0` page) |
| `mipi_lcd_10/13/15/16` | 1024x600 | 4 | — | — |

- `panel-init-sequence` 포맷: `[type][delay_ms][len][payload...]`
  (`0x05`=short write, `0x15`/`0x39`=long write, len = payload 바이트 수)
- 전략: 제로 구현 대신 **mainline의 ILI9881C / JD9365 드라이버를 우리 variant로 확장**
- 실기기에서 어느 variant인지는 미확인 → 1차 시도 후 timing/lane 교체 필요할 수 있음

## 7. 남은 제약 / 준비물

- `brcmfmac4354`(AP6354) 펌웨어가 Armbian 이미지에 없음 → 벤더 백업에서 추출해 넣어야 WiFi 동작
- 벤더 부트로더/DDR blob은 `~/tfos-work/backup/emmc-full.img`(3.0GB 유효 백업)에 보존됨
- UART 어댑터 없음 → OPI UART7 + 점퍼선으로 콘솔 확보(현재 사용 중)
  - OPI 콘솔: `/boot/armbianEnv.txt`에 `overlays=uart7` (백업 `armbianEnv.txt.bak-*`)

## 8. 복구 절차 (eMMC 접근이 가능해지면)

1. **eMMC를 들어내거나 신호를 쇼트**해 bootrom을 MaskROM으로 강제 진입 (`2207:330c` 확인)
2. `tools/flash-image.sh --check` (사전 점검: MBR, idbloader 해시, eMMC 용량, 백업 sha256)
3. 플래시 → 재부팅
4. UART7 콘솔로 확인:
   - `channel 0/1 training pass!` → `U-Boot 2022.07` 배너 → 커널 로그
   - 실패 시 즉시 **전원 끄고** DDR blob 버전/주파수 교체 (v1.27 → 벤더 추출 blob 순)
5. 부팅 확인 후 `rockusb` 동작 검증 (`u-boot` 프롬프트에서 `rockusb 0 mmc 0` → OPI에서 `rkdeveloptool ld`)

## 9. 교훈 (재발 방지)

- **검증되지 않은 부트로더를 실기기에 먼저 올리지 말 것.** 커널/루트fs는 SD·USB·네트워크 등
  비파괴 경로로 먼저 검증하고, 부트로더는 ①벤더 DDR blob 사용 ②`rockusb` 포함 ③DDR 파라미터 대조를
  모두 만족한 뒤에만 교체한다.
- 플래시 전 **MaskROM 진입 수단(하드웨어)** 을 먼저 확보한다. 복구 수단 없는 상태의 부트로더 교체는 금지.
- 커널 빌드 중단은 `kill -9` 금지 (증분 빌드 오염 → `make clean` 필요).
- Armbian userpatches 경로: 커널 패치는 `userpatches/kernel/<KERNELPATCHDIR>/`,
  u-boot 패치는 `userpatches/u-boot/<UBOOT_GIT_PATCHDIR>/`.

---

*이 문서는 작업 진행에 따라 갱신합니다. 최초 작성 2026-11-09 20:50 KST.*
