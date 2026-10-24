# True Virtual Level

**See your true levels, not just the level cap.**

True Virtual Level is a RuneScape plugin that extends the game's existing **Skills interface** to show virtual levels earned through XP beyond the usual displayed level caps. It works within the familiar Skills panel rather than replacing it with a separate interface.

**[View True Virtual Level on Mod.io](https://mod.io/g/runescape/m/true-virtual-level)**

## Features

- **Virtual skill levels:** Display standard-curve virtual levels up to **126** directly in the Skills interface.
- **Extended virtual total:** Optionally include additional virtual levels in the total shown in the Skills panel.
- **Extended skill tooltips:** See additional level and XP-to-next-level information when hovering eligible skills at level 120 or above.
- **Invention curve choice:** Keep Invention's native elite XP curve or optionally display it using the standard XP curve.
- **Native interface behavior:** Preserve boosted and drained skill levels rather than treating temporary changes as earned XP.
- **200 million XP milestone:** At virtual level 126, progression toward 200 million XP is treated as the final XP milestone, not as progress toward a nonexistent level 127.

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

### Understanding Invention

Invention uses a different, **elite** XP curve from most other skills. By default, True Virtual Level preserves Invention's native progression, which supports levels up to **150**. If you enable **Use standard XP curve**, TVL instead calculates Invention's displayed virtual level using the standard curve, up to **126**.

This is a **display preference**. It does not change your actual Invention XP or the game's underlying progression.

## Public API for plugin developers

True Virtual Level exposes a **read-only Lua API** so other RuneScape plugins can use the same virtual-level calculations and respect the player's Invention curve preference. The API is exported from `main.lua` and implemented in `src/api.lua`.

The public API has its **own version number**, separate from the plugin's release version. The currently implemented API version is `1.0.0`.

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
| `GetAPIVersion()` | API version string, currently `"1.0.0"`. |
| `GetInventionCurve()` | `"elite"` or `"standard"`, reflecting the current Invention setting. |
| `GetMaxXP()` | Supported XP cap: `200000000`. |
| `GetMaxVirtualLevel(skill)` | `150` for native elite-curve Invention; otherwise `126`. |
| `GetXPForLevel(skill, level)` | Standard-curve XP threshold for a supported level, or `nil` when unavailable. |
| `GetVirtualLevel(skill, xp)` | Calculated standard-curve virtual level, or `nil` when unavailable. |
| `GetProgress(skill, xp)` | Table describing standard-curve level and XP progress, or `nil` when unavailable. |

For `skill`, pass a RuneScape `SkillType` value such as `SkillType.ATTACK` or `SkillType.INVENTION`. XP values are numbers, not formatted strings.

### `GetProgress` result

`GetProgress(skill, xp)` returns these fields when the selected curve is supported:

| Field | Meaning |
| --- | --- |
| `level` | Current calculated virtual level. |
| `maxLevel` | Maximum supported level for this calculation. |
| `currentXP` | Supplied XP clamped to the range from zero to 200 million. |
| `levelXP` | XP threshold at the current virtual level. |
| `nextXP` | XP threshold for the next target. |
| `remainingXP` | XP remaining until that target. |
| `progress` | Fractional progress between `0` and `1` (multiply by 100 for a percentage). |
| `targetType` | `"level"` for the next level, or `"xp_cap"` for the 200 million XP milestone at level 126. |

### Invention compatibility and fallbacks

When Invention is using its **native elite curve**, `GetXPForLevel`, `GetVirtualLevel`, and `GetProgress` return **`nil`** for Invention. This is intentional: TVL does not apply the standard XP formula to elite progression. Consumer plugins should use the game's native Invention information or their own elite-curve handling in that case.

Because TVL is an **optional** dependency, integrations should continue working when TVL is not installed or enabled. Check that the dependency and requested functions exist, and handle `nil` results. `GetInventionCurve()` reads the current setting each time it is called, so consumers can request an updated value after the player changes the preference.

The public API was tested from a separate Level Lens development build using an optional dependency, including calculations at 100 million and 200 million XP. This test confirms cross-plugin access; it does not mean Level Lens currently uses TVL for its normal progress bars.

## License

The original True Virtual Level source code is available under the **MIT License**. See [LICENSE](LICENSE) for the license text and the separate notice regarding Jagex intellectual property.

## Jagex EULA

> This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User Licence Agreement (EULA) found at https://legal.jagex.com/docs/terms/eula (and all terms incorporated into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.

RuneScape and associated intellectual property belong to Jagex and/or its licensors. True Virtual Level is an independently developed plugin and is not an official Jagex product.
