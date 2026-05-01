package.preload["notify"] = function()
  return function(message, level, opts)
    _G.__lsp_progress_notify_events = _G.__lsp_progress_notify_events or {}
    table.insert(_G.__lsp_progress_notify_events, {
      message = message,
      level = level,
      opts = opts,
    })

    return { id = #_G.__lsp_progress_notify_events }
  end
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

local snapshot = progress.status()
local task = snapshot["1:\"token-1\""]
assert(task ~= nil, "task should be created on begin")
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

snapshot = progress.status()
task = snapshot["1:\"token-1\""]
assert(task.done == true, "task should be marked done")
assert(task.message == "Done", "end message mismatch")

assert(
  vim.wait(200, function()
    return next(progress.status()) == nil
  end),
  "completed task should be cleaned up"
)

local events = _G.__lsp_progress_notify_events or {}
assert(#events >= 3, "notify should have been called multiple times")
assert(events[1].opts.on_open == on_open, "on_open should be forwarded to notify")
assert(events[1].opts.on_close == on_close, "on_close should be forwarded to notify")

events[1].opts.on_open()
events[1].opts.on_close()
assert(opened == 1, "on_open callback should remain callable")
assert(closed == 1, "on_close callback should remain callable")

vim.cmd("LspProgressNotifyDisable")
assert(progress.is_enabled() == false, "plugin should be disabled")

print("smoke tests passed")
