cask "battery-meter" do
  version "0.1.0"

  # sha256 is updated by the Release workflow (PR: automation/bump-cask-v*).
  sha256 "cf4dfbd569bda4570bdacdb721661cafc81044fa91858a99d02c833cc291a889"

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
