# Mistty UX Feature Brainstorm

Date: 2026-04-14
Inputs: terminal UX patterns, SwiftUI primitives, cmux architecture, Ghostty/WezTerm/Kitty feature requests, current improvement plan

Mistty's current state: macOS terminal on libghostty, SwiftUI, sessions/tabs/split panes, sidebar, session manager (Cmd+J), copy mode, window mode. ContentView recently decomposed into managers.

---

## Scoring

Each idea is rated on three axes (1-5):

- **Delight**: how much would this make users choose Mistty over alternatives?
- **Complexity**: how hard to build (1 = easy, 5 = very hard)
- **Uniqueness**: how differentiated from what exists in Ghostty, Kitty, WezTerm, iTerm2

Composite score: `(delight * uniqueness) / complexity`. Higher is better.

---

## Tier 1: Table Stakes

These are expected by users switching from any modern terminal or tmux setup. Missing any of these is a reason to not switch.

### 1. Session Resurrection

Automatically save and restore full terminal state (layout, working directories, scrollback, pane arrangement) across app restarts. No manual save/restore keybindings.

- **Prior art**: tmux-resurrect + continuum (manual/auto save, manual restore), cmux SessionPersistence (automatic), Kitty 0.43 session management (partial). WezTerm relies on community plugin resurrect.wezterm.
- **SwiftUI approach**: `NSApplicationDelegate` state restoration hooks. `@SceneStorage` for per-window layout metadata. Serialize split tree + working directories to JSON on `applicationWillTerminate`. Replay scrollback via environment variables on restore (cmux's `SessionScrollbackReplayStore` pattern).
- **Delight**: 4 — top-voted request across Ghostty (#1847), WezTerm (#3237), Kitty (#1197, open since 2018)
- **Complexity**: 3 — scrollback capture and replay is the hard part; layout serialization is straightforward
- **Uniqueness**: 2 — cmux and tmux-resurrect do this; Ghostty/Kitty/WezTerm don't (natively)
- **Score**: (4 * 2) / 3 = **2.67**

### 2. Command Palette

Cmd+K opens a fuzzy-searchable floating panel showing all available actions with their keyboard shortcuts. Teaches shortcuts while providing a fallback for forgotten ones.

- **Prior art**: VS Code (Cmd+Shift+P), Warp (Cmd+P), Kitty 0.46 (command palette), cmux (command palette with project-specific actions), Ghostty (NSPanel-based command palette in source, not yet shipped publicly)
- **SwiftUI approach**: `NSPanel` subclass (non-activating, floating) hosting a SwiftUI `TextField` + filtered `List`. Toggle via `NSEvent.addLocalMonitorForEvents`. Use `@FocusedValue` to route selected actions to the active terminal pane.
- **Delight**: 3 — expected in modern apps, not a differentiator
- **Complexity**: 2 — well-understood pattern, Ghostty's source is a reference
- **Uniqueness**: 1 — Kitty, Warp, cmux all have this
- **Score**: (3 * 1) / 2 = **1.50**

### 3. Declarative Project Layouts

A `.mistty.toml` file in a project root defines the workspace layout: pane arrangement, commands per pane, working directories. Opening a project directory detects the file and offers to apply the layout.

- **Prior art**: tmuxinator (YAML), tmuxp (YAML/JSON), zellij KDL layouts, sesh.toml wildcard configs, cmux's cmux.json with directory trust model
- **SwiftUI approach**: Parse TOML at workspace creation. Build the split tree programmatically via the existing pane management API. Add a `CmuxDirectoryTrust`-style trust prompt (`.alert()` modifier) before executing project configs from untrusted directories.
- **Delight**: 4 — reproducible environments are a top reason people use tmux
- **Complexity**: 2 — parsing + split tree construction; the split tree API already exists
- **Uniqueness**: 2 — tmuxinator/zellij/cmux do this, but no libghostty-based terminal does
- **Score**: (4 * 2) / 2 = **4.00**

### 4. Fuzzy Workspace Switcher

Cmd+J (already exists as session manager) enhanced with frecency-ranked project directories (zoxide integration), active workspace list, and instant "last workspace" toggle via Cmd+`.

- **Prior art**: sesh (tmux + zoxide fusion, fuzzy finder, last-session toggle), WezTerm smart_workspace_switcher plugin, zellij session manager TUI
- **SwiftUI approach**: Enhance the existing session manager overlay. Add a frecency store (SQLite or flat file, like zoxide's algorithm). `Cmd+`` mapped via `.commands {}` for instant toggle with no UI. The picker shows Nerd Font icons to distinguish running workspaces vs. directory suggestions.
- **Delight**: 4 — sesh users cite this as the reason they stay on tmux
- **Complexity**: 2 — the session manager UI exists; adding frecency and zoxide data is incremental
- **Uniqueness**: 2 — sesh does this for tmux; no native terminal has it built in
- **Score**: (4 * 2) / 2 = **4.00**

---

## Tier 2: Differentiators

These would make Mistty stand out from Ghostty, Kitty, and WezTerm. Each addresses a gap that users have been requesting for years without resolution.

### 5. Which-Key Overlay

After pressing a leader key (configurable, e.g., Ctrl+Space), a transient overlay appears showing categorized actions with their shortcuts. Hierarchical: press `w` for window actions, `p` for pane actions. Fades after selection or timeout.

- **Prior art**: tmux-which-key (popup menu after prefix), zellij status bar (always-visible mode hints), Karabiner-Elements key viewer, Emacs which-key
- **SwiftUI approach**: `.overlay()` modifier with a `ZStack` containing a semi-transparent background and a `VStack` of action categories. Triggered by `NSEvent.addLocalMonitorForEvents` detecting the leader key. Each category is a `Button` with `.keyboardShortcut()`. Use `withAnimation(.easeOut(duration: 0.15))` for fade transitions. No permanent screen real estate consumed (unlike zellij's status bar).
- **Delight**: 5 — zellij's status bar is the #1 reason users cite for choosing it over tmux; this is the same benefit without the screen cost
- **Complexity**: 2 — straightforward overlay UI with event monitoring
- **Uniqueness**: 4 — no terminal combines hierarchical which-key with zero-chrome transient overlay
- **Score**: (5 * 4) / 2 = **10.00**

### 6. Notification Rings

Per-pane visual indicator (colored ring/badge) when a pane produces new output while not focused. Tab/workspace highlight in sidebar. Cmd+Shift+U jumps to the most recent unread pane. Attention coordinator prevents flash spam during navigation.

- **Prior art**: cmux (blue ring, tab highlight, jump-to-unread, WorkspaceAttentionCoordinator), tmux visual-activity/visual-bell, zellij (no equivalent)
- **SwiftUI approach**: Each pane view gets a `.border()` or `.overlay()` ring driven by an `@Observable` attention state. The sidebar row uses a `Circle()` badge. The attention coordinator is a shared `@Observable` that debounces state changes and tracks a "most recent unread" stack. OSC 9/99/777 escape sequence handling in the libghostty surface delegate triggers the notification.
- **Delight**: 5 — critical for parallel agent workflows where multiple terminals produce output
- **Complexity**: 3 — OSC parsing, attention state machine, debouncing, sidebar integration
- **Uniqueness**: 4 — cmux has this; no other terminal does it well
- **Score**: (5 * 4) / 3 = **6.67**

### 7. Floating Panes

Persistent overlay panes that float above the terminal grid. Toggle the floating layer with Cmd+F. Floating panes keep running when hidden. Drag to reposition, resize handles.

- **Prior art**: zellij (Alt+f toggle, move mode, pin to always-on-top), tmux popup (temporary, not persistent), Ghostty discussion #3197 (201 votes, not shipped)
- **SwiftUI approach**: A `ZStack` layer above the split tree containing draggable `NSPanel`-style views (or SwiftUI views with `.offset()` + `DragGesture`). Each floating pane wraps a terminal surface via `NSViewRepresentable`. State stored in the workspace model alongside the split tree. `.onKeyPress()` for Cmd+F toggle.
- **Delight**: 4 — 201 votes on Ghostty, top request on WezTerm (#270)
- **Complexity**: 3 — drag/resize, z-ordering, focus management between floating and tiled panes
- **Uniqueness**: 3 — zellij has this; no GPU-accelerated native macOS terminal does
- **Score**: (4 * 3) / 3 = **4.00**

### 8. Rich Sidebar Metadata

Each workspace row in the sidebar shows: git branch with dirty indicator, linked PR status, listening ports, working directory, latest notification text. The sidebar becomes a project dashboard, not just a tab list.

- **Prior art**: cmux (git branch, PR status, ports, custom status entries), VS Code sidebar (source control badges)
- **SwiftUI approach**: Extend the existing sidebar `List` row with an `HStack`/`VStack` of metadata views. Git branch from shell integration env vars or periodic `git rev-parse` calls. Port scanning via `lsof -iTCP -sTCP:LISTEN -P` scoped to the terminal's TTY. PR status via `gh pr view --json` (optional, user-configured). Use `@Observable` per-workspace metadata model updated on a timer or on terminal output events.
- **Delight**: 4 — turns the sidebar from "tab names" into "project context at a glance"
- **Complexity**: 3 — git/port detection, PR API integration, keeping metadata fresh without polling too aggressively
- **Uniqueness**: 4 — cmux is the only terminal that does this
- **Score**: (4 * 4) / 3 = **5.33**

### 9. Socket API for Scriptability

Unix domain socket (`/tmp/mistty.sock`) exposing workspace, pane, and session operations. A `mistty` CLI binary acts as a thin client. Enables scripting, automation, and integration with external tools (Raycast, Hammerspoon, shell scripts).

- **Prior art**: cmux (Unix socket with access modes), Kitty (remote control protocol), Ghostty 1.3 (AppleScript preview), WezTerm (Lua event system)
- **SwiftUI approach**: Not SwiftUI-specific. A `NWListener` on a Unix domain socket in the app process. JSON-RPC or line-delimited JSON protocol. The CLI is a separate Swift executable that connects and sends commands. Access control via file permissions (cmux's access mode enum is a good model).
- **Delight**: 4 — Ghostty's scripting API discussion has 240 votes; power users and tool authors need this
- **Complexity**: 3 — socket server, protocol design, CLI binary, security model
- **Uniqueness**: 3 — Kitty has remote control, cmux has socket API; Ghostty and WezTerm don't
- **Score**: (4 * 3) / 3 = **4.00**

---

## Tier 3: Moonshots

Ambitious features that could define Mistty's identity. Higher risk, but the payoff is a terminal that feels like nothing else.

### 10. Native tmux Control Mode

Render tmux panes as native Mistty splits/tabs. Connect to a remote tmux session and display its windows using Mistty's GPU-rendered terminal surfaces instead of nested terminal-in-terminal. Bidirectional: actions in Mistty (split, close, resize) map to tmux commands.

- **Prior art**: iTerm2 (the only terminal that ships this; a key reason users stay on iTerm2). Ghostty #1935 (top-voted open issue). WezTerm #336 (filed by the maintainer).
- **SwiftUI approach**: The tmux control mode protocol (`tmux -CC`) sends structured output describing pane layout changes. Parse this stream and map it to Mistty's split tree model. Each tmux pane becomes a libghostty surface receiving the pane's output stream. Resize events in Mistty send `resize-pane` commands back to tmux. The split tree model already supports programmatic manipulation.
- **Delight**: 5 — top-voted open issue in Ghostty; the feature that keeps users on iTerm2
- **Complexity**: 5 — tmux control mode protocol is complex, edge cases with resize/reflow, bidirectional sync
- **Uniqueness**: 5 — only iTerm2 has this; shipping it would be a headline feature
- **Score**: (5 * 5) / 5 = **5.00**

### 11. Block-Based Output

Treat each command + its output as a discrete, selectable block. Click to select an entire block. Jump between blocks (navigate by command, not by line). Blocks carry metadata: timestamp, exit code, duration, working directory.

- **Prior art**: Warp (the defining feature of their terminal), VS Code terminal (shell integration marks commands)
- **SwiftUI approach**: Requires shell integration (OSC 133 semantic prompts) to detect command boundaries. The terminal surface would need a block overlay layer that draws selection highlights and metadata badges. Block navigation (Cmd+Up/Down to jump between prompts) maps to scrolling to the previous/next OSC 133 mark. Metadata display via `.popover()` on hover or click. This is deeply integrated with the terminal renderer, not just a SwiftUI overlay.
- **Delight**: 5 — Warp's most-cited feature; Ghostty discussion #6916 (72 votes) for "selecting text a la Warp"
- **Complexity**: 4 — shell integration parsing, block boundary detection, overlay rendering synced with terminal scroll, metadata extraction
- **Uniqueness**: 4 — only Warp does this; no libghostty-based terminal has attempted it
- **Score**: (5 * 4) / 4 = **5.00**

### 12. Workspace Snapshots (Time Travel)

Named snapshots of a workspace's full state (layout, scrollback, working directories) that can be restored later. "Bookmark this moment" before a risky operation. Browse snapshots in a timeline view.

- **Prior art**: Git stash (conceptually), tmux-resurrect (save/restore, but not named snapshots), Time Machine (macOS backup with timeline)
- **SwiftUI approach**: Extend the session persistence system to support multiple named snapshots per workspace. A `.sheet()` or sidebar section shows a timeline of snapshots with timestamps and user-provided names. Restoring a snapshot rebuilds the split tree and replays scrollback. Store snapshots in `~/Library/Application Support/Mistty/snapshots/`.
- **Delight**: 3 — niche but powerful for users who do risky operations (database migrations, deploy scripts)
- **Complexity**: 3 — builds on session persistence; the incremental work is snapshot management UI and storage
- **Uniqueness**: 5 — no terminal or multiplexer offers named workspace snapshots
- **Score**: (3 * 5) / 3 = **5.00**

### 13. Cursor Trail

Smooth animated trail following the cursor, with configurable color, length, and decay. A cosmetic feature that generates outsized enthusiasm.

- **Prior art**: Kitty (shipped cursor_trail, customizable color in 0.43), Neovide (smooth cursor animation). Ghostty discussion #4199 (347 votes, top-voted discussion). WezTerm #6492 and #7387.
- **SwiftUI approach**: This lives in the terminal renderer (libghostty/Metal layer), not in SwiftUI. Would require patching the Ghostty fork's Metal shader to add a trail effect. Configuration exposed via Mistty's settings.
- **Delight**: 3 — 347 votes on Ghostty, described as "the last thing keeping many users on Kitty" in WezTerm issues
- **Complexity**: 4 — Metal shader work in the Ghostty fork; not a SwiftUI feature
- **Uniqueness**: 2 — Kitty already ships this
- **Score**: (3 * 2) / 4 = **1.50**

### 14. Inline Preview Panes

Hover over a file path in terminal output to see a preview (syntax-highlighted code, image thumbnail, markdown render). Click to open in a split pane. Uses macOS Quick Look or a custom renderer.

- **Prior art**: VS Code terminal (Cmd+click opens files), cmux MarkdownPanel, macOS Quick Look (spacebar preview in Finder)
- **SwiftUI approach**: Detect file paths in terminal output via regex on OSC-marked semantic zones or on hover. Show a `.popover()` with a `QLPreviewView` (via `NSViewRepresentable` wrapping `QLPreviewPanel`) or a custom `CodeEditor` view for source files. "Open in pane" creates a new split with a `MarkdownPanel`-style read-only view.
- **Delight**: 4 — bridges the gap between terminal and IDE without leaving the terminal
- **Complexity**: 4 — path detection in terminal output, Quick Look integration, split pane creation from hover
- **Uniqueness**: 5 — no terminal does inline file previews from output
- **Score**: (4 * 5) / 4 = **5.00**

---

## Score Rankings

| Rank | Idea | Tier | Delight | Uniqueness | Complexity | Score |
|------|------|------|---------|------------|------------|-------|
| 1 | Which-Key Overlay | 2 | 5 | 4 | 2 | **10.00** |
| 2 | Notification Rings | 2 | 5 | 4 | 3 | **6.67** |
| 3 | Rich Sidebar Metadata | 2 | 4 | 4 | 3 | **5.33** |
| 4 | Native tmux Control Mode | 3 | 5 | 5 | 5 | 5.00 |
| 5 | Block-Based Output | 3 | 5 | 4 | 4 | 5.00 |
| 6 | Workspace Snapshots | 3 | 3 | 5 | 3 | 5.00 |
| 7 | Inline Preview Panes | 3 | 4 | 5 | 4 | 5.00 |
| 8 | Declarative Project Layouts | 1 | 4 | 2 | 2 | 4.00 |
| 9 | Fuzzy Workspace Switcher | 1 | 4 | 2 | 2 | 4.00 |
| 10 | Floating Panes | 2 | 4 | 3 | 3 | 4.00 |
| 11 | Socket API for Scriptability | 2 | 4 | 3 | 3 | 4.00 |
| 12 | Session Resurrection | 1 | 4 | 2 | 3 | 2.67 |
| 13 | Command Palette | 1 | 3 | 1 | 2 | 1.50 |
| 14 | Cursor Trail | 3 | 3 | 2 | 4 | 1.50 |

---

## Top 3 Recommendations

1. **Which-Key Overlay** (score 10.00): Highest bang-for-buck. Zellij proved that keybinding discoverability is the #1 driver of adoption over tmux. A transient overlay avoids zellij's tradeoff of permanent screen real estate. Two days of work for a feature that defines the app's personality.

2. **Notification Rings** (score 6.67): The agent-workflow killer feature. As AI coding assistants run parallel terminal sessions, knowing which pane has new output without checking each one becomes critical. cmux is the only terminal that does this well, and it's GPL-licensed (can't just copy it).

3. **Rich Sidebar Metadata** (score 5.33): Transforms the sidebar from a tab list into a project dashboard. Git branch, ports, and PR status at a glance. Pairs naturally with notification rings (both enrich the sidebar). Incremental to build since the sidebar already exists.

These three share a theme: **contextual awareness without mode-switching**. The user never leaves their terminal flow to check what's happening, what keys are available, or which project they're in.

---

## Implementation Sequence

If building in order of dependency and value:

1. Which-Key Overlay (no dependencies, immediate UX win)
2. Notification Rings (needs OSC parsing, enables the sidebar enrichment story)
3. Rich Sidebar Metadata (builds on notification infrastructure)
4. Session Resurrection (table stakes, but Phase 2 decomposition should land first)
5. Declarative Project Layouts (builds on session resurrection's serialization)
6. Fuzzy Workspace Switcher (enhances existing Cmd+J session manager)

## Sources

- /tmp/ai-research-terminal-ux-patterns.md
- /tmp/ai-research-swiftui-ui-primitives.md
- /tmp/ai-research-cmux-patterns.md
- /tmp/ai-research-terminal-feature-requests.md
- /tmp/ai-plan-mistty-improvements.md
- Existing research notes on tmux, shpool/zmx, zellij, cmux from ~/Documents/research/terminal/
