cask "netcharge" do
  version "0.1.4-build.5"
  sha256 "66df588d23f960a17674ddc0f474be1018da071ca9b85ec1711b9ed4dbaf2e50"

  url "https://github.com/mohuwamg/NetCharge/releases/download/v#{version}/NetCharge-macOS-arm64.dmg"
  name "NetCharge"
  desc "Menu bar network speed and battery charge limit control"
  homepage "https://github.com/mohuwamg/NetCharge"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "NetCharge.app"
end
