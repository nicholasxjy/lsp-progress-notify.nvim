package = "lsp-progress-notify.nvim"
version = "1.0.0-1"
source = {
  url = "git+https://github.com/nicholasxjy/lsp-progress-notify.nvim",
  tag = "v1.0.0",
}
description = {
  summary = "Native floating LSP progress notifications for Neovim",
  homepage = "https://github.com/nicholasxjy/lsp-progress-notify.nvim",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  copy_directories = {
    "doc",
    "plugin",
    "lua",
  },
}
