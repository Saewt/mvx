<h1 align="center">mvx</h1>
<p align="center">A native macOS terminal workspace with agent status tracking, tiling layouts, and session persistence</p>

<p align="center">
  <img src="./mvx.png" alt="mvx screenshot" width="900" />
</p>

## Features

<table>
<tr>
<td width="40%" valign="middle">
<h3>Agent status badges</h3>
Tabs display color-coded badges when coding agents change state: running (green), waiting for input (orange), done (teal), or error (red). You can jump to the next session that requires attention with a single shortcut.
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Sidebar with live context</h3>
Each session tab shows its git branch, dirty status, current working directory, and foreground process name, updated in real time.
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Session groups</h3>
Organize sessions into named groups with color tags. Collapse, expand, and move sessions between groups with drag and drop.
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Tiling pane layouts</h3>
Split any pane horizontally or vertically, resize panes by dragging dividers, and move between panes from the keyboard. Layouts are saved and restored on relaunch.
</td>
</tr>
</table>

- **Command palette** — Keyboard-driven access to all workspace commands (`⌘⇧P`)
- **Session persistence** — Layout, working directories, and pane splits are restored on relaunch
- **Terminal hyperlinks** — OSC 8 hyperlinks are parsed and rendered as clickable links
- **Clipboard integration** — OSC 52 clipboard read/write with configurable policy
- **Built-in themes** — Catppuccin (default), Dracula, Solarized, Nord
- **Native macOS app** — Built with Swift and SwiftUI for fast startup and low memory usage
- **GPU-accelerated** — Powered by libghostty for smooth rendering

## Install

Download the latest release, open the `.dmg`, and move `mvx.app` to the `Applications` folder.

If macOS blocks the app on first launch because it cannot verify the developer, open **System Settings > Privacy & Security**, review the security notice for `mvx`, and choose **Open Anyway**.

If the app remains quarantined after installation, you can remove the quarantine attribute from Terminal:
```
xattr -cr /Applications/mvx.app
```

mvx ships with Sparkle-compatible update metadata for direct distribution builds.

## Session restore

On relaunch, mvx restores:
- Window and pane layout
- Split ratios
- Working directories

mvx does **not** restore live process state. Active shell sessions, running agents, or editors are not resumed after a restart.
