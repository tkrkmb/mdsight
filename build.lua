-- lazy.nvim が導入と更新のたびに実行する。チェックアウトした版と同じ版の実行ファイルを
-- Release から取得し、プラグインのディレクトリの直下に mdsight として置く。
-- Lua と実行ファイルの版がずれると RPC が噛み合わないため、latest ではなく版を指定して取る。

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local target = vim.fs.joinpath(root, "mdsight")

local function fail(msg)
  error("mdsight build: " .. msg, 0)
end

local function version()
  local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(root, "src-tauri", "Cargo.toml"))
  if ok then
    -- 最初の version は [package] の版（依存の版は `name = "..."` の形で書いている）
    for _, line in ipairs(lines) do
      local found = line:match('^version%s*=%s*"([^"]+)"')
      if found then
        return found
      end
    end
  end
  fail("cannot read the version from src-tauri/Cargo.toml")
end

local function asset()
  local uname = vim.uv.os_uname()
  if uname.sysname == "Darwin" then
    return "mdsight-universal-macos"
  end
  if uname.sysname == "Linux" and uname.machine == "x86_64" then
    return "mdsight-x86_64-linux"
  end
  fail(("no prebuilt executable for %s %s"):format(uname.sysname, uname.machine))
end

-- what は「何ができなかったか」（例：download <url>）。失敗の理由に使う。
local function run(cmd, what)
  local ok, result = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if not ok then
    fail(("cannot %s: %s"):format(what, tostring(result)))
  end
  if result.code ~= 0 then
    fail(("cannot %s: %s"):format(what, vim.trim(result.stderr or "")))
  end
end

local release = version()
local name = asset()
local url = ("https://github.com/tkrkmb/mdsight/releases/download/v%s/%s.tar.gz"):format(release, name)

local work = vim.fn.tempname()
vim.fn.mkdir(work, "p")
-- 一時ディレクトリは別のファイルシステムにあることがあるので、いったん隣に写してから
-- rename で差し替える。途中で失敗しても、すでにある実行ファイルは残る。
local staged = target .. ".new"
local ok, err = pcall(function()
  local archive = vim.fs.joinpath(work, name .. ".tar.gz")
  run({ "curl", "-fsSL", "-o", archive, url }, "download " .. url)
  run({ "tar", "-xzf", archive, "-C", work }, "extract " .. name .. ".tar.gz")
  local extracted = vim.fs.joinpath(work, name, "mdsight")
  if not vim.uv.fs_stat(extracted) then
    fail("the archive has no mdsight executable")
  end
  local copied, copy_err = vim.uv.fs_copyfile(extracted, staged)
  if not copied then
    fail("cannot copy the executable: " .. tostring(copy_err))
  end
  vim.uv.fs_chmod(staged, tonumber("755", 8))
  local renamed, rename_err = vim.uv.fs_rename(staged, target)
  if not renamed then
    fail("cannot replace the executable: " .. tostring(rename_err))
  end
end)
vim.fn.delete(work, "rf")
vim.fn.delete(staged)
if not ok then
  error(err, 0)
end

-- 置いた実行ファイルの版を出す。Linux で WebKitGTK が無いと起動できないが、
-- 取得は済んでいるので失敗にはしない。
local probe = vim.system({ target, "--version" }, { text = true }):wait()
if probe.code == 0 then
  print("mdsight: installed " .. vim.trim(probe.stdout))
else
  print(("mdsight: installed v%s, but it does not run yet: %s"):format(release, vim.trim(probe.stderr or "")))
end
