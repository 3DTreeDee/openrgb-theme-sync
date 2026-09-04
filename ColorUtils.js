.pragma library

// Convert a QML color to RRGGBB hex (no '#', the format the OpenRGB CLI expects)
function toHexRGB(color) {
    if (color === undefined || color === null) return "000000"

    // Already a "#RRGGBB" or "#AARRGGBB" hex string: normalize it
    if (typeof color === "string") {
        let c = color.trim()
        if (c.charAt(0) === "#") c = c.slice(1)
        if (c.length >= 6) {
            // "RRGGBB" or "AARRGGBB" -> keep the last 6 (RRGGBB)
            c = c.slice(-6)
            return c.toUpperCase()
        }
        return "000000"
    }

    const r = Math.max(0, Math.min(255, Math.round(color.r * 255)))
    const g = Math.max(0, Math.min(255, Math.round(color.g * 255)))
    const b = Math.max(0, Math.min(255, Math.round(color.b * 255)))
    return toHex2(r) + toHex2(g) + toHex2(b)
}

function toHex2(v) {
    const h = v.toString(16).toUpperCase()
    return h.length < 2 ? "0" + h : h
}

// Parse a "#RRGGBB"/"RRGGBB" string as a color, with fallback
function parseOrDefault(text, fallback) {
    if (typeof text !== "string") return fallback
    let c = text.trim()
    if (c.charAt(0) === "#") c = c.slice(1)
    if (/^[0-9a-fA-F]{6}$/.test(c)) {
        const r = parseInt(c.slice(0, 2), 16) / 255
        const g = parseInt(c.slice(2, 4), 16) / 255
        const b = parseInt(c.slice(4, 6), 16) / 255
        return Qt.rgba(r, g, b, 1)
    }
    return fallback
}

function isValidHex(text) {
    if (typeof text !== "string") return false
    let c = text.trim()
    if (c.charAt(0) === "#") c = c.slice(1)
    return /^[0-9a-fA-F]{6}$/.test(c)
}

// Split a line into tokens, respecting single-quoted groups ('Color Cycle')
function splitQuoted(text) {
    const tokens = []
    let cur = ""
    let inQuote = false
    for (let i = 0; i < text.length; i++) {
        const ch = text[i]
        if (ch === "'") {
            inQuote = !inQuote
            continue
        }
        if (ch === " " && !inQuote) {
            if (cur) {
                tokens.push(cur)
                cur = ""
            }
            continue
        }
        cur += ch
    }
    if (cur) tokens.push(cur)
    return tokens
}

// Parse the output of `openrgb --list-devices` into a list of devices:
// [{ id, name, modes: [names], hasZones }]
function parseDevices(output) {
    const devices = []
    if (typeof output !== "string") return devices

    const lines = output.split("\n")
    let current = null

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i]
        const header = /^(\d+):\s+(.+)$/.exec(line)
        if (header) {
            current = {
                id: Number(header[1]),
                name: header[2].trim(),
                modes: [],
                hasZones: false
            }
            devices.push(current)
            continue
        }
        if (!current) continue

        const modeMatch = /Modes:\s*\[(.*?)\](.*)$/.exec(line)
        if (modeMatch) {
            const activeModifier = modeMatch[1]
            const rest = modeMatch[2]
            const all = splitQuoted((activeModifier || "") + " " + (rest || ""))
            current.modes = all
            continue
        }
        if (/^\s*Zones:/.test(line)) {
            current.hasZones = true
        }
    }

    return devices
}

// Select the suggested default mode for a device: the first mode that takes a
// fixed color. "Direct", then "Static". Falls back to the first mode.
function suggestedMode(modes) {
    if (!modes || modes.length === 0) return "Direct"
    const pref = ["Direct", "Static", "Breathing"]
    for (const p of pref) {
        if (modes.includes(p)) return p
    }
    return modes[0]
}

// Modes that make no sense for a fixed theme color
function colorlessModes() {
    return ["Off", "Random", "Rainbow", "Color Cycle", "Spectrum Cycle", "Marquee", "Rainbow Wave", "Sin"]
}

// Merge a fresh device list with the previously known one. Devices already known
// (by id) that are missing from the fresh scan are kept, so an intermittent scan
// doesn't drop devices from the UI/config (e.g. a mouse that sometimes isn't listed).
function mergeDevices(previous, fresh) {
    const prev = (Array.isArray(previous) ? previous : []).slice()
    const out = []
    const byId = {}
    for (const p of prev) {
        if (p && p.id !== undefined) byId[p.id] = p
    }
    for (const f of (fresh || [])) {
        if (f && f.id !== undefined) {
            byId[f.id] = f
        }
    }
    const ids = Object.keys(byId)
        .map(Number)
        .filter(n => !isNaN(n))
        .sort((a, b) => a - b)
    for (const id of ids) {
        out.push(byId[id])
    }
    return out
}


