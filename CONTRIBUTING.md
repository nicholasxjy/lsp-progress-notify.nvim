# Contributing

感谢贡献 `lsp-progress-notify.nvim`。

## 开发环境

要求：
- Neovim `0.11+`
- `rcarriga/nvim-notify`
- 可选：`stylua`
- 可选：Lua Language Server

## 本地测试

```bash
nvim --headless -u NONE -c "lua dofile('tests/smoke.lua')" -c qa
```

## 格式化检查

```bash
stylua --check .
```

自动格式化：

```bash
stylua .
```

## Help 文档

更新 help 文档后，可本地检查：

```bash
nvim --headless -u NONE "+set rtp+=${PWD}" "+helptags doc" "+help lsp-progress-notify" +qa
```

## 提交建议

- 保持仅支持 Neovim `0.11+`
- 修改功能时同步更新 `README.md` 与 `doc/lsp-progress-notify.txt`
- 新增行为尽量补充到 `tests/smoke.lua`
