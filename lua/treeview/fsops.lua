local M = {}

local state = require("treeview.state")
local uv = vim.uv

local function get_indent_level(lnum)
  return vim.fn.indent(lnum) / vim.fn.shiftwidth()
end

local hl_by_type = {
  create = "DiagnosticInfo",
  rename = "DiagnosticWarn",
  delete = "DiagnosticError",
}

local function center(text, width)
  local pad = math.floor((width - vim.fn.strdisplaywidth(text)) / 2)
  return string.rep(" ", math.max(pad, 0)) .. text
end

local function op_is_dir(path)
  return path:sub(-1) == "/"
end

local function relpath(path)
  if not path then return path end
  local root = state.project_root
  if not root then return path end
  -- normalize root to not have trailing slash for matching
  local normalized_root = root:gsub("/$", "")
  if path == normalized_root or path == normalized_root .. "/" then
    return "."
  end
  local prefix = normalized_root .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end


function M.validate(lines)
  local errors = {}
  local stack = {} -- { level, is_dir, line_num, path }
  local resolved_paths = {}
  local path = nil
  for i, line in ipairs(lines) do
    local level = get_indent_level(i)
    if level % 1 ~= 0 then
      table.insert(errors, {
        line = i,
        message = ("'%s' has irregular indentation with tab width '%d'")
                    :format(vim.trim(line.name), vim.fn.shiftwidth())
      })
    end
    while #stack > 0 and stack[#stack].level >= level do
      table.remove(stack)
    end
    local parent = stack[#stack]
    if parent then
      path = vim.fs.joinpath(parent.path, vim.trim(line.name))
    else
      path = state.project_root .. "/"
    end
    table.insert(resolved_paths, { path = path })
    if parent and not parent.is_dir then
      table.insert(errors, {
        line = i,
        message = ("'%s' cannot be a child of '%s' (not a directory)"):format(vim.trim(line.name), relpath(parent.path)),
      })
    end
    table.insert(stack, { level = level, is_dir = line.is_dir, line_num = i, path = path })
  end
  return errors, resolved_paths
end

function M.diff(live_extmarks, resolved_paths)
  local ops = {}
  local seen = {}
  local id_by_row = {}
  for _, mark in ipairs(live_extmarks) do
    local id, row, col = unpack(mark)
    id_by_row[row] = id
  end
  -- Find new or moved files
  for row, entry in ipairs(resolved_paths) do
    local new_path = entry.path
    local id = id_by_row[row - 1]
    local info = id and state.identity[id]
    if not info then
      table.insert(ops, { type = "create", path = new_path })
    else
      seen[id] = true
      if info.orig_path ~= new_path then
        table.insert(ops, { type = "rename", from = info.orig_path, to = new_path })
      end
    end
  end

  -- Find deleted files
  for id, info in pairs(state.identity) do
    if not seen[id] then
      table.insert(ops, { type = "delete", path = info.orig_path })
    end
  end
  return ops
end

function M.describe(op)
  local line = nil
  if op.type == "create" then
    line = ("CREATE %s"):format(relpath(op.path))
  elseif op.type == "rename" then
    line = ("RENAME %s -> %s"):format(relpath(op.from), relpath(op.to))
  elseif op.type == "delete" then
    line = ("DELETE %s"):format(relpath(op.path))
  else
    line = ("ERROR %s"):format(op.type)
  end

  return line, op.type
end

function M.confirm(ops, callback)
  if #ops == 0 then
    callback(false)
    return
  end

  local lines = {}
  local hl_lines = {}
  for _, op in ipairs(ops) do
    local text, op_type = M.describe(op)
    table.insert(lines, text)
    table.insert(hl_lines, { line = #lines - 1, hl = hl_by_type[op_type], type=op_type })
  end

  local width = math.min(120, math.max(40, vim.fn.max(vim.tbl_map(vim.fn.strdisplaywidth, lines))))

  table.insert(lines, "")
  table.insert(lines, "")
  table.insert(lines, center("Apply these changes?", width))
  table.insert(lines, "")
  table.insert(lines, center("[Y]es  [N]o", width))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("treeview_confirm")
  for _, hl in ipairs(hl_lines) do
    vim.api.nvim_buf_set_extmark(buf, ns, hl.line, 0, {
      end_col = #hl.type,
      hl_group = hl.hl,
    })
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = #lines,
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
  })


  local function close(answer)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    callback(answer)
  end

  vim.keymap.set("n", "y", function() close(true) end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "n", function() close(false) end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function() close(false) end, { buffer = buf, nowait = true })
end

function M.error(errors)
  if #errors == 0 then return end
  local lines = {}
  local hl_lines = {}
  local err_msg = "ERROR"
  for _, err in ipairs(errors) do
    table.insert(lines, ("%s %s"):format(err_msg, err.message))
    table.insert(hl_lines, { line = #lines - 1, hl = "DiagnosticError" })
  end
  local width = math.min(180, math.max(40, vim.fn.max(vim.tbl_map(vim.fn.strdisplaywidth, lines))))
  table.insert(lines, "")
  table.insert(lines, "")
  table.insert(lines, center("Fix these errors before saving", width))
  table.insert(lines, "")
  table.insert(lines, center("[press any key to close]", width))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local ns = vim.api.nvim_create_namespace("treeview_error")
  for _, hl in ipairs(hl_lines) do
    vim.api.nvim_buf_set_extmark(buf, ns, hl.line, 0, {
      end_col = #err_msg,
      hl_group = hl.hl,
    })
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = #lines,
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
  })
  local function close()
    vim.api.nvim_win_close(win, true)
  end
  -- any key closes: map a broad set, or use a generic buffer-local catch-all
  for _, key in ipairs({ "<CR>", "<Esc>", "q", "y", "n" }) do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true })
  end
  vim.cmd("redraw")
  vim.fn.getchar()
  vim.api.nvim_win_close(win, true)
end

function M.execute(ops)
  local ok = true
  -- order matters: creates, then renames, then deletes
  local order = { create = 1, rename = 2, delete = 3 }
  table.sort(ops, function(a, b) return order[a.type] < order[b.type] end)
  --
  -- Prune delete ops whose path is inside another delete op in this batch,
  -- since deleting a directory (rf) already removes its descendants.
  local delete_dirs = {}
  for _, op in ipairs(ops) do
    if op.type == "delete" and op_is_dir(op.path) then
      table.insert(delete_dirs, op.path)
    end
  end
  if #delete_dirs > 0 then
    local filtered = {}
    for _, op in ipairs(ops) do
      local skip = false
      if op.type == "delete" then
        for _, dir in ipairs(delete_dirs) do
          if op.path ~= dir and op.path:sub(1, #dir) == dir then
            skip = true
            break
          end
        end
      end
      if not skip then
        table.insert(filtered, op)
      end
    end
    ops = filtered
  end

  for _, op in ipairs(ops) do
    local success, err
    if op.type == "create" then
      if op_is_dir(op.path) then
        success, err = vim.uv.fs_mkdir(op.path, 493)
      else
        success = vim.fn.writefile({}, op.path) == 0
      end
    elseif op.type == "rename" then
      success, err = vim.uv.fs_rename(op.from, op.to)
    elseif op.type == "delete" then
      success = vim.fn.delete(op.path, "rf") == 0
    end
    if not success then
      ok = false
      vim.notify(("Failed %s: %s"):format(op.type, err or op.path), vim.log.levels.ERROR)
    end
  end
  return ok
end

return M
