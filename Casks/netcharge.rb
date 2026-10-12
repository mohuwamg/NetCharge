cask "netcharge" do
  version "0.1.3-build.4"
  sha256 "d285b8062639662a925b7deb0f0f033637095a0ccd3d54fe69637b18a47d50ec"

  url "https://github.com/mohuwamg/NetCharge/releases/download/v#{version}/NetCharge-macOS-arm64.dmg"
  name "NetCharge"
  desc "Menu bar network speed and battery charge limit control"
  homepage "https://github.com/mohuwamg/NetCharge"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "NetCharge.app"
end
