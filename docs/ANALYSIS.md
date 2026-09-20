# AirPods 5 → iOS 26.6.2 移植分析报告

> 生成日期：2026-09-21 · 设备：iPhone17,3 (iPhone 16) · 源：iOS 27.0 (24A437) · 目标：iOS 26.6.2 (23G90)

## 1. 结论摘要

- **AirPods 5 整代（2026）在 iOS 26.6.2 上完全缺失支持**，iOS 27.0 首次完整引入。
- 目标机与源机同为 iPhone 16，蓝牙芯片一致 → 属**纯用户态差异**（DSC + 系统资源），不需要内核/驱动移植。
- 需要补齐的最小集合：**9 个 UARP 配件类 + 1 个 Swift 功能类 + 2 条显示名 + 8 个型号 ID 表项**（详见 §5）。
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
   - iOS 27.0：显示名 `AirPods 5`、`AirPods 5 (Wireless Charging)`；`B868FeatureProviding`

## 4. 两版本共有/独有概览

| 项目 | iOS 27.0 | iOS 26.6.2 |
|---|---|---|
| `UARPSupportedAccessoryA3454`（AirPods Max 2） | ✅ | ✅（补丁期已加入） |
| `UARPSupportedAccessoryA3063/64/65`（Pro 3） | ✅ | ✅ |
| `B768FeatureProviding`、`AirPods 4` | ✅ | ✅ |
| **AirPods 5 全部型号/类/显示名** | ✅ | ❌ |
| **`B868FeatureProviding`** | ✅ | ❌ |

## 5. 26.6.2 缺失清单（移植目标）

- **UARP 配件类（9）**：`A3439`、`A3440`、`A3441`、`A3529`、`A3529USB`、`A3530USB`、`A3532`、`A3533`
  （注：`A3531` 无独立类，通过产品 ID 表引用）
- **Swift 功能类**：`B868FeatureProviding`（B768=AirPods 4 的同位类）
- **显示名**：`AirPods 5`、`AirPods 5 (Wireless Charging)`
- **型号 ID 表**：`A3439`、`A3440`、`A3441`、`A3529`、`A3530`、`A3531`、`A3532`、`A3533`

## 6. 影响面（待 hook 定位后确认）

- 设备识别与命名（配对弹窗、设置页名称/图标/分类）
- UARP 固件更新/个性化（配件定义类缺失时通常直接不提供更新）
- 电量显示、ANC/自适应音频、手势等是否受型号表驱动（待验证）

## 7. 方案设计

```
tweak/   rootless Theos 包（ElleKit；/var/jb，兼容 roothide jbroot 探测）
         - 数据驱动型号表（JSON/plist，新增型号无需改代码）
         - 候选 hook：UARPSupportedAccessoryManager（注册/查询）、
           HeadphoneConfigs / MobileBluetooth 型号查找、显示名查询
app/     SwiftUI 控制 App：开关、型号列表、日志导出、重启 bluetoothd
CI       dsc-analysis.yml（分析数据）· build-tweak.yml（出 .deb）· build-app.yml（出 .ipa）
```

## 8. 风险与限制

- **SSV**：iOS 15+ 系统卷签名保护 → 不能替换 DSC/系统二进制，必须运行时注入
- **Swift 类**（`B868FeatureProviding`）不能直接 `%hook`，需 hook 其调用点或桥接层
- **bluetoothd 注入**：rootless 注入器需支持系统守护进程；否则改从 UI/框架层入手
- **固件更新链路**（UARP 配件定义）需真机回归验证
- 越狱工具与 iOS 版本匹配性（Dopamine/roothide 的可用范围）

## 9. 进度与下一步

- [x] IPSW 解包、AEA 解密、DSC 定位
- [x] 型号映射 + 缺失清单（字节级 diff）
- [ ] CI 分析管线修复（bash 3.2 `mapfile` → 已替换为兼容写法）
- [ ] 获取 `objc_classes.txt` / `swift.txt` / 符号表 → 确定 hook 点
- [ ] tweak v0.1：注册型号 ID + 显示名（最小可见效果）
- [ ] 控制 App + Actions 编译
- [ ] 真机回归：配对、设置页、固件更新、电量
