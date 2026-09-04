import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "ColorUtils.js" as ColorUtils

PluginSettings {
    id: root
    pluginId: "openrgbThemeSync"

    StyledText {
        width: parent.width
        text: I18n.tr("General")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "enabled"
        label: I18n.tr("Active sync")
        description: I18n.tr("Automatically apply the theme color to OpenRGB")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "applyOnStartup"
        label: I18n.tr("Apply on startup")
        description: I18n.tr("Apply the current color when the plugin loads")
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: I18n.tr("Color")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    SelectionSetting {
        settingKey: "colorKey"
        label: I18n.tr("Theme color")
        description: I18n.tr("Which DMS color is sent to the LEDs")
        options: [
            { label: I18n.tr("Accent (primary)"), value: "primary" },
            { label: I18n.tr("Secondary accent"), value: "secondary" },
            { label: I18n.tr("Tertiary accent"), value: "tertiary" },
            { label: I18n.tr("Surface"), value: "surface" },
            { label: I18n.tr("Surface text"), value: "surfaceText" },
            { label: I18n.tr("Container"), value: "surfaceContainer" },
            { label: I18n.tr("Container high"), value: "surfaceContainerHigh" },
            { label: I18n.tr("Error"), value: "error" },
            { label: I18n.tr("Success"), value: "success" },
            { label: I18n.tr("Custom"), value: "custom" }
        ]
        defaultValue: "primary"
    }

    ColorSetting {
        settingKey: "customColor"
        label: I18n.tr("Custom color")
        description: I18n.tr("Used when the selected color is 'Custom'")
        defaultValue: "#66FFDA"
    }

    StyledText {
        width: parent.width
        text: I18n.tr("Brightness")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    ToggleSetting {
        settingKey: "useBrightness"
        label: I18n.tr("Adjust brightness")
        description: I18n.tr("Force device brightness (OpenRGB)")
        defaultValue: false
    }

    SliderSetting {
        settingKey: "brightness"
        label: I18n.tr("Brightness level")
        description: I18n.tr("Percentage if 'Adjust brightness' is on")
        minimum: 0
        maximum: 100
        unit: "%"
        defaultValue: 100
    }

    StyledText {
        width: parent.width
        text: I18n.tr("Devices")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    StyledText {
        width: parent.width
        text: I18n.tr("By default the color is applied to all devices. For devices that don't respond to color alone (e.g. mice with a spectrum mode), enable a fixed color mode.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        topPadding: Theme.spacingXS
        wrapMode: Text.WordWrap
    }

    property var devicesList: []
    property bool redetecting: false

    Connections {
        target: pluginService
        function onPluginDataChanged(changedId) {
            if (changedId === pluginId) {
                root.devicesList = root.loadValue("detectedDevices", [])
            }
        }
    }

    DankButton {
        text: root.redetecting ? I18n.tr("Detecting…") : I18n.tr("Detect devices")
        onClicked: root.redetect()
    }

    StyledText {
        width: parent.width
        visible: root.devicesList.length === 0
        text: I18n.tr("No OpenRGB devices detected. Make sure openrgb is installed.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        topPadding: Theme.spacingXS
    }

    Repeater {
        model: root.devicesList
        width: parent.width
        delegate: Column {
            width: parent.width
            spacing: Theme.spacingS
            topPadding: Theme.spacingS

            StyledText {
                width: parent.width
                text: "#" + modelData.id + " · " + modelData.name
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            SelectionSetting {
                settingKey: "device." + modelData.name + ".mode"
                label: I18n.tr("Color mode")
                description: I18n.tr("Mode used to apply the color on this device")
                options: root.modeOptions(modelData.modes)
                defaultValue: ColorUtils.suggestedMode(modelData.modes)
            }

            ToggleSetting {
                settingKey: "device." + modelData.name + ".enabled"
                label: I18n.tr("Apply mode on this device")
                description: I18n.tr("When off, the device only receives the global color")
                defaultValue: false
            }
        }
    }

    function modeOptions(modes) {
        const out = []
        const colorless = ColorUtils.colorlessModes()
        for (const m of (modes || [])) {
            if (!colorless.includes(m)) {
                out.push({ label: m, value: m })
            }
        }
        return out.length > 0 ? out : []
    }

    function redetect() {
        if (root.redetecting) return
        root.redetecting = true
        Proc.runCommand(
            "openrgbThemeSync.settings.detect",
            ["openrgb", "--list-devices"],
            (stdout, exitCode) => {
                root.redetecting = false
                if (exitCode !== 0 || !stdout) return
                const previous = root.loadValue("detectedDevices", [])
                const merged = ColorUtils.mergeDevices(previous, ColorUtils.parseDevices(stdout))
                root.saveValue("detectedDevices", merged)
                root.devicesList = root.loadValue("detectedDevices", [])
            },
            0,
            15000
        )
    }

    function reload() {
        root.devicesList = root.loadValue("detectedDevices", [])
    }

    Component.onCompleted: {
        root.reload()
        Qt.callLater(root.reload)
    }
}
