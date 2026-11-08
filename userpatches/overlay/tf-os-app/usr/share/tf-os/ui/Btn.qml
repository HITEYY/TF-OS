import QtQuick
import QtQuick.Controls

// kind: primary(파랑) | secondary(연파랑) | danger(연빨강)
Button {
    id: b
    property string kind: "primary"
    implicitHeight: Theme.u * 1.3
    implicitWidth: Theme.u * 2.5
    font.pixelSize: Theme.u * 0.45
    font.bold: true
    scale: down ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

    contentItem: Label {
        text: b.text; font: b.font
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: !b.enabled ? Theme.offText : b.kind === "primary" ? "white" : b.kind === "danger" ? Theme.red : Theme.blue
    }
    background: Rectangle {
        radius: Theme.radius
        color: !b.enabled ? Theme.off
             : b.kind === "primary" ? (b.down ? Theme.blueDown : Theme.blue)
             : b.kind === "danger" ? Theme.redLight
             : (b.down ? Theme.blueLightDown : Theme.blueLight)
    }
}
