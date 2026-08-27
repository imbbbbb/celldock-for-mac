import Foundation

/// User-assigned labels for physical modules.
///
/// Keyed by IMEI rather than by USB location or session identity. A label
/// exists to tell one physical module from another, so it has to survive the
/// two things that routinely change: moving the module to a different USB
/// port, and switching its USB identity between the DJI and Quectel modes.
/// The IMEI is the only identifier stable across both — verified on hardware,
/// where it stayed the same while the VID/PID changed from 2CA3:4006 to
/// 2C7C:0125.
enum ModuleLabelStore {
    private static let defaultsKey = "ModuleLabels.v1"

    /// Long enough to be descriptive, short enough to sit in a module picker
    /// row without truncating everything else.
    static let maximumLength = 40

    static func label(forIMEI imei: String?) -> String? {
        guard let key = normalize(imei) else { return nil }
        return table()[key]
    }

    /// Passing nil or an all-whitespace label clears it, so the module falls
    /// back to its generated name rather than showing an empty title.
    static func setLabel(_ label: String?, forIMEI imei: String?) {
        guard let key = normalize(imei) else { return }
        var current = table()
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            current[key] = String(trimmed.prefix(maximumLength))
        } else {
            current.removeValue(forKey: key)
        }
        UserDefaults.standard.set(current, forKey: defaultsKey)
    }

    private static func table() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private static func normalize(_ imei: String?) -> String? {
        guard let imei else { return nil }
        let trimmed = imei.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
