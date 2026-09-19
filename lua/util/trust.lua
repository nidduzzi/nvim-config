local M = {}

---@return string
function M.store()
  return vim.fs.joinpath(vim.fn.stdpath("state") --[[@as string]], "trusted-projects")
end

---@return table<string, boolean>
local function read_store()
  local trusted = {}
  local path = M.store()
  if vim.uv.fs_stat(path) then
    for _, line in ipairs(vim.fn.readfile(path)) do
      local root = vim.trim(line)
      if root ~= "" and not root:match("^#") then
        trusted[root] = true
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
  return read_store()[canonical(root)] == true
end

---@param root string
function M.allow(root)
  local path = canonical(root)
  local trusted = read_store()
  if trusted[path] then
    return
  end

  local store = M.store()
  vim.fn.mkdir(vim.fs.dirname(store), "p")
  local lines = vim.uv.fs_stat(store) and vim.fn.readfile(store) or {}
  table.insert(lines, path)
  vim.fn.writefile(lines, store)
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
    if vim.trim(line) ~= path then
      table.insert(kept, line)
    end
  end
  vim.fn.writefile(kept, store)
end

---@return string[]
function M.all()
  local roots = vim.tbl_keys(read_store())
  table.sort(roots)
  return roots
end

return M
