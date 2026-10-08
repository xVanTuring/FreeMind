import AppKit
import SwiftUI

/// 样式页：选中主题的形状、颜色、文字、分支颜色、外框。
struct TopicStyleInspector: View {
    let editor: MapEditor

    private static let fontSizes = [10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32, 36, 40, 48]

    var body: some View {
        if let topic = editor.selectedTopic, let node = editor.layout.node(topic.id) {
            content(topic: topic, node: node)
        } else if let relationship = editor.selectedRelationshipModel {
            RelationshipInspector(editor: editor, relationship: relationship)
        } else {
            EmptySelectionHint()
        }
    }

    @ViewBuilder
    private func content(topic: Topic, node: NodeLayout) -> some View {
        let style = topic.style
        let resolved = node.style

        InspectorSection(title: L("Topic")) {
            InspectorRow(title: L("Shape")) {
                Picker(L("Shape"), selection: Binding(
                    get: { resolved.shape },
                    set: { shape in editor.updateStyle(actionName: L("Change Shape")) { $0.shape = shape } })) {
                    ForEach(TopicShape.allCases) { shape in
                        Label(shape.title, systemImage: shape.symbolName).tag(shape)
                    }
                }
                .inspectorPopUp()
            }
            InspectorRow(title: L("Fill")) {
                ColorButton(shown: resolved.fill, current: style.fill,
                            presets: ColorPalette.soft + ColorPalette.strong, allowNone: true) { paint, live in
                    editor.updateStyle(actionName: L("Change Fill"), coalesce: live ? "fill" : nil) { $0.fill = paint }
                }
            }
            InspectorRow(title: L("Border")) {
                ColorButton(shown: resolved.border, current: style.border, allowNone: true) { paint, live in
                    editor.updateStyle(actionName: L("Change Border"), coalesce: live ? "border" : nil) { $0.border = paint }
                }
            }
        }

        InspectorSection(title: L("Text")) {
            InspectorRow(title: L("Size")) {
                let size = Int(resolved.font.pointSize.rounded())
                Picker(L("Size"), selection: Binding(
                    get: { size },
                    set: { v in editor.updateStyle(actionName: L("Change Font Size")) { $0.fontSize = Double(v) } })) {
                    ForEach(Array(Set(Self.fontSizes + [size])).sorted(), id: \.self) { s in
                        Text("\(s)").tag(s)
                    }
                }
                .inspectorPopUp(width: 80)
            }
            InspectorRow(title: L("Font Style")) {
                HStack(spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { NSFontManager.shared.traits(of: resolved.font).contains(.boldFontMask) },
                        set: { v in editor.updateStyle(actionName: L("Bold")) { $0.bold = v } })) {
                        Image(systemName: "bold").frame(width: 14)
                    }
                    .help(L("Bold (⌘B)"))
                    Toggle(isOn: Binding(
                        get: { style.italic ?? false },
                        set: { v in editor.updateStyle(actionName: L("Italic")) { $0.italic = v ? true : nil } })) {
                        Image(systemName: "italic").frame(width: 14)
                    }
                    .help(L("Italic (⌘I)"))
                }
                .toggleStyle(.button)
            }
            InspectorRow(title: L("Color")) {
                ColorButton(shown: resolved.text, current: style.textColor) { paint, live in
                    editor.updateStyle(actionName: L("Change Text Color"), coalesce: live ? "text-color" : nil) { $0.textColor = paint }
                }
            }
        }

        InspectorSection(title: L("Branch")) {
            InspectorRow(title: L("Branch Color")) {
                ColorButton(shown: resolved.branchColor, current: style.branchColor) { paint, live in
                    editor.updateStyle(actionName: L("Change Branch Color"), coalesce: live ? "branch-color" : nil) {
                        $0.branchColor = paint
                    }
                }
            }
            .help(L("Colors the lines and topics of this whole branch."))
            InspectorRow(title: L("Boundary")) {
                Toggle(L("Boundary"), isOn: Binding(
                    get: { style.boundary ?? false },
                    set: { _ in editor.toggleBoundary() }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .help(L("Draw a boundary around this branch"))
        }

        if let image = topic.image {
            InspectorSection(title: L("Image")) {
                InspectorRow(title: L("Width")) {
                    Slider(value: Binding(
                        get: { image.width },
                        set: { editor.setImageWidth(of: topic.id, width: $0.rounded()) }), in: 24...600)
                    Text("\(Int(image.width))").monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }

        InspectorFooter {
            Button(L("Reset Style")) { editor.clearStyle() }
                .disabled(editor.selectedTopics.allSatisfy { $0.style.isEmpty || $0.style == TopicStyle(boundary: $0.style.boundary) })
                .help(L("Remove individual formatting so the topic follows the theme."))
        }
    }
}

/// 联系线设置：标签、颜色、虚线、箭头。
struct RelationshipInspector: View {
    let editor: MapEditor
    let relationship: Relationship
    @State private var label = ""

    var body: some View {
        let id = relationship.id
        InspectorSection(title: L("Relationship Label")) {
            TextField(L("Describe how the two topics are related"), text: $label)
                .textFieldStyle(.roundedBorder)
                .onSubmit { editor.updateRelationship(id, actionName: L("Edit Relationship Label")) { $0.title = label } }
            Text(L("Press Return to apply.")).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { label = relationship.title }
        .onChange(of: relationship.id) { label = relationship.title }
        .onChange(of: relationship.title) { label = relationship.title }

        InspectorSection(title: L("Line")) {
            InspectorRow(title: L("Color")) {
                ColorButton(shown: editor.layout.relationship(id)?.color, current: relationship.color) { paint, live in
                    editor.updateRelationship(id, actionName: L("Change Line Color"), coalesce: live ? "relationship-color-\(id)" : nil) {
                        $0.color = paint
                    }
                }
            }
            switchRow(L("Dashed line"), \.dashed, actionName: L("Change Line Style"))
            switchRow(L("Arrow at start"), \.arrowStart, actionName: L("Change Arrow"))
            switchRow(L("Arrow at end"), \.arrowEnd, actionName: L("Change Arrow"))
        }

        InspectorFooter {
            HStack {
                Button(L("Reset Shape")) { editor.resetRelationshipShape(id) }
                Button(L("Delete Relationship"), role: .destructive) { editor.deleteRelationship(id) }
            }
            Text(L("Drag the line, its label or the round handles on the canvas to change the curve."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func switchRow(_ title: String, _ key: WritableKeyPath<Relationship, Bool>, actionName: String) -> some View {
        let id = relationship.id
        return InspectorRow(title: title) {
            Toggle(title, isOn: Binding(
                get: { relationship[keyPath: key] },
                set: { v in editor.updateRelationship(id, actionName: actionName) { $0[keyPath: key] = v } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}
