-- True Virtual Level
-- Extends virtual levels to 126 in RuneScape's Skills panel.

local SKILLS_INTERFACE = 1466
local CURRENT_LEVEL = 4
local BASE_LEVEL = 5
local VIRTUAL_TOTAL = 11
local VIRTUAL_TOTAL_SLOT = 2
local MAX_XP = 200000000

-- Skills panel order differs from the SkillType enum order.
local skills = {
    SkillType.ATTACK, SkillType.STRENGTH, SkillType.DEFENCE,
    SkillType.RANGED, SkillType.PRAYER, SkillType.MAGIC,
    SkillType.RUNECRAFTING, SkillType.CONSTRUCTION, SkillType.DUNGEONEERING,
    SkillType.HITPOINTS, SkillType.AGILITY, SkillType.HERBLORE,
    SkillType.THIEVING, SkillType.CRAFTING, SkillType.FLETCHING,
    SkillType.SLAYER, SkillType.HUNTER, SkillType.DIVINATION,
    SkillType.MINING, SkillType.SMITHING, SkillType.FISHING,
    SkillType.COOKING, SkillType.FIREMAKING, SkillType.WOODCUTTING,
    SkillType.FARMING, SkillType.SUMMONING, SkillType.INVENTION,
    SkillType.ARCHAEOLOGY, SkillType.NECROMANCY,
}

-- Standard XP formula, extended through level 126.
local xp_for_level = { [1] = 0 }
local points = 0

for level = 1, 125 do
    points = points + math.floor(level + 300 * 2 ^ (level / 7))
    xp_for_level[level + 1] = math.floor(points / 4)
end

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

-- Store component locations rather than UI objects, which can be recreated.
local modified_labels = {}

local function set_level_text(interface, component_id, slot, text)
    local component = interface:GetComponent(component_id, 0, slot)
    if not component or component.type ~= ui.ComponentType.LABEL then
        return
    end

    local key = component_id .. ":" .. slot
    modified_labels[key] = {
        component_id = component_id,
        slot = slot,
        text = text,
    }

    if component.content ~= text then
        component.content = text
    end
end

local original_total = nil
local displayed_total = nil

local function update_virtual_total(interface, extra_levels)
    local component = interface:GetComponent(VIRTUAL_TOTAL, 0, VIRTUAL_TOTAL_SLOT)
    if not component or component.type ~= ui.ComponentType.LABEL then
        return
    end

    local current = component.content
    local native_total

    if current == displayed_total and original_total then
        native_total = original_total
    else
        native_total = tonumber(current)
        if not native_total then return end
        original_total = native_total
    end

    local new_total = tostring(native_total + extra_levels)
    displayed_total = new_total

    if current ~= new_total then
        component.content = new_total
    end
end

local function update_levels()
    if not Player.IsAvailable() then return end

    local interface = ui.Interfaces:GetInterface(SKILLS_INTERFACE)
    if not interface then return end
    local extra_levels = 0

    for index, skill in ipairs(skills) do
        -- Invention already uses its own virtual level system.
        if skill ~= SkillType.INVENTION then
            local level = get_virtual_level(Player.GetXPUncapped(skill))

            if level then
                extra_levels = extra_levels + (level - 120)
                local slot = index - 1
                local text = tostring(level)

                set_level_text(interface, BASE_LEVEL, slot, text)

                -- Keep boosted and drained levels visible as normal.
                if Player.GetLevelGameplay(skill) == Player.GetLevelUncapped(skill) then
                    set_level_text(interface, CURRENT_LEVEL, slot, text)
                end
            end
        end
    end
    update_virtual_total(interface, extra_levels)
end

function PluginShutdown()
    Event.Logic.Unsubscribe("true_virtual_level_refresh")

    local interface = ui.Interfaces:GetInterface(SKILLS_INTERFACE)
    local restored, skipped = 0, 0

    if interface then
        for _, label in pairs(modified_labels) do
            local component = interface:GetComponent(label.component_id, 0, label.slot)

            if component and component.type == ui.ComponentType.LABEL then
                local skill = skills[label.slot + 1]
                local native_level = Player.GetLevelUncapped(skill)

                if type(native_level) == "number" and component.content == label.text then
                    -- RuneScape's native virtual display stops at 120.
                    component.content = tostring(math.min(native_level, 120))
                    restored = restored + 1
                else
                    skipped = skipped + 1
                end
            else
                skipped = skipped + 1
            end
        end
    else
        log("True Virtual Level: Skills interface unavailable during shutdown")
    end
    if interface and original_total and displayed_total then
        local component = interface:GetComponent(VIRTUAL_TOTAL, 0, VIRTUAL_TOTAL_SLOT)

        if component
            and component.type == ui.ComponentType.LABEL
            and component.content == displayed_total then
            component.content = tostring(original_total)
        end
    end

    original_total = nil
    displayed_total = nil
    modified_labels = {}
    log("True Virtual Level: restored " .. restored .. " labels, skipped " .. skipped)
end

-- Refresh periodically so newly opened Skills panels are updated too.
local ticks = 0
Event.Logic.Subscribe("true_virtual_level_refresh", function()
    ticks = ticks + 1
    if ticks >= 10 then
        ticks = 0
        update_levels()
    end
end)

log("True Virtual Level loaded")
