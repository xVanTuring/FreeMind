<p align="center">
  <img src="Sources/FreeMind/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="FreeMind icon">
</p>

<h1 align="center">FreeMind</h1>

<p align="center">
  A native macOS mind-mapping app inspired by XMind. Most editing is done from the keyboard.<br>
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a>
</p>

![Main window with a sample map and the format panel](docs/images/hero.png)

## Features

### Mapping

- **Five structures**: mind map (balanced), logic chart (right / left), org chart and tree chart. Switch at any time.
- **12 built-in themes**: Classic, Rainbow, Fresh, Ocean, Forest, Sunset, Candy, Business, Minimal, Ink & Paper, Midnight and Graphite. Adjust the background, branch colors, font and line width, then save the result as your own theme.
- **Topic content**: notes, hyperlinks, attachments, images, labels, markers (priority, progress, flags, stars, symbols), boundaries, and relationships with labels and adjustable curves.
- **Per-topic styling**: shape (rounded rectangle, rectangle, capsule, ellipse, diamond, underline, no border), fill, border, text color, font size, bold / italic and branch color. Styles can be copied and pasted.
- **Keyboard first**: Tab adds a subtopic, Return adds a sibling, and typing on a selected topic edits it. Input methods compose text in place.
- **Find**: ⌘F searches topic text, labels and notes, and expands collapsed branches to show matches.

### Files

- **Own `.fmind` format**: a macOS package that keeps attachments inside the file, so nothing gets lost when you move or share it ([format spec, in Chinese](docs/format.md)).
- **Collapsed branches are saved in the file** and restored when you reopen it, along with the zoom level, scroll position and selection.
- **Import**: Markdown, OPML, XMind (current format and XMind 8) and plain indented outlines.
- **Export**: Markdown (optionally with attachments copied to a folder), OPML, PNG and PDF, plus printing.
- **Finder integration**: a Quick Look extension provides thumbnails and space-bar previews for `.fmind` files.

### App

- **Welcome window**: lists recent maps with thumbnails; click one to open it. Right-click the Dock icon for New Map and Open.
- **Template gallery**: ⌘N lets you start from a blank map or a template. Any map can be saved as a template.
- **Native macOS behavior**: autosave, version browsing, undo / redo, window tabs, full screen and dark mode.
- **Automatic updates**: signed and notarized releases on GitHub; the app checks for new versions daily (FreeMind ▸ Check for Updates…).
- **AI agent access (MCP)**: FreeMind runs a local [MCP](https://modelcontextprotocol.io) server, so agents such as Claude Code can read your open maps and add, edit, move or delete topics. Every change an agent makes is one undo step. Set it up in Settings ▸ Agent ([details, in Chinese](docs/mcp.md)).
- English and Simplified Chinese interface, following the system language.

## Screenshots

### Welcome window

Recent maps are listed at launch. Click one to continue where you left off.

![Welcome window](docs/images/welcome.png)

### Template gallery

Templates include Getting Started, Project Plan, Meeting Notes, SWOT Analysis, Weekly Plan, Book Notes, Brainstorm, Decision Making and Org Chart.

![Template gallery](docs/images/gallery.png)

### Format panel

One setting per row; colors open in a palette with the theme default, preset colors, and the system color panel for anything else.

<img src="docs/images/colors.png" width="620" alt="Color palette in the format panel">

### Five structures

![Five structures](docs/images/structures.png)

### Built-in themes (selection)

![Built-in themes](docs/images/themes.png)

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Insert subtopic | Tab |
| Insert sibling topic | Return |
| Insert topic before | ⇧Return |
| Insert parent topic | ⌘Return |
| Edit text | Space / F2 / double-click, or just start typing |
| New line while editing | ⇧Return |
| Delete topic | ⌫ (⌥⌫ deletes the topic but keeps its subtopics) |
| Move selection | Arrow keys (add ⇧ to extend) |
| Reorder / promote / demote | ⌥↑ ⌥↓ / ⌥← ⌥→ |
| Collapse / expand branch | ⌘/ (⌥⌘/ expand all, ⌃⌘/ collapse all) |
| Move topic | Drag it (hold ⌥ to copy) |
| Note / link / attachment / image / labels | ⌥⌘N / ⌘K / ⌥⌘A / ⇧⌘I / ⇧⌘L |
| Priority | ⌘1 … ⌘6 |
| Relationship | ⌘L, then click the target topic (or select two topics first) |
| Boundary | ⌥⌘B |
| Zoom | ⌘+ ⌘- ⌘0, ⌘9 zoom to fit, ⌘ + scroll |
| Format panel | ⌥⌘I |
| New / open | ⌘N (opens the template gallery) / ⌘O |
| Welcome window (recent maps) | ⇧⌘1 |
| Pan the canvas | Scroll on the trackpad, or hold ⌥ and drag empty space |

See Help ▸ Keyboard Shortcuts for the full list. The Getting Started map opens on first launch and is always available from Help ▸ Getting Started.

## Sample maps

[`docs/samples/`](docs/samples) contains the maps used for the screenshots above. Open them in FreeMind to explore.

## Building

Requires macOS 14 or later, Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen                      # generates FreeMind.xcodeproj from project.yml
xcodebuild -project FreeMind.xcodeproj -scheme FreeMind -configuration Release build
xcodebuild -project FreeMind.xcodeproj -scheme FreeMind test
```

Local builds are ad-hoc signed and run directly. The first build resolves the [Sparkle](https://sparkle-project.org) package used for automatic updates.

Helper scripts:

- `scripts/make-icon.sh` renders `Sources/FreeMind/Resources/AppIcon.svg` into the app icon set (requires `rsvg-convert`).
- `scripts/check-strings.sh` checks that every UI string has a Chinese translation.
- `scripts/package.sh` builds a Developer ID signed, notarized `.zip` and `.dmg`; `scripts/release.sh` publishes a GitHub release and the Sparkle update feed ([details, in Chinese](docs/release.md)).

## Project layout

```
Sources/FreeMind/
├─ App/            Launch, main menu, welcome window, document controller
├─ Model/          Topic tree, markers, relationships (value types; undo stores snapshots)
├─ Theme/          Color descriptions, theme definitions, built-in and custom themes
├─ Layout/         Style resolution, text measurement, layout for the five structures
├─ Canvas/         Canvas view (drawing, selection, inline editing, drag and drop), renderer, popovers
├─ Document/       NSDocument subclass, .fmind package I/O, attachment store, export
├─ Editor/         MapEditor (all edits and undo), window, toolbar, find bar, status bar
├─ Inspector/      Format panel (Style / Map / Markers / Content)
├─ ImportExport/   Markdown, OPML, XMind, image export
├─ Templates/      Built-in templates, user templates, template gallery
├─ Settings/       Preferences, settings window, keyboard shortcuts window
├─ MCP/            Local MCP server for AI agents (HTTP, JSON-RPC, tools)
└─ Resources/      Info.plist, icons, English and Chinese localizations
Extensions/
├─ QuickLook/      Space-bar preview extension (data-based, renders PDF)
├─ Thumbnail/      Finder thumbnail extension
└─ Shared/         Reading code and sandbox entitlements shared by both extensions
```

## License

Copyright © 2026 xVanTuring

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

See [LICENSE](LICENSE) for the full text (SPDX: `GPL-3.0-or-later`).
