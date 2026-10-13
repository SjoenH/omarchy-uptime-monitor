import QtQuick
import qs.Commons

// The most recent checks as a bar graph, oldest on the left: one bar per
// check, as tall as its response time, and a full-height bar in the "down"
// colour for a check that failed. Slots not yet filled show as faint ticks.
// `samples` is [{ up, ms }], oldest first.
Item {
    id: root

    property var samples: []
    property int capacity: 40
    property color foreground: Color.foreground
    property color upColor: foreground
    property color downColor: Color.urgent
    readonly property real barGap: Math.max(1, Style.space(2))
    readonly property real barWidth: Math.max(1, (width - barGap * (capacity - 1)) / capacity)
    // Slowest successful check, which sets the scale.
    readonly property real peak: {
        var most = 1;
        for (var i = 0; i < samples.length; i++) {
            if (samples[i].up && samples[i].ms > most)
                most = samples[i].ms;

        }
        return most;
    }
    readonly property int upCount: {
        var n = 0;
        for (var i = 0; i < samples.length; i++) {
            if (samples[i].up)
                n++;

        }
        return n;
    }

    function barHeight(sample) {
        if (!sample)
            return Math.max(2, Style.space(2));

        if (!sample.up)
            return height;

        // A quarter of the height at least, so a fast check is still a bar.
        return Math.round(height * (0.25 + 0.75 * sample.ms / peak));
    }

    implicitHeight: Style.space(30)
    Accessible.role: Accessible.Graphic
    Accessible.name: samples.length === 0 ? "No checks yet" : upCount + " of the last " + samples.length + " checks were up"

    Repeater {
        model: root.capacity

        Rectangle {
            required property int index
            // Right-aligned, so the newest check is always the last bar.
            readonly property var sample: root.samples[index - (root.capacity - root.samples.length)] || null

            objectName: "historyBar-" + index
            x: index * (root.barWidth + root.barGap)
            y: root.height - height
            width: root.barWidth
            height: root.barHeight(sample)
            radius: Math.min(width / 2, Style.space(2))
            // CONVENTION-EXCEPTION: status indicator colors for up/down states
            color: sample ? (sample.up ? root.upColor : root.downColor) : Util.alpha(root.foreground, 0.12)
        }

    }

}
