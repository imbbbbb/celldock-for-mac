import Foundation

/// A configuration the module was observed working in, captured before a mode
/// switch overwrites it.
///
/// This is the rollback target for "restore the last verified configuration".
/// Only configurations that matched a known mode are ever recorded: a snapshot
/// of a half-written or unrecognised tuple would be a trap, not a way back.
struct ModeConfigurationSnapshot: Equatable, Codable {
    let configuration: ModemUSBConfiguration
    let usbNetMode: Int
    let firmwareRevision: String?
    let imei: String?
    let recordedAt: Date

    /// The mode this snapshot can be restored to, if it still maps to one.
    var mode: ModemMode? {
        configuration.mode
    }

    var compactDescription: String {
        "\(configuration.usbcfgValueDescription) · usbnet=\(usbNetMode)"
    }
}

/// Persists the last verified configuration per physical module.
///
/// Keyed by IMEI rather than VID/PID, because the identity a module reports
/// changes with the mode while the IMEI does not — keying on VID/PID would file
/// the same module under two different entries and lose the rollback target
/// exactly when a switch went wrong.
enum ModeConfigurationSnapshotStore {
    private static let defaultsKey = "ModuleModeSnapshots.v1"
    private static let unknownModuleKey = "unknown-module"

    /// Recording is a read-modify-write over one shared table, and each
    /// `ModemService` runs on its own serial queue — so two modules switching
    /// at once really can race here. Losing that write would delete a module's
    /// rollback target, which is the one thing needed when a switch goes wrong.
    /// Reads are locked too, since the UI reads from the main thread.
    private static let lock = NSLock()

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func record(_ snapshot: ModeConfigurationSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        var table = loadTable()
        table[key(for: snapshot.imei)] = snapshot
        guard let data = try? encoder.encode(table) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func snapshot(forIMEI imei: String?) -> ModeConfigurationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return loadTable()[key(for: imei)]
    }

    /// Every stored snapshot, newest first. Used by the diagnostic export.
    static func allSnapshots() -> [ModeConfigurationSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return loadTable().values.sorted { $0.recordedAt > $1.recordedAt }
    }

    private static func loadTable() -> [String: ModeConfigurationSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let table = try? decoder.decode(
                  [String: ModeConfigurationSnapshot].self,
                  from: data
              ) else {
            return [:]
        }
        return table
    }

    private static func key(for imei: String?) -> String {
        guard let imei else { return unknownModuleKey }
        let trimmed = imei.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unknownModuleKey : trimmed
    }
}
