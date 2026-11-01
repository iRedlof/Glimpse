cask "glimpse" do
  version "1.1.2"
  sha256 :no_check

  url "https://github.com/iRedlof/Glimpse/releases/download/v#{version}/Glimpse-#{version}.zip"
  name "Glimpse"
  desc "A lightweight macOS menu bar calendar app"
  homepage "https://github.com/iRedlof/Glimpse"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Glimpse.app"

  zap trash: [
    "~/Library/Preferences/com.rohit.Glimpse.plist",
  ]
end
