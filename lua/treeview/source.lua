local M = {}

local config = require("treeview.config")
local state = require("treeview.state")
local uv = vim.uv

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local has_mini, mini = pcall(require, "mini.icons")

-- Node fs structure
-- { level = 0, name = "file.type", type = "type", path = "path/to/file", prefix = "prefix" }
--
-- Do we split up entries containg pure fs info and UI containing prefix/icons/hls/fold status?
-- Can we buld prefix from level? Should be possible
-- Only node should be tree like, we should be able to generate lines and hls from node
-- Node is not truly tree like, just contains level information

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


-- Check if path should be ignored
local function should_ignore(name)
  for _, pattern in ipairs(config.options.ignore_patterns) do
    if name:match(pattern) then
      return true
    end
  end
  return false
end

local function build_node(path, level)
  local handle = vim.uv.fs_scandir(path)
  if not handle then
    return 0
  end
  local entries = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if not should_ignore(name) then
      table.insert(entries, {
        name = name,
        type = type,
        level = level,
      })
    end

  end
  table.sort(entries, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    end
    return a.type == "directory"
  end)
  local count = 0
  for _, entry in ipairs(entries) do
    local icon, hl = get_icon(entry.name, entry.type)
    local node = {
      level = level,
      name = entry.name,
      type = entry.type,
      path = path .. "/" .. entry.name,
      icon = icon,
      icon_hl = hl,
    }
    table.insert(state.nodes, node)
    count = count + 1
    if entry.type == "directory" then
      local child_count = build_node(node.path, level + 1)
      node.descendant_count = child_count
      count = count + child_count
    end

  end
  return count
end

function M.build_tree(path)
  local icon, hl = get_icon(vim.fn.fnamemodify(path, ":t"), "directory")
  state.nodes = { {
    level = 0,
    name = vim.fn.fnamemodify(path, ":t"),
    type = "directory",
    path = path,
    icon = icon,
    icon_hl = hl,
  }, }
  state.nodes[1].descendant_count = build_node(path, 1)
end

local debounce_timer = nil
local function on_change(err, filename, events)
  if err then return end
  if debounce_timer then
    debounce_timer:stop()
  end
  debounce_timer = uv.new_timer()
  if debounce_timer == nil then
    return
  end
  debounce_timer:start(100, 0, vim.schedule_wrap(function()
    require("treeview.ui").render()
  end))
end

function M.sync_watchers()
  local current = {}

  -- single pass: collect current dirs AND start new watchers
  for _, node in ipairs(state.nodes) do
    if node.type == "directory" then
      current[node.path] = true
      if not state.watchers[node.path] then
        local handle = uv.new_fs_event()
        if handle == nil then
          vim.notify("Failed to create fs_event handle for " .. node.path, vim.log.levels.ERROR)
          return
        end
        handle:start(node.path, {}, on_change)
        state.watchers[node.path] = handle
      end
    end
  end

  -- prune stale
  for path, handle in pairs(state.watchers) do
    if not current[path] then
      handle:stop()
      if not handle:is_closing() then handle:close() end
      state.watchers[path] = nil
    end
  end
end

return M
