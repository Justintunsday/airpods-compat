# AirPods 5 → iOS 26.6.2 移植分析报告

> 生成日期：2026-09-21 · 设备：iPhone17,3 (iPhone 16) · 源：iOS 27.0 (24A437) · 目标：iOS 26.6.2 (23G90)

## 1. 结论摘要

- **AirPods 5 整代（2026）在 iOS 26.6.2 上完全缺失支持**，iOS 27.0 首次完整引入。
- 目标机与源机同为 iPhone 16，蓝牙芯片一致 → 属**纯用户态差异**（DSC + 系统资源），不需要内核/驱动移植。
- 已定位的缺口包括 **AirPods 5 UARP 配件类、HeadphoneManager 的 Swift 功能类、显示名和型号 ID 表项**（详见 §5）；这些缺口不等于已证明的完整移植清单。
- 路径：rootless 越狱包（Theos）+ 数据驱动型号表；系统卷受 SSV 保护，只能运行时注入，不能替换 DSC。

## 2. 型号映射（Apple KB109525）

| 型号 ID | 官方身份 | 年份 |
|---|---|---|
| A3531 / A3532 / A3533 | AirPods 5（耳机） | 2026 |
| A3439 / A3440 / A3441 | AirPods 5（无线充电版耳机） | 2026 |
| A3529 | AirPods 5 充电盒 | 2026 |
| A3530 | AirPods 5 无线充电盒 | 2026 |
| A3454 | AirPods Max 2 | 2026 |
| A3063 / A3064 / A3065 | AirPods Pro 3 | 2025 |
| A3053 / A3050 / A3054 | AirPods 4 | 2024 |
| A3056 / A3055 / A3057 | AirPods 4 (ANC) | 2024 |

## 3. 分析方法与数据来源

1. `tar` 解包 IPSW → `BuildManifest.plist` 定位组件：
   - `OS` → `043-69462-655.dmg.aea`（根文件系统）
   - `Cryptex1,SystemOS` → `043-70113-704.dmg.aea`（**DSC 所在卷**）
2. AEA 解密：`ipsw fw aea`（WKMS 公钥体系，无需私钥）→ 原始 APFS 镜像
3. 资源/二进制：7-Zip（24.09+）直接读 APFS
   - Windows 限制：APFS 压缩分片（`.77.dyldlinkedit`、`.symbols`）无法解压 → 改用 **GitHub Actions (macOS)** 远程抽 DSC
4. 差异提取：字节级字符串扫描（`A3531` 等）+ 正则类名集合（`UARPSupportedAccessory[A-Za-z0-9_]+`、`[A-Z]\d{3}FeatureProviding`），两版本做集合 diff
5. 证据样本：
   - `dyld_shared_cache_arm64e.50`：`…A3454 ∥ A3532 ∥ A3531…`，邻接 `AirPods Pro 2 (USB-C)`、`Mapped Analytics Event/Payload`
   - `dyld_shared_cache_arm64e.26.dyldreadonly`：类名 `UARPSupportedAccessoryA3532`
   - iOS 27.0：显示名 `AirPods 5`、`AirPods 5 (Wireless Charging)`；`B868FeatureContent` 与 `B868FeatureProviding.swift` 字符串

## 4. 两版本共有/独有概览

| 项目 | iOS 27.0 | iOS 26.6.2 |
|---|---|---|
| `UARPSupportedAccessoryA3454`（AirPods Max 2） | ✅ | ✅（补丁期已加入） |
| `UARPSupportedAccessoryA3063/64/65`（Pro 3） | ✅ | ✅ |
| `B768FeatureProviding`、`AirPods 4` | ✅ | ✅ |
| **AirPods 5 全部型号/类/显示名** | ✅ | ❌ |
| **`B868FeatureContent`（HeadphoneManager）** | ✅ | ❌ |

## 5. 26.6.2 缺失清单（移植目标）

- **UARP 配件类（7）**：`A3440`、`A3441`、`A3529`、`A3529USB`、`A3530USB`、`A3532`、`A3533`
  （注：`A3439`、`A3531` 没有独立类，分别由 A3440、A3532 的备选型号覆盖）
- **Swift 功能类**：`B868FeatureContent`（HeadphoneManager；B768 是 AirPods 4 的同位类）；iOS 27 的 HeadphoneSettingsUI 另有 `B868FeatureProviding.swift` 字符串
- **显示名**：`AirPods 5`、`AirPods 5 (Wireless Charging)`
- **型号 ID 表**：`A3439`、`A3440`、`A3441`、`A3529`、`A3530`、`A3531`、`A3532`、`A3533`

## 6. Hook 目标（已定位，iOS 27.0 DSC）

`ipsw dyld str` 命中（26.6.2 均无）：

| 组件 | 镜像 | 证据（地址/符号） | 用途 |
|---|---|---|---|
| 显示名 | **CoreBluetooth** | `"AirPods 5"` @0x2071740f3；`"AirPods 5 (Wireless Charging)"` @0x2071740fd | 设备名称映射 |
| 型号 ID | **CoreUARP** | `"A3531"` @0x25e9dd0df、`"A3532"`、`"A3439"` | 配件身份表 |
| 配件类 | **CoreUARP** | `UARPSupportedAccessoryA3532`（`_OBJC_CLASS_$_…`、`-[… init]`、ivar `hwID`） | 配件定义 / 固件 |
| 功能能力 | **HeadphoneManager**（Swift） | `B868FeatureContent` @0x202731ee0；`B868FeatureContent.productIDs: UInt32`；`init(id:headphoneDevice:)`；协议 `B868FeatureContentType` | 型号→特性映射 |

对照：AirPods 4 的同位实现为 `B768FeatureContent`/`B768FeatureProviding`（两版本都有）。

### 6.1 数值产品 ID（CoreUARP 反汇编提取）

| 类 | productID | 备选型号 | 继承自 |
|---|---|---|---|
| `UARPSupportedAccessoryA3532` | 0x2036 | A3531 | `…AirPodsBud` |
| `UARPSupportedAccessoryA3533` | 0x2037 | — | `…AirPodsBud` |
| `UARPSupportedAccessoryA3440` | 0x2030 | A3439 | `…AirPodsBud` |
| `UARPSupportedAccessoryA3441` | 0x2032 | — | `…AirPodsBud` |
| `UARPSupportedAccessoryA3529` | 0x2035 | — | `…AirPodsCase` |
| `UARPSupportedAccessoryA3529USB` | 0x13a5 | — | `…AirPodsCaseUSB` |
| `UARPSupportedAccessoryA3530USB` | 0x13a4 | — | `…AirPodsCaseUSB` |

注册 API：`-[UARPSupportedAccessoryManager addSupportedAccessory:]`（`+defaultManager`）。

## 7. 移植方案（基于以上定位）

1. **CoreUARP**：运行时以现有具体类为模板（26.6.2 已含 `A3064`/`A3122`/`A3122USB`）动态创建
   `AirPodsCompat_A35xx` 子类，覆盖 `+productID` / `+appleModelNumber` /
   `+mobileAssetAppleModelNumber` / `+alternativeAppleModelNumbers`，再注册进 manager（已实现于 `tweak/Tweak.xm`）
2. **CoreBluetooth**：hook `-[CBDevice productName]` 与
   `+[CBAccessoryLogging getProductNameFromProductID:]`，按 PID 返回 "AirPods 5" 等名称（已实现）
3. **HeadphoneManager / HeadphoneSettingsUI**（待 v0.4）：iOS 27 抽取的 dylib 中，
   `B868FeatureContent` 位于前者，`B868FeatureProviding.swift` 位于后者。
   iOS 26.6.2 的 `HeadphoneDevice.allFeatureContents(productID:device:)` 已存在，
   但没有 `B868FeatureContent`。需要先反汇编对比两版该工厂函数的调用链，
   并确定 Swift 协议见证表与 ABI，才能接入新的特性对象。
   不能仅创建同名 Objective-C 类，或把 AirPods 5 的 productID 映射到 AirPods 4 的
   `B768FeatureContent`：这两种做法都不能证明返回了正确的 AirPods 5 特性集。
4. 型号表外置：`tweak/layout/Library/Application Support/AirPodsCompat/AirPodsCompatModels.plist`

## 8. 影响面（待 hook 定位后确认）

- 设备识别与命名（配对弹窗、设置页名称/图标/分类）
- UARP 固件更新/个性化（配件定义类缺失时通常直接不提供更新）
- 电量显示、ANC/自适应音频、手势等是否受型号表驱动（待验证）

## 9. 风险与限制

- **SSV**：iOS 15+ 系统卷签名保护 → 不能替换 DSC/系统二进制，必须运行时注入
- **Swift 功能链**不能仅靠同名 Objective-C 类补齐，需确认工厂函数调用点、Swift ABI 和协议见证表
- **bluetoothd 注入**：rootless 注入器需支持系统守护进程；否则改从 UI/框架层入手
- **固件更新链路**（UARP 配件定义）需真机回归验证
- 越狱工具与 iOS 版本匹配性（Dopamine/roothide 的可用范围）

## 10. 进度与下一步

- [x] IPSW 解包、AEA 解密、DSC 定位
- [x] 型号映射 + 缺失清单（字节级 diff）
- [x] GitHub Actions DSC 分析管线（远程抽 DSC + 定向查询 + dylib 抽取）
- [x] hook 目标定位：CoreUARP / CoreBluetooth / HeadphoneManager
- [x] 反汇编提取数值 productID + 注册 API
- [x] tweak v0.2：UARP 配件动态注册 + CoreBluetooth 名称 hook（CI 编译通过）
- [x] 控制 App 未签名 ipa（CI 编译通过）
- [ ] 真机验证：安装 deb → 配对 AirPods 5 → 名称/识别/设置页
- [ ] v0.4：HeadphoneManager `B868FeatureContent` 与 HeadphoneSettingsUI
      `B868FeatureProviding` 特性链（先确认 Swift 工厂函数调用链及 ABI）
- [ ] 真机回归：固件更新、电量、手势、ANC

## 11. v0.4 研究记录（Swift 特性链）

目标：把 iOS 27 的 `B868FeatureContent` 特性链移植到 26.6.2。结论：**暂不实现**，证据如下。

### 11.1 工厂函数结构（两版一致）

`HeadphoneDevice.allFeatureContents(productID:device:)` 固定构造 10 元素数组：

- 元素 0/1：**硬编码** `B698FeatureContent`、`B768FeatureContent`（直接 `init` + 写 existential）
- 元素 2..9：8 个闭包 `AHyXEfU_ … U6`，每个闭包 = 申请对象 + 调自身 failable init + 写 existential
- 27.0 闭包映射：`U_ = B788`、`U0 = B494B`、`U1 = B868`、`U4 = B518`、`U5 = B515d`、`U2/U3/U6 = 占位`
- **匹配逻辑在各自类的 failable init 内部**（init 返回 nil 表示不适用），工厂不做筛选

### 11.2 接受的 productID（反汇编实测）

| 类 | iOS | 接受集合 |
|---|---|---|
| `B868FeatureContent` | 27.0 | `{0x2036, 0x2030, 0x2037, 0x2032}`（AirPods 5 / 无线充电版四个耳机 PID） |
| `B768FeatureContent` | 27.0 | `{0x2019, 0x201b}` |
| `B768FeatureContent` | 26.6.2 | `{0x2019, 0x201b}` |

类内部只存两个字段：`productIDs`（offset 0x10，存的就是该 PID 本身）与 `device`（offset 0x18）。
**特性语义不在字段里，而在类的「类型身份」上**（消费者按类型分派）。

### 11.3 existential / 见证表 ABI（两版相同）

- 容器：5 字（`any FeatureContentType`）：`[0]=对象指针`、`[3]=type metadata`、`[4]=witness table`
- 见证表布局：`[0]=conformance descriptor(…AAMc)`、`[1]=productIDs.vgTW`、`[2]=device.vgTW`、`[3]=init(cfC).TW`
- 协议只有 3 个需求，26.6.2 与 27.0 完全一致 → **ABI 不是障碍**

### 11.4 阻塞点与下一步

- 动态 ObjC 类**无法**提供 Swift witness table；伪造见证表或复用 B768 的 WP 都等于「把 AirPods 5 当成 AirPods 4」，特性可能错误 → 不做
- 直接 `bl`/`b` 扫描没有找到工厂调用者；这只能排除目标地址上的直接分支，
  **不能排除** Swift 协议见证表、dyld stub 或其他间接调用
- 已将 `HeadphoneConfigs`、`MobileBluetooth`、`BluetoothSettings.bundle` 加入 DSC 抽取列表，
  下一步在它们中定位消费者；确认分派方式后再决定能否用「按 PID 处理」的保守 hook 实现

### 11.5 消费者定位进展（未完成）

对 7 个 dylib（HeadphoneManager、HeadphoneSettingsUI、HeadphoneConfigs、MobileBluetooth、
BluetoothSettings.bundle、CoreBluetooth、CoreUARP）做了两类扫描，**均 0 命中**：

- 直接调用工厂 `allFeatureContents(productID:device:)` 的 `bl`/`b`
- 类型分派入口：`B768FeatureContentCMa` / `B868FeatureContentCMa`（`as?` 会调用的 metadata accessor）

更新：§11.6 在 `HeadphoneSettingsUI` 找到了型号特定的协议见证表，
因此「消费者一定在未抽取二进制中」的推论不成立。仍需定位获取工厂结果并选择 UI provider 的入口。
可继续检查：

- `HearingAidUIServer` / 听力相关框架
- `headphonesd` 等用户态守护进程
- 用 `ipsw dyld xref`（CI/macOS）对工厂地址做全缓存交叉引用
- 同时检查 HeadphoneSettingsUI 自身的 `*FeatureProviding` 表（按型号→Provider 的选择逻辑）是否可安全扩展

在定位并确认分派方式之前，v0.4 保持「未实现」，不做猜测性映射。

### 11.6 HeadphoneSettingsUI 的间接分派证据

对 `artifacts-consumers/sym_26_6_2_HeadphoneSettingsUI.txt` 和
`sym_27_0_HeadphoneSettingsUI.txt` 使用 `tools/compare_feature_conformances.py` 比较：

- 两版的 `B768FeatureContent` 都有 `HeadphoneNameProviding`、
  `SleepDetectionFeatureProviding`、`HeadphoneSettingsUIContentProvider`
  三组协议 conformances（各自有 `Mc` descriptor 与 `WP` witness table）。
- 27.0 的 `B868FeatureContent` 新增同样三组 conformances，以及
  `featureType`、`platformName`、`singularName`、`marketingName` 四个 extension getter；
  26.6.2 没有对应的 B868 符号。
- 因此 `HeadphoneSettingsUI` **确实含有** B868 的 UI 语义实现。
  工厂调用和类型 accessor 的直接分支为 0，并不能证明该框架与特性链无关；
  Swift runtime 可通过协议见证表完成分派。这是符号证据，尚未定位到最终的 UI 入口。

下一步应追踪 `HeadphoneSettingsUIContentProvider` 的泛型包装／调用者及
`HeadphoneDevice.allFeatureContents` 的动态引用，确认 UI 侧如何获得 existential 数组。
仅补 `HeadphoneManager` 类而缺少上述 UI conformances，不足以复现 27.0 的界面行为。

### 11.7 回退路径与协议描述符引用扫描（补充证据）

- `DefaultFeatureContentInternal` 在 26.6.2 与 27.0 **都**符合 `HeadphoneNameProviding` /
  `SleepDetectionFeatureProviding` / `HeadphoneSettingsUIContentProvider`
  → 未知型号存在「通用回退页」，v0.4 的收益主要在品牌/文案与专属行，而非「有没有页面」
- 从一致性描述符 (ADMc) 反解协议描述符并对 5 个 dylib 做 ADRP/ADD 引用扫描：**0 引用**
- 这印证了 §11.6：`as? any …UIContentProvider` 的合法转换走运行时一致性查找，
  不引用类符号，"0 命中"不能排除关系；工厂消费者仍在已抽取集合之外
- 已把 `Preferences.app`、`BluetoothManager`、`HeadphoneProxService`、`HearingAid`、
  `headphonesd`、`HearingAidUIServer` 加入 DSC 抽取候选，下一步在这些二进制里找工厂调用方

### 11.8 扫描工具纠错与已定位的调用链（重要）

**工具缺陷**：`find_callers.py` 原先用线性反汇编扫描 `bl/b`，而 `__TEXT` 段
起点并非指令边界，导致解码失步、全库 0 命中。§11.4/§11.6 中"直接调用为 0"的
排查结论因此**不可信**。已改为**指令编码模式扫描**（不解码，对数据岛免疫），
并用正例/反例自检（正例：`B768FeatureContentCMa` 应命中 2 处；反例：随机地址 0 处）。

**已定位的调用链**（修复后重扫 9 个 dylib）：

- `allFeatureContents(productID:device:)` 的**唯一**调用方 = `HeadphoneDevice.featureContent`
  属性 getter（27.0 `0x2027144c0`，26.6.2 `0x1dcbc0744`）
- getter 内部还有私有缓存 `_featureContent`（`…15_featureContent33_B2EB…vg`）与
  `first(where:)` 闭包；ObjC 层无暴露（纯 Swift vtable 分派）
- 依赖收敛：抽取到的 9 个 dylib 中只有 **BluetoothSettings / HeadphoneConfigs /
  HeadphoneSettingsUI** 链接 `HeadphoneManager` → UI 消费者就在这三者之内

**当前静态边界**：getter 的跨模块调用走 Swift 类 vtable（`ldr xN,[xMetadata,#slot]; blr`），
不产生 `bl` 目标；协议描述符相对指针解析结果每个版本的 6~7 个 UI 一致性都收敛到同一地址
（自洽），但其为奇数地址、且在三个消费者 dylib 中未发现 ADRP/ADD 引用（可能经 GOT/链式
fixup 间接）。`ipsw macho info -u` 对抽取出的 dylib 返回 "no fixups"，暂不可用。

**下一步（按性价比排序）**：

1. 真机并行验证：26.6.2 + 现有 deb，观察 AirPods 5 是否已有通用设置页
   （`DefaultFeatureContentInternal` 回退在所有版本存在）→ 决定 v0.4 的真实收益
2. CI 上用 `ipsw dyld xref`（macOS，处理完整缓存 fixup）对以下地址做全缓存交叉引用：
   `HeadphoneDevice.featureContent` getter（两版各一）与 UI 协议描述符地址
3. 或自行解析 chained fixups，定位 vtable 槽位后反查消费者

### 11.9 xref 可行性结论（第 1 项任务结果）

按任务边界在 CI（万兆缓存、macOS）上跑了两次 `ipsw dyld xref`：

- `--all`：64 分钟未完成，人工取消
- 按镜像定向（HeadphoneManager / HeadphoneSettingsUI / HeadphoneConfigs / BluetoothSettings）：
  17 分钟未完成，人工取消

结论：`ipsw dyld xref` 上游标记 WIP，在 split cache 上**不可用**；已从默认矩阵移除，
保留为手动脚本 `analysis/xref.sh`（带 timeout，输出 `xref.txt`）。

补充证据：抽取出的 dylib **没有 `LC_DYLD_CHAINED_FIXUPS`**（只有 `LC_DYSYMTAB` 的 745 条
indirect symtab），即缓存内的 rebase 信息在抽取时未保留 → 元数据 vtable 槽位无法用本地工具
静态还原（对 getter 地址做原始 8 字节扫描只命中**符号表**条目，不是分发槽）。

因此第 1 项任务在现有工具下**无法完成**，按任务边界第 2 条：不做 B768 映射、不伪造
witness table、不加猜测性 hook。转入第 3 项：真机验证通用设置页与识别效果。

### 11.10 vtable 槽位定位尝试（第 1 项收尾）

在 xref 不可用后，尝试自行恢复 vtable 槽位：

1. `HeadphoneDevice` 无 ObjC 元数据符号（无 `__DATA__TtC…HeadphoneDevice`），只有 Swift 符号
   `CMa/CMo/CMf/CN`（27.0：`CMf@0x27090e3f8`、`CN@0x27090e410`）
2. 抽取出的 dylib 中，`CMf` 槽位为 `0`、数据段指针普遍被清零（抽取时未保留
   chained fixup / rebase），因此无法从抽取产物恢复槽位
3. 新增 `tools/dsc_read.py`：直接解析各分片自带头部，实现 VM→(分片文件, 偏移) 读取
   （27.0 的 `CMf` 位于 `.54.dylddata`；26.6.2 位于 `.33.dylddata`）
4. 但 DSC 里 `CMf` 本身为 `0`（Swift 类元数据惰性初始化），元数据对象不在邻近窗口；
   在 `CMf` ±8KB 窗口内用 raw/low32/low36/low43 及“相对 image base”等常见 chained
   fixup 解码均**未命中** getter 地址

要完成静态定位，需实现 arm64e chained fixups 的完整解码（`starts_in_image` →
按页链式遍历）+ Swift 类元数据布局定位（描述符 → method descriptors → vtable 序号）。
工作量与不确定性都较大；按任务边界第 2 条，**不做猜测性实现**，
优先转真机验证（第 3 项）以获得真实行为证据。

工具沉淀（可复用）：`dsc_read.py`（DSC 按地址读取）、`find_refs.py`（ADRP/ADD 模式扫描）、
`find_callers.py`（b/bl 编码扫描，含正反例自检）、`disass_swift.py`、`dump_feature_closures.py`。
