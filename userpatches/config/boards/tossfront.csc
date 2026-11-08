# Rockchip RK3399 hexa core 2GB eMMC - Toss Front 1/1.5 (SUNMI)
BOARD_NAME="Toss Front"
BOARD_VENDOR="sunmi"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
INTRODUCED="2022"
# 보드 전용 U-Boot 없음 -> evb 기반. eMMC(sdhci)/UART2 핀은 RK3399 고정이라 그대로 동작할 것으로 기대 (미검증)
BOOTCONFIG="evb-rk3399_defconfig"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="rockchip/rk3399-tossfront.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS2,1500000 console=tty0"
