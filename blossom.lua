-- BLOSSOM
-- Basic Logging Of Scoring Statistics Originating (in) MAME

-- Tracks stage-by-stage scoring during INP playback
-- Supported games: dkong, dkongjr, ckongpt2, dkong3
-- Supported MAME versions: 0.175+
-- Exports scoring data and summary in CSV, JSON, and TXT format

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

-- Detect and log MAME version for debugging
local function detect_mame_version()
  if emu.app_version then
    return emu.app_version()
  end
  return "unknown"
end

-- ============================================================================
-- GAME CONFIGURATIONS
-- ============================================================================

-- GAME DETECTION
local function detect_game()
  local rom_name = emu.romname()
  if rom_name == "dkong" then
    return "dkong"
  elseif rom_name == "dkongjr" then
    return "dkongjr"
  elseif rom_name == "ckongpt2" then
    return "ckongpt2"
  elseif rom_name == "dkong3" then
    return "dkong3"
  end
  return nil -- Unsupported game
end

local GAME_TYPE = detect_game()

if not GAME_TYPE then
  error("ERROR: Unsupported game. This script only works with dkong, dkongjr, and ckongpt2")
end

-- GAME CONFIGURATIONS
local GAME_CONFIGS = {
  dkong = {
    short_name = "Donkey Kong",
    full_name = "Donkey Kong (US Set 1)",
    romset = "dkong",
    frame_rate = 60.606060606060606,

    -- MEMORY ADDRESSES
    addresses = {
      game_mode = 0x600A,
      score_1 = 0x60B2, -- lower
      score_2 = 0x60B3, -- middle
      score_3 = 0x60B4, -- upper
      screen_type = 0x6227,
      lives = 0x6228,
      level = 0x6229,
      input_start_coin = 0x7D00,
    },

    -- GAME MODES
    modes = {
      transition = 0x0A,
      gameplay = 0x0C,
      dead = 0x0D,
      game_over = 0x10,
    },

    -- FEATURE FLAGS
    supports_lives_tracking = false,
    supports_variation_detection = false,
    has_loops = false,
    has_pace = true,
    continuous_boards = false,
    death_detection_method = "game_mode",

    -- GAME-SPECIFIC SETTINGS
    screen_names = {
      [1] = "Barrel",
      [2] = "Pie",
      [3] = "Spring",
      [4] = "Rivet",
    },
    start_level = 4,
    start_stage = 5,
    begin_avg = 5,
    begin_pace_level = 5,
    begin_pace_stage = 6,
    death_point_value = 700,
    barrel_multiplier = 3,
    killscreen_level = 22,
    killscreen_stage = 1,
    supports_22_4_pace = false,
    -- INPUT DETECTION
    start_button_bit = 2,
    coin_button_bit = 7,
    input_active_high = true,
    coin_impulse = false,
  },

  dkongjr = {
    short_name = "Donkey Kong Junior",
    full_name = "Donkey Kong Junior",
    romset = "dkongjr",
    frame_rate = 60.606060606060606,

    -- MEMORY ADDRESSES
    addresses = {
      game_mode = 0x600A,
      score_1 = 0x60B2, -- lower
      score_2 = 0x60B3, -- middle
      score_3 = 0x60B4, -- upper
      screen_type = 0x6227,
      lives = 0x6228,
      level = 0x6229,
      input_start_coin = 0x7D00,
    },

    -- GAME MODES
    modes = {
      transition = 0x0A,
      gameplay = 0x0C,
      dead = 0x0D,
      game_over = 0x10,
    },

    -- FEATURE FLAGS
    supports_lives_tracking = false,
    supports_variation_detection = false,
    has_loops = false,
    has_pace = true,
    continuous_boards = false,
    death_detection_method = "game_mode",

    -- GAME-SPECIFIC SETTINGS
    screen_names = {
      [1] = "Spring",
      [2] = "Jungle",
      [3] = "Chain",
      [4] = "Hideout",
    },
    start_level = 3,
    start_stage = 3,
    begin_avg = 4,
    begin_pace_level = 4,
    begin_pace_stage = 4,
    death_point_value = 2000,
    barrel_multiplier = 1,
    killscreen_level = 22,
    killscreen_stage = 1,
    level_display_bug = true,
    supports_22_4_pace = false,
    -- INPUT DETECTION
    start_button_bit = 2,
    coin_button_bit = 7,
    input_active_high = true,
    coin_impulse = false,
  },

  ckongpt2 = {
    short_name = "Crazy Kong Part II",
    full_name = "Crazy Kong Part II (Set 1)",
    romset = "ckongpt2",
    frame_rate = 60.0,

    -- MEMORY ADDRESSES
    addresses = {
      game_mode = 0x600A,
      score_1 = 0x60B2, -- lower
      score_2 = 0x60B3, -- middle
      score_3 = 0x60B4, -- upper
      screen_type = 0x6227,
      lives = 0x6228,
      level = 0x6229,
      input_start_coin = 0xB800,
    },

    -- GAME MODES
    modes = {
      transition = 0x0A,
      gameplay = 0x0C,
      dead = 0x0D,
      game_over = 0x10,
    },

    -- FEATURE FLAGS
    supports_lives_tracking = false,
    supports_variation_detection = false,
    has_loops = false,
    has_pace = true,
    continuous_boards = false,
    death_detection_method = "game_mode",

    -- GAME-SPECIFIC SETTINGS
    screen_names = {
      [1] = "Barrel",
      [2] = "Pie",
      [3] = "Spring",
      [4] = "Rivet",
    },
    start_level = 4,
    start_stage = 4,
    begin_avg = 5,
    begin_pace_level = 5,
    begin_pace_stage = 4,
    death_point_value = 700,
    barrel_multiplier = 1,
    killscreen_level = 22,
    killscreen_stage = 1,
    supports_22_4_pace = true,
    -- INPUT DETECTION
    start_button_bit = 2,
    coin_button_bit = 0,
    input_active_high = false, -- ACTIVE LOW!
    coin_impulse = false,
  },

  dkong3 = {
    short_name = "Donkey Kong 3",
    full_name = "Donkey Kong 3",
    romset = "dkong3",
    frame_rate = 60.606060606060606,

    -- MEMORY ADDRESSES
    addresses = {
      game_mode = 0x6001,
      dead = 0x6101,
      score_1 = 0x68F0, -- upper
      score_2 = 0x68F1, -- middle
      score_3 = 0x68F2, -- lower
      lives = 0x601A,
      screen_type = 0x601B,
      level = 0x6019,
      dip_switches = 0x7D80,
      input_start = 0x7C00, -- Start buttons (separate from coin)
      input_coin = 0x7C80, -- Coin buttons (separate from start)
    },

    -- GAME MODES
    modes = {
      attract = 0x02,
      gameplay = 0x09,
      bonus_calc = 0x14,
      bonus_msg = 0x16,
      transition_1 = 0x17,
      transition_2 = 0x07,
      transition_3 = 0x08,
      game_over_1 = 0x10,
      game_over_2 = 0x11,
    },

    -- DEATH STATUS
    death_status = {
      alive = 0x00,
      dead = 0x01,
    },

    -- FEATURE FLAGS
    supports_lives_tracking = true,
    supports_variation_detection = true,
    has_loops = true,
    has_pace = false,
    continuous_boards = true,
    death_detection_method = "separate_address",

    -- GAME-SPECIFIC SETTINGS
    screen_names = {
      [0] = "Blue",
      [1] = "Grey",
      [2] = "Gold",
    },
    num_screen_types = 3,
    loop_size = 256,
    max_diff_board = 27,
    rbs_milestone = 159,
    -- INPUT DETECTION
    start_button_bit = 5,
    coin_button_bit = 5, -- Same bit, different addresses
    input_active_high = true,
    coin_impulse = true, -- Only lasts 1 frame!
  },
}

-- ============================================================================
-- STATE TRACKING
-- ============================================================================

-- STATE TRACKING - DK/DKJR/CK
local prev_game_mode = 0
local prev_screen_type = 0
local prev_level = 0
local prev_score = 0 -- Adjusted score from last time we checked
local prev_raw_score = 0 -- Raw score for rollover detection
local stage_start_score = 0
local level_score_accumulated = 0
local current_level_being_played = 0
local frame_count = 0
local stage_data = {}
local current_screen_num = 0
local level_position = {}
local stage_completed_mode = nil
local completed_screen_type = 0
local completed_level = 0
local last_stage_was_completed = false
local death_count = 0
local total_death_points = 0 -- Accumulates points earned on death attempts
local start_score_for_pace = 0 -- Sum of stage scores during start phase (excludes deaths)
local start_score_total = 0 -- Total score after start phase (for display)
local start_phase_death_points = 0 -- Sum of death points during start phase
local start_phase_deaths = 0 -- Count of deaths during start phase
local score_offset = 0 -- Tracks million-point rollovers
local game_over_processed = false -- Prevents double-printing at game over

-- Best/Worst stage and level tracking (platformer games only)
-- Indexed by screen type (1-4) to match screen_sum/screen_count pattern
local screen_scores = {
  [1] = {}, -- DK/CK: Barrels, DKJR: Springs
  [2] = {}, -- DK/CK: Pies, DKJR: Jungles
  [3] = {}, -- DK/CK: Springs, DKJR: Chains
  [4] = {}, -- DK/CK: Rivets, DKJR: Hideouts
}
local level_scores = {} -- {score, label, level}

-- Pace and averages tracking (DK/DKJR/CK only)
local screen_sum = { 0, 0, 0, 0 } -- Sum for screen types 1-4
local screen_count = { 0, 0, 0, 0 } -- Count for screen types 1-4
local level_sum = 0
local level_count = 0
local can_calculate_pace = false -- Set to true after Level 5 is complete (Level 4 for DKJR)
local last_pace = nil -- Stores pace from last completed stage
local last_pace_22_4 = nil -- Stores 22-4 pace from last completed stage (ckongpt2 only)

-- STATE TRACKING - DK3 ONLY
local dk3_prev_game_mode = 0
local dk3_prev_dead_status = 0
local dk3_prev_screen_type = 0
local dk3_prev_level = 0
local dk3_actual_board_num = 0
local dk3_rbs_count = 0
local dk3_current_loop = 1
local dk3_loop_start_score = 0
local dk3_max_diff_reached = false
local dk3_max_diff_count = 0
local dk3_rbs_milestones = {}
local dk3_loop_milestones = {}
local dk3_stage_completed = false
local dk3_completed_screen_type = 0
local dk3_completed_level = 0
local dk3_screen_sum = { 0, 0, 0 } -- Blue, Grey, Gold
local dk3_screen_count = { 0, 0, 0 }
local game_variation = nil -- For DK3 variation detection

-- DK3 life tracking for extended statistics
local dk3_life_tracking = {} -- Array of {life_num, start_score, end_score, start_board, boards_completed}
local dk3_current_life_start_score = 0
local dk3_current_life_start_board = 1 -- Game starts on board 1

-- GAMEPLAY DURATION TRACKING
local start_button_pressed = false -- Edge detected: start button was pressed
local coin_inserted = false -- Edge detected: coin was inserted
local gameplay_started = false -- Confirmed: actual gameplay has begun
local start_frame = nil -- Frame number when gameplay started
local end_frame = nil -- Frame number when gameplay ended
local prev_start_state = false -- Previous frame's start button state (for edge detection)
local prev_coin_state = false -- Previous frame's coin button state (for edge detection)

-- ============================================================================
-- OUTPUT CONFIGURATIONS
-- ============================================================================

-- OUTPUT CONFIGURATION
local EXPORT_CSV = true
local EXPORT_JSON = true
local EXPORT_TEXT = true

-- Get INP filename for display (strips path if present)
local function get_inp_filename()
  local playback_file = mame_options.entries["playback"]:value()
  if playback_file and playback_file ~= "" then
    return playback_file:match("^.+[/\\](.+)$") or playback_file
  end
  return "unknown"
end

-- Try to get INP filename from playback option
local function get_output_filenames()
  local playback_file = mame_options.entries["playback"]:value()

  if playback_file and playback_file ~= "" then
    local base_name = playback_file:match("(.+)%.inp$") or playback_file
    base_name = base_name:match("^.+[/\\](.+)$") or base_name

    -- Add timestamp to prevent file collisions
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename_base = base_name .. "_" .. timestamp .. "_scores"

    return filename_base .. ".csv", filename_base .. ".json", filename_base .. ".txt"
  else
    return nil, nil, nil
  end
end

local CSV_FILE, JSON_FILE, TEXT_FILE = get_output_filenames()

if not CSV_FILE then
  error(
    "ERROR: No playback file detected. This script requires MAME to be run with -playback option"
  )
end

-- Create blossom_logs directory
local function create_output_directory()
  os.execute("mkdir blossom_logs 2>nul") -- Windows
  os.execute("mkdir -p blossom_logs 2>/dev/null") -- Unix/Mac
end

create_output_directory()

-- Prepend directory to output files
CSV_FILE = "blossom_logs/" .. CSV_FILE
JSON_FILE = "blossom_logs/" .. JSON_FILE
TEXT_FILE = "blossom_logs/" .. TEXT_FILE


-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- GAME CONFIG HELPERS
-- Get current game config
local function get_config()
  return GAME_CONFIGS[GAME_TYPE]
end

-- Get screen name based on game type
local function get_screen_type_name(screen_type)
  local config = get_config()
  return config.screen_names[screen_type] or "Unknown"
end

-- MEMORY HELPERS
-- Read single byte from memory
local function read_byte(address)
  local mem = mame_devices[":maincpu"].spaces["program"]
  local ok, val = pcall(function()
    return mem:read_u8(address)
  end)
  if not ok then
    return 0 -- Return 0 if read fails
  end
  return val
end

-- Read player 1 score from memory (3 bytes BCD = 6 digits)
local function read_score()
  local config = GAME_CONFIGS[GAME_TYPE]
  local mem = mame_devices[":maincpu"].spaces["program"]

  local ok1, byte1 = pcall(function()
    return mem:read_u8(config.addresses.score_1)
  end)
  local ok2, byte2 = pcall(function()
    return mem:read_u8(config.addresses.score_2)
  end)
  local ok3, byte3 = pcall(function()
    return mem:read_u8(config.addresses.score_3)
  end)

  if not (ok1 and ok2 and ok3) then
    return 0
  end

  -- DK3 has different byte order (upper, middle, lower)
  local score_string
  if GAME_TYPE == "dkong3" then
    score_string = string.format("%02X%02X%02X", byte1, byte2, byte3)
  else
    score_string = string.format("%02X%02X%02X", byte3, byte2, byte1)
  end

  return tonumber(score_string, 10)
end

-- Get adjusted score accounting for million-point rollovers
local function get_adjusted_score(raw_score)
  return raw_score + score_offset
end

-- Read and check for rollover - call this instead of read_score when logging data
local function read_score_with_rollover_check()
  local raw_score = read_score()

  -- Detect score rollover from 999900 to 000000 (million+ points)
  -- Compare raw scores to detect the transition, not adjusted scores
  if prev_raw_score > 900000 and raw_score < 100000 then
    score_offset = score_offset + 1000000
  end

  prev_raw_score = raw_score
  return get_adjusted_score(raw_score)
end

-- Check if a button is pressed (handles both ACTIVE HIGH and ACTIVE LOW polarity)
local function check_button_pressed(address, bit_position, active_high)
  local value = read_byte(address)

  -- Extract the specific bit using math (no bitwise operators needed - MAME compatible)
  -- Divide by 2^bit_position and check if result is odd
  local shifted = math.floor(value / (2 ^ bit_position))
  local bit_set = (shifted % 2) == 1

  if active_high then
    return bit_set -- Button pressed when bit is 1 (dkong, dkongjr, dkong3)
  else
    return not bit_set -- Button pressed when bit is 0 (ckongpt2 only)
  end
end

-- Format frame count as H:MM:SS playing time
local function format_duration(frames)
  if not frames or frames < 0 then
    return "0:00:00"
  end

  local config = get_config()
  local seconds = frames / config.frame_rate
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = math.floor(seconds % 60)

  return string.format("%d:%02d:%02d", hours, minutes, secs)
end

-- FORMATTING HELPERS
-- Format number with commas (e.g., 12345 -> "12,345")
local function format_number(num)
  local formatted = tostring(num)
  local k
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

-- Format decimal number with commas (e.g., 12345.67 -> "12,345.67")
local function format_number_decimal(num)
  local integer_part = math.floor(num)
  local decimal_part = num - integer_part
  local formatted_int = format_number(integer_part)
  return string.format("%s.%02d", formatted_int, math.floor(decimal_part * 100 + 0.5))
end

-- Format level number for display (handles DKJR display bug)
local function format_level_for_display(level)
  local config = get_config()

  if config.level_display_bug then
    if level >= 10 and level <= 16 then
      return string.format("[%d]", level)
    elseif level >= 17 and level <= 21 then
      return string.char(65 + (level - 17)) -- A-F
    else
      return tostring(level)
    end
  else
    return tostring(level)
  end
end

-- Format stage name as 'level-position' (uses format_level_for_display for level portion)
local function get_stage_name(level, position)
  local level_display = format_level_for_display(level)
  return string.format("%s-%d", level_display, position)
end

-- PACE HELPERS
-- Calculate base pace for each game
local function calculate_pace(lives_remaining)
  if not can_calculate_pace then
    return nil
  end

  local config = get_config()

  -- Check if we have all required screen type averages
  for i = 1, 4 do
    if screen_count[i] == 0 then
      return nil
    end
  end

  -- Calculate averages for each screen type
  local screen_avg = {}
  for i = 1, 4 do
    screen_avg[i] = screen_sum[i] / screen_count[i]
  end

  -- Calculate estimated death points
  local estimated_death_points
  if death_count == 0 then
    estimated_death_points = lives_remaining * config.death_point_value
  else
    estimated_death_points = total_death_points + (lives_remaining * config.death_point_value)
  end

  -- Now calculate pace
  local pace

  -- Pace formulas:
  --   DK:    start + (((barrel_avg * 3) + pie_avg + spring_avg + rivet_avg) * 17) + deaths
  --   DKJR:  start + ((jungle_avg + spring_avg + hideout_avg + chain_avg) * 18) + deaths
  --   CK:    start + ((barrel_avg + pie_avg + spring_avg + rivet_avg) * 17) + deaths

  if GAME_TYPE == "dkong" then
    pace = start_score_for_pace
      + (((screen_avg[1] * 3) + screen_avg[2] + screen_avg[3] + screen_avg[4]) * 17)
      + estimated_death_points
  elseif GAME_TYPE == "dkongjr" then
    -- Memory mapping: 1=Spring, 2=Jungle, 3=Chain, 4=Hideout
    pace = start_score_for_pace
      + ((screen_avg[2] + screen_avg[1] + screen_avg[4] + screen_avg[3]) * 18)
      + estimated_death_points
  elseif GAME_TYPE == "ckongpt2" then
    pace = start_score_for_pace
      + ((screen_avg[1] + screen_avg[2] + screen_avg[3] + screen_avg[4]) * 17)
      + estimated_death_points
  end

  -- Round to nearest 100
  return math.floor(pace / 100 + 0.5) * 100
end

-- Calculate extended pace for CK
local function calculate_22_4_pace(base_pace, lives_remaining)
  local config = get_config()
  if not config.supports_22_4_pace or not base_pace then
    return nil
  end
  return base_pace + 13700 + (lives_remaining * 1500)
end

-- ============================================================================
-- DK3 HELPER FUNCTIONS
-- ============================================================================

-- Get board name with loop information for DK3
local function get_board_name_dk3(actual_board, memory_board, loop_num)
  if actual_board <= 255 then
    return string.format("%d", actual_board)
  elseif actual_board == 256 then
    return string.format("256 (Board 0)")
  else
    if memory_board == 0 then
      return string.format("%d (Loop %d: Board 256/0)", actual_board, loop_num)
    else
      return string.format("%d (Loop %d: Board %d)", actual_board, loop_num, memory_board)
    end
  end
end

-- Detect DK3 game variation from DIP switches
local function detect_variation_dk3()
  local config = get_config()
  local dip_value = read_byte(config.addresses.dip_switches)

  local variations = {
    [0x00] = "Difficulty 1 - Marathon",
    [0x3E] = "Difficulty 1 - 5 Lives",
    [0x40] = "Difficulty 2 - Marathon",
    [0x7E] = "Difficulty 2 - 5 Lives",
    [0x80] = "Difficulty 3 - Marathon",
    [0xBE] = "Difficulty 3 - 5 Lives",
    [0xC0] = "Difficulty 4 - Marathon",
    [0xFE] = "Difficulty 4 - 5 Lives",
  }

  if variations[dip_value] then
    return variations[dip_value]
  else
    -- Decode custom settings
    local lives_map = { [0] = "3", [1] = "4", [2] = "5", [3] = "6" }
    local bonus_map = { [0] = "30k", [1] = "40k", [2] = "50k", [3] = "None" }
    local diff_map = { [0] = "1", [1] = "2", [2] = "3", [3] = "4" }

    local lives = lives_map[dip_value % 4]
    local bonus = bonus_map[math.floor(dip_value / 4) % 4]
    local extra = bonus_map[math.floor(dip_value / 16) % 4]
    local diff = diff_map[math.floor(dip_value / 64)]

    return string.format(
      "Custom: %s Lives, %s Bonus, %s Extra, Diff %s (0x%02X)",
      lives,
      bonus,
      extra,
      diff,
      dip_value
    )
  end
end

-- Record a DK3 board result
local function record_board_dk3(
  actual_board,
  memory_board,
  screen_num,
  score_earned,
  total_score,
  is_death,
  death_num,
  lives_remaining,
  screen_type
)
  local board_info = {
    screen_num = screen_num,
    board = get_board_name_dk3(actual_board, memory_board, dk3_current_loop),
    screen_type = get_screen_type_name(screen_type),
    level = actual_board,
    score_earned = score_earned,
    total_score = total_score,
    death = is_death,
    death_num = death_num,
    is_level_total = false,
    frame = frame_count,
    lives = lives_remaining,
    avg_type = nil,
    avg_value = nil,
  }

  table.insert(stage_data, board_info)

  -- Track averages (only for completed boards, not deaths, and only during max difficulty)
  local avg_str = ""
  if not is_death and dk3_max_diff_reached then
    -- Skip Board 0 (256, 512, etc.) - these are Blue boards not included in averages
    local memory_board_check = actual_board % 256
    if memory_board_check ~= 0 then
      local avg_value = nil
      local avg_type = nil

      -- Update sum and count for this screen type (0, 1, or 2)
      if screen_type >= 0 and screen_type <= 2 then
        local idx = screen_type + 1 -- Lua arrays are 1-indexed
        dk3_screen_sum[idx] = dk3_screen_sum[idx] + score_earned
        dk3_screen_count[idx] = dk3_screen_count[idx] + 1
        avg_value = dk3_screen_sum[idx] / dk3_screen_count[idx]
        avg_type = get_screen_type_name(screen_type) .. " Avg"
      end

      -- Store in board_info and format for console
      if avg_value then
        board_info.avg_type = avg_type
        board_info.avg_value = avg_value
        avg_str = string.format(" | %s: %s", avg_type, format_number_decimal(avg_value))
      end
    end
  end

  -- Console output
  if is_death then
    print(
      string.format(
        "*** Death #%d - Board %s [%s] *** | Death Points: %s | Total Score: %s | Lives: %d",
        death_num,
        board_info.board,
        board_info.screen_type,
        format_number(score_earned),
        format_number(total_score),
        lives_remaining
      )
    )
  else
    print(
      string.format(
        "Board %s [%s] Complete | Board Score: %s | Total Score: %s | Lives: %d%s",
        board_info.board,
        board_info.screen_type,
        format_number(score_earned),
        format_number(total_score),
        lives_remaining,
        avg_str
      )
    )
  end

  -- Check for MAX DIFFICULTY reached (board 26 completion triggers the message, board 27+ gets averages)
  if not is_death then
    local memory_board_check = actual_board % 256
    if memory_board_check == 26 then
      dk3_max_diff_count = dk3_max_diff_count + 1
      dk3_max_diff_reached = true
      print(
        string.format(
          "\n>>> MAX DIFFICULTY REACHED <<< | Start Phase %d Score: %s | Total Score: %s\n",
          dk3_max_diff_count,
          format_number(total_score),
          format_number(total_score)
        )
      )
    end
  end

  -- Check for RBS milestone (finishing board 159, 415, 671, etc.)
  if
    not is_death
    and (actual_board == 159 or (actual_board > 159 and (actual_board - 159) % 256 == 0))
  then
    dk3_rbs_count = dk3_rbs_count + 1
    local rbs_score = total_score - dk3_loop_start_score

    -- Store milestone data
    table.insert(dk3_rbs_milestones, {
      rbs_num = dk3_rbs_count,
      total_score = total_score,
      rbs_score = rbs_score,
    })

    print(
      string.format(
        "\n>>> REPETITIVE BLUE SCREEN %d REACHED <<< | RBS %d Score: %s | Total Score: %s\n",
        dk3_rbs_count,
        dk3_rbs_count,
        format_number(rbs_score),
        format_number(total_score)
      )
    )
  end

  -- Check for loop completion (board 256, 512, 768, etc. = memory board 0)
  if not is_death and actual_board % 256 == 0 and actual_board > 0 then
    local loop_num = actual_board / 256 -- Which loop just completed (1, 2, 3, etc.)
    local loop_score = total_score - dk3_loop_start_score

    -- Store milestone data
    table.insert(dk3_loop_milestones, {
      loop_num = loop_num,
      total_score = total_score,
      loop_score = loop_score,
    })

    print(
      string.format(
        "\n>>> LOOP %d COMPLETE | LOOP %d Score: %s | Total Score: %s <<<\n",
        loop_num,
        loop_num,
        format_number(loop_score),
        format_number(total_score)
      )
    )

    -- Pause average tracking for next loop's start phase
    dk3_max_diff_reached = false
  end
end

-- Record a stage result
local function record_stage(
  screen_type,
  level,
  position,
  screen_num,
  score_earned,
  total_score,
  is_death,
  death_num,
  lives_remaining
)
  local stage_info = {
    screen_num = screen_num,
    stage = get_stage_name(level, position),
    screen_type = get_screen_type_name(screen_type),
    level = level,
    score_earned = score_earned,
    total_score = total_score,
    death = is_death,
    death_num = death_num,
    is_level_total = false,
    frame = frame_count,
    avg_type = nil, -- Will store "Barrel Avg", "Pie Avg", etc.
    avg_value = nil, -- Will store the calculated average
    pace = nil, -- Will store the calculated pace
    pace_22_4 = nil, -- Will store the 22-4 extended pace (ckongpt2 only)
  }

  table.insert(stage_data, stage_info)

  -- Track start phase scores and deaths
  local config = get_config()
  if start_score_total == 0 then -- Still in start phase
    if is_death then
      -- Track deaths during start phase
      start_phase_deaths = start_phase_deaths + 1
      start_phase_death_points = start_phase_death_points + score_earned
    else
      -- Accumulate stage scores during start phase
      start_score_for_pace = start_score_for_pace + score_earned

      -- Check if this completes the start phase
      if level == config.start_level and position == config.start_stage then
        start_score_total = total_score
      end
    end
  end

  -- Track averages (only for completed stages, not deaths)
  local avg_str = ""
  if not is_death and level >= config.begin_avg and level <= 21 then
    local avg_value = nil
    local avg_type = nil

    -- Update sum and count for this screen type
    if screen_type >= 1 and screen_type <= 4 then
      screen_sum[screen_type] = screen_sum[screen_type] + score_earned
      screen_count[screen_type] = screen_count[screen_type] + 1
      avg_value = screen_sum[screen_type] / screen_count[screen_type]
      avg_type = get_screen_type_name(screen_type) .. " Avg"
    end

    -- Store in stage_info and format for console
    if avg_value then
      stage_info.avg_type = avg_type
      stage_info.avg_value = avg_value
      avg_str = string.format(" | %s: %s", avg_type, format_number_decimal(avg_value))
    end

    -- Check if we can enable pace calculation
    if
      level > config.begin_pace_level
      or (level == config.begin_pace_level and position >= config.begin_pace_stage)
    then
      local all_screens_seen = true
      for i = 1, 4 do
        if screen_count[i] == 0 then
          all_screens_seen = false
          break
        end
      end
      if all_screens_seen then
        can_calculate_pace = true
      end
    end
  end

  -- Track individual scores for best/worst analysis (only for completed stages, not deaths)
  if not is_death and level >= config.begin_avg and level <= 21 then
    local level_display = format_level_for_display(level)

    -- Determine the display label for this stage
    local stage_label
    if screen_type == 1 and config.barrel_multiplier == 3 then
      -- DK Barrels appear 3x per level - show stage position
      stage_label = get_stage_name(level, position)
    else
      -- All other screens appear 1x per level - show level only
      stage_label = string.format("L%s", level_display)
    end

    -- Store score in appropriate screen type array
    if screen_type >= 1 and screen_type <= 4 then
      table.insert(
        screen_scores[screen_type],
        { score = score_earned, label = stage_label, level = level }
      )
    end
  end

  -- Calculate pace (only for completed stages, not deaths)
  local pace_str = ""
  if not is_death then
    local pace = calculate_pace(lives_remaining)
    if pace then
      -- Store pace in stage_info for text file output
      stage_info.pace = pace
      last_pace = pace

      -- Check if we should show extended pace (ckongpt2 only)
      local pace_22_4 = calculate_22_4_pace(pace, lives_remaining)
      if pace_22_4 then
        stage_info.pace_22_4 = pace_22_4
        last_pace_22_4 = pace_22_4

        -- On 22-1->22-3: show only 22-4 pace
        if level == 22 and position >= 1 and position <= 3 then
          pace_str = string.format(" | 22-4 Pace: %s", format_number(pace_22_4))
        else
          -- Before 22-1: show both paces
          pace_str = string.format(
            " | 22-1 Pace: %s | 22-4 Pace: %s",
            format_number(pace),
            format_number(pace_22_4)
          )
        end
      else
        pace_str = string.format(" | Pace: %s", format_number(pace))
      end
    end
  end

  -- Clean console output
  if is_death then
    print(
      string.format(
        "*** Death #%d - Stage %s *** | Death Points: %s | Total Score: %s",
        death_num,
        stage_info.stage,
        format_number(score_earned),
        format_number(total_score)
      )
    )
  else
    print(
      string.format(
        "Stage %s Complete | Stage Score: %s | Total Score: %s%s%s",
        stage_info.stage,
        format_number(score_earned),
        format_number(total_score),
        avg_str,
        pace_str
      )
    )
  end
end

-- Record a level total
local function record_level_total(level, score_earned, total_score)
  local level_display = format_level_for_display(level)
  local level_info = {
    screen_num = "",
    stage = string.format("Level %s Total", level_display),
    screen_type = "",
    level = level,
    score_earned = score_earned,
    total_score = total_score,
    death = false,
    death_num = nil,
    is_level_total = true,
    frame = frame_count,
  }

  table.insert(stage_data, level_info)

  -- Track L5-L21 level averages
  local avg_str = ""
  local config = get_config()
  if level >= config.begin_avg and level <= 21 then
    level_sum = level_sum + score_earned
    level_count = level_count + 1
    avg_str = string.format(" | Level Avg: %s", format_number_decimal(level_sum / level_count))
  end

  -- Track level scores for best/worst analysis
  local config = get_config()
  if level >= config.begin_avg and level <= 21 then
    local level_display = format_level_for_display(level)
    table.insert(
      level_scores,
      { score = score_earned, label = string.format("L%s", level_display), level = level }
    )
  end

  print(
    string.format(
      "\n>>> LEVEL %s COMPLETE | Level Score: %s | Total Score: %s%s <<<\n",
      level_display,
      format_number(score_earned),
      format_number(total_score),
      avg_str
    )
  )
end

-- Helper to find best and worst scores with tie handling
local function find_best_worst(scores_array)
  if #scores_array == 0 then
    return nil, nil, nil, nil -- best_score, best_labels, worst_score, worst_labels
  end

  -- Find best (max) score
  local best_score = scores_array[1].score
  for _, entry in ipairs(scores_array) do
    if entry.score > best_score then
      best_score = entry.score
    end
  end

  -- Find worst (min) score
  local worst_score = scores_array[1].score
  for _, entry in ipairs(scores_array) do
    if entry.score < worst_score then
      worst_score = entry.score
    end
  end

  -- Collect all labels that match best score
  local best_labels = {}
  for _, entry in ipairs(scores_array) do
    if entry.score == best_score then
      table.insert(best_labels, entry.label)
    end
  end

  -- Collect all labels that match worst score
  local worst_labels = {}
  for _, entry in ipairs(scores_array) do
    if entry.score == worst_score then
      table.insert(worst_labels, entry.label)
    end
  end

  -- Join labels with comma-space
  local best_str = table.concat(best_labels, ", ")
  local worst_str = table.concat(worst_labels, ", ")

  return best_score, best_str, worst_score, worst_str
end

-- Calculate DK3 life statistics
local function calculate_dk3_life_stats()
  if #dk3_life_tracking == 0 then
    return nil -- No deaths yet
  end

  local stats = {
    total_lives = #dk3_life_tracking,
    first_life_score = dk3_life_tracking[1].end_score - dk3_life_tracking[1].start_score,
    last_life_score = 0,
    five_lives_score = nil,
    longest_life_points = { score = 0, life_nums = {} },
    longest_life_boards = { boards = 0, life_nums = {} },
    shortest_life_points = { score = math.huge, life_nums = {} },
    shortest_life_boards = { boards = math.huge, life_nums = {} },
    avg_points = 0,
    avg_boards = 0,
  }

  -- Calculate last life score
  local last_life = dk3_life_tracking[#dk3_life_tracking]
  stats.last_life_score = last_life.end_score - last_life.start_score

  -- Calculate 5 lives score (score at 5th death)
  if #dk3_life_tracking >= 5 then
    stats.five_lives_score = dk3_life_tracking[5].end_score
  end

  -- Find longest/shortest lives and calculate totals
  local total_points = 0
  local total_boards = 0

  for _, life in ipairs(dk3_life_tracking) do
    local life_points = life.end_score - life.start_score
    local life_boards = life.boards_completed

    total_points = total_points + life_points
    total_boards = total_boards + life_boards

    -- Longest by points
    if life_points > stats.longest_life_points.score then
      stats.longest_life_points.score = life_points
      stats.longest_life_points.life_nums = { life.life_num }
    elseif life_points == stats.longest_life_points.score then
      table.insert(stats.longest_life_points.life_nums, life.life_num)
    end

    -- Longest by boards
    if life_boards > stats.longest_life_boards.boards then
      stats.longest_life_boards.boards = life_boards
      stats.longest_life_boards.life_nums = { life.life_num }
    elseif life_boards == stats.longest_life_boards.boards then
      table.insert(stats.longest_life_boards.life_nums, life.life_num)
    end

    -- Shortest by points
    if life_points < stats.shortest_life_points.score then
      stats.shortest_life_points.score = life_points
      stats.shortest_life_points.life_nums = { life.life_num }
    elseif life_points == stats.shortest_life_points.score then
      table.insert(stats.shortest_life_points.life_nums, life.life_num)
    end

    -- Shortest by boards
    if life_boards < stats.shortest_life_boards.boards then
      stats.shortest_life_boards.boards = life_boards
      stats.shortest_life_boards.life_nums = { life.life_num }
    elseif life_boards == stats.shortest_life_boards.boards then
      table.insert(stats.shortest_life_boards.life_nums, life.life_num)
    end
  end

  -- Calculate averages
  stats.avg_points = total_points / stats.total_lives
  stats.avg_boards = total_boards / stats.total_lives

  return stats
end

-- ============================================================================
-- EXPORT FUNCTIONS
-- ============================================================================

-- Export to CSV
local function export_csv()
  if not EXPORT_CSV then
    return
  end

  local file = io.open(CSV_FILE, "w")
  if not file then
    print("ERROR: Could not create CSV file - check file permissions or if file is open")
    return
  end

  -- Write header based on game type
  if GAME_TYPE == "dkong3" then
    file:write(
      "Attempt_Num,Board_Number,Board_Label,Screen_Type,Score_Earned,Total_Score,Death,Death_Num,Lives,Frame,Variation,Romset,INP_File,Start_Button_Frame,End_Game_Frame,Playing_Time_Frames\n"
    )
  else
    file:write(
      "Screen_Num,Stage,Screen_Type,Level,Score_Earned,Total_Score,Death,Death_Num,Frame,Romset,INP_File,Start_Button_Frame,End_Game_Frame,Playing_Time_Frames\n"
    )
  end

  -- Write data
  local first_row = true
  for _, stage in ipairs(stage_data) do
    local screen_num_str = stage.screen_num == "" and "" or tostring(stage.screen_num)
    local death_num_str = stage.death_num and tostring(stage.death_num) or ""
    local inp_file_str = first_row and get_inp_filename() or ""
    local start_frame_str = ""
    local end_frame_str = ""
    local duration_str = ""
    if first_row then
      start_frame_str = start_frame and tostring(start_frame) or ""
      end_frame_str = end_frame and tostring(end_frame) or ""
      if start_frame and end_frame then
        duration_str = tostring(end_frame - start_frame)
      end
    end

    if GAME_TYPE == "dkong3" then
      -- DK3 format with Lives and Variation
      local config = get_config()
      local variation_str = first_row and (game_variation or "") or ""
      local romset_str = first_row and config.romset or ""
      file:write(string.format(
        "%s,%d,%s,%s,%d,%d,%s,%s,%d,%d,%s,%s,%s,%s,%s,%s\n",
        screen_num_str, -- Attempt_Num
        stage.level, -- Board_Number
        stage.board, -- Board_Label
        stage.screen_type, -- Screen_Type
        stage.score_earned,
        stage.total_score,
        stage.death and "true" or "false",
        death_num_str,
        stage.lives or 0,
        stage.frame,
        variation_str,
        romset_str,
        inp_file_str,
        start_frame_str,
        end_frame_str,
        duration_str
      ))
    else
      -- Standard platformer format
      local config = get_config()
      local romset_str = first_row and config.romset or ""
      file:write(
        string.format(
          "%s,%s,%s,%d,%d,%d,%s,%s,%d,%s,%s,%s,%s,%s\n",
          screen_num_str,
          stage.stage,
          stage.screen_type,
          stage.level,
          stage.score_earned,
          stage.total_score,
          stage.death and "true" or "false",
          death_num_str,
          stage.frame,
          romset_str,
          inp_file_str,
          start_frame_str,
          end_frame_str,
          duration_str
        )
      )
    end

    first_row = false
  end

  file:close()
  print(string.format("\n[OK] CSV exported to: %s", CSV_FILE))
end

-- Export to JSON
local function export_json()
  if not EXPORT_JSON then
    return
  end

  local file = io.open(JSON_FILE, "w")
  if not file then
    print("ERROR: Could not create JSON file")
    return
  end

  local config = get_config()

  file:write("{\n")
  file:write(string.format('  "game": "%s",\n', config.full_name))
  file:write(string.format('  "romset": "%s",\n', config.romset))

  -- Add DK3-specific variation field
  if GAME_TYPE == "dkong3" then
    file:write(string.format('  "variation": "%s",\n', game_variation or ""))
  end

  file:write(string.format('  "final_score": %d,\n', prev_score))

  -- Add final level/stage info
  if GAME_TYPE == "dkong3" then
    -- DK3: final_level (formatted label) and final_stage (board number)
    local final_level_str = ""
    local final_stage_num = nil
    for i = #stage_data, 1, -1 do
      if not stage_data[i].is_level_total then
        local board_label = stage_data[i].board
        -- Only prepend "Board " for simple numeric boards (avoid "Board 257 (Loop 2: Board 1)")
        if not board_label:match("%(") then
          final_level_str = "Board " .. board_label
        else
          final_level_str = board_label
        end
        final_stage_num = stage_data[i].level -- Raw board number (actual_board_num)
        break
      end
    end

    if final_level_str ~= "" then
      file:write(string.format('  "final_level": "%s",\n', final_level_str))
      file:write(string.format('  "final_stage": %d,\n', final_stage_num))
    else
      file:write('  "final_level": null,\n')
      file:write('  "final_stage": null,\n')
    end
  else
    -- Platformer: final_level (stage name) and final_stage (screen_num)
    local final_level_str = ""
    local final_stage_num = nil
    for i = #stage_data, 1, -1 do
      if not stage_data[i].is_level_total then
        final_level_str = stage_data[i].stage -- Formatted stage like "22-1"
        final_stage_num = stage_data[i].screen_num -- Unique stage counter
        break
      end
    end

    if final_level_str ~= "" then
      file:write(string.format('  "final_level": "%s",\n', final_level_str))
      file:write(string.format('  "final_stage": %d,\n', final_stage_num))
    else
      file:write('  "final_level": null,\n')
      file:write('  "final_stage": null,\n')
    end
  end

  -- Timing information
  if start_frame and end_frame then
    local duration_frames = end_frame - start_frame
    file:write(string.format('  "playing_time": "%s",\n', format_duration(duration_frames)))
  else
    file:write('  "playing_time": null,\n')
  end

  if start_frame then
    file:write(string.format('  "start_button_frame": %d,\n', start_frame))
  else
    file:write('  "start_button_frame": null,\n')
  end

  if end_frame then
    file:write(string.format('  "end_game_frame": %d,\n', end_frame))
  else
    file:write('  "end_game_frame": null,\n')
  end

  if start_frame and end_frame then
    local duration_frames = end_frame - start_frame
    file:write(string.format('  "playing_time_frames": %d,\n', duration_frames))
  else
    file:write('  "playing_time_frames": null,\n')
  end

  file:write(string.format('  "inp_file": "%s",\n', get_inp_filename()))

  file:write('  "stages": [\n')
  for i, stage in ipairs(stage_data) do
    file:write("    {\n")

    if stage.is_level_total then
      file:write('      "screen_num": null,\n')
    else
      file:write(string.format('      "screen_num": %d,\n', stage.screen_num))
    end

    -- Use "board" or "stage" depending on game type
    if GAME_TYPE == "dkong3" then
      file:write(string.format('      "board": "%s",\n', stage.board))
    else
      file:write(string.format('      "stage": "%s",\n', stage.stage))
    end

    file:write(string.format('      "screen_type": "%s",\n', stage.screen_type))
    file:write(string.format('      "level": %d,\n', stage.level))
    file:write(string.format('      "score_earned": %d,\n', stage.score_earned))
    file:write(string.format('      "total_score": %d,\n', stage.total_score))

    -- Add lives for DK3
    if GAME_TYPE == "dkong3" then
      file:write(string.format('      "lives": %d,\n', stage.lives or 0))
    end

    file:write(string.format('      "death": %s,\n', stage.death and "true" or "false"))

    if stage.death_num then
      file:write(string.format('      "death_num": %d,\n', stage.death_num))
    else
      file:write('      "death_num": null,\n')
    end

    file:write(
      string.format('      "is_level_total": %s,\n', stage.is_level_total and "true" or "false")
    )
    file:write(string.format('      "frame": %d\n', stage.frame))
    file:write(i < #stage_data and "    },\n" or "    }\n")
  end

  file:write("  ]\n")
  file:write("}\n")

  file:close()
  print(string.format("[OK] JSON exported to: %s", JSON_FILE))
end

-- Export to Text
local function export_text()
  if not EXPORT_TEXT then
    return
  end

  local file = io.open(TEXT_FILE, "w")
  if not file then
    print("ERROR: Could not create text file")
    return
  end

  local config = get_config()

  if GAME_TYPE == "dkong3" then
    -- ============================================================================
    -- DK3 TEXT FORMAT
    -- ============================================================================
    -- Find final board
    local final_board = ""
    for i = #stage_data, 1, -1 do
      final_board = stage_data[i].board
      break
    end

    -- Header
    local config = get_config()
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))
    file:write(string.format("Variation: %s\n", game_variation or ""))
    -- Add playing time if available
    if start_frame and end_frame then
      local duration_frames = end_frame - start_frame
      file:write(string.format("Estimated Playing Time: %s\n", format_duration(duration_frames)))
    end
    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_board ~= "" then
      file:write(string.format("Final Board: %s\n", final_board))
    end

    -- Display RBS milestones
    for _, rbs in ipairs(dk3_rbs_milestones) do
      file:write(
        string.format(
          "RBS %d Score: %s (%s)\n",
          rbs.rbs_num,
          format_number(rbs.total_score),
          format_number(rbs.rbs_score)
        )
      )
    end

    -- Display Loop milestones
    for _, loop in ipairs(dk3_loop_milestones) do
      file:write(
        string.format(
          "Loop %d Score: %s (%s)\n",
          loop.loop_num,
          format_number(loop.total_score),
          format_number(loop.loop_score)
        )
      )
    end

    -- Screen type averages (only shown if max difficulty was reached)
    if dk3_max_diff_count > 0 then
      for i = 0, 2 do
        local idx = i + 1
        if dk3_screen_count[idx] > 0 then
          file:write(
            string.format(
              "Max Difficulty %s Average: %s\n",
              config.screen_names[i],
              format_number_decimal(dk3_screen_sum[idx] / dk3_screen_count[idx])
            )
          )
        end
      end
    end

    -- Life statistics
    local life_stats = calculate_dk3_life_stats()
    if life_stats then
      file:write("\n") -- Blank line before life stats

      -- Only show Total Lives for Marathon variations (redundant for 5 Lives)
      if game_variation and not game_variation:match("5 Lives") then
        file:write(string.format("Total Lives: %d\n", life_stats.total_lives))
      end

      file:write(
        string.format("First Life Score: %s\n", format_number(life_stats.first_life_score))
      )

      -- Only show 5 Lives Score if: Marathon variation AND player died 5+ times
      if life_stats.five_lives_score and game_variation and not game_variation:match("5 Lives") then
        file:write(string.format("5 Lives Score: %s\n", format_number(life_stats.five_lives_score)))
      end

      file:write(string.format("Last Life Score: %s\n", format_number(life_stats.last_life_score)))

      -- Longest life by points
      local longest_points_str = "#"
        .. table.concat(life_stats.longest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (points): %s - %s\n",
          longest_points_str,
          format_number(life_stats.longest_life_points.score)
        )
      )

      -- Longest life by boards
      local longest_boards_str = "#"
        .. table.concat(life_stats.longest_life_boards.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (boards): %s - %d\n",
          longest_boards_str,
          life_stats.longest_life_boards.boards
        )
      )

      -- Shortest life by points
      local shortest_points_str = "#"
        .. table.concat(life_stats.shortest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Shortest Life (points): %s - %s\n",
          shortest_points_str,
          format_number(life_stats.shortest_life_points.score)
        )
      )

      -- Shortest life by boards
      local shortest_boards_str = "#"
        .. table.concat(life_stats.shortest_life_boards.life_nums, ", #")
      file:write(
        string.format(
          "Shortest Life (boards): %s - %d\n",
          shortest_boards_str,
          life_stats.shortest_life_boards.boards
        )
      )

      file:write(
        string.format(
          "Average Life (points): %s\n",
          format_number(math.floor(life_stats.avg_points))
        )
      )
      file:write(string.format("Average Life (boards): %d\n", math.floor(life_stats.avg_boards)))
    end

    file:write(string.format("Total Death Points: %s\n\n", format_number(total_death_points)))
    file:write("===================================\n\n")

    -- Board data
    for _, board in ipairs(stage_data) do
      if board.death then
        file:write(
          string.format(
            "Death #%d - Board %s [%s]: %s --> %s | Lives: %d\n",
            board.death_num,
            board.board,
            board.screen_type,
            format_number(board.score_earned),
            format_number(board.total_score),
            board.lives
          )
        )
      else
        local board_line = string.format(
          "Board %s [%s]: %s --> %s | Lives: %d",
          board.board,
          board.screen_type,
          format_number(board.score_earned),
          format_number(board.total_score),
          board.lives
        )

        if board.avg_type and board.avg_value then
          board_line = board_line
            .. string.format(" | %s: %s", board.avg_type, format_number_decimal(board.avg_value))
        end

        file:write(board_line .. "\n")
      end
    end
  else
    -- ============================================================================
    -- STANDARD PLATFORMER TEXT FORMAT
    -- ============================================================================
    -- Find the final stage (last non-level-total entry)
    local final_stage = ""
    local final_level = nil
    local final_stage_position = nil
    for i = #stage_data, 1, -1 do
      if not stage_data[i].is_level_total then
        final_stage = stage_data[i].stage
        final_level = stage_data[i].level
        final_stage_position = stage_data[i].stage:match("%-(%d+)$")
        if final_stage_position then
          final_stage_position = tonumber(final_stage_position)
        end
        break
      end
    end

    -- Header
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))

    -- Add playing time if available
    if start_frame and end_frame then
      local duration_frames = end_frame - start_frame
      file:write(string.format("Estimated Playing Time: %s\n", format_duration(duration_frames)))
    end

    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_stage ~= "" then
      file:write(string.format("Final Stage: %s\n", final_stage))
    end

    -- Show pace based on game type and final stage
    if final_level and last_pace then
      if config.supports_22_4_pace then
        -- Crazy Kong Part II
        if
          final_level == 22
          and final_stage_position
          and final_stage_position >= 1
          and final_stage_position <= 3
        then
          -- On 22-1, 22-2, or 22-3: show only 22-4 pace
          if last_pace_22_4 then
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        elseif final_level < 22 then
          -- Before level 22: show both paces
          file:write(string.format("22-1 Pace: %s\n", format_number(last_pace)))
          if last_pace_22_4 then
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        end
      else
        -- Donkey Kong and Donkey Kong Junior
        if final_level < 22 then
          file:write(string.format("Pace: %s\n", format_number(last_pace)))
        end
      end
    end

    if start_score_total > 0 then
      if start_phase_deaths > 0 then
        file:write(
          string.format(
            "Start Score: %s (%s + %s)\n",
            format_number(start_score_total),
            format_number(start_score_for_pace),
            format_number(start_phase_death_points)
          )
        )
      else
        file:write(string.format("Start Score: %s\n", format_number(start_score_total)))
      end
    end

    -- Best/Worst statistics
    -- Determine display order based on game
    local display_order
    if GAME_TYPE == "dkongjr" then
      -- DKJR gameplay order: Jungle, Spring, Chain, Hideout
      display_order = { 2, 1, 3, 4 }
    else
      -- DK/CK order: Barrel, Pie, Spring, Rivet
      display_order = { 1, 2, 3, 4 }
    end

    for _, i in ipairs(display_order) do
      if #screen_scores[i] > 0 then
        local best_score, best_labels, worst_score, worst_labels = find_best_worst(screen_scores[i])
        local avg = screen_sum[i] / screen_count[i]
        file:write(
          string.format(
            "L%d+ %ss: Average: %s | Best: %s (%s) | Worst: %s (%s)\n",
            config.begin_avg,
            get_screen_type_name(i),
            format_number_decimal(avg),
            format_number(best_score),
            best_labels,
            format_number(worst_score),
            worst_labels
          )
        )
      end
    end

    if #level_scores > 0 then
      local best_score, best_labels, worst_score, worst_labels = find_best_worst(level_scores)
      local avg = level_sum / level_count
      file:write(
        string.format(
          "L%d+ Levels: Average: %s | Best: %s (%s) | Worst: %s (%s)\n",
          config.begin_avg,
          format_number_decimal(avg),
          format_number(best_score),
          best_labels,
          format_number(worst_score),
          worst_labels
        )
      )
    end

    file:write(string.format("Total Death Points: %s\n\n", format_number(total_death_points)))
    file:write("===================================\n\n")

    -- Track when we change levels to insert separators
    local current_output_level = nil

    for _, stage in ipairs(stage_data) do
      if stage.is_level_total then
        -- Level total line
        local level_display = format_level_for_display(stage.level)
        file:write(string.format("L%s: %s\n", level_display, format_number(stage.score_earned)))
        file:write("---\n")
        current_output_level = stage.level
      else
        -- Regular stage or death
        if stage.death then
          -- Death format: "19-3 Death #3: 1,000 --> 1,014,000"
          file:write(
            string.format(
              "Death #%d - %s: %s --> %s\n",
              stage.death_num,
              stage.stage,
              format_number(stage.score_earned),
              format_number(stage.total_score)
            )
          )
        else
          -- Completed stage format with avg and pace data
          local stage_line = string.format(
            "%s: %s --> %s",
            stage.stage,
            format_number(stage.score_earned),
            format_number(stage.total_score)
          )

          -- Add average if present
          if stage.avg_type and stage.avg_value then
            stage_line = stage_line
              .. string.format(" | %s: %s", stage.avg_type, format_number_decimal(stage.avg_value))
          end

          -- Add pace if present
          if stage.pace then
            if stage.pace_22_4 then
              stage_line = stage_line
                .. string.format(
                  " | 22-1 Pace: %s | 22-4 Pace: %s",
                  format_number(stage.pace),
                  format_number(stage.pace_22_4)
                )
            else
              stage_line = stage_line .. string.format(" | Pace: %s", format_number(stage.pace))
            end
          end

          file:write(stage_line .. "\n")
        end
      end
    end
  end

  file:close()
  print(string.format("[OK] Text exported to: %s", TEXT_FILE))
end

-- Helper to print Game Over / Session Ended summary for platformers
local function print_platformer_summary(header_text, current_score)
  local config = get_config()

  -- Find the final stage (last non-level-total entry)
  local final_stage = ""
  local final_level = nil
  local final_stage_position = nil
  for i = #stage_data, 1, -1 do
    if not stage_data[i].is_level_total then
      final_stage = stage_data[i].stage
      final_level = stage_data[i].level
      final_stage_position = stage_data[i].stage:match("%-(%d+)$")
      if final_stage_position then
        final_stage_position = tonumber(final_stage_position)
      end
      break
    end
  end

  print(string.format("\n=== %s ===", header_text))
  -- Display playing time if we have valid start/end frames
  if start_frame and end_frame then
    local duration_frames = end_frame - start_frame
    print(string.format("Estimated Playing Time: %s", format_duration(duration_frames)))
  end
  print(string.format("Final Score: %s", format_number(current_score)))
  if final_stage ~= "" then
    print(string.format("Final Stage: %s", final_stage))
  end

  -- Show pace based on game type and final stage
  if final_level and last_pace then
    if config.supports_22_4_pace then
      -- Crazy Kong Part II
      if
        final_level == 22
        and final_stage_position
        and final_stage_position >= 1
        and final_stage_position <= 3
      then
        -- On 22-1, 22-2, or 22-3: show only 22-4 pace
        if last_pace_22_4 then
          print(string.format("22-4 Pace: %s", format_number(last_pace_22_4)))
        end
      elseif final_level < 22 then
        -- Before level 22: show both paces
        print(string.format("22-1 Pace: %s", format_number(last_pace)))
        if last_pace_22_4 then
          print(string.format("22-4 Pace: %s", format_number(last_pace_22_4)))
        end
      end
    else
      -- Donkey Kong and Donkey Kong Junior
      if final_level < 22 then
        print(string.format("Pace: %s", format_number(last_pace)))
      end
    end
  end

  if start_score_total > 0 then
    if start_phase_deaths > 0 then
      print(
        string.format("Start Score (excluding deaths): %s", format_number(start_score_for_pace))
      )
    else
      print(string.format("Start Score: %s", format_number(start_score_total)))
    end
  end

  -- Screen type statistics (1-4)
  -- Determine display order based on game
  local display_order
  if GAME_TYPE == "dkongjr" then
    -- DKJR gameplay order: Jungle, Spring, Chain, Hideout
    display_order = { 2, 1, 3, 4 }
  else
    -- DK/CK order: Barrel, Pie, Spring, Rivet
    display_order = { 1, 2, 3, 4 }
  end

  for _, i in ipairs(display_order) do
    if #screen_scores[i] > 0 then
      local best_score, best_labels, worst_score, worst_labels = find_best_worst(screen_scores[i])
      local avg = screen_sum[i] / screen_count[i]
      print(
        string.format(
          "L%d+ %ss: Average: %s | Best: %s (%s) | Worst: %s (%s)",
          config.begin_avg,
          get_screen_type_name(i),
          format_number_decimal(avg),
          format_number(best_score),
          best_labels,
          format_number(worst_score),
          worst_labels
        )
      )
    end
  end

  -- Levels
  if #level_scores > 0 then
    local best_score, best_labels, worst_score, worst_labels = find_best_worst(level_scores)
    local avg = level_sum / level_count
    print(
      string.format(
        "L%d+ Levels: Average: %s | Best: %s (%s) | Worst: %s (%s)",
        config.begin_avg,
        format_number_decimal(avg),
        format_number(best_score),
        best_labels,
        format_number(worst_score),
        worst_labels
      )
    )
  end

  print(string.format("Total Death Points: %s", format_number(total_death_points)))
end

-- Helper to print Game Over / Session Ended summary for DK3
local function print_dk3_summary(header_text, current_score)
  local config = get_config()

  -- Find final board
  local final_board = ""
  for i = #stage_data, 1, -1 do
    final_board = stage_data[i].board
    break
  end

  print(string.format("\n=== %s ===", header_text))
  print(string.format("Final Score: %s", format_number(current_score)))
  if final_board ~= "" then
    print(string.format("Final Board: %s", final_board))
  end

  -- Display playing time if we have valid start/end frames
  if start_frame and end_frame then
    local duration_frames = end_frame - start_frame
    print(string.format("Estimated Playing Time: %s", format_duration(duration_frames)))
  end

  -- Display RBS milestones
  for _, rbs in ipairs(dk3_rbs_milestones) do
    print(
      string.format(
        "RBS %d Score: %s (%s)",
        rbs.rbs_num,
        format_number(rbs.total_score),
        format_number(rbs.rbs_score)
      )
    )
  end

  -- Display Loop milestones
  for _, loop in ipairs(dk3_loop_milestones) do
    print(
      string.format(
        "Loop %d Score: %s (%s)",
        loop.loop_num,
        format_number(loop.total_score),
        format_number(loop.loop_score)
      )
    )
  end

  -- Screen type averages (only shown if max difficulty was reached)
  if dk3_max_diff_count > 0 then
    for i = 0, 2 do
      local idx = i + 1
      if dk3_screen_count[idx] > 0 then
        print(
          string.format(
            "Max Difficulty %s Average: %s",
            config.screen_names[i],
            format_number_decimal(dk3_screen_sum[idx] / dk3_screen_count[idx])
          )
        )
      end
    end
  end

  -- Life statistics
  local life_stats = calculate_dk3_life_stats()
  if life_stats then
    print("") -- Blank line before life stats

    -- Only show Total Lives for Marathon variations (redundant for 5 Lives)
    if game_variation and not game_variation:match("5 Lives") then
      print(string.format("Total Lives: %d", life_stats.total_lives))
    end

    print(string.format("First Life Score: %s", format_number(life_stats.first_life_score)))

    -- Only show 5 Lives Score if: Marathon variation AND player died 5+ times
    if life_stats.five_lives_score and game_variation and not game_variation:match("5 Lives") then
      print(string.format("5 Lives Score: %s", format_number(life_stats.five_lives_score)))
    end

    print(string.format("Last Life Score: %s", format_number(life_stats.last_life_score)))

    -- Longest life by points
    local longest_points_str = "#" .. table.concat(life_stats.longest_life_points.life_nums, ", #")
    print(
      string.format(
        "Longest Life (points): %s - %s",
        longest_points_str,
        format_number(life_stats.longest_life_points.score)
      )
    )

    -- Longest life by boards
    local longest_boards_str = "#" .. table.concat(life_stats.longest_life_boards.life_nums, ", #")
    print(
      string.format(
        "Longest Life (boards): %s - %d",
        longest_boards_str,
        life_stats.longest_life_boards.boards
      )
    )

    -- Shortest life by points
    local shortest_points_str = "#"
      .. table.concat(life_stats.shortest_life_points.life_nums, ", #")
    print(
      string.format(
        "Shortest Life (points): %s - %s",
        shortest_points_str,
        format_number(life_stats.shortest_life_points.score)
      )
    )

    -- Shortest life by boards
    local shortest_boards_str = "#"
      .. table.concat(life_stats.shortest_life_boards.life_nums, ", #")
    print(
      string.format(
        "Shortest Life (boards): %s - %d",
        shortest_boards_str,
        life_stats.shortest_life_boards.boards
      )
    )

    print(
      string.format("Average Life (points): %s", format_number(math.floor(life_stats.avg_points)))
    )
    print(string.format("Average Life (boards): %d", math.floor(life_stats.avg_boards)))
  end

  print(string.format("Total Death Points: %s", format_number(total_death_points)))
end

-- ============================================================================
-- MAIN FRAME LOOP - PLATFORMER GAMES (DK/DKJR/CK)
-- ============================================================================
local function on_frame_platformer()
  frame_count = frame_count + 1

  local config = get_config()

  -- Read current state (don't read score every frame, only when needed)
  local game_mode = read_byte(config.addresses.game_mode)
  local screen_type = read_byte(config.addresses.screen_type)
  local level = read_byte(config.addresses.level)
  local lives = read_byte(config.addresses.lives)

  -- GAMEPLAY DURATION TRACKING (runs only until gameplay confirmed)
  if not gameplay_started then
    local config = get_config()

    -- Read button states from same address (dkong, dkongjr, ckongpt2)
    local current_coin_state = check_button_pressed(
      config.addresses.input_start_coin,
      config.coin_button_bit,
      config.input_active_high
    )
    local current_start_state = check_button_pressed(
      config.addresses.input_start_coin,
      config.start_button_bit,
      config.input_active_high
    )

    -- Edge detection for coin insertion
    if current_coin_state and not prev_coin_state then
      coin_inserted = true
    end

    -- Edge detection for start button press
    if current_start_state and not prev_start_state then
      start_button_pressed = true
      if coin_inserted and not start_frame then
        start_frame = frame_count - 1
      end
    end

    -- Confirm gameplay mode started (allows wrapper to stop checking buttons)
    if coin_inserted and start_button_pressed and game_mode == config.modes.gameplay then
      gameplay_started = true
    end

    -- Update previous states for next frame's edge detection
    prev_coin_state = current_coin_state
    prev_start_state = current_start_state
  end

  -- Initialize stage_start_score on first gameplay
  if prev_game_mode ~= config.modes.gameplay and game_mode == config.modes.gameplay then
    local current_score = read_score_with_rollover_check()

    -- Check if we're starting a new level
    if level ~= current_level_being_played and current_level_being_played > 0 then
      -- Level changed - record total for previous level (using accumulated score, not delta)
      record_level_total(current_level_being_played, level_score_accumulated, current_score)

      -- Start tracking new level
      level_score_accumulated = 0 -- Reset for new level
      current_level_being_played = level
    elseif current_level_being_played == 0 then
      -- First level of the game
      level_score_accumulated = 0
      current_level_being_played = level
    end

    if stage_start_score == 0 or last_stage_was_completed then
      -- This is a new unique screen (not a retry after death)
      current_screen_num = current_screen_num + 1
      last_stage_was_completed = false

      -- Initialize position tracking for this level if needed
      if not level_position[level] then
        level_position[level] = 0
      end

      -- Increment position for this level
      level_position[level] = level_position[level] + 1
    end

    stage_start_score = current_score
    stage_completed_mode = nil
    prev_score = current_score
  end

  -- Track screen/level during gameplay
  if game_mode == config.modes.gameplay then
    prev_screen_type = screen_type
    prev_level = level
  end

  -- STAGE COMPLETION: Detect when leaving gameplay (except death)
  if
    prev_game_mode == config.modes.gameplay
    and game_mode ~= config.modes.gameplay
    and game_mode ~= config.modes.dead
  then
    if stage_completed_mode == nil then
      stage_completed_mode = game_mode
      completed_screen_type = prev_screen_type
      completed_level = prev_level
    end
  end

  -- RECORD STAGE: Wait for transition screen after completion
  if game_mode == config.modes.transition and stage_completed_mode ~= nil then
    local current_score = read_score_with_rollover_check()
    local score_earned = current_score - stage_start_score
    local current_position = level_position[completed_level]

    record_stage(
      completed_screen_type,
      completed_level,
      current_position,
      current_screen_num,
      score_earned,
      current_score,
      false,
      nil,
      lives
    )

    -- Add to level score (only for completed stages, not deaths)
    level_score_accumulated = level_score_accumulated + score_earned

    last_stage_was_completed = true
    stage_completed_mode = nil
    prev_score = current_score
  end

  -- DEATH DETECTION
  -- Death occurs when mode changes from GAMEPLAY to DEAD
  if game_mode == config.modes.dead and prev_game_mode == config.modes.gameplay then
    local current_score = read_score_with_rollover_check()
    death_count = death_count + 1
    local score_earned = current_score - stage_start_score
    local current_position = level_position[level]

    -- Accumulate death points
    total_death_points = total_death_points + score_earned

    -- Record the death
    record_stage(
      screen_type,
      level,
      current_position,
      current_screen_num,
      score_earned,
      current_score,
      true,
      death_count,
      lives
    )

    last_stage_was_completed = false
    stage_start_score = current_score
    prev_score = current_score
  end

  -- GAME OVER
  if
    game_mode == config.modes.game_over
    and prev_game_mode ~= config.modes.game_over
    and not game_over_processed
  then
    local current_score = read_score_with_rollover_check()

    game_over_processed = true

    -- Capture end frame for duration calculation
    if not end_frame then
      end_frame = frame_count - 1
    end

    -- Only record final level total if NOT on killscreen death
    local is_killscreen = (current_level_being_played == 22 and level_position[22] == 1)

    if current_level_being_played > 0 and (is_killscreen or last_stage_was_completed) then
      record_level_total(current_level_being_played, level_score_accumulated, current_score)
    end

    print_platformer_summary("GAME OVER", current_score)
    export_csv()
    export_json()
    export_text()
    print("") -- Blank line after exports to separate from WolfMAME messages
    prev_score = current_score
  end

  -- Update previous state
  prev_game_mode = game_mode
  prev_screen_type = screen_type
  prev_level = level
end

-- ============================================================================
-- MAIN FRAME LOOP - DONKEY KONG 3
-- ============================================================================
local function on_frame_dkong3()
  frame_count = frame_count + 1

  local config = get_config()
  local game_mode = read_byte(config.addresses.game_mode)
  local dead_status = read_byte(config.addresses.dead)
  local screen_type = read_byte(config.addresses.screen_type)
  local level = read_byte(config.addresses.level)
  local lives = read_byte(config.addresses.lives)

  -- GAMEPLAY DURATION TRACKING (runs only until gameplay confirmed)
  if not gameplay_started then
    local config = get_config()

    -- Read button states from SEPARATE addresses (DK3 only!)
    local current_coin_state = check_button_pressed(
      config.addresses.input_coin, -- Different address for coin
      config.coin_button_bit,
      config.input_active_high
    )
    local current_start_state = check_button_pressed(
      config.addresses.input_start, -- Different address for start
      config.start_button_bit,
      config.input_active_high
    )

    -- Edge detection for coin insertion (critical for PORT_IMPULSE!)
    if current_coin_state and not prev_coin_state then
      coin_inserted = true
    end

    -- Edge detection for start button press
    if current_start_state and not prev_start_state then
      start_button_pressed = true
      -- Capture start frame immediately if coin already inserted
      -- Subtract 1 because frame_count was incremented before we detected the press
      if coin_inserted and not start_frame then
        start_frame = frame_count - 1
      end
    end

    -- Confirm gameplay mode started (allows wrapper to stop checking buttons)
    if coin_inserted and start_button_pressed and game_mode == config.modes.gameplay then
      gameplay_started = true
    end

    -- Update previous states for next frame's edge detection
    prev_coin_state = current_coin_state
    prev_start_state = current_start_state
  end

  -- BOARD START: Entering gameplay
  if dk3_prev_game_mode ~= config.modes.gameplay and game_mode == config.modes.gameplay then
    local current_score = read_score_with_rollover_check()

    -- New screen starting
    current_screen_num = current_screen_num + 1
    stage_start_score = current_score
    dk3_stage_completed = false
    prev_score = current_score
  end

  -- Track current screen/level during gameplay
  if game_mode == config.modes.gameplay then
    dk3_prev_screen_type = screen_type
    dk3_prev_level = level
  end

  -- STAGE COMPLETION: Detect when bonus message appears (score finalized)
  if dk3_prev_game_mode == config.modes.bonus_calc and game_mode == config.modes.bonus_msg then
    dk3_stage_completed = true
    dk3_completed_screen_type = dk3_prev_screen_type
    dk3_completed_level = dk3_prev_level
  end

  -- RECORD STAGE: Wait for transition after bonus message
  if dk3_stage_completed and game_mode == config.modes.transition_1 then
    local current_score = read_score_with_rollover_check()
    local score_earned = current_score - stage_start_score

    dk3_actual_board_num = dk3_actual_board_num + 1

    record_board_dk3(
      dk3_actual_board_num,
      dk3_completed_level,
      current_screen_num,
      score_earned,
      current_score,
      false,
      nil,
      lives,
      dk3_completed_screen_type
    )

    -- After recording board 256, 512, 768, etc., increment loop counter and set new loop_start_score
    if dk3_actual_board_num % 256 == 0 then
      dk3_current_loop = dk3_current_loop + 1
      dk3_loop_start_score = current_score
    end

    dk3_stage_completed = false
    prev_score = current_score
  end

  -- DEATH DETECTION
  if
    dead_status == config.death_status.dead and dk3_prev_dead_status == config.death_status.alive
  then
    local current_score = read_score_with_rollover_check()
    death_count = death_count + 1
    local score_earned = current_score - stage_start_score

    total_death_points = total_death_points + score_earned

    -- For deaths, use actual_board_num + 1 (the board being attempted)
    local death_board_num = dk3_actual_board_num + 1

    -- Lives haven't decremented in memory yet at death detection, so subtract 1
    local lives_after_death = lives > 0 and (lives - 1) or 0

    record_board_dk3(
      death_board_num,
      level,
      current_screen_num,
      score_earned,
      current_score,
      true,
      death_count,
      lives_after_death,
      screen_type
    )

    -- Record life performance
    -- Calculate boards completed: dk3_actual_board_num is last COMPLETED board
    -- death_board_num is the board being ATTEMPTED (not completed)
    local boards_completed = dk3_actual_board_num - dk3_current_life_start_board + 1
    if boards_completed < 0 then
      boards_completed = 0 -- Edge case: died on first board of life
    end

    table.insert(dk3_life_tracking, {
      life_num = death_count,
      start_score = dk3_current_life_start_score,
      end_score = current_score,
      start_board = dk3_current_life_start_board,
      boards_completed = boards_completed, -- Store directly instead of calculating later
    })

    -- Reset for next life
    dk3_current_life_start_score = current_score
    dk3_current_life_start_board = death_board_num -- Next life starts on the board where we died

    stage_start_score = current_score
    prev_score = current_score
  end

  -- GAME OVER
  if
    (game_mode == config.modes.game_over_1 or game_mode == config.modes.game_over_2)
    and dk3_prev_game_mode ~= config.modes.game_over_1
    and dk3_prev_game_mode ~= config.modes.game_over_2
    and not game_over_processed
  then
    local current_score = read_score_with_rollover_check()

    game_over_processed = true

    -- Capture end frame for duration calculation
    if not end_frame then
      end_frame = frame_count - 1
    end

    print_dk3_summary("GAME OVER", current_score)
    export_csv()
    export_json()
    export_text()
    print("") -- Blank line after exports to separate from WolfMAME messages
    prev_score = current_score
  end

  -- Update previous state
  dk3_prev_game_mode = game_mode
  dk3_prev_dead_status = dead_status
  dk3_prev_screen_type = screen_type
  dk3_prev_level = level
end

-- ============================================================================
-- MAIN FRAME LOOP ROUTER
-- ============================================================================
local function on_frame()
  if GAME_TYPE == "dkong3" then
    on_frame_dkong3()
  else
    on_frame_platformer()
  end
end

-- INITIALIZATION
print("\n=== BLOSSOM ===")

local config = get_config()

if GAME_TYPE == "dkong3" then
  -- DK3: Show variation after game name
  print(string.format("Game: %s", config.full_name))
  print(string.format("romset: %s", config.romset))
  game_variation = detect_variation_dk3()
  print(string.format("Variation: %s", game_variation))
  print(string.format("MAME version: %s", detect_mame_version()))
  print(string.format("INP: %s\n", get_inp_filename()))
else
  -- Standard platformers: No variation line
  print(string.format("Game: %s", config.full_name))
  print(string.format("romset: %s", config.romset))
  print(string.format("MAME version: %s", detect_mame_version()))
  print(string.format("INP: %s\n", get_inp_filename()))
end

print("Tracking gameplay...\n")

-- Wrap on_frame in error protection for MAME 0.254+
local function protected_on_frame()
  local ok, err = pcall(on_frame)
  if not ok then
    print(string.format("[ERROR] Frame %d: %s", frame_count, tostring(err)))
  end
end

register_frame_callback(protected_on_frame)

register_stop_callback(function()
  -- Only process if game over hasn't been handled yet
  if not game_over_processed and current_screen_num > 0 then
    local current_score = read_score_with_rollover_check()

    -- Capture end frame for duration calculation
    if not end_frame then
      end_frame = frame_count - 1
    end

    if GAME_TYPE == "dkong3" then
      -- If we're mid-life when exiting, record the current life
      if
        death_count == 0
        or (dk3_actual_board_num > 0 and dk3_current_life_start_score < current_score)
      then
        -- Calculate boards completed for current life
        local boards_completed = dk3_actual_board_num - dk3_current_life_start_board + 1
        if boards_completed < 0 then
          boards_completed = 0
        end

        -- Record the life in progress
        table.insert(dk3_life_tracking, {
          life_num = death_count + 1, -- This would be the next death number
          start_score = dk3_current_life_start_score,
          end_score = current_score,
          start_board = dk3_current_life_start_board,
          boards_completed = boards_completed,
        })
      end

      print_dk3_summary("SESSION ENDED", current_score)
    else
      -- Determine if this is killscreen
      local is_killscreen = (current_level_being_played == 22 and level_position[22] == 1)

      -- Record final level total only if appropriate
      if
        current_level_being_played > 0
        and level_score_accumulated > 0
        and (is_killscreen or last_stage_was_completed)
      then
        record_level_total(current_level_being_played, level_score_accumulated, current_score)
      end

      print_platformer_summary("SESSION ENDED", current_score)
    end

    export_csv()
    export_json()
    export_text()
    print("") -- Blank line to separate from WolfMAME messages
  end
end)
