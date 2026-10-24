-- True Virtual Level: supplemental Skills hover tooltip.

-- This module detects which skill cell the mouse is over, builds the extra XP
-- information, positions the tooltip beside that cell, and destroys it when
-- no longer needed. Progression calculations and saved settings are imported.
-- Coordinate handling is preserved as-is; scaling fixes belong to a later commit.

local progression = require("src/progression")
local settings = require("src/settings").values
local MAX_XP = progression.MAX_XP
local xp_for_level = progression.xp_for_level
local standard_level_from_xp = progression.standard_level_from_xp
local get_hover_level = progression.get_hover_level
local hover = {}

local function display_level(level)
    return settings.cap_120 and math.min(level, 120) or level
end

-- Track the current tooltip and the skill/interface it belongs to.
-- Reuse it while the same cell is hovered; recreate it when the target changes.
-- The error flag prevents repeated log messages if the UI API is unavailable.

local hover_panel = nil
local hover_panel_slot = nil
local hover_panel_interface = nil
local hover_labels = nil
local hover_logged_error = false

-- Add thousands separators to XP values for readable tooltip text.
-- This affects presentation only; the underlying XP remains numeric.

local function format_xp(value)
    local text = tostring(math.floor(value))
    while true do
        local updated, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = updated
        if count == 0 then return text end
    end
end

-- Build the three text lines for the currently selected progression curve.
-- At level 126, track remaining XP toward the cap rather than another level.

local function hover_lines(level, xp)
    local level_cap = settings.cap_120 and 120 or 126
    if xp >= MAX_XP then
        return {
            "True virtual level: " .. level,
            "XP Cap Reached!",
            "Remaining: 0",
        }
    end
    if level >= level_cap then
        return {
            "True virtual level: " .. level,
            "XP cap: " .. format_xp(MAX_XP),
            "Remaining: " .. format_xp(math.max(0, MAX_XP - xp)),
        }
    end
    local threshold = xp_for_level[level + 1]
    return {
        "True virtual level: " .. level,
        "Next level: " .. format_xp(threshold),
        "Remainder: " .. format_xp(math.max(0, threshold - xp)),
    }
end

-- Dispose of the PrettyUI tooltip and clear references to its UI objects.
-- Called when hovering stops, the feature is disabled, or the plugin shuts down.

local function destroy_hover_panel()
    if hover_panel then pcall(function() hover_panel:Destroy() end) end
    hover_panel = nil
    hover_panel_slot = nil
    hover_panel_interface = nil
    hover_labels = nil
end

-- Resolve a skill component's approximate screen position by walking parents.
-- Child positions are relative to their containers, so add ancestor offsets
-- and subtract scrolling. These coordinates are an existing assumption that
-- still needs testing at different interface scales and window sizes.

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

-- Find a top-level UI layer that can host the supplemental tooltip.
-- Prefer the plugin overlay layer, falling back to the game area when needed.

local function hover_overlay_parent()
    if not id or not id.Component then return nil end
    local key = id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP
        or id.Component.TOPLEVEL_V2__GAME_AREA
    if not key then return nil end
    return ui.Interfaces:GetComponent(key)
end

-- Refresh the tooltip for the skill currently under the mouse.
-- Check the user setting and PrettyUI availability before reading skill cells.
-- The caller provides the live Skills interface and its visual skill order.

local function update_hover_panel(interface, skills)
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

    -- Locate the hovered skill cell. The native skill component exposes
    -- isMouseOver; the XP and selected curve determine our supplemental text.
    local hovered_slot, hovered_level, hovered_xp = nil, nil, nil
    for index, skill in ipairs(skills) do
        if skill ~= SkillType.INVENTION or settings.invention then
            local slot = index - 1
            local component = interface:GetComponent(2, 0, slot)
            if component and component.isMouseOver then
                local xp = Player.GetXPUncapped(skill)
                local level = (skill == SkillType.INVENTION and settings.invention)
                    and standard_level_from_xp(xp) or get_hover_level(xp)
                if level then level = display_level(level) end
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

    -- No eligible hovered skill means there is nothing to display.
    if not hovered_slot then destroy_hover_panel() return end
    local lines = hover_lines(hovered_level, hovered_xp)
    -- Update existing text in place when the mouse stays on the same skill.
    -- Recreating the UI every refresh would cause unnecessary churn.
    if hover_panel and hover_panel_slot == hovered_slot
        and hover_panel_interface == interface and hover_labels then
        for i, value in ipairs(lines) do
            hover_labels[i].content = value
        end
        pcall(function() hover_panel:Update() end)
        return
    end
    destroy_hover_panel()

    -- Create the anchored PrettyUI panel. Protected calls keep a tooltip
    -- failure from interrupting the rest of the Skills interface refresh.
    local ok, result = pcall(function()
        return prettyui.AnchoredTooltip.new(parent, {
            width = 145,
            height = 57,
            padding = 4,
            backgroundColour = 0x100D09FF,
            backgroundAlpha = 1.0,
            -- Re-read the cell's position whenever PrettyUI updates the
            -- anchor; the existing offsets are deliberately unchanged.
            anchor = function()
                local component = interface:GetComponent(2, 0, hovered_slot)
                local x, y, w, h = screen_rect(component)
                if not x then return nil end
                return Vector2.new(x + 73, y + h + 4)
            end,
            buildContent = function(tooltip, content)
                -- Draw a backing rectangle and three readable XP labels.
                -- Font, dimensions, and colors match the previous build.
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
                    label:SetSize(139, 16)
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

-- Public module entry points used by main.lua.
hover.update = update_hover_panel
hover.destroy = destroy_hover_panel
return hover
