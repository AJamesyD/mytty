local M = {}

M.type = 'mistty'

local function cli(args)
  local cmd = 'mistty-cli ' .. args .. ' --json 2>/dev/null'
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local ok, decoded = pcall(vim.fn.json_decode, output)
  if not ok then
    return nil
  end
  return decoded
end

local function cli_fire(args)
  vim.fn.system('mistty-cli ' .. args .. ' 2>/dev/null')
end

function M.is_in_session()
  return vim.env.MISTTY_SOCKET ~= nil
end

function M.current_pane_id()
  local result = cli('pane active')
  if result and result.id then
    return result.id
  end
  return nil
end

function M.current_pane_at_edge(direction)
  local dir = ({ left = 'left', right = 'right', up = 'up', down = 'down' })[direction]
  if not dir then
    return false
  end
  local result = cli('pane at-edge --direction ' .. dir)
  if result and result.atEdge ~= nil then
    return result.atEdge
  end
  return false
end

function M.current_pane_is_zoomed()
  local result = cli('pane active')
  if result and result.zoomed ~= nil then
    return result.zoomed
  end
  return false
end

function M.next_pane(direction)
  local dir = ({ left = 'left', right = 'right', up = 'up', down = 'down' })[direction]
  if not dir then
    return false
  end
  local before = M.current_pane_id()
  cli_fire('pane focus --direction ' .. dir)
  local after = M.current_pane_id()
  return before ~= after
end

function M.resize_pane(direction, amount)
  local dir = ({ left = 'left', right = 'right', up = 'up', down = 'down' })[direction]
  if not dir then
    return false
  end
  cli_fire('pane resize --direction ' .. dir .. ' --amount ' .. tostring(amount))
  return true
end

function M.split_pane(direction)
  local dir = ({ left = 'horizontal', right = 'horizontal', up = 'vertical', down = 'vertical' })[direction]
  if not dir then
    return false
  end
  cli_fire('pane create --direction ' .. dir)
  return true
end

function M.on_init()
  cli_fire('pane set-var --key is-vim --value true')
end

function M.on_exit()
  cli_fire('pane set-var --key is-vim')
end

return M
