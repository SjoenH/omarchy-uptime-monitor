import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    // === 2. SIGNALS ===
    // === 7. STATES & TRANSITIONS ===
    // === 8. SIGNAL HANDLERS ===

    // === 1. METADATA ===
    id: root

    // === 3. PROPERTIES ===
    // 3a. State properties
    property QtObject anchorItem: null
    property QtObject hostWidget: null
    property string edUrl: ""
    property string edLabel: ""
    property int edValue: 30
    property string edUnit: "sec"
    property string edCron: "0 * * * *"
    property bool edIsCron: false
    property bool suppressSync: false
    // Set by Stop. The URL stays in the field so monitoring can be started
    // again, which means closing the panel must not commit it.
    property bool userStopped: false
    // Wall clock, ticking while the panel is open, for the wait to the next check.
    property double nowMs: Date.now()
    readonly property color foreground: root.barForeground
    readonly property color dim: Qt.darker(root.foreground, 1.55)
    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property bool monitoring: root.urlW() !== ""

    // === 9. FUNCTIONS ===
    function urlW() {
        return root.hostWidget ? (root.hostWidget.url || "") : "";
    }

    function labelW() {
        return root.hostWidget ? (root.hostWidget.label || "") : "";
    }

    function schedW() {
        return root.hostWidget ? (root.hostWidget.schedule || null) : null;
    }

    function statusW() {
        if (root.hostWidget)
            return root.hostWidget.status;

        return {
            "up": null,
            "responseTime": 0,
            "lastChecked": "—",
            "consecutiveFailures": 0,
            "lastError": ""
        };
    }

    function syncFromWidget() {
        if (root.suppressSync) {
            root.suppressSync = false;
            return ;
        }
        root.edUrl = root.urlW();
        root.edLabel = root.labelW();
        var s = root.schedW();
        if (s && s.cron !== undefined) {
            root.edIsCron = true;
            root.edCron = s.cron;
        } else {
            root.edIsCron = false;
            var x = s || {
            };
            root.edValue = parseInt(x.value, 10) || 30;
            root.edUnit = x.unit || "sec";
        }
    }

    function validUrl() {
        return root.edUrl.trim() !== "";
    }

    function normalizedUrl() {
        var u = root.edUrl.trim();
        if (u === "")
            return "";

        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(u))
            return u;

        return "https://" + u;
    }

    function cronOk() {
        if (!root.hostWidget)
            return false;

        return root.hostWidget.cronSyntaxOk(root.edCron);
    }

    function canCommit() {
        return root.validUrl() && (!root.edIsCron || root.cronOk());
    }

    function buildSchedule() {
        return root.edIsCron ? {
            "cron": root.edCron
        } : {
            "value": root.edValue,
            "unit": root.edUnit
        };
    }

    function commit() {
        if (!root.hostWidget || !root.canCommit())
            return ;

        root.userStopped = false;
        root.hostWidget.persist({
            "url": root.normalizedUrl(),
            "label": root.edLabel.trim(),
            "schedule": root.buildSchedule()
        });
    }

    function applySchedule() {
        if (root.hostWidget)
            root.hostWidget.persist({
            "schedule": root.buildSchedule()
        });

    }

    function switchMode(mode) {
        var next = mode === "cron";
        if (next === root.edIsCron)
            return ;

        root.edIsCron = next;
        if (next && !root.edCron.trim())
            root.edCron = "0 * * * *";

        if (root.hostWidget && next)
            root.hostWidget.persist({
            "schedule": {
                "cron": root.edCron
            }
        });
        else if (root.hostWidget)
            root.hostWidget.persist({
            "schedule": {
                "value": root.edValue,
                "unit": root.edUnit
            }
        });
    }

    function stop() {
        root.userStopped = true;
        root.suppressSync = true;
        if (root.hostWidget)
            root.hostWidget.persist({
            "url": ""
        });

    }

    function open() {
        root.userStopped = false;
        root.nowMs = Date.now();
        root.syncFromWidget();
        root.controller.show();
    }

    function close() {
        // Hide first. While it is open the panel is a full-screen overlay
        // that takes every click, so nothing that goes wrong while saving
        // may leave it up.
        root.controller.hide();
        if (!root.userStopped)
            root.commit();

    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction);

        return false;
    }

    function nextCronText() {
        if (!root.hostWidget)
            return "—";

        var n = root.hostWidget.nextCronRun(root.edCron, new Date());
        if (!n)
            return "—";

        return Qt.formatDateTime(n, "dd MMM HH:mm");
    }

    function urgentColor() {
        return root.bar ? root.bar.urgent : Color.urgent;
    }

    function dotColor(s) {
        return root.hostWidget ? root.hostWidget.dotColor(s) : Color.muted;
    }

    function statusText() {
        var s = root.statusW();
        if (root.urlW() === "")
            return "Not monitoring";

        if (!s || s.up === null)
            return "Checking…";

        return s.up ? "Up" : "Down";
    }

    // The arched line over the title: when it was last checked, and how often.
    function captionText() {
        if (!root.monitoring)
            return "Nothing is being watched yet";

        var last = root.hostWidget ? root.hostWidget.lastCheckAt : 0;
        var every = root.hostWidget.scheduleLabel(root.hostWidget.schedule);
        if (last <= 0)
            return "Checking now, then " + every;

        return "Checked at " + Qt.formatTime(new Date(last), "HH:mm") + ", " + every;
    }

    // Host name of the monitored URL, for the card when there is no label.
    function hostOf(url) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/i.exec(String(url));
        return m ? m[1] : String(url);
    }

    function cardName() {
        return root.labelW() !== "" ? root.labelW() : root.hostOf(root.urlW());
    }

    // Under the status: how fast it answered, or why it is down.
    function cardNote() {
        var s = root.statusW();
        if (!s || s.up === null || !root.hostWidget)
            return "";

        if (s.up)
            return root.hostWidget.formatTime(s.responseTime);

        return s.lastError + (s.consecutiveFailures > 1 ? " ×" + s.consecutiveFailures : "");
    }

    function historyW() {
        return root.hostWidget ? root.hostWidget.history : [];
    }

    // Under the graph, on the left: how much of the shown history was up.
    function historySummary() {
        var checks = root.historyW();
        if (checks.length === 0)
            return "No checks yet";

        var up = 0;
        for (var i = 0; i < checks.length; i++) {
            if (checks[i].up)
                up++;

        }
        // Never round a history with a failure in it up to 100%.
        var percent = up === checks.length ? 100 : Math.min(99, Math.round(100 * up / checks.length));
        return percent + "% up \u00b7 " + checks.length + (checks.length === 1 ? " check" : " checks");
    }

    // Under the graph, on the right: how long until the next check.
    function nextCheckText() {
        var next = root.hostWidget ? root.hostWidget.nextCheckAt : 0;
        if (!root.monitoring || next <= 0)
            return "";

        var seconds = Math.max(0, Math.round((next - root.nowMs) / 1000));
        if (seconds < 60)
            return "next in " + seconds + "s";

        if (seconds < 3600)
            return "next in " + Math.round(seconds / 60) + "m";

        if (seconds < 86400)
            return "next in " + Math.floor(seconds / 3600) + "h " + Math.round((seconds % 3600) / 60) + "m";

        return "next in " + Math.round(seconds / 86400) + "d";
    }

    function toggleMonitoring() {
        if (root.monitoring)
            root.stop();
        else
            root.commit();
    }

    function statusColor() {
        var s = root.statusW();
        if (root.urlW() === "")
            return root.dim;

        if (!s || s.up === null)
            return root.dim;

        return s.up ? root.hostWidget.upColor : root.urgentColor();
    }

    objectName: "uptimeMonitorPanel"
    moduleName: "no.koka.uptime-monitor"
    manageIpc: false
    // === 5. ATTACHED OBJECTS & BEHAVIORS ===
    Accessible.role: Accessible.Dialog
    Accessible.name: "Uptime Monitor Configuration"

    // === 6. CHILD OBJECTS ===
    Timer {
        interval: 1000
        repeat: true
        running: root.opened
        onTriggered: root.nowMs = Date.now()
    }

    KeyboardPanel {
        id: panel

        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(340))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) {
                root.switchPanel(direction);
            }

            Column {
                id: content

                width: parent.width
                spacing: Style.space(12)

                PanelTitle {
                    width: parent.width
                    caption: root.captionText()
                    leftWord: "Uptime"
                    rightWord: "Monitor"
                    foreground: root.foreground
                    fontFamily: root.fontFamily

                    // The bar's dot, with a halo: the status at a glance.
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(parent.width * 0.74)
                        height: width
                        radius: width / 2
                        // CONVENTION-EXCEPTION: status indicator colors for up/down states
                        color: Util.alpha(root.dotColor(root.statusW()), 0.22)

                        Rectangle {
                            objectName: "titleDot"
                            anchors.centerIn: parent
                            width: Math.round(parent.width * 0.5)
                            height: width
                            radius: width / 2
                            // CONVENTION-EXCEPTION: status indicator colors for up/down states
                            color: root.dotColor(root.statusW())
                        }

                    }

                }

                StatCard {
                    objectName: "statusCard"
                    width: parent.width
                    visible: root.monitoring
                    name: root.cardName()
                    detail: root.urlW()
                    value: root.statusText()
                    // CONVENTION-EXCEPTION: status indicator colors for up/down states
                    valueColor: root.statusColor()
                    note: root.cardNote()
                    foreground: root.foreground
                    fontFamily: root.fontFamily

                    Column {
                        width: parent.width
                        spacing: Style.spacing.md

                        HistoryGraph {
                            objectName: "historyGraph"
                            width: parent.width
                            samples: root.historyW()
                            capacity: root.hostWidget ? root.hostWidget.historyCapacity : 40
                            foreground: root.foreground
                            upColor: root.hostWidget ? root.hostWidget.upColor : root.foreground
                            downColor: root.urgentColor()
                        }

                        Item {
                            width: parent.width
                            implicitHeight: historyCaption.implicitHeight

                            Text {
                                id: historyCaption

                                objectName: "historySummary"
                                textFormat: Text.PlainText
                                text: root.historySummary()
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }

                            Text {
                                objectName: "nextCheck"
                                anchors.right: parent.right
                                textFormat: Text.PlainText
                                text: root.nextCheckText()
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }

                        }

                    }

                }

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        textFormat: Text.PlainText
                        text: "URL"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    TextField {
                        objectName: "urlField"
                        width: parent.width
                        text: root.edUrl
                        placeholderText: "example.com"
                        foreground: root.foreground
                        accent: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        Accessible.name: "URL to monitor"
                        onTextChanged: root.edUrl = text
                        onAccepted: root.commit()
                        Keys.onEscapePressed: root.close()
                    }

                }

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        textFormat: Text.PlainText
                        text: "Label (optional)"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    TextField {
                        objectName: "labelField"
                        width: parent.width
                        text: root.edLabel
                        placeholderText: "My Site"
                        foreground: root.foreground
                        accent: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        Accessible.name: "Label shown in the bar"
                        onTextChanged: root.edLabel = text
                        onAccepted: root.commit()
                        Keys.onEscapePressed: root.close()
                    }

                }

                Column {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                        textFormat: Text.PlainText
                        text: "Check every"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    ButtonGroup {
                        width: parent.width
                        options: [{
                            "value": "simple",
                            "label": "Every"
                        }, {
                            "value": "cron",
                            "label": "Cron"
                        }]
                        value: root.edIsCron ? "cron" : "simple"
                        foreground: root.foreground
                        background: Color.background
                        accent: Color.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.body
                        onChanged: function(mode) {
                            root.switchMode(mode);
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Style.space(8)
                        visible: !root.edIsCron

                        NumberField {
                            width: parent.width
                            fieldWidth: parent.width
                            value: root.edValue
                            from: 1
                            to: 100000
                            stepSize: 1
                            foreground: root.foreground
                            accent: Color.accent
                            fontFamily: root.fontFamily
                            onModified: function(v) {
                                root.edValue = v;
                                root.applySchedule();
                            }
                        }

                        ButtonGroup {
                            width: parent.width
                            options: [{
                                "value": "sec",
                                "label": "Sec"
                            }, {
                                "value": "min",
                                "label": "Min"
                            }, {
                                "value": "hour",
                                "label": "Hour"
                            }, {
                                "value": "day",
                                "label": "Day"
                            }]
                            value: root.edUnit
                            foreground: root.foreground
                            background: Color.background
                            accent: Color.accent
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            onChanged: function(u) {
                                root.edUnit = u;
                                root.applySchedule();
                            }
                        }

                    }

                    Column {
                        width: parent.width
                        spacing: Style.space(2)
                        visible: root.edIsCron

                        TextField {
                            objectName: "cronField"
                            width: parent.width
                            text: root.edCron
                            placeholderText: "min hour dom month dow (0 * * * *)"
                            foreground: root.foreground
                            accent: root.cronOk() ? Color.accent : root.urgentColor()
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            Accessible.name: "Cron expression"
                            onTextChanged: root.edCron = text
                            onAccepted: {
                                if (root.cronOk())
                                    root.applySchedule();

                            }
                            Keys.onEscapePressed: root.close()
                        }

                        Text {
                            objectName: "cronHint"
                            width: parent.width
                            visible: root.edCron.trim() !== ""
                            textFormat: Text.PlainText
                            text: root.cronOk() ? "Next: " + root.nextCronText() : "Needs 5 cron fields"
                            // CONVENTION-EXCEPTION: status indicator colors
                            color: root.cronOk() ? root.dim : root.urgentColor()
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                        }

                    }

                }

                ActionButton {
                    objectName: "monitorButton"
                    width: parent.width
                    text: root.monitoring ? "Stop monitoring" : "Start monitoring"
                    // CONVENTION-EXCEPTION: stopping is the destructive action
                    textColor: root.monitoring ? root.urgentColor() : root.foreground
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    enabled: root.monitoring || root.canCommit()
                    onClicked: root.toggleMonitoring()
                }

            }

        }

    }

}
