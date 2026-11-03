cask "battery-meter" do
  version "0.1.1"

  # sha256 is updated by the Release workflow (PR: automation/bump-cask-v*).
  sha256 "366151df5a968df23e03679a9d67255c169f9a763cec5d3c46b6467ff0e4f48f"

  url "https://github.com/anllacarpro/battery-meter/releases/download/v#{version}/Battery-Meter-#{version}.zip"
  name "Battery Meter"
  desc "Menu bar battery monitor with runtime estimates, health details, and history"
  homepage "https://github.com/anllacarpro/battery-meter"

  depends_on macos: ">= :sequoia"

  app "Battery Meter.app"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  caveats <<~EOS
    Battery Meter requires macOS 27 (Tahoe) or later and a Mac with a built-in battery.
    The app is ad hoc signed; if macOS blocks it, remove quarantine:
      xattr -cr "/Applications/Battery Meter.app"
  EOS
end
