-- True Virtual Level: public API for optional plugin integrations.
--
-- The RuneScape plugin loader exposes the value returned by main.lua to
-- dependent plugins. This module builds that return value without exposing
-- mutable settings or internal XP tables.
--
-- All XP thresholds here use TVL's existing standard curve. Invention's
-- native elite curve is deliberately not approximated by that formula.

local progression = require("src/progression")
local settings_module = require("src/settings")
local settings = settings_module.values

local api = {}

local function standard_cap()
    return settings.cap_120 and 120 or 126
end

-- API version is independent of the plugin release version.
function api.GetAPIVersion()
    return "1.0.0"
end

-- Return the currently selected Invention XP curve. Read on every call so
-- dependent plugins see settings changes without requiring a reload.
function api.GetInventionCurve()
    return settings.invention and "standard" or "elite"
end

-- The XP ceiling applies to every skill, regardless of its level curve.
function api.GetMaxXP()
    return progression.MAX_XP
end

-- Set the optional standard-curve level cap from another plugin.
-- Persist the preference and refresh TVL's Skills interface immediately.
-- Returns false for non-boolean inputs.
function api.SetLevelCap120(enabled)
    return settings_module.set_cap_120(enabled)
end

-- Read the currently selected standard-curve cap.
function api.GetLevelCap120()
    return settings.cap_120
end

-- Return the highest displayed virtual level supported for this skill.
-- Native elite-curve Invention reaches 150; the standard curve reaches 126.
function api.GetMaxVirtualLevel(skill)
    if skill == SkillType.INVENTION and not settings.invention then
        return 150
    end
    return standard_cap()
end

-- Get the XP threshold for a level on the selected standard curve.
-- For elite-curve Invention return nil: its thresholds are different and
-- are not defined by progression.lua. Consumers can retain native handling.
function api.GetXPForLevel(skill, level)
    if skill == SkillType.INVENTION and not settings.invention then
        return nil
    end
    if type(level) ~= "number" or level % 1 ~= 0 then
        return nil
    end
    if level > standard_cap() then return nil end
    return progression.xp_for_level[level]
end

-- Calculate a level from XP on the currently selected standard curve.
-- For elite Invention return nil instead of pretending it uses standard XP.
-- Consumers should use the game's native Invention level in that case.
function api.GetVirtualLevel(skill, xp)
    if skill == SkillType.INVENTION and not settings.invention then
        return nil
    end
    local level = progression.standard_level_from_xp(xp)
    return level and math.min(level, standard_cap()) or nil
end

-- Describe progress toward the next standard-curve level or 200m XP.
-- Returns nil for invalid XP or native elite-curve Invention. At level 126,
-- the target is the 200m milestone, NOT an imaginary level 127.
--
-- progress is a fraction from 0 to 1. Consumers may multiply by 100.
function api.GetProgress(skill, xp)
    if type(xp) ~= "number" or xp ~= xp
        or xp == math.huge or xp == -math.huge then
        return nil
    end
    if skill == SkillType.INVENTION and not settings.invention then
        return nil
    end

    local capped_xp = math.max(0, math.min(xp, progression.MAX_XP))
    local level = math.min(progression.standard_level_from_xp(capped_xp), standard_cap())
    local start_xp = progression.xp_for_level[level]
    local at_cap = level == standard_cap()
    local target_xp = at_cap and progression.MAX_XP
        or progression.xp_for_level[level + 1]
    local span = target_xp - start_xp
    local fraction = span > 0 and (capped_xp - start_xp) / span or 1

    return {
        level = level,
        maxLevel = standard_cap(),
        currentXP = capped_xp,
        levelXP = start_xp,
        nextXP = target_xp,
        remainingXP = math.max(0, target_xp - capped_xp),
        progress = math.max(0, math.min(1, fraction)),
        targetType = at_cap and "xp_cap" or "level",
    }
end

return api
