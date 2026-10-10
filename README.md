# NetCharge

NetCharge 是用 Swift 编写的 macOS 菜单栏工具：菜单栏以红点和蓝点分别显示上传、下载速度；点击后可查看电池状态并设置充电上限。

## 系统要求

- macOS 13 或更新版本的 Apple Silicon MacBook。
- 充电上限功能要求固件允许读写 `bfF0`、`bfD0`、`bfE0` SMC 键。网络速度显示不依赖这些键。

## 下载安装（无需构建）

1. 在 [GitHub Releases](https://github.com/mohuwamg/NetCharge/releases/latest) 下载最新的 `NetCharge-macOS-arm64.zip`，双击解压得到 `NetCharge.app`。无需安装 Xcode、Swift 或 Git。
2. 如果已运行旧版本，先在菜单栏面板中点击「退出 NetCharge」。将解压得到的 `NetCharge.app` 拖入「应用程序」文件夹；Finder 提示时选择「替换」。
3. 从「应用程序」打开 NetCharge。它只显示在菜单栏，不显示 Dock 图标。

此安装包经过本机临时签名，**未经过 Apple 公证**。如果 macOS 阻止首次打开，请先确认下载来源，再按 [Apple 的说明](https://support.apple.com/102445) 到「系统设置 → 隐私与安全性」选择「仍要打开」。无需关闭 Gatekeeper。

每个 Release 还附有同名 `.sha256` 校验文件和「本次修改」说明。`main` 分支更新后，GitHub Actions 会自动运行测试、构建 Apple Silicon 版 App 并发布新 Release；安装包不保存在源码仓库中。

## 首次启用充电上限

1. 点击菜单栏中的网速显示，打开 NetCharge 面板。
2. 点击「安装充电控制服务」，在 macOS 弹出的授权对话框中输入管理员密码。这一步会安装 NetCharge 自带的 Swift 后台服务，并在接管时停用已识别的 `batt` LaunchDaemon；不会调用 `batt` 来控制充电。
3. 在滑块上选择目标上限（10%–95%，每档 5%），点击「设置充电上限」并完成管理员授权。选择 100% 表示关闭上限。下限自动设为上限减 2%。
4. 面板出现「充电上限 80%」之类的状态后，可用下面的只读命令独立检查固件实际读回值：

   ```bash
   /Applications/NetCharge.app/Contents/Resources/netcharge-helper probe
   pmset -g batt
   ```

   `probe` 输出中的 `active` 应为 `true`，`upperLimit` 应为所设数值。`pmset` 用于查看当前电量和是否正在充电。菜单栏的电量百分比与固件控制值可能相差几个百分点；判断是否仍在充电时，还应看「充电中」状态。

若固件不支持这些键或拒绝写入，应用会报告错误。控制服务安装后每 60 秒核对一次固件上限，状态保存在 `/Library/Application Support/NetCharge/status.json`。

## 更新

从 [GitHub Releases](https://github.com/mohuwamg/NetCharge/releases/latest) 下载新版 ZIP，退出旧版 App，解压后在 Finder 中替换「应用程序」里的 `NetCharge.app`。

替换 App 后运行以下命令更新后台服务，再启动 App，避免 App 与服务版本不一致：

```bash
sudo bash /Applications/NetCharge.app/Contents/Resources/install-helper.sh
open /Applications/NetCharge.app
```

确认 NetCharge 接管并读回原有上限后，才单独卸载 `batt`。卸载其他充电管理工具可能重置 SMC 设置；卸载后再次运行 `probe` 核对。

## 参考

- [Stats 的网络模块](https://github.com/exelban/stats/blob/d31a662624eec1fd59239ecb4142cfbac1a37d72/Modules/Net/readers.swift)：网络接口选择与累计字节计数方式。
- [batt 项目](https://github.com/charlie0129/batt)：固件控制键行为及兼容性研究。NetCharge 未复制其 GPL 源码。
