package = "lsp-progress-notify.nvim"
version = "scm-1"
source = {
  url = "git+https://github.com/jy/lsp-progress-notify.nvim",
}
description = {
  summary = "LSP progress notifications for Neovim using nvim-notify",
  homepage = "https://github.com/jy/lsp-progress-notify.nvim",
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
