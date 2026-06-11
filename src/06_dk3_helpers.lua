-- ============================================================================
-- DK3 HELPER FUNCTIONS
-- ============================================================================

-- Get board name with loop information for DK3
local function get_board_name_dk3(actual_board, memory_board, loop_num)
  if actual_board <= 255 then
    return string.format("%d", actual_board)
  elseif actual_board == 256 then
    return string.format("256 (Board 0)")
  else
    if memory_board == 0 then
      return string.format("%d (Loop %d: Board 256/0)", actual_board, loop_num)
    else
      return string.format("%d (Loop %d: Board %d)", actual_board, loop_num, memory_board)
    end
  end
end

-- Detect DK3 game variation from DIP switches
local function detect_variation_dk3()
  local config = get_config()
  local dip_value = read_byte(config.addresses.dip_switches)

  local variations = {
    [0x00] = "Difficulty 1 - Marathon",
    [0x3E] = "Difficulty 1 - 5 Lives",
    [0x40] = "Difficulty 2 - Marathon",
    [0x7E] = "Difficulty 2 - 5 Lives",
    [0x80] = "Difficulty 3 - Marathon",
    [0xBE] = "Difficulty 3 - 5 Lives",
    [0xC0] = "Difficulty 4 - Marathon",
    [0xFE] = "Difficulty 4 - 5 Lives",
  }

  if variations[dip_value] then
    return variations[dip_value]
  else
    -- Decode custom settings
    local lives_map = { [0] = "3", [1] = "4", [2] = "5", [3] = "6" }
    local bonus_map = { [0] = "30k", [1] = "40k", [2] = "50k", [3] = "None" }
    local diff_map = { [0] = "1", [1] = "2", [2] = "3", [3] = "4" }

    local lives = lives_map[dip_value % 4]
    local bonus = bonus_map[math.floor(dip_value / 4) % 4]
    local extra = bonus_map[math.floor(dip_value / 16) % 4]
    local diff = diff_map[math.floor(dip_value / 64)]

    return string.format(
      "Custom: %s Starting Lives, %s Bonus Life, %s Additional Bonus, Difficulty %s (0x%02X)",
      lives,
      bonus,
      extra,
      diff,
      dip_value
    )
  end
end
