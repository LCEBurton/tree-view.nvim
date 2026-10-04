local config = require("treeview.config")
local state = require("treeview.state")
local source = require("treeview.source")

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local has_mini, mini = pcall(require, "mini.icons")

local ns = vim.api.nvim_create_namespace("tree_view")

local M = {}

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

local function create_buffer()
  state.tree_buf = vim.api.nvim_create_buf(false, true)


  -- Buffer options 
  vim.bo[state.tree_buf].modifiable = false  -- read-only
  vim.bo[state.tree_buf].bufhidden = "wipe"  -- delete buffer when window closes
  vim.bo[state.tree_buf].buftype = "nofile"  -- not associated with a file
  vim.bo[state.tree_buf].swapfile = false  -- no swap file

  vim.api.nvim_buf_set_name(state.tree_buf, "Tree View")

  -- Buffer keymaps

  return state.tree_buf

end

local function ensure_buffer()
  if state.tree_buf and vim.api.nvim_buf_is_valid(state.tree_buf) then
    return state.tree_buf
  end

  return create_buffer()

end

local function setTreeWinOptions(_win, _buf)
  -- Window options 
  vim.wo[_win].number = false
  vim.wo[_win].relativenumber = false
  vim.wo[_win].signcolumn = "no"
  vim.wo[_win].foldcolumn = "0"
  vim.wo[_win].cursorline = true
  vim.wo[_win].winfixwidth = true

  vim.api.nvim_win_set_buf(_win, _buf)

 -- Keymaps: q to close, r to refresh, <CR> to go to file
 vim.keymap.set("n", "q", function() M.close() end, { buffer = _buf, noremap = true, silent = true })
 vim.keymap.set("n", "r", function() M.render() end, { buffer = _buf, noremap = true, silent = true })
 vim.keymap.set("n", "<CR>", function() M.goTo() end, { buffer = _buf, noremap = true, silent = true })
end

local function update_tree_width()
  if not (state.tree_win and vim.api.nvim_win_is_valid(state.tree_win)) then
    return
  end

  local max_width = config.options.width
  for _, line in ipairs(state.lines) do
    local w = vim.fn.strdisplaywidth(line.text)
    max_width = math.max(max_width, w)
  end

  vim.api.nvim_win_set_width(state.tree_win, max_width)
end

local function render_lines(buf, lines, hls)

  -- Create scratch buffer (not associated with a file)
  local rendered_lines = vim.tbl_map(function(entry) return entry.text end, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered_lines)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, hl.line, hl.start_col, {
      end_col = hl.end_col,
      hl_group = hl.hl,
    })
  end
  vim.bo[buf].modifiable = false


end



local function create_window(_state)
  local buf = ensure_buffer()


  -- Create split window
  vim.cmd(config.options.side == "left" and "topleft vsplit" or "botright vsplit")
  _state.tree_win = vim.api.nvim_get_current_win()

  setTreeWinOptions(_state.tree_win, buf)

end

local function find_next_sibling_index(idx, level)
  local i = idx + 1
  while state.nodes[i] and state.nodes[i].level > level do
    i = i + 1
  end
  return i
end



local function create_lines(prefix, start, parent_level)
  local n_idx = start

  while n_idx <= #state.nodes do
    local node = state.nodes[n_idx]

    -- Stop if we've moved back up to parent level or higher
    if parent_level and node.level <= parent_level then
      return n_idx
    end

    local icon, hl = get_icon(node.name, node.type)
    local sibling_idx = find_next_sibling_index(n_idx, node.level)
    local next_sibling = state.nodes[sibling_idx]
    local is_last_entry = not next_sibling or next_sibling.level < node.level

    local branch = is_last_entry and "└── " or "├── "

    table.insert(state.lines, {
      text = prefix .. branch .. icon .. " " .. node.name,
      type = node.type,
      path = node.path,
    })

    if hl then
      table.insert(state.hls, {
        line = #state.lines - 1,
        start_col = #prefix + #branch,
        end_col = #prefix + #branch + #icon,
        hl = hl,
      })
    end

    local next_node = state.nodes[n_idx + 1]
    n_idx = n_idx + 1

    if node.type == "directory" and next_node and next_node.level > node.level then
      local new_prefix = prefix .. (is_last_entry and "    " or "│   ")
      n_idx = create_lines(new_prefix, n_idx, node.level)
    end
  end

  return n_idx
end


function M.render()

  local project_root = config.project_root or vim.fn.getcwd()

  source.build_tree(project_root)


  local root_icon, root_hl = get_icon(vim.fn.fnamemodify(project_root, ":t"), "directory")

  state.lines = {
    {
      text = root_icon .. " " .. vim.fn.fnamemodify(project_root, ":t"),
      type = "directory",
      path = project_root,
    },
  }
  state.hls = {
    {
      line = 0,
      start_col = 0,
      end_col = #root_icon,
      hl = root_hl,
    },
  }

  create_lines("", 2, 0)
  render_lines(state.tree_buf, state.lines, state.hls)
  update_tree_width()

end


function M.goTo()

  if not (state.tree_win and vim.api.nvim_win_is_valid(state.tree_win)) then
    print("Tree view is not open.")
    return
  end

  local buf = vim.api.nvim_win_get_buf(state.tree_win)

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

  vim.cmd("wincmd =") -- Equalize window sizes

end


function M.open()
  local buf = ensure_buffer()

  if not buf then
    vim.notify("Could not create buffer", vim.log.levels.ERROR)
    return
  end

  if not state.tree_win or not vim.api.nvim_win_is_valid(state.tree_win) then
    create_window(state)
    M.render()
  else
    vim.api.nvim_set_current_win(state.tree_win)
  end
end



function M.close()
  if state.tree_win and vim.api.nvim_win_is_valid(state.tree_win) then
    vim.api.nvim_win_close(state.tree_win, true)
    state.tree_win = nil
  end
  if state.tree_buf and vim.api.nvim_buf_is_valid(state.tree_buf) then
    vim.api.nvim_buf_delete(state.tree_buf, { force = true })
    state.tree_buf = nil
  end
end


return M
