cask "battery-meter" do
  version "0.1.3"

  # sha256 is updated by the Release workflow (PR: automation/bump-cask-v*).
  sha256 "3f2a2484b0cfe08187997e6b016e965d071da0a9d2e3a23a1b9911ce506e2bb1"

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
