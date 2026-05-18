//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }

    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color mauve: _theme.mauve
    readonly property color blue: _theme.blue

    readonly property string notesFile: StandardPath.home + "/Notes.md"

    // Load existing notes on startup
    property string notesContent: ""

    Process {
        id: loader
        command: ["bash", "-c", "cat '" + root.notesFile + "' 2>/dev/null || echo ''"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.notesContent = this.text;
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            saveAndClose();
        }
    }

    function saveAndClose() {
        // Save notes
        Qt.execDetached(["bash", "-c",
            "cat << 'QNOTES_EOF' > " + root.notesFile + "\n" +
            root.textArea.text + "\n" +
            "QNOTES_EOF"
        ]);
        Qt.quit();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)

        MouseArea {
            anchors.fill: parent
            onClicked: root.saveAndClose()
        }
    }

    Rectangle {
        id: noteCard
        width: Math.min(root.s(600), parent.width * 0.9)
        height: Math.min(root.s(500), parent.height * 0.8)
        anchors.centerIn: parent
        radius: root.s(16)
        color: root.crust
        border.width: 1
        border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(16)
            spacing: root.s(12)

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(8)

                Text {
                    text: "󰗨"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.s(24)
                    color: root.mauve
                }
                Text {
                    text: "Quick Notes"
                    font.family: "Outfit"
                    font.pixelSize: root.s(20)
                    font.weight: Font.Bold
                    color: root.text
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: root.s(34); height: root.s(34)
                    radius: root.s(10)
                    color: saveMouse.containsMouse ? Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.6) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰁨"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: root.s(20)
                        color: root.blue
                    }
                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.saveAndClose()
                    }
                }
                Rectangle {
                    width: root.s(34); height: root.s(34)
                    radius: root.s(10)
                    color: closeMouse.containsMouse ? Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.6) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: root.s(20)
                        color: root.subtext0
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.saveAndClose()
                    }
                }
            }

            // Text editor
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.s(10)
                color: root.surface0
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: root.s(4)
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOn
                    ScrollBar.vertical.width: root.s(8)

                    TextArea {
                        id: textArea
                        text: root.notesContent
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(14)
                        color: root.text
                        selectByMouse: true
                        wrapMode: TextEdit.WordWrap
                        background: null

                        placeholderText: "Type your notes here...\n\n- Ideas\n- Commands\n- Reminders"
                        placeholderTextColor: root.subtext0
                    }
                }
            }

            // Footer
            Text {
                text: "Press Esc to save & close  ·  Saved to ~/Notes.md"
                font.family: "JetBrains Mono"
                font.pixelSize: root.s(11)
                color: root.subtext0
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
