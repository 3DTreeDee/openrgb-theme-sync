# OpenRGB Theme Sync

Sync your Dank Material Shell theme colors with your RGB hardware via OpenRGB.

## Demo

[![Demo: Wallpaper by Workspace + OpenRGB Theme Sync](https://i.ytimg.com/vi/OfQJ_lEPi8I/hqdefault.jpg)](https://youtu.be/OfQJ_lEPi8I&t=4s)

Combined demo with Wallpaper by Workspace: switching niri workspaces applies
the per-workspace wallpaper and regenerates the theme, while this plugin pushes
the theme color to the RGB hardware live — watch the PC lighting turn green
with the green wallpaper. Chapters: `0:00` neutral · `0:04` green → green RGB ·
`0:06` warm · `0:08` snow → white RGB.

## What it does

This daemon watches for theme color changes and applies the configured color to
all your OpenRGB devices. Devices that ignore a color-only command receive a
fixed color mode so their LEDs still match your theme.

## Requirements

- DankMaterialShell with plugin support (`requires_dms >= 1.0.0`).
- [OpenRGB](https://openrgb.org/) installed (`openrgb` on `PATH`) with its
  **SDK server** enabled (Settings → SDK Server → *Start server*). Keep the
  server running (e.g. autostart `openrgb --startminimized --server`); the
  plugin talks to your hardware through it, so commands are fast (~1 s) and
  never trigger a full hardware rescan.

## Setup

1. Copy this folder to `~/.config/DankMaterialShell/plugins/openrgbThemeSync/`.
2. In DMS go to Settings → Plugins → Scan, enable **OpenRGB Theme Sync**. A
   startup check verifies that `openrgb` is installed and reachable.
3. Open the plugin settings and click **Detect devices** so the daemon learns
   your hardware.

## Settings

- **General**
  - *Active sync*: apply the theme color to OpenRGB automatically.
  - *Apply on startup*: apply the current color when the plugin loads.
- **Color**
  - *Theme color*: which DMS color is sent to the LEDs
    (primary / secondary / tertiary / surface / … / custom).
  - *Custom color*: used when *Theme color* is set to *Custom*.
- **Brightness**
  - *Adjust brightness*: force the device brightness.
  - *Brightness level*: percentage when enabled.
- **Devices**
  - *Detect devices*: re-scan connected OpenRGB devices.
  - Per device you can enable a **fixed color mode** and pick the mode. This is
    useful for devices that don't change color from a global color command
    alone (for example mice running a spectrum/flow mode).

## Notes

- The global color is applied to all devices, then each device configured with
  a fixed mode is set individually by **name** (stable across rescans).
  Commands run serially to avoid OpenRGB connection races, and rapid theme
  changes are coalesced so only the latest color is applied.
- If the SDK server stops responding, the daemon restarts it automatically and
  retries failed applies with exponential backoff.
- The daemon runs invisibly in the background.
- Command failures show up as toast notifications and are logged to the console.

## License

MIT — see [LICENSE](./LICENSE).
