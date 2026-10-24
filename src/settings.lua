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
}

-- Hold the active settings view so it can be replaced or destroyed cleanly.
local settings_view = nil

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

function module.register(on_change)
    Event.SettingsLayerReady.Subscribe("true_virtual_level_settings", function(event)
        if settings_view then settings_view:Destroy() end
        local parent = event.component
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
        settings_view:AddTitle("Invention")
        setting_checkbox(settings_view, "Use standard XP curve", "invention", "tvl_invention",
            "Calculate Invention using the standard XP curve instead of its elite curve.", on_change)
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
end

return module
