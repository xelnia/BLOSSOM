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
