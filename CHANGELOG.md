# Changelog

## 0.0.2 - 2026-05-01

### Features
- Add `notification.on_open` and `notification.on_close` hooks and forward them to `nvim-notify`

### Documentation
- Document notification lifecycle hooks in the README and help docs

## 0.0.1 - 2026-05-01

### Features
- Initial release of `lsp-progress-notify.nvim`
- Display LSP progress through `nvim-notify` with one updatable notification per task
- Fall back to `vim.notify` when `nvim-notify` is unavailable
- Add a demo GIF to the README

### Documentation
- Translate the README to English
- Add `vim.pack` installation instructions
