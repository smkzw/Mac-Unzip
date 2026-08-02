import AppKit
import AVKit
import PDFKit
import QuickLookUI
import SwiftUI

struct ArchiveImagePreviewStateView: View {
    let filename: String
    let cacheURL: ValidatedPreviewCacheURL?
    let fallbackImage: NSImage?
    @State private var image: NSImage?
    @State private var isLoading = false

    init(filename: String, cacheURL: ValidatedPreviewCacheURL?, fallbackImage: NSImage?) {
        self.filename = filename
        self.cacheURL = cacheURL
        self.fallbackImage = fallbackImage
        _image = State(initialValue: fallbackImage)
    }

    var body: some View {
        Group {
            if let image {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .accessibilityLabel(filename)
                .accessibilityIdentifier(filename)
            } else if isLoading {
                ProgressView("正在读取图片…")
                    .accessibilityIdentifier("正在读取图片")
            } else {
                PreviewFailureStateView(message: "无法读取这张图片。")
            }
        }
        .task(id: cacheURL?.url) {
            guard let cacheURL else {
                image = fallbackImage
                return
            }
            isLoading = true
            image = nil
            let worker = Task.detached(priority: .userInitiated) {
                cacheURL.readData().flatMap(NSImage.init(data:)).map(SendableImage.init)
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            image = prepared?.image
            isLoading = false
        }
    }
}

struct PDFKitPreviewStateView: View {
    let cacheURL: ValidatedPreviewCacheURL?
    @State private var document: PDFDocument?
    @State private var isLoading = false

    init(cacheURL: ValidatedPreviewCacheURL?) {
        self.cacheURL = cacheURL
    }

    var body: some View {
        AccessibleGroupHost(identifier: "PDFKit 预览") {
            VStack(spacing: 8) {
                if isLoading {
                    ProgressView("正在读取 PDF…")
                        .accessibilityIdentifier("正在读取 PDF")
                } else {
                    PDFKitCanvas(document: document)
                }
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
            }
        }
        .task(id: cacheURL?.url) {
            document = nil
            guard let cacheURL else { return }
            isLoading = true
            let worker = Task.detached(priority: .userInitiated) {
                cacheURL.readData().flatMap(PDFDocument.init(data:)).map(SendablePDFDocument.init)
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            document = prepared?.document
            isLoading = false
        }
    }

    private var statusText: String {
        let localization = AppLocalization()
        if isLoading { return localization.string("正在读取 PDF…") }
        guard let document, document.pageCount > 0 else {
            return localization.string("PDF 文档加载失败")
        }
        return localization.format("PDF 文档已加载，%ld 页", document.pageCount)
    }
}

private struct PDFKitCanvas: NSViewRepresentable {
    let document: PDFDocument?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        updateAccessibility(in: view)
        DispatchQueue.main.async { updateAccessibility(in: view) }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document { nsView.document = document }
        updateAccessibility(in: nsView)
        DispatchQueue.main.async { updateAccessibility(in: nsView) }
    }

    private func updateAccessibility(in view: NSView) {
        let pageCount = document?.pageCount ?? 0
        view.setAccessibilityLabel(AppLocalization().format("PDFKit 安全缓存预览，%ld 页", pageCount))
        labelPDFHierarchy(in: view, pageCount: pageCount)
        labelPDFVirtualElements(view.accessibilityChildren() ?? [], pageCount: pageCount)
    }

    private func labelPDFHierarchy(in view: NSView, pageCount: Int) {
        let role: NSAccessibility.Role? = view.accessibilityRole()
        let label: String? = view.accessibilityLabel()
        if role == .group, label?.isEmpty != false {
            view.setAccessibilityLabel(AppLocalization().format("PDF 文档页面内容，共 %ld 页", pageCount))
            view.setAccessibilityIdentifier("PDF 文档页面内容")
        }
        for subview in view.subviews {
            labelPDFHierarchy(in: subview, pageCount: pageCount)
        }
    }

    private func labelPDFVirtualElements(_ elements: [Any], pageCount: Int) {
        for element in elements {
            guard let virtualElement = element as? NSObject,
                  virtualElement.responds(to: NSSelectorFromString("accessibilityLabel")) else { continue }
            let role: String? = virtualElement.responds(to: NSSelectorFromString("accessibilityRole"))
                ? virtualElement.value(forKey: "accessibilityRole") as? String
                : nil
            let label = virtualElement.value(forKey: "accessibilityLabel") as? String
            if label?.isEmpty != false, let fallback = fallbackLabel(forRole: role, pageCount: pageCount) {
                virtualElement.setValue(fallback, forKey: "accessibilityLabel")
            }
            let children: [Any] = virtualElement.responds(to: NSSelectorFromString("accessibilityChildren"))
                ? virtualElement.value(forKey: "accessibilityChildren") as? [Any] ?? []
                : []
            labelPDFVirtualElements(children, pageCount: pageCount)
        }
    }

    private func fallbackLabel(forRole role: String?, pageCount: Int) -> String? {
        switch role {
        case NSAccessibility.Role.group.rawValue:
            return AppLocalization().format("PDF 页面容器，共 %ld 页", pageCount)
        case NSAccessibility.Role.button.rawValue:
            return AppLocalization().string("PDF 滚动控制")
        case "AXIncrementArrow":
            return AppLocalization().string("向前滚动 PDF")
        case "AXDecrementArrow":
            return AppLocalization().string("向后滚动 PDF")
        default:
            return nil
        }
    }
}

@MainActor
enum FixturePreviewCache {
    static func makePDF(pageCount: Int = 2) -> ValidatedPreviewCacheURL? {
        let root = ValidatedPreviewCacheURL.cacheRoot
        try? FileManager.default.removeItem(at: root)
        let directory = root
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("品牌指南.pdf")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let document = PDFDocument()
            for pageNumber in 1...pageCount {
                let pageView = FixturePDFPageView(
                    pageNumber: pageNumber,
                    frame: NSRect(x: 0, y: 0, width: 612, height: 792)
                )
                let pageData = pageView.dataWithPDF(inside: pageView.bounds)
                guard let page = PDFDocument(data: pageData)?.page(at: 0) else { return nil }
                document.insert(page, at: document.pageCount)
            }
            guard document.write(to: url) else { return nil }
            return ValidatedPreviewCacheURL(candidateURL: url)
        } catch {
            return nil
        }
    }
}

private final class FixturePDFPageView: NSView {
    private let pageNumber: Int

    init(pageNumber: Int, frame frameRect: NSRect) {
        self.pageNumber = pageNumber
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let title = NSAttributedString(
            string: "品牌指南",
            attributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
        )
        title.draw(at: NSPoint(x: 72, y: 650))
        let body = NSAttributedString(
            string: "Mac Unzip 安全预览缓存示例\nPDFKit 已加载真实的第 \(pageNumber) 页。",
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor.black
            ]
        )
        body.draw(in: NSRect(x: 72, y: 520, width: 468, height: 100))
    }
}

struct OfficeQuickLookPreviewStateView: View {
    let cacheURL: ValidatedPreviewCacheURL?
    let documentKind: OfficePreviewKind

    var body: some View {
        Group {
            if cacheURL != nil {
                QuickLookCanvas(cacheURL: cacheURL)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 72))
                    Text(documentKind.preparingMessage())
                        .font(.title2)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(documentKind.accessibilityLabel())
    }
}

private struct QuickLookCanvas: NSViewRepresentable {
    let cacheURL: ValidatedPreviewCacheURL?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        guard let previewView = QLPreviewView(frame: .zero, style: .normal) else {
            let fallback = NSTextField(
                labelWithString: AppLocalization().string("系统暂时无法创建文档预览。")
            )
            fallback.alignment = .center
            fallback.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(fallback)
            NSLayoutConstraint.activate([
                fallback.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                fallback.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container
        }
        previewView.setAccessibilityLabel(AppLocalization().string("Office Quick Look 安全缓存预览"))
        previewView.previewItem = revalidatedURL as NSURL?
        previewView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: container.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.subviews.compactMap { $0 as? QLPreviewView }.first?.previewItem = revalidatedURL as NSURL?
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let previewView = nsView.subviews.compactMap({ $0 as? QLPreviewView }).first else { return }
        previewView.previewItem = nil
        previewView.close()
    }

    private var revalidatedURL: URL? {
        cacheURL.flatMap { ValidatedPreviewCacheURL(candidateURL: $0.url)?.url }
    }
}

struct NativeVideoPreviewStateView: View {
    let cacheURL: ValidatedPreviewCacheURL?
    @State private var player: AVPlayer?
    @State private var failureMessage: String?

    var body: some View {
        Group {
            if let failureMessage {
                PreviewFailureStateView(message: failureMessage)
            } else if let player {
                NativeVideoCanvas(player: player)
            } else {
                ProgressView("正在准备视频预览…")
                    .accessibilityLabel(AppLocalization().string("正在准备视频预览…"))
            }
        }
        .task(id: cacheURL?.url) {
            player?.pause()
            player = nil
            failureMessage = nil
            guard let url = cacheURL.flatMap({ ValidatedPreviewCacheURL(candidateURL: $0.url)?.url }) else {
                return
            }
            do {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else {
                    failureMessage = "这个视频无法播放。"
                    return
                }
                try Task.checkCancellation()
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } catch is CancellationError {
                return
            } catch {
                failureMessage = "这个视频无法播放。"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === player?.currentItem else { return }
            failureMessage = "播放视频时发生错误。"
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct NativeVideoCanvas: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.player = player
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(AppLocalization().string("原生视频预览"))
        view.setAccessibilityIdentifier("原生视频预览")
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Void) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

// Immutable after init(data:); consumed on MainActor only after detached task completes.
private struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

// Immutable after init(data:); consumed on MainActor only after detached task completes.
private struct SendablePDFDocument: @unchecked Sendable {
    let document: PDFDocument
}

struct MarkdownPreviewStateView: View {
    let filename: String
    let cacheURL: ValidatedPreviewCacheURL?
    @State private var content: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let content {
                MarkdownPreviewView(content: content, title: filename)
            } else if isLoading {
                ProgressView("正在读取 Markdown…")
                    .accessibilityIdentifier("正在读取 Markdown")
            } else {
                PreviewFailureStateView(message: "无法读取 Markdown 文件。")
            }
        }
        .task(id: cacheURL?.url) {
            guard let cacheURL else { content = nil; return }
            isLoading = true
            content = nil
            let worker = Task.detached(priority: .userInitiated) {
                cacheURL.readData().flatMap { String(data: $0, encoding: .utf8) }
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            content = result
            isLoading = false
        }
    }
}

struct PreviewFailureStateView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "无法预览",
            systemImage: "exclamationmark.triangle",
            description: Text(AppLocalization().string(message))
        )
        .accessibilityIdentifier("预览失败")
    }
}

struct UnsupportedPreviewStateView: View {
    let filename: String

    var body: some View {
        ContentUnavailableView(
            "此文件类型暂不支持预览",
            systemImage: "doc.questionmark",
            description: Text(filename)
        )
    }
}
