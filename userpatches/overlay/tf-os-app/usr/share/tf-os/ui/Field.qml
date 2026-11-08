import QtQuick
import QtQuick.Controls

TextField {
    id: f
    implicitHeight: Theme.u * 1.3
    font.pixelSize: Theme.u * 0.45
    color: Theme.text
    placeholderTextColor: Theme.hint
    leftPadding: Theme.u * 0.4; rightPadding: Theme.u * 0.4
    selectByMouse: true
    background: Rectangle {
        radius: Theme.u * 0.25; color: Theme.bg
        border.width: f.activeFocus ? 2 : 0; border.color: Theme.blue
    }
}
