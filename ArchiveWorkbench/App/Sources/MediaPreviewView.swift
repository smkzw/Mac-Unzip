import AppKit
import ArchiveDomain
import SwiftUI

struct MediaPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entries: [ArchiveEntry]
    @Binding var selection: ArchiveEntryID?
    let metadataByEntryID: [ArchiveEntryID: ArchiveEntryMetadata]
    let previewCacheURL: ValidatedPreviewCacheURL?
    let isPreviewLoading: Bool
    let previewErrorMessage: String?
    let isVisualCapture: Bool
    let isCompact: Bool
    var reduceMotion: Bool = false
    var reduceTransparency: Bool = false
    var increaseContrast: Bool = false

    private var displayedEntry: ArchiveEntry? {
        entries.first(where: { $0.id == selection }) ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let entry = displayedEntry {
                Text(displayName(for: entry))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.displayPath)
                    .accessibilityLabel(AppLocalization().format("正在预览 %@", displayName(for: entry)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, isVisualCapture ? 36 : 18)
                    .padding(.bottom, 18)

                previewPanel(for: entry)

                Divider()
                mediaStrip
            } else {
                ContentUnavailableView.search(text: "")
            }
        }
    }

    @ViewBuilder
    private func previewPanel(for entry: ArchiveEntry) -> some View {
        if isVisualCapture {
            preview(for: entry)
                .frame(maxWidth: .infinity)
                .frame(height: 468)
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, 10)
        } else {
            preview(for: entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func preview(for entry: ArchiveEntry) -> some View {
        if isPreviewLoading {
            ProgressView("正在准备预览…")
                .accessibilityIdentifier("正在准备预览")
        } else if let previewErrorMessage {
            PreviewFailureStateView(message: previewErrorMessage)
        } else {
        switch PreviewRoutingPolicy().kind(forFilename: entry.displayPath) {
        case .image:
            ArchiveImagePreviewStateView(
                filename: displayName(for: entry),
                cacheURL: previewCacheURL,
                fallbackImage: entry.displayPath == "首页主视觉.png" ? sampleImage : nil
            )
        case .video:
            NativeVideoPreviewStateView(cacheURL: previewCacheURL)
        case .pdfKit:
            PDFKitPreviewStateView(cacheURL: previewCacheURL)
        case .quickLookOffice(let documentKind):
            OfficeQuickLookPreviewStateView(
                cacheURL: previewCacheURL,
                documentKind: documentKind
            )
        case .markdown:
            MarkdownPreviewStateView(
                filename: displayName(for: entry),
                cacheURL: previewCacheURL
            )
        case .unsupported:
            UnsupportedPreviewStateView(filename: entry.displayPath)
        }
        }
    }

    private var mediaStrip: some View {
        AccessibleGroupHost(identifier: "媒体条带") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(entries, id: \.id) { entry in
                        VStack(spacing: 2) {
                            Button {
                                selection = entry.id
                            } label: {
                                thumbnail(for: entry)
                                    .frame(
                                        width: 96,
                                        height: isCompact ? 50 : 60
                                    )
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        if entry.id == displayedEntry?.id {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectionRingColor, lineWidth: increaseContrast ? 4 : 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalization().format("选择文件 %@", entry.displayPath))
                            .accessibilityIdentifier(entry.displayPath)
                            .accessibilityHint(accessibleSelectionLabel(for: entry.displayPath))
                            .help(AppLocalization().format("选择文件 %@", entry.displayPath))
                            Text(displayName(for: entry))
                                .font(.body)
                                .foregroundStyle(metadataForegroundColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(entry.displayPath)
                                .accessibilityIdentifier("文件名：\(entry.displayPath)")
                                .accessibilityLabel(AppLocalization().string("文件名称"))
                                .accessibilityValue(entry.displayPath)
                            .frame(height: 18)
                            Text(size(for: entry))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(metadataForegroundColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(AppLocalization().format("文件大小：%@", size(for: entry)))
                                .accessibilityIdentifier("文件大小：\(size(for: entry))")
                                .accessibilityLabel(AppLocalization().string("文件大小"))
                                .accessibilityValue(size(for: entry))
                            .frame(height: 18)
                        }
                        .frame(width: 100)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .animation(reduceMotion ? nil : .default, value: selection)
            }
        }
        .frame(height: 166)
    }

    private var metadataForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    @ViewBuilder
    private func thumbnail(for entry: ArchiveEntry) -> some View {
        if ["首页主视觉.png", "产品截图.heic"].contains(entry.displayPath), let image = sampleImage {
            rasterThumbnail(image: image, showsPlayButton: false)
        } else if entry.displayPath == "演示视频.mp4", let image = sampleImage {
            rasterThumbnail(image: image, showsPlayButton: true)
        } else {
            Image(systemName: symbol(for: entry.displayPath))
                .resizable()
                .scaledToFit()
                .padding(20)
                .foregroundStyle(.primary)
        }
    }

    private func rasterThumbnail(image: NSImage, showsPlayButton: Bool) -> some View {
        GeometryReader { proxy in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                if showsPlayButton {
                    Circle()
                        .fill(playButtonBackground)
                        .frame(width: 36, height: 36)
                    Image(systemName: "play.fill")
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var sampleImage: NSImage? {
        let url = Bundle.main.url(forResource: "首页主视觉", withExtension: "png", subdirectory: "SampleMedia")
            ?? Bundle.main.url(forResource: "首页主视觉", withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }

    private func symbol(for name: String) -> String {
        if name.hasSuffix(".mp4") { return "play.rectangle.fill" }
        if name.hasSuffix(".pdf") { return "doc.richtext.fill" }
        if name.hasSuffix(".svg") { return "scribble.variable" }
        return "photo.fill"
    }

    private func size(for entry: ArchiveEntry) -> String {
        let formatted = metadataByEntryID[entry.id]?.size ?? "—"
        return formatted.split(separator: " ").prefix(2).joined(separator: " ")
    }

    /// Background for the play-button badge; solid under Reduce Transparency.
    private var playButtonBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            : AnyShapeStyle(.regularMaterial)
    }

    /// Selection ring color; uses the label color for maximum contrast when requested.
    private var selectionRingColor: AnyShapeStyle {
        increaseContrast
            ? AnyShapeStyle(Color.primary)
            : AnyShapeStyle(.tint)
    }

    private func displayName(for entry: ArchiveEntry) -> String {
        entry.displayPath.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
            ?? entry.displayPath
    }

    private func accessibleSelectionLabel(for filename: String) -> String {
        let localization = AppLocalization()
        switch PreviewRoutingPolicy().kind(forFilename: filename) {
        case .image:
            return localization.format("选择%@的%@预览", filename, localization.string("图像"))
        case .video:
            return localization.format("选择%@的%@预览", filename, localization.string("视频"))
        case .pdfKit:
            return localization.format("选择%@的%@预览", filename, localization.string("PDF 文档"))
        case .quickLookOffice(let documentKind):
            return documentKind.selectionLabel(filename: filename)
        case .markdown:
            return localization.format("选择%@的%@预览", filename, localization.string("Markdown"))
        case .unsupported: return localization.format("选择文件 %@", filename)
        }
    }
}
