# Neovim Smart-Splits Integration

MytTY supports seamless pane navigation with neovim's
[smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) plugin.

## How It Works

- **Ctrl-H/J/K/L** navigates between MytTY panes
- When the active pane is running neovim, MytTY passes the keypress through
- smart-splits.nvim handles navigation within neovim splits
- When neovim is at its boundary, smart-splits calls back to MytTY via CLI

## Neovim Configuration

Add to your neovim config:

```lua
require('smart-splits').setup({
  at_edge = function(direction)
    local dir_map = {
      left = 'left',
      right = 'right',
      up = 'up',
      down = 'down',
    }
    os.execute('mytty-cli pane focus --direction ' .. dir_map[direction])
  end
})

-- Keymaps
vim.keymap.set('n', '<C-h>', require('smart-splits').move_cursor_left)
vim.keymap.set('n', '<C-j>', require('smart-splits').move_cursor_down)
vim.keymap.set('n', '<C-k>', require('smart-splits').move_cursor_up)
vim.keymap.set('n', '<C-l>', require('smart-splits').move_cursor_right)
```

## Requirements

- `mytty-cli` must be in your PATH (installed via `just install-cli`)
- MytTY XPC service must be running (starts automatically with the app)
