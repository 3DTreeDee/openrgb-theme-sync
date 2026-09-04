import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "ColorUtils.js" as ColorUtils

PluginComponent {
    id: root
    property var popoutService: null

    // --- Global config (persisted via PluginSettings) ---
    readonly property bool syncEnabled: pluginData?.enabled !== undefined ? pluginData.enabled : true
    readonly property string colorKey: pluginData?.colorKey || "primary"
    readonly property string customColor: pluginData?.customColor || "#66FFDA"
    readonly property bool applyOnStartup: pluginData?.applyOnStartup !== undefined ? pluginData.applyOnStartup : true
    readonly property bool useBrightness: pluginData?.useBrightness !== undefined ? pluginData.useBrightness : false
    readonly property int brightness: Number(pluginData?.brightness || 100)

    // --- Reactive color: re-evaluates when the theme changes (matugen) ---
    readonly property color liveColor: colorKey === "primary" ? Theme.primary
        : colorKey === "secondary" ? Theme.secondary
        : colorKey === "tertiary" ? Theme.tertiary
        : colorKey === "surface" ? Theme.surface
        : colorKey === "surfaceText" ? Theme.surfaceText
        : colorKey === "surfaceContainer" ? Theme.surfaceContainer
        : colorKey === "surfaceContainerHigh" ? Theme.surfaceContainerHigh
        : colorKey === "error" ? Theme.error
        : colorKey === "success" ? Theme.success
        : ColorUtils.parseOrDefault(customColor, Theme.primary)

    readonly property var detectedDevices: pluginData?.detectedDevices || []

    // Devices with their own fixed mode (everything else gets the global color).
    // Config is keyed by device NAME, which is stable across rescans (numeric ids
    // shift between local scans and the SDK server enumeration). The CLI accepts
    // `-d "name"` directly, so no id resolution is needed. Numeric id keys are
    // honored as a legacy fallback.
    readonly property var configuredDevices: {
        const out = []
        for (const d of (detectedDevices || [])) {
            const base = "device." + d.name + "."
            let enabled = pluginData[base + "enabled"]
            let mode = pluginData[base + "mode"]
            if (enabled === undefined) {
                enabled = pluginData["device." + d.id + ".enabled"]
                mode = pluginData["device." + d.id + ".mode"]
            }
            if (enabled && mode) out.push({ target: d.name || String(d.id), mode: mode })
        }
        return out
    }

    property string lastHex: ""
    property bool pendingConfigChange: false
    property bool ready: false
    property bool detectedOnce: false
    property var cmdQueue: []
    property bool cmdRunning: false
    property int applyGen: 0
    property bool batchFailed: false
    property bool retryPending: false
    property int retryCount: 0
    readonly property int retryMax: 5
    readonly property int retryBaseMs: 2000
    property bool sdkLaunching: false
    property bool applyToastShown: false

    onPluginServiceChanged: {
        if (pluginService && !detectedOnce) {
            detectDevices()
        }
    }

    Timer {
        id: debounce
        interval: 150
        repeat: false
        onTriggered: root.apply(false)
    }

    Timer {
        id: themeDebounce
        interval: 1200
        repeat: false
        onTriggered: root.apply(true)
    }

    Timer {
        id: retryTimer
        interval: 1
        repeat: false
        onTriggered: {
            retryPending = false
            if (!syncEnabled) return
            console.log("[openrgbThemeSync] Retrying apply")
            pendingConfigChange = true
            apply()
        }
    }

    Timer {
        id: sdkWatchdog
        interval: 15000
        repeat: true
        onTriggered: root.checkSdk()
    }

    Timer {
        id: sdkResume
        interval: 12000
        repeat: false
        onTriggered: sdkLaunching = false
    }

    onLiveColorChanged: {
        if (ready && syncEnabled) debounce.restart()
    }

    Connections {
        target: Theme
        function onMatugenCompleted() {
            if (ready && syncEnabled) themeDebounce.restart()
        }
    }

    Connections {
        target: pluginService
        function onPluginDataChanged(changedId) {
            if (changedId !== pluginId) return
            if (syncEnabled && ready) {
                pendingConfigChange = true
                debounce.restart()
            }
        }
    }

    function apply(force) {
        if (!syncEnabled) return

        let color = ColorUtils.toHexRGB(liveColor)
        color = color.indexOf("#") === 0 ? color.slice(1) : color
        if (!force && color === lastHex && !pendingConfigChange && !retryPending) return
        lastHex = color
        pendingConfigChange = false
        // Invalidate queued batches of older colors (coalescing): only the latest
        // requested color runs. Does not affect the in-flight command (it
        // finishes) nor detection (non-coalescible).
        applyGen++

        // 1) Apply the color globally (to every non-configured device)
        const baseArgs = ["openrgb"]
        if (useBrightness && brightness >= 0 && brightness <= 100) baseArgs.push("-b", String(brightness))
        baseArgs.push("--color", color)

        // 2) Re-apply to configured devices with their fixed mode
        const configured = configuredDevices

        const commands = [baseArgs]

        if (configured.length === 0) {
            console.log("[openrgbThemeSync] Applying color", color, "to all devices")
            runSequential(commands, finishApply)
            return
        }

        console.log("[openrgbThemeSync] Applying color", color, "globally + per-device modes")
        for (const d of configured) {
            const args = ["openrgb", "-d", d.target, "-m", d.mode]
            if (useBrightness && brightness >= 0 && brightness <= 100) args.push("-b", String(brightness))
            args.push("-c", color)
            commands.push(args)
        }
        runSequential(commands, finishApply)
    }

    function finishApply() {
        if (batchFailed) scheduleRetry()
        else resetRetry()
        batchFailed = false
    }

    function scheduleRetry() {
        if (retryPending) return
        if (retryCount >= retryMax) {
            resetRetry()
            return
        }
        retryPending = true
        const delay = Math.min(retryBaseMs * Math.pow(2, retryCount), 30000)
        retryCount++
        retryTimer.interval = delay
        retryTimer.restart()
        console.log("[openrgbThemeSync] Retry scheduled in", delay, "ms (attempt", retryCount + ")")
    }

    function resetRetry() {
        retryPending = false
        retryCount = 0
        applyToastShown = false
        retryTimer.stop()
    }

    function checkSdk() {
        if (!syncEnabled) return
        if (sdkLaunching) return
        Proc.runCommand(
            "openrgbThemeSync.sdkcheck",
            ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/6742 2>/dev/null && echo ok || echo fail"],
            (out, code) => {
                if (String(out).trim() === "ok") return
                if (sdkLaunching) return
                sdkLaunching = true
                console.log("[openrgbThemeSync] OpenRGB SDK server not responding, relaunching")
                ToastService?.showInfo("OpenRGB Theme Sync", "OpenRGB SDK server not responding, restarting it")
                Proc.runCommand(
                    "openrgbThemeSync.relaunch",
                    ["sh", "-c", "nohup openrgb --startminimized --server >/dev/null 2>&1 & disown"],
                    () => sdkResume.restart(),
                    0,
                    5000
                )
            },
            0,
            3000
        )
    }

    function runSequential(cmds, onDone, coalescible) {
        const list = Array.isArray(cmds) ? cmds : [cmds]
        batchFailed = false
        const gen = coalescible === false ? -1 : applyGen
        for (let i = 0; i < list.length; i++) {
            cmdQueue.push({ args: list[i], done: i === list.length - 1 ? onDone : null, gen: gen })
        }
        pumpQueue()
    }

    function pumpQueue() {
        if (cmdRunning || cmdQueue.length === 0) return
        const entry = cmdQueue.shift()
        // Stale batch (a newer color arrived): dropped without running.
        // Its 'done' is not fired; the current batch owns retries/state.
        if (entry.gen >= 0 && entry.gen !== applyGen) {
            Qt.callLater(pumpQueue)
            return
        }
        cmdRunning = true
        Proc.runCommand(
            "openrgbThemeSync.apply",
            entry.args,
            (stdout, exitCode) => {
                cmdRunning = false
                if (exitCode !== 0) {
                    batchFailed = true
                    console.error("[openrgbThemeSync] Failed (exit", exitCode + ")", entry.args.join(" "), "::", stdout)
                    if (!applyToastShown) {
                        applyToastShown = true
                        ToastService?.showInfo("OpenRGB Theme Sync", "Could not apply color to OpenRGB")
                    }
                }
                if (entry.done) {
                    const cb = entry.done
                    entry.done = null
                    cb(stdout, exitCode)
                }
                Qt.callLater(pumpQueue)
            },
            0,
            15000
        )
    }

    function detectDevices() {
        runSequential([["openrgb", "--list-devices"]], (stdout, exitCode) => {
            if (exitCode !== 0 || !stdout) {
                console.error("[openrgbThemeSync] Device detection failed")
                return
            }
            const fresh = ColorUtils.parseDevices(stdout)
            const previous = pluginData?.detectedDevices || []
            const devices = ColorUtils.mergeDevices(previous, fresh)
            pluginService?.savePluginData(pluginId, "detectedDevices", devices)
            detectedOnce = devices.length > 0
            if (devices.length > 0) {
                console.log("[openrgbThemeSync] Detected", devices.length, "device(s):",
                    devices.map(d => d.name + " (#" + d.id + ")").join(", "))
            }
            if (ready && syncEnabled) apply()
        }, false)
    }

    Component.onCompleted: {
        if (syncEnabled && applyOnStartup) {
            Qt.callLater(() => {
                ready = true
                apply()
            })
        } else {
            ready = true
        }
        if (syncEnabled) {
            sdkWatchdog.start()
            Qt.callLater(checkSdk)
        }
        console.log("[openrgbThemeSync] Daemon started")
    }
}
