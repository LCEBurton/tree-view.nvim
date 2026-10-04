local M = {}

local config = require("treeview.config")
local state = require("treeview.state")

-- Node fs structure
-- { level = 0, name = "file.type", type = "type", path = "path/to/file", prefix = "prefix" }
--
-- Do we split up entries containg pure fs info and UI containing prefix/icons/hls/fold status?
-- Can we buld prefix from level? Should be possible
-- Only node should be tree like, we should be able to generate lines and hls from node
-- Node is not truly tree like, just contains level information


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
    return
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

  for _, entry in ipairs(entries) do
    local node = {
      level = level,
      name = entry.name,
      type = entry.type,
      path = path .. "/" .. entry.name,
    }
    table.insert(state.nodes, node)

    if entry.type == "directory" then
      build_node(node.path, level + 1)
    end
  end
end

function M.build_tree(path)
  state.nodes = { {
    level = 0,
    name = vim.fn.fnamemodify(path, ":t"),
    type = "directory",
    path = path,
  }, }
  build_node(path, 1)
end

return M
