-- Where this machine keeps a browser to debug in: a name on PATH first,
-- then an installed application, then whatever Playwright downloaded. Real
-- executables are created rather than mocked, the same way root_spec.lua's
-- symlink spec does, so this proves the actual filesystem walk rather than a
-- description of it.

local browser = require("util.browser")

---@param path string
local function make_executable(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local windows = vim.fn.has("win32") == 1
  vim.fn.writefile(windows and { "@echo off", "exit /b 0" } or { "#!/bin/sh", "exit 0" }, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

describe("playwright_cache", function()
  local before

  before_each(function()
    before = vim.env.PLAYWRIGHT_BROWSERS_PATH
  end)

  after_each(function()
    vim.env.PLAYWRIGHT_BROWSERS_PATH = before
  end)

  it("is whatever PLAYWRIGHT_BROWSERS_PATH says, on every platform", function()
    vim.env.PLAYWRIGHT_BROWSERS_PATH = "/somewhere/set/by/hand"
    assert.are.same("/somewhere/set/by/hand", browser.playwright_cache())
  end)

  it("falls back to this real platform's own default location", function()
    vim.env.PLAYWRIGHT_BROWSERS_PATH = nil
    local cache = browser.playwright_cache()

    if vim.fn.has("win32") == 1 then
      assert.is_truthy(cache:find("ms%-playwright$"))
      if vim.env.LOCALAPPDATA then
        assert.is_truthy(cache:find(vim.env.LOCALAPPDATA, 1, true))
      end
    elseif vim.fn.has("mac") == 1 then
      assert.is_truthy(cache:find("Library/Caches/ms%-playwright$"))
    else
      assert.is_truthy(cache:find("ms%-playwright$"))
      assert.is_truthy(cache:find("cache", 1, true) or cache:find(".cache", 1, true))
    end
  end)
end)

describe("executable", function()
  local dir, path_before, playwright_before, installed_before

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path_before = vim.env.PATH
    playwright_before = vim.env.PLAYWRIGHT_BROWSERS_PATH
    -- Neither real place this machine might actually have a browser should
    -- leak into what these tests see: the CI runners this also has to pass
    -- on genuinely have one each, ubuntu-latest on PATH and macos-latest
    -- and windows-latest as a real installed application, which is a third
    -- lookup entirely and not something clearing PATH touches at all.
    vim.env.PLAYWRIGHT_BROWSERS_PATH = vim.fs.joinpath(dir, "no-playwright-here")
    installed_before = { mac = browser.installed.mac, win32 = browser.installed.win32 }
    browser.installed = { mac = {}, win32 = {} }
  end)

  after_each(function()
    vim.env.PATH = path_before
    vim.env.PLAYWRIGHT_BROWSERS_PATH = playwright_before
    browser.installed = installed_before
    vim.fn.delete(dir, "rf")
  end)

  it("prefers a name found on PATH over anything in Playwright's cache", function()
    local windows = vim.fn.has("win32") == 1
    local named = vim.fs.joinpath(dir, "google-chrome" .. (windows and ".bat" or ""))
    make_executable(named)
    vim.env.PATH = dir .. (windows and ";" or ":") .. path_before

    -- A build newer than anything a real check would find, so if this were
    -- returned instead it would be unmistakable.
    local cache = vim.env.PLAYWRIGHT_BROWSERS_PATH
    make_executable(vim.fs.joinpath(cache, "chromium-999", "chrome-linux64", "chrome"))

    local found = browser.executable()
    assert.is_truthy(found)
    assert.is_truthy(found:find(vim.fs.basename(named), 1, true))
  end)

  it("picks the newest Playwright build by number, not by name order", function()
    -- Not path_before: the ubuntu-latest runner this also has to pass on
    -- genuinely ships /usr/bin/google-chrome, and a PATH that still reaches
    -- it finds that ahead of anything Playwright has, real chrome winning
    -- for the wrong reason on the one machine that already has one.
    vim.env.PATH = dir
    local cache = vim.env.PLAYWRIGHT_BROWSERS_PATH

    -- Sorted as text, chromium-2000 reads before chromium-999; sorted as the
    -- number in the name, it does not. Three builds, out of numeric order on
    -- disk, so a directory listing cannot be the thing that decides it.
    make_executable(vim.fs.joinpath(cache, "chromium-500", "chrome-linux64", "chrome"))
    make_executable(vim.fs.joinpath(cache, "chromium-2000", "chrome-linux64", "chrome"))
    make_executable(vim.fs.joinpath(cache, "chromium-999", "chrome-linux64", "chrome"))

    local found = browser.executable()
    assert.is_truthy(found)
    assert.is_truthy(found:find("chromium%-2000"))
  end)

  it("looks inside the platform's own chrome layout for the build it finds", function()
    -- Not path_before, and the found path is checked against the cache
    -- directory rather than just asserted truthy, for the same reason as
    -- the two tests above: a merely-truthy check passed here even while
    -- PATH still reached a real system browser, proving nothing about the
    -- layout lookup this test is actually about.
    vim.env.PATH = dir
    local cache = vim.env.PLAYWRIGHT_BROWSERS_PATH
    local windows = vim.fn.has("win32") == 1
    local mac = vim.fn.has("mac") == 1
    local relative = windows and { "chromium-1", "chrome-win", "chrome.exe" }
      or mac and { "chromium-1", "chrome-mac", "Chromium.app", "Contents", "MacOS", "Chromium" }
      or { "chromium-1", "chrome-linux64", "chrome" }
    make_executable(vim.fs.joinpath(cache, unpack(relative)))

    local found = browser.executable()
    assert.is_truthy(found)
    assert.is_truthy(found:find(cache, 1, true))
  end)

  it("is nil rather than an error when nothing anywhere has a browser", function()
    -- Same reason as the build-ordering test above: path_before still
    -- reaches whatever this machine really has installed, and CI's own
    -- ubuntu-latest runner really has one.
    vim.env.PATH = dir
    assert.is_nil(browser.executable())
  end)
end)
