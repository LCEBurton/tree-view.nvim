local M = {}

M.options = {}
M.project_root = nil

-- Configuration
local defaults = {
  width = 50,
  side = "left", -- or "right"
  gitignore = true,
  ignore_patterns = {
    "^node_modules$",
    "^%.cache$",

    -- Python stuff
    "^__pycache__$",
    "^__init__.py$",

    "^%.", -- ignore hidden files
    "%.egg%-info$",
  },
  markers = { ".git", ".context" },
}

function M.find_project_root(options)
  local cwd = vim.fn.getcwd()

  local root = vim.fs.root(cwd, options.markers)

  return root
end
--
-- Convert a single gitignore line into a lua pattern matching a basename.
-- Only supports simple glob-style patterns (no "/" handling, no "**").
local function gitignore_line_to_pattern(line)
  line = vim.trim(line)
  if line == "" or line:sub(1, 1) == "#" then
    return nil
  end

  -- Strip trailing slash (directory-only marker)
  line = line:gsub("/$", "")

  -- Skip negation patterns and patterns containing a slash (path-relative),
  -- since should_ignore only matches against basenames.
  if line:sub(1, 1) == "!" or line:find("/") then
    return nil
  end

  -- Escape lua pattern magic characters, then re-expand glob wildcards.
  local escaped = line:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", function(c)
    if c == "*" or c == "?" then
      return c -- handle below
    end
    return "%" .. c
  end)

  escaped = escaped:gsub("%*", ".*"):gsub("%?", ".")

  return "^" .. escaped .. "$"
end

-- Read a .gitignore file at `root` and return a list of lua patterns.
local function parse_gitignore(root)
  local path = (root or vim.fn.getcwd()) .. "/.gitignore"
  local f = io.open(path, "r")
  if not f then
    return {}
  end

  local patterns = {}
  for line in f:lines() do
    local pattern = gitignore_line_to_pattern(line)
    if pattern then
      table.insert(patterns, pattern)
    end
  end
  f:close()

  return patterns
end

function M.setup(opts)
  opts = opts or {}

  local ignore_patterns = vim.list_extend(
    vim.deepcopy(defaults.ignore_patterns),
    opts.ignore_patterns or {}
  )

  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  M.options.ignore_patterns = ignore_patterns

  M.project_root = M.find_project_root(M.options)

  if M.options.gitignore then
    local gitignore_patterns = parse_gitignore(opts.root)
    M.options.ignore_patterns = vim.list_extend(M.options.ignore_patterns, gitignore_patterns)
  end

end

return M
