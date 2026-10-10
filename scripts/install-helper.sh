#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "请以管理员权限运行安装脚本" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/netcharge-helper"
DESTINATION="/Library/PrivilegedHelperTools/com.netcharge.helper"
PLIST="/Library/LaunchDaemons/com.netcharge.helper.plist"

if [[ ! -x "$SOURCE" ]]; then
    echo "找不到 netcharge-helper" >&2
    exit 1
fi

# Detect the common batt LaunchDaemon labels before taking over its setting.
BATT_LABEL=""
BATT_DISABLED=0
restore_batt_on_error() {
    if [[ "$BATT_DISABLED" == "1" ]]; then
        echo "NetCharge 接管失败，恢复 batt 服务。" >&2
        /bin/launchctl enable "system/$BATT_LABEL" || true
        /bin/launchctl bootstrap system "/Library/LaunchDaemons/$BATT_LABEL.plist" || true
    fi
}
trap restore_batt_on_error EXIT
for label in sh.brew.batt cc.chlc.batt; do
    if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
        BATT_LABEL="$label"
        break
    fi
done
if /usr/bin/pgrep -x batt >/dev/null 2>&1 && [[ -z "$BATT_LABEL" ]]; then
    echo "检测到正在运行的 batt，但无法确认其服务名称；请先手动停止它。" >&2
    exit 1
fi

mkdir -p /Library/PrivilegedHelperTools "/Library/Application Support/NetCharge"
if /bin/launchctl print system/com.netcharge.helper >/dev/null 2>&1; then
    /bin/launchctl bootout system "$PLIST"
fi

install -o root -g wheel -m 755 "$SOURCE" "$DESTINATION"
cat > "$PLIST" <<'PLIST_CONTENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.netcharge.helper</string>
<key>ProgramArguments</key><array>
<string>/Library/PrivilegedHelperTools/com.netcharge.helper</string>
<string>maintain</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>StandardErrorPath</key><string>/Library/Logs/NetCharge-helper.log</string>
<key>StandardOutPath</key><string>/Library/Logs/NetCharge-helper.log</string>
</dict></plist>
PLIST_CONTENT
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

# Adopt the existing limit by reading SMC, then stop batt before writing.
"$DESTINATION" adopt-current
if [[ -n "$BATT_LABEL" ]]; then
    /bin/launchctl disable "system/$BATT_LABEL"
    BATT_DISABLED=1
    /bin/launchctl bootout system "/Library/LaunchDaemons/$BATT_LABEL.plist"
fi

"$DESTINATION" apply-config
/bin/launchctl bootstrap system "$PLIST"
BATT_DISABLED=0
echo "NetCharge 控制服务已安装。"
