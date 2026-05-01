# lsp-progress-notify.nvim

[![ci](https://github.com/jy/lsp-progress-notify.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/jy/lsp-progress-notify.nvim/actions/workflows/ci.yml)
[![stylua](https://github.com/jy/lsp-progress-notify.nvim/actions/workflows/stylua.yml/badge.svg)](https://github.com/jy/lsp-progress-notify.nvim/actions/workflows/stylua.yml)
[![license](https://img.shields.io/github/license/jy/lsp-progress-notify.nvim)](./LICENSE)
[![neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

一个基于 [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify) 的 Neovim 插件，用通知窗口显示 LSP client 的加载 / 索引 / 初始化进度。

它基于 Neovim 0.11+ 的 `LspProgress` autocmd，在 `begin/report/end` 三个阶段自动更新同一条通知，而不是反复弹出一堆新消息。

## 功能

- 使用 `nvim-notify` 展示 LSP 进度
- 同一个任务只更新一条通知
- 支持多个 LSP client 并发显示
- 支持 spinner 动画
- client detach 时自动收尾
- 仅支持 Neovim 0.11+
- 基于 `LspProgress` autocmd 实现

## 要求

- **Neovim 0.11 及以上**
- [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)

> 本插件**不支持 Neovim 0.10 及以下版本**。

## 安装

请确认你的 Neovim 版本为 `0.11+`，否则插件不会工作。

仓库现在包含：

- `plugin/lsp-progress-notify.lua`：注册用户命令
- `doc/lsp-progress-notify.txt`：`:help lsp-progress-notify`
- `lsp-progress-notify.nvim-scm-1.rockspec`：luarocks / rocks.nvim 用

### lazy.nvim

```lua
{
  "jy/lsp-progress-notify.nvim",
  dependencies = {
    "rcarriga/nvim-notify",
  },
  config = function()
    require("lsp-progress-notify").setup()
  end,
}
```

如果你希望全局 `vim.notify` 也交给 `nvim-notify`：

```lua
{
  "rcarriga/nvim-notify",
  config = function()
    vim.notify = require("notify")
  end,
}
```

## 默认配置

```lua
require("lsp-progress-notify").setup({
  enabled = true,
  spinner_interval = 120,
  icons = {
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    done = "",
  },
  messages = {
    complete = "Completed",
    detached = "Detached",
    working = "Working…",
  },
  notification = {
    level = vim.log.levels.INFO,
    ongoing_timeout = false,
    done_timeout = 2000,
    render = "default",
    stages = "fade",
  },
  title = function(client_name, task)
    return client_name
  end,
  format = function(client_name, task)
    local parts = {}

    if task.title and task.title ~= "" then
      table.insert(parts, task.title)
    end

    if task.message and task.message ~= "" and task.message ~= task.title then
      table.insert(parts, task.message)
    end

    local text = table.concat(parts, " — ")

    if task.percentage then
      if text ~= "" then
        text = string.format("%s (%d%%)", text, task.percentage)
      else
        text = string.format("%d%%", task.percentage)
      end
    end

    if text == "" then
      return task.done and "Completed" or "Working…"
    end

    return text
  end,
})
```

## 自定义示例

### 1. 更紧凑的标题

```lua
require("lsp-progress-notify").setup({
  title = function(client_name)
    return string.format(" %s", client_name)
  end,
})
```

### 2. 完成后更快消失

```lua
require("lsp-progress-notify").setup({
  notification = {
    done_timeout = 800,
  },
})
```

### 3. 自定义消息格式

```lua
require("lsp-progress-notify").setup({
  format = function(client_name, task)
    local label = task.title or task.message or "LSP"
    if task.percentage then
      return string.format("[%s] %s %d%%", client_name, label, task.percentage)
    end
    return string.format("[%s] %s", client_name, label)
  end,
})
```

## 命令

插件启动后会注册以下命令：

- `:LspProgressNotifyEnable`
- `:LspProgressNotifyDisable`
- `:LspProgressNotifyToggle`

## 帮助文档

安装后可执行：

```vim
:helptags ALL
:help lsp-progress-notify
```

## 健康检查

插件提供了 health check：

```vim
:checkhealth lsp-progress-notify
```

会检查：
- Neovim 版本是否为 `0.11+`
- `nvim-notify` 是否可用
- 用户命令是否已注册

## 导出 API

```lua
local progress = require("lsp-progress-notify")

progress.setup(opts)
progress.enable()
progress.disable()
progress.is_enabled()
progress.status()
```

`status()` 会返回当前追踪中的任务快照，方便调试。

## 版本兼容性

- 支持：Neovim `>= 0.11`
- 不支持：Neovim `0.10.x`、`0.9.x` 及更早版本

本插件不再包含旧版 `$/progress` handler fallback，统一使用 `LspProgress` autocmd。

## 工作原理

插件会跟踪每个 LSP client 的 progress token：

- `begin`：创建通知
- `report`：替换旧通知内容
- `end`：将 spinner 换成完成图标，并在 `done_timeout` 后关闭

所以像 `lua_ls`、`rust_analyzer`、`tsserver`、`gopls` 这类会发送工作进度的服务，都可以直接显示出加载状态。

## 开发

仓库包含：

- `tests/smoke.lua`：headless smoke test
- `.github/workflows/ci.yml`：GitHub Actions smoke test
- `.github/workflows/stylua.yml`：格式检查
- `.stylua.toml`：StyLua 配置
- `.luarc.json`：LuaLS 配置
- `CONTRIBUTING.md`：开发说明

本地测试：

```bash
nvim --headless -u NONE -c "lua dofile('tests/smoke.lua')" -c qa
```

本地格式检查：

```bash
stylua --check .
```

## Rocks 安装

如果你使用 `rocks.nvim` / `luarocks`，仓库也提供了 rockspec：

```lua
{
  "jy/lsp-progress-notify.nvim",
  rocks = { "lsp-progress-notify.nvim" },
}
```

## 许可证

MIT
