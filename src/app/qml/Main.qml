// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Chih
// MaeShare for Nokia N900 / Maemo 5 (Fremantle).
// Plain QtQuick 1.0. Dark Material-3 palette, Fremantle touch sizes, 800x480.
// Every user-visible string goes through i18n.js (string table, 6 languages).
import QtQuick 1.0
import "i18n.js" as I

Rectangle {
    id: app
    width: 800
    height: 480
    color: "#181A1E"
    smooth: true

    property color accent: "#82D5C8"
    property color surface: "#22252A"
    property color textMain: "#E2E4E9"
    property color textMuted: "#8A919E"

    // 仅截图用（--tab-devices=21）：注入几台假设备，检查设备类型图标的样式
    property variant fakeDevices: [
        { "alias": "Blue Phone", "ip": "192.168.1.21", "port": 53317, "deviceType": "mobile", "protocol": "https" },
        { "alias": "Brave Laptop", "ip": "192.168.1.22", "port": 53317, "deviceType": "desktop", "protocol": "https" },
        { "alias": "Localsend Web", "ip": "192.168.1.23", "port": 53317, "deviceType": "web", "protocol": "https" }
    ]

    property string screen: "receive"
    property string previousTab: "receive"
    property bool promptShown: false
    // 接收页的两个浮层：历史（从右滑入）/ 信息（右上角小卡片）
    property bool receiveHistoryOpen: false
    property bool receiveInfoOpen: false

    // 相册「分享到 MaeShare」：文件已进入已选列表，直接切到发送页并重新扫一遍设备
    Connections {
        target: transfer
        onShareReady: {
            app.goTab("send");
            transfer.scan();
        }
    }

    // ------------------------------------------------------------- 语言
    // langTag："system" 或具体语言；tlang：实际生效的语言目录
    property string langTag: transfer.language.length > 0 ? transfer.language : "system"

    function langFamily() {
        return I.resolve(transfer.language.length > 0 ? transfer.language : transfer.systemLanguage);
    }
    function tx(key) { return I.t(app.langFamily(), key); }
    function fm(key, value) { return I.a(app.tx(key), value); }
    // LocalSend 的 deviceType → Material 设备图标（手机 / 电脑 / 平板 / 电视 / 网页 / 服务端）
    function deviceIcon(type) {
        var t = ("" + type).toLowerCase();
        if (t === "mobile") return "icons/device-mobile.svg";
        if (t === "desktop") return "icons/device-desktop.svg";
        if (t === "tablet") return "icons/device-tablet.svg";
        if (t === "tv") return "icons/device-tv.svg";
        if (t === "web") return "icons/device-web.svg";
        if (t === "server" || t === "headless") return "icons/device-server.svg";
        return "icons/device-other.svg";
    }
    function langName(tag) {
        return tag === "system" ? app.tx("language_system") : I.name(tag);
    }
    function chooseLanguage(tag) {
        transfer.language = (tag === "system" ? "" : tag);
        banner.text = app.langName(tag);
        banner.show();
    }

    // ------------------------------------------------------------- 导航状态
    function activeTabName() {
        if (screen === "receive" || screen === "send" || screen === "settings")
            return screen;
        return previousTab;
    }
    function goTab(name) {
        previousTab = name;
        screen = name;
    }
    function pushPage(name) {
        if (screen === "receive" || screen === "send" || screen === "settings")
            previousTab = screen;
        screen = name;
    }
    function goBack() {
        screen = previousTab;
    }
    function pageTitle() {
        if (screen === "language") return app.tx("page_language");
        if (screen === "browser")
            return transfer.pickerMode === "folder" ? app.tx("page_folder")
                 : transfer.pickerMode === "received" ? app.tx("page_received")
                 : transfer.pickerMode === "photos" ? app.tx("page_photos") : app.tx("page_files");
        if (screen === "name") return app.tx("page_name");
        if (screen === "manual") return app.tx("page_manual");
        if (screen === "about") return app.tx("page_about");
        return "MaeShare";
    }
    function fmtSize(n) {
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
        if (n >= 1024) return Math.round(n / 1024) + " KB";
        return n + " B";
    }
    // 接收页副行只显示 IP 末段（192.168.1.21 -> #21），与信息卡片里的完整列表互补
    function ipShort() {
        var a = transfer.localAddress;
        if (a.indexOf(".") < 0) return a;
        return "#" + a.substring(a.lastIndexOf(".") + 1);
    }
    function suffixOf(name) {
        var dot = name.lastIndexOf(".");
        if (dot <= 0) return "?";
        var s = name.substring(dot + 1).toUpperCase();
        if (s.length > 4) s = s.substring(0, 4);
        return s;
    }

    // ------------------------------------------------------------- 左侧导航栏（图标）
    Rectangle {
        id: rail
        width: 110
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        color: "#1F2227"

        Column {
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            FsNavIcon {
                icon: "icons/nav-wifi.svg"
                active: app.activeTabName() === "receive"
                onClicked: app.goTab("receive")
            }
            FsNavIcon {
                icon: "icons/nav-send.svg"
                active: app.activeTabName() === "send"
                onClicked: app.goTab("send")
            }
            FsNavIcon {
                icon: "icons/nav-settings.svg"
                active: app.activeTabName() === "settings"
                onClicked: app.goTab("settings")
            }
        }
    }

    // ------------------------------------------------------------- 内容区
    Item {
        id: contentArea
        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Loader {
            anchors.fill: parent
            sourceComponent: screen === "receive" ? receivePage
                           : screen === "send" ? sendPage
                           : screen === "settings" ? settingsPage
                           : screen === "browser" ? browserPage
                           : screen === "name" ? namePage
                           : screen === "manual" ? manualPage
                           : screen === "about" ? aboutPage
                           : screen === "language" ? languagePage
                           : screen === "text" ? textPage
                           : receivePage
        }
    }

    // ------------------------------------------------------------- 接收页
    Component {
        id: receivePage
        Item {
            anchors.fill: parent

            // 右边缘左滑 → 打开历史（放在最前面，层级最低，不挡右上角图标）
            MouseArea {
                id: historySwipe
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 96
                enabled: !app.receiveHistoryOpen
                property real startX: 0

                onPressed: startX = mouseX
                onReleased: {
                    if (startX - mouseX > 30) app.receiveHistoryOpen = true;
                }
            }

            // 右上角：历史 / 信息
            Row {
                id: receiveIcons
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 2
                anchors.rightMargin: 6
                spacing: 0

                Item {
                    width: 64
                    height: 64

                    Image {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: "icons/history.svg"
                        opacity: historyArea.pressed ? 0.5 : 0.92
                    }
                    MouseArea {
                        id: historyArea
                        anchors.fill: parent
                        onClicked: app.receiveHistoryOpen = true
                    }
                }
                Item {
                    width: 64
                    height: 64

                    Image {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: "icons/info.svg"
                        opacity: infoArea.pressed ? 0.5 : 0.92
                    }
                    MouseArea {
                        id: infoArea
                        anchors.fill: parent
                        onClicked: app.receiveInfoOpen = !app.receiveInfoOpen
                    }
                }
            }

            // 监听中：简单的一颗实心圆 + 一圈向外扩散的波纹（不再有固定外环）
            Rectangle {
                id: pulseRing
                anchors.centerIn: radar
                width: 84
                height: 84
                radius: width / 2
                color: "transparent"
                border.width: 3
                border.color: app.accent
                smooth: true
                opacity: 0.0
                visible: transfer.listening
                scale: 0.96

                SequentialAnimation {
                    id: pulseAnim
                    loops: Animation.Infinite
                    running: false

                    ParallelAnimation {
                        PropertyAnimation { target: pulseRing; property: "scale"; from: 0.96; to: 1.55; duration: 1300; easing.type: Easing.OutQuad }
                        PropertyAnimation { target: pulseRing; property: "opacity"; from: 0.9; to: 0.0; duration: 1300; easing.type: Easing.OutQuad }
                    }
                }
            }

            // 切页会销毁并重建这个组件：Qt Quick 1 里「构造时就 running=true」的动画
            // 不一定会真的跑起来，所以进入页面后显式 start 一次。
            Connections {
                target: transfer
                onChanged: {
                    if (transfer.listening && transfer.active && !pulseAnim.running) {
                        pulseRing.scale = 0.96;
                        pulseAnim.start();
                    } else if ((!transfer.listening || !transfer.active) && pulseAnim.running) {
                        pulseAnim.stop();
                        pulseRing.opacity = 0;
                    }
                }
                // 收到文本消息时直接把内容弹出来（不再让人去找一个 .txt 文件）
                onMessageArrived: {
                    textDlg.titleText = app.tx("text_received");
                    textDlg.bodyText = transfer.receivedText();
                    textDlg.open();
                }
            }
            Component.onCompleted: {
                if (transfer.listening && transfer.active) {
                    pulseRing.scale = 0.96;
                    pulseAnim.start();
                }
            }

            // 监听状态：只有一颗实心圆（圆内是「开 / 关」），点按切换监听
            Item {
                id: radar
                anchors.horizontalCenter: parent.horizontalCenter
                y: 44
                width: 158
                height: 158

                Rectangle {
                    id: radarCore
                    anchors.centerIn: parent
                    width: 84
                    height: 84
                    radius: 42
                    color: transfer.listening ? app.accent : "#2A313A"
                    smooth: true

                    Text {
                        anchors.centerIn: parent
                        text: transfer.listening ? app.tx("on") : app.tx("off")
                        color: transfer.listening ? "#0E2320" : app.textMuted
                        font.pixelSize: 22
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: transfer.listening ? transfer.stopReceive() : transfer.startReceive()
                }
            }

            Text {
                id: deviceName
                anchors.horizontalCenter: parent.horizontalCenter
                y: 196
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: transfer.localName
                color: "#FFFFFF"
                font.pixelSize: 31
                font.bold: true
            }
            Text {
                id: deviceSub
                anchors.horizontalCenter: parent.horizontalCenter
                y: 236
                text: app.ipShort() + " · " + app.tx("port_label")
                color: app.textMuted
                font.pixelSize: 18
            }

            // 只有收到纯文本时才出现的快捷入口
            FsChip {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 272
                visible: transfer.receivedIsText
                text: app.tx("text_received")
                onClicked: {
                    textDlg.titleText = app.tx("text_received");
                    textDlg.bodyText = transfer.receivedText();
                    textDlg.open();
                }
            }

            FsTextDialog {
                id: textDlg
                acceptText: app.tx("close")
            }

            Text {
                id: quickSave
                visible: !transfer.busy
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                text: app.tx("quick_save") + " · " + (transfer.autoSave ? app.tx("on") : app.tx("off"))
                color: transfer.autoSave ? app.accent : app.textMuted
                font.pixelSize: 18

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -16
                    onClicked: transfer.autoSave = !transfer.autoSave
                }
            }

            // 信息小卡片（右上角浮层，点按信息图标切换）
            Rectangle {
                id: infoPanel
                z: 40
                visible: app.receiveInfoOpen
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 50
                anchors.rightMargin: 8
                width: 308
                height: infoBody.height + 30
                radius: 18
                smooth: true
                color: "#232935"
                border.width: 1
                border.color: "#35403D"

                // 卡片自身吃掉点击：否则点卡片会穿透到下层透明遮罩，把卡片关掉。
                // 必须写在内容之前，这样列里的控件仍在它上面。
                MouseArea { anchors.fill: parent; onClicked: {} }

                Column {
                    id: infoBody
                    x: 16
                    y: 15
                    width: parent.width - 32
                    spacing: 9

                    Row {
                        width: parent.width
                        spacing: 10

                        Text {
                            width: 52
                            text: app.tx("info_alias")
                            color: app.textMuted
                            font.pixelSize: 17
                        }
                        Text {
                            width: parent.width - 62
                            text: transfer.localName
                            color: "#FFFFFF"
                            font.pixelSize: 17
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 10

                        Text {
                            width: 52
                            text: app.tx("info_ip")
                            color: app.textMuted
                            font.pixelSize: 17
                        }
                        Text {
                            width: parent.width - 62
                            text: transfer.localAddresses
                            color: "#FFFFFF"
                            font.pixelSize: 17
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 10

                        Text {
                            width: 52
                            text: app.tx("info_port")
                            color: app.textMuted
                            font.pixelSize: 17
                        }
                        Text {
                            width: parent.width - 62
                            text: "53317"
                            color: "#FFFFFF"
                            font.pixelSize: 17
                        }
                    }
                }
            }

            // 点空白处收起信息卡片
            Rectangle {
                z: 30
                anchors.fill: parent
                color: "transparent"
                visible: app.receiveInfoOpen

                MouseArea {
                    anchors.fill: parent
                    onClicked: app.receiveInfoOpen = false
                }
            }

            // 历史：从右侧滑入的整页面板
            Rectangle {
                id: historyPanel
                z: 60
                y: 0
                width: parent.width
                height: parent.height
                radius: 0
                color: "#141619"
                visible: x < width - 0.5
                x: app.receiveHistoryOpen ? 0 : width

                Behavior on x {
                    NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
                }

                // 整页吸收点击：这一层是整屏面板，空白处没写 MouseArea 就会穿透到
                // 下面的接收页（很可能正好点到 Quick save 开关或信息图标）。
                // 放在最前面声明，行与按钮在它之上，照常可点。
                MouseArea { anchors.fill: parent; onClicked: {} }

                // 头部：返回 + 标题
                Item {
                    id: historyHead
                    width: parent.width
                    height: 52

                    Image {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: "icons/arrow-back.svg"
                        opacity: historyBack.pressed ? 0.5 : 0.9
                    }
                    MouseArea {
                        id: historyBack
                        x: 0
                        y: 0
                        width: 58
                        height: 52
                        onClicked: app.receiveHistoryOpen = false
                    }
                    Text {
                        x: 62
                        anchors.verticalCenter: parent.verticalCenter
                        text: app.tx("history")
                        color: "#FFFFFF"
                        font.pixelSize: 24
                        font.bold: true
                    }
                }

                Row {
                    id: historyActions
                    x: 16
                    y: 56
                    spacing: 10

                    FsChip {
                        text: app.tx("history_open_dir")
                        onClicked: {
                            transfer.openReceived();
                            app.receiveHistoryOpen = false;
                            app.pushPage("browser");
                        }
                    }
                    FsChip {
                        text: app.tx("history_clear")
                        onClicked: clearHistoryDialog.open()
                    }
                }

                Flickable {
                    id: historyFlick
                    x: 0
                    y: 112
                    width: parent.width
                    height: parent.height - 112
                    contentWidth: width
                    contentHeight: historyColumn.height + 16
                    clip: true
                    flickableDirection: Flickable.VerticalFlick

                    Column {
                        id: historyColumn
                        x: 16
                        width: historyFlick.width - 32

                        Repeater {
                            model: transfer.history

                            Item {
                                width: historyColumn.width
                                height: 64

                                Text {
                                    id: historyName
                                    x: 0
                                    y: 8
                                    width: parent.width
                                    text: modelData.name
                                    color: "#FFFFFF"
                                    font.pixelSize: 19
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: historyMeta
                                    x: 0
                                    y: 33
                                    width: parent.width
                                    text: modelData.when + " · " + modelData.sizeText + " · " + I.t(app.langFamily(), modelData.peer)
                                    color: app.textMuted
                                    font.pixelSize: 15
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: "#242A33"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (transfer.historyIsText(index)) {
                                            historyTextDialog.titleText = modelData.name;
                                            historyTextDialog.bodyText = transfer.historyTextAt(index);
                                            historyTextDialog.open();
                                        } else {
                                            // 直接交给系统查看器，不再先跳目录再点一次
                                            transfer.openHistoryFile(index);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: transfer.history.length === 0
                    anchors.centerIn: parent
                    text: app.tx("history_empty")
                    color: app.textMuted
                    font.pixelSize: 19
                }
            }

            FsDialog {
                id: clearHistoryDialog
                titleText: app.tx("history_clear")
                message: app.tx("history_clear_q")
                acceptText: app.tx("history_clear")
                rejectText: app.tx("send_cancel")

                onAccepted: transfer.clearHistory()
            }

            FsTextDialog {
                id: historyTextDialog
                acceptText: app.tx("close")
                copyText: app.tx("copy")
            }
        }
    }

    // ------------------------------------------------------------- 发送页
    Component {
        id: sendPage
        Item {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 14

            Text {
                x: 2
                y: 0
                text: app.tx("send_pick")
                color: app.textMain
                font.pixelSize: 22
                font.bold: true
            }

            Row {
                id: cardRow
                x: 0
                y: 30
                width: parent.width
                spacing: 12

                FsActionCard {
                    width: (cardRow.width - 2 * cardRow.spacing) / 3
                    icon: "icons/card-file.svg"
                    title: app.tx("send_files")
                    enabledCard: !transfer.busy
                    onClicked: {
                        transfer.beginPicker("files");
                        app.pushPage("browser");
                    }
                }
                FsActionCard {
                    width: (cardRow.width - 2 * cardRow.spacing) / 3
                    icon: "icons/card-photo.svg"
                    title: app.tx("send_photos")
                    enabledCard: !transfer.busy
                    onClicked: {
                        transfer.beginPicker("photos");
                        app.pushPage("browser");
                    }
                }
                FsActionCard {
                    width: (cardRow.width - 2 * cardRow.spacing) / 3
                    icon: "icons/card-text.svg"
                    title: app.tx("card_text")
                    enabledCard: !transfer.busy
                    onClicked: app.pushPage("text")
                }
            }

            // 已选内容摘要：原来是一行裸文字，清除动作沉在左下角，和内容脱节。
            // 现在收成一条可读的状态条，清除/取消就落在条内右侧。
            Rectangle {
                id: selBar
                x: 0
                y: 124
                width: parent.width
                height: 56
                radius: 14
                smooth: true
                color: "#252932"
                visible: transfer.selectedCount > 0

                Image {
                    id: selTile
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                    source: "icons/file-document.svg"
                }

                Text {
                    id: selName
                    anchors.left: selTile.right
                    anchors.leftMargin: 12
                    anchors.right: selCount.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: I.t(app.langFamily(), transfer.selectedSummary)
                    color: "#FFFFFF"
                    font.pixelSize: 17
                    font.bold: true
                    elide: Text.ElideMiddle
                }

                Text {
                    id: selCount
                    anchors.right: selClear.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: transfer.selectedCount === 1
                    text: app.tx("sel_one")
                    color: app.textMuted
                    font.pixelSize: 15
                }

                Item {
                    id: selClear
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    height: parent.height
                    width: selClearLabel.width + 28

                    Text {
                        id: selClearLabel
                        anchors.centerIn: parent
                        text: transfer.busy ? app.tx("send_cancel") : app.tx("send_clear")
                        color: selClearMouse.pressed ? "#FFFFFF" : app.textMuted
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: selClearMouse
                        anchors.fill: parent
                        onClicked: {
                            if (transfer.busy) transfer.cancel();
                            else transfer.clearSelection();
                        }
                    }
                }
            }

            Row {
                x: 0
                y: 184
                spacing: 6

                Text {
                    text: app.tx("send_nearby")
                    color: app.textMain
                    font.pixelSize: 22
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    width: 60
                    height: 60
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.centerIn: parent
                        width: 34
                        height: 34
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: "icons/refresh.svg"
                        opacity: scanArea.pressed ? 0.45 : 0.9
                    }
                    MouseArea {
                        id: scanArea
                        anchors.fill: parent
                        enabled: !transfer.busy
                        onClicked: transfer.scan()
                    }
                }
                // 手输地址：组播发现不到的设备（跨网段、路由器屏蔽组播）靠这个连
                Item {
                    width: 60
                    height: 60
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.centerIn: parent
                        width: 34
                        height: 34
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: "icons/manual.svg"
                        opacity: manualArea.pressed ? 0.45 : 0.9
                    }
                    MouseArea {
                        id: manualArea
                        anchors.fill: parent
                        enabled: !transfer.busy
                        onClicked: app.pushPage("manual")
                    }
                }
            }

            // 内容还没选：设备列表先不出现，避免「先选设备」的旧习惯
            Rectangle {
                x: 0
                y: 246
                width: parent.width
                height: 104
                radius: 16
                smooth: true
                color: "#22262B"
                visible: false   // 设备列表不再藏在“先选内容”后面

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    text: app.tx("send_pick_first")
                    color: app.textMuted
                    font.pixelSize: 19
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                x: 0
                y: 252
                width: parent.width
                visible: !transfer.busy && transfer.devices.length === 0 && previewTab !== 21
                horizontalAlignment: Text.AlignHCenter
                text: app.tx("send_empty")
                color: app.textMuted
                font.pixelSize: 19
                wrapMode: Text.WordWrap
            }

            ListView {
                id: deviceList
                x: 0
                y: 246
                width: parent.width
                height: parent.height - 246
                clip: true
                spacing: 8
                visible: !transfer.busy || previewTab === 21
                model: previewTab === 21 ? app.fakeDevices : transfer.devices

                delegate: Rectangle {
                    width: deviceList.width
                    height: 72
                    radius: 14
                    smooth: true
                    opacity: transfer.busy ? 0.6 : 1.0
                    color: devMouse.pressed ? "#384152"
                         : (modelData.ip === transfer.host ? "#2C4744" : "#252932")

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Image {
                            width: 34
                            height: 34
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            anchors.verticalCenter: parent.verticalCenter
                            source: app.deviceIcon(modelData.deviceType)
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: modelData.alias
                                color: "#FFFFFF"
                                font.pixelSize: 20
                                font.bold: true
                                elide: Text.ElideRight
                                width: deviceList.width - 150
                            }
                            Row {
                                spacing: 8

                                Rectangle {
                                    width: ipTxt.width + 14
                                    height: 24
                                    radius: 7
                                    color: "#333E3B"

                                    Text {
                                        id: ipTxt
                                        anchors.centerIn: parent
                                        text: modelData.ip
                                        color: app.accent
                                        font.pixelSize: 16
                                    }
                                }
                                Text {
                                    text: modelData.deviceModel ? modelData.deviceModel : app.tx("device_generic")
                                    color: app.textMuted
                                    font.pixelSize: 17
                                    elide: Text.ElideRight
                                    width: deviceList.width - ipTxt.width - 130
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: devMouse
                        anchors.fill: parent
                        enabled: !transfer.busy
                        onClicked: transfer.sendToDevice(index)
                    }
                }
            }

            // 不再需要单独的发发送键：选好内容后点设备就直接发
        }
    }

    // ------------------------------------------------------------- 发送文本页
    Component {
        id: textPage
        Item {
            anchors.fill: parent

            FsTopBar {
                id: textBar
                title: app.tx("page_text")
                backText: app.tx("back")
                onBack: app.goBack()
            }

            Item {
                x: 16
                y: 64
                width: parent.width - 32
                height: parent.height - 76

                Rectangle {
                    id: textBox
                    width: parent.width
                    height: 146
                    radius: 14
                    color: "#252932"
                    border.width: 1
                    border.color: textEdit.activeFocus ? app.accent : "#39414F"

                    Text {
                        x: 16
                        y: 14
                        width: parent.width - 32
                        text: app.tx("text_placeholder")
                        color: "#77839A"
                        font.pixelSize: 20
                        visible: textEdit.text.length === 0
                    }

                    Flickable {
                        id: textFlick
                        anchors.fill: parent
                        anchors.margins: 14
                        contentWidth: width
                        contentHeight: textEdit.height
                        clip: true
                        flickableDirection: Flickable.VerticalFlick

                        Text {
                            id: textMeasure
                            width: textFlick.width
                            visible: false
                            text: textEdit.text.length > 0 ? textEdit.text : " "
                            font.pixelSize: 20
                            wrapMode: Text.WordWrap
                        }

                        TextEdit {
                            id: textEdit
                            width: textFlick.width
                            height: Math.max(textFlick.height, textMeasure.height + 10)
                            color: "#FFFFFF"
                            font.pixelSize: 20
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            focus: true
                            // 页面切入时显式抢焦点：只写 focus: true 时这台机器上
                            // scene 没有焦点项，键盘（和中文输入面板）都不会出现。
                            Component.onCompleted: forceActiveFocus()
                        }
                    }

                    // 没焦点时点一下把焦点交进去；已经有焦点就关掉这层，
                    // 免得挡住 TextEdit 的光标定位和 Flickable 的拖动。
                    MouseArea {
                        anchors.fill: parent
                        enabled: !textEdit.activeFocus
                        onClicked: textEdit.forceActiveFocus()
                    }
                }

                Row {
                    id: textChipRow
                    anchors.top: textBox.bottom
                    anchors.topMargin: 8
                    spacing: 10

                    FsChip {
                        id: textClearChip
                        text: app.tx("send_clear")
                        visible: textEdit.text.length > 0 && !transfer.busy
                        onClicked: textEdit.text = ""
                    }
                    FsChip {
                        text: app.tx("paste")
                        visible: !transfer.busy
                        onClicked: {
                            // 中文靠键盘打不出来时，从剪贴板整段贴进来
                            var t = transfer.clipboardText();
                            if (t.length > 0) {
                                textEdit.text = textEdit.text.length > 0
                                        ? textEdit.text + "\n" + t : t;
                            }
                            textEdit.forceActiveFocus();
                        }
                    }
                }

                Text {
                    id: textDeviceLabel
                    anchors.left: parent.left
                    anchors.top: textChipRow.bottom
                    anchors.topMargin: 10
                    text: app.tx("text_pick_device")
                    color: app.textMain
                    font.pixelSize: 21
                    font.bold: true
                    visible: !transfer.busy
                }

                // 编辑完文本直接点设备就发：不需要先连设备，也没有单独的发送键
                ListView {
                    id: textDeviceList
                    anchors.top: textDeviceLabel.bottom
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    width: parent.width
                    height: parent.height - (textDeviceList.y)
                    clip: true
                    spacing: 8
                    visible: !transfer.busy
                    model: transfer.devices

                    delegate: Rectangle {
                        width: textDeviceList.width
                        height: 60
                        radius: 12
                        smooth: true
                        color: textDevMouse.pressed ? "#384152"
                             : (modelData.ip === transfer.host ? "#2C4744" : "#252932")

                        Image {
                            x: 16
                            width: 26
                            height: 26
                            anchors.verticalCenter: parent.verticalCenter
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            source: app.deviceIcon(modelData.deviceType)
                        }
                        Text {
                            x: 54
                            width: parent.width - 54 - 116
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.alias
                            color: "#FFFFFF"
                            font.pixelSize: 19
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.ip
                            color: app.accent
                            font.pixelSize: 16
                        }
                        MouseArea {
                            id: textDevMouse
                            anchors.fill: parent
                            onClicked: transfer.sendTextToDevice(index, textEdit.text)
                        }
                    }
                }

                Text {
                    anchors.top: textDeviceLabel.bottom
                    anchors.topMargin: 26
                    anchors.left: parent.left
                    anchors.right: parent.right
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    visible: !transfer.busy && transfer.devices.length === 0
                    text: app.tx("send_empty")
                    color: app.textMuted
                    font.pixelSize: 19
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ------------------------------------------------------------- 设置页
    Component {
        id: settingsPage
        Item {
            anchors.fill: parent

            Flickable {
                id: setFlick
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                contentWidth: width
                contentHeight: setCol.height + 16
                clip: true
                flickableDirection: Flickable.VerticalFlick

                Column {
                    id: setCol
                    width: setFlick.width
                    spacing: 14

                    Rectangle {
                        id: setCard
                        width: parent.width
                        height: setInner.height + 28
                        radius: 16
                        smooth: true
                        color: app.surface

                        Column {
                            id: setInner
                            x: 18
                            y: 14
                            width: parent.width - 36
                            spacing: 4

                            Text {
                                text: app.tx("settings_general")
                                color: app.accent
                                font.pixelSize: 19
                                font.bold: true
                            }

                            Item {
                                width: parent.width
                                height: 64

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: app.tx("settings_autosave")
                                    color: app.textMain
                                    font.pixelSize: 21
                                }
                                FsSwitch {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: transfer.autoSave
                                    enabled: !transfer.busy
                                    onToggled: transfer.autoSave = value
                                }
                            }

                            // 保持唤醒：只在传输期间向 MCE 请求「暂缓灭屏」，空闲时完全不占
                            Item {
                                width: parent.width
                                height: 64

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.rightMargin: 96
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Text {
                                        text: app.tx("settings_keepawake")
                                        color: app.textMain
                                        font.pixelSize: 21
                                    }
                                    Text {
                                        text: app.tx("settings_keepawake_hint")
                                        color: app.textMuted
                                        font.pixelSize: 15
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }
                                FsSwitch {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: transfer.keepAwake
                                    onToggled: transfer.keepAwake = value
                                }
                            }

                            FsRow {
                                width: parent.width
                                label: app.tx("settings_savedir")
                                valueText: transfer.receiveDirectory.replace("/home/user/", "~/")
                                onClicked: {
                                    transfer.beginPicker("folder");
                                    app.pushPage("browser");
                                }
                            }
                            FsRow {
                                width: parent.width
                                label: app.tx("settings_devname")
                                valueText: transfer.localName
                                onClicked: app.pushPage("name")
                            }
                            FsRow {
                                width: parent.width
                                label: app.tx("settings_language")
                                valueText: app.langName(app.langTag)
                                onClicked: app.pushPage("language")
                            }
                            FsRow {
                                width: parent.width
                                label: app.tx("settings_about")
                                valueText: app.fm("settings_version", transfer.version)
                                onClicked: app.pushPage("about")
                            }
                        }
                    }

                    // 说明信息：整宽放到页面最底部
                    Column {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: "MaeShare"
                            color: "#FFFFFF"
                            font.pixelSize: 24
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: app.tx("settings_blurb")
                            color: app.textMuted
                            font.pixelSize: 18
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: app.fm("settings_local", transfer.localAddress)
                            color: app.textMain
                            font.pixelSize: 18
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: app.tx("settings_security")
                            color: app.textMuted
                            font.pixelSize: 17
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: app.tx("settings_limits")
                            color: app.textMuted
                            font.pixelSize: 16
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- 语言选择页
    Component {
        id: languagePage
        Item {
            anchors.fill: parent

            FsTopBar {
                id: langBar
                title: app.tx("page_language")
                backText: app.tx("back")
                onBack: app.goBack()
            }

            Flickable {
                id: langFlick
                x: 0
                y: 62
                width: parent.width
                height: parent.height - 62
                contentWidth: width
                contentHeight: langCol.height + 10
                clip: true
                flickableDirection: Flickable.VerticalFlick

                Column {
                    id: langCol
                    x: 0
                    y: 0
                    width: langFlick.width

                    Repeater {
                        model: I.TAGS

                        Rectangle {
                            id: langRow
                            width: langCol.width
                            height: 60
                            smooth: true
                            color: app.langTag === modelData ? "#2A3240"
                                 : (rowMouse.pressed ? "#252932" : (index % 2 === 0 ? "#1B1E23" : "#181A1E"))

                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }

                            Rectangle {
                                x: 0
                                y: 8
                                width: 4
                                height: parent.height - 16
                                radius: 2
                                color: app.accent
                                visible: app.langTag === modelData
                            }

                            Text {
                                x: 20
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 76
                                text: app.langName(modelData)
                                color: app.langTag === modelData ? "#FFFFFF" : app.textMain
                                font.pixelSize: 20
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Image {
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 26
                                smooth: true
                                source: "icons/nav-check-svg.svg"
                                visible: app.langTag === modelData
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                onClicked: app.chooseLanguage(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- 文件浏览页
    Component {
        id: browserPage
        Item {
            anchors.fill: parent

            FsTopBar {
                id: browserBar
                title: app.pageTitle()
                backText: app.tx("back")
                actionText: transfer.pickerMode === "received" ? ""
                          : transfer.pickerMode === "folder" ? app.tx("browser_select_dir")
                          : app.fm("browser_done", transfer.selectedCount)
                onBack: app.goBack()
                onAction: {
                    if (transfer.pickerMode === "folder")
                        transfer.setReceiveDirectory(transfer.folder);
                    app.goBack();
                }
            }

            FsIconChip {
                x: 10
                y: 62
                icon: "icons/arrow-up-accent.svg"
                fallbackText: app.tx("browser_up")
                onClicked: transfer.up()
            }
            Text {
                x: 84
                y: 62
                width: parent.width - 84 - 190
                height: 50
                text: transfer.folder.replace("/home/user/MyDocs", app.tx("files_root"))
                color: app.accent
                font.pixelSize: 17
                elide: Text.ElideLeft
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                y: 62
                height: 50
                width: 178
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: transfer.pickerMode === "received" ? app.tx("browser_tap")
                      : transfer.pickerMode === "folder" ? app.tx("browser_current")
                      : app.fm("browser_selected", transfer.selectedCount)
                color: app.textMuted
                font.pixelSize: 15
                elide: Text.ElideRight
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 80
                horizontalAlignment: Text.AlignHCenter
                visible: transfer.entries.length === 0
                text: app.tx("browser_empty")
                color: app.textMuted
                font.pixelSize: 19
                wrapMode: Text.WordWrap
            }

            ListView {
                id: fileList
                x: 0
                y: 116
                width: parent.width
                height: parent.height - 116
                clip: true
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                // 只在自己的模式下出现：隔壁那个空的 GridView 若留在上面，
                // 会作为一个不可见的 Flickable 把点击和滑动全部吃掉。
                visible: transfer.pickerMode !== "photos"
                enabled: transfer.pickerMode !== "photos"
                model: transfer.pickerMode === "photos" ? [] : transfer.entries

                delegate: Item {
                    width: fileList.width
                    height: 62

                    // 左侧类型图标：直接用图标本身，不加外框。
                    // x=27 / 26 宽 → 图标中心 x≈40，与上方 Up 箭头按钮（60 宽胶囊、中心 x=40）对齐。
                    Image {
                        x: 27
                        width: 26
                        height: 26
                        anchors.verticalCenter: parent.verticalCenter
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: modelData.directory ? "icons/file-folder.svg" : "icons/file-document.svg"
                    }
                    Text {
                        x: 64
                        width: parent.width - 64 - (transfer.pickerMode === "received" ? 40 : 96)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        elide: Text.ElideMiddle
                        font.pixelSize: 19
                        color: "#FFFFFF"
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: transfer.pickerMode === "folder" || transfer.pickerMode === "received" ? 14 : 62
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.directory ? "" : app.fmtSize(modelData.size)
                        color: app.textMuted
                        font.pixelSize: 15
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 14
                        width: parent.width - 28
                        height: 1
                        color: "#282C34"
                    }
                    FsCheckBox {
                        // z 要高于整行 MouseArea（z:3），否则勾选框被行点击吃掉，
                        // 点勾选框等于打开文件，选择功能形同虚设。
                        z: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !modelData.directory && transfer.pickerMode !== "folder" && transfer.pickerMode !== "received"
                        checked: transfer.selectedCount >= 0 && transfer.isSelected(modelData.path)
                        onClicked: transfer.toggleSelection(modelData.path)
                    }
                    MouseArea {
                        z: 3
                        anchors.fill: parent
                        onClicked: transfer.activateEntry(modelData.path)
                    }
                }
            }

            GridView {
                id: photoGrid
                x: 0
                y: 116
                width: parent.width
                height: parent.height - 116
                clip: true
                cellWidth: parent.width / 3
                cellHeight: 176
                visible: transfer.pickerMode === "photos"
                enabled: transfer.pickerMode === "photos"
                model: transfer.pickerMode === "photos" ? transfer.entries : []

                delegate: Item {
                    width: photoGrid.cellWidth
                    height: 176

                    Rectangle {
                        x: 6
                        y: 4
                        width: parent.width - 12
                        height: 124
                        radius: 12
                        color: "#252932"
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: modelData.directory ? "" : "file://" + modelData.path
                            sourceSize.width: 260
                            sourceSize.height: 260
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                            smooth: true
                            asynchronous: true
                            // 缩略图按 260 解码，避免每张照片原尺寸解码吃内存
                        }
                        // 目录格：Material 文件夹图标（与文件列表同一套图标）
                        Image {
                            anchors.centerIn: parent
                            visible: modelData.directory
                            width: 46
                            height: 46
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            source: "icons/file-folder.svg"
                        }
                    }
                    Text {
                        x: 6
                        y: 132
                        width: parent.width - 56
                        height: 20
                        text: modelData.name
                        elide: Text.ElideMiddle
                        font.pixelSize: 15
                        color: app.textMuted
                    }
                    FsCheckBox {
                        // 同上：勾选框必须压在格子点击区之上，否则点不到勾
                        z: 4
                        x: parent.width - 46
                        y: 128
                        visible: !modelData.directory
                        checked: transfer.selectedCount >= 0 && transfer.isSelected(modelData.path)
                        onClicked: transfer.toggleSelection(modelData.path)
                    }
                    MouseArea {
                        z: 3
                        width: parent.width
                        height: 134
                        onClicked: modelData.directory ? transfer.activateEntry(modelData.path)
                                                     : transfer.toggleSelection(modelData.path)
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- 设备名称页
    Component {
        id: namePage
        Item {
            anchors.fill: parent

            FsTopBar {
                id: nameBar
                title: app.tx("page_name")
                backText: app.tx("back")
                actionText: app.tx("name_save")
                onBack: app.goBack()
                onAction: {
                    transfer.setLocalName(nameField.text);
                    app.goBack();
                }
            }

            Column {
                x: 16
                y: 70
                width: 440
                spacing: 14

                Text {
                    text: app.tx("name_hint")
                    color: app.textMuted
                    font.pixelSize: 19
                }
                FsField {
                    id: nameField
                    width: parent.width
                    maximumLength: 50
                    autoFocus: true
                    text: transfer.localName
                }
                Row {
                    width: parent.width
                    spacing: 10

                    FsChip {
                        text: app.tx("name_random")
                        enabled: !transfer.busy
                        onClicked: {
                            nameField.inputItem.focus = false;
                            transfer.regenerateName();
                        }
                    }
                    FsChip {
                        text: app.tx("name_restore")
                        onClicked: nameField.text = transfer.localName
                    }
                    FsChip {
                        text: app.tx("paste")
                        onClicked: {
                            // 键盘不可用时的兜底：从剪贴板取名字。
                            // 必须写 inputItem.text：text 是 alias 且上面挂着
                            // transfer.localName 的绑定，直接赋值会被绑定挡掉。
                            var t = transfer.clipboardText();
                            if (t.length > 0) nameField.inputItem.text = t.substring(0, 50);
                            nameField.inputItem.forceActiveFocus();
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: app.tx("name_note")
                    color: app.textMuted
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ------------------------------------------------------------- 手输地址页
    // 组播发现不到的场景（跨网段、路由器过滤组播、对方只开了网页版）走这里：
    // 填 IP 后由 probe 去 /api/localsend/v2/info 取对方指纹并记住设备。
    Component {
        id: manualPage
        Item {
            anchors.fill: parent

            FsTopBar {
                id: manualBar
                title: app.tx("page_manual")
                backText: app.tx("back")
                onBack: app.goBack()
            }

            Column {
                x: 16
                y: 70
                width: parent.width - 32
                spacing: 14

                Text {
                    width: parent.width
                    text: app.tx("manual_desc")
                    color: app.textMuted
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                }

                FsField {
                    id: manualField
                    width: 448
                    maximumLength: 15
                    autoFocus: true
                    text: transfer.host
                    onTextChanged: transfer.host = text
                }

                Row {
                    spacing: 12

                    FsButton {
                        width: 200
                        fontSize: 19
                        bold: true
                        primary: true
                        text: app.tx("manual_connect")
                        // 不用 enabled: 禁用态在薄荷底上是灰字，对比度太低；
                        // 改成变暗提示，重复点击由 connectManual 里的 working 判断挡掉。
                        opacity: transfer.busy ? 0.55 : 1.0
                        onClicked: {
                            manualField.inputItem.focus = false;
                            transfer.connectManual(manualField.text);
                            app.goBack();
                        }
                    }
                    FsChip {
                        text: app.tx("paste")
                        onClicked: {
                            var t = transfer.clipboardText();
                            // QML 里 QString 已被转成普通 JS 字符串，没有 QString 的方法，
                            // 所以用 JS 原生 replace 去掉首尾空白
                            t = t.replace(/^\s+/, "").replace(/\s+$/, "");
                            // 只取第一行，避免把整段文字当成地址
                            var nl = t.indexOf("\n");
                            if (nl >= 0) t = t.substring(0, nl);
                            // 同名字页：text 上挂着 transfer.host 的绑定，写 inputItem
                            if (t.length > 0) manualField.inputItem.text = t;
                            manualField.inputItem.forceActiveFocus();
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: app.fm("manual_note", transfer.localAddress)
                    color: app.textMuted
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ------------------------------------------------------------- 关于页
    Component {
        id: aboutPage
        Item {
            anchors.fill: parent

            FsTopBar {
                id: aboutBar
                title: app.tx("page_about")
                backText: app.tx("back")
                onBack: app.goBack()
            }

            Flickable {
                x: 0
                y: 62
                width: parent.width
                height: parent.height - 62
                contentWidth: width
                contentHeight: aboutContent.height + 30
                clip: true
                flickableDirection: Flickable.VerticalFlick

                Column {
                    id: aboutContent
                    x: 16
                    width: parent.width - 32
                    spacing: 12

                    Row {
                        spacing: 14

                        Image {
                            source: "icon.png"
                            width: 64
                            height: 64
                            smooth: true
                        }
                        Column {
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: "MaeShare"
                                font.pixelSize: 28
                                font.bold: true
                                color: "#FFFFFF"
                            }
                            Text {
                                text: app.fm("about_version", transfer.version)
                                font.pixelSize: 17
                                color: app.textMuted
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: app.tx("about_d1")
                        font.pixelSize: 19
                        color: app.textMain
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: app.tx("about_d2")
                        font.pixelSize: 17
                        color: app.textMuted
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: app.tx("about_d3")
                        font.pixelSize: 17
                        color: app.textMuted
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: app.tx("about_credits")
                        font.pixelSize: 15
                        color: "#6B727F"
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: app.tx("about_link")
                        font.pixelSize: 15
                        color: "#6B727F"
                    }
                    // 退出走系统顶栏关闭（应用是普通窗口，可切后台），这里不再放退出按钮
                }
            }
        }
    }

    // ------------------------------------------------------------- 弹窗与提示
    Item {
        id: popupHost
        anchors.fill: parent
        z: 1000

        FsBanner {
            id: banner
        }

        FsDialog {
            id: receiveDialog
            titleText: app.tx("dialog_receive")
            message: I.t(app.langFamily(), transfer.offer)
            acceptText: app.tx("dialog_accept")
            rejectText: app.tx("dialog_reject")
            onAccepted: {
                app.promptShown = false;
                transfer.answer(true);
            }
            onRejected: {
                app.promptShown = false;
                transfer.answer(false);
            }
        }

        FsDialog {
            id: completionDialog
            titleText: app.tx("dialog_complete")
            message: I.t(app.langFamily(), transfer.receivedSummary)
            acceptText: transfer.canOpenReceived ? app.tx("dialog_open") : app.tx("dialog_view")
            rejectText: app.tx("dialog_close")
            onAccepted: {
                if (transfer.receivedIsText()) {
                    receivedTextDialog.titleText = app.tx("text_message");
                    receivedTextDialog.bodyText = transfer.receivedText();
                    receivedTextDialog.open();
                } else if (transfer.canOpenReceived) {
                    transfer.openLastReceived();
                } else {
                    transfer.openReceived();
                    app.pushPage("browser");
                }
            }
        }

        // 收到一条 LocalSend 文本消息：直接给可选中 / 可复制的正文，而不是一个文件
        FsTextDialog {
            id: receivedTextDialog
            acceptText: app.tx("close")
            copyText: app.tx("copy")
        }
    }

    Connections {
        target: transfer
        onFeedback: {
            banner.text = I.t(app.langFamily(), text);
            banner.show();
        }
        onReceiveCompleted: {
            if (transfer.receivedIsText()) {
                receivedTextDialog.titleText = app.tx("text_message");
                receivedTextDialog.bodyText = transfer.receivedText();
                receivedTextDialog.open();
            } else {
                completionDialog.open();
            }
        }
        onChanged: {
            if (transfer.offer.length > 0 && !app.promptShown) {
                completionDialog.close();
                app.promptShown = true;
                receiveDialog.open();
            } else if (transfer.offer.length === 0 && app.promptShown) {
                app.promptShown = false;
                receiveDialog.close();
            }
        }
    }

    // 图片查看浮层：收到或历史里的图片直接在这里渲染。
    // 不再启动外部 image-viewer —— 那是一个独立进程（实测约 30MB），在这台 235MB 内存的
    // 机器上经常起不来或起了不切前台，而应用内显示只多一帧解码，零额外进程。
    Rectangle {
        id: imageOverlay
        z: 300
        anchors.fill: parent
        color: "#0B0F0E"
        visible: transfer.previewImage.length > 0

        // QML 里没写 MouseArea 的 Rectangle 不接收点击，事件会穿透到下层的历史列表，
        // 于是点一下图片就等于点了后面某一条记录 —— 表现为「打开后又跳下一张」。
        // 这里铺一层全屏 MouseArea 吃掉点击，预览期间只认右上角的关闭按钮。
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Image {
            id: overlayImage
            anchors.fill: parent
            anchors.topMargin: 60
            anchors.bottomMargin: 14
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            fillMode: Image.PreserveAspectFit
            smooth: true
            // 只在屏幕尺寸上解码：一张 5MP 照片原尺寸解码要 15MB 左右，
            // 按 800x480 解码只要 1MB 出头，235MB 内存的机器差别很大。
            // 但尺寸必须按原图长宽比算（transfer.previewDecode*），否则竖图会被压扁。
            sourceSize.width: transfer.previewDecodeWidth
            sourceSize.height: transfer.previewDecodeHeight
            source: transfer.previewImage.length > 0 ? "file://" + transfer.previewImage : ""
        }

        Rectangle {
            id: imageBar
            anchors.top: parent.top
            width: parent.width
            height: 58
            color: "#161A19"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: imageClose.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                text: transfer.previewImage.length > 0
                      ? transfer.previewImage.substring(transfer.previewImage.lastIndexOf("/") + 1)
                      : ""
                color: app.textMain
                font.pixelSize: 18
            }

            Rectangle {
                id: imageClose
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                height: 50
                radius: 25
                color: imageCloseMouse.pressed ? app.accent : "#2C4744"

                Text {
                    anchors.centerIn: parent
                    text: app.tx("close")
                    color: imageCloseMouse.pressed ? "#0E2320" : app.textMain
                    font.pixelSize: 17
                    font.bold: true
                }
                MouseArea {
                    id: imageCloseMouse
                    anchors.fill: parent
                    onClicked: transfer.closePreview()
                }
            }
        }

        // 解码失败时给一句人话，而不是一块黑屏
        Text {
            anchors.centerIn: parent
            visible: overlayImage.status === Image.Error && transfer.previewImage.length > 0
            text: app.tx("image_failed")
            color: app.textMuted
            font.pixelSize: 19
        }
    }

    // 解不了的格式（WebP / HEIC / AVIF…）：说明文件已经收好、这台机器解不了，而不是黑屏
    Item {
        id: unsupportedOverlay
        z: 320
        anchors.fill: parent
        visible: transfer.unsupportedFormat.length > 0

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.55
        }
        MouseArea { anchors.fill: parent; onClicked: {} }

        Rectangle {
            id: unsupportedCard
            width: 620
            height: unsupportedCol.height + 40
            radius: 18
            smooth: true
            color: app.surface
            anchors.centerIn: parent

            Column {
                id: unsupportedCol
                x: 22
                y: 20
                width: parent.width - 44
                spacing: 12

                Text {
                    width: parent.width
                    text: app.tx("image_unsupported_title").replace("%1", transfer.unsupportedFormat)
                    color: app.accent
                    font.pixelSize: 21
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    text: app.tx("image_unsupported_body").replace("%1", transfer.unsupportedFormat).replace("%2", transfer.unsupportedPath)
                    color: app.textMain
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: 4 }

                Rectangle {
                    width: 132
                    height: 50
                    radius: 25
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: unsupportedCloseMouse.pressed ? app.accent : "#2C4744"

                    Text {
                        anchors.centerIn: parent
                        text: app.tx("close")
                        color: unsupportedCloseMouse.pressed ? "#0E2320" : app.textMain
                        font.pixelSize: 18
                        font.bold: true
                    }
                    MouseArea {
                        id: unsupportedCloseMouse
                        anchors.fill: parent
                        onClicked: transfer.closeUnsupported()
                    }
                }
            }
        }
    }

    // 预览模式（--preview）：直接跳到指定页面，供真机截图检查布局
    Timer {
        id: previewConnect
        interval: 7000
        onTriggered: transfer.connectManual(transfer.host)
    }

    Component.onCompleted: {
        if (previewTab === 1) goTab("send");
        else if (previewTab === 2) goTab("settings");
        else if (previewTab === 3) { goTab("settings"); pushPage("name"); }
        else if (previewTab === 5) { goTab("settings"); pushPage("about"); }
        else if (previewTab === 6) { transfer.beginPicker("photos"); pushPage("browser"); }
        else if (previewTab === 7) { goTab("settings"); transfer.beginPicker("folder"); pushPage("browser"); }
        else if (previewTab === 8) { banner.text = I.t(app.langFamily(), "已接收 3 个文件"); banner.show(); }
        else if (previewTab === 9) { goTab("send"); transfer.beginPicker("files"); pushPage("browser"); }
        else if (previewTab === 10) {
            receiveDialog.message = I.t(app.langFamily(), "来自 测试设备\n\nphoto.jpg\ndoc.pdf\n\n1234567 字节");
            receiveDialog.open();
        }
        else if (previewTab === 11) {
            // 文件行样式检查：进入 DCIM 看图片文件（后缀 + 大小）
            goTab("send"); transfer.beginPicker("files"); pushPage("browser");
            transfer.browse("/home/user/MyDocs/DCIM");
        }
        else if (previewTab === 12) { goTab("settings"); pushPage("language"); }
        else if (previewTab === 14) { goTab("send"); pushPage("text"); }
        else if (previewTab === 15) { goTab("send"); pushPage("text"); transfer.sendText("MaeShare preview text"); }
        else if (previewTab === 16) { goTab("receive"); app.receiveHistoryOpen = true; }
        else if (previewTab === 17) { goTab("receive"); app.receiveInfoOpen = true; }
        else if (previewTab === 18) {
            // 选中态检查：进 MyDocs 根目录，程序化选中第一个「非目录」的真文件，
            // 用来看勾选框、Done(n)、Selected n 是否真的联动
            goTab("send"); transfer.beginPicker("files"); transfer.browse("/home/user/MyDocs"); pushPage("browser");
            for (var pi = 0; pi < transfer.entries.length; ++pi) {
                if (!transfer.entries[pi].directory) { transfer.activateEntry(transfer.entries[pi].path); break; }
            }
        }
        else if (previewTab === 19) {
            // 新发送流程：选中文件后回到发送页，设备列表这时才出现
            goTab("send"); transfer.beginPicker("files"); transfer.browse("/home/user/MyDocs");
            for (var pj = 0; pj < transfer.entries.length; ++pj) {
                if (!transfer.entries[pj].directory) { transfer.activateEntry(transfer.entries[pj].path); break; }
            }
        }
        else if (previewTab === 20) {
            // 切页回来动画是否还在跑：接收页 → 发送页 → 接收页。
            // 波纹初始 opacity 是 0，若重建后动画没启动，截图里根本看不到那圈波纹。
            goTab("receive"); goTab("send"); goTab("receive");
        }
        else if (previewTab === 21) {
            // 设备类型图标检查：发送页注入三台假设备（手机 / 电脑 / 网页）
            goTab("send");
        }
        else if (previewTab === 22) {
            // 手输地址页布局检查
            goTab("send"); pushPage("manual");
        }
        else if (previewTab === 23) {
            // 手输地址联通检查：等启动时的 identity job 跑完再走 connectManual
            goTab("send");
            previewConnect.start();
        }
        else if (previewTab === 24) {
            // 手输地址 + 已选内容：连上即发
            goTab("send"); transfer.beginPicker("files"); transfer.browse("/home/user/MyDocs");
            for (var pk = 0; pk < transfer.entries.length; ++pk) {
                if (!transfer.entries[pk].directory) { transfer.activateEntry(transfer.entries[pk].path); break; }
            }
            previewConnect.start();
        }
    }
}
