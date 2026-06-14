-- ============================================================================
-- MAIN FRAME LOOP - PLATFORMER GAMES (DK/DKJR/CK)
-- ============================================================================
local function on_frame_platformer()
  frame_count = read_frame_number()

  -- Detect INP playback end (prevents phantom events after recording ends)
  if
    inp_playback_active
    and not inp_playback_ended
    and mame_options.entries["playback"]:value() == ""
  then
    inp_playback_ended = true
    inp_end_frame = frame_count + start_frame_offset
    finalize_session("SESSION ENDED")
    return
  end

  if inp_playback_ended then
    return
  end

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
  if
    s.death_pending
    and s.prev_game_mode == config.modes.dead
    and game_mode ~= config.modes.dead
  then
    local current_score = read_score_with_rollover_check()
    s.death_count = s.death_count + 1
    local score_earned = current_score - s.stage_start_score

    s.total_death_points = s.total_death_points + score_earned

    record_stage(
      s.death_pending_screen_type,
      s.death_pending_level,
      s.death_pending_position,
      s.current_screen_num,
      score_earned,
      current_score,
      true,
      s.death_count,
      lives,
      s.death_pending_bonus
    )

    -- Record life performance
    local stages_completed = s.stages_completed_count - s.current_life_start_stage_count
    if stages_completed < 0 then
      stages_completed = 0
    end

    table.insert(s.life_tracking, {
      life_num = s.death_count,
      start_score = s.current_life_start_score,
      end_score = current_score,
      start_stage_index = s.current_life_start_stage_count,
      stages_completed = stages_completed,
    })

    s.current_life_start_score = current_score
    s.current_life_start_stage_count = s.stages_completed_count

    s.last_stage_was_completed = false
    s.stage_start_score = current_score
    s.prev_score = current_score
    s.death_pending = false
    s.death_pending_screen_type = 0
    s.death_pending_level = 0
    s.death_pending_position = 0
    s.death_pending_bonus = 0
  end

  -- START BUTTON EDGE DETECTION: Capture frame-accurate press timing
  -- Buffers the frame until $6005 confirms a valid game start
  if not s.start_frame then
    local raw = read_byte(config.addresses.input_start_coin)
    local bit_val = (raw >> config.start_button_bit) & 1
    local pressed
    if config.input_active_high then
      pressed = (bit_val == 1)
    else
      pressed = (bit_val == 0)
    end
    if pressed and not s.prev_start_state then
      s.pending_start_frame = frame_count + start_frame_offset
    end
    s.prev_start_state = pressed
  end

  -- GAMEPLAY DETECTION: $6005 entering "playing" confirms credit + start sequence
  -- Promotes buffered start frame; falls back to current frame for pre-banked credits
  if not s.gameplay_started then
    local game_active = read_byte(config.addresses.game_active)
    if game_active == config.game_active_playing then
      s.gameplay_started = true
      if not s.start_frame then
        if s.pending_start_frame then
          s.start_frame = s.pending_start_frame
        else
          s.start_frame = frame_count + start_frame_offset
        end
        local msg = string.format("  [Timing] Start button: Frame %s", format_number(s.start_frame))
        if session_banner_pending then
          session_pending_timing_msg = msg
        else
          print(msg)
        end
      end
    end
  end

  -- SCORE MILESTONE TRACKING
  if s.gameplay_started then
    local current_score = read_score_with_rollover_check()
    while current_score >= s.next_score_milestone do
      local milestone_frame = frame_count + 1
      table.insert(s.score_milestones, {
        score = s.next_score_milestone,
        frame = milestone_frame,
        stage = get_stage_name(s.prev_level, s.level_position[s.prev_level] or 0),
        screen_num = s.current_screen_num,
        bonus_timer = read_bonus_timer(),
        lives = read_byte(config.addresses.lives),
        during_gameplay = (game_mode == config.modes.gameplay),
      })
      local ms_time_str = ""
      if s.start_frame then
        ms_time_str = string.format(" - %s", format_duration(milestone_frame - s.start_frame))
      end
      print(
        string.format(
          "  *** %s Milestone (Frame %s%s | Lives: %d) ***",
          format_number(s.next_score_milestone),
          format_number(milestone_frame),
          ms_time_str,
          read_byte(config.addresses.lives)
        )
      )
      s.next_score_milestone = s.next_score_milestone + 100000
    end
  end

  -- RECORDED LIVES TRACKING
  if s.gameplay_started and game_mode == config.modes.gameplay then
    local current_lives = read_byte(config.addresses.lives)
    if not s.starting_lives then
      s.starting_lives = current_lives
      s.prev_lives_for_earn = current_lives
    end
    if s.prev_lives_for_earn and current_lives > s.prev_lives_for_earn then
      s.earned_lives = s.earned_lives + (current_lives - s.prev_lives_for_earn)
    end
    s.prev_lives_for_earn = current_lives
  end

  -- SPEEDRUN START: First position change (memory leads visual by 1 frame)
  if game_mode == config.modes.gameplay and not s.speedrun_start_frame then
    local px = read_byte(config.addresses.player_x)
    local py = read_byte(config.addresses.player_y)
    if not s.spawn_x then
      -- First gameplay frame: capture spawn position
      s.spawn_x = px
      s.spawn_y = py
    elseif px ~= s.spawn_x or py ~= s.spawn_y then
      s.speedrun_start_frame = frame_count + 1
      print(
        string.format("  [Timing] Speedrun start: Frame %s", format_number(s.speedrun_start_frame))
      )
    end
  end

  -- SPEEDRUN "START" END: Rivet/key clear on start level (all clear = count reaches 0)
  -- Phase 1: Wait for gameplay (0x0C) on the clear screen to start checking
  -- Phase 2: Once gameplay seen, check for rivet=0 (mode may have already left gameplay)
  if
    s.gameplay_started
    and not s.speedrun_end_frame
    and level == config.start_level
    and screen_type == config.clear_screen_type
  then
    if game_mode == config.modes.gameplay then
      s.clear_screen_gameplay_seen = true
    end
    if s.clear_screen_gameplay_seen then
      local rivet_count = read_byte(config.addresses.rivet_key_count)
      if rivet_count == 0 then
        s.speedrun_end_frame = frame_count
        local sr_dur = s.speedrun_end_frame - s.speedrun_start_frame
        print(
          string.format(
            "  [Timing] Start Speedrun End: Frame %s (%s frames - %s)",
            format_number(s.speedrun_end_frame),
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
  if not s.start_phase_end_frame and s.gameplay_started then
    local vram_tile = read_byte(config.addresses.level_display_vram)
    if vram_tile == config.start_level + 1 then
      s.start_phase_end_frame = frame_count
      local std_dur = s.start_phase_end_frame - s.start_frame
      print(
        string.format(
          "  [Timing] Standard Start End: Frame %s (%s frames - %s)",
          format_number(s.start_phase_end_frame),
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
    and not s.killscreen_frame
    and level == config.killscreen_level
  then
    local ks_flag = read_byte(config.addresses.bonus_timer_flag)
    local ks_secondary = read_byte(config.addresses.bonus_timer_secondary)
    local ks_player = read_byte(config.addresses.player_status)
    local ks_jump = read_byte(config.addresses.jump_status)
    if ks_flag == 0x03 and ks_secondary == 0x00 and ks_player == 0x01 and ks_jump ~= 0x01 then
      s.killscreen_frame = frame_count + 3
      local ks_dur = s.killscreen_frame - s.speedrun_start_frame
      print(
        string.format(
          "  [Timing] Killscreen Speedrun End: Frame %s (%s frames - %s)",
          format_number(s.killscreen_frame),
          format_number(ks_dur),
          format_duration(ks_dur)
        )
      )
    end
  end

  -- Initialize stage_start_score on first gameplay
  if s.prev_game_mode ~= config.modes.gameplay and game_mode == config.modes.gameplay then
    local current_score = read_score_with_rollover_check()

    -- Check if we're starting a new level
    if level ~= s.current_level_being_played and s.current_level_being_played > 0 then
      -- Level changed - record total for previous level (using accumulated score, not delta)
      record_level_total(s.current_level_being_played, s.level_score_accumulated, current_score)

      -- Start tracking new level
      s.level_score_accumulated = 0 -- Reset for new level
      s.current_level_being_played = level
    elseif s.current_level_being_played == 0 then
      -- First level of the game
      s.level_score_accumulated = 0
      s.current_level_being_played = level
    end

    if not s.first_gameplay_seen or s.last_stage_was_completed then
      -- This is a new unique screen (not a retry after death)
      s.current_screen_num = s.current_screen_num + 1
      s.last_stage_was_completed = false

      -- Initialize position tracking for this level if needed
      if not s.level_position[level] then
        s.level_position[level] = 0
      end

      -- Increment position for this level
      s.level_position[level] = s.level_position[level] + 1
    end

    s.stage_start_score = current_score
    s.stage_completed_mode = nil
    s.prev_score = current_score
    s.first_gameplay_seen = true
  end

  -- Track screen/level during gameplay
  if game_mode == config.modes.gameplay then
    s.prev_screen_type = screen_type
    s.prev_level = level
  end

  -- STAGE COMPLETION: Detect when leaving gameplay (except death)
  if
    s.prev_game_mode == config.modes.gameplay
    and game_mode ~= config.modes.gameplay
    and game_mode ~= config.modes.dead
  then
    if s.stage_completed_mode == nil then
      s.stage_completed_mode = game_mode
      s.completed_screen_type = s.prev_screen_type
      s.completed_level = s.prev_level
    end
  end

  -- RECORD STAGE: Wait for transition screen after completion
  if game_mode == config.modes.transition and s.stage_completed_mode ~= nil then
    local current_score = read_score_with_rollover_check()
    local score_earned = current_score - s.stage_start_score
    local current_position = s.level_position[s.completed_level] or 1

    record_stage(
      s.completed_screen_type,
      s.completed_level,
      current_position,
      s.current_screen_num,
      score_earned,
      current_score,
      false,
      nil,
      lives,
      nil
    )

    -- Add to level score (only for completed stages, not deaths)
    s.level_score_accumulated = s.level_score_accumulated + score_earned

    s.last_stage_was_completed = true
    s.stage_completed_mode = nil
    s.prev_score = current_score
  end

  -- DEATH DETECTION: Flag death for deferred recording
  -- Actual recording happens when leaving DEAD mode (score settlement)
  if game_mode == config.modes.dead and s.prev_game_mode == config.modes.gameplay then
    s.death_pending = true
    s.death_pending_screen_type = screen_type
    s.death_pending_level = level
    s.death_pending_position = s.level_position[level]
    s.death_pending_bonus = read_bonus_timer()
    -- Reset clear screen tracking to prevent false speedrun end trigger on reload
    s.clear_screen_gameplay_seen = false
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
    and s.prev_game_mode ~= config.modes.game_over
    and not s.game_over_processed
  then
    finalize_session("GAME OVER")
  end

  -- MULTI-SESSION DETECTION: After game over, watch for $6005 to leave "playing"
  -- Reset prepares for a potential next game; $6005 detection handles the rest
  if s.game_over_processed then
    local game_active = read_byte(config.addresses.game_active)
    if game_active ~= config.game_active_playing then
      session_count = session_count + 1
      CSV_FILE, JSON_FILE, TEXT_FILE = get_output_filenames(session_count)
      reset_session_state()
      session_banner_pending = true
    end
  end

  -- Print deferred session banner once gameplay is confirmed
  if session_banner_pending and s.gameplay_started then
    print(string.format("\n=== SESSION %d ===\n", session_count))
    print("Tracking gameplay...\n")
    if session_pending_timing_msg then
      print(session_pending_timing_msg)
      session_pending_timing_msg = nil
    end
    session_banner_pending = false
  end

  -- Update previous state
  s.prev_game_mode = game_mode
  s.prev_screen_type = screen_type
  s.prev_level = level
end

-- ============================================================================
-- MAIN FRAME LOOP - DONKEY KONG 3
-- ============================================================================
local function on_frame_dkong3()
  frame_count = read_frame_number()

  -- Detect INP playback end (prevents phantom events after recording ends)
  if
    inp_playback_active
    and not inp_playback_ended
    and mame_options.entries["playback"]:value() == ""
  then
    inp_playback_ended = true
    inp_end_frame = frame_count + start_frame_offset
    finalize_session("SESSION ENDED")
    return
  end

  if inp_playback_ended then
    return
  end

  local config = get_config()
  local game_mode = read_byte(config.addresses.game_mode)
  local dead_status = read_byte(config.addresses.dead)
  local screen_type = read_byte(config.addresses.screen_type)
  local level = read_byte(config.addresses.level)
  local lives = read_byte(config.addresses.lives)

  -- DK3 DEATH SCORE SETTLEMENT: Record deferred death when score settles
  -- Mirrors platformer settlement at on_frame_platformer() and stop callback in 11_init.lua
  if s.dk3_death_pending then
    local settle_now = false

    -- Normal settlement: dead_status returns to alive
    if
      dead_status == config.death_status.alive
      and s.dk3_prev_dead_status == config.death_status.dead
    then
      settle_now = true
    end

    -- Game over while death pending (dead_status may not return to alive)
    if
      (game_mode == config.modes.game_over_1 or game_mode == config.modes.game_over_2)
      and s.dk3_prev_game_mode ~= config.modes.game_over_1
      and s.dk3_prev_game_mode ~= config.modes.game_over_2
    then
      settle_now = true
    end

    if settle_now then
      local current_score = read_score_with_rollover_check()
      s.death_count = s.death_count + 1
      local score_earned = current_score - s.dk3_death_pending_start_score

      s.total_death_points = s.total_death_points + score_earned

      local death_board_num = s.dk3_actual_board_num + 1

      record_board_dk3(
        death_board_num,
        s.dk3_death_pending_level,
        s.current_screen_num,
        score_earned,
        current_score,
        true,
        s.death_count,
        s.dk3_death_pending_lives_at_death,
        s.dk3_death_pending_screen_type,
        s.dk3_death_pending_bonus
      )

      -- Record life performance
      local boards_completed = s.dk3_actual_board_num - s.dk3_current_life_start_board + 1
      if boards_completed < 0 then
        boards_completed = 0
      end

      table.insert(s.dk3_life_tracking, {
        life_num = s.death_count,
        start_score = s.dk3_current_life_start_score,
        end_score = current_score,
        start_board = s.dk3_current_life_start_board,
        boards_completed = boards_completed,
      })

      s.dk3_current_life_start_score = current_score
      s.dk3_current_life_start_board = death_board_num

      s.stage_start_score = current_score
      s.prev_score = current_score
      s.dk3_death_pending = false
      s.dk3_death_pending_screen_type = 0
      s.dk3_death_pending_level = 0
      s.dk3_death_pending_lives_at_death = 0
      s.dk3_death_pending_bonus = 0
      s.dk3_death_pending_start_score = 0
    end
  end

  -- START BUTTON EDGE DETECTION: Capture frame-accurate press timing
  -- Buffers the frame until $6005 confirms a valid game start
  if not s.start_frame then
    local raw = read_byte(config.addresses.input_start)
    local bit_val = (raw >> config.start_button_bit) & 1
    local pressed
    if config.input_active_high then
      pressed = (bit_val == 1)
    else
      pressed = (bit_val == 0)
    end
    if pressed and not s.prev_start_state then
      s.pending_start_frame = frame_count + start_frame_offset
    end
    s.prev_start_state = pressed
  end

  -- GAMEPLAY DETECTION: $6005 entering "playing" confirms credit + start sequence
  -- Promotes buffered start frame; falls back to current frame for pre-banked credits
  if not s.gameplay_started then
    local game_active = read_byte(config.addresses.game_active)
    if game_active == config.game_active_playing then
      s.gameplay_started = true
      if not s.start_frame then
        if s.pending_start_frame then
          s.start_frame = s.pending_start_frame
        else
          s.start_frame = frame_count + start_frame_offset
        end
        local msg = string.format("  [Timing] Start button: Frame %s", format_number(s.start_frame))
        if session_banner_pending then
          session_pending_timing_msg = msg
        else
          print(msg)
        end
      end
    end
  end

  -- SCORE MILESTONE TRACKING
  if s.gameplay_started then
    local current_score = read_score_with_rollover_check()
    while current_score >= s.next_score_milestone do
      local milestone_frame = frame_count + 1
      table.insert(s.score_milestones, {
        score = s.next_score_milestone,
        frame = milestone_frame,
        board = s.dk3_actual_board_num + 1,
        screen_num = s.current_screen_num,
        bonus_timer = read_bonus_timer(),
        lives = read_byte(config.addresses.lives),
        during_gameplay = (game_mode == config.modes.gameplay),
      })
      local ms_time_str = ""
      if s.start_frame then
        ms_time_str = string.format(" - %s", format_duration(milestone_frame - s.start_frame))
      end
      print(
        string.format(
          "  *** %s Milestone (Frame %s%s | Lives: %d) ***",
          format_number(s.next_score_milestone),
          format_number(milestone_frame),
          ms_time_str,
          read_byte(config.addresses.lives)
        )
      )
      s.next_score_milestone = s.next_score_milestone + 100000
    end
  end

  -- RECORDED LIVES TRACKING
  if s.gameplay_started and game_mode == config.modes.gameplay then
    local current_lives = read_byte(config.addresses.lives)
    if not s.starting_lives then
      s.starting_lives = current_lives
      s.prev_lives_for_earn = current_lives
    end
    if s.prev_lives_for_earn and current_lives > s.prev_lives_for_earn then
      s.earned_lives = s.earned_lives + (current_lives - s.prev_lives_for_earn)
    end
    s.prev_lives_for_earn = current_lives
  end

  -- SPEEDRUN START: Deferred for DK3 (no established speedrun category)
  -- Requires button press detection in addition to position change

  -- BOARD START: Entering gameplay
  if s.dk3_prev_game_mode ~= config.modes.gameplay and game_mode == config.modes.gameplay then
    local current_score = read_score_with_rollover_check()

    -- New screen starting
    s.current_screen_num = s.current_screen_num + 1
    s.stage_start_score = current_score
    s.dk3_stage_completed = false
    s.prev_score = current_score
  end

  -- Track current screen/level during gameplay
  if game_mode == config.modes.gameplay then
    s.dk3_prev_screen_type = screen_type
    s.dk3_prev_level = level
  end

  -- STAGE COMPLETION: Detect when bonus message appears (score finalized)
  if s.dk3_prev_game_mode == config.modes.bonus_calc and game_mode == config.modes.bonus_msg then
    s.dk3_stage_completed = true
    s.dk3_completed_screen_type = s.dk3_prev_screen_type
    s.dk3_completed_level = s.dk3_prev_level
  end

  -- RECORD STAGE: Wait for transition after bonus message
  if s.dk3_stage_completed and game_mode == config.modes.transition_1 then
    local current_score = read_score_with_rollover_check()
    local score_earned = current_score - s.stage_start_score

    s.dk3_actual_board_num = s.dk3_actual_board_num + 1

    record_board_dk3(
      s.dk3_actual_board_num,
      s.dk3_completed_level,
      s.current_screen_num,
      score_earned,
      current_score,
      false,
      nil,
      lives,
      s.dk3_completed_screen_type,
      nil
    )

    -- After recording board 256, 512, 768, etc., increment loop counter and set new loop_start_score
    if s.dk3_actual_board_num % config.loop_size == 0 then
      s.dk3_current_loop = s.dk3_current_loop + 1
      s.dk3_loop_start_score = current_score
    end

    s.dk3_stage_completed = false
    s.prev_score = current_score
  end

  -- DEATH DETECTION: Flag death for deferred recording
  if
    dead_status == config.death_status.dead
    and s.dk3_prev_dead_status == config.death_status.alive
  then
    s.dk3_death_pending = true
    s.dk3_death_pending_screen_type = screen_type
    s.dk3_death_pending_level = level
    s.dk3_death_pending_start_score = s.stage_start_score
    -- Capture lives at detection time (haven't decremented in memory yet)
    s.dk3_death_pending_lives_at_death = lives > 0 and (lives - 1) or 0
    s.dk3_death_pending_bonus = read_bonus_timer()
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
    and s.dk3_prev_game_mode ~= config.modes.game_over_1
    and s.dk3_prev_game_mode ~= config.modes.game_over_2
    and not s.game_over_processed
  then
    finalize_session("GAME OVER")
  end

  -- MULTI-SESSION DETECTION: After game over, watch for $6005 to leave "playing"
  -- Reset prepares for a potential next game; $6005 detection handles the rest
  if s.game_over_processed then
    local game_active = read_byte(config.addresses.game_active)
    if game_active ~= config.game_active_playing then
      session_count = session_count + 1
      CSV_FILE, JSON_FILE, TEXT_FILE = get_output_filenames(session_count)
      reset_session_state()
      session_banner_pending = true
    end
  end

  -- Print deferred session banner once gameplay is confirmed
  if session_banner_pending and s.gameplay_started then
    print(string.format("\n=== SESSION %d ===\n", session_count))
    print("Tracking gameplay...\n")
    if session_pending_timing_msg then
      print(session_pending_timing_msg)
      session_pending_timing_msg = nil
    end
    session_banner_pending = false
  end

  -- Update previous state
  s.dk3_prev_game_mode = game_mode
  s.dk3_prev_dead_status = dead_status
  s.dk3_prev_screen_type = screen_type
  s.dk3_prev_level = level
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
