# cmux Architecture, Patterns, and Antipatterns

Research for Mistty (macOS terminal emulator with libghostty + SwiftUI).

## Project Overview

cmux is a Ghostty-based macOS terminal (14k stars, v0.63.2 as of 2026-04-06) with vertical tabs, notification rings, an in-app browser, and SSH remote sessions. Written in Swift (77.7%) with AppKit, it uses libghostty for terminal rendering and reads existing Ghostty config. The remote daemon is a Go binary bootstrapped over SSH.

- License: GPL-3.0-or-later
- Build: Xcode project (GhosttyTabs.xcodeproj) + Swift Package Manager (Package.swift with SwiftTerm dependency, though the main build uses Xcode)
- Ghostty integration: git submodule pointing to a fork (manaflow-ai/ghostty), built as GhosttyKit.xcframework via Zig

---

## 1. Architecture

### Hierarchy: Window > TabManager > Workspace > BonsplitController > Panels

The core domain model has four layers:

1. **Window / TabManager** (`TabManager.swift`): Manages the sidebar of workspaces. Each window has one TabManager. `typealias Tab = Workspace` confirms workspaces are the sidebar-level unit.

2. **Workspace** (`Workspace.swift`): The central object. Each sidebar tab is a Workspace. A Workspace owns:
   - One `BonsplitController` (split pane tree manager, from the `Bonsplit` library)
   - A dictionary of `panels: [UUID: any Panel]`
   - Mapping between Bonsplit's `TabID` and panel UUIDs (`surfaceIdToPanelId`)
   - All sidebar metadata: git branch, PR status, listening ports, notifications, status entries, log entries, progress state
   - Remote SSH session state (when `cmux ssh` is used)

3. **BonsplitController**: Third-party split pane library managing a tree of panes. Each pane can hold multiple tabs (surfaces). Bonsplit handles split orientation, divider positions, tab reordering, drag-to-split, and zoom.

4. **Panel** (`Panel.swift`): Protocol with three implementations:
   - `TerminalPanel` (wraps a GhosttyTerminalView)
   - `BrowserPanel` (wraps a WKWebView via portal pattern)
   - `MarkdownPanel` (renders markdown files)

### Key architectural decisions

- **AppKit, not SwiftUI for core rendering**: Terminal views use AppKit's NSView hierarchy with a "portal" pattern (TerminalWindowPortal, BrowserWindowPortal) where views are hosted at the window level and positioned to match SwiftUI anchor views. This avoids SwiftUI's view lifecycle destroying terminal state during tab switches.

- **`keepAllAlive` content lifecycle**: Bonsplit is configured with `contentViewLifecycle: .keepAllAlive`, meaning all tab content stays alive even when not selected. This preserves terminal state across tab switches.

- **Flat Sources directory**: All Swift files live in `Sources/` with only three subdirectories (`Find/`, `Panels/`, `Update/`). No module separation.

- **Single executable target**: Package.swift defines one target. The CLI (`CLI/cmux.swift`) appears to be a separate build artifact, not a Swift Package target.

### Session persistence

`SessionPersistence.swift` handles save/restore of workspace layout, panel metadata, scrollback, browser history, and divider positions. The snapshot model is hierarchical: `SessionWorkspaceSnapshot` contains `SessionPanelSnapshot[]` and `SessionWorkspaceLayoutSnapshot` (recursive split tree).

### Remote SSH architecture

The remote system is substantial:
- A Go daemon (`daemon/remote/`) is bootstrapped onto the remote host via SCP
- Communication uses newline-delimited JSON-RPC over SSH stdio
- A SOCKS5/HTTP CONNECT proxy tunnels browser traffic through the daemon
- A reverse SSH forward provides CLI relay back to the local app
- HMAC-SHA256 challenge-response authentication protects the relay

---

## 2. Patterns Worth Adopting

### Panel protocol with typed variants

The `Panel` protocol is clean: `id`, `panelType`, `displayTitle`, `displayIcon`, `isDirty`, `close()`, `focus()`, `unfocus()`, plus focus intent management. The `PanelFocusIntent` enum (`.panel`, `.terminal(.surface | .findField)`, `.browser(.webView | .addressBar | .findField)`) is a good pattern for managing focus across heterogeneous content types. Mistty could adopt this for terminal + browser + preview panes.

### Socket control API for scriptability

cmux exposes a Unix domain socket (`/tmp/cmux.sock`) with multiple access modes (off, cmux-only, automation, password, full open). The CLI communicates with the running app through this socket. This is the right pattern for a terminal that wants to be scriptable: the app is the server, the CLI is a thin client. The access mode enum with per-mode file permissions is well-designed.

### Notification system via OSC sequences + CLI

Notifications use standard terminal escape sequences (OSC 9/99/777) plus a `cmux notify` CLI command for agent hooks. Each pane gets a visual ring, tabs light up, and Cmd+Shift+U jumps to the most recent unread. The `WorkspaceAttentionCoordinator` manages flash decisions with a persistent state model that prevents navigation flashes from competing with notification indicators. This is directly relevant to Mistty's core value prop.

### Sidebar metadata aggregation

Each workspace aggregates metadata from all its panels: git branches, PR status, listening ports, status entries, log entries, progress state. The `SidebarBranchOrdering` enum handles deduplication and display ordering across panels. The `SidebarStatusEntry` struct with key/value/icon/color/priority/timestamp is a flexible model for showing contextual info per workspace.

### Session restore with scrollback persistence

The session persistence system captures terminal scrollback (with configurable line limits), browser navigation history, divider positions, and panel metadata. The `restoredTerminalScrollbackByPanelId` dictionary provides fallback scrollback when live capture fails. The `SessionScrollbackReplayStore` replays scrollback into new terminal sessions via environment variables.

### Ghostty config compatibility

Reading `~/.config/ghostty/config` for themes, fonts, and colors is a smart adoption strategy. Users switching from Ghostty get their settings for free. The `GhosttyConfig.swift` handles parsing and the `GhosttyBackgroundTheme` manages opacity-aware color theming.

### Port scanning for sidebar display

`PortScanner.swift` detects listening ports per terminal session. For remote sessions, it uses `ss` or `lsof` over SSH, scoped to the terminal's TTY. The sidebar shows which ports each workspace is listening on. This is useful context for development workflows.

---

## 3. Antipatterns to Avoid

### Workspace.swift is a god object

`Workspace.swift` is the single largest file in the project. Based on the raw content retrieved, it contains thousands of lines covering:
- Panel lifecycle (create, close, detach, attach)
- Focus management (reconciliation, flash animations, intent tracking)
- Split pane operations (all BonsplitDelegate methods)
- Session persistence (snapshot, restore)
- Remote SSH session management (daemon bootstrap, proxy, relay, port scanning)
- Sidebar metadata (git branches, PRs, ports, status entries, logs)
- Tab context menu actions
- Browser portal visibility reconciliation
- Terminal geometry reconciliation
- Custom layout application from cmux.json

The remote SSH code alone (WorkspaceRemoteSessionController, WorkspaceRemoteDaemonRPCClient, WorkspaceRemoteDaemonProxyTunnel, WorkspaceRemoteProxyBroker, WorkspaceRemoteCLIRelayServer, and many supporting types) is embedded directly in Workspace.swift rather than in separate files. This makes the file extremely difficult to navigate and reason about.

**Lesson for Mistty**: Split the workspace into focused components early. Remote session management, sidebar metadata aggregation, session persistence, and focus reconciliation should each be their own type, composed into the workspace.

### Flat source directory with no module boundaries

All Swift source files live in a single `Sources/` directory with minimal subdirectory organization. There are no Swift Package modules or framework targets to enforce dependency boundaries. Any file can reference any other type. This makes it easy to accumulate coupling.

**Lesson for Mistty**: Use Swift Package local packages or at least clear directory conventions from the start. Terminal rendering, session management, sidebar UI, and configuration should have clear boundaries.

### Complex focus reconciliation

The focus management code is intricate: `reconcileFocusState()`, `scheduleFocusReconcile()`, `applyTabSelection()`, `preserveFocusAfterNonFocusSplit()`, `beginEventDrivenLayoutFollowUp()`, `attemptEventDrivenLayoutFollowUp()`, with generation counters, stall detection, backoff delays, and multiple notification observers. This complexity stems from the tension between SwiftUI's declarative model and AppKit's imperative first-responder system, compounded by the portal pattern.

**Lesson for Mistty**: If using a portal/hosting pattern for terminal views, design the focus ownership model carefully upfront. Consider whether SwiftUI's `@FocusState` can be the single source of truth, or commit fully to AppKit focus management with a clear state machine.

### Defensive pointer validation

The `cmuxSurfacePointerAppearsLive()` function checks `malloc_zone_from_ptr` and `malloc_size` to detect freed Ghostty surface pointers. This suggests the Swift wrapper can outlive the native surface, creating use-after-free risks. The code works around this with runtime checks rather than ownership guarantees.

**Lesson for Mistty**: Design the libghostty surface lifecycle so Swift wrappers cannot outlive the native surface. Use a handle type that nullifies on close rather than relying on malloc introspection.

### Two test directories

The project has both `tests/` (Python integration tests) and `tests_v2/` plus `cmuxTests/` and `cmuxUITests/`. The Python tests communicate via the socket API and run on a VM. This split suggests the testing strategy evolved organically.

---

## 4. Terminal Multiplexer UX Ideas

### Workspace-as-context (not just tabs)

cmux's workspace model bundles terminal panes, browser panes, git branch, PR status, listening ports, notifications, and custom metadata into a single sidebar entry. This is richer than tmux's window concept. For Mistty, each workspace could represent a project context with all its associated state.

### Notification rings with jump-to-unread

The blue ring on panes + tab highlight + Cmd+Shift+U to jump to latest unread is the killer feature for parallel agent workflows. The `WorkspaceAttentionCoordinator` prevents flash spam by checking persistent state before allowing animations.

### In-app browser with scriptable API

Browser panes that route through the remote network (for SSH sessions) so `localhost` URLs work. The browser has a scriptable API (accessibility tree snapshots, element refs, click, fill, evaluate JS). This is unique among terminal apps.

### Custom commands via cmux.json

Project-specific actions defined in a `cmux.json` file that launch from the command palette. The `CmuxConfig.swift` and `CmuxConfigExecutor.swift` handle parsing and execution. The `CmuxDirectoryTrust.swift` adds a trust model so arbitrary project configs don't auto-execute.

### Vertical tabs with rich metadata

The sidebar shows per-workspace: git branch (with dirty indicator), linked PR status/number, working directory, listening ports, and latest notification text. This density of information in the sidebar is more useful than traditional horizontal tab bars.

### SSH as a first-class workspace type

`cmux ssh user@remote` creates a dedicated workspace with automatic daemon bootstrap, proxy tunneling, port detection, and CLI relay. The remote terminal sessions are tracked separately from local ones, with proper cleanup on disconnect.

---

## 5. Build System / Dev Tooling

### Xcode project + shell scripts

The primary build uses `GhosttyTabs.xcodeproj` with shell scripts for workflow:
- `scripts/setup.sh`: one-time submodule init + xcframework build
- `scripts/reload.sh`: debug build (with `--launch` to auto-open)
- `scripts/reloadp.sh`: release build
- `scripts/rebuild.sh`: clean rebuild

### Ghostty as a git submodule

The ghostty fork is a git submodule built with Zig (`zig build -Demit-xcframework=true -Doptimize=ReleaseFast`). This is a pragmatic approach for depending on a C/Zig library from Swift.

### Go daemon with cross-compilation

The remote daemon is a Go module (`daemon/remote/`) cross-compiled for darwin/linux x amd64/arm64. Release builds embed a manifest with SHA-256 digests in Info.plist. Dev builds can fall back to local `go build` with an env var flag.

### Python integration tests via socket API

Integration tests are Python scripts that communicate with the running app through the Unix socket. Tests run on a VM (`cmux-vm`). This is a practical approach for testing a GUI app's behavior programmatically.

### Sparkle for auto-updates

The app uses Sparkle for auto-updates, with separate feeds for stable and nightly builds. Nightly has its own bundle ID so it runs alongside stable.

### Homebrew cask distribution

`brew tap manaflow-ai/cmux && brew install --cask cmux` with the homebrew-cmux repo as a submodule.

---

## Key Takeaway for Mistty

The most transferable pattern is the **Workspace model as a rich context container** with the **Panel protocol** for heterogeneous content types, combined with the **socket API for scriptability** and **notification system for agent awareness**. The most important antipattern to avoid is letting the Workspace type grow into a god object. cmux's Workspace.swift demonstrates what happens when session management, remote connectivity, focus reconciliation, sidebar metadata, and panel lifecycle all live in one type: the file becomes unmaintainable. Mistty should decompose these concerns into separate types from the start, composed via protocols or dependency injection.

## Sources

- [2026-04-14] https://github.com/manaflow-ai/cmux (README, directory structure, file listings)
- [2026-04-14] https://github.com/manaflow-ai/cmux/blob/main/CONTRIBUTING.md (build setup, dev scripts)
- [2026-04-14] https://github.com/manaflow-ai/cmux/blob/main/Sources/Workspace.swift (core domain model, session persistence, remote SSH, focus management)
- [2026-04-14] https://github.com/manaflow-ai/cmux/blob/main/Sources/Panels/Panel.swift (Panel protocol, focus intent types, attention coordination)
- [2026-04-14] https://github.com/manaflow-ai/cmux/blob/main/Sources/TabManager.swift (workspace placement, sidebar settings)
- [2026-04-14] https://github.com/manaflow-ai/cmux/blob/main/Sources/SocketControlSettings.swift (socket access modes, password store)
- [2026-04-14] https://github.com/manaflow-ai/cmux/blob/main/daemon/remote/README.md (Go daemon architecture, RPC methods, CLI relay)
- [2026-04-14] https://github.com/manaflow-ai/cmux/blob/main/Package.swift (Swift package structure)
