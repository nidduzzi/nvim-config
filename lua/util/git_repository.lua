local M = {}

---@class git_repository.Location
---@field worktree string the directory holding `.git`
---@field gitdir string
---@field commondir string shared by every worktree of the repository

---@class git_repository.ConfigEntry
---@field file string
---@field key string
---@field value string

---@type string[]
M.harmless_keys = {
  "^core%.repositoryformatversion$",
  "^core%.filemode$",
  "^core%.bare$",
  "^core%.logallrefupdates$",
  "^core%.ignorecase$",
  "^core%.precomposeunicode$",
  "^core%.symlinks$",
  "^core%.autocrlf$",
  "^core%.eol$",
  "^core%.safecrlf$",
  "^core%.quotepath$",
  "^core%.longpaths$",
  "^core%.checkstat$",
  "^core%.trustctime$",
  "^core%.untrackedcache$",
  "^core%.splitindex$",
  "^core%.commitgraph$",
  "^core%.sparsecheckout$",
  "^core%.sparsecheckoutcone$",
  "^core%.abbrev$",
  "^core%.compression$",
  "^extensions%.worktreeconfig$",
  "^extensions%.objectformat$",
  "^extensions%.refstorage$",
  "^extensions%.partialclone$",
  "^remote%..+%.url$",
  "^remote%..+%.pushurl$",
  "^remote%..+%.fetch$",
  "^remote%..+%.push$",
  "^remote%..+%.tagopt$",
  "^remote%..+%.prune$",
  "^remote%..+%.prunetags$",
  "^remote%..+%.mirror$",
  "^remote%..+%.promisor$",
  "^remote%..+%.partialclonefilter$",
  "^remote%..+%.skipdefaultupdate$",
  "^remote%..+%.skipfetchall$",
  "^remote%..+%.followremotehead$",
  "^remote%..+%.gh%-resolved$",
  "^remote%..+%.glab%-resolved%-head$",
  "^branch%..+%.[%w%-]+$",
  "^submodule%..+%.url$",
  "^submodule%..+%.active$",
  "^submodule%..+%.branch$",
  "^submodule%..+%.ignore$",
  "^submodule%..+%.fetchrecursesubmodules$",
  "^submodule%..+%.shallow$",
  "^submodule%.recurse$",
  "^submodule%.active$",
  "^user%.name$",
  "^user%.email$",
  "^user%.signingkey$",
  "^user%.useconfigonly$",
  "^gpg%.format$",
  "^commit%.gpgsign$",
  "^tag%.gpgsign$",
  "^rerere%.enabled$",
  "^rerere%.autoupdate$",
  "^secrets%.patterns$",
  "^secrets%.allowed$",
  "^secrets%.providers$",
  "^pull%.rebase$",
  "^pull%.ff$",
  "^push%.default$",
  "^push%.autosetupremote$",
  "^fetch%.prune$",
  "^init%.defaultbranch$",
  "^lfs%.repositoryformatversion$",
}

---@param key string as `git config --list` prints it: section and name lowercased
---@return boolean
function M.is_harmless_key(key)
  for _, pattern in ipairs(M.harmless_keys) do
    if key:match(pattern) then
      return true
    end
  end
  return false
end

---@param path string
---@return string|nil
local function read_first_line(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local line = file:read("*l")
  file:close()
  return line and vim.trim(line) or nil
end

---@param base string
---@param path string
---@return string
local function absolute(base, path)
  if vim.startswith(path, "/") or path:match("^%a:[/\\]") then
    return vim.fs.normalize(path)
  end
  return vim.fs.normalize(vim.fs.joinpath(base, path))
end

---@param start string
---@return git_repository.Location|nil
function M.locate(start)
  local dot_git = vim.fs.find(".git", { path = start, upward = true })[1]
  if not dot_git then
    return nil
  end

  local worktree = vim.fs.dirname(dot_git)
  local gitdir = dot_git
  local stat = vim.uv.fs_stat(dot_git)
  if stat and stat.type == "file" then
    local pointer = (read_first_line(dot_git) or ""):match("^gitdir:%s*(.+)$")
    if not pointer then
      return nil
    end
    gitdir = absolute(worktree, pointer)
  end

  local commondir_pointer = read_first_line(vim.fs.joinpath(gitdir, "commondir"))
  local commondir = commondir_pointer and absolute(gitdir, commondir_pointer) or gitdir

  return { worktree = worktree, gitdir = gitdir, commondir = commondir }
end

---@param location git_repository.Location
---@return string[]
function M.config_files(location)
  local files = {}
  for _, candidate in ipairs({
    vim.fs.joinpath(location.commondir, "config"),
    vim.fs.joinpath(location.gitdir, "config"),
    vim.fs.joinpath(location.commondir, "config.worktree"),
    vim.fs.joinpath(location.gitdir, "config.worktree"),
  }) do
    if vim.uv.fs_stat(candidate) and not vim.tbl_contains(files, candidate) then
      files[#files + 1] = candidate
    end
  end
  return files
end

---@param file string
---@return git_repository.ConfigEntry[] entries
---@return string|nil unreadable why git could not read the file
function M.read_config(file)
  local result = vim
    .system({ "git", "config", "--file", file, "--no-includes", "--null", "--list" }, {
      cwd = vim.fs.dirname(file),
      text = true,
    })
    :wait()
  if result.code ~= 0 then
    return {}, vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or ("git config exited " .. result.code)
  end

  local entries = {}
  for record in vim.gsplit(result.stdout or "", "\0", { plain = true, trimempty = true }) do
    local key, value = record:match("^([^\n]*)\n?(.*)$")
    entries[#entries + 1] = { file = file, key = key, value = value }
  end
  return entries, nil
end

---@param location git_repository.Location
---@return string[]
function M.hooks(location)
  local directory = vim.fs.joinpath(location.commondir, "hooks")
  local found = {}
  if not vim.uv.fs_stat(directory) then
    return found
  end
  for name, kind in vim.fs.dir(directory) do
    if kind ~= "directory" and not name:match("%.sample$") then
      found[#found + 1] = vim.fs.joinpath(directory, name)
    end
  end
  table.sort(found)
  return found
end

---@class git_repository.Programs
---@field entries git_repository.ConfigEntry[] settings not known to be harmless
---@field hooks string[]

---@param location git_repository.Location
---@return git_repository.Programs
function M.programs(location)
  local entries = {}
  for _, file in ipairs(M.config_files(location)) do
    local read, unreadable = M.read_config(file)
    if unreadable then
      entries[#entries + 1] = { file = file, key = "(unreadable)", value = unreadable }
    end
    for _, entry in ipairs(read) do
      if not M.is_harmless_key(entry.key) then
        entries[#entries + 1] = entry
      end
    end
  end
  return { entries = entries, hooks = M.hooks(location) }
end

---@param start string
---@return boolean
function M.names_no_programs(start)
  local location = M.locate(start)
  if not location then
    return false
  end
  local programs = M.programs(location)
  return #programs.entries == 0 and #programs.hooks == 0
end

return M
