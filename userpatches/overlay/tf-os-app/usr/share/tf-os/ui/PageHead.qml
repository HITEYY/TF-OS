import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 위: ‹ 뒤로 (+ 오른쪽 액션), 아래: 큰 굵은 제목 (+ 보조 문구)
ColumnLayout {
    id: h
    property string title
    property string sub
    property string action
    property bool back: true
    signal backClicked()
    signal actionClicked()
    spacing: Theme.u * 0.1

    Item {
        Layout.fillWidth: true; Layout.preferredHeight: Theme.u * 0.9
        Label { visible: h.back; text: "‹"; font.pixelSize: Theme.u * 1.0; color: Theme.text
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                MouseArea { anchors { fill: parent; margins: -Theme.u * 0.3 } onClicked: h.backClicked() } }
        Label { visible: h.action !== ""; text: h.action; font.pixelSize: Theme.u * 0.4; font.bold: true; color: Theme.blue
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                MouseArea { anchors { fill: parent; margins: -Theme.u * 0.3 } onClicked: h.actionClicked() } }
    }
    Label { Layout.fillWidth: true; text: h.title; wrapMode: Text.Wrap; font.pixelSize: Theme.u * 0.75; font.bold: true; color: Theme.text }
    Label { Layout.fillWidth: true; visible: h.sub !== ""; text: h.sub; wrapMode: Text.Wrap; font.pixelSize: Theme.u * 0.4; color: Theme.sub }
}
