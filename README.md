# tree-view.nvim

A small filesystem tree viewer for Neovim.

## Installation

Using lazy.nvim:

```lua
{
    "YOUR_GITHUB_USERNAME/tree-view.nvim",
    dependencies = {
        "nvim-tree/nvim-web-devicons",
        { "nvim-mini/mini.icons", opts = {} },
    },
    config = function()
        require("tree-view").setup({
            width = 40,
            side = "left",
        })
    end,
}
```

## Usage

```lua
    vim.keymap.set("n", "<leader>T", function()
        require("tree-view").toggle()
    end, { desc = "Toggle tree view" })
```
