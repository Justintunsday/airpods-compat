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

## 兼容性

| iOS | 代表性设备 | 状态 | 说明 |
|---|---|---|---|
| 15.6.x | iPhone 13 (iPhone14,5) | 构建支持 | 老系统无 AirPods 5 类；tweak 运行时自动挑选同族具体类做基类 |
| 16.6.x | iPhone 13 | 构建支持 | 同上 |
| 17.7 | iPhone 14 Pro (iPhone15,2) | 构建支持 | 同上 |
| 18.6.2 | iPhone 16 (iPhone17,3) | 构建支持 | iPhone 16 出厂最低 18.0 |
| 26.6.2 | iPhone 16 | 主目标 | 已完成的验证目标 |
| 27.0 | iPhone 16 | 源版本 | 原生支持，tweak 自动跳过 |
| jailbreak | — | rootless + rootful | CI 同时产出 `iphoneos-arm64`(rootless) 与 `iphoneos-arm`(rootful) |

> 跨版本可移植性由「运行时能力探测」保证：tweak 不硬编码类名，优先使用现有具体类；
> 找不到时自动从 `UARPSupportedAccessoryAirPodsBud/Case/CaseUSB` 的具体子类里挑一个。
> `HeadphoneManager` 仅新系统有，老系统走 UARP + CoreBluetooth 名称链路。

## 安全模型（v0.3）

- 默认只注册**本机缺失的新代型号**（`tier=core`，19 个：AirPods 4/5、Pro 3、Max 2 及对应盒子）
- **抽象基类优先**（`…AirPodsBud/Case/CaseUSB`），具体型号类只作 fallback，避免继承别的型号能力
- UARP 注册只在 `bluetoothd / uarpd / bluetoothuserd / bluetoothaudiod` 内执行，UI 进程只做名称显示
- **崩溃守护**：注册前写标记，完成后清除；若标记残留（上次启动异常），本次自动跳过注册
- App 可切换：总开关 / UARP 注册 / 仅新代 vs 全部型号（含 Beats、老型号）

## 全型号支持

型号表由 `tools/extract_airpods_models.py` 从 iOS 27 CoreUARP 自动提取
（`models/airpods.json` → tweak 的 plist + App 内 `Models.json`），共 **33 个配件类**：

- AirPods 1/2/3/4/4-ANC/5（含无线充电版）、AirPods Pro 1/2/3、AirPods Max 1/2
- 各代充电盒（含 USB / MagSafe / 无线充电变体）
- 同族的 Beats 蓝牙配件（自动识别到的 0x2xxx/0x1xxx 产品 ID 一并注册）

tweak 在运行时**只注册本机缺失的型号**：iOS 27 原生已有的会自动跳过，
老系统则补齐各自的缺口（含备选型号，如 A3532↔A3531）。

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

## 非越狱自检（建议先做）

`airpodscompat-app` 的 **诊断 → 运行自检（无需越狱）** 可直接在未越狱设备上验证：

1. 用 AltStore / Sideloadly / TrollStore 安装 `AirPodsCompat-unsigned.ipa`（需重签）
2. 打开 App → 诊断 → 运行自检
3. 报告包含：
   - 系统原生是否认识 A3532/A3533/A3440/A3441/A3529/A3529USB/A3530USB（以及 `+productID` 实际值）
   - `HeadphoneManager` 的 `B868FeatureContent` 是否存在
   - **动态注册干跑**：与越狱 tweak 完全相同的注册逻辑在本进程内执行并校验 PASS/FAIL
4. 复制报告即可判断下一步

> 无越狱只能验证「系统是否认识 + 注册逻辑是否可行」；让蓝牙守护进程真正生效仍需越狱 tweak。

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
