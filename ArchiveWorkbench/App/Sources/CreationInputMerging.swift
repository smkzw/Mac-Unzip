import ArchiveProviders
import Foundation

/// How to resolve archive-root name collisions when appending create-archive inputs.
enum CreationInputConflictResolution: Equatable, Sendable {
    case rename
    case replace
    case cancel
}

enum CreationInputConflict: Equatable, Sendable {
    /// Same source identity — already listed.
    case duplicateExisting(CreationInput)
    /// Different sources share the same archive-root name.
    case archiveRootCollision(incoming: CreationInput, existing: CreationInput)
}

struct CreationInput: Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    var sourceURL: URL
    var archiveRootName: String

    init(sourceURL: URL, archiveRootName: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.sourceURL = sourceURL.standardizedFileURL
        let fallback = sourceURL.lastPathComponent
        let trimmed = archiveRootName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.archiveRootName = trimmed.isEmpty ? fallback : trimmed
    }

    var asProviderInput: ArchiveCreationInput {
        ArchiveCreationInput(sourceURL: sourceURL, archiveRootName: archiveRootName)
    }
}

struct CreationInputMergeResult: Equatable, Sendable {
    /// Proposed final list. Unchanged from `existing` while conflicts remain unresolved.
    var inputs: [CreationInput]
    var added: [CreationInput]
    var skippedDuplicates: [CreationInput]
    var pendingConflicts: [CreationInputConflict]
}

enum CreationInputMerging {
    /// Pure merge. Never copies source data. Does not mutate the caller's draft.
    /// Parent/child coverage uses on-disk directory checks, not `hasDirectoryPath`.
    static func merge(
        existing: [CreationInput],
        incoming: [URL],
        conflictResolution: CreationInputConflictResolution? = nil
    ) -> CreationInputMergeResult {
        merge(
            existing: existing,
            incoming: incoming.map { CreationInput(sourceURL: $0) },
            conflictResolution: conflictResolution
        )
    }

    static func merge(
        existing: [CreationInput],
        incoming: [CreationInput],
        conflictResolution: CreationInputConflictResolution? = nil
    ) -> CreationInputMergeResult {
        var result = CreationInputMergeResult(
            inputs: existing,
            added: [],
            skippedDuplicates: [],
            pendingConflicts: []
        )
        // Stage the full batch; commit only when no unresolved conflicts remain.
        var staged = existing
        let existingKeys = Set(existing.map(identityKey))
        var existingRootNames = Dictionary(
            existing.map { ($0.archiveRootName.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let batchDirectoryParents = incoming.compactMap { input -> String? in
            isDirectory(input.sourceURL) ? input.sourceURL.path : nil
        }

        for input in incoming {
            let key = identityKey(input)
            if existingKeys.contains(key) || staged.contains(where: { identityKey($0) == key }) {
                result.skippedDuplicates.append(input)
                continue
            }

            let parentPaths = batchDirectoryParents
                + staged.compactMap { isDirectory($0.sourceURL) ? $0.sourceURL.path : nil }
            if isCovered(byParents: parentPaths, candidate: input.sourceURL) {
                result.skippedDuplicates.append(input)
                continue
            }

            let rootKey = input.archiveRootName.lowercased()
            if let colliding = existingRootNames[rootKey]
                ?? staged.first(where: { $0.archiveRootName.lowercased() == rootKey }),
               identityKey(colliding) != key {
                let conflict = CreationInputConflict.archiveRootCollision(
                    incoming: input,
                    existing: colliding
                )
                switch conflictResolution {
                case .none:
                    result.pendingConflicts.append(conflict)
                    continue
                case .cancel:
                    continue
                case .replace:
                    staged.removeAll { $0.archiveRootName.lowercased() == rootKey }
                    staged.append(input)
                    result.added.append(input)
                    existingRootNames[rootKey] = input
                case .rename:
                    let renamed = CreationInput(
                        sourceURL: input.sourceURL,
                        archiveRootName: uniquedArchiveRootName(
                            input.archiveRootName,
                            among: staged.map(\.archiveRootName)
                        ),
                        id: input.id
                    )
                    staged.append(renamed)
                    result.added.append(renamed)
                    existingRootNames[renamed.archiveRootName.lowercased()] = renamed
                }
                continue
            }

            staged.append(input)
            result.added.append(input)
            existingRootNames[rootKey] = input
        }

        if result.pendingConflicts.isEmpty {
            result.inputs = staged
        } else {
            // Atomic batch: leave draft untouched until the user resolves conflicts.
            result.inputs = existing
            result.added = []
        }
        return result
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func uniquedArchiveRootName(_ name: String, among existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        if !taken.contains(name.lowercased()) { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !taken.contains(candidate.lowercased()) {
                return candidate
            }
            counter += 1
        }
    }

    static func hasDuplicateArchiveRoots(_ inputs: [CreationInput]) -> Bool {
        var seen = Set<String>()
        for input in inputs {
            let key = input.archiveRootName.lowercased()
            if !seen.insert(key).inserted { return true }
        }
        return false
    }

    /// Collisions among a single proposed list (e.g. after preflight sanitize).
    static func collisionsWithin(_ inputs: [CreationInput]) -> [CreationInputConflict] {
        var firstByRoot: [String: CreationInput] = [:]
        var conflicts: [CreationInputConflict] = []
        for input in inputs {
            let key = input.archiveRootName.lowercased()
            if let existing = firstByRoot[key], identityKey(existing) != identityKey(input) {
                conflicts.append(.archiveRootCollision(incoming: input, existing: existing))
            } else if firstByRoot[key] == nil {
                firstByRoot[key] = input
            }
        }
        return conflicts
    }

    /// Shared create-draft entry: always runs conflict detection/merge (never silent bypass).
    static func makeDraft(
        inputs: [URL],
        format: CreationFormat,
        generation: UInt64
    ) -> ArchiveCreationDraft {
        let merged = merge(existing: [], incoming: inputs)
        var draft = ArchiveCreationDraft(
            inputs: merged.inputs,
            format: format,
            generation: generation
        )
        if !merged.pendingConflicts.isEmpty {
            draft.seededPendingConflicts = merged.pendingConflicts
            draft.seededPendingIncoming = inputs.map { CreationInput(sourceURL: $0) }
            draft.seededConflictReplaceBaseline = true
        }
        return draft
    }

    private static func identityKey(_ input: CreationInput) -> String {
        input.sourceURL.standardizedFileURL.path
    }

    /// True only when `candidate` is a real descendant path of a selected parent directory.
    /// ` /foo` must not treat `/foobar` as covered — requires a path-separator boundary.
    private static func isCovered(byParents parents: [String], candidate: URL) -> Bool {
        let path = candidate.standardizedFileURL.path
        for parent in parents {
            let normalizedParent = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
            if path == normalizedParent { continue }
            let prefix = normalizedParent + "/"
            if path.hasPrefix(prefix) { return true }
        }
        return false
    }
}


/// Windows ZIP preflight filename sanitizer shared by AppModel fix/preflight paths.
enum WindowsFilenameSanitizer {
    static func sanitize(_ name: String) -> String? {
        let forbidden = CharacterSet(charactersIn: "<>:\"|?*")
        let reserved = Set(["CON", "PRN", "AUX", "NUL"])
        let reservedDevicePrefixes = ["COM", "LPT"]

        var result = String(name.unicodeScalars.filter {
            !forbidden.contains($0) && $0.value >= 0x20
        })
        while result.hasSuffix(".") || result.hasSuffix(" ") {
            result = String(result.dropLast())
        }
        let stem = result.split(separator: ".", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
        let isNumberedDevice = reservedDevicePrefixes.contains { prefix in
            stem.hasPrefix(prefix) && stem.count == 4 && stem.last?.isNumber == true
        }
        if reserved.contains(stem) || isNumberedDevice {
            result = "_" + result
        }
        if result.utf16.count > 255 {
            let ext = URL(fileURLWithPath: result).pathExtension
            let suffix = ext.isEmpty ? "" : "." + ext
            let budget = max(0, 255 - suffix.utf16.count)
            var base = result
            if !suffix.isEmpty, base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
            }
            if base.utf16.count > budget {
                let endIndex = base.utf16.index(base.utf16.startIndex, offsetBy: budget)
                var cut = base.utf16[..<endIndex]
                if let lastUnit = cut.last, UTF16.isLeadSurrogate(lastUnit) {
                    cut = cut.dropLast()
                }
                base = String(decoding: cut, as: UTF16.self)
            }
            result = base + suffix
        }
        return result == name ? nil : result
    }
}


/// Pure decision for async preflight auto-fix completion.
enum PreflightSanitizedCommit {
    enum Outcome: Equatable, Sendable {
        case stale
        case apply([CreationInput])
        case requireConflictResolution(conflicts: [CreationInputConflict], incoming: [CreationInput])
    }

    static func plan(
        draftGeneration: UInt64,
        draftRevision: UInt64,
        expectedGeneration: UInt64,
        expectedRevision: UInt64,
        sanitized: [CreationInput]
    ) -> Outcome {
        guard draftGeneration == expectedGeneration, draftRevision == expectedRevision else {
            return .stale
        }
        guard !sanitized.isEmpty else { return .stale }
        let collisions = CreationInputMerging.collisionsWithin(sanitized)
        if !collisions.isEmpty {
            return .requireConflictResolution(conflicts: collisions, incoming: sanitized)
        }
        return .apply(sanitized)
    }
}

/// Applies a create-panel conflict resolution only when draft identity still matches.
enum CreationConflictApplication {
    struct Token: Equatable, Sendable {
        var generation: UInt64
        var inputsRevision: UInt64
        var batchToken: UUID
        var replaceBaseline: Bool
    }

    static func apply(
        draft: ArchiveCreationDraft,
        token: Token,
        incoming: [CreationInput],
        resolution: CreationInputConflictResolution,
        format: CreationFormat
    ) -> ArchiveCreationDraft? {
        guard draft.generation == token.generation else { return nil }
        guard draft.inputsRevision == token.inputsRevision else { return nil }
        guard resolution != .cancel else { return nil }
        let baseline = token.replaceBaseline ? [] : draft.inputs
        let merged = CreationInputMerging.merge(
            existing: baseline,
            incoming: incoming,
            conflictResolution: resolution
        )
        var next = draft
        next.commitMerge(merged, format: format)
        next.seededPendingConflicts = []
        next.seededPendingIncoming = []
        next.seededConflictReplaceBaseline = false
        return next
    }
}

extension ArchiveCreationDraft {
    /// Computes a merge without mutating `self` when conflicts remain.
    func proposingInputs(
        _ urls: [URL],
        conflictResolution: CreationInputConflictResolution? = nil
    ) -> CreationInputMergeResult {
        CreationInputMerging.merge(
            existing: inputs,
            incoming: urls,
            conflictResolution: conflictResolution
        )
    }

    /// Commits a fully resolved merge result.
    mutating func commitMerge(
        _ merged: CreationInputMergeResult,
        format: CreationFormat = .zip
    ) {
        guard merged.pendingConflicts.isEmpty else { return }
        inputs = merged.inputs
        bumpInputsRevision()
        if outputURL == nil {
            outputURL = Self.defaultOutputURL(
                for: inputs.map(\.sourceURL),
                format: format
            )
        }
    }

    mutating func replaceInputs(_ newInputs: [CreationInput], format: CreationFormat) {
        inputs = newInputs
        bumpInputsRevision()
        if outputURL == nil {
            outputURL = Self.defaultOutputURL(
                for: inputs.map(\.sourceURL),
                format: format
            )
        }
    }
}
