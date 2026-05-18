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
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color mauve: _theme.mauve
    readonly property color blue: _theme.blue
    readonly property color green: _theme.green
    readonly property color red: _theme.red
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow

    property var sysData: ({})

    Keys.onPressed: event => { if (event.key === Qt.Key_Escape) Qt.quit(); }

    function pctColor(val) {
        if (val > 80) return root.red;
        if (val > 50) return root.peach;
        return root.green;
    }

    // Background
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.s(500), parent.width * 0.85)
        height: cardLayout.implicitHeight + root.s(32)
        radius: root.s(16)
        color: root.crust
        border.width: 1; border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)

        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 32 }

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: root.s(16)
            spacing: root.s(12)

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text { text: "󰻠"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(24); color: root.mauve }
                Text { text: "System Monitor"; font.family: "Outfit"; font.pixelSize: root.s(20); font.weight: Font.Bold; color: root.text; Layout.fillWidth: true }
                Text { text: "Esc to close"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
            }

            // CPU Bar
            ColumnLayout {
                Layout.fillWidth: true; spacing: root.s(4)
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "CPU"; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); font.weight: Font.Bold; color: root.text }
                    Text { text: sysData.cpu !== undefined ? sysData.cpu.toFixed(1) + "%" : "..."; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                }
                Rectangle {
                    Layout.fillWidth: true; height: root.s(8); radius: root.s(4); color: root.surface0
                    Rectangle {
                        width: parent.width * Math.min((sysData.cpu || 0) / 100, 1); height: parent.height; radius: root.s(4)
                        color: root.pctColor(sysData.cpu || 0)
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
                Text { text: sysData.cpu_temp !== undefined ? sysData.cpu_temp.toFixed(0) + "°C" : ""; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: sysData.cpu_temp > 80 ? root.red : root.subtext0 }
            }

            // RAM Bar
            ColumnLayout {
                Layout.fillWidth: true; spacing: root.s(4)
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "RAM"; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); font.weight: Font.Bold; color: root.text }
                    Text { text: sysData.mem_used !== undefined ? sysData.mem_used + "MB / " + sysData.mem_total + "MB" : "..."; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                }
                Rectangle {
                    Layout.fillWidth: true; height: root.s(8); radius: root.s(4); color: root.surface0
                    Rectangle {
                        width: parent.width * Math.min((sysData.mem_perc || 0) / 100, 1); height: parent.height; radius: root.s(4)
                        color: root.pctColor(sysData.mem_perc || 0)
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // Disk Bar
            ColumnLayout {
                Layout.fillWidth: true; spacing: root.s(4)
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Disk (/)"; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); font.weight: Font.Bold; color: root.text }
                    Text { text: sysData.disk_root !== undefined ? sysData.disk_root + "%" : "..."; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                }
                Rectangle {
                    Layout.fillWidth: true; height: root.s(8); radius: root.s(4); color: root.surface0
                    Rectangle {
                        width: parent.width * Math.min((sysData.disk_root || 0) / 100, 1); height: parent.height; radius: root.s(4)
                        color: root.pctColor(sysData.disk_root || 0)
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // Info rows
            GridLayout {
                Layout.fillWidth: true
                columns: 2; rowSpacing: root.s(4); columnSpacing: root.s(16)
                Text { text: "Uptime"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                Text { text: sysData.uptime || "..."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text }
                Text { text: "Processes"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                Text { text: sysData.processes !== undefined ? sysData.processes.toString() : "..."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text }
            }

            // Refresh button
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: root.s(120); height: root.s(30); radius: root.s(10)
                color: refreshMouse.containsMouse ? root.surface1 : root.surface0
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: " Refresh"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(13)
                    color: root.blue
                }
                MouseArea {
                    id: refreshMouse; anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        dataFetcher.running = false;
                        dataFetcher.running = true;
                    }
                }
            }
        }

        // Data fetcher
        Process {
            id: dataFetcher
            command: ["bash", "-c", "~/.config/hypr/scripts/fetch_sysmon.sh"]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        let t = this.text.trim();
                        let j = t.indexOf('{');
                        if (j >= 0) root.sysData = JSON.parse(t.substring(j));
                    } catch(e) {}
                }
            }
        }
        Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: { dataFetcher.running = false; dataFetcher.running = true; }
        }
    }
}
