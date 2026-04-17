# ADR-007: Ghostty Submodule Upgrade Policy

Status: accepted
Date: 2026-04-17

## Context

Mistty vendors Ghostty as a git submodule at `vendor/ghostty/`, currently
pinned to v1.3.1 (commit 332b2ae). Research on 2026-04-17 found 679 commits
on upstream main since that tag, with no new tagged release yet (in-tree
version is 1.3.2-dev). Analysis performed 2026-04-17 via `git log`/`git diff` on the vendored submodule.

Key finding: `ghostty_surface_free_text` has a parameter mismatch bug at
v1.3.1 that causes a memory leak on every call. Mistty has 5 call sites
(CopyModeManager, PaneView, IPCService). Fixed upstream in commit 4803d58bb.

## Decision

Pin to tagged releases when available. Between tags, pin to a specific
commit only when a bug directly affects Mistty (like the free_text leak).

### When to upgrade

- **Immediately:** when a tagged release (v1.3.2, v1.4.0) appears.
  Watch: `https://github.com/ghostty-org/ghostty/releases`
- **Soon (before next Mistty release):** pin to a main commit after
  4803d58bb to fix the memory leak, if v1.3.2 hasn't shipped by then.
- **Evaluate:** when Mistty needs new libghostty APIs (kitty graphics
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
3. Run `mistty-cli pane active` (exercises IPC text reads).
4. Split panes, navigate between them (exercises surface creation/focus).
5. If Instruments is available, run Leaks on the copy mode flow.

Commit the submodule pointer update as a standalone commit:
`build(deps): update ghostty submodule to <version>`.

### What to watch for in future upgrades

- **libc++ removal** (commit 43a05dc96): simplifies linking, may require
  build config changes. Already landed on main.
- **GHOSTTY_API visibility macros**: no-op for static linking, but if
  Mistty ever switches to dynamic linking, these matter.
- **New libghostty-vt API**: a standalone terminal emulation library.
  Not relevant to Mistty's embedded apprt usage, but could enable
  features like terminal preview thumbnails in the session manager.
- **Kitty graphics API**: new C functions for kitty image protocol.
  Relevant if Mistty wants to expose image state through IPC.
- **Surface unique IDs**: new `ghostty_surface_id` API. Could replace
  Mistty's internal pane ID generation.

## Consequences

- Mistty stays on stable releases by default, reducing risk from
  upstream churn.
- The memory leak is a known issue until the upgrade happens.
- The upgrade checklist lives here, not in someone's head.
