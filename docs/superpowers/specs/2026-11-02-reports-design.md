# Battery Meter reports: design

## Intent and why

The owner wants "deep reports" in the full window: answers about how the battery is really used, beyond the live numbers and the two History charts. The owner chose all six reports below after research showed that other Mac battery apps (coconutBattery, iStat Menus, AlDente) track health over time but don't combine usage, charging habits, sleep drain and per-app energy in one place.

## Goals

The window gets a **Reports** pane with six sections:

1. **Usage:** hours on battery, charge used and average draw, for each of the last 7 days and each of the last 4 weeks.
2. **Discharge sessions:** a list of sessions with start, end, duration, percent used and hours per full charge.
3. **Charging habits:**
   - the typical level you plug in at and unplug at
   - the average time per day sitting at 100% on AC
   - cycles added per week
   - the charger wattage used most often
4. **Health trend:**
   - capacity lost per month
   - the projected date the battery reaches 80% health, Apple's service threshold
   - "Health is steady" when it isn't declining
5. **Sleep drain:**
   - battery lost during each sleep period in the last 7 days
   - the average loss per hour asleep
   - what woke the Mac, grouped into a few plain categories
6. **Top battery users:** the apps with the most energy impact while on battery over the last 7 days, shown as a share of the total.

The Overview pane also gets a compact **This week** card (battery time, charge used and average sleep drain) with a "See reports…" button that opens the Reports pane. The owner asked for the reports "in the overview or something".

## Non-goals

- No export, sharing, notifications or charge control.
- No data that needs admin rights. `powermetrics` is out.
- No change to the existing History charts beyond reusing their daily-health logic.

## Anti-goals

- **Unsupported claims:** a report that states something the data can't support, such as a health projection from 3 days of data. Every section needs a clear "not enough data yet" state that says what it's waiting for.
- **A slower app:** building reports must never run on the main thread.
- **Leaking data:** app names and sleep data stay on this Mac.

## Data sources (verified on the owner's Mac, no admin rights needed)

- **History:** the app's own history, one reading per minute.
- **Sleep and wake log:** `pmset -g log`, about 30k lines.
  - **Line format:** `2026-11-01 21:10:31 -0500 Sleep  <tab>Entering Sleep state due to '...' Using Batt (Charge:50%) 307 secs`.
  - **Event types:** `Wake` and `DarkWake` lines read `... due to <reason> Using BATT (Charge:50%)`.
  - **Power source casing:** the power source appears as "Batt", "BATT" or "AC".
  - **Retention:** macOS keeps only some days of this log.
- **Per-app power:** `top -l 2 -s 1 -o power -stats pid,command,power -n 20`.
  - Only the second sample is meaningful.
  - Command names are cut off at 16 characters, so GUI apps are resolved to their full names by pid.

## Constraints

Everything in the first design still applies: native look, sentence case, light and dark mode, Command Line Tools only (no `@State`), and read-only IOKit.

## Decisions (assistant's calls, not confirmed by the owner)

- **Layout:** Reports is its own sidebar pane, placed right after Overview, with the "This week" card in Overview. The Overview stays glanceable.
- **Per-app sampling:** `top` runs every 5 minutes, only while on battery, and takes about 2 s per run. The samples are kept for 30 days in `app-energy.json` next to the history. "Reset learned data" clears them too.
- **Energy units:** energy impact has no unit, so the report shows each app's share of the total rather than watts.
- **Refresh:** reports rebuild off the main thread when the Reports or Overview pane appears, at most once every 5 minutes. The sleep log is re-read at most every 30 minutes.

## Left to the builder

Visual layout within each section, within the native look. The charts follow the `dataviz` skill.
