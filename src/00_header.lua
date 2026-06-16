-- BLOSSOM
-- Basic Logging Of Scoring Statistics Originating (in) MAME

-- Tracks stage-by-stage scoring during INP playback
-- Supported games: dkong, dkongjr, ckongpt2, dkong3
-- Supported MAME versions: 0.175+
-- Exports scoring data and summary in CSV, JSON, and TXT format

local BLOSSOM_VERSION = "2.0.1"

-- Export toggles: set to false to suppress specific output formats
local EXPORT_CSV = true
local EXPORT_JSON = true
local EXPORT_TEXT = true
