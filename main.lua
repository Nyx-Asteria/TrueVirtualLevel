-- True Virtual Level: Skills interface coordinator.

-- This file reads the player's current skill XP and updates the visible Skills
-- panel labels and total. It does not change the player's actual XP or levels.
-- XP calculations live in progression.lua, saved preferences in settings.lua,
-- and the supplemental hover tooltip in hover.lua.

local SKILLS_INTERFACE = 1466
local CURRENT_LEVEL = 4
local BASE_LEVEL = 5
local VIRTUAL_TOTAL = 11
local VIRTUAL_TOTAL_SLOT = 2

-- Skills panel slots run row-by-row, independently of SkillType enum order.

local skills = {
    SkillType.ATTACK, SkillType.HITPOINTS, SkillType.MINING,
    SkillType.STRENGTH, SkillType.AGILITY, SkillType.SMITHING,
    SkillType.DEFENCE, SkillType.HERBLORE, SkillType.FISHING,
    SkillType.RANGED, SkillType.THIEVING, SkillType.COOKING,
    SkillType.PRAYER, SkillType.CRAFTING, SkillType.FIREMAKING,
    SkillType.MAGIC, SkillType.FLETCHING, SkillType.WOODCUTTING,
    SkillType.RUNECRAFTING, SkillType.SLAYER, SkillType.FARMING,
    SkillType.CONSTRUCTION, SkillType.HUNTER, SkillType.SUMMONING,
    SkillType.DUNGEONEERING, SkillType.DIVINATION, SkillType.INVENTION,
    SkillType.ARCHAEOLOGY, SkillType.NECROMANCY,
}

-- Load shared calculations and persisted settings from their dedicated modules.

local progression = require("src/progression")
local settings_module = require("src/settings")
local settings = settings_module.values
local get_virtual_level = progression.get_virtual_level
local standard_level_from_xp = progression.standard_level_from_xp
local elite = require("src/elite")

-- Standard-curve display cap; elite Invention remains native when selected.
local function capped_standard_level(level)
    return level and (settings.cap_120 and math.min(level, 120) or level)
end

-- Decide whether TVL should override a skill's displayed level.
-- Invention normally keeps its native elite XP curve; the optional setting
-- enables the standard curve for that skill instead.

local function is_extended_skill(skill)
    return skill ~= SkillType.INVENTION or settings.invention
end

-- Remember which native text labels we changed and what they originally said.
-- Store component IDs and slots rather than UI objects: the game can recreate
-- components when the interface is closed, reopened, or rebuilt.

local modified_labels = {}

-- Find a specific Skills panel label and replace its visible text.
-- Save the original text the first time we modify it so it can be restored
-- when a setting changes or the plugin shuts down. Avoid redundant writes.

local function set_level_text(interface, component_id, slot, text)
    local component = interface:GetComponent(component_id, 0, slot)
    if not component or component.type ~= ui.ComponentType.LABEL then
        return
    end

    local key = component_id .. ":" .. slot
    local previous = modified_labels[key]
    modified_labels[key] = {
        component_id = component_id,
        slot = slot,
        text = text,
        original = previous and previous.original or component.content,
    }

    if component.content ~= text then
        component.content = text
    end
end

-- Keep the game's original total separate from our displayed total.
-- Otherwise repeated refreshes could add the extra virtual levels again.

local original_total = nil
local displayed_total = nil

-- Update the visible total-level label using the native total plus TVL's
-- additional levels. If the game changes the label itself, capture that new
-- native value before applying our adjustment.

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

-- The supplemental tooltip is managed independently of the Skills labels.

local hover = require("src/hover")

-- Restore a label only if it still contains the value TVL wrote.
-- This avoids overwriting a newer value supplied by the game or another plugin.
-- Invention is special: its original label may be stale if XP was gained while
-- TVL displayed the standard curve. Read the current native level instead.

local INVENTION_SLOT = nil
for index, skill in ipairs(skills) do
    if skill == SkillType.INVENTION then
        INVENTION_SLOT = index - 1
        break
    end
end

local function restore_level_label(interface, key, label)
    local component = interface:GetComponent(label.component_id, 0, label.slot)
    if component and component.type == ui.ComponentType.LABEL
        and component.content == label.text and label.original ~= nil then
        local original = label.original
        if label.slot == INVENTION_SLOT
            and (label.component_id == BASE_LEVEL or label.component_id == CURRENT_LEVEL)
            and Player.IsAvailable() then
            -- Reconstruct the elite virtual level from XP. The uncapped
            -- level API can still report 120 after a standard-curve override.
            local elite_level = elite.level_from_xp(Player.GetXPUncapped(SkillType.INVENTION))
            if elite_level then
                original = tostring(elite_level)
            end
        end
        component.content = original
    end
    modified_labels[key] = nil
end

-- Main refresh routine: read XP, calculate virtual levels, and update labels.

-- Player.GetXPUncapped supplies XP; progression.lua translates that XP into
-- levels. The BASE_LEVEL and CURRENT_LEVEL components hold the text displayed
-- in the Skills panel. set_level_text performs the actual label replacement.
-- This runs periodically and after settings changes; it is not an XP modifier.

local function update_levels()
    if not Player.IsAvailable() then
        hover.destroy()
        return
    end

    local interface = ui.Interfaces:GetInterface(SKILLS_INTERFACE)
    if not interface then
        hover.destroy()
        return
    end
    local extra_levels = 0
    local active_labels = {}

    -- Each entry maps a SkillType to its visual slot in the Skills panel.
    -- Read current XP for eligible skills, then update only qualifying labels.
    for index, skill in ipairs(skills) do
        if is_extended_skill(skill) then
            local invention_standard = skill == SkillType.INVENTION and settings.invention
            local level
            if invention_standard then
                level = capped_standard_level(standard_level_from_xp(Player.GetXPUncapped(skill)))
            else
                level = not settings.cap_120 and get_virtual_level(Player.GetXPUncapped(skill)) or nil
            end
            if level then
                local slot = index - 1
                if invention_standard then
                    -- Native total already includes Invention's elite-curve level.
                    -- Replace that contribution rather than adding (level - 120).
                    local level_difference = elite.standard_level_difference(
                        Player.GetXPUncapped(skill), level)
                    if level_difference then
                        extra_levels = extra_levels + level_difference
                    end
                else
                    extra_levels = extra_levels + (level - 120)
                end
                local text = tostring(level)
                set_level_text(interface, BASE_LEVEL, slot, text)
                active_labels[BASE_LEVEL .. ":" .. slot] = true

                -- CURRENT_LEVEL may show temporary boosts or drains.
                -- Only replace it when gameplay and uncapped levels agree,
                -- preserving the game's temporary level indicators.
                if Player.GetLevelGameplay(skill) == Player.GetLevelUncapped(skill) then
                    set_level_text(interface, CURRENT_LEVEL, slot, text)
                    active_labels[CURRENT_LEVEL .. ":" .. slot] = true
                end
            end
        end
    end

    -- Restore labels no longer overridden by the current settings.
    for key, label in pairs(modified_labels) do
        if not active_labels[key] then
            restore_level_label(interface, key, label)
        end
    end
    update_virtual_total(interface, settings.virtual_total and extra_levels or 0)

    -- Refresh the supplemental XP tooltip.
    hover.update(interface, skills)
end

-- Register the Plugin Hub settings callback. settings.lua saves the change;
-- main.lua then refreshes the Skills panel to reflect it immediately.
-- Keep settings UI and persistence in src/settings.lua.
-- UI refresh behavior remains owned by main.lua.

settings_module.register(function(key, selected)
    if key == "hover" and not selected then
        hover.destroy()
    end
    update_levels()
end)

-- Unsubscribe and restore native labels when the plugin is disabled.
-- Only restore values still owned by TVL, then clear our cached state.

function PluginShutdown()
    Event.Logic.Unsubscribe("true_virtual_level_refresh")
    settings_module.shutdown()
    hover.destroy()

    local interface = ui.Interfaces:GetInterface(SKILLS_INTERFACE)
    if interface then
        for key, label in pairs(modified_labels) do
            restore_level_label(interface, key, label)
        end
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
end

-- Poll at a reduced frequency rather than on every game logic tick.
-- This catches XP changes and Skills panels that have been reopened or rebuilt,
-- while avoiding unnecessary UI reads and writes on each tick.
-- The refresh interval is unchanged by this documentation-only update.

local ticks = 0
Event.Logic.Subscribe("true_virtual_level_refresh", function()
    ticks = ticks + 1
    if ticks >= 10 then
        ticks = 0
        update_levels()
    end
end)

log("True Virtual Level loaded")

-- Export the public API to plugins declaring TVL as a dependency.
-- This does not change TVL's existing UI or event subscriptions.
return require("src/api")
