import Darwin
import Foundation

enum PreviewKind: Equatable, Sendable {
    case image
    case video
    case pdfKit
    case quickLookOffice(OfficePreviewKind)
    case markdown
    case unsupported
}

enum OfficePreviewKind: Equatable, Sendable {
    case word
    case excel
    case powerPoint

    func displayName(localization: AppLocalization = AppLocalization()) -> String {
        switch self {
        case .word: localization.string("Word 文档")
        case .excel: localization.string("Excel 表格")
        case .powerPoint: localization.string("PowerPoint 演示文稿")
        }
    }

    func preparingMessage(localization: AppLocalization = AppLocalization()) -> String {
        localization.format("正在准备%@预览", displayName(localization: localization))
    }

    func accessibilityLabel(localization: AppLocalization = AppLocalization()) -> String {
        localization.format("%@ Quick Look 预览", displayName(localization: localization))
    }

    func selectionLabel(
        filename: String,
        localization: AppLocalization = AppLocalization()
    ) -> String {
        localization.format(
            "选择%@的%@预览",
            filename,
            displayName(localization: localization)
        )
    }
}

struct PreviewRoutingPolicy: Sendable {
    func kind(forFilename filename: String) -> PreviewKind {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        switch fileExtension {
        case "png", "jpg", "jpeg", "heic", "gif", "tif", "tiff", "bmp", "webp", "svg":
            return .image
        case "mp4", "mov", "m4v":
            return .video
        case "pdf":
            return .pdfKit
        case "doc", "docx":
            return .quickLookOffice(.word)
        case "xls", "xlsx":
            return .quickLookOffice(.excel)
        case "ppt", "pptx":
            return .quickLookOffice(.powerPoint)
        case "md", "markdown", "mdown":
            return .markdown
        default:
            return .unsupported
        }
    }
}

struct ValidatedPreviewCacheURL: Equatable, Sendable {
    let url: URL
    private let relativeComponents: [String]

    static let maximumPreviewBytes = 256 * 1_024 * 1_024

    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacUnzip/PreviewCache", isDirectory: true)
    }

    init?(candidateURL: URL) {
        guard let components = Self.relativeComponents(for: candidateURL),
              let descriptor = Self.openValidatedFile(
                relativeComponents: components,
                maximumBytes: Self.maximumPreviewBytes
              ) else { return nil }
        close(descriptor)

        var securedURL = Self.cacheRoot.standardizedFileURL
        for component in components {
            securedURL.appendPathComponent(component)
        }
        url = securedURL
        relativeComponents = components
    }

    func readData(
        maximumBytes: Int = Self.maximumPreviewBytes,
        beforeOpeningFinalComponent: (() -> Void)? = nil
    ) -> Data? {
        guard maximumBytes >= 0,
              maximumBytes < Int.max,
              let descriptor = Self.openValidatedFile(
                relativeComponents: relativeComponents,
                maximumBytes: maximumBytes,
                beforeOpeningFinalComponent: beforeOpeningFinalComponent
              ) else { return nil }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let readLimit = maximumBytes + 1
        var result = Data()
        do {
            while result.count < readLimit {
                guard !Task.isCancelled else { return nil }
                let requestedBytes = min(64 * 1_024, readLimit - result.count)
                guard let chunk = try handle.read(upToCount: requestedBytes),
                      !chunk.isEmpty else {
                    return result
                }
                result.append(chunk)
            }
        } catch {
            return nil
        }
        return result
    }

    private static func relativeComponents(for candidateURL: URL) -> [String]? {
        let root = cacheRoot.standardizedFileURL
        let candidatePath = candidateURL.path
        guard candidateURL.isFileURL,
              candidatePath.hasPrefix(root.path + "/") else { return nil }
        let relativePath = candidatePath.dropFirst(root.path.count + 1)
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components
    }

    private static func openValidatedFile(
        relativeComponents: [String],
        maximumBytes: Int,
        beforeOpeningFinalComponent: (() -> Void)? = nil
    ) -> Int32? {
        guard maximumBytes >= 0,
              !relativeComponents.isEmpty,
              relativeComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        var currentDescriptor = open(
            cacheRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard currentDescriptor >= 0,
              descriptor(currentDescriptor, hasType: S_IFDIR) else {
            if currentDescriptor >= 0 { close(currentDescriptor) }
            return nil
        }
        defer { close(currentDescriptor) }

        for component in relativeComponents.dropLast() {
            let nextDescriptor = openat(
                currentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard nextDescriptor >= 0,
                  descriptor(nextDescriptor, hasType: S_IFDIR) else {
                if nextDescriptor >= 0 { close(nextDescriptor) }
                return nil
            }
            close(currentDescriptor)
            currentDescriptor = nextDescriptor
        }

        beforeOpeningFinalComponent?()
        guard let finalComponent = relativeComponents.last else { return nil }
        let fileDescriptor = openat(
            currentDescriptor,
            finalComponent,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard fileDescriptor >= 0 else { return nil }

        var fileStatus = stat()
        guard fstat(fileDescriptor, &fileStatus) == 0,
              fileStatus.st_mode & S_IFMT == S_IFREG,
              fileStatus.st_size >= 0,
              fileStatus.st_size <= off_t(maximumBytes) else {
            close(fileDescriptor)
            return nil
        }
        return fileDescriptor
    }

    private static func descriptor(_ descriptor: Int32, hasType type: mode_t) -> Bool {
        var descriptorStatus = stat()
        return fstat(descriptor, &descriptorStatus) == 0
            && descriptorStatus.st_mode & S_IFMT == type
    }
}
