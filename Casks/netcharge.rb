cask "netcharge" do
  version "0.1.5-build.6"
  sha256 "05921d9331e927e318b6f3d53d3c9b25eaa805b81677be8bc6ccf3757179f9fe"

  url "https://github.com/mohuwamg/NetCharge/releases/download/v#{version}/NetCharge-macOS-arm64.dmg"
  name "NetCharge"
  desc "Menu bar network speed and battery charge limit control"
  homepage "https://github.com/mohuwamg/NetCharge"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "NetCharge.app"
end
