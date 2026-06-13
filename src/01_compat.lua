-- ============================================================================
-- MAME VERSION COMPATIBILITY LAYER
-- ============================================================================

-- Check minimum version requirements (MAME 0.175+)
if not manager then
  error(
    "ERROR: This script requires MAME 0.175 or newer.\n"
      .. "The 'manager' Lua API is not available in your MAME version.\n"
      .. "Please upgrade to MAME 0.175 or later."
  )
end

if not emu.register_frame_done and not emu.add_machine_frame_notifier then
  error(
    "ERROR: This script requires MAME 0.175 or newer.\n"
      .. "Frame callback APIs (emu.register_frame_done or emu.add_machine_frame_notifier) are not available.\n"
      .. "Please upgrade to MAME 0.175 or later."
  )
end

local mame_machine
local mame_options
local mame_devices
local screen_device

-- Detect if manager.machine is a property or method
if type(manager.machine) == "userdata" then
  -- Newer MAME: manager.machine is a property
  mame_machine = manager.machine
elseif type(manager.machine) == "function" then
  -- Older MAME: manager:machine() is a method
  mame_machine = manager:machine()
else
  error("ERROR: Cannot access MAME machine object. Incompatible MAME version.")
end

-- Detect if machine.options is a property or method
if type(mame_machine.options) == "userdata" then
  -- Newer MAME: options is a property
  mame_options = mame_machine.options
elseif type(mame_machine.options) == "function" then
  -- Older MAME: options is a method
  mame_options = mame_machine:options()
else
  error("ERROR: Cannot access MAME options object. Incompatible MAME version.")
end

-- Detect if machine.devices is a property or method
if type(mame_machine.devices) == "userdata" or type(mame_machine.devices) == "table" then
  -- Newer MAME: devices is a property or table
  mame_devices = mame_machine.devices
elseif type(mame_machine.devices) == "function" then
  -- Older MAME (if any): devices is a method
  mame_devices = mame_machine:devices()
else
  error("ERROR: Cannot access MAME devices object. Incompatible MAME version.")
end

-- Access the screen device for frame counting
-- screen.frame_number provides the deterministic MAME frame counter
-- that matches the UI display (with +1 offset applied at read time)
if type(mame_machine.screens) == "userdata" or type(mame_machine.screens) == "table" then
  screen_device = mame_machine.screens[":screen"]
elseif type(mame_machine.screens) == "function" then
  screen_device = mame_machine:screens()[":screen"]
else
  error("ERROR: Cannot access MAME screens object. Incompatible MAME version.")
end

-- Detect if screen.frame_number is a property or method
local read_frame_number
if type(screen_device.frame_number) == "function" then
  -- Older MAME: frame_number() is a method
  read_frame_number = function()
    return screen_device:frame_number()
  end
else
  -- Newer MAME: frame_number is a property
  read_frame_number = function()
    return screen_device.frame_number
  end
end

-- Store frame/stop callback subscriptions for MAME 0.254+
-- CRITICAL: Must be global for MAME 0.254+ to prevent garbage collection
_G.frame_subscription = nil
_G.stop_subscription = nil

local function register_frame_callback(callback)
  if emu.add_machine_frame_notifier then
    -- Newer MAME (0.254+) - Store in GLOBAL to prevent GC
    _G.frame_subscription = emu.add_machine_frame_notifier(callback)
    if not _G.frame_subscription then
      error("ERROR: Failed to register frame notifier")
    end
  elseif emu.register_frame_done then
    -- MAME 0.175-0.253
    emu.register_frame_done(callback)
  else
    error("ERROR: Cannot register frame callback. No compatible callback API found.")
  end
end

local function register_stop_callback(callback)
  if emu.add_machine_stop_notifier then
    -- Newer MAME (0.254+) - Store in GLOBAL to prevent GC
    _G.stop_subscription = emu.add_machine_stop_notifier(callback)
    if not _G.stop_subscription then
      error("ERROR: Failed to register stop notifier")
    end
  elseif emu.register_stop then
    -- MAME 0.175-0.253
    emu.register_stop(callback)
  else
    error("ERROR: Cannot register stop callback. No compatible callback API found.")
  end
end

-- Frame callback timing offset for edge-detected signals.
-- add_machine_frame_notifier (0.254+) fires 1 frame earlier in the cycle
-- than register_frame_done (0.175-0.253) relative to the input viewer.
local start_frame_offset = 0
if emu.add_machine_frame_notifier then
  start_frame_offset = 1
end

-- Detect and log MAME version for debugging
local function detect_mame_version()
  if emu.app_version then
    return emu.app_version()
  end
  return "unknown"
end
