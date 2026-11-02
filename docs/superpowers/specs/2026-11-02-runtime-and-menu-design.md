# Runtime headline and quick menu: design

## Intent and why

The owner saw "Left right now 1h 30m" on an Air that normally lasts much longer. The math was right for that instant (26.6 W with iPhone Mirroring and a compile running), but the headline treated a spike as the norm. The owner also wants a better menu bar experience: a right-click menu with quick actions, and a clearer popover.

## Findings (owner's Mac, 2026-11-02)

- At the screenshot: 12.03 V × 2.21 A = 26.6 W, 75% charge → about 1.5 h. Correct for that moment.
- History on battery (28 readings): p25 5.5 W, median 6.7 W, p75 19.2 W, max 34.3 W. At the median a full charge lasts about 8.5 h. macOS said 5:05 at 73%.
- `top` showed iPhone Mirroring and `rapportd` with a very high energy impact, plus `swift run` compiles.
- The estimator's smoother starts from the first reading after each launch, and that reading landed in a compile. "Per full charge 2h 5m estimate" is capacity ÷ the draw of that moment, because there is no discharge history yet.
- Menu bar access today: left click opens the popover, right click does nothing (`MenuBarExtra` in window style has no right-click). [Apple's HIG](https://developers.apple.com/design/human-interface-guidelines/components/system-experiences/the-menu-bar/) prefers a menu, and allows a popover when the content is too complex for one. It also says menu bar extras can be hidden, so the app must stay reachable another way. A [macOS 27 beta report](https://github.com/jizhi0v0/macos27-beta-issues/issues/34) says the window-style status button ignores VoiceOver and automation, while `NSStatusItem` with `NSPopover` works (single developer, unconfirmed).

## Goals

1. **Honest headline ("Typical and now").**
   - The headline is "Estimated left": the time left at a draw halfway between the owner's typical draw and the last 30 minutes.
   - Under it, "At this pace": the time left at the current draw, with the watts.
   - When the pace is high compared with typical, a line names the apps using the most power.
   - "Per full charge" stops using the draw of the moment.
2. **Quick menu.** Click opens the popover. Right-click or Control-click opens a menu with quick actions.
3. **UI and UX polish** of the menu bar item and the popover, within the native look.

## Non-goals

- No charge control, no Low Power Mode toggle (needs admin), no notifications.
- No new dependencies. Public AppKit API only.
- No change to the Reports pane.

## Anti-goals

- A headline that swings with a compile spike.
- Calling a number "typical" without enough battery history.
- Any change that makes the app unreachable when the menu bar icon is hidden.
- Losing VoiceOver access to the menu bar item.

## Decisions made by the owner

- Headline: "Typical and now", with "At this pace" and the high-use apps underneath.
- Access: the status item opens the popover on click and a quick menu on right-click.

## Decisions made by the assistant (not confirmed by the owner)

- **Typical draw:** the mean `powerWatts` of on-battery readings in the last 7 days, shown only with at least 30 such readings (about 30 minutes). **Changed from the median on 2026-11-02, after the Task 5 review:** runtime follows the mean draw, because spikes are real energy use. On the owner's data the median predicted 8.5 h per full charge, the observed drain implied about 6.1 h, the learned sessions said 4h 55m, and the mean gave 5.4 h. Without it, the headline uses the 30-minute average and is labeled "estimate".
- **Blend:** headline draw = 0.5 × typical + 0.5 × the 30-minute average (EMA, half-life 1800 s).
- **High use:** pace ≥ 10 W, typical known, and pace ≥ 2 × typical.
- **Top apps now:** `EnergySampler` takes its first sample 20 s after launch (then every 300 s) and keeps the names of the top 2 apps of the latest sample, shown only while that sample is under 10 minutes old.
- **App lifecycle:** the app moves from the SwiftUI `App` to an AppKit `NSApplicationDelegate`. This is needed to open the main window from the status item, because `openWindow` does not work outside a SwiftUI scene. It also gives a main menu, so ⌘, ⌘W and ⌘Q work while the window is open.
- **Reopen:** launching the app again (Spotlight, Finder) opens the main window, so a hidden menu bar icon never locks the owner out.
- **Menu bar item:** monospaced digits, a bolt while charging, red symbol at 10% or less on battery, and a VoiceOver label with the full state.
- **Quick menu items:** Open Battery Meter, Reports…, History…, Health…, Menu bar shows (Hours left, Percent, Hours and percent), Launch at login, Settings… (⌘,), Quit Battery Meter (⌘Q).

## Left to the builder

Exact spacing, sizes and animation within the native look. The tuning constants above are fixed; the builder may not change them without saying so.

## Addendum: menu bar personalization (owner request, 2026-11-02)

The owner asked for more personalization, for example the percentage inside the battery icon and the hours left outside it.

**Decisions by the assistant (not confirmed by the owner):**

- **Icon:** three choices. "Battery symbol" (today's native SF Symbol), "Battery with percentage inside" (a custom-drawn battery, because macOS has no native one), and "No icon".
- **Text:** five choices. Hours left, Percent, Hours and percent, Power draw (for example "26.6 W"), and None (icon only). The icon and the text can't both be empty; if both are, the symbol icon is used.
- **Time style:** "6h 30m" or "6:30".
- **Colors:** Monochrome (adapts to the menu bar), Red when low, or Red when low and green when charging.
- **Low battery threshold:** 5%, 10%, 15% or 20%.
- **Defaults keep today's look** (symbol, hours left, red when low, 10%, "6h 30m"), so nothing changes until the owner picks.
- **Settings** gets a "Menu bar" group with these controls and a live preview, so the earlier "four controls" rule for Settings is extended on purpose. The right-click "Menu bar shows" submenu stays and maps to the text choice (it gains Power draw and Icon only).
- **Custom icon:** drawn with AppKit, a battery outline with a level fill, the percentage inside it (legible at 100% and at 5%) and a bolt while charging. It is a template image (adapts to the menu bar) unless a color applies.

**Non-goals:** custom fonts, user images, different text per power state.
