# Terminal UX Patterns for Mistty

Research for Mistty (macOS terminal emulator, libghostty + SwiftUI).
Builds on existing research: cmux patterns, tmux best parts, shpool/zmx, zellij basics.

---

## 1. tmux's Best UX Moments

### (a) The Prefix Key Model

The prefix key (default Ctrl-b, commonly remapped to Ctrl-a) creates a dedicated namespace for multiplexer commands that never collides with application keybindings. Users press the prefix, then a single key to act. This two-step model works because:

- It avoids stealing any modifier+key combos from the shell, editor, or TUI apps running inside.
- It creates a clear mental boundary: "I'm now talking to the multiplexer, not the app."
- The timeout (default 500ms) means accidental prefix presses are harmless.
- Power users chain it with repeat mode (e.g., `bind -r` for resize) so repeated actions don't need re-pressing the prefix.

The downside: discoverability is zero. New users must memorize bindings or consult a cheat sheet. tmux-which-key and zellij's status bar both exist to solve this gap.

**Native macOS equivalent**: A leader key model where Cmd+\ (or a configurable key) opens a transient command mode. The app could show a brief overlay of available actions (like which-key) that fades after the next keypress. This preserves the "namespace isolation" benefit while adding visual discoverability that tmux lacks.

### (b) Sesh's Fuzzy Session Switching

Sesh (2.3k stars, v2.25.0 as of 2026-04-13) combines zoxide's frecency-ranked directory history with tmux session management. The core UX flow:

1. Press a keybinding (e.g., prefix+T) to open a fuzzy finder popup.
2. The list shows: active tmux sessions, configured sessions from `sesh.toml`, and zoxide directory results, all mixed together with Nerd Font icons distinguishing types.
3. Ctrl-a/t/g/x cycle between "all", "tmux only", "configs only", "zoxide only" views.
4. Selecting a directory auto-creates a named session there. Selecting an active session switches to it.
5. A preview pane (right side, 55% width) shows `sesh preview {}` output for the highlighted item.
6. Ctrl-d kills the highlighted session inline without leaving the picker.
7. `sesh last` (bound to prefix+L) toggles between the two most recent sessions instantly.

Key design decisions:
- Smart naming: sessions are named from git remote, git repo name, or directory basename.
- Wildcard configs: `[[wildcard]] pattern = "~/projects/*"` applies startup commands to any matching directory without per-project config.
- `sesh.toml` with JSON Schema for editor autocomplete.
- Raycast extension for switching sessions from outside the terminal.

**Native macOS equivalent**: A Cmd+K command palette that combines workspace switching with project creation. The list would show: running workspaces (with git branch, port info from sidebar metadata), recent projects (from a frecency store like zoxide), and configured project templates. Selecting a project that isn't running creates a new workspace with the configured layout. The "last workspace" toggle (Cmd+`) would be instant, no UI needed.

### (c) tmux-which-key's Discoverable Menus

tmux-which-key (260 stars) shows a popup menu after pressing a trigger key (default: Ctrl+Space or prefix+Space). The menu displays categorized actions with their keybindings:

- Hierarchical: top-level shows categories (Windows, Panes, Client, etc.), drilling into submenus.
- Mnemonic keys: `w` for Windows, `p` for Panes, `C` for Client.
- Transient states: some menus stay open for repeated commands (e.g., cycling layouts with `l` repeatedly).
- User macros: multi-command sequences triggered by a single menu entry.
- YAML configuration with schema validation.

The UX insight: the menu teaches keybindings while providing a fallback for forgotten ones. Users gradually memorize shortcuts and stop opening the menu, but it's always there as a safety net.

**Native macOS equivalent**: A Cmd+Space (or configurable) overlay that shows a categorized action menu. Unlike a flat command palette, this would be hierarchical: press `w` to see window actions, `p` for pane actions. Each entry shows the direct keyboard shortcut so users learn over time. The menu would be configurable via a YAML/TOML file in the app's config directory.

### (d) Tmuxinator/Tmuxp Declarative Layouts

Tmuxinator (Ruby, YAML) and tmuxp (Python, YAML/JSON) let users define project workspaces declaratively:

```yaml
# tmuxinator example
name: myproject
root: ~/projects/myproject
windows:
  - editor:
      layout: main-vertical
      panes:
        - nvim
        - ""
  - server: npm run dev
  - logs: tail -f log/development.log
```

One command (`tmuxinator start myproject`) creates the entire workspace. The UX value:
- Reproducible environments: same layout every time.
- Shareable: commit the YAML to the repo for team onboarding.
- Composable: different projects get different layouts.

Sesh's `sesh.toml` with `[[session]]` and `[[wildcard]]` entries is the modern evolution, adding startup commands, preview commands, and window definitions without a separate tool.

**Native macOS equivalent**: A `.mistty.toml` or `.mistty/layout.kdl` file in the project root (like cmux's `cmux.json`). Opening a project directory auto-detects this file and offers to apply the layout. The Layout Manager UI (like zellij's) would let users save the current workspace arrangement as a layout file, avoiding manual YAML editing.

### (e) Resurrect + Continuum for Session Persistence

tmux-resurrect (12.6k stars) saves and restores the complete tmux environment:
- All sessions, windows, panes, and their order
- Working directories per pane
- Exact pane layouts (even when zoomed)
- Running programs (configurable list)
- Optional: vim/neovim sessions, pane contents (scrollback)

Key bindings: prefix+Ctrl-s to save, prefix+Ctrl-r to restore. tmux-continuum adds automatic saving (every 15 minutes) and auto-restore on tmux start.

The UX insight: "You should feel like you never quit tmux." The restore is idempotent (won't duplicate existing panes). The save captures enough state that a reboot feels like closing and reopening a laptop lid.

**Native macOS equivalent**: This should be automatic and invisible. A native macOS app can hook into NSApplicationDelegate's state restoration. On quit, persist: workspace layouts, pane working directories, scrollback (with configurable limits), running command metadata. On launch, restore everything silently. No manual save/restore keybindings needed. cmux already does this with `SessionPersistence.swift`.

---

## 2. cmux's UX Innovations

(Building on existing research in /tmp/ai-research-cmux-patterns.md)

### (a) Vertical Sidebar with Rich Metadata

Each workspace in the sidebar shows:
- Workspace name (editable)
- Git branch with dirty indicator
- Linked PR status and number
- Working directory
- Listening ports (detected via port scanning)
- Latest notification text
- Custom status entries (key/value/icon/color/priority)

This density of contextual information per workspace is unique among terminal apps. Traditional tab bars show only a name. cmux's sidebar turns each workspace into a project dashboard.

### (b) Notification Rings and Attention Management

- Blue ring on panes that have new output
- Tab/workspace highlight in sidebar
- Cmd+Shift+U jumps to the most recent unread notification
- `WorkspaceAttentionCoordinator` prevents flash spam by checking persistent state before allowing animations
- Notifications via OSC 9/99/777 escape sequences plus `cmux notify` CLI command

This is the killer feature for parallel agent workflows where multiple terminals produce output simultaneously.

### (c) Command Palette

cmux has a command palette for launching custom commands defined in `cmux.json` project files. The `CmuxDirectoryTrust.swift` adds a trust model so arbitrary project configs don't auto-execute (similar to VS Code's workspace trust).

### (d) In-App Browser

Browser panes that route through the remote network (for SSH sessions) so `localhost` URLs work. The browser has a scriptable API (accessibility tree snapshots, element refs, click, fill, evaluate JS). Unique among terminal apps.

### (e) SSH Workspace Creation

`cmux ssh user@remote` creates a dedicated workspace with:
- Automatic Go daemon bootstrap on the remote host
- SOCKS5/HTTP CONNECT proxy tunneling through SSH
- Port detection and display in sidebar
- CLI relay back to local app
- Proper cleanup on disconnect

---

## 3. Zellij's UX Innovations

### (a) Status Bar with Mode Indicators and Keybinding Hints

Zellij's status bar is its defining UX feature. It shows:
- Current mode (Normal, Pane, Tab, Resize, Move, Search, Session, etc.)
- Available keybindings for the current mode, updated in real time
- Session name
- Tab bar with tab names

The status bar solves tmux's biggest UX problem: discoverability. New users can see what keys do what without consulting documentation. The mode-based approach (inspired by vim) means different keys do different things in different modes, but the status bar always tells you what's available.

Confirmed by multiple sources: the status bar is the #1 reason users cite for choosing zellij over tmux. The dasroot.net comparison (2026-02) and zellij.dev tutorials both emphasize this as the primary differentiator.

### (b) Floating Panes

Floating panes in zellij are persistent, toggleable overlays:
- `Alt f` toggles the floating pane layer on/off
- Floating panes persist when hidden (commands keep running)
- Can be moved with mouse drag or keyboard (Move mode, Ctrl+h)
- Can be "pinned" (always-on-top) with Ctrl+p then `i`
- Multiple floating panes can coexist, with focus switching via Alt+arrows

Real-world uses (from tutorials and community):
- Quick terminal for one-off commands without disrupting layout
- File picker (zellij has a built-in filepicker plugin)
- Monitoring dashboards that overlay the main workspace
- Scratch pads for notes or calculations

**Native macOS equivalent**: SwiftUI overlay views that float above the terminal grid. Cmd+F to toggle floating pane layer. Floating panes could have native macOS window chrome (title bar, close/minimize) or a minimal frame. The "pinned" concept maps to macOS's "float on top" window behavior.

### (c) Session Manager TUI

The `session-manager` (Ctrl+o then `w`) and `welcome-screen` provide:
- List of running sessions (attach to switch)
- List of exited sessions (resurrect to revive)
- New session creation with optional folder picker (Ctrl+f opens filepicker)
- Layout selection for new sessions
- Session renaming (Ctrl+r)
- Fuzzy search/filter across all sessions

The welcome screen can be configured as the terminal's startup program, making zellij the session orchestrator. The resurrection feature preserves layout and command metadata from exited sessions.

### (d) KDL Layout Files

Zellij uses KDL (a document-oriented config language) for layouts:

```kdl
layout {
    pane split_direction="vertical" {
        pane edit="src/main.rs"
        pane split_direction="horizontal" {
            pane command="cargo" { args "check"; start_suspended true }
            pane command="cargo" { args "run"; start_suspended true }
            pane command="cargo" { args "test"; start_suspended true }
        }
    }
    pane size=1 borderless=true {
        plugin location="zellij:compact-bar"
    }
}
```

Key features:
- `edit` panes open `$EDITOR` to a specific file
- `command` panes are first-class: show exit code, re-run with Enter
- `start_suspended true` means commands wait for user to press Enter
- `pane_template` for DRY definitions
- Layout Manager UI (Ctrl+o then `l`) to save/load/override layouts without editing files

The `start_suspended` pattern is particularly clever: it sets up the workspace with all the commands ready to go, but doesn't waste resources running them until needed.

### (e) Plugin System (zjstatus, room, monocle)

Zellij plugins are WASM modules that run in sandboxed environments:

- **zjstatus**: Highly customizable status bar replacement with widgets (clock, mode indicator, tab names, custom formatting). Lets users create tmux-powerline-style status bars.
- **room**: Fuzzy tab switcher (like Ctrl+P for tabs). Type to filter, Enter to switch.
- **monocle**: Fuzzy finder for file names and contents. Opens results in `$EDITOR` scrolled to the correct line, or opens a terminal at the file's location.
- **harpoon**: Quick-navigate to bookmarked panes (inspired by ThePrimeagen's harpoon for neovim).
- **multitask**: Mini-CI that runs commands in parallel with progress tracking.
- **zellij-forgot**: Searchable cheat sheet for custom keybindings and notes.

### Why Zellij's Discoverability is Better Than tmux

1. **Zero-config discoverability**: The status bar shows keybindings from first launch. tmux requires installing tmux-which-key or memorizing bindings.
2. **Mode indicators**: Users always know what mode they're in and what keys are available. tmux has no mode concept (just prefix + key).
3. **Progressive disclosure**: The compact bar shows essentials; the full bar shows everything. Users choose their level of chrome.
4. **Contextual hints**: The right side of the status bar shows context-dependent actions (e.g., "New Pane" when in normal mode, resize handles when in resize mode).

The tradeoff: zellij's status bar takes screen real estate (1-2 lines). Power users who've memorized bindings may prefer tmux's zero-chrome approach.

---

## 4. WezTerm's Workspace Model

WezTerm (GPU-accelerated terminal in Rust, Lua config) has a built-in multiplexer with workspaces:

### Workspace Concept
- Each workspace is a named collection of windows/tabs/panes
- Workspaces are isolated: switching workspaces shows only that workspace's windows
- Similar to tmux sessions but native to the terminal emulator

### Workspace Switching UX
- `smart_workspace_switcher.wezterm` plugin (192 stars): fuzzy finder powered by zoxide, inspired by sesh
  - One keypress (Leader+s) opens fuzzy finder
  - Shows: existing workspaces + zoxide directory results
  - Selecting a directory creates a new workspace named after it
  - Events system for custom behavior (update status bar, run commands on switch)
  - `switch_to_prev_workspace()` for quick toggle between last two workspaces
- WezTerm's `InputSelector` action provides a native fuzzy finder UI
- Lua scripting enables project-specific workspace setup (split panes, run commands)

### Project Selector Pattern (from blog.annimon.com)
A Lua-based project selector that:
1. Defines projects as functions that create specific pane layouts
2. Opens via Leader+p with a fuzzy finder
3. Each project can have custom splits, commands, and working directories
4. Supports Nerd Font icons and colored labels in the picker
5. Frequently-used projects can get dedicated keybindings (Leader+b for blog)

### Comparison to tmux Sessions
- Advantage: no separate process. Workspaces are native to the terminal, so there's no tmux server to manage, no prefix key needed, and the terminal's native rendering is used directly.
- Advantage: Lua scripting is more expressive than tmux.conf for complex workspace setup.
- Disadvantage: no remote persistence. If the terminal closes, workspaces are gone (unless using WezTerm's multiplexer server mode).
- Disadvantage: smaller ecosystem. tmux has decades of plugins; WezTerm's plugin system is newer.

---

## 5. Modern Terminal UX Patterns That Delight Users

### Warp: Block-Based Output

Warp's most significant innovation is treating each command+output as a discrete "block":
- Each block is selectable, copyable, shareable as a unit
- One-click copy of entire command output
- Jump between blocks (navigate by command, not by line)
- Blocks carry metadata: timestamp, exit code, duration, working directory
- AI can use a block as a focused context window

The bottom-anchored input area (fixed position, like a chat app) eliminates the cognitive load of finding the prompt. Users always know where to type.

Warp's AI integration follows three modes:
1. **Natural language input**: Type a description, get the actual command shown for review before execution
2. **Contextual suggestions**: After errors, suggest fixes (opt-in, dismissible with one key)
3. **Explain mode**: Click "Explain" on any command to see what each flag does

Key principle: AI is transparent (shows generated commands) and educational (explain mode teaches rather than creates dependency).

### Warp: Command Palette

Cmd+P opens a fuzzy-searchable palette showing:
- Recent commands
- All available actions with their keyboard shortcuts
- Saved workflows (shareable command sequences)
- Settings

The palette teaches shortcuts: every entry shows its keybinding, so users learn over time.

### Warp: Workflows (Shareable Command Sequences)

YAML-defined step-by-step command sequences:
- Each step has a command and description
- Execute step-by-step with Run/Skip/Cancel
- Shareable via "Warp Drive" (team feature)
- Discoverable through the command palette

This bridges the gap between one-off commands and full scripts.

### Fig/Amazon Q Developer CLI: IDE-Style Autocomplete

Fig (now Amazon Q Developer CLI) brought IDE-style autocomplete to the terminal:
- Dropdown menu appears as you type, showing subcommands, flags, and arguments
- Works with hundreds of CLI tools (git, npm, docker, aws, etc.)
- Completion specs are community-contributed (open source)
- Inline suggestions (ghost text) for command completion
- Theming support

The autocomplete dropdown is the single most-requested feature in terminal UX surveys. It turns the terminal from a memorization exercise into a guided experience.

Amazon Q extends this with:
- Natural language to command translation
- Context-aware suggestions based on current directory and shell history
- `@workspace` context for project-aware assistance

### Tabby: Cross-Platform with Plugin Ecosystem

Tabby (formerly Terminus) offers:
- Serial port and SSH connection manager with saved profiles
- Split panes with drag-and-drop
- Plugin system (TypeScript) for extending functionality
- Theming and appearance customization
- Built-in SFTP integration

### Common Patterns Across Modern Terminals

1. **Command palette** (Cmd+P/Ctrl+Shift+P): Universal in Warp, VS Code terminal, cmux. The standard for feature discoverability.
2. **Fuzzy finding everywhere**: Sessions, files, commands, tabs. fzf-style filtering is expected.
3. **Rich status information**: Git branch, working directory, running processes. Not just a title bar.
4. **Declarative project layouts**: YAML/TOML/KDL files that reproduce a workspace with one command.
5. **Session persistence across restarts**: Expected to be automatic, not manual.
6. **AI assistance**: Natural language to commands, error explanations, contextual suggestions. Opt-in and transparent.
7. **Notification/attention management**: Visual indicators for panes with new output, jump-to-unread.

---

## 6. Synthesis: What Mistty Should Prioritize

### Tier 1: Table Stakes (users expect these)
- Session persistence across app restarts (automatic, invisible)
- Command palette (Cmd+K) for feature discoverability
- Fuzzy workspace/project switching (sesh-style, with frecency)
- Declarative project layouts (`.mistty.toml` in project root)

### Tier 2: Differentiators (what makes users switch)
- Notification rings with jump-to-unread (cmux's killer feature for agent workflows)
- Rich sidebar metadata per workspace (git branch, ports, PR status)
- Discoverable keybinding hints (zellij's status bar approach, but as an optional overlay)
- Floating panes (zellij-style, persistent and toggleable)

### Tier 3: Delight (what makes users evangelists)
- Block-based output (Warp's model, treating command+output as selectable units)
- "Last workspace" instant toggle (sesh's prefix+L, mapped to Cmd+`)
- Layout Manager UI (save current arrangement as a layout file without editing config)
- IDE-style autocomplete integration (Fig/Amazon Q style, or at least hooks for it)

### The Single Most Important UX Decision
The which-key/status-bar discoverability pattern. Zellij proved that showing available keybindings in context is the #1 driver of user adoption over tmux. A native macOS app can do this better: a transient overlay (like Karabiner-Elements' key viewer) that appears after pressing a leader key, shows categorized actions with their shortcuts, and fades after selection. This combines tmux-which-key's hierarchical menus with zellij's always-visible hints, without permanently consuming screen real estate.

---

## Sources

- [2026-04-14] https://github.com/joshmedeski/sesh (README, v2.25.0, session manager UX, sesh.toml config)
- [2026-04-14] https://github.com/alexwforsythe/tmux-which-key (README, popup menu UX, YAML config)
- [2026-04-14] https://github.com/tmux-plugins/tmux-resurrect (README, session persistence UX)
- [2026-04-14] https://zellij.dev/tutorials/basic-functionality/ (status bar, floating panes, multiple select)
- [2026-04-14] https://zellij.dev/tutorials/layouts/ (KDL layouts, command panes, pane templates, Layout Manager)
- [2026-04-14] https://zellij.dev/tutorials/session-management/ (session manager, welcome screen, resurrection)
- [2026-04-14] https://zellij.dev/documentation/plugin-examples (zjstatus, room, monocle, harpoon, multitask)
- [2026-04-14] https://dasroot.net/posts/2026/02/terminal-multiplexers-tmux-vs-zellij-comparison/ (feature comparison, UX differences)
- [2026-04-14] https://blog.annimon.com/wezterm-projects/ (WezTerm project selector, Lua workspace setup)
- [2026-04-14] https://github.com/MLFlexer/smart_workspace_switcher.wezterm (WezTerm workspace switcher, zoxide integration)
- [2026-04-14] https://blakecrosley.com/guides/design/warp (Warp block model, bottom-anchored input, AI integration, command palette, workflows)
- [2026-04-14] https://github.com/manaflow-ai/cmux (sidebar metadata, notification rings, command palette, SSH workspaces)
- [2026-04-14] /tmp/ai-research-cmux-patterns.md (prior cmux architecture research)
- [2026-04-14] https://joshmedeski.com/posts/smart-tmux-sessions-with-sesh/ (sesh UX philosophy)
- [2026-04-14] https://www.joshmedeski.com/posts/i-made-my-favorite-tmux-feature-better-with-sesh/ (last-session switching)
- [2026-04-14] https://hodalog.com/en/terminal-multiplexer-adoption/ (workspace-per-product pattern, WezTerm adoption)
- [2026-04-14] https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-autocomplete.html (Amazon Q CLI autocomplete)
