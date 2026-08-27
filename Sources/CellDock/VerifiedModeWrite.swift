import Foundation

/// Proof that a target mode was written to the module *and* read back matching
/// field for field.
///
/// This type exists to make one specific mistake unrepresentable. Restarting
/// the module with `AT+CFUN=1,1` after a write that did not verify is the one
/// failure that cannot be recovered from the host side — the module comes back
/// with a configuration nobody intended, possibly without the AT interface that
/// would let CellDock fix it. So the restart path takes a `VerifiedModeWrite`
/// as its argument, `init` is private, and `verify(target:readBack…)` is the
/// only way to obtain one. Living in its own file keeps the private initializer
/// genuinely out of reach: Swift's `private` is file-scoped, so a caller in
/// `ModemService` cannot fabricate this value even by accident.
struct VerifiedModeWrite: Equatable {
    let mode: ModemMode

    private init(mode: ModemMode) {
        self.mode = mode
    }

    /// Returns a credential only when the module's own read-back matches the
    /// target exactly.
    ///
    /// The comparison is whole-value: `ModemUSBConfiguration` carries the
    /// vendor ID, product ID and all seven USBCFG flags, so equality here *is*
    /// the field-by-field check, and a mode can never be accepted with a
    /// mismatched USB identity. `usbnet` is verified separately because the
    /// module stores it outside USBCFG.
    static func verify(
        target: ModemMode,
        readBackConfiguration: ModemUSBConfiguration?,
        readBackUSBNetMode: Int?
    ) -> VerifiedModeWrite? {
        guard let readBackConfiguration,
              readBackConfiguration == target.configuration,
              let readBackUSBNetMode,
              readBackUSBNetMode == target.requiredUSBNetMode else {
            return nil
        }
        return VerifiedModeWrite(mode: target)
    }
}
