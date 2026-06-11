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
