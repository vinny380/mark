# Homebrew cask for Mark. Lives in the tap repo (github.com/vinny380/homebrew-tap) as Casks/mark.rb.
# Update version + sha256 from `scripts/release.sh` for each release.
cask "mark" do
  version "1.0.0"
  sha256 "b8ee1695a93c3f7307cc5eaac9d799755a0c5fbe7278bb17510aabd965071ed5"

  url "https://github.com/vinny380/mark/releases/download/v#{version}/Mark-#{version}.zip"
  name "Mark"
  desc "Tiny native Markdown editor: right-click your Desktop, start typing"
  homepage "https://github.com/vinny380/mark"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Mark.app"
  binary "#{appdir}/Mark.app/Contents/Resources/mark"

  zap trash: [
    "~/Library/Preferences/com.vinny.mark.plist",
    "~/Library/Saved Application State/com.vinny.mark.savedState",
  ]

  caveats <<~EOS
    Mark isn't notarized by Apple yet. The first time you open it, go to
    System Settings → Privacy & Security and click "Open Anyway".

    To get "New Markdown File" in Finder's right-click menu, open Mark once, then
    turn it on in System Settings → General → Login Items & Extensions.
  EOS
end
