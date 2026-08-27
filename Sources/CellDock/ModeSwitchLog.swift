import Foundation

/// One recorded attempt to switch the module's mode, successful or not.
///
/// Refused and failed attempts matter more than successful ones here: they are
/// the record of what the module was asked to do and why the transaction
/// stopped, which is exactly what is missing when someone reports that a
/// switch "did not work".
struct ModeSwitchLogEntry: Equatable, Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let targetMode: ModemMode
    let succeeded: Bool
    /// The message shown to the user. Every failure branch of the transaction
    /// has distinct wording, so this pinpoints where the switch stopped —
    /// refused before unlocking, read-back mismatch, ambiguous write, and so on.
    let detail: String

    var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }
}

/// A bounded, persisted history of mode-switch attempts.
enum ModeSwitchLogStore {
    private static let defaultsKey = "ModuleModeSwitchLog.v1"

    /// Old attempts are diagnostic history, not evidence worth unbounded disk.
    private static let maximumEntries = 50

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

    static func append(
        targetMode: ModemMode,
        startedAt: Date,
        result: ModemActionResult
    ) {
        let succeeded: Bool
        let detail: String
        switch result {
        case let .success(message):
            succeeded = true
            detail = message ?? ""
        case let .failure(message):
            succeeded = false
            detail = message
        }

        let entry = ModeSwitchLogEntry(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: Date(),
            targetMode: targetMode,
            succeeded: succeeded,
            detail: detail
        )

        var entries = allEntries()
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    /// Oldest first, matching the order they were appended.
    static func allEntries() -> [ModeSwitchLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? decoder.decode(
                  [ModeSwitchLogEntry].self,
                  from: data
              ) else {
            return []
        }
        return entries
    }

    /// Newest first, for display.
    static func recentEntries(limit: Int) -> [ModeSwitchLogEntry] {
        Array(allEntries().reversed().prefix(limit))
    }
}
