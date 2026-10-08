import AppKit
import SwiftUI

/// 设置窗口。
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            ExportSettings()
                .tabItem { Label(L("Export"), systemImage: "square.and.arrow.up") }
            LibrarySettings()
                .tabItem { Label(L("Templates & Themes"), systemImage: "square.grid.2x2") }
        }
        .frame(width: 560, height: 440)
    }
}

private struct GeneralSettings: View {
    @Bindable private var prefs = Preferences.shared
    @State private var themes = ThemeLibrary.shared

    var body: some View {
        Form {
            Section(L("New Maps")) {
                Toggle(L("Show the template gallery when creating a new map"), isOn: $prefs.showTemplateGalleryOnNew)
                Picker(L("Default structure"), selection: $prefs.defaultStructure) {
                    ForEach(MapStructure.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                Picker(L("Default theme"), selection: $prefs.defaultThemeID) {
                    ForEach(themes.allThemes) { Text($0.displayName).tag($0.id) }
                }
                Picker(L("Default spacing"), selection: $prefs.defaultSpacing) {
                    ForEach(MapSpacing.allCases) { Text($0.title).tag($0) }
                }
            }
            Section(L("Opening Maps")) {
                Toggle(L("Restore zoom level and position"), isOn: $prefs.restoreViewState)
                Text(L("Collapsed branches are always saved in the file and restored."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExportSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section(L("Markdown")) {
                Picker(L("Use headings for"), selection: $prefs.markdownHeadingLevels) {
                    Text(L("None (lists only)")).tag(0)
                    ForEach(1...6, id: \.self) { Text(LF("%d levels", $0)).tag($0) }
                }
                Text(L("Deeper levels are exported as nested lists."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("Include notes"), isOn: $prefs.markdownIncludeNotes)
                Toggle(L("Include labels"), isOn: $prefs.markdownIncludeLabels)
                Toggle(L("Export attachments and images to a folder"), isOn: $prefs.markdownExportAttachments)
            }
            Section(L("Image")) {
                Picker(L("PNG resolution"), selection: $prefs.pngScale) {
                    Text("1×").tag(1)
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                    Text("4×").tag(4)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LibrarySettings: View {
    @State private var templates = TemplateLibrary.shared.userTemplates()
    @State private var themes = ThemeLibrary.shared

    var body: some View {
        Form {
            Section(L("My Templates")) {
                if templates.isEmpty {
                    Text(L("No templates yet. Use File ▸ Save as Template to create one."))
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    HStack {
                        Image(systemName: "doc.richtext")
                        Text(template.name)
                        Spacer()
                        Button(L("Show in Finder")) {
                            if let url = template.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button(L("Delete"), role: .destructive) {
                            try? TemplateLibrary.shared.deleteUserTemplate(template)
                            templates = TemplateLibrary.shared.userTemplates()
                        }
                    }
                }
                Button(L("Open Templates Folder")) { NSWorkspace.shared.open(AppDirectories.templates) }
            }
            Section(L("Custom Themes")) {
                if themes.customThemes.isEmpty {
                    Text(L("No custom themes yet. Adjust a theme in the format panel, then choose Save as Custom Theme."))
                        .foregroundStyle(.secondary)
                }
                ForEach(themes.customThemes) { theme in
                    HStack {
                        Image(nsImage: ThemePreview.image(for: theme, size: CGSize(width: 100, height: 60)))
                            .resizable().frame(width: 50, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(theme.displayName)
                        Spacer()
                        Button(L("Delete"), role: .destructive) { themes.delete(id: theme.id) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { templates = TemplateLibrary.shared.userTemplates() }
    }
}

/// 快捷键一览。
struct KeyboardShortcutsView: View {
    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [(String, String)]
    }

    private var groups: [Group] {
        [
            Group(title: L("Add Topics"), items: [
                ("⇥", L("Insert subtopic")), ("↩", L("Insert sibling topic")), ("⇧↩", L("Insert topic before")),
                ("⌘↩", L("Insert parent topic")), ("⌘D", L("Duplicate topic")),
            ]),
            Group(title: L("Edit"), items: [
                (L("Space / F2"), L("Edit topic text")), (L("Type"), L("Replace topic text")),
                ("⇧↩", L("New line while editing")), ("⎋", L("Cancel editing")), ("⌫", L("Delete topic")),
                ("⌥⌫", L("Delete topic but keep its subtopics")), ("⌘Z / ⇧⌘Z", L("Undo / Redo")),
            ]),
            Group(title: L("Navigate & Organize"), items: [
                ("← → ↑ ↓", L("Move selection")), ("⇧ + ← → ↑ ↓", L("Extend selection")),
                ("⌥↑ / ⌥↓", L("Move topic up / down")), ("⌥← / ⌥→", L("Promote / demote topic")),
                ("⌘/", L("Collapse or expand branch")), ("⌥⌘/", L("Expand all")), ("⌃⌘/", L("Collapse all")),
                ("⌘A / ⇧⌘A", L("Select all / select siblings")), ("⌘Home", L("Select central topic")),
                (L("Drag"), L("Move topic; hold ⌥ to copy")), (L("⌥ + drag blank space"), L("Pan the map")),
            ]),
            Group(title: L("Topic Content"), items: [
                ("⌥⌘N", L("Note")), ("⌘K", L("Hyperlink")), ("⌥⌘A", L("Attach file")), ("⇧⌘I", L("Insert image")),
                ("⇧⌘L", L("Labels")), ("⌘1 … ⌘6", L("Priority 1 to 6")), ("⌥⌘B", L("Boundary")),
                ("⌘L", L("Connect two topics")),
                ("⌘B / ⌘I", L("Bold / italic")), ("⌥⌘C / ⌥⌘V", L("Copy / paste style")),
            ]),
            Group(title: L("View"), items: [
                ("⌘+ / ⌘-", L("Zoom in / out")), ("⌘0", L("Actual size")), ("⌘9", L("Zoom to fit")),
                (L("⌘ + scroll"), L("Zoom with the mouse wheel")), ("⌘F / ⌘G", L("Find / find next")),
                ("⌥⌘I", L("Show or hide the format panel")),
            ]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title).font(.headline)
                        ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.0)
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .frame(width: 150, alignment: .leading)
                                Text(item.1).foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}
