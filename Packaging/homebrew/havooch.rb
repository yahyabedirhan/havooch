# The cask the tap yahyabedirhan/homebrew-tap carries as Casks/havooch.rb.
# scripts/update-tap.sh copies this file there on each release and fills in
# `version` and `sha256`; edit the cask here, never in the tap.
#
# Install: brew install --cask yahyabedirhan/tap/havooch
#
# Homebrew rules for an app that is ad-hoc signed and not notarized (checked
# 2026-10-05, Homebrew 7.0):
# - homebrew/cask (the official tap) disables casks that fail Gatekeeper
#   checks since September 2026, so this cask can live only in our own tap.
#   https://brew.sh/2025/11/12/homebrew-5.0.0/ and
#   https://docs.brew.sh/Acceptable-Casks
# - Third-party taps aren't held to that check, but `--no-quarantine` is
#   disabled (Homebrew 5.1.0, https://github.com/Homebrew/brew/pull/21629), so
#   brew quarantines the app and the person passes Gatekeeper once by hand:
#   the caveat below says how. The `binary` below is a link to the command
#   inside that app, so Gatekeeper stops the first run of `havooch` too, not
#   only the first launch of the app.
# - Clearing the quarantine in the cask itself (`xattr` in a postflight) is
#   what Homebrew asks taps not to do, and third-party cask flight blocks are
#   deprecated until 2027-12-11 (https://brew.sh/2026/09/13/homebrew-7.0.0/).
#   This cask has none.
# - Since Homebrew 6.0 a third-party tap must be trusted. Installing by the
#   full name (yahyabedirhan/tap/havooch) trusts this one cask.
#   https://docs.brew.sh/Tap-Trust
cask "havooch" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/yahyabedirhan/havooch/releases/download/v#{version}/havooch-#{version}.zip"
  name "Havooch"
  desc "Video player for giving feedback to coding agents"
  homepage "https://github.com/yahyabedirhan/havooch"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Havooch.app"
  binary "#{appdir}/Havooch.app/Contents/Helpers/havooch"

  zap trash: [
    "~/Library/Application Support/Havooch",
    "~/Library/Preferences/com.yahyabedirhan.havooch.plist",
  ]

  caveats <<~EOS
    Havooch is ad-hoc signed and not notarized by Apple. The first time you
    open Havooch or run `havooch` (the command is a link into the app), macOS
    says "Havooch Not Opened": it can't check the app for malicious software.
    Allow it once:
      1. Open System Settings > Privacy & Security.
      2. Next to the message about Havooch, click Open Anyway, then confirm.
    Or clear the quarantine flag yourself:
      xattr -dr com.apple.quarantine "#{appdir}/Havooch.app"

    For your coding agent, install the mate skill:
      npx skills add yahyabedirhan/havooch-mate --skill havooch-mate --global
  EOS
end
