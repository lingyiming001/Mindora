import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct NodeRichContent: View {
    @ObservedObject var model: EditorModel
    let nodeID: UUID
    private var node: MindMapNode? { model.document.root.find(nodeID) }
    var body: some View {
        if let node {
            InspectorSection("链接与代码") {
                Button { model.insertContent(.link) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link").frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.link.isEmpty ? "添加网址" : "编辑网址").fontWeight(.medium)
                            Text(node.link.isEmpty ? "关联文档、页面或资料" : node.link).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("⌥⌘K").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if let url = Self.webURL(node.link) {
                    HStack {
                        Button("打开链接", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                        Spacer()
                        Button("删除", role: .destructive) { model.updateNode(nodeID) { $0.link = "" } }
                    }.controlSize(.small)
                }
                Divider()
                Button { model.insertContent(.code) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right").frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.code.isEmpty ? "添加代码块" : "编辑代码块").fontWeight(.medium)
                            Text(node.code.isEmpty ? "粘贴片段，保留缩进" : "\(node.codeLanguage.isEmpty ? "纯文本" : node.codeLanguage) · \(node.code.components(separatedBy: "\n").count) 行")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("⌥⌘C").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if !node.code.isEmpty {
                    HStack {
                        Text("点击主题上的代码区可编辑").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("删除", role: .destructive) { model.updateNode(nodeID) { $0.code = ""; $0.codeLanguage = "" } }.controlSize(.small)
                    }
                }
            }
            InspectorSection("图片与文件") {
                HStack {
                    Button("添加图片", systemImage: "photo.badge.plus") { importAttachments(imagesOnly: true) }
                    Button("添加文件", systemImage: "paperclip") { importAttachments(imagesOnly: false) }
                }.controlSize(.small)
                Text("随导图保存 · 单文件最多 3 MB，整份导图附件最多 8 MB，每个主题最多 16 项。")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(node.attachments) { attachment in
                    AttachmentCard(attachment: attachment, export: { exportAttachment(attachment) }, remove: {
                        model.updateNode(nodeID) { $0.attachments.removeAll { $0.id == attachment.id } }
                    })
                }
            }
        }
    }
    nonisolated static func webURL(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let parts = URLComponents(string: text.contains("://") ? text : "https://" + text),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, let url = parts.url else { return nil }
        return url
    }
    private func importAttachments(imagesOnly: Bool) {
        let panel = NSOpenPanel()
        panel.title = imagesOnly ? "添加图片到当前主题" : "添加文件到当前主题"
        panel.allowedContentTypes = imagesOnly ? [.image] : [.item]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, let node else { return }
        guard node.attachments.count + panel.urls.count <= 16 else { model.errorMessage = "每个主题最多添加 16 个附件。"; return }
        do {
            var incoming: [NodeAttachment] = []
            var bytes = model.document.allNodes.flatMap(\.attachments).reduce(0) { $0 + $1.data.count }
            for url in panel.urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let metadata = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard metadata.isRegularFile == true, let size = metadata.fileSize, size <= 3 * 1024 * 1024 else {
                    model.errorMessage = "“\(url.lastPathComponent)”不是普通文件，或超过 3 MB。此次未添加任何附件。"; return
                }
                let data = try Data(contentsOf: url)
                bytes += data.count
                guard data.count <= 3 * 1024 * 1024, bytes <= 8 * 1024 * 1024 else {
                    model.errorMessage = "附件超过容量限制。单文件最多 3 MB，整份导图附件最多 8 MB。此次未添加任何附件。"; return
                }
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                incoming.append(NodeAttachment(name: url.lastPathComponent, typeIdentifier: type.identifier, data: data))
            }
            model.updateNode(nodeID) { $0.attachments.append(contentsOf: incoming) }
        } catch { model.errorMessage = "无法添加附件：\(error.localizedDescription)" }
    }
    private func exportAttachment(_ attachment: NodeAttachment) {
        let panel = NSSavePanel()
        panel.title = "导出附件"; panel.nameFieldStringValue = attachment.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do { try attachment.data.write(to: url, options: .atomic) }
        catch { model.errorMessage = "无法导出附件：\(error.localizedDescription)" }
    }
}

private struct AttachmentCard: View {
    let attachment: NodeAttachment
    let export: () -> Void
    let remove: () -> Void
    @State private var preview: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let preview {
                Image(nsImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            HStack(alignment: .top) {
                Image(systemName: preview == nil ? "doc" : "photo").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.name).font(.system(size: 11, weight: .medium)).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("导出…", action: export)
                Spacer()
                Button("移除", role: .destructive, action: remove)
            }.controlSize(.small)
        }.padding(10).background(InterfaceStyle.panel, in: RoundedRectangle(cornerRadius: 9))
        .task(id: attachment.id) {
            guard UTType(attachment.typeIdentifier)?.conforms(to: .image) == true,
                  let source = CGImageSourceCreateWithData(attachment.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
            preview = NSImage(cgImage: image, size: .zero)
        }
    }
}
