import QtQuick
import QtQuick.Controls

Switch {
    id: s
    implicitHeight: Theme.u * 1.2
    padding: 0
    rightPadding: Theme.u * 1.3
    contentItem: Label { text: s.text; font.pixelSize: Theme.u * 0.45; color: Theme.text; verticalAlignment: Text.AlignVCenter }
    indicator: Rectangle {
        width: Theme.u * 1.0; height: Theme.u * 0.6; radius: height / 2
        x: s.width - width; y: (s.height - height) / 2
        color: s.checked ? Theme.blue : "#D1D6DB"
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: parent.height - 6; height: width; radius: width / 2; y: 3; color: "white"
            x: s.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }
}
