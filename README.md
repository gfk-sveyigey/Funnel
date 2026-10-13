# Funnel — iOS 磁力下载 App

## 一、项目目标

- 平台：仅 iOS（侧载分发，非 App Store）。
- 定位：粘贴/接收磁力链接 → 后台下载 → 成品进「文件」App，可播放。
- 引擎：**SwiftyTorrent**（纯 Swift，省掉 libtorrent/Boost 的构建地狱）。
- 保活：**静音音频** 与 **画中画（PiP）** 双方案，用户可选/可切换。

## 二、技术选型与依据

- 引擎 `SwiftyTorrent`
  - 优点：纯 Swift，无 C++/Boost 交叉编译，集成成本低。
  - 代价：成熟度与功能覆盖未知，**这是本项目最大的风险**（见 M0）。
  - 缓解：用 `TorrentEngineProtocol` 门面隔离引擎，一旦不可用可整体替换为 libtorrent，UI 层零改动。
- 保活双方案
  - 静音音频：`AVAudioSession(.playback)` + 循环播放极短静音文件，无界面侵入、最稳。
  - PiP：`AVPictureInPictureController` 挂循环占位视频，用户可见、可主动关闭。
  - 两者都依赖 `UIBackgroundModes: audio`；做成策略可插拔 + 失败自动降级链。
- 分发
  - AltStore / SideStore（7 天重签）、付费账号（1 年）、或 TrollStore（视系统版本）。

## 三、前置验证（M0，Gate 里程碑）

必须先用 3–5 天回答清楚这些问题，否则后续排期无意义：

- SwiftyTorrent 的语言版本 / iOS 部署目标能否编到当前 Swift/Xcode。
- 支持范围：DHT（单播 UDP）、UDP/HTTP Tracker、PEX、磁力元数据获取（BEP-9）。
- 多文件种子与**文件选择**（只下部分文件）。
- 断点续传 / 跨启动恢复。
- 限速、做种控制、加密连接、uTP。
- 并发模型（是否绑 RunLoop、是否适合 `actor` / 多线程）。
- 内存占用与大文件表现。
- **许可证**（合规必须确认）。

产出：一份「可行 / 需改造 / 不可行」结论。**不可行则切换 libtorrent 预案。**

## 四、系统架构（模块划分）

- `App / UI 层`：SwiftUI，粘贴磁力、任务列表、任务详情、设置、日志。
- `TorrentEngineProtocol`（门面）：`add(magnet:) / pause / resume / remove / fileSelection / statusStream`。
  - `SwiftyTorrentEngine`：默认实现。
  - `LibTorrentEngine`：预案实现（接口预留）。
- `TorrentTaskStore`：任务模型持久化与状态同步。
- `KeepAliveCoordinator`：静音音频 / PiP 策略调度 + 降级链 + 打断处理。
- `FileStore`：`Documents/` 落盘、目录结构、分享、删除、缺失检测。
- `LiveActivity`（可选）：锁屏/灵动岛显示进度，不承担保活。

## 五、数据模型（要点）

- `TorrentTask`：`id / infoHash / magnet / name / 状态 / 总大小 / 已下 / 速度 / peers / 文件列表 / 保存路径`。
- `TorrentFile`：`index / path / length / 已下 / 选中`。
- 与 HTTP 下载不同：这是「种子 → 目录 + N 文件」，进度是 per-file 聚合。
- 元数据阶段（只有 info hash、还没有文件列表）要有**独立状态**，UI 需单独表现。
- 持久化只存**相对文件名**（容器路径会变），与 Nox 现有约定一致。

## 六、保活子系统设计（核心）

- `KeepAliveMode`：`.off / .silentAudio / .pictureInPicture`，设置项可选。
- `KeepAliveCoordinator` 行为
  - 有活跃任务时启动、全部暂停/完成时停止。
  - 静音音频：`.playback` 会话 + 循环短静音；监听 `AVAudioSession.interruptionNotification`，被打断后按需恢复。
  - PiP：`AVPictureInPictureController` + 循环占位视频；实现 `pictureInPictureControllerDidStopPictureInPicture`，用户关闭后自动降级到静音音频（若开启）。
  - 场景切换（`scenePhase`）时统一收口启停。
- 边界
  - 保活随时可能失效 → **断点续传是硬要求**，恢复后必须能续下。
  - iOS 无「悬浮窗权限」；PiP 是唯一可浮层形式，仅为保活载体，不是真悬浮窗。

## 七、Info.plist / 权限清单

- `UIBackgroundModes: audio`（保活必需）。
- `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`（文件 App 可见）。
- `NSLocalNetworkUsageDescription`（+ `NSBonjourServices`，若启用局域网发现）。
- 多数 Tracker 是 HTTP/UDP：UDP 不受 ATS 管，HTTP Tracker 可能需 `NSAppTransportSecurity` 例外。
- `NSPhotoLibraryAddUsageDescription`（若支持存相册）。
- 跳过 `com.apple.developer.networking.multicast`（放弃 LSD，靠 DHT/Tracker/PEX）。

## 八、目录结构（工程建议）

- `Nox-like/App`（入口、TabView）
- `Engine/`（门面协议 + SwiftyTorrent 适配 + 预案）
- `KeepAlive/`（两种策略 + 协调器）
- `Store/`（任务持久化、文件管理）
- `Features/Browser`（磁力粘贴/接收）、`Features/Tasks`、`Features/Settings`、`Features/Logs`
- `Resources/`（静音音频、PiP 占位视频、Localizable）

## 九、里程碑与排期（单人）

- **M0 可行性 Spike（3–5 天，Gate）**：SwiftyTorrent 编译 + 磁力跑通。
- **M1 骨架与引擎接入（1–2 周）**：门面 + 粘贴磁力 + 任务列表 + 元数据阶段 UI。
- **M2 保活子系统（约 1 周）**：静音音频 + PiP 双方案、切换、降级、打断处理。
- **M3 下载能力（1–2 周）**：文件选择、进度/速度、暂停续传、限速（视引擎能力）、做种开关。
- **M4 文件与分享（约 1 周）**：Documents 落盘、分享/导出、删除、缺失检测。
- **M5 稳定与打磨（2–3 周）**：异常恢复、内存/发热、日志、Live Activity。

合计约 **2–3 个月**，含风险缓冲。M0 失败则整体切换 libtorrent 预案，排期重估。

## 十、风险登记

- **SwiftyTorrent 不成熟/不可用（高）** → M0 验证 + 门面抽象。
- **保活不稳定、被系统杀（高）** → 断点续传 + 双方案降级 + 恢复重连。
- **协议覆盖不全**（部分 Tracker/DHT 场景失败）（中） → 引擎补齐或换实现。
- **功耗/发热**（中） → 限速、完成即停做种、可配置。
- **合规/版权**（中） → 仅作技术工具、确认引擎许可证。
- **上架风险** → 不申请上架，仅侧载，已规避。

## 十一、MVP 验收标准（DoD）

- 粘贴磁力 → 成功获取元数据 → 可勾选文件 → 下载完成进 `Documents/`。
- 切后台后（保活开启）能持续下载；被系统杀死后重启能续传。
- 静音音频与 PiP 两种保活可切换，PiP 关闭能自动降级。
- 完成文件在「文件」App 可见、可分享、可删除。
- 无崩溃、无明显内存泄漏，日志可导出。
