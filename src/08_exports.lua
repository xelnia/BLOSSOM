-- ============================================================================
-- EXPORT FUNCTIONS
-- ============================================================================

-- ============================================================================
-- JSON SERIALIZATION HELPERS
-- ============================================================================

-- Marker for ordered JSON objects (preserves key order)
-- Usage: json_ordered({ {"key1", val1}, {"key2", val2}, ... })
local function json_ordered(pairs_list)
  return { __json_ordered = true, pairs = pairs_list }
end

-- Serialize any Lua value to a JSON string with pretty-print indentation
-- Handles: nil, boolean, number, string, ordered objects, arrays
local function to_json(val, indent_level)
  indent_level = indent_level or 0
  local indent = string.rep("  ", indent_level)
  local child_indent = string.rep("  ", indent_level + 1)

  if val == nil then
    return "null"
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  elseif type(val) == "number" then
    if val == math.floor(val) and math.abs(val) < 1e15 then
      return string.format("%d", val)
    else
      return string.format("%.3f", val)
    end
  elseif type(val) == "string" then
    local escaped = val:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
    return '"' .. escaped .. '"'
  elseif type(val) == "table" then
    if val.__json_ordered then
      -- Ordered object: array of {key, value} pairs
      if #val.pairs == 0 then
        return "{}"
      end
      local lines = {}
      for i, pair in ipairs(val.pairs) do
        local k = pair[1]
        local v = pair[2]
        local comma = i < #val.pairs and "," or ""
        local serialized = to_json(v, indent_level + 1)
        table.insert(lines, string.format('%s"%s": %s%s', child_indent, k, serialized, comma))
      end
      return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
    else
      -- Regular array (sequential integer keys)
      if #val == 0 then
        return "[]"
      end
      local lines = {}
      for i, item in ipairs(val) do
        local comma = i < #val and "," or ""
        local serialized = to_json(item, indent_level + 1)
        table.insert(lines, child_indent .. serialized .. comma)
      end
      return "[\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "]"
    end
  end

  return "null"
end

-- ============================================================================
-- CSV EXPORT
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
      "attempt_num,board_number,board_label,screen_type,board_score,running_total,death,death_num,lives,frame,bonus_timer\n"
    )
  else
    file:write(
      "screen_num,stage,screen_type,level,board_score,running_total,death,death_num,lives,frame,bonus_timer\n"
    )
  end

  -- Write data (exclude level totals)
  for _, stage in ipairs(stage_data) do
    if not stage.is_level_total then
      local screen_num_str = stage.screen_num == "" and "" or tostring(stage.screen_num)
      local death_num_str = stage.death_num and tostring(stage.death_num) or ""
      local bonus_timer_str = stage.bonus_timer and tostring(stage.bonus_timer) or ""

      if GAME_TYPE == "dkong3" then
        file:write(
          string.format(
            "%s,%d,%s,%s,%d,%d,%s,%s,%d,%d,%s\n",
            screen_num_str,
            stage.level,
            stage.board,
            stage.screen_type,
            stage.score_earned,
            stage.total_score,
            stage.death and "true" or "false",
            death_num_str,
            stage.lives or 0,
            stage.frame,
            bonus_timer_str
          )
        )
      else
        file:write(
          string.format(
            "%s,%s,%s,%d,%d,%d,%s,%s,%d,%d,%s\n",
            screen_num_str,
            stage.stage,
            stage.screen_type,
            stage.level,
            stage.score_earned,
            stage.total_score,
            stage.death and "true" or "false",
            death_num_str,
            stage.lives or 0,
            stage.frame,
            bonus_timer_str
          )
        )
      end
    end
  end

  file:close()
  print(string.format("\n[OK] CSV exported to: %s", CSV_FILE))
end

-- ============================================================================
-- JSON EXPORT
-- ============================================================================

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

  -- Find the final stage/board (last non-level-total entry)
  local final_level_str = nil
  local final_stage_num = nil
  if GAME_TYPE == "dkong3" then
    for i = #stage_data, 1, -1 do
      local board_label = stage_data[i].board
      if not board_label:match("%(") then
        final_level_str = "Board " .. board_label
      else
        final_level_str = board_label
      end
      final_stage_num = stage_data[i].level
      break
    end
  else
    for i = #stage_data, 1, -1 do
      if not stage_data[i].is_level_total then
        final_level_str = stage_data[i].stage
        final_stage_num = stage_data[i].screen_num
        break
      end
    end
  end

  -- METADATA
  local metadata = json_ordered({
    { "game", config.full_name },
    { "variation", GAME_TYPE == "dkong3" and game_variation or nil },
    { "romset", config.romset },
    { "inp_file", get_inp_filename() },
    { "mame_version", detect_mame_version() },
    { "blossom_version", BLOSSOM_VERSION },
  })

  -- SCORING SUMMARY
  local scoring_pairs = {
    { "final_score", prev_score },
    { "final_level", final_level_str },
    { "final_stage", final_stage_num },
    { "recorded_deaths", death_count },
    { "total_death_points", total_death_points },
  }

  if GAME_TYPE == "dkong3" then
    -- DK3 scoring summary
    -- Screen type averages (max difficulty only)
    if dk3_max_diff_count > 0 then
      local avg_pairs = {}
      for i = 0, 2 do
        local idx = i + 1
        if dk3_screen_count[idx] > 0 then
          table.insert(
            avg_pairs,
            { config.screen_names[i]:lower(), dk3_screen_sum[idx] / dk3_screen_count[idx] }
          )
        end
      end
      if #avg_pairs > 0 then
        table.insert(scoring_pairs, { "max_diff_screen_averages", json_ordered(avg_pairs) })
      end
    end

    -- RBS milestones (score data)
    local rbs_score_array = {}
    for _, rbs in ipairs(dk3_rbs_milestones) do
      table.insert(
        rbs_score_array,
        json_ordered({
          { "rbs_num", rbs.rbs_num },
          { "total_score", rbs.total_score },
          { "rbs_score", rbs.rbs_score },
        })
      )
    end
    table.insert(scoring_pairs, { "rbs_milestones", rbs_score_array })

    -- Loop milestones (score data)
    local loop_score_array = {}
    for _, loop in ipairs(dk3_loop_milestones) do
      table.insert(
        loop_score_array,
        json_ordered({
          { "loop_num", loop.loop_num },
          { "total_score", loop.total_score },
          { "loop_score", loop.loop_score },
        })
      )
    end
    table.insert(scoring_pairs, { "loop_milestones", loop_score_array })

    -- Life statistics
    local life_stats = calculate_dk3_life_stats()
    if life_stats then
      local life_pairs = {
        { "recorded_lives", life_stats.total_lives },
        { "first_life_score", life_stats.first_life_score },
        { "five_lives_score", life_stats.five_lives_score },
        { "last_life_score", life_stats.last_life_score },
        {
          "longest_life_points",
          json_ordered({
            { "score", life_stats.longest_life_points.score },
            { "life_nums", life_stats.longest_life_points.life_nums },
          }),
        },
        {
          "longest_life_boards",
          json_ordered({
            { "boards", life_stats.longest_life_boards.boards },
            { "life_nums", life_stats.longest_life_boards.life_nums },
          }),
        },
        {
          "shortest_life_points",
          json_ordered({
            { "score", life_stats.shortest_life_points.score },
            { "life_nums", life_stats.shortest_life_points.life_nums },
          }),
        },
        {
          "shortest_life_boards",
          json_ordered({
            { "boards", life_stats.shortest_life_boards.boards },
            { "life_nums", life_stats.shortest_life_boards.life_nums },
          }),
        },
        { "avg_points", math.floor(life_stats.avg_points) },
        { "avg_boards", math.floor(life_stats.avg_boards) },
      }
      table.insert(scoring_pairs, { "life_stats", json_ordered(life_pairs) })
    end
  else
    -- Platformer scoring summary
    table.insert(scoring_pairs, { "total_screens", current_screen_num })

    -- Pace
    local final_level = nil
    if final_level_str then
      local level_match = final_level_str:match("^(%d+)-")
      if level_match then
        final_level = tonumber(level_match)
      end
    end

    if final_level and last_pace then
      if config.supports_22_4_pace then
        table.insert(scoring_pairs, { "pace_22_1", last_pace })
        table.insert(scoring_pairs, { "pace_22_4", last_pace_22_4 })
      else
        table.insert(scoring_pairs, { "pace", last_pace })
      end
    end

    -- Start score
    if start_score_total > 0 then
      table.insert(scoring_pairs, { "start_score_total", start_score_total })
      table.insert(scoring_pairs, { "start_score_for_pace", start_score_for_pace })
      table.insert(scoring_pairs, { "start_phase_deaths", start_phase_deaths })
      table.insert(scoring_pairs, { "start_phase_death_points", start_phase_death_points })
    end

    -- Screen type averages
    local display_order
    if GAME_TYPE == "dkongjr" then
      display_order = { 2, 1, 3, 4 }
    else
      display_order = { 1, 2, 3, 4 }
    end

    local screen_avg_pairs = {}
    for _, i in ipairs(display_order) do
      if #screen_scores[i] > 0 then
        local best_score, best_labels, worst_score, worst_labels = find_best_worst(screen_scores[i])
        local avg = screen_sum[i] / screen_count[i]
        local type_name = get_screen_type_name(i):lower()
        table.insert(screen_avg_pairs, {
          type_name,
          json_ordered({
            { "average", avg },
            { "best_score", best_score },
            { "best_stages", best_labels },
            { "worst_score", worst_score },
            { "worst_stages", worst_labels },
            { "count", screen_count[i] },
          }),
        })
      end
    end
    if #screen_avg_pairs > 0 then
      table.insert(scoring_pairs, { "screen_type_averages", json_ordered(screen_avg_pairs) })
    end

    -- Level averages
    if #level_scores > 0 then
      local best_score, best_labels, worst_score, worst_labels = find_best_worst(level_scores)
      local avg = level_sum / level_count
      table.insert(scoring_pairs, {
        "level_averages",
        json_ordered({
          { "average", avg },
          { "best_score", best_score },
          { "best_levels", best_labels },
          { "worst_score", worst_score },
          { "worst_levels", worst_labels },
          { "count", level_count },
        }),
      })
    end
  end

  local scoring_summary = json_ordered(scoring_pairs)

  -- TIMING SUMMARY
  local timing_pairs = {}

  -- Raw frame markers
  table.insert(timing_pairs, { "start_button_frame", start_frame })

  if GAME_TYPE ~= "dkong3" then
    table.insert(timing_pairs, { "speedrun_start_frame", speedrun_start_frame })
    table.insert(timing_pairs, { "start_phase_clear_frame", speedrun_end_frame })
    table.insert(timing_pairs, { "start_phase_end_frame", start_phase_end_frame })
    table.insert(timing_pairs, { "killscreen_frame", killscreen_frame })
  end

  table.insert(timing_pairs, { "end_game_frame", end_frame })
  table.insert(timing_pairs, { "game_over_vram_frame", game_over_vram_frame })

  -- Computed durations (platformer only)
  if GAME_TYPE ~= "dkong3" then
    -- Speedrun start duration
    if speedrun_start_frame and speedrun_end_frame then
      local dur = speedrun_end_frame - speedrun_start_frame
      table.insert(timing_pairs, { "speedrun_start_duration_frames", dur })
      table.insert(timing_pairs, { "speedrun_start_time", format_duration(dur) })
    else
      table.insert(timing_pairs, { "speedrun_start_duration_frames", nil })
      table.insert(timing_pairs, { "speedrun_start_time", nil })
    end

    -- Standard start duration
    if start_frame and start_phase_end_frame then
      local dur = start_phase_end_frame - start_frame
      table.insert(timing_pairs, { "standard_start_duration_frames", dur })
      table.insert(timing_pairs, { "standard_start_time", format_duration(dur) })
    else
      table.insert(timing_pairs, { "standard_start_duration_frames", nil })
      table.insert(timing_pairs, { "standard_start_time", nil })
    end

    -- Speedrun killscreen duration
    if speedrun_start_frame and killscreen_frame then
      local dur = killscreen_frame - speedrun_start_frame
      table.insert(timing_pairs, { "speedrun_killscreen_duration_frames", dur })
      table.insert(timing_pairs, { "speedrun_killscreen_time", format_duration(dur) })
    else
      table.insert(timing_pairs, { "speedrun_killscreen_duration_frames", nil })
      table.insert(timing_pairs, { "speedrun_killscreen_time", nil })
    end
  end

  -- Playing time (standard total: start button to game over VRAM, fallback to end_frame)
  if start_frame and game_over_vram_frame then
    local dur = game_over_vram_frame - start_frame
    table.insert(timing_pairs, { "playing_time_frames", dur })
    table.insert(timing_pairs, { "playing_time", format_duration(dur) })
  elseif start_frame and end_frame then
    local dur = end_frame - start_frame
    table.insert(timing_pairs, { "playing_time_frames", dur })
    table.insert(timing_pairs, { "playing_time", format_duration(dur) })
  else
    table.insert(timing_pairs, { "playing_time_frames", nil })
    table.insert(timing_pairs, { "playing_time", nil })
  end

  -- DK3 milestone timing
  if GAME_TYPE == "dkong3" then
    local max_diff_timing = {}
    for _, md in ipairs(dk3_max_diff_milestones) do
      local time_from_start = nil
      if start_frame then
        time_from_start = format_duration(md.frame - start_frame)
      end
      table.insert(
        max_diff_timing,
        json_ordered({
          { "count", md.count },
          { "frame", md.frame },
          { "time_from_start", time_from_start },
        })
      )
    end
    table.insert(timing_pairs, { "max_diff_milestones", max_diff_timing })

    local rbs_timing = {}
    for _, rbs in ipairs(dk3_rbs_milestones) do
      local time_from_start = nil
      if start_frame then
        time_from_start = format_duration(rbs.frame - start_frame)
      end
      table.insert(
        rbs_timing,
        json_ordered({
          { "rbs_num", rbs.rbs_num },
          { "frame", rbs.frame },
          { "time_from_start", time_from_start },
        })
      )
    end
    table.insert(timing_pairs, { "rbs_milestone_timing", rbs_timing })

    local loop_timing = {}
    for _, loop in ipairs(dk3_loop_milestones) do
      local time_from_start = nil
      if start_frame then
        time_from_start = format_duration(loop.frame - start_frame)
      end
      table.insert(
        loop_timing,
        json_ordered({
          { "loop_num", loop.loop_num },
          { "frame", loop.frame },
          { "time_from_start", time_from_start },
        })
      )
    end
    table.insert(timing_pairs, { "loop_milestone_timing", loop_timing })
  end

  local timing_summary = json_ordered(timing_pairs)

  -- SCORE MILESTONES (top-level)
  local milestones_array = {}
  for _, ms in ipairs(score_milestones) do
    local ms_pairs = {
      { "score", ms.score },
      { "frame", ms.frame },
      { "time_from_start", start_frame and format_duration(ms.frame - start_frame) or nil },
    }
    if ms.stage then
      table.insert(ms_pairs, { "stage", ms.stage })
    elseif ms.board then
      table.insert(ms_pairs, { "board", ms.board })
    end
    table.insert(ms_pairs, { "screen_num", ms.screen_num })
    table.insert(ms_pairs, { "bonus_timer", ms.bonus_timer })
    table.insert(ms_pairs, { "during_gameplay", ms.during_gameplay })
    table.insert(milestones_array, json_ordered(ms_pairs))
  end

  -- DEATHS (extracted from stage_data)
  local deaths_array = {}
  for _, stage in ipairs(stage_data) do
    if stage.death then
      local death_pairs = {
        { "death_num", stage.death_num },
        { "frame", stage.frame },
      }
      if GAME_TYPE == "dkong3" then
        table.insert(death_pairs, { "board", stage.board })
        table.insert(death_pairs, { "board_number", stage.level })
      else
        table.insert(death_pairs, { "stage", stage.stage })
        table.insert(death_pairs, { "screen_num", stage.screen_num })
      end
      table.insert(death_pairs, { "screen_type", stage.screen_type })
      table.insert(death_pairs, { "death_points", stage.score_earned })
      table.insert(death_pairs, { "running_total", stage.total_score })
      table.insert(death_pairs, { "lives", stage.lives or 0 })
      table.insert(death_pairs, { "bonus_timer", stage.bonus_timer })
      table.insert(deaths_array, json_ordered(death_pairs))
    end
  end

  -- STAGES (completed stages only: no level totals, no deaths)
  local stages_array = {}
  for _, stage in ipairs(stage_data) do
    if not stage.is_level_total and not stage.death then
      local stage_pairs = {}
      if GAME_TYPE == "dkong3" then
        table.insert(stage_pairs, { "attempt_num", stage.screen_num })
        table.insert(stage_pairs, { "board", stage.board })
        table.insert(stage_pairs, { "board_number", stage.level })
      else
        table.insert(stage_pairs, { "screen_num", stage.screen_num })
        table.insert(stage_pairs, { "stage", stage.stage })
        table.insert(stage_pairs, { "level", stage.level })
      end
      table.insert(stage_pairs, { "screen_type", stage.screen_type })
      table.insert(stage_pairs, { "board_score", stage.score_earned })
      table.insert(stage_pairs, { "running_total", stage.total_score })
      table.insert(stage_pairs, { "lives", stage.lives or 0 })
      table.insert(stage_pairs, { "frame", stage.frame })
      table.insert(stage_pairs, { "bonus_timer", stage.bonus_timer })

      if stage.avg_type then
        table.insert(stage_pairs, { "avg_type", stage.avg_type })
        table.insert(stage_pairs, { "avg_value", stage.avg_value })
      end

      if stage.pace then
        table.insert(stage_pairs, { "pace", stage.pace })
        if stage.pace_22_4 then
          table.insert(stage_pairs, { "pace_22_4", stage.pace_22_4 })
        end
      end

      table.insert(stages_array, json_ordered(stage_pairs))
    end
  end

  -- ASSEMBLE AND WRITE
  local root = json_ordered({
    { "metadata", metadata },
    { "scoring_summary", scoring_summary },
    { "timing_summary", timing_summary },
    { "score_milestones", milestones_array },
    { "deaths", deaths_array },
    { "stages", stages_array },
  })

  file:write(to_json(root, 0))
  file:write("\n")

  file:close()
  print(string.format("[OK] JSON exported to: %s", JSON_FILE))
end

-- ============================================================================
-- TEXT EXPORT
-- ============================================================================

-- Helper: compute playing time frames (start button to game over VRAM, fallback to end_frame)
local function get_playing_time_frames()
  if start_frame and game_over_vram_frame then
    return game_over_vram_frame - start_frame
  elseif start_frame and end_frame then
    return end_frame - start_frame
  end
  return nil
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

    -- HEADER
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("Variation: %s\n", game_variation or ""))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))
    file:write(string.format("MAME version: %s\n", detect_mame_version()))
    file:write(string.format("BLOSSOM version: %s\n", BLOSSOM_VERSION))

    -- SCORING SUMMARY
    file:write("\nSCORING SUMMARY\n")
    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_board ~= "" then
      file:write(string.format("Final Board: %s\n", final_board))
    end
    file:write(string.format("Recorded Deaths: %d\n", death_count))
    file:write(string.format("Total Death Points: %s\n", format_number(total_death_points)))

    -- RBS milestones (score data)
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

    -- Loop milestones (score data)
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

    -- Screen type averages (max difficulty only)
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
      file:write("\n")

      if game_variation and not game_variation:match("5 Lives") then
        file:write(
          string.format("Recorded Lives (starting + earned): %d\n", life_stats.total_lives)
        )
      end

      file:write(
        string.format("First Life Score: %s\n", format_number(life_stats.first_life_score))
      )

      if life_stats.five_lives_score and game_variation and not game_variation:match("5 Lives") then
        file:write(string.format("5 Lives Score: %s\n", format_number(life_stats.five_lives_score)))
      end

      file:write(string.format("Last Life Score: %s\n", format_number(life_stats.last_life_score)))

      local longest_points_str = "#"
        .. table.concat(life_stats.longest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (points): %s - %s\n",
          longest_points_str,
          format_number(life_stats.longest_life_points.score)
        )
      )

      local longest_boards_str = "#"
        .. table.concat(life_stats.longest_life_boards.life_nums, ", #")
      file:write(
        string.format(
          "Longest Life (boards): %s - %d\n",
          longest_boards_str,
          life_stats.longest_life_boards.boards
        )
      )

      local shortest_points_str = "#"
        .. table.concat(life_stats.shortest_life_points.life_nums, ", #")
      file:write(
        string.format(
          "Shortest Life (points): %s - %s\n",
          shortest_points_str,
          format_number(life_stats.shortest_life_points.score)
        )
      )

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

    -- TIMING SUMMARY
    file:write("\nTIMING SUMMARY\n")

    local playing_frames = get_playing_time_frames()
    if playing_frames then
      file:write(string.format("Unofficial Playing Time: %s\n", format_duration(playing_frames)))
    end

    -- DK3 milestone timing
    for _, md in ipairs(dk3_max_diff_milestones) do
      local time_str = ""
      if start_frame then
        time_str = string.format(" (%s)", format_duration(md.frame - start_frame))
      end
      file:write(
        string.format(
          "Max Difficulty %d: Frame %s%s\n",
          md.count,
          format_number(md.frame),
          time_str
        )
      )
    end

    for _, rbs in ipairs(dk3_rbs_milestones) do
      local time_str = ""
      if start_frame then
        time_str = string.format(" (%s)", format_duration(rbs.frame - start_frame))
      end
      file:write(
        string.format("RBS %d: Frame %s%s\n", rbs.rbs_num, format_number(rbs.frame), time_str)
      )
    end

    for _, loop in ipairs(dk3_loop_milestones) do
      local time_str = ""
      if start_frame then
        time_str = string.format(" (%s)", format_duration(loop.frame - start_frame))
      end
      file:write(
        string.format(
          "Loop %d Complete: Frame %s%s\n",
          loop.loop_num,
          format_number(loop.frame),
          time_str
        )
      )
    end

    -- Full game frame range
    if start_frame and (game_over_vram_frame or end_frame) then
      local end_f = game_over_vram_frame or end_frame
      local dur = end_f - start_frame
      file:write(
        string.format(
          "Full Game: Frame %s - %s (%s frames)\n",
          format_number(start_frame),
          format_number(end_f),
          format_number(dur)
        )
      )
    end

    -- SCORE MILESTONES
    if #score_milestones > 0 then
      file:write("\nSCORE MILESTONES\n")
      for _, ms in ipairs(score_milestones) do
        local time_str = ""
        if start_frame then
          time_str = string.format(" - %s", format_duration(ms.frame - start_frame))
        end
        local board_str = ms.board and string.format(" | Board %d", ms.board) or ""
        local timer_str = ms.bonus_timer
            and string.format(" | Timer: %s", format_number(ms.bonus_timer))
          or ""
        local phase_str = ""
        if ms.during_gameplay == false then
          phase_str = " [stage end]"
        end
        file:write(
          string.format(
            "%s (Frame %s%s)%s%s%s\n",
            format_number(ms.score),
            format_number(ms.frame),
            time_str,
            board_str,
            timer_str,
            phase_str
          )
        )
      end
    end

    file:write("\n===================================\n\nSTAGE DATA\n")

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

    -- HEADER
    file:write("=== BLOSSOM SCORE LOG ===\n")
    file:write(string.format("Game: %s\n", config.full_name))
    file:write(string.format("romset: %s\n", config.romset))
    file:write(string.format("INP file: %s\n", get_inp_filename()))
    file:write(string.format("MAME version: %s\n", detect_mame_version()))
    file:write(string.format("BLOSSOM version: %s\n", BLOSSOM_VERSION))

    -- SCORING SUMMARY
    file:write("\nSCORING SUMMARY\n")
    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_stage ~= "" then
      file:write(string.format("Final Stage: %s\n", final_stage))
    end
    file:write(string.format("Total Screens: %d\n", current_screen_num))
    file:write(string.format("Recorded Deaths: %d\n", death_count))
    file:write(string.format("Total Death Points: %s\n", format_number(total_death_points)))

    -- Pace
    if final_level and last_pace then
      if config.supports_22_4_pace then
        if
          final_level == 22
          and final_stage_position
          and final_stage_position >= 1
          and final_stage_position <= 3
        then
          if last_pace_22_4 then
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        elseif final_level < 22 then
          file:write(string.format("22-1 Pace: %s\n", format_number(last_pace)))
          if last_pace_22_4 then
            file:write(string.format("22-4 Pace: %s\n", format_number(last_pace_22_4)))
          end
        end
      else
        if final_level < 22 then
          file:write(string.format("Pace: %s\n", format_number(last_pace)))
        end
      end
    end

    -- Start score
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

    -- Screen type averages
    local display_order
    if GAME_TYPE == "dkongjr" then
      display_order = { 2, 1, 3, 4 }
    else
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

    -- TIMING SUMMARY
    file:write("\nTIMING SUMMARY\n")

    -- Unofficial times (guaranteed: playing time; conditional: start, killscreen)
    local playing_frames = get_playing_time_frames()
    if playing_frames then
      file:write(string.format("Unofficial Playing Time: %s\n", format_duration(playing_frames)))
    end

    if speedrun_start_frame and speedrun_end_frame then
      local dur = speedrun_end_frame - speedrun_start_frame
      file:write(string.format("Unofficial Speedrun Start Time: %s\n", format_duration(dur)))
    end

    if start_frame and start_phase_end_frame then
      local dur = start_phase_end_frame - start_frame
      file:write(string.format("Unofficial Standard Start Time: %s\n", format_duration(dur)))
    end

    if speedrun_start_frame and killscreen_frame then
      local dur = killscreen_frame - speedrun_start_frame
      file:write(string.format("Unofficial Speedrun Killscreen Time: %s\n", format_duration(dur)))
    end

    -- Frame ranges
    file:write("\n")

    if start_frame and (game_over_vram_frame or end_frame) then
      local end_f = game_over_vram_frame or end_frame
      local dur = end_f - start_frame
      file:write(
        string.format(
          "Full Game: Frame %s - %s (%s frames)\n",
          format_number(start_frame),
          format_number(end_f),
          format_number(dur)
        )
      )
    end

    if speedrun_start_frame and speedrun_end_frame then
      local dur = speedrun_end_frame - speedrun_start_frame
      file:write(
        string.format(
          "Speedrun Start: Frame %s - %s (%s frames)\n",
          format_number(speedrun_start_frame),
          format_number(speedrun_end_frame),
          format_number(dur)
        )
      )
    end

    if start_frame and start_phase_end_frame then
      local dur = start_phase_end_frame - start_frame
      file:write(
        string.format(
          "Standard Start: Frame %s - %s (%s frames)\n",
          format_number(start_frame),
          format_number(start_phase_end_frame),
          format_number(dur)
        )
      )
    end

    if speedrun_start_frame and killscreen_frame then
      local dur = killscreen_frame - speedrun_start_frame
      file:write(
        string.format(
          "Speedrun Killscreen: Frame %s - %s (%s frames)\n",
          format_number(speedrun_start_frame),
          format_number(killscreen_frame),
          format_number(dur)
        )
      )
    end

    -- SCORE MILESTONES
    if #score_milestones > 0 then
      file:write("\nSCORE MILESTONES\n")
      for _, ms in ipairs(score_milestones) do
        local time_str = ""
        if start_frame then
          time_str = string.format(" - %s", format_duration(ms.frame - start_frame))
        end
        local stage_str = ms.stage and string.format(" | %s", ms.stage) or ""
        local timer_str = ms.bonus_timer
            and string.format(" | Timer: %s", format_number(ms.bonus_timer))
          or ""
        local phase_str = ""
        if ms.during_gameplay == false then
          phase_str = " [stage end]"
        end
        file:write(
          string.format(
            "%s (Frame %s%s)%s%s%s\n",
            format_number(ms.score),
            format_number(ms.frame),
            time_str,
            stage_str,
            timer_str,
            phase_str
          )
        )
      end
    end

    file:write("\n===================================\n\nSTAGE DATA\n")

    -- Per-stage data (unchanged from current format)
    local current_output_level = nil

    for _, stage in ipairs(stage_data) do
      if stage.is_level_total then
        local level_display = format_level_for_display(stage.level)
        file:write(string.format("L%s: %s\n", level_display, format_number(stage.score_earned)))
        file:write("---\n")
        current_output_level = stage.level
      else
        if stage.death then
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
          local stage_line = string.format(
            "%s: %s --> %s",
            stage.stage,
            format_number(stage.score_earned),
            format_number(stage.total_score)
          )

          if stage.avg_type and stage.avg_value then
            stage_line = stage_line
              .. string.format(" | %s: %s", stage.avg_type, format_number_decimal(stage.avg_value))
          end

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
