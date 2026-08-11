# tree-view.nvim

A small filesystem tree viewer for Neovim.

## Installation

Using lazy.nvim:

```lua
{
    "LCEBurton/tree-view.nvim",
    dependencies = {
        "nvim-tree/nvim-web-devicons",
        { "nvim-mini/mini.icons", opts = {} },
    },
    config = function()
        require("tree-view").setup({
            width = 40,         -- Min width - extended if line length is greater than width value
            side = "left",      -- Side plugin opens on
            ignore_patterns = { -- Patterns to be ignored - default list included and values are appended
                "%.pyc$",
                "%.o$",
            },
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

```
    In tree-view buffer
    q - closes tree-view
    r - refreshes tree-view
    <CR> - Opens file under cursor in new window. Subsequent file opens will be opened in the same created window
```

## TODO

Display status of git if .git exists
Allow parsing of .gitignore files to configure ignore list
Folding directories
