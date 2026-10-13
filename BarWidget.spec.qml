import QtQuick
import qs.Commons

// Runs against the real BarWidget.qml and Panel.qml through tests/run.sh.
// `h` is the harness (tests/harness/Harness.qml); a test that has to wait is
// a generator and yields the number of milliseconds to wait. Every probe goes
// to tests/fixtures/server.py on localhost.
Item {
    id: spec

    property var h: null
    readonly property string server: "http://127.0.0.1:" + h.env("SPEC_HTTP_PORT")
    // Port 1 is reserved and closed: a connection that is refused at once.
    readonly property string unreachable: "http://127.0.0.1:1/"
    readonly property var october: new Date(2026, 9, 13, 10, 0, 0)

    function monitor(url, schedule, label) {
        return h.createWidget({
            "url": url,
            "label": label || "",
            "schedule": schedule || {
                "value": 30,
                "unit": "sec"
            }
        });
    }

    function stamp(date) {
        function two(n) {
            return (n < 10 ? "0" : "") + n;
        }

        return date.getFullYear() + "-" + two(date.getMonth() + 1) + "-" + two(date.getDate()) + " " + two(date.getHours()) + ":" + two(date.getMinutes());
    }

    // --- Probing -----------------------------------------------------------

    function* test_a200IsUp() {
        var w = monitor(server + "/ok");
        yield 500;
        h.compare(w.status.up, true);
        h.compare(w.status.lastError, "");
        h.compare(w.status.consecutiveFailures, 0);
    }

    function* test_aRedirectIsUp() {
        var w = monitor(server + "/redirect");
        yield 500;
        h.compare(w.status.up, true);
        h.compare(w.status.lastError, "Redirect: 302");
    }

    function* test_anErrorStatusIsDown() {
        var w = monitor(server + "/error");
        yield 500;
        h.compare(w.status.up, false);
        h.compare(w.status.lastError, "HTTP 500");
    }

    function* test_aRefusedConnectionIsDownAndCounted() {
        var w = monitor(unreachable, {
            "value": 1,
            "unit": "sec"
        });
        yield 2600;
        h.compare(w.status.up, false);
        h.compare(w.status.lastError, "Connection failed");
        h.verify(w.status.consecutiveFailures >= 2, "failures add up across checks, got " + w.status.consecutiveFailures);
    }

    function* test_nothingIsProbedUntilAUrlIsSet() {
        var w = monitor("");
        yield 300;
        h.compare(w.configured, false);
        h.compare(w.status.up, null);
    }

    // Regression: a result for a URL that had since been replaced was shown
    // as the status of the new one.
    function* test_aResultForAReplacedUrlIsDiscarded() {
        var w = monitor(server + "/slow-error");
        yield 300;
        w.persist({
            "url": server + "/ok"
        });
        yield 2200;
        h.compare(w.status.up, true);
        h.compare(w.status.lastError, "");
    }

    // --- Stopping ----------------------------------------------------------

    // Regression: Stop left the URL in the field, and closing the panel
    // committed it again, so monitoring quietly resumed.
    function* test_stopSurvivesClosingThePanel() {
        var w = monitor(server + "/ok");
        yield 400;
        w.open();
        yield 50;
        h.click(h.byName("stopButton"));
        yield 50;
        h.compare(w.url, "", "Stop clears the monitored URL");
        w.close();
        yield 100;
        h.compare(w.url, "", "closing the panel does not start it again");
        h.compare(h.lastPersisted().url, "");
    }

    // Regression: the check timer kept running after Stop and probed an
    // empty URL, which turned the dot red.
    function* test_aStoppedMonitorStopsChecking() {
        var w = monitor(server + "/ok", {
            "value": 1,
            "unit": "sec"
        });
        yield 400;
        h.compare(w.status.up, true);
        w.persist({
            "url": ""
        });
        yield 2400;
        h.compare(w.status.up, null, "no up/down state once stopped");
        h.compare(w.status.consecutiveFailures, 0);
    }

    function* test_stoppingMidProbeDoesNotReportItsResult() {
        var w = monitor(server + "/slow-error");
        yield 300;
        w.persist({
            "url": ""
        });
        yield 1800;
        h.compare(w.status.up, null);
    }

    function* test_startingAgainAfterStop() {
        var w = monitor(server + "/ok");
        yield 400;
        w.open();
        yield 50;
        h.click(h.byName("stopButton"));
        yield 50;
        h.click(h.byName("stopButton"));
        yield 500;
        h.compare(w.url, server + "/ok", "the same button starts monitoring again");
        h.compare(w.status.up, true);
    }

    // --- Settings ----------------------------------------------------------

    // Regression: persist() assigned url/label/schedule directly, which broke
    // their bindings to settings; later shell.json changes were ignored.
    function* test_settingsStillApplyAfterSaving() {
        var w = monitor(server + "/ok", null, "First");
        yield 300;
        w.persist({
            "label": "Renamed"
        });
        yield 50;
        h.compare(w.label, "Renamed");
        w.settings = {
            "url": server + "/error",
            "label": "From shell.json",
            "schedule": {
                "cron": "0 * * * *"
            }
        };
        yield 500;
        h.compare(w.url, server + "/error");
        h.compare(w.label, "From shell.json");
        h.compare(w.schedule.cron, "0 * * * *");
        h.compare(w.status.up, false, "and the new URL is the one being probed");
    }

    function* test_typingAUrlAndPressingEnterStartsMonitoring() {
        var w = monitor("");
        yield 50;
        w.open();
        yield 50;
        var field = h.byName("urlField");
        h.click(field);
        h.type(server + "/ok");
        h.key(Qt.Key_Return);
        yield 500;
        h.compare(w.url, server + "/ok");
        h.compare(w.status.up, true);
    }

    function test_aBareHostGetsHttps() {
        var w = monitor("");
        var panel = h.byName("uptimeMonitorPanel");
        panel.edUrl = "  example.com ";
        h.compare(panel.normalizedUrl(), "https://example.com");
        panel.edUrl = "http://example.com";
        h.compare(panel.normalizedUrl(), "http://example.com");
    }

    function test_scheduleParsing() {
        var w = monitor("");
        h.compare(w.parseSchedule(null), {
            "value": 30,
            "unit": "sec"
        });
        h.compare(w.parseSchedule({
            "value": "5",
            "unit": "min"
        }), {
            "value": 5,
            "unit": "min"
        });
        h.compare(w.parseSchedule({
            "value": -3
        }), {
            "value": 30,
            "unit": "sec"
        });
        h.compare(w.parseSchedule({
            "cron": "0 * * * *"
        }), {
            "cron": "0 * * * *"
        });
        h.compare(w.scheduleMs({
            "value": 2,
            "unit": "hour"
        }), 7.2e+06);
        h.compare(w.unitMs("day", 1), 8.64e+07);
        h.compare(w.scheduleLabel({
            "value": 5,
            "unit": "min"
        }), "every 5m");
        h.compare(w.scheduleLabel({
            "cron": "0 3 * * 1"
        }), "cron: 0 3 * * 1");
    }

    // --- Rendering ---------------------------------------------------------

    // Regression: "up" used the theme accent (any hue, red included) and
    // "checking" used a lightened background that vanished on a light bar.
    function* test_theDotSaysCheckingUpAndDown() {
        var w = monitor(server + "/ok", {
            "value": 1,
            "unit": "sec"
        });
        var dot = h.byName("statusDot");
        h.verify(Qt.colorEqual(dot.color, Color.muted), "checking is muted, got " + dot.color);
        h.verify(!Qt.colorEqual(Color.muted, h.bar.background), "which is visible against the bar");
        yield 800;
        h.verify(Qt.colorEqual(dot.color, w.upColor), "up is green, got " + dot.color);
        h.verify(Qt.colorEqual(w.upColor, "#00cc66"));
        w.persist({
            "url": unreachable
        });
        yield 800;
        h.verify(Qt.colorEqual(dot.color, h.bar.urgent), "down is the theme's urgent colour, got " + dot.color);
    }

    // The label is whatever the user typed; it must never be parsed as markup.
    function test_theLabelIsRenderedAsPlainText() {
        var w = monitor("", null, "<i>Prod</i>");
        var label = h.byName("barLabel");
        h.compare(label.text, "<i>Prod</i>");
        h.compare(label.textFormat, Text.PlainText);
    }

    function* test_theTooltipDescribesTheMonitor() {
        var w = monitor(server + "/ok", {
            "value": 5,
            "unit": "min"
        }, "Local");
        h.compare(w.tooltipText(), "Local — " + server + "/ok\nchecking · every 5m");
        yield 500;
        h.compare(w.tooltipText(), "Local — " + server + "/ok\nUP · every 5m");
    }

    function test_theWidgetFitsTheBar() {
        var w = monitor(server + "/ok", null, "Local");
        h.compare(w.implicitHeight, h.bar.barSize);
    }

    // --- Cron --------------------------------------------------------------

    function test_cronFieldExpansion() {
        var w = monitor("");
        h.compare(Object.keys(w.cronField("*", 0, 5)).join(","), "0,1,2,3,4,5");
        h.compare(Object.keys(w.cronField("*/15", 0, 59)).join(","), "0,15,30,45");
        h.compare(Object.keys(w.cronField("1-5", 0, 59)).join(","), "1,2,3,4,5");
        h.compare(Object.keys(w.cronField("1,10,20-22", 0, 59)).join(","), "1,10,20,21,22");
        h.compare(Object.keys(w.cronField("5/15", 0, 59)).join(","), "5,20,35,50", "a bare start with a step runs to the end of the field");
    }

    // Regression: these came from shell.json unvalidated; a negative step
    // looped forever and an oversized range expanded without bound.
    function test_cronFieldCannotRunAway() {
        var w = monitor("");
        h.compare(Object.keys(w.cronField("*/-5", 0, 5)).join(","), "0,1,2,3,4,5");
        h.compare(Object.keys(w.cronField("0-99999999999", 0, 5)).join(","), "0,1,2,3,4,5");
        h.compare(Object.keys(w.cronField("nonsense", 0, 5)).join(","), "");
    }

    function test_cronSyntax() {
        var w = monitor("");
        var good = ["* * * * *", "*/5 * * * *", "0 3 * * 1", "0 0 1 1 *", "15,45 9-17 * * 1-5", "0 0 * * 7"];
        for (var i = 0; i < good.length; i++) h.compare(w.cronSyntaxOk(good[i]), true, good[i])
        var bad = ["", "* * * *", "0 0 0 0 0 0", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *", "*/0 * * * *", "*/-5 * * * *", "5-1 * * * *", "a * * * *", "1,,2 * * * *"];
        for (var j = 0; j < bad.length; j++) h.compare(w.cronSyntaxOk(bad[j]), false, bad[j])
    }

    function test_nextCronRun() {
        var w = monitor("");
        h.compare(stamp(w.nextCronRun("* * * * *", new Date(2026, 7, 28, 10, 0, 30))), "2026-08-28 10:01");
        h.compare(stamp(w.nextCronRun("*/5 * * * *", october)), "2026-10-13 10:05");
        h.compare(stamp(w.nextCronRun("30 9 * * *", october)), "2026-10-14 09:30", "today's 09:30 has passed");
        h.compare(stamp(w.nextCronRun("30 14 * * *", october)), "2026-10-13 14:30", "today's 14:30 has not");
        h.compare(stamp(w.nextCronRun("0 3 * * 1", october)), "2026-10-19 03:00", "next Monday");
        h.compare(stamp(w.nextCronRun("0 0 * * 7", october)), "2026-10-18 00:00", "7 is Sunday too");
        h.compare(stamp(w.nextCronRun("0 0 1 1 *", october)), "2027-01-01 00:00");
        h.compare(stamp(w.nextCronRun("0 0 29 2 *", october)), "2028-02-29 00:00", "leap day");
        h.compare(stamp(w.nextCronRun("0 12 13 * 5", october)), "2026-10-13 12:00", "day-of-month OR day-of-week");
        h.compare(w.nextCronRun("0 0 0 0 0 0", october), null);
    }

    // Regression: the search stepped one minute at a time on the UI thread:
    // about half a second for a yearly schedule and up to two for one that
    // never matches, repeated on every keystroke in the cron field.
    function test_nextCronRunIsFastForRareSchedules() {
        var w = monitor("");
        var started = Date.now();
        h.compare(stamp(w.nextCronRun("0 0 1 1 *", october)), "2027-01-01 00:00");
        h.compare(w.nextCronRun("0 0 30 2 *", october), null, "Feb 30 never comes");
        var took = Date.now() - started;
        h.verify(took < 500, "took " + took + " ms");
    }

    // A time skipped by a daylight-saving change must not come back shifted
    // by an hour. Run from every day of the year, in both test timezones.
    function test_nextCronRunNeverReturnsAShiftedTime() {
        var w = monitor("");
        for (var day = 0; day < 366; day++) {
            var run = w.nextCronRun("30 2 * * *", new Date(2026, 0, 1 + day, 12, 0, 0));
            if (run.getHours() !== 2 || run.getMinutes() !== 30)
                h.verify(false, "from day " + day + " got " + run);

        }
    }

    function test_scheduleRunsFromNow() {
        var w = monitor("");
        h.compare(w.nextScheduleRun({
            "value": 5,
            "unit": "min"
        }, october).getTime() - october.getTime(), 300000);
        h.compare(stamp(w.nextScheduleRun({
            "cron": "0 * * * *"
        }, october)), "2026-10-13 11:00");
    }

}
