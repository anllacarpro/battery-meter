# Battery Meter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu bar app with a full window that shows honest battery hours, real health and battery history.

**Architecture:** A Swift package with two targets. `BatteryCore` is a pure library with no UI: it parses the AppleSmartBattery registry data, estimates hours, learns hours per full charge, and stores history. It holds all the logic and all the tests. `BatteryMeter` is a thin SwiftUI app: `MenuBarExtra` (window style) for the popover, a `Window` for the full app, and a `@MainActor @Observable` model that polls `BatteryCore`. A shell script wraps the release binary into a `.app` bundle, because only Command Line Tools are installed (no Xcode).

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI, Swift Charts, IOKit, ServiceManagement (`SMAppService`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-01-battery-meter-design.md`

## Global Constraints

- Platform: `.macOS("27.0")`, arm64. The owner's Mac runs macOS 27.2, and Command Line Tools only (no `xcodebuild`).
- Read-only: never write to IOKit or change any power setting.
- Native look: system font, materials (`.regularMaterial`), system colors, light and dark mode. No custom fonts and no emoji in the UI. The menu bar uses template SF Symbols.
- Never show values the hardware doesn't provide. A missing optional key hides its row or tile, and never shows "0".
- Bundle ID `com.noodlexz.BatteryMeter`, app name "Battery Meter", `LSUIElement` = true.
- Copy uses sentence case ("Open history…", "Plugged in", "Reset learned data").
- Fixed values: read every 10 s, record history every 60 s. The hours-left smoother half-life is 300 s and the live-tile smoother half-life is 30 s. Draw below 0.5 W means hours left is unknown. Hours shown are capped at 99 h and rounded to the nearest 5 min. A gap longer than 300 s between readings resets the smoothers and splits discharge sessions. History retention options are 30, 90, 180 or 365 days, with 180 as the default.

## Review Focus

1. **Sleep/wake:** After the lid opens, hours left must not use the draw from before sleep. A gap longer than 300 s resets the smoothers (test in Task 3), and sessions split at the gap (test in Task 4).
2. **Unplug:** The first on-battery estimate must not be computed from charging current. A change in power source resets the smoothers (test in Task 3).
3. **Crash mid-write:** A truncated last line in the history file is skipped, and the rest of the history still loads (test in Task 5).
4. **Missing data:** If there's no battery or `BatteryData` is missing, parse returns nil and the app shows the empty state. A missing optional key such as adapter watts gives nil, not 0 (tests in Task 2).
5. **Sentinels and edge states:** `AvgTimeToFull` = 65535 means unknown. Being full on AC means "Plugged in", not "Charging" (tests in Tasks 2 and 3).

---

### Task 1: Package scaffold and reading model

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/BatteryCore/BatteryReading.swift`, `Sources/BatteryMeter/BatteryMeterApp.swift` (placeholder `@main` with an empty `MenuBarExtra("Battery Meter", systemImage: "battery.100percent") { Text("…") }`)
- Test: `Tests/BatteryCoreTests/BatteryReadingTests.swift`

**Interfaces:**
- Produces:
```swift
public struct BatteryReading: Codable, Sendable, Equatable {
  public var timestamp: Date
  public var percent: Int                 // CurrentCapacity, 0–100
  public var remainingCapacity: Int       // mAh
  public var fullChargeCapacity: Int      // mAh
  public var designCapacity: Int          // mAh
  public var cycleCount: Int
  public var designCycleCount: Int?
  public var voltage: Int                 // mV
  public var amperage: Int                // mA, signed; negative = discharging
  public var isCharging: Bool
  public var externalConnected: Bool
  public var fullyCharged: Bool
  public var adapterWatts: Int?
  public var notChargingReason: Int?
  public var osMinutesToEmpty: Int?
  public var osMinutesToFull: Int?
  public var healthPercent: Double { get }  // fullChargeCapacity / designCapacity * 100
  public var powerWatts: Double { get }     // |voltage * amperage| / 1_000_000
  public var remainingWattHours: Double { get } // remainingCapacity * voltage / 1_000_000
  public var fullWattHours: Double { get }      // fullChargeCapacity * voltage / 1_000_000
}
```

- [ ] **Step 1:** Run `git init`. Write a `.gitignore` containing `.build/`, `.superpowers/`, `build/` and `.DS_Store`. Write `Package.swift` with targets `BatteryCore` (library), `BatteryMeter` (executable, depends on BatteryCore), and `BatteryCoreTests`, using platform `.macOS("27.0")`.
- [ ] **Step 2: Write the failing test** `healthAndPower` using the owner's real values: design 4629, full 4575, remaining 1515, voltage 11356, amperage -362. Expect `healthPercent` ≈ 98.83 (±0.01), `powerWatts` ≈ 4.111 (±0.001) and `remainingWattHours` ≈ 17.204 (±0.001).
- [ ] **Step 3:** Run `swift test`. It should fail to compile because `BatteryReading` is missing. **If `import Testing` itself fails with Command Line Tools, stop and report to the owner.** Don't switch frameworks silently.
- [ ] **Step 4:** Implement `BatteryReading`.
- [ ] **Step 5:** Run `swift test` and confirm it passes. Run `swift build` and confirm the app target builds.
- [ ] **Step 6:** Commit with the message `feat: package scaffold and battery reading model`.

### Task 2: Parse AppleSmartBattery data

**Files:**
- Create: `Sources/BatteryCore/BatteryParser.swift`, `Sources/BatteryCore/IOKitBatterySource.swift`
- Test: `Tests/BatteryCoreTests/BatteryParserTests.swift`

**Interfaces:**
- Consumes: `BatteryReading`.
- Produces:
  - `public enum BatteryParser { public static func parse(_ raw: [String: Any], at date: Date) -> BatteryReading? }`
  - `public struct IOKitBatterySource: Sendable { public init(); public func readRaw() -> [String: Any]? }`

Key mapping, taken from the owner's `ioreg` output:
- **Top level:**
  - `CurrentCapacity` gives percent, and `CycleCount` gives cycle count.
  - `DesignCycleCount9C` gives the design cycle count.
  - `Voltage` and `Amperage` give voltage and amperage.
  - `IsCharging`, `ExternalConnected` and `FullyCharged` give the three state flags.
  - `AvgTimeToEmpty` and `AvgTimeToFull` give the OS estimates.
- **`BatteryData` sub-dictionary:** `DesignCapacity`, `FullChargeCapacity` and `RemainingCapacity`.
- **`ChargerData.NotChargingReason`** gives the not-charging reason.
- **`AdapterDetails.Watts`** gives the adapter wattage.

Rules:
- Read every integer via `(value as? NSNumber)?.int64Value`. This turns the unsigned bit pattern (for example 18446744073709551254) into a signed value (-362).
- Treat 65535 in either `AvgTime*` key as nil.
- Return nil if `BatteryData` or any capacity key, `CurrentCapacity`, `Voltage` or `Amperage` is missing, or if `DesignCapacity` is 0.

- [ ] **Step 1: Write the failing tests:**
  - `parsesOwnerSample`: build the dict from the values above, with Amperage as `NSNumber(value: UInt64(18446744073709551254))`. Expect amperage -362, cycle count 8, design cycle count 1000, design capacity 4629, minutes to empty 214, and minutes to full nil (raw 65535).
  - `missingAdapterWattsIsNil`: expect `adapterWatts == nil`.
  - `missingBatteryDataReturnsNil`.
  - `zeroDesignCapacityReturnsNil`.
- [ ] **Step 2:** Run `swift test --filter BatteryParserTests` and confirm it fails.
- [ ] **Step 3:** Implement `BatteryParser.parse`. Implement `IOKitBatterySource.readRaw()` with `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))`, then `IORegistryEntryCreateCFProperties`, then `IOObjectRelease`.
- [ ] **Step 4:** Add the test `liveBatteryParses`. It's an on-machine integration test, guarded so it skips when `readRaw()` is nil. It expects a non-nil parse with `designCapacity > 0`.
- [ ] **Step 5:** Run `swift test` and confirm everything passes.
- [ ] **Step 6:** Commit with the message `feat: parse AppleSmartBattery registry data`.

### Task 3: Smoothing, power state and duration formatting

**Files:**
- Create: `Sources/BatteryCore/EMASmoother.swift`, `Sources/BatteryCore/PowerState.swift`, `Sources/BatteryCore/DurationText.swift`
- Test: `Tests/BatteryCoreTests/PowerStateTests.swift`

**Interfaces:**
- Consumes: `BatteryReading`.
- Produces:
  - `public struct EMASmoother: Sendable { public init(halfLife: TimeInterval); public mutating func add(_ value: Double, at date: Date); public mutating func reset(); public private(set) var value: Double? }`. This is a time-weighted EMA: `alpha = 1 - pow(0.5, dt / halfLife)`. When `dt > 300`, it resets and then takes the new value.
  - `public enum PowerState: Equatable, Sendable { case onBattery(timeLeft: TimeInterval?), charging(timeToFull: TimeInterval?), pluggedIn }`
  - `public struct PowerEstimator: Sendable { public init(); public mutating func update(with reading: BatteryReading) -> PowerState; public var liveWatts: Double? { get }; public var liveVolts: Double? { get }; public var liveAmps: Double? { get } }`. It owns one 300 s smoother for hours left and three 30 s smoothers for the live tiles (watts, volts and amps). It resets both when `externalConnected` changes. `onBattery` means `!externalConnected`. On battery, timeLeft is `remainingWattHours / smoothedWatts * 3600`. It's nil if the smoothed draw is under 0.5 W, and capped at 99 h. On AC, the state is `charging` if `isCharging` (using `osMinutesToFull * 60`, or nil), and `pluggedIn` otherwise.
  - `public enum DurationText { public static func short(_ seconds: TimeInterval) -> String }`. It rounds to the nearest 5 min and formats as "6h 40m", "45m" or "0m".

- [ ] **Step 1: Write the failing tests:**
  - **`steadyUnderNoisyDraw`:** Feed alternating 3 W and 9 W readings every 10 s for 30 min. After the first 10 min, the max and min timeLeft differ by less than 10%.
  - **`gapResetsSmoother`:** Feed 10 W for 10 min, then wait 400 s and feed 2 W. timeLeft equals `remainingWh / 2 W` (±1%).
  - **`unplugResetsSmoother`:** Feed charging readings at 30 W, then one on-battery reading at 4 W. timeLeft is based on 4 W.
  - **`nearZeroDrawIsUnknown`:** 0.3 W gives `.onBattery(timeLeft: nil)`.
  - **`fullOnACIsPluggedIn`:** externalConnected true, isCharging false and fullyCharged true gives `.pluggedIn`.
  - **`chargingUsesOSTimeToFull`:** 65 min gives `.charging(timeToFull: 3900)`.
  - **`formatting`:** 24 000 s gives "6h 40m", 2 690 s gives "45m", 100 s gives "0m", and 362 000 s caps at "99h 0m".
- [ ] **Step 2:** Run `swift test --filter PowerStateTests` and confirm it fails.
- [ ] **Step 3:** Implement the three files.
- [ ] **Step 4:** Run `swift test` and confirm everything passes.
- [ ] **Step 5:** Commit with the message `feat: steady hours-left estimator and power state`.

### Task 4: Learn hours per full charge

**Files:**
- Create: `Sources/BatteryCore/FullChargeLearner.swift`
- Test: `Tests/BatteryCoreTests/FullChargeLearnerTests.swift`

**Interfaces:**
- Consumes: `BatteryReading`.
- Produces:
  - `public struct FullChargeEstimate: Equatable, Sendable { public var hours: Double; public var isEstimate: Bool }`
  - `public struct DischargeSession: Equatable, Sendable { public var start: Date; public var end: Date; public var percentDrop: Int; public var hoursPerFullCharge: Double }`
  - `public enum FullChargeLearner { public static func sessions(in history: [BatteryReading]) -> [DischargeSession]; public static func estimate(history: [BatteryReading], current: BatteryReading?, liveWatts: Double?) -> FullChargeEstimate? }`

Rules:
- A session is a run of consecutive readings with `!externalConnected`. It splits at any gap over 300 s.
- A session is kept only if it dropped ≥ 10 points and lasted ≥ 20 min.
- `hoursPerFullCharge = durationHours / (percentDrop / 100)`.
- `estimate` takes the newest 10 kept sessions, weighted `0.7^i` with i = 0 for the newest, and sets `isEstimate: false`.
- If there are no kept sessions, it falls back to `current.fullWattHours / liveWatts` with `isEstimate: true`. It returns nil when it can't compute either.

- [ ] **Step 1: Write the failing tests:**
  - **`singleSession`:** 100% to 80% over 2 h gives one session with 10 h per full charge.
  - **`gapSplitsSession`:** A 20-minute gap in the middle gives two sessions, and neither includes the gap time.
  - **`shortSessionIgnored`:** A 5-point drop gives no sessions.
  - **`recentWeighted`:** An old session at 12 h and a new one at 8 h give an estimate below 10 h.
  - **`coldStartFallback`:** With no history, full Wh 52 and live 5.2 W, expect `FullChargeEstimate(hours: 10, isEstimate: true)`.
- [ ] **Step 2:** Run `swift test --filter FullChargeLearnerTests` and confirm it fails.
- [ ] **Step 3:** Implement the learner.
- [ ] **Step 4:** Run `swift test` and confirm everything passes.
- [ ] **Step 5:** Commit with the message `feat: learn hours per full charge from discharge sessions`.

### Task 5: History store

**Files:**
- Create: `Sources/BatteryCore/HistoryStore.swift`
- Test: `Tests/BatteryCoreTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: `BatteryReading` (Codable).
- Produces: `public final class HistoryStore: @unchecked Sendable`, with these members:
  - `public init(fileURL: URL)`
  - `public static var defaultURL: URL`, which is `~/Library/Application Support/BatteryMeter/history.jsonl`
  - `public func append(_ r: BatteryReading) throws`
  - `public func load(since: Date) -> [BatteryReading]`
  - `public func prune(olderThan: Date) throws`
  - `public func reset() throws`

Storage is JSON Lines, one reading per line, with ISO 8601 dates. Appending opens the file in append mode and creates the directory if needed. Loading skips any line that fails to decode. Pruning rewrites the file atomically. Access goes through a serial `DispatchQueue`.

- [ ] **Step 1: Write the failing tests** (each one uses a temporary directory):
  - `appendThenLoad` round-trips 3 readings.
  - `loadSinceFilters`.
  - `truncatedLastLineSkipped`: after writing 2 readings, append the raw bytes `{"timest`. `load` returns 2.
  - `pruneRemovesOld`.
  - `resetEmpties`.
- [ ] **Step 2:** Run `swift test --filter HistoryStoreTests` and confirm it fails.
- [ ] **Step 3:** Implement the store.
- [ ] **Step 4:** Run `swift test` and confirm everything passes.
- [ ] **Step 5:** Commit with the message `feat: append-only history store`.

### Task 6: App model, menu bar item, popover and bundle script

**Files:**
- Create: `Sources/BatteryMeter/BatteryModel.swift`, `Sources/BatteryMeter/MenuBarLabel.swift`, `Sources/BatteryMeter/PopoverView.swift`, `Sources/BatteryMeter/StatTile.swift`, `Sources/BatteryMeter/EmptyStateView.swift`, `scripts/bundle.sh`
- Modify: `Sources/BatteryMeter/BatteryMeterApp.swift`

**Interfaces:**
- Consumes: everything in `BatteryCore`.
- Produces: `@MainActor @Observable final class BatteryModel`, with these members:
  - `var reading: BatteryReading?`
  - `var state: PowerState?`
  - `var liveWatts: Double?`, `var liveVolts: Double?` and `var liveAmps: Double?`
  - `var fullCharge: FullChargeEstimate?`
  - `var history: [BatteryReading]`
  - `func start()`
  - `func resetLearnedData()`

`start()` reads immediately and then every 10 s (`Timer` on the main run loop). It appends to the store every 60 s, reloads `history` (limited to the retention window) at launch and after each append, and prunes once per launch. It reads `retentionDays` from `UserDefaults` (default 180).

UI decisions:
- **Menu bar label:** a template SF Symbol plus text.
  - Symbol: `battery.100percent`, `.75percent`, `.50percent`, `.25percent` or `.0percent` by charge level, `battery.100percent.bolt` when charging, and `powerplug` when plugged in.
  - Text by state: `DurationText.short(timeLeft)` on battery, "—" if it's unknown, `DurationText.short(timeToFull)` when charging, and the percent when plugged in.
  - The text format follows the `menuBarFormat` setting from Task 8. It defaults to hours left.
- **Popover:** `.menuBarExtraStyle(.window)`, 300 pt wide, 16 pt padding.
  - **Header:** caption "Left right now", "Charging" or "Plugged in", then the big number in `.system(size: 38, weight: .bold, design: .rounded)` with `.contentTransition(.numericText())`.
  - **Charge bar:** a capsule `ProgressView` tinted green, or yellow at 20% and below, with the percent and power source under it.
  - **Tiles:** a 2×2 `StatTile` grid on `.regularMaterial`, with a 12 pt corner radius.
    - Hours per full charge, with an "estimate" caption when `isEstimate`.
    - Health % to one decimal.
    - Cycles as "8 of 1000".
    - Power draw as "4.1 W".
  - **Footer:** an "Open history…" row that calls `openWindow(id: "main")`.
  - **No battery:** `EmptyStateView` replaces the content with an SF Symbol `battery.0percent`, "No battery found" and one line of explanation.
- **`scripts/bundle.sh`:**
  1. Run `swift build -c release`.
  2. Create `build/Battery Meter.app/Contents/{MacOS,Resources}` and copy the binary in.
  3. Write `Info.plist` with the bundle ID, `LSUIElement` true, `LSMinimumSystemVersion` 27.0, `CFBundleShortVersionString` 0.1.0 and `CFBundleExecutable` BatteryMeter.
  4. Sign ad hoc with `codesign --force --sign - "build/Battery Meter.app"`.

- [ ] **Step 1:** Implement the model and the views. Wire `MenuBarExtra` and a placeholder `Window("Battery Meter", id: "main") { Text("Overview") }` into the app.
- [ ] **Step 2:** Run `swift build` and confirm there are no errors or warnings in the app target.
- [ ] **Step 3:** Write the bundle script, then run `bash scripts/bundle.sh && open "build/Battery Meter.app"`. The expected result:
  - A battery symbol with hours appears in the menu bar, with no Dock icon.
  - Clicking it shows the popover with real values: cycles "8 of 1000" and health about 98.8%.
- [ ] **Step 4: Visual check.** Run `screencapture -x build/popover-light.png` with the popover open, then repeat in dark mode. Compare both against the approved mockup at `.superpowers/brainstorm/*/content/macos-style.html` (option A). Fix spacing, alignment and contrast before moving on, because a screen that looks off is a failure.
- [ ] **Step 5:** Commit with the message `feat: menu bar item and popover`.

### Task 7: Full window: overview, history, health

**Files:**
- Create: `Sources/BatteryMeter/MainWindow.swift`, `Sources/BatteryMeter/OverviewView.swift`, `Sources/BatteryMeter/HistoryView.swift`, `Sources/BatteryMeter/HealthView.swift`
- Modify: `Sources/BatteryMeter/BatteryMeterApp.swift`

**Interfaces:**
- Consumes: `BatteryModel` and `FullChargeLearner.sessions(in:)`.
- Produces: `enum SidebarItem: String, CaseIterable, Identifiable { case overview, history, health, settings }`. Task 8 fills in settings.

Decisions:
- **Window layout:** `NavigationSplitView` with sidebar labels and SF Symbols:
  - "Overview" uses `gauge.with.dots.needle.33percent`.
  - "History" uses `chart.xyaxis.line`.
  - "Health" uses `heart.text.square`.
  - "Settings" uses `gearshape`.
- **Window size:** default 760×520, minimum 640×440.
- **Overview:** the two big numbers (left now and per full charge) and the four popover tiles, plus voltage and amperage. Values come from the 30 s smoothed reading.
- **History:** two Swift Charts in `GroupBox`es.
  - "Hours per full charge" is a `LineMark` and `PointMark` per session.
  - "Battery health" is the daily mean of `healthPercent` as a `LineMark`.
  - When there's no data, each chart shows `ContentUnavailableView` with "Not enough history yet".
  - **Load the `dataviz` skill before writing chart code.**
- **Health:** a grouped `Form` of `LabeledContent` rows for design capacity, full charge capacity, health %, cycles, voltage, amperage, adapter watts and not-charging reason. A row is hidden when its value is nil.
- **Dock icon:** `NSApp.setActivationPolicy(.regular)` when the window appears, and `.accessory` when it disappears.

- [ ] **Step 1:** Implement the views and wire `SidebarItem` selection.
- [ ] **Step 2:** Run `swift build` and confirm it builds clean.
- [ ] **Step 3:** Run `bash scripts/bundle.sh && open "build/Battery Meter.app"`, then click "Open history…". Expect the window and a Dock icon. Expect the Dock icon to go away when the window closes. Expect the Health rows to match `ioreg -rn AppleSmartBattery`.
- [ ] **Step 4: Visual check.** Take screenshots in light and dark mode, check them against mockup option B, and fix anything that looks off.
- [ ] **Step 5:** Commit with the message `feat: full window with overview, history and health`.

### Task 8: Settings

**Files:**
- Create: `Sources/BatteryMeter/SettingsView.swift`
- Modify: `Sources/BatteryMeter/MainWindow.swift`, `Sources/BatteryMeter/MenuBarLabel.swift`, `Sources/BatteryMeter/BatteryModel.swift`

**Interfaces:**
- Consumes: `BatteryModel.resetLearnedData()` and `HistoryStore.reset()`.
- Produces: the `@AppStorage` keys `menuBarFormat` (`"hours"`, `"percent"` or `"both"`, default `"hours"`) and `retentionDays` (Int, default 180).

Decisions:
- **Layout:** a grouped `Form` with exactly four controls.
- **"Launch at login":** a `Toggle` bound to `SMAppService.mainApp` status, calling register or unregister. Errors show inline in secondary text. On first launch, register once if the status is `.notRegistered`, and store a `didOfferLaunchAtLogin` flag so it's on by default.
- **"Menu bar shows":** a `Picker` with "Hours left", "Percent" and "Hours and percent".
- **"Keep history for":** a `Picker` with 30, 90, 180 and 365 days.
- **"Reset learned data…":** a destructive button behind a `confirmationDialog`. It clears the store and the in-memory history.

- [ ] **Step 1:** Implement the settings view and wire `menuBarFormat` into `MenuBarLabel`.
- [ ] **Step 2:** Run `swift build` and confirm it builds clean.
- [ ] **Step 3:** Run `bash scripts/bundle.sh`, copy the app to `~/Applications`, and open it. Then check each control:
  - Toggling launch at login updates **System Settings → General → Login Items**.
  - Each menu bar format changes the label right away.
  - Reset empties the History charts.
- [ ] **Step 4:** Run `swift test` and confirm every core test still passes.
- [ ] **Step 5:** Commit with the message `feat: settings`.
