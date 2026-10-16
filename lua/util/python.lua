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

---@return string[]
function M.managed_patterns()
  local home = vim.env.HOME or ""
  local data_home = vim.env.XDG_DATA_HOME or vim.fs.joinpath(home, ".local", "share")
  return {
    vim.fs.joinpath(vim.env.MISE_DATA_DIR or vim.fs.joinpath(data_home, "mise"), "installs", "python", "*", "bin", "python3"),
    vim.fs.joinpath(vim.env.UV_PYTHON_INSTALL_DIR or vim.fs.joinpath(data_home, "uv", "python"), "*", "bin", "python3"),
    vim.fs.joinpath(vim.env.PYENV_ROOT or vim.fs.joinpath(home, ".pyenv"), "versions", "*", "bin", "python3"),
    vim.fs.joinpath(vim.env.ASDF_DATA_DIR or vim.fs.joinpath(home, ".asdf"), "installs", "python", "*", "bin", "python3"),
  }
end

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

---@return string[]
function M.candidates()
  local found = {}
  for _, pattern in ipairs(M.managed_patterns()) do
    local paths = vim.fn.glob(pattern, false, true)
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

---@param python string
---@return string|nil
function M.replacement_for(python)
  if python ~= "" and M.makes_venvs(python) then
    return nil
  end

  for _, candidate in ipairs(M.candidates()) do
    if M.makes_venvs(candidate) then
      return candidate
    end
  end
end

---@param path string
---@param directory string
---@return string
function M.path_without(path, directory)
  local entries = vim.split(path, ":", { plain = true })
  for index, entry in ipairs(entries) do
    if entry == directory then
      table.remove(entries, index)
      break
    end
  end
  return table.concat(entries, ":")
end

---@param registry { on: fun(self, event: string, handler: fun(handle: { once: fun(self, event: string, handler: fun()) })) }
function M.prefer_usable_while_installing(registry)
  local installs_in_progress = 0
  local prepended_directory = nil

  registry:on("package:install:handle", function(handle)
    if installs_in_progress == 0 then
      local replacement = M.replacement_for(vim.fn.exepath("python3"))
      prepended_directory = replacement and vim.fs.dirname(replacement)
      if prepended_directory then
        vim.env.PATH = prepended_directory .. ":" .. (vim.env.PATH or "")
      end
    end
    installs_in_progress = installs_in_progress + 1

    handle:once(
      "closed",
      vim.schedule_wrap(function()
        installs_in_progress = installs_in_progress - 1
        if installs_in_progress == 0 and prepended_directory then
          vim.env.PATH = M.path_without(vim.env.PATH or "", prepended_directory)
          prepended_directory = nil
        end
      end)
    )
  end)
end

return M
