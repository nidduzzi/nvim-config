--- Where this machine keeps a browser that speaks the debugging protocol.
---
--- js-debug looks for an installed Chrome and stops if it finds none, saying
--- so in a notification that a session nobody watched has already outlived.
--- Plenty of machines have no Chrome on PATH and a browser all the same: macOS
--- keeps it in an application bundle, Windows under Program Files, and
--- Playwright downloads one per build into a cache of its own.

local M = {}

--- Names a browser is installed under on PATH.
M.commands = {
  "google-chrome",
  "google-chrome-stable",
  "chromium",
  "chromium-browser",
  "brave-browser",
  "microsoft-edge",
}

--- Where a platform keeps the program inside an installed browser.
M.installed = {
  mac = {
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  },
  win32 = {
    "Google/Chrome/Application/chrome.exe",
    "Chromium/Application/chrome.exe",
    "BraveSoftware/Brave-Browser/Application/brave.exe",
    "Microsoft/Edge/Application/msedge.exe",
  },
}

--- Where Playwright puts the browsers it downloads, which is its decision and
--- a different directory on each platform.
---@return string
function M.playwright_cache()
  local home = vim.uv.os_homedir() or ""
  if vim.env.PLAYWRIGHT_BROWSERS_PATH then
    return vim.env.PLAYWRIGHT_BROWSERS_PATH
  end
  if vim.fn.has("win32") == 1 and vim.env.LOCALAPPDATA then
    return vim.fs.joinpath(vim.env.LOCALAPPDATA, "ms-playwright")
  end
  if vim.fn.has("mac") == 1 then
    return vim.fs.joinpath(home, "Library", "Caches", "ms-playwright")
  end
  return vim.fs.joinpath(vim.env.XDG_CACHE_HOME or vim.fs.joinpath(home, ".cache"), "ms-playwright")
end

---@return string|nil
local function from_playwright()
  -- Newest build wins, which is how Playwright itself picks: the directories
  -- are named chromium-<build>, and the program inside is named for the
  -- platform it runs on.
  local builds = vim.fn.glob(vim.fs.joinpath(M.playwright_cache(), "chromium-*"), false, true)
  table.sort(builds, function(a, b)
    return (tonumber(a:match("(%d+)$")) or 0) > (tonumber(b:match("(%d+)$")) or 0)
  end)

  for _, build in ipairs(builds) do
    for _, relative in ipairs({
      "chrome-linux64/chrome",
      "chrome-linux/chrome",
      "chrome-mac/Chromium.app/Contents/MacOS/Chromium",
      "chrome-mac-arm64/Chromium.app/Contents/MacOS/Chromium",
      "chrome-win/chrome.exe",
    }) do
      local candidate = vim.fs.joinpath(build, relative)
      if vim.fn.executable(candidate) == 1 then
        return candidate
      end
    end
  end
end

---@return string|nil
local function installed()
  if vim.fn.has("mac") == 1 then
    for _, path in ipairs(M.installed.mac) do
      if vim.fn.executable(path) == 1 then
        return path
      end
    end
    return nil
  end

  if vim.fn.has("win32") ~= 1 then
    return nil
  end

  for _, root in ipairs({ vim.env.PROGRAMFILES, vim.env["PROGRAMFILES(X86)"], vim.env.LOCALAPPDATA }) do
    for _, relative in ipairs(root and M.installed.win32 or {}) do
      local candidate = vim.fs.joinpath(root, relative)
      if vim.fn.executable(candidate) == 1 then
        return candidate
      end
    end
  end
end

--- The browser a debug session should open, or nil to let the adapter look.
---@return string|nil
function M.executable()
  for _, name in ipairs(M.commands) do
    local found = require("util.lsp").safe_exepath(name)
    if found ~= "" then
      return found
    end
  end

  return installed() or from_playwright()
end

return M
