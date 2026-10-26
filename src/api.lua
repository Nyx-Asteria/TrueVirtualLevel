-- True Virtual Level: public API for optional plugin integrations.
--
-- The RuneScape plugin loader exposes the value returned by main.lua to
-- dependent plugins. This module builds that return value without exposing
-- mutable settings or internal XP tables.
--
-- Standard skills use progression.lua; native Invention uses the exact
-- elite thresholds in elite.lua. Neither calculation changes player XP.

local progression = require("src/progression")
local elite = require("src/elite")
local settings_module = require("src/settings")
local settings = settings_module.values

local api = {}

local function standard_cap(override)
    return override or (settings.cap_120 and 120 or 126)
end

-- Optional calculation-only cap. Invalid overrides fail instead of silently
-- changing the meaning of a call. No persistent settings are touched.
local function valid_override(override)
    return override == nil or override == 120 or override == 126
end

local function native_elite(skill)
    return skill == SkillType.INVENTION and not settings.invention
end

local function valid_xp(xp)
    return type(xp) == "number" and xp == xp
        and xp ~= math.huge and xp ~= -math.huge
end

-- API version is independent of the plugin release version.
function api.GetAPIVersion()
    return "1.1.0"
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
-- The optional 120/126 override affects only standard-curve skills.
function api.GetMaxVirtualLevel(skill, cap_override)
    if not valid_override(cap_override) then return nil end
    if native_elite(skill) then
        return 150
    end
    return standard_cap(cap_override)
end

-- Return a standard-curve XP threshold up to the effective cap.
-- The legacy nil result for native elite Invention is preserved here.
function api.GetXPForLevel(skill, level, cap_override)
    if not valid_override(cap_override) then return nil end
    if native_elite(skill) then
        return nil
    end
    if type(level) ~= "number" or level % 1 ~= 0 then
        return nil
    end
    if level > standard_cap(cap_override) then return nil end
    return progression.xp_for_level[level]
end

-- Calculate a standard-curve level from XP with an optional cap override.
-- Preserve the legacy nil result for native elite Invention.
function api.GetVirtualLevel(skill, xp, cap_override)
    if not valid_override(cap_override) then return nil end
    if native_elite(skill) then
        return nil
    end
    local level = progression.standard_level_from_xp(xp)
    return level and math.min(level, standard_cap(cap_override)) or nil
end

-- Describe progress toward the next level or the 200m XP milestone.
-- Native elite Invention now uses its own exact XP thresholds through 150.
-- An optional 120/126 cap applies ONLY to standard-curve calculations.
-- At the final supported level, progress continues toward 200m XP.
-- The result shape is identical for both curves; progress ranges from 0 to 1.
function api.GetProgress(skill, xp, cap_override)
    if not valid_xp(xp) or not valid_override(cap_override) then
        return nil
    end

    local capped_xp = math.max(0, math.min(xp, progression.MAX_XP))
    local is_elite = native_elite(skill)
    local max_level = is_elite and 150 or standard_cap(cap_override)
    local level = is_elite and elite.level_from_xp(capped_xp)
        or progression.standard_level_from_xp(capped_xp)
    level = math.min(level, max_level)

    local start_xp = is_elite and elite.xp_for_level(level)
        or progression.xp_for_level[level]
    local at_cap = level == max_level
    local target_xp = at_cap and progression.MAX_XP
        or (is_elite and elite.xp_for_level(level + 1)
            or progression.xp_for_level[level + 1])
    local span = target_xp - start_xp
    local fraction = span > 0 and (capped_xp - start_xp) / span or 1

    return {
        level = level,
        maxLevel = max_level,
        currentXP = capped_xp,
        levelXP = start_xp,
        nextXP = target_xp,
        remainingXP = math.max(0, target_xp - capped_xp),
        progress = math.max(0, math.min(1, fraction)),
        targetType = at_cap and "xp_cap" or "level",
    }
end

return api
