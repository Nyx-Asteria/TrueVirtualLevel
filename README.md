# True Virtual Level

**See your true levels, not just the level cap.**

True Virtual Level is a RuneScape plugin that extends the game's existing **Skills interface** to show virtual levels earned through XP beyond the usual displayed level caps. It works within the familiar Skills panel rather than replacing it with a separate interface.

**[View True Virtual Level on Mod.io](https://mod.io/g/runescape/m/true-virtual-level)**

## Features

- **Virtual skill levels:** Display standard-curve virtual levels up to **126**, or optionally cap them at **120**, directly in the Skills interface.
- **Extended virtual total:** Optionally include additional virtual levels in the total shown in the Skills panel.
- **Extended skill tooltips:** See additional level and XP-to-next-level information when hovering eligible skills at level 120 or above.
- **Invention curve choice:** Keep Invention's native elite XP curve or optionally display it using the standard XP curve.
- **Native interface behavior:** Preserve boosted and drained skill levels rather than treating temporary changes as earned XP.
- **200 million XP milestone:** At the selected standard-curve virtual level cap (120 or 126), continue tracking progress toward 200 million XP rather than a nonexistent next virtual level.

True Virtual Level changes **how progression is displayed**, not the XP, levels, or progression rules stored by the game.

## Installation

Install **True Virtual Level** from its [Mod.io page](https://mod.io/g/runescape/m/true-virtual-level) using RuneScape's supported plugin installation workflow. The plugin requires **PrettyUI**, which is declared as a required dependency in its manifest.

## Settings

Open the RuneScape **Plugin Hub**, find **True Virtual Level**, and open its settings.

| Setting | What it does | Default |
| --- | --- | --- |
| **Extended skill tooltips** | Shows additional virtual-level and remaining-XP details when hovering eligible skills at level 120 or above. | On |
| **Extended virtual total** | Includes levels above 120 in the Skills panel's displayed total. | On |
| **Use standard XP curve** (Invention) | Displays Invention using standard skill XP thresholds rather than its native elite curve. | Off |
| **Cap virtual levels at 120** | Limits standard-curve virtual levels to 120 rather than 126. Especially useful for plugins using TVL’s API. | Off |

### Understanding Invention

Invention uses a different, **elite** XP curve from most other skills. By default, True Virtual Level preserves Invention's native progression, which supports levels up to **150**. If you enable **Use standard XP curve**, TVL instead calculates Invention's displayed virtual level using the standard curve, up to **126**, or **120** when the optional cap is enabled.

This is a **display preference**. It does not change your actual Invention XP or the game's underlying progression.

### Virtual level cap

**Cap virtual levels at 120** is the last setting in TVL’s settings panel. It is off by default, preserving standard-curve levels through 126. When enabled, standard-curve skills stop displaying virtual levels above 120; native elite-curve Invention retains its own progression through 150. The cap changes displayed progression, not earned XP. At the configured cap, the hover and progression calculations continue tracking XP toward the 200 million milestone.

This option is particularly useful for plugins that use TVL’s API and prefer a level-120 ceiling. Other plugins can also read or change the saved preference through the API, as described below.

## Public API for plugin developers

True Virtual Level exposes a **Lua API** so other RuneScape plugins can use the same virtual-level calculations and respect the player's Invention curve and level-cap preferences. The API is exported from `main.lua` and implemented in `src/api.lua`.

The public API has its **own version number**, separate from the plugin's release version. The currently implemented API version reported by `GetAPIVersion()` is `1.1.0`.

### Declare an optional dependency

During local development, a consumer plugin can declare TVL using its development folder name:

```json
{
  "optionalDependencies": {
    "tvl": "TrueVirtualLevel"
  }
}
```

**Before publishing a consumer plugin**, replace `"TrueVirtualLevel"` with True Virtual Level's **Numeric ID** `"6471068"`. The URL slug `true-virtual-level` is **not** the numeric ID. The alias `tvl` is the name used to access the dependency in Lua.

This JSON fragment shows the optional dependency entry; add it to your existing `plugin.json` rather than replacing the entire manifest. JSON does not support comments.

### Call the API

```lua
-- "tvl" is supplied by the optionalDependencies alias above.
-- An optional dependency may be unavailable, so check before using it.
if type(tvl) == "table" and type(tvl.GetProgress) == "function" then
    local xp = Player.GetXPUncapped(SkillType.ATTACK)
    local progress = tvl.GetProgress(SkillType.ATTACK, xp)

    if progress then
        print("Virtual level: " .. progress.level)
        print("XP remaining: " .. progress.remainingXP)
        print("Progress: " .. math.floor(progress.progress * 100) .. "%")
    end
end
```

### Available functions

| Function | Returns |
| --- | --- |
| `GetAPIVersion()` | API version string, currently `"1.1.0"`. |
| `GetInventionCurve()` | `"elite"` or `"standard"`, reflecting the current Invention setting. |
| `GetMaxXP()` | Supported XP cap: `200000000`. |
| `GetMaxVirtualLevel(skill, cap_override?)` | `150` for native elite Invention; otherwise the configured standard-curve cap or optional override (`120` or `126`). |
| `GetLevelCap120()` | Boolean indicating whether the optional standard-curve level-120 cap is enabled. |
| `SetLevelCap120(enabled)` | Sets the saved level-cap preference using a boolean (`true` or `false`); returns `false` for invalid input. |
| `GetXPForLevel(skill, level, cap_override?)` | Standard-curve XP threshold up to the effective cap; `nil` for native elite Invention or unavailable levels. |
| `GetVirtualLevel(skill, xp, cap_override?)` | Calculated standard-curve level limited by the effective cap; retains `nil` for native elite Invention. |
| `GetProgress(skill, xp, cap_override?)` | Progress for standard skills **and native elite Invention**; `nil` for invalid inputs. |

For `skill`, pass a RuneScape `SkillType` value such as `SkillType.ATTACK` or `SkillType.INVENTION`. XP values are numbers, not formatted strings.

### `GetProgress` result

`GetProgress(skill, xp, cap_override?)` returns these fields for standard skills and native elite Invention:

| Field | Meaning |
| --- | --- |
| `level` | Current calculated virtual level. |
| `maxLevel` | Maximum supported level for this calculation. |
| `currentXP` | Supplied XP clamped to the range from zero to 200 million. |
| `levelXP` | XP threshold at the current virtual level. |
| `nextXP` | XP threshold for the next target. |
| `remainingXP` | XP remaining until that target. |
| `progress` | Fractional progress between `0` and `1` (multiply by 100 for a percentage). |
| `targetType` | `"level"` for the next level, or `"xp_cap"` for the 200 million XP milestone at the effective maximum (standard 120/126 or elite 150). |

### Reading and changing the level cap

The 120 cap is a **shared, saved TVL preference**, not a per-plugin override. Changing it affects TVL’s own Skills interface and the progression results seen by other API consumers.

```lua
-- Read the player’s current cap preference.
if type(tvl) == "table" and type(tvl.GetLevelCap120) == "function" then
    local capped_at_120 = tvl.GetLevelCap120()
end

-- Only change the preference after the player chooses to do so.
if type(tvl) == "table" and type(tvl.SetLevelCap120) == "function" then
    local success = tvl.SetLevelCap120(true)  -- Set standard-curve cap to 120.
    -- tvl.SetLevelCap120(false) restores the default cap of 126.
end
```

`SetLevelCap120(enabled)` accepts a boolean, saves the setting, and requests a refresh of TVL’s Skills interface. It returns `false` for non-boolean arguments. The TVL settings checkbox also reflects changes made through the API.

**Guidance for plugin developers:** Plugins that call `SetLevelCap120()` are **strongly encouraged to provide a user-facing setting** that explains the change and lets the player override or disable it. Do not silently or repeatedly force a preferred cap, particularly when the player has changed TVL’s own setting. Provide a straightforward way to reverse the change. If an integration only needs progression data, prefer the read-only API methods.

### Calculation-only level cap overrides

`GetProgress`, `GetVirtualLevel`, `GetMaxVirtualLevel`, and `GetXPForLevel` accept an optional final argument of **`120`** or **`126`**. Omit it to follow the player's saved TVL preference. The override affects only that call: it **does not change** the player's TVL setting or the Skills interface. An unsupported override returns `nil`.

```lua
local xp = Player.GetXPUncapped(SkillType.ATTACK)
local follows_tvl = tvl.GetProgress(SkillType.ATTACK, xp)
local cap_120 = tvl.GetProgress(SkillType.ATTACK, xp, 120)
local cap_126 = tvl.GetProgress(SkillType.ATTACK, xp, 126)
```

For native elite Invention, the maximum remains **150**, regardless of the optional standard-curve override. At the chosen maximum level, progress targets the 200 million XP milestone. Use overrides for a consumer plugin's own display preferences instead of calling `SetLevelCap120()` and modifying the player's saved TVL preference.

### Invention compatibility and fallbacks

When Invention uses its **native elite curve**, `GetProgress(SkillType.INVENTION, xp)` now returns level, thresholds, remaining XP, and fractional progress through level **150** using TVL's native elite XP table. `GetXPForLevel()` and `GetVirtualLevel()` **still return `nil`** for native elite Invention to preserve their existing behavior. When the player selects standard Invention, all progression methods use the standard curve.

**Compatibility note:** Prior API versions returned `nil` from `GetProgress()` for native elite Invention. Integrations that relied on that sentinel should check `GetInventionCurve()` explicitly. The API version is now **1.1.0**.

Because TVL is an **optional** dependency, integrations should continue working when TVL is not installed or enabled. Check that the dependency and requested functions exist, and handle `nil` results. `GetInventionCurve()` reads the current setting each time it is called, so consumers can request an updated value after the player changes the preference.

The public API has been tested through an optional Level Lens integration, including standard skill progression, Invention curve selection, and progress calculations toward the 200 million XP cap.

## License

The original True Virtual Level source code is available under the **MIT License**. See [LICENSE](LICENSE) for the license text and the separate notice regarding Jagex intellectual property.

## Jagex EULA

> This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User Licence Agreement (EULA) found at https://legal.jagex.com/docs/terms/eula (and all terms incorporated into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.

RuneScape and associated intellectual property belong to Jagex and/or its licensors. True Virtual Level is an independently developed plugin and is not an official Jagex product.
