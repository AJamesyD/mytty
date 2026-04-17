# Phase 3b: Bidirectional Neovim Navigation

Mytty macOS terminal emulator, libghostty backend.

**Goal:** Enable bidirectional split navigation between neovim and Mytty panes via a smart-splits.nvim backend. A user pressing Ctrl+h/j/k/l moves focus across neovim splits and Mytty panes as if they were a single layout.

**Date:** 2026-04-15

---

## 1. Navigation flow

Two directions of navigation must work together.

**Neovim to Mytty:** The user presses Ctrl+h at neovim's leftmost split. smart-splits detects the edge (comparing `winnr()` before and after `wincmd`), calls the Mytty backend's `next_pane('left')`, which runs `mytty-cli pane focus --direction left`. Mytty moves focus to the adjacent pane.

**Mytty to neovim:** The user presses Ctrl+h in a Mytty pane. `PaneNavigationManager` intercepts the keypress. If the pane has a `is-vim` variable set, the keypress is forwarded to the pane (neovim handles it via smart-splits). If the variable is not set, Mytty navigates panes directly.

The round-trip case: neovim receives the forwarded keypress, smart-splits checks if neovim has a split in that direction. If yes, neovim moves its own cursor. If no (at edge), smart-splits calls back to Mytty via the CLI.

### Current

`PaneNavigationManager` already intercepts Ctrl+h/j/k/l. It checks `pane.isRunningVimLike` (process title matching against "nvim", "neovim", "vim") and forwards the keypress if true. This handles the Mytty-to-neovim direction but relies on process name heuristics.

The neovim-to-Mytty direction does not work. No smart-splits backend exists for Mytty.

### Proposed

Replace `isRunningVimLike` process detection with explicit pane variables set by the smart-splits backend. Add IPC methods and CLI commands that the backend needs. Write the backend.

Process detection stays as a fallback: if `vars["is-vim"]` is not set, `isRunningVimLike` still applies. This preserves the current behavior for users who have not configured smart-splits.

---

## 2. New IPC methods

Three new methods on the service protocol.

### `pane.atEdge`

Check if the active pane is at the edge of the layout in a given direction.

- **Params:** `direction` (string: left/right/up/down), `sessionId` (int, 0 = active)
- **Returns:** `{"atEdge": true}` or `{"atEdge": false}`
- **Used by:** `current_pane_at_edge()` in the smart-splits backend

Implementation: call `tab.layout.adjacentPane(from: pane, direction:)`. If nil, the pane is at the edge.

#### Alternative considered

The wezterm backend uses a try-and-check pattern: call `next_pane`, then check if the pane ID changed. This works with existing methods but has a side effect (focus actually moves). A dedicated query method avoids the side effect.

### `pane.setVar`

Set a per-pane variable.

- **Params:** `paneId` (int, 0 = active), `key` (string), `value` (string or null to unset)
- **Returns:** `{}`
- **Used by:** `on_init()`/`on_exit()` in the smart-splits backend to set/clear `is-vim`

Implementation: add a `vars: [String: String]` dictionary to `MyttyPane`. When `value` is null, remove the key.

### `pane.getVar`

Get a per-pane variable.

- **Params:** `paneId` (int, 0 = active), `key` (string)
- **Returns:** `{"value": "true"}` or `{"value": null}`
- **Used by:** `PaneNavigationManager` keybinding handler (internal), and available to external scripts

#### Alternative considered for pane variables

OSC 1337 `SetUserVar` escape sequences (used by wezterm and kitty). Rejected for two reasons:

1. libghostty parses OSC 1337 `SetUserVar` but does not expose it to the app layer (the action returns invalid).
2. The DESIGN.md constraint prohibits parsing raw escape sequences outside libghostty.

The IPC-based approach achieves the same result without violating architecture constraints. If libghostty adds `SetUserVar` support in the future, Mytty can wire it to the same `vars` dictionary.

### `zoomed` field on pane responses

Add `zoomed: Bool` to `PaneResponse`. smart-splits checks `current_pane_is_zoomed()` and can block navigation when the pane is zoomed (configurable in smart-splits). The value comes from `MyttyTab.zoomedPane`: true if the pane matches the tab's zoomed pane.

---

## 3. smart-splits.nvim backend

A Lua module distributed as a separate neovim plugin (`mytty-nav`). Users can also contribute it upstream to smart-splits.nvim once stable.

The module lives at `lua/smart-splits/mux/mytty.lua` in the plugin's runtimepath. smart-splits loads backends dynamically via `require('smart-splits.mux.' .. config.multiplexer_integration)`.

Detection: the backend checks for the `$MYTTY_SOCKET` environment variable. Users configure smart-splits with `multiplexer_integration = 'mytty'`, or Mytty can be added to the auto-detection chain in `mux/utils.lua` (upstream PR, out of scope for this phase).

All functions use `vim.fn.system()` to call `mytty-cli`, following the pattern established by the tmux and wezterm backends.

| smart-splits function | mytty-cli command |
|---|---|
| `is_in_session()` | Check `$MYTTY_SOCKET` exists |
| `current_pane_id()` | `mytty-cli pane active --json` (parse pane ID) |
| `next_pane(direction)` | `mytty-cli pane focus --direction <dir>` |
| `current_pane_at_edge(direction)` | `mytty-cli pane at-edge --direction <dir> --json` (parse `atEdge`) |
| `current_pane_is_zoomed()` | `mytty-cli pane active --json` (parse `zoomed`) |
| `resize_pane(direction, amount)` | `mytty-cli pane resize --direction <dir> --amount <n>` |
| `split_pane(direction, size)` | `mytty-cli pane create --direction <dir>` |
| `on_init()` | `mytty-cli pane set-var --key is-vim --value true` |
| `on_exit()` | `mytty-cli pane set-var --key is-vim` (no value = unset) |

---

## 4. Keybinding interception changes

### Current

`PaneNavigationManager.handleKeyDown` checks `pane.isRunningVimLike` (process title heuristic). If true, returns the event (forwards to pane). If false, calls `tab.layout.adjacentPane` and navigates.

### Proposed

Change the check order:

1. If the tab has only one pane (no splits), forward the keypress to the pane. (Current behavior already does this: `adjacentPane` returns nil, the event passes through.)
2. Check `pane.vars["is-vim"]`. If set, forward to the pane.
3. Fall back to `pane.isRunningVimLike`. If true, forward to the pane.
4. Otherwise, navigate Mytty panes.

The only code change is inserting the `vars["is-vim"]` check before the existing `isRunningVimLike` check in `PaneNavigationManager.handleKeyDown`.

---

## 5. Environment variables

Mytty needs to set environment variables on child processes so the smart-splits backend can detect it is running inside Mytty.

### Current

Mytty does not set custom environment variables for child processes. libghostty manages the process environment.

### Proposed

Set two variables when creating a pane's shell process:

- `MYTTY_SOCKET`: set to `MyttyIPC.socketPath`. The smart-splits backend uses this to detect Mytty and locate the socket.
- `TERM_PROGRAM`: set to `mytty`. Standard convention (wezterm, kitty, and iTerm2 all set this).

How these are injected depends on libghostty's surface configuration API. If libghostty supports an environment dictionary on surface creation, use that. If not, set the variables on the app's `ProcessInfo.processInfo.environment` before surface creation (they propagate to child processes). The implementation must verify which approach libghostty supports.

---

## 6. Migration strategy

Four sub-phases, each a separate commit:

1. **3b-1:** Add `pane.atEdge`, `pane.setVar`, `pane.getVar` IPC methods. Add `vars` dictionary to `MyttyPane`. Add `zoomed` to `PaneResponse`. Add CLI subcommands (`at-edge`, `set-var`, `get-var`).
2. **3b-2:** Write the `mytty.lua` smart-splits backend. Test neovim-to-Mytty direction.
3. **3b-3:** Update `PaneNavigationManager` to check `vars["is-vim"]` before `isRunningVimLike`. Test bidirectional flow.
4. **3b-4:** Set `MYTTY_SOCKET` and `TERM_PROGRAM` environment variables for child processes.

---

## 7. Files changed

Modified files:

| File | Changes |
|------|---------|
| `MyttyShared/MyttyServiceProtocol.swift` | Add `pane.atEdge`, `pane.setVar`, `pane.getVar` method declarations |
| `Mytty/Services/IPCService.swift` | Implement the three new methods |
| `Mytty/Services/IPCListener.swift` | Add dispatch cases for the three new methods |
| `Mytty/Models/MyttyPane.swift` | Add `vars: [String: String]` property |
| `MyttyShared/Models/PaneResponse.swift` | Add `zoomed: Bool` field |
| `MyttyCLI/Commands/PaneCommand.swift` | Add `at-edge`, `set-var`, `get-var` subcommands |
| `Mytty/App/PaneNavigationManager.swift` | Check `vars["is-vim"]` before `isRunningVimLike` |

New files:

| File | Purpose |
|------|---------|
| `extras/neovim/lua/smart-splits/mux/mytty.lua` | smart-splits.nvim backend for Mytty |

---

## 8. Testing

Unit tests for:

- `pane.atEdge` returns true for a single-pane tab (at edge in all directions)
- `pane.atEdge` returns false when an adjacent pane exists in the queried direction
- `pane.setVar`/`pane.getVar` round-trip: set a value, read it back
- `pane.setVar` with null value removes the key
- Pane variable cleanup: closing a pane does not leak its `vars` dictionary
- `zoomed` field in `PaneResponse` reflects `MyttyTab.zoomedPane` state
- `PaneNavigationManager` forwards keypress when `vars["is-vim"]` is set
- `PaneNavigationManager` navigates panes when `vars["is-vim"]` is not set and `isRunningVimLike` is false

---

## 9. Out of scope

| Feature | Reason | Target |
|---------|--------|--------|
| OSC 1337 SetUserVar parsing | libghostty does not expose it; architecture constraint | When libghostty adds support |
| Upstream smart-splits.nvim PR | Separate from the Mytty codebase | After 3b is stable |
| Configurable navigation keys | Ctrl+h/j/k/l is the universal default | Phase 4 (config system) |
| Nested neovim detection | Known limitation in wezterm/kitty backends too | Future |
| Auto-detection in smart-splits | Requires upstream changes to `mux/utils.lua` | After upstream PR |

---

## 10. Acceptance criteria

- In neovim with smart-splits configured for Mytty: Ctrl+l at the rightmost neovim split moves focus to the Mytty pane to the right.
- In a Mytty pane running neovim with smart-splits: Ctrl+h moves focus into neovim (not to the Mytty pane to the left).
- In a Mytty pane not running neovim: Ctrl+h moves focus to the Mytty pane to the left.
- Single-pane tabs: all Ctrl+h/j/k/l keypresses pass through to the pane.
- `mytty-cli pane at-edge --direction left --json` returns `{"atEdge": true}` when the active pane is at the left edge.
- `mytty-cli pane set-var --key is-vim --value true` followed by `mytty-cli pane get-var --key is-vim --json` returns `{"value": "true"}`.
- `mytty-cli pane set-var --key is-vim` (no value) clears the variable; subsequent `get-var` returns `{"value": null}`.
- `$MYTTY_SOCKET` is set in the environment of shell processes spawned by Mytty.
