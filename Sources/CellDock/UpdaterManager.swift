import AppKit
import Combine
import Foundation
import Sparkle

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    static let defaultsKey = "CellDockUpdateChannel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable: return L10n.tr("稳定版")
        case .beta: return L10n.tr("测试版")
        }
    }

    fileprivate var feedURL: String {
        "https://celldock.app/\(rawValue)/appcast.xml"
    }
}

@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    private var controller: SPUStandardUpdaterController!

    @Published private(set) var canCheckForUpdates = false
    @Published var channel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: UpdateChannel.defaultsKey)
        }
    }

    /// Pinned off for this fork.
    ///
    /// The setter used to write straight through to Sparkle, which persists the
    /// value in its own preferences. With the updater unstarted that looks
    /// harmless — but it arms the setting, so whoever re-enables the updater
    /// later inherits automatic checks already switched on, pointing at an
    /// appcast for the project this was forked from.
    ///
    /// Reporting false unconditionally also keeps the Settings toggle honest:
    /// it shows the state that actually applies.
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set {
            // Ignored on purpose. Re-enabling updates takes more than a toggle:
            // it needs an appcast that serves this build. See `start()`.
        }
    }

    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
        return L10n.tr("版本 %@（构建 %@）", version, build)
    }

    private override init() {
        let storedChannel = UserDefaults.standard.string(forKey: UpdateChannel.defaultsKey)
        channel = UpdateChannel(rawValue: storedChannel ?? "") ?? .stable
        super.init()

        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Deliberately does not start the updater.
    ///
    /// This build is a fork carrying the multi-mode rework. The upstream
    /// appcast advertises the project it was forked from, so letting Sparkle
    /// run would eventually offer an "update" that replaces this build with
    /// one that has none of these changes — silently, and with no way back
    /// short of rebuilding from source.
    ///
    /// Leaving the updater unstarted also keeps `canCheckForUpdates` false,
    /// which disables the Check for Updates control in Settings instead of
    /// letting it fail in the user's face.
    func start() {
        // Intentionally empty. See the note above before re-enabling: doing so
        // requires an appcast that serves *this* build, not upstream's.
    }

    func checkForUpdates() {
        // No-op for the same reason. The control that calls this is disabled
        // anyway, since the updater was never started.
    }

    /// Returns nil so that Sparkle has nowhere to look even if the updater is
    /// somehow started. This delegate overrides `SUFeedURL` in Info.plist, so
    /// it — not the plist — is what actually decides.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        nil
    }
}
