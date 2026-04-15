# Phase 2c: Basic Session Persistence

**Status:** Draft
**Date:** 2026-04-14
**Scope:** Save and restore the session/tab/pane tree across app restarts. Shells restart fresh (no scrollback, no process restoration).

---

## 1. What State to Save

### Saved

| Level | Fields |
|-------|--------|
| Global | active session index, window frame (if needed) |
| Session | `name`, `directory` URL, `sshCommand`, tab order, active tab index |
| Tab | `customTitle`, `directory` URL, pane layout, active pane index |
| Pane | `directory` URL, `command`, `useCommandField` |
| Layout node | split direction, split ratio, recursive left/right structure |

### Not Saved

- Scrollback (deferred to Phase 4c)
- Running processes (shells restart fresh)
- `processTitle` (set by the terminal, not the user)
- `hasBell`, `zoomedPane`, `copyModeState`, `windowModeState` (transient UI state)
- Popup state (transient)
- ID generator state (regenerated on restore)

---

## 2. Serialization Format

JSON via `Codable`. Written to `~/.config/mistty/sessions.json`.

Why JSON over plist or NSCoder: human-readable, debuggable, no AppKit dependency, works with `Codable` directly.

### Schema

```
PersistentState
  version: Int
  activeSessionIndex: Int?
  sessions: [PersistentSession]

PersistentSession
  name: String
  directory: URL
  sshCommand: String?
  activeTabIndex: Int?
  tabs: [PersistentTab]

PersistentTab
  customTitle: String?
  directory: URL?
  activePaneIndex: Int?
  layout: PersistentLayoutNode

PersistentLayoutNode (enum, Codable)
  leaf(PersistentPane)
  split(SplitDirection, PersistentLayoutNode, PersistentLayoutNode, CGFloat)

PersistentPane
  directory: URL?
  command: String?
  useCommandField: Bool
```

A `version` field gates decoding. If the stored version does not match the current version, skip restore and start fresh. This is the first version, so no migration logic is needed. The version field enables future migration.

---

## 3. Save Triggers

All saves go through a single `PersistenceService` that coalesces writes.

| Trigger | Debounce |
|---------|----------|
| `NSApplication.willTerminateNotification` (app quit) | Immediate |
| `NSApplication.didResignActiveNotification` (app loses focus) | 2 seconds |
| Structural change (session create/delete, tab create/delete, pane split/close) | 5 seconds |

The debounce timer resets on each new trigger. Only one write happens per debounce window.

---

## 4. Restore Behavior

On app launch:

1. Check for `~/.config/mistty/sessions.json`.
2. If found and version matches: decode and restore the full tree.
3. Assign fresh sequential IDs to all sessions, tabs, and panes (old IDs are not restored).
4. For each pane: create a new `TerminalSurfaceView` with the saved directory and command.
5. Set active session, tab, and pane after the tree is fully built.
6. If a saved directory does not exist on disk: substitute the home directory.
7. If no saved state exists, or restore fails: create the default session (current behavior).

---

## 5. Edge Cases

| Scenario | Behavior |
|----------|----------|
| Corrupt JSON | Log a warning, start fresh. Do not crash. |
| Missing directory | Substitute home directory. Log which directory was missing. |
| Empty `sessions` array | Start fresh. |
| App crash (no `willTerminate`) | The `didResignActive` save provides a recent snapshot. Accept that crash recovery may lose the last few seconds of layout changes. |
| Multiple windows | Out of scope. Save the single window's state only. |

---

## 6. New Files

| File | Contents |
|------|----------|
| `Mistty/Services/PersistenceService.swift` | Save/restore logic, debounce timer, JSON encoding/decoding, file I/O |
| `Mistty/Models/PersistentState.swift` | All `Codable` structs: `PersistentState`, `PersistentSession`, `PersistentTab`, `PersistentPane`, `PersistentLayoutNode` |

---

## 7. Changes to Existing Files

| File | Change |
|------|--------|
| `MisttyApp.swift` | Call `PersistenceService.restore()` on launch. Register for `willTerminateNotification`. |
| `SessionStore.swift` | Add `toPersistentState() -> PersistentState`. Add `restore(from: PersistentState)`. |
| `SplitDirection.swift` | Add `Codable` conformance. |

---

## 8. Testing

| Test | Verifies |
|------|----------|
| Round-trip | Create state, serialize, deserialize, check equality |
| Corrupt JSON | Graceful fallback to default session |
| Missing directory | Home directory substitution |
| Version mismatch | Graceful fallback to default session |
| Empty sessions array | Fresh start |

---

## 9. Acceptance Criteria

- Quit app with 2 sessions, 3 tabs, and split panes. Relaunch. Same layout restored.
- Session names, custom tab titles, and working directories preserved.
- Pane commands re-execute in the correct directories.
- Corrupt `sessions.json`: app starts normally with a default session.
- Delete `sessions.json`: app starts normally with a default session.

---

## 10. What This Enables

- **Phase 4c (Advanced Persistence)** extends this with scrollback and running command restoration.
- **Phase 5e (Project Layouts)** reuses the serialization format for `.mistty.toml` layout definitions.
