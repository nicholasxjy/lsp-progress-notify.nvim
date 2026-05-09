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
    level = vim.log.levels.INFO,
    ongoing_timeout = false,
    done_timeout = 2000,
    render = "default",
    stages = "fade",
    on_open = nil,
    on_close = nil,
  },
}

local state = {
  enabled = false,
  tasks = {},
  client_notifications = {},
  spinner_frame = 1,
  timer = nil,
  augroup = nil,
  commands_created = false,
}

local function default_format(_, task)
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

local function get_notify()
  local ok, notify = pcall(require, "notify")

  if ok then
    return notify, true
  end

  return vim.notify, false
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

local function next_spinner_icon()
  local frames = M.config.icons.spinner
  local frame = frames[state.spinner_frame]

  state.spinner_frame = (state.spinner_frame % #frames) + 1

  return frame
end

local function current_spinner_icon()
  local frames = M.config.icons.spinner
  return frames[state.spinner_frame]
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
      state.client_notifications[tostring(client_id)] = nil
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
    return tostring(a.token) < tostring(b.token)
  end)
  return tasks
end

local function show_client(client_id)
  local tasks = get_client_tasks(client_id)
  if #tasks == 0 then
    return
  end

  local notify, is_nvim_notify = get_notify()
  local client = vim.lsp.get_client_by_id(client_id)
  local client_name = client and client.name or string.format("LSP %d", client_id)

  local all_done = true
  local lines = {}
  local spinner = current_spinner_icon()
  for _, task in ipairs(tasks) do
    if not task.done then
      all_done = false
    end
    local icon = task.done and M.config.icons.done or spinner
    local msg = M.config.format(task.client_name, task)
    table.insert(lines, icon .. " " .. msg)
  end

  local message = table.concat(lines, "\n")
  local title = M.config.title(client_name)
  local icon = all_done and M.config.icons.done or spinner
  local timeout = all_done and M.config.notification.done_timeout or M.config.notification.ongoing_timeout
  local existing = state.client_notifications[tostring(client_id)]

  if is_nvim_notify then
    state.client_notifications[tostring(client_id)] = notify(message, M.config.notification.level, {
      title = title,
      icon = icon,
      timeout = timeout,
      replace = existing,
      render = M.config.notification.render,
      stages = M.config.notification.stages,
      on_open = M.config.notification.on_open,
      on_close = M.config.notification.on_close,
      hide_from_history = not all_done,
    })
    return
  end

  state.client_notifications[tostring(client_id)] = notify(message, M.config.notification.level, {
    title = title,
    timeout = timeout,
  })
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

local function make_key(client_id, token)
  return string.format("%s:%s", client_id, vim.inspect(token))
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
    }
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
    desc = "Show LSP progress through nvim-notify",
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
  create_commands()

  if M.config.enabled then
    M.enable()
  end

  return M
end

return M
