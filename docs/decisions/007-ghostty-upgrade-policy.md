# ADR-007: Ghostty Submodule Upgrade Policy

Status: accepted
Date: 2026-04-17

## Context

Mytty vendors Ghostty as a git submodule at `vendor/ghostty/`, currently
pinned to commit 563b085a4 (2026-05-04, upstream main). Previous pin was
v1.3.1 (332b2ae). No v1.3.2 tag exists yet (in-tree version is 1.3.2-dev).

Key fixes obtained in this pin:
- `4803d58bb`: `ghostty_surface_free_text` parameter mismatch causing a
  memory leak on every call. Mytty has 5 call sites (CopyModeManager,
  PaneView, IPCService).
- `563b085a4`: zero-width grapheme attachment during pending wrap
  (rendering correctness).
- `43a05dc96`: libc++ dependency removal (smaller binary, simpler linking).

## Decision

Pin to tagged releases when available. Between tags, pin to a specific
commit only when a bug directly affects Mytty (like the free_text leak).

### When to upgrade

- **Immediately:** when a tagged release (v1.3.2, v1.4.0) appears.
  Watch: `https://github.com/ghostty-org/ghostty/releases`
- **Soon (before next Mytty release):** pin to a main commit after
  4803d58bb to fix the memory leak, if v1.3.2 hasn't shipped by then.
- **Evaluate:** when Mytty needs new libghostty APIs (kitty graphics
  passthrough, hyperlink URI access, default color queries).

### How to upgrade

```bash
cd vendor/ghostty
git fetch origin --tags
git checkout v1.3.2          # or specific commit hash
cd ../..
just build-libghostty        # rebuild with nix devshell
just build                   # verify Swift build
just test                    # verify tests pass
```

Then verify manually:
1. Open a session, type text, close panes (exercises surface lifecycle).
2. Enter copy mode, select text, yank (exercises `ghostty_surface_text`
   and `ghostty_surface_free_text`, the leak fix).
3. Run `mytty-cli pane active` (exercises IPC text reads).
4. Split panes, navigate between them (exercises surface creation/focus).
5. If Instruments is available, run Leaks on the copy mode flow.

Commit the submodule pointer update as a standalone commit:
`build(deps): update ghostty submodule to <version>`.

### What to watch for in future upgrades

- **`ghostty_app_key_is_binding` removed** (commit 7c91cef28): replaced
  by `ghostty_config_key_is_binding`. Mytty doesn't call either, but if
  a future feature needs app-level binding checks, use the config variant.
- **`ghostty_input_trigger_key_u.translated` removed** (commit 971753074):
  Mytty doesn't use this field. No action needed.
- **New libghostty-vt API**: a standalone terminal emulation library.
  Not relevant to Mytty's embedded apprt usage, but could enable
  features like terminal preview thumbnails in the session manager.
- **Kitty graphics API**: new C functions for kitty image protocol.
  Relevant if Mytty wants to expose image state through IPC.
- **Surface unique IDs**: new `ghostty_surface_id` API. Could replace
  Mytty's internal pane ID generation.

## Consequences

- Mytty stays on stable releases by default, reducing risk from
  upstream churn.
- The memory leak fix is included as of 563b085a4 (2026-05-05 upgrade).
- The upgrade checklist lives here, not in someone's head.

## Upgrade Log

| Date | From | To | Reason |
|------|------|----|--------|
| 2026-05-05 | v1.3.1 (332b2aefc) | 563b085a4 | Memory leak fix (4803d58bb), grapheme rendering fix, libc++ removal. No API breakage. |
