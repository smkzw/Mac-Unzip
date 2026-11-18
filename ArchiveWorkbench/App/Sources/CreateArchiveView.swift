import AppKit
import ArchiveProviders
import SwiftUI
import UniformTypeIdentifiers

struct CreateArchiveView: View {
    @Bindable var model: AppModel
    @Binding var draft: ArchiveCreationDraft
    let chooseOutput: (String) -> URL?
    let dismiss: () -> Void
    @State private var showRARLicenseConfirmation = false
    @State private var rarRevertFormat: CreationFormat?
    @State private var isInputDropTargeted = false
    @State private var pendingInputConflicts: [CreationInputConflict] = []
    @State private var pendingConflictIncoming: [CreationInput] = []
    @State private var pendingConflictToken: CreationConflictApplication.Token?
    @State private var dropTask: Task<Void, Never>?

    private var hasPendingInputConflicts: Bool { !pendingInputConflicts.isEmpty }

    private var passwordsMatch: Bool {
        !model.creationEncryptionEnabled
            || !model.creationFormat.supportsEncryption
            || (!model.creationPassword.isEmpty && model.creationPassword == model.creationPasswordConfirm)
    }

    private var canCreate: Bool {
        draft.canCreate && passwordsMatch && !model.isCreating
            && !hasPendingInputConflicts
            && !draft.hasDuplicateArchiveRoots
            && model.engineInstalled(for: model.creationFormat)
            && (model.creationFormat != .zip || (model.preflightIssues.isEmpty && !model.isRunningPreflight))
    }

    private var createDisabledReason: String {
        let localization = AppLocalization()
        if draft.inputs.isEmpty { return localization.string("请先添加要压缩的文件") }
        if draft.outputURL == nil { return localization.string("请选择保存位置") }
        if hasPendingInputConflicts || draft.hasDuplicateArchiveRoots {
            return localization.string("请先解决文件名冲突")
        }
        if !model.engineInstalled(for: model.creationFormat) { return missingEngineMessage(for: model.creationFormat) }
        if model.creationEncryptionEnabled && model.creationFormat.supportsEncryption && model.creationPassword.isEmpty { return localization.string("请输入密码") }
        if !passwordsMatch { return localization.string("两次输入的密码不一致") }
        if model.creationFormat == .zip {
            if model.isRunningPreflight { return localization.string("正在检查文件名兼容性…") }
            if !model.preflightIssues.isEmpty { return localization.string("请先自动修正文件名兼容性问题") }
        }
        if model.isCreating { return localization.string("正在创建中…") }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    formatPicker
                    inputList
                    compressionSection
                    if model.creationFormat.supportsEncryption {
                        encryptionSection
                    }
                    if model.creationFormat == .zip {
                        preflightSection
                    }
                    compatibility
                    destination
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .alert(
            "无法创建压缩包",
            isPresented: Binding(
                get: { model.creationErrorMessage != nil },
                set: { if !$0 { model.creationErrorMessage = nil } }
            )
        ) {
            Button("好") { model.creationErrorMessage = nil }
        } message: {
            Text(model.creationErrorMessage ?? "")
        }
        .alert(
            AppLocalization().string(RARLicenseConfirmation.confirmationTitle),
            isPresented: $showRARLicenseConfirmation
        ) {
            Button(AppLocalization().string(RARLicenseConfirmation.confirmButton)) {
                RARLicenseConfirmation().confirm()
            }
            Button(AppLocalization().string(RARLicenseConfirmation.cancelButton), role: .cancel) {
                model.creationFormat = rarRevertFormat ?? .zip
            }
        } message: {
            Text(AppLocalization().string(RARLicenseConfirmation.confirmationMessage))
        }
        .alert(
            AppLocalization().string("文件已存在"),
            isPresented: Binding(
                get: { model.pendingOverwriteURL != nil },
                set: { if !$0 { model.resolveOverwriteConfirmation(replace: false) } }
            )
        ) {
            Button(AppLocalization().string("替换"), role: .destructive) {
                model.resolveOverwriteConfirmation(replace: true)
            }
            Button(AppLocalization().string("取消"), role: .cancel) {
                model.resolveOverwriteConfirmation(replace: false)
            }
        } message: {
            Text(AppLocalization().format(
                "“%@”已存在。继续创建将替换原有文件。",
                model.pendingOverwriteURL?.lastPathComponent ?? ""
            ))
        }
        .frame(width: UIConstants.createPanelWidth, height: UIConstants.createPanelHeight)
        .interactiveDismissDisabled(model.isCreating)
        .onChange(of: model.lastCreatedURL) { _, outputURL in
            if outputURL != nil { dismiss() }
        }
        .onAppear {
            consumeSeededConflictsIfNeeded()
            if model.creationFormat == .zip {
                Task { await model.runPreflight(inputs: draft.inputs) }
            }
        }
        .onChange(of: model.creationFormat) { oldFormat, newFormat in
            if let current = draft.outputURL {
                let retagged = ArchiveCreationDraft.retaggedFilename(current.lastPathComponent, for: newFormat)
                draft.outputURL = current.deletingLastPathComponent().appendingPathComponent(retagged)
            }
            if newFormat == .zip {
                Task { await model.runPreflight(inputs: draft.inputs) }
            } else {
                model.resetPreflight()
            }
            if newFormat == .rar, model.engineInstalled(for: .rar),
               !RARLicenseConfirmation().isConfirmed {
                rarRevertFormat = oldFormat == .rar ? rarRevertFormat : oldFormat
                showRARLicenseConfirmation = true
            }
        }
        .onDisappear {
            dropTask?.cancel()
            dropTask = nil
            pendingInputConflicts = []
            pendingConflictIncoming = []
            model.resetCreationState()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("创建归档面板")
        .accessibilityIdentifier("创建归档面板")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: UIConstants.space4) {
            Text("新建压缩包")
                .font(.title2.weight(.semibold))
            Text(ArchiveCreationCopy.subtitle())
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Format Picker

    private var formatPicker: some View {
        GroupBox("格式") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("格式", selection: $model.creationFormat) {
                    ForEach(CreationFormat.allCases, id: \.self) { format in
                        Text(model.engineInstalled(for: format)
                            ? format.displayName
                            : format.displayName + AppLocalization().string("（未安装）")
                        ).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("格式选择")

                Text(model.creationFormat.capabilityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !model.engineInstalled(for: model.creationFormat) {
                    Text(missingEngineMessage(for: model.creationFormat))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("引擎缺失提示")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func missingEngineMessage(for format: CreationFormat) -> String {
        let localization = AppLocalization()
        switch format {
        case .sevenZip: return localization.string("创建 7z 需要免费的 7zz 工具。可在「终端」运行 brew install 7zip，或从 7-zip.org 下载，安装后在「设置 → 引擎」确认已检测到。")
        case .rar: return localization.string("创建 RAR 需要 RARLAB 官方 rar 工具。请从 rarlab.com 下载 macOS 版并安装，然后在「设置 → 引擎」确认已检测到。")
        default: return ""
        }
    }

    private func inputSubtitle(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if parent.hasPrefix(tempRoot) {
            return AppLocalization().string("已为 Windows 兼容性自动修正")
        }
        return parent
    }

    private var inputList: some View {
        GroupBox(ArchiveCreationCopy.inputCount(draft.inputs.count)) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous)
                        .fill(
                            isInputDropTargeted
                                ? UIConstants.accent.opacity(UIConstants.dropFillOpacity)
                                : Color.primary.opacity(0.03)
                        )
                    RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous)
                        .strokeBorder(
                            isInputDropTargeted ? UIConstants.accent : Color.primary.opacity(0.16),
                            style: StrokeStyle(
                                lineWidth: isInputDropTargeted ? 2 : 1,
                                dash: isInputDropTargeted ? [] : [7, 5]
                            )
                        )
                    VStack(spacing: UIConstants.space8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.title2)
                            .foregroundStyle(isInputDropTargeted ? UIConstants.accent : .secondary)
                        Text(AppLocalization().string("将文件或文件夹拖到此处"))
                            .font(.body.weight(.medium))
                        Text(AppLocalization().string("支持同时拖入多个文件与不同层级的目录；压缩包也作为输入加入。"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(UIConstants.space16)
                }
                .frame(minHeight: UIConstants.createDropMinHeight)
                .onDrop(of: [.fileURL], isTargeted: $isInputDropTargeted) { providers in
                    guard !model.isCreating, !hasPendingInputConflicts else { return false }
                    let generation = draft.generation
                    dropTask?.cancel()
                    dropTask = Task { await ingestDropProviders(providers, draftGeneration: generation) }
                    return true
                }
                .accessibilityIdentifier("创建拖放区")

                HStack(spacing: 10) {
                    Button(AppLocalization().string("从访达选择…")) {
                        presentAddInputsPanel()
                    }
                    .disabled(model.isCreating || hasPendingInputConflicts)
                    .accessibilityIdentifier("从访达选择")
                    Spacer()
                    Button(AppLocalization().string("清空")) {
                        guard !model.isCreating, !hasPendingInputConflicts else { return }
                        draft.inputs = []
                        draft.outputURL = nil
                        draft.bumpInputsRevision()
                    }
                    .disabled(model.isCreating || hasPendingInputConflicts || draft.inputs.isEmpty)
                    .accessibilityIdentifier("清空输入")
                }

                if draft.inputs.isEmpty {
                    Text(AppLocalization().string("尚未添加文件"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(draft.inputs) { input in
                            HStack(spacing: 10) {
                                let isDir = CreationInputMerging.isDirectory(input.sourceURL)
                                Image(systemName: isDir ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(isDir ? .blue : .secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(input.archiveRootName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(inputSubtitle(for: input.sourceURL))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    guard !model.isCreating, !hasPendingInputConflicts else { return }
                                    draft.inputs.removeAll { $0.id == input.id }
                                    draft.bumpInputsRevision()
                                    if draft.inputs.isEmpty { draft.outputURL = nil }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isCreating || hasPendingInputConflicts)
                                .accessibilityLabel(AppLocalization().string("移除"))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(height: min(CGFloat(draft.inputs.count) * 44 + 8, 180))
                }
            }
        }
        .alert(
            AppLocalization().string("文件名冲突"),
            isPresented: Binding(
                get: { !pendingInputConflicts.isEmpty },
                set: { if !$0 { clearPendingConflicts() } }
            )
        ) {
            Button(AppLocalization().string("自动改名并保留两项")) {
                applyConflictResolution(.rename)
            }
            Button(AppLocalization().string("替换"), role: .destructive) {
                applyConflictResolution(.replace)
            }
            Button(AppLocalization().string("取消"), role: .cancel) {
                clearPendingConflicts()
            }
        } message: {
            let names = pendingInputConflicts.compactMap { conflict -> String? in
                if case .archiveRootCollision(let incoming, let existing) = conflict {
                    return "\(incoming.archiveRootName) ← \(existing.sourceURL.path) / \(incoming.sourceURL.path)"
                }
                return nil
            }
            Text(AppLocalization().format(
                "以下文件在归档根目录同名：%@。请选择自动改名保留两项、替换或取消。",
                names.joined(separator: "；")
            ))
        }
    }

    private func presentAddInputsPanel() {
        guard !model.isCreating, !hasPendingInputConflicts else { return }
        let panel = NSOpenPanel()
        panel.title = ArchiveCreationCopy.inputPanelTitle()
        panel.prompt = ArchiveCreationCopy.inputPanelPrompt()
        panel.message = ArchiveCreationCopy.inputPanelMessage()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        applyIncomingInputs(panel.urls)
    }

    private func ingestDropProviders(
        _ providers: [NSItemProvider],
        draftGeneration: UInt64
    ) async {
        var urls: [URL] = []
        for provider in providers {
            if Task.isCancelled { return }
            if let url = await loadFileURL(from: provider) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }
        await MainActor.run {
            guard !Task.isCancelled else { return }
            guard draft.generation == draftGeneration else { return }
            guard !model.isCreating, !hasPendingInputConflicts else { return }
            applyIncomingInputs(urls)
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func applyIncomingInputs(_ urls: [URL]) {
        guard !model.isCreating, !hasPendingInputConflicts else { return }
        let decision = DropRouting.decide(
            urls: urls,
            context: .createPanel,
            isSupportedArchive: ArchiveFileTypes.isSupportedArchive
        )
        let routed: [URL] = {
            switch decision {
            case .createArchiveInputs(let batch): return batch
            default: return urls
            }
        }()
        let merged = draft.proposingInputs(routed)
        if !merged.pendingConflicts.isEmpty {
            armPendingConflicts(
                merged.pendingConflicts,
                incoming: routed.map { CreationInput(sourceURL: $0) },
                replaceBaseline: false
            )
            return
        }
        draft.commitMerge(merged, format: model.creationFormat)
        if !merged.skippedDuplicates.isEmpty {
            model.transientStatusMessage = AppLocalization().format(
                "已跳过 %ld 个重复项",
                merged.skippedDuplicates.count
            )
        }
        if model.creationFormat == .zip {
            Task { await model.runPreflight(inputs: draft.inputs) }
        }
    }

    private func applyConflictResolution(_ resolution: CreationInputConflictResolution) {
        let incoming = pendingConflictIncoming
        let token = pendingConflictToken
        clearPendingConflicts()
        guard let token else { return }
        guard let applied = CreationConflictApplication.apply(
            draft: draft,
            token: token,
            incoming: incoming,
            resolution: resolution,
            format: model.creationFormat
        ) else {
            return
        }
        draft = applied
        if model.creationFormat == .zip {
            Task { await model.runPreflight(inputs: draft.inputs) }
        }
    }

    private func consumeSeededConflictsIfNeeded() {
        guard !draft.seededPendingConflicts.isEmpty else { return }
        armPendingConflicts(
            draft.seededPendingConflicts,
            incoming: draft.seededPendingIncoming,
            replaceBaseline: draft.seededConflictReplaceBaseline
        )
        draft.seededPendingConflicts = []
        draft.seededPendingIncoming = []
        draft.seededConflictReplaceBaseline = false
    }

    private func armPendingConflicts(
        _ conflicts: [CreationInputConflict],
        incoming: [CreationInput],
        replaceBaseline: Bool
    ) {
        pendingInputConflicts = conflicts
        pendingConflictIncoming = incoming
        pendingConflictToken = CreationConflictApplication.Token(
            generation: draft.generation,
            inputsRevision: draft.inputsRevision,
            batchToken: UUID(),
            replaceBaseline: replaceBaseline
        )
    }

    private func clearPendingConflicts() {
        pendingInputConflicts = []
        pendingConflictIncoming = []
        pendingConflictToken = nil
    }

    // MARK: - Compression Section

    private var compressionSection: some View {
        GroupBox("压缩") {
            VStack(alignment: .leading, spacing: 10) {
                if model.creationFormat == .zip {
                    Picker("压缩级别", selection: $model.creationCompressionLevel) {
                        ForEach(ZIPCompressionLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("ZIP压缩级别")
                } else {
                    Text("默认压缩")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Encryption Section (ZIP only)

    private var encryptionSection: some View {
        GroupBox("加密") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("加密", isOn: $model.creationEncryptionEnabled)
                    .accessibilityIdentifier("加密开关")

                if model.creationEncryptionEnabled {
                    SecureField("密码", text: $model.creationPassword)
                        .accessibilityIdentifier("加密密码")
                    SecureField("确认密码", text: $model.creationPasswordConfirm)
                        .accessibilityIdentifier("确认密码")

                    if !model.creationPassword.isEmpty
                        && model.creationPassword != model.creationPasswordConfirm {
                        Text("密码不一致")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("密码不一致")
                    }

                    if model.creationFormat == .zip {
                        Picker("加密方式", selection: $model.creationEncryptionMethod) {
                            ForEach(EncryptionMethod.allCases, id: \.self) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("加密方式")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Preflight Section (ZIP only)

    @ViewBuilder
    private var preflightSection: some View {
        if !model.preflightIssues.isEmpty {
            GroupBox("Windows 兼容性检查") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.preflightIssues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.filename)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text("\(issue.issue) — \(issue.suggestion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Button("自动修正") {
                            Task { await applyPreflightAutoFix() }
                        }
                        .disabled(hasPendingInputConflicts || model.isCreating)
                        .accessibilityIdentifier("自动修正")
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("预检问题列表")
        }
    }

    private var compatibility: some View {
        HStack(alignment: .top, spacing: UIConstants.space12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: UIConstants.space4) {
                Text(compatibilityTitle)
                    .font(.callout.weight(.semibold))
                Text(compatibilityDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(UIConstants.space12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: UIConstants.cornerRadiusSmall, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("兼容性摘要")
    }

    private var compatibilityTitle: String {
        let localization = AppLocalization()
        switch model.creationFormat {
        case .zip: return localization.string("Windows 11 可直接打开")
        case .sevenZip: return localization.string("7-Zip / Keka / The Unarchiver 兼容")
        case .rar: return localization.string("WinRAR / 7-Zip / Keka 兼容")
        case .tarGz, .tarXz, .tarZst: return localization.string("macOS / Linux / Windows (7-Zip) 兼容")
        }
    }

    private var compatibilityDetail: String {
        let localization = AppLocalization()
        switch model.creationFormat {
        case .zip:
            return localization.string("使用 UTF-8 文件名，自动排除 macOS 元数据；创建前检查 Windows 保留名、非法字符和名称冲突。")
        case .sevenZip:
            return localization.string("AES-256 加密，高压缩率；Windows 需 7-Zip 打开，macOS 可用 Keka 或 The Unarchiver。")
        case .rar:
            return localization.string("RARLAB 专有格式，广泛兼容；需已安装并授权 RARLAB rar 命令行工具。")
        case .tarGz, .tarXz, .tarZst:
            return localization.string("保留 Unix 权限；适合 macOS/Linux 分发，Windows 需 7-Zip 解压。符号链接出于安全考虑不予包含。")
        }
    }

    private var destination: some View {
        GroupBox("保存位置") {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(draft.outputURL?.path ?? ArchiveCreationCopy.noSelection())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(draft.outputURL == nil ? .secondary : .primary)
                Spacer()
                Button("选择…") {
                    if let url = chooseOutput(draft.suggestedFilename(for: model.creationFormat)) {
                        draft.outputURL = url
                    }
                }
                .disabled(model.isCreating)
                .help(model.isCreating ? "正在创建中，暂不能更改保存位置" : "选择压缩包的保存位置")
                .accessibilityIdentifier("选择保存位置")
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isCreating {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.operationMessage)
                    Spacer()
                    Text(model.creationProgress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                ProgressView(value: model.creationProgress)
                    .accessibilityIdentifier("创建进度")
                HStack {
                    Spacer()
                    Button("取消") { model.cancelCreation() }
                        .accessibilityIdentifier("取消创建")
                }
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ArchiveCreationCopy.verificationNote())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !canCreate {
                        Text(createDisabledReason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("新建压缩包") {
                    guard let outputURL = draft.outputURL else { return }
                    model.startCreation(at: outputURL, inputs: draft.inputs)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .help(canCreate ? AppLocalization().string("创建压缩包") : createDisabledReason)
                .accessibilityIdentifier("确认创建归档")
            }
        }
    }

    @MainActor
    private func applyPreflightAutoFix() async {
        guard !hasPendingInputConflicts, !model.isCreating else { return }
        let generation = draft.generation
        let revision = draft.inputsRevision
        let sanitized = await model.fixPreflightIssues(inputs: draft.inputs)
        switch PreflightSanitizedCommit.plan(
            draftGeneration: draft.generation,
            draftRevision: draft.inputsRevision,
            expectedGeneration: generation,
            expectedRevision: revision,
            sanitized: sanitized
        ) {
        case .stale:
            return
        case .requireConflictResolution(let conflicts, let incoming):
            armPendingConflicts(conflicts, incoming: incoming, replaceBaseline: true)
        case .apply(let inputs):
            draft.replaceInputs(inputs, format: model.creationFormat)
            await model.runPreflight(inputs: draft.inputs)
        }
    }
}
