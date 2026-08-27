import Foundation

/// Builds the text of the module diagnostic report.
///
/// Deliberately unlocalised: this report exists to be pasted into a bug report
/// or handed to whoever is debugging the firmware, so stable English labels and
/// raw values are more useful than translated ones. It is also a pure function
/// of its inputs, which keeps it testable without a module attached.
enum ModuleDiagnosticReport {
    static func generate(
        snapshot: ModemSnapshot,
        lastVerified: ModeConfigurationSnapshot?,
        log: [ModeSwitchLogEntry],
        generatedAt: Date
    ) -> String {
        var lines: [String] = []
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]

        lines.append("CellDock module diagnostic report")
        lines.append("generated: \(stamp.string(from: generatedAt))")
        lines.append("")

        lines.append("== Current state ==")
        lines.append("usb identity   : \(snapshot.usbIdentity ?? "-")")
        lines.append("usbcfg         : \(snapshot.usbConfiguration?.usbcfgValueDescription ?? "-")")
        lines.append("usbnet         : \(snapshot.usbNetMode.map(String.init) ?? "-")")
        lines.append("mode           : \(snapshot.usbConfiguration?.mode?.rawValue ?? "unrecognised")")
        lines.append("firmware       : \(snapshot.firmwareRevision ?? "-")")
        lines.append(
            "media backend  : "
                + ModemFirmwareCapability
                    .backend(forRevision: snapshot.firmwareRevision)
                    .rawValue
        )
        lines.append(
            "firmware known : "
                + (ModemFirmwareCapability.isVerified(revision: snapshot.firmwareRevision)
                    ? "yes"
                    : "no")
        )
        lines.append("imei           : \(snapshot.moduleIMEI ?? "-")")
        lines.append("adb            : \(flag(snapshot.usbConfiguration?.adbEnabled))")
        lines.append("usb audio      : \(flag(snapshot.usbConfiguration?.audioEnabled))")
        lines.append("location id    : \(snapshot.usbLocationID.map { String(format: "0x%08X", $0) } ?? "-")")
        lines.append("")

        lines.append("== Last verified configuration ==")
        if let lastVerified {
            lines.append("mode           : \(lastVerified.mode?.rawValue ?? "unrecognised")")
            lines.append("usbcfg         : \(lastVerified.configuration.usbcfgValueDescription)")
            lines.append("usbnet         : \(lastVerified.usbNetMode)")
            lines.append("firmware       : \(lastVerified.firmwareRevision ?? "-")")
            lines.append("imei           : \(lastVerified.imei ?? "-")")
            lines.append("recorded       : \(stamp.string(from: lastVerified.recordedAt))")
        } else {
            lines.append("(none recorded)")
        }
        lines.append("")

        lines.append("== Mode switch log (\(log.count) entries, newest first) ==")
        if log.isEmpty {
            lines.append("(no switches recorded)")
        } else {
            for entry in log {
                let outcome = entry.succeeded ? "OK  " : "FAIL"
                let seconds = String(format: "%.1fs", entry.duration)
                lines.append(
                    "\(stamp.string(from: entry.startedAt))  \(outcome)  "
                        + "-> \(entry.targetMode.rawValue)  (\(seconds))"
                )
                if !entry.detail.isEmpty {
                    lines.append("    \(entry.detail)")
                }
            }
        }
        lines.append("")

        lines.append("== Known modes ==")
        for mode in ModemMode.allCases {
            lines.append(
                "\(mode.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)): "
                    + mode.configuration.usbcfgValueDescription
                    + " · usbnet=\(mode.requiredUSBNetMode)"
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func flag(_ enabled: Bool?) -> String {
        guard let enabled else { return "-" }
        return enabled ? "on" : "off"
    }
}
