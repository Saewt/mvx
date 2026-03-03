cask "mvx" do
  version "0.1.0"
  sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  url "https://downloads.example.com/mvx/mvx-0.1.0.dmg"
  name "mvx"
  desc "AI-agent-aware terminal workspace for macOS"
  homepage "https://github.com/emirekici/mvx"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "mvx.app"
end
