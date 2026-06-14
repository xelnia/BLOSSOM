-- Record a DK3 board result
local function record_board_dk3(
  actual_board,
  memory_board,
  screen_num,
  score_earned,
  total_score,
  is_death,
  death_num,
  lives_remaining,
  screen_type,
  bonus_timer
)
  local board_info = {
    screen_num = screen_num,
    board = get_board_name_dk3(actual_board, memory_board, s.dk3_current_loop),
    screen_type = get_screen_type_name(screen_type),
    level = actual_board,
    score_earned = score_earned,
    total_score = total_score,
    death = is_death,
    death_num = death_num,
    is_level_total = false,
    frame = frame_count,
    lives = lives_remaining,
    avg_type = nil,
    avg_value = nil,
    bonus_timer = bonus_timer,
  }

  table.insert(s.stage_data, board_info)

  local config = get_config()

  -- Track averages (only for completed boards, not deaths, and only during max difficulty)
  local avg_str = ""
  if not is_death and s.dk3_max_diff_reached then
    -- Skip Board 0 (256, 512, etc.) - these are Blue boards not included in averages
    local memory_board_check = actual_board % config.loop_size
    if memory_board_check ~= 0 then
      local avg_value = nil
      local avg_type = nil

      -- Update sum and count for this screen type (0, 1, or 2)
      if screen_type >= 0 and screen_type <= 2 then
        local idx = screen_type + 1 -- Lua arrays are 1-indexed
        s.dk3_screen_sum[idx] = s.dk3_screen_sum[idx] + score_earned
        s.dk3_screen_count[idx] = s.dk3_screen_count[idx] + 1
        avg_value = s.dk3_screen_sum[idx] / s.dk3_screen_count[idx]
        avg_type = get_screen_type_name(screen_type) .. " Avg"
      end

      -- Store in board_info and format for console
      if avg_value then
        board_info.avg_type = avg_type
        board_info.avg_value = avg_value
        avg_str = string.format(" | %s: %s", avg_type, format_number_decimal(avg_value))
      end
    end
  end

  -- Console output
  if is_death then
    local timer_str = bonus_timer and string.format(" | Timer: %s", format_number(bonus_timer))
      or ""
    print(
      string.format(
        "*** Death #%d - Board %s [%s] *** | Death Points: %s | Total Score: %s | Lives: %d%s",
        death_num,
        board_info.board,
        board_info.screen_type,
        format_number(score_earned),
        format_number(total_score),
        lives_remaining,
        timer_str
      )
    )
  else
    print(
      string.format(
        "Board %s [%s] Complete | Board Score: %s | Total Score: %s | Lives: %d%s",
        board_info.board,
        board_info.screen_type,
        format_number(score_earned),
        format_number(total_score),
        lives_remaining,
        avg_str
      )
    )
  end

  -- Check for MAX DIFFICULTY reached (completing board before max_diff_board triggers the message)
  if not is_death then
    local memory_board_check = actual_board % config.loop_size
    if memory_board_check == config.max_diff_board - 1 then
      s.dk3_max_diff_count = s.dk3_max_diff_count + 1
      s.dk3_max_diff_reached = true
      local start_phase_score = total_score - s.dk3_loop_start_score

      -- Store milestone data (parallel to RBS/loop milestones)
      table.insert(s.dk3_max_diff_milestones, {
        count = s.dk3_max_diff_count,
        total_score = total_score,
        start_phase_score = start_phase_score,
        frame = frame_count,
        lives = lives_remaining,
      })

      print(
        string.format(
          "\n>>> MAX DIFFICULTY REACHED <<< | Start Phase %d Score: %s | Total Score: %s | Lives: %d\n",
          s.dk3_max_diff_count,
          format_number(start_phase_score),
          format_number(total_score),
          lives_remaining
        )
      )
    end
  end

  -- Check for RBS milestone (completing board before rbs_milestone, then every 256 boards)
  local rbs_trigger = config.rbs_milestone - 1
  if
    not is_death
    and (
      actual_board == rbs_trigger
      or (actual_board > rbs_trigger and (actual_board - rbs_trigger) % config.loop_size == 0)
    )
  then
    s.dk3_rbs_count = s.dk3_rbs_count + 1
    local rbs_score = total_score - s.dk3_loop_start_score

    -- Store milestone data
    table.insert(s.dk3_rbs_milestones, {
      rbs_num = s.dk3_rbs_count,
      total_score = total_score,
      rbs_score = rbs_score,
      frame = frame_count,
      lives = lives_remaining,
    })

    print(
      string.format(
        "\n>>> REPETITIVE BLUE SCREEN %d REACHED <<< | RBS %d Score: %s | Total Score: %s | Lives: %d\n",
        s.dk3_rbs_count,
        s.dk3_rbs_count,
        format_number(rbs_score),
        format_number(total_score),
        lives_remaining
      )
    )
  end

  -- Check for loop completion (every loop_size boards = memory board 0)
  if not is_death and actual_board % config.loop_size == 0 and actual_board > 0 then
    local loop_num = actual_board / config.loop_size -- Which loop just completed (1, 2, 3, etc.)
    local loop_score = total_score - s.dk3_loop_start_score

    -- Store milestone data
    table.insert(s.dk3_loop_milestones, {
      loop_num = loop_num,
      total_score = total_score,
      loop_score = loop_score,
      frame = frame_count,
      lives = lives_remaining,
    })

    print(
      string.format(
        "\n>>> LOOP %d COMPLETE | LOOP %d Score: %s | Total Score: %s | Lives: %d <<<\n",
        loop_num,
        loop_num,
        format_number(loop_score),
        format_number(total_score),
        lives_remaining
      )
    )

    -- Pause average tracking for next loop's start phase
    s.dk3_max_diff_reached = false
  end
end

-- Record a stage result
local function record_stage(
  screen_type,
  level,
  position,
  screen_num,
  score_earned,
  total_score,
  is_death,
  death_num,
  lives_remaining,
  bonus_timer
)
  local stage_info = {
    screen_num = screen_num,
    stage = get_stage_name(level, position),
    screen_type = get_screen_type_name(screen_type),
    level = level,
    score_earned = score_earned,
    total_score = total_score,
    death = is_death,
    death_num = death_num,
    is_level_total = false,
    frame = frame_count,
    avg_type = nil, -- Will store "Barrel Avg", "Pie Avg", etc.
    avg_value = nil, -- Will store the calculated average
    pace = nil, -- Will store the calculated pace
    pace_22_4 = nil, -- Will store the 22-4 extended pace (ckongpt2 only)
    bonus_timer = bonus_timer,
    lives = lives_remaining,
  }

  table.insert(s.stage_data, stage_info)

  -- Track start phase scores and deaths
  local config = get_config()
  if s.start_score_total == 0 then -- Still in start phase
    if is_death then
      -- Track deaths during start phase
      s.start_phase_deaths = s.start_phase_deaths + 1
      s.start_phase_death_points = s.start_phase_death_points + score_earned
    else
      -- Accumulate stage scores during start phase
      s.start_score_for_pace = s.start_score_for_pace + score_earned

      -- Check if this completes the start phase
      if level == config.start_level and position == config.start_stage then
        s.start_score_total = total_score
      end
    end
  end

  -- Track averages (only for completed stages, not deaths)
  local avg_str = ""
  if not is_death and level >= config.begin_avg and level <= 21 then
    local avg_value = nil
    local avg_type = nil

    -- Update sum and count for this screen type
    if screen_type >= 1 and screen_type <= 4 then
      s.screen_sum[screen_type] = s.screen_sum[screen_type] + score_earned
      s.screen_count[screen_type] = s.screen_count[screen_type] + 1
      avg_value = s.screen_sum[screen_type] / s.screen_count[screen_type]
      avg_type = get_screen_type_name(screen_type) .. " Avg"
    end

    -- Store in stage_info and format for console
    if avg_value then
      stage_info.avg_type = avg_type
      stage_info.avg_value = avg_value
      avg_str = string.format(" | %s: %s", avg_type, format_number_decimal(avg_value))
    end

    -- Check if we can enable pace calculation
    if
      level > config.begin_pace_level
      or (level == config.begin_pace_level and position >= config.begin_pace_stage)
    then
      local all_screens_seen = true
      for i = 1, 4 do
        if s.screen_count[i] == 0 then
          all_screens_seen = false
          break
        end
      end
      if all_screens_seen then
        s.can_calculate_pace = true
      end
    end
  end

  -- Track individual scores for best/worst analysis (only for completed stages, not deaths)
  if not is_death and level >= config.begin_avg and level <= 21 then
    local level_display = format_level_for_display(level)

    -- Determine the display label for this stage
    local stage_label
    if screen_type == 1 and config.barrel_multiplier == 3 then
      -- DK Barrels appear 3x per level - show stage position
      stage_label = get_stage_name(level, position)
    else
      -- All other screens appear 1x per level - show level only
      stage_label = string.format("L%s", level_display)
    end

    -- Store score in appropriate screen type array
    if screen_type >= 1 and screen_type <= 4 then
      table.insert(
        s.screen_scores[screen_type],
        { score = score_earned, label = stage_label, level = level }
      )
    end
  end

  -- Calculate pace (only for completed stages, not deaths)
  local pace_str = ""
  if not is_death then
    local pace = calculate_pace(lives_remaining)
    if pace then
      -- Store pace in stage_info for text file output
      stage_info.pace = pace
      s.last_pace = pace

      -- Check if we should show extended pace (ckongpt2 only)
      local pace_22_4 = calculate_22_4_pace(pace, lives_remaining)
      if pace_22_4 then
        stage_info.pace_22_4 = pace_22_4
        s.last_pace_22_4 = pace_22_4

        -- On 22-1->22-3: show only 22-4 pace
        if level == 22 and position >= 1 and position <= 3 then
          pace_str = string.format(" | 22-4 Pace: %s", format_number(pace_22_4))
        else
          -- Before 22-1: show both paces
          pace_str = string.format(
            " | 22-1 Pace: %s | 22-4 Pace: %s",
            format_number(pace),
            format_number(pace_22_4)
          )
        end
      else
        pace_str = string.format(" | Pace: %s", format_number(pace))
      end
    end
  end

  -- Clean console output
  if is_death then
    local timer_str = bonus_timer and string.format(" | Timer: %s", format_number(bonus_timer))
      or ""
    print(
      string.format(
        "*** Death #%d - Stage %s *** | Death Points: %s | Total Score: %s%s",
        death_num,
        stage_info.stage,
        format_number(score_earned),
        format_number(total_score),
        timer_str
      )
    )
  else
    print(
      string.format(
        "Stage %s Complete | Stage Score: %s | Total Score: %s%s%s",
        stage_info.stage,
        format_number(score_earned),
        format_number(total_score),
        avg_str,
        pace_str
      )
    )
  end
end

-- Record a level total
local function record_level_total(level, score_earned, total_score)
  local level_display = format_level_for_display(level)
  local level_info = {
    screen_num = "",
    stage = string.format("Level %s Total", level_display),
    screen_type = "",
    level = level,
    score_earned = score_earned,
    total_score = total_score,
    death = false,
    death_num = nil,
    is_level_total = true,
    frame = frame_count,
  }

  table.insert(s.stage_data, level_info)

  -- Track L5-L21 level averages
  local avg_str = ""
  local config = get_config()
  if level >= config.begin_avg and level <= 21 then
    s.level_sum = s.level_sum + score_earned
    s.level_count = s.level_count + 1
    avg_str = string.format(" | Level Avg: %s", format_number_decimal(s.level_sum / s.level_count))
  end

  -- Track level scores for best/worst analysis
  local config = get_config()
  if level >= config.begin_avg and level <= 21 then
    local level_display = format_level_for_display(level)
    table.insert(
      s.level_scores,
      { score = score_earned, label = string.format("L%s", level_display), level = level }
    )
  end

  print(
    string.format(
      "\n>>> LEVEL %s COMPLETE | Level Score: %s | Total Score: %s%s <<<\n",
      level_display,
      format_number(score_earned),
      format_number(total_score),
      avg_str
    )
  )
end

-- Helper to find best and worst scores with tie handling
local function find_best_worst(scores_array)
  if #scores_array == 0 then
    return nil, nil, nil, nil -- best_score, best_labels, worst_score, worst_labels
  end

  -- Find best (max) score
  local best_score = scores_array[1].score
  for _, entry in ipairs(scores_array) do
    if entry.score > best_score then
      best_score = entry.score
    end
  end

  -- Find worst (min) score
  local worst_score = scores_array[1].score
  for _, entry in ipairs(scores_array) do
    if entry.score < worst_score then
      worst_score = entry.score
    end
  end

  -- Collect all labels that match best score
  local best_labels = {}
  for _, entry in ipairs(scores_array) do
    if entry.score == best_score then
      table.insert(best_labels, entry.label)
    end
  end

  -- Collect all labels that match worst score
  local worst_labels = {}
  for _, entry in ipairs(scores_array) do
    if entry.score == worst_score then
      table.insert(worst_labels, entry.label)
    end
  end

  -- Join labels with comma-space
  local best_str = table.concat(best_labels, ", ")
  local worst_str = table.concat(worst_labels, ", ")

  return best_score, best_str, worst_score, worst_str
end

-- Calculate DK3 life statistics
local function calculate_dk3_life_stats()
  if #s.dk3_life_tracking == 0 then
    return nil -- No deaths yet
  end

  local stats = {
    total_lives = #s.dk3_life_tracking,
    first_life_score = s.dk3_life_tracking[1].end_score - s.dk3_life_tracking[1].start_score,
    last_life_score = 0,
    five_lives_score = nil,
    longest_life_points = { score = 0, life_nums = {} },
    longest_life_boards = { boards = 0, life_nums = {} },
    shortest_life_points = { score = math.huge, life_nums = {} },
    shortest_life_boards = { boards = math.huge, life_nums = {} },
    avg_points = 0,
    avg_boards = 0,
  }

  -- Calculate last life score
  local last_life = s.dk3_life_tracking[#s.dk3_life_tracking]
  stats.last_life_score = last_life.end_score - last_life.start_score

  -- Calculate 5 lives score (score at 5th death)
  if #s.dk3_life_tracking >= 5 then
    stats.five_lives_score = s.dk3_life_tracking[5].end_score
  end

  -- Find longest/shortest lives and calculate totals
  local total_points = 0
  local total_boards = 0

  for _, life in ipairs(s.dk3_life_tracking) do
    local life_points = life.end_score - life.start_score
    local life_boards = life.boards_completed

    total_points = total_points + life_points
    total_boards = total_boards + life_boards

    -- Longest by points
    if life_points > stats.longest_life_points.score then
      stats.longest_life_points.score = life_points
      stats.longest_life_points.life_nums = { life.life_num }
    elseif life_points == stats.longest_life_points.score then
      table.insert(stats.longest_life_points.life_nums, life.life_num)
    end

    -- Longest by boards
    if life_boards > stats.longest_life_boards.boards then
      stats.longest_life_boards.boards = life_boards
      stats.longest_life_boards.life_nums = { life.life_num }
    elseif life_boards == stats.longest_life_boards.boards then
      table.insert(stats.longest_life_boards.life_nums, life.life_num)
    end

    -- Shortest by points
    if life_points < stats.shortest_life_points.score then
      stats.shortest_life_points.score = life_points
      stats.shortest_life_points.life_nums = { life.life_num }
    elseif life_points == stats.shortest_life_points.score then
      table.insert(stats.shortest_life_points.life_nums, life.life_num)
    end

    -- Shortest by boards
    if life_boards < stats.shortest_life_boards.boards then
      stats.shortest_life_boards.boards = life_boards
      stats.shortest_life_boards.life_nums = { life.life_num }
    elseif life_boards == stats.shortest_life_boards.boards then
      table.insert(stats.shortest_life_boards.life_nums, life.life_num)
    end
  end

  -- Calculate averages
  stats.avg_points = total_points / stats.total_lives
  stats.avg_boards = total_boards / stats.total_lives

  return stats
end
