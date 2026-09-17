--- Reach the parts of a language server that nothing binds a key to.
---
--- A server offers more than the handful of requests an editor wires up by
--- default. Two kinds go unused in Neovim while the same server's VS Code
--- extension puts them behind menu items:
---
---   * commands, advertised in `executeCommandProvider`. ruff offers
---     ruff.applyFormat, ruff.applyAutofix, ruff.applyOrganizeImports and
---     ruff.printDebugInformation; that is where "Ruff: Fix all imports" in
---     VS Code goes.
---   * code actions of a particular kind. pyrefly answers refactor.extract,
---     refactor.inline, refactor.move and source.fixAll.pyrefly; pyright
---     answers source.organizeImports. `vim.lsp.buf.code_action()` shows them
---     mixed in with everything else, so the useful ones are reachable but
---     never directly.
---
--- Nothing here is specific to Python. Whatever is attached to the buffer is
--- asked what it can do, and that is what is offered.

local M = {}

--- Every command the attached servers advertise.
---@return { client: vim.lsp.Client, command: string }[]
function M.commands()
  local found = {}

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    local provider = (client.server_capabilities or {}).executeCommandProvider
    for _, command in ipairs(provider and provider.commands or {}) do
      table.insert(found, { client = client, command = command })
    end
  end

  table.sort(found, function(a, b)
    return a.command < b.command
  end)

  return found
end

--- Ask a server to run one of its commands.
---
--- The argument a command wants is server-specific and not described anywhere
--- in the protocol, so this sends the document it was invoked on, which is
--- what document-scoped commands take. A server that wanted something else
--- answers with an error, which is reported rather than swallowed.
---@param entry { client: vim.lsp.Client, command: string }
function M.run(entry)
  local arguments = {
    vim.uri_from_bufnr(0),
    { uri = vim.uri_from_bufnr(0), version = vim.lsp.util.buf_versions[vim.api.nvim_get_current_buf()] },
  }

  entry.client:exec_cmd({ command = entry.command, arguments = arguments }, { bufnr = 0 }, function(err)
    if err then
      vim.notify(
        ("%s\n\n%s"):format(entry.command, err.message or vim.inspect(err)),
        vim.log.levels.ERROR,
        { title = entry.client.name }
      )
    end
  end)
end

--- Pick one of the commands the servers here advertise.
function M.pick()
  local commands = M.commands()

  if #commands == 0 then
    vim.notify(
      "No language server attached here advertises any commands.",
      vim.log.levels.WARN,
      { title = "Server commands" }
    )
    return
  end

  local items = {}
  for index, entry in ipairs(commands) do
    table.insert(items, {
      idx = index,
      score = 0,
      text = entry.command .. " " .. entry.client.name,
      entry = entry,
    })
  end

  Snacks.picker.pick({
    source = "lsp_commands",
    items = items,
    title = "Commands the servers here offer",
    layout = { preset = "select", layout = { width = 0.7, height = 0.6 } },
    format = function(item)
      return {
        { ("%-40s"):format(item.entry.command), "SnacksPickerLabel" },
        { "  ", "SnacksPickerComment" },
        { item.entry.client.name, "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        M.run(item.entry)
      end
    end,
  })
end

--- Apply a code action of a kind, without showing a menu.
---
--- This is how "organize imports" works in an editor with a button for it: the
--- same code action request, asked for one kind. Two details make it more than
--- a one-liner.
---
--- Servers answer a `source.organizeImports` filter with their own sub-kind,
--- `source.organizeImports.ruff`, and some answer with neighbouring kinds as
--- well, so the filtering is redone here rather than trusted.
---
--- And an action may arrive without its edit: ruff sends the title and expects
--- a `codeAction/resolve` before it will say what to change. Neovim's
--- `apply = true` shows a menu when more than one action matches, which in
--- practice means the key appears to do nothing.
---@param kind string
---@param label string what to call this in messages
function M.apply_kind(kind, label)
  local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/codeAction" })

  if #clients == 0 then
    vim.notify(
      ("%s\n\nNo language server here offers code actions."):format(label),
      vim.log.levels.WARN,
      { title = "Language servers" }
    )
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local params = vim.lsp.util.make_range_params(0, clients[1].offset_encoding or "utf-16")
  params.context = { diagnostics = {}, only = { kind } }

  vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", params, function(results)
    for id, response in pairs(results) do
      local client = vim.lsp.get_client_by_id(id)

      for _, action in ipairs(response.result or {}) do
        -- The server's own sub-kind counts; a neighbouring kind does not.
        local matches = action.kind == kind or (action.kind or ""):find(kind .. ".", 1, true) == 1

        if client and matches then
          M.apply_action(client, action, label)
          return
        end
      end
    end

    vim.notify(
      ("%s\n\nNothing attached here offers that."):format(label),
      vim.log.levels.WARN,
      { title = "Language servers" }
    )
  end)
end

--- Carry out one code action, resolving it first when it arrived without edits.
---@param client vim.lsp.Client
---@param action table
---@param label string
function M.apply_action(client, action, label)
  local function carry_out(resolved)
    if resolved.edit then
      vim.lsp.util.apply_workspace_edit(resolved.edit, client.offset_encoding)
    end

    if resolved.command then
      local command = type(resolved.command) == "table" and resolved.command or resolved
      client:exec_cmd(command, { bufnr = 0 })
    end

    vim.notify(
      ("%s\n%s"):format(resolved.title or label, client.name),
      vim.log.levels.INFO,
      { title = "Language servers" }
    )
  end

  if action.edit or action.command then
    carry_out(action)
    return
  end

  -- No edit yet: the server is waiting to be asked what the action does.
  client:request("codeAction/resolve", action, function(err, resolved)
    if err or not resolved then
      vim.notify(
        ("%s\n\n%s could not resolve it: %s"):format(label, client.name, err and err.message or "no edit returned"),
        vim.log.levels.ERROR,
        { title = "Language servers" }
      )
      return
    end
    carry_out(resolved)
  end, 0)
end

--- What each attached server could do that this buffer has no key for.
function M.report()
  local lines = {}

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    local caps = client.server_capabilities or {}
    local extras = {}

    local provider = caps.executeCommandProvider
    if provider and provider.commands and #provider.commands > 0 then
      table.insert(extras, "commands: " .. table.concat(provider.commands, ", "))
    end

    if type(caps.codeActionProvider) == "table" and caps.codeActionProvider.codeActionKinds then
      table.insert(extras, "action kinds: " .. table.concat(caps.codeActionProvider.codeActionKinds, ", "))
    end

    for capability, label in pairs({
      callHierarchyProvider = "call hierarchy",
      typeHierarchyProvider = "type hierarchy",
      codeLensProvider = "code lenses",
      selectionRangeProvider = "selection ranges",
      inlayHintProvider = "inlay hints",
    }) do
      if caps[capability] then
        table.insert(extras, label)
      end
    end

    table.insert(lines, ("%s\n  %s"):format(client.name, table.concat(extras, "\n  ")))
  end

  if #lines == 0 then
    lines = { "No language server is attached to this buffer." }
  end

  vim.notify(table.concat(lines, "\n\n"), vim.log.levels.INFO, { title = "What the servers here offer" })
end

return M
