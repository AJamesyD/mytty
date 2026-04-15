# ADR-006: Config File as Single Source of Truth

Status: accepted
Date: 2026-04-15

## Context

Mistty had a Settings GUI (Cmd+,) that could edit config values. On save,
it serialized the entire config from scratch using a hand-built TOML writer.
Any config sections the writer didn't know about (like `[keybindings]`) were
silently dropped. A user who changed font size in Settings would lose their
keybinding config.

Every terminal emulator in this space (Ghostty, Alacritty, kitty, WezTerm)
uses config-file-only. The GUI writer was both unusual and broken.

## Decision

The config file is the single source of truth. The Settings GUI is read-only:
it shows current values and provides an "Open Config File" button. Removed
`save()` and `tomlEscape()` from `MisttyConfig`. Added a
`MisttyConfig.configFileURL` static property so the GUI can open the file.

## Consequences

- Data loss bug eliminated with zero new code (net deletion of >150 lines).
- Users must edit TOML directly. This matches terminal user expectations.
- A future GUI editor is possible but requires a format-preserving TOML
  library that maintains comments, ordering, and unknown sections. The TODO
  in SettingsView marks this as the prerequisite.

## Lesson

Serialization that reconstructs from scratch will always lag behind the
parser. If the parser accepts N sections, the serializer must know about
all N. This is a maintenance trap. Prefer round-tripping the original
file or not writing at all.
