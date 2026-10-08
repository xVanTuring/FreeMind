<p align="center">
  <img src="Sources/FreeMind/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="FreeMind icon">
</p>

<h1 align="center">FreeMind</h1>

<p align="center">
  A native macOS mind-mapping app inspired by XMind. Most editing is done from the keyboard.<br>
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a>
</p>

![Main window with a sample map and the format panel](docs/images/hero.png)

## Highlights

### AI agents can edit your maps (MCP)

FreeMind runs a local [MCP](https://modelcontextprotocol.io) server. Once connected, AI agents that support MCP,
such as Claude Code and Codex, can read and edit the maps you have open:

- Read a whole map or a single branch, search topics, and render the map as an image to check the result
- Add, edit, move and delete topics; set markers, labels, notes, relationships and formatting
- Create maps, open or import Markdown / OPML / XMind files, and save

For example, ask the agent to "turn these meeting notes into a mind map" or "give every unfinished task a priority".
Every change an agent makes is one undo step, so ⌘Z takes it back.

To connect, open Settings ▸ Agent, click Copy Command and run it once in Terminal to add FreeMind to Claude Code;
other agents can use the configuration from Copy JSON. Only programs on your own Mac can connect, and every request
must carry the access token. Turn off "Allow agents to edit maps" to give agents read-only access.
See the [MCP guide (in Chinese)](docs/mcp.md).

### Local only, no cloud

- Your maps are `.fmind` files on your Mac. There is no account and no server, and FreeMind never uploads your maps anywhere.
- Editing, saving, importing and exporting all work offline. The only time FreeMind goes online on its own is a daily
  check for a new version on GitHub, which you can turn off in Settings ▸ General ("Check for updates automatically").
- When you connect an AI agent, the map content it reads is handled by the model service that agent uses; that part
  depends on the agent you choose.

### Sync and back up with iCloud Drive

FreeMind has no sync service of its own. To keep maps in sync across your Macs or keep a backup in the cloud, save them
to iCloud Drive (choose iCloud Drive in the sidebar of the Save dialog). A `.fmind` map is a single file in Finder with
its attachments stored inside, so they are synced and backed up together.

Don't edit the same map on two Macs at the same time; before you continue on another Mac, wait for iCloud to finish syncing.

## Download

Get the latest `FreeMind-<version>.dmg` from the [Releases](https://github.com/xVanTuring/FreeMind/releases/latest) page,
open it and drag FreeMind into the Applications folder.

- Requires macOS 14 or later.
- The app is signed with Developer ID and notarized by Apple, so it opens without a security warning.
- Once installed, FreeMind tells you when a new version is available, so you don't need to download it again by hand.

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

## Development

Build instructions, helper scripts, related documents and the project layout are in [Dev.md](Dev.md) (in Chinese).

## License

Copyright © 2026 xVanTuring

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

See [LICENSE](LICENSE) for the full text (SPDX: `GPL-3.0-or-later`).
