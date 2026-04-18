# Phase 2b: Contextual Sidebar

**Date:** 2026-04-14 (updated 2026-04-14)
**Depends on:** Phase 2a (OSC Foundation, done)
**Scope:** Three features that make the sidebar show what's happening without mode-switching: notification badges, rich metadata, and shell integration display.

## Prior art and research

Competitive landscape for each feature area:

- **cmux:** notification rings, sidebar metadata (git branch, ports, working directory). The only terminal that combines notifications + git + ports + working directory in a sidebar.
- **iTerm2:** blue dot for new input, shell integration marks, Cmd+Shift+Up/Down prompt navigation.
- **VS Code:** file watcher for git, gutter decorations (blue/red circles) per command, Cmd+Up/Down prompt navigation.
- **Warp:** block-based output with exit code/duration, native git detection, red background on failed blocks. The only terminal with structured command metadata.
- **Kitty:** configurable tab_activity_symbol, red for bell.
- **tmux:** single-char flags (#, !) in status bar.

Command state indicators across terminals: most terminals show command results inline (Warp blocks, VS Code gutter). None show command results in a sidebar tab row. The closest pattern is IDE run configurations showing pass/fail icons. Mytty's approach (process title left, result icon right) is novel for terminal sidebars.

Mytty combines cmux's sidebar metadata with Warp's structured command metadata in a single view.

## Decision log

### D1: Tab row shows process title (left) + last command result (right)

**Chosen:** Process title as running indicator, command result as trailing status.
**Alternatives considered:** Dedicated running spinner (rejected: no reliable command-started signal without OSC 133 C). Elapsed timer (rejected: also needs OSC 133 C to know when a command starts).
**Presupposition:** SET_TITLE reliably reflects the foreground process name. Users read process name as running/idle signal.
**Revisit when:** libghostty exposes OSC 133 C (command output start) as an action, enabling explicit running-state detection.

### D2: Notification treatment uses macOS-native patterns

**Chosen:** SF Symbols for tab indicators (bell.fill red, xmark.circle.fill orange). Session rollup as count pill (like Mail's unread count).
**Alternatives considered:** Colored dots (rejected: more Linux/web than macOS). cmux-style glow rings (rejected: high cost, requires pane border rendering).
**Presupposition:** macOS users expect Mail-style badges and SF Symbol indicators, not colored dots.
**Revisit when:** User testing shows the SF Symbols are too small or the pill badge is overlooked.

### D3: Session-level metadata only (not per-tab)

**Chosen:** Git branch + working directory on session row for the active tab.
**Alternatives considered:** Per-tab metadata line (rejected: ~50% row height increase, common-case redundancy when tabs share a repo).
**Presupposition:** Tabs within a session usually share the same repo/directory.
**Revisit when:** Daily use shows frequent tab-level divergence within sessions.

> **Implementation note (2026-04-18):** D2 was overridden during implementation. The shipped sidebar uses glow dots (6px Circle with shadow) instead of SF Symbols, matching DESIGN.md Tenet 3 (pre-attentive signals over symbolic identification) and the sidebar-information-architecture.md recommendation.

> **Implementation note (2026-04-18):** D3 (git branch + working directory on session rows) was built and reverted. Per-pane metadata does not belong at session level. The feature may return in a different form.

### D4: Event-driven git detection (not polling, not file watcher)

**Chosen:** Run `git rev-parse` on OSC 7 (directory change) and COMMAND_FINISHED events.
**Alternatives considered:** File watcher on .git/HEAD (rejected: no existing file watcher infrastructure, lifecycle complexity). Periodic polling (rejected: wasteful when event-driven triggers are available). Shell integration env var (rejected: requires user shell config changes).
**Presupposition:** OSC 7 and COMMAND_FINISHED fire frequently enough to keep git info current. Git commands complete in <50ms for typical repos.
**Revisit when:** Users report stale git info, or git commands are slow on large repos (add timeout + caching).

### D5: No "unread output" indicator for v1

**Chosen:** Ship bell + command failure only. No blue "unread output" dot.
**Alternatives considered:** Title-change heuristic (rejected: fires on prompt redraws, too noisy). Render callback hook (rejected: no libghostty API for this).
**Presupposition:** There is no clean per-pane output signal from libghostty without hooking into the render path.
**Revisit when:** Phase 3 socket API provides output events, or libghostty adds an output callback action.

### D6: Success is quiet, failure is loud

**Chosen:** Successful commands show a small green checkmark (informational). Failed commands show orange X + notification badge on background tabs.
**Alternatives considered:** Notify on all completions (rejected: too noisy for common commands like cd, ls). Notify on long commands only (rejected: arbitrary threshold, what counts as "long"?).
**Presupposition:** Most commands succeed. Failure is the exception that needs attention. Success is the default that needs confirmation, not interruption.
**Revisit when:** User feedback requests success notifications for long-running commands (add configurable duration threshold in Phase 4).

### D7: Prompt navigation via jump_to_prompt binding action

**Chosen:** Cmd+Shift+Up/Down triggers `ghostty_surface_binding_action(surface, "jump_to_prompt:-1/1", ...)`.
**Alternatives considered:** Cmd+Up/Down (rejected: conflicts with macOS text navigation). Custom scrollback parsing (rejected: libghostty already tracks prompt marks).
**Presupposition:** `ghostty_surface_binding_action` with "jump_to_prompt" works from the apprt layer. Shell integration (OSC 133) is configured.
**Revisit when:** jump_to_prompt doesn't work as expected from the apprt binding API (test during implementation).

### D8: Port detection deferred

**Chosen:** Defer to 2b-5 or later.
**Alternatives considered:** Ship with git + ports together (rejected: lsof integration adds complexity, port info is lower value than git branch).
**Presupposition:** Git branch and working directory are the highest-value metadata items.
**Revisit when:** 2b-2 ships and users ask for port info.

---

## Feature 1: Notification badges

### Tab-level indicators

Replace the existing 6px bell dot with SF Symbol indicators:

| State | SF Symbol | Color | Size | Trigger | Clears when |
|-------|-----------|-------|------|---------|-------------|
| Bell | bell.fill | .red | 10px | RING_BELL while tab inactive | Tab becomes active |
| Command failed | xmark.circle.fill | .orange | 10px | COMMAND_FINISHED with non-zero exit while tab inactive | Tab becomes active |

Priority: command failed > bell. Only one indicator shown.

Bell indicator only appears when the tab is NOT the active tab of the active session. Same rule as existing hasBell behavior.

Command failure indicator: set when COMMAND_FINISHED fires with non-zero exit AND the tab is not active. If the tab IS active, no badge (the user can see the result directly).

### Session-level rollup

When collapsed, session row shows a trailing pill badge (like Mail's unread count):
- Background: highest-severity color (.orange if any failure, .red if bell only)
- Text: count of tabs with notifications
- Hidden when 0

### Model changes

- MyttyTab: add `var hasFailedCommand: Bool = false`
- MyttySession: add computed `var notificationCount: Int` and `var notificationSeverity: NotificationSeverity?`

---

## Feature 2: Rich sidebar metadata

### Session row metadata line

Below session name, 11px monospaced .secondary text:

```
main* · ~/Code/mytty
```

Shows metadata for the session's active tab's active pane:
- Git branch + dirty indicator (main*)
- Shortened working directory
- Ports (deferred to 2b-5)

Separated by ` · `. Hidden when no metadata exists.

### Git branch detection

Event-driven, not polling:
- Run `git rev-parse --abbrev-ref HEAD` and `git diff --quiet` asynchronously
- Trigger on: OSC 7 (directory change), COMMAND_FINISHED
- Debounce: 200ms. Rapid COMMAND_FINISHED events (watch loops, repeated Ctrl+C) coalesce into one git check.
- Cache result per pane. Invalidate on next trigger.
- Timeout: 500ms. If git commands are slow, show stale cache.

### Working directory display

Shorten pane.workingDirectory:
- Replace home with ~
- If >3 components after home: ~/…/parent/leaf

---

## Feature 3: Shell integration display

### Tab row layout

```
[indicator] [process title]          [result icon] [duration]
```

Left side: notification indicator (SF Symbol, if any) + process title (from tab.displayTitle, which shows the process name via SET_TITLE).

Right side (trailing, right-aligned): last command result icon + duration.

The process title serves as the running-state indicator:
- "zsh" / "bash" / "fish" = idle at prompt
- "cargo" / "npm" / "python" = command running
- "nvim" / "vim" = interactive app (no command results expected)

### Command result display

- checkmark.circle.fill (.green, dimmed to .secondary opacity) for exit 0
- xmark.circle.fill (.orange) for non-zero exit
- Duration shown only if > 1 second: "2s", "1m 23s", "2h 5m"
- Nothing shown if no COMMAND_FINISHED has fired for this pane

### Prompt navigation

Confirmed feasible via ghostty binding action API.

- Cmd+Shift+Up: `ghostty_surface_binding_action(surface, "jump_to_prompt:-1", 18)`
- Cmd+Shift+Down: `ghostty_surface_binding_action(surface, "jump_to_prompt:1", 17)`

Requires shell integration (OSC 133) to be configured in the user's shell.

Silent failure handling: if the first jump_to_prompt call results in no scroll movement, show a one-time hint (e.g., status bar message or brief overlay): "Enable shell integration for prompt navigation." Detect no-movement by comparing scroll position before and after the call.

Visual highlight on navigation: deferred (requires renderer-level changes). The scroll itself is the v1 deliverable.

---

## Implementation phases

### 2b-1: Notification badges

- Add hasFailedCommand to MyttyTab
- Update handleCommandFinished to set it (only when tab is not active)
- Replace bell dot with SF Symbol indicators in SidebarView
- Add session-level notification rollup (count pill)
- Clear indicators on tab activation

### 2b-2: Git branch + working directory metadata

- Add GitDetectionService (async Process for git commands)
- Add gitBranch, gitDirty to MyttyPane
- Add metadata line to SessionRowView
- Trigger on OSC 7 and COMMAND_FINISHED
- Path shortening helper

### 2b-3: Command status display (tab row trailing result)

- Add trailing result view to tab row (checkmark/X + duration)
- Duration formatting helper
- Process title already shown via displayTitle

### 2b-4: Prompt navigation

- Add Cmd+Shift+Up/Down to TerminalCommands
- Call ghostty_surface_binding_action with jump_to_prompt
- Add menu items

### 2b-5: Port detection (deferred)

- lsof integration
- Add to metadata line

---

## New files

| File | Contents |
|------|----------|
| Mytty/Services/GitDetectionService.swift | Async git rev-parse + git diff --quiet |

## Changed files

| File | Changes |
|------|---------|
| MyttyPane.swift | Add gitBranch, gitDirty |
| MyttyTab.swift | Add hasFailedCommand |
| MyttySession.swift | Add computed notificationCount, notificationSeverity |
| ContentView+Handlers.swift | Update handleCommandFinished to set hasFailedCommand, trigger git detection on COMMAND_FINISHED and PWD |
| SidebarView.swift | SF Symbol indicators, session rollup pill, metadata line, trailing command result |
| TerminalCommands.swift | Add jumpToPreviousPrompt, jumpToNextPrompt |
| MyttyApp.swift | Add Cmd+Shift+Up/Down menu items |

## Testing

- Notification priority: hasFailedCommand > hasBell > nothing
- Notification clearing: cleared when tab becomes active
- Session rollup: computed count and severity from child tabs
- Git detection: mock git commands, verify branch/dirty parsing
- Duration formatting: seconds, minutes+seconds, hours+minutes
- Path shortening: home replacement, truncation

## Acceptance criteria

- Non-zero exit code on background tab shows orange xmark.circle.fill SF Symbol
- Bell on background tab shows red bell.fill SF Symbol
- Collapsed session shows pill badge with count and highest-severity color
- Session row shows git branch (with dirty *) and shortened working directory
- Tab row shows process title (left) and last command result (right-aligned)
- Commands > 1s show formatted duration
- Cmd+Shift+Up/Down scrolls between prompts

## Future work (from decision log)

- Running-state indicator: when libghostty exposes OSC 133 C, add explicit running state
- Unread output: when socket API or output callback exists, add blue indicator
- Success notification for long commands: configurable duration threshold (Phase 4 config)
- Port detection: lsof integration (2b-5)
- Per-tab metadata: if session-level proves insufficient
- Prompt navigation visual highlight: renderer-level prompt line decoration

## Sources

- /tmp/ai-research-phase2b-inputs.md
- /tmp/ai-research-phase2b-notification-patterns.md
- /tmp/ai-research-command-state-indicators.md (command state patterns across terminals)
- /tmp/ai-brainstorm-phase2b-sidebar.md
- /tmp/ai-debate-phase2b-sidebar.md
- /tmp/ai-research-ghostty-osc-handling.md
- /tmp/ai-research-sidebar-patterns.md
- /tmp/ai-research-terminal-ui-ux-patterns.md
