--- Repair Neovim's built-in LSP mappings.
---
--- Neovim 0.11 binds a family of global LSP keys whose description is the
--- function they call:
---
---   gra  vim.lsp.buf.code_action()      grr  vim.lsp.buf.references()
---   grn  vim.lsp.buf.rename()           gri  vim.lsp.buf.implementation()
---   grt  vim.lsp.buf.type_definition()  grx  vim.lsp.codelens.run()
---   gO   vim.lsp.buf.document_symbol()
---
--- Two problems follow. The hints read as source code rather than as what the
--- key does, which is what you see when you pause on `g`. And they are global
--- and unconditional: they exist in a buffer with no language server at all,
--- and in one whose server cannot rename, where pressing them appears to do
--- nothing.
---
--- The keys stay, because they are Neovim's own and worth muscle memory. They
--- are rebound here to say what they do, and to say why nothing happened when
--- nothing can happen.

local M = {}

---@type { lhs: string, method: string, desc: string, run: fun() }[]
M.keys = {
  {
    lhs = "grn",
    method = "textDocument/rename",
    desc = "Rename symbol",
    run = vim.lsp.buf.rename,
  },
  {
    lhs = "gra",
    method = "textDocument/codeAction",
    desc = "Code actions",
    run = vim.lsp.buf.code_action,
  },
  {
    lhs = "grr",
    method = "textDocument/references",
    desc = "References",
    run = vim.lsp.buf.references,
  },
  {
    lhs = "gri",
    method = "textDocument/implementation",
    desc = "Implementations",
    run = vim.lsp.buf.implementation,
  },
  {
    lhs = "grt",
    method = "textDocument/typeDefinition",
    desc = "Type definition",
    run = vim.lsp.buf.type_definition,
  },
  {
    lhs = "grx",
    method = "textDocument/codeLens",
    desc = "Run the code lens on this line",
    run = function()
      vim.lsp.codelens.run()
    end,
  },
  {
    lhs = "gO",
    method = "textDocument/documentSymbol",
    desc = "Symbols in this file",
    run = vim.lsp.buf.document_symbol,
  },
}

--- Which attached servers can answer this request.
---@param method string
---@return vim.lsp.Client[]
local function providers(method)
  return vim.lsp.get_clients({ bufnr = 0, method = method })
end

function M.setup()
  for _, key in ipairs(M.keys) do
    vim.keymap.set({ "n", "x" }, key.lhs, function()
      if #providers(key.method) > 0 then
        key.run()
        return
      end

      -- Saying nothing is the behaviour that made these keys feel broken.
      local attached = vim.lsp.get_clients({ bufnr = 0 })
      local reason = #attached == 0 and "No language server is attached to this buffer."
        or ("Attached here: %s — none of them can do this."):format(
          table.concat(
            vim.tbl_map(function(client)
              return client.name
            end, attached),
            ", "
          )
        )

      vim.notify(
        ("%s\n\n%s\n:checkhealth dotfiles lists what this project provides."):format(key.desc, reason),
        vim.log.levels.WARN,
        { title = "Language servers" }
      )
    end, { desc = key.desc })
  end
end

return M
