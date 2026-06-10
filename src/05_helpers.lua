-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- GAME CONFIG HELPERS
-- Get current game config
local function get_config()
  return GAME_CONFIGS[GAME_TYPE]
end

-- Get screen name based on game type
local function get_screen_type_name(screen_type)
  local config = get_config()
  return config.screen_names[screen_type] or "Unknown"
end

-- MEMORY HELPERS
-- Read single byte from memory
local function read_byte(address)
  local mem = mame_devices[":maincpu"].spaces["program"]
  local ok, val = pcall(function()
    return mem:read_u8(address)
  end)
  if not ok then
    return 0 -- Return 0 if read fails
  end
  return val
end

-- Read player 1 score from memory (3 bytes BCD = 6 digits)
local function read_score()
  local config = GAME_CONFIGS[GAME_TYPE]
  local mem = mame_devices[":maincpu"].spaces["program"]

  local ok1, byte1 = pcall(function()
    return mem:read_u8(config.addresses.score_1)
  end)
  local ok2, byte2 = pcall(function()
    return mem:read_u8(config.addresses.score_2)
  end)
  local ok3, byte3 = pcall(function()
    return mem:read_u8(config.addresses.score_3)
  end)

  if not (ok1 and ok2 and ok3) then
    return 0
  end

  -- DK3 has different byte order (upper, middle, lower)
  local score_string
  if GAME_TYPE == "dkong3" then
    score_string = string.format("%02X%02X%02X", byte1, byte2, byte3)
  else
    score_string = string.format("%02X%02X%02X", byte3, byte2, byte1)
  end

  return tonumber(score_string, 10)
end

-- Get adjusted score accounting for million-point rollovers
local function get_adjusted_score(raw_score)
  return raw_score + score_offset
end

-- Read and check for rollover - call this instead of read_score when logging data
local function read_score_with_rollover_check()
  local raw_score = read_score()

  -- Detect score rollover from 999900 to 000000 (million+ points)
  -- Compare raw scores to detect the transition, not adjusted scores
  if prev_raw_score > 900000 and raw_score < 100000 then
    score_offset = score_offset + 1000000
  end

  prev_raw_score = raw_score
  return get_adjusted_score(raw_score)
end

-- Check if a button is pressed (handles both ACTIVE HIGH and ACTIVE LOW polarity)
local function check_button_pressed(address, bit_position, active_high)
  local value = read_byte(address)

  -- Extract the specific bit using math (no bitwise operators needed - MAME compatible)
  -- Divide by 2^bit_position and check if result is odd
  local shifted = math.floor(value / (2 ^ bit_position))
  local bit_set = (shifted % 2) == 1

  if active_high then
    return bit_set -- Button pressed when bit is 1 (dkong, dkongjr, dkong3)
  else
    return not bit_set -- Button pressed when bit is 0 (ckongpt2 only)
  end
end

-- Read the bonus timer value, handling encoding differences between games
-- DK/DKJR/CK: plain binary at 0x62B1 (value 50 = timer 5000)
-- DK3: BCD at 0x68C2 (value 0x79 = timer 7900)
local function read_bonus_timer()
  local config = get_config()
  local raw = read_byte(config.addresses.bonus_timer)

  if config.bonus_timer_bcd then
    -- BCD decode: each nibble is a decimal digit
    local high = math.floor(raw / 16)
    local low = raw % 16
    return (high * 10 + low) * 100
  else
    -- Plain binary: multiply directly
    return raw * 100
  end
end

-- Format frame count as H:MM:SS.mmm playing time (rounded to nearest millisecond)
local function format_duration(frames)
  if not frames or frames < 0 then
    return "0:00:00.000"
  end

  local config = get_config()
  local total_ms = math.floor((frames / config.frame_rate) * 1000 + 0.5)
  local ms = total_ms % 1000
  local total_secs = math.floor(total_ms / 1000)
  local hours = math.floor(total_secs / 3600)
  local minutes = math.floor((total_secs % 3600) / 60)
  local secs = total_secs % 60

  return string.format("%d:%02d:%02d.%03d", hours, minutes, secs, ms)
end

-- FORMATTING HELPERS
-- Format number with commas (e.g., 12345 -> "12,345")
local function format_number(num)
  local formatted = tostring(num)
  local k
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

-- Format decimal number with commas (e.g., 12345.67 -> "12,345.67")
local function format_number_decimal(num)
  local integer_part = math.floor(num)
  local decimal_part = num - integer_part
  local formatted_int = format_number(integer_part)
  return string.format("%s.%02d", formatted_int, math.floor(decimal_part * 100 + 0.5))
end

-- Format level number for display (handles DKJR display bug)
local function format_level_for_display(level)
  local config = get_config()

  if config.level_display_bug then
    if level >= 10 and level <= 16 then
      return string.format("[%d]", level)
    elseif level >= 17 and level <= 21 then
      return string.char(65 + (level - 17)) -- A-F
    else
      return tostring(level)
    end
  else
    return tostring(level)
  end
end

-- Format stage name as 'level-position' (uses format_level_for_display for level portion)
local function get_stage_name(level, position)
  local level_display = format_level_for_display(level)
  return string.format("%s-%d", level_display, position)
end

-- PACE HELPERS
-- Calculate base pace for each game
local function calculate_pace(lives_remaining)
  if not can_calculate_pace then
    return nil
  end

  local config = get_config()

  -- Check if we have all required screen type averages
  for i = 1, 4 do
    if screen_count[i] == 0 then
      return nil
    end
  end

  -- Calculate averages for each screen type
  local screen_avg = {}
  for i = 1, 4 do
    screen_avg[i] = screen_sum[i] / screen_count[i]
  end

  -- Calculate estimated death points
  local estimated_death_points
  if death_count == 0 then
    estimated_death_points = lives_remaining * config.death_point_value
  else
    estimated_death_points = total_death_points + (lives_remaining * config.death_point_value)
  end

  -- Now calculate pace
  local pace

  -- Pace formulas:
  --   DK:    start + (((barrel_avg * 3) + pie_avg + spring_avg + rivet_avg) * 17) + deaths
  --   DKJR:  start + ((jungle_avg + spring_avg + hideout_avg + chain_avg) * 18) + deaths
  --   CK:    start + ((barrel_avg + pie_avg + spring_avg + rivet_avg) * 17) + deaths

  if GAME_TYPE == "dkong" then
    pace = start_score_for_pace
      + (((screen_avg[1] * 3) + screen_avg[2] + screen_avg[3] + screen_avg[4]) * 17)
      + estimated_death_points
  elseif GAME_TYPE == "dkongjr" then
    -- Memory mapping: 1=Spring, 2=Jungle, 3=Chain, 4=Hideout
    pace = start_score_for_pace
      + ((screen_avg[2] + screen_avg[1] + screen_avg[4] + screen_avg[3]) * 18)
      + estimated_death_points
  elseif GAME_TYPE == "ckongpt2" then
    pace = start_score_for_pace
      + ((screen_avg[1] + screen_avg[2] + screen_avg[3] + screen_avg[4]) * 17)
      + estimated_death_points
  end

  -- Round to nearest 100
  return math.floor(pace / 100 + 0.5) * 100
end

-- Calculate extended pace for CK
local function calculate_22_4_pace(base_pace, lives_remaining)
  local config = get_config()
  if not config.supports_22_4_pace or not base_pace then
    return nil
  end
  return base_pace + 13700 + (lives_remaining * 1500)
end
