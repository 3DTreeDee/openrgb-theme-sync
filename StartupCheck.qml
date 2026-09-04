import QtQuick
import qs.Common

QtObject {
    function check(done) {
        // The openrgb binary must exist and the SDK server must answer.
        // --list-devices fails (exit != 0) when no SDK server is reachable.
        Proc.runCommand(
            "openrgbThemeSync.startupCheck",
            ["sh", "-c", "command -v openrgb >/dev/null 2>&1 && openrgb --list-devices >/dev/null 2>&1"],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    done(null)
                    return
                }
                done({
                    "title": I18n.tr("OpenRGB or its SDK server is not available"),
                    "details": I18n.tr("Make sure openrgb is installed and its SDK server is enabled (Settings → SDK Server → Start server). The server must answer on the local port.")
                })
            }
        )
    }
}
