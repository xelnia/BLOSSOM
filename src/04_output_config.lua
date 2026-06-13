-- ============================================================================
-- OUTPUT CONFIGURATIONS
-- ============================================================================

-- Cache INP base name and timestamp at startup (before playback option might clear)
local inp_base_name = nil
local inp_timestamp = nil

local function cache_inp_info()
  local playback_file = mame_options.entries["playback"]:value()
  if playback_file and playback_file ~= "" then
    local base = playback_file:match("(.+)%.inp$") or playback_file
    inp_base_name = base:match("^.+[/\\](.+)$") or base
    inp_timestamp = os.date("%Y%m%d_%H%M%S")
  end
end

cache_inp_info()

if not inp_base_name then
  error(
    "ERROR: No playback file detected. This script requires MAME to be run with -playback option"
  )
end

-- Get INP filename for display (strips path if present)
local function get_inp_filename()
  local playback_file = mame_options.entries["playback"]:value()
  if playback_file and playback_file ~= "" then
    return playback_file:match("^.+[/\\](.+)$") or playback_file
  end
  return "unknown"
end

-- Create blossom_logs directory
local function create_output_directory()
  os.execute("mkdir blossom_logs 2>nul") -- Windows
  os.execute("mkdir -p blossom_logs 2>/dev/null") -- Unix/Mac
end

create_output_directory()

-- Generate output filenames for a given session number (includes directory prefix)
local function get_output_filenames(session_num)
  local session_suffix = string.format("_session_%03d", session_num)
  local filename_base = "blossom_logs/"
    .. inp_base_name
    .. "_"
    .. inp_timestamp
    .. session_suffix
    .. "_scores"
  return filename_base .. ".csv", filename_base .. ".json", filename_base .. ".txt"
end

local CSV_FILE, JSON_FILE, TEXT_FILE = get_output_filenames(1)
