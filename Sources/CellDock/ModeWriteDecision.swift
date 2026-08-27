import Foundation

/// What should happen after the module was asked to write a configuration.
///
/// Separated from the I/O so every branch is testable without hardware —
/// including the two that are unsafe to reproduce on a real module: a write
/// whose outcome the transport could not determine, and a read-back that
/// disagrees with the target.
enum ModeWriteDecision: Equatable {
    /// Read-back matched the target exactly. Carries the credential the restart
    /// path requires.
    case commit(VerifiedModeWrite)
    /// The transport could not tell whether the module received the write. The
    /// configuration may already be correct, so the module is left alone and
    /// re-read once it re-enumerates. Never retried.
    case indeterminate
    /// The module refused the write. Nothing changed.
    case rejected(String?)
    /// The write reported success but the read-back disagrees. The module must
    /// not be restarted.
    case verificationFailed

    /// How the module answered the write itself.
    enum WriteOutcome: Equatable {
        case succeeded
        case rejected(String?)
        /// The AT interface went away mid-write, most likely because the module
        /// re-enumerated — which means the write may well have landed.
        case ambiguous
    }

    /// `readBack` is a closure rather than a value because reading back is
    /// itself an AT round-trip: after an ambiguous write the interface is
    /// probably gone, and issuing more commands against it is pointless. The
    /// closure is only invoked on the one path where a read-back is meaningful.
    static func decide(
        target: ModemMode,
        write: WriteOutcome,
        readBack: () -> (configuration: ModemUSBConfiguration?, usbNetMode: Int?)
    ) -> ModeWriteDecision {
        switch write {
        case .ambiguous:
            // Checked before anything else. Re-issuing an ambiguous write would
            // write a second time against a state nobody knows, which is how a
            // recoverable situation becomes an unrecoverable one.
            return .indeterminate
        case let .rejected(message):
            return .rejected(message)
        case .succeeded:
            let observed = readBack()
            guard let verified = VerifiedModeWrite.verify(
                target: target,
                readBackConfiguration: observed.configuration,
                readBackUSBNetMode: observed.usbNetMode
            ) else {
                return .verificationFailed
            }
            return .commit(verified)
        }
    }
}
