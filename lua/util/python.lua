--- A Python that can make a virtualenv.
---
--- Mason installs a Python package by creating a virtualenv with whatever
--- `python3` is on PATH, and a distribution's python3 often cannot: Debian
--- and its descendants ship `ensurepip` in a separate `python3-venv` package,
--- so `:MasonInstall debugpy` fails with `spawn: python3 failed with exit
--- code 1` and nothing about what is missing.
---
--- A machine that has mise, uv or pyenv has a Python that can, and it is
--- already on disk. This finds it.

local M = {}

--- Where a version manager keeps the interpreters it installed, relative to
--- the home directory. Globs, because each keeps one directory per version.
---@type string[]
M.managed = {
  ".local/share/mise/installs/python/*/bin/python3",
  ".local/share/uv/python/*/bin/python3",
  ".pyenv/versions/*/bin/python3",
  ".asdf/installs/python/*/bin/python3",
}

--- Can this interpreter create a virtualenv?
---
--- Asked of the interpreter rather than assumed from its version, because
--- what is missing is a package the distribution split out, not a feature of
--- the language.
---@param python string
---@return boolean
function M.makes_venvs(python)
  if vim.fn.executable(python) ~= 1 then
    return false
  end
  vim.fn.system({ python, "-c", "import ensurepip" })
  return vim.v.shell_error == 0
end

--- Interpreters this machine has, most recently installed first, so a version
--- manager's newest is preferred over its oldest.
---@return string[]
function M.candidates()
  local found = {}
  for _, pattern in ipairs(M.managed) do
    local paths = vim.fn.glob(vim.fs.joinpath(vim.env.HOME or "", pattern), false, true)
    table.sort(paths, function(a, b)
      return a > b
    end)
    vim.list_extend(found, paths)
  end
  return found
end

--- The first Python on this machine that can create a virtualenv, or nil.
---@return string|nil
function M.usable()
  local on_path = vim.fn.exepath("python3")
  if on_path ~= "" and M.makes_venvs(on_path) then
    return on_path
  end

  for _, candidate in ipairs(M.candidates()) do
    if M.makes_venvs(candidate) then
      return candidate
    end
  end
end

--- Put a Python that works ahead of one that does not.
---
--- A side effect, and the only one here: it changes what `python3` means for
--- every process the editor starts. That is the point --- Mason is not the
--- only thing that asks for python3 and then needs a virtualenv --- and it
--- happens only when the one on PATH cannot do the job.
---@return string|nil what was put in front, if anything
function M.prefer_usable()
  local on_path = vim.fn.exepath("python3")
  if on_path ~= "" and M.makes_venvs(on_path) then
    return nil
  end

  for _, candidate in ipairs(M.candidates()) do
    if M.makes_venvs(candidate) then
      vim.env.PATH = vim.fs.dirname(candidate) .. ":" .. (vim.env.PATH or "")
      return candidate
    end
  end
end

return M
