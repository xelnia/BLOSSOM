-- BLOSSOM
-- Basic Logging Of Scoring Statistics Originating (in) MAME

-- Tracks stage-by-stage scoring during INP playback
-- Supported games: dkong, dkongjr, ckongpt2, dkong3
-- Supported MAME versions: 0.175+
-- Exports scoring data and summary in CSV, JSON, and TXT format

local BLOSSOM_VERSION = "2.2.0"

-- Console display toggles (these do not affect export files)
local SHOW_INIT_HEADER = true
local SHOW_RUNNING_LOG = true
local SHOW_SCORING_SUMMARY = true
local SHOW_LIVES_SUMMARY = true
local SHOW_TIMING_SUMMARY = true
local SHOW_SCORE_MILESTONES = true

-- Export toggles: set to false to suppress specific output formats
local EXPORT_CSV = true
local EXPORT_JSON = true
local EXPORT_TEXT = true
