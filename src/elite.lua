-- Invention's native elite XP curve, including virtual levels through 150.
-- Calculate the level from XP instead of trusting GetLevelUncapped(), which
-- may return the level-120 cap when restoring a TVL-overridden label.

local elite = {}
local xp_for_level = {
    0, 830, 1861, 2902, 3980, 5126, 6380, 7787, 9400, 11275,
    13605, 16372, 19656, 23546, 28134, 33520, 39809, 47109, 55535, 65209,
    77190, 90811, 106221, 123573, 143025, 164742, 188893, 215651, 245196, 277713,
    316311, 358547, 404634, 454796, 509259, 568254, 632019, 700797, 774834, 854383,
    946227, 1044569, 1149696, 1261903, 1381488, 1508756, 1644015, 1787581, 1939773, 2100917,
    2283490, 2476369, 2679917, 2894505, 3120508, 3358307, 3608290, 3870846, 4146374, 4435275,
    4758122, 5096111, 5449685, 5819299, 6205407, 6608473, 7028964, 7467354, 7924122, 8399751,
    8925664, 9472665, 10041285, 10632061, 11245538, 11882262, 12542789, 13227679, 13937496, 14672812,
    15478994, 16313404, 17176661, 18069395, 18992239, 19945833, 20930821, 21947856, 22997593, 24080695,
    25259906, 26475754, 27728955, 29020233, 30350318, 31719944, 33129852, 34580790, 36073511, 37608773,
    39270442, 40978509, 42733789, 44537107, 46389292, 48291180, 50243611, 52247435, 54303504, 56412678,
    58575824, 60793812, 63067521, 65397835, 67785643, 70231841, 72737330, 75303019, 77929820, 80618654
}
local virtual_xp = {
    [121] = 83370445, [122] = 86186124, [123] = 89066630, [124] = 92012904, [125] = 95025896,
    [126] = 98106559, [127] = 101255855, [128] = 104474750, [129] = 107764216, [130] = 111125230,
    [131] = 114558777, [132] = 118065845, [133] = 121647430, [134] = 125304532, [135] = 129038159,
    [136] = 132849323, [137] = 136739041, [138] = 140708338, [139] = 144758242, [140] = 148889790,
    [141] = 153104021, [142] = 157401983, [143] = 161784728, [144] = 166253312, [145] = 170808801,
    [146] = 175452262, [147] = 180184770, [148] = 185007406, [149] = 189921255, [150] = 194927409,
}
for level, xp in pairs(virtual_xp) do
    xp_for_level[level] = xp
end

-- Public threshold lookup for the native elite progression API.
function elite.xp_for_level(level)
    if type(level) ~= "number" or level % 1 ~= 0 then return nil end
    return xp_for_level[level]
end

function elite.level_from_xp(xp)
    if type(xp) ~= "number" then return nil end
    local level = 1
    for next_level = 2, 150 do
        if xp < xp_for_level[next_level] then break end
        level = next_level
    end
    return level
end

-- The native total already includes Invention's elite virtual level.
-- When TVL displays the standard curve, adjust that contribution by the
-- difference between the standard and elite levels at the same XP.
function elite.standard_level_difference(xp, standard_level)
    if type(standard_level) ~= "number" then return nil end
    local elite_level = elite.level_from_xp(xp)
    if not elite_level then return nil end
    return standard_level - elite_level
end

return elite
