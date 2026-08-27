import AppKit
import SwiftUI

enum PhoneWindowSection: String, CaseIterable, Identifiable {
    case messages
    case dialer
    case recents
    case contacts
    case recordings
    case proxy
    case sim
    case moduleMode
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: return L10n.tr("短信")
        case .dialer: return L10n.tr("拨号")
        case .recents: return L10n.tr("最近通话")
        case .contacts: return L10n.tr("通讯录")
        case .recordings: return L10n.tr("通话录音")
        case .proxy: return L10n.tr("代理")
        case .sim: return L10n.tr("SIM 卡")
        case .moduleMode: return L10n.tr("模块模式")
        case .settings: return L10n.tr("设置")
        }
    }

    var systemImage: String {
        switch self {
        case .messages: return "message"
        case .dialer: return "circle.grid.3x3.fill"
        case .recents: return "clock.arrow.circlepath"
        case .contacts: return "person.crop.circle"
        case .recordings: return "waveform"
        case .proxy: return "point.forward.to.point.capsulepath"
        case .sim: return "simcard"
        case .moduleMode: return "arrow.left.arrow.right.circle"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class PhoneWindowModel: ObservableObject {
    @Published var selection: PhoneWindowSection = .messages
    @Published private(set) var prefersFullCallPresentation = false
    @Published private(set) var pendingListFocusSection: PhoneWindowSection?
    @Published var dialNumber = ""
    @Published var selectedCallRecordID: CallHistoryRecord.ID?
    @Published var selectedRecordingID: CallRecordingRecord.ID?
    @Published private(set) var callRecordRequestSerial = 0
    @Published private(set) var requestedCallRecordID: CallHistoryRecord.ID?
    @Published private(set) var simModuleRequestSerial = 0
    @Published private(set) var requestedSIMModuleID: CellularModuleID?

    var onCallPresentationChange: (() -> Void)?

    func activateFromRail(_ section: PhoneWindowSection) {
        setFullCallPresentation(false)
        pendingListFocusSection = section
        selection = section
    }

    func setFullCallPresentation(_ isFull: Bool) {
        guard prefersFullCallPresentation != isFull else { return }
        prefersFullCallPresentation = isFull
        onCallPresentationChange?()
    }

    func consumeListFocusRequest(for section: PhoneWindowSection) {
        guard pendingListFocusSection == section else { return }
        pendingListFocusSection = nil
    }

    func present(
        number: String?,
        section: PhoneWindowSection?,
        callRecordID: CallHistoryRecord.ID? = nil,
        simModuleID: CellularModuleID? = nil
    ) {
        if number != nil || section != nil || callRecordID != nil || simModuleID != nil {
            setFullCallPresentation(false)
        }
        if let section { selection = section }
        if let callRecordID {
            requestedCallRecordID = callRecordID
            selectedCallRecordID = callRecordID
            selection = .recents
            callRecordRequestSerial &+= 1
        }
        if let simModuleID {
            requestedSIMModuleID = simModuleID
            selection = .sim
            simModuleRequestSerial &+= 1
        }
        if let number, !number.isEmpty {
            dialNumber = number
            selection = .dialer
        }
    }
}

@MainActor
final class MessagesWindowModel: ObservableObject {
    @Published private(set) var requestSerial = 0
    @Published private(set) var composeSerial = 0
    @Published private(set) var requestedMessageID: SMSMessage.ID?
    @Published private(set) var requestedDestination: String?

    func present(messageID: SMSMessage.ID? = nil, destination: String? = nil) {
        requestedMessageID = messageID
        requestedDestination = destination
        requestSerial &+= 1
    }

    func beginComposing() {
        composeSerial &+= 1
    }
}

@MainActor
final class CommunicationWindowController: NSObject, NSWindowDelegate {
    static let shared = CommunicationWindowController()

    private enum Kind: Hashable {
        case phone
        case messages
    }

    let phoneModel = PhoneWindowModel()
    let messagesModel = MessagesWindowModel()

    private weak var appState: AppState?
    private var windows: [Kind: NSWindow] = [:]

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appLanguageDidChange),
            name: .cellDockAppLanguageDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appActivationDidChange),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appActivationDidChange),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    var hasVisibleWindows: Bool {
        windows.values.contains(where: \.isVisible)
    }

    func configure(appState: AppState) {
        self.appState = appState
        phoneModel.onCallPresentationChange = { [weak self] in
            self?.updateCallIslandVisibility()
        }
        CallIslandWindowController.shared.configure(
            appState: appState,
            onOpenFullCall: { [weak self] in
                self?.showCurrentCall()
            }
        )
    }

    /// Reopens the primary communication window without changing the section
    /// that was selected before the window closed. A newly-created model starts
    /// on Messages, so this also gives first-time Dock reopens the expected page.
    func handleApplicationReopen() {
        show(.phone)
    }

    func showPhone(
        number: String? = nil,
        section: PhoneWindowSection? = nil,
        callRecordID: CallHistoryRecord.ID? = nil,
        simModuleID: CellularModuleID? = nil
    ) {
        phoneModel.present(
            number: number,
            section: section ?? (number == nil ? .recents : nil),
            callRecordID: callRecordID,
            simModuleID: simModuleID
        )
        if phoneModel.selection == .recents {
            appState?.callHistory.acknowledgeMissedCalls()
        }
        show(.phone)
    }

    func showMessages(
        messageID: SMSMessage.ID? = nil,
        destination: String? = nil
    ) {
        messagesModel.present(messageID: messageID, destination: destination)
        phoneModel.activateFromRail(.messages)
        show(.phone)
    }

    func showCurrentCall() {
        guard appState?.call.hasCall == true else { return }
        phoneModel.setFullCallPresentation(true)
        show(.phone)
    }

    func callDidChange(previousHadCall: Bool) {
        guard let appState else { return }
        if appState.call.hasCall {
            if !previousHadCall {
                let phoneWindow = windows[.phone]
                let canPresentFullCall = NSApplication.shared.isActive &&
                    phoneWindow?.isVisible == true &&
                    phoneWindow?.isKeyWindow == true
                phoneModel.setFullCallPresentation(canPresentFullCall)
            }
        } else {
            phoneModel.setFullCallPresentation(false)
        }
        updateCallIslandVisibility()
    }

    var isPresentingCallUI: Bool {
        isFullCallForeground || CallIslandWindowController.shared.isVisible
    }

    private func show(_ kind: Kind) {
        guard let appState else { return }
        let window: NSWindow
        if let existing = windows[kind] {
            window = existing
        } else {
            let hostingController: NSHostingController<AnyView>
            switch kind {
            case .phone:
                hostingController = NSHostingController(
                    rootView: AnyView(
                        PhoneWindowView(
                            model: phoneModel,
                            messagesModel: messagesModel,
                            contacts: SystemContactStore.shared
                        )
                        .environmentObject(appState)
                        .cellDockLanguageEnvironment()
                    )
                )
            case .messages:
                hostingController = NSHostingController(
                    rootView: AnyView(
                        MessagesWindowView(
                            model: messagesModel,
                            contacts: SystemContactStore.shared,
                            sidebarWidth: .constant(CommunicationUI.sidebarWidth)
                        )
                        .environmentObject(appState)
                        .cellDockLanguageEnvironment()
                    )
                )
            }

            window = NSWindow(contentViewController: hostingController)
            window.title = kind == .phone ? communicationWindowTitle : L10n.tr("短信")
            window.styleMask = [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar = nil
            window.titlebarSeparatorStyle = .none
            // The full-size SwiftUI content replaces the visible title bar, so
            // let unhandled background regions retain native window dragging.
            window.isMovable = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.delegate = self
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            switch kind {
            case .phone:
                window.minSize = NSSize(width: 700, height: 480)
                window.setContentSize(NSSize(width: 700, height: 480))
                window.setFrameAutosaveName("CellDockCommunicationWindow.v5")
            case .messages:
                window.minSize = NSSize(width: 680, height: 480)
                window.setContentSize(NSSize(width: 720, height: 500))
                window.setFrameAutosaveName("CellDockMessagesWindow.v4")
            }
            window.center()
            windows[kind] = window
        }

        if kind == .phone {
            window.title = communicationWindowTitle
        }

        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.updateCallIslandVisibility()
        }
    }

    func refreshCommunicationWindowTitle() {
        windows[.phone]?.title = communicationWindowTitle
    }

    @objc private func appLanguageDidChange() {
        windows[.phone]?.title = communicationWindowTitle
        windows[.messages]?.title = L10n.tr("短信")
    }

    @objc private func appActivationDidChange() {
        updateCallIslandVisibility()
    }

    private var communicationWindowTitle: String {
        switch phoneModel.selection {
        case .messages: return L10n.tr("短信")
        case .recents, .dialer, .contacts: return L10n.tr("最近通话")
        case .recordings: return L10n.tr("通话录音")
        case .proxy: return L10n.tr("代理")
        case .sim: return L10n.tr("SIM 卡")
        case .moduleMode: return L10n.tr("模块模式")
        case .settings: return L10n.tr("设置")
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateCallIslandVisibility()
            guard
                  !self.hasVisibleWindows,
                  !MainWindowController.shared.isVisible,
                  !StandaloneFlowWindowController.shared.hasVisibleWindows,
                  !InitialSetupWindowController.shared.isVisible else {
                return
            }
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateCallIslandVisibility()
    }

    func windowDidResignKey(_ notification: Notification) {
        updateCallIslandVisibility()
    }

    private var isFullCallForeground: Bool {
        guard let window = windows[.phone] else { return false }
        return appState?.call.hasCall == true &&
            phoneModel.prefersFullCallPresentation &&
            NSApplication.shared.isActive &&
            window.isVisible &&
            window.isKeyWindow
    }

    private func updateCallIslandVisibility() {
        guard let appState else { return }
        let alwaysShowsIncomingIsland = appState.call.phase == .incoming
        CallIslandWindowController.shared.updateVisibility(
            shouldShow: appState.call.hasCall &&
                (alwaysShowsIncomingIsland || !isFullCallForeground)
        )
    }
}
