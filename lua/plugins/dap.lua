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

-- Where a build puts its output, keyed on the file that proves the build
-- system is in use. A directory nobody's build system names is not searched.
local BUILD_OUTPUT = {
  ["Cargo.toml"] = { "target/debug", "target/release" },
  ["CMakeLists.txt"] = { "build", "cmake-build-debug", "cmake-build-release", "out" },
  ["Makefile"] = { ".", "build", "bin" },
  ["makefile"] = { ".", "build", "bin" },
  ["meson.build"] = { "build" },
  ["build.zig"] = { "zig-out/bin" },
}

---@param path string
---@return boolean
local function looks_runnable(path)
  if vim.fn.executable(path) ~= 1 or vim.fn.isdirectory(path) == 1 then
    return false
  end
  return not path:match("%.d$") and not path:match("%.o$") and not path:match("%.so[%.%d]*$")
end

---@param root string
---@return string[]
local function built_executables(root)
  local found, seen = {}, {}
  for marker, directories in pairs(BUILD_OUTPUT) do
    if vim.uv.fs_stat(vim.fs.joinpath(root, marker)) then
      for _, directory in ipairs(directories) do
        for _, path in ipairs(vim.fn.glob(vim.fs.joinpath(root, directory, "*"), false, true)) do
          if looks_runnable(path) and not seen[path] then
            seen[path] = true
            found[#found + 1] = path
          end
        end
      end
    end
  end

  -- A project built by hand has no marker and no build directory, so the
  -- binary sits next to its source. Only the root, and only when nothing
  -- else was found, so a real build tree is never trawled.
  if #found == 0 then
    for _, path in ipairs(vim.fn.glob(vim.fs.joinpath(root, "*"), false, true)) do
      if looks_runnable(path) then
        found[#found + 1] = path
      end
    end
  end

  table.sort(found, function(a, b)
    local left = vim.uv.fs_stat(a)
    local right = vim.uv.fs_stat(b)
    return (left and left.mtime.sec or 0) > (right and right.mtime.sec or 0)
  end)
  return found
end

-- Returns the path outright when there is nothing to ask, and a coroutine
-- when there is. nvim-dap resumes the coroutine with the answer; returning one
-- for a question nobody needs to answer deadlocks the session it belongs to.
---@param root string
---@return thread|string
local function program_for(root)
  local candidates = built_executables(root)

  if #candidates == 1 then
    return candidates[1]
  end

  return coroutine.create(function(dap_coroutine)
    if #candidates == 0 then
      vim.ui.input({ prompt = "Path to executable: ", default = root .. "/", completion = "file" }, function(chosen)
        coroutine.resume(dap_coroutine, chosen)
      end)
      return
    end

    vim.ui.select(candidates, {
      prompt = "Which executable?",
      format_item = function(path)
        return vim.fs.relpath(root, path) or path
      end,
    }, function(chosen)
      coroutine.resume(dap_coroutine, chosen)
    end)
  end)
end

---@param filetype string
---@param root string
local function codelldb_configurations(filetype, root)
  return {
    {
      type = "codelldb",
      request = "launch",
      name = "Launch a " .. filetype .. " executable",
      program = function()
        return program_for(root)
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
          type = "server",
          host = "127.0.0.1",
          port = "${port}",
          executable = {
            command = command,
            args = {
              "--project=" .. root,
              "-e",
              table.concat({
                "using DebugAdapter, Sockets",
                "server = Sockets.listen(parse(Int, ARGS[1]))",
                "conn = Sockets.accept(server)",
                "run(DebugAdapter.DebugSession(conn))",
              }, "; "),
              "${port}",
            },
          },
        })
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("dotfiles_dap_configurations", { clear = true }),
        pattern = vim.list_extend({ "julia" }, CODELLDB_FILETYPES),
        callback = function(event)
          local root = project_root()
          local ours = event.match == "julia" and julia_configurations(root) or codelldb_configurations(event.match, root)

          -- Prepended rather than assigned. mason-nvim-dap registers an
          -- "LLDB: Launch" for every adapter it installs, and that one asks
          -- for the executable with vim.fn.input. Returning early when
          -- something was already registered left ours unreachable; replacing
          -- would discard what a project set in its own .nvim.lua.
          local mine = {}
          for _, configuration in ipairs(ours) do
            mine[configuration.name] = true
          end

          local merged = vim.deepcopy(ours)
          for _, configuration in ipairs(dap.configurations[event.match] or {}) do
            if not mine[configuration.name] then
              merged[#merged + 1] = configuration
            end
          end
          dap.configurations[event.match] = merged
        end,
      })
    end,
  },
}
