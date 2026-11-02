# Runtime headline and quick menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the headline hours honest ("Typical and now"), add a right-click quick menu on the status item, and polish the menu bar item and popover.

**Architecture:**
- Pure logic goes in `BatteryCore` with tests: typical draw, runtime estimate, menu bar appearance and the quick menu model.
- The app moves to an AppKit lifecycle. An `NSStatusItem` shows an `NSPopover` on click and an `NSMenu` on right-click. An AppKit-owned `NSWindow` hosts the existing SwiftUI main window.
- The views only render model values.

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI, AppKit (`NSStatusItem`, `NSPopover`, `NSMenu`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-02-runtime-and-menu-design.md`. The earlier designs in `docs/superpowers/specs/` still apply.

**Branch:** `feat/runtime-and-menu`, cut from `main`.

## Global Constraints

- Platform `.macOS("27.0")`, arm64, Command Line Tools only. Public API only, no new dependencies.
- Don't use SwiftUI `@State`, `@Entry` or `@Previewable`; they don't build under Command Line Tools. Use `@Observable` objects, `@AppStorage` or AppKit state.
- Native look: system font, materials, system colors, light and dark mode, sentence case, no emoji (SF Symbols are fine).
- Never show values the data can't support. Typical draw needs at least 30 on-battery readings in the last 7 days; without it the headline is labeled "estimate".
- No data work on the main thread: typical draw is computed off the main actor.
- Fixed values: typical window 7 days, minimum 30 readings, blend weight 0.5, recent half-life 1800 s, high use = pace ≥ 10 W and ≥ 2 × typical, first top-apps sample 20 s after launch, a top-apps sample is shown only while under 600 s old, red symbol at ≤ 10% on battery.
- Stage files by explicit path only. The owner has untracked `.agents/`, `.claude/` and `skills-lock.json`.
- No system side effects while verifying: don't run `bundle.sh --install`, and don't register the login item. A debug-binary smoke run of at most 8 s is allowed, followed by killing it.

## Review Focus

1. **A spike at launch.** A first reading taken during a compile (26 W) with a 6.7 W typical draw must not set the headline to the spike. Tested in Task 1.
2. **Thin history.** With fewer than 30 on-battery readings there is no typical draw, `isEstimate` is true and "Per full charge" is hidden. Tested in Tasks 1 and 2.
3. **Hidden menu bar icon.** Launching the app again must open the main window. Verified in Task 4 (owner check).
4. **Window closed.** Closing the main window returns the app to menu-bar-only and keeps the status item. Verified in Task 4 (owner check).
5. **Control-click.** Control-click behaves like right-click, and a click while the menu is open does not open the popover. Verified in Task 4 (owner check).

---

### Task 1: Typical draw and runtime estimate

**Files:**
- Create: `Sources/BatteryCore/TypicalDraw.swift`, `Sources/BatteryCore/RuntimeEstimate.swift`
- Modify: `Sources/BatteryCore/PowerState.swift`
- Test: `Tests/BatteryCoreTests/TypicalDrawTests.swift`, `Tests/BatteryCoreTests/PowerStateTests.swift`

**Interfaces:**
- Consumes: `BatteryReading` (`timestamp`, `externalConnected`, `powerWatts`, `remainingWattHours`).
- Produces:
```swift
public enum TypicalDraw {
  public static let minReadings = 30
  public static func watts(in history: [BatteryReading], now: Date) -> Double?  // mean powerWatts, on battery, last 7 days; nil under minReadings
}
public struct RuntimeEstimate: Equatable, Sendable {
  public var headline: TimeInterval?    // time left at the blended draw
  public var atPace: TimeInterval?      // time left at the 30 s smoothed draw
  public var paceWatts: Double?
  public var typicalWatts: Double?
  public var isEstimate: Bool           // typicalWatts == nil
  public var isHighUse: Bool            // paceWatts >= 10 && typical != nil && paceWatts >= 2 * typical
  public init(headline: TimeInterval?, atPace: TimeInterval?, paceWatts: Double?, typicalWatts: Double?, isEstimate: Bool, isHighUse: Bool)
}
// PowerEstimator changes:
public mutating func update(with reading: BatteryReading, typicalWatts: Double? = nil) -> PowerState  // .onBattery(timeLeft:) now carries the headline
public var runtime: RuntimeEstimate? { get }  // non-nil only while on battery
public var recentWatts: Double? { get }       // 30-minute EMA
```

Rules:
- `recentWatts` uses an `EMASmoother` with half-life 1800 s. It resets on power-source change and on gaps, like the other smoothers.
- Headline draw = `0.5 × typical + 0.5 × recent` when typical is known, otherwise `recent`. The result is nil below 0.5 W. Cap at 99 h.
- `atPace` uses the existing 30 s smoother (`liveWatts`). It's nil below 0.5 W.

- [ ] **Step 1: Write the failing tests:**
  - `typicalIsMeanOfBatteryReadings`: 31 on-battery readings, 30 at 5 W and one at 40 W, give about 6.13 (±0.01). AC readings and readings older than 7 days are ignored.
  - `typicalNeedsThirtyReadings`: 29 readings give nil, 30 give a value.
  - `headlineBlendsTypicalAndRecent`: remaining 40 Wh, typical 6 W, recent 14 W gives headline = 40 ÷ 10 W = 4 h (±1%).
  - `spikeAtLaunchDoesNotDominateHeadline`: typical 6.7 W, first reading at 26.6 W, remaining 43 Wh gives a headline over 2.5 h while `atPace` is under 1.7 h.
  - `noTypicalUsesRecentAndIsEstimate`.
  - `highUseThresholds`: pace 26.6, typical 6.7 gives true. Pace 12, typical 8 gives false. Pace 9, typical 2 gives false.
  - `runtimeIsNilOffBattery`.
  - Update the existing on-battery `PowerStateTests` that call `update(with:)` so they still pass (typical defaults to nil).
- [ ] **Step 2:** Run `swift test --filter TypicalDrawTests` and expect a FAIL (types missing).
- [ ] **Step 3:** Implement `TypicalDraw`, `RuntimeEstimate`, and the `PowerEstimator` changes.
- [ ] **Step 4:** Run `swift test` and expect a PASS.
- [ ] **Step 5:** Commit with the message `feat: typical draw and blended runtime estimate`.

### Task 2: Model wiring, per-full-charge fallback and top apps now

**Files:**
- Modify: `Sources/BatteryCore/FullChargeLearner.swift`, `Sources/BatteryMeter/BatteryModel.swift`, `Sources/BatteryMeter/EnergySampler.swift`
- Test: `Tests/BatteryCoreTests/FullChargeLearnerTests.swift`

**Interfaces:**
- Consumes: Task 1's `TypicalDraw`, `RuntimeEstimate`, `PowerEstimator.update(with:typicalWatts:)`.
- Produces:
```swift
// FullChargeLearner: the third parameter is renamed
public static func estimate(history: [BatteryReading], current: BatteryReading?, fallbackWatts: Double?) -> FullChargeEstimate?
// BatteryModel additions (all observable):
var runtime: RuntimeEstimate?
var typicalWatts: Double?
// EnergySampler becomes @Observable:
var topApps: [String]          // up to 2 names of the latest sample, by power
var topAppsDate: Date?
func freshTopApps(now: Date) -> [String]   // empty when older than 600 s
```

Rules:
- `BatteryModel` computes `typicalWatts` off the main actor (`Task.detached(priority: .utility)`) after the history loads, every 600 s, and after a retention change. Reset sets it nil.
- `refresh` passes `typicalWatts` to the estimator and publishes `estimator.runtime`.
- `updateFullCharge` passes `typicalWatts` as `fallbackWatts` (cold start = full capacity ÷ typical draw, `isEstimate: true`). It no longer uses `liveWatts`.
- `EnergySampler.start()` takes the first sample 20 s later, then every 300 s. `topApps` keeps names whose cleaned name is non-empty, ordered by power.

- [ ] **Step 1: Write the failing tests** (update `coldStartFallback` and friends for the renamed parameter):
  - `coldStartUsesFallbackWatts`: full 52 Wh, fallback 6.5 W gives 8 h with `isEstimate == true`.
  - `noFallbackAndNoHistoryIsNil`.
- [ ] **Step 2:** Run `swift test --filter FullChargeLearnerTests` and expect a FAIL.
- [ ] **Step 3:** Implement the rename and the model and sampler changes.
- [ ] **Step 4:** Run `swift test` and `swift build`. Expect a PASS with no Swift warnings.
- [ ] **Step 5:** Commit with the message `feat: wire typical draw into the model and per-full-charge`.

### Task 3: Menu bar appearance and quick menu model

**Files:**
- Create: `Sources/BatteryCore/MenuBarAppearance.swift`, `Sources/BatteryCore/QuickMenu.swift`
- Test: `Tests/BatteryCoreTests/MenuBarAppearanceTests.swift`, `Tests/BatteryCoreTests/QuickMenuTests.swift`

**Interfaces:**
- Consumes: `PowerState`, `MenuBarFormat`, `MenuBarText`.
- Produces:
```swift
public enum MenuBarAppearance {
  public static func symbolName(percent: Int, state: PowerState) -> String   // same mapping as MenuBarLabel today
  public static func isLow(percent: Int, state: PowerState) -> Bool          // on battery and percent <= 10
  public static func accessibilityLabel(percent: Int, state: PowerState) -> String
}
public enum QuickMenuAction: Equatable, Sendable {
  case open, reports, history, health, settings
  case setFormat(MenuBarFormat)
  case toggleLaunchAtLogin
  case quit
}
public struct QuickMenuItem: Equatable, Sendable {
  public var title: String
  public var action: QuickMenuAction?
  public var isChecked: Bool
  public var keyEquivalent: String      // "" when none; "," and "q" use the command modifier
  public var children: [QuickMenuItem]
  public var isSeparator: Bool
}
public enum QuickMenu { public static func items(format: MenuBarFormat, launchAtLogin: Bool) -> [QuickMenuItem] }
```

Rules:
- `symbolName`: charging gives `battery.100percent.bolt`, plugged in gives `powerplug`, and on battery the level mapping of the current `MenuBarLabel.levelSymbol` (88… → 100, 63 → 75, 38 → 50, 13 → 25, else 0).
- `accessibilityLabel` examples: "Battery 75 percent, about 5 hours 30 minutes left", "Battery 80 percent, charging, 1 hour 10 minutes to full", "Battery 100 percent, plugged in", and "Battery 40 percent, on battery" when the time is unknown.
- `QuickMenu.items` order and titles: Open Battery Meter · Reports… · History… · Health… · separator · Menu bar shows (children: Hours left, Percent, Hours and percent, with the current one checked) · Launch at login (checked when on) · Settings… (key ",") · separator · Quit Battery Meter (key "q").

- [ ] **Step 1: Write the failing tests:**
  - `symbolMapping`: percents 100, 75, 50, 25 and 5 on battery, plus charging and plugged in.
  - `lowOnlyOnBattery`: 10 on battery is true, 10 charging is false, 11 on battery is false.
  - `accessibilityLabels`: the four examples above.
  - `quickMenuOrderAndTitles`: the exact title sequence, with separators at the right indices.
  - `quickMenuChecksCurrentFormat`: each format checks exactly one child, and the launch toggle follows `launchAtLogin`.
  - `quickMenuKeys`: Settings has "," and Quit has "q".
- [ ] **Step 2:** Run `swift test --filter QuickMenuTests` and expect a FAIL.
- [ ] **Step 3:** Implement both files.
- [ ] **Step 4:** Run `swift test` and expect a PASS.
- [ ] **Step 5:** Commit with the message `feat: menu bar appearance and quick menu model`.

### Task 4: AppKit lifecycle, status item and main window

**Files:**
- Create: `Sources/BatteryMeter/main.swift`, `Sources/BatteryMeter/AppDelegate.swift`, `Sources/BatteryMeter/StatusItemController.swift`, `Sources/BatteryMeter/MainWindowController.swift`, `Sources/BatteryMeter/MainMenu.swift`
- Delete: `Sources/BatteryMeter/BatteryMeterApp.swift`, `Sources/BatteryMeter/MenuBarLabel.swift`
- Modify: `Sources/BatteryMeter/PopoverView.swift` (footer actions become closures, no `@Environment(\.openWindow)`), `Sources/BatteryMeter/SnapshotRenderer.swift`, `Sources/BatteryMeter/BatteryModel.swift` (an `onRefresh` callback)

**Interfaces:**
- Consumes: Task 3's `MenuBarAppearance`, `QuickMenu`, `QuickMenuAction`; the existing `MainWindow`, `SettingsState`, `ReportsModel`, `EnergySampler`, `ChartHover`, `SidebarItem`.
- Produces:
```swift
@MainActor final class MainWindowController: NSObject, NSWindowDelegate {
  func show(pane: SidebarItem?)        // writes sidebarSelection when non-nil, sets .regular, activates, orders front
}
@MainActor final class StatusItemController {
  init(model: BatteryModel, sampler: EnergySampler, settings: SettingsState, window: MainWindowController)
  func updateLabel()                   // called after each model refresh and on menuBarFormat changes
}
struct PopoverActions { var openWindow: () -> Void; var openReports: () -> Void; var openSettings: () -> Void; var quit: () -> Void }
```

Behavior decisions:
- **Entry:** `main.swift` creates `NSApplication.shared`, sets `AppDelegate` as delegate and calls `run()`. The delegate does what `BatteryMeterApp.init` did: build the model, reports and sampler, wire `onReset` and `onHistoryLoaded`, honor `SnapshotRenderer.requestedDirectory` in DEBUG (render and exit without creating a status item), then `settings.offerLaunchAtLoginOnce()`, `model.start()`, `sampler.start()`.
- **Activation policy:** `.accessory` at launch. `MainWindowController.show` sets `.regular`. `windowWillClose` sets `.accessory`. Closing the window keeps the app and the status item running.
- **Window:** `NSWindow` (titled, closable, miniaturizable, resizable), content `NSHostingController(rootView: MainWindow(...))`, default 760×520, content minimum 640×440, `setFrameAutosaveName("MainWindow")`, `isReleasedWhenClosed = false`. The existing `.toolbar(removing: .title)` and split view stay.
- **Reopen:** `applicationShouldHandleReopen` shows the main window.
- **Main menu:** an app menu (About Battery Meter, Settings… ⌘, → settings pane, Hide ⌘H, Quit ⌘Q) and a Window menu (Minimize ⌘M, Close ⌘W), built in `MainMenu.swift`.
- **Status item:** `NSStatusBar.system.statusItem(withLength: .variableLength)`. The button shows a template SF Symbol from `MenuBarAppearance.symbolName` and the `MenuBarText` text in `NSFont.monospacedDigitSystemFont`. It is tinted red when `isLow`, and carries `accessibilityLabel`. `sendAction(on: [.leftMouseUp, .rightMouseUp])`. A right click, or a left click with Control held, builds an `NSMenu` from `QuickMenu.items`, assigns it to the status item, calls `performClick`, and clears it again when it closes. A plain left click toggles the `NSPopover` (`behavior = .transient`, content `NSHostingController(rootView: PopoverView(model: BatteryModel, sampler: EnergySampler, actions: PopoverActions))`). Opening the menu closes the popover first.
- **Actions:** the menu and the popover footer call `MainWindowController.show(pane:)` with `.overview`, `.reports`, `.history`, `.health` or `.settings`. `setFormat` writes the `menuBarFormat` default. `toggleLaunchAtLogin` uses `SettingsState`. `quit` calls `NSApp.terminate(nil)`.
- **Label updates:** `BatteryModel.onRefresh` runs after each `refresh`. The controller also observes `UserDefaults.didChangeNotification` for `menuBarFormat`.

- [ ] **Step 1:** Implement the entry point, delegate, main window controller and main menu. Keep the snapshot path working.
- [ ] **Step 2:** Implement `StatusItemController`, the `PopoverActions` wiring and the `onRefresh` callback. Delete the two replaced files.
- [ ] **Step 3:** Run `swift build` (no Swift warnings) and `swift test`.
- [ ] **Step 4:** Run `.build/debug/BatteryMeter --render-snapshots <tmp>` and check the popover and window PNGs still render. Check that `history.jsonl` and `app-energy.json` are unchanged.
- [ ] **Step 5:** Smoke run: start `.build/debug/BatteryMeter` in the background, wait about 6 s, check with `pgrep` that it's alive and that no crash report appeared, then kill it. Record the result.
- [ ] **Step 6:** Run `bash scripts/bundle.sh` (don't install or open it).
- [ ] **Step 7:** Commit with the message `feat: appkit status item with right-click quick menu`.

### Task 5: Popover and Overview polish

**Files:**
- Modify: `Sources/BatteryMeter/PopoverView.swift`, `Sources/BatteryMeter/OverviewView.swift`, `Sources/BatteryMeter/BatteryComponents.swift`, `Sources/BatteryMeter/SnapshotRenderer.swift`

**Interfaces:**
- Consumes: Task 2's `BatteryModel.runtime`, `EnergySampler.freshTopApps(now:)`; Task 4's `PopoverActions`.
- Produces: no new public types.

Design decisions (load `swiftui-expert-skill` first):
- **Header on battery:** caption "Estimated left" (an "estimate" tag beside it when `runtime.isEstimate`), the headline in the existing 38 pt rounded bold with the numeric transition, the charge bar, then a quiet secondary row: "At this pace" on the left, `<duration> · <watts> W` on the right.
- **High use:** when `runtime.isHighUse` and `freshTopApps` is non-empty, a line under the secondary row: a `bolt.fill` symbol and "High use: <names>" in secondary color (names joined by ", "). Nothing is shown otherwise.
- **Charging or plugged in:** the header keeps today's captions and has no secondary row.
- **Tiles:** Per full charge, Health, Cycles and Power draw as today. "Per full charge" is hidden when nil.
- **Footer:** the "Open history…" and "Quit" rows become four icon buttons with tooltips, VoiceOver labels and shortcuts: Open window (`macwindow`, ⌘O), Reports (`chart.bar.doc.horizontal`), Settings (`gearshape`, ⌘,) and Quit (`power`, ⌘Q). Spacing follows an 8 pt grid.
- **Accessibility:** the bar and tiles keep combined labels; the numeric transition respects Reduce Motion.
- **Overview:** the big "Left right now" number becomes "Estimated left" with the same headline, and "At this pace" replaces the duplicate "Per full charge" caption wording. It must read the same as the popover.
- **Snapshots:** render `popover-{light,dark}.png` (normal), `popover-high-use-{light,dark}.png` (synthetic: pace 26.6 W, typical 6.7 W, apps "iPhone Mirroring, rapportd"), `popover-estimate-{light,dark}.png` (no typical) and the Overview pane. Inspect every PNG and fix spacing, hierarchy and contrast.

- [ ] **Step 1:** Implement the popover, Overview and component changes.
- [ ] **Step 2:** Run `swift build` (no Swift warnings) and `swift test`.
- [ ] **Step 3:** Render the snapshots and review each PNG in light and dark mode. Fix what looks off.
- [ ] **Step 4:** Check that `history.jsonl` and `app-energy.json` are unchanged by the snapshot run, and that `bash scripts/bundle.sh` builds.
- [ ] **Step 5:** Commit with the message `feat: clearer popover and overview headline`.

### Task 6: Menu bar personalization

**Files:**
- Create: `Sources/BatteryCore/MenuBarStyle.swift`, `Sources/BatteryMeter/BatteryIconRenderer.swift`, `Sources/BatteryMeter/MenuBarSettingsSection.swift`
- Modify: `Sources/BatteryCore/MenuBarText.swift`, `Sources/BatteryCore/MenuBarAppearance.swift`, `Sources/BatteryCore/QuickMenu.swift`, `Sources/BatteryMeter/StatusItemController.swift`, `Sources/BatteryMeter/SettingsView.swift`, `Sources/BatteryMeter/SnapshotRenderer.swift`
- Test: `Tests/BatteryCoreTests/MenuBarStyleTests.swift`, plus updates to `MenuBarTextTests.swift`, `MenuBarAppearanceTests.swift` and `QuickMenuTests.swift`

**Interfaces:**
- Consumes: Task 3's `MenuBarText`, `MenuBarFormat`, `MenuBarAppearance`, `QuickMenu`; Task 4's `StatusItemController` and `SettingsState`.
- Produces:
```swift
public enum MenuBarIconStyle: String, CaseIterable, Sendable { case symbol, percentInside, none }
public enum MenuBarColorMode: String, CaseIterable, Sendable { case monochrome, lowOnly, lowAndCharging }
public enum MenuBarTimeStyle: String, CaseIterable, Sendable { case hoursMinutes, clock }   // "6h 30m" or "6:30"
// MenuBarFormat gains two cases: watts, none
public enum MenuBarColorRole: Sendable { case none, low, charging }
public struct MenuBarStyle: Equatable, Sendable {
  public var icon: MenuBarIconStyle
  public var format: MenuBarFormat
  public var colors: MenuBarColorMode
  public var lowThreshold: Int          // 5, 10, 15 or 20
  public var timeStyle: MenuBarTimeStyle
  public static let standard: MenuBarStyle   // symbol, hours, lowOnly, 10, hoursMinutes
  public init(defaults: UserDefaults)         // keys: menuBarIcon, menuBarFormat, menuBarColors, menuBarLowThreshold, menuBarTimeStyle; anything invalid falls back to the standard value
}
// MenuBarText.text(state:percent:format:timeStyle:watts:) -> String      (timeStyle defaults to .hoursMinutes, watts to nil)
// MenuBarAppearance.colorRole(percent:state:style:) -> MenuBarColorRole
// MenuBarAppearance.isLow(percent:state:threshold:) -> Bool               (threshold defaults to 10)
```

Rules:
- `.none` text is the empty string. If the icon is also `.none`, the item falls back to the symbol icon, so it is never empty.
- `.watts` shows the live draw with one decimal and a space, for example "26.6 W", and "—" when unknown.
- `.clock` prints hours and minutes as "6:30" and "0:45", rounded to 5 minutes like `DurationText`. It applies to `.hours` and `.both`.
- `colorRole`: `.low` when on battery, the percent is at or below the threshold and `colors != .monochrome`; `.charging` when charging and `colors == .lowAndCharging`; otherwise `.none`.
- `QuickMenu` "Menu bar shows" children: Hours left, Percent, Hours and percent, Power draw, Icon only (a checkmark on the current one).

App behavior:
- `BatteryIconRenderer.image(percent:charging:role:)` draws a battery about 24 × 12 pt: an outline, a terminal nub, a level fill, and the percentage in `NSFont.monospacedDigitSystemFont` inside the body, legible at "100", at "5" and over the fill. A bolt overlay while charging. It is a template image when the role is `.none`, otherwise a colored image (red for `.low`, green for `.charging`).
- `StatusItemController` builds the button from `MenuBarStyle(defaults:)`: icon by style (`symbol` uses `MenuBarAppearance.symbolName`, `percentInside` uses the renderer, `none` shows no image), and the text from `MenuBarText`. It updates when any of the five keys changes (generalize today's `menuBarFormat` observer).
- `MenuBarSettingsSection`: a "Menu bar" group in Settings with pickers for Icon (Battery symbol, Battery with percentage inside, No icon), Text, Time style (shown only when the text includes hours), Colors and Low battery at, plus a live preview of the item on a strip. It writes the five keys with `@AppStorage`.

- [ ] **Step 1: Write the failing tests:**
  - `standardStyleIsToday`: `MenuBarStyle.standard` is symbol, hours, lowOnly, 10, hoursMinutes.
  - `styleReadsDefaults` and `invalidValuesFallBack`, using a throwaway `UserDefaults(suiteName:)`.
  - `clockStyle`: 23 400 s gives "6:30" and 2 700 s gives "0:45". With `.both` and `.clock` the text is "6:30 · 34%".
  - `wattsText`: 26.6 gives "26.6 W" and nil gives "—".
  - `noneFormatIsEmpty` and `noIconAndNoTextFallsBackToSymbol` (through a pure helper on `MenuBarStyle`, for example `effectiveIcon`).
  - `colorRoles`: low at the threshold (true), just above (false), monochrome (never), charging with `lowAndCharging` (charging), charging with `lowOnly` (none).
  - Update `quickMenuOrderAndTitles` and `quickMenuChecksCurrentFormat` for the two new children.
- [ ] **Step 2:** Run `swift test --filter MenuBarStyleTests` and expect a FAIL.
- [ ] **Step 3:** Implement the core types, then the renderer, the controller changes and the Settings section.
- [ ] **Step 4:** Run `swift build` (no Swift warnings) and `swift test`.
- [ ] **Step 5:** In snapshot mode render `menubar-icons-{light,dark}.png` (the icon at 100, 85, 50, 20, 8 and 5 percent; template and colored; charging) and `window-settings-menubar-{light,dark}.png`. View every PNG and fix legibility, the percentage inside the icon, spacing and contrast. Check that the snapshot run writes nothing.
- [ ] **Step 6:** Run `bash scripts/bundle.sh` (don't install or open it) and do the 8 s smoke run again, since the status item changed.
- [ ] **Step 7:** Commit with the message `feat: menu bar personalization`.
