-- Debuggers for the languages nothing else here covers.
--
-- lazyvim.plugins.extras.dap.core brings nvim-dap and covers Python,
-- JavaScript, TypeScript and TSX. LazyVim's lang.rust and lang.clangd extras
-- would add the rest and also rustaceanvim, crates.nvim and clangd_extensions,
-- each of which starts a language server on its own terms. This configuration
-- attaches only what a project provides, so the adapters are taken and the rest
-- is left. See DECISIONS.md.
--
-- Every path is resolved when a session starts, so moving a toolchain or
-- opening a different project needs no edit here.

local function project_root()
  return require("util.lsp").root(vim.fn.getcwd())
end

---@param root string
---@param name string
---@return string|nil
local function in_project(root, name)
  if not require("util.trust").is_trusted(root) then
    return nil
  end
  for _, dir in ipairs(require("util.lsp").bin_dirs(root)) do
    for _, candidate in ipairs(vim.fn.glob(vim.fs.joinpath(root, dir, name), false, true)) do
      if vim.fn.executable(candidate) == 1 then
        return candidate
      end
    end
  end
end

---@param root string
---@param name string
---@return string|nil
local function anywhere(root, name)
  return in_project(root, name) or (vim.fn.executable(name) == 1 and vim.fn.exepath(name) or nil)
end

---@param what string
---@param root string
---@return string
local function missing(what, root)
  if #require("util.lsp").bin_dirs(root) > 0 and not require("util.trust").is_trusted(root) then
    return ("%s may be in this project, which is not trusted.\n\n:DotfilesTrustProject to use it."):format(what)
  end
  return ("%s was not found in this project or on PATH."):format(what)
end

-- The DAP protocol does not say which languages an adapter speaks, so this
-- cannot be asked of the adapter. codelldb is LLDB, and these are what LLDB
-- debugs: a fact about the debugger rather than a preference.
local CODELLDB_FILETYPES = { "rust", "c", "cpp", "objc", "objcpp", "zig" }

---@param filetype string
---@param root string
local function codelldb_configurations(filetype, root)
  return {
    {
      type = "codelldb",
      request = "launch",
      name = "Launch a " .. filetype .. " executable",
      program = function()
        return vim.fn.input("Path to executable: ", root .. "/", "file")
      end,
      cwd = root,
      stopOnEntry = false,
    },
    {
      type = "codelldb",
      request = "attach",
      name = "Attach to a running process",
      pid = function()
        return require("dap.utils").pick_process()
      end,
      cwd = root,
    },
  }
end

---@param root string
local function julia_configurations(root)
  return {
    {
      type = "julia",
      request = "launch",
      name = "Run this file",
      program = "${file}",
      cwd = root,
      juliaEnv = root,
    },
  }
end

return {
  {
    "mfussenegger/nvim-dap-python",
    optional = true,
    config = function()
      local dap = require("dap")

      pcall(function()
        require("dap-python").setup("debugpy-adapter")
      end)

      dap.adapters.python = function(callback)
        local root = project_root()
        local python = in_project(root, "python") or in_project(root, "python3")

        if python then
          callback({
            type = "executable",
            command = python,
            args = { "-m", "debugpy.adapter" },
            options = { source_filetype = "python" },
            enrich_config = function(config, on_config)
              config.pythonPath = config.pythonPath or python
              on_config(config)
            end,
          })
          return
        end

        if vim.fn.executable("debugpy-adapter") == 1 then
          callback({
            type = "executable",
            command = vim.fn.exepath("debugpy-adapter"),
            options = { source_filetype = "python" },
          })
          return
        end

        vim.notify(missing("debugpy", root), vim.log.levels.ERROR, { title = "Python debugger" })
      end
    end,
  },

  {
    "mfussenegger/nvim-dap",
    optional = true,
    dependencies = {
      {
        "mason-org/mason.nvim",
        optional = true,
        opts = function(_, opts)
          opts.ensure_installed = opts.ensure_installed or {}
          table.insert(opts.ensure_installed, "codelldb")
        end,
      },
    },
    opts = function()
      local dap = require("dap")

      dap.adapters.codelldb = function(callback)
        local root = project_root()
        local command = anywhere(root, "codelldb")
        if not command then
          vim.notify(missing("codelldb", root), vim.log.levels.ERROR, { title = "Debugger" })
          return
        end
        callback({
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = { command = command, args = { "--port", "${port}" } },
        })
      end

      dap.adapters.julia = function(callback)
        local root = project_root()
        local command = anywhere(root, "julia")
        if not command then
          vim.notify(missing("julia", root), vim.log.levels.ERROR, { title = "Julia debugger" })
          return
        end
        callback({
          type = "executable",
          command = command,
          args = {
            "--project=" .. root,
            "-e",
            [[using DebugAdapter; DebugAdapter.run_debugger(stdin, stdout)]],
          },
        })
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("dotfiles_dap_configurations", { clear = true }),
        pattern = vim.list_extend({ "julia" }, CODELLDB_FILETYPES),
        callback = function(event)
          if dap.configurations[event.match] then
            return
          end
          local root = project_root()
          dap.configurations[event.match] = event.match == "julia" and julia_configurations(root) or codelldb_configurations(event.match, root)
        end,
      })
    end,
  },
}
