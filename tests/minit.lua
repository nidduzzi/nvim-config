#!/usr/bin/env -S nvim -l

-- Minimal init for the test run: `nvim -l tests/minit.lua`.
--
-- LAZY_STDPATH keeps everything the run downloads under .tests/ in this
-- repository rather than in the real data directory, so a test run cannot
-- disturb the editor you use, and CI can cache one directory.
--
-- lazy.minit's own `--minitest` path is deliberately not used, and the reason
-- is worth writing down. It builds an assert shim over MiniTest.expect and
-- then overwrites it with `assert = require("luassert")`, so luassert is
-- mandatory; luassert is a luarocks package that pulls in `say`, and
-- installing that chain needs luarocks and a hererocks build. mini.test
-- already emulates `describe`, `it`, `before_each` and `after_each` natively,
-- so the only thing luassert was providing is the handful of assertions
-- shimmed below. Two rocks and a build step, for that.
--
-- The spec is deliberately not this whole configuration. Loading it would drag
-- in every plugin, a colorscheme and a language server, and the unit tests
-- would be measuring lazy.nvim's startup rather than the code under test. The
-- specs require the util modules directly; they are plain Lua and that is the
-- point of testing them here.
--
-- Screen-level behaviour is not tested from here. It needs the real
-- configuration with its plugins attached, which is what
-- tools/nvim-harness/screen-test.sh drives.

vim.env.LAZY_STDPATH = ".tests"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"), "bootstrap.lua")()

require("lazy.minit").setup({
  spec = {
    { "nvim-mini/mini.test", opts = {} },
  },
})

-- The config's own lua/ has to be findable before a spec can require it. After
-- setup, because LAZY_STDPATH rewrites the XDG variables.
vim.opt.runtimepath:prepend(vim.uv.cwd())

local Test = require("mini.test")
local expect = Test.expect

-- Enough of luassert's surface for these specs to read as ordinary busted.
-- Anything not here should be added when a spec needs it, rather than by
-- reaching for the rock.
local plain = assert
assert = setmetatable({
  same = expect.equality,
  equal = expect.equality,
  are = { same = expect.equality, equal = expect.equality },
  is_not = { same = expect.no_equality, equal = expect.no_equality },
  is_true = function(value, message)
    return expect.equality(value, true, message)
  end,
  is_false = function(value, message)
    return expect.equality(value, false, message)
  end,
  is_nil = function(value, message)
    return expect.equality(value, nil, message)
  end,
  is_truthy = function(value, message)
    return expect.equality(not not value, true, message)
  end,
  is_falsy = function(value, message)
    return expect.equality(not not value, false, message)
  end,
  has_error = expect.error,
  no_error = expect.no_error,
}, {
  __call = function(_, ...)
    return plain(...)
  end,
})

Test.setup({
  collect = {
    find_files = function()
      return #_G.arg > 0 and _G.arg or vim.fn.globpath("tests", "**/*_spec.lua", true, true)
    end,
  },
})

Test.run()
