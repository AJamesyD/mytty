# Terminal Emulator Feature Requests: Ghostty, WezTerm, Kitty

Research date: 2026-04-14

---

## Ghostty (50.7k stars)

### Top Open Feature Requests (issues, sorted by reactions)

1. **tmux Control Mode support** (#1935) - Native integration with tmux panes via control mode protocol
2. **Toggle background opacity keybind** (#5047) - Quick transparency toggle
3. **Scrollback history in state restoration** (#1847, macOS) - Persist scrollback across restarts
4. **RTL text support** (#1442) - Minimal right-to-left rendering for single lines
5. **`write_scrollback_file:open` to use `$EDITOR`** (#2504) - Open scrollback in user's editor
6. **OSC 99 desktop notifications** (#5634) - Targeted for 1.4.0 milestone
7. **Swap to last active tab** (#1844) - Keybind to toggle between recent tabs
8. **Move tab to new window** (#2630) - Detach tab into its own window
9. **GTK split drag-and-drop reorder** (#10224) - Rearrange splits via mouse on Linux

### Top Discussions (sorted by votes)

1. **Cursor trail/animation** (347 votes, discussion #4199) - Kitty/Neovide-style cursor trail. Closed/answered; not yet shipped natively.
2. **Windows support** (279 votes, discussion #2563) - Highly requested, in progress for 1.2+
3. **Scripting API** (240 votes, discussion #2353) - Labeled "feature-design" and "feedback-requested." Users want Lua/Wasm/custom scripting to automate Ghostty. Mitchell has acknowledged this as a long-term goal.
4. **Float pane / popup support** (201 votes, discussion #3197) - Floating overlay panes (like tmux popups or Zellij floating panes)
5. **Copy mode** (174 votes, discussion #3488) - tmux-style copy mode for keyboard-driven text selection in scrollback. Labeled "feature-design."
6. **Smooth scrolling** (112 votes, discussion #2355) - Pixel-level scrolling. Labeled "feature-design."
7. **Hints mode** (99 votes, discussion #2394) - Quick-select URLs, paths, hashes via keyboard hints (like Kitty's hints kitten). Closed/answered.
8. **Scroll by less than a full cell** (91 votes, discussion #3206) - Sub-cell pixel scrolling
9. **Opening URLs via keyboard** (80 votes, discussion #9568) - Keyboard-driven URL opening. Labeled "feature-design."
10. **Selecting text a la Warp** (72 votes, discussion #6916) - Click-to-position cursor in prompt
11. **Define split layouts** (68 votes, discussion #2480) - Predefined split configurations
12. **Command finished notifications** (65 votes, discussion #3555) - Alert when long commands complete. Shipped in 1.3.
13. **SSH integration** (62 votes, discussion #3087) - Automatic terminfo, shell integration over SSH
14. **Session manager** (discussion #3358) - Save/restore terminal sessions
15. **Send input to multiple panes** (discussion #3227) - Broadcast input to all splits

### Recently Shipped Features That Generated Excitement

- **Ghostty 1.3** (2026-03-09): Scrollback search, native scrollbars, command completion notifications, AppleScript automation (macOS), key tables for modal keybindings, chained keybindings, rich clipboard copy (HTML), click-to-move-cursor in prompts, drag-and-drop split rearrangement (macOS)
- **Ghostty 1.2** (2025-09-15): Windows support, FreeBSD support, 2600+ commits
- **libghostty announcement** (2025-09-22): Embeddable terminal library. `libghostty-vt` for parsing terminal sequences. Zig API available, C API in progress. Long-term plan includes GPU rendering, GTK widgets, Swift frameworks.

---

## WezTerm (25.5k stars)

### Top Open Feature Requests (issues, sorted by reactions)

1. **Dropdown/Quake/Visor terminal** (#1751) - Global hotkey to toggle a dropdown terminal. Top-voted issue overall.
2. **Drag to reorder tabs and panes** (#549) - Mouse-based tab/pane reordering
3. **tmux control mode** (#336) - Native tmux integration, filed by wez himself
4. **Cursor trail effect** (#6492, #7387) - Two separate issues requesting Kitty-style cursor trails
5. **Switch pane layouts** (#3516) - Cycle between layout modes (like tmux layouts)
6. **OSC 52 clipboard querying** (#2050) - Opt-in clipboard read support
7. **Popup window support** (#270) - Floating popup panes
8. **Lua type annotations** (#3132) - Better IDE support for WezTerm's Lua config
9. **Save current layout** (#3237) - Persist window/tab/pane arrangement
10. **Smooth scrolling** (#3812) - Pixel-level smooth scroll

### Notable Bugs/Issues

- **100% CPU on macOS 15.4 launch** (#6833, 47 reactions) - Major stability issue
- **Textures broken on NixOS** (#5990) - Rendering regression

### Community Workarounds for Missing Features

- **resurrect.wezterm** plugin: Community-built session save/restore. Active development, but users report issues (#111 on the plugin repo).
- **wezterm-sessions** plugin: Another community session manager
- Blog posts describe complex Lua configs to approximate Zellij-style layouts and workspace switching

### WezTerm Development Status

WezTerm has 1.4k open issues and 233 open PRs. The maintainer (wez) has a "Next Release Checklist" (#6341) pinned. Development pace has been a concern in the community, with the large backlog of issues.

---

## Kitty (32.4k stars)

### Top Open Feature Requests (issues, sorted by reactions)

1. **macOS session restore** (#1197) - Kitty doesn't restore windows/tabs after restart on macOS. Open since 2018, labeled "enhancement" and "help wanted."
2. **Bidirectional text support** (#2109) - RTL/BiDi rendering. Open since 2019, labeled "help wanted."
3. **Tab bar on the side** (#2305) - Vertical tab bar. Open since 2020.
4. **Docked windows in layouts** (#2391) - Pin windows to edges across layout modes
5. **Unicode text processing RFC** (#8533) - Kovid's own RFC for standardizing Unicode handling in terminals
6. **Custom XKB keymap issues** (#1990) - Long-standing input handling issue
7. **Cursor trail on command prompt only** (#8147) - Limit cursor trail to prompt area

### Top Discussions (sorted by votes)

1. **Share your tab bar style** (42 votes, 159 comments) - Community showcase
2. **xterm-kitty TERM discussion** (29 votes) - Ongoing pain point with SSH and remote compatibility
3. **Vi mode for kitty** (26 votes) - Community kitten for vi-style navigation
4. **Mouse resize for splits** (11 votes, discussion) - Shipped in 0.46
5. **tmux persistent session capability** (8 votes) - Users asking how to replace tmux sessions
6. **Save current layout to file** (Q&A) - Recurring request
7. **Kittens for session management** (Q&A) - Users want programmatic session control

### Recently Shipped Features That Generated Excitement

- **Kitty 0.46** (2026-03-11): Smooth pixel scrolling, momentum scrolling on Linux, draggable tabs, mouse-based split resizing, command palette, window title bars, OKLCH/LAB color support, Wayland background blur
- **Kitty 0.45** (2025-12-24): Keyboard-first file selector kitten
- **Kitty 0.43** (2025-09-28): Native session management, multiple cursor protocol, configurable scrollbar, cursor trail color customization, blinking text, custom Python functions for tab titles, semi-transparent title bars on macOS

---

## Cross-Cutting Themes: Unmet Needs Across All Three Terminals

### 1. Session/Layout Persistence and Restoration (confirmed across 3 sources)

All three terminals have highly-upvoted requests for saving and restoring terminal state:
- **Ghostty**: Scrollback in state restoration (#1847), session manager (discussion #3358), define split layouts (discussion #2480)
- **WezTerm**: Save current layout (#3237), save and load layouts (#1949). Community built resurrect.wezterm as a workaround.
- **Kitty**: macOS restore (#1197, top-voted open issue, open since 2018). Session management was partially addressed in 0.43 but the macOS restore issue remains open. "Save current layout to file" is a recurring Q&A topic.

None of these terminals offer a complete, built-in solution for saving the full terminal state (layout, scrollback, working directories, running processes) and restoring it after restart. Kitty 0.43 added session management, but the macOS restore issue from 2018 is still open. WezTerm relies entirely on community plugins. Ghostty has no session persistence yet.

### 2. Scripting/Automation API and Extensibility (confirmed across 3 sources)

Users across all three terminals want programmable control:
- **Ghostty**: Scripting API (240 votes, #2 most-voted discussion). AppleScript support shipped in 1.3 as a preview. libghostty announced for embeddable use. But no general scripting API yet.
- **WezTerm**: Already has Lua configuration, but users want Lua type annotations (#3132) for better IDE support, and the plugin ecosystem (resurrect.wezterm, wezterm-sessions) shows demand for more extensibility.
- **Kitty**: Has kittens (Python-based extensions) and remote control protocol, but users want more: vi mode kitten (community-built), session management kittens, custom tab title functions (shipped in 0.43).

The gap: no terminal offers a stable, well-documented plugin/extension API with a package ecosystem. WezTerm's Lua config is the closest, but lacks type safety and a plugin registry. Ghostty's scripting API is the most-requested feature after Windows support.

### 3. tmux Control Mode / Native Multiplexer Integration (confirmed across 2 sources)

Both Ghostty and WezTerm have tmux control mode as a top-voted feature request:
- **Ghostty**: #1935 (top-voted open issue) - tmux control mode support
- **WezTerm**: #336 (filed by the maintainer himself) - tmux control mode support
- **Kitty**: Discussion about "how does kitty fully replace tmux" (10 votes). Kitty's approach is to provide its own multiplexing rather than integrate with tmux.

Users want their terminal to natively render tmux panes as native tabs/splits, eliminating the double-nesting of terminal-in-terminal. iTerm2 on macOS is the only major terminal that has shipped this, and it's a key reason some users stay on iTerm2.

### 4. Smooth Scrolling (confirmed across 3 sources)

Requested across all three:
- **Ghostty**: 112 votes (discussion #2355), 91 votes for sub-cell scrolling (#3206). Labeled "feature-design." Not yet shipped.
- **WezTerm**: #3812 - Smooth scrolling request
- **Kitty**: Shipped in 0.46 (2026-03-11). Pixel-based scrolling with momentum on Linux.

Kitty is the first of the three to ship this. Ghostty has it in design phase. WezTerm's request remains open.

### 5. Cursor Trail / Visual Animations (confirmed across 3 sources)

A surprisingly popular cosmetic request:
- **Ghostty**: 347 votes (top-voted discussion overall). Not yet shipped natively.
- **WezTerm**: Two separate issues (#6492, #7387). Described as "the last thing keeping many users on Kitty."
- **Kitty**: Shipped cursor_trail in 2024. Added cursor_trail_color customization in 0.43. Community excitement was high.

Kitty pioneered this feature and it became a differentiator. Both Ghostty and WezTerm users are actively requesting it.

### 6. Floating/Popup Panes (confirmed across 2 sources)

- **Ghostty**: 201 votes (discussion #3197) - Float pane / popup support
- **WezTerm**: #270 - Popup window support (filed 2020)
- **Kitty**: Not a prominent request (Kitty's layout system is different)

Confidence: moderate. Confirmed in Ghostty and WezTerm but not a top Kitty request.

### 7. Bidirectional (RTL) Text Support (confirmed across 2 sources)

- **Ghostty**: #1442 - Minimal RTL support
- **Kitty**: #2109 - BiDi text support (open since 2019, "help wanted")
- **WezTerm**: Not found in top issues

Confidence: moderate. Long-standing request in Ghostty and Kitty.

---

## Recently Added Features That Generated Excitement

| Feature | Terminal | Version | Date |
|---|---|---|---|
| Session management | Kitty | 0.43 | 2025-09-28 |
| Smooth pixel scrolling | Kitty | 0.46 | 2026-03-11 |
| Tab dragging | Kitty | 0.46 | 2026-03-11 |
| Mouse split resizing | Kitty | 0.46 | 2026-03-11 |
| Command palette | Kitty | 0.46 | 2026-03-11 |
| Scrollback search | Ghostty | 1.3 | 2026-03-09 |
| Native scrollbars | Ghostty | 1.3 | 2026-03-09 |
| AppleScript automation | Ghostty | 1.3 | 2026-03-09 |
| Command notifications | Ghostty | 1.3 | 2026-03-09 |
| Key tables (modal keybinds) | Ghostty | 1.3 | 2026-03-09 |
| Windows support | Ghostty | 1.2 | 2025-09-15 |
| libghostty-vt (embeddable lib) | Ghostty | N/A | 2025-09-22 |
| Keyboard file selector kitten | Kitty | 0.45 | 2025-12-24 |

---

## Sources

- [2026-04-14] https://github.com/ghostty-org/ghostty/issues?q=is%3Aissue+is%3Aopen+sort%3Areactions-%2B1-desc (Ghostty issues sorted by reactions)
- [2026-04-14] https://github.com/ghostty-org/ghostty/discussions?discussions_q=sort%3Atop (Ghostty discussions sorted by votes)
- [2026-04-14] https://github.com/wezterm/wezterm/issues?q=is%3Aissue+is%3Aopen+sort%3Areactions-%2B1-desc (WezTerm issues sorted by reactions)
- [2026-04-14] https://github.com/kovidgoyal/kitty/issues?q=is%3Aissue+is%3Aopen+sort%3Areactions-%2B1-desc (Kitty issues sorted by reactions)
- [2026-04-14] https://github.com/kovidgoyal/kitty/discussions?discussions_q=sort%3Atop (Kitty discussions sorted by votes)
- [2026-04-14] https://linuxiac.com/ghostty-1-3-terminal-emulator-released-with-native-scrollbars/ (Ghostty 1.3 release coverage)
- [2026-04-14] https://linuxiac.com/kitty-0-46-terminal-emulator-released-with-smooth-scrolling-and-tab-dragging/ (Kitty 0.46 release coverage)
- [2026-04-14] https://linuxiac.com/kitty-terminal-0-43-brings-session-management/ (Kitty 0.43 release coverage)
- [2026-04-14] https://mitchellh.com/writing/libghostty-is-coming (libghostty announcement)
- [2026-04-14] https://mwop.net/blog/2024-10-21-wezterm-resurrect.html (WezTerm resurrect plugin usage)
- [2026-04-14] https://github.com/wezterm/wezterm/issues/3237 (WezTerm save layout request)
- [2026-04-14] https://github.com/wezterm/wezterm/issues/1949 (WezTerm save/load layouts)
- [2026-04-14] https://serverhost.com/blog/category/ghostty/ (Ghostty 1.2 release coverage)
