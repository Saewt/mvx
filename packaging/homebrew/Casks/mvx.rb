cask "mvx" do
  version "0.1.2"
  sha256 "d70be45aec75e25fc21a27f754c396ba07611f585499bf2c0fd9bfa6a2c3a452"

  url "https://github.com/Saewt/mvx/releases/download/v0.1.2/mvx-0.1.2.dmg"
  name "mvx"
  desc "AI-agent-aware terminal workspace for macOS"
  homepage "https://github.com/Saewt/mvx"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "mvx.app"
end
