-- Helper to print Game Over / Session Ended summary for platformers
local function print_platformer_summary(header_text, current_score)
  local config = get_config()

  -- Find the final stage (last non-level-total entry)
  local final_stage = ""
  local final_level = nil
  local final_stage_position = nil
  for i = #s.stage_data, 1, -1 do
    if not s.stage_data[i].is_level_total then
      final_stage = s.stage_data[i].stage
      final_level = s.stage_data[i].level
      final_stage_position = s.stage_data[i].stage:match("%-(%d+)$")
      if final_stage_position then
        final_stage_position = tonumber(final_stage_position)
      end
      break
    end
  end

  print(string.format("\n=== %s ===", header_text))
  print("\nSCORING SUMMARY\n---------------")
  print(string.format("Final Score: %s", format_number(current_score)))
  if final_stage ~= "" then
    print(string.format("Final Stage: %s", final_stage))
  end
  print(string.format("Total Screens: %d", s.current_screen_num))

  -- Show pace based on game type and final stage
  if final_level and s.last_pace then
    if config.supports_22_4_pace then
      -- Crazy Kong Part II
      if
        final_level == 22
        and final_stage_position
        and final_stage_position >= 1
        and final_stage_position <= 3
      then
        -- On 22-1, 22-2, or 22-3: show only 22-4 pace
        if s.last_pace_22_4 then
          print(string.format("22-4 Pace: %s", format_number(s.last_pace_22_4)))
        end
      elseif final_level < 22 then
        -- Before level 22: show both paces
        print(string.format("22-1 Pace: %s", format_number(s.last_pace)))
        if s.last_pace_22_4 then
          print(string.format("22-4 Pace: %s", format_number(s.last_pace_22_4)))
        end
      end
    else
      -- Donkey Kong and Donkey Kong Junior
      if final_level < 22 then
        print(string.format("Pace: %s", format_number(s.last_pace)))
      end
    end
  end

  if s.start_score_total > 0 then
    if s.start_phase_deaths > 0 then
      print(
        string.format(
          "Start Score: %s (%s + %s)",
          format_number(s.start_score_total),
          format_number(s.start_score_for_pace),
          format_number(s.start_phase_death_points)
        )
      )
    else
      print(string.format("Start Score: %s", format_number(s.start_score_total)))
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
    if #s.screen_scores[i] > 0 then
      local best_score, best_labels, worst_score, worst_labels = find_best_worst(s.screen_scores[i])
      local avg = s.screen_sum[i] / s.screen_count[i]
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
  if #s.level_scores > 0 then
    local best_score, best_labels, worst_score, worst_labels = find_best_worst(s.level_scores)
    local avg = s.level_sum / s.level_count
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

  -- Recorded Lives / Deaths / Death Points (diagnostic group)
  if s.starting_lives then
    local total_lives = s.starting_lives + s.earned_lives
    if s.earned_lives > 0 then
      print(
        string.format(
          "Recorded Lives (starting + bonus): %d (%d + %d)",
          total_lives,
          s.starting_lives,
          s.earned_lives
        )
      )
    else
      print(string.format("Recorded Lives: %d", total_lives))
    end
  end
  print(string.format("Recorded Deaths: %d", s.death_count))
  print(string.format("Total Death Points: %s", format_number(s.total_death_points)))

  -- Life statistics
  local life_stats = calculate_life_stats()
  if life_stats then
    print(string.format("First Life Score: %s", format_number(life_stats.first_life_score)))
    print(string.format("Last Life Score: %s", format_number(life_stats.last_life_score)))

    local longest_points_str = "#" .. table.concat(life_stats.longest_life_points.life_nums, ", #")
    print(
      string.format(
        "Longest Life (points): %s - %s",
        longest_points_str,
        format_number(life_stats.longest_life_points.score)
      )
    )

    local longest_stages_str = "#" .. table.concat(life_stats.longest_life_stages.life_nums, ", #")
    print(
      string.format(
        "Longest Life (stages): %s - %d",
        longest_stages_str,
        life_stats.longest_life_stages.stages
      )
    )

    local shortest_points_str = "#"
      .. table.concat(life_stats.shortest_life_points.life_nums, ", #")
    print(
      string.format(
        "Shortest Life (points): %s - %s",
        shortest_points_str,
        format_number(life_stats.shortest_life_points.score)
      )
    )

    local shortest_stages_str = "#"
      .. table.concat(life_stats.shortest_life_stages.life_nums, ", #")
    print(
      string.format(
        "Shortest Life (stages): %s - %d",
        shortest_stages_str,
        life_stats.shortest_life_stages.stages
      )
    )

    print(string.format("Average Life (points): %s", format_number_decimal(life_stats.avg_points)))
    print(string.format("Average Life (stages): %s", format_number_decimal(life_stats.avg_stages)))
  end

  -- TIMING SUMMARY
  local playing_frames = get_playing_time_frames()
  local has_plat_timing = playing_frames
    or (s.speedrun_start_frame and s.speedrun_end_frame)
    or (s.start_frame and s.start_phase_end_frame)
    or (s.speedrun_start_frame and s.killscreen_frame)
    or (s.start_frame and (s.game_over_vram_frame or s.end_frame))

  if has_plat_timing then
    print("\nTIMING SUMMARY\n--------------")
  end

  -- Elapsed times (ordered shortest to longest expected duration)
  if s.speedrun_start_frame and s.speedrun_end_frame then
    local dur = s.speedrun_end_frame - s.speedrun_start_frame
    print(string.format("Unofficial Speedrun Start Time: %s", format_duration(dur)))
  end

  if s.start_frame and s.start_phase_end_frame then
    local dur = s.start_phase_end_frame - s.start_frame
    print(string.format("Unofficial Standard Start Time: %s", format_duration(dur)))
  end

  if s.speedrun_start_frame and s.killscreen_frame then
    local dur = s.killscreen_frame - s.speedrun_start_frame
    print(string.format("Unofficial Speedrun Killscreen Time: %s", format_duration(dur)))
  end

  if playing_frames then
    print(string.format("Unofficial Full Game Time: %s", format_duration(playing_frames)))
  end

  -- Frame ranges (same order as elapsed times)
  if has_plat_timing then
    print("")
  end

  if s.speedrun_start_frame and s.speedrun_end_frame then
    local dur = s.speedrun_end_frame - s.speedrun_start_frame
    print(
      string.format(
        "Speedrun Start Frames: %s - %s (%s frames)",
        format_number(s.speedrun_start_frame),
        format_number(s.speedrun_end_frame),
        format_number(dur)
      )
    )
  end

  if s.start_frame and s.start_phase_end_frame then
    local dur = s.start_phase_end_frame - s.start_frame
    print(
      string.format(
        "Standard Start Frames: %s - %s (%s frames)",
        format_number(s.start_frame),
        format_number(s.start_phase_end_frame),
        format_number(dur)
      )
    )
  end

  if s.speedrun_start_frame and s.killscreen_frame then
    local dur = s.killscreen_frame - s.speedrun_start_frame
    print(
      string.format(
        "Speedrun Killscreen Frames: %s - %s (%s frames)",
        format_number(s.speedrun_start_frame),
        format_number(s.killscreen_frame),
        format_number(dur)
      )
    )
  end

  if s.start_frame and (s.game_over_vram_frame or s.end_frame) then
    local end_f = s.game_over_vram_frame or s.end_frame
    local dur = end_f - s.start_frame
    print(
      string.format(
        "Full Game Frames: %s - %s (%s frames)",
        format_number(s.start_frame),
        format_number(end_f),
        format_number(dur)
      )
    )
  end

  -- SCORE MILESTONES
  if #s.score_milestones > 0 then
    print("\nSCORE MILESTONES\n----------------")
    local prev_ms_frame = nil
    for _, ms in ipairs(s.score_milestones) do
      local time_str = ""
      if s.start_frame then
        time_str = string.format(" - %s", format_duration(ms.frame - s.start_frame))
      end
      local delta_str = ""
      if prev_ms_frame then
        delta_str = string.format(" | +%s", format_duration(ms.frame - prev_ms_frame))
      end
      local stage_str = ms.stage and string.format(" | %s", ms.stage) or ""
      local timer_str = ms.bonus_timer
          and string.format(" | Timer: %s", format_number(ms.bonus_timer))
        or ""
      local lives_str = ms.lives and string.format(" | Lives: %d", ms.lives) or ""
      local phase_str = ""
      if ms.during_gameplay == false then
        phase_str = " [stage end]"
      end
      print(
        string.format(
          "%s (Frame %s%s)%s%s%s%s%s",
          format_number(ms.score),
          format_number(ms.frame),
          time_str,
          delta_str,
          stage_str,
          timer_str,
          lives_str,
          phase_str
        )
      )
      prev_ms_frame = ms.frame
    end
  end
end

-- Helper to print Game Over / Session Ended summary for DK3
local function print_dk3_summary(header_text, current_score)
  local config = get_config()

  -- Find final board
  local final_board = ""
  for i = #s.stage_data, 1, -1 do
    final_board = s.stage_data[i].board
    break
  end

  print(string.format("\n=== %s ===", header_text))
  print("\nSCORING SUMMARY\n---------------")
  print(string.format("Final Score: %s", format_number(current_score)))

  -- 5 Lives Score (headline stat, shown directly under Final Score)
  local life_stats = calculate_dk3_life_stats()
  if
    life_stats
    and life_stats.five_lives_score
    and game_variation
    and not game_variation:match("5 Lives")
  then
    print(string.format("5 Lives Score: %s", format_number(life_stats.five_lives_score)))
  end

  if final_board ~= "" then
    print(string.format("Final Board: %s", final_board))
  end

  -- Display Max Difficulty milestones
  for _, md in ipairs(s.dk3_max_diff_milestones) do
    local lives_str = md.lives and string.format(" | Lives: %d", md.lives) or ""
    local score_str
    if md.total_score == md.max_diff_score then
      score_str = format_number(md.total_score)
    else
      score_str = string.format(
        "Total: %s | %d: %s",
        format_number(md.total_score),
        md.count,
        format_number(md.max_diff_score)
      )
    end
    print(string.format("Max Difficulty %d Score: %s%s", md.count, score_str, lives_str))
  end

  -- Display RBS milestones
  for _, rbs in ipairs(s.dk3_rbs_milestones) do
    local lives_str = rbs.lives and string.format(" | Lives: %d", rbs.lives) or ""
    local score_str
    if rbs.total_score == rbs.rbs_score then
      score_str = format_number(rbs.total_score)
    else
      score_str = string.format(
        "Total: %s | %d: %s",
        format_number(rbs.total_score),
        rbs.rbs_num,
        format_number(rbs.rbs_score)
      )
    end
    print(string.format("RBS %d Score: %s%s", rbs.rbs_num, score_str, lives_str))
  end

  -- Display Loop milestones
  for _, loop in ipairs(s.dk3_loop_milestones) do
    local lives_str = loop.lives and string.format(" | Lives: %d", loop.lives) or ""
    local score_str
    if loop.total_score == loop.loop_score then
      score_str = format_number(loop.total_score)
    else
      score_str = string.format(
        "Total: %s | %d: %s",
        format_number(loop.total_score),
        loop.loop_num,
        format_number(loop.loop_score)
      )
    end
    print(string.format("Loop %d Score: %s%s", loop.loop_num, score_str, lives_str))
  end

  -- Screen type averages (only shown if max difficulty was reached)
  if s.dk3_max_diff_count > 0 then
    for i = 0, 2 do
      local idx = i + 1
      if s.dk3_screen_count[idx] > 0 then
        print(
          string.format(
            "Max Difficulty %s Average: %s",
            config.screen_names[i],
            format_number_decimal(s.dk3_screen_sum[idx] / s.dk3_screen_count[idx])
          )
        )
      end
    end
  end

  -- Per-life detail statistics
  if life_stats then
    print("") -- Blank line before life details

    print(string.format("First Life Score: %s", format_number(life_stats.first_life_score)))
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

    print(string.format("Average Life (points): %s", format_number_decimal(life_stats.avg_points)))
    print(string.format("Average Life (boards): %s", format_number_decimal(life_stats.avg_boards)))
  end

  -- Recorded Lives / Deaths / Death Points (diagnostic group)
  print("") -- Blank line before diagnostic group
  if s.starting_lives then
    local total_lives = s.starting_lives + s.earned_lives
    -- Only show Recorded Lives for Marathon variations (redundant for 5 Lives)
    if not game_variation or not game_variation:match("5 Lives") then
      if s.earned_lives > 0 then
        print(
          string.format(
            "Recorded Lives (starting + bonus): %d (%d + %d)",
            total_lives,
            s.starting_lives,
            s.earned_lives
          )
        )
      else
        print(string.format("Recorded Lives: %d", total_lives))
      end
    end
  end
  print(string.format("Recorded Deaths: %d", s.death_count))
  print(string.format("Total Death Points: %s", format_number(s.total_death_points)))

  -- TIMING SUMMARY
  local playing_frames = get_playing_time_frames()
  local has_dk3_timing = playing_frames
    or #s.dk3_max_diff_milestones > 0
    or #s.dk3_rbs_milestones > 0
    or #s.dk3_loop_milestones > 0
    or (s.start_frame and (s.game_over_vram_frame or s.end_frame))

  if has_dk3_timing then
    print("\nTIMING SUMMARY\n--------------")
  end

  local prev_md_frame = nil
  for _, md in ipairs(s.dk3_max_diff_milestones) do
    local time_str = ""
    if s.start_frame then
      local total_dur = md.frame - s.start_frame
      if prev_md_frame then
        time_str = string.format(
          " (Total: %s | %d: %s)",
          format_duration(total_dur),
          md.count,
          format_duration(md.frame - prev_md_frame)
        )
      else
        time_str = string.format(" (%s)", format_duration(total_dur))
      end
    end
    print(
      string.format("Max Difficulty %d: Frame %s%s", md.count, format_number(md.frame), time_str)
    )
    prev_md_frame = md.frame
  end

  local prev_rbs_frame = nil
  for _, rbs in ipairs(s.dk3_rbs_milestones) do
    local time_str = ""
    if s.start_frame then
      local total_dur = rbs.frame - s.start_frame
      if prev_rbs_frame then
        time_str = string.format(
          " (Total: %s | %d: %s)",
          format_duration(total_dur),
          rbs.rbs_num,
          format_duration(rbs.frame - prev_rbs_frame)
        )
      else
        time_str = string.format(" (%s)", format_duration(total_dur))
      end
    end
    print(string.format("RBS %d: Frame %s%s", rbs.rbs_num, format_number(rbs.frame), time_str))
    prev_rbs_frame = rbs.frame
  end

  local prev_loop_frame = nil
  for _, loop in ipairs(s.dk3_loop_milestones) do
    local time_str = ""
    if s.start_frame then
      local total_dur = loop.frame - s.start_frame
      if prev_loop_frame then
        time_str = string.format(
          " (Total: %s | %d: %s)",
          format_duration(total_dur),
          loop.loop_num,
          format_duration(loop.frame - prev_loop_frame)
        )
      else
        time_str = string.format(" (%s)", format_duration(total_dur))
      end
    end
    print(
      string.format(
        "Loop %d Complete: Frame %s%s",
        loop.loop_num,
        format_number(loop.frame),
        time_str
      )
    )
    prev_loop_frame = loop.frame
  end

  if playing_frames then
    print(string.format("Unofficial Full Game Time: %s", format_duration(playing_frames)))
  end

  if s.start_frame and (s.game_over_vram_frame or s.end_frame) then
    local end_f = s.game_over_vram_frame or s.end_frame
    local dur = end_f - s.start_frame
    print("")
    print(
      string.format(
        "Full Game Frames: %s - %s (%s frames)",
        format_number(s.start_frame),
        format_number(end_f),
        format_number(dur)
      )
    )
  end

  -- SCORE MILESTONES
  if #s.score_milestones > 0 then
    print("\nSCORE MILESTONES\n----------------")
    local prev_ms_frame = nil
    for _, ms in ipairs(s.score_milestones) do
      local time_str = ""
      if s.start_frame then
        time_str = string.format(" - %s", format_duration(ms.frame - s.start_frame))
      end
      local delta_str = ""
      if prev_ms_frame then
        delta_str = string.format(" | +%s", format_duration(ms.frame - prev_ms_frame))
      end
      local board_str = ms.board and string.format(" | Board %d", ms.board) or ""
      local timer_str = ms.bonus_timer
          and string.format(" | Timer: %s", format_number(ms.bonus_timer))
        or ""
      local lives_str = ms.lives and string.format(" | Lives: %d", ms.lives) or ""
      local phase_str = ""
      if ms.during_gameplay == false then
        phase_str = " [stage end]"
      end
      print(
        string.format(
          "%s (Frame %s%s)%s%s%s%s%s",
          format_number(ms.score),
          format_number(ms.frame),
          time_str,
          delta_str,
          board_str,
          timer_str,
          lives_str,
          phase_str
        )
      )
      prev_ms_frame = ms.frame
    end
  end
end

-- ============================================================================
-- SESSION FINALIZATION
-- ============================================================================
-- Consolidates game over, INP end, and manual exit into a single path.
-- Called from: frame loop (game over, INP end) and stop callback (manual exit).
local function finalize_session(reason)
  if s.game_over_processed then
    return
  end
  if s.current_screen_num == 0 then
    return
  end

  local config = get_config()
  local current_score = read_score_with_rollover_check()

  -- Settle any pending death before processing session end
  if GAME_TYPE == "dkong3" then
    if s.dk3_death_pending then
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
  else
    if s.death_pending then
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
        read_byte(config.addresses.lives),
        s.death_pending_bonus
      )

      s.last_stage_was_completed = false
      s.stage_start_score = current_score
      s.prev_score = current_score
      s.death_pending = false
      s.death_pending_screen_type = 0
      s.death_pending_level = 0
      s.death_pending_position = 0
      s.death_pending_bonus = 0
    end
  end

  -- Capture end frame for duration calculation
  if not s.end_frame then
    if inp_end_frame then
      s.end_frame = inp_end_frame
    else
      s.end_frame = frame_count
    end
  end

  -- Game-specific finalization and summary
  if GAME_TYPE == "dkong3" then
    -- Capture VRAM-based game over timing (only for actual game over)
    if reason == "GAME OVER" and not s.game_over_vram_frame then
      local vram_tile = read_byte(config.addresses.game_over_vram)
      if vram_tile == 0x17 then
        s.game_over_vram_frame = frame_count
        if s.start_frame then
          local go_dur = s.game_over_vram_frame - s.start_frame
          print(
            string.format(
              "  [Timing] Standard Game End: Frame %s (%s frames - %s)",
              format_number(s.game_over_vram_frame),
              format_number(go_dur),
              format_duration(go_dur)
            )
          )
        end
      end
    end

    -- Record current life in progress (SESSION ENDED only)
    if reason ~= "GAME OVER" then
      if
        s.death_count == 0
        or (s.dk3_actual_board_num > 0 and s.dk3_current_life_start_score < current_score)
      then
        local boards_completed = s.dk3_actual_board_num - s.dk3_current_life_start_board + 1
        if boards_completed < 0 then
          boards_completed = 0
        end

        table.insert(s.dk3_life_tracking, {
          life_num = s.death_count + 1,
          start_score = s.dk3_current_life_start_score,
          end_score = current_score,
          start_board = s.dk3_current_life_start_board,
          boards_completed = boards_completed,
        })
      end
    end

    print_dk3_summary(reason, current_score)
  else
    -- Capture VRAM-based game over timing (only for actual game over)
    if reason == "GAME OVER" and not s.game_over_vram_frame then
      local vram_tile = read_byte(config.addresses.game_over_vram)
      if vram_tile == 0x17 then
        s.game_over_vram_frame = frame_count
        if s.start_frame then
          local go_dur = s.game_over_vram_frame - s.start_frame
          print(
            string.format(
              "  [Timing] Standard Game End: Frame %s (%s frames - %s)",
              format_number(s.game_over_vram_frame),
              format_number(go_dur),
              format_duration(go_dur)
            )
          )
        end
      end
    end

    -- Record final level total
    local is_killscreen = (s.current_level_being_played == 22 and s.level_position[22] == 1)

    if
      s.current_level_being_played > 0
      and s.level_score_accumulated > 0
      and (is_killscreen or s.last_stage_was_completed)
    then
      record_level_total(s.current_level_being_played, s.level_score_accumulated, current_score)
    end

    print_platformer_summary(reason, current_score)
  end

  export_csv()
  export_json()
  export_text()
  print("") -- Blank line to separate from WolfMAME messages

  s.game_over_processed = true
  s.prev_score = current_score
end
