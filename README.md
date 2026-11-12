# DSH Go · iOS / TrollStore 移植工程

把 [lxsfful/dsh-go](https://github.com/lxsfful/dsh-go)（上游 [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)）的 Flutter 工程编译成 **TrollStore 可直接安装的 .ipa**。

原仓库是 Flutter 项目：UI、`packages/dsh_client`、`packages/dsh_remote` 和绝大多数 pub 依赖本身就是跨平台的，Android 特有部分集中在 `app/android/` 的 200+ 个 Kotlin 原生插件里。所以这里做的是 **iOS 平台层补齐 + 安卓能力降级 + 免签名打包**，不是重写 App。

---

## 一、先说结论：能搬的和搬不动的

| 功能 | Android | iOS (TrollStore) | 原因 |
| --- | --- | --- | --- |
| 远程 SSH 连接电脑 / 服务器上的 DSH | ✅ | ✅ | `dartssh2` 纯 Dart |
| DSHarness Remote（WebRTC / HTTP 直连） | ✅ | ✅ | `flutter_webrtc` 有 iOS 实现 |
| 聊天界面、Markdown / 公式、终端页、工具审批 | ✅ | ✅ | 纯 Flutter |
| 网页模式（DSH Web / WKWebView） | ✅ | ✅ | `webview_flutter` 的 iOS 实现 |
| 图片附件、文件选择、语音输入、分享 / 导出对话 | ✅ | ✅ | iOS 原生权限已在 Info.plist 配好 |
| 论坛、社区、端到端加密分享链接、主题设置 | ✅ | ✅ | 纯网络 / 纯 Dart |
| 桌面图标切换、快捷方式、磁贴 | ✅ | ❌ | iOS 无对应 API |
| 悬浮桌宠、通知常驻、灵动岛式卡片 | ✅ | ❌ | iOS 不允许跨 App 悬浮窗 |
| 无障碍读屏 / 自动点按「手机操控」 | ✅ | ❌ | iOS 无 AccessibilityService |
| Shizuku / 无线 ADB / Root 后台通道 | ✅ | ❌ | Android 专属 |
| **在手机本机跑 Ubuntu + Node.js + DSH 引擎** | ✅ | ❌ | 见下 |
| APK 自更新 | ✅ | ❌ | 改为手动安装新 .ipa |

**为什么本机引擎搬不过去**：Android 版靠 `proot` 在 App 私有目录里解包一份 Ubuntu rootfs，再执行里面的 Linux ELF（Node.js / DSH）。TrollStore 绕过的是 AMFI / CoreTrust 的**代码签名校验**——让任意签名、任意 entitlements 的 .ipa 被系统永久接受；它不是完整越狱，不提供 platformization，App 仍在沙盒里，没有挂载、`ptrace`、进程拦截这类能力，也执行不了一整份未签名的 Linux ELF（部分设备上 TrollStore 的「条件式 JIT」也不等于能跑 Ubuntu rootfs + Node）。这不是换个签名就能解决的问题。

所以 iOS 版是 **「远程连接版」**：连你电脑 / 服务器上跑着的 DSH，手机当作完整的移动端客户端用。这也是原项目 README 里本来就支持的第二条路线，功能损失最小。

**为什么这里给的是工程而不是现成的 .ipa**：编译 iOS App 需要 macOS + Xcode，当前工作机是 Windows，装不了 Xcode，也签不出 Mach-O。所以交付物是完整的 iOS Runner 工程 + 一条 GitHub Actions（macOS runner）自动出包流水线：一次点击就产出可装进 TrollStore 的 `.ipa`。有 Mac 的话也可以直接在本地跑两个脚本。

对 Android 原生 MethodChannel，本工程会自动扫描 Kotlin / Dart 源码里的通道名，生成一份 Swift 兜底实现（`IosChannelStubs.swift`），返回「不支持 / 空值」而不是抛 `MissingPluginException` 让 App 崩溃；Dart 层原有的 `MissingPluginException` 降级逻辑继续生效。

---

## 一·五、直接下载（已构建好的 .ipa）

不想自己跑流水线，可以直接下载已构建并通过 TrollStore 验证的 .ipa：

- **下载地址**：[`DSH-Go-TrollStore.ipa`](https://github.com/fushanhuang/dsh-go-ios/releases/download/v1.0/DSH-Go-TrollStore.ipa)（Release `v1.0`，约 27.3 MB）
- **SHA-256**：`ac7c24cef78514fc88f678572b70edcb1bd26f6677415bfd5745a05a1dce3083`
- **安装**：把 .ipa 存到 iPhone 的「文件」App → 分享给 **TrollStore** → 安装。无需开发者账号、无需 7 天重签。

> 该包是免签名 / ad-hoc 签名产物，由 TrollStore 用 CoreTrust 通道重签并永久注册。本机引擎（Ubuntu+Node）在 iOS 上不可用，请走「远程连接」。

---

## 二、三步出 .ipa

### 1. 把本目录上传成一个 GitHub 仓库

在 https://github.com/new 建一个**公开**仓库（例如 `dsh-go-ios`），把本目录所有文件拖进网页上传框（包含 `.github/`、`scripts/`、`ios-overlay/`，目录结构要保留）。

公开仓库的 macOS runner 免费；私有仓库的 macOS 分钟数要计费。

### 2. 跑 Actions

仓库 → **Actions** → **Build TrollStore IPA** → **Run workflow**，可填：

| 输入 | 默认值 | 说明 |
| --- | --- | --- |
| `upstream_repo` | `lxsfful/dsh-go` | 想跟上游最新代码就填 `ccch1mneyyy/dsh-Go` |
| `upstream_ref` | `main` | 分支 / tag / commit |
| `bundle_id` | `io.github.lxsfful.dshgo.troll` | 换成自己的，避免和别的 App 撞 ID |
| `deployment_target` | `15.0` | 按设备的 TrollStore 支持范围调整 |
| `make_release` | `false` | 勾 true 会额外建一个 Release，方便手机直接下载 |

流水线在 `macos-15` 上：sparse clone 上游 → 生成 `ios/` Runner 工程 → 覆盖配置 → `pod install` → `flutter build ios --release --no-codesign` → ad-hoc 重签 → 打成 `Payload/Runner.app` 结构的 `.ipa`。

### 3. 安装

下载 artifact（或 Release 资产）里的 `.ipa` → 存到 iPhone 的「文件」App → 分享给 **TrollStore** → 安装。

TrollStore 会用自己的 CoreTrust 通道重签并永久注册，不需要开发者账号、不需要 7 天重签、不需要越狱环境常驻。

---

## 三、有 Mac 的话，本地构建

```bash
git clone https://github.com/<你>/dsh-go-ios.git
cd dsh-go-ios

# 需要 Flutter 3.47.7（Dart ^3.13.5）、Xcode 16+、CocoaPods
brew install cocoapods

bash scripts/prepare.sh
bash scripts/build_ipa.sh
ls -lh out/
```

脚本都支持环境变量覆盖，等价性见 `scripts/lib.sh`：

```bash
UPSTREAM_REPO=ccch1mneyyy/dsh-Go \
BUNDLE_ID=com.example.dshgo.troll \
IOS_DEPLOYMENT_TARGET=15.0 \
bash scripts/prepare.sh
```

`prepare.sh` 生成的上游源码在 `upstream/`，iOS 工程在 `upstream/app/ios/`，可以再用 Xcode 打开 `Runner.xcworkspace` 手动改图标、签名或加原生能力。

---

## 四、目录说明

```
.github/workflows/build-ipa.yml   macOS CI：一键出 .ipa
scripts/lib.sh                    公共变量 / 日志 / 工具函数
scripts/prepare.sh                拉上游 → flutter create → 套 iOS 配置
scripts/patch_pubspec.py          pubspec 的 iOS 适配（WKWebView 实现等）
scripts/gen_channel_stubs.py      扫描 Kotlin/Dart 通道名 → 生成 Swift 兜底
scripts/build_ipa.sh              编译 → ad-hoc 签名 → 打 .ipa
ios-overlay/Info.plist           权限、ATS、本地网络、显示名
ios-overlay/AppDelegate.swift     注册 Flutter 插件 + 通道兜底
ios-overlay/Runner.entitlements   TrollStore 用的 entitlements（保持精简）
ios-overlay/Podfile               iOS 15 + 关 bitcode + 关签名
```

---

## 五、已知限制 / 排错

- **本机引擎入口在 iOS 上仍会出现在界面里**，但点击后引擎状态恒为「未安装 / 不支持」，请直接用「远程连接」。要彻底隐藏，在 `upstream/app/lib/` 里按 `Platform.isIOS` 屏蔽对应入口即可。
- **WKWebView 访问 `http://` 局域网地址**：Info.plist 已开 ATS 例外与 `NSLocalNetworkUsageDescription`，首次访问会弹一次本地网络授权。
- **构建报 `No such module` / pod 冲突**：`cd upstream/app/ios && pod deintegrate && pod install --repo-update`。
- **Flutter 版本不匹配**：工作流用 `3.47.7`，与上游 `tooling/setup-toolchain.sh` 一致；上游升级后同步改 workflow 里的 `flutter-version`。
- **iOS 18+ 启动即闪退**：通常是 entitlements 里加了私有权限。本工程默认只保留 `get-task-allow`，别额外塞 `com.apple.private.*`；需要调试能力时自行评估。
- **TrollStore 版本 / 系统版本**：官方文档给出的支持范围是 iOS 14.0 beta2 – 16.6.1、16.7 RC (20H18)、17.0（不同版本/芯片条件不同），新系统是否有新的 CoreTrust 通道以官方仓库为准；`deployment_target` 不要设得比设备系统还新。
- **装好后重启就打不开**：TrollStore 需要持久化助手（persistence helper）在图标缓存重载后重新注册为系统 App，按 TrollStore 的引导装好 helper 再试。
- **想开条件式 JIT**：`Runner.entitlements` 里已保留 `get-task-allow = true`，这是 TrollStore 2.0.12+ 显示 JIT 选项的前提；本项目用不到它，遇到调试需求再动。
- **构建报 `NWPath has no member 'isUltraConstrained'`**：`connectivity_plus 7.3.2` 引用了 iOS 26.0 才引入的 `NWPath.isUltraConstrained`（`#available(iOS 26.0, *)` 保护），而 GitHub 的 macOS runner 只提供到 iOS 18.x SDK，Swift 即便有可用性保护也要求 SDK 里存在该符号，于是报「no member」。`prepare.sh` / `build_ipa.sh` 已自动把该引用中和成 `false`（`.satellite` 连接类型本 App 用不到）；本地构建若用 iOS 26+ SDK 则无需此补丁。

---

## 六、授权

上游 DSH Go 为 **AGPL-3.0**（`sdk/`、`examples/` 为 MIT），DSH Go 名称与标识及吉祥物不在开源授权范围内（`ASSETS.md`）。本仓库仅提供构建脚本与平台适配层，沿用上游授权；再发布请遵守上游的署名与再发布要求。本工程与 DeepSeek 官方无关。
