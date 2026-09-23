--- Files this editor writes about you, kept to your own account.
---
--- The state directory holds what you asked the agent, which projects you
--- have trusted, and which conversation belongs to which project. None of it
--- is a secret in the sense of a key, and all of it is about you: on a shared
--- machine the default of world-readable means the next account along can
--- read your questions.
---
--- Neovim writes with the process umask, which is usually 0022 and so 0644.
--- These are written and then narrowed, because there is no way to ask
--- writefile for a mode.
---
--- On Windows the mode bits do not exist: NTFS reports 666 whatever chmod is
--- asked for, and privacy is an access control list. The calls below are
--- harmless there, and the state directory is already under the user's own
--- AppData.

local M = {}

--- Owner only, for a file.
M.file_mode = tonumber("600", 8)

--- Owner only, for a directory, which also needs the execute bit to be
--- entered at all.
M.directory_mode = tonumber("700", 8)

--- Make a directory nobody else can read, and narrow what is already in it.
---
--- The files inside matter as much as the directory: a state directory that
--- existed before this was written holds world-readable files, and making the
--- directory private does not change their mode. Only the files directly
--- inside, because these directories hold a flat list and walking a tree on
--- every write is not what this is for.
---@param path string
function M.mkdir(path)
  vim.fn.mkdir(path, "p")
  pcall(vim.uv.fs_chmod, path, M.directory_mode)

  for name, kind in vim.fs.dir(path) do
    if kind == "file" then
      pcall(vim.uv.fs_chmod, vim.fs.joinpath(path, name), M.file_mode)
    end
  end
end

--- Write lines to a file nobody else can read.
---@param path string
---@param lines string[]
function M.writefile(path, lines)
  vim.fn.writefile(lines, path)
  pcall(vim.uv.fs_chmod, path, M.file_mode)
end

--- Narrow a file this module did not write, when one is opened for writing
--- through another route.
---@param path string
function M.narrow(path)
  pcall(vim.uv.fs_chmod, path, M.file_mode)
end

return M
