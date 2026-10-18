-- lua/treeview/init.lua

local M = {}

local config = require("treeview.config")
local state = require("treeview.state")
local ui = require("treeview.ui")

function M.setup(opts)
  config.setup(opts)
  state.project_root = config.project_root

  vim.api.nvim_create_user_command("TreeViewOpen", function()
    M.open()
  end, {})

  vim.api.nvim_create_user_command("TreeViewClose", function()
    M.close()
  end, {})

  vim.api.nvim_create_user_command("TreeViewToggle", function()
    M.toggle()
  end, {})

  vim.api.nvim_create_user_command("TreeViewReload", function()
    require("plenary.reload").reload_module("treeview")
    require("treeview").setup(opts)
  end, {})

  -- Reset project root and re-render tree when directory changes
  vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
      config.setup(opts)
      state.project_root = config.project_root
    end,
  })
end

function M.open()
  ui.open()
end

function M.close()
  ui.close()
end

function M.toggle()
  if state.tree_win and vim.api.nvim_win_is_valid(state.tree_win) then
    M.close()
  else
    M.open()
  end
end

return M
