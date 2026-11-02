# Battery Meter: design

## Intent and why

A personal native macOS app that tells its owner honestly how long their MacBook battery lasts. macOS's own battery estimate and Battery settings are "not good enough": the owner wants real hours, and wants the battery details macOS keeps but doesn't show. The look of the app matters as much as the numbers. A screen that looks off is a failure even if the data is right.

## Goals

1. **Hours left right now**, based on actual current power draw, not a fixed guess. This is the headline number.
2. **Hours per full charge**, learned over time from real usage, shrinking as the battery ages.
3. **Battery health details** that macOS hides or rounds. On the owner's Mac (verified with a read-only check):
   - Real health: FullChargeCapacity / DesignCapacity = 4575 / 4629 mAh = 98.8%, where macOS shows "100%".
   - Cycle count against the rated limit (8 of 1000).
   - Live power draw (about 4.2 W), voltage and amperage.
   - Charger wattage, charging state, and why it isn't charging.
4. **History**: record readings in the background so capacity, cycles and full-charge hours can be charted over months.
5. **Native look and feel**: it should look like part of macOS (system font, translucent materials, system colors, light and dark mode).

## Surfaces (version one)

1. **Menu bar item** showing hours left (for example "🔋 6h 40m") next to the clock.
2. **Popover** opened from the menu bar item, Control Center style:
   - big hours-left number
   - charge bar with percent and power source
   - tiles for: hours per full charge, health %, cycle count, current power draw
   - an "Open history…" link at the bottom
3. **Full window**, System Settings style, with a sidebar (Overview, History, Health, Settings), big numbers, and clean charts of full-charge hours and capacity over time.

The approved mockup direction is the popover (option A in the brainstorm); the owner then asked for the full window as well. Mockups are in `.superpowers/brainstorm/`.

## Non-goals

- Not distributed or sold: personal use first. No App Store, signing or notarization work unless asked later.
- No controlling the battery (no charge limiting). Read-only.
- No iPhone/iPad, no cloud sync, no accounts.

## Anti-goals

- Numbers that jump around wildly (the complaint about macOS's estimate).
- Anything that looks non-native or unpolished.
- Showing values the hardware doesn't provide (temperature and manufacture date are not exposed on this Mac, so they are left out).

## Constraints

- Native macOS app. Data comes from the AppleSmartBattery IOKit service (`ioreg -rn AppleSmartBattery` shows the keys) and the IOPowerSources APIs.
- Signed integer values appear as huge unsigned numbers (for example Amperage 18446744073709551254 is -362 mA) and must be converted.
- Must follow light and dark mode.

## Decisions made by the owner

- Native macOS.
- Menu bar popover plus a full window, both in version one.
- Tools are left to the builder.

## Decisions made by the assistant (the owner has not confirmed these)

- Swift and SwiftUI, with Swift Charts for charts and `MenuBarExtra` for the menu bar item.
- Background recording via a lightweight sampler inside the app. How often to sample, and how long to keep history, is left to the builder.
- Temperature tile dropped; replaced by power draw.
- Formula for hours left (smoothed current draw against remaining capacity) is left to the builder, with the requirement that it be steadier than macOS's estimate.
- **Target:** the macOS version on the owner's Mac (builder checks with `sw_vers`), this Mac only. If a Mac has no battery or a key is missing, show a calm empty state instead of crashing.
- **While charging or on AC:** the menu bar and popover show time to full while charging, and "Plugged in" when full or idle. Hours left is only shown on battery.
- **Hours per full charge, cold start:** until there is enough history, seed it from full capacity divided by current draw and label it "estimate". Weight it toward recent discharge sessions.
- **Recording:** the app is a menu bar app that stays running and launches at login (on by default, can be turned off). History has gaps when the app isn't running; that's accepted. Menu bar only (no Dock icon) except while the full window is open.
- **Live tiles:** power draw, voltage and amperage show lightly smoothed values so they don't flicker. Only the headline hours figure has a stricter steadiness requirement.
- **Settings page contents:** launch at login, menu bar display format, history retention, and a "reset learned data" button. Nothing else.
- **Menu bar icon:** a template SF Symbol that adapts to the menu bar, plus the hours text. The emoji in the mockup was illustrative only.

## Left to the builder

- Project layout, storage format for history, sampling interval, smoothing method.
- Exact visual polish, within "native macOS, focus on how it looks".
