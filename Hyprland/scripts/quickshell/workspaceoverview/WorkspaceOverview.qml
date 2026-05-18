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
    readonly property color green: _theme.green
    readonly property color red: _theme.red
    readonly property color peach: _theme.peach

    property var workspaceData: []
    property bool dataLoaded: false

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) Qt.quit();
    }

    // Fetch workspace data
    Process {
        id: dataFetcher
        command: ["bash", "-c", "~/.config/hypr/scripts/fetch_workspaces.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let raw = this.text.trim();
                    // Find JSON in output (might have debug output mixed in)
                    let jsonStart = raw.indexOf('[');
                    if (jsonStart >= 0) {
                        root.workspaceData = JSON.parse(raw.substring(jsonStart));
                        root.dataLoaded = true;
                    }
                } catch(e) {
                    console.log("Workspace parse error:", e);
                }
            }
        }
    }

    // Background overlay
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)

        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
        }
    }

    // Workspace grid
    Rectangle {
        id: gridCard
        anchors.centerIn: parent
        width: Math.min(root.s(900), parent.width * 0.85)
        height: Math.min(root.s(500), parent.height * 0.7)
        radius: root.s(16)
        color: root.crust
        border.width: 1
        border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)

        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 32 }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(16)
            spacing: root.s(12)

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "⃞ Workspace Overview"
                    font.family: "Outfit"
                    font.pixelSize: root.s(22)
                    font.weight: Font.Bold
                    color: root.text
                }
                Text {
                    text: "Click to switch · Esc to close"
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(11)
                    color: root.subtext0
                    Layout.alignment: Qt.AlignRight
                }
            }

            // Workspace grid
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.s(10)
                color: root.surface0
                clip: true

                GridView {
                    id: wsGrid
                    anchors.fill: parent
                    anchors.margins: root.s(8)
                    cellWidth: (parent.width - root.s(24)) / 3
                    cellHeight: root.s(130)
                    model: root.workspaceData
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        width: wsGrid.cellWidth - root.s(8)
                        height: wsGrid.cellHeight - root.s(8)
                        radius: root.s(12)
                        color: modelData.isactive ? root.mauve : (delegateMouse.containsMouse ? root.surface2 : root.surface1)
                        border.width: modelData.isactive ? 2 : 0
                        border.color: modelData.isactive ? Qt.lighter(root.mauve, 1.3) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        scale: delegateMouse.containsMouse ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutExpo } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(10)
                            spacing: root.s(4)

                            // Workspace number + windows count
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: modelData.isactive ? "●" : "○"
                                    font.pixelSize: root.s(14)
                                    color: modelData.isactive ? root.base : root.subtext0
                                }
                                Text {
                                    text: "Workspace " + modelData.id
                                    font.family: "Outfit"
                                    font.pixelSize: root.s(15)
                                    font.weight: Font.Bold
                                    color: modelData.isactive ? root.base : root.text
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.windows + " win"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(11)
                                    color: modelData.isactive ? root.base : root.subtext0
                                }
                            }

                            // Window list
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: root.s(8)
                                color: Qt.rgba(0, 0, 0, modelData.isactive ? 0.2 : 0.15)
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: root.s(6)
                                    spacing: root.s(3)

                                    Repeater {
                                        model: modelData.windowlist || []
                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.s(4)
                                            Text {
                                                text: modelData.floating ? "⧉" : "▬"
                                                font.pixelSize: root.s(10)
                                                color: modelData.isactive ? root.base : root.peach
                                            }
                                            Text {
                                                text: modelData.class || modelData.title || "Window"
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: root.s(10)
                                                color: modelData.isactive ? Qt.rgba(1,1,1,0.8) : root.subtext0
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Rectangle {
                                                visible: modelData.fullscreen
                                                width: root.s(8); height: root.s(8); radius: root.s(4)
                                                color: root.red
                                            }
                                        }
                                    }

                                    // Empty workspace
                                    Item {
                                        Layout.fillHeight: true
                                        visible: (modelData.windowlist || []).length === 0
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Empty"
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(12)
                                            color: root.subtext0
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: delegateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Qt.execDetached(["bash", "-c", "hyprctl dispatch workspace " + modelData.id]);
                                Qt.quit();
                            }
                        }
                    }
                }
            }
        }
    }
}
