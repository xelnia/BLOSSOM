-- INITIALIZATION
print("\n=== BLOSSOM ===")

local config = get_config()

if GAME_TYPE == "dkong3" then
  -- DK3: Show variation after game name
  print(string.format("Game: %s", config.full_name))
  print(string.format("romset: %s", config.romset))
  game_variation = detect_variation_dk3()
  print(string.format("Variation: %s", game_variation))
  print(string.format("MAME version: %s", detect_mame_version()))
  print(string.format("INP: %s\n", get_inp_filename()))
else
  -- Standard platformers: No variation line
  print(string.format("Game: %s", config.full_name))
  print(string.format("romset: %s", config.romset))
  print(string.format("MAME version: %s", detect_mame_version()))
  print(string.format("INP: %s\n", get_inp_filename()))
end

print("Tracking gameplay...\n")

-- Detect INP playback mode (guards against false INP-end detection on live play)
if mame_options.entries["playback"]:value() ~= "" then
  inp_playback_active = true
end

-- Wrap on_frame in error protection for MAME 0.254+
local function protected_on_frame()
  local ok, err = pcall(on_frame)
  if not ok then
    print(string.format("[ERROR] Frame %d: %s", frame_count, tostring(err)))
  end
end

register_frame_callback(protected_on_frame)

register_stop_callback(function()
  finalize_session("SESSION ENDED")
end)
