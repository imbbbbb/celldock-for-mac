import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Mode switching and the diagnostic snapshot the recovery flow needs.
///
/// This lives in Settings rather than in the initial-setup window on purpose.
/// Setup is a one-shot onboarding flow that dismisses itself as soon as the
/// module reports `.ready` and then never reappears, so a module sitting in DJI
/// or iPhone/iPad mode would have no route back to full Mac functionality if
/// switching were only offered there.
struct ModuleModeRecoveryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pendingMode: ModemMode?
    @State private var moduleLabelDraft = ""
    @State private var selectedModuleID: CellularModuleID?

    /// The module this page acts on.
    ///
    /// With several modules attached, every reading shown here and every action
    /// taken here must refer to the same one. Showing one module's diagnostics
    /// while writing another's configuration is the failure this guards
    /// against — and it would be invisible until the wrong module rebooted.
    private var targetModem: ModemSnapshot {
        appState.communicationModuleSnapshot(selectedModuleID)
    }

    var body: some View {
        VStack(spacing: 16) {
            modulePicker
            statusSection
            if let pendingMode {
                confirmationSection(pendingMode)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            recoverySection
            modeSection
            logSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.22), value: pendingMode)
        .onChange(of: targetModem.usbConfiguration) { _, _ in
            pendingMode = nil
        }
        .onAppear {
            if selectedModuleID == nil {
                selectedModuleID = appState.currentCommunicationModuleID
                    ?? appState.cellularModules.first?.id
            }
            loadModuleLabelDraft()
        }
        .onChange(of: targetModem.moduleIMEI) { _, _ in
            // A different physical module is now in front of us.
            loadModuleLabelDraft()
        }
        .onChange(of: selectedModuleID) { _, _ in
            // Any pending confirmation belonged to the previous module.
            pendingMode = nil
            loadModuleLabelDraft()
        }
    }

    private var currentMode: ModemMode? {
        targetModem.usbConfiguration?.mode
    }

    private var isBusy: Bool {
        appState.isConvertingModuleIdentity
    }

    /// A configuration write must never race a call or another write. The call
    /// check is scoped to the target module: another module being on a call is
    /// no reason to refuse switching this one.
    private var canSwitch: Bool {
        targetModem.isConnected && !isBusy && !appState.moduleHasCall(selectedModuleID)
    }

    /// Only shown when there is a choice to make. With one module attached a
    /// picker would be noise; with several, acting on the wrong one is the
    /// whole risk.
    @ViewBuilder
    private var modulePicker: some View {
        let modules = appState.cellularModules
        if modules.count > 1 {
            HStack(spacing: 10) {
                Text(L10n.tr("模块"))
                    .font(.subheadline.weight(.medium))
                Picker(L10n.tr("模块"), selection: $selectedModuleID) {
                    ForEach(modules) { module in
                        Text(module.selectorTitle).tag(Optional(module.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("模块状态"))
                .font(.headline)

            VStack(spacing: 8) {
                statusRow(L10n.tr("当前模式"), currentModeText)
                Divider()
                statusRow(
                    L10n.tr("USB 身份"),
                    targetModem.usbIdentity ?? L10n.tr("等待检测")
                )
                Divider()
                statusRow(L10n.tr("设备配置"), configurationText)
                Divider()
                statusRow(L10n.tr("联网模式"), usbNetText)
                Divider()
                statusRow(
                    L10n.tr("固件版本"),
                    targetModem.firmwareRevision ?? L10n.tr("等待检测")
                )
                Divider()
                statusRow("IMEI", targetModem.moduleIMEI ?? L10n.tr("等待检测"))
                Divider()
                moduleLabelRow
                Divider()
                statusRow("ADB", flagText(targetModem.usbConfiguration?.adbEnabled))
                Divider()
                statusRow(
                    L10n.tr("USB 通话音频"),
                    flagText(targetModem.usbConfiguration?.audioEnabled)
                )
            }
            .adaptiveGlassSurface(cornerRadius: 19, padding: 12, treatment: .clear)

            if let currentMode, !currentMode.providesCallAudio {
                Text(L10n.tr("当前模式未启用 USB 通话音频，切换到「Mac 完整功能」后恢复。短信、eSIM、联系人、代理与蜂窝网络不受影响。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isBusy {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.tr("正在写入配置…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 10)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(minHeight: 21)
    }

    private var currentModeText: String {
        currentMode?.localizedTitle ?? L10n.tr("未识别的配置")
    }

    private var configurationText: String {
        targetModem.usbConfiguration?.usbcfgValueDescription ?? L10n.tr("等待检测")
    }

    private var usbNetText: String {
        targetModem.usbNetMode.map { "usbnet=\($0)" } ?? L10n.tr("等待检测")
    }

    private func flagText(_ enabled: Bool?) -> String {
        guard let enabled else { return L10n.tr("等待检测") }
        return enabled ? L10n.tr("已启用") : L10n.tr("已关闭")
    }

    /// A name the user gives this physical module, so several of them can be
    /// told apart. Stored against the IMEI, so it follows the module across USB
    /// ports and across mode switches that change its VID/PID.
    private var moduleLabelRow: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("模块备注"))
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 10)

            DragResistantTextField(
                text: $moduleLabelDraft,
                placeholder: L10n.tr("未命名"),
                onSubmit: commitModuleLabel
            )
            .frame(maxWidth: 220, minHeight: 22)
            .disabled(targetModem.moduleIMEI == nil)
            .onChange(of: moduleLabelDraft) { _, _ in
                // Persist as the user types: this field has no confirm button,
                // and losing a name because they clicked away would be worse
                // than writing a few extra times to UserDefaults.
                commitModuleLabel()
            }
        }
        .frame(minHeight: 21)
    }

    private func commitModuleLabel() {
        appState.setModuleLabel(moduleLabelDraft, forIMEI: targetModem.moduleIMEI)
    }

    private func loadModuleLabelDraft() {
        moduleLabelDraft = appState.moduleLabel(forIMEI: targetModem.moduleIMEI) ?? ""
    }

    // MARK: - Recovery

    private static let snapshotTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("恢复"))
                .font(.headline)

            VStack(spacing: 10) {
                // Only shown when it would actually do something — that is,
                // when the module is not already in the snapshotted mode.
                if let snapshot = appState.lastVerifiedConfigurationSnapshot(for: selectedModuleID),
                   let snapshotMode = snapshot.mode,
                   snapshotMode != currentMode {
                    lastVerifiedRow(snapshot, mode: snapshotMode)
                }
                forceReleaseAudioRow
            }
        }
    }

    /// A one-click return to the configuration the module was last seen working
    /// in. Goes through the same switch transaction as any other mode change.
    private func lastVerifiedRow(
        _ snapshot: ModeConfigurationSnapshot,
        mode snapshotMode: ModemMode
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 19))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("上一次已验证配置"))
                    .font(.subheadline.weight(.semibold))
                Text(snapshotMode.localizedTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(snapshot.compactDescription)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text(Self.snapshotTimestampFormatter.string(from: snapshot.recordedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button {
                pendingMode = snapshotMode
            } label: {
                Text(L10n.tr("恢复"))
            }
            .adaptiveGlassButton()
            .disabled(!canSwitch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassSurface(cornerRadius: 17, padding: 12, treatment: .clear)
    }

    /// Always offered, including during a call — a wedged audio path is exactly
    /// when this is needed, and it leaves the call itself alone.
    private var forceReleaseAudioRow: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 19))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("强制释放通话音频"))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.tr("通话结束后 Mac 的麦克风或扬声器仍被占用时使用。主机音频立即释放，模块侧清理在后台完成。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                appState.forceReleaseCallAudio(moduleID: selectedModuleID)
            } label: {
                Text(L10n.tr("释放"))
            }
            .adaptiveGlassButton()
            .disabled(!targetModem.isConnected)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassSurface(cornerRadius: 17, padding: 12, treatment: .clear)
    }

    // MARK: - Modes

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("切换模式"))
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(ModemMode.allCases, id: \.self) { mode in
                    modeRow(mode)
                }
            }
        }
    }

    private func modeRow(_ mode: ModemMode) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: mode.systemImageName)
                .font(.system(size: 19))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(mode.localizedTitle)
                    .font(.subheadline.weight(.semibold))
                Text(mode.localizedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if currentMode == mode {
                Label(L10n.tr("使用中"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button {
                    pendingMode = mode
                } label: {
                    Text(L10n.tr("切换"))
                }
                .adaptiveGlassButton()
                .disabled(!canSwitch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassSurface(cornerRadius: 17, padding: 12, treatment: .clear)
    }

    // MARK: - Confirmation

    private func confirmationSection(_ mode: ModemMode) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.tr("确认切换模式？"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(mode.localizedConsequence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 9) {
                Text(L10n.tr("即将写入"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(mode.configuration.usbcfgValueDescription)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }

            Text("顺序：VID:PID, DIAG, NMEA, AT, MODEM, NET, ADB, AUDIO")
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Text(L10n.tr("CellDock 会先解锁模组，只有逐字段回读与目标完全一致时才重启模块；回读不一致时不会重启，当前配置保持不变。"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.tr("当前配置会先存为快照。若切换后需要回退，可在本页「恢复」中一键返回；「导出诊断报告」可留存完整记录。"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    pendingMode = nil
                } label: {
                    Text(L10n.tr("取消"))
                }
                .adaptiveGlassButton()

                Spacer()

                Button {
                    pendingMode = nil
                    appState.switchToMode(mode, moduleID: selectedModuleID)
                } label: {
                    Text(L10n.tr("切换并重启"))
                }
                .adaptiveGlassButton(.accented)
                .disabled(!canSwitch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassSurface(
            cornerRadius: 17,
            padding: 12,
            treatment: .clear,
            tint: Color.orange.opacity(0.055)
        )
    }

    // MARK: - Log

    private var logSection: some View {
        let entries = appState.modeSwitchLog

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.tr("模式切换日志"))
                    .font(.headline)
                Spacer(minLength: 8)
                Button {
                    exportDiagnosticReport()
                } label: {
                    Text(L10n.tr("导出诊断报告"))
                }
                .adaptiveGlassButton()
            }

            if entries.isEmpty {
                Text(L10n.tr("尚无切换记录。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 9) {
                    ForEach(entries) { entry in
                        logRow(entry)
                    }
                }
                .adaptiveGlassSurface(cornerRadius: 19, padding: 12, treatment: .clear)
            }
        }
    }

    private func logRow(_ entry: ModeSwitchLogEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: entry.succeeded
                ? "checkmark.circle.fill"
                : "exclamationmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(entry.succeeded ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.targetMode.localizedTitle)
                    .font(.caption.weight(.semibold))
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Text(Self.snapshotTimestampFormatter.string(from: entry.startedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Writes the report wherever the user chooses. Errors surface as an alert
    /// rather than being swallowed — a diagnostic export that silently produced
    /// nothing would be worse than no button at all.
    private func exportDiagnosticReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CellDock-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try appState.makeDiagnosticReport(for: selectedModuleID)
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
