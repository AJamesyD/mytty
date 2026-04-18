# Sidebar Visual Rework Spec

Created: 2026-04-14
Status: Implemented (Phase 1b)
Prior art: /tmp/ai-research-sidebar-patterns.md

## Goal

Replace the current plain `List` + `DisclosureGroup` sidebar with a visually structured
session/tab hierarchy. No new features (metadata, git branch, etc. are Phase 2). This is
purely visual: better spacing, clearer hierarchy, active state indicators, pane count hints.

## Current state

`SidebarView.swift` (~80 lines): SwiftUI `List` with `.listStyle(.sidebar)`. Each session
is a `DisclosureGroup` with a text label. Tabs are indented `HStack` rows with text + bell
dot. Active session gets semibold + `.primary` color. That's it.

## What changes

### Session header row

- Left accent bar: 3px wide, accent-colored, on the active session only.
  Inactive sessions: no accent bar.
- Session name: 13px system font, semibold when active, regular when inactive.
  (Keeps current behavior.)
- Tab count badge: small pill to the right of the session name showing tab count
  (e.g., "3"). Muted text, monospace, only shown when session is collapsed OR has 2+ tabs.
- Collapse chevron: use the system `DisclosureGroup` chevron (current behavior).
  If we move away from `DisclosureGroup` to a custom view, use `chevron.right` SF Symbol
  with rotation animation.
- Spacing between sessions: 8px vertical gap. No divider lines.

### Tab rows

- Indentation: 12px from session header (increase from current 8px).
- Height: ~28px (current is roughly this with padding).
- Content: bell dot (if active) + tab title. Close button on hover only (not yet,
  this is a future interaction improvement).
- Active tab (the tab containing the focused terminal): subtle background fill
  using `MyttyTheme.selectedRowBackground`. No left accent bar on tabs (only sessions
  get the accent bar, to avoid visual clutter).
- Inactive tabs: no background, text at `.secondary` opacity. (Current behavior.)
- Pane count indicator: when a tab has 2+ panes, show a small "⫽ N" indicator
  after the tab title in muted monospace. This is informational only (no expand/collapse
  of panes in the sidebar for now).

### Theme tokens needed

New tokens to add to `MyttyTheme.swift`:

| Token | Value | Purpose |
|---|---|---|
| `sessionAccent` | `Color.accentColor` | Active session left bar |
| `tabCountBadge` | `Color.secondary.opacity(0.6)` | Tab count pill text |

Everything else uses existing tokens: `selectedRowBackground`, `bellIndicator`,
`.primary`, `.secondary`.

### What stays the same

- Drag handle (right edge resize): unchanged.
- `List` with `.listStyle(.sidebar)`: keep for now. The system list style gives us
  correct sidebar background color, scroll behavior, and accessibility. Moving to a
  fully custom `ScrollView` is a future option if `List` becomes limiting.
- Session tap to activate: unchanged.
- Tab tap to activate: unchanged.
- Bell indicator: unchanged (already uses `MyttyTheme.bellIndicator`).

## What we're NOT doing

- Session colors (user-assignable per session): Phase 2 or later. Requires config system.
  For now, the accent bar uses the system accent color.
- Pane sub-rows (expandable pane list under tabs): deferred. The pane count indicator
  is enough for now. Expanding panes in the sidebar adds complexity and the sidebar
  would get tall fast with many splits.
- Hover actions (close button, add tab button on session header): future polish.
- Drag-and-drop reordering: separate roadmap item.
- Session metadata (git branch, working directory, ports): Phase 2.
- Connector lines between levels: research says these add noise. Indentation is enough.

## Implementation approach

### Option A: Stay with DisclosureGroup (recommended)

Keep `DisclosureGroup` for collapse/expand. Add the accent bar as an `.overlay` on the
session label. Add the tab count badge inline. Add pane count to tab rows.

Pros: minimal change, system animations, accessibility built-in.
Cons: limited control over spacing between sessions (List manages spacing).

### Option B: Custom ScrollView + manual expand/collapse

Replace `List` with `ScrollView` + `LazyVStack`. Full control over spacing, backgrounds,
animations.

Pros: full visual control, can do 8px session gaps precisely.
Cons: lose system sidebar background, scroll indicators, accessibility traits.
Need to reimplement keyboard navigation.

**Recommendation: Option A.** The visual improvements are achievable within `List` +
`DisclosureGroup`. The 8px session gap can be approximated with `.padding(.top, 8)` on
session rows. If `List` becomes limiting during implementation, we can revisit, but
starting with the simpler approach follows Gall's Law.

## Verification

- `just build` passes.
- Visual check: active session has accent bar, tab count shows, pane count shows on
  multi-pane tabs, spacing between sessions is visible.
- No behavior change: all tap targets work as before, collapse/expand works.

## Files to modify

1. `Mytty/App/MyttyTheme.swift` (add 2 tokens)
2. `Mytty/Views/Sidebar/SidebarView.swift` (rework `SessionRowView` and tab rows)

## Open questions

1. Should the tab count badge be visible when the session is expanded? The research
   suggests "only when collapsed" (Chrome pattern), but showing it always gives a
   quick count without scanning. Leaning toward: show when collapsed or when 2+ tabs.
2. The pane count indicator ("⫽ 2"): is the "⫽" character (U+2AEB) readable at 11px?
   Alternative: use an SF Symbol like `rectangle.split.2x1` scaled down. Need to test.
