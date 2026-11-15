# CoffeeRefill 发布清单

当前候选版本：`1.1`（构建 `2`）。先验收 GitHub 版；Mac App Store 版需要独立实现。

## 1. 本地验收

- [ ] 停掉旧版与其他修改全局禁睡的工具。使用 Apple Silicon MacBook，记录硬件、系统版本和供电方式。发布前覆盖最低承诺版本 macOS 14 和当前正式版。
- [ ] 检查初始状态；取消管理员授权应不修改设置。重新授权后开启、关闭、再次开启，检查图标和读回状态；确认有效会话不会重复弹授权框。
- [ ] 接电、用电池各测一次合盖熄屏、闭盖任务持续运行、开盖亮屏。接外屏另测一次。用持续写时间戳的任务检查闭盖期间是否停顿，仅看开盖亮屏无法证明任务持续运行。
- [ ] 验证「关闭并退出」后恢复正常睡眠。开启后另测强制退出、注销或重启；确认是否恢复，必要时用 `sudo /usr/bin/pmset -a disablesleep 0` 手动恢复。全局设置的异常恢复无法保证。
- [ ] 用另一台 Mac 或干净环境，从 GitHub 下载最终签名包，验证 Gatekeeper、安装、打开及退出。所有通过后再公开正式版。

可只读检查电源状态：

```bash
/usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | grep '"SleepDisabled"'
```

`verify-lid.sh` 是早期 `caffeinate` 方案的探针，不能替代以上验收。

## 2. GitHub 版：保留合盖功能

1. 定下 GitHub 仓库名称、源码是否公开、许可证和最终 Bundle ID；当前为 `local.raccoon.SleepSwitch`。若想让他人复用源码，选择许可证并添加 `LICENSE`。发布源码前确认有权分发代码及图标。准备一张菜单栏截图和本版更新说明。
2. 把源文件和文档纳入 Git。`Build/`、`dist/`、Xcode 用户设置和签名密钥留在本机。参见 [导入现有项目](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github) 和 [选择许可证](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。
3. 加入 [Apple Developer Program](https://developer.apple.com/help/account/membership/program-enrollment/)，取得 [Developer ID Application 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。用 Xcode Release archive 导出带 Hardened Runtime 的签名版，向 Apple 提交公证。若以 ZIP 提交公证，收到 `Accepted` 后用 `xcrun stapler staple CoffeeRefill.app` 把票据附到 `.app`，再用 `ditto -c -k --keepParent` 重新打包。详见 [Apple 公证指南](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
4. 对最终 `.app` 运行 `codesign --verify --deep --strict CoffeeRefill.app`、`xcrun stapler validate CoffeeRefill.app` 和 `syspolicy_check distribution CoffeeRefill.app`。对最终 ZIP 生成 `shasum -a 256` 校验值；验收后创建 `v1.1` 标签和 [GitHub Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。上传带 `.app` 的 ZIP 和 SHA-256 文件，注明 Apple Silicon、最低系统、管理员授权原因、全局禁睡影响及恢复命令。GitHub 自动生成的 Source code ZIP 只含源码。

本地 `dist/` 的 `.xcarchive` 留给开发者，用于保存构建及调试符号；`-rc-` ZIP 仅供试用。面向用户发签名且公证后的 `.app` ZIP 就够，无需额外制作 `.dmg` 或 `.pkg`。

正式签名前可先在非同步目录归档。若签名校验提示 `resource fork, Finder information, or similar detritus not allowed`，用 `xattr -lr CoffeeRefill.app` 定位附加属性，按 [Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html) 处理构建产物后再验证。

## 3. Mac App Store 版：先确定功能

现有实现通过管理员授权执行 `pmset -a disablesleep`，且没有启用 App Sandbox。[审核规则 2.4.5(i)、(v)](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) 要求沙盒并禁止请求 root 权限。更换签名或安装包无法解决这两项。

若愿意提供只防空闲睡眠的商店版，可以用 Apple 的 [公开电源断言](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep) 做沙盒原型。该断言不保证合盖后继续运行。原型通过实机验证后，再在 App Store Connect 建立记录，准备截图、简介、支持链接、隐私政策及数据收集说明，在 Xcode Organizer 上传归档，按需通过 TestFlight 测试后提交审核。参见 [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) 与 [应用隐私信息](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)。
