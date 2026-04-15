# mistty-nav

smart-splits.nvim backend for Mistty terminal emulator.

Enables bidirectional Ctrl+h/j/k/l navigation between neovim splits and Mistty panes.

## Requirements

- [Mistty](https://github.com/your-user/mistty) terminal emulator
- [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim)
- `mistty-cli` in your PATH (`just install-cli` from the Mistty repo)

## Setup

Add this plugin to your neovim config. With lazy.nvim:

```lua
{
  'your-user/mistty',
  config = function()
    -- The plugin adds lua/smart-splits/mux/mistty.lua to the runtimepath
  end,
  subdir = 'extras/neovim',
}
```

Configure smart-splits to use the Mistty backend:

```lua
require('smart-splits').setup({
  multiplexer_integration = 'mistty',
})
```

## How it works

**Neovim to Mistty:** When you press Ctrl+h at neovim's leftmost split, smart-splits detects the edge and calls `mistty-cli pane focus --direction left` to move focus to the adjacent Mistty pane.

**Mistty to neovim:** When you press Ctrl+h in a Mistty pane running neovim, Mistty forwards the keypress to neovim. smart-splits handles it (moving within neovim or calling back to Mistty if at the edge).

The backend sets a `is-vim` variable on the active pane via `mistty-cli pane set-var` when neovim starts, and clears it on exit. Mistty uses this variable to decide whether to forward keypresses or navigate panes directly.
