package = "lsp-progress-notify.nvim"
version = "scm-1"
source = {
  url = "git+https://github.com/nicholasxjy/lsp-progress-notify.nvim",
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
