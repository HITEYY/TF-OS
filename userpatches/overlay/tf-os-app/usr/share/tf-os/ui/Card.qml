import QtQuick
import QtQuick.Layouts

// 흰 카드. 자식은 내부 ColumnLayout 으로 들어감.
Rectangle {
    id: c
    property real pad: Theme.u * 0.2
    default property alias content: col.data
    color: Theme.card
    radius: Theme.u * 0.4
    implicitHeight: col.implicitHeight + 2 * pad
    ColumnLayout { id: col; anchors { fill: parent; margins: c.pad } spacing: 0 }
}
