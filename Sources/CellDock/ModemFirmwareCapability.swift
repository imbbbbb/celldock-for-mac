import Foundation

/// Which media path a firmware actually supports for USB call audio.
enum ModemMediaBackendKind: String, Equatable, CaseIterable {
    /// Custom QDC firmware: module-side ADB helper, D4/AFE routing and
    /// `/sys/class/android_usb/f_audio/audio_enable`.
    case qdcADBHelper
    /// Stock Quectel firmware where standard QPCMV/UAC genuinely works.
    case standardQuectelUAC
    /// Raw USB PCM over the NMEA/PCM interface.
    case rawUSBPCM
    /// No usable call-audio path. Calls degrade; everything else keeps working.
    case unsupported
}

/// Maps firmware revisions to the media backend verified on real hardware.
///
/// Capability is deliberately **not** inferred from `AT+QPCMV=?`. On the
/// verified QDC507 firmware that query reports `(0,1),(0-2)` — advertising a
/// control interface the firmware does not actually implement — while both
/// `AT+QPCMV?` and `AT+QPCMV=0` return ERROR. Trusting the advertisement is
/// how the audio path gets wedged, so standard QPCMV is only ever sent to
/// firmware verified to implement it.
enum ModemFirmwareCapability {
    /// Firmware revisions verified on hardware, keyed by the `AT+QGMR` revision
    /// in upper case. Anything absent here is treated as unsupported rather
    /// than probed, because a wrong guess is unrecoverable from the host side.
    private static let verifiedBackends: [String: ModemMediaBackendKind] = [
        "QDC507GLEFM21_01.001.01.007": .qdcADBHelper
    ]

    static func backend(forRevision revision: String?) -> ModemMediaBackendKind {
        guard let normalized = normalize(revision) else { return .unsupported }
        return verifiedBackends[normalized] ?? .unsupported
    }

    /// Whether this firmware has been verified at all. Unverified firmware is
    /// still allowed to run — cellular data, SMS, eSIM and status all work —
    /// it just does not get a call-audio path.
    static func isVerified(revision: String?) -> Bool {
        guard let normalized = normalize(revision) else { return false }
        return verifiedBackends[normalized] != nil
    }

    /// Whether standard QPCMV control commands may be sent to this firmware.
    ///
    /// Only firmware verified as `.standardQuectelUAC` qualifies. Custom QDC
    /// firmware and unknown firmware are both refused.
    static func allowsStandardQPCMV(revision: String?) -> Bool {
        backend(forRevision: revision) == .standardQuectelUAC
    }

    /// Whether it is safe to write a configuration that enables USB audio.
    ///
    /// A verified firmware answers from the table. For unverified firmware we
    /// fall back to the module's own `AT+QPCMV=?` advertisement — not because
    /// it is trustworthy, but because refusing outright would strand modules
    /// this build has never seen. The caller must pass what the module actually
    /// reported; `nil` means the query failed and the write is refused.
    static func permitsEnablingUSBAudio(
        revision: String?,
        advertisesUACMode: Bool?
    ) -> Bool {
        switch backend(forRevision: revision) {
        case .qdcADBHelper, .standardQuectelUAC:
            return true
        case .rawUSBPCM:
            return false
        case .unsupported:
            return advertisesUACMode == true
        }
    }

    /// Picks the firmware revision out of an `AT+QGMR` response.
    ///
    /// Matches the *shape* of a revision rather than merely excluding known
    /// noise: `QDC507GLEFM21_01.001.01.007` has no spaces and carries a
    /// separator, while stray URCs that land in the same buffer (`RDY`,
    /// `+CPIN: READY`, `+QUSIM: 1`) have neither.
    ///
    /// Returning nil is the safe failure. A bogus revision makes verified
    /// firmware look unknown, which sends the audio gate back to the module's
    /// own `AT+QPCMV=?` advertisement — the very claim this type exists because
    /// it cannot be trusted. "Unknown" is at least honest.
    static func revision(fromResponseLines lines: [String]) -> String? {
        lines.first { line in
            let upper = line.uppercased()
            guard !upper.isEmpty,
                  upper != "OK",
                  upper != "ERROR",
                  !upper.hasPrefix("AT"),
                  !upper.hasPrefix("+") else {
                return false
            }
            return !upper.contains(" ")
                && upper.count >= 8
                && (upper.contains("_") || upper.contains("."))
        }
    }

    private static func normalize(_ revision: String?) -> String? {
        guard let revision else { return nil }
        let trimmed = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }
}
