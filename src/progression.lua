-- True Virtual Level: skill XP and virtual-level calculations.

-- All standard-curve XP thresholds are calculated here so the Skills labels
-- and hover tooltip use the same numbers. This module is independent of UI
-- components and saved settings; it does not change game account data.

local progression = {}
local MAX_XP = 200000000

-- Generate RuneScape's standard cumulative XP thresholds through level 126.
-- Each level adds floor(level + 300 * 2^(level/7)) points; dividing the running
-- total by four gives the XP required for the next level. Level 1 starts at 0 XP.
-- The 200m cap is the maximum XP considered by TVL, not a new level 127.

local xp_for_level = { [1] = 0 }
local points = 0

for level = 1, 125 do
    points = points + math.floor(level + 300 * 2 ^ (level / 7))
    xp_for_level[level + 1] = math.floor(points / 4)
end

-- Return a virtual level only after the standard level-121 XP threshold.
-- Returning nil below that threshold lets the game keep its native labels.
-- Clamp XP to 200m so unexpected higher values cannot exceed level 126.

local function get_virtual_level(xp)
    if type(xp) ~= "number" or xp < xp_for_level[121] then
        return nil
    end

    xp = math.min(xp, MAX_XP)
    local level = 120

    for next_level = 121, 126 do
        if xp < xp_for_level[next_level] then break end
        level = next_level
    end

    return level
end

-- Translate XP to a standard-curve level starting from level 1.
-- Used when the player enables standard-curve Invention: unlike other skills,
-- Invention normally follows its own elite curve, so its displayed level may
-- need replacing even below 121. The setting decision is made by main.lua.

local function standard_level_from_xp(xp)
    if type(xp) ~= "number" then return nil end
    xp = math.max(0, math.min(xp, MAX_XP))
    local level = 1
    for next_level = 2, 126 do
        if xp < xp_for_level[next_level] then break end
        level = next_level
    end
    return level
end

-- The supplemental tooltip is useful from level 120 onward, even though
-- main.lua only overrides ordinary skill labels at virtual level 121+.
-- Return nil below the level-120 threshold to leave native tooltips alone.

local function get_hover_level(xp)
    if type(xp) ~= "number" or xp < xp_for_level[120] then
        return nil
    end
    return get_virtual_level(xp) or 120
end

-- Export calculations to the plugin's other Lua modules.
progression.MAX_XP = MAX_XP
progression.xp_for_level = xp_for_level
progression.get_virtual_level = get_virtual_level
progression.standard_level_from_xp = standard_level_from_xp
progression.get_hover_level = get_hover_level

return progression
