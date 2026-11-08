pragma Singleton
import QtQuick

// 토스 앱 느낌의 디자인 토큰: 회색 바탕 + 흰 카드 + 파란 포인트, 큰 굵은 제목, 넉넉한 여백.
// (토스 로고/에셋은 쓰지 않음 — 색/간격/모서리 언어만 따름)
QtObject {
    property real u: 100                 // 기본 단위 = 화면 높이/12 (main.qml 에서 바인딩)
    readonly property color bg: "#F2F4F6"
    readonly property color card: "#FFFFFF"
    readonly property color text: "#191F28"
    readonly property color sub: "#6B7684"
    readonly property color hint: "#8B95A1"
    readonly property color blue: "#3182F6"
    readonly property color blueDown: "#1B64DA"
    readonly property color blueLight: "#E8F3FF"
    readonly property color blueLightDown: "#D3E8FF"
    readonly property color red: "#F04452"
    readonly property color redLight: "#FFEBEE"
    readonly property color off: "#E5E8EB"
    readonly property color offText: "#B0B8C1"
    readonly property string family: "NanumGothic"
    readonly property real radius: u * 0.3
}
