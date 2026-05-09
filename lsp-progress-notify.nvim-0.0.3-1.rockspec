package = "lsp-progress-notify.nvim"
version = "0.0.3-1"
source = {
  url = "git+https://github.com/nicholasxjy/lsp-progress-notify.nvim",
  tag = "v0.0.3",
}
description = {
  summary = "LSP progress notifications for Neovim using nvim-notify",
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
