import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    // === 2. SIGNALS ===
    // === 7. STATES & TRANSITIONS ===

    // === 1. METADATA ===
    id: root

    // === 3. PROPERTIES ===
    // 3a. State properties
    property string url: setting("url", "")
    property string label: setting("label", "")
    property var schedule: root.parseSchedule(setting("schedule", null))
    // 3b. State/readonly
    property var status: root.emptyStatus()
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool configured: root.url !== ""

    // === 9. FUNCTIONS (private first, then public) ===
    function _emptyStatus() {
        return {
            "up": null,
            "responseTime": 0,
            "lastChecked": "—",
            "consecutiveFailures": 0,
            "lastError": ""
        };
    }

    function _defaultSchedule() {
        return {
            "value": 30,
            "unit": "sec"
        };
    }

    function _parseSchedule(s) {
        if (s && typeof s === "object") {
            if (s.cron !== undefined)
                return {
                "cron": s.cron
            };

            var n = parseInt(s.value, 10);
            return {
                "value": (n && n > 0) ? n : 30,
                "unit": s.unit || "sec"
            };
        }
        return root._defaultSchedule();
    }

    function _isCronSchedule(s) {
        return s && s.cron !== undefined;
    }

    function _unitMs(unit, n) {
        if (unit === "min")
            return n * 1000 * 60;

        if (unit === "hour")
            return n * 1000 * 60 * 60;

        if (unit === "day")
            return n * 1000 * 60 * 60 * 24;

        return n * 1000;
    }

    function _scheduleMs(s) {
        var x = root._parseSchedule(s);
        return root._unitMs(x.unit || "sec", Math.max(1, parseInt(x.value, 10) || 30));
    }

    function _scheduleLabel(s) {
        var x = root._parseSchedule(s);
        if (x.cron !== undefined)
            return "cron: " + x.cron;

        var uname = {
            "sec": "s",
            "min": "m",
            "hour": "h",
            "day": "d"
        }[x.unit] || "s";
        return "every " + x.value + uname;
    }

    function _cronField(pattern, min, max) {
        var allowed = {
        };
        var parts = String(pattern).split(",");
        for (var i = 0; i < parts.length; i++) {
            var p = parts[i].trim(), step = 1, base = p;
            if (p.indexOf("/") >= 0) {
                step = parseInt(p.split("/")[1], 10) || 1;
                base = p.split("/")[0];
            }
            if (base === "*")
                base = min + "-" + max;

            if (base.indexOf("-") >= 0) {
                var lo = parseInt(base.split("-")[0], 10), hi = parseInt(base.split("-")[1], 10);
                if (!isNaN(lo) && !isNaN(hi))
                    for (var v = lo; v <= hi; v += step) allowed[v] = true;

            } else {
                var single = parseInt(base, 10);
                if (!isNaN(single))
                    allowed[single] = true;
                else if (step > 1 && p.indexOf("/") >= 0)
                    for (var v2 = min; v2 <= max; v2 += step) allowed[v2] = true;
            }
        }
        return allowed;
    }

    function _nextCronRun(cron, from) {
        var f = String(cron).trim().split(/\s+/);
        if (f.length !== 5)
            return null;

        var fmin = root._cronField(f[0], 0, 59), fhour = root._cronField(f[1], 0, 23);
        var fdom = root._cronField(f[2], 1, 31), fmonth = root._cronField(f[3], 1, 12), fdow = root._cronField(f[4], 0, 7);
        var domStar = String(f[2]).trim() === "*", dowStar = String(f[4]).trim() === "*";
        var d = new Date(from.getTime());
        d.setSeconds(0, 0);
        d.setMinutes(d.getMinutes() + 1);
        for (var guard = 0; guard < 366 * 24 * 60; guard++) {
            var monthOk = fmonth[d.getMonth() + 1] === true, domOk = fdom[d.getDate()] === true;
            var dow = d.getDay(), dowOk = (fdow[dow] === true) || (dow === 0 && fdow[7] === true);
            var dayOk = (domStar && dowStar) ? true : (domStar ? dowOk : (dowStar ? domOk : (domOk || dowOk)));
            if (monthOk && dayOk && fhour[d.getHours()] === true && fmin[d.getMinutes()] === true)
                return d;

            d.setMinutes(d.getMinutes() + 1);
        }
        return null;
    }

    function _nextScheduleRun(schedule, from) {
        var s = root._parseSchedule(schedule);
        if (root._isCronSchedule(s))
            return root._nextCronRun(s.cron, from);

        return new Date(from.getTime() + root._scheduleMs(schedule));
    }

    function _cronIsValid(cron) {
        return root._cronSyntaxOk(cron) && root._nextCronRun(cron, new Date()) !== null;
    }

    function _cronFieldOk(pattern, min, max) {
        var parts = String(pattern).split(",");
        if (parts.length === 0 || String(pattern).trim() === "")
            return false;

        for (var i = 0; i < parts.length; i++) {
            var p = parts[i].trim();
            if (p === "")
                return false;

            var step = 1, base = p;
            var slash = p.indexOf("/");
            if (slash >= 0) {
                var stepStr = p.slice(slash + 1);
                if (!/^\d+$/.test(stepStr))
                    return false;

                step = parseInt(stepStr, 10);
                if (step < 1)
                    return false;

                base = p.slice(0, slash);
            }
            if (base === "*")
                continue;

            if (/^(\d+)-(\d+)$/.test(base)) {
                var lo = parseInt(RegExp.$1, 10), hi = parseInt(RegExp.$2, 10);
                if (hi < lo || lo < min || hi > max)
                    return false;

                continue;
            }
            if (!/^\d+$/.test(base))
                return false;

            var v = parseInt(base, 10);
            if (v < min || v > max)
                return false;

        }
        return true;
    }

    function _cronSyntaxOk(cron) {
        var f = String(cron).trim().split(/\s+/);
        if (f.length !== 5)
            return false;

        return root._cronFieldOk(f[0], 0, 59) && root._cronFieldOk(f[1], 0, 23) && root._cronFieldOk(f[2], 1, 31) && root._cronFieldOk(f[3], 1, 12) && root._cronFieldOk(f[4], 0, 7);
    }

    function _scheduleArm() {
        var nxt = root._nextScheduleRun(root.schedule, new Date());
        if (nxt) {
            checkTimer.interval = Math.max(1000, nxt.getTime() - Date.now());
            checkTimer.repeat = false;
        } else {
            checkTimer.interval = 60 * 1000;
            checkTimer.repeat = true;
        }
        checkTimer.start();
    }

    function _formatTime(ms) {
        if (ms < 1000)
            return ms + "ms";

        return (ms / 1000).toFixed(2) + "s";
    }

    function dotColor(s) {
        if (!s || s.up === null)
            return Qt.lighter(Color.background, 1.3);

        return s.up ? Color.accent : root.bar.urgent;
    }

    // --- Public API ---
    function emptyStatus() {
        return root._emptyStatus();
    }

    function defaultSchedule() {
        return root._defaultSchedule();
    }

    function parseSchedule(s) {
        return root._parseSchedule(s);
    }

    function isCronSchedule(s) {
        return root._isCronSchedule(s);
    }

    function unitMs(unit, n) {
        return root._unitMs(unit, n);
    }

    function scheduleMs(s) {
        return root._scheduleMs(s);
    }

    function scheduleLabel(s) {
        return root._scheduleLabel(s);
    }

    function cronField(pattern, min, max) {
        return root._cronField(pattern, min, max);
    }

    function nextCronRun(cron, from) {
        return root._nextCronRun(cron, from);
    }

    function nextScheduleRun(schedule, from) {
        return root._nextScheduleRun(schedule, from);
    }

    function cronIsValid(cron) {
        return root._cronIsValid(cron);
    }

    function cronSyntaxOk(cron) {
        return root._cronSyntaxOk(cron);
    }

    function cronFieldOk(pattern, min, max) {
        return root._cronFieldOk(pattern, min, max);
    }

    function formatTime(ms) {
        return root._formatTime(ms);
    }

    function persist(patch) {
        var urlChanged = patch && patch.url !== undefined && patch.url !== root.url;
        var schedChanged = patch && patch.schedule !== undefined;
        if (patch) {
            if (patch.url !== undefined)
                root.url = patch.url;

            if (patch.label !== undefined)
                root.label = patch.label;

            if (patch.schedule !== undefined)
                root.schedule = root._parseSchedule(patch.schedule);

        }
        var entry = {
            "id": root.moduleName,
            "url": root.url,
            "label": root.label,
            "schedule": root.schedule
        };
        root.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);

        if (urlChanged)
            root.arm();
        else if (schedChanged)
            root._scheduleArm();
    }

    function previewUrl(v) {
        root.url = v;
        root.arm();
    }

    function previewLabel(v) {
        root.label = v;
    }

    function previewSchedule(v) {
        root.schedule = root._parseSchedule(v);
        root.arm();
    }

    function arm() {
        if (!root.configured)
            return ;

        probeProcess.running = true;
        root._scheduleArm();
    }

    function open() {
        if (panelLoader.item)
            panelLoader.item.open();

    }

    function close() {
        if (panelLoader.item)
            panelLoader.item.close();

    }

    function toggle() {
        if (panelLoader.item)
            panelLoader.item.toggle();

    }

    function injectPanel() {
        if (!panelLoader.item)
            return ;

        panelLoader.item.bar = root.bar;
        panelLoader.item.anchorItem = root;
        panelLoader.item.hostWidget = root;
    }

    function tooltipText() {
        var name = (root.label !== "" ? root.label + " — " : "") + root.url;
        var state = root.status.up === null ? "checking" : (root.status.up ? "UP" : "DOWN");
        return name + "\n" + state + (root.configured ? " · " + root.scheduleLabel(root.schedule) : "");
    }

    objectName: "uptimeMonitor"
    moduleName: "no.koka.uptime-monitor"
    // 3c. Layout
    implicitWidth: barContent.implicitWidth + 10
    implicitHeight: root.barSize
    // === 5. ATTACHED OBJECTS & BEHAVIORS ===
    Accessible.role: Accessible.Button
    Accessible.name: "Uptime Monitor"
    // === 8. SIGNAL HANDLERS ===
    onBarChanged: injectPanel()
    onUrlChanged: {
        if (panelLoader.item)
            panelLoader.item.syncFromWidget();

        Qt.callLater(function() {
            root.arm();
        });
    }
    onLabelChanged: {
        if (panelLoader.item)
            panelLoader.item.syncFromWidget();

    }
    Component.onCompleted: Qt.callLater(root.arm)

    // === 6. CHILD OBJECTS ===
    Timer {
        id: checkTimer

        interval: 30000
        repeat: false
        running: false
        onTriggered: {
            if (root.isCronSchedule(root.parseSchedule(root.schedule)))
                root._scheduleArm();

            probeProcess.running = true;
        }
    }

    Process {
        id: probeProcess

        running: false
        // URL is passed as its own argv element (never interpolated into a
        // shell string), and timing comes from curl itself.
        command: ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "--connect-timeout", "5", "--max-time", "10", "--proto", "=https,http", "--", root.url]
        onExited: function(exitCode) {
            var now = new Date();
            var st = root.emptyStatus();
            st.lastChecked = Qt.formatDateTime(now, "dd MMM HH:mm:ss");
            if (exitCode === 0 && probeOut.data) {
                var parts = String(probeOut.data).trim().split(" ");
                var code = parts[0], time = Math.round(parseFloat(parts[1]) * 1000) || 0;
                if (root.isCronSchedule(root.parseSchedule(root.schedule))) {
                    root._scheduleArm();
                } else {
                    checkTimer.interval = root.scheduleMs(root.schedule);
                    checkTimer.repeat = true;
                    checkTimer.start();
                }
                if (code && (code[0] === "2" || code[0] === "3")) {
                    st.up = true;
                    st.responseTime = time;
                    st.consecutiveFailures = 0;
                    st.lastError = code[0] === "3" ? "Redirect: " + code : "";
                } else {
                    st.up = false;
                    st.consecutiveFailures = (root.status.consecutiveFailures || 0) + 1;
                    st.lastError = "HTTP " + (code || exitCode);
                }
            } else {
                st.up = false;
                st.consecutiveFailures = (root.status.consecutiveFailures || 0) + 1;
                st.lastError = exitCode === 28 ? "Timeout" : "Connection failed";
                if (!root.isCronSchedule(root.parseSchedule(root.schedule))) {
                    checkTimer.interval = root.scheduleMs(root.schedule);
                    checkTimer.repeat = true;
                    checkTimer.start();
                }
            }
            root.status = st;
        }

        stdout: StdioCollector {
            id: probeOut
        }

    }

    Loader {
        id: panelLoader

        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    MouseArea {
        id: clickArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: "Uptime Monitor — click to configure"
        onEntered: {
            if (root.bar)
                root.bar.showTooltip(root, root.tooltipText());

        }
        onExited: {
            if (root.bar)
                root.bar.hideTooltip(root);

        }
        onClicked: root.toggle()

        Row {
            id: barContent

            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                // CONVENTION-EXCEPTION: status indicator colors for up/down states
                color: root.dotColor(root.status)

                Behavior on color {
                    ColorAnimation {
                        duration: 300
                    }

                }

            }

            Text {
                visible: root.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                // CONVENTION-EXCEPTION: fallback color for null bar context
                color: root.bar ? root.bar.foreground : Style.colorText
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
            }

        }

    }

}
