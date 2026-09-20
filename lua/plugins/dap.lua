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
  local lsp = require("util.lsp")
  for _, dir in ipairs(lsp.bin_dirs(root)) do
    local found = lsp.executables_named(root, dir, name)
    if found[1] then
      return found[1]
    end
  end
end

--- Whether a program that exists will also run.
---
--- A version manager's shim is on PATH and answers `executable()` whatever
--- directory you are in, and then refuses to run outside a project that names
--- a version: mise exits with "No version is set for shim: julia". The
--- debugger started it, the adapter died before speaking, and the session
--- never existed --- with nothing on the screen to say so.
---
--- Every adapter here is a program that reports its own version, and the cost
--- is one process at the moment a session starts.
---@param command string
---@return boolean, string
local function runs(command)
  local output = vim.fn.system({ command, "--version" })
  if vim.v.shell_error == 0 then
    return true, ""
  end
  return false, vim.trim(output)
end

---@param root string
---@param name string
---@return string|nil path
---@return string|nil refused
local function anywhere(root, name)
  local from_path = require("util.lsp").safe_exepath(name, root)
  local found = in_project(root, name) or (from_path ~= "" and from_path or nil)
  if not found then
    return nil, nil
  end

  local ok, why = runs(found)
  if ok then
    return found, nil
  end
  return nil, ("%s is at %s, and does not run here:\n\n%s"):format(name, found, why)
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
    local left = (vim.uv.fs_stat(a) or {}).mtime
    local right = (vim.uv.fs_stat(b) or {}).mtime
    local newest, older = left and left.sec or 0, right and right.sec or 0
    if newest ~= older then
      return newest > older
    end
    return a < b
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

-- The first version of Node that runs TypeScript by stripping its types,
-- which is what decides whether a .ts file needs a separate runtime at all.
local NODE_STRIPS_TYPES = { 22, 6 }

---@return boolean
local function node_strips_types()
  if vim.fn.executable("node") ~= 1 then
    return false
  end
  local major, minor = vim.fn.system({ "node", "--version" }):match("v(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)
  if not major or not minor then
    return false
  end
  if major ~= NODE_STRIPS_TYPES[1] then
    return major > NODE_STRIPS_TYPES[1]
  end
  return minor >= NODE_STRIPS_TYPES[2]
end

--- TypeScript and TSX, launched with a runtime this machine has.
---
--- LazyVim's own configuration names `tsx` or `ts-node` as the runtime for
--- anything TypeScript. Neither is installed by anything here, and a launch
--- naming a runtime that does not exist fails without a message: the debugger
--- UI opens, no session starts, and nothing says why. Node has stripped types
--- since 22.6, so on a current Node there is no separate runtime to find.
---@param root string
---@return table[]
local function javascript_configurations(root)
  local configuration = {
    type = "pwa-node",
    request = "launch",
    name = "Run this file",
    program = "${file}",
    cwd = root,
    sourceMaps = true,
    skipFiles = { "<node_internals>/**", "node_modules/**" },
  }

  if not node_strips_types() then
    for _, runtime in ipairs({ "tsx", "ts-node" }) do
      if vim.fn.executable(runtime) == 1 then
        configuration.runtimeExecutable = runtime
        break
      end
    end
  end

  return { configuration }
end

--- nvim-dap-python registers `file`, `file:args`, `attach` and `file:doctest`.
--- Those names are the plugin's, and nvim-dap sorts nothing: the first entry
--- in the prompt is whichever was registered first. This one is prepended so
--- the obvious answer is the one already selected, and reads like the entries
--- for every other language here.
---@param root string
local function python_configurations(root)
  return {
    {
      type = "python",
      request = "launch",
      name = "Run this file",
      program = "${file}",
      cwd = root,
      console = "integratedTerminal",
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
        local command, refused = anywhere(root, "codelldb")
        if not command then
          vim.notify(refused or missing("codelldb", root), vim.log.levels.ERROR, { title = "Debugger" })
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
        local command, refused = anywhere(root, "julia")
        if not command then
          vim.notify(refused or missing("julia", root), vim.log.levels.ERROR, { title = "Julia debugger" })
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

      local javascript_filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" }
      local handled = vim.list_extend({ "julia", "python" }, CODELLDB_FILETYPES)
      vim.list_extend(handled, javascript_filetypes)

      ---@type table<string, fun(root: string): table[]>
      local builders = {
        julia = julia_configurations,
        python = python_configurations,
      }
      for _, filetype in ipairs(javascript_filetypes) do
        builders[filetype] = javascript_configurations
      end

      local function register(filetype)
        local root = project_root()
        local builder = builders[filetype]
        local ours = builder and builder(root) or codelldb_configurations(filetype, root)

        -- Prepended rather than assigned. mason-nvim-dap registers an
        -- "LLDB: Launch" for every adapter it installs, and that one asks for
        -- the executable with vim.fn.input. Returning early when something was
        -- already registered left ours unreachable; replacing would discard
        -- what a project set in its own .nvim.lua.
        local mine = {}
        for _, configuration in ipairs(ours) do
          mine[configuration.name] = true
        end

        local merged = vim.deepcopy(ours)
        for _, configuration in ipairs(dap.configurations[filetype] or {}) do
          if not mine[configuration.name] then
            merged[#merged + 1] = configuration
          end
        end
        dap.configurations[filetype] = merged
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("dotfiles_dap_configurations", { clear = true }),
        pattern = handled,
        callback = function(event)
          register(event.match)
        end,
      })

      -- This plugin loads when a debug key is first pressed, by which time
      -- FileType has long since fired for the file being debugged. Without
      -- this, nothing is registered for the buffer you are standing in and the
      -- key appears to do nothing at all.
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local filetype = vim.bo[buf].filetype
        if vim.tbl_contains(handled, filetype) then
          register(filetype)
        end
      end
    end,
  },
}
