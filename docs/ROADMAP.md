# Mistty Roadmap

Created: 2026-04-14
Iteration: 3 (final)

## Principles

1. **Incremental delivery**: each item ships complete and standalone. No half-built infrastructure.
2. **Personal-first, generalizable**: solve your own workflow pain, design interfaces that generalize.
3. **Contextual awareness**: Mistty's identity is "you never leave your flow to check what's happening."
4. **Infrastructure ships with features**: build plumbing when a feature needs it, not before.
5. **Dependency-ordered**: phases are sequenced by what unblocks what. No fake timelines.

---

## Phase 0: Quality gate (HARD BLOCKER for all feature work)

**Why first:** clean foundation prevents compounding tech debt. No feature work until this is green.

- [ ] Fix pre-existing test failure (`test_fullFlow_typeFilterSelectConfirm`)
- [ ] `swift format` on all modified files
- [ ] Reviewer pass on Phase 2 extractions:
  - `nonisolated(unsafe)` warnings on monitor tokens
  - Consistency of activate/deactivate pattern across 3 managers
  - Cross-mode callback pattern (onNeedExitCopyMode / onNeedExitWindowMode)
- [ ] Refactor pass: address reviewer findings
- [x] Delete stale `Xcode.app/` from project directory (done 2026-04-14)

**Done when:** all tests pass (0 failures), zero compiler warnings, reviewer sign-off on refactor.

---

## Phase 1: Identity

**Why this phase:** these features together answer "why Mistty instead of Ghostty + tmux?" Each is standalone with no cross-dependencies. Build in any order based on energy and mood.

### 1a. Which-Key Overlay
Transient hierarchical keybinding overlay. Configurable leader key opens categorized actions (w=windows, p=panes, s=sessions). Shows shortcuts. Fades after selection or 3s timeout.

- Complexity: 2 | Score: 10.00
- Reuses: NSEvent monitoring, SwiftUI `.overlay()`
- Initially hardcoded keybindings. Reads from config when 2c lands.
- Gap analysis: lack of effort. No terminal combines transient + hierarchical.

### 1b. Notification Rings + OSC Foundation
Per-pane output badges (colored ring), sidebar session badges (dot), Cmd+Shift+U jump-to-unread. Attention coordinator debounces flash spam.

Builds OSC parsing as part of the feature: OSC 9/99/777 (notifications), OSC 7 (working directory), OSC 133 (command boundaries). The parser is the foundation for 2a, 3b, and 5b.

- Complexity: 3 | Score: 6.67
- Gap analysis: lack of effort. cmux built it. No one else bothered.

### 1c. Auto-hide Panels
Sidebar and tab bar support Pinned / Auto-hide / Hidden modes. Auto-hide: overlay slides in on edge hover (150ms dwell, 20px trigger zone), out on mouse leave (300ms delay). Panels overlay terminal content (no resize/reflow). Keyboard shortcuts always work regardless of mode.

- Complexity: 2 | Delight: 4
- Design: /tmp/ai-design-autohide-panels.md
- Gap analysis: terminals prioritize chrome. Zen Browser proved the pattern.

**Done when:** which-key shows actions and fades, notification badges appear on unfocused panes with output, sidebar/tab bar auto-hide on hover. All existing tests pass.

---

## Phase 2: Session management

**Why this phase:** sessions are Mistty's core value prop over plain Ghostty. These features make sessions worth using.

### 2a. Rich Sidebar Metadata
Git branch + dirty indicator, working directory (from OSC 7), listening ports per session row.

- Complexity: 3 | Score: 5.33
- Depends on: 1b (OSC 7 working directory tracking)

### 2b. Fuzzy Workspace Switcher
Enhance Cmd+J: frecency-ranked directories (zoxide integration), Nerd Font icons, preview pane. Cmd+\` for instant last-workspace toggle (no UI, instant switch).

- Complexity: 2 | Score: 4.00
- Depends on: nothing

### 2c. Configurable Keybindings
TOML config file (`~/.config/mistty/keys.toml`) for all keybindings. Which-key overlay (1a) reads from this config. Power users remap everything.

- Complexity: 2
- Retroactively enhances 1a.

### 2d. Session Resurrection
Auto-save (layout, working directories, scrollback) on quit. Auto-restore on launch. Invisible.

- Complexity: 3
- Why genuinely hard: process state (running commands, env vars, file descriptors) can't be serialized. Layout + scrollback + cwd is the achievable subset.

**Done when:** sidebar shows git branch and ports, Cmd+J shows zoxide results, keybindings are configurable, quit+relaunch restores layout.

---

## Phase 3: Platform

**Why this phase:** these create the foundation for external tool integration and architectural health.

### 3a. @FocusedValue Migration
Replace NotificationCenter menu commands with @FocusedValue. Publish MisttySession (not SessionStore). Fix multi-window menu targeting bug.

- Complexity: 2
- Architectural cleanup. Not user-visible but fixes a real bug.

### 3b. Shell Integration (OSC 133)
Command boundary detection from the OSC parser built in 1b. Enables: Cmd+Up/Down to jump between prompts, per-command exit code and duration display.

- Complexity: 3
- Depends on: 1b (OSC foundation)
- Enables: 5b (block-based output)

### 3c. Socket API + CLI
Unix domain socket (`/tmp/mistty-$UID.sock`). JSON-RPC protocol. `mistty` CLI binary as thin client. Access control via file permissions.

- Complexity: 3
- Enables: 3d, Raycast/Hammerspoon integration, scripting

### 3d. Neovim Split Navigation
smart-splits.nvim integration via socket API. Bidirectional Ctrl+h/j/k/l between neovim splits and Mistty panes.

- Complexity: 2 (once 3c exists)
- Depends on: 3c
- Why unsolved in Ghostty: deliberate design choice (no IPC). Mistty can solve it.
- Personal pain point.

**Done when:** menu commands work correctly in multi-window, Cmd+Up/Down jumps between prompts, `mistty pane list` returns JSON, Ctrl+h/j/k/l crosses neovim/Mistty boundary.

---

## Phase 4: Differentiators

### 4a. Declarative Project Layouts
`.mistty.toml` in project root: pane arrangement, commands, working directories. Directory trust prompt for untrusted projects.

- Complexity: 2
- Depends on: 2d (serialization format)

### 4b. Floating Panes
Persistent overlay panes above the terminal grid. Cmd+F toggles floating layer. Panes keep running when hidden. Drag to reposition.

- Complexity: 3
- 201 votes on Ghostty. Mistty's SwiftUI architecture makes this easier than Ghostty's renderer-level splits.

### 4c. Ghostty Config Compatibility
Read `~/.config/ghostty/config` for themes, fonts, colors. Zero-friction migration.

- Complexity: 2

### 4d. Command Palette (Cmd+K)
Fuzzy-searchable floating panel. All actions with shortcuts. Lower priority because which-key (1a) covers discoverability.

- Complexity: 2

---

## Phase 5: Moonshots

### 5a. Native tmux Control Mode
Render tmux panes as native Mistty splits via `tmux -CC`. The headline feature. Only iTerm2 has this.

- Complexity: 5
- Why genuinely hard: protocol is complex, poorly documented. Bidirectional sync edge cases (resize reflow, pane reordering, Unicode). iTerm2 invested years.
- Defensible moat: hard to copy.

### 5b. Block-Based Output
Command+output as selectable blocks. Metadata: exit code, duration, cwd. Click to select entire block. Cmd+Up/Down to navigate.

- Complexity: 4
- Depends on: 3b (shell integration)
- Only Warp has this.

### 5c. Inline Preview Panes
Hover file paths in terminal output for Quick Look preview. Click to open in split pane.

- Complexity: 4
- No terminal does this. Novel.

### 5d. Workspace Snapshots
Named save points with timeline. "Bookmark this moment" before risky operations. Browse and restore from timeline view.

- Complexity: 3
- Novel concept. No prior art.

### 5e. SSH Workspace Creation
`mistty ssh user@host` creates a dedicated workspace with port detection, sidebar metadata, and proper cleanup on disconnect.

- Complexity: 4
- Prior art: cmux (Go daemon bootstrap over SSH)

---

## Dependency graph

```
Phase 0 (cleanup) ──────────────────────────────────────────────────────────>

Phase 1 (all parallel, no cross-deps):
  1a (which-key) ·····················> 2c (config keys) enhances it
  1b (notifications + OSC) ──> 2a (rich sidebar)
                           └──> 3b (shell integration) ──> 5b (blocks)
  1c (auto-hide) ·····················> standalone

Phase 2:
  2b (fuzzy switcher) ················> standalone
  2d (session resurrection) ──> 4a (project layouts)

Phase 3:
  3c (socket API) ──> 3d (neovim nav)
```

## What's NOT on this roadmap

- CI/CD (GitHub Actions): deferred until contributors exist
- IPC service refactoring: works, not broken
- C callback notification replacement: works, low priority
- Cursor trail: Metal shader work in Ghostty fork, high complexity for cosmetic value
- AI integration: interesting but premature. Revisit when the terminal is solid.

## Sources

- /tmp/ai-brainstorm-mistty-ux.md (14 ideas scored)
- /tmp/ai-debate-mistty-features.md (debate transcript)
- /tmp/ai-design-autohide-panels.md (auto-hide panel design, 3 iterations)
- /tmp/ai-plan-mistty-improvements.md (v5, original improvement plan)
- /tmp/ai-review-mistty-plan.md (plan review findings)
- /tmp/ai-research-terminal-ux-patterns.md
- /tmp/ai-research-swiftui-ui-primitives.md
- /tmp/ai-research-cmux-patterns.md
- /tmp/ai-research-terminal-feature-requests.md
- ~/Documents/research/terminal/terminal-session-management-research.md
