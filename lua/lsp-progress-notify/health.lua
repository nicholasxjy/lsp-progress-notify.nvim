local M = {}

function M.check()
  local health = vim.health or require("health")

  health.start("lsp-progress-notify.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim version is supported (>= 0.11)")
  else
    health.error("Neovim 0.11+ is required")
  end

  local ok = pcall(require, "notify")
  if ok then
    health.ok("rcarriga/nvim-notify is available")
  else
    health.warn("rcarriga/nvim-notify is not available; plugin will fall back to vim.notify")
  end

  if vim.fn.exists(":LspProgressNotifyEnable") == 2 then
    health.ok("User commands are registered")
  else
    health.info(
      "User commands are not registered yet; add the plugin to 'runtimepath' or load it through your plugin manager"
    )
  end
end

return M
