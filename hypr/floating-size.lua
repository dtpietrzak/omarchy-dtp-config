-- A floating window opens at the size its app last had. Omarchy's own size
-- rules still apply the first time, and again for a file dialog, which keeps
-- its own size so it does not replace the app's.
--
-- The size is the window's layout size, in the same units window rules use.
-- It is stored under the app class and kept across a restart.

local state_path = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
  .. "/omarchy-dtp-config/floating-sizes.lua"

local sizes = {}
local seen = {}

local function sh_quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function is_file_dialog(title)
  if type(title) ~= "string" or title == "" then
    return false
  end
  return title:match("^Open.*Files?$")
    or title:match("^Open [Ff]older")
    or title:match("^Save.*Files?$")
    or title:match("^Save.*As$")
    or title:match("^Save$")
    or title:match("^All Files$")
    or title:match("[Ww]ants to open")
    or title:match("[Ww]ants to save")
    or title:match("^[Cc]hoose")
end

local function app_key(window)
  local class = window.initial_class
  if type(class) ~= "string" or class == "" then
    class = window.class
  end
  if type(class) ~= "string" or class == "" then
    return nil
  end
  return class
end

local function load_sizes()
  local chunk = loadfile(state_path)
  if not chunk then
    return
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    return
  end
  for key, size in pairs(data) do
    if type(key) == "string" and type(size) == "table" then
      local width, height = tonumber(size[1]), tonumber(size[2])
      if width and height and width >= 50 and height >= 50 and width <= 10000 and height <= 10000 then
        sizes[key] = { math.floor(width), math.floor(height) }
      end
    end
  end
end

local function save_sizes()
  local directory = state_path:match("^(.*)/")
  if directory then
    os.execute("mkdir -p " .. sh_quote(directory))
  end

  local keys = {}
  for key in pairs(sizes) do
    table.insert(keys, key)
  end
  table.sort(keys)

  local lines = { "return {" }
  for _, key in ipairs(keys) do
    local size = sizes[key]
    table.insert(lines, string.format("  [%q] = { %d, %d },", key, size[1], size[2]))
  end
  table.insert(lines, "}")
  table.insert(lines, "")

  local temporary = state_path .. ".tmp"
  local file = io.open(temporary, "w")
  if not file then
    return
  end
  file:write(table.concat(lines, "\n"))
  file:close()
  os.rename(temporary, state_path)
end

-- File dialogs share an app's class, and a fullscreen window reports the
-- monitor. Neither is the size the next ordinary window should open at.
local function remember(window)
  if not window or not window.floating or window.hidden or window.mapped == false then
    return false
  end
  if (window.fullscreen or 0) ~= 0 or is_file_dialog(window.title) or is_file_dialog(window.initial_title) then
    return false
  end
  local size = window.size
  if not size or size.x < 50 or size.y < 50 then
    return false
  end

  local key = app_key(window)
  if not key then
    return false
  end

  local width, height = math.floor(size.x), math.floor(size.y)
  local previous = seen[window.address]
  seen[window.address] = { width, height }
  if previous and previous[1] == width and previous[2] == height then
    return false
  end

  local current = sizes[key]
  if current and current[1] == width and current[2] == height then
    return false
  end

  sizes[key] = { width, height }
  return true
end

local function remember_others(except_address)
  local changed = false
  for _, window in ipairs(hl.get_windows()) do
    if window.address ~= except_address and remember(window) then
      changed = true
    end
  end
  if changed then
    save_sizes()
  end
end

local function apply(window)
  local key = app_key(window)
  local remembered = key and sizes[key]
  if not remembered or not window.floating or window.hidden or (window.fullscreen or 0) ~= 0 then
    return
  end
  if is_file_dialog(window.title) or is_file_dialog(window.initial_title) then
    return
  end
  local size = window.size
  if size and math.abs(size.x - remembered[1]) < 2 and math.abs(size.y - remembered[2]) < 2 then
    seen[window.address] = { remembered[1], remembered[2] }
    return
  end

  hl.dispatch(hl.dsp.window.resize({
    x = remembered[1],
    y = remembered[2],
    relative = false,
    window = window,
  }))
  seen[window.address] = { remembered[1], remembered[2] }
end

load_sizes()

hl.on("window.open", function(window)
  remember_others(window.address)
  apply(window)
end)

hl.on("window.close", function(window)
  if remember(window) then
    save_sizes()
  end
end)

hl.on("hyprland.shutdown", function()
  remember_others(nil)
end)

-- There is no resize event. Sample the goal size, which does not move while
-- the resize animation is still running.
hl.timer(function()
  remember_others(nil)
end, { timeout = 100, type = "repeat" })
