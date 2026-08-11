local M = {}

local buf = nil

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local has_mini, mini = pcall(require, "mini.icons")

local ns = vim.api.nvim_create_namespace("tree_view")

local state = {
  lines = {},
  file_win = nil,
  tree_win = nil,
}

-- Configuration
local config = {
  width = 50,
  side = "left", -- or "right"
  ignore_patterns = {
    "^node_modules$",
    "^%.cache$",
    "^build$",
    "^dist$",
    "^htmlcov$",

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

    table.insert(lines, {
      line = prefix .. branch .. icon .. " " .. entry.name,
      path = path .. "/" .. entry.name,
      name = entry.name,
      type = entry.type,
    })

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
  if state.tree_win and vim.api.nvim_win_is_valid(state.tree_win) then
    vim.api.nvim_win_close(state.tree_win, true)
    state.tree_win = nil
    buf = nil
    return
  end

  M.open()
end

function M.open()
  -- Get project root
  local root = vim.fn.getcwd()

  -- Build tree
  state.lines = {}
  if has_mini then
    table.insert(state.lines, {
      line = mini.get("directory", vim.fn.fnamemodify(root, ":t")) .. " " .. vim.fn.fnamemodify(root, ":t"),
      path = root,
      name = vim.fn.fnamemodify(root, ":t"),
      type = "directory",
    })
  else
    table.insert(state.lines, {
      line = "📁 " .. vim.fn.fnamemodify(root, ":t"),
      path = root,
      name = vim.fn.fnamemodify(root, ":t"),
      type = "directory",
    })
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
  build_tree(state.lines, hls, root, "")

  -- Create scratch buffer (not associated with a file)
  local rendered_lines = vim.tbl_map(function(entry) return entry.line end, state.lines)
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered_lines)
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
  state.tree_win = vim.api.nvim_get_current_win()

  M.setTreeWinOptions(state.tree_win, buf)

end

function M.setTreeWinOptions(_win, _buf)
  -- Calculate the width of the tree view based on the longest line
  local max_width = config.width
  for _, line in ipairs(state.lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line.line))
  end

  -- Window options 
  vim.wo[_win].number = false
  vim.wo[_win].relativenumber = false
  vim.wo[_win].signcolumn = "no"
  vim.wo[_win].foldcolumn = "0"
  vim.wo[_win].cursorline = true
  vim.wo[_win].winfixwidth = true

  vim.api.nvim_win_set_buf(_win, _buf)
  vim.api.nvim_win_set_width(_win, max_width)

  -- Keymaps: q to close, r to refresh, <CR> to go to file
  vim.keymap.set("n", "q", function() require("tree-view").toggle() end, { buffer = _buf, noremap = true, silent = true })
  vim.keymap.set("n", "r", function() require("tree-view").refresh() end, { buffer = _buf, noremap = true, silent = true })
  vim.keymap.set("n", "<CR>", function() require("tree-view").goTo() end, { buffer = _buf, noremap = true, silent = true })
end

function M.refresh()
  if state.tree_win and vim.api.nvim_win_is_valid(state.tree_win) then
    vim.api.nvim_win_close(state.tree_win, true)
    state.tree_win = nil
    buf = nil
  end
  M.open()
end

function M.goTo()

  if not (state.tree_win and vim.api.nvim_win_is_valid(state.tree_win)) then
    print("Tree view is not open.")
    return
  end

  buf = vim.api.nvim_win_get_buf(state.tree_win)

  local cursor = vim.api.nvim_win_get_cursor(state.tree_win)
  local line_num = cursor[1] - 1 -- zero-indexed
  local buf_lines = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)
  if #buf_lines == 0 then
    print("No line under cursor.")
    return
  end

  local selected_line = state.lines[line_num + 1]

  if selected_line.type == "directory" then
    print("Selected line is a directory. Please select a file.")
    return
  end

  local new_buf = vim.fn.bufadd(selected_line.path)
  vim.fn.bufload(new_buf)

  if state.file_win and vim.api.nvim_win_is_valid(state.file_win) then
    vim.api.nvim_win_set_buf(state.file_win, new_buf)
  else
    state.file_win = vim.api.nvim_open_win(new_buf, true, {
      split = "right",
      win = state.tree_win,
    })
  end

  local tree_buf = vim.api.nvim_win_get_buf(state.tree_win)
  M.setTreeWinOptions(state.tree_win, tree_buf)
  vim.cmd("wincmd =") -- Equalize window sizes

end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

return M
