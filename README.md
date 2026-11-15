# CoffeeRefill

CoffeeRefill 是一个 macOS 菜单栏工具。它可以开启全局禁睡，让 MacBook 合盖后继续运行。当前发布验收目标为 Apple Silicon MacBook，最低系统版本为 macOS 14。

## 安装与使用

在 [GitHub Releases](https://github.com/lttleraccoon-afk/CoffeeRefill/releases) 的 **Assets** 下载 `CoffeeRefill-1.1-rc-macos-arm64.zip`，解压并把 `CoffeeRefill.app` 拖到「应用程序」。

预览版使用本地临时签名，未经 Apple 公证。首次尝试打开后，如果 macOS 提示无法验证开发者，请先确认 ZIP 来自本仓库的 Release，再按 [Apple 的打开指引](https://support.apple.com/zh-cn/102445)，在「系统设置 › 隐私与安全性」选择「仍要打开」。也可以按下方步骤从源码构建。与 ZIP 一起下载 `.sha256` 文件后，可在下载目录运行 `shasum -a 256 -c CoffeeRefill-1.1-rc-macos-arm64.zip.sha256` 核对下载完整性。

打开 `CoffeeRefill.app`，点击菜单栏月亮图标。开启全局禁睡后图标变为闪电。本次运行第一次切换时，系统弹出管理员授权对话框。之后的切换和「关闭并退出」复用同一会话。应用回读 `SleepDisabled` 后才更新开关。取消授权或执行失败时，重新打开面板可查看提示与当前状态。

全局禁睡开启时，应用监听盖子状态。合盖运行 `/usr/bin/pmset displaysleepnow`，让显示器立即休眠。开盖运行 `/usr/bin/caffeinate -u -t 1`，唤醒显示器。合盖熄屏会同时作用于外接显示器，锁屏行为由 macOS 设置决定。关闭全局禁睡会停止监听。

开关通过系统授权执行与下列终端命令等效的操作：

```bash
sudo /usr/bin/pmset -a disablesleep 1
sudo /usr/bin/pmset -a disablesleep 0
```

设置对整台 Mac 生效，关闭会将它设为 `0`。开启期间，合盖、主动睡眠及保护性睡眠均可能受到影响。请在通风处使用，收进包前先关闭。避免与其他修改 `SleepDisabled` 的工具或多个 CoffeeRefill 实例同时使用。

面板中的「关闭并退出」先恢复睡眠，再退出应用。授权会话随应用退出结束，不安装常驻 root 服务。若应用断开连接时仍有本次启用的禁睡，会话会尝试关闭。强制退出或重启后，请重新打开应用检查状态；如仍显示开启，在面板关闭或在终端运行 `sudo /usr/bin/pmset -a disablesleep 0`。

## 从源码构建

打开 `SleepSwitch.xcodeproj`，选择 SleepSwitch 方案与 My Mac 后运行。也可在工程目录用命令行构建：

```bash
xcodebuild -project SleepSwitch.xcodeproj -scheme SleepSwitch \
  -configuration Release -destination 'platform=macOS,arch=arm64' ARCHS=arm64 build
```

项目不使用第三方依赖，本地构建默认采用临时签名。发布步骤见 [发布清单](RELEASING.md)。

## 许可证

[MIT License](LICENSE)
