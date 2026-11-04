cask "battery-meter" do
  version "0.2.0"

  # sha256 is updated by the Release workflow (PR: automation/bump-cask-v*).
  sha256 "67f0f837bdfce62fb1c61402abf37aecbd5f7d8c8a75960c119235e2d0be8d31"

  url "https://github.com/anllacarpro/battery-meter/releases/download/v#{version}/Battery-Meter-#{version}.zip"
  name "Battery Meter"
  desc "Menu bar battery monitor with runtime estimates, health details, and history"
  homepage "https://github.com/anllacarpro/battery-meter"

  depends_on macos: :golden_gate

  app "Battery Meter.app"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  caveats <<~EOS
    Battery Meter requires macOS 27 (Golden Gate) or later and a Mac with a built-in battery.
    The app is ad hoc signed; if macOS blocks it, remove quarantine:
      xattr -cr "/Applications/Battery Meter.app"
  EOS
end
