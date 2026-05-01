if vim.g.loaded_lsp_progress_notify == 1 then
  return
end

vim.g.loaded_lsp_progress_notify = 1

if vim.fn.has("nvim-0.11") ~= 1 then
  return
end

local function command(name, fn, desc)
  vim.api.nvim_create_user_command(name, function()
    fn(require("lsp-progress-notify"))
  end, { desc = desc })
end

command("LspProgressNotifyEnable", function(progress)
  progress.enable()
end, "Enable lsp-progress-notify")

command("LspProgressNotifyDisable", function(progress)
  progress.disable()
end, "Disable lsp-progress-notify")

command("LspProgressNotifyToggle", function(progress)
  if progress.is_enabled() then
    progress.disable()
  else
    progress.enable()
  end
end, "Toggle lsp-progress-notify")
