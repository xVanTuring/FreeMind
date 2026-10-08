import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 标记页：优先级、进度、旗帜、星星、符号 + 标签。
struct MarkersInspector: View {
    let editor: MapEditor
    @State private var labelText = ""

    var body: some View {
        if let topic = editor.selectedTopic {
            ForEach(MarkerGroup.allCases) { group in
                InspectorSection(title: group.title) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 7), alignment: .leading, spacing: 4) {
                        ForEach(MarkerCatalog.markers(in: group), id: \.rawValue) { marker in
                            let on = topic.markers.contains(marker)
                            Button { editor.toggleMarker(marker) } label: {
                                Image(nsImage: MarkerRenderer.image(for: marker, size: 20))
                                    .frame(width: 28, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor.opacity(0.2) : Color.clear))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Color.accentColor : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .help(MarkerCatalog.title(for: marker))
                        }
                    }
                }
            }
            InspectorSection(title: L("Labels")) {
                TextField(L("Separate labels with commas"), text: $labelText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyLabels)
                if !topic.labels.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(topic.labels, id: \.self) { label in
                            HStack(spacing: 4) {
                                Text(label).font(.caption)
                                Button {
                                    editor.removeLabel(label, from: editor.selection)
                                } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                    .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                }
                Text(L("Press Return to apply. Labels appear under the topic."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onAppear { labelText = topic.labels.joined(separator: ", ") }
            .onChange(of: topic.id) { labelText = editor.selectedTopic?.labels.joined(separator: ", ") ?? "" }
            .onChange(of: topic.labels) { labelText = topic.labels.joined(separator: ", ") }

            InspectorFooter {
                Button(L("Clear Markers")) { editor.clearMarkers() }
                    .disabled(topic.markers.isEmpty)
            }
        } else {
            EmptySelectionHint()
        }
    }

    private func applyLabels() {
        let labels = labelText.split(whereSeparator: { $0 == "," || $0 == "，" }).map { String($0) }
        editor.setLabels(editor.selection, labels)
    }
}

/// 内容页：备注、超链接、图片、附件。
struct ContentInspector: View {
    let editor: MapEditor
    @State private var linkText = ""
    @State private var dropTargeted = false

    var body: some View {
        if let topic = editor.selectedTopic {
            InspectorSection(title: L("Note")) {
                NoteTextView(text: Binding(
                    get: { editor.map.topic(topic.id)?.note ?? "" },
                    set: { editor.setNote(topic.id, $0) }))
                    .padding(4)
                    .frame(minHeight: 140)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            }

            InspectorSection(title: L("Hyperlink")) {
                HStack {
                    TextField(L("https://example.com or a file path"), text: $linkText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { editor.setLink(topic.id, linkText) }
                    Button {
                        MindMapCanvasView.open(link: linkText)
                    } label: { Image(systemName: "arrow.up.forward.square") }
                        .disabled(linkText.isEmpty)
                        .help(L("Open"))
                }
                Text(L("Press Return to apply."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onAppear { linkText = topic.link ?? "" }
            .onChange(of: topic.id) { linkText = editor.selectedTopic?.link ?? "" }
            .onChange(of: topic.link) { linkText = topic.link ?? "" }

            InspectorSection(title: L("Image")) {
                if let image = topic.image {
                    if let ns = editor.attachments?.image(for: image.id) {
                        Image(nsImage: ns).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    HStack {
                        Button(L("Replace…")) { canvas?.insertImage(nil) }
                        Button(L("Remove"), role: .destructive) { editor.removeImage(from: topic.id) }
                    }
                } else {
                    Button(L("Insert Image…")) { canvas?.insertImage(nil) }
                }
            }

            InspectorSection(title: L("Attachments")) {
                if topic.attachments.isEmpty {
                    Text(L("No attachments. Drop files here or onto a topic."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(topic.attachments) { attachment in
                            AttachmentRow(editor: editor, topicID: topic.id, attachment: attachment)
                        }
                    }
                }
                Button(L("Attach File…")) { canvas?.attachFile(nil) }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(dropTargeted ? Color.accentColor.opacity(0.12) : .clear)
                .padding(.horizontal, -8))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadURLs(providers) { urls in
                    do { try editor.addAttachments(urls, to: topic.id) } catch { NSApp.presentError(error) }
                }
                return true
            }
        } else {
            EmptySelectionHint()
        }
    }

    private var canvas: MindMapCanvasView? { editor.delegate as? MindMapCanvasView }

    private func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

struct AttachmentRow: View {
    let editor: MapEditor
    let topicID: UUID
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (attachment.name as NSString).pathExtension) ?? .data))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                Button(L("Open")) { open() }
                Button(L("Quick Look")) { canvas?.quickLook(attachment.id) }
                Button(L("Save a Copy…")) { canvas?.saveAttachment(attachment.id) }
                Divider()
                Button(L("Remove"), role: .destructive) { editor.removeAttachment(attachment.id, from: topicID) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.07)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
        .help(L("Double-click to open"))
    }

    private var canvas: MindMapCanvasView? { editor.delegate as? MindMapCanvasView }

    private func open() { canvas?.openAttachment(attachment.id) }
}
