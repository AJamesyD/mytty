# mytty-nav

smart-splits.nvim backend for Mytty terminal emulator.

Enables bidirectional Ctrl+h/j/k/l navigation between neovim splits and Mytty panes.

## Requirements

- [Mytty](https://github.com/AJamesyD/mytty) terminal emulator
- [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim)
- `mytty-cli` in your PATH (`just install-cli` from the Mytty repo)

## Setup

Add this plugin to your neovim config. With lazy.nvim:

```lua
{
  'AJamesyD/mytty',
  config = function()
    -- The plugin adds lua/smart-splits/mux/mytty.lua to the runtimepath
  end,
  subdir = 'extras/neovim',
}
```

Configure smart-splits to use the Mytty backend:

```lua
require('smart-splits').setup({
  multiplexer_integration = 'mytty',
})
```

## How it works

**Neovim to Mytty:** When you press Ctrl+h at neovim's leftmost split, smart-splits detects the edge and calls `mytty-cli pane focus --direction left` to move focus to the adjacent Mytty pane.

**Mytty to neovim:** When you press Ctrl+h in a Mytty pane running neovim, Mytty forwards the keypress to neovim. smart-splits handles it (moving within neovim or calling back to Mytty if at the edge).

The backend sets an `is-vim` variable on the active pane via `mytty-cli pane set-var` when neovim starts, and clears it on exit. Mytty uses this variable to decide whether to forward keypresses or navigate panes directly.
