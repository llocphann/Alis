pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root
    property var clock: SystemClock {
        id: clock
        precision: ((Config.options?.time?.secondPrecision ?? false)
                || GlobalStates.screenLocked)
            ? SystemClock.Seconds : SystemClock.Minutes
    }
    property date minuteDate: new Date()
    property date todayDate: new Date()
    property int _lastMinuteKey: -1
    property int _lastDayKey: -1

    function _syncCoarseDates(): void {
        const now = clock.date
        if (!now)
            return
        const ms = now.getTime()
        if (!Number.isFinite(ms))
            return
        const minKey = Math.floor(ms / 60000)
        if (minKey !== root._lastMinuteKey) {
            root._lastMinuteKey = minKey
            root.minuteDate = new Date(ms)
        }
        const dayKey = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate()
        if (dayKey !== root._lastDayKey) {
            root._lastDayKey = dayKey
            root.todayDate = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12, 0, 0, 0)
        }
    }

    property string time: {
        const fmt = Config.options?.time?.format ?? "hh:mm";
        return Qt.locale().toString(fmt.includes("s") ? clock.date : root.minuteDate, fmt);
    }
    // Like time, but appends :ss when secondPrecision is enabled — used by bar clocks
    property string timeDisplay: {
        const fmt = Config.options?.time?.format ?? "hh:mm";
        if (!(Config.options?.time?.secondPrecision ?? false))
            return Qt.locale().toString(fmt.includes("s") ? clock.date : root.minuteDate, fmt);
        if (fmt.includes("s"))
            return Qt.locale().toString(clock.date, fmt);
        const meridiemIndex = Math.max(fmt.lastIndexOf(" AP"), fmt.lastIndexOf(" ap"));
        return Qt.locale().toString(clock.date, meridiemIndex >= 0 ? fmt.slice(0, meridiemIndex) + ":ss" + fmt.slice(meridiemIndex) : fmt + ":ss");
    }
    property string shortDate: Qt.locale().toString(root.todayDate, Config.options?.time?.shortDateFormat ?? "dd/MM")
    property string date: Qt.locale().toString(root.todayDate, Config.options?.time?.dateFormat ?? "dddd, dd/MM")
    property string collapsedCalendarFormat: Qt.locale().toString(root.todayDate, "dd MMMM yyyy")
    property string uptime: "0h, 0m"

    function _refreshUptime(): void {
        fileUptime.reload();
        const textUptime = String(fileUptime.text() ?? "").trim();
        const uptimeSeconds = Number(textUptime.split(/\s+/)[0]);
        if (!Number.isFinite(uptimeSeconds) || uptimeSeconds < 0)
            return;

        // Convert seconds to days, hours, and minutes
        const days = Math.floor(uptimeSeconds / 86400);
        const hours = Math.floor((uptimeSeconds % 86400) / 3600);
        const minutes = Math.floor((uptimeSeconds % 3600) / 60);

        // Build the formatted uptime string
        let formatted = "";
        if (days > 0)
            formatted += `${days}d`;
        if (hours > 0)
            formatted += `${formatted ? ", " : ""}${hours}h`;
        if (minutes > 0 || !formatted)
            formatted += `${formatted ? ", " : ""}${minutes}m`;
        uptime = formatted;
    }

    Connections {
        target: clock
        Component.onCompleted: root._syncCoarseDates()
        function onSecondsChanged(): void {
            root._syncCoarseDates()
        }
        function onMinutesChanged(): void {
            root._syncCoarseDates()
            root._refreshUptime()
        }
        function onHoursChanged(): void {
            root._syncCoarseDates()
        }
    }

    Component.onCompleted: root._refreshUptime()

    FileView {
        id: fileUptime

        path: "/proc/uptime"
    }
}
