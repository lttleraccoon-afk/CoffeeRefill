# CoffeeRefill 发布清单

当前候选版本为 `1.1`（构建 `2`），通过 GitHub 发布免费预览版。

## 1. 本地验收

- [ ] 停掉旧版与其他修改全局禁睡的工具。使用 Apple Silicon MacBook，记录硬件、系统版本和供电方式。发布前覆盖最低承诺版本 macOS 14 和当前正式版。
- [ ] 检查初始状态；取消管理员授权应不修改设置。重新授权后开启、关闭、再次开启，检查图标和读回状态；确认有效会话不会重复弹授权框。
- [ ] 接电、用电池各测一次合盖熄屏、闭盖任务持续运行、开盖亮屏。接外屏另测一次。用持续写时间戳的任务检查闭盖期间是否停顿，仅看开盖亮屏无法证明任务持续运行。
- [ ] 验证「关闭并退出」后恢复正常睡眠。开启后另测强制退出、注销或重启；确认是否恢复，必要时用 `sudo /usr/bin/pmset -a disablesleep 0` 手动恢复。全局设置的异常恢复无法保证。
- [ ] 有条件时在另一台 Apple Silicon Mac 上从 GitHub 下载实际发布的 ZIP，验证解压、安装、首次打开及退出。

可只读检查电源状态：

```bash
/usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | grep '"SleepDisabled"'
```

`verify-lid.sh` 是早期 `caffeinate` 方案的探针，不能替代以上验收。

## 2. 免费发布 GitHub 预览版

1. 将源码、README 和 `LICENSE` 提交到 Git。`Build/`、`dist/` 和 Xcode 用户设置留在本机。
2. 在 GitHub Releases 建立 `v1.1-rc.1`，勾选 **This is a pre-release**，上传 `CoffeeRefill-1.1-rc-macos-arm64.zip` 和对应的 `.sha256` 文件。注明 Apple Silicon、macOS 14 或更新版本、本地临时签名及 Apple 公证状态。[GitHub Release 指南](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
3. 核对说明和附件后发布。若希望任何人都能访问，可以把仓库设为 **Public**，届时源码和已发布的 Release 都可访问。[仓库可见性设置](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)

## 3. 可选：签名和公证的 GitHub 版

1. 加入 [Apple Developer Program](https://developer.apple.com/help/account/membership/program-enrollment/)，取得 [Developer ID Application 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。用 Xcode Release archive 导出带 Hardened Runtime 的签名版，向 Apple 提交公证。若以 ZIP 提交公证，收到 `Accepted` 后用 `xcrun stapler staple CoffeeRefill.app` 把票据附到 `.app`，再用 `ditto -c -k --keepParent` 重新打包。详见 [Apple 公证指南](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
2. 对最终 `.app` 运行 `codesign --verify --deep --strict CoffeeRefill.app`、`xcrun stapler validate CoffeeRefill.app` 和 `syspolicy_check distribution CoffeeRefill.app`。对最终 ZIP 生成 `shasum -a 256` 校验值，再上传到 [GitHub Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。GitHub 自动生成的 Source code ZIP 只含源码。

本地 `dist/` 的 `.xcarchive` 留给开发者，用于保存构建及调试符号；`-rc-` ZIP 仅供试用。面向用户发签名且公证后的 `.app` ZIP 就够，无需额外制作 `.dmg` 或 `.pkg`。

正式签名前可先在非同步目录归档。若签名校验提示 `resource fork, Finder information, or similar detritus not allowed`，用 `xattr -lr CoffeeRefill.app` 定位附加属性，按 [Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html) 处理构建产物后再验证。

## 4. Mac App Store 版

现有实现通过管理员授权执行 `pmset -a disablesleep`，且没有启用 App Sandbox。[审核规则 2.4.5(i)、(v)](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) 要求沙盒并禁止请求 root 权限。更换签名或安装包无法解决这两项。

若愿意提供只防空闲睡眠的商店版，可以用 Apple 的 [公开电源断言](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep) 做沙盒原型。该断言不保证合盖后继续运行。原型通过实机验证后，再在 App Store Connect 建立记录，准备截图、简介、支持链接、隐私政策及数据收集说明，在 Xcode Organizer 上传归档，按需通过 TestFlight 测试后提交审核。参见 [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) 与 [应用隐私信息](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)。
