# M0 引擎评估与选型

## 结论

采用 **SwiftTorrent**（`warppipe/swift-torrent`，纯 Swift、SwiftPM）。
默认引擎已切到 `SwiftTorrentEngine`；把 `EngineFactory.kind` 改成 `.simulated` 可一键回退占位引擎。

> ✅ **断点续传已实现**：库源码 vendor 进 `Vendor/swift-torrent` 并打过补丁，重启后按分片哈希校验续传，详见下文《断点续传》。

## 候选对比

| 引擎 | 形态 | 关键依赖 | 平台 | 版本 | 许可证 | 结论 |
|---|---|---|---|---|---|---|
| SwiftyTorrent (`danylokos`) | Xcode 工程 + Carthage | libtorrent 1.2.17 + Boost 1.69、VLCKit、Swinject | Xcode 13 / iOS 15 | 无 tag/release（master 停在 2024-04） | 无 | ❌ 弃用 |
| **SwiftTorrent (`warppipe`)** | **SwiftPM 包** | swift-nio / nio-extras / swift-crypto | iOS 17+ / macOS 14+ | 无 tag（main 分支，2026-01 更新） | **无** | ✅ 采用（许可证待解决） |
| libtorrent (`arvidn`) | C++ 库 | Boost 等 | 全平台 | 2.0.x | BSD-3 等 | 备选（预案） |

## 为什么弃用 SwiftyTorrent

- 与 README 假设相反：它**不是纯 Swift**，而是基于 libtorrent（C++）+ Boost，`bootstrap.sh` 要编 185.7 MB 的 `libtorrent.xcframework`。
- 依赖分发用 Carthage（VLCKit、Swinject），不是 SwiftPM，没有 `Package.swift`。
- 工程停在 Xcode 13 / iOS 15（2021），且 2024-04 之后无更新。
- 无 tag/release → 无法版本化引用；无 LICENSE。

## 为什么选 SwiftTorrent

- **纯 Swift，零 C/C++ 依赖**，与项目目标一致。
- **标准 SwiftPM 包**，直接在 `project.yml` 声明依赖，Xcode / CI 自动解析。
- 能力覆盖 M0 关心的点：BEP-3（peer wire）、BEP-5（DHT）、BEP-9（元数据交换）、BEP-10（扩展协议）、BEP-15（UDP tracker）、多文件、磁力链接、resume data、`AsyncStream<Alert>` 事件。
- 平台 iOS 17+ / macOS 14+、Swift 5.9+，与我们的部署目标（iOS 26）和语言模式（Swift 5）兼容。

## 已知风险与限制

1. **许可证缺失（高，阻塞发布）**：仓库没有 LICENSE 文件，默认「保留所有权利」。**在拿到作者授权或换成有许可证的实现前，不应对外分发。** 建议给作者开 issue 请求补 MIT/Apache，或 fork 后经授权补许可证。
2. **无版本标签**：只能 `branch: main` 或锁 commit SHA，复现性较弱。当前用 `branch: main`，后续建议锁 revision。
3. **成熟度**：个人项目、约 44★，API 仍可能变动，需要自建回归。
4. **能力缺口**：
   - **断点续传**：上游未实现，已 vendor + 打补丁修复，见下文《断点续传》。
   - 无 per-file 选择优先级 → `selectFiles` 目前只记录、不下发（M3 需补）。
   - 无 per-file 进度 → 文件行进度暂显 0，只有任务级进度准确。
   - `deleteFiles` 粒度太粗（会删整个 savePath）→ 已改为由 `FileStore` 删除。


## 断点续传（已实现）

上游库本身不消费 `resumeData`：`TorrentHandle.init` 不引用它，`setupDownloadComponents` 用 `PieceManager(info:)` 从零建 `Bitfield`，`DiskIO` 也不校验已存在文件——原样使用会「杀进程重启后从头重下」。

本仓库采用 **vendoring + 打补丁**（不依赖上游合并）：

- 库源码放进 `Vendor/swift-torrent`，`project.yml` 改用本地 `path:` 依赖；CI 不再拉取上游分支，构建可复现。
- `PieceManager` 新增 `init(info:completed:)`，用 `ResumeData.completedPieces` 初始化分片位图；新增 `verifyPieces(_:using:)`，启动时对「声称已完成」的分片按 SHA-1 重新校验磁盘数据。
- `TorrentHandle` 保存 `params.resumeData`，在 `setupDownloadComponents` 里先 seed 再校验，并按校验通过的分片重算 `totalDownloaded`（tracker 的 `left` 因此正确）。
- 校验不通过（文件缺失 / 被截断 / 被改坏）的分片会被丢弃重下，等价于一次「快速 recheck」。

App 层配合：

- `TorrentTask.resumeData`（`Data?`）随 `tasks.json` 持久化。
- 暂停、切后台、以及每 15 秒的定时器都会调用 `engine.resumeData(_:)` 抓一次并写盘。
- 重启后任务为「已暂停」：点「继续」时 `AppModel` 发现引擎已无句柄（`engine.contains == false`），就用磁力 + 存下来的 `resumeData` 重新加入，只补缺失分片。

> 注意：磁力任务的 info（文件列表）仍需从 DHT / peer 重新获取一次（通常几秒），之后按校验结果续传；已下载分片不会丢。

### 仍未做的（可选）

1. **给上游提 PR**：把这些补丁提回 `warppipe/swift-torrent`，合并后即可去掉 vendoring。
2. **缓存 .torrent info**：把 info 字典一并持久化，重启后无需重新获取元数据。
3. **换回 libtorrent 预案**：resume / 文件校验更成熟，代价是 C++ + Boost 的构建复杂度。
## 集成方式

- `project.yml`：`packages:` 声明 `SwiftTorrent` 为本地路径 `Vendor/swift-torrent`（已打续传补丁），target `Funnel` 依赖该 package。
- `Funnel/Engine/SwiftTorrentEngine.swift`：把 `TorrentEngineProtocol` 映射到 `Session` / `TorrentHandle` / `TorrentStatus`。
- `EngineFactory.kind = .swiftTorrent`：默认启用；改 `.simulated` 回退。
- CI：build / release 工作流新增 `xcodebuild -resolvePackageDependencies`，先解析再编译。

## M0 验证清单（在 macOS 26 / Xcode 26.6 上）

- [ ] `xcodegen generate` + `xcodebuild` 能解析并编译 SwiftTorrent（iOS 26）。
- [ ] 粘贴磁力 → 获取元数据 → 文件列表出现。
- [ ] 能连上 peer 并真正下载（公网种子）。
- [ ] 后台保活（静音音频 / PiP）下仍持续下载。
- [ ] 杀进程重启后能续传（已 vendor + 打补丁；需真机验证「只补缺失分片」）。
- [ ] 限速、做种开关生效。
- [ ] 许可证问题解决。
