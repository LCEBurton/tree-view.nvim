local config = require("treeview.config")
local state = require("treeview.state")
local source = require("treeview.source")
local fsops = require("treeview.fsops")

local ns = vim.api.nvim_create_namespace("tree_view")
local info_ns = vim.api.nvim_create_namespace("tree_view_info")

local M = {}

local function update_tree_width()
  if not (state.tree_win and vim.api.nvim_win_is_valid(state.tree_win)) then
    return
  end
  local max_width = config.options.width
  for _, line in ipairs(state.lines) do
    local w = vim.fn.strdisplaywidth(line.text)
    max_width = math.max(max_width, w)
  end
  if vim.api.nvim_win_get_width(state.tree_win) ~= max_width then
    vim.api.nvim_win_set_width(state.tree_win, max_width)
  end
end

local function render_lines(buf, lines, hls)

  -- Create scratch buffer (not associated with a file)
  local rendered_lines = vim.tbl_map(function(entry) return entry.text end, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered_lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, hl.line, hl.start_col, {
      end_col = hl.end_col,
      hl_group = hl.hl,
    })
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false  -- reset modified flag after rendering


end

local function find_next_sibling_index(idx, level)
  local node = state.nodes[idx]
  if node and node.type == "directory" and node.descendant_count then
    return idx + 1 + node.descendant_count
  end
  return idx + 1
end



local function create_lines(prefix, start, parent_level)
  local n_idx = start

  while n_idx <= #state.nodes do
    local node = state.nodes[n_idx]

    -- Stop if we've moved back up to parent level or higher
    if parent_level and node.level <= parent_level then
      return n_idx
    end

    local icon, hl = node.icon, node.icon_hl
    local sibling_idx = find_next_sibling_index(n_idx, node.level)
    local next_sibling = state.nodes[sibling_idx]
    local is_last_entry = not next_sibling or next_sibling.level < node.level
    local branch = ""

    if state.collapsed[node.path] then
      branch = is_last_entry and "╘══ " or "╞══ "
    else
      branch = is_last_entry and "└── " or "├── "
    end

    table.insert(state.lines, {
      text = prefix .. branch .. icon .. " " .. node.name,
      type = node.type,
      path = node.path,
      descendant_count = node.descendant_count,
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

    if state.collapsed[node.path] then
      -- Skip all children of this node
      n_idx = n_idx + (node.descendant_count or 0)
    end


    if
      node.type == "directory"
      and next_node
      and next_node.level > node.level
      and not state.collapsed[node.path]
    then
      local new_prefix = prefix .. (is_last_entry and "    " or "│   ")
      n_idx = create_lines(new_prefix, n_idx, node.level)
    end
  end

  return n_idx
end



local function update_display(project_root)
  local root = state.nodes[1]
  local root_icon, root_hl = root.icon, root.icon_hl

  state.lines = {
    {
      text = root_icon .. " " .. vim.fn.fnamemodify(project_root, ":t"),
      type = "directory",
      path = project_root,
      descendant_count = state.nodes[1].descendant_count,
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

local function add_descendant_count(_buf, _win)
  vim.api.nvim_buf_clear_namespace(_buf, info_ns, 0, -1)
  local line_num = vim.api.nvim_win_get_cursor(_win)[1] - 1
  local line = state.lines[line_num + 1]
  if line and line.type == "directory"
    and state.collapsed[line.path]
    and line.descendant_count and line.descendant_count > 0 then
    vim.api.nvim_buf_set_extmark(_buf, info_ns, line_num, 0, {
      virt_text = { { " (" .. line.descendant_count .. ")", "Comment" } },
      virt_text_pos = "eol",
    })
  end
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
  vim.keymap.set("n", "<space>", function()
    local cursor = vim.api.nvim_win_get_cursor(_win)
    local line_num = cursor[1]
    local selected_line = state.lines[line_num]
    if selected_line and selected_line.type == "directory" then
      state.collapsed[selected_line.path] = not state.collapsed[selected_line.path]
      update_display(config.project_root or vim.fn.getcwd())
      vim.api.nvim_win_set_cursor(state.tree_win, { line_num, cursor[2] })
    end
  end, { buffer = _buf, noremap = true, nowait = true, silent = true })

  vim.keymap.set("n", "e", function() M.enter_edit_mode() end, { buffer = _buf, noremap = true, silent = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = _buf,
    callback = function()
      add_descendant_count(_buf, _win)
    end,
  })
end




local function create_window(_state)
  local buf = ensure_buffer()


  -- Create split window
  vim.cmd(config.options.side == "left" and "topleft vsplit" or "botright vsplit")
  _state.tree_win = vim.api.nvim_get_current_win()

  setTreeWinOptions(_state.tree_win, buf)

end

function M.render()

  local project_root = config.project_root or vim.fn.getcwd()

  source.build_tree(project_root)
  source.sync_watchers()

  update_display(project_root)
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
  for _, handle in pairs(state.watchers) do
    handle:stop()
    if not handle:is_closing() then handle:close() end
  end
end

local function to_raw_lines()
  -- map path -> level from state.nodes (source of truth for depth)
  local level_by_path = {}
  for _, node in ipairs(state.nodes) do
    level_by_path[node.path] = node.level
  end

  local raw_lines = {}
  for _, line in ipairs(state.lines) do
    local level = level_by_path[line.path] or 0
    local name = vim.fn.fnamemodify(line.path, ":t")
    if line.type == "directory" then
      name = name .. "/"
    end
    local indent = string.rep(" ", level * vim.fn.shiftwidth())
    table.insert(raw_lines, indent .. name)
  end
  return raw_lines
end

local function parse_raw_lines(lines)
  local parsed = {}
  for _, line in ipairs(lines) do
    local is_dir = line:sub(-1) == "/"
    table.insert(parsed, {
      name = line,
      is_dir = is_dir,
    })
  end
  return parsed
end

function M.save_edit_mode()
  local lines = vim.api.nvim_buf_get_lines(state.tree_buf, 0, -1, false)
  local parsed = parse_raw_lines(lines) -- your own helper: text -> {name, is_dir} per line
  local errors, resolved_paths = fsops.validate(parsed)

  if #errors > 0 then
    fsops.error(errors)
    return -- stay in edit mode, buffer untouched
  end

  local live_extmarks = vim.api.nvim_buf_get_extmarks(state.tree_buf, state.identity_ns, 0, -1, {})
  local ops = fsops.diff(live_extmarks, resolved_paths)

  vim.schedule(function()
    fsops.confirm(ops, function(answer)
      if answer then
        fsops.execute(ops)
        state.edit_mode = false
        vim.bo[state.tree_buf].modifiable = false
        M.render() -- rebuild from disk, reflecting actual post-op state
        vim.bo[state.tree_buf].modified = false
      end
    end)
  end)
  -- if confirm() returns false, stay in edit mode, nothing executed
end

function M.enter_edit_mode()
  state.old_nodes = vim.deepcopy(state.nodes)  -- or whatever snapshot you need
  state.identity = {}
  state.identity_ns = vim.api.nvim_create_namespace("treeview_identity")

  vim.api.nvim_buf_clear_namespace(state.tree_buf, state.identity_ns, 0, -1)
  vim.api.nvim_clear_autocmds({ buffer = state.tree_buf, event = "BufWriteCmd" })


  vim.bo[state.tree_buf].modifiable = true
  vim.bo[state.tree_buf].buftype = "acwrite"  -- to trigger BufWriteCmd
  vim.bo[state.tree_buf].shiftwidth = 2
  vim.api.nvim_buf_set_lines(state.tree_buf, 0, -1, false, to_raw_lines())
  state.edit_mode = true

  for i, line in ipairs(state.lines) do
    local id = vim.api.nvim_buf_set_extmark(state.tree_buf, state.identity_ns, i - 1, 0, {})
    local _path = line.path
    if line.type == "directory" and _path:sub(-1) ~= "/" then
      _path = _path .. "/"
    end
    state.identity[id] = { orig_path = _path, type = line.type }
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = state.tree_buf,
    callback = function()
      M.save_edit_mode()
    end,
  })

  vim.keymap.set("n", "<Esc>", function()
    vim.bo[state.tree_buf].modifiable = false
    M.render()  -- revert to last saved state
    state.edit_mode = false
    vim.bo[state.tree_buf].modified = false
  end, { buffer = state.tree_buf, noremap = true, silent = true })
end


return M
