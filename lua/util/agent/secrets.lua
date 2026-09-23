--- Whether a buffer looks like it holds a credential.
---
--- The agent is sent the code you are looking at, and the file you are looking
--- at is sometimes a `.env`. Nothing else in this configuration reads a buffer
--- and sends it somewhere, so the check belongs where that happens rather than
--- as a general-purpose scanner.
---
--- Names and contents are both checked, because neither is enough on its own:
--- a key pasted into a scratch buffer has no telling name, and an empty
--- `.env.example` has no telling contents.

local M = {}

--- What a credential looks like, in a filename.
---
--- Patterns rather than names, because the same secret is `.env`,
--- `.env.local`, `.env.production` and `env.staging` depending on who set the
--- project up.
---@type { name: string, pattern: string }[]
M.name_markers = {
  { name = "an environment file", pattern = "%.?env[%.%w]*$" },
  { name = "a private key", pattern = "id_[rd]sa$" },
  { name = "a private key", pattern = "%.pem$" },
  { name = "a private key", pattern = "%.p12$" },
  { name = "a key file", pattern = "%.key$" },
  { name = "a keyring", pattern = "%.kdbx?$" },
  { name = "a credentials file", pattern = "credentials" },
  { name = "a secrets file", pattern = "secrets?%.[%w]+$" },
  { name = "an SSH configuration", pattern = "%.ssh/" },
  { name = "a cloud credential", pattern = "%.aws/" },
  { name = "a kubernetes configuration", pattern = "kubeconfig" },
}

--- What a credential looks like, in a line.
---
--- The prefixes are the ones the issuers themselves document, so a match is a
--- statement about the token's format rather than a guess about the word
--- before it. The last two are the shape of an assignment, which is how a
--- secret usually appears in a file that is mostly not secret.
---@type { name: string, pattern: string }[]
M.text_markers = {
  { name = "a private key block", pattern = "^%-%-%-%-%-BEGIN [%u ]*PRIVATE KEY%-%-%-%-%-" },
  { name = "an AWS access key", pattern = "AKIA[%u%d][%u%d][%u%d][%u%d]" },
  { name = "a GitHub token", pattern = "gh[pousr]_[%w]+" },
  { name = "an OpenAI key", pattern = "sk%-[%w]+" },
  { name = "an Anthropic key", pattern = "sk%-ant%-[%w-]+" },
  { name = "a Slack token", pattern = "xox[baprs]%-[%w-]+" },
  { name = "a Google API key", pattern = "AIza[%w_-]+" },
  { name = "a private key in one line", pattern = "PRIVATE KEY%-%-%-%-%-" },
  { name = "an assigned secret", pattern = "[%u_]*SECRET[%u_]*%s*[=:]%s*[\"']?[%w/+=_-]+" },
  { name = "an assigned token", pattern = "[%u_]*TOKEN[%u_]*%s*[=:]%s*[\"']?[%w/+=_.-]+" },
  { name = "an assigned password", pattern = "[%u_]*PASSWORD[%u_]*%s*[=:]%s*[\"']?[^%s\"']+" },
  { name = "an assigned key", pattern = "[%u_]*API_?KEY[%u_]*%s*[=:]%s*[\"']?[%w/+=_-]+" },
}

--- How many lines of a buffer are read before giving up. A credential at the
--- bottom of a ten thousand line file is not what this is for, and reading all
--- of one on every question is.
M.lines_read = 400

--- What makes this buffer look like it holds a credential, if anything.
---@param bufnr? integer
---@return string|nil what was recognised
function M.found(bufnr)
  bufnr = bufnr or 0

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= "" then
    local lowered = name:lower()
    for _, marker in ipairs(M.name_markers) do
      -- .env.example and its kind are templates, and refusing to discuss one
      -- is refusing to discuss the shape of a configuration.
      if lowered:match(marker.pattern) and not lowered:match("example") and not lowered:match("sample") then
        return marker.name .. " (" .. vim.fn.fnamemodify(name, ":t") .. ")"
      end
    end
  end

  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, M.lines_read, false)) do
    for _, marker in ipairs(M.text_markers) do
      if line:match(marker.pattern) then
        return marker.name
      end
    end
  end
end

return M
