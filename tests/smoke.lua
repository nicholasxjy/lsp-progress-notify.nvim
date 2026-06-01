package.preload["notify"] = function()
  error("lsp-progress-notify.nvim should not require an external notify backend")
end

vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd.runtime("plugin/lsp-progress-notify.lua")

local progress = require("lsp-progress-notify")

assert(vim.fn.has("nvim-0.11") == 1, "tests require Neovim 0.11+")
assert(vim.fn.exists(":LspProgressNotifyEnable") == 2, "enable command missing")
assert(vim.fn.exists(":LspProgressNotifyDisable") == 2, "disable command missing")
assert(vim.fn.exists(":LspProgressNotifyToggle") == 2, "toggle command missing")

local opened = 0
local closed = 0
local function on_open()
  opened = opened + 1
end

local function on_close()
  closed = closed + 1
end

progress.setup({
  enabled = false,
  notification = {
    done_timeout = 20,
    on_open = on_open,
    on_close = on_close,
  },
})

assert(progress.is_enabled() == false, "plugin should start disabled")
vim.cmd("LspProgressNotifyEnable")
assert(progress.is_enabled() == true, "plugin should be enabled")

vim.api.nvim_exec_autocmds("LspProgress", {
  data = {
    client_id = 1,
    params = {
      token = "token-1",
      value = {
        kind = "begin",
        title = "Indexing",
        message = "Scanning workspace",
        percentage = 5,
      },
    },
  },
})

assert(
  vim.wait(200, function()
    return progress.status()["1:\"token-1\""] ~= nil
  end),
  "task should be created on begin"
)
assert(opened >= 1, "notification window should open on begin")

local snapshot = progress.status()
local task = snapshot["1:\"token-1\""]
assert(task.title == "Indexing", "task title mismatch")
assert(task.message == "Scanning workspace", "task message mismatch")
assert(task.percentage == 5, "task percentage mismatch")
assert(task.done == false, "task should be active")

vim.api.nvim_exec_autocmds("LspProgress", {
  data = {
    client_id = 1,
    params = {
      token = "token-1",
      value = {
        kind = "report",
        message = "Halfway there",
        percentage = 50,
      },
    },
  },
})

assert(
  vim.wait(200, function()
    local current = progress.status()["1:\"token-1\""]
    return current and current.message == "Halfway there" and current.percentage == 50
  end),
  "task report should update state"
)

snapshot = progress.status()
task = snapshot["1:\"token-1\""]
assert(task.message == "Halfway there", "task report should update message")
assert(task.percentage == 50, "task report should update percentage")

vim.api.nvim_exec_autocmds("LspProgress", {
  data = {
    client_id = 1,
    params = {
      token = "token-1",
      value = {
        kind = "end",
        message = "Done",
      },
    },
  },
})

assert(
  vim.wait(200, function()
    local current = progress.status()["1:\"token-1\""]
    return current and current.done == true and current.message == "Done"
  end),
  "task should be marked done"
)

snapshot = progress.status()
task = snapshot["1:\"token-1\""]
assert(task.done == true, "task should be marked done")
assert(task.message == "Done", "end message mismatch")

vim.api.nvim_exec_autocmds("LspProgress", {
  data = {
    client_id = 2,
    params = {
      token = 42,
      value = {
        kind = "begin",
        title = "Compiling",
        message = "Building modules",
      },
    },
  },
})

assert(
  vim.wait(200, function()
    return progress.status()["2:42"] ~= nil
  end),
  "numeric token should produce a stable key"
)

snapshot = progress.status()
task = snapshot["2:42"]
assert(task.title == "Compiling", "numeric token task title mismatch")
assert(task.message == "Building modules", "numeric token task message mismatch")
assert(task.done == false, "numeric token task should be active")

vim.api.nvim_exec_autocmds("LspProgress", {
  data = {
    client_id = 2,
    params = {
      token = 42,
      value = {
        kind = "end",
      },
    },
  },
})

assert(
  vim.wait(200, function()
    local current = progress.status()["2:42"]
    return current and current.done == true and current.message == "Building modules"
  end),
  "numeric token task should complete"
)

assert(
  vim.wait(200, function()
    return next(progress.status()) == nil
  end),
  "completed task should be cleaned up"
)

assert(opened >= 2, "notification windows should open for tracked clients")
assert(closed >= 2, "notification windows should close after completed tasks are cleaned up")

vim.cmd("LspProgressNotifyDisable")
assert(progress.is_enabled() == false, "plugin should be disabled")

print("smoke tests passed")
