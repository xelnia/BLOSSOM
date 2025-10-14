-- BLOSSOM
-- Basic Logging Of Scoring Statistics Originating (in) MAME

-- Tracks stage-by-stage scoring during INP playback
-- Supported games: dkong, dkongjr, ckongpt2
-- Supported MAME versions: 0.175+
-- Exports scoring data and summary in CSV, JSON, and TXT format

-- MEMORY ADDRESSES
local ADDR_GAME_MODE = 0x600A
local ADDR_SCORE_P1_1 = 0x60B2 -- lower digits
local ADDR_SCORE_P1_2 = 0x60B3 -- middle digits
local ADDR_SCORE_P1_3 = 0x60B4 -- upper digits
local ADDR_SCREEN_TYPE = 0x6227
local ADDR_LIVES = 0x6228
local ADDR_LEVEL = 0x6229

-- GAME MODE VALUES
local MODE_TRANSITION = 0x0A
local MODE_GAMEPLAY = 0x0C
local MODE_DEAD = 0x0D
local MODE_GAME_OVER = 0x10

-- MAME VERSION COMPATIBILITY LAYER

-- Check minimum version requirements (MAME 0.175+)
if not manager then
    error("ERROR: This script requires MAME 0.175 or newer.\n" ..
          "The 'manager' Lua API is not available in your MAME version.\n" ..
          "Please upgrade to MAME 0.175 or later.")
end

if not emu.register_frame_done and not emu.add_machine_frame_notifier then
    error("ERROR: This script requires MAME 0.175 or newer.\n" ..
          "Frame callback APIs (emu.register_frame_done or emu.add_machine_frame_notifier) are not available.\n" ..
          "Please upgrade to MAME 0.175 or later.")
end

local mame_machine
local mame_options
local mame_devices

-- Detect if manager.machine is a property or method
if type(manager.machine) == "userdata" then
    -- Modern MAME (0.227+): manager.machine is a property
    mame_machine = manager.machine
elseif type(manager.machine) == "function" then
    -- Older MAME (0.175-0.226): manager:machine() is a method
    mame_machine = manager:machine()
else
    error("ERROR: Cannot access MAME machine object. Incompatible MAME version.")
end

-- Detect if machine.options is a property or method
if type(mame_machine.options) == "userdata" then
    -- Modern MAME (0.227+): options is a property
    mame_options = mame_machine.options
elseif type(mame_machine.options) == "function" then
    -- Older MAME (0.175-0.226): options is a method
    mame_options = mame_machine:options()
else
    error("ERROR: Cannot access MAME options object. Incompatible MAME version.")
end

-- Detect if machine.devices is a property or method
if type(mame_machine.devices) == "userdata" or type(mame_machine.devices) == "table" then
    -- MAME 0.175+: devices is a property or table
    mame_devices = mame_machine.devices
elseif type(mame_machine.devices) == "function" then
    -- Older MAME (if any): devices is a method
    mame_devices = mame_machine:devices()
else
    error("ERROR: Cannot access MAME devices object. Incompatible MAME version.")
end

-- Store frame/stop callback subscriptions for MAME 0.254+
-- CRITICAL: Must be global for MAME 0.254+ to prevent garbage collection
_G.frame_subscription = nil
_G.stop_subscription = nil

local function register_frame_callback(callback)
    if emu.add_machine_frame_notifier then
        -- Modern MAME (0.254+) - Store in GLOBAL to prevent GC
        _G.frame_subscription = emu.add_machine_frame_notifier(callback)
        if not _G.frame_subscription then
            error("ERROR: Failed to register frame notifier")
        end
    elseif emu.register_frame_done then
        -- MAME 0.175-0.253
        emu.register_frame_done(callback)
    else
        error("ERROR: Cannot register frame callback. No compatible callback API found.")
    end
end

local function register_stop_callback(callback)
    if emu.add_machine_stop_notifier then
        -- Modern MAME (0.254+) - Store in GLOBAL to prevent GC
        _G.stop_subscription = emu.add_machine_stop_notifier(callback)
        if not _G.stop_subscription then
            error("ERROR: Failed to register stop notifier")
        end
    elseif emu.register_stop then
        -- MAME 0.175-0.253
        emu.register_stop(callback)
    else
        error("ERROR: Cannot register stop callback. No compatible callback API found.")
    end
end

-- Detect and log MAME version for debugging
local function detect_mame_version()
    if emu.app_version then
        return emu.app_version()
    end
    return "unknown"
end

-- GAME DETECTION
local function detect_game()
    local rom_name = emu.romname()
    if rom_name == "dkong" then
        return "dkong"
    elseif rom_name == "dkongjr" then
        return "dkongjr"
    elseif rom_name == "ckongpt2" then
        return "ckongpt2"
    end
    return nil  -- Unsupported game
end

local GAME_TYPE = detect_game()

if not GAME_TYPE then
    error("ERROR: Unsupported game. This script only works with dkong, dkongjr, and ckongpt2")
end

-- GAME CONFIGURATIONS
local GAME_CONFIGS = {
    dkong = {
        name = "Donkey Kong",
        screen_names = {
            [1] = "Barrel",
            [2] = "Pie",
            [3] = "Spring",
            [4] = "Rivet"
        },
        -- START score capture
        start_level = 4,           -- Capture START score after completing Level 4...
        start_stage = 5,           -- ...specifically after stage 4-5 (Rivet)
        
        -- Average tracking
        begin_avg = 5,             -- Begin gathering averages starting from Level 5
        
        -- Pace calculation readiness
        begin_pace_level = 5,      -- Can BEGIN calculating pace after Level 5...
        begin_pace_stage = 6,      -- ...specifically after stage 5-6 (Rivet)
        
        death_point_value = 700,
        barrel_multiplier = 3,     -- Barrels appear 3x per level in formula
        killscreen_level = 22,
        killscreen_stage = 1,
        supports_22_4_pace = false
    },
    
    dkongjr = {
        name = "Donkey Kong Junior",
        screen_names = {
            -- NOTE: Memory values differ from DK/CK in the way the stages are played
            [1] = "Spring",        -- Second stage of later levels
            [2] = "Jungle",        -- First stage of all levels
            [3] = "Chain",         -- Last stage of all levels
            [4] = "Hideout"        -- Third stage of all levels
        },
        -- START score capture
        start_level = 3,           -- Capture START score after completing Level 3...
        start_stage = 3,           -- ...specifically after stage 3-3 (Chain)
        
        -- Average tracking
        begin_avg = 4,             -- Begin gathering averages starting from Level 4
        
        -- Pace calculation readiness
        begin_pace_level = 4,      -- Can BEGIN calculating pace after Level 4...
        begin_pace_stage = 4,      -- ...specifically after stage 4-4 (Chain)
        
        death_point_value = 2000,
        barrel_multiplier = 1,     -- No barrel multiplier for DKJR
        killscreen_level = 22,
        killscreen_stage = 1,
        level_display_bug = true,
        supports_22_4_pace = false
    },
    
    ckongpt2 = {
        name = "Crazy Kong Part II",
        screen_names = {
            [1] = "Barrel",
            [2] = "Pie",
            [3] = "Spring",
            [4] = "Rivet"
        },
        -- START score capture
        start_level = 4,           -- Capture START score after completing Level 4...
        start_stage = 4,           -- ...specifically after stage 4-4 (Rivet)
        
        -- Average tracking
        begin_avg = 5,             -- Begin gathering averages starting from Level 5
        
        -- Pace calculation readiness
        begin_pace_level = 5,      -- Can BEGIN calculating pace after Level 5...
        begin_pace_stage = 4,      -- ...specifically after stage 5-4 (Rivet)
        
        death_point_value = 700,
        barrel_multiplier = 1,     -- No barrel multiplier for CK
        killscreen_level = 22,
        killscreen_stage = 1,
        supports_22_4_pace = true
    }
}

-- OUTPUT CONFIGURATION
local EXPORT_CSV = true
local EXPORT_JSON = true
local EXPORT_TEXT = true

-- Try to get INP filename from playback option
local function get_output_filenames()
    local playback_file = mame_options.entries["playback"]:value()
    
    if playback_file and playback_file ~= "" then
        local base_name = playback_file:match("(.+)%.inp$") or playback_file
        base_name = base_name:match("^.+[/\\](.+)$") or base_name
        
        -- Add timestamp: YYYYMMDD_HHMMSS
        local timestamp = os.date("%Y%m%d_%H%M%S")
        local filename_base = base_name .. "_" .. timestamp .. "_scores"
        
        return filename_base .. ".csv", filename_base .. ".json", filename_base .. ".txt"
    else
        return nil, nil, nil  -- No playback file
    end
end

local CSV_FILE, JSON_FILE, TEXT_FILE = get_output_filenames()

if not CSV_FILE then
    error("ERROR: No playback file detected. This script requires MAME to be run with -playback option")
end

-- STATE TRACKING
local prev_game_mode = 0
local prev_screen_type = 0
local prev_level = 0
local prev_score = 0  -- Adjusted score from last time we checked
local prev_raw_score = 0  -- Raw score for rollover detection
local stage_start_score = 0
local level_score_accumulated = 0
local current_level_being_played = 0
local frame_count = 0
local stage_data = {}
local current_screen_num = 0
local level_position = {}
local stage_completed_mode = nil
local completed_screen_type = 0
local completed_level = 0
local last_stage_was_completed = false
local death_count = 0
local total_death_points = 0  -- Accumulates points earned on death attempts
local start_score_for_pace = 0      -- Sum of stage scores during start phase (excludes deaths)
local start_score_total = 0         -- Total score after start phase (for display)
local start_phase_death_points = 0  -- Sum of death points during start phase
local start_phase_deaths = 0        -- Count of deaths during start phase
local score_offset = 0  -- Tracks million-point rollovers
local game_over_processed = false  -- Prevents double-printing at game over

-- Screen type averages tracking (works for all games)
local screen_sum = {0, 0, 0, 0}    -- Sum for screen types 1-4
local screen_count = {0, 0, 0, 0}  -- Count for screen types 1-4
local level_sum = 0
local level_count = 0
local can_calculate_pace = false  -- Set to true after Level 5 is complete
local last_pace = nil  -- Stores pace from last completed stage
local last_pace_22_4 = nil  -- Stores 22-4 pace from last completed stage (ckongpt2 only)

-- HELPER FUNCTIONS

-- Game config helpers
-- Helper to get current game config
local function get_config()
    return GAME_CONFIGS[GAME_TYPE]
end

-- Helper to get screen name based on game type
local function get_screen_type_name(screen_type)
    local config = get_config()
    return config.screen_names[screen_type] or "Unknown"
end

-- Memory helpers
-- Read single byte from memory
local function read_byte(address)
    local mem = mame_devices[":maincpu"].spaces["program"]
    local ok, val = pcall(function() return mem:read_u8(address) end)
    if not ok then
        return 0  -- Return 0 if read fails
    end
    return val
end

-- Read player 1 score from memory (3 bytes BCD = 6 digits)
local function read_score()
    local mem = mame_devices[":maincpu"].spaces["program"]
    
    -- Safe read the three score bytes
    local ok1, byte_60B2 = pcall(function() return mem:read_u8(ADDR_SCORE_P1_1) end)
    local ok2, byte_60B3 = pcall(function() return mem:read_u8(ADDR_SCORE_P1_2) end)
    local ok3, byte_60B4 = pcall(function() return mem:read_u8(ADDR_SCORE_P1_3) end)
    
    -- If any read failed, return 0
    if not (ok1 and ok2 and ok3) then
        return 0
    end
    
    -- Format as hex string and concatenate: 01|10|00 -> "011000"
    local score_string = string.format("%02X%02X%02X", byte_60B4, byte_60B3, byte_60B2)
    
    -- Convert to number
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

-- Formatting helpers
-- Format number with commas (e.g., 12345 -> "12,345")
local function format_number(num)
    local formatted = tostring(num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
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
            return string.char(65 + (level - 17))  -- A-F
        else
            return tostring(level)
        end
    else
        return tostring(level)
    end
end

local function get_stage_name(level, position)
    local config = get_config()
    local level_display = level
    
    -- Handle DKJR level display bug
    if config.level_display_bug then
        if level >= 10 and level <= 16 then
            level_display = string.format("[%d]", level)
        elseif level >= 17 and level <= 21 then
            level_display = string.char(65 + (level - 17))  -- A-F
        else
            level_display = tostring(level)
        end
    else
        level_display = tostring(level)
    end
    
    return string.format("%s-%d", level_display, position)
end

-- Calculation helpers
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
    
    local pace
    
    if GAME_TYPE == "dkong" then
        -- DK: start + (((barrel_avg * 3) + pie_avg + spring_avg + rivet_avg) * 17)
        pace = start_score_for_pace + (((screen_avg[1] * 3) + screen_avg[2] + screen_avg[3] + screen_avg[4]) * 17)
        
    elseif GAME_TYPE == "dkongjr" then
        -- DKJR: start + ((jungle_avg + spring_avg + hideout_avg + chain_avg) * 18)
        -- Memory mapping: 1=Spring, 2=Jungle, 3=Chain, 4=Hideout
        pace = start_score_for_pace + ((screen_avg[2] + screen_avg[1] + screen_avg[4] + screen_avg[3]) * 18)
        
    elseif GAME_TYPE == "ckongpt2" then
        -- CK: start + ((barrel_avg + pie_avg + spring_avg + rivet_avg) * 17)
        pace = start_score_for_pace + ((screen_avg[1] + screen_avg[2] + screen_avg[3] + screen_avg[4]) * 17)
    end
    
    pace = pace + estimated_death_points
    
    -- Round to nearest 100
    return math.floor(pace / 100 + 0.5) * 100
end

local function calculate_22_4_pace(base_pace, lives_remaining)
    local config = get_config()
    if not config.supports_22_4_pace or not base_pace then
        return nil
    end
    return base_pace + 13700 + (lives_remaining * 1500)
end

-- Record a stage result
local function record_stage(screen_type, level, position, screen_num, score_earned, total_score, is_death, death_num, lives_remaining)
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
        avg_type = nil,  -- Will store "Barrel Avg", "Pie Avg", etc.
        avg_value = nil, -- Will store the calculated average
        pace = nil,      -- Will store the calculated pace
        pace_22_4 = nil  -- Will store the 22-4 extended pace (ckongpt2 only)
    }
    
    table.insert(stage_data, stage_info)
    
    -- Track start phase scores and deaths
    local config = get_config()
    if start_score_total == 0 then  -- Still in start phase
        if is_death then
            -- Track deaths during start phase
            start_phase_deaths = start_phase_deaths + 1
            start_phase_death_points = start_phase_death_points + score_earned
        else
            -- Accumulate stage scores during start phase
            start_score_for_pace = start_score_for_pace + score_earned
            
            -- Check if this completes the start phase
            if level == config.start_level and position == config.start_stage then
                start_score_total = total_score
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
            screen_sum[screen_type] = screen_sum[screen_type] + score_earned
            screen_count[screen_type] = screen_count[screen_type] + 1
            avg_value = screen_sum[screen_type] / screen_count[screen_type]
            avg_type = get_screen_type_name(screen_type) .. " Avg"
        end
        
        -- Store in stage_info and format for console
        if avg_value then
            stage_info.avg_type = avg_type
            stage_info.avg_value = avg_value
            avg_str = string.format(" | %s: %s", avg_type, format_number_decimal(avg_value))
        end
        
        -- Check if we can enable pace calculation
        if level > config.begin_pace_level or 
           (level == config.begin_pace_level and position >= config.begin_pace_stage) then
            local all_screens_seen = true
            for i = 1, 4 do
                if screen_count[i] == 0 then
                    all_screens_seen = false
                    break
                end
            end
            if all_screens_seen then
                can_calculate_pace = true
            end
        end
    end
    
    -- Calculate pace (only for completed stages, not deaths)
    local pace_str = ""
    if not is_death then
        local pace = calculate_pace(lives_remaining)
        if pace then
            -- Store pace in stage_info for text file output
            stage_info.pace = pace
            last_pace = pace
            
            -- Check if we should show extended pace (ckongpt2 only)
            local pace_22_4 = calculate_22_4_pace(pace, lives_remaining)
            if pace_22_4 then
                stage_info.pace_22_4 = pace_22_4
                last_pace_22_4 = pace_22_4
                pace_str = string.format(" | 22-1 Pace: %s | 22-4 Pace: %s", 
                    format_number(pace), format_number(pace_22_4))
            else
                pace_str = string.format(" | Pace: %s", format_number(pace))
            end
        end
    end

    -- Clean console output
    if is_death then
        print(string.format("Stage %s Death #%d | Death Points: %s | Total Score: %s",
            stage_info.stage,
            death_num,
            format_number(score_earned),
            format_number(total_score)))
    else
        print(string.format("Stage %s Complete | Stage Score: %s | Total Score: %s%s%s",
            stage_info.stage,
            format_number(score_earned),
            format_number(total_score),
            avg_str,
            pace_str))
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
        frame = frame_count
    }
    
    table.insert(stage_data, level_info)
    
    -- Track L5-L21 level averages
    local avg_str = ""
    local config = get_config()
    if level >= config.begin_avg and level <= 21 then
        level_sum = level_sum + score_earned
        level_count = level_count + 1
        avg_str = string.format(" | Level Avg: %s", format_number_decimal(level_sum / level_count))
    end
    
    print(string.format("\n>>> LEVEL %s COMPLETE | Level Score: %s | Total Score: %s%s <<<\n",
        level_display,
        format_number(score_earned),
        format_number(total_score),
        avg_str))
end

-- Export to CSV
local function export_csv()
    if not EXPORT_CSV then return end

    local file = io.open(CSV_FILE, "w")
    if not file then
        print("ERROR: Could not create CSV file - check file permissions or if file is open")
        return
    end
    
    file:write("Screen_Num,Stage,Screen_Type,Level,Score_Earned,Total_Score,Death,Death_Num,Frame\n")
    
    for _, stage in ipairs(stage_data) do
        local screen_num_str = stage.screen_num == "" and "" or tostring(stage.screen_num)
        local death_num_str = stage.death_num and tostring(stage.death_num) or ""
        file:write(string.format("%s,%s,%s,%d,%d,%d,%s,%s,%d\n",
            screen_num_str,
            stage.stage,
            stage.screen_type,
            stage.level,
            stage.score_earned,
            stage.total_score,
            stage.death and "true" or "false",
            death_num_str,
            stage.frame
        ))
    end
    
    file:close()
    print(string.format("\n[OK] CSV exported to: %s", CSV_FILE))
end

-- Export to JSON
local function export_json()
    if not EXPORT_JSON then return end
    
    local file = io.open(JSON_FILE, "w")
    if not file then
        print("ERROR: Could not create JSON file")
        return
    end
    
    file:write("{\n")
    file:write(string.format('  "game": "%s",\n', GAME_TYPE))
    file:write(string.format('  "total_screens": %d,\n', current_screen_num))
    file:write(string.format('  "final_score": %d,\n', prev_score))
    file:write('  "stages": [\n')
    
    for i, stage in ipairs(stage_data) do
        file:write("    {\n")
        
        if stage.is_level_total then
            file:write('      "screen_num": null,\n')
        else
            file:write(string.format('      "screen_num": %d,\n', stage.screen_num))
        end
        
        file:write(string.format('      "stage": "%s",\n', stage.stage))
        file:write(string.format('      "screen_type": "%s",\n', stage.screen_type))
        file:write(string.format('      "level": %d,\n', stage.level))
        file:write(string.format('      "score_earned": %d,\n', stage.score_earned))
        file:write(string.format('      "total_score": %d,\n', stage.total_score))
        file:write(string.format('      "death": %s,\n', stage.death and "true" or "false"))
        
        if stage.death_num then
            file:write(string.format('      "death_num": %d,\n', stage.death_num))
        else
            file:write('      "death_num": null,\n')
        end
        
        file:write(string.format('      "is_level_total": %s,\n', stage.is_level_total and "true" or "false"))
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
    if not EXPORT_TEXT then return end
    
    local file = io.open(TEXT_FILE, "w")
    if not file then
        print("ERROR: Could not create text file")
        return
    end
    
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
    local config = get_config()
    file:write(string.format("=== %s SCORE LOG ===\n", config.name:upper()))
    file:write(string.format("Final Score: %s\n", format_number(prev_score)))
    if final_stage ~= "" then
        file:write(string.format("Final Stage: %s\n", final_stage))
    end
    
    -- Show pace based on game type and final stage
    if final_level and last_pace then
        if config.supports_22_4_pace then
            -- Crazy Kong Part II
            if final_level == 22 and final_stage_position and final_stage_position >= 1 and final_stage_position <= 3 then
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
            file:write(string.format("Start Score: %s (%s + %s)\n", 
                format_number(start_score_total),
                format_number(start_score_for_pace),
                format_number(start_phase_death_points)))
        else
            file:write(string.format("Start Score: %s\n", format_number(start_score_total)))
        end
    end
    
    -- Screen type averages
    local config = get_config()
    for i = 1, 4 do
        if screen_count[i] > 0 then
            file:write(string.format("L%d+ %s Average: %s\n", 
                config.begin_avg,
                get_screen_type_name(i),
                format_number_decimal(screen_sum[i] / screen_count[i])))
        end
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
                file:write(string.format("%s Death #%d: %s --> %s\n",
                    stage.stage,
                    stage.death_num,
                    format_number(stage.score_earned),
                    format_number(stage.total_score)))
            else
                -- Completed stage format with avg and pace data
                local stage_line = string.format("%s: %s --> %s",
                    stage.stage,
                    format_number(stage.score_earned),
                    format_number(stage.total_score))
                
                -- Add average if present
                if stage.avg_type and stage.avg_value then
                    stage_line = stage_line .. string.format(" | %s: %s", 
                        stage.avg_type, 
                        format_number_decimal(stage.avg_value))
                end
                
                -- Add pace if present
                if stage.pace then
                    if stage.pace_22_4 then
                        stage_line = stage_line .. string.format(" | 22-1 Pace: %s | 22-4 Pace: %s", 
                            format_number(stage.pace), format_number(stage.pace_22_4))
                    else
                        stage_line = stage_line .. string.format(" | Pace: %s", format_number(stage.pace))
                    end
                end
                
                file:write(stage_line .. "\n")
            end
        end
    end
    
    file:close()
    print(string.format("[OK] Text exported to: %s", TEXT_FILE))
end

-- MAIN FRAME LOOP
local function on_frame()
    frame_count = frame_count + 1

    -- Read current state (don't read score every frame, only when needed)
    local game_mode = read_byte(ADDR_GAME_MODE)
    local screen_type = read_byte(ADDR_SCREEN_TYPE)
    local level = read_byte(ADDR_LEVEL)
    local lives = read_byte(ADDR_LIVES)

    -- Initialize stage_start_score on first gameplay
    if prev_game_mode ~= MODE_GAMEPLAY and game_mode == MODE_GAMEPLAY then
        local current_score = read_score_with_rollover_check()
        
        -- Check if we're starting a new level
        if level ~= current_level_being_played and current_level_being_played > 0 then
            -- Level changed - record total for previous level (using accumulated score, not delta)
            record_level_total(current_level_being_played, level_score_accumulated, current_score)
            
            -- Start tracking new level
            level_score_accumulated = 0  -- Reset for new level
            current_level_being_played = level
        elseif current_level_being_played == 0 then
            -- First level of the game
            level_score_accumulated = 0
            current_level_being_played = level
        end
        
        if stage_start_score == 0 or last_stage_was_completed then
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
    end
    
    -- Track screen/level during gameplay
    if game_mode == MODE_GAMEPLAY then
        prev_screen_type = screen_type
        prev_level = level
    end
    
    -- STAGE COMPLETION: Detect when leaving gameplay (except death)
    if prev_game_mode == MODE_GAMEPLAY and game_mode ~= MODE_GAMEPLAY and game_mode ~= MODE_DEAD then
        if stage_completed_mode == nil then
            stage_completed_mode = game_mode
            completed_screen_type = prev_screen_type
            completed_level = prev_level
        end
    end
    
    -- RECORD STAGE: Wait for transition screen after completion
    if game_mode == MODE_TRANSITION and stage_completed_mode ~= nil then
        local current_score = read_score_with_rollover_check()
        local score_earned = current_score - stage_start_score
        local current_position = level_position[completed_level]
        
        record_stage(completed_screen_type, completed_level, current_position, 
                    current_screen_num, score_earned, current_score, false, nil, lives)
        
        -- Add to level score (only for completed stages, not deaths)
        level_score_accumulated = level_score_accumulated + score_earned
        
        last_stage_was_completed = true
        stage_completed_mode = nil
        prev_score = current_score
    end
    
    -- DEATH DETECTION
    -- Death occurs when mode changes from GAMEPLAY to DEAD
    if game_mode == MODE_DEAD and prev_game_mode == MODE_GAMEPLAY then
        local current_score = read_score_with_rollover_check()
        death_count = death_count + 1
        local score_earned = current_score - stage_start_score
        local current_position = level_position[level]
        
        -- Accumulate death points
        total_death_points = total_death_points + score_earned
        
        -- Record the death
        record_stage(screen_type, level, current_position, current_screen_num, 
                    score_earned, current_score, true, death_count, lives)
        
        last_stage_was_completed = false
        stage_start_score = current_score
        prev_score = current_score
    end
    
    -- GAME OVER
    if game_mode == MODE_GAME_OVER and prev_game_mode ~= MODE_GAME_OVER and not game_over_processed then
        local current_score = read_score_with_rollover_check()
        game_over_processed = true
        
        -- Only record final level total if NOT on killscreen death
        local is_killscreen = (current_level_being_played == 22 and level_position[22] == 1)
        
        if current_level_being_played > 0 and (is_killscreen or last_stage_was_completed) then
            record_level_total(current_level_being_played, level_score_accumulated, current_score)
        end
        
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
        
        print("\n=== GAME OVER ===")
        print(string.format("Final Score: %s", format_number(current_score)))
        if final_stage ~= "" then
            print(string.format("Final Stage: %s", final_stage))
        end
        
        -- Show pace based on game type and final stage
        if final_level and last_pace then
            local config = get_config()
            
            if config.supports_22_4_pace then
                -- Crazy Kong Part II
                if final_level == 22 and final_stage_position and final_stage_position >= 1 and final_stage_position <= 3 then
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
                print(string.format("Start Score: %s (%s + %s)", 
                    format_number(start_score_total),
                    format_number(start_score_for_pace),
                    format_number(start_phase_death_points)))
            else
                print(string.format("Start Score: %s", format_number(start_score_total)))
            end
        end
        
        -- Screen type averages
        local config = get_config()
        for i = 1, 4 do
            if screen_count[i] > 0 then
                print(string.format("L%d+ %s Average: %s", 
                    config.begin_avg,
                    get_screen_type_name(i),
                    format_number_decimal(screen_sum[i] / screen_count[i])))
            end
        end
        
        print(string.format("Total Death Points: %s", format_number(total_death_points)))
        export_csv()
        export_json()
        export_text()
        prev_score = current_score
    end

    -- Update previous state
    prev_game_mode = game_mode
    prev_screen_type = screen_type
    prev_level = level
end

-- INITIALIZATION
print("=== BLOSSOM ===")
print(string.format("MAME Version: %s", detect_mame_version()))
print(string.format("Detected game: %s", GAME_TYPE))
print(string.format("Output files: %s, %s, %s", CSV_FILE, JSON_FILE, TEXT_FILE))
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
    -- Only process if game over hasn't been handled yet
    if not game_over_processed and current_screen_num > 0 then
        local current_score = read_score_with_rollover_check()
        
        -- Determine if this is killscreen
        local is_killscreen = (current_level_being_played == 22 and level_position[22] == 1)
        
        -- Record final level total only if appropriate
        if current_level_being_played > 0 and level_score_accumulated > 0 and 
           (is_killscreen or last_stage_was_completed) then
            record_level_total(current_level_being_played, level_score_accumulated, current_score)
        end
        
        print("\n=== INP Playback Ended ===")
        export_csv()
        export_json()
        export_text()
    end
end)