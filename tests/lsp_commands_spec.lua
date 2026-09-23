-- The commands and code-action kinds a server advertises but nothing binds a
-- key to. vim.lsp.get_clients and vim.lsp.buf_request_all are monkey-patched
-- with plain fake clients, so this proves the collecting, sorting and
-- kind-matching without a real language server to attach.

local lsp_commands = require("util.lsp_commands")

---@param name string
---@param capabilities table
---@return table
local function fake_client(name, capabilities)
  return { name = name, server_capabilities = capabilities, offset_encoding = "utf-16" }
end

describe("commands the attached servers advertise", function()
  local original_get_clients

  before_each(function()
    original_get_clients = vim.lsp.get_clients
  end)

  after_each(function()
    vim.lsp.get_clients = original_get_clients
  end)

  it("is empty when nothing is attached", function()
    vim.lsp.get_clients = function()
      return {}
    end
    assert.are.same({}, lsp_commands.commands())
  end)

  it("skips a client that advertises no commands", function()
    vim.lsp.get_clients = function()
      return { fake_client("lua_ls", {}) }
    end
    assert.are.same({}, lsp_commands.commands())
  end)

  it("collects every command a client offers", function()
    vim.lsp.get_clients = function()
      return {
        fake_client("ruff", {
          executeCommandProvider = { commands = { "ruff.applyFormat", "ruff.applyAutofix" } },
        }),
      }
    end
    local found = lsp_commands.commands()
    assert.are.equal(2, #found)
  end)

  it("sorts by command name first, so the same command from two servers stays adjacent", function()
    vim.lsp.get_clients = function()
      return {
        fake_client("zzz_server", { executeCommandProvider = { commands = { "aaa.doThing" } } }),
        fake_client("aaa_server", { executeCommandProvider = { commands = { "aaa.doThing" } } }),
        fake_client("mid_server", { executeCommandProvider = { commands = { "bbb.other" } } }),
      }
    end
    local found = lsp_commands.commands()
    local order = {}
    for _, entry in ipairs(found) do
      table.insert(order, entry.command .. ":" .. entry.client.name)
    end
    assert.are.same({
      "aaa.doThing:aaa_server",
      "aaa.doThing:zzz_server",
      "bbb.other:mid_server",
    }, order)
  end)
end)

describe("a code action of a kind, applied without a menu", function()
  local original_get_clients, original_request_all, original_get_by_id, original_apply_edit

  before_each(function()
    original_get_clients = vim.lsp.get_clients
    original_request_all = vim.lsp.buf_request_all
    original_get_by_id = vim.lsp.get_client_by_id
    original_apply_edit = vim.lsp.util.apply_workspace_edit
  end)

  after_each(function()
    vim.lsp.get_clients = original_get_clients
    vim.lsp.buf_request_all = original_request_all
    vim.lsp.get_client_by_id = original_get_by_id
    vim.lsp.util.apply_workspace_edit = original_apply_edit
  end)

  ---@param client table
  ---@param actions table[]
  local function serving(client, actions)
    vim.lsp.get_clients = function()
      return { client }
    end
    vim.lsp.get_client_by_id = function(id)
      return id == 1 and client or nil
    end
    vim.lsp.buf_request_all = function(_, _, _, callback)
      callback({ [1] = { result = actions } })
    end
  end

  it("refuses with no client offering code actions at all", function()
    vim.lsp.get_clients = function()
      return {}
    end

    local notified
    local original_notify = vim.notify
    vim.notify = function(message)
      notified = message
    end
    lsp_commands.apply_kind("source.organizeImports", "Organize imports")
    vim.notify = original_notify

    assert.is_truthy(notified:match("No language server here offers code actions"))
  end)

  it("matches the exact kind a server answers with", function()
    local client = fake_client("pyright", {})
    client.exec_cmd = function() end
    serving(client, { { kind = "source.organizeImports", edit = { changes = {} } } })

    local edited
    vim.lsp.util.apply_workspace_edit = function(edit)
      edited = edit
    end

    lsp_commands.apply_kind("source.organizeImports", "Organize imports")
    assert.is_truthy(edited)
  end)

  it("matches a server's own sub-kind, not just an exact one", function()
    -- ruff answers source.organizeImports.ruff for a request asking for
    -- source.organizeImports -- the whole reason this is a prefix match and
    -- not string equality.
    local client = fake_client("ruff", {})
    serving(client, { { kind = "source.organizeImports.ruff", edit = { changes = {} } } })

    local edited
    vim.lsp.util.apply_workspace_edit = function(edit)
      edited = edit
    end

    lsp_commands.apply_kind("source.organizeImports", "Organize imports")
    assert.is_truthy(edited)
  end)

  it("does not match a merely-similar kind that is not actually a sub-kind", function()
    -- source.organizeImportsExtra shares a prefix as plain text but is not
    -- source.organizeImports.<anything> -- the dot in the match is what
    -- keeps this refused rather than silently applied.
    local client = fake_client("odd-server", {})
    serving(client, { { kind = "source.organizeImportsExtra", edit = { changes = {} } } })

    local notified
    local original_notify = vim.notify
    vim.notify = function(message)
      notified = message
    end
    local edited = false
    vim.lsp.util.apply_workspace_edit = function()
      edited = true
    end

    lsp_commands.apply_kind("source.organizeImports", "Organize imports")
    vim.notify = original_notify

    assert.is_false(edited)
    assert.is_truthy(notified:match("Nothing attached here offers that"))
  end)

  it("resolves an action that arrived without an edit before applying it", function()
    -- ruff sends the title and expects codeAction/resolve before it says
    -- what to change; apply_kind must not treat "no edit yet" as "nothing
    -- to do".
    local client = fake_client("ruff", {})
    local resolved_with
    client.request = function(_, method, action, callback)
      resolved_with = action
      callback(nil, { title = action.title, edit = { changes = {} } })
    end
    serving(client, { { kind = "source.organizeImports.ruff", title = "Organize imports" } })

    local edited = false
    vim.lsp.util.apply_workspace_edit = function()
      edited = true
    end

    lsp_commands.apply_kind("source.organizeImports", "Organize imports")
    assert.is_truthy(resolved_with)
    assert.is_true(edited)
  end)
end)
