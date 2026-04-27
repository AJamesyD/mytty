# Ambient Identity and Session Source Protocol (v4, final)

Mytty macOS terminal emulator, libghostty backend.

**Status:** Proposed

**Goal:** Give every Mytty-spawned shell a discoverable identity via environment variables (Layer 1), then let users configure external commands as pluggable session sources for the picker (Layer 2).

**Date:** 2026-04-21

**Research:** (ephemeral, not persisted)
**Related:** [Phase 3a: Socket API](phase3a-socket-api.md) (transport layer for the IPC socket)

---

## 1. Overview

Two layers, shipped independently:

- **Layer 1 (Ambient Identity):** Environment variables injected into every shell Mytty spawns. Scripts, prompts, and `mytty-cli` can detect they are running inside Mytty and address specific sessions, tabs, and panes.
- **Layer 2 (Session Source Protocol):** A TOML config format for registering external commands that produce session candidates for the picker. Sources run as child processes, output JSON or plain text, and feed into the existing picker with deduplication and priority ordering.

Layer 1 ships first. It unblocks Layer 2, third-party shell integrations, and `mytty-cli` workflows that need to know their context.

## 2. Layer 1: Ambient Identity

### 2.1 Environment Variables

Every shell spawned by Mytty MUST inherit these variables:

| Variable | Value | Example |
|----------|-------|---------|
| `MYTTY` | `1` | `1` |
| `MYTTY_VERSION` | Mytty version string | `0.4.0` |
| `MYTTY_SOCKET` | Unix domain socket path for `mytty-cli` | `/tmp/mytty-<uid>/mytty.sock` |
| `MYTTY_SESSION_ID` | Numeric session ID | `1` |
| `MYTTY_SESSION_NAME` | Session name at spawn time | `Dev` |
| `MYTTY_TAB_ID` | Numeric tab ID | `2` |
| `MYTTY_PANE_ID` | Numeric pane ID | `3` |

`MYTTY_SESSION_NAME` reflects the name at the time the shell was spawned. If the user renames the session later, the env var in existing shells retains the old value. This matches how `TERM_PROGRAM` works: set once at spawn, not live-updated.

**Socket directory permissions.** The socket directory (`/tmp/mytty-<uid>/`) MUST be created with mode 0700 and the socket file with mode 0600. This matches the existing behavior in IPCListener.swift. No other user on the system can connect to the socket.

**Schema versioning.** New fields added to this table in future versions MUST be optional. No schema version field is needed.

### 2.2 TERM_PROGRAM

Mytty overrides `TERM_PROGRAM` to `mytty`. The existing code in `TerminalSurfaceView.swift` already sets `TERM_PROGRAM=mytty` via `ghostty_env_var_s`.

Rationale: Mytty is a distinct terminal from Ghostty. Tools like starship, fish, and neovim use `TERM_PROGRAM` for terminal detection. These tools SHOULD detect `mytty`, not `ghostty`. Ghostty-specific terminal capabilities (kitty graphics protocol, etc.) are provided by libghostty regardless of the `TERM_PROGRAM` value; they depend on `TERM` and terminfo, not `TERM_PROGRAM`.

Scripts that need to detect Mytty specifically SHOULD check `TERM_PROGRAM=mytty` or `MYTTY=1`. Scripts that need to detect Ghostty-compatible terminal features SHOULD check `TERM` or query terminal capabilities directly.

### 2.3 Implementation

The injection site is `TerminalSurfaceView.swift`. The existing code builds an array of `ghostty_env_var_s` structs and passes them to `ghostty_surface_new` via `cfg.env_vars` and `cfg.env_var_count`.

Currently, two variables are set this way: `MYTTY_SOCKET` and `TERM_PROGRAM`. Layer 1 adds the remaining variables (`MYTTY`, `MYTTY_VERSION`, `MYTTY_SESSION_ID`, `MYTTY_SESSION_NAME`, `MYTTY_TAB_ID`, `MYTTY_PANE_ID`) to the same array.

The IDs come from the owning `MyttySession`, `MyttyTab`, and `MyttyPane` objects, which are available at surface creation time. `MYTTY_VERSION` comes from the app bundle version. `MYTTY_SOCKET` comes from `MyttyIPC.socketPath` (already used in the existing code).

### 2.4 Detection Patterns

Shell script:
```sh
if [ -n "$MYTTY" ]; then
    mytty-cli pane.focus --id "$MYTTY_PANE_ID"
fi
```

Fish:
```fish
if set -q MYTTY
    mytty-cli session.rename --id $MYTTY_SESSION_ID --name (basename $PWD)
end
```

## 3. Layer 2: Session Source Protocol

### 3.1 Config Syntax

**Security note.** Source commands execute with the user's full privileges. A command in `config.toml` has the same access as any command the user runs in their terminal. Mytty does not sandbox source processes.

Sources are defined as `[[session-source]]` tables in `~/.config/mytty/config.toml`:

```toml
[[session-source]]
name = "projects"
command = "find ~/projects -maxdepth 1 -type d"
action = "create-session"

[[session-source]]
name = "zoxide"
command = "zoxide query -l"
action = "create-session"
priority = 3
timeout-ms = 1000
```

The `[[session-source]]` syntax uses TOML's array-of-tables. MyttyConfig.swift already parses `[[popup]]` via `table["popup"]?.array` using TOMLKit. Session sources follow the same pattern: `table["session-source"]?.array`, iterating each entry's `.table` to extract fields. No parser changes needed.

Built-in sources (running sessions, SSH hosts, zoxide directories) cannot be disabled in v1. Disabling built-in sources is Phase 2.

### 3.2 Fields

| Field | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `name` | Yes | String | | Display name for the source, shown in `mytty-cli source list` |
| `command` | Yes | String | | Shell command to execute. Passed to `/bin/sh -c`. Empty or whitespace-only commands are rejected at config load with a warning |
| `action` | Yes | String | | What happens when the user selects an item. See section 3.6 |
| `priority` | No | Integer | `5` | Lower number = higher priority. Controls dedup winner and sort tiebreaking. MUST be >= 1 for user sources. Priority 0 is reserved for built-in sources. Sources with `priority < 1` are rejected at config load with a warning |
| `timeout-ms` | No | Integer | `2000` | Maximum time in milliseconds to wait for the command to produce output |
| `max-items` | No | Integer | `200` | Maximum number of items to accept from this source. Items beyond this limit are silently dropped |

**Config validation at load time:** Sources missing `name`, `command`, or `action` MUST be skipped with a warning. Sources with an invalid `action` value MUST be skipped with a warning. Sources with empty/whitespace-only `command` MUST be skipped with a warning. Sources with `priority < 1` MUST be rejected with a warning.

### 3.3 Command Execution

All sources run when the picker opens. Sources do not run on app launch or config load.

1. The command runs as a child process via `/bin/sh -c "<command>"`.
2. Working directory is the CWD of the pane that opened the picker. Falls back to the user's home directory if the pane has not reported a CWD.
3. The caller passes the CWD to SessionSourceRunner. The runner does not query the model for CWD.
4. The process inherits all `MYTTY_*` environment variables from section 2.1.
5. `MYTTY_QUERY` is set to the current picker filter text (empty string on initial open).
6. The command string is static. Mytty MUST NOT perform shell interpolation of `MYTTY_QUERY` into the command string. The query is available only as an environment variable. This prevents injection attacks where a user's typed text is interpreted as shell syntax.
7. stdout is captured. stderr is discarded (but logged for diagnostics).
8. If the process exceeds `timeout-ms`, it is terminated with SIGTERM. After 500ms, if the process is still alive, it is killed with SIGKILL (via `kill(pid, SIGKILL)`, since `Process.terminate()` sends SIGTERM only). Partial stdout collected before the timeout is parsed. See section 5.
9. Items are accepted up to the `max-items` limit. Items beyond the limit are dropped.
10. **stdout cap:** Mytty reads at most 1 MB from stdout. Output beyond this limit is truncated. Partial output up to the cap is parsed.

### 3.4 Output Parsing

Mytty accepts two output formats. It tries JSON first, then falls back to plain text.

**Parse order:**
1. Try `JSONDecoder` on the full stdout as a JSON array.
2. If that fails, split stdout by newlines and try decoding each line as a JSON object (JSON Lines format).
3. If that fails, try decoding the full stdout as a single JSON object (produces one item).
4. If all JSON attempts fail, treat each non-empty line as plain text.

**JSON format:** Each item has this shape:

```json
{
    "name": "my-project",
    "path": "/Users/me/projects/my-project",
    "subtitle": "~/projects/my-project",
    "dedup_key": "/Users/me/projects/my-project"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name in the picker |
| `path` | No | Directory path. Used as `dedup_key` default and as the session working directory for `create-session`. Falls back to the user's home directory if absent |
| `subtitle` | No | Secondary text shown below the name |
| `dedup_key` | No | Deduplication key. Defaults to `path` if present, otherwise `name` |

Unknown fields in JSON items MUST be ignored. This allows source scripts to include extra metadata without breaking parsing.

**Plain text format:** Each non-empty line is treated as a potential path. If the line starts with `/` or `~`, the item name is derived from the basename and the full path is used as `dedup_key`. Lines that are not paths use the full line as both `name` and `dedup_key`.

```
/Users/me/projects/alpha
/Users/me/projects/beta
/Users/me/projects/gamma
```

### 3.5 JSON Output Example

A source script that outputs JSON:

```sh
#!/bin/sh
# List git repos with metadata
find ~/projects -maxdepth 2 -name .git -type d | while read gitdir; do
    dir=$(dirname "$gitdir")
    name=$(basename "$dir")
    echo "{\"name\":\"$name\",\"path\":\"$dir\"}"
done
```

### 3.6 Actions

The `action` field determines what happens when the user selects an item from this source.

| Action | Behavior |
|--------|----------|
| `create-session` | Create a new session. Uses the item's `path` as the working directory (falls back to home directory if absent) and `name` as the session name |
| `focus-session` | Focus an existing session by name. Exact case-sensitive match. If zero sessions match, no-op with a warning logged. If multiple sessions match, focus the first |

Actions map to existing IPC methods: `create-session` maps to `session.create`, `focus-session` maps to `session.focus`. This keeps the CLI and GUI as peers (tenet 4).

The picker's action handler MUST call the same model methods that IPCService uses (which include `broker.publish`), so CLI subscribers see the mutation. The picker MUST NOT bypass the model layer or use a separate code path.

### 3.7 Picker Integration

The existing picker uses a `SessionManagerItem` enum with cases for running sessions, directories, SSH hosts, and new-session creation. Source items integrate via a new enum case:

```swift
case sourceItem(MyttySessionSourceItem, source: MyttySessionSource)
```

The `confirmSelection` method's switch statement gets a new case for `.sourceItem` that dispatches based on the source's `action` field:

- `create-session`: calls the same session creation path as `.directory` and `.newSession`.
- `focus-session`: calls the same session focus path as `.runningSession`.

This is the minimal change. Replacing the enum with a protocol is a larger refactor deferred to Phase 2.

`SessionManagerViewModel` gains a reference to the source runner. When the picker opens, it starts all configured sources concurrently alongside the existing built-in item collection. Source results are merged into `allItems` as they arrive, triggering re-filtering and re-rendering.

**Built-in source priorities:**

| Source | Priority | Notes |
|--------|----------|-------|
| Running sessions | 0 | Always highest priority |
| SSH hosts | 8 | From `~/.ssh/config` |
| Zoxide directories | 10 | From `zoxide query -l` |
| User-configured sources | 5 (default) | Configurable via `priority` field |

### 3.8 Deduplication

The picker merger handles deduplication across all sources (including built-in sources).

- Each item has a `dedup_key` (see section 3.4).
- When two items share the same `dedup_key`, the item from the higher-priority source wins (lower `priority` number).
- When two items share the same `dedup_key` and the same priority, the item from the source that appears first in config order wins.
- Priority 0 is reserved for running sessions (the built-in source). User-configured sources MUST use priority >= 1.
- Dedup by `dedup_key`, not by `name`. Two sources MAY produce items with the same name but different paths (e.g., `~/work/api` and `~/personal/api`). These are distinct items.

### 3.9 Picker Behavior

The picker snapshots the configured sources at open time. If config changes while the picker is closed, the next open picks up the new config.

The picker MUST NOT be opened from copy mode or window mode. The modal key handler consumes the key before it reaches the picker keybinding.

The picker keybinding SHOULD NOT use the `unconsumed:` prefix, so it remains accessible during passthrough processes.

Sources run concurrently when the picker opens. The picker displays results as they arrive:

1. Fast sources (in-memory running sessions, quick commands) appear immediately.
2. Slow sources append their results when they complete. The picker re-sorts and re-renders.
3. The user's current selection MUST NOT jump when late-arriving source results are merged.
4. Sources that exceed their `timeout-ms` are killed (SIGTERM, then SIGKILL after 500ms). Partial output collected before the timeout is parsed. See section 5.
5. Source errors (non-zero exit, parse failures) are not shown in the picker. They are visible via `mytty-cli source list`, which reports each source's last status.

When the picker is dismissed (selection or cancellation), all still-running source processes MUST be killed (SIGTERM, then SIGKILL after 500ms).

### 3.10 Config Example

A complete config with multiple sources:

```toml
# ~/.config/mytty/config.toml

[[session-source]]
name = "projects"
command = "find ~/projects -maxdepth 1 -type d"
action = "create-session"
priority = 3

[[session-source]]
name = "zoxide"
command = "zoxide query -l | head -50"
action = "create-session"
priority = 5
timeout-ms = 1000
```

## 4. IPC

### 4.1 source.list

Returns the list of configured sources with their current status.

Request:
```json
{"jsonrpc": "2.0", "method": "source.list", "id": 1}
```

Response:
```json
{
    "jsonrpc": "2.0",
    "result": [
        {
            "name": "projects",
            "command": "find ~/projects -maxdepth 1 -type d",
            "action": "create-session",
            "priority": 3,
            "timeout_ms": 2000,
            "max_items": 200,
            "last_status": "ok"
        },
        {
            "name": "zoxide",
            "command": "zoxide query -l | head -50",
            "action": "create-session",
            "priority": 5,
            "timeout_ms": 1000,
            "max_items": 200,
            "last_status": "timeout"
        }
    ],
    "id": 1
}
```

The `last_status` field is one of: `ok`, `timeout`, `error`, `not-run`. It reflects the most recent execution. New sources start as `not-run`.

**Hot-reload:** Config hot-reload of sources does NOT publish a `source.changed` event. The picker snapshots sources at open time. `source.list` always reflects the current config.

### 4.2 CLI Introspection

```sh
$ mytty-cli source list
NAME          STATUS    PRIORITY
projects      ok        3
zoxide        timeout   5
```

The `--json` flag produces machine-readable output matching the `source.list` JSON-RPC response, consistent with other list commands.

```sh
$ mytty-cli source list --json
```

### 4.3 Three-File Sync

Per the IPC rules, `source.list` requires additions to:

1. `MyttyShared/MyttyServiceProtocol.swift` (protocol declaration: `listSources`)
2. `Mytty/Services/IPCService.swift` (implementation: `listSources`)
3. `Mytty/Services/IPCListener.swift` (dispatch case: `"source.list"` calls `listSources`)

The CLI command goes in `MyttyCLI/Commands/SourceCommand.swift`.

## 5. Error Handling

| Condition | Behavior |
|-----------|----------|
| Command not found | `last_status = "error"`. Logged. No picker items from this source |
| Command exits non-zero | `last_status = "error"`. Logged. Partial stdout is still parsed (some commands write valid output before failing) |
| Command exceeds timeout | `last_status = "timeout"`. Process terminated with SIGTERM, then SIGKILL after 500ms via `kill(pid, SIGKILL)`. Partial stdout collected before the timeout is parsed |
| Command exceeds 1 MB stdout | Output truncated at 1 MB. Partial output up to the cap is parsed. `last_status = "error"` |
| JSON parse failure | Fall back to plain text parsing per the parse order in section 3.4. If all attempts fail, `last_status = "error"` |
| Empty output | Zero items from this source. `last_status = "ok"` (empty output is not an error) |
| Config: missing name/command/action | Source is skipped at config load time. Warning logged |
| Config: invalid action value | Source is skipped at config load time. Warning logged |
| Config: empty/whitespace-only command | Source is skipped at config load time. Warning logged |
| Config: priority < 1 | Source is rejected at config load time. Warning logged |
| Items exceed max-items | Items beyond the limit are silently dropped |

## 6. Footguns

**MYTTY_QUERY injection.** The query text is passed as an environment variable, not interpolated into the command string. A command like `grep "$MYTTY_QUERY"` is safe because the shell expands the variable at runtime without Mytty performing substitution. If a source script uses `eval` or unquoted expansion (e.g., `grep $MYTTY_QUERY` without quotes), that is the script author's bug, not Mytty's.

**MYTTY_SESSION_NAME is a snapshot.** The env var reflects the session name at shell spawn time. Renaming a session does not update the variable in existing shells. Scripts that need the current name SHOULD call `mytty-cli session get --id $MYTTY_SESSION_ID`.

**MYTTY_SOCKET is a snapshot.** Like `MYTTY_SESSION_NAME`, the socket path is set at shell spawn time. If Mytty restarts and creates a new socket, existing shells retain the old (now invalid) path. Scripts SHOULD handle connection failures gracefully.

**Dedup by path, not name.** Two directories named `api` in different parent directories are distinct items. The `dedup_key` defaults to `path`, which is the correct dedup dimension. Sources that produce non-path items SHOULD set `dedup_key` explicitly.

**Source commands run with user permissions.** Mytty does not sandbox or elevate source commands. They run as the user's shell, with the user's PATH and permissions. A malicious command in `config.toml` has the same access as any command the user runs in their terminal.

**Source scripts SHOULD NOT call mutating IPC methods.** A source script that calls `mytty-cli session.create` or similar during execution produces confusing UX (sessions appearing mid-pick). Mytty does not enforce this; it is a convention. Source scripts SHOULD only produce output, not change state.

## 7. Sequencing

| Layer | Ships | Unblocks |
|-------|-------|----------|
| Layer 1 (Ambient Identity) | First | Layer 2, third-party shell integrations, `mytty-cli` context-aware scripts |
| Layer 2 (Session Sources) | Second | Pluggable picker, external tool integration |

Hints mode and mouse bridge are independent tracks. Neither blocks or is blocked by this spec.

## 8. Non-Goals

| Feature | Reason | When |
|---------|--------|------|
| On-query refresh mode (re-run source on each keystroke) | No built-in or known source needs it yet. Adds debounce, kill-before-restart, and concurrent overlap complexity | Add when a real source needs it |
| `connect-or-create` action | Combines focus and create in one action. Can be composed from `focus-session` + `create-session` by the user | Add when the composition proves too awkward |
| Icon field on source items | The picker does not render source-specific icons in v1 | Add when the picker renders source-specific icons |
| Directory-based source registration (`sources.d/`) | No directory-based config exists in Mytty yet. Premature for one feature | Phase 2, when third-party tools need to register sources without editing user config |
| Inline command sugar (`session-sources = ["cmd"]`) | Tables are more honest about behavior | Phase 2, if users request lower friction |
| `.custom(method, params)` action escape hatch | Start with the known action set | When needed (likely when Ghostty tmux control mode lands) |
| Live-updating `MYTTY_SESSION_NAME` | Updating env vars in a running shell is not possible without shell cooperation. The cost exceeds the benefit | Not planned |
| Source-level dedup | External commands cannot know what other sources produced. Merger-level dedup is simpler and sufficient | Not planned |
| Caching / stale-while-revalidate | Useful for slow sources. Adds complexity around cache invalidation | Phase 2, when real-world usage shows which sources are too slow |
| Preview command | fzf-style preview pane for source items. Requires a rendering surface in the picker | Phase 2 |
| Source-switching keybinding | fzf+sesh pattern for cycling between source groups in the picker. Requires picker UI changes | Phase 2 |
| `MYTTY_PANE_CWD` env var | Scripts can already get the CWD via the process table or `mytty-cli`. Adding another env var that goes stale on `cd` creates confusion | Not planned |
| Disabling built-in sources | Built-in sources always run in v1. Disabling requires a naming/identity scheme for built-ins | Phase 2 |
| `create-layout` action | Declarative layout creation from a source item. Pairs with Phase 5e (layout presets) | Phase 2 |

## 9. Concurrency: SessionSourceRunner

SessionSourceRunner is **nonisolated** (not `@MainActor`). It spawns `Process` instances on background tasks, captures stdout, parses output, and enforces timeouts and the 1 MB stdout cap.

Results are delivered back to `@MainActor` via async return values or `Task { @MainActor in }`. This follows the same pattern as IPCListener, which performs socket I/O on a dedicated queue and dispatches results to the main actor.

The runner does not hold references to model objects. The caller passes CWD and environment variables as parameters. The runner returns parsed items; the caller (on `@MainActor`) updates the picker model.

**Implementation note:** `Process.terminate()` sends SIGTERM. For the SIGKILL escalation after 500ms, use `kill(process.processIdentifier, SIGKILL)` directly.

## 10. Files

### Layer 1

| File | Changes |
|------|---------|
| `Mytty/Views/Terminal/TerminalSurfaceView.swift` | Add `MYTTY`, `MYTTY_VERSION`, `MYTTY_SESSION_ID`, `MYTTY_SESSION_NAME`, `MYTTY_TAB_ID`, `MYTTY_PANE_ID` to the existing `ghostty_env_var_s` array passed to `ghostty_surface_new` |

### Layer 2

| File | Purpose |
|------|---------|
| `Mytty/Config/MyttyConfig.swift` | Parse `[[session-source]]` tables via `table["session-source"]?.array` |
| `Mytty/Models/MyttySessionSource.swift` | `MyttySessionSource`: Sendable struct (not @Observable). Fields: name, command, action, priority, timeout, max-items, last_status |
| `Mytty/Models/MyttySessionSourceItem.swift` | `MyttySessionSourceItem`: Sendable struct. Fields: name, path, subtitle, dedup_key |
| `Mytty/Services/SessionSourceRunner.swift` | Nonisolated. Execute source commands, parse output, enforce timeouts, SIGTERM/SIGKILL escalation, 1 MB stdout cap |
| `Mytty/Views/SessionManager/SessionManagerViewModel.swift` | Add `.sourceItem` case to `SessionManagerItem`. Start source runner on picker open. Merge source results into `allItems` |
| `MyttyShared/MyttyServiceProtocol.swift` | Add `listSources` method |
| `Mytty/Services/IPCService.swift` | Implement `listSources` |
| `Mytty/Services/IPCListener.swift` | Add `source.list` dispatch case |
| `MyttyCLI/Commands/SourceCommand.swift` | `mytty-cli source list` and `mytty-cli source list --json` commands |
| `MyttyTests/Services/SessionSourceRunnerTests.swift` | Unit tests for command execution, output parsing, timeout handling, stdout cap |

## 11. Acceptance Criteria

### Layer 1

1. A shell spawned by Mytty has `MYTTY=1` in its environment.
2. `MYTTY_VERSION` matches the app bundle version.
3. `MYTTY_SOCKET` points to the active IPC socket.
4. `MYTTY_SESSION_ID`, `MYTTY_TAB_ID`, and `MYTTY_PANE_ID` match the owning objects.
5. `MYTTY_SESSION_NAME` reflects the session name at spawn time.
6. `TERM_PROGRAM` is set to `mytty`.
7. Splitting a pane produces a new shell with the new pane's `MYTTY_PANE_ID`.

### Layer 2

1. A `[[session-source]]` table in config registers a source visible in `mytty-cli source list`.
2. Opening the picker runs all configured sources concurrently.
3. Source items appear in the picker, merged with built-in items.
4. Selecting a `create-session` item creates a session in the item's directory.
5. Selecting a `focus-session` item focuses the named session (exact case-sensitive match).
6. Duplicate items (same `dedup_key`) show only the highest-priority source's version.
7. Sources that exceed `timeout-ms` are killed. Partial output is parsed.
8. `mytty-cli source list` shows each source's name, status, and priority.
9. `mytty-cli source list --json` produces machine-readable output.
10. JSON array, JSON Lines, single JSON object, and plain text output formats all parse correctly.
11. `MYTTY_QUERY` is set in the source command's environment.
12. The command string is not modified based on the query (no interpolation).
13. The user's selection does not jump when late-arriving source results are merged.
14. Sources with `priority < 1` are rejected at config load.
15. Items beyond `max-items` are dropped.
16. All running source processes are killed when the picker is dismissed.
17. Output beyond 1 MB is truncated. Partial output is parsed.
18. The picker's action handler uses the same model methods as IPCService.
