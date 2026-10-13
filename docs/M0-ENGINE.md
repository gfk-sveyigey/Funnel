# M0 引擎评估与选型

## 结论

采用 **SwiftTorrent**（`warppipe/swift-torrent`，纯 Swift、SwiftPM）。
默认引擎已切到 `SwiftTorrentEngine`；把 `EngineFactory.kind` 改成 `.simulated` 可一键回退占位引擎。

> ⚠️ 已知阻塞项：**断点续传未实现**（库接受 `resumeData` 但从不应用），详见下文。

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
   - **断点续传未实现（高，阻塞）** → 见下文《断点续传》一节。
   - 无 per-file 选择优先级 → `selectFiles` 目前只记录、不下发（M3 需补）。
   - 无 per-file 进度 → 文件行进度暂显 0，只有任务级进度准确。
   - `deleteFiles` 粒度太粗（会删整个 savePath）→ 已改为由 `FileStore` 删除。


## 断点续传：当前引擎的阻塞项

- 库里确实有 `ResumeData`（`Storage/ResumeData.swift`，带 `encode()` / `decode(from:)`），`TorrentHandle.generateResumeData()` 也能产出。
- 但 **`AddTorrentParams.resumeData` 在整个库里从未被读取**：
  - `TorrentHandle.init` 不引用 `params.resumeData`；
  - `setupDownloadComponents` 用 `PieceManager(info:)` 从零构建 `Bitfield`；
  - `DiskIO` 也没有「校验已存在文件 / 恢复已完成分片」的逻辑。
- 结论：**杀进程重启后进度丢失、会从头重下**，与 README「断点续传是硬要求」冲突。

### 可选处理

1. **给上游提 PR（推荐，工作量可控）**：让 `PieceManager` 接受初始 `Bitfield`（用 `ResumeData.completedPieces`），让 `DiskIO` 启动时按分片哈希校验已存在文件，并把 `params.resumeData` 透传进 `TorrentHandle`。库内已有 `Bitfield` / `PieceManager.getCompleted()` / `FileStorage` 等构件。
2. **自行维护 fork**：上游未合并前先自用（也顺带能解决许可证问题）。
3. **接受重下**：仅保证重启后任务不丢（当前实现：置为暂停 + 手动继续）。
4. **换回 libtorrent 预案**：libtorrent 有成熟的 resume / 文件校验，代价是 C++ + Boost 的构建复杂度。

## 集成方式

- `project.yml`：`packages:` 声明 `SwiftTorrent`（`branch: main`），target `Funnel` 依赖该 package。
- `Funnel/Engine/SwiftTorrentEngine.swift`：把 `TorrentEngineProtocol` 映射到 `Session` / `TorrentHandle` / `TorrentStatus`。
- `EngineFactory.kind = .swiftTorrent`：默认启用；改 `.simulated` 回退。
- CI：build / release 工作流新增 `xcodebuild -resolvePackageDependencies`，先解析再编译。

## M0 验证清单（在 macOS 26 / Xcode 26.6 上）

- [ ] `xcodegen generate` + `xcodebuild` 能解析并编译 SwiftTorrent（iOS 26）。
- [ ] 粘贴磁力 → 获取元数据 → 文件列表出现。
- [ ] 能连上 peer 并真正下载（公网种子）。
- [ ] 后台保活（静音音频 / PiP）下仍持续下载。
- [ ] 杀进程重启后能续传（**当前引擎未实现 resume 恢复，需上游修复 / fork 或换引擎**）。
- [ ] 限速、做种开关生效。
- [ ] 许可证问题解决。
