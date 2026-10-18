-- Quick manual check for watcher leaks.
-- Run with :luafile scripts/test_watcher_leak.lua after opening tree-view
-- on a temp directory, or adapt into plenary.busted test.

local state = require("treeview.state")
local source = require("treeview.source")

local function count_watchers()
  local n = 0
  for _ in pairs(state.watchers) do n = n + 1 end
  return n
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.mkdir(root .. "/a", "p")
vim.fn.mkdir(root .. "/b", "p")

source.build_tree(root)
source.sync_watchers()
local before = count_watchers()
print("watchers after initial sync:", before)
assert(before == 3, "expected 3 watchers (root, a, b), got " .. before) -- root + a + b

-- simulate directory removal
vim.fn.delete(root .. "/b", "rf")
source.build_tree(root)
source.sync_watchers()
local after_delete = count_watchers()
print("watchers after delete:", after_delete)
assert(after_delete == 2, "expected 2 watchers after delete, got " .. after_delete)

-- simulate re-sync with no changes (should stay same, not duplicate)
source.sync_watchers()
local after_resync = count_watchers()
print("watchers after resync (no change):", after_resync)
assert(after_resync == 2, "watcher count changed on no-op resync: " .. after_resync)

-- cleanup
for path, handle in pairs(state.watchers) do
  handle:stop()
  if not handle:is_closing() then handle:close() end
  state.watchers[path] = nil
end
vim.fn.delete(root, "rf")

print("OK: no watcher leak detected")
