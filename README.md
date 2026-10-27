# Screenshot

一款原生 SwiftUI 编写的 macOS 菜单栏截图工具，主打**滚动截图**。

## 特性

- **截图**：点击窗口或拖出区域，选区在截图前可以移动、缩放；支持多显示器
- **原地标注**：选好区域后，遮罩本身就变成 PaperKit 标注编辑器，可以画笔、形状、文字、模糊，然后复制、保存、分享或完成，不用离开当前屏幕
- **滚动截图**：照常滚动窗口或区域，结果就像窗口放在一块无限长的屏幕上——侧边栏、正文、检查器等每个滚动区域都完整展开、并排摆放，工具栏和状态栏保留在四周。支持纵向和横向、多个区域，滚轮、触控板、拖滚动条、键盘滚动都能识别
- **预览与编辑**：完成后角落出现浮动缩略图，点开即可在标注窗口里继续编辑
- **提取文字**：在标注编辑器里点 *Extract Text*（⇧⌘C），用 Vision 识别截图或滚动长图中的文字并复制到剪贴板，聊天记录、报错弹窗、文档不用手抄
- **拼图**：多张普通截图堆在角落预览里，点 *Combine* 拖动拼接（边缘自动吸附），导出为一张图
- 截图只保存在内存中：没有历史记录、云同步或录屏

## 系统要求

| | 版本 |
|---|---|
| 运行 | macOS 26+ |
| 开发 | Xcode 27+ |

首次截图时需要在 系统设置 → 隐私与安全性 → 屏幕录制 中允许 Screenshot。

## 构建

```bash
git clone https://github.com/zhang-hongshen/Screenshot.git
cd Screenshot
open Screenshot.xcodeproj
```

命令行编译和测试：

```bash
xcodebuild -project Screenshot.xcodeproj -scheme Screenshot -destination 'platform=macOS' build
xcodebuild test -project Screenshot.xcodeproj -scheme Screenshot -destination 'platform=macOS'
```

唯一的第三方依赖是 [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（全局快捷键）。架构和开发约定见 [AGENTS.md](AGENTS.md)。

### 名称与版本号

在 Xcode 中选中 target **Screenshot** → General 修改：

- **Version**：版本号，必须和发布用的 tag 一致（例如 tag `0.1.0`，不带 `v`），发布流水线会检查这一点
- **Build**：构建号，发布时由 CI 自动设置为 workflow 的运行编号

Bundle ID 固定为 `com.zhanghongshen.Screenshot`。

## 发布

推送版本号格式的带注释 tag（如 `0.1.0`）会触发 `.github/workflows/release.yml`，依次完成：Archive macOS 版本 → Developer ID 签名 → 打包 DMG → 对 DMG 签名、公证（notarytool）并 staple → 创建 GitHub Release 并上传 DMG 及其 SHA-256 校验值。Release 说明取自 tag 的注释正文。

```bash
git tag -a 0.1.0 -m "0.1.0" -m "1. 第一个版本"
git push origin 0.1.0
```

签名需要在仓库 Secrets 中配置：

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application 证书（.p12）的 base64 |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 的密码 |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_ID` | 用于公证的 Apple ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | 该 Apple ID 的 App 专用密码 |

没有配置证书时会跳过签名和公证，发布一个 ad-hoc 签名的 DMG。首次打开未签名版本：右键点击 App → 打开，或执行 `xattr -dr com.apple.quarantine /Applications/Screenshot.app`。

## 许可证

[MIT](LICENSE)
