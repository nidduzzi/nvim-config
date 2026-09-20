local M = {}

---@return string
function M.store()
  return vim.fs.joinpath(vim.fn.stdpath("state") --[[@as string]], "trusted-projects")
end

--- The directory's identity, as the filesystem knows it.
---
--- A path is not one: /tmp/work can be deleted and made again by something
--- else, and a store that remembers only the path would hand that new
--- directory the trust you gave the old one --- which, here, means running
--- programs out of it.
---
--- The inode alone is not enough. A directory deleted and immediately made
--- again is routinely given the same one back, which is what happened the
--- first time this was written: the spec that deletes and recreates a
--- directory still read as trusted. Creation time separates them --- the two
--- differ by a millisecond there, and nanoseconds are recorded.
---@param path string
---@return string|nil
local function identity(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local born = stat.birthtime or stat.ctime
  return ("%d:%d:%d.%d"):format(stat.dev, stat.ino, born.sec, born.nsec)
end

--- Trusted roots, as path to the identity recorded with it.
---
--- A line is `path\tidentity`. A line with no identity is from an older
--- store: it is dropped rather than honoured, so the question is asked once
--- more and answered with something checkable.
---@return table<string, string>
local function read_store()
  local trusted = {}
  local path = M.store()
  if vim.uv.fs_stat(path) then
    for _, line in ipairs(vim.fn.readfile(path)) do
      local root, recorded = line:match("^(.-)\t(.+)$")
      if root and vim.trim(root) ~= "" and not root:match("^#") then
        trusted[vim.trim(root)] = vim.trim(recorded)
      end
    end
  end
  return trusted
end

---@param root string
---@return string
local function canonical(root)
  return vim.uv.fs_realpath(root) or root
end

---@param root string
---@return boolean
function M.is_trusted(root)
  local path = canonical(root)
  local recorded = read_store()[path]
  return recorded ~= nil and recorded == identity(path)
end

---@param root string
function M.allow(root)
  local path = canonical(root)
  local now = identity(path)
  if not now then
    return
  end

  local store = M.store()
  vim.fn.mkdir(vim.fs.dirname(store), "p")

  local kept = {}
  for _, line in ipairs(vim.uv.fs_stat(store) and vim.fn.readfile(store) or {}) do
    local existing = line:match("^(.-)\t")
    if existing ~= path then
      table.insert(kept, line)
    end
  end

  table.insert(kept, ("%s\t%s"):format(path, now))
  vim.fn.writefile(kept, store)
end

---@param root string
function M.revoke(root)
  local path = canonical(root)
  local store = M.store()
  if not vim.uv.fs_stat(store) then
    return
  end

  local kept = {}
  for _, line in ipairs(vim.fn.readfile(store)) do
    if (line:match("^(.-)\t") or vim.trim(line)) ~= path then
      table.insert(kept, line)
    end
  end
  vim.fn.writefile(kept, store)
end

--- Every root still trusted: still on disk, and still the same directory.
---@return string[]
function M.all()
  local roots = {}
  for root, recorded in pairs(read_store()) do
    if recorded == identity(root) then
      roots[#roots + 1] = root
    end
  end
  table.sort(roots)
  return roots
end

return M
