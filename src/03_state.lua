-- ============================================================================
-- STATE TRACKING
-- ============================================================================

-- PERMANENT STATE — not reset between sessions
-- frame_count: Raw MAME frame counter, overwritten from read_frame_number() every frame.
-- Session timing uses start_frame/end_frame deltas, not frame_count resets.
local frame_count = 0

-- game_variation: DIP switch configuration, does not change mid-INP.
local game_variation = nil -- For DK3 variation detection

-- INP playback end detection — one INP, one playback, never reset.
local inp_playback_active = false -- Set true at startup if INP playback detected
local inp_playback_ended = false -- Set true when INP playback option goes empty
local inp_end_frame = nil -- Frame number when INP end was detected

-- Multi-session tracking — not reset between sessions
local session_count = 1

-- ============================================================================
-- PER-SESSION STATE — reset between sessions via reset_session_state()
-- ============================================================================

local function create_session_state()
  return {
    -- DK/DKJR/CK state
    prev_game_mode = 0,
    prev_screen_type = 0,
    prev_level = 0,
    prev_score = 0, -- Adjusted score from last time we checked
    prev_raw_score = 0, -- Raw score for rollover detection
    stage_start_score = 0,
    level_score_accumulated = 0,
    current_level_being_played = 0,
    stage_data = {},
    current_screen_num = 0,
    level_position = {},
    stage_completed_mode = nil,
    completed_screen_type = 0,
    completed_level = 0,
    last_stage_was_completed = false,
    first_gameplay_seen = false,
    death_count = 0,
    total_death_points = 0, -- Accumulates points earned on death attempts
    start_score_for_pace = 0, -- Sum of stage scores during start phase (excludes deaths)
    start_score_total = 0, -- Total score after start phase (for display)
    start_phase_death_points = 0, -- Sum of death points during start phase
    start_phase_deaths = 0, -- Count of deaths during start phase
    score_offset = 0, -- Tracks million-point rollovers
    game_over_processed = false, -- Prevents double-printing at game over

    -- Deferred death recording (score may settle after mode changes to DEAD)
    -- Platformer game_mode transitions directly to DEAD, so settlement fires
    -- on the same frame as board start (execution order protects stage_start_score).
    death_pending = false,
    death_pending_screen_type = 0,
    death_pending_level = 0,
    death_pending_position = 0,
    death_pending_bonus = 0,

    -- Best/Worst stage and level tracking (platformer games only)
    -- Indexed by screen type (1-4) to match screen_sum/screen_count pattern
    screen_scores = {
      [1] = {}, -- DK/CK: Barrels, DKJR: Springs
      [2] = {}, -- DK/CK: Pies, DKJR: Jungles
      [3] = {}, -- DK/CK: Springs, DKJR: Chains
      [4] = {}, -- DK/CK: Rivets, DKJR: Hideouts
    },
    level_scores = {}, -- {score, label, level}

    -- Pace and averages tracking (DK/DKJR/CK only)
    screen_sum = { 0, 0, 0, 0 }, -- Sum for screen types 1-4
    screen_count = { 0, 0, 0, 0 }, -- Count for screen types 1-4
    level_sum = 0,
    level_count = 0,
    can_calculate_pace = false, -- Set to true after Level 5 is complete (Level 4 for DKJR)
    last_pace = nil, -- Stores pace from last completed stage
    last_pace_22_4 = nil, -- Stores 22-4 pace from last completed stage (ckongpt2 only)

    -- DK3 state
    dk3_prev_game_mode = 0,
    dk3_prev_dead_status = 0,
    dk3_prev_screen_type = 0,
    dk3_prev_level = 0,
    dk3_actual_board_num = 0,
    dk3_rbs_count = 0,
    dk3_current_loop = 1,
    dk3_loop_start_score = 0,
    dk3_max_diff_reached = false,
    dk3_max_diff_count = 0,
    dk3_max_diff_milestones = {}, -- Array of {count, total_score, max_diff_score, frame, lives}
    dk3_rbs_milestones = {},
    dk3_loop_milestones = {},
    dk3_stage_completed = false,
    dk3_completed_screen_type = 0,
    dk3_completed_level = 0,
    dk3_screen_sum = { 0, 0, 0 }, -- Blue, Grey, Gold
    dk3_screen_count = { 0, 0, 0 },

    -- DK3 life tracking for extended statistics
    dk3_life_tracking = {}, -- Array of {life_num, start_score, end_score, start_board, boards_completed}
    dk3_current_life_start_score = 0,
    dk3_current_life_start_board = 1, -- Game starts on board 1

    -- Platformer life tracking
    life_tracking = {}, -- Array of {life_num, start_score, end_score, start_stage_index, stages_completed}
    current_life_start_score = 0,
    current_life_start_stage_count = 0,
    stages_completed_count = 0,

    -- Deferred death recording for DK3
    -- DK3 uses a separate dead_status address (0x6101) instead of a game_mode value,
    -- so game_mode can re-enter gameplay before dead_status clears.
    -- All state must be captured at detection time to avoid clobbering by the board start block.
    dk3_death_pending = false,
    dk3_death_pending_screen_type = 0,
    dk3_death_pending_level = 0,
    dk3_death_pending_lives_at_death = 0,
    dk3_death_pending_bonus = 0,
    dk3_death_pending_start_score = 0,

    -- Gameplay duration tracking
    -- start_button_pressed = false, -- Edge detected: start button was pressed
    -- coin_inserted = false, -- Edge detected: coin was inserted
    gameplay_started = false, -- Confirmed: actual gameplay has begun
    start_frame = nil, -- Frame number when gameplay started
    pending_start_frame = nil,
    end_frame = nil, -- Frame number when gameplay ended
    prev_start_state = false, -- Previous frame's start button state (for edge detection)
    -- prev_coin_state = false, -- Previous frame's coin button state (for edge detection)

    -- Recorded Lives tracking (all games)
    starting_lives = nil, -- Lives count at first gameplay frame
    earned_lives = 0, -- Accumulated upward increments (bonus lives)
    prev_lives_for_earn = nil, -- Previous frame's lives for delta detection

    -- Score milestones (all games)
    score_milestones = {}, -- {score, frame} entries at every 100K
    next_score_milestone = 100000,

    -- Standard timing (VRAM-based)
    start_phase_end_frame = nil, -- VRAM level digit change
    game_over_vram_frame = nil, -- VRAM "G" tile appearance

    -- Speedrun timing (DK/DKJR/CK only)
    speedrun_start_frame = nil, -- First position change + 1
    speedrun_end_frame = nil, -- Frame when rivet/key count reaches 0 on start level clear screen
    spawn_x = nil, -- Spawn position for movement detection
    spawn_y = nil,
    clear_screen_gameplay_seen = false, -- True once gameplay mode seen on start level clear screen
    killscreen_frame = nil, -- Killscreen trigger + 3 (visual death frame)
  }
end

local s = create_session_state()

-- Reset session state in-place (preserves all references to s)
local function reset_session_state()
  local fresh = create_session_state()
  for k in pairs(s) do
    s[k] = nil
  end
  for k, v in pairs(fresh) do
    s[k] = v
  end
end
