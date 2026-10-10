#!/bin/bash
set -euo pipefail

VERSION="${1:?用法: update-cask.sh <版本> <DMG SHA-256> [输出路径]}"
SHA256="${2:?用法: update-cask.sh <版本> <DMG SHA-256> [输出路径]}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${3:-$PROJECT_ROOT/Casks/netcharge.rb}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-build\.[0-9]+$ ]]; then
    echo "版本格式应为 0.1.3-build.5" >&2
    exit 1
fi
if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "DMG SHA-256 必须为 64 位小写十六进制数" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
cask "netcharge" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/mohuwamg/NetCharge/releases/download/v#{version}/NetCharge-macOS-arm64.dmg"
  name "NetCharge"
  desc "Menu bar network speed and battery charge limit control"
  homepage "https://github.com/mohuwamg/NetCharge"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "NetCharge.app"
end
EOF
