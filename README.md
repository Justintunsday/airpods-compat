# airpods-compat

研究新版 AirPods 在旧版 iOS 上的兼容性，提供保守的运行时兼容层、
只读诊断 App 与 CI。编译成功不代表设备功能或固件更新已经验证。

- 设备：iPhone 16（`iPhone17,3`），iOS 18.0 – 27.x
- 源版本：iOS 27.0（24A437） · 主目标：iOS 26.6.2（23G90）
- 越狱：rootless（Dopamine / ElleKit / roothide）与 rootful 均可

## 当前保守策略

- **首次安装默认只补缺失显示名**：保留系统返回的非空名称；总开关关闭时不安装名称 hook。
- **UARP 注册默认关闭**：需在 App 手动开启。已有明确写入的有效开关值会保留，
  升级后请检查；缺失值与错误类型不会开启实验能力。
- **设置页借用暂停**：不再安装 `allFeatureContents` 的 Swift 私有函数 hook。
  旧 `BorrowProfile` 配置保留但不生效；需先验证 Swift 调用约定、返回值所有权和真机稳定性。
- **自检只读**：真机不创建动态配件类、不修改系统配件管理器；注册测试仅在模拟器桩类中运行。
- **iOS 27+ 跳过兼容 hook 与注册**；SpringBoard 已移出注入范围。
- **异常即停止**：配置校验失败、私有方法 ABI 不符、基类不可用时跳过；注册失败保留
  进程独立的守护标记，不在后续启动时自动重试。

详细范围、恢复方法与未验证项见 [docs/STABILITY.md](docs/STABILITY.md)。

## 注册范围与边界

- **手动开启注册后默认只尝试缺失的新代型号**（`tier=core`，19 个：AirPods 4/5、Pro 3、Max 2 及对应盒子），
  Beats/老型号需在 App 里切换到「全部型号」
- **只使用抽象基类**：`UARPSupportedAccessoryAirPodsBud/Case/CaseUSB` 或
  `UARPSupportedAccessoryBeatsBluetooth`；不退回其他具体型号，不继承其能力
- **进程分工**：UARP 注册只在 `bluetoothd / uarpd / bluetoothuserd / bluetoothaudiod` 内执行；
  设置和配对服务仅补缺失名称
- **崩溃守护**：每个配件守护进程在注册前独立创建标记，完成后清除；若标记残留，
  该进程后续启动持续跳过 UARP 注册。排查原因后，需在越狱环境中手动删除
  `/Library/Application Support/AirPodsCompat/.registration-in-progress.<进程名>`
  （rootless 安装位于 `/var/jb/Library/Application Support/AirPodsCompat/`）才能重新尝试。
- App 可切换：总开关 / UARP 注册开关 / 注册范围；设置页借用显示为暂停。
  写入系统偏好文件需要相应权限；保存失败时界面显示错误并保留原值。

## 全型号支持

型号表由 `tools/extract_airpods_models.py` 从 iOS 27 的 CoreUARP 反汇编自动提取
（`models/airpods.json` → tweak 的 plist + App 内 `Models.json`），共 **33 个配件类**：

- AirPods 1/2/3/4/4-ANC/5（含无线充电版）、AirPods Pro 1/2/3、AirPods Max 1/2
- 各代充电盒（USB / MagSafe / 无线变体）
- 同族的 Beats 蓝牙配件
- 备选型号关系（A3532↔A3531、A3440↔A3439、A3064↔A3063、A3048↔A3047 …）

手动启用注册后，只尝试本机缺失、配置合法且抽象基类可用的型号。
33 个类是数据覆盖范围，不代表 33 个型号的实际功能均已验证。

## 兼容性

| iOS | 代表性设备 | 状态 |
|---|---|---|
| 15.6.x | iPhone 13 (iPhone14,5) | 构建支持（无 cryptex，走整包回退分析） |
| 16.6.x | iPhone 13 | 构建支持 |
| 17.7 | iPhone 14 Pro (iPhone15,2) | 构建支持 |
| 18.6.2 | iPhone 16 | 构建支持 |
| 26.6.2 | iPhone 16 | 主目标 |
| 27.0 | iPhone 16 | 源版本（原生支持，自动跳过注册） |

## 产物（GitHub Actions artifacts）

| artifact | 内容 |
|---|---|
| `airpodscompat-deb` | `AirPodsCompat-rootless-iphoneos-arm64.deb`（装 `/var/jb`）、`AirPodsCompat-rootful-iphoneos-arm.deb`（装 `/`）、`INSTALL.txt` |
| `airpodscompat-app` | `AirPodsCompat-unsigned.ipa`（未签名，可重签/TrollStore） |
| `dsc-analysis-<版本>` | 各版本 DSC 分析数据与抽取出的 CoreUARP / CoreBluetooth / HeadphoneManager dylib |

**怎么选包**：`iphoneos-arm64` = rootless，`iphoneos-arm` = rootful；
设备上可用 `dpkg-deb -f <deb> Architecture` 复核。

## 安装

- **越狱设备**：Sileo / Zebra 安装匹配架构的 deb → 重启用户空间
  （或 `killall bluetoothd SpringBoard`）
- **未越狱设备**：AltStore / Sideloadly 安装 ipa → 「诊断 → 运行自检」

## 仓库结构

```
.github/workflows/
  dsc-analysis.yml   # 6 个 iOS 版本的 DSC 分析矩阵（15.6.1/16.6.1/17.7/18.6.2/26.6.2/27.0）
  build-tweak.yml    # 构建 rootless + rootful 两个 deb
  build-app.yml      # XcodeGen + xcodebuild 出未签名 ipa
  test-app.yml       # iOS 模拟器单元测试
analysis/run.sh      # DSC 分析脚本（远程抽 DSC + 定向查询 + dylib 抽取）
tools/               # 分析脚本：extract_airpods_models（CoreUARP 型号表）、
                     # stub_map（stub/GOT→符号）、disass_context（调用点反汇编）等
models/airpods.json  # 型号表源数据
tweak/               # Theos 包（AirPodsCompat.dylib + 型号表 + 注入 filter）
app/                 # SwiftUI 控制 App + 非越狱自检 + 单元测试
docs/ANALYSIS.md     # 分析报告（型号映射、hook 目标、风险）
```

## 测试

**1. 模拟器单元测试（CI）**：`Test App` workflow 在 iOS Simulator 上运行
`app/Tests/AirPodsCompatTests.swift`，测试前注入 stub 的 UARP 类，
强制走完整注册路径，断言：

- 型号表完整（≥30 个型号、产品 ID 唯一性）
- 每个缺失型号都能注册成功、`setOfAccessories` 数量确实增长
- 各配件 `identifier` 互不相同（防回归：曾因标识相同被 NSSet 合并成 1 个）

**2. 非越狱自检（真机）**：App →「诊断 → 运行自检」只读输出型号表、
系统原生类和 `HeadphoneManager` 类存在性，可复制报告；不尝试实际注册。

**3. 设备探测（真机）**：App →「诊断 → 设备探测」列出：
- 音频路由（AVAudioSession）中的已连接设备（AirPods 会显示名称/端口）
- 附近 BLE 广播中解析出的 Apple 近场配对型号 ID（0x2036/0x2030/0x2037/0x2032
  会高亮为 AirPods 5）
- 私有 `BluetoothManager` 的已连接设备列表（尽力而为，失败不影响其他区块）
  状态区分别标明连接、配对和附近广播；附近广播不代表当前已连接。
可一键复制探测报告。
扫描 20 秒后自动停止，离开页面也会停止；缓存最多 128 个设备并淘汰过期广播。

**安全策略测试**：模拟器回归覆盖默认关闭、错误类型、重复 PID/型号、非法基类、
截断广播、私有方法的对象/标量返回值与异常。

**3. 构建校验**：两个 deb 的 `Architecture` 与安装路径（`var/jb` vs `Library`）均在 CI 生成。

## 分析流程

1. `analysis/run.sh <版本> [build] [设备]` 远程抽取 DSC（iOS 15 自动回退为整包下载 + 本地抽取）
2. `ipsw dyld` 定向查询 + 抽取目标 dylib（不做全量 dump，避免 30 分钟级卡顿）
3. `tools/extract_airpods_models.py` 反汇编 CoreUARP，输出型号表（tier/基类/备选型号）

## 已知差异（iOS 26.6.2 相对 27.0）

- **显示名**：`AirPods 5`、`AirPods 5 (Wireless Charging)`（27.0 位于 CoreBluetooth）
- **UARP 配件类**：A3440/A3441/A3529/A3529USB/A3530USB/A3532/A3533
  （A3439、A3531 由备选型号覆盖）
- **Swift 功能链（v0.4 历史借用方案，当前暂停）**：27.0 的 `B868FeatureContent` 在 26.6.2 不存在。
  以下描述为历史方案；当前代码不安装此 hook，旧配置不生效。
  tweak 在唯一工厂 `HeadphoneDevice.allFeatureContents(productID:device:)` 入口把
  4 个 AirPods 5 PID（0x2036/0x2030/0x2037/0x2032）替换为 AirPods 4 (ANC) 的
  0x201b，复用系统真实的 `B768FeatureContent` 与其见证表（不伪造 witness table、
  tweak 内不含 B768 实现代码）；注入范围含 `HeadphoneProxService` 与 Preferences；
  iOS 27+ 检测到 `B868FeatureContent` 原生支持时自动跳过。
  调用链证据见 `docs/ANALYSIS.md` §11.12–§11.14。
  **借用目标可选**：pref `BorrowProfile` = `airpods4anc`（默认，B768/0x201b）/
  `airpodspro2`（B698/0x2014）/ `airpodspro3`（B788/0x2027）/ `off`
  （控制 App 可选；类↔型号映射见 §11.16）。这是借用现有 UI，
  **不等于移植 iOS 27 的 B868 专属特性或验证了实际设备功能**。
  **适用范围 iOS 26+**：FeatureContent 链从 26 才有；15.6.1–18.6.2 上
  `HeadphoneManager` 不存在或没有该链，hook 安全跳过、保持 v0.3 行为
  （跨版本证据见 §11.15；旧版 ANC 行的 PID 门控清单见 §11.16）。
- **型号 ID 表**：A3439…A3533（A3531 通过 A3532 的备选型号覆盖）

参考：Apple《Identify your AirPods》 <https://support.apple.com/en-us/109525>
