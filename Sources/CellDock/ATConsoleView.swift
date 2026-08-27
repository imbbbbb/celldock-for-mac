import AppKit
import SwiftUI

struct ATConsoleView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?
    private let embedded: Bool
    private let targetModuleID: CellularModuleID?
    @State private var command = ""
    @State private var results: [ATConsoleExecutionResult] = []
    @State private var localError: String?
    @State private var commandFocused = false
    @State private var hostWindow: NSWindow?
    /// Whether this console is the one that suspended background dragging, so
    /// it only hands the setting back if it actually took it away.
    @State private var didSuspendBackgroundDragging = false

    private let suggestions = [
        "AT", "ATI", "AT+CSQ", "AT+QCSQ", "AT+COPS?", "AT+CPIN?"
    ]

    init(
        embedded: Bool = false,
        targetModuleID: CellularModuleID? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.embedded = embedded
        self.targetModuleID = targetModuleID
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if embedded {
                AdaptiveGlassContainer(spacing: 14) {
                    consoleContent
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    AdaptiveGlassBackdrop()
                        .ignoresSafeArea()

                    AdaptiveGlassContainer(spacing: 14) {
                        consoleContent
                    }
                    .padding(22)
                }
                .frame(width: 700, height: 560)
            }
        }
        .background(WindowAccessor(window: $hostWindow))
        .onChange(of: hostWindow) { _, window in
            suspendBackgroundDragging(on: window)
        }
        .onAppear {
            // This console writes directly to the module, so a command left
            // over from a previous visit must never sit one Return away from
            // being sent. SwiftUI keeps this view's state across section
            // switches, so clearing on appear is what actually guarantees it.
            command = ""
            localError = nil
            commandFocused = true
            suspendBackgroundDragging(on: hostWindow)
        }
        .onDisappear {
            commandFocused = false
            if didSuspendBackgroundDragging {
                hostWindow?.isMovableByWindowBackground = true
                didSuspendBackgroundDragging = false
            }
        }
    }

    private var consoleContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            commandArea
            outputArea
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .adaptiveGlassSurface(cornerRadius: 12, treatment: .clear)
            VStack(alignment: .leading, spacing: 2) {
                Text("AT 控制台")
                    .font(.title2.weight(.semibold))
                Text("通过当前模块的 interface 2 执行单行命令")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(targetModem.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(targetModem.isConnected ? L10n.tr("所选模组已连接") : L10n.tr("所选模组未连接"))
                    .font(.caption.weight(.medium))
            }
            if !embedded {
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 18, height: 18)
                }
                .adaptiveGlassButton()
                .controlSize(.small)
                .disabled(appState.isExecutingAT)
                .accessibilityLabel(L10n.tr("关闭 AT 控制台"))
            }
        }
    }

    private var commandArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DragResistantTextField(
                    text: $command,
                    placeholder: L10n.tr("例如 AT+QCSQ"),
                    focus: $commandFocused,
                    isMonospaced: true,
                    onSubmit: { execute() }
                )
                .frame(minWidth: 0, minHeight: 22)
                Button {
                    execute()
                } label: {
                    if appState.isExecutingAT {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("执行中")
                        }
                    } else {
                        Label("执行", systemImage: "play.fill")
                    }
                }
                .adaptiveGlassButton(.prominent)
                .disabled(!canExecute)
                .keyboardShortcut(.return, modifiers: .command)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Text("常用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            command = suggestion
                            localError = nil
                            commandFocused = true
                        }
                        .adaptiveGlassButton()
                        .controlSize(.small)
                        .font(.caption.monospaced())
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }

            if let localError {
                Label(localError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if appState.moduleHasCall(targetModuleID) {
                Label("通话期间暂停手动 AT，避免改变通话和音频状态。", systemImage: "phone.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .adaptiveGlassCard()
    }

    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("执行记录", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                if !results.isEmpty {
                    Button(L10n.tr("复制全部")) { copyAll() }
                        .adaptiveGlassButton()
                        .controlSize(.small)
                        .help(L10n.tr("复制全部执行记录"))
                    Button("清空") { results.removeAll() }
                        .adaptiveGlassButton()
                        .controlSize(.small)
                }
            }

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("尚未执行命令")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { result in
                            resultRow(result)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .defaultScrollAnchor(.top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .adaptiveGlassCard()
    }

    private func resultRow(_ result: ATConsoleExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("> \(result.command)")
                    .font(.subheadline.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                Circle()
                    .fill(result.isSuccess ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(result.isSuccess ? L10n.tr("完成") : L10n.tr("失败"))
                    .font(.caption.weight(.medium))
                Text("\(result.elapsedMilliseconds) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    copy(result)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .adaptiveGlassButton()
                .controlSize(.mini)
                .help("复制命令和返回")
            }

            Text(result.output.isEmpty ? L10n.tr("（模块没有返回文本）") : result.output)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(result.isSuccess ? Color.primary : Color.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = result.error,
               !result.output.localizedCaseInsensitiveContains(error) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(11)
        .adaptiveGlassSurface(
            cornerRadius: 12,
            treatment: .clear,
            tint: (result.isSuccess ? Color.green : Color.red).opacity(0.045)
        )
    }

    private var footer: some View {
        HStack {
            Label("命令直接作用于模块，不自动重试；不支持需要 > 载荷的数据命令。", systemImage: "exclamationmark.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            if !embedded {
                Button("关闭") { close() }
                    .adaptiveGlassButton()
                    .disabled(appState.isExecutingAT)
            }
        }
    }

    private var canExecute: Bool {
        targetModem.isConnected &&
            !appState.moduleHasCall(targetModuleID) &&
            !appState.isExecutingAT &&
            !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func execute() {
        localError = nil
        do {
            command = try ATConsoleCommandValidator.validate(command)
        } catch {
            localError = error.localizedDescription
            return
        }
        guard canExecute else { return }
        let submittedCommand = command
        appState.executeAT(submittedCommand, via: targetModuleID) { result in
            results.insert(result, at: 0)
            if results.count > 50 {
                results.removeLast(results.count - 50)
            }
            if !result.isSuccess, result.output.isEmpty {
                localError = result.error
            }
            // Terminal convention: the command has moved into the log, so the
            // input line clears. It also means nothing stale can be left behind
            // when the user navigates away.
            command = ""
            commandFocused = true
        }
    }

    private var targetModem: ModemSnapshot {
        appState.communicationModuleSnapshot(targetModuleID)
    }

    private func copy(_ result: ATConsoleExecutionResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript(for: result), forType: .string)
    }

    /// Copies the whole log in the order it is displayed, so what lands on the
    /// clipboard matches what the user is looking at. SwiftUI cannot extend a
    /// text selection across separate `Text` views, so without this the only
    /// way to collect a session is one entry at a time.
    private func copyAll() {
        let text = results.map(transcript(for:)).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func transcript(for result: ATConsoleExecutionResult) -> String {
        [
            "> \(result.command)",
            result.output,
            result.error.map { L10n.tr("错误：%@", $0) }
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Suspends the window's background dragging while the console is on screen.
    ///
    /// The communication window has no visible title bar, so it opts into
    /// `isMovableByWindowBackground` to stay draggable. In a console that turns
    /// a drag across the command line into a window drag, which makes selecting
    /// text impossible. Overriding `mouseDownCanMoveWindow` on the field should
    /// be enough on its own; this is the belt to that pair of braces, and it is
    /// scoped to the console — every other section keeps background dragging.
    private func suspendBackgroundDragging(on window: NSWindow?) {
        guard let window, window.isMovableByWindowBackground else { return }
        didSuspendBackgroundDragging = true
        window.isMovableByWindowBackground = false
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

/// Exposes the hosting `NSWindow` so the console can adjust window-level
/// behaviour that SwiftUI does not surface.
private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view is not in a window yet during `makeNSView`.
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard window !== nsView.window else { return }
        DispatchQueue.main.async { window = nsView.window }
    }
}

