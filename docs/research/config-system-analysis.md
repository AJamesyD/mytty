# Mistty Configuration System Analysis

Date: 2026-04-14

## What already exists

1. **TOMLKit** is a dependency. Config is TOML at `~/.config/mistty/config.toml`.
2. **MisttyConfig** struct (Mistty/Config/MisttyConfig.swift): parse/load/save with hand-rolled field-by-field TOML parsing. Currently handles: fontSize, fontFamily, cursorStyle, scrollbackLines, sidebarVisible, popups, SSH config.
3. **Ghostty C API** for terminal-level config: `ghostty_config_new()`, `ghostty_config_load_file()`, `ghostty_config_get()`, `ghostty_config_finalize()`. Already wired up in GhosttyApp.swift. Handles ~200 terminal settings with validation and diagnostics.

## Reuse strategy: two layers, no new dependencies

```
Layer 1: Terminal rendering (Ghostty C API)
  - Font, colors, cursor, scrollback, terminal keybinds
  - Parsed by Ghostty's Zig config system (battle-tested, ~200 settings)
  - Loaded from ~/.config/ghostty/config (Ghostty compat for free)
  - Mistty can override via its own config

Layer 2: App behavior (MisttyConfig + TOMLKit)
  - Panels, sessions, which-key, notifications, keybindings
  - Parsed by TOMLKit (already a dependency)
  - Loaded from ~/.config/mistty/config.toml

Layer 3 (future): Per-project overrides
  - .mistty.toml in project root
  - Overrides Layer 2 settings for that workspace
  - Directory trust model for security
```

## Why NOT Lua (for now)

- Lua adds a runtime dependency and embedding complexity
- WezTerm's Lua config is powerful but users cite complexity as a downside
- TOML covers all static config needs
- Lua would only be needed for: event hooks, computed config, dynamic keybinds
- These are Phase 5 features. Add Lua when a feature requires it, not before.
- If Lua is added later, it can coexist with TOML (TOML for simple config, Lua for scripting)

## Config surface area

### Appearance (Layer 1, via Ghostty)
- font-family, font-size, font-weight, line-height
- theme / color scheme (16 ANSI + fg/bg/cursor/selection)
- cursor-style (block/bar/underline), cursor-blink
- window-opacity, background-blur
- padding

### Appearance (Layer 2, Mistty-specific)
- sidebar-position: left | right
- tab-bar-style: custom | native

### Panel behavior (Layer 2)
- sidebar-mode: pinned | auto-hide | hidden
- tab-bar-mode: pinned | auto-hide | hidden
- sidebar-width: integer (default 220)
- auto-hide-dwell-ms: integer (default 150)
- auto-hide-dismiss-ms: integer (default 300)

### Keybindings (Layer 2)
- All action bindings in a [keybind] table
- Format: "modifier+key" = "action"
- Which-key overlay reads from this table

### Terminal behavior (Layer 1 via Ghostty + Layer 2 overrides)
- shell, scrollback-lines, word-delimiters
- close-confirm: always | when-running | never
- new-tab-cwd: current | home | <path>
- new-split-cwd: current | home | <path>
- bell-mode: badge | sound | notification | none

### Session management (Layer 2)
- auto-restore: bool
- scrollback-persist-lines: integer
- default-session-name: directory | git-repo | custom

### Notifications (Layer 2)
- notification-style: ring | dot | highlight | none
- notification-color: string
- dock-badge: bool

### Which-key (Layer 2)
- leader-key: string
- which-key-timeout-ms: integer
- which-key-enabled: bool

### Copy mode (Layer 2)
- copy-mode-keys: vi | emacs
- search-case-sensitive: bool
- yank-to-clipboard: bool

### Integration (Layer 2)
- read-ghostty-config: bool (default true)
- shell-integration: bool
- socket-api: off | local | automation

## Implementation approach

The current MisttyConfig uses hand-rolled field-by-field parsing:
```swift
if let size = table["font_size"]?.int { config.fontSize = size }
```

This is tedious but simple. Options to reduce boilerplate:
1. **Keep hand-rolled**: explicit, easy to debug, no magic. Works fine for ~30 fields.
2. **Swift Codable + TOMLKit**: TOMLKit supports Codable. Define the struct with Codable conformance and decode directly. Less boilerplate but less control over defaults and validation.
3. **Property wrapper**: `@ConfigKey("font_size", default: 13) var fontSize: Int`. More magic but very clean call sites.

Recommendation: start with Codable (option 2) for the bulk of simple fields. Hand-roll parsing only for complex types (keybindings, popups, SSH hosts).

## Ghostty config compatibility

Since GhosttyApp.swift already calls `ghostty_config_load_file()`, reading Ghostty's config is just:
```swift
let ghosttyConfigPath = "~/.config/ghostty/config"
if FileManager.default.fileExists(atPath: ghosttyConfigPath) {
    ghostty_config_load_file(cfg, ghosttyConfigPath)
}
```
cmux does exactly this. Mistty's own config overrides Ghostty's (loaded after).

## Sources

- Mistty/Config/MisttyConfig.swift (current implementation)
- Mistty/App/GhosttyApp.swift (Ghostty C API usage)
- vendor/ghostty/src/config/CApi.zig (Ghostty config C API)
- vendor/ghostty/include/ghostty.h (C API declarations)
- /tmp/ai-research-cmux-patterns.md (cmux's GhosttyConfig.swift)

## Example config file

Shows the full shape of what `~/.config/mistty/config.toml` could look like:

```toml
# ~/.config/mistty/config.toml

# Appearance (overrides Ghostty config if read-ghostty-config = true)
font-family = "Berkeley Mono"
font-size = 13
theme = "catppuccin-mocha"
cursor-style = "block"
cursor-blink = false
window-opacity = 1.0
padding = 4

# Panels
sidebar-position = "left"       # left | right
sidebar-mode = "auto-hide"      # pinned | auto-hide | hidden
sidebar-width = 220
tab-bar-mode = "pinned"          # pinned | auto-hide | hidden
auto-hide-dwell-ms = 150
auto-hide-dismiss-ms = 300

# Terminal
shell = "/bin/zsh"
scrollback-lines = 10000
close-confirm = "when-running"   # always | when-running | never
new-tab-cwd = "current"          # current | home | <path>
new-split-cwd = "current"
word-delimiters = " /\\()\"'-.,:;<>~!@#$%^&*|+=[]{}~?│"

# Bell
bell-mode = "badge"              # badge | sound | notification | none

# Sessions
auto-restore = true
scrollback-persist-lines = 5000
default-session-name = "directory"  # directory | git-repo | custom

# Notifications
notification-style = "ring"      # ring | dot | highlight | none
notification-color = "blue"
dock-badge = true

# Which-key
leader-key = "ctrl+space"
which-key-timeout-ms = 3000
which-key-enabled = true

# Copy mode
copy-mode-keys = "vi"            # vi | emacs
search-case-sensitive = false
yank-to-clipboard = true

# Window mode
resize-step = 0.05

# Integration
read-ghostty-config = true
shell-integration = true
socket-api = "off"               # off | local | automation

# Keybindings
[keybind]
"cmd+j" = "session-manager"
"cmd+s" = "toggle-sidebar"
"cmd+t" = "new-tab"
"cmd+w" = "close-pane"
"cmd+d" = "split-right"
"cmd+shift+d" = "split-down"
"ctrl+h" = "navigate-left"
"ctrl+j" = "navigate-down"
"ctrl+k" = "navigate-up"
"ctrl+l" = "navigate-right"
"cmd+shift+u" = "jump-to-unread"
"cmd+`" = "last-workspace"

# Popups (existing feature)
[[popup]]
name = "htop"
command = "htop"
shortcut = "cmd+shift+h"
width = 0.8
height = 0.8
close_on_exit = true

# SSH overrides (existing feature)
[ssh]
default_command = "ssh"

[[ssh.host]]
hostname = "devbox"
command = "et"
```
