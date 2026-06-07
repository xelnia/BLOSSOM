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
      -- TIMING & ANALYSIS ADDRESSES
      bonus_timer = 0x62B1,
      player_x = 0x6203,
      player_y = 0x6205,
      rivet_key_count = 0x6290,
      level_display_vram = 0x74A3, -- Level ones digit tile in VRAM
      level_display_tens_vram = 0x74C3, -- Level tens digit tile in VRAM
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
    -- BONUS TIMER FORMAT
    bonus_timer_bcd = false,
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
      -- TIMING & ANALYSIS ADDRESSES
      bonus_timer = 0x62B1,
      player_x = 0x6203,
      player_y = 0x6205,
      rivet_key_count = 0x6290,
      level_display_vram = 0x7484, -- Level digit tile in VRAM (single digit, no tens)
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
    -- BONUS TIMER FORMAT
    bonus_timer_bcd = false,
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
      -- TIMING & ANALYSIS ADDRESSES
      bonus_timer = 0x68C2,
      player_x = 0x6107,
      player_y = 0x6109,
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
