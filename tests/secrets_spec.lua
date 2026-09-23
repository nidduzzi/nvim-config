local secrets = require("util.agent.secrets")

---@param name string
---@param lines string[]
---@return integer
local function buffer(name, lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  if name ~= "" then
    vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(vim.fn.tempname(), name))
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

describe("what looks like a credential", function()
  it("recognises the file by name", function()
    for _, name in ipairs({ ".env", ".env.local", "id_rsa", "server.pem", "kubeconfig" }) do
      assert.is_truthy(secrets.found(buffer(name, { "" })), name)
    end
  end)

  it("recognises the token by shape, whatever the file is called", function()
    for _, line in ipairs({
      "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
      'token = "ghp_16CharactersOrSo"',
      "-----BEGIN RSA PRIVATE KEY-----",
      "SLACK_TOKEN=xoxb-123-456-abcdef",
      "DJANGO_SECRET_KEY = 'abc123'",
    }) do
      assert.is_truthy(secrets.found(buffer("notes.txt", { line })), line)
    end
  end)

  it("leaves ordinary code alone", function()
    assert.is_nil(secrets.found(buffer("main.lua", {
      "local function add(a, b)",
      "  return a + b",
      "end",
      "-- the key insight is that addition is commutative",
    })))
  end)

  it("leaves a template alone", function()
    -- An .env.example is the shape of a configuration, which is a reasonable
    -- thing to ask about, and it holds nothing.
    assert.is_nil(secrets.found(buffer(".env.example", { "DATABASE_URL=", "API_KEY=" })))
    assert.is_nil(secrets.found(buffer("secrets.sample.yaml", { "password:" })))
  end)

  it("reads only the top of a large file", function()
    local lines = {}
    for i = 1, secrets.lines_read + 50 do
      lines[i] = "line " .. i
    end
    lines[#lines] = "API_KEY=sk-thisisfardown"
    assert.is_nil(secrets.found(buffer("big.txt", lines)))
  end)
end)
