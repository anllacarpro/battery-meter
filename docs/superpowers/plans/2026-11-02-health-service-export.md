# Health accuracy, service advice and CSV export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Health match macOS's Maximum Capacity, tell the user when the battery needs service, and let them export their history as CSV.

**Architecture:**
- Pure logic lives in `BatteryCore` with Swift Testing tests: a new optional `nominalChargeCapacity` on `BatteryReading`, a `ServiceAdvice` enum and a `HistoryCSV` encoder.
- The app only renders them: a row and an advice section in `HealthView`, and an export button in `SettingsView`.

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI, Swift Testing.

**Spec:** none. The request came from the conversation of 2026-11-02: health showed 100.5% (`FullChargeCapacity` 4666 over `DesignCapacity` 4629), and these were the three recommendations picked. `docs/superpowers/specs/2026-11-01-battery-meter-design.md` still applies.

**Branch:** `feat/health-service-export`, cut from `main`.

## Global Constraints

- Platform `.macOS("27.0")`, arm64, Command Line Tools only.
- Don't use SwiftUI `@State`, `@Entry` or `@Previewable`; use `@Observable` objects or `@AppStorage`.
- Native look, sentence case, no emoji. Never show a value the data can't support.
- Old `history.jsonl` lines have no `NominalChargeCapacity`; they must still decode.
- Health never exceeds 100.
- Run tests with `swift test`.

## Review Focus

- A reading with no nominal capacity (old history line, or the key missing from the registry) falls back to `fullChargeCapacity`. Pinned in Task 1.
- `nominalChargeCapacity` of 0 is treated as missing, not as 0% health. Pinned in Task 1.
- Health and cycles exactly at the advice thresholds. Pinned in Task 2.
- A battery with no `designCycleCount` can't trigger the cycles advice. Pinned in Task 2.
- Empty history exports a header-only CSV, not an empty file. Pinned in Task 3.

---

### Task 1: Health from nominal charge capacity

**Files:**
- Modify: `Sources/BatteryCore/BatteryReading.swift`, `Sources/BatteryCore/BatteryParser.swift`
- Modify: `Sources/BatteryMeter/HealthView.swift`
- Test: `Tests/BatteryCoreTests/BatteryReadingTests.swift`, `Tests/BatteryCoreTests/BatteryParserTests.swift`

**Interfaces:**
- Produces: `BatteryReading.nominalChargeCapacity: Int?` (mAh, last init parameter, default `nil`) and `healthPercent` computed from it.

- [ ] **Step 1: Write the failing tests.**
  - In `BatteryReadingTests`: `healthUsesNominalCapacityWhenPresent` (design 4629, full 4666, nominal 4400 → `abs(healthPercent - 95.06) < 0.01`); `healthFallsBackToFullChargeWhenNominalMissing` (nominal `nil`, full 4575 → 98.83); `zeroNominalCountsAsMissing` (nominal 0, full 4575 → 98.83). The existing `healthNeverExceedsOneHundred` stays.
  - In `BatteryParserTests`: a fixture that includes `BatteryData["NominalChargeCapacity"] = 4785` parses to `nominalChargeCapacity == 4785`; the existing fixture without it parses to `nil`. Follow the file's existing fixture helper.
- [ ] **Step 2: Run `swift test`; expect compile failure on the missing property.**
- [ ] **Step 3: Implement.**
  - Add `public var nominalChargeCapacity: Int?` to `BatteryReading` and as the last init parameter with default `nil`.
  - `healthPercent` uses `nominalChargeCapacity` when it is non-nil and > 0, else `fullChargeCapacity`, then caps at 100.
  - `BatteryParser.parse` reads `battery["NominalChargeCapacity"]` through the existing `int(_:)`.
  - `HealthView`: after the "Full charge capacity" row add a "Nominal charge capacity" row, shown only when the value is non-nil.
- [ ] **Step 4: Run `swift test`; expect all pass.**
- [ ] **Step 5: Commit** `feat: base health on nominal charge capacity like macOS`.

### Task 2: Service advice

**Files:**
- Create: `Sources/BatteryCore/ServiceAdvice.swift`
- Modify: `Sources/BatteryMeter/HealthView.swift`
- Test: `Tests/BatteryCoreTests/ServiceAdviceTests.swift`

**Interfaces:**
- Consumes: `BatteryReading.healthPercent`, `cycleCount`, `designCycleCount`.
- Produces: `public enum ServiceAdvice: Equatable, Sendable { case none; case lowHealth; case highCycles }` with `public static func advice(for reading: BatteryReading) -> ServiceAdvice` and `public var message: String?` (nil for `.none`).

- [ ] **Step 1: Write the failing tests** in `ServiceAdviceTests`:
  - `healthyBatteryNeedsNothing`: health 100, 9 of 1000 cycles → `.none`, `message == nil`.
  - `healthBelow80IsLowHealth`: health 79.9 → `.lowHealth`; health exactly 80 → `.none`.
  - `cyclesAtEightyPercentOfLimitIsHighCycles`: 800 of 1000 → `.highCycles`; 799 → `.none`.
  - `missingDesignCycleCountNeverTriggersCycles`: `designCycleCount` nil, 5000 cycles → `.none`.
  - `lowHealthWinsOverHighCycles`: both true → `.lowHealth`.
  - Messages: `.lowHealth` → "Health is below 80%, Apple's service threshold. Consider a battery service."; `.highCycles` → "This battery is near its rated cycle count. Health may start to drop faster."
- [ ] **Step 2: Run `swift test --filter ServiceAdviceTests`; expect compile failure.**
- [ ] **Step 3: Implement `ServiceAdvice`** as above. In `HealthView`, render the message in a `Section` above "Electrical" only when `message` is non-nil, with a `Label` using the `exclamationmark.triangle` SF Symbol and `.foregroundStyle(.secondary)`.
- [ ] **Step 4: Run `swift test`; expect all pass.**
- [ ] **Step 5: Commit** `feat: advise battery service on low health or high cycles`.

### Task 3: CSV export

**Files:**
- Create: `Sources/BatteryCore/HistoryCSV.swift`
- Modify: `Sources/BatteryMeter/SettingsView.swift`, `Sources/BatteryMeter/BatteryModel.swift`
- Test: `Tests/BatteryCoreTests/HistoryCSVTests.swift`

**Interfaces:**
- Consumes: `HistoryStore.load(since:) -> [BatteryReading]`.
- Produces: `public enum HistoryCSV { public static func encode(_ readings: [BatteryReading]) -> String }`. Header `timestamp,percent,remaining_mah,full_charge_mah,design_mah,nominal_mah,cycles,voltage_mv,amperage_ma,charging,external_power`. One row per reading in the given order, timestamps ISO 8601 UTC, booleans `true`/`false`, a missing nominal as an empty field, every line ending in `\n`.

- [ ] **Step 1: Write the failing tests** in `HistoryCSVTests`:
  - `emptyHistoryIsHeaderOnly`: output equals the header plus `\n`.
  - `rowFormatsEveryColumn`: timestamp `Date(timeIntervalSince1970: 0)` → row `1970-01-01T00:00:00Z,61,2710,4666,4629,4785,9,11853,-662,false,false`.
  - `missingNominalIsEmptyField`: row has `,,` where nominal goes.
- [ ] **Step 2: Run `swift test --filter HistoryCSVTests`; expect compile failure.**
- [ ] **Step 3: Implement `HistoryCSV.encode`** with `ISO8601DateFormatter` (default options, UTC).
- [ ] **Step 4: Wire the UI.** In `BatteryModel` add `func exportHistory(to url: URL) throws` that loads the whole history (`since: .distantPast`) and writes `HistoryCSV.encode` atomically as UTF-8. In `SettingsView`'s "History" section add an "Export history…" button that opens an `NSSavePanel` (default name `battery-history.csv`, content type `.commaSeparatedText`) and calls it; on error show an `NSAlert` with the error's `localizedDescription`.
- [ ] **Step 5: Run `swift test`; expect all pass. Run `swift build`; expect success.**
- [ ] **Step 6: Commit** `feat: export history as CSV`.
