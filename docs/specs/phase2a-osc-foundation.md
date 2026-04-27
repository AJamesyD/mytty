# Phase 2a: OSC Foundation

Mytty macOS terminal emulator, libghostty backend.

**Status:** Implemented

**Goal:** Handle the remaining OSC action callbacks from libghostty, storing state on the model layer. Visual rendering of most new state is deferred to Phase 2b.

**Date:** 2026-04-14

---

## 1. Action routing architecture

### Current pattern

```
C callback (arbitrary thread)
  -> NotificationCenter.post (with userInfo dict)
    -> ContentView+Handlers.swift observer (main thread via .receive(on:))
      -> model update
```

Six actions use this pattern today: RENDER, SET_TITLE, CLOSE_WINDOW, CELL_SIZE/SIZE_LIMIT/INITIAL_SIZE/MOUSE_*, RING_BELL, SCROLLBAR.

### Proposed: keep the same pattern

Each new action gets:
- A `Notification.Name` constant (in GhosttyApp.swift, alongside existing ones)
- A handler method in ContentView+Handlers.swift

This keeps all model mutations on the main thread without new synchronization code.

### Alternative considered

Direct model updates from the C callback, bypassing NotificationCenter. Rejected: the callback runs on an arbitrary libghostty thread. The existing pattern already handles main-thread dispatch correctly. Changing the pattern mid-project adds risk for no benefit.

---

## 2. PWD tracking (OSC 7)

**Action:** `GHOSTTY_ACTION_PWD` with `{ pwd: const char* }`

### Model changes (MyttyPane.swift)

Add `workingDirectory: URL?` to MyttyPane. Keep the existing `directory: URL?` as-is (it represents the initial/configured directory from the session). `workingDirectory` tracks the live value reported by the shell.

On first PWD action, `workingDirectory` is set. It updates on every subsequent PWD action.

### Handler (ContentView+Handlers.swift)

```swift
// On .ghosttyPwd notification:
// 1. Extract pwd string from userInfo
// 2. Convert to URL via URL(fileURLWithPath:)
// 3. Set pane.workingDirectory
```

### Display

Sidebar path display (shortened: `~` for home, last 2 components for deep paths) is deferred to Phase 2b sidebar metadata work.

---

## 3. Title sequence handling (OSC 0/1/2)

### Title priority (highest to lowest)

| Priority | Source | Property | Set by |
|----------|--------|----------|--------|
| 1 | User rename (Phase 1b) | `tab.customTitle` | User action |
| 2 | SET_TAB_TITLE | `tab.tabTitle` | OSC (shell-integration) |
| 3 | SET_TITLE | `tab.processTitle` | OSC 0/1/2 |
| 4 | Default | `"Shell"` | Fallback |

### Model changes (MyttyTab.swift)

Add `tabTitle: String?` to MyttyTab. Rename the existing `title` usage so `displayTitle` computes from the priority chain:

```swift
var displayTitle: String {
    customTitle ?? tabTitle ?? processTitle ?? "Shell"
}
```

`processTitle` moves from MyttyPane to MyttyTab (it is a display concern, not a process concern). If keeping it on MyttyPane is simpler given existing code, the handler copies it to the tab on update.

### SET_TITLE debounce

Add a 75ms debounce timer on SET_TITLE updates. If a new SET_TITLE arrives within 75ms, cancel the previous pending update and schedule the new one. This matches Ghostty's pattern and prevents title flicker from shells that emit rapid title sequences.

The debounce timer lives in the handler (ContentView+Handlers.swift), not the model.

### SET_TAB_TITLE

New notification: `.ghosttySetTabTitle`. Handler sets `tab.tabTitle`. No debounce needed (this is an explicit, infrequent action from shell integration).

### PROMPT_TITLE

Deferred to Phase 5. Requires a prompt dialog (command palette or NSAlert). Not needed for foundation work.

---

## 4. Desktop notifications (OSC 9/99/777)

**Action:** `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` with `{ title: const char*, body: const char* }`

### Behavior

1. Only show the notification when the source pane is not focused (same rule as bell).
2. Use `UNUserNotificationCenter` to post.
3. Include the pane's UUID in the notification's `userInfo` dictionary. This enables click-to-focus in a future phase.
4. Request notification permission (`requestAuthorization`) on the first notification attempt. Cache the authorization result to avoid repeated prompts.

### Handler

```swift
// On .ghosttyDesktopNotification:
// 1. Check if pane is focused; skip if yes
// 2. Build UNMutableNotificationContent with title + body
// 3. Set userInfo["paneId"] = pane.id.uuidString
// 4. Add request to UNUserNotificationCenter
```

Permission request happens lazily: the first time a notification is about to be posted, check authorization status. If `.notDetermined`, request. If `.denied`, skip silently.

---

## 5. Command finished (OSC 133)

**Action:** `GHOSTTY_ACTION_COMMAND_FINISHED` with `{ exit_code: int16, duration: uint64 }`

### Model changes (MyttyPane.swift)

```swift
struct CommandResult {
    let exitCode: Int16   // -1 means no exit code
    let duration: UInt64  // nanoseconds
}

// On MyttyPane:
var lastCommandResult: CommandResult?
```

### Handler

Store the result on the pane. No UI action in Phase 2a.

Phase 2b uses this for sidebar badges (exit code indicators) and prompt navigation. Phase 4 adds config-gated bell/notification on non-zero exit.

---

## 6. Progress report

**Action:** `GHOSTTY_ACTION_PROGRESS_REPORT` with `{ state: enum, progress: int8 }`

### Model changes (MyttyPane.swift)

```swift
enum ProgressState {
    case remove
    case set(progress: Int8)  // 0-100, or -1 for unknown
    case error
    case indeterminate
    case pause
}

// On MyttyPane:
var progressState: ProgressState?
```

### Auto-expiry

When `progressState` is set to anything other than `.remove`, start a 15-second timer. If no new progress report arrives within 15s, set `progressState` to `nil`. This matches Ghostty's behavior.

The timer lives in the handler, not the model. Each new progress report resets the timer.

### Handler

On `.remove` state: set `progressState = nil` and cancel the expiry timer.
On any other state: set `progressState`, reset the 15s expiry timer.

Visual rendering (progress bar in sidebar or tab) is deferred to Phase 2b.

---

## 7. Out of scope

| Action/Feature | Reason deferred | Target phase |
|---|---|---|
| COLOR_CHANGE | Needs theme system | Phase 3+ |
| OPEN_URL | Needs URL handling policy | Phase 3+ |
| MOUSE_OVER_LINK | Needs link preview UI | Phase 3+ |
| PROMPT_TITLE | Needs prompt dialog UI | Phase 5 |
| Sidebar metadata display | Depends on Phase 2a model | Phase 2b |
| Prompt navigation (Cmd+Up/Down) | Depends on OSC 133 data | Phase 2b |
| Config gating for notifications/bell | Needs config system | Phase 4 |

---

## 8. Files changed

No new files. All changes go in existing files:

| File | Changes |
|---|---|
| GhosttyApp.swift | New action cases in `actionCallback` switch. New `Notification.Name` constants for PWD, SET_TAB_TITLE, DESKTOP_NOTIFICATION, COMMAND_FINISHED, PROGRESS_REPORT. |
| ContentView+Handlers.swift | New handler methods for each notification. Debounce timer for SET_TITLE. Expiry timer for progress. |
| MyttyPane.swift | Add `workingDirectory: URL?`, `lastCommandResult: CommandResult?`, `progressState: ProgressState?`. Add `CommandResult` struct and `ProgressState` enum. |
| MyttyTab.swift | Add `tabTitle: String?`. Update `displayTitle` to use the 4-level priority chain. Move or copy `processTitle` handling. |

---

## 9. Testing

Unit tests for:
- **Title priority:** verify `displayTitle` returns the correct value for each combination of `customTitle`, `tabTitle`, `processTitle`, and nil states.
- **PWD propagation:** verify that setting `workingDirectory` on a pane updates the stored URL correctly.
- **Progress auto-expiry:** verify that `progressState` resets to nil after 15s with no new reports. Verify that a new report resets the timer.

---

## 10. Acceptance criteria

- `echo -e '\e]7;file:///tmp\e\\'` sets `pane.workingDirectory` to `/tmp`.
- Rapid shell prompt title changes do not cause visible flicker (75ms debounce).
- User-set `customTitle` (Phase 1b rename) takes priority over all terminal-set titles.
- SET_TAB_TITLE takes priority over SET_TITLE but not over `customTitle`.
- `printf '\e]9;Test notification\e\\'` shows a macOS notification when the pane is not focused.
- Notifications do not appear when the source pane is focused.
- OSC 133 command finished stores exit code and duration on the pane model.
- Progress report data is stored on the pane model and auto-expires after 15s of inactivity.
