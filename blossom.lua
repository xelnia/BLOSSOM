-- BLOSSOM
-- Basic Logging Of Scoring Statistics Originating (in) MAME

-- Tracks stage-by-stage scoring during INP playback
-- Supported games: dkong, dkongjr, ckongpt2, dkong3
-- Supported MAME versions: 0.175+
-- Exports scoring data and summary in CSV, JSON, and TXT format

local BLOSSOM_VERSION = "2.0.0"

-- Export toggles: set to false to suppress specific output formats
local EXPORT_CSV = true
local EXPORT_JSON = true
local EXPORT_TEXT = true

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
    frame_rate = 2000 / 33,

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
      -- TIMING & ANALYSIS ADDRESSES
      bonus_timer = 0x62B1,
      player_x = 0x6203,
      player_y = 0x6205,
      rivet_key_count = 0x6290,
      level_display_vram = 0x74A3, -- Level ones digit tile in VRAM
      level_display_tens_vram = 0x74C3, -- Level tens digit tile in VRAM
      game_over_vram = 0x7696, -- VRAM tile for "G" in GAME OVER
      -- KILLSCREEN DETECTION
      bonus_timer_flag = 0x6386, -- Bonus timer runout flag
      bonus_timer_secondary = 0x6387, -- Secondary countdown after runout
      player_status = 0x6200, -- Player alive/dead status
      jump_status = 0x6214, -- Jump flag
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
    clear_screen_type = 4, -- Rivet screen
    supports_22_4_pace = false,
    -- INPUT DETECTION
    start_button_bit = 2,
    coin_button_bit = 7,
    input_active_high = true,
    coin_impulse = false,
    -- BONUS TIMER FORMAT
    bonus_timer_bcd = false,
  },

  dkongjr = {
    short_name = "Donkey Kong Junior",
    full_name = "Donkey Kong Junior",
    romset = "dkongjr",
    frame_rate = 2000 / 33,

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
      -- TIMING & ANALYSIS ADDRESSES
      bonus_timer = 0x62B1,
      player_x = 0x6203,
      player_y = 0x6205,
      rivet_key_count = 0x6290,
      level_display_vram = 0x7484, -- Level digit tile in VRAM (single digit, no tens)
      game_over_vram = 0x7696, -- VRAM tile for "G" in GAME OVER
      -- KILLSCREEN DETECTION
      bonus_timer_flag = 0x6386, -- Bonus timer runout flag
      bonus_timer_secondary = 0x6387, -- Secondary countdown after runout
      player_status = 0x6200, -- Player alive/dead status
      jump_status = 0x6214, -- Jump flag
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
    clear_screen_type = 3, -- Chain screen (key clear)
    level_display_bug = true,
    supports_22_4_pace = false,
    -- INPUT DETECTION
    start_button_bit = 2,
    coin_button_bit = 7,
    input_active_high = true,
    coin_impulse = false,
    -- BONUS TIMER FORMAT
    bonus_timer_bcd = false,
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
      -- TIMING & ANALYSIS ADDRESSES
      bonus_timer = 0x62B1,
      player_x = 0x6203,
      player_y = 0x6205,
      rivet_key_count = 0x6290,
      level_display_vram = 0x9083, -- Level ones digit tile in VRAM
      level_display_tens_vram = 0x90A3, -- Level tens digit tile in VRAM
      game_over_vram = 0x9296, -- VRAM tile for "G" in GAME OVER
      -- KILLSCREEN DETECTION
      bonus_timer_flag = 0x6386, -- Bonus timer runout flag
      bonus_timer_secondary = 0x6387, -- Secondary countdown after runout
      player_status = 0x6200, -- Player alive/dead status
      jump_status = 0x6214, -- Jump flag
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
    clear_screen_type = 4, -- Rivet screen
    supports_22_4_pace = true,
    -- INPUT DETECTION
    start_button_bit = 2,
    coin_button_bit = 0,
    input_active_high = false, -- ACTIVE LOW!
    coin_impulse = false,
    -- BONUS TIMER FORMAT
    bonus_timer_bcd = false,
  },

  dkong3 = {
    short_name = "Donkey Kong 3",
    full_name = "Donkey Kong 3",
    romset = "dkong3",
    frame_rate = 2000 / 33,

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
      -- TIMING & ANALYSIS ADDRESSES
      bonus_timer = 0x68C2,
      player_x = 0x6107,
      player_y = 0x6109,
      game_over_vram = 0x7629, -- VRAM tile for "G" in GAME OVER
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
    max_diff_board = 27, -- Where max difficulty starts
    rbs_milestone = 160, -- Where RBS starts
    -- INPUT DETECTION
    start_button_bit = 5,
    coin_button_bit = 5, -- Same bit, different addresses
    input_active_high = true,
    coin_impulse = true, -- Only lasts 1 frame!
    -- BONUS TIMER FORMAT
    bonus_timer_bcd = true,
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
local first_gameplay_seen = false
local death_count = 0
local total_death_points = 0 -- Accumulates points earned on death attempts
local start_score_for_pace = 0 -- Sum of stage scores during start phase (excludes deaths)
local start_score_total = 0 -- Total score after start phase (for display)
local start_phase_death_points = 0 -- Sum of death points during start phase
local start_phase_deaths = 0 -- Count of deaths during start phase
local score_offset = 0 -- Tracks million-point rollovers
local game_over_processed = false -- Prevents double-printing at game over

-- Deferred death recording (score may settle after mode changes to DEAD)
-- Platformer game_mode transitions directly to DEAD, so settlement fires
-- on the same frame as board start (execution order protects stage_start_score).
local death_pending = false
local death_pending_screen_type = 0
local death_pending_level = 0
local death_pending_position = 0
local death_pending_bonus = 0

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
local dk3_max_diff_milestones = {} -- Array of {count, total_score, start_phase_score, frame}
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

-- Deferred death recording for DK3
-- DK3 uses a separate dead_status address (0x6101) instead of a game_mode value,
-- so game_mode can re-enter gameplay before dead_status clears.
-- All state must be captured at detection time to avoid clobbering by the board start block.
local dk3_death_pending = false
local dk3_death_pending_screen_type = 0
local dk3_death_pending_level = 0
local dk3_death_pending_lives_at_death = 0
local dk3_death_pending_bonus = 0
local dk3_death_pending_start_score = 0

-- GAMEPLAY DURATION TRACKING
local start_button_pressed = false -- Edge detected: start button was pressed
local coin_inserted = false -- Edge detected: coin was inserted
local gameplay_started = false -- Confirmed: actual gameplay has begun
local start_frame = nil -- Frame number when gameplay started
local end_frame = nil -- Frame number when gameplay ended
local prev_start_state = false -- Previous frame's start button state (for edge detection)
local prev_coin_state = false -- Previous frame's coin button state (for edge detection)

-- Score milestones (all games)
local score_milestones = {} -- {score, frame} entries at every 100K
local next_score_milestone = 100000

-- Standard timing (VRAM-based)
local start_phase_end_frame = nil -- VRAM level digit change
local game_over_vram_frame = nil -- VRAM "G" tile appearance

-- Speedrun timing (DK/DKJR/CK only)
local speedrun_start_frame = nil -- First position change + 1
local speedrun_end_frame = nil -- Frame when rivet/key count reaches 0 on start level clear screen
local spawn_x = nil -- Spawn position for movement detection
local spawn_y = nil
local clear_screen_gameplay_seen = false -- True once gameplay mode seen on start level clear screen
local killscreen_frame = nil -- Killscreen trigger + 3 (visual death frame)

-- ============================================================================
-- OUTPUT CONFIGURATIONS
-- ============================================================================

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

-- Read the bonus timer value, handling encoding differences between games
-- DK/DKJR/CK: plain binary at 0x62B1 (value 50 = timer 5000)
-- DK3: BCD at 0x68C2 (value 0x79 = timer 7900)
local function read_bonus_timer()
  local config = get_config()
  local raw = read_byte(config.addresses.bonus_timer)

  if config.bonus_timer_bcd then
    -- BCD decode: each nibble is a decimal digit
    local high = math.floor(raw / 16)
    local low = raw % 16
    return (high * 10 + low) * 100
  else
    -- Plain binary: multiply directly
    return raw * 100
  end
end

-- Format frame count as H:MM:SS.mmm playing time (rounded to nearest millisecond)
local function format_duration(frames)
  if not frames or frames < 0 then
    return "0:00:00.000"
  end

  local config = get_config()
  local total_ms = math.floor((frames / config.frame_rate) * 1000 + 0.5)
  local ms = total_ms % 1000
  local total_secs = math.floor(total_ms / 1000)
  local hours = math.floor(total_secs / 3600)
  local minutes = math.floor((total_secs % 3600) / 60)
  local secs = total_secs % 60

  return string.format("%d:%02d:%02d.%03d", hours, minutes, secs, ms)
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
  screen_type,
  bonus_timer
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
    bonus_timer = bonus_timer,
  }

  table.insert(stage_data, board_info)

  local config = get_config()

  -- Track averages (only for completed boards, not deaths, and only during max difficulty)
  local avg_str = ""
  if not is_death and dk3_max_diff_reached then
    -- Skip Board 0 (256, 512, etc.) - these are Blue boards not included in averages
    local memory_board_check = actual_board % config.loop_size
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
    local timer_str = bonus_timer and string.format(" | Timer: %s", format_number(bonus_timer))
      or ""
    print(
      string.format(
        "*** Death #%d - Board %s [%s] *** | Death Points: %s | Total Score: %s | Lives: %d%s",
        death_num,
        board_info.board,
        board_info.screen_type,
        format_number(score_earned),
        format_number(total_score),
        lives_remaining,
        timer_str
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

  -- Check for MAX DIFFICULTY reached (completing board before max_diff_board triggers the message)
  if not is_death then
    local memory_board_check = actual_board % config.loop_size
    if memory_board_check == config.max_diff_board - 1 then
      dk3_max_diff_count = dk3_max_diff_count + 1
      dk3_max_diff_reached = true
      local start_phase_score = total_score - dk3_loop_start_score

      -- Store milestone data (parallel to RBS/loop milestones)
      table.insert(dk3_max_diff_milestones, {
        count = dk3_max_diff_count,
        total_score = total_score,
        start_phase_score = start_phase_score,
        frame = frame_count,
      })

      print(
        string.format(
          "\n>>> MAX DIFFICULTY REACHED <<< | Start Phase %d Score: %s | Total Score: %s\n",
          dk3_max_diff_count,
          format_number(start_phase_score),
          format_number(total_score)
        )
      )
    end
  end

  -- Check for RBS milestone (completing board before rbs_milestone, then every 256 boards)
  local rbs_trigger = config.rbs_milestone - 1
  if
    not is_death
    and (
      actual_board == rbs_trigger
      or (actual_board > rbs_trigger and (actual_board - rbs_trigger) % config.loop_size == 0)
    )
  then
    dk3_rbs_count = dk3_rbs_count + 1
    local rbs_score = total_score - dk3_loop_start_score

    -- Store milestone data
    table.insert(dk3_rbs_milestones, {
      rbs_num = dk3_rbs_count,
      total_score = total_score,
      rbs_score = rbs_score,
      frame = frame_count,
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

  -- Check for loop completion (every loop_size boards = memory board 0)
  if not is_death and actual_board % config.loop_size == 0 and actual_board > 0 then
    local loop_num = actual_board / config.loop_size -- Which loop just completed (1, 2, 3, etc.)
    local loop_score = total_score - dk3_loop_start_score

    -- Store milestone data
    table.insert(dk3_loop_milestones, {
      loop_num = loop_num,
      total_score = total_score,
      loop_score = loop_score,
      frame = frame_count,
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
  lives_remaining,
  bonus_timer
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
    bonus_timer = bonus_timer,
    lives = lives_remaining,
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
    local timer_str = bonus_timer and string.format(" | Timer: %s", format_number(bonus_timer))
      or ""
    print(
      string.format(
        "*** Death #%d - Stage %s *** | Death Points: %s | Total Score: %s%s",
        death_num,
        stage_info.stage,
        format_number(score_earned),
        format_number(total_score),
        timer_str
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

-- ============================================================================
-- JSON SERIALIZATION HELPERS
-- ============================================================================

-- Marker for ordered JSON objects (preserves key order)
-- Usage: json_ordered({ {"key1", val1}, {"key2", val2}, ... })
local function json_ordered(pairs_list)
  return { __json_ordered = true, pairs = pairs_list }
end

-- Serialize any Lua value to a JSON string with pretty-print indentation
-- Handles: nil, boolean, number, string, ordered objects, arrays
local function to_json(val, indent_level)
  indent_level = indent_level or 0
  local indent = string.rep("  ", indent_level)
  local child_indent = string.rep("  ", indent_level + 1)

  if val == nil then
    return "null"
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  elseif type(val) == "number" then
    if val == math.floor(val) and math.abs(val) < 1e15 then
      return string.format("%d", val)
    else
      return string.format("%.3f", val)
    end
  elseif type(val) == "string" then
    local escaped = val:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
    return '"' .. escaped .. '"'
  elseif type(val) == "table" then
    if val.__json_ordered then
      -- Ordered object: array of {key, value} pairs
      if #val.pairs == 0 then
        return "{}"
      end
      local lines = {}
      for i, pair in ipairs(val.pairs) do
        local k = pair[1]
        local v = pair[2]
        local comma = i < #val.pairs and "," or ""
        local serialized = to_json(v, indent_level + 1)
        table.insert(lines, string.format('%s"%s": %s%s', child_indent, k, serialized, comma))
      end
      return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
    else
      -- Regular array (sequential integer keys)
      if #val == 0 then
        return "[]"
      end
      local lines = {}
      for i, item in ipairs(val) do
        local comma = i < #val and "," or ""
        local serialized = to_json(item, indent_level + 1)
        table.insert(lines, child_indent .. serialized .. comma)
      end
      return "[\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "]"
    end
  end

  return "null"
end

-- ============================================================================
-- CSV EXPORT
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
      "attempt_num,board_number,board_label,screen_type,board_score,running_total,death,death_num,lives,frame,bonus_timer\n"
    )
  else
    file:write(
      "screen_num,stage,screen_type,level,board_score,running_total,death,death_num,lives,frame,bonus_timer\n"
    )
  end

  -- Write data (exclude level totals)
  for _, stage in ipairs(stage_data) do
    if not stage.is_level_total then
      local screen_num_str = stage.screen_num == "" and "" or tostring(stage.screen_num)
      local death_num_str = stage.death_num and tostring(stage.death_num) or ""
      local bonus_timer_str = stage.bonus_timer and tostring(stage.bonus_timer) or ""

      if GAME_TYPE == "dkong3" then
        file:write(
          string.format(
            "%s,%d,%s,%s,%d,%d,%s,%s,%d,%d,%s\n",
            screen_num_str,
            stage.level,
            stage.board,
            stage.screen_type,
            stage.score_earned,
            stage.total_score,
            stage.death and "true" or "false",
            death_num_str,
            stage.lives or 0,
            stage.frame,
            bonus_timer_str
          )
        )
      else
        file:write(
          string.format(
            "%s,%s,%s,%d,%d,%d,%s,%s,%d,%d,%s\n",
            screen_num_str,
            stage.stage,
            stage.screen_type,
            stage.level,
            stage.score_earned,
            stage.total_score,
            stage.death and "true" or "false",
            death_num_str,
            stage.lives or 0,
            stage.frame,
            bonus_timer_str
          )
        )
      end
    end
  end

  file:close()
  print(string.format("\n[OK] CSV exported to: %s", CSV_FILE))
end

-- ============================================================================
-- JSON EXPORT
-- ============================================================================

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

  -- Find the final stage/board (last non-level-total entry)
  local final_level_str = nil
  local final_stage_num = nil
  if GAME_TYPE == "dkong3" then
    for i = #stage_data, 1, -1 do
      local board_label = stage_data[i].board
      if not board_label:match("%(") then
        final_level_str = "Board " .. board_label
      else
        final_level_str = board_label
      end
      final_stage_num = stage_data[i].level
      break
    end
  else
    for i = #stage_data, 1, -1 do
      if not stage_data[i].is_level_total then
        final_level_str = stage_data[i].stage
        final_stage_num = stage_data[i].screen_num
        break
      end
    end
  end

  -- METADATA
  local metadata = json_ordered({
    { "game", config.full_name },
    { "variation", GAME_TYPE == "dkong3" and game_variation or nil },
    { "romset", config.romset },
    { "inp_file", get_inp_filename() },
    { "mame_version", detect_mame_version() },
    { "blossom_version", BLOSSOM_VERSION },
  })

  -- SCORING SUMMARY
  local scoring_pairs = {
    { "final_score", prev_score },
    { "final_level", final_level_str },
    { "final_stage", final_stage_num },
    { "recorded_deaths", death_count },
    { "total_death_points", total_death_points },
  }

  if GAME_TYPE == "dkong3" then
    -- DK3 scoring summary
    -- Screen type averages (max difficulty only)
    if dk3_max_diff_count > 0 then
      local avg_pairs = {}
      for i = 0, 2 do
        local idx = i + 1
        if dk3_screen_count[idx] > 0 then
          table.insert(
            avg_pairs,
            { config.screen_names[i]:lower(), dk3_screen_sum[idx] / dk3_screen_count[idx] }
          )
        end
      end
      if #avg_pairs > 0 then
        table.insert(scoring_pairs, { "max_diff_screen_averages", json_ordered(avg_pairs) })
      end
    end

    -- RBS milestones (score data)
    local rbs_score_array = {}
    for _, rbs in ipairs(dk3_rbs_milestones) do
      table.insert(
        rbs_score_array,
        json_ordered({
          { "rbs_num", rbs.rbs_num },
          { "total_score", rbs.total_score },
          { "rbs_score", rbs.rbs_score },
        })
      )
    end
    table.insert(scoring_pairs, { "rbs_milestones", rbs_score_array })

    -- Loop milestones (score data)
    local loop_score_array = {}
    for _, loop in ipairs(dk3_loop_milestones) do
      table.insert(
        loop_score_array,
        json_ordered({
          { "loop_num", loop.loop_num },
          { "total_score", loop.total_score },
          { "loop_score", loop.loop_score },
        })
      )
    end
    table.insert(scoring_pairs, { "loop_milestones", loop_score_array })

    -- Life statistics
    local life_stats = calculate_dk3_life_stats()
    if life_stats then
      local life_pairs = {
        { "recorded_lives", life_stats.total_lives },
        { "first_life_score", life_stats.first_life_score },
        { "five_lives_score", life_stats.five_lives_score },
        { "last_life_score", life_stats.last_life_score },
        {
          "longest_life_points",
          json_ordered({
            { "score", life_stats.longest_life_points.score },
            { "life_nums", life_stats.longest_life_points.life_nums },
          }),
        },
        {
          "longest_life_boards",
          json_ordered({
            { "boards", life_stats.longest_life_boards.boards },
            { "life_nums", life_stats.longest_life_boards.life_nums },
          }),
        },
        {
          "shortest_life_points",
          json_ordered({
            { "score", life_stats.shortest_life_points.score },
            { "life_nums", life_stats.shortest_life_points.life_nums },
          }),
        },
        {
          "shortest_life_boards",
          json_ordered({
            { "boards", life_stats.shortest_life_boards.boards },
            { "life_nums", life_stats.shortest_life_boards.life_nums },
          }),
        },
        { "avg_points", math.floor(life_stats.avg_points) },
        { "avg_boards", math.floor(life_stats.avg_boards) },
      }
      table.insert(scoring_pairs, { "life_stats", json_ordered(life_pairs) })
    end
  else
    -- Platformer scoring summary
    table.insert(scoring_pairs, { "total_screens", current_screen_num })

    -- Pace
    local final_level = nil
    if final_level_str then
      local level_match = final_level_str:match("^(%d+)-")
      if level_match then
        final_level = tonumber(level_match)
      end
    end

    if final_level and last_pace then
      if config.supports_22_4_pace then
        table.insert(scoring_pairs, { "pace_22_1", last_pace })
        table.insert(scoring_pairs, { "pace_22_4", last_pace_22_4 })
      else
        table.insert(scoring_pairs, { "pace", last_pace })
      end
    end

    -- Start score
    if start_score_total > 0 then
      table.insert(scoring_pairs, { "start_score_total", start_score_total })
      table.insert(scoring_pairs, { "start_score_for_pace", start_score_for_pace })
      table.insert(scoring_pairs, { "start_phase_deaths", start_phase_deaths })
      table.insert(scoring_pairs, { "start_phase_death_points", start_phase_death_points })
    end

    -- Screen type averages
    local display_order
    if GAME_TYPE == "dkongjr" then
      display_order = { 2, 1, 3, 4 }
    else
      display_order = { 1, 2, 3, 4 }
    end

    local screen_avg_pairs = {}
    for _, i in ipairs(display_order) do
      if #screen_scores[i] > 0 then
        local best_score, best_labels, worst_score, worst_labels = find_best_worst(screen_scores[i])
        local avg = screen_sum[i] / screen_count[i]
        local type_name = get_screen_type_name(i):lower()
        table.insert(screen_avg_pairs, {
          type_name,
          json_ordered({
            { "average", avg },
            { "best_score", best_score },
            { "best_stages", best_labels },
            { "worst_score", worst_score },
            { "worst_stages", worst_labels },
            { "count", screen_count[i] },
          }),
        })
      end
    end
    if #screen_avg_pairs > 0 then
      table.insert(scoring_pairs, { "screen_type_averages", json_ordered(screen_avg_pairs) })
    end

    -- Level averages
    if #level_scores > 0 then
      local best_score, best_labels, worst_score, worst_labels = find_best_worst(level_scores)
      local avg = level_sum / level_count
      table.insert(scoring_pairs, {
        "level_averages",
        json_ordered({
          { "average", avg },
          { "best_score", best_score },
          { "best_levels", best_labels },
          { "worst_score", worst_score },
          { "worst_levels", worst_labels },
          { "count", level_count },
        }),
      })
    end
  end

  local scoring_summary = json_ordered(scoring_pairs)

  -- TIMING SUMMARY
  local timing_pairs = {}

  -- Raw frame markers
  table.insert(timing_pairs, { "start_button_frame", start_frame })

  if GAME_TYPE ~= "dkong3" then
    table.insert(timing_pairs, { "speedrun_start_frame", speedrun_start_frame })
    table.insert(timing_pairs, { "start_phase_clear_frame", speedrun_end_frame })
    table.insert(timing_pairs, { "start_phase_end_frame", start_phase_end_frame })
    table.insert(timing_pairs, { "killscreen_frame", killscreen_frame })
  end

  table.insert(timing_pairs, { "end_game_frame", end_frame })
  table.insert(timing_pairs, { "game_over_vram_frame", game_over_vram_frame })

  -- Computed durations (platformer only)
  if GAME_TYPE ~= "dkong3" then
    -- Speedrun start duration
    if speedrun_start_frame and speedrun_end_frame then
      local dur = speedrun_end_frame - speedrun_start_frame
      table.insert(timing_pairs, { "speedrun_start_duration_frames", dur })
      table.insert(timing_pairs, { "speedrun_start_time", format_duration(dur) })
    else
      table.insert(timing_pairs, { "speedrun_start_duration_frames", nil })
      table.insert(timing_pairs, { "speedrun_start_time", nil })
    end

    -- Standard start duration
    if start_frame and start_phase_end_frame then
      local dur = start_phase_end_frame - start_frame
      table.insert(timing_pairs, { "standard_start_duration_frames", dur })
      table.insert(timing_pairs, { "standard_start_time", format_duration(dur) })
    else
      table.insert(timing_pairs, { "standard_start_duration_frames", nil })
      table.insert(timing_pairs, { "standard_start_time", nil })
    end

    -- Speedrun killscreen duration
    if speedrun_start_frame and killscreen_frame then
      local dur = killscreen_frame - speedrun_start_frame
      table.insert(timing_pairs, { "speedrun_killscreen_duration_frames", dur })
      table.insert(timing_pairs, { "speedrun_killscreen_time", format_duration(dur) })
    else
      table.insert(timing_pairs, { "speedrun_killscreen_duration_frames", nil })
      table.insert(timing_pairs, { "speedrun_killscreen_time", nil })
    end
  end

  -- Playing time (standard total: start button to game over VRAM, fallback to end_frame)
  if start_frame and game_over_vram_frame then
    local dur = game_over_vram_frame - start_frame
    table.insert(timing_pairs, { "playing_time_frames", dur })
    table.insert(timing_pairs, { "playing_time", format_duration(dur) })
  elseif start_frame and end_frame then
    local dur = end_frame - start_frame
    table.insert(timing_pairs, { "playing_time_frames", dur })
    table.insert(timing_pairs, { "playing_time", format_duration(dur) })
  else
    table.insert(timing_pairs, { "playing_time_frames", nil })
    table.insert(timing_pairs, { "playing_time", nil })
  end

  -- DK3 milestone timing
  if GAME_TYPE == "dkong3" then
    local max_diff_timing = {}
    for _, md in ipairs(dk3_max_diff_milestones) do
      local time_from_start = nil
      if start_frame then
        time_from_start = format_duration(md.frame - start_frame)
      end
      table.insert(
        max_diff_timing,
        json_ordered({
          { "count", md.count },
          { "frame", md.frame },
          { "time_from_start", time_from_start },
        })
      )
    end
    table.insert(timing_pairs, { "max_diff_milestones", max_diff_timing })

    local rbs_timing = {}
    for _, rbs in ipairs(dk3_rbs_milestones) do
      local time_from_start = nil
      if start_frame then
        time_from_start = format_duration(rbs.frame - start_frame)
      end
      table.insert(
        rbs_timing,
        json_ordered({
          { "rbs_num", rbs.rbs_num },
          { "frame", rbs.frame },
          { "time_from_start", time_from_start },
        })
      )
    end
    table.insert(timing_pairs, { "rbs_milestone_timing", rbs_timing })

    local loop_timing = {}
    for _, loop in ipairs(dk3_loop_milestones) do
      local time_from_start = nil
      if start_frame then
        time_from_start = format_duration(loop.frame - start_frame)
      end
      table.insert(
        loop_timing,
        json_ordered({
          { "loop_num", loop.loop_num },
          { "frame", loop.frame },
          { "time_from_start", time_from_start },
        })
      )
    end
    table.insert(timing_pairs, { "loop_milestone_timing", loop_timing })
  end

  local timing_summary = json_ordered(timing_pairs)

  -- SCORE MILESTONES (top-level)
  local milestones_array = {}
  for _, ms in ipairs(score_milestones) do
    local ms_pairs = {
      { "score", ms.score },
      { "frame", ms.frame },
      { "time_from_start", start_frame and format_duration(ms.frame - start_frame) or nil },
    }
    if ms.stage then
      table.insert(ms_pairs, { "stage", ms.stage })
    elseif ms.board then
      table.insert(ms_pairs, { "board", ms.board })
    end
    table.insert(ms_pairs, { "screen_num", ms.screen_num })
    table.insert(ms_pairs, { "bonus_timer", ms.bonus_timer })
    table.insert(ms_pairs, { "during_gameplay", ms.during_gameplay })
    table.insert(milestones_array, json_ordered(ms_pairs))
  end

  -- DEATHS (extracted from stage_data)
  local deaths_array = {}
  for _, stage in ipairs(stage_data) do
    if stage.death then
      local death_pairs = {
        { "death_num", stage.death_num },
        { "frame", stage.frame },
      }
      if GAME_TYPE == "dkong3" then
        table.insert(death_pairs, { "board", stage.board })
        table.insert(death_pairs, { "board_number", stage.level })
      else
        table.insert(death_pairs, { "stage", stage.stage })
        table.insert(death_pairs, { "screen_num", stage.screen_num })
      end
      table.insert(death_pairs, { "screen_type", stage.screen_type })
      table.insert(death_pairs, { "death_points", stage.score_earned })
      table.insert(death_pairs, { "running_total", stage.total_score })
      table.insert(death_pairs, { "lives", stage.lives or 0 })
      table.insert(death_pairs, { "bonus_timer", stage.bonus_timer })
      table.insert(deaths_array, json_ordered(death_pairs))
    end
  end

  -- STAGES (completed stages only: no level totals, no deaths)
  local stages_array = {}
  for _, stage in ipairs(stage_data) do
    if not stage.is_level_total and not stage.death then
      local stage_pairs = {}
      if GAME_TYPE == "dkong3" then
        table.insert(stage_pairs, { "attempt_num", stage.screen_num })
        table.insert(stage_pairs, { "board", stage.board })
        table.insert(stage_pairs, { "board_number", stage.level })
      else
        table.insert(stage_pairs, { "screen_num", stage.screen_num })
        table.insert(stage_pairs, { "stage", stage.stage })
        table.insert(stage_pairs, { "level", stage.level })
      end
      table.insert(stage_pairs, { "screen_type", stage.screen_type })
      table.insert(stage_pairs, { "board_score", stage.score_earned })
      table.insert(stage_pairs, { "running_total", stage.total_score })
      table.insert(stage_pairs, { "lives", stage.lives or 0 })
      table.insert(stage_pairs, { "frame", stage.frame })
      table.insert(stage_pairs, { "bonus_timer", stage.bonus_timer })

      if stage.avg_type then
        table.insert(stage_pairs, { "avg_type", stage.avg_type })
        table.insert(stage_pairs, { "avg_value", stage.avg_value })
      end

      if stage.pace then
        table.insert(stage_pairs, { "pace", stage.pace })
        if stage.pace_22_4 then
          table.insert(stage_pairs, { "pace_22_4", stage.pace_22_4 })
        end
      end

      table.insert(stages_array, json_ordered(stage_pairs))
    end
  end

  -- ASSEMBLE AND WRITE
  local root = json_ordered({
    { "metadata", metadata },
    { "scoring_summary", scoring_summary },
    { "timing_summary", timing_summary },
    { "score_milestones", milestones_array },
    { "deaths", deaths_array },
    { "stages", stages_array },
  })

  file:write(to_json(root, 0))
  file:write("\n")

  file:close()
  print(string.format("[OK] JSON exported to: %s", JSON_FILE))
end

-- ============================================================================
-- TEXT EXPORT
-- ============================================================================

-- Helper: compute playing time frames (start button to game over VRAM, fallback to end_frame)
local function get_playing_time_frames()
  if start_frame and game_over_vram_frame then
    return game_over_vram_frame - start_frame
  elseif start_frame and end_frame then
    return end_frame - start_frame
  end
  return nil
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

    -- HEADER
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("Variation: %s\n", game_variation or ""))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))
    file:write(string.format("MAME version: %s\n", detect_mame_version()))
    file:write(string.format("BLOSSOM version: %s\n", BLOSSOM_VERSION))

    -- SCORING SUMMARY
    file:write("\nSCORING SUMMARY\n")
    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_board ~= "" then
      file:write(string.format("Final Board: %s\n", final_board))
    end
    file:write(string.format("Recorded Deaths: %d\n", death_count))
    file:write(string.format("Total Death Points: %s\n", format_number(total_death_points)))

    -- RBS milestones (score data)
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

    -- Loop milestones (score data)
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

    -- Screen type averages (max difficulty only)
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
      file:write("\n")

      if game_variation and not game_variation:match("5 Lives") then
        file:write(
          string.format("Recorded Lives (starting + earned): %d\n", life_stats.total_lives)
        )
      end

      file:write(
        string.format("First Life Score: %s\n", format_number(life_stats.first_life_score))
      )

      if life_stats.five_lives_score and game_variation and not game_variation:match("5 Lives") then
        file:write(string.format("5 Lives Score: %s\n", format_number(life_stats.five_lives_score)))
      end

      file:write(string.format("Last Life Score: %s\n", format_number(life_stats.last_life_score)))

      local longest_points_str = "#"
        .. table.concat(life_stats.longest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (points): %s - %s\n",
          longest_points_str,
          format_number(life_stats.longest_life_points.score)
        )
      )

      local longest_boards_str = "#"
        .. table.concat(life_stats.longest_life_boards.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (boards): %s - %d\n",
          longest_boards_str,
          life_stats.longest_life_boards.boards
        )
      )

      local shortest_points_str = "#"
        .. table.concat(life_stats.shortest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Shortest Life (points): %s - %s\n",
          shortest_points_str,
          format_number(life_stats.shortest_life_points.score)
        )
      )

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

    -- TIMING SUMMARY
    local playing_frames = get_playing_time_frames()
    local has_dk3_timing = playing_frames
      or #dk3_max_diff_milestones > 0
      or #dk3_rbs_milestones > 0
      or #dk3_loop_milestones > 0
      or (start_frame and (game_over_vram_frame or end_frame))

    if has_dk3_timing then
      file:write("\nTIMING SUMMARY\n")
    end

    -- DK3 milestone timing
    for _, md in ipairs(dk3_max_diff_milestones) do
      local time_str = ""
      if start_frame then
        time_str = string.format(" (%s)", format_duration(md.frame - start_frame))
      end
      file:write(
        string.format(
          "Max Difficulty %d: Frame %s%s\n",
          md.count,
          format_number(md.frame),
          time_str
        )
      )
    end

    for _, rbs in ipairs(dk3_rbs_milestones) do
      local time_str = ""
      if start_frame then
        time_str = string.format(" (%s)", format_duration(rbs.frame - start_frame))
      end
      file:write(
        string.format("RBS %d: Frame %s%s\n", rbs.rbs_num, format_number(rbs.frame), time_str)
      )
    end

    for _, loop in ipairs(dk3_loop_milestones) do
      local time_str = ""
      if start_frame then
        time_str = string.format(" (%s)", format_duration(loop.frame - start_frame))
      end
      file:write(
        string.format(
          "Loop %d Complete: Frame %s%s\n",
          loop.loop_num,
          format_number(loop.frame),
          time_str
        )
      )
    end

    -- Elapsed times
    if playing_frames then
      file:write(string.format("Unofficial Full Game Time: %s\n", format_duration(playing_frames)))
    end

    -- Frame ranges
    if start_frame and (game_over_vram_frame or end_frame) then
      local end_f = game_over_vram_frame or end_frame
      local dur = end_f - start_frame
      file:write("\n")
      file:write(
        string.format(
          "Full Game Frames: %s - %s (%s frames)\n",
          format_number(start_frame),
          format_number(end_f),
          format_number(dur)
        )
      )
    end

    -- SCORE MILESTONES
    if #score_milestones > 0 then
      file:write("\nSCORE MILESTONES\n")
      for _, ms in ipairs(score_milestones) do
        local time_str = ""
        if start_frame then
          time_str = string.format(" - %s", format_duration(ms.frame - start_frame))
        end
        local board_str = ms.board and string.format(" | Board %d", ms.board) or ""
        local timer_str = ms.bonus_timer
            and string.format(" | Timer: %s", format_number(ms.bonus_timer))
          or ""
        local phase_str = ""
        if ms.during_gameplay == false then
          phase_str = " [stage end]"
        end
        file:write(
          string.format(
            "%s (Frame %s%s)%s%s%s\n",
            format_number(ms.score),
            format_number(ms.frame),
            time_str,
            board_str,
            timer_str,
            phase_str
          )
        )
      end
    end

    file:write("\n===================================\n\nSTAGE DATA\n")

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

    -- HEADER
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))
    file:write(string.format("MAME version: %s\n", detect_mame_version()))
    file:write(string.format("BLOSSOM version: %s\n", BLOSSOM_VERSION))

    -- SCORING SUMMARY
    file:write("\nSCORING SUMMARY\n")
    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_stage ~= "" then
      file:write(string.format("Final Stage: %s\n", final_stage))
    end
    file:write(string.format("Total Screens: %d\n", current_screen_num))
    file:write(string.format("Recorded Deaths: %d\n", death_count))
    file:write(string.format("Total Death Points: %s\n", format_number(total_death_points)))

    -- Pace
    if final_level and last_pace then
      if config.supports_22_4_pace then
        if
          final_level == 22
          and final_stage_position
          and final_stage_position >= 1
          and final_stage_position <= 3
        then
          if last_pace_22_4 then
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        elseif final_level < 22 then
          file:write(string.format("22-1 Pace: %s\n", format_number(last_pace)))
          if last_pace_22_4 then
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        end
      else
        if final_level < 22 then
          file:write(string.format("Pace: %s\n", format_number(last_pace)))
        end
      end
    end

    -- Start score
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

    -- Screen type averages
    local display_order
    if GAME_TYPE == "dkongjr" then
      display_order = { 2, 1, 3, 4 }
    else
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

    -- TIMING SUMMARY
    local playing_frames = get_playing_time_frames()
    local has_plat_timing = playing_frames
      or (speedrun_start_frame and speedrun_end_frame)
      or (start_frame and start_phase_end_frame)
      or (speedrun_start_frame and killscreen_frame)
      or (start_frame and (game_over_vram_frame or end_frame))

    if has_plat_timing then
      file:write("\nTIMING SUMMARY\n")
    end

    -- Unofficial times (guaranteed: full game time; conditional: start, killscreen)
    -- Ordered shortest to longest expected duration
    if speedrun_start_frame and speedrun_end_frame then
      local dur = speedrun_end_frame - speedrun_start_frame
      file:write(string.format("Unofficial Speedrun Start Time: %s\n", format_duration(dur)))
    end

    if start_frame and start_phase_end_frame then
      local dur = start_phase_end_frame - start_frame
      file:write(string.format("Unofficial Standard Start Time: %s\n", format_duration(dur)))
    end

    if speedrun_start_frame and killscreen_frame then
      local dur = killscreen_frame - speedrun_start_frame
      file:write(string.format("Unofficial Speedrun Killscreen Time: %s\n", format_duration(dur)))
    end

    if playing_frames then
      file:write(string.format("Unofficial Full Game Time: %s\n", format_duration(playing_frames)))
    end

    -- Frame ranges (same order as elapsed times)
    if has_plat_timing then
      file:write("\n")
    end

    if speedrun_start_frame and speedrun_end_frame then
      local dur = speedrun_end_frame - speedrun_start_frame
      file:write(
        string.format(
          "Speedrun Start Frames: %s - %s (%s frames)\n",
          format_number(speedrun_start_frame),
          format_number(speedrun_end_frame),
          format_number(dur)
        )
      )
    end

    if start_frame and start_phase_end_frame then
      local dur = start_phase_end_frame - start_frame
      file:write(
        string.format(
          "Standard Start Frames: %s - %s (%s frames)\n",
          format_number(start_frame),
          format_number(start_phase_end_frame),
          format_number(dur)
        )
      )
    end

    if speedrun_start_frame and killscreen_frame then
      local dur = killscreen_frame - speedrun_start_frame
      file:write(
        string.format(
          "Speedrun Killscreen Frames: %s - %s (%s frames)\n",
          format_number(speedrun_start_frame),
          format_number(killscreen_frame),
          format_number(dur)
        )
      )
    end

    if start_frame and (game_over_vram_frame or end_frame) then
      local end_f = game_over_vram_frame or end_frame
      local dur = end_f - start_frame
      file:write(
        string.format(
          "Full Game Frames: %s - %s (%s frames)\n",
          format_number(start_frame),
          format_number(end_f),
          format_number(dur)
        )
      )
    end

    -- SCORE MILESTONES
    if #score_milestones > 0 then
      file:write("\nSCORE MILESTONES\n")
      for _, ms in ipairs(score_milestones) do
        local time_str = ""
        if start_frame then
          time_str = string.format(" - %s", format_duration(ms.frame - start_frame))
        end
        local stage_str = ms.stage and string.format(" | %s", ms.stage) or ""
        local timer_str = ms.bonus_timer
            and string.format(" | Timer: %s", format_number(ms.bonus_timer))
          or ""
        local phase_str = ""
        if ms.during_gameplay == false then
          phase_str = " [stage end]"
        end
        file:write(
          string.format(
            "%s (Frame %s%s)%s%s%s\n",
            format_number(ms.score),
            format_number(ms.frame),
            time_str,
            stage_str,
            timer_str,
            phase_str
          )
        )
      end
    end

    file:write("\n===================================\n\nSTAGE DATA\n")

    -- Per-stage data (unchanged from current format)
    local current_output_level = nil

    for _, stage in ipairs(stage_data) do
      if stage.is_level_total then
        local level_display = format_level_for_display(stage.level)
        file:write(string.format("L%s: %s\n", level_display, format_number(stage.score_earned)))
        file:write("---\n")
        current_output_level = stage.level
      else
        if stage.death then
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
          local stage_line = string.format(
            "%s: %s --> %s",
            stage.stage,
            format_number(stage.score_earned),
            format_number(stage.total_score)
          )

          if stage.avg_type and stage.avg_value then
            stage_line = stage_line
              .. string.format(" | %s: %s", stage.avg_type, format_number_decimal(stage.avg_value))
          end

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
  print(string.format("Final Score: %s", format_number(current_score)))
  if final_stage ~= "" then
    print(string.format("Final Stage: %s", final_stage))
  end
  print(string.format("Total Screens: %d", current_screen_num))

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
        string.format(
          "Start Score: %s (%s + %s)",
          format_number(start_score_total),
          format_number(start_score_for_pace),
          format_number(start_phase_death_points)
        )
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

  print(string.format("Recorded Deaths: %d", death_count))
  print(string.format("Total Death Points: %s", format_number(total_death_points)))

  -- Timing summary (ordered shortest to longest expected duration)
  print("")

  if speedrun_start_frame and speedrun_end_frame then
    local dur = speedrun_end_frame - speedrun_start_frame
    print(
      string.format(
        "Unofficial Speedrun Start: %s | Frame %s - %s (%s frames)",
        format_duration(dur),
        format_number(speedrun_start_frame),
        format_number(speedrun_end_frame),
        format_number(dur)
      )
    )
  end

  if start_frame and start_phase_end_frame then
    local dur = start_phase_end_frame - start_frame
    print(
      string.format(
        "Unofficial Standard Start: %s | Frame %s - %s (%s frames)",
        format_duration(dur),
        format_number(start_frame),
        format_number(start_phase_end_frame),
        format_number(dur)
      )
    )
  end

  if speedrun_start_frame and killscreen_frame then
    local dur = killscreen_frame - speedrun_start_frame
    print(
      string.format(
        "Unofficial Speedrun Killscreen: %s | Frame %s - %s (%s frames)",
        format_duration(dur),
        format_number(speedrun_start_frame),
        format_number(killscreen_frame),
        format_number(dur)
      )
    )
  end

  if start_frame and (game_over_vram_frame or end_frame) then
    local final_frame = game_over_vram_frame or end_frame
    local dur = final_frame - start_frame
    print(
      string.format(
        "Unofficial Full Game: %s | Frame %s - %s (%s frames)",
        format_duration(dur),
        format_number(start_frame),
        format_number(final_frame),
        format_number(dur)
      )
    )
  end
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

    -- Only show Recorded Lives for Marathon variations (redundant for 5 Lives)
    if game_variation and not game_variation:match("5 Lives") then
      print(string.format("Recorded Lives (starting + earned): %d", life_stats.total_lives))
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

  print(string.format("Recorded Deaths: %d", death_count))
  print(string.format("Total Death Points: %s", format_number(total_death_points)))

  -- Timing summary (DK3 milestones, then full game)
  print("")

  for _, md in ipairs(dk3_max_diff_milestones) do
    local time_str = ""
    if start_frame then
      time_str = string.format(" | %s", format_duration(md.frame - start_frame))
    end
    print(
      string.format("Max Difficulty %d: Frame %s%s", md.count, format_number(md.frame), time_str)
    )
  end

  for _, rbs in ipairs(dk3_rbs_milestones) do
    local time_str = ""
    if start_frame then
      time_str = string.format(" | %s", format_duration(rbs.frame - start_frame))
    end
    print(string.format("RBS %d: Frame %s%s", rbs.rbs_num, format_number(rbs.frame), time_str))
  end

  for _, loop in ipairs(dk3_loop_milestones) do
    local time_str = ""
    if start_frame then
      time_str = string.format(" | %s", format_duration(loop.frame - start_frame))
    end
    print(
      string.format(
        "Loop %d Complete: Frame %s%s",
        loop.loop_num,
        format_number(loop.frame),
        time_str
      )
    )
  end

  if start_frame and (game_over_vram_frame or end_frame) then
    local final_frame = game_over_vram_frame or end_frame
    local dur = final_frame - start_frame
    print(
      string.format(
        "Unofficial Full Game: %s | Frame %s - %s (%s frames)",
        format_duration(dur),
        format_number(start_frame),
        format_number(final_frame),
        format_number(dur)
      )
    )
  end
end

-- ============================================================================
-- MAIN FRAME LOOP - PLATFORMER GAMES (DK/DKJR/CK)
-- ============================================================================
local function on_frame_platformer()
  frame_count = read_frame_number()

  local config = get_config()

  -- Read current state (don't read score every frame, only when needed)
  local game_mode = read_byte(config.addresses.game_mode)
  local screen_type = read_byte(config.addresses.screen_type)
  local level = read_byte(config.addresses.level)
  local lives = read_byte(config.addresses.lives)

  -- DEATH SCORE SETTLEMENT: Record deferred death when leaving DEAD mode
  -- Mirrors DK3 settlement at on_frame_dkong3() and stop callback in 11_init.lua
  -- Score may update 1+ frames after mode changes to DEAD, so we wait
  -- for the score to settle before recording the death entry
  if death_pending and prev_game_mode == config.modes.dead and game_mode ~= config.modes.dead then
    local current_score = read_score_with_rollover_check()
    death_count = death_count + 1
    local score_earned = current_score - stage_start_score

    total_death_points = total_death_points + score_earned

    record_stage(
      death_pending_screen_type,
      death_pending_level,
      death_pending_position,
      current_screen_num,
      score_earned,
      current_score,
      true,
      death_count,
      lives,
      death_pending_bonus
    )

    last_stage_was_completed = false
    stage_start_score = current_score
    prev_score = current_score
    death_pending = false
    death_pending_screen_type = 0
    death_pending_level = 0
    death_pending_position = 0
    death_pending_bonus = 0
  end

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
        print(string.format("  [Timing] Start button: Frame %s", format_number(start_frame)))
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

  -- SCORE MILESTONE TRACKING
  if gameplay_started then
    local current_score = read_score_with_rollover_check()
    while current_score >= next_score_milestone do
      table.insert(score_milestones, {
        score = next_score_milestone,
        frame = frame_count,
        stage = get_stage_name(prev_level, level_position[prev_level] or 0),
        screen_num = current_screen_num,
        bonus_timer = read_bonus_timer(),
        during_gameplay = (game_mode == config.modes.gameplay),
      })
      local ms_time_str = ""
      if start_frame then
        ms_time_str = string.format(" - %s", format_duration(frame_count - start_frame))
      end
      print(
        string.format(
          "  *** %s Milestone (Frame %s%s) ***",
          format_number(next_score_milestone),
          format_number(frame_count),
          ms_time_str
        )
      )
      next_score_milestone = next_score_milestone + 100000
    end
  end

  -- SPEEDRUN START: First position change (memory leads visual by 1 frame)
  if game_mode == config.modes.gameplay and not speedrun_start_frame then
    local px = read_byte(config.addresses.player_x)
    local py = read_byte(config.addresses.player_y)
    if not spawn_x then
      -- First gameplay frame: capture spawn position
      spawn_x = px
      spawn_y = py
    elseif px ~= spawn_x or py ~= spawn_y then
      speedrun_start_frame = frame_count + 1
      print(
        string.format("  [Timing] Speedrun start: Frame %s", format_number(speedrun_start_frame))
      )
    end
  end

  -- SPEEDRUN "START" END: Rivet/key clear on start level (all clear = count reaches 0)
  -- Phase 1: Wait for gameplay (0x0C) on the clear screen to start checking
  -- Phase 2: Once gameplay seen, check for rivet=0 (mode may have already left gameplay)
  if
    gameplay_started
    and not speedrun_end_frame
    and level == config.start_level
    and screen_type == config.clear_screen_type
  then
    if game_mode == config.modes.gameplay then
      clear_screen_gameplay_seen = true
    end
    if clear_screen_gameplay_seen then
      local rivet_count = read_byte(config.addresses.rivet_key_count)
      if rivet_count == 0 then
        speedrun_end_frame = frame_count
        local sr_dur = speedrun_end_frame - speedrun_start_frame
        print(
          string.format(
            "  [Timing] Start Speedrun End: Frame %s (%s frames - %s)",
            format_number(speedrun_end_frame),
            format_number(sr_dur),
            format_duration(sr_dur)
          )
        )
      end
    end
  end

  -- STANDARD "START" END DETECTION (VRAM-based, platformer only)
  -- Captures the frame when the on-screen level indicator changes to start_level + 1
  -- Uses VRAM tile (not internal level byte) for visual timing consistency
  if not start_phase_end_frame and gameplay_started then
    local vram_tile = read_byte(config.addresses.level_display_vram)
    if vram_tile == config.start_level + 1 then
      start_phase_end_frame = frame_count
      local std_dur = start_phase_end_frame - start_frame
      print(
        string.format(
          "  [Timing] Standard Start End: Frame %s (%s frames - %s)",
          format_number(start_phase_end_frame),
          format_number(std_dur),
          format_duration(std_dur)
        )
      )
    end
  end

  -- KILLSCREEN DETECTION: 4-address state machine (DK/DKJR/CK)
  -- Fires when bonus timer runout reaches final state with player alive and grounded
  -- Visual death occurs 3 frames after internal trigger
  if
    game_mode == config.modes.gameplay
    and not killscreen_frame
    and level == config.killscreen_level
  then
    local ks_flag = read_byte(config.addresses.bonus_timer_flag)
    local ks_secondary = read_byte(config.addresses.bonus_timer_secondary)
    local ks_player = read_byte(config.addresses.player_status)
    local ks_jump = read_byte(config.addresses.jump_status)
    if ks_flag == 0x03 and ks_secondary == 0x00 and ks_player == 0x01 and ks_jump ~= 0x01 then
      killscreen_frame = frame_count + 3
      local ks_dur = killscreen_frame - speedrun_start_frame
      print(
        string.format(
          "  [Timing] Killscreen Speedrun End: Frame %s (%s frames - %s)",
          format_number(killscreen_frame),
          format_number(ks_dur),
          format_duration(ks_dur)
        )
      )
    end
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

    if not first_gameplay_seen or last_stage_was_completed then
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
    first_gameplay_seen = true
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
    local current_position = level_position[completed_level] or 1

    record_stage(
      completed_screen_type,
      completed_level,
      current_position,
      current_screen_num,
      score_earned,
      current_score,
      false,
      nil,
      lives,
      nil
    )

    -- Add to level score (only for completed stages, not deaths)
    level_score_accumulated = level_score_accumulated + score_earned

    last_stage_was_completed = true
    stage_completed_mode = nil
    prev_score = current_score
  end

  -- DEATH DETECTION: Flag death for deferred recording
  -- Actual recording happens when leaving DEAD mode (score settlement)
  if game_mode == config.modes.dead and prev_game_mode == config.modes.gameplay then
    death_pending = true
    death_pending_screen_type = screen_type
    death_pending_level = level
    death_pending_position = level_position[level]
    death_pending_bonus = read_bonus_timer()
  end

  -- KNOWN EDGE CASE: Simultaneous death + stage completion (platformer)
  -- If the player dies on the exact frame a stage completes, both stage_completed_mode
  -- and death_pending will be set. The completion records first (transition detection),
  -- then death settles when leaving dead mode. This can cause death points to include
  -- the stage bonus, and the death may be attributed to the next stage. This is the
  -- "extra man" bug: lives increment then immediately decrement, death stage is not
  -- replayed. Extremely rare; needs testing.

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

    -- Capture VRAM-based game over timing
    if not game_over_vram_frame then
      local vram_tile = read_byte(config.addresses.game_over_vram)
      if vram_tile == 0x17 then
        game_over_vram_frame = frame_count
        if start_frame then
          local go_dur = game_over_vram_frame - start_frame
          print(
            string.format(
              "  [Timing] Standard Game End: Frame %s (%s frames - %s)",
              format_number(game_over_vram_frame),
              format_number(go_dur),
              format_duration(go_dur)
            )
          )
        end
      end
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
  frame_count = read_frame_number()

  local config = get_config()
  local game_mode = read_byte(config.addresses.game_mode)
  local dead_status = read_byte(config.addresses.dead)
  local screen_type = read_byte(config.addresses.screen_type)
  local level = read_byte(config.addresses.level)
  local lives = read_byte(config.addresses.lives)

  -- DK3 DEATH SCORE SETTLEMENT: Record deferred death when score settles
  -- Mirrors platformer settlement at on_frame_platformer() and stop callback in 11_init.lua
  if dk3_death_pending then
    local settle_now = false

    -- Normal settlement: dead_status returns to alive
    if
      dead_status == config.death_status.alive
      and dk3_prev_dead_status == config.death_status.dead
    then
      settle_now = true
    end

    -- Game over while death pending (dead_status may not return to alive)
    if
      (game_mode == config.modes.game_over_1 or game_mode == config.modes.game_over_2)
      and dk3_prev_game_mode ~= config.modes.game_over_1
      and dk3_prev_game_mode ~= config.modes.game_over_2
    then
      settle_now = true
    end

    if settle_now then
      local current_score = read_score_with_rollover_check()
      death_count = death_count + 1
      local score_earned = current_score - dk3_death_pending_start_score

      total_death_points = total_death_points + score_earned

      local death_board_num = dk3_actual_board_num + 1

      record_board_dk3(
        death_board_num,
        dk3_death_pending_level,
        current_screen_num,
        score_earned,
        current_score,
        true,
        death_count,
        dk3_death_pending_lives_at_death,
        dk3_death_pending_screen_type,
        dk3_death_pending_bonus
      )

      -- Record life performance
      local boards_completed = dk3_actual_board_num - dk3_current_life_start_board + 1
      if boards_completed < 0 then
        boards_completed = 0
      end

      table.insert(dk3_life_tracking, {
        life_num = death_count,
        start_score = dk3_current_life_start_score,
        end_score = current_score,
        start_board = dk3_current_life_start_board,
        boards_completed = boards_completed,
      })

      dk3_current_life_start_score = current_score
      dk3_current_life_start_board = death_board_num

      stage_start_score = current_score
      prev_score = current_score
      dk3_death_pending = false
      dk3_death_pending_screen_type = 0
      dk3_death_pending_level = 0
      dk3_death_pending_lives_at_death = 0
      dk3_death_pending_bonus = 0
      dk3_death_pending_start_score = 0
    end
  end

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
        print(string.format("  [Timing] Start button: Frame %s", format_number(start_frame)))
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

  -- SCORE MILESTONE TRACKING
  if gameplay_started then
    local current_score = read_score_with_rollover_check()
    while current_score >= next_score_milestone do
      table.insert(score_milestones, {
        score = next_score_milestone,
        frame = frame_count,
        board = dk3_actual_board_num + 1,
        screen_num = current_screen_num,
        bonus_timer = read_bonus_timer(),
        during_gameplay = (game_mode == config.modes.gameplay),
      })
      local ms_time_str = ""
      if start_frame then
        ms_time_str = string.format(" - %s", format_duration(frame_count - start_frame))
      end
      print(
        string.format(
          "  *** %s Milestone (Frame %s%s) ***",
          format_number(next_score_milestone),
          format_number(frame_count),
          ms_time_str
        )
      )
      next_score_milestone = next_score_milestone + 100000
    end
  end

  -- SPEEDRUN START: Deferred for DK3 (no established speedrun category)
  -- Requires button press detection in addition to position change

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
      dk3_completed_screen_type,
      nil
    )

    -- After recording board 256, 512, 768, etc., increment loop counter and set new loop_start_score
    if dk3_actual_board_num % config.loop_size == 0 then
      dk3_current_loop = dk3_current_loop + 1
      dk3_loop_start_score = current_score
    end

    dk3_stage_completed = false
    prev_score = current_score
  end

  -- DEATH DETECTION: Flag death for deferred recording
  if
    dead_status == config.death_status.dead
    and dk3_prev_dead_status == config.death_status.alive
  then
    dk3_death_pending = true
    dk3_death_pending_screen_type = screen_type
    dk3_death_pending_level = level
    dk3_death_pending_start_score = stage_start_score
    -- Capture lives at detection time (haven't decremented in memory yet)
    dk3_death_pending_lives_at_death = lives > 0 and (lives - 1) or 0
    dk3_death_pending_bonus = read_bonus_timer()
  end

  -- KNOWN EDGE CASE: Simultaneous death + stage completion (DK3)
  -- If the player dies on the exact frame a stage completes, both dk3_stage_completed
  -- and dk3_death_pending will be set. The completion records first (transition_1),
  -- then death settles when dead_status returns to alive. This can cause death points
  -- to include the stage bonus, and dk3_actual_board_num may have already incremented.
  -- DK3 does NOT replay the death stage - the next board starts normally with lives
  -- decremented. Extremely rare; needs testing.

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

    -- Capture VRAM-based game over timing
    if not game_over_vram_frame then
      local vram_tile = read_byte(config.addresses.game_over_vram)
      if vram_tile == 0x17 then
        game_over_vram_frame = frame_count
        if start_frame then
          local go_dur = game_over_vram_frame - start_frame
          print(
            string.format(
              "  [Timing] Standard Game End: Frame %s (%s frames - %s)",
              format_number(game_over_vram_frame),
              format_number(go_dur),
              format_duration(go_dur)
            )
          )
        end
      end
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
  -- Settle any pending death before processing session end
  -- Platformer: mirrors frame loop settlement in on_frame_platformer() in 10_frame_loops.lua ~line 15
  if death_pending then
    local current_score = read_score_with_rollover_check()
    death_count = death_count + 1
    local score_earned = current_score - stage_start_score
    total_death_points = total_death_points + score_earned
    local stop_config = get_config()

    record_stage(
      death_pending_screen_type,
      death_pending_level,
      death_pending_position,
      current_screen_num,
      score_earned,
      current_score,
      true,
      death_count,
      read_byte(stop_config.addresses.lives),
      death_pending_bonus
    )

    last_stage_was_completed = false
    stage_start_score = current_score
    prev_score = current_score
    death_pending = false
    death_pending_screen_type = 0
    death_pending_level = 0
    death_pending_position = 0
    death_pending_bonus = 0
  end

  -- DK3: mirrors frame loop settlement in on_frame_dkong3() in 10_frame_loops.lua ~line 373
  if dk3_death_pending then
    local current_score = read_score_with_rollover_check()
    death_count = death_count + 1
    local score_earned = current_score - dk3_death_pending_start_score
    total_death_points = total_death_points + score_earned

    local death_board_num = dk3_actual_board_num + 1

    record_board_dk3(
      death_board_num,
      dk3_death_pending_level,
      current_screen_num,
      score_earned,
      current_score,
      true,
      death_count,
      dk3_death_pending_lives_at_death,
      dk3_death_pending_screen_type,
      dk3_death_pending_bonus
    )

    local boards_completed = dk3_actual_board_num - dk3_current_life_start_board + 1
    if boards_completed < 0 then
      boards_completed = 0
    end

    table.insert(dk3_life_tracking, {
      life_num = death_count,
      start_score = dk3_current_life_start_score,
      end_score = current_score,
      start_board = dk3_current_life_start_board,
      boards_completed = boards_completed,
    })

    dk3_current_life_start_score = current_score
    dk3_current_life_start_board = death_board_num
    stage_start_score = current_score
    prev_score = current_score
    dk3_death_pending = false
    dk3_death_pending_screen_type = 0
    dk3_death_pending_level = 0
    dk3_death_pending_lives_at_death = 0
    dk3_death_pending_bonus = 0
    dk3_death_pending_start_score = 0
  end

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
