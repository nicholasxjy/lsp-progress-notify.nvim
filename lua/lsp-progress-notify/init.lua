local uv = vim.uv or vim.loop

local M = {}

local defaults = {
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
    ongoing_timeout = false,
    done_timeout = 2000,
    min_width = 32,
    width = 44,
    max_width = 56,
    max_height = 12,
    row = 1,
    col = 2,
    spacing = 1,
    border = "rounded",
    zindex = 50,
    winblend = 0,
    on_open = nil,
    on_close = nil,
  },
}

local state = {
  enabled = false,
  tasks = {},
  client_notifications = {},
  notification_seq = 0,
  spinner_frame = 1,
  timer = nil,
  augroup = nil,
  commands_created = false,
}

local namespace = vim.api.nvim_create_namespace("lsp-progress-notify")

local function default_format(_, task)
  local parts = {}

  if task.title and task.title ~= "" then
    table.insert(parts, task.title)
  end

  if task.message and task.message ~= "" and task.message ~= task.title then
    table.insert(parts, task.message)
  end

  local text = table.concat(parts, " — ")

  if text == "" then
    if task.done then
      return M.config.messages.complete
    end

    return M.config.messages.working
  end

  return text
end

local function default_title(client_name)
  return client_name
end

M.config = vim.tbl_deep_extend("force", defaults, {
  format = default_format,
  title = default_title,
})

local function ensure_supported_version()
  if vim.fn.has("nvim-0.11") ~= 1 then
    error("lsp-progress-notify.nvim requires Neovim >= 0.11")
  end
end

local function is_timer_active()
  if not state.timer then
    return false
  end

  local ok, active = pcall(function()
    return state.timer:is_active()
  end)

  return ok and active or false
end

local function stop_timer()
  if is_timer_active() then
    state.timer:stop()
  end
end

local function active_task_count()
  local count = 0

  for _, task in pairs(state.tasks) do
    if not task.done then
      count = count + 1
    end
  end

  return count
end

local function clamp(value, min, max)
  if value < min then
    return min
  end

  if value > max then
    return max
  end

  return value
end

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

local function truncate(text, width)
  if display_width(text) <= width then
    return text
  end

  local suffix = "…"
  local target = width - display_width(suffix)
  if target <= 0 then
    return suffix
  end

  local result = ""
  local current = 0

  for _, char in ipairs(vim.fn.split(text, "\\zs")) do
    local char_width = display_width(char)
    if current + char_width > target then
      break
    end
    result = result .. char
    current = current + char_width
  end

  return result .. suffix
end

local function pad_right(text, width)
  local padding = width - display_width(text)
  if padding <= 0 then
    return text
  end

  return text .. string.rep(" ", padding)
end

local function center_gap(left, right, width)
  left = truncate(left, width)
  local remaining = width - display_width(left) - display_width(right)
  if remaining < 1 then
    return truncate(left, width)
  end

  return left .. string.rep(" ", remaining) .. right
end

local function progress_bar(percentage, width)
  percentage = clamp(percentage or 0, 0, 100)

  local filled = math.floor((width * percentage / 100) + 0.5)
  if filled <= 0 then
    return string.rep("─", width)
  end

  if filled >= width then
    return string.rep("━", width)
  end

  return string.rep("━", filled) .. string.rep("─", width - filled)
end

local function current_spinner_icon()
  local frames = M.config.icons.spinner
  return frames[state.spinner_frame]
end

local function set_highlights()
  local highlights = {
    LspProgressNotifyNormal = { fg = "#d8dee9", bg = "#20242a" },
    LspProgressNotifyBorder = { fg = "#3a414a", bg = "#20242a" },
    LspProgressNotifyTitle = { fg = "#d8dee9", bg = "#20242a", bold = true },
    LspProgressNotifyMuted = { fg = "#8f98a3", bg = "#20242a" },
    LspProgressNotifyDim = { fg = "#707983", bg = "#20242a" },
    LspProgressNotifyActive = { fg = "#8bd17c", bg = "#20242a" },
    LspProgressNotifyInfo = { fg = "#7aa2f7", bg = "#20242a" },
    LspProgressNotifyDone = { fg = "#e5c07b", bg = "#20242a" },
    LspProgressNotifyBar = { fg = "#8bd17c", bg = "#20242a" },
  }

  for group, options in pairs(highlights) do
    options.default = true
    vim.api.nvim_set_hl(0, group, options)
  end
end

local function ensure_notification(client_id)
  local key = tostring(client_id)
  local notification = state.client_notifications[key]

  if notification and vim.api.nvim_buf_is_valid(notification.buf) then
    return notification
  end

  state.notification_seq = state.notification_seq + 1
  notification = {
    buf = vim.api.nvim_create_buf(false, true),
    win = nil,
    close_seq = 0,
    seq = state.notification_seq,
  }

  vim.bo[notification.buf].buftype = "nofile"
  vim.bo[notification.buf].bufhidden = "wipe"
  vim.bo[notification.buf].swapfile = false
  vim.bo[notification.buf].filetype = "lsp-progress-notify"

  state.client_notifications[key] = notification

  return notification
end

local function configured_width()
  local notification = M.config.notification
  local columns = vim.o.columns
  local available = math.max(20, columns - (notification.col * 2) - 4)
  local max_width = math.min(notification.max_width, available)

  return clamp(notification.width, notification.min_width, max_width)
end

local function window_config(width, height, row)
  local notification = M.config.notification

  return {
    relative = "editor",
    anchor = "NE",
    row = row,
    col = math.max(0, vim.o.columns - notification.col),
    width = width,
    height = height,
    style = "minimal",
    focusable = false,
    border = notification.border,
    zindex = notification.zindex,
  }
end

local function close_client_notification(client_id)
  local key = tostring(client_id)
  local notification = state.client_notifications[key]

  if not notification then
    return
  end

  if notification.win and vim.api.nvim_win_is_valid(notification.win) then
    pcall(vim.api.nvim_win_close, notification.win, true)
    if M.config.notification.on_close then
      pcall(M.config.notification.on_close)
    end
  end

  if notification.buf and vim.api.nvim_buf_is_valid(notification.buf) then
    pcall(vim.api.nvim_buf_delete, notification.buf, { force = true })
  end

  state.client_notifications[key] = nil
end

local function layout_notifications()
  local notifications = {}

  for _, notification in pairs(state.client_notifications) do
    if notification.win and vim.api.nvim_win_is_valid(notification.win) then
      table.insert(notifications, notification)
    end
  end

  table.sort(notifications, function(a, b)
    return a.seq < b.seq
  end)

  local row = M.config.notification.row
  local width = configured_width()

  for _, notification in ipairs(notifications) do
    local height = vim.api.nvim_win_get_height(notification.win)
    vim.api.nvim_win_set_config(notification.win, window_config(width, height, row))
    row = row + height + M.config.notification.spacing + 2
  end
end

local function schedule_notification_close(client_id, delay)
  if not delay or delay == false then
    return
  end

  local notification = state.client_notifications[tostring(client_id)]
  if not notification then
    return
  end

  notification.close_seq = notification.close_seq + 1
  local close_seq = notification.close_seq

  vim.defer_fn(function()
    local current = state.client_notifications[tostring(client_id)]
    if current and current.close_seq == close_seq then
      close_client_notification(client_id)
      layout_notifications()
    end
  end, delay)
end

local function render_client_lines(title, client_name, tasks, all_done)
  local width = configured_width()
  local content_width = width - 2
  local lines = {}
  local highlights = {}
  local spinner = current_spinner_icon()
  local header_icon = all_done and M.config.icons.done or spinner
  local strip_end = #"▌"
  local header_start = #"▌ "
  local task_icon_start = #"▌   "
  local bar_start = #"▌     "

  table.insert(lines, "▌ " .. center_gap(header_icon .. "  " .. title, "LSP", content_width))
  table.insert(highlights, {
    group = "LspProgressNotifyActive",
    line = 0,
    start_col = 0,
    end_col = strip_end,
  })
  table.insert(highlights, {
    group = "LspProgressNotifyTitle",
    line = 0,
    start_col = header_start,
    end_col = -1,
  })

  local max_task_lines = math.max(1, M.config.notification.max_height - 1)
  local used_task_lines = 0

  for index, task in ipairs(tasks) do
    if used_task_lines >= max_task_lines then
      local remaining = #tasks - index + 1
      local overflow = pad_right(string.format("+ %d more task(s)", remaining), content_width)
      table.insert(lines, "▌ " .. overflow)
      table.insert(highlights, {
        group = "LspProgressNotifyMuted",
        line = #lines - 1,
        start_col = header_start,
        end_col = -1,
      })
      break
    end

    local icon = task.done and M.config.icons.done or spinner
    local percentage = task.percentage and string.format("%d%%", task.percentage) or ""
    local message = tostring(M.config.format(client_name, task) or "")
    local text_width = content_width - 4 - display_width(percentage)

    if percentage ~= "" then
      text_width = text_width - 1
    end

    local left = icon .. "  " .. truncate(message, math.max(1, text_width))
    local line = "▌   " .. center_gap(left, percentage, content_width - 2)

    table.insert(lines, line)
    table.insert(highlights, {
      group = "LspProgressNotifyMuted",
      line = #lines - 1,
      start_col = 0,
      end_col = strip_end,
    })
    table.insert(highlights, {
      group = task.done and "LspProgressNotifyDone" or "LspProgressNotifyInfo",
      line = #lines - 1,
      start_col = task_icon_start,
      end_col = task_icon_start + #icon,
    })

    used_task_lines = used_task_lines + 1

    if task.percentage and not task.done and used_task_lines < max_task_lines then
      local bar_width = content_width - 5
      table.insert(lines, "▌     " .. progress_bar(task.percentage, bar_width))
      table.insert(highlights, {
        group = "LspProgressNotifyBar",
        line = #lines - 1,
        start_col = bar_start,
        end_col = -1,
      })
      used_task_lines = used_task_lines + 1
    end
  end

  return lines, highlights, width
end

local function next_spinner_icon()
  local frames = M.config.icons.spinner
  local frame = frames[state.spinner_frame]

  state.spinner_frame = (state.spinner_frame % #frames) + 1

  return frame
end

local function schedule_cleanup(key, client_id, delay)
  vim.defer_fn(function()
    local task = state.tasks[key]
    if task and task.done then
      state.tasks[key] = nil
    end
    local remaining = false
    for _, t in pairs(state.tasks) do
      if t.client_id == client_id then
        remaining = true
        break
      end
    end
    if not remaining then
      close_client_notification(client_id)
      layout_notifications()
    end
  end, delay)
end

local function get_client_tasks(client_id)
  local tasks = {}
  for _, task in pairs(state.tasks) do
    if task.client_id == client_id then
      table.insert(tasks, task)
    end
  end
  table.sort(tasks, function(a, b)
    return (a.seq or 0) < (b.seq or 0)
  end)
  return tasks
end

local function show_client(client_id)
  local tasks = get_client_tasks(client_id)
  if #tasks == 0 then
    close_client_notification(client_id)
    layout_notifications()
    return
  end

  local client = vim.lsp.get_client_by_id(client_id)
  local client_name = client and client.name or string.format("LSP %d", client_id)

  local all_done = true
  for _, task in ipairs(tasks) do
    if not task.done then
      all_done = false
    end
  end

  local title = M.config.title(client_name, tasks[1]) or client_name
  local lines, highlights, width = render_client_lines(title, client_name, tasks, all_done)
  local notification = ensure_notification(client_id)
  local height = #lines

  vim.bo[notification.buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(notification.buf, namespace, 0, -1)
  vim.api.nvim_buf_set_lines(notification.buf, 0, -1, false, lines)
  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      notification.buf,
      namespace,
      highlight.group,
      highlight.line,
      highlight.start_col,
      highlight.end_col
    )
  end
  vim.bo[notification.buf].modifiable = false

  if not notification.win or not vim.api.nvim_win_is_valid(notification.win) then
    notification.win = vim.api.nvim_open_win(
      notification.buf,
      false,
      window_config(width, height, M.config.notification.row)
    )
    vim.wo[notification.win].winblend = M.config.notification.winblend
    vim.wo[notification.win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

    if M.config.notification.on_open then
      pcall(M.config.notification.on_open, notification.win)
    end
  else
    vim.api.nvim_win_set_buf(notification.win, notification.buf)
    vim.api.nvim_win_set_config(
      notification.win,
      window_config(width, height, M.config.notification.row)
    )
  end

  layout_notifications()

  if not all_done then
    schedule_notification_close(client_id, M.config.notification.ongoing_timeout)
  end
end

local function ensure_timer()
  if active_task_count() == 0 or is_timer_active() then
    return
  end

  if not state.timer then
    state.timer = uv.new_timer()
  end

  state.timer:start(
    M.config.spinner_interval,
    M.config.spinner_interval,
    vim.schedule_wrap(function()
      if not state.enabled then
        stop_timer()
        return
      end

      if active_task_count() == 0 then
        stop_timer()
        return
      end

      next_spinner_icon()

      local client_ids = {}
      for _, task in pairs(state.tasks) do
        if not task.done then
          client_ids[task.client_id] = true
        end
      end
      for client_id in pairs(client_ids) do
        show_client(client_id)
      end
    end)
  )
end

local function serialize_token(token)
  local token_type = type(token)

  if token_type == "string" then
    return string.format("%q", token)
  end

  if token_type == "number" or token_type == "boolean" or token == nil then
    return tostring(token)
  end

  return vim.inspect(token)
end

local function make_key(client_id, token)
  return tostring(client_id) .. ":" .. serialize_token(token)
end

local function finish_task(task, key, message)
  task.done = true

  if message and message ~= "" then
    task.message = message
  elseif not task.message or task.message == "" then
    task.message = M.config.messages.complete
  end

  show_client(task.client_id)
  schedule_cleanup(key, task.client_id, M.config.notification.done_timeout or 1000)

  if active_task_count() == 0 then
    stop_timer()
  end
end

local function handle_progress(client_id, token, value)
  if not state.enabled or not value then
    return
  end

  local client = vim.lsp.get_client_by_id(client_id)
  local client_name = client and client.name or string.format("LSP %d", client_id)
  local key = make_key(client_id, token)
  local task = state.tasks[key]

  if not task then
    task = {
      client_id = client_id,
      client_name = client_name,
      token = token,
      title = nil,
      message = nil,
      percentage = nil,
      done = false,
      seq = (state.task_seq or 0) + 1,
    }
    state.task_seq = task.seq
    state.tasks[key] = task
  end

  task.client_name = client_name

  if value.title ~= nil then
    task.title = value.title
  end

  if value.message ~= nil then
    task.message = value.message
  end

  if value.percentage ~= nil then
    task.percentage = value.percentage
  end

  if value.kind == "end" then
    finish_task(task, key, value.message)
    return
  end

  task.done = false
  show_client(client_id)
  ensure_timer()
end

local function clear_client_tasks(client_id)
  for key, task in pairs(state.tasks) do
    if task.client_id == client_id and not task.done then
      finish_task(task, key, M.config.messages.detached)
    end
  end
end

local function create_commands()
  if state.commands_created or vim.fn.exists(":LspProgressNotifyEnable") == 2 then
    state.commands_created = true
    return
  end

  vim.api.nvim_create_user_command("LspProgressNotifyEnable", function()
    M.enable()
  end, { desc = "Enable lsp-progress-notify" })

  vim.api.nvim_create_user_command("LspProgressNotifyDisable", function()
    M.disable()
  end, { desc = "Disable lsp-progress-notify" })

  vim.api.nvim_create_user_command("LspProgressNotifyToggle", function()
    if state.enabled then
      M.disable()
    else
      M.enable()
    end
  end, { desc = "Toggle lsp-progress-notify" })

  state.commands_created = true
end

local function setup_autocmds()
  state.augroup = vim.api.nvim_create_augroup("LspProgressNotify", { clear = true })

  vim.api.nvim_create_autocmd("LspProgress", {
    group = state.augroup,
    callback = function(event)
      local data = event.data or {}
      local params = data.params or {}
      local client_id = data.client_id
      local token = params.token
      local value = params.value and vim.deepcopy(params.value) or nil

      vim.schedule(function()
        handle_progress(client_id, token, value)
      end)
    end,
    desc = "Show LSP progress in floating windows",
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = state.augroup,
    callback = function(event)
      local data = event.data or {}
      local client_id = data.client_id

      if client_id then
        vim.schedule(function()
          clear_client_tasks(client_id)
        end)
      end
    end,
    desc = "Clear LSP progress notifications for detached clients",
  })
end

function M.enable()
  ensure_supported_version()

  if state.enabled then
    return
  end

  create_commands()
  set_highlights()
  state.enabled = true
  setup_autocmds()
end

function M.disable()
  if not state.enabled then
    return
  end

  state.enabled = false
  stop_timer()
  state.tasks = {}
  state.task_seq = 0

  local client_ids = {}
  for client_id in pairs(state.client_notifications) do
    table.insert(client_ids, client_id)
  end
  for _, client_id in ipairs(client_ids) do
    close_client_notification(client_id)
  end
  state.client_notifications = {}

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
end

function M.is_enabled()
  return state.enabled
end

function M.status()
  local snapshot = {}

  for key, task in pairs(state.tasks) do
    snapshot[key] = vim.deepcopy(task)
  end

  return snapshot
end

function M.setup(opts)
  vim.validate({
    opts = { opts, "table", true },
  })

  ensure_supported_version()

  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  set_highlights()
  create_commands()

  if M.config.enabled then
    M.enable()
  end

  return M
end

return M
