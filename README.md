<div align="center">

<img src="docs/icon.png" width="112" alt="LayoutSnap 布局快照">

# LayoutSnap 布局快照

macOS 窗口布局管理与恢复工具

[![CI](https://github.com/Skyearn/LayoutSnap/actions/workflows/ci.yml/badge.svg)](https://github.com/Skyearn/LayoutSnap/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Skyearn/LayoutSnap)](https://github.com/Skyearn/LayoutSnap/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

</div>

---

## 概述

LayoutSnap（中文名：布局快照）是一个常驻菜单栏的 macOS 工具，用于保存与恢复窗口布局。

它在某一时刻扫描系统中所有普通应用的窗口，记录每个窗口的位置、尺寸、
所在显示器、最小化状态以及窗口之间的前后叠放顺序，将其保存为一个「布局」。
此后可通过菜单或全局快捷键，将窗口恢复到该布局所描述的状态。

适用场景：

- 多显示器环境发生变化后恢复窗口排列（外接显示器插拔、扩展坞切换、分辨率调整、合盖唤醒）
- 在多套工作环境之间切换，例如「办公」与「影音」
- 窗口位置被意外打乱后，恢复到之前的状态

本项目的功能按实际使用需要设计，围绕多显示器环境切换与多套工作环境切换两个场景展开，
基于 macOS 公开的 Accessibility API 实现，未使用任何私有接口。

## 功能

| 能力 | 说明 |
| --- | --- |
| 保存布局 | 记录所有窗口的位置、尺寸、所在显示器、最小化状态与前后叠放顺序 |
| 恢复布局 | 通过菜单或全局快捷键还原；未运行的应用会自动启动 |
| 四种保存方式 | 添加当前窗口、添加部分窗口、保存部分窗口、保存所有窗口；可存为新布局，或追加/覆盖已有布局 |
| 布局编辑 | 按应用分组列出窗口，可删除整个应用、删除单个窗口、修改坐标、停用、调整顺序 |
| 跨显示器投影 | 显示器配置变化后，窗口按相对比例投影到新的屏幕上 |
| 自动恢复 | 显示器配置变化、系统唤醒、指定应用启动时自动恢复某个布局 |
| 全局快捷键 | 四个功能与每个布局均可单独录制快捷键，默认仅「恢复布局」绑定 `⌃Z` |
| 菜单栏状态 | 以图标变化表示处理中、成功、警告、失败与权限缺失，不占用菜单栏文字空间 |
| 忽略应用 | 从运行中的应用列表中选择，或从「应用程序」文件夹中选取，无需手输 Bundle ID |
| 命令行模式 | 提供 `--scan`、`--save`、`--restore`、`--doctor`、`--selftest` 等子命令 |
| 导入导出 | 布局以可读的 JSON 格式保存，便于备份与迁移 |

## 安装

### 下载安装（推荐）

1. 从 [Releases](https://github.com/Skyearn/LayoutSnap/releases) 下载 `LayoutSnap-x.y.z.dmg`
2. 打开磁盘映像，将 LayoutSnap 拖入「应用程序」文件夹
3. 首次启动时，在「应用程序」中右键点击 LayoutSnap，选择「打开」

   若双击后被系统拦截，也可在终端执行一次：

   ```bash
   xattr -dr com.apple.quarantine /Applications/LayoutSnap.app
   ```

   > 原因是本项目未使用 Apple 开发者账号进行公证（需年费）。代码完全公开，
   > 也可按下一节自行构建。

4. 授权辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 → 勾选 LayoutSnap
   （若列表中不存在，点击 `+` 添加 `/Applications/LayoutSnap.app`）
5. 授权后需**重启 LayoutSnap** 才会生效

### 从源码构建

要求 Xcode 15 及以上、macOS 13 及以上：

```bash
git clone https://github.com/Skyearn/LayoutSnap.git
cd LayoutSnap

# 编译并打包为 build/LayoutSnap.app
./scripts/build.sh

# 安装到「应用程序」（开机自启需要固定路径）
./scripts/build.sh release install
```

使用 Xcode 开发：执行 `open Package.swift` 即可（SwiftPM 工程，无需 `.xcodeproj`）。

## 使用

### 保存布局

将窗口调整到目标状态，点击菜单栏图标 →「保存所有窗口」→「新建布局…」，
输入名称即可。

四个入口按「窗口范围」和「追加还是覆盖」区分：

```
添加当前窗口 ▸
    添加到「工作」      ← 把当前这个窗口加进去，其他记录不动
    添加到「看片」
    ─────────────
    新建布局…
添加部分窗口 ▸
    添加到「工作」      ← 勾选若干窗口后加进去
    ...
保存部分窗口 ▸
    覆盖「工作」        ← 勾选若干窗口，整体覆盖
    ...
保存所有窗口 ▸
    覆盖「工作」        ← 用当前所有窗口整体覆盖
    ...
```

命名约定：**「添加」= 追加，「保存」= 覆盖**。

- 追加时，若同一应用、同一标题的窗口已在布局中，则更新那一条的位置而不是新增一条
- 覆盖等价于重新拍一次快照，布局里原有的窗口记录会被替换

### 恢复布局

- 按 `⌃Z`（默认快捷键）恢复最近使用过的布局
- 或点击菜单栏图标 →「恢复布局」→ 在列表中选择
- 也可为单个布局绑定独立快捷键（设置 → 快捷键）

### 编辑布局

点击菜单栏图标 →「管理布局」→ 选择布局 →「编辑布局…」，
会打开设置窗口并定位到该布局。

窗口列表按应用分组：

- **删除本应用**：移除该应用在此布局中的全部记录（仅删除记录，不影响实际窗口）
- 每条窗口右侧提供：`↩︎` 仅归位该窗口、`⇄` 以当前窗口位置覆盖记录、`✎` 编辑、
  `↑↓` 调整顺序、`🗑` 删除
- 应用名左侧与标题栏左侧提供**三态复选框**（全选／半选／全不选），
  可一次切换整个应用或整个布局的启用状态

### 显示器配置变化时自动恢复

1. 连接外接显示器并调整窗口，保存为「办公」
2. 设置 → 通用 → 启用「显示器配置变化时自动恢复」，选择「办公」
3. 此后连接显示器时窗口会自动恢复，合盖唤醒同样适用

### 触发应用

在「设置 → 布局」中为布局指定触发应用，这些应用启动时会自动恢复该布局。
恢复过程中被自动启动的应用不会再次触发，不会形成循环。

## 菜单结构

```
恢复布局 ▸
    再次恢复「工作」           ⌃Z
    ─────────────
    工作
    看片
────────────────────────
添加当前窗口 ▸
    添加到「工作」
    添加到「看片」
    ─────────────
    新建布局…
────────────────────────
添加部分窗口 ▸
保存部分窗口 ▸
保存所有窗口 ▸
────────────────────────
管理布局 ▸
    工作 ▸  编辑布局… / 更新布局 / 重命名… / 复制一份 / 删除…
────────────────────────
恢复时启动未运行的应用        ✓      ← 可勾选
────────────────────────
设置…                          ⌘,
打开日志文件夹
────────────────────────
退出 LayoutSnap                ⌘Q
```

> **快捷键的显示位置**：带展开箭头的父项在 macOS 上不显示快捷键，
> 该位置由展开箭头占用（Xcode 的「查找 ▸」遵循同一约定，`⌘F` 显示在子项「查找…」上）。
> 因此每个功能的快捷键均挂载在**实际执行该动作的菜单项**上：
> 「恢复布局」的 `⌃Z` 位于「再次恢复「工作」」，「保存…」的快捷键位于「新建布局…」
> （快捷键触发的即为新建流程）。

## 快捷键

设置 → **快捷键**，所有快捷键均在此页面录制：

| 功能 | 默认值 |
| --- | --- |
| 恢复布局 | **⌃Z** |
| 添加当前窗口 | 不设置 |
| 添加部分窗口 | 不设置 |
| 保存部分窗口 | 不设置 |
| 保存所有窗口 | 不设置 |
| 每个布局（单独） | 不设置 |

> 「添加当前窗口」「添加部分窗口」「保存部分窗口」的快捷键作用于**最近使用的布局**（最近恢复过、或最近保存/添加到的那个）。
> 若还没有可用布局，则转为新建布局流程。

录制方式：点击右侧按钮后按下组合键，必须包含 `⌘`、`⌃`、`⌥`、`⇧` 中的至少一个修饰键。

- `Esc` 取消本次录制，`Delete` 清除已设置的快捷键
- 录制期间会临时注销所有全局热键，避免组合键触发原绑定动作
- 同一组合键只能绑定一个功能，绑定到新位置时会自动解除原绑定
- 若组合键已被系统或其他应用占用，注册会失败并记录到日志

## 菜单栏图标状态

菜单栏不显示文字（避免占用其他应用的空间），以图标变化表示状态：

| 图标 | 含义 |
| --- | --- |
| 窗口字形 | 就绪 |
| 沙漏 | 正在扫描或正在恢复 |
| 对勾 | 上一次操作成功（数秒后自动回到就绪） |
| 警告三角 | 部分窗口未恢复成功、布局内无窗口等提示 |
| 叉 | 操作失败 |
| 手掌 | 尚未获得辅助功能权限（授权后自动恢复为窗口字形） |

操作结果不写入菜单，也不做悬停提示，而是记录到日志：

```bash
tail -f ~/Library/Logs/LayoutSnap/LayoutSnap.log
# [10-08 12:17:07] [info] 开始恢复「默认」，共 7 个窗口
# [10-08 12:17:11] [info] 状态：已恢复 7 个窗口
# [10-08 12:17:11] [info] 恢复完成：已恢复 7 个窗口，耗时 3.4s
```

> 菜单中不设标题行与「上次操作」行：macOS 原生菜单均从功能项开始，
> 且菜单栏图标已表达状态，历史细节查阅日志即可。
> 菜单栏 toolTip 为固定文案，不随状态变化——动态刷新 toolTip 会导致
> AppKit 反复重新弹出提示框。

## 命令行

```bash
APP=/Applications/LayoutSnap.app/Contents/MacOS/LayoutSnap

$APP --doctor              # 检查权限、显示器、功能快捷键与已保存的布局
$APP --check-layout "工作"  # 只计算每条记录会落到哪块屏上，不移动任何窗口
$APP --scan                # 列出当前所有窗口（位置、尺寸、所在显示器）
$APP --scan --json         # 同上，JSON 输出
$APP --save "家里"          # 将所有窗口保存为布局
$APP --save-window 3 "看板"  # 仅将 --scan 列表中的第 3 个窗口保存为布局
$APP --restore "家里"       # 恢复布局
$APP --list                # 列出已保存的布局
$APP --selftest            # 运行内置自检（127 项断言）
```

`--selftest` 不需要辅助功能权限，可随时用于验证代码正确性；CI 中运行的即为该命令。

## 性能

窗口数量增加会变慢，主要有两个原因：每个窗口的读写都需要与目标应用进行一次
进程间通信（AX IPC），以及恢复时需要等待几何变更生效。相应的优化如下。

**扫描（保存）**

- **按应用并行**：不同应用之间互不影响，可同时扫描；默认并发 4，可在设置中调整（1–8）
- **显示器列表只查询一次**：`NSScreen` 查询开销不小，而一次扫描会调用数百次，
  因此加入 2 秒 TTL 缓存
- **每个窗口的属性只读一遍**：避免 `role`／`subrole`／`frame`／`minimized` 的重复读取

**恢复**

- **按应用并行**，同样受并发上限约束；**同一应用内部保持串行**——
  应用自身的窗口管理逻辑容易相互干扰，跨应用才是安全的并行单位
- **将固定延时改为轮询**：原先每移动一个窗口需固定等待 90ms 再回读结果，
  现改为每 10ms 探测一次，通常十余毫秒即可确认；较慢的应用会等待至 150ms 超时
- 取消最小化、等待应用交出窗口等环节同样改为轮询
- 收尾的叠放顺序处理不再每提升一个窗口等待 30ms

> 每次恢复的耗时都会写入日志（`恢复完成：已恢复 7 个窗口，耗时 1.1s`），
> 可直接据此对比调整前后的差异。并发数位于 设置 → 通用 → 并行处理的应用数。

## 实现要点

- **窗口读写**：`AXUIElement`（`AXPosition`、`AXSize`、`AXMinimized`、`AXFullScreen`）。
  无响应的应用会将 AX 调用阻塞数秒，因此统一将 `AXUIElementSetMessagingTimeout`
  限制在 1 秒以内。
- **坐标系**：AX 与 CGWindowList 使用「主屏左上角为原点、y 轴向下」的全局坐标；
  `NSScreen` 使用「左下角为原点、y 轴向上」的坐标，由 `ScreenGeometry` 负责转换。
- **跨显示器投影**：布局中同时保存绝对坐标与相对显示器的归一化矩形。
  原显示器仍存在时使用绝对坐标（最精确）；显示器缺失时使用归一化坐标投影到新屏幕，
  并收敛到可见区域内。
- **前后顺序**：以 `CGWindowListCopyWindowInfo` 的返回顺序作为 z 序，
  恢复时按从后到前的顺序调用 `AXRaise`，还原原有叠放关系。
- **窗口配对**：采用贪心匹配，评分由标题相似度（×3）、位置接近度（×2）、
  尺寸接近度与窗口类型一致性组成；评分过低时按顺序匹配剩余窗口，避免错误配对。
- **全局热键**：使用 Carbon `RegisterEventHotKey`。相比 `NSEvent` 全局监听，
  注册的是系统级热键，不需要「输入监控」权限，也不会拦截其他按键。
- **图标**：菜单栏使用系统符号 `rectangle.3.group`；App 图标通过渲染该符号、
  逐像素测量三块矩形的比例后以 CoreGraphics 重新绘制
  （SF Symbols 许可不允许将其直接用于 App 图标）。
  修改图标时调整 `scripts/make_icon.swift` 中的 `glyphRects`，然后执行：

  ```bash
  swift scripts/make_icon.swift
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
  ./scripts/build.sh release
  ```

## 数据文件

```
~/Library/Application Support/LayoutSnap/layouts.json   布局
~/Library/Logs/LayoutSnap/LayoutSnap.log                日志
```

`layouts.json` 为可读格式，可直接编辑或通过导入导出功能备份。
单条窗口记录的结构如下：

```jsonc
{
  "bundleID": "com.apple.Safari",
  "title": "Apple",            // 保存时的窗口标题
  "matchTitle": null,          // 自定义匹配关键词，设置后优先使用
  "isEnabled": true,           // false 表示保留记录但不参与恢复
  "frame": { "x": 0, "y": 25, "width": 960, "height": 900 },   // 全局坐标
  "displayFrame": { },         // 保存时所在显示器的矩形
  "relativeFrame": { },        // 相对显示器的归一化坐标（显示器变化时使用）
  "zIndex": 0                  // 前后顺序，0 位于最前
}
```

## 常见问题

**执行恢复后窗口未移动**

首先确认菜单栏图标是否为手掌（缺少权限）。授权后必须重启应用。
Chromium／Electron 系应用（Chrome、VS Code、Slack 等）需在设置中启用**兼容模式**。

**开机自启不可用**

需先将 App 放入 `/Applications`：执行 `./scripts/build.sh release install`，
然后在 系统设置 → 通用 → 登录项 中确认。

**授权有效，但重新编译后需要重新授权**

说明本次构建退回了 ad-hoc 签名。检查 `security find-identity -v -p codesigning`
是否存在可用证书，或显式指定：`CODESIGN_IDENTITY="证书名" ./scripts/build.sh`。

**需要查看恢复过程的详细信息**

菜单 →「打开日志文件夹」，`LayoutSnap.log` 中记录了每一步的执行细节。

## 已知限制

- **窗口无法跨「调度中心」空间移动**。macOS 未提供公开 API 可将窗口移动到其他 Space
  （yabai 等工具使用私有接口并需关闭 SIP）。LayoutSnap 仅恢复位置与尺寸，
  窗口保留在其原有 Space 中。
- 保存时处于**全屏**的窗口默认不做处理，避免影响正在全屏使用的窗口
  （可在设置中改为同样切换到全屏）。
- 少数应用（游戏、部分 Electron 应用、自带窗口管理器的应用）会拒绝通过脚本修改窗口，
  日志中会记录「移动窗口失败」，可先尝试兼容模式。
- 恢复仅**按照布局描述摆放窗口**，不会关闭布局外的窗口。
- 恢复时默认会**启动布局里记录、但当前没有运行的应用**；不想被打扰可以在菜单里取消勾选
  「恢复时启动未运行的应用」，这些窗口会被跳过（报告里计入「跳过」而非「失败」）。

## 开发

```
Package.swift                     SwiftPM 清单（Xcode 中直接打开此文件）
Resources/Info.plist              LSUIElement=true，菜单栏应用，无 Dock 图标
Resources/AppIcon.icns            App 图标
Sources/LayoutSnap/
  main.swift                      入口：先判断是否为命令行模式，否则进入菜单栏模式
  App/
    AppDelegate.swift             生命周期与首次运行引导
    AppController.swift           核心调度：菜单、热键、系统通知
    StatusBarController.swift     菜单栏图标状态机与菜单
    CLI.swift                     命令行模式
    SelfTest.swift                不依赖权限的自检（127 项）
  Core/
    AX.swift                      Accessibility API 封装
    Models.swift                  Layout / LayoutSnapshot / Frame / HotKeySpec
    WindowScanner.swift           扫描窗口并生成快照
    WindowMatcher.swift           快照与真实窗口的配对评分
    WindowRestorer.swift          恢复流程（兼容模式、叠放顺序、并行调度）
    WindowLocator.swift           查找记录对应的真实窗口
    ScreenGeometry.swift          坐标系转换、显示器解析、投影与缓存
    AppLauncher.swift             启动应用并等待其交出窗口
    LayoutStore.swift             布局持久化与编辑操作
    AppSettings.swift             偏好设置
    AppActions.swift              四个全局动作
    HotKeyCenter.swift            Carbon 全局热键注册
    HotKeyKeys.swift              NSEvent 与 Carbon 键码换算
    KeyCodes.swift                键码表
  UI/                             SwiftUI 界面（通用 / 布局 / 快捷键 / 关于）
scripts/build.sh                 编译、打包与签名
scripts/package.sh               生成 zip 与 dmg
scripts/make_icon.swift          生成图标
```

运行测试：

```bash
swift build && ./build/LayoutSnap.app/Contents/MacOS/LayoutSnap --selftest
```

## 发布流程

推送 tag 即会自动构建并创建 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/release.yml` 会依次执行：编译通用二进制（arm64 与 x86_64）、
生成 zip 与 dmg、运行自检、生成 `SHA256SUMS.txt`、创建 Release。

如需附带正式签名与公证，在仓库 Secrets 中配置以下条目；
未配置时使用 ad-hoc 签名，功能一致，仅首次启动需要手动放行：

| Secret | 说明 |
| --- | --- |
| `MACOS_CERT_P12` | Developer ID Application 证书导出的 `.p12`，经 base64 编码后的文本 |
| `MACOS_CERT_PASSWORD` | 上述 p12 文件的密码 |
| `KEYCHAIN_PASSWORD` | 临时钥匙串的密码，可任意设置 |
| `APPLE_ID` | 公证使用的 Apple ID |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_PASSWORD` | App 专用密码 |

## 许可

[Apache License 2.0](LICENSE)
