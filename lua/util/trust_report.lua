local M = {}

---@class trust_report.Program
---@field path string
---@field target string
---@field leaves_project boolean
---@field first_line string
---@field package? string name@version, for a program installed by a Node package
---@field lockfile? string what the project's lockfile says about that package

---@class trust_report.ProgramDirectory
---@field directory string relative to the project
---@field python_home? string the `home` a virtualenv was made from
---@field programs trust_report.Program[]

---@class trust_report.Report
---@field root string
---@field directories trust_report.ProgramDirectory[]
---@field git? git_repository.Programs
---@field git_worktree? string
---@field agent_files string[]

---@param path string
---@return string
local function first_line(path)
  local file = io.open(path, "rb")
  if not file then
    return "(unreadable)"
  end
  local head = file:read(200) or ""
  file:close()
  if vim.startswith(head, "#!") then
    return vim.trim(head:match("^[^\n]*"))
  end
  return "(not a script)"
end

---@param path string
---@return table|nil
local function read_json(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  local ok, decoded = pcall(vim.json.decode, text)
  return ok and type(decoded) == "table" and decoded or nil
end

---@param path string
---@return string|nil
local function read_text(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

---@param target string resolved path of a program under node_modules
---@return string|nil name
local function node_package_name(target)
  local after = target:match(".*/node_modules/(.+)$")
  if not after then
    return nil
  end
  return after:match("^(@[^/]+/[^/]+)") or after:match("^([^/]+)")
end

---@param root string
---@param name string
---@param version string
---@return string
local function lockfile_says(root, name, version)
  local npm_lock = read_json(vim.fs.joinpath(root, "package-lock.json"))
  if npm_lock then
    local locked = (npm_lock.packages or {})["node_modules/" .. name]
    if not locked then
      return "not in package-lock.json"
    end
    if locked.version ~= version then
      return ("package-lock.json pins %s, installed is %s"):format(tostring(locked.version), version)
    end
    return locked.integrity and "pinned in package-lock.json with an integrity hash" or "pinned in package-lock.json, no integrity hash"
  end

  for _, lockfile in ipairs({ "pnpm-lock.yaml", "bun.lock" }) do
    local text = read_text(vim.fs.joinpath(root, lockfile))
    if text then
      if text:find(name .. "@" .. version, 1, true) then
        return ("%s lists %s@%s"):format(lockfile, name, version)
      end
      return ("%s does not list %s@%s"):format(lockfile, name, version)
    end
  end

  local yarn_lock = read_text(vim.fs.joinpath(root, "yarn.lock"))
  if yarn_lock then
    local entry_start = yarn_lock:find('\n"?' .. vim.pesc(name) .. "@")
    local entry = entry_start and yarn_lock:sub(entry_start, (yarn_lock:find("\n\n", entry_start, true) or #yarn_lock))
    if entry and entry:find('version "' .. version .. '"', 1, true) then
      return ("yarn.lock lists %s@%s"):format(name, version)
    end
    return ("yarn.lock does not list %s@%s"):format(name, version)
  end
  return "no lockfile"
end

---@param root string
---@param directory string relative to root
---@return trust_report.ProgramDirectory
local function program_directory(root, directory)
  local absolute = vim.fs.joinpath(root, directory)
  local venv_config = vim.fs.joinpath(vim.fs.dirname(absolute), "pyvenv.cfg")
  local venv_text = read_text(venv_config)

  local programs = {}
  for name, kind in vim.fs.dir(absolute) do
    local path = vim.fs.joinpath(absolute, name)
    if kind ~= "directory" and vim.fn.executable(path) == 1 then
      local target = vim.uv.fs_realpath(path) or path
      local relative = vim.fs.relpath(root, target)
      local program = {
        path = vim.fs.joinpath(directory, name),
        target = target,
        leaves_project = relative == nil,
        first_line = first_line(target),
      }
      local package_name = node_package_name(target)
      if package_name then
        local manifest = read_json(vim.fs.joinpath(root, "node_modules", package_name, "package.json")) or {}
        local version = tostring(manifest.version or "?")
        program.package = package_name .. "@" .. version
        program.lockfile = lockfile_says(root, package_name, version)
      end
      programs[#programs + 1] = program
    end
  end
  table.sort(programs, function(a, b)
    return a.path < b.path
  end)

  return {
    directory = directory,
    python_home = venv_text and vim.trim(venv_text:match("home%s*=%s*([^\n]+)") or "") or nil,
    programs = programs,
  }
end

M.agent_instruction_files = {
  "CLAUDE.md",
  "CLAUDE.local.md",
  ".claude/CLAUDE.md",
  ".claude/settings.json",
  ".claude/settings.local.json",
  "AGENTS.md",
}

---@param root string
---@return trust_report.Report
function M.collect(root)
  local lsp = require("util.lsp")
  local repository = require("util.git_repository")

  local directories = {}
  for _, directory in ipairs(lsp.bin_dirs(root)) do
    if vim.fn.isdirectory(vim.fs.joinpath(root, directory)) == 1 then
      directories[#directories + 1] = program_directory(root, directory)
    end
  end

  local location = repository.locate(root)

  local agent_files = {}
  for _, relative in ipairs(M.agent_instruction_files) do
    if vim.uv.fs_stat(vim.fs.joinpath(root, relative)) then
      agent_files[#agent_files + 1] = relative
    end
  end
  for _, rule in ipairs(vim.fn.glob(vim.fs.joinpath(root, ".claude", "rules", "*.md"), false, true)) do
    agent_files[#agent_files + 1] = vim.fs.relpath(root, rule) or rule
  end

  return {
    root = root,
    directories = directories,
    git = location and repository.programs(location) or nil,
    git_worktree = location and location.worktree or nil,
    agent_files = agent_files,
  }
end

---@param report trust_report.Report
---@return string[]
function M.lines(report)
  local home = function(path)
    return vim.fn.fnamemodify(path, ":~")
  end
  local lines = {
    "# What trusting " .. home(report.root) .. " runs",
    "",
    "Nothing here was run to build this list. <leader>gt to decide.",
    "",
    "## Programs from the project",
    "",
  }

  if #report.directories == 0 then
    lines[#lines + 1] = "None: no virtualenv, node_modules/.bin or other program directory."
  end
  for _, directory in ipairs(report.directories) do
    lines[#lines + 1] = ("### %s (%d programs)"):format(directory.directory, #directory.programs)
    if directory.python_home then
      lines[#lines + 1] = "virtualenv made from: " .. directory.python_home
    end
    for _, program in ipairs(directory.programs) do
      local is_link = program.target ~= vim.fs.joinpath(report.root, program.path)
      if program.leaves_project then
        lines[#lines + 1] = ("- %s -> OUTSIDE the project: %s"):format(program.path, home(program.target))
      elseif is_link then
        lines[#lines + 1] = ("- %s -> %s"):format(program.path, vim.fs.relpath(report.root, program.target))
      else
        lines[#lines + 1] = "- " .. program.path
      end
      lines[#lines + 1] = "    " .. program.first_line
      if program.package then
        lines[#lines + 1] = ("    package %s, %s"):format(program.package, program.lockfile)
      end
    end
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## git"
  lines[#lines + 1] = ""
  if not report.git then
    lines[#lines + 1] = "Not a git repository."
  elseif #report.git.entries == 0 and #report.git.hooks == 0 then
    lines[#lines + 1] = "The repository's own config and hooks name no programs: git runs here without trust."
  else
    for _, entry in ipairs(report.git.entries) do
      lines[#lines + 1] = ("- %s = %s"):format(entry.key, entry.value)
      lines[#lines + 1] = "    in " .. home(entry.file)
    end
    for _, hook in ipairs(report.git.hooks) do
      lines[#lines + 1] = "- hook " .. home(hook)
      lines[#lines + 1] = "    " .. first_line(hook)
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Agent"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Trust lets the agent's edit rung write files here. These steer it:"
  if #report.agent_files == 0 then
    lines[#lines + 1] = "None."
  end
  for _, file in ipairs(report.agent_files) do
    lines[#lines + 1] = "- " .. file
  end
  return lines
end

---@param root string
function M.open(root)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.lines(M.collect(root)))
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
end

return M
