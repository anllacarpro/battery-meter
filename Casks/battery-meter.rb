cask "battery-meter" do
  version "0.1.2"

  # sha256 is updated by the Release workflow (PR: automation/bump-cask-v*).
  sha256 "53b85bc4759bfe516f05d2a1bf8dddbfbc74da6c4980b4b759cdb8607e53c30a"

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
