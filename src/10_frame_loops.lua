-- ============================================================================
-- MAIN FRAME LOOP - PLATFORMER GAMES (DK/DKJR/CK)
-- ============================================================================
local function on_frame_platformer()
  frame_count = read_frame_number() + 1

  local config = get_config()

  -- Read current state (don't read score every frame, only when needed)
  local game_mode = read_byte(config.addresses.game_mode)
  local screen_type = read_byte(config.addresses.screen_type)
  local level = read_byte(config.addresses.level)
  local lives = read_byte(config.addresses.lives)

  -- DEATH SCORE SETTLEMENT: Record deferred death when leaving DEAD mode
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
      lives
    )

    last_stage_was_completed = false
    stage_start_score = current_score
    prev_score = current_score
    death_pending = false
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

  -- DEATH DETECTION: Flag death for deferred recording
  -- Actual recording happens when leaving DEAD mode (score settlement)
  if game_mode == config.modes.dead and prev_game_mode == config.modes.gameplay then
    death_pending = true
    death_pending_screen_type = screen_type
    death_pending_level = level
    death_pending_position = level_position[level]
    death_pending_bonus = read_bonus_timer()
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
  frame_count = read_frame_number() + 1

  local config = get_config()
  local game_mode = read_byte(config.addresses.game_mode)
  local dead_status = read_byte(config.addresses.dead)
  local screen_type = read_byte(config.addresses.screen_type)
  local level = read_byte(config.addresses.level)
  local lives = read_byte(config.addresses.lives)

  -- DK3 DEATH SCORE SETTLEMENT: Record deferred death when score settles
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
      local score_earned = current_score - stage_start_score

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
        dk3_death_pending_screen_type
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
    -- Capture lives at detection time (haven't decremented in memory yet)
    dk3_death_pending_lives_at_death = lives > 0 and (lives - 1) or 0
    dk3_death_pending_bonus = read_bonus_timer()
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
