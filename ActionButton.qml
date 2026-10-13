import QtQuick
import qs.Commons
import qs.Ui

// The panel's one full-width action, after "Add a city" in Omarchy's world
// clock: an outlined row that takes the kit's hover and focus chrome.
BorderSurface {
    id: root

    property string text: ""
    property color foreground: Color.foreground
    property color textColor: foreground
    property color accent: Color.accent
    property string fontFamily: Style.font.family
    readonly property bool hot: mouse.containsMouse

    signal clicked()

    implicitHeight: Style.spacing.controlHeight + Style.spacing.md
    radius: Style.cornerRadius
    color: Style.controlFill(activeFocus, hot, foreground, accent)
    borderSpec: Border.controlSpec(activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"), foreground, accent)
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()

    Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.text
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

}
