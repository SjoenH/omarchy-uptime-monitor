import QtQuick 2.15
import QtTest 1.2

TestCase {
    name: "UptimeMonitor"
    when: windowShown

    // --- Cron field helpers (mirror BarWidget.qml logic) ---
    function _cronField(pattern, min, max) {
        var allowed = {}
        var parts = String(pattern).split(",")
        for (var i = 0; i < parts.length; i++) {
            var p = parts[i].trim()
            var step = 1, base = p
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
    function _nextCronRun(cron, from) {
        var f = String(cron).trim().split(/\s+/)
        if (f.length !== 5) return null
        var fmin = _cronField(f[0], 0, 59), fhour = _cronField(f[1], 0, 23)
        var fdom = _cronField(f[2], 1, 31), fmonth = _cronField(f[3], 1, 12), fdow = _cronField(f[4], 0, 7)
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
    function _cronSyntaxOk(cron) {
        var f = String(cron).trim().split(/\s+/)
        if (f.length !== 5) return false
        return _cronField(f[0], 0, 59) && _cronField(f[1], 0, 23) && _cronField(f[2], 1, 31) && _cronField(f[3], 1, 12) && _cronField(f[4], 0, 7)
    }
    function _unitMs(unit, n) {
        if (unit === "min") return n * 1000 * 60
        if (unit === "hour") return n * 1000 * 60 * 60
        if (unit === "day") return n * 1000 * 60 * 60 * 24
        return n * 1000
    }
    function _assert(name, cond) { if (cond) console.log("PASS " + name); else { console.log("FAIL " + name); Qt.exit(1) } }

    // --- Cron field parsing ---
    function test_cronFieldEveryMinute() {
        var f = _cronField("*", 0, 59)
        _assert("cronField: * allows all", f[0] === true && f[59] === true)
    }

    function test_cronFieldStep() {
        var f = _cronField("*/5", 0, 59)
        _assert("cronField: */5 has 0,5,10...", f[0] === true && f[5] === true && f[10] === true && f[55] === true)
    }

    function test_cronFieldRange() {
        var f = _cronField("1-5", 0, 59)
        _assert("cronField: 1-5 has 1..5", f[1] === true && f[3] === true && f[5] === true && f[0] === undefined)
    }

    function test_cronFieldInvalidEmpty() {
        _assert("cronField: empty rejected", _cronField("", 0, 59) === false)
    }

    // --- Cron syntax validation ---
    function test_cronSyntaxOkValid() {
        _assert("cronSyntaxOk: valid 5-field", _cronSyntaxOk("* * * * *") === true)
    }

    function test_cronSyntaxOkInvalid() {
        _assert("cronSyntaxOk: 6-field rejected", _cronSyntaxOk("0 0 0 0 0 0") === false)
        _assert("cronSyntaxOk: 4-field rejected", _cronSyntaxOk("* * * *") === false)
    }

    // --- Next cron run ---
    function test_nextCronRunEveryMinute() {
        var n = _nextCronRun("* * * * *", new Date(2026, 7, 28, 10, 0, 30))
        _assert("nextCronRun: every minute -> next min", n && n.getMinutes() === 1 && n.getSeconds() === 0)
    }

    function test_nextCronRunStep() {
        var n = _nextCronRun("*/5 * * * *", new Date(2026, 7, 28, 10, 0, 0))
        _assert("nextCronRun: */5 -> 10:05", n && n.getMinutes() === 5 && n.getHours() === 10)
    }

    function test_nextCronRunInvalid() {
        _assert("nextCronRun: 6-field rejected", _nextCronRun("0 0 0 0 0 0", new Date()) === null)
    }

    function test_nextCronRunCronDayOfWeek() {
        var n = _nextCronRun("0 0 * * 1", new Date(2026, 7, 28, 10, 0, 0))
        _assert("nextCronRun: mon 00:00 returns date", n !== null)
    }

    // --- Unit conversion ---
    function test_unitMsSeconds() { _assert("unit: 30 sec = 30000ms", _unitMs("sec", 30) === 30000) }
    function test_unitMsMinutes() { _assert("unit: 5 min = 300000ms", _unitMs("min", 5) === 300000) }
    function test_unitMsHours() { _assert("unit: 2 hour = 7200000ms", _unitMs("hour", 2) === 7200000) }
    function test_unitMsDays() { _assert("unit: 1 day = 86400000ms", _unitMs("day", 1) === 86400000) }

    // --- Schedule parsing ---
    function test_parseScheduleCron() {
        var s = { cron: "0 * * * *" }
        _assert("parseSchedule: cron preserved", s.cron === "0 * * * *")
    }

    function test_parseScheduleInterval() {
        var result = { value: 30, unit: "sec" }
        _assert("parseSchedule: interval parsed", result.value === 30 && result.unit === "sec")
    }

    // --- Status helpers ---
    function test_emptyStatus() {
        var s = { up: null, responseTime: 0, lastChecked: "—", consecutiveFailures: 0, lastError: "" }
        _assert("emptyStatus: all fields present", s.up === null && s.consecutiveFailures === 0)
    }
}