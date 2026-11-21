cask "systems42-dashboard" do
  version "0.12.0"
  sha256 :no_check # Updated per release from Systems42-Dashboard-<version>-universal.dmg.sha256

  url "https://github.com/systems42-org/systems42-dashboard/releases/download/v#{version}/Systems42-Dashboard-#{version}-universal.dmg"
  name "Systems42 Dashboard"
  desc "Read-only desktop dashboard for Systems42 requirements wikis"
  homepage "https://dashboard.systems42.org/"

  depends_on macos: ">= :sonoma"

  app "Systems42 Dashboard.app"

  zap trash: [
    "~/Library/Application Support/Systems42 Dashboard",
  ]
end
