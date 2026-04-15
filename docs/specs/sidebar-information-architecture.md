# Mistty Sidebar Information Architecture

Research date: 2026-04-15
Context: Mapping all information channels to visual elements for sidebar and tab bar.

## Part 1: Information Channels (What We Need to Encode)

### Session Row

| Channel | Type | Priority | When visible |
|---------|------|----------|-------------|
| Session name | Identity | Always | Always |
| Active session | Focus state | High | One session at a time |
| Tab count | Structural | Low | Always (or when >1) |
| Notification rollup count | Attention | High | When collapsed + notifications exist |
| Notification severity | Attention | High | When collapsed + notifications exist |
| Git branch + dirty | Metadata | Medium | Phase 2b-2, when git repo detected |
| Working directory | Metadata | Low | Phase 2b-2, always |
| Collapsed/expanded | Structural | Low | Always (disclosure triangle) |

### Tab Row (Sidebar)

| Channel | Type | Priority | When visible |
|---------|------|----------|-------------|
| Tab name (process title) | Identity | Always | Always |
| Active tab | Focus state | High | One tab per session |
| Bell notification | Attention | High | Background tab received bell |
| Command failed | Attention | Highest | Background tab had non-zero exit |
| Pane count | Structural | Low | When >1 pane |
| Command result + duration | Status | Medium | Phase 2b-3, after command finishes |

### Tab Bar Item

| Channel | Type | Priority | When visible |
|---------|------|----------|-------------|
| Tab name | Identity | Always | Always |
| Active tab | Focus state | High | One tab at a time |
| Bell notification | Attention | High | Background tab received bell |
| Command failed | Attention | Highest | Background tab had non-zero exit |
| Close button | Action | Low | On hover or active |

## Part 2: Available Visual Elements

From the research, these are the visual encoding channels available on a single row:

| Visual element | What it encodes well | Coexistence | macOS precedent |
|----------------|---------------------|-------------|-----------------|
| Background highlight | Selection/focus (identity) | Independent of everything | Universal (Mail, Finder, Xcode) |
| Left-edge accent bar | Priority or active state | Conflicts with identity if same element | Linear, cmux, Discord (pill) |
| Leading dot (small, colored) | Unread/attention state | Coexists with background + text | Mail, Messages, Discord |
| Leading icon (SF Symbol) | Type or severity | Coexists with background | Xcode, System Settings, Reminders |
| Text weight (bold/semibold) | Unread/active state | Coexists with color + background | Slack, Discord |
| Text color | VCS status or severity | Conflicts with other text color uses | JetBrains, VS Code |
| Text opacity | Muted/inactive state | Coexists with everything | Slack, Figma, cmux |
| Trailing badge (pill) | Count | Coexists with everything | Mail, Reminders, Notes, System Settings |
| Trailing icon | Status or action | Coexists with badge | Xcode (git badge), Safari (audio) |
| Trailing text (muted) | Metadata | Coexists with badge | Timestamps, durations |
| Overlay on icon | Notification count | Coexists with icon | Discord, System Settings |
| Bottom/top border | Active state | Coexists with background | Safari tabs, Chrome tabs, browser pattern |
| Animation (pulse/spin) | Loading/activity | Highest salience, use sparingly | Safari, iTerm2, cmux |
| Hover-revealed elements | Secondary actions/info | Reduces clutter | Figma, Finder, Safari |

## Part 3: The Three-Channel Ceiling

Research finding: most apps successfully show 3 simultaneous channels per row.
4+ channels require progressive disclosure (hover) or separate views.

Mistty's sidebar tab row needs up to 5 channels simultaneously:
1. Active tab (focus)
2. Tab name (identity)
3. Notification state (attention)
4. Pane count (structural)
5. Command result + duration (status, Phase 2b-3)

This exceeds the 3-channel ceiling. We need to either:
- Use progressive disclosure (hover reveals command result)
- Merge channels (pane count into tab name template)
- Accept that some channels are lower-priority and can be subtle

## Part 4: Mapping Options

### Option A: "Mail/Messages" (dots lead, pills trail)

```
Session row:
  [blue accent bar] [session name] [semibold if active]  [tab count pill] [notification pill]

Tab row (sidebar):
  [●/○ dot] [tab name]  [pane indicator] [result icon + duration]
   red=bell, orange=fail, none=default
   
Tab bar:
  [tab name] [close]
   bottom border: blue=active, orange=fail, red=bell
```

Channels used per tab row: background (active) + dot (notification) + text (name) + trailing (pane count) = 4
The dot and background are independent. Dot is pre-attentive (color at fixed position).
Command result goes trailing right, only visible when present.

Pros: Familiar macOS pattern. Dot is pre-attentive. Identity and status are independent.
Cons: Dot + pane count + command result = busy right side. Dot may feel small.

### Option B: "Discord" (edge indicator + overlay badge)

```
Session row:
  [3px accent bar: blue=active, colored=notification] [session name]  [notification pill]
  The bar encodes the HIGHER priority of {active, notification}.
  When active AND has notification: notification color wins (you're already looking at it).
  When inactive AND no notification: no bar.

Tab row (sidebar):
  [2px accent bar: blue=active, orange=fail, red=bell] [tab name]  [pane indicator]

Tab bar:
  [tab name] [close]
   bottom border: same color logic
```

Channels used per tab row: accent bar (active OR notification) + text (name) + trailing (pane count) = 3
Clean, under the ceiling. But identity and status share the bar (the problem we already found).

Pros: Minimal, unified visual language. Under 3-channel ceiling.
Cons: Identity and status share the same element. We already tried this and it's confusing.

### Option C: "Slack" (text styling + trailing badge)

```
Session row:
  [blue accent bar] [session name: semibold if active, normal if not]  [notification pill]

Tab row (sidebar):
  [tab name: bold if notification, normal if not] [colored dot suffix] [pane indicator]
  Text color: orange if failed, red if bell, default otherwise.
  
Tab bar:
  [tab name: colored text if notification]  [close]
```

Channels used per tab row: background (active) + text weight (notification) + text color (severity) + trailing (pane count) = 4
Uses text styling instead of a separate element.

Pros: No extra UI elements. Very clean.
Cons: Text color for status conflicts with future uses (Phase 2b-2 git status could use text color). Subtle. Violates the "color budget" finding.

### Option D: "Xcode + Reminders" (icon vocabulary + independent identity)

```
Session row:
  [blue accent bar: active only] [session name]  [tab count pill] [notification pill]
  Bar is ONLY identity. Pill is ONLY status. Never mixed.

Tab row (sidebar):
  [background highlight if active] [6px glow dot if notification] [tab name]  [pane indicator]
  Dot: red glow = bell, orange glow = fail. No dot = no notification.
  Dot and active highlight coexist (you can see "active + failed").
  
Tab bar:
  [6px glow dot if notification] [tab name]  [close]
  Bottom border: blue if active (identity only).
  Dot: same colors as sidebar.
```

Channels used per tab row: background (active) + dot (notification) + text (name) + trailing (pane count) = 4
Identity and status are fully independent. Both can show simultaneously.

Pros: Clean separation of identity and status. Glow dot is pre-attentive and premium.
      Scales to Phase 2b-3 (command result goes trailing right, independent of dot).
      Session accent bar stays simple (blue = active, that's it).
Cons: 4 channels on tab row (above ceiling, but the dot is tiny and pre-attentive).

### Option E: "Linear + Mail hybrid" (edge for identity, dot for status, pill for count)

```
Session row:
  [3px blue accent bar: active only] [session name]  [notification pill when collapsed]
  When expanded: no pill (you can see the tab dots directly).
  When collapsed: pill shows count + severity color.

Tab row (sidebar):
  [2px blue accent bar: active tab only] [tab name]  [trailing: glow dot if notification]
  Dot on the RIGHT (trailing), not leading. Like Xcode's git badge position.
  This keeps the left edge clean for the accent bar system.
  
Tab bar:
  [tab name]  [glow dot if notification] [close]
  Active: blue bottom border.
  Dot: trailing, before close button.
```

Channels used per tab row: accent bar (active) + text (name) + trailing dot (notification) + trailing (pane count) = 4
But the accent bar and trailing dot are at opposite ends, so visual scanning is split.

Pros: Left edge is unified (accent bars only). Trailing dot is near where your eye goes for "what's new."
Cons: Trailing dot competes with pane count and future command result. Right side gets crowded.

## Part 5: Recommendation

**Option D ("Xcode + Reminders")** is the strongest design.

Reasoning:
1. Identity and status are fully independent (the core problem with Option B that we already experienced).
2. The glow dot is pre-attentive (color at fixed position, <200ms recognition).
3. It stays under the practical channel limit: background is ambient, dot is tiny, text is always there, trailing info is secondary.
4. It composes with Phase 2b-2 (git metadata goes on a second line under session name, independent of all indicators).
5. It composes with Phase 2b-3 (command result goes trailing right on tab row, independent of the leading dot).
6. The session accent bar stays pure (blue = active, nothing else), which is the simplest mental model.
7. The glow effect (Circle + shadow) makes the dot feel premium without being complex.

The notification pill on collapsed sessions is the "how much?" answer. The dot on tabs is the "where?" answer. The accent bar is the "which one am I in?" answer. Three questions, three independent visual elements, zero conflicts.

### Phase 2b-3 preview (how command result fits)

```
Tab row with all channels active:
  [●] [cargo build]                    [✓ 2s] [⊞ 3]
  dot  process title                   result  panes
  
  orange dot = last command failed
  "cargo build" = currently running process
  "✓ 2s" = last command succeeded in 2 seconds (trailing, muted)
  "⊞ 3" = 3 panes (trailing, muted)
```

Everything has its own position. Nothing conflicts.

## Sources

- /tmp/ai-research-sidebar-notification-ui-patterns.md (2026-04-15)
- /tmp/ai-design-phase2b-contextual-sidebar.md (Phase 2b spec)
