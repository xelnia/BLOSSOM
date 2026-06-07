-- ============================================================================
-- EXPORT FUNCTIONS
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
      "Attempt_Num,Board_Number,Board_Label,Screen_Type,Score_Earned,Total_Score,Death,Death_Num,Lives,Frame,Variation,Romset,INP_File,Start_Button_Frame,End_Game_Frame,Playing_Time_Frames\n"
    )
  else
    file:write(
      "Screen_Num,Stage,Screen_Type,Level,Score_Earned,Total_Score,Death,Death_Num,Frame,Romset,INP_File,Start_Button_Frame,End_Game_Frame,Playing_Time_Frames\n"
    )
  end

  -- Write data
  local first_row = true
  for _, stage in ipairs(stage_data) do
    local screen_num_str = stage.screen_num == "" and "" or tostring(stage.screen_num)
    local death_num_str = stage.death_num and tostring(stage.death_num) or ""
    local inp_file_str = first_row and get_inp_filename() or ""
    local start_frame_str = ""
    local end_frame_str = ""
    local duration_str = ""
    if first_row then
      start_frame_str = start_frame and tostring(start_frame) or ""
      end_frame_str = end_frame and tostring(end_frame) or ""
      if start_frame and end_frame then
        duration_str = tostring(end_frame - start_frame)
      end
    end

    if GAME_TYPE == "dkong3" then
      -- DK3 format with Lives and Variation
      local config = get_config()
      local variation_str = first_row and (game_variation or "") or ""
      local romset_str = first_row and config.romset or ""
      file:write(string.format(
        "%s,%d,%s,%s,%d,%d,%s,%s,%d,%d,%s,%s,%s,%s,%s,%s\n",
        screen_num_str, -- Attempt_Num
        stage.level, -- Board_Number
        stage.board, -- Board_Label
        stage.screen_type, -- Screen_Type
        stage.score_earned,
        stage.total_score,
        stage.death and "true" or "false",
        death_num_str,
        stage.lives or 0,
        stage.frame,
        variation_str,
        romset_str,
        inp_file_str,
        start_frame_str,
        end_frame_str,
        duration_str
      ))
    else
      -- Standard platformer format
      local config = get_config()
      local romset_str = first_row and config.romset or ""
      file:write(
        string.format(
          "%s,%s,%s,%d,%d,%d,%s,%s,%d,%s,%s,%s,%s,%s\n",
          screen_num_str,
          stage.stage,
          stage.screen_type,
          stage.level,
          stage.score_earned,
          stage.total_score,
          stage.death and "true" or "false",
          death_num_str,
          stage.frame,
          romset_str,
          inp_file_str,
          start_frame_str,
          end_frame_str,
          duration_str
        )
      )
    end

    first_row = false
  end

  file:close()
  print(string.format("\n[OK] CSV exported to: %s", CSV_FILE))
end

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

  file:write("{\n")
  file:write(string.format('  "game": "%s",\n', config.full_name))
  file:write(string.format('  "romset": "%s",\n', config.romset))

  -- Add DK3-specific variation field
  if GAME_TYPE == "dkong3" then
    file:write(string.format('  "variation": "%s",\n', game_variation or ""))
  end

  file:write(string.format('  "final_score": %d,\n', prev_score))

  -- Add final level/stage info
  if GAME_TYPE == "dkong3" then
    -- DK3: final_level (formatted label) and final_stage (board number)
    local final_level_str = ""
    local final_stage_num = nil
    for i = #stage_data, 1, -1 do
      if not stage_data[i].is_level_total then
        local board_label = stage_data[i].board
        -- Only prepend "Board " for simple numeric boards (avoid "Board 257 (Loop 2: Board 1)")
        if not board_label:match("%(") then
          final_level_str = "Board " .. board_label
        else
          final_level_str = board_label
        end
        final_stage_num = stage_data[i].level -- Raw board number (actual_board_num)
        break
      end
    end

    if final_level_str ~= "" then
      file:write(string.format('  "final_level": "%s",\n', final_level_str))
      file:write(string.format('  "final_stage": %d,\n', final_stage_num))
    else
      file:write('  "final_level": null,\n')
      file:write('  "final_stage": null,\n')
    end
  else
    -- Platformer: final_level (stage name) and final_stage (screen_num)
    local final_level_str = ""
    local final_stage_num = nil
    for i = #stage_data, 1, -1 do
      if not stage_data[i].is_level_total then
        final_level_str = stage_data[i].stage -- Formatted stage like "22-1"
        final_stage_num = stage_data[i].screen_num -- Unique stage counter
        break
      end
    end

    if final_level_str ~= "" then
      file:write(string.format('  "final_level": "%s",\n', final_level_str))
      file:write(string.format('  "final_stage": %d,\n', final_stage_num))
    else
      file:write('  "final_level": null,\n')
      file:write('  "final_stage": null,\n')
    end
  end

  -- Timing information
  if start_frame and end_frame then
    local duration_frames = end_frame - start_frame
    file:write(string.format('  "playing_time": "%s",\n', format_duration(duration_frames)))
  else
    file:write('  "playing_time": null,\n')
  end

  if start_frame then
    file:write(string.format('  "start_button_frame": %d,\n', start_frame))
  else
    file:write('  "start_button_frame": null,\n')
  end

  if end_frame then
    file:write(string.format('  "end_game_frame": %d,\n', end_frame))
  else
    file:write('  "end_game_frame": null,\n')
  end

  if start_frame and end_frame then
    local duration_frames = end_frame - start_frame
    file:write(string.format('  "playing_time_frames": %d,\n', duration_frames))
  else
    file:write('  "playing_time_frames": null,\n')
  end

  file:write(string.format('  "inp_file": "%s",\n', get_inp_filename()))

  file:write('  "stages": [\n')
  for i, stage in ipairs(stage_data) do
    file:write("    {\n")

    if stage.is_level_total then
      file:write('      "screen_num": null,\n')
    else
      file:write(string.format('      "screen_num": %d,\n', stage.screen_num))
    end

    -- Use "board" or "stage" depending on game type
    if GAME_TYPE == "dkong3" then
      file:write(string.format('      "board": "%s",\n', stage.board))
    else
      file:write(string.format('      "stage": "%s",\n', stage.stage))
    end

    file:write(string.format('      "screen_type": "%s",\n', stage.screen_type))
    file:write(string.format('      "level": %d,\n', stage.level))
    file:write(string.format('      "score_earned": %d,\n', stage.score_earned))
    file:write(string.format('      "total_score": %d,\n', stage.total_score))

    -- Add lives for DK3
    if GAME_TYPE == "dkong3" then
      file:write(string.format('      "lives": %d,\n', stage.lives or 0))
    end

    file:write(string.format('      "death": %s,\n', stage.death and "true" or "false"))

    if stage.death_num then
      file:write(string.format('      "death_num": %d,\n', stage.death_num))
    else
      file:write('      "death_num": null,\n')
    end

    file:write(
      string.format('      "is_level_total": %s,\n', stage.is_level_total and "true" or "false")
    )
    file:write(string.format('      "frame": %d\n', stage.frame))
    file:write(i < #stage_data and "    },\n" or "    }\n")
  end

  file:write("  ]\n")
  file:write("}\n")

  file:close()
  print(string.format("[OK] JSON exported to: %s", JSON_FILE))
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

    -- Header
    local config = get_config()
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))
    file:write(string.format("Variation: %s\n", game_variation or ""))
    -- Add playing time if available
    if start_frame and end_frame then
      local duration_frames = end_frame - start_frame
      file:write(string.format("Estimated Playing Time: %s\n", format_duration(duration_frames)))
    end
    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_board ~= "" then
      file:write(string.format("Final Board: %s\n", final_board))
    end

    -- Display RBS milestones
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

    -- Display Loop milestones
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

    -- Screen type averages (only shown if max difficulty was reached)
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
      file:write("\n") -- Blank line before life stats

      -- Only show Total Lives for Marathon variations (redundant for 5 Lives)
      if game_variation and not game_variation:match("5 Lives") then
        file:write(string.format("Total Lives: %d\n", life_stats.total_lives))
      end

      file:write(
        string.format("First Life Score: %s\n", format_number(life_stats.first_life_score))
      )

      -- Only show 5 Lives Score if: Marathon variation AND player died 5+ times
      if life_stats.five_lives_score and game_variation and not game_variation:match("5 Lives") then
        file:write(string.format("5 Lives Score: %s\n", format_number(life_stats.five_lives_score)))
      end

      file:write(string.format("Last Life Score: %s\n", format_number(life_stats.last_life_score)))

      -- Longest life by points
      local longest_points_str = "#"
        .. table.concat(life_stats.longest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (points): %s - %s\n",
          longest_points_str,
          format_number(life_stats.longest_life_points.score)
        )
      )

      -- Longest life by boards
      local longest_boards_str = "#"
        .. table.concat(life_stats.longest_life_boards.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (boards): %s - %d\n",
          longest_boards_str,
          life_stats.longest_life_boards.boards
        )
      )

      -- Shortest life by points
      local shortest_points_str = "#"
        .. table.concat(life_stats.shortest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Shortest Life (points): %s - %s\n",
          shortest_points_str,
          format_number(life_stats.shortest_life_points.score)
        )
      )

      -- Shortest life by boards
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

    file:write(string.format("Total Death Points: %s\n\n", format_number(total_death_points)))
    file:write("===================================\n\n")

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

    -- Header
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))

    -- Add playing time if available
    if start_frame and end_frame then
      local duration_frames = end_frame - start_frame
      file:write(string.format("Estimated Playing Time: %s\n", format_duration(duration_frames)))
    end

    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_stage ~= "" then
      file:write(string.format("Final Stage: %s\n", final_stage))
    end

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
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        elseif final_level < 22 then
          -- Before level 22: show both paces
          file:write(string.format("22-1 Pace: %s\n", format_number(last_pace)))
          if last_pace_22_4 then
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        end
      else
        -- Donkey Kong and Donkey Kong Junior
        if final_level < 22 then
          file:write(string.format("Pace: %s\n", format_number(last_pace)))
        end
      end
    end

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

    -- Best/Worst statistics
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

    file:write(string.format("Total Death Points: %s\n\n", format_number(total_death_points)))
    file:write("===================================\n\n")

    -- Track when we change levels to insert separators
    local current_output_level = nil

    for _, stage in ipairs(stage_data) do
      if stage.is_level_total then
        -- Level total line
        local level_display = format_level_for_display(stage.level)
        file:write(string.format("L%s: %s\n", level_display, format_number(stage.score_earned)))
        file:write("---\n")
        current_output_level = stage.level
      else
        -- Regular stage or death
        if stage.death then
          -- Death format: "19-3 Death #3: 1,000 --> 1,014,000"
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
          -- Completed stage format with avg and pace data
          local stage_line = string.format(
            "%s: %s --> %s",
            stage.stage,
            format_number(stage.score_earned),
            format_number(stage.total_score)
          )

          -- Add average if present
          if stage.avg_type and stage.avg_value then
            stage_line = stage_line
              .. string.format(" | %s: %s", stage.avg_type, format_number_decimal(stage.avg_value))
          end

          -- Add pace if present
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
