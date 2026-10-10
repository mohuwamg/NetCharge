cask "netcharge" do
  version "0.1.3-build.3"
  sha256 "79fef15fe6ad39d7b0f669591ecaec04d22f3970c848e1897c078774719081ed"

  url "https://github.com/mohuwamg/NetCharge/releases/download/v#{version}/NetCharge-macOS-arm64.dmg"
  name "NetCharge"
  desc "Menu bar network speed and battery charge limit control"
  homepage "https://github.com/mohuwamg/NetCharge"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "NetCharge.app"
end
