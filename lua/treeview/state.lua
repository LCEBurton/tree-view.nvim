
local M = {
  nodes = {},
  lines = {},
  hls = {},
  collapsed = {},
  watchers = {},
  file_win = nil,
  tree_win = nil,
  tree_buf = nil,
  project_root = nil,
  edit_mode = false,
  old_nodes = nil,
  identity = {},
  identity_ns = nil,
}

return M
