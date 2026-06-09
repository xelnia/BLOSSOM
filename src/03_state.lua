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

-- Deferred death recording (score may settle after mode changes to DEAD)
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
local dk3_max_diff_frame = nil -- Frame when max difficulty first reached
local dk3_rbs_milestones = {}
local dk3_loop_milestones = {}
local dk3_million_frame = nil -- Frame when score first reaches/passes 1,000,000
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
local dk3_death_pending = false
local dk3_death_pending_screen_type = 0
local dk3_death_pending_level = 0
local dk3_death_pending_lives_at_death = 0
local dk3_death_pending_bonus = 0

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
local speedrun_end_frame = nil -- Rivet/key clear - 1 (start) or killscreen + 2 (full)
local spawn_x = nil -- Spawn position for movement detection
local spawn_y = nil
local clear_screen_gameplay_seen = false -- True once gameplay mode seen on start level clear screen
local killscreen_frame = nil -- Killscreen trigger + 3 (visual death frame)
