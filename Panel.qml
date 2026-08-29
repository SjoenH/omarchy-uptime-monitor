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
        root.suppressSync = true;
        if (root.hostWidget)
            root.hostWidget.persist({
            "url": ""
        });

    }

    function open() {
        root.syncFromWidget();
        root.controller.show();
    }

    function close() {
        root.commit();
        root.controller.hide();
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

    function dotColor(s) {
        if (!s || s.up === null)
            return Qt.lighter(Color.background, 1.3);

        return s.up ? Color.accent : root.bar.urgent;
    }

    function statusText() {
        var s = root.statusW();
        if (root.urlW() === "")
            return "Not monitoring";

        if (!s || s.up === null)
            return "Checking…";

        return s.up ? "Up" : "Down";
    }

    function statusColor() {
        var s = root.statusW();
        if (root.urlW() === "")
            return Qt.darker(root.barForeground, 1.4);

        if (!s || s.up === null)
            return Qt.darker(root.barForeground, 1.4);

        return s.up ? Color.accent : root.bar.urgent;
    }

    objectName: "uptimeMonitorPanel"
    moduleName: "no.koka.uptime-monitor"
    manageIpc: false
    // === 5. ATTACHED OBJECTS & BEHAVIORS ===
    Accessible.role: Accessible.Dialog
    Accessible.name: "Uptime Monitor Configuration"

    // === 6. CHILD OBJECTS ===
    KeyboardPanel {
        id: panel

        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(280))
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
                padding: Style.space(4)

                Text {
                    width: parent.width
                    text: "Uptime Monitor"
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                }

                Row {
                    spacing: Style.space(8)
                    visible: root.urlW() !== ""

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        // CONVENTION-EXCEPTION: status indicator colors for up/down states
                        color: root.dotColor(root.statusW())
                    }

                    Text {
                        text: root.statusText()
                        // CONVENTION-EXCEPTION: status indicator colors for up/down states
                        color: root.statusColor()
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }

                    Text {
                        text: root.hostWidget ? root.hostWidget.scheduleLabel(root.hostWidget.schedule) : ""
                        color: Qt.darker(root.barForeground, 1.4)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                    }

                }

                Text {
                    width: parent.width
                    visible: root.urlW() !== "" && root.statusW().lastChecked && root.statusW().lastChecked !== "—"
                    text: "Last checked " + root.statusW().lastChecked
                    color: Qt.darker(root.barForeground, 1.4)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                }

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "URL"
                        color: Qt.darker(root.barForeground, 1.4)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    TextField {
                        width: parent.width
                        text: root.edUrl
                        placeholderText: "example.com"
                        foreground: root.barForeground
                        accent: Color.accent
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        onTextChanged: root.edUrl = text
                        onAccepted: root.commit()
                        Keys.onEscapePressed: root.close()
                    }

                }

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Label (optional)"
                        color: Qt.darker(root.barForeground, 1.4)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    TextField {
                        width: parent.width
                        text: root.edLabel
                        placeholderText: "My Site"
                        foreground: root.barForeground
                        accent: Color.accent
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        onTextChanged: root.edLabel = text
                        onAccepted: root.commit()
                        Keys.onEscapePressed: root.close()
                    }

                }

                Column {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                        text: "Check every:"
                        color: Qt.darker(root.barForeground, 1.4)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
                        foreground: root.barForeground
                        background: Color.background
                        accent: Color.accent
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
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
                            foreground: root.barForeground
                            accent: Color.accent
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
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
                            foreground: root.barForeground
                            background: Color.background
                            accent: Color.accent
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
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
                            width: parent.width
                            text: root.edCron
                            placeholderText: "min hour dom month dow (0 * * * *)"
                            foreground: root.barForeground
                            accent: root.cronOk() ? Color.accent : root.bar.urgent
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.body
                            onTextChanged: root.edCron = text
                            onAccepted: {
                                if (root.cronOk())
                                    root.applySchedule();

                            }
                            Keys.onEscapePressed: root.close()
                        }

                        Text {
                            width: parent.width
                            visible: root.edCron.trim() !== ""
                            text: root.cronOk() ? "Next: " + root.nextCronText() : "Needs 5 cron fields"
                            // CONVENTION-EXCEPTION: status indicator colors
                            color: root.cronOk() ? Qt.darker(root.barForeground, 1.4) : root.bar.urgent
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                        }

                    }

                }

                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                        width: (parent.width - Style.space(8)) / 2
                        visible: root.urlW() !== ""
                        text: "Save"
                        focusable: true
                        foreground: root.barForeground
                        accent: Color.accent
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        fontSize: Style.font.body
                        enabled: root.canCommit()
                        onClicked: root.commit()
                    }

                    Button {
                        width: root.urlW() === "" ? parent.width : (parent.width - Style.space(8)) / 2
                        text: root.urlW() === "" ? "Start monitoring" : "Stop"
                        focusable: true
                        foreground: root.urlW() === "" ? root.barForeground : root.bar.urgent
                        accent: Color.accent
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        fontSize: Style.font.body
                        enabled: root.urlW() !== "" || root.canCommit()
                        onClicked: {
                            if (root.urlW() === "")
                                root.commit();
                            else
                                root.stop();
                        }
                    }

                }

            }

        }

    }

}
