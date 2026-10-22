-- True Virtual Level
-- Extends virtual levels to 126 in RuneScape's Skills panel.

local SKILLS_INTERFACE = 1466
local CURRENT_LEVEL = 4
local BASE_LEVEL = 5
local VIRTUAL_TOTAL = 11
local VIRTUAL_TOTAL_SLOT = 2
local MAX_XP = 200000000

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

-- Settings default to enabled tooltips and virtual total.
local settings = {
    hover = PersistentDB:GetBool("tvl_hover") ~= false,
    invention = PersistentDB:GetBool("tvl_invention") == true,
    virtual_total = PersistentDB:GetBool("tvl_virtual_total") ~= false,
}

local settings_view = nil

local function is_extended_skill(skill)
    return skill ~= SkillType.INVENTION or settings.invention
end

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

-- Invention can optionally use the standard curve at any level.
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

-- Tooltips start at 120; native virtual labels start at 121.
local function get_hover_level(xp)
    if type(xp) ~= "number" or xp < xp_for_level[120] then
        return nil
    end
    return get_virtual_level(xp) or 120
end

-- Store component locations rather than UI objects, which can be recreated.
local modified_labels = {}

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

-- Additional XP details alongside the native Skills tooltip.
local hover_panel = nil
local hover_panel_slot = nil
local hover_panel_interface = nil
local hover_labels = nil
local hover_logged_error = false

local function format_xp(value)
    local text = tostring(math.floor(value))
    while true do
        local updated, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = updated
        if count == 0 then return text end
    end
end

-- Format the tooltip for the selected XP curve.
local function hover_lines(level, xp)
    if level >= 126 or xp >= MAX_XP then
        return {
            "True virtual level: " .. level,
            "Next level: Max level",
            "Remainder: 0",
        }
    end
    local threshold = xp_for_level[level + 1]
    return {
        "True virtual level: " .. level,
        "Next level: " .. format_xp(threshold),
        "Remainder: " .. format_xp(math.max(0, threshold - xp)),
    }
end

local function destroy_hover_panel()
    if hover_panel then pcall(function() hover_panel:Destroy() end) end
    hover_panel = nil
    hover_panel_slot = nil
    hover_panel_interface = nil
    hover_labels = nil
end

-- Resolve screen coordinates through the movable interface hierarchy.
local function screen_rect(component)
    if not component then return nil end

    local x, y = 0, 0
    local current = component
    local seen = {}
    local depth = 0
    while current and depth < 20 do
        local key = tostring(current)
        if seen[key] then break end
        seen[key] = true
        local ok, px, py, sx, sy, parent = pcall(function()
            return current.x, current.y, current.scrollX, current.scrollY, current.parent
        end)
        if not ok then break end
        if type(px) == "number" then x = x + px end
        if type(py) == "number" then y = y + py end
        -- Account for scrolling within parent containers.
        if parent then
            if type(sx) == "number" then x = x - sx end
            if type(sy) == "number" then y = y - sy end
        end
        current = parent
        depth = depth + 1
    end
    local ok, width, height = pcall(function()
        return component.width, component.height
    end)
    if not ok then return nil end
    if depth < 2 then return nil end
    return x, y, width or 60, height or 27
end

local function hover_overlay_parent()
    if not id or not id.Component then return nil end
    local key = id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP
        or id.Component.TOPLEVEL_V2__GAME_AREA
    if not key then return nil end
    return ui.Interfaces:GetComponent(key)
end

local function update_hover_panel(interface)
    if not settings.hover then
        destroy_hover_panel()
        return
    end
    if not prettyui or not prettyui.AnchoredTooltip then
        if not hover_logged_error then
            log("TVL hover: PrettyUI AnchoredTooltip unavailable")
            hover_logged_error = true
        end
        return
    end
    local parent = hover_overlay_parent()
    if not parent then
        if not hover_logged_error then
            log("TVL hover: overlay parent unavailable")
            hover_logged_error = true
        end
        return
    end

    local hovered_slot, hovered_level, hovered_xp = nil, nil, nil
    for index, skill in ipairs(skills) do
        if is_extended_skill(skill) then
            local slot = index - 1
            local component = interface:GetComponent(2, 0, slot)
            if component and component.isMouseOver then
                local xp = Player.GetXPUncapped(skill)
                local level = (skill == SkillType.INVENTION and settings.invention)
                    and standard_level_from_xp(xp) or get_hover_level(xp)
                if level then
                    local x = screen_rect(component)
                    if not x and not hover_logged_error then
                        log("TVL hover: native skill coordinates unavailable for slot " .. slot)
                        hover_logged_error = true
                    end
                    if x then
                        hovered_slot, hovered_level, hovered_xp = slot, level, xp
                        break
                    end
                end
            end
        end
    end

    if not hovered_slot then destroy_hover_panel() return end
    local lines = hover_lines(hovered_level, hovered_xp)
    if hover_panel and hover_panel_slot == hovered_slot
        and hover_panel_interface == interface and hover_labels then
        for i, value in ipairs(lines) do
            hover_labels[i].content = value
        end
        pcall(function() hover_panel:Update() end)
        return
    end
    destroy_hover_panel()

    local ok, result = pcall(function()
        return prettyui.AnchoredTooltip.new(parent, {
            width = 178,
            height = 57,
            padding = 4,
            backgroundColour = 0x100D09FF,
            backgroundAlpha = 1.0,
            -- Anchor the tooltip to the skill cell.
            anchor = function()
                local component = interface:GetComponent(2, 0, hovered_slot)
                local x, y, w, h = screen_rect(component)
                if not x then return nil end
                return Vector2.new(x + 48, y + h + 4)
            end,
            buildContent = function(tooltip, content)
                -- Opaque backing beneath the tooltip text.
                local background = ui.Rectangle.new(content)
                background:SetPos(0, 0)
                background:SetSize(0, 0, 1.0, 1.0)
                background.fill = true
                background.colour = Vector4.new(0.055, 0.045, 0.032, 1.0)

                local labels = {}
                local values = lines
                for i = 1, #values do
                    local label = ui.Text.new(content)
                    label:SetPos(2, (i - 1) * 16)
                    label:SetSize(168, 16)
                    label.content = values[i]
                    label.rgba = 0xF4E5BFFF
                    if id and id.Font and id.Font.NOTOSANS_12 then
                        label.font = id.Font.NOTOSANS_12
                    end
                    labels[i] = label
                end
                return labels
            end,
        })
    end)
    if ok and result then
        hover_panel = result
        hover_panel_slot = hovered_slot
        hover_panel_interface = interface
        hover_labels = result.contentResult
    elseif not hover_logged_error then
        log("TVL hover panel creation error: " .. tostring(result))
        hover_logged_error = true
    end
end

-- Restore a plugin-written label only when its content still matches ours.
local function restore_level_label(interface, key, label)
    local component = interface:GetComponent(label.component_id, 0, label.slot)
    if component and component.type == ui.ComponentType.LABEL
        and component.content == label.text and label.original ~= nil then
        component.content = label.original
    end
    modified_labels[key] = nil
end

local function update_levels()
    if not Player.IsAvailable() then
        destroy_hover_panel()
        return
    end

    local interface = ui.Interfaces:GetInterface(SKILLS_INTERFACE)
    if not interface then
        destroy_hover_panel()
        return
    end
    local extra_levels = 0
    local active_labels = {}

    for index, skill in ipairs(skills) do
        if is_extended_skill(skill) then
            local invention_standard = skill == SkillType.INVENTION and settings.invention
            local level
            if invention_standard then
                level = standard_level_from_xp(Player.GetXPUncapped(skill))
            else
                level = get_virtual_level(Player.GetXPUncapped(skill))
            end
            if level then
                local slot = index - 1
                if invention_standard then
                    -- Native total already includes Invention's elite-curve level.
                    -- Replace that contribution rather than adding (level - 120).
                    local key = BASE_LEVEL .. ":" .. slot
                    local saved = modified_labels[key]
                    local base = interface:GetComponent(BASE_LEVEL, 0, slot)
                    local native_level = tonumber(saved and saved.original or
                        (base and base.content))
                    if native_level then
                        extra_levels = extra_levels + level - native_level
                    end
                else
                    extra_levels = extra_levels + (level - 120)
                end
                local text = tostring(level)
                set_level_text(interface, BASE_LEVEL, slot, text)
                active_labels[BASE_LEVEL .. ":" .. slot] = true

                -- Keep real boosted and drained levels visible as normal.
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
    update_hover_panel(interface)
end

-- Plugin Hub settings.
local function setting_checkbox(view, title, key, persistence_key, description)
    view:AddCheckboxButton({
        { text = title, value = key, selected = settings[key] },
    }, {
        onChange = function(_, _, _, selected)
            settings[key] = selected
            if persistence_key then
                PersistentDB:SetBool(persistence_key, selected)
            end
            if key == "hover" and not selected then
                destroy_hover_panel()
            end
            update_levels()
        end,
    })
    view:AddText(description)
end

Event.SettingsLayerReady.Subscribe("true_virtual_level_settings", function(event)
    if settings_view then settings_view:Destroy() end
    local parent = event.component
    if not parent then return end
    settings_view = prettyui.SimpleView.new(parent, {
        width = parent.width,
        height = parent.height,
    })
    settings_view:AddTitle("Display")
    setting_checkbox(settings_view, "Extended skill tooltips", "hover", "tvl_hover",
        "Show virtual levels and remaining XP when hovering a skill at level 120 or above.")
    setting_checkbox(settings_view, "Extended virtual total", "virtual_total", "tvl_virtual_total",
        "Include levels above 120 in the Skills panel total.")

    settings_view:AddTitle("Invention")
    setting_checkbox(settings_view, "Use standard XP curve", "invention", "tvl_invention",
        "Calculate Invention using the standard XP curve instead of its elite curve.")
end)

function PluginShutdown()
    Event.Logic.Unsubscribe("true_virtual_level_refresh")
    Event.SettingsLayerReady.Unsubscribe("true_virtual_level_settings")
    if settings_view then
        settings_view:Destroy()
        settings_view = nil
    end
    destroy_hover_panel()

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
