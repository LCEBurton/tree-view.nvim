local M = {}

local buf = nil
local win = nil

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local has_mini, mini = pcall(require, "mini.icons")

local ns = vim.api.nvim_create_namespace("tree_view")

-- Configuration
local config = {
  width = 50,
  side = "left", -- or "right"
  ignore_patterns = {
    "^node_modules$",
    "^%.cache$",
    "^build$",
    "^dist$",

    -- Python stuff
    "^__pycache__$",
    "^__init__.py$",

    "^%.", -- ignore hidden files
    "%.egg%-info$",
  },
}

-- Check if path should be ignored
local function should_ignore(name)
  for _, pattern in ipairs(config.ignore_patterns) do
    if name:match(pattern) then
      return true
    end
  end
  return false
end

local function get_icon(name, type)
  if type == "directory" then
    if has_mini then
      return mini.get("directory", name)
    else
      return "📁", nil
    end
  else
    if has_devicons then
      return devicons.get_icon(name, nil, { default = true })
    else
      return "📄", nil
    end
  end
end

-- Build tree structure recursively
local function build_tree(lines, hls, path, prefix)
  local handle = vim.uv.fs_scandir(path)
  if not handle then
    return lines, hls
  end
  local entries = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then break end

    if not should_ignore(name) then
      table.insert(entries, { name = name, type = type })
    end
  end

  -- Sort: directories first, then alphabetically
  table.sort(entries, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    end
    return a.type == "directory"
  end)

  for i, entry in ipairs(entries) do
    local is_last_entry = i == #entries
    local branch = is_last_entry and "└── " or "├── "
    local icon, hl = get_icon(entry.name, entry.type)

    table.insert(lines, prefix .. branch .. icon .. " " .. entry.name)

    if hl then
      table.insert(hls, {
        name = entry.name,
        line = #lines - 1,
        start_col = #prefix + #branch,
        end_col = #prefix + #branch + #icon,
        hl = hl,
      })
    end

    if entry.type == "directory" then
      local new_prefix = prefix .. (is_last_entry and "    " or "│   ")
      build_tree(lines, hls, path .. "/" .. entry.name, new_prefix)
    end
  end
end

-- Create or toggle tree view
function M.toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
    win = nil
    buf = nil
    return
  end

  M.open()
end

function M.open()
  -- Get project root
  local root = vim.fn.getcwd()

  -- Build tree
  local lines = {}
  if has_mini then
    lines = { mini.get("directory", vim.fn.fnamemodify(root, ":t")) .. " " .. vim.fn.fnamemodify(root, ":t") }
  else
    lines = { "📁 " .. vim.fn.fnamemodify(root, ":t")}
  end

  local hls = {}
  if has_mini then
    local icon, hl = get_icon(vim.fn.fnamemodify(root, ":t"), "directory")
    table.insert(hls, {
      name = vim.fn.fnamemodify(root, ":t"),
      line = 0,
      start_col = 0,
      end_col = #icon,
      hl = hl,
    })
  end
  build_tree(lines, hls, root, "")

  -- Create scratch buffer (not associated with a file)
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, hl.line, hl.start_col, {
      end_col = hl.end_col,
      hl_group = hl.hl,
    })
  end

  -- Buffer options 
  vim.bo[buf].modifiable = false  -- read-only
  vim.bo[buf].bufhidden = "wipe"  -- delete buffer when window closes
  vim.api.nvim_buf_set_name(buf, "Tree View")

  -- Create split window
  vim.cmd(config.side == "left" and "topleft vsplit" or "botright vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, config.width)

  -- Window options 
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = true

  -- Keymaps: q to close, r to refresh
  vim.keymap.set("n", "q", function() require("tree-view").toggle() end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "r", function() require("tree-view").refresh() end, { buffer = buf, noremap = true, silent = true })
end

function M.refresh()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
    win = nil
    buf = nil
  end
  M.open()
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

return M
