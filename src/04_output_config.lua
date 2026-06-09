-- ============================================================================
-- OUTPUT CONFIGURATIONS
-- ============================================================================

-- OUTPUT CONFIGURATION
local EXPORT_CSV = true
local EXPORT_JSON = true
local EXPORT_TEXT = true

-- Get INP filename for display (strips path if present)
local function get_inp_filename()
  local playback_file = mame_options.entries["playback"]:value()
  if playback_file and playback_file ~= "" then
    return playback_file:match("^.+[/\\](.+)$") or playback_file
  end
  return "unknown"
end

-- Try to get INP filename from playback option
local function get_output_filenames()
  local playback_file = mame_options.entries["playback"]:value()

  if playback_file and playback_file ~= "" then
    local base_name = playback_file:match("(.+)%.inp$") or playback_file
    base_name = base_name:match("^.+[/\\](.+)$") or base_name

    -- Add timestamp to prevent file collisions
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename_base = base_name .. "_" .. timestamp .. "_scores"

    return filename_base .. ".csv", filename_base .. ".json", filename_base .. ".txt"
  else
    return nil, nil, nil
  end
end

local CSV_FILE, JSON_FILE, TEXT_FILE = get_output_filenames()

if not CSV_FILE then
  error(
    "ERROR: No playback file detected. This script requires MAME to be run with -playback option"
  )
end

-- Create blossom_logs directory
local function create_output_directory()
  os.execute("mkdir blossom_logs 2>nul") -- Windows
  os.execute("mkdir -p blossom_logs 2>/dev/null") -- Unix/Mac
end

create_output_directory()

-- Prepend directory to output files
CSV_FILE = "blossom_logs/" .. CSV_FILE
JSON_FILE = "blossom_logs/" .. JSON_FILE
TEXT_FILE = "blossom_logs/" .. TEXT_FILE
