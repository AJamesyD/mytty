# Debate: Mistty's First 3 Shipped Features

Date: 2026-04-14
Question: What should Mistty's first 3 shipped features be, and in what order?

## Personas

- **A (Platform Builder)**: Socket API first, then OSC infrastructure + notification rings, then session resurrection.
- **B (Pragmatic Incrementalist)**: Which-key overlay first, then notification rings, then declarative project layouts.
- **C (Headline Chaser)**: Native tmux control mode first, then socket API, then session resurrection.

---

## Round 1

### A (Platform Builder)

**Challenge to B**: You call which-key "2 days of work," but that's the feature in isolation. Without a socket API, which-key is hardcoded to Mistty's internal actions. External tools (Raycast, Hammerspoon, shell scripts) can't register custom actions. You're building a closed system. Kitty's `kitty @` remote control (Evidence 9) enabled an entire ecosystem. The socket API is the difference between "a nice overlay" and "a platform."

**Defense**: Evidence 11 shows that OSC 9/99/777 parsing for notifications is also needed for shell integration (OSC 133 for command boundaries). Building notification rings without the OSC infrastructure means you'll parse escape sequences ad-hoc, then rewrite that parsing when you need block-based output or working directory tracking. Two infrastructure investments (socket API + OSC parsing) unlock 6+ features each. The composite score doesn't capture this multiplier effect.

### B (Pragmatic Incrementalist)

**Challenge to A**: Evidence 15 is fatal to your position. "A socket API without users is a tree falling in an empty forest." Kitty's `kitty @` took years to build an ecosystem. Mistty has zero users. Who writes Raycast extensions for a terminal nobody uses? You need users first, and users come from visible features. Evidence 13 confirms cmux's notification rings work without a socket API, driven by terminal output events from the libghostty surface delegate. Evidence 14 confirms which-key needs only NSEvent monitoring and a SwiftUI overlay, both already in use.

**Defense**: Evidence 1 shows zellij's status bar is the #1 cited reason for choosing it over tmux. Which-key is the same benefit (keybinding discoverability) without the screen cost. Evidence 6 gives which-key a composite score of 10.00, nearly double the next feature. Evidence 7 shows early-stage OSS projects succeed with one hero feature. Which-key IS that hero feature for Mistty: "the discoverable terminal." Two days of work, zero infrastructure dependencies, defines the app's personality.

### C (Headline Chaser)

**Challenge to B**: Which-key is a nice-to-have, not a reason to switch terminals. Nobody writes a blog post about "this terminal shows me my keybindings." Evidence 5 shows iTerm2's tmux control mode is THE reason users stay despite its age and performance issues. Evidence 4 shows it's Ghostty's top-voted issue. Evidence 7 says early-stage projects succeed with one hero feature, and that feature needs to be ambitious enough to generate word-of-mouth. Zellij's hero feature wasn't "a status bar," it was "a terminal multiplexer that's actually learnable." The status bar was the mechanism, but the ambition was the story.

**Defense**: Evidence 12 shows the tmux control mode protocol is well-defined. The edge cases (resize reflow, pane reordering, Unicode handling) are where iTerm2 spent years, but Mistty's SwiftUI split tree model is more flexible than iTerm2's Objective-C view hierarchy. The brainstorm notes that Mistty already supports programmatic split tree manipulation. A basic tmux control mode (connect, display panes, resize) could ship in 4-6 weeks, with edge case refinement ongoing. It doesn't have to be perfect on day one.

---

## Round 2

### A (Platform Builder)

**Challenge to C**: Your "4-6 weeks for basic tmux control mode" estimate is optimistic to the point of dishonesty. Evidence 12 says iTerm2 spent years on edge cases. "Basic" tmux control mode that breaks on resize, Unicode, or pane reordering is worse than no tmux control mode, because users will file bugs and lose trust. Evidence 8 frames session persistence as a hygiene factor (Herzberg): absence causes dissatisfaction, presence doesn't cause satisfaction. tmux control mode has the same risk: a broken version causes more dissatisfaction than no version.

**Defense**: I'll concede B's point about the chicken-and-egg problem (Evidence 15). But the concession is partial. The socket API doesn't need external adopters to be valuable. The `mistty` CLI binary is the first client, and it enables scripting from day one. `mistty split --cmd "npm run dev"` in a shell script is immediately useful to the developer (Evidence 10: they run AI agents in parallel terminals). The socket API's first user is the developer themselves.

### B (Pragmatic Incrementalist)

**Challenge to A**: Your concession actually strengthens my position. If the socket API's first user is the developer, then the developer should build the features they personally need first (Evidence 10: they use tmux-which-key daily). Which-key scratches their own itch, ships in 2 days, and creates the "discoverable terminal" identity. Then notification rings (1 week) solve their agent workflow pain. THEN build the socket API when there are features that need it. Infrastructure should be pulled by demand, not pushed by speculation.

**Defense**: Evidence 2 is underappreciated. cmux grew to 14k stars in ~6 months. Its differentiators were notification rings, rich sidebar, and vertical tabs. NOT a socket API. NOT tmux control mode. Visible, polished, standalone features drove adoption. The pattern is clear: ship visible wins, build audience, then add infrastructure. Reversing this order is how projects die in obscurity with beautiful architecture.

### C (Headline Chaser)

**Challenge to A**: You're right that my 4-6 week estimate is aggressive. But I'll reframe: the question isn't "can we ship perfect tmux control mode in 6 weeks?" It's "can we ship a demo that makes people say 'holy shit, Mistty renders my tmux sessions natively'?" A proof-of-concept that handles the 80% case (connect to tmux, display panes, basic resize) is enough for a blog post and a demo video. The remaining 20% of edge cases can ship iteratively. Evidence 7: early-stage projects succeed with one hero feature. The hero feature doesn't have to be complete; it has to be compelling.

**Defense**: Evidence 3 shows tmux-resurrect has 12.6k stars. Session persistence is the most-wanted tmux plugin. Evidence 5 shows iTerm2 retains users because of tmux control mode. These are the same user base: people who use tmux for remote work and want their terminal to understand tmux. Mistty can own this audience. Which-key and notification rings compete with cmux for the "local terminal power user" audience. tmux control mode competes with iTerm2 for the "remote work professional" audience, which is larger and more loyal.

---

## Round 3

### A (Platform Builder)

**Challenge to C**: You're now arguing for a demo, not a feature. A proof-of-concept that handles 80% of cases will hit the other 20% within the first week of real usage. Users SSH to remote servers with non-ASCII hostnames, resize their windows, and use tmux plugins that modify pane layouts. The 20% isn't edge cases; it's the daily workflow of the target audience. Evidence 12 is explicit: "the edge cases (resize reflow, pane reordering, Unicode handling) are where iTerm2 spent years." You can't demo your way past this.

**New evidence**: The brainstorm scores tmux control mode at 5.00 (complexity 5, delight 5, uniqueness 5). Which-key scores 10.00 (complexity 2, delight 5, uniqueness 4). The ratio of value-to-effort is 2:1 in favor of which-key. For a solo developer (Evidence 10), effort matters more than for a funded team.

**Revised position**: I'm moving toward B's position on sequencing. Ship which-key first (2 days, defines identity), then build OSC parsing as part of notification rings (the infrastructure emerges from the feature, as B argues). The socket API moves to position 3, pulled by the need for external scripting after the first two features establish the user base. My original position of "infrastructure first" was wrong because it assumed users would wait for the platform to be built. They won't.

### B (Pragmatic Incrementalist)

**Challenge to C**: Your reframe to "demo-quality tmux control mode" actually proves my point. If you ship a demo that breaks on resize, you've spent 4-6 weeks building something you can't recommend people use daily. Meanwhile, which-key (2 days) and notification rings (1 week) are features that work perfectly from day one. Evidence 2 shows cmux's growth was driven by polished standalone features, not ambitious demos. The developer's time is the scarcest resource (solo project, Evidence 10). Spending it on a 4-6 week gamble when 1.5 weeks of work ships two complete features is not a rational allocation.

**New evidence**: Evidence 14 confirms which-key needs only NSEvent monitoring (already used by copy mode and window mode managers) and a SwiftUI overlay (already used by the session manager). This means the feature reuses existing patterns in the codebase, reducing risk to near zero. Notification rings (Evidence 13) similarly reuse the libghostty surface delegate's output events. Both features are low-risk because they build on proven infrastructure.

**Defense**: My ranking stands: (1) Which-Key Overlay, (2) Notification Rings, (3) Declarative Project Layouts. But I'll accept A's revised position on the socket API as a reasonable #3 alternative. The key principle is: visible features first, infrastructure pulled by demand.

### C (Headline Chaser)

**Challenge to B**: I'll grant that the effort math doesn't work for tmux control mode as feature #1 for a solo developer. But I want to push back on the framing that which-key is a "hero feature." Evidence 7 says early-stage projects succeed with one hero feature. Zellij's hero feature was "a multiplexer you can learn without reading a manual." Warp's was "a terminal that understands commands." Ghostty's was "a terminal that's actually fast." Each of these is a sentence that makes someone want to try the app. "A terminal that shows you keybindings" is... fine? It's a feature of the hero feature, not the hero feature itself.

**New evidence**: The brainstorm's top 3 recommendations frame the theme as "contextual awareness without mode-switching." That's a stronger hero narrative than any single feature. Which-key + notification rings + rich sidebar together tell the story: "Mistty knows what's happening and tells you without asking." That's a sentence that makes someone want to try the app. The hero feature is the combination, not any individual piece.

**Revised position**: I'm conceding that tmux control mode is wrong for position #1. The effort-to-value ratio doesn't work for a solo developer at launch. But I want to register that it should be on the roadmap as the "Phase 2 headline" after the first three features establish the user base. My revised ranking: (1) Which-Key Overlay, (2) Notification Rings, (3) Rich Sidebar Metadata. The three together form the "contextual awareness" hero narrative. tmux control mode becomes the Phase 2 headline that generates the blog posts.

---

## Anti-Sycophancy Gate: The Case for tmux Control Mode as #1

The strongest argument for leading with tmux control mode, despite the consensus against it:

1. **Market positioning**: Which-key and notification rings make Mistty "a better cmux." tmux control mode makes Mistty "the only alternative to iTerm2 for remote work." The second positioning targets a larger, more underserved audience. cmux already serves the "local terminal power user" niche.

2. **Moat depth**: Which-key is 2 days of work for Mistty, but it's also 2 days of work for Ghostty, Kitty, or WezTerm to copy. tmux control mode's complexity IS the moat. If Mistty ships it, competitors can't easily replicate it. Evidence 12 shows iTerm2 spent years on this. The difficulty is the defensibility.

3. **User retention**: Evidence 5 shows users stay on iTerm2 specifically for tmux control mode, despite iTerm2's inferior performance. A feature that retains users through switching costs is more valuable than a feature that attracts users through novelty. Which-key attracts; tmux control mode retains.

4. **The "just ship a demo" argument has precedent**: Ghostty shipped with known gaps and iterated. Zellij 0.1 was missing features. Early adopters of developer tools tolerate rough edges if the core promise is compelling. A tmux control mode that handles 80% of cases and improves weekly is a compelling narrative for early adopters.

**Why this argument loses**: The effort math. A solo developer spending 4-6 weeks (optimistic) on one feature that might not work reliably means 4-6 weeks of no other progress. If it takes 3 months (realistic, per Evidence 12's complexity warning), that's a quarter of the year on one bet. Which-key + notification rings + rich sidebar ship in ~3 weeks total and establish three complete features. The risk-adjusted value favors the incremental approach. tmux control mode is the right Phase 2 bet after the user base exists.

---

## Convergence

### Decision: Top 3 Features in Order

1. **Which-Key Overlay**: ~2 days of work, zero new infrastructure, reuses existing NSEvent monitoring and SwiftUI overlay patterns, highest composite score (10.00), defines Mistty's identity as "the discoverable terminal."

2. **Notification Rings**: ~1 week of work, builds OSC parsing infrastructure that enables future features (block-based output, shell integration), solves the developer's personal pain point (parallel AI agent workflows), second-highest composite score (6.67).

3. **Rich Sidebar Metadata**: ~1-2 weeks of work, transforms the sidebar from a tab list into a project dashboard, pairs naturally with notification rings (both enrich the sidebar), completes the "contextual awareness without mode-switching" narrative that becomes Mistty's hero story.

### Key Tradeoff

**Incremental completeness over headline impact.** Three polished, standalone features that each work perfectly and together form a coherent identity ("the terminal that knows what's happening") beat one ambitious feature that might not work reliably. The hero feature is the combination, not any single piece.

### Dissent: Strongest Losing Argument

tmux control mode is the only feature that creates a defensible moat. Its complexity is its protection against competitors copying it. By choosing incremental features, Mistty risks being "a better cmux" rather than "the only alternative to iTerm2 for remote work." If Ghostty or WezTerm ships which-key or notification rings first, Mistty loses its differentiators. tmux control mode can't be easily replicated.

### Conditions That Would Change This Answer

1. **If Mistty had 2+ developers**: tmux control mode becomes viable as #1 because one developer can work on it while the other ships visible features.
2. **If Ghostty ships a scripting API or which-key**: Mistty's differentiators evaporate. Pivot to tmux control mode as the moat.
3. **If the developer stops using tmux daily**: The personal workflow alignment (Evidence 10) weakens. Re-evaluate whether tmux control mode's audience is still the target.
4. **If cmux's growth stalls**: The evidence that "visible standalone features drive adoption" (Evidence 2) weakens. Reconsider the infrastructure-first approach.

---

## Phase 2 Roadmap (out of scope, but informed by debate)

After the first three features ship:
- Socket API (pulled by demand for scripting and external tool integration)
- tmux control mode (the headline feature that generates blog posts, built on a foundation of users and infrastructure)
- Session resurrection (table stakes, builds on OSC parsing infrastructure from notification rings)

## Sources

[2026-04-14] /tmp/ai-brainstorm-mistty-ux.md (brainstorm with 14 scored ideas, composite scoring methodology)
