-- :checkhealth mdsight。導入がうまくいかないときに、どこでつまずいているかを示す。
local state = require("mdsight.state")

local M = {}

-- プラグインのディレクトリ（このファイルの3つ上）
local function plugin_root()
  local here = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(here, ":p:h:h:h")
end

-- プラグインのディレクトリの src-tauri/Cargo.toml の版。なければ nil
local function plugin_version(root)
  local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(root, "src-tauri", "Cargo.toml"))
  if not ok then
    return nil
  end
  for _, line in ipairs(lines) do
    local found = line:match('^version%s*=%s*"([^"]+)"')
    if found then
      return found
    end
  end
  return nil
end

local function run(cmd)
  local ok, result = pcall(function()
    return vim.system(cmd, { text = true, timeout = 5000 }):wait()
  end)
  if not ok then
    return nil, tostring(result)
  end
  return result
end

local function check_executable(bin)
  if vim.fn.executable(bin) ~= 1 then
    vim.health.error("executable not found: " .. bin, {
      "With lazy.nvim, run :Lazy build mdsight",
      "Without a plugin manager, run the extract command in the README again",
    })
    return false
  end
  vim.health.ok("executable: " .. bin)
  return true
end

local function check_version(bin, root)
  local expected = plugin_version(root)
  if expected == nil then
    vim.health.info("version not checked: src-tauri/Cargo.toml is not in the plugin directory")
    return
  end
  local result, err = run({ bin, "--version" })
  if result == nil or result.code ~= 0 then
    local reason = err or vim.trim(result.stderr or "")
    vim.health.warn("cannot run " .. bin .. " --version: " .. reason)
    return
  end
  local actual = vim.trim(result.stdout or ""):match("^mdsight%s+(%S+)$")
  if actual == expected then
    vim.health.ok("version " .. actual .. " matches the plugin")
  else
    vim.health.warn(("executable version %s differs from the plugin version %s"):format(tostring(actual), expected), {
      "With lazy.nvim, run :Lazy build mdsight",
      "Without a plugin manager, extract the plugin and the executable from the same release",
    })
  end
end

-- Linux では、実行ファイルが使うライブラリ（主に WebKitGTK 4.1）が揃っているかを ldd で調べる
local function check_libraries(bin)
  local result, err = run({ "ldd", bin })
  if result == nil or result.code ~= 0 then
    vim.health.warn("cannot run ldd: " .. (err or vim.trim(result.stderr or "")))
    return
  end
  local missing = {}
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    local name = line:match("^%s*(%S+)%s+=>%s+not found")
    if name then
      table.insert(missing, name)
    end
  end
  if #missing == 0 then
    vim.health.ok("all shared libraries are found")
  else
    vim.health.error("missing shared libraries: " .. table.concat(missing, ", "), {
      "Install WebKitGTK 4.1 (on Fedora: sudo dnf install webkit2gtk4.1)",
    })
  end
end

function M.check()
  vim.health.start("mdsight")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10 or later")
  else
    vim.health.error("Neovim 0.10 or later is required")
  end

  local root = plugin_root()
  local bin = state.bin
  if bin == nil then
    vim.health.error('setup() has not been called', {
      'Add require("mdsight").setup() to init.lua (with lazy.nvim, add opts = {} to the spec)',
    })
    bin = vim.fs.joinpath(root, "mdsight")
  else
    vim.health.ok("setup() has been called")
  end

  if not check_executable(bin) then
    return
  end
  check_version(bin, root)
  if vim.uv.os_uname().sysname == "Linux" then
    check_libraries(bin)
  end
end

return M
