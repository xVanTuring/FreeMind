import AppKit
import SwiftUI

/// NSPopover 里放 SwiftUI 视图用的控制器（自动按内容计算大小）。
/// 必须用 NSHostingController：NSHostingView 的 .preferredContentSize 不会更新视图控制器的 preferredContentSize，
/// 弹出框拿到 0×0 后用默认大小显示，内容被居中裁掉两边。
final class HostingPopoverController<Content: View>: NSHostingController<Content> {
    override init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 备注编辑。
struct NotePopoverView: View {
    let editor: MapEditor
    let topicID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("Note"), systemImage: "note.text").font(.headline)
                Spacer()
                Text(editor.map.topic(topicID)?.title ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            NoteTextView(text: Binding(
                get: { editor.map.topic(topicID)?.note ?? "" },
                set: { editor.setNote(topicID, $0) }))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            Text(L("Notes are saved automatically. Markdown is kept as plain text."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 380, height: 260)
    }
}

/// 超链接编辑。
struct LinkPopoverView: View {
    let editor: MapEditor
    let topicID: UUID
    let close: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Hyperlink"), systemImage: "link").font(.headline)
            TextField(L("https://example.com or a file path"), text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)
            HStack {
                if editor.map.topic(topicID)?.hasLink ?? false {
                    Button(L("Remove"), role: .destructive) {
                        editor.setLink(topicID, nil)
                        close()
                    }
                    Button(L("Open")) { MindMapCanvasView.open(link: text) }
                        .disabled(text.isEmpty)
                }
                Spacer()
                Button(L("Cancel")) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Done"), action: apply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { text = editor.map.topic(topicID)?.link ?? "" }
    }

    private func apply() {
        editor.setLink(topicID, text)
        close()
    }
}

/// 标签编辑：逗号分隔，下方列出图中已用过的标签可直接点选。
struct LabelsPopoverView: View {
    let editor: MapEditor
    let topicID: UUID
    let close: () -> Void
    @State private var text = ""

    private var existing: [String] {
        var all: [String] = []
        editor.map.root.forEach { t in for l in t.labels where !all.contains(l) { all.append(l) } }
        return all
    }

    private var current: [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Labels"), systemImage: "tag").font(.headline)
            TextField(L("Separate labels with commas"), text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)
            let suggestions = existing.filter { !current.contains($0) }
            if !suggestions.isEmpty {
                Text(L("Used in this map")).font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { label in
                        Button(label) {
                            text = (current + [label]).joined(separator: ", ")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { close() }.keyboardShortcut(.cancelAction)
                Button(L("Done"), action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { text = (editor.map.topic(topicID)?.labels ?? []).joined(separator: ", ") }
    }

    private func apply() {
        editor.setLabels([topicID], current)
        close()
    }
}

/// 联系线标签编辑。
struct RelationshipLabelPopoverView: View {
    let editor: MapEditor
    let relationshipID: UUID
    let close: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Relationship Label"), systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
            TextField(L("Describe how the two topics are related"), text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)
            HStack {
                Spacer()
                Button(L("Cancel")) { close() }.keyboardShortcut(.cancelAction)
                Button(L("Done"), action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { text = editor.map.relationships.first { $0.id == relationshipID }?.title ?? "" }
    }

    private func apply() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.updateRelationship(relationshipID, actionName: L("Edit Relationship Label")) { $0.title = title }
        close()
    }
}

/// 简单的自动换行布局。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
