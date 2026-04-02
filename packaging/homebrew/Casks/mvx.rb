cask "mvx" do
  version "0.1.3"
  sha256 "1e55fe1ec583f89706b099bdf1c67b7ed4219978b7cdb3929bdf7705fb16c981"

  url "https://github.com/Saewt/mvx/releases/download/v0.1.3/mvx-0.1.3.dmg"
  name "mvx"
  desc "AI-agent-aware terminal workspace for macOS"
  homepage "https://github.com/Saewt/mvx"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "mvx.app"
end
