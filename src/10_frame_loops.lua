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
