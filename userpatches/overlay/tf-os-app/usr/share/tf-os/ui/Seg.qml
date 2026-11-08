import QtQuick
import QtQuick.Controls

// 알약형 선택 칩
Row {
    id: r
    property var options: []
    property string current: options.length ? options[0] : ""
    spacing: Theme.u * 0.15
    Repeater {
        model: r.options
        delegate: Rectangle {
            width: lbl.implicitWidth + Theme.u * 0.7; height: Theme.u * 0.85; radius: height / 2
            color: r.current === modelData ? Theme.blue : Theme.bg
            Label { id: lbl; anchors.centerIn: parent; text: modelData; font.pixelSize: Theme.u * 0.36; font.bold: true
                    color: r.current === modelData ? "white" : Theme.sub }
            MouseArea { anchors.fill: parent; onClicked: r.current = modelData }
        }
    }
}
