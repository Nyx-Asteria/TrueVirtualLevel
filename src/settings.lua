-- True Virtual Level: saved preferences and Plugin Hub controls.

-- Read the player's preferences from PersistentDB, build the settings view,
-- and notify main.lua when a setting changes. The shared values table is used
-- by main.lua and hover.lua; UI updates remain the responsibility of main.lua.

local module = {}

-- Existing PersistentDB keys are intentionally unchanged, preserving user
-- preferences across plugin updates. Hover and virtual total default to on;
-- standard-curve Invention is opt-in and defaults to off.

module.values = {
    -- Show extra XP-to-next-level details when hovering eligible skills.
    hover = PersistentDB:GetBool("tvl_hover") ~= false,
    -- Display Invention using standard XP thresholds instead of its native
    -- elite curve; this affects labels and calculations, not actual XP.
    invention = PersistentDB:GetBool("tvl_invention") == true,
    -- Include TVL's additional virtual levels in the Skills panel total.
    virtual_total = PersistentDB:GetBool("tvl_virtual_total") ~= false,
    -- Optionally stop displayed standard virtual levels at 120.
    cap_120 = PersistentDB:GetBool("tvl_cap_120") == true,
}

-- Hold the active settings view so it can be replaced or destroyed cleanly.
local settings_view = nil
local settings_parent = nil
local settings_changed = nil
local build_settings_view

-- Create one checkbox and its explanatory text.
-- On change, update the shared in-memory value, save it under its existing
-- database key, then ask main.lua to refresh the displayed skill information.

local function setting_checkbox(view, title, key, persistence_key, description, on_change)
    view:AddCheckboxButton({
        { text = title, value = key, selected = module.values[key] },
    }, {
        onChange = function(_, _, _, selected)
            module.values[key] = selected
            if persistence_key then
                PersistentDB:SetBool(persistence_key, selected)
            end
            on_change(key, selected)
        end,
    })
    view:AddText(description)
end

-- Build the settings view when RuneScape supplies the Plugin Hub layer.
-- The layer can be recreated, so destroy any previous view before rebuilding.
-- The callback comes from main.lua and runs after each preference change.

build_settings_view = function(parent, on_change)
        if settings_view then settings_view:Destroy() end
        if not parent then return end
        settings_view = prettyui.SimpleView.new(parent, {
            width = parent.width,
            height = parent.height,
        })
        -- Display options control the supplemental hover and virtual total.
        settings_view:AddTitle("Display")
        setting_checkbox(settings_view, "Extended skill tooltips", "hover", "tvl_hover",
            "Show virtual levels and remaining XP when hovering a skill at level 120 or above.", on_change)
        setting_checkbox(settings_view, "Extended virtual total", "virtual_total", "tvl_virtual_total",
            "Include levels above 120 in the Skills panel total.", on_change)

        -- Invention uses a different native XP curve, so changing this option
        -- changes which level TVL calculates from the player's existing XP.
        settings_view:AddTitle("XP curve")
        -- A radio group enforces a single selected curve without rebuilding
        -- the settings view (which would reset the scroll position).
        settings_view:AddRadioButton({
            { text = "Invention uses Elite Curve (default)", value = "elite" },
            { text = "Invention uses Standard Curve", value = "standard" },
        }, {
            selectedValue = module.values.invention and "standard" or "elite",
            onChange = function(_, value)
                if value ~= "elite" and value ~= "standard" then return end
                local use_standard = value == "standard"
                if module.values.invention == use_standard then return end
                module.values.invention = use_standard
                PersistentDB:SetBool("tvl_invention", use_standard)
                on_change("invention", use_standard)
            end,
        })
        settings_view:AddText("Choose whether Invention displays its native elite XP curve or the standard XP curve. This does not change your XP.")

        -- Keep the cap option last; it is especially useful to API consumers.
        settings_view:AddTitle("Virtual level cap")
        setting_checkbox(settings_view, "Cap virtual levels at 120", "cap_120", "tvl_cap_120",
            "Limit standard-curve virtual levels to 120 instead of 126. Especially useful for plugins using TVL's API. XP is unchanged.", on_change)
end

-- Programmatic changes use the same persistence and refresh path as the UI.
-- Rebuild the active settings view so its checkbox reflects the new value.
function module.set_cap_120(enabled)
    if type(enabled) ~= "boolean" then return false end
    if module.values.cap_120 == enabled then return true end
    module.values.cap_120 = enabled
    PersistentDB:SetBool("tvl_cap_120", enabled)
    if settings_changed then settings_changed("cap_120", enabled) end
    if settings_parent and settings_changed then
        build_settings_view(settings_parent, settings_changed)
    end
    return true
end

function module.register(on_change)
    settings_changed = on_change
    Event.SettingsLayerReady.Subscribe("true_virtual_level_settings", function(event)
        settings_parent = event.component
        build_settings_view(settings_parent, on_change)
    end)
end

-- Remove the settings subscription and destroy the view on plugin shutdown.
-- Prevents stale controls and callbacks from surviving a plugin reload.

function module.shutdown()
    Event.SettingsLayerReady.Unsubscribe("true_virtual_level_settings")
    if settings_view then
        settings_view:Destroy()
        settings_view = nil
    end
    settings_parent = nil
    settings_changed = nil
end

return module
