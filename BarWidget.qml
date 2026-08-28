import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "no.koka.uptime-monitor"

  implicitWidth: barContent.implicitWidth + 10
  implicitHeight: root.barSize

  // ---- data model -----------------------------------------------------------
  // One monitor watches a single URL. Settings are saved through the shell's
  // updateEntryInline (single id) so the bar patches the running widget in
  // place instead of rebuilding.
  property string url: setting("url", "")
  property string label: setting("label", "")
  property var schedule: root.parseSchedule(setting("schedule", null))

  // { up, responseTime, lastChecked, consecutiveFailures, lastError }
  property var status: root.emptyStatus()

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool configured: root.url !== ""

  function emptyStatus() {
    return { up: null, responseTime: 0, lastChecked: "—", consecutiveFailures: 0, lastError: "" }
  }

  function persist(patch) {
    var urlChanged = patch && patch.url !== undefined && patch.url !== root.url
    var schedChanged = patch && patch.schedule !== undefined
    if (patch) {
      if (patch.url !== undefined) root.url = patch.url
      if (patch.label !== undefined) root.label = patch.label
      if (patch.schedule !== undefined) root.schedule = root.parseSchedule(patch.schedule)
    }
    var entry = { id: root.moduleName, url: root.url, label: root.label, schedule: root.schedule }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
    // Only run an immediate probe when the target actually changed. Just
    // viewing/editing the panel shouldn't refresh the last-checked time.
    if (urlChanged) root.arm()
    else if (schedChanged) checkTimer.arm()
  }

  // Live-preview helpers (no persistence): update the in-memory display only.
  function previewUrl(v) { root.url = v; root.arm() }
  function previewLabel(v) { root.label = v }
  function previewSchedule(v) { root.schedule = root.parseSchedule(v); root.arm() }

  // ---- schedule maths --------------------------------------------------------
  function defaultSchedule() { return { value: 30, unit: "sec" } }
  function parseSchedule(s) {
    if (s && typeof s === "object") {
      if (s.cron !== undefined) return { cron: s.cron }
      var n = parseInt(s.value, 10)
      return { value: (n && n > 0) ? n : 30, unit: s.unit || "sec" }
    }
    return root.defaultSchedule()
  }
  function isCronSchedule(s) { return s && s.cron !== undefined }
  function unitMs(unit, n) {
    if (unit === "min") return n * 1000 * 60
    if (unit === "hour") return n * 1000 * 60 * 60
    if (unit === "day") return n * 1000 * 60 * 60 * 24
    return n * 1000
  }
  function scheduleMs(s) {
    var x = root.parseSchedule(s)
    return root.unitMs(x.unit || "sec", Math.max(1, parseInt(x.value, 10) || 30))
  }
  function scheduleLabel(s) {
    var x = root.parseSchedule(s)
    if (x.cron !== undefined) return "cron: " + x.cron
    var uname = { sec: "s", min: "m", hour: "h", day: "d" }[x.unit] || "s"
    return "every " + x.value + uname
  }

  // ---- cron next-run --------------------------------------------------------
  function cronField(pattern, min, max) {
    var allowed = {}
    var parts = String(pattern).split(",")
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim(), step = 1, base = p
      if (p.indexOf("/") >= 0) { step = parseInt(p.split("/")[1], 10) || 1; base = p.split("/")[0] }
      if (base === "*") base = min + "-" + max
      if (base.indexOf("-") >= 0) {
        var lo = parseInt(base.split("-")[0], 10), hi = parseInt(base.split("-")[1], 10)
        if (!isNaN(lo) && !isNaN(hi)) for (var v = lo; v <= hi; v += step) allowed[v] = true
      } else {
        var single = parseInt(base, 10)
        if (!isNaN(single)) allowed[single] = true
        else if (step > 1 && p.indexOf("/") >= 0) for (var v2 = min; v2 <= max; v2 += step) allowed[v2] = true
      }
    }
    return allowed
  }
  function nextCronRun(cron, from) {
    var f = String(cron).trim().split(/\s+/)
    if (f.length !== 5) return null
    var fmin = root.cronField(f[0], 0, 59), fhour = root.cronField(f[1], 0, 23)
    var fdom = root.cronField(f[2], 1, 31), fmonth = root.cronField(f[3], 1, 12), fdow = root.cronField(f[4], 0, 7)
    var domStar = String(f[2]).trim() === "*", dowStar = String(f[4]).trim() === "*"
    var d = new Date(from.getTime()); d.setSeconds(0, 0); d.setMinutes(d.getMinutes() + 1)
    for (var guard = 0; guard < 366 * 24 * 60; guard++) {
      var monthOk = fmonth[d.getMonth() + 1] === true, domOk = fdom[d.getDate()] === true
      var dow = d.getDay(), dowOk = (fdow[dow] === true) || (dow === 0 && fdow[7] === true)
      var dayOk = (domStar && dowStar) ? true : (domStar ? dowOk : (dowStar ? domOk : (domOk || dowOk)))
      if (monthOk && dayOk && fhour[d.getHours()] === true && fmin[d.getMinutes()] === true) return d
      d.setMinutes(d.getMinutes() + 1)
    }
    return null
  }
  function nextScheduleRun(schedule, from) {
    var s = root.parseSchedule(schedule)
    if (root.isCronSchedule(s)) return root.nextCronRun(s.cron, from)
    return new Date(from.getTime() + root.scheduleMs(schedule))
  }
  function cronIsValid(cron) {
    return root.cronSyntaxOk(cron) && root.nextCronRun(cron, new Date()) !== null
  }

  // Cheap, O(1) syntactic validation of a 5-field cron expression. Used for
  // live field-hint/error state in the panel; it does NOT scan ahead for the
  // next matching run (that's expensive and belongs in nextCronRun).
  function cronFieldOk(pattern, min, max) {
    var parts = String(pattern).split(",")
    if (parts.length === 0 || String(pattern).trim() === "") return false
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim()
      if (p === "") return false
      var step = 1, base = p
      var slash = p.indexOf("/")
      if (slash >= 0) {
        var stepStr = p.slice(slash + 1)
        if (!/^\d+$/.test(stepStr)) return false
        step = parseInt(stepStr, 10)
        if (step < 1) return false
        base = p.slice(0, slash)
      }
      if (base === "*") continue
      if (/^(\d+)-(\d+)$/.test(base)) {
        var lo = parseInt(RegExp.$1, 10), hi = parseInt(RegExp.$2, 10)
        if (hi < lo || lo < min || hi > max) return false
        continue
      }
      if (!/^\d+$/.test(base)) return false
      var v = parseInt(base, 10)
      if (v < min || v > max) return false
    }
    return true
  }
  function cronSyntaxOk(cron) {
    var f = String(cron).trim().split(/\s+/)
    if (f.length !== 5) return false
    return root.cronFieldOk(f[0], 0, 59) &&
           root.cronFieldOk(f[1], 0, 23) &&
           root.cronFieldOk(f[2], 1, 31) &&
           root.cronFieldOk(f[3], 1, 12) &&
           root.cronFieldOk(f[4], 0, 7)
  }

  // ---- health checker -------------------------------------------------------
  Timer {
    id: checkTimer
    interval: 30000
    repeat: false
    running: false

  function arm() {
      var nxt = root.nextScheduleRun(root.schedule, new Date())
      if (nxt) {
        checkTimer.interval = Math.max(1000, nxt.getTime() - Date.now())
        checkTimer.repeat = false
      } else {
        checkTimer.interval = 60 * 1000
        checkTimer.repeat = true
      }
      checkTimer.start()
    }

    onTriggered: {
      if (root.isCronSchedule(root.parseSchedule(root.schedule))) checkTimer.arm()
      probeProcess.running = true
    }
  }

  Process {
    id: probeProcess
    running: false
    command: ["sh", "-c",
      "start=$(date +%s%3N) && " +
      "code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 '" + root.url + "' 2>/dev/null) && " +
      "end=$(date +%s%3N) && echo \"$code $((end - start))\""]

    stdout: StdioCollector { id: probeOut }

    onExited: function(exitCode) {
      var now = new Date()
      var st = root.emptyStatus()
      st.lastChecked = Qt.formatDateTime(now, "dd MMM HH:mm:ss")
      if (exitCode === 0 && probeOut.data) {
        var parts = String(probeOut.data).trim().split(" ")
        var code = parts[0], time = parseInt(parts[1], 10) || 0
        if (root.isCronSchedule(root.parseSchedule(root.schedule))) {
          // cron: re-arm to the next matching run
          checkTimer.arm()
        } else {
          checkTimer.interval = root.scheduleMs(root.schedule)
          checkTimer.repeat = true
          checkTimer.start()
        }
        if (code && (code[0] === "2" || code[0] === "3")) {
          st.up = true
          st.responseTime = time
          st.consecutiveFailures = 0
          st.lastError = code[0] === "3" ? "Redirect: " + code : ""
        } else {
          st.up = false
          st.consecutiveFailures = (root.status.consecutiveFailures || 0) + 1
          st.lastError = "HTTP " + (code || exitCode)
        }
      } else {
        st.up = false
        st.consecutiveFailures = (root.status.consecutiveFailures || 0) + 1
        st.lastError = exitCode === 28 ? "Timeout" : "Connection failed"
        if (!root.isCronSchedule(root.parseSchedule(root.schedule))) {
          checkTimer.interval = root.scheduleMs(root.schedule)
          checkTimer.repeat = true
          checkTimer.start()
        }
      }
      root.status = st
    }
  }

  function arm() {
    if (!root.configured) return
    probeProcess.running = true
    checkTimer.arm()
  }

  Component.onCompleted: Qt.callLater(root.arm)

  function formatTime(ms) {
    if (ms < 1000) return ms + "ms"
    return (ms / 1000).toFixed(2) + "s"
  }
  function colorOf(s) {
    if (s.up === null) return "#888888"
    return s.up ? "#00cc66" : "#ff4444"
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = root
    panelLoader.item.hostWidget = root
  }

  onBarChanged: injectPanel()
  onUrlChanged: {
    if (panelLoader.item) panelLoader.item.syncFromWidget()
    Qt.callLater(function(){ root.arm() })
  }
  onLabelChanged: if (panelLoader.item) panelLoader.item.syncFromWidget()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      if (root.bar) root.bar.showTooltip(root, root.tooltipText())
    }
    onExited: {
      if (root.bar) root.bar.hideTooltip(root)
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
        color: root.colorOf(root.status)
        Behavior on color { ColorAnimation { duration: 300 } }
      }

      Text {
        visible: root.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.bar ? root.bar.foreground : "#f8f8f2"
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  function tooltipText() {
    var name = (root.label !== "" ? root.label + " — " : "") + root.url
    var state = root.status.up === null ? "checking" : (root.status.up ? "UP" : "DOWN")
    return name + "\n" + state + (root.configured ? " · " + root.scheduleLabel(root.schedule) : "")
  }
}
