import AppKit
import SwiftUI

/// 底部状态栏：主题数量、选中信息、操作提示、缩放。
struct StatusBarView: View {
    let editor: MapEditor
    let zoomAction: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(LF("%d topics", editor.topicCount))
                .monospacedDigit()
            if editor.selection.count > 1 {
                Text(LF("%d selected", editor.selection.count))
            }
            // 联系线隐藏着时提醒一下，点一下重新显示
            if editor.map.relationshipsHidden, !editor.map.relationships.isEmpty {
                Button { editor.setRelationshipsHidden(false) } label: {
                    Label(LF("%d relationships hidden", editor.map.relationships.count), systemImage: "eye.slash")
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
                .help(L("Show relationships (⌥⌘L)"))
            }
            Divider().frame(height: 12)
            Text(hint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { z in
                    Button("\(Int(z * 100))%") { zoomAction(CGFloat(z)) }
                }
                Divider()
                Button(L("Zoom to Fit")) { NSApp.sendAction(#selector(MapViewController.zoomToFit(_:)), to: nil, from: nil) }
            } label: {
                Text("\(Int((editor.zoom * 100).rounded()))%").monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var hint: String {
        if editor.isEditing {
            return L("Return to finish · ⇧Return for a new line · Tab to add a subtopic · Esc to cancel")
        }
        if editor.primaryID == nil {
            return L("Click a topic to select it · Double-click blank space to fit the map")
        }
        return L("Tab subtopic · Return sibling · Space edit · ⌘/ fold · Drag to move")
    }
}

/// 查找栏。
struct FindBarView: View {
    @Bindable var editor: MapEditor
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("Find topics"), text: $editor.findQuery)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(maxWidth: 320)
                .onSubmit { editor.findNext() }
            Toggle(L("Include notes"), isOn: $editor.findInNotes)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            if !editor.findQuery.isEmpty {
                Text(resultText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ControlGroup {
                Button { editor.findNext(backwards: true) } label: { Image(systemName: "chevron.left") }
                    .help(L("Previous (⇧⌘G)"))
                Button { editor.findNext() } label: { Image(systemName: "chevron.right") }
                    .help(L("Next (⌘G)"))
            }
            .fixedSize()
            .disabled(editor.findResults.isEmpty)
            Spacer()
            Button(L("Done"), action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onReceive(NotificationCenter.default.publisher(for: .freeMindFocusFind)) { note in
            if (note.object as? MapEditor) === editor { focused = true }
        }
    }

    private var resultText: String {
        if editor.findResults.isEmpty { return L("No matches") }
        if let i = editor.findIndex { return LF("%d of %d", i + 1, editor.findResults.count) }
        return LF("%d matches", editor.findResults.count)
    }
}
