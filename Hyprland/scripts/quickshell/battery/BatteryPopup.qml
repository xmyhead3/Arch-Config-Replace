import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    // --- RECEIVE THE DBUS LIST FROM MAIN.QML ---
    property var notifModel

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        // Uses the physical screen width so the popup scales synchronously with the TopBar
        currentWidth: Screen.width
    }
    
    // Helper function scoped to the root Item for easy access in deeply nested elements and Canvases
    function s(val) { 
        return scaler.s(val); 
    }

    // -------------------------------------------------------------------------
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color green: _theme.green
    readonly property color teal: _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue

    // -------------------------------------------------------------------------
    // STATE & POLLING
    // -------------------------------------------------------------------------
    property int batCapacity: 0
    property string batStatus: "Unknown"
    property string powerProfile: "balanced"
    
    property int upHours: 0
    property int upMins: 0

    property real sysVolume: 0
    property bool sysMuted: false
    property real sysBrightness: 0
    
    property string currentUserName: ""
    
    property bool dndEnabled: false
    property bool clickRippleActive: false
    property real clickRippleTime: 0
    property bool isDraggingCore: false
    property real dragStartY: 0
    property real dragStartBrightness: 0

    // State object for collapsible notification groups
    property var collapsedGroups: ({})

    function toggleGroup(groupName) {
        let temp = Object.assign({}, collapsedGroups);
        temp[groupName] = !temp[groupName];
        collapsedGroups = temp;
    }

    function isCollapsed(groupName) {
        return collapsedGroups[groupName] === true;
    }

    // Anti-Jitter Sync States
    property bool isDraggingVol: false
    property bool isDraggingBri: false

    Timer { id: volSyncDelay; interval: 800; onTriggered: window.isDraggingVol = false; triggeredOnStart: true; }
    Timer { id: briSyncDelay; interval: 800; onTriggered: window.isDraggingBri = false; triggeredOnStart: true; }

    readonly property bool isCharging: batStatus === "Charging"

    // Unified hue for Battery
    readonly property color batColorStart: {
        if (isCharging) return window.green;
        if (batCapacity >= 70) return window.blue;
        if (batCapacity >= 30) return window.yellow;
        return window.red;
    }
    readonly property color batColorEnd: Qt.lighter(batColorStart, 1.15)

    // Unified hue for Performance Profile
    readonly property color profileStart: {
        if (powerProfile === "performance") return window.red;
        if (powerProfile === "power-saver") return window.green;
        return window.blue;
    }
    readonly property color profileEnd: Qt.lighter(profileStart, 1.15)

    // Ambient Blobs - Based strictly on aesthetic pairs derived from battery state
    readonly property color ambientPrimary: window.batColorStart
    readonly property color ambientSecondary: {
        if (isCharging) return window.sapphire;
        if (batCapacity >= 70) return window.mauve;
        if (batCapacity >= 30) return window.peach;
        return window.maroon; 
    }

    property real animCapacity: 0
    Behavior on animCapacity { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }
    
    onAnimCapacityChanged: batCanvas.requestPaint()
    onBatColorStartChanged: batCanvas.requestPaint()

    Timer {
        id: liquidTimer
        interval: 33
        running: true
        repeat: true
        onTriggered: batCanvas.requestPaint()
    }

    // --- INIT DND STATE FROM CACHE ---
    Process {
        id: dndInit
        running: true
        command: ["bash", "-c", "mkdir -p ~/.cache && cat ~/.cache/qs_dnd 2>/dev/null || echo '0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.dndEnabled = (this.text.trim() === "1");
            }
        }
    }

    Process {
        id: userPoller
        command: ["bash", "-c", "echo $USER"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                window.currentUserName = this.text.trim();
            }
        }
    }

    Process {
        id: sysPoller
        command: ["bash", "-c", 
            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo 'Unknown'; " +
            "powerprofilesctl get 2>/dev/null || echo 'balanced'; " +
            "awk '{print int($1/3600)\"h \"int(($1%3600)/60)\"m\"}' /proc/uptime 2>/dev/null || echo '0h 0m'; " +
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100), ($3==\"[MUTED]\"?\"off\":\"on\")}' || echo '0 on'; " +
            "brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 1, length($4)-1)}' || echo '0'"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 6) {
                    if (window.batCapacity !== parseInt(lines[0])) {
                        window.batCapacity = parseInt(lines[0]);
                        window.animCapacity = window.batCapacity;
                    }
                    window.batStatus = lines[1];
                    window.powerProfile = lines[2];
                    
                    let upParts = lines[3].split("h ");
                    if (upParts.length === 2) {
                        window.upHours = parseInt(upParts[0]) || 0;
                        window.upMins = parseInt(upParts[1].replace("m", "")) || 0;
                    }

                    if (!window.isDraggingVol) {
                        let volParts = (lines[4] || "0 on").trim().split(" ");
                        window.sysVolume = parseInt(volParts[0]) || 0;
                        window.sysMuted = (volParts[1] === "off");
                    }
                    
                    if (!window.isDraggingBri) {
                        window.sysBrightness = parseInt(lines[5]) || 0;
                    }
                }
            }
        }
    }
    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true;
        onTriggered: sysPoller.running = true
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }

    // --- ENHANCED STARTUP ANIMATION STATES ---
    property real introMain: 0
    property real introTop: 0
    property real introNotifs: 0
    property real introCore: 0
    property real introSliders: 0
    property real introActions: 0
    property real introProfiles: 0

    ParallelAnimation {
        running: true

        // Base window fades, scales, and lifts
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }

        // Top bar drops in
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTop"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        // Notification List cascades in smoothly
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: window; property: "introNotifs"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuart }
        }

        // Central core pops out and breathes
        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: window; property: "introCore"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        // Hardware sliders slide up
        SequentialAnimation {
            PauseAnimation { duration: 350 }
            NumberAnimation { target: window; property: "introSliders"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }
        }

        // Actions waterfall
        SequentialAnimation {
            PauseAnimation { duration: 450 }
            NumberAnimation { target: window; property: "introActions"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        }

        // Power profiles finish the wave
        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: window; property: "introProfiles"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: window; property: "introMain"; to: 0; duration: 400; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introTop"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introNotifs"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introCore"; to: 0; duration: 350; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introSliders"; to: 0; duration: 250; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introActions"; to: 0; duration: 200; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introProfiles"; to: 0; duration: 150; easing.type: Easing.InQuart }
    }

    // Helper: Safely clear an entire group of notifications by AppName
    function clearGroup(appName) {
        if (!notifModel) return;
        for (let i = notifModel.count - 1; i >= 0; i--) {
            if (notifModel.get(i).appName === appName) {
                notifModel.remove(i);
            }
        }
    }

    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        scale: 0.92 + (0.08 * introMain)
        opacity: introMain
        transform: Translate { y: window.s(15) * (1 - introMain) }

        // Unified Outer Background
        Rectangle {
            anchors.fill: parent
            radius: window.s(20)
            color: window.base
            border.color: window.surface0 
            border.width: 1
            clip: true

            // Rotating Background Blobs - Spanning across the whole widget natively
            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
                opacity: 0.08
                color: window.ambientPrimary
                Behavior on color { ColorAnimation { duration: 1000 } }
            }
            
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
                opacity: 0.06
                color: window.ambientSecondary
                Behavior on color { ColorAnimation { duration: 1000 } }
            }

            RowLayout {
                anchors.fill: parent
                spacing: window.s(15) // Seamless separation instead of a line

                // ==========================================
                // LEFT SIDE: NOTIFICATION CENTER
                // ==========================================
                Item {
                    Layout.preferredWidth: window.s(320)
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(20)
                        spacing: window.s(15)

                        // --- Notification Header & DND Toggle ---
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(38)
                            spacing: window.s(12)
                            
                            transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                            opacity: introTop

                            Text {
                                text: "Notifications"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: window.s(18)
                                color: window.text
                            }

                            Item { Layout.fillWidth: true } // Spacer

                            // DND Toggle Button
                            Rectangle {
                                Layout.preferredWidth: dndMa.containsMouse ? window.s(38) + dndText.implicitWidth + window.s(8) : window.s(38)
                                Layout.preferredHeight: window.s(38)
                                radius: window.s(12)
                                color: window.dndEnabled ? Qt.alpha(window.red, 0.15) : (dndMa.containsMouse ? window.surface1 : "transparent")
                                border.color: window.dndEnabled ? window.red : (dndMa.containsMouse ? window.surface2 : "transparent")
                                border.width: 1
                                clip: true

                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: window.s(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: window.s(8)

                                    Text {
                                        id: dndText
                                        text: window.dndEnabled ? "Silent" : "Mute"
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(13)
                                        color: window.dndEnabled ? window.red : window.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: dndMa.containsMouse ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }

                                    Text {
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(18)
                                        color: window.dndEnabled ? window.red : (dndMa.containsMouse ? window.text : window.overlay0)
                                        text: window.dndEnabled ? "󰂛" : "󰂚"
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    id: dndMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        window.dndEnabled = !window.dndEnabled;
                                        Quickshell.execDetached(["sh", "-c", "mkdir -p ~/.cache && echo '" + (window.dndEnabled ? "1" : "0") + "' > ~/.cache/qs_dnd"]);
                                    }
                                }
                            }
                        }

                        // --- Zero State ---
                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: "JetBrains Mono"
                            font.weight: Font.Medium
                            font.pixelSize: window.s(14)
                            color: window.overlay0
                            text: "You're all caught up."
                            visible: !notifModel || notifModel.count === 0
                            opacity: introNotifs
                        }

                        // --- Notification List ---
                        ListView {
                            id: notifList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: window.notifModel
                            spacing: window.s(8)
                            clip: true
                            
                            opacity: introNotifs
                            transform: Translate { y: window.s(20) * (1 - introNotifs) }

                            ScrollBar.vertical: ScrollBar {
                                active: notifList.moving || notifList.movingVertically
                                width: window.s(4)
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: window.s(4); radius: window.s(2); color: window.surface2 }
                            }

                            // Fluid Animations
                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutQuint }
                                    NumberAnimation { property: "x"; from: window.s(-40); to: 0; duration: 500; easing.type: Easing.OutExpo }
                                    NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 500; easing.type: Easing.OutBack }
                                }
                            }
                            remove: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0.0; duration: 300; easing.type: Easing.OutQuint }
                                    NumberAnimation { property: "scale"; to: 0.9; duration: 300; easing.type: Easing.OutQuint }
                                }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "y"; duration: 400; easing.type: Easing.OutExpo }
                            }

                            // --- Grouping Configuration ---
                            section.property: "appName"
                            section.criteria: ViewSection.FullString
                            section.delegate: Item {
                                width: ListView.view.width
                                height: window.s(46)
                                
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: window.s(10)
                                    anchors.bottomMargin: window.s(4)
                                    color: headerMa.containsMouse ? window.surface1 : "transparent"
                                    radius: window.s(8)
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: window.s(6)
                                        anchors.rightMargin: window.s(6)
                                        spacing: window.s(8)

                                        // Clickable Area for Collapse Toggle
                                        MouseArea {
                                            id: headerMa
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.toggleGroup(section)

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: window.s(8)
                                                
                                                Text {
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: window.s(14)
                                                    color: window.mauve
                                                    text: window.isCollapsed(section) ? "󰅂" : "󰅀"
                                                    Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                                }

                                                Text {
                                                    text: section.toUpperCase()
                                                    font.family: "JetBrains Mono"
                                                    font.weight: Font.Black
                                                    font.pixelSize: window.s(11)
                                                    color: window.text
                                                    Layout.fillWidth: true
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }
                                        }

                                        // Clear Group Button
                                        Rectangle {
                                            Layout.preferredWidth: window.s(26)
                                            Layout.preferredHeight: window.s(26)
                                            radius: window.s(13)
                                            color: groupClearMa.containsMouse ? window.surface2 : "transparent"
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            Text {
                                                anchors.centerIn: parent
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: window.s(14)
                                                color: groupClearMa.containsMouse ? window.red : window.overlay0
                                                text: "󰅖"
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            MouseArea {
                                                id: groupClearMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: window.clearGroup(section)
                                            }
                                        }
                                    }
                                }
                            }

                            // --- Individual Notification Card ---
                            delegate: Item {
                                id: delegateWrapper
                                width: ListView.view.width
                                property bool isHidden: window.isCollapsed(model.appName)
                                height: isHidden ? 0 : innerCard.height
                                visible: height > 0
                                opacity: isHidden ? 0 : 1
                                clip: true
                                
                                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                Rectangle {
                                    id: innerCard
                                    width: parent.width
                                    height: cardContent.height + window.s(24)
                                    radius: window.s(14)
                                    color: cardHover.containsMouse ? window.surface1 : window.surface0
                                    border.color: cardHover.containsMouse ? window.surface2 : "transparent"
                                    border.width: 1
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    MouseArea {
                                        id: cardHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    // Left side accent stripe
                                    Rectangle {
                                        width: window.s(4)
                                        height: parent.height
                                        anchors.left: parent.left
                                        color: window.ambientPrimary
                                    }

                                    ColumnLayout {
                                        id: cardContent
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: window.s(14)
                                        anchors.leftMargin: window.s(18) // make room for the accent stripe
                                        spacing: window.s(6)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: window.s(8)

                                            Text {
                                                text: model.summary || "Notification"
                                                font.family: "JetBrains Mono"
                                                font.weight: Font.Bold
                                                font.pixelSize: window.s(13)
                                                color: window.text
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                            }

                                            // Individual Dismiss Button
                                            Rectangle {
                                                Layout.preferredWidth: window.s(22)
                                                Layout.preferredHeight: window.s(22)
                                                radius: window.s(11)
                                                color: itemClearMa.containsMouse ? Qt.alpha(window.red, 0.15) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: window.s(12)
                                                    color: itemClearMa.containsMouse ? window.red : window.overlay0
                                                    text: "󰅖"
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }

                                                MouseArea {
                                                    id: itemClearMa
                                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if(window.notifModel) window.notifModel.remove(index);
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            text: model.body || ""
                                            font.family: "JetBrains Mono"
                                            font.weight: Font.Medium
                                            font.pixelSize: window.s(11)
                                            color: window.subtext0
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            visible: text !== ""
                                            textFormat: Text.PlainText 
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // RIGHT SIDE: HARDWARE & BATTERY CORE
                // ==========================================
                Item {
                    Layout.preferredWidth: window.s(480)
                    Layout.fillHeight: true

                    // Radar Rings (Centered on the Hardware Panel so it aligns perfectly with the gauge)
                    Item {
                        anchors.fill: parent
                        
                        Repeater {
                            model: 3
                            Rectangle {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: window.s(-70)
                                width: window.s(320) + (index * window.s(170))
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: window.ambientSecondary
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 1000 } }
                                opacity: 0.06 - (index * 0.02)
                            }
                        }
                    }

                    // TOP: UPTIME COMPONENT
                    Row {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: window.s(25)
                        spacing: window.s(6)
                        
                        transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                        opacity: introTop
                        
                        // Hours Box
                        Rectangle {
                            width: window.s(44); height: window.s(48); radius: window.s(10)
                            color: window.surface0; border.color: window.surface1; border.width: 1
                            
                            Rectangle { anchors.fill: parent; radius: window.s(10); color: window.ambientPrimary; opacity: 0.05; Behavior on color { ColorAnimation { duration: 1000 } } }
                            Column {
                                anchors.centerIn: parent
                                Text { 
                                    text: window.upHours.toString().padStart(2, '0')
                                    font.pixelSize: window.s(18); font.family: "JetBrains Mono"; font.weight: Font.Black
                                    color: window.ambientPrimary
                                    Behavior on color { ColorAnimation { duration: 1000 } }
                                    anchors.horizontalCenter: parent.horizontalCenter 
                                }
                                Text { 
                                    text: "HR"; font.pixelSize: window.s(8); font.family: "JetBrains Mono"; font.weight: Font.Bold
                                    color: window.subtext0; anchors.horizontalCenter: parent.horizontalCenter 
                                }
                            }
                        }

                        // Pulsing Colon
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ":"
                            font.pixelSize: window.s(22); font.family: "JetBrains Mono"; font.weight: Font.Black
                            color: window.ambientPrimary
                            Behavior on color { ColorAnimation { duration: 1000 } }
                            
                            opacity: uptimePulse
                            property real uptimePulse: 1.0
                            SequentialAnimation on uptimePulse {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { to: 0.2; duration: 800; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                            }
                        }

                        // Mins Box
                        Rectangle {
                            width: window.s(44); height: window.s(48); radius: window.s(10)
                            color: window.surface0; border.color: window.surface1; border.width: 1
                            
                            Rectangle { anchors.fill: parent; radius: window.s(10); color: window.ambientSecondary; opacity: 0.05; Behavior on color { ColorAnimation { duration: 1000 } } }
                            Column {
                                anchors.centerIn: parent
                                Text { 
                                    text: window.upMins.toString().padStart(2, '0')
                                    font.pixelSize: window.s(18); font.family: "JetBrains Mono"; font.weight: Font.Black
                                    color: window.ambientSecondary
                                    Behavior on color { ColorAnimation { duration: 1000 } }
                                    anchors.horizontalCenter: parent.horizontalCenter 
                                }
                                Text { 
                                    text: "MIN"; font.pixelSize: window.s(8); font.family: "JetBrains Mono"; font.weight: Font.Bold
                                    color: window.subtext0; anchors.horizontalCenter: parent.horizontalCenter 
                                }
                            }
                        }
                    }

                    // Expanding top-right logout icon
                    Rectangle {
                        id: logoutBtn
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.margins: window.s(25)
                        width: logoutMa.containsMouse ? window.s(44) + usernameText.implicitWidth + window.s(12) : window.s(44)
                        height: window.s(44); radius: window.s(14)
                        color: logoutMa.containsMouse ? window.surface1 : "transparent"
                        border.color: logoutMa.containsMouse ? window.surface2 : "transparent"
                        clip: true
                        
                        transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                        opacity: introTop

                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: window.s(13)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: window.s(12)

                            Text {
                                id: usernameText
                                text: window.currentUserName
                                font.family: "JetBrains Mono"
                                font.weight: Font.Bold
                                font.pixelSize: window.s(14)
                                color: window.text
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: logoutMa.containsMouse ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                            }

                            Text {
                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                color: logoutMa.containsMouse ? window.red : window.overlay0
                                text: "󰍃"
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: logoutMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { 
                                exitAnim.start(); // Trigger graceful UI exit
                                Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/exit.sh"]); 
                                Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]); 
                            }
                        }
                    }

                    // CENTRAL CORE & BATTERY RING 
                    Item {
                        anchors.fill: parent
                        z: 1
                        
                        opacity: introCore
                        transform: Translate { y: window.s(25) * (1 - introCore) }
                        scale: 0.9 + (0.1 * introCore)

                        // AMETHYST GLOW HALOS
                        Rectangle {
                            anchors.centerIn: centralCore
                            width: centralCore.width + window.s(80)
                            height: width
                            radius: width / 2
                            color: window.mauve
                            opacity: 0.06
                            z: 0
                            SequentialAnimation on scale {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { to: 1.04; duration: 3000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 3000; easing.type: Easing.InOutSine }
                            }
                        }
                        Rectangle {
                            anchors.centerIn: centralCore
                            width: centralCore.width + window.s(45)
                            height: width
                            radius: width / 2
                            color: centralCore.isDangerState ? window.red : window.ambientPrimary
                            opacity: (centralCore.isDangerState ? 0.25 : 0.15) + (heroMa.containsMouse ? 0.12 : 0.0)
                            z: 0
                            Behavior on color { ColorAnimation { duration: 400 } }
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            SequentialAnimation on scale {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { to: heroMa.containsMouse ? 1.15 : 1.08; duration: heroMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: heroMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                            }
                        }

                        Rectangle {
                            id: centralCore
                            width: window.s(260)
                            height: width
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: window.s(-70)
                            radius: width / 2
                            z: 1

                            property bool isDangerState: !window.isCharging && window.batCapacity < 15
                            
                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                running: true
                                NumberAnimation { 
                                    to: heroMa.containsMouse ? 1.05 : (centralCore.isDangerState ? 1.04 : 1.01)
                                    duration: heroMa.containsMouse ? 1200 : (centralCore.isDangerState ? 600 : 2500)
                                    easing.type: Easing.InOutSine 
                                }
                                NumberAnimation { 
                                    to: 1.0
                                    duration: heroMa.containsMouse ? 1200 : (centralCore.isDangerState ? 600 : 2500)
                                    easing.type: Easing.InOutSine 
                                }
                            }

                            border.color: Qt.rgba(0.7, 0.53, 1.0, 0.15)
                            border.width: 1

                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: window.surface1 }
                                GradientStop { position: 1.0; color: window.base }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: window.maroon
                                opacity: centralCore.isDangerState ? 0.15 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 1000 } }
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite; running: centralCore.isDangerState
                                    NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.15; duration: 600; easing.type: Easing.InOutSine }
                                }
                            }

                            Item {
                                anchors.fill: parent
                                
                                property real textPulse: 0.0
                                SequentialAnimation on textPulse {
                                    loops: Animation.Infinite; running: true
                                    NumberAnimation { from: 0.0; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1.0; to: 0.0; duration: 1200; easing.type: Easing.InOutSine }
                                }
                                
                                property real pumpPhase: 0.0
                                NumberAnimation on pumpPhase {
                                    running: heroMa.containsMouse && window.isCharging
                                    loops: Animation.Infinite
                                    from: 0.0; to: 1.0; duration: 1200
                                    easing.type: Easing.InOutSine 
                                    onStopped: batCanvas.requestPaint()
                                }
                                
                                property real dischargePhase: 1.0
                                NumberAnimation on dischargePhase {
                                    running: heroMa.containsMouse && !window.isCharging
                                    loops: Animation.Infinite
                                    from: 1.0; to: 0.0; duration: 1600
                                    easing.type: Easing.InOutSine
                                    onStopped: batCanvas.requestPaint()
                                }
                                
                                onPumpPhaseChanged: { if(heroMa.containsMouse && window.isCharging) batCanvas.requestPaint() }
                                onDischargePhaseChanged: { if(heroMa.containsMouse && !window.isCharging) batCanvas.requestPaint() }
                                
                                Canvas {
                                    id: batCanvas
                                    anchors.fill: parent
                                    rotation: 180 
                                    
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        
                                        // LIQUID WAVE FILL (rotated space: y=0 = visual bottom)
                                        var lt = Date.now() / 1500;
                                        var liqPct = window.animCapacity / 100;
                                        var liqSurface = height * liqPct;
                                        var turbulence = 0.5 + 0.5 * (Math.sin(lt * 2.7) * Math.sin(lt * 1.3 + 1) * Math.cos(lt * 0.9 + 2));
                                        var waveAmp = window.s(window.animCapacity < 20 && !window.isCharging ? 10 : 4) * (0.8 + 0.3 * turbulence);
                                        var waveSteps = 24;
                                        var ccx = width / 2, ccy = height / 2;
                                        var ringR = (width / 2) - window.s(18);

                                        var wf = function(wi) {
                                            return (Math.sin(lt * 1.5 + wi * 0.5) * 0.5
                                                  + Math.sin(lt + wi * 0.3) * 0.3
                                                  + Math.sin(lt * 0.5 + wi * 0.7) * 0.2) * waveAmp;
                                        };

                                        var liqGrad = ctx.createLinearGradient(0, liqSurface + waveAmp, 0, 0);
                                        liqGrad.addColorStop(0, Qt.lighter(window.batColorStart, 1.15).toString());
                                        liqGrad.addColorStop(0.3, window.mauve.toString());
                                        liqGrad.addColorStop(0.6, window.batColorStart.toString());
                                        liqGrad.addColorStop(1, Qt.darker(window.batColorEnd, 1.25).toString());

                                        ctx.save();
                                        ctx.beginPath();
                                        ctx.arc(ccx, ccy, ringR, 0, Math.PI * 2);
                                        ctx.clip();

                                        // depth layers
                                        if (liqPct > 0.02) {
                                            var dlAlphas = [0.06, 0.04];
                                            var dlSpeeds = [0.6, 0.8];
                                            var dlAmps = [waveAmp * 0.7, waveAmp * 0.5];
                                            var dlOffs = [0.3, 0.6];
                                            for (var di = 0; di < 2; di++) {
                                                var ds = Math.min(1, liqPct * (1 + dlOffs[di]));
                                                var dy = height * ds;
                                                ctx.beginPath();
                                                ctx.moveTo(0, height);
                                                ctx.lineTo(0, dy + Math.sin(lt * dlSpeeds[di]) * dlAmps[di]);
                                                for (var dxi = 1; dxi <= waveSteps; dxi++) {
                                                    var dwf = (Math.sin(lt * dlSpeeds[di] * 1.5 + dxi * 0.5) * 0.5
                                                             + Math.sin(lt * dlSpeeds[di] + dxi * 0.3) * 0.3) * dlAmps[di];
                                                    ctx.lineTo((dxi / waveSteps) * width, dy + dwf);
                                                }
                                                ctx.lineTo(width, height);
                                                ctx.closePath();
                                                ctx.fillStyle = Qt.darker(window.batColorStart, 1.3 + di * 0.2).toString();
                                                ctx.globalAlpha = dlAlphas[di];
                                                ctx.fill();
                                            }
                                            ctx.globalAlpha = 1.0;
                                        }

                                        ctx.fillStyle = liqGrad;
                                        ctx.beginPath();
                                        ctx.moveTo(0, 0);
                                        ctx.lineTo(0, liqSurface + wf(0));
                                        for (var li = 1; li <= waveSteps; li++) {
                                            ctx.lineTo((li / waveSteps) * width, liqSurface + wf(li));
                                        }
                                        ctx.lineTo(width, 0);
                                        ctx.closePath();
                                        ctx.fill();

                                        // specular highlight band
                                        ctx.fillStyle = liqGrad;
                                        ctx.globalAlpha = 0.25;
                                        ctx.beginPath();
                                        ctx.moveTo(0, liqSurface + wf(0) - window.s(6));
                                        for (var sj = 0; sj <= waveSteps; sj++) {
                                            ctx.lineTo((sj / waveSteps) * width, liqSurface + wf(sj) - window.s(6));
                                        }
                                        ctx.lineTo(width, liqSurface + wf(waveSteps));
                                        ctx.lineTo(0, liqSurface + wf(0));
                                        ctx.closePath();
                                        ctx.fill();
                                        ctx.globalAlpha = 1.0;

                                        // liquid shimmer band
                                        var shimmerX = ((lt * 0.3) % 1.0) * width;
                                        var shimmerW = window.s(15);
                                        var shimmerIdx = Math.max(0, Math.min(waveSteps, waveSteps * (shimmerX / width)));
                                        var shimmerYOff = wf(shimmerIdx);
                                        ctx.beginPath();
                                        ctx.moveTo(shimmerX - shimmerW, Math.max(0, liqSurface + shimmerYOff - window.s(20)));
                                        ctx.lineTo(shimmerX + shimmerW, Math.max(0, liqSurface + shimmerYOff - window.s(20)));
                                        ctx.lineTo(shimmerX + shimmerW + window.s(5), Math.max(0, liqSurface + shimmerYOff + window.s(5)));
                                        ctx.lineTo(shimmerX - shimmerW - window.s(5), Math.max(0, liqSurface + shimmerYOff + window.s(5)));
                                        ctx.closePath();
                                        ctx.fillStyle = "#ffffff";
                                        ctx.globalAlpha = 0.06 + 0.04 * (0.5 + 0.5 * Math.sin(lt * 0.5));
                                        ctx.fill();
                                        ctx.globalAlpha = 1.0;

                                        // surface foam
                                        var foamCount = 10;
                                        for (var fi = 0; fi < foamCount; fi++) {
                                            var ffx = (fi / foamCount) * width + Math.sin(lt * 0.5 + fi) * window.s(8);
                                            var ffwf = wf(Math.max(0, Math.min(waveSteps, waveSteps * (ffx / width))));
                                            var ffy = liqSurface + ffwf - window.s(1 + Math.sin(lt + fi * 1.7) * 1.5);
                                            var ffs = window.s(1 + Math.sin(lt * 0.7 + fi * 2.3) * 0.8);
                                            ctx.beginPath();
                                            ctx.arc(ffx, ffy, ffs, 0, Math.PI * 2);
                                            ctx.fillStyle = window.batColorEnd.toString();
                                            ctx.globalAlpha = 0.15 + 0.1 * Math.sin(lt * 0.5 + fi);
                                            ctx.fill();
                                        }
                                        ctx.globalAlpha = 1.0;

                                        // floating embers
                                        var emberCount = 5;
                                        for (var ei = 0; ei < emberCount; ei++) {
                                            var ePhase = ((lt * 0.12 + ei * 0.55) % 1.0);
                                            var ex = ccx + Math.sin(lt * 0.3 + ei * 1.3) * ringR * 0.45;
                                            var ey = ccy + ringR * 0.6 - ePhase * ringR * 1.2;
                                            var es = window.s(1 + Math.sin(lt * 0.4 + ei * 2.0) * 0.8);
                                            var eAlpha = Math.min(ePhase * 2, (1 - ePhase) * 2);
                                            eAlpha = Math.min(eAlpha, 0.6);
                                            ctx.beginPath();
                                            ctx.arc(ex, ey, es, 0, Math.PI * 2);
                                            ctx.fillStyle = window.mauve.toString();
                                            ctx.globalAlpha = eAlpha * 0.6;
                                            ctx.fill();
                                            ctx.beginPath();
                                            ctx.arc(ex, ey, es * 2.5, 0, Math.PI * 2);
                                            ctx.fillStyle = window.mauve.toString();
                                            ctx.globalAlpha = eAlpha * 0.15;
                                            ctx.fill();
                                        }
                                        ctx.globalAlpha = 1.0;

                                        // pulse ripples
                                        var rippleIntervals = [3.0, 4.2];
                                        for (var ri = 0; ri < rippleIntervals.length; ri++) {
                                            var rPhase = ((lt / rippleIntervals[ri]) % 1.0);
                                            if (rPhase < 0.35) {
                                                var rr = (rPhase / 0.35) * ringR;
                                                var ra = (1 - rPhase / 0.35) * 0.12;
                                                ctx.beginPath();
                                                ctx.arc(ccx, ccy, rr, 0, Math.PI * 2);
                                                ctx.strokeStyle = window.mauve.toString();
                                                ctx.lineWidth = window.s(1.5);
                                                ctx.globalAlpha = ra;
                                                ctx.stroke();
                                            }
                                        }
                                        ctx.globalAlpha = 1.0;

                                        // click ripple
                                        if (window.clickRippleActive) {
                                            var crPhase = 1.0 - (Date.now() - window.clickRippleTime) / 800;
                                            if (crPhase > 0) {
                                                var crr = (1 - crPhase) * ringR;
                                                var cra = crPhase * 0.25;
                                                ctx.beginPath();
                                                ctx.arc(ccx, ccy, crr, 0, Math.PI * 2);
                                                ctx.strokeStyle = window.mauve.toString();
                                                ctx.lineWidth = window.s(3);
                                                ctx.globalAlpha = cra;
                                                ctx.stroke();
                                            }
                                        }
                                        ctx.globalAlpha = 1.0;

                                        // lava lamp blobs
                                        var blbTime = Date.now() / 2000;
                                        var blbColors = [window.ambientPrimary, window.ambientSecondary, window.mauve];
                                        for (var bi = 0; bi < 3; bi++) {
                                            var bx = ccx + Math.sin(blbTime * 0.5 + bi * 2.094) * ringR * 0.35;
                                            var by = ccy + Math.cos(blbTime * 0.7 + bi * 2.094) * ringR * 0.25 + window.s(10);
                                            var br = window.s(18 + Math.sin(blbTime + bi * 2.094) * 6);
                                            var bg = ctx.createRadialGradient(bx, by, 0, bx, by, br);
                                            bg.addColorStop(0, Qt.lighter(blbColors[bi % 3], 1.3).toString());
                                            bg.addColorStop(1, blbColors[bi % 3].toString());
                                            ctx.beginPath();
                                            ctx.arc(bx, by, br, 0, Math.PI * 2);
                                            ctx.fillStyle = bg;
                                            ctx.globalAlpha = 0.3 + 0.15 * Math.sin(blbTime + bi);
                                            ctx.fill();
                                        }
                                        ctx.globalAlpha = 1.0;

                                        // charging bubbles
                                        if (window.isCharging) {
                                            var bbTime = Date.now() / 1000;
                                            var bbCount = 8;
                                            for (var bu = 0; bu < bbCount; bu++) {
                                                var bo = (bu / bbCount) * 3.0;
                                                var bp = ((bbTime * 0.8 + bo) % 3.0) / 3.0;
                                                var by2 = ccy + ringR - (bp * ringR * 2);
                                                var bx2 = ccx + Math.sin(bbTime * 1.2 + bu * 0.8) * ringR * 0.3;
                                                var bs = window.s(2 + Math.sin(bu + bbTime * 0.5) * 1.5);
                                                var ba = (1 - bp) * 0.5;
                                                if (by2 > ccy - ringR && by2 < ccy + ringR) {
                                                    ctx.beginPath();
                                                    ctx.arc(bx2, by2, bs, 0, Math.PI * 2);
                                                    ctx.fillStyle = window.batColorEnd.toString();
                                                    ctx.globalAlpha = ba;
                                                    ctx.fill();
                                                    ctx.beginPath();
                                                    ctx.arc(bx2 - bs * 0.3, by2 - bs * 0.3, bs * 0.3, 0, Math.PI * 2);
                                                    ctx.fillStyle = "#ffffff";
                                                    ctx.globalAlpha = ba * 0.5;
                                                    ctx.fill();
                                                }
                                            }
                                        }
                                        ctx.globalAlpha = 1.0;
                                        ctx.restore();

                                        // RING
                                        var centerX = width / 2;
                                        var centerY = height / 2;
                                        var radius = (width / 2) - window.s(18); 
                                        var endAngle = (window.animCapacity / 100) * 2 * Math.PI;
                                        
                                        ctx.lineCap = "round";
                                        
                                        ctx.lineWidth = window.s(8);
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
                                        ctx.strokeStyle = window.surface1;
                                        ctx.stroke();

                                        // Amethyst crystal under-glow ring
                                        ctx.lineWidth = window.s(6);
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius + window.s(3), 0, 2 * Math.PI);
                                        ctx.strokeStyle = window.mauve.toString();
                                        ctx.globalAlpha = 0.12;
                                        ctx.stroke();
                                        ctx.globalAlpha = 1.0;

                                        ctx.lineWidth = window.s(6);
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius - window.s(3), 0, 2 * Math.PI);
                                        ctx.strokeStyle = window.mauve.toString();
                                        ctx.globalAlpha = 0.08;
                                        ctx.stroke();
                                        ctx.globalAlpha = 1.0;
                                        
                                        var fillGrad = ctx.createLinearGradient(0, height, width, 0);
                                        fillGrad.addColorStop(0, window.mauve.toString());
                                        fillGrad.addColorStop(0.5, window.batColorStart.toString());
                                        fillGrad.addColorStop(1, window.batColorEnd.toString());

                                        ctx.globalAlpha = 1.0;
                                        ctx.lineWidth = window.s(14);
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius, 0, endAngle);
                                        ctx.strokeStyle = fillGrad;
                                        ctx.stroke();

                                        // ring plasma sweep
                                        var plasmaAngle = (lt * 0.4) % (Math.PI * 2);
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius, plasmaAngle - 0.4, plasmaAngle + 0.4);
                                        ctx.lineWidth = window.s(18);
                                        ctx.strokeStyle = window.mauve.toString();
                                        ctx.globalAlpha = 0.12 + 0.05 * Math.sin(lt * 0.3);
                                        ctx.stroke();
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius, plasmaAngle - 0.1, plasmaAngle + 0.1);
                                        ctx.lineWidth = window.s(22);
                                        ctx.strokeStyle = window.batColorEnd.toString();
                                        ctx.globalAlpha = 0.25 + 0.1 * Math.sin(lt * 0.5);
                                        ctx.stroke();
                                        ctx.globalAlpha = 1.0;

                                        if (heroMa.containsMouse && endAngle > 0.1) {
                                            if (window.isCharging) {
                                                var surgeAngle = parent.pumpPhase * (endAngle + 0.6) - 0.3;
                                                if (surgeAngle > 0 && surgeAngle < endAngle) {
                                                    var sStart = Math.max(0, surgeAngle - 0.4);
                                                    var sEnd = Math.min(endAngle, surgeAngle + 0.4);
                                                    ctx.beginPath();
                                                    ctx.arc(centerX, centerY, radius, sStart, sEnd);
                                                    ctx.lineWidth = window.s(22);
                                                    ctx.strokeStyle = window.batColorStart.toString();
                                                    ctx.globalAlpha = 0.5 * Math.sin(parent.pumpPhase * Math.PI);
                                                    ctx.stroke();

                                                    sStart = Math.max(0, surgeAngle - 0.2);
                                                    sEnd = Math.min(endAngle, surgeAngle + 0.2);
                                                    ctx.beginPath();
                                                    ctx.arc(centerX, centerY, radius, sStart, sEnd);
                                                    ctx.lineWidth = window.s(28);
                                                    ctx.strokeStyle = window.batColorEnd.toString();
                                                    ctx.globalAlpha = 0.8 * Math.sin(parent.pumpPhase * Math.PI);
                                                    ctx.stroke();
                                                }
                                                
                                                if (parent.pumpPhase > 0.7) {
                                                    var flarePhase = (parent.pumpPhase - 0.7) / 0.3;
                                                    var hitX = centerX + Math.cos(endAngle) * radius;
                                                    var hitY = centerY + Math.sin(endAngle) * radius;
                                                    ctx.beginPath();
                                                    ctx.arc(hitX, hitY, window.s(7) + (flarePhase * window.s(15)), 0, 2*Math.PI);
                                                    ctx.fillStyle = window.batColorEnd.toString();
                                                    ctx.globalAlpha = (1.0 - flarePhase) * 0.6;
                                                    ctx.fill();
                                                }
                                            } else {
                                                var drainCenter = parent.dischargePhase * endAngle;
                                                for (var d = 0; d < 2; d++) {
                                                    var dSpread = 0.2 + (d * 0.15);
                                                    var dStart = Math.max(0, drainCenter - dSpread);
                                                    var dEnd = Math.min(endAngle, drainCenter + dSpread);
                                                    
                                                    if (dStart < dEnd) {
                                                        ctx.beginPath();
                                                        ctx.arc(centerX, centerY, radius, dStart, dEnd);
                                                        ctx.lineWidth = window.s(14) + (1 - d) * window.s(2);
                                                        ctx.strokeStyle = window.batColorEnd.toString();
                                                        ctx.globalAlpha = 0.2 * Math.sin(parent.dischargePhase * Math.PI);
                                                        ctx.stroke();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: window.s(-2)
                                
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: window.s(8)
                                    
                                    Text {
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(28)
                                        color: window.isCharging || window.batCapacity < 30 ? window.batColorStart : window.mauve
                                        text: window.isCharging ? "󰂄" : (window.batCapacity > 20 ? "󰁹" : "󰂃")
                                        Behavior on color { ColorAnimation { duration: 400 } }
                                    }
                                    
                                    Text {
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: window.s(54)
                                        color: window.text
                                        text: Math.round(window.animCapacity) + "%" 
                                    }
                                }

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredHeight: window.s(26)
                                    Layout.preferredWidth: statusText.implicitWidth + window.s(20)
                                    radius: window.s(13)
                                    color: window.isCharging ? Qt.rgba(0.18, 0.65, 0.35, 0.25) : (centralCore.isDangerState ? Qt.rgba(0.8, 0.15, 0.15, 0.2) : "transparent")
                                    Behavior on color { ColorAnimation { duration: 300 } }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: window.isCharging ? Qt.lighter(window.green, 1.5) : (centralCore.isDangerState ? Qt.lighter(window.red, 1.5) : "transparent")
                                        opacity: parent.parent.textPulse * 0.3
                                    }

                                    Text {
                                        id: statusText
                                        anchors.centerIn: parent
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: window.s(12)
                                        color: window.isCharging ? window.crust : (centralCore.isDangerState ? window.red : window.subtext0)
                                        text: window.batStatus.toUpperCase()
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: heroMa
                            anchors.fill: centralCore
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: batCanvas.requestPaint()
                            onExited: batCanvas.requestPaint()
                            onClicked: {
                                window.clickRippleActive = true;
                                window.clickRippleTime = Date.now();
                                clickRippleTimer.restart();
                            }
                            onPressed: (mouse) => {
                                window.isDraggingCore = true;
                                window.dragStartY = mouse.y;
                                window.dragStartBrightness = window.sysBrightness;
                            }
                            onPositionChanged: (mouse) => {
                                if (window.isDraggingCore && pressed) {
                                    var deltaY = window.dragStartY - mouse.y;
                                    var pctChange = Math.round((deltaY / centralCore.height) * 100);
                                    var nb = Math.max(0, Math.min(100, window.dragStartBrightness + pctChange));
                                    window.sysBrightness = nb;
                                    Quickshell.execDetached(["brightnessctl", "set", nb + "%"]);
                                }
                            }
                            onReleased: {
                                window.isDraggingCore = false;
                            }
                        }

                        Timer {
                            id: clickRippleTimer
                            interval: 800
                            onTriggered: window.clickRippleActive = false
                        }
                    }

                    // BOTTOM DOCKS
                    ColumnLayout {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: window.s(25)
                        spacing: window.s(15)

                        // 1. HARDWARE CONTROLS DOCK (Sliders)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(96)
                            radius: window.s(14)
                            color: window.surface0
                            border.color: window.surface1
                            border.width: 1

                            opacity: introSliders
                            transform: Translate { y: window.s(20) * (1.0 - introSliders) }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: window.s(14)
                                spacing: window.s(12)

                                // Brightness Slider
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: window.s(15)

                                    Item {
                                        Layout.preferredWidth: window.s(32)
                                        Layout.preferredHeight: window.s(32)
                                        Text {
                                            anchors.centerIn: parent
                                            text: window.sysBrightness > 66 ? "󰃠" : (window.sysBrightness > 33 ? "󰃟" : "󰃞")
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(22)
                                            color: window.ambientPrimary
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        height: window.s(18)
                                        
                                        Timer {
                                            id: briCmdThrottle
                                            interval: 50
                                            property int targetPct: -1
                                            onTriggered: {
                                                if (targetPct >= 0) {
                                                    Quickshell.execDetached(["brightnessctl", "set", targetPct + "%"]);
                                                    targetPct = -1;
                                                }
                                            }
                                        }

                                        Rectangle {
                                            height: parent.height + window.s(6)
                                            width: (parent.width * (window.sysBrightness / 100)) + window.s(12)
                                            radius: window.s(12)
                                            anchors.verticalCenter: parent.verticalCenter
                                            opacity: 0.2
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: window.mauve; Behavior on color { ColorAnimation { duration: 300 } } }
                                                GradientStop { position: 0.5; color: window.batColorStart; Behavior on color { ColorAnimation { duration: 300 } } }
                                                GradientStop { position: 1.0; color: window.batColorEnd; Behavior on color { ColorAnimation { duration: 300 } } }
                                            }
                                            Behavior on width { enabled: !window.isDraggingBri; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: window.s(9)
                                            color: window.surface1
                                            border.color: window.surface2
                                            border.width: 1
                                            clip: true

                                            Rectangle {
                                                height: parent.height
                                                width: parent.width * (window.sysBrightness / 100)
                                                radius: window.s(9)
                                                opacity: briMa.containsMouse ? 1.0 : 0.85
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                Behavior on width { enabled: !window.isDraggingBri; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: window.mauve; Behavior on color { ColorAnimation { duration: 300 } } }
                                                    GradientStop { position: 0.5; color: window.batColorStart; Behavior on color { ColorAnimation { duration: 300 } } }
                                                    GradientStop { position: 1.0; color: window.batColorEnd; Behavior on color { ColorAnimation { duration: 300 } } }
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: briMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onPressed: (mouse) => { briSyncDelay.stop(); window.isDraggingBri = true; updateBri(mouse.x); }
                                            onPositionChanged: (mouse) => { if (pressed) updateBri(mouse.x); }
                                            onReleased: { briSyncDelay.restart(); }
                                            
                                            function updateBri(mx) {
                                                let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                                window.sysBrightness = pct; 
                                                briCmdThrottle.targetPct = pct;
                                                if (!briCmdThrottle.running) briCmdThrottle.start();
                                            }
                                        }
                                    }
                                }

                                // Volume Slider
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: window.s(15)

                                    Rectangle {
                                        Layout.preferredWidth: window.s(32)
                                        Layout.preferredHeight: window.s(32)
                                        radius: window.s(16)
                                        color: volIconMa.containsMouse ? window.surface1 : "transparent"
                                        border.color: volIconMa.containsMouse ? window.profileStart : "transparent"
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: window.sysMuted || window.sysVolume === 0 ? "󰖁" : (window.sysVolume > 50 ? "󰕾" : "󰖀")
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(22)
                                            color: window.sysMuted ? window.overlay0 : window.profileStart
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        MouseArea {
                                            id: volIconMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                volSyncDelay.stop();
                                                window.isDraggingVol = true; 
                                                window.sysMuted = !window.sysMuted;
                                                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                                volSyncDelay.restart();
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        height: window.s(18)
                                        
                                        Timer {
                                            id: volCmdThrottle
                                            interval: 50
                                            property int targetPct: -1
                                            onTriggered: {
                                                if (targetPct >= 0) {
                                                    if (targetPct > 0 && window.sysMuted) {
                                                        window.sysMuted = false;
                                                        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
                                                    }
                                                    Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", targetPct + "%"]);
                                                    targetPct = -1;
                                                }
                                            }
                                        }

                                        Rectangle {
                                            height: parent.height + window.s(6)
                                            width: (parent.width * (window.sysVolume / 100)) + window.s(12)
                                            radius: window.s(12)
                                            anchors.verticalCenter: parent.verticalCenter
                                            opacity: window.sysMuted ? 0.05 : 0.2
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: window.sysMuted ? window.surface2 : window.profileStart; Behavior on color { ColorAnimation { duration: 300 } } }
                                                GradientStop { position: 1.0; color: window.sysMuted ? Qt.lighter(window.surface2, 1.15) : window.profileEnd; Behavior on color { ColorAnimation { duration: 300 } } }
                                            }
                                            Behavior on width { enabled: !window.isDraggingVol; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: window.s(9)
                                            color: window.surface1
                                            border.color: window.surface2
                                            border.width: 1
                                            clip: true

                                            Rectangle {
                                                height: parent.height
                                                width: parent.width * (window.sysVolume / 100)
                                                radius: window.s(9)
                                                opacity: window.sysMuted ? 0.5 : (volMa.containsMouse ? 1.0 : 0.85)
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                Behavior on width { enabled: !window.isDraggingVol; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: window.sysMuted ? window.surface2 : window.profileStart; Behavior on color { ColorAnimation { duration: 300 } } }
                                                    GradientStop { position: 1.0; color: window.sysMuted ? Qt.lighter(window.surface2, 1.15) : window.profileEnd; Behavior on color { ColorAnimation { duration: 300 } } }
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: volMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onPressed: (mouse) => { volSyncDelay.stop(); window.isDraggingVol = true; updateVol(mouse.x); }
                                            onPositionChanged: (mouse) => { if (pressed) updateVol(mouse.x); }
                                            onReleased: { volSyncDelay.restart(); }
                                            
                                            function updateVol(mx) {
                                                let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                                window.sysVolume = pct;
                                                volCmdThrottle.targetPct = pct;
                                                if (!volCmdThrottle.running) volCmdThrottle.start();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 2. SYSTEM ACTIONS DOCK
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(75)
                            spacing: window.s(12)
                            
                            Repeater {
                                model: ListModel {
                                    ListElement { cmd: "bash ~/.config/hypr/scripts/lock.sh"; icon: ""; baseColor: "mauve"; weight: 1.0 }
                                    ListElement { cmd: "bash ~/.config/hypr/scripts/lock.sh & systemctl suspend"; icon: "ᶻ 𝗓 𝗓"; baseColor: "blue"; weight: 1.0 }
                                    ListElement { cmd: "systemctl reboot"; icon: "󰑓"; baseColor: "yellow"; weight: 2.5 }
                                    ListElement { cmd: "systemctl poweroff -i"; icon: ""; baseColor: "red"; weight: 3.5 }
                                }
                                
                                delegate: Rectangle {
                                    id: actionCapsule
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: window.s(14)

                                    opacity: introActions
                                    transform: Translate { y: window.s(30) * (1.0 - introActions) + (index * window.s(12) * (1.0 - introActions)) }
                                    
                                    property color c1: window[baseColor] || window.surface1
                                    property color c2: Qt.lighter(c1, 1.2)

                                    color: actionMa.containsMouse ? window.surface1 : window.surface0
                                    border.color: actionMa.containsMouse ? c1 : window.surface2
                                    border.width: actionMa.containsMouse ? 2 : 1
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }
                                    
                                    scale: actionMa.pressed ? (0.98 - (0.01 * weight)) : (actionMa.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }

                                    property real fillLevel: 0.0
                                    property bool triggered: false
                                    property real flashOpacity: 0.0
                                    
                                    Canvas {
                                        id: actionWaveCanvas
                                        anchors.fill: parent
                                        
                                        property real wavePhase: 0.0
                                        NumberAnimation on wavePhase {
                                            running: actionCapsule.fillLevel > 0.0 && actionCapsule.fillLevel < 1.0
                                            loops: Animation.Infinite
                                            from: 0; to: Math.PI * 2; duration: 800
                                        }
                                        onWavePhaseChanged: requestPaint()
                                        Connections { target: actionCapsule; function onFillLevelChanged() { actionWaveCanvas.requestPaint() } }
                                        
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.clearRect(0, 0, width, height);
                                            if (actionCapsule.fillLevel <= 0.001) return;
                                            
                                            var r = window.s(14); 
                                            var fillY = height * (1.0 - actionCapsule.fillLevel);
                                            ctx.save();
                                            ctx.beginPath();
                                            ctx.moveTo(r, 0);
                                            ctx.lineTo(width - r, 0);
                                            ctx.arcTo(width, 0, width, r, r);
                                            ctx.lineTo(width, height - r);
                                            ctx.arcTo(width, height, width - r, height, r);
                                            ctx.lineTo(r, height);
                                            ctx.arcTo(0, height, 0, height - r, r);
                                            ctx.lineTo(0, r);
                                            ctx.arcTo(0, 0, r, 0, r);
                                            ctx.closePath();
                                            ctx.clip(); 
                                            
                                            ctx.beginPath();
                                            ctx.moveTo(0, fillY);
                                            if (actionCapsule.fillLevel < 0.99) {
                                                var waveAmp = window.s(10) * Math.sin(actionCapsule.fillLevel * Math.PI); 
                                                var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                                var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                                ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                                ctx.lineTo(width, height);
                                                ctx.lineTo(0, height);
                                            } else {
                                                ctx.lineTo(width, 0);
                                                ctx.lineTo(width, height);
                                                ctx.lineTo(0, height);
                                            }
                                            ctx.closePath();
                                            
                                            var grad = ctx.createLinearGradient(0, 0, 0, height);
                                            grad.addColorStop(0, actionCapsule.c1.toString());
                                            grad.addColorStop(1, actionCapsule.c2.toString());
                                            ctx.fillStyle = grad;
                                            ctx.fill();
                                            ctx.restore();
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent; radius: window.s(14); color: "#ffffff"
                                        opacity: actionCapsule.flashOpacity
                                        PropertyAnimation on opacity { id: cardFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                                    }

                                    Text { 
                                        anchors.centerIn: parent
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(24)
                                        color: actionMa.containsMouse ? window.text : window.subtext0
                                        text: icon
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    Item {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                        height: actionCapsule.height * actionCapsule.fillLevel
                                        clip: true
                                        
                                        Text { 
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: (actionCapsule.height / 2) - (height / 2) - (actionCapsule.height - parent.height)
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(24)
                                            color: window.crust
                                            text: icon 
                                        }
                                    }

                                    MouseArea {
                                        id: actionMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: actionCapsule.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        
                                        onPressed: { 
                                            if (!actionCapsule.triggered) { 
                                                drainAnim.stop(); 
                                                fillAnim.start(); 
                                            }
                                        }
                                        onReleased: {
                                            if (!actionCapsule.triggered && actionCapsule.fillLevel < 1.0) { 
                                                fillAnim.stop(); 
                                                drainAnim.start(); 
                                            }
                                        }
                                    }

                                    NumberAnimation {
                                        id: fillAnim; target: actionCapsule; property: "fillLevel"; to: 1.0
                                        duration: (550 * weight) * (1.0 - actionCapsule.fillLevel); easing.type: Easing.InSine
                                        onFinished: {
                                            actionCapsule.triggered = true; actionCapsule.flashOpacity = 0.6; cardFlashAnim.start();
                                            exitAnim.start(); exitTimer.start(); // Start graceful exit sequence
                                        }
                                    }
                                    
                                    NumberAnimation {
                                        id: drainAnim; target: actionCapsule; property: "fillLevel"; to: 0.0
                                        duration: 1500 * actionCapsule.fillLevel; easing.type: Easing.OutQuad
                                    }

                                    Timer {
                                        id: exitTimer; interval: 500 
                                        onTriggered: { Quickshell.execDetached(["sh", "-c", cmd]); Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]); }
                                    }
                                }
                            }
                        }

                        // 3. POWER PROFILES DOCK
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(54)
                            radius: window.s(14)
                            color: window.surface0 
                            border.color: window.surface1
                            border.width: 1

                            opacity: introProfiles
                            transform: Translate { y: window.s(20) * (1.0 - introProfiles) }
                            
                            Rectangle {
                                id: sliderPill
                                width: (parent.width - window.s(2)) / 3 
                                height: parent.height - window.s(2)
                                y: window.s(1)
                                radius: window.s(10)
                                x: {
                                    if (window.powerProfile === "performance") return window.s(1);
                                    if (window.powerProfile === "balanced") return width + window.s(1);
                                    return (width * 2) + window.s(1);
                                }
                                
                                Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: window.profileStart; Behavior on color { ColorAnimation{duration:400} } }
                                    GradientStop { position: 1.0; color: window.profileEnd; Behavior on color { ColorAnimation{duration:400} } }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0
                                
                                Repeater {
                                    model: ListModel {
                                        ListElement { name: "performance"; icon: "󰓅"; label: "Perform" } 
                                        ListElement { name: "balanced"; icon: "󰗑"; label: "Balance" }   
                                        ListElement { name: "power-saver"; icon: "󰌪"; label: "Saver" } 
                                    }
                                    
                                    delegate: Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        
                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: window.s(8)
                                            Text {
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                                color: window.powerProfile === name ? window.crust : (profileMa.containsMouse ? window.text : window.subtext0)
                                                text: icon
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            Text {
                                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13)
                                                color: window.powerProfile === name ? window.crust : (profileMa.containsMouse ? window.text : window.subtext0)
                                                text: label
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                        }
                                        
                                        MouseArea {
                                            id: profileMa
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { Quickshell.execDetached(["powerprofilesctl", "set", name]); sysPoller.running = true; }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
