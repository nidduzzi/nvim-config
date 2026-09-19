-- Debuggers for the compiled languages, and for Julia.
--
-- lazyvim.plugins.extras.dap.core brings nvim-dap and installs debugpy and the
-- JavaScript adapter, which covers Python, TypeScript and TSX. Rust, C, C++
-- and Julia are not covered by anything this configuration loads.
--
-- LazyVim's lang.rust and lang.clangd extras would add them, and also
-- rustaceanvim, crates.nvim and clangd_extensions, each of which decides for
-- itself which language server to start. This configuration attaches only what
-- a project provides (see util/lsp.lua), so the adapters are taken and the
-- rest is left. See DECISIONS.md.
--
-- codelldb speaks to Rust, C and C++ alike; it is LLDB with a DAP front end.
-- Julia has no adapter in any distribution: DebugAdapter.jl is a package the
-- project itself must depend on, so it is wired up only when the project has
-- it.
local function codelldb_configuration(name)
  return {
    {
      type = "codelldb",
      request = "launch",
      name = "Launch " .. name .. " executable",
      program = function()
        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
      end,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
    },
    {
      type = "codelldb",
      request = "attach",
      name = "Attach to a running process",
      pid = function()
        return require("dap.utils").pick_process()
      end,
      cwd = "${workspaceFolder}",
    },
  }
end

local function julia_configuration()
  return {
    {
      type = "julia",
      request = "launch",
      name = "Run this file",
      program = "${file}",
      cwd = "${workspaceFolder}",
      juliaEnv = "${workspaceFolder}",
    },
  }
end

---@param root string
---@return string|nil
local function project_python(root)
  local trust = require("util.trust")
  for _, dir in ipairs(require("util.lsp").bin_dirs(root)) do
    for _, candidate in ipairs(vim.fn.glob(root .. "/" .. dir .. "/python", false, true)) do
      if vim.fn.executable(candidate) == 1 then
        return trust.is_trusted(root) and candidate or nil
      end
    end
  end
end

---@return string[]|nil argv
---@return string|nil why_not
local function debugpy_command()
  local root = require("util.lsp").root(vim.fn.getcwd())

  local python = project_python(root)
  if python then
    return { python, "-m", "debugpy.adapter" }
  end

  if vim.fn.executable("debugpy-adapter") == 1 then
    return { vim.fn.exepath("debugpy-adapter") }
  end

  local venv = #require("util.lsp").bin_dirs(root) > 0
  if venv then
    return nil,
      "This project has a Python environment, but it is not trusted.\n\n:DotfilesTrustProject to debug with it, or install debugpy with :MasonInstall debugpy."
  end
  return nil, "No debugpy. Install it in the project, or with :MasonInstall debugpy."
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
      dap.adapters.python = function(callback, config)
        local argv, why_not = debugpy_command()
        if not argv then
          vim.notify(why_not, vim.log.levels.ERROR, { title = "Python debugger" })
          return
        end
        callback({
          type = "executable",
          command = argv[1],
          args = vim.list_slice(argv, 2),
          options = { source_filetype = "python" },
          enrich_config = function(cfg, on_config)
            cfg.pythonPath = cfg.pythonPath or argv[1]
            on_config(cfg)
          end,
        })
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

      dap.adapters.codelldb = dap.adapters.codelldb
        or {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "codelldb",
            args = { "--port", "${port}" },
          },
        }

      for _, language in ipairs({ "rust", "c", "cpp" }) do
        dap.configurations[language] = dap.configurations[language] or codelldb_configuration(language)
      end

      -- Started through the project's own Julia, because DebugAdapter is a
      -- dependency of the project rather than a tool the editor installs.
      dap.adapters.julia = dap.adapters.julia
        or {
          type = "executable",
          command = "julia",
          args = {
            "--project=.",
            "-e",
            [[using DebugAdapter; DebugAdapter.run_debugger(stdin, stdout)]],
          },
        }

      dap.configurations.julia = dap.configurations.julia or julia_configuration()
    end,
  },
}
