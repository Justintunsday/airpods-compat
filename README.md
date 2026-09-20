# airpods-compat

把 **AirPods 5（A3531 / A3532 / A3533，含无线充电版 A3439 / A3440 / A3441，充电盒 A3529 / A3530）**
的支持移植到更低版本 iOS（目标：iPhone 16 = iPhone17,3 上的 iOS 26.6.2）。

## 目标机型

| 项目 | 值 |
|---|---|
| 设 备 | iPhone17,3（iPhone 16） |
| 源固件 | iOS 27.0（24A437，iPhone17,3_27.0_24A437_Restore.ipsw） |
| 目标固件 | iOS 26.6.2（23G90） |
| 越狱 | rootless（Dopamine / ElleKit），同时兼容 roothide 布局 |
| 交付 | 1) rootless 越狱包（tweak）2) 控制 App（GitHub Actions 编译） |

## 已知差异（来自 DSC 字符串/类名 diff）

iOS 26.6.2 相对 iOS 27.0 缺少的 AirPods 5 相关项：

- **显示名**：`AirPods 5`、`AirPods 5 (Wireless Charging)`
- **UARP 配件类**：`UARPSupportedAccessoryA3439 / A3440 / A3441 / A3529 / A3529USB / A3530USB / A3532 / A3533`
- **Swift 功能类**：`B868FeatureProviding`（B768 为 AirPods 4，B868 推测为 AirPods 5）
- **型号 ID 表**：A3439 / A3440 / A3441 / A3529 / A3530 / A3531 / A3532 / A3533

参考：Apple《Identify your AirPods》 <https://support.apple.com/en-us/109525>

完整分析（型号映射、差异清单、方案与风险）见 **[docs/ANALYSIS.md](docs/ANALYSIS.md)**。

## 仓库结构

```
.github/workflows/
  dsc-analysis.yml   # macOS runner 远程抽 DSC + ipsw dyld 查询（artifact）
  build-tweak.yml    # Theos 编译 rootless .deb（artifact）
  build-app.yml      # XcodeGen + xcodebuild 出未签名 .ipa（artifact）
analysis/
  run.sh             # DSC 分析脚本（CI 与本地 macOS 通用）
tweak/               # rootless Theos 包（AirPodsCompat）
  Tweak.xm           # 数据驱动；已定位 CoreUARP / CoreBluetooth / HeadphoneManager
  layout/…           # 型号表 AirPodsCompatModels.plist
app/                 # SwiftUI 控制 App（XcodeGen 工程）
docs/ANALYSIS.md     # 分析报告（型号映射、差异清单、hook 目标、风险）
```

## 构建

Actions 里手动触发 **Build Tweak** / **Build App**，或 push 到 `tweak/**`、`app/**` 自动构建，
产物在对应 run 的 Artifacts：`airpodscompat-deb`、`airpodscompat-app`。

- 安装 deb：`dpkg -i` 到 rootless 越狱环境（Dopamine / roothide）
- 安装 ipa：TrollStore / AltStore 重签后安装

## 分析流程

1. Actions → **DSC Analysis** → Run workflow（默认分析 27.0 与 26.6.2）
2. 运行结束后下载 `dsc-analysis` artifact
3. 从中提取 `objc_classes.txt` / `swift.txt` / `sym_*.txt`，确定 hook 目标

## 本地（macOS）复现

```bash
brew install blacktop/tap/ipsw
bash analysis/run.sh 27.0
bash analysis/run.sh 26.6.2
```
