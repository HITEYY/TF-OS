import QtQuick
import QtQuick.Controls

// 토스식 목록 행: 제목 + 보조 텍스트 + 오른쪽 값/신호/›
Item {
    id: r
    property string title
    property string sub
    property string trail
    property bool chevron: true
    property int strength: -1          // 0~100 이면 신호 막대 표시
    property bool highlight: false
    property color titleColor: Theme.text
    signal clicked()
    implicitHeight: sub !== "" ? Theme.u * 1.6 : Theme.u * 1.3
    implicitWidth: 100

    Rectangle { anchors.fill: parent; radius: Theme.u * 0.25
                color: ma.pressed ? Theme.bg : r.highlight ? Theme.blueLight : "transparent" }
    Column {
        anchors { left: parent.left; leftMargin: Theme.u * 0.3; right: tail.left; rightMargin: Theme.u * 0.2; verticalCenter: parent.verticalCenter }
        spacing: Theme.u * 0.05
        Label { width: parent.width; text: r.title; elide: Text.ElideRight; font.pixelSize: Theme.u * 0.46; font.bold: true; color: r.titleColor }
        Label { width: parent.width; visible: r.sub !== ""; text: r.sub; elide: Text.ElideRight; font.pixelSize: Theme.u * 0.34; color: Theme.hint }
    }
    Row {
        id: tail
        anchors { right: parent.right; rightMargin: Theme.u * 0.3; verticalCenter: parent.verticalCenter }
        spacing: Theme.u * 0.2
        Label { visible: r.trail !== ""; anchors.verticalCenter: parent.verticalCenter; text: r.trail; font.pixelSize: Theme.u * 0.38; color: Theme.sub }
        Row {   // 신호 막대 4개
            visible: r.strength >= 0; height: Theme.u * 0.45; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.u * 0.05
            Repeater {
                model: 4
                delegate: Rectangle {
                    width: Theme.u * 0.1; height: Theme.u * (0.15 + index * 0.1); radius: width / 2
                    y: parent.height - height
                    color: r.strength > index * 25 + 10 ? Theme.blue : Theme.off
                }
            }
        }
        Label { visible: r.chevron; anchors.verticalCenter: parent.verticalCenter; text: "›"; font.pixelSize: Theme.u * 0.7; color: Theme.offText }
    }
    MouseArea { id: ma; anchors.fill: parent; onClicked: r.clicked() }
}
