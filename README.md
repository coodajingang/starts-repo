<div align="center">
  <img src="https://img.icons8.com/fluency/96/play-button-circled.png" alt="CloudPlayer" width="96" height="96"/>
  <h1>☁️ CloudPlayer</h1>
  <p>
    <strong>Apple 全平台 Alist 播放器客户端</strong>
  </p>
  <p>
    <img src="https://img.shields.io/badge/iOS-17.0+-000?logo=apple&labelColor=555" alt="iOS 17+"/>
    <img src="https://img.shields.io/badge/macOS-14.0+-000?logo=apple&labelColor=555" alt="macOS 14+"/>
    <img src="https://img.shields.io/badge/tvOS-17.0+-000?logo=apple&labelColor=555" alt="tvOS 17+"/>
    <img src="https://img.shields.io/badge/visionOS-1.0+-000?logo=apple&labelColor=555" alt="visionOS 1+"/>
  </p>
  <p>
    <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9"/>
    <img src="https://img.shields.io/badge/SwiftUI-5.9-007AFF?logo=swift&logoColor=white" alt="SwiftUI"/>
    <img src="https://img.shields.io/badge/SwiftData-5.9-AC53FF?logo=swift&logoColor=white" alt="SwiftData"/>
    <img src="https://img.shields.io/badge/AVFoundation-000?logo=apple&labelColor=555" alt="AVFoundation"/>
  </p>
  <p>
    <a href="#特性">✨ 特性</a> •
    <a href="#快速开始">🚀 快速开始</a> •
    <a href="#技术架构">🏗️ 技术架构</a> •
    <a href="#api-参考">📡 API 参考</a> •
    <a href="#播放策略">🎯 播放策略</a> •
    <a href="#开发计划">📋 开发计划</a>
  </p>
  <br>
</div>

---

**CloudPlayer** 是一款连接 [Alist](https://alist.nn.ci/) 与 WebDAV 服务器的 Apple 全平台视频播放器。它专注于"浏览 → 点击 → 播放"的核心体验，让你随时随地访问网盘中的媒体文件。

> 对标 Infuse 的部分功能，但只依赖 alist 服务端，不直接接入 Google Drive 等云 API。

---

## ✨ 特性

### 📡 多源连接

| 源类型 | 认证方式 | 状态 |
|--------|----------|------|
| **Alist 服务器** | Token / 用户名+密码 | ✅ 稳定 |
| **WebDAV 服务器** | Basic Auth | ✅ 稳定 |
| **本地文件系统** | 沙盒权限 | ✅ 稳定 |

### 🎬 播放引擎

- **AVFoundation 核心** — 基于 `AVPlayer` 的播放引擎
- **智能格式检测** — 自动识别需要 FFmpeg 解封装的格式
- **GCDWebServer 代理** — 为需要自定义 Header 的直链添加 Referer/UA
- **直链自动刷新** — 30 分钟轮询，过期无感切换
- **VideoToolbox 硬解码** — 支持 H.264/H.265 硬件加速解码
- **格式自动回退** — 原生播放失败自动切换到 FFmpeg 解封装

### 🎯 播放控制

- 倍速播放：0.25x ~ 3.0x 逐级调节
- 手势控制：单击/双击/捏合
- 进度拖动：支持 Range 请求
- 画中画（iOS 15+）
- 后台播放
- 音量/静音调节

### 📝 字幕系统

- **格式支持**：SRT / ASS / VTT / MicroDVD / SubRip
- **自动关联**：同目录同名字幕自动识别
- **样式解析**：ASS 格式标签清理
- **实时显示**：时间轴精准匹配

### 💾 数据持久化

| 存储 | 用途 | 技术 |
|------|------|------|
| **SwiftData** | 播放记录、连接配置、收藏、历史 | iOS 17+ 原生 ORM |
| **Keychain** | Token、WebDAV 密码 | `KeychainAccess` 封装 |
| **UserDefaults** | 偏好设置（速度、音量、主题） | 轻量级 KV 存储 |

---

## 🚀 快速开始

### 环境要求

| 工具 | 版本 |
|------|------|
| Xcode | 15.2+ |
| Swift | 5.9+ |
| iOS | 17.0+ |
| macOS | 14.0+ |
| tvOS | 17.0+ |
| visionOS | 1.0+ |

### 构建

```bash
# 克隆
git clone https://github.com/yourusername/CloudPlayer.git
cd CloudPlayer

# 打开 Xcode 项目
open Package.swift

# 或使用 SPM 构建
swift build
```

### 使用

1. 启动应用，进入**连接页面**
2. 输入 Alist 服务器地址和 Token（或用户名密码）
3. 浏览文件目录树
4. 点击视频文件 → **自动选择最佳播放策略** → 开始播放

### 调试

```bash
# 运行单元测试
swift test

# 查看日志（Xcode 控制台）
# [MediaPlayerService] Smart play: strategy=directPlay
# [GCDWebServer] Proxy request: /proxy/xxxx-xxxx
# [SwiftDataManager] Saved playback record
```

---

## 🏗️ 技术架构

### 项目结构

```
CloudPlayer/
├── Package.swift                          # SPM 配置
├── Sources/CloudPlayer/
│   ├── CloudPlayerApp.swift               # 入口 + 服务初始化 + Splash
│   │
│   ├── Models/                            # 数据模型层
│   │   ├── MediaFile.swift                # 媒体文件 + Alist API 响应模型
│   │   ├── DriveConnection.swift          # 存储源配置（Alist/WebDAV/本地）
│   │   └── PlaybackState.swift            # 播放器状态 + 记录 + 字幕/音轨
│   │
│   ├── Services/                          # 服务层（Actor 隔离）
│   │   ├── AlistService.swift             # Alist REST API 客户端
│   │   ├── WebDAVService.swift            # WebDAV PROPFIND 客户端
│   │   ├── LocalFileService.swift         # 本地文件浏览
│   │   ├── MediaPlayerService.swift       # AVPlayer 封装 + 智能播放
│   │   ├── FFmpegService.swift            # FFmpeg 解封装 + VideoToolbox 硬解码
│   │   ├── GCDWebServerService.swift      # 本地 HTTP 代理服务器
│   │   └── ProxyService.swift             # URLProtocol 代理备选
│   │
│   ├── ViewModels/                        # MVVM 视图模型层
│   │   ├── BrowserViewModel.swift         # 文件浏览 + 连接管理
│   │   ├── PlayerViewModel.swift          # 播放控制 + 字幕 + 进度
│   │   └── SettingsViewModel.swift        # 设置 + 连接管理
│   │
│   ├── Views/                             # SwiftUI 视图层
│   │   ├── Shared/                        # 通用组件
│   │   │   ├── SharedViews.swift          # FileRow、ProgressSlider、Controls
│   │   │   └── VideoPlayerView.swift      # AVPlayerLayer + PiP + 手势
│   │   ├── iOS/                           # NavigationStack + TabView
│   │   ├── macOS/                         # NavigationSplitView
│   │   ├── tvOS/                          # 焦点导航 + 卡片网格
│   │   └── visionOS/                      # 空间计算适配
│   │
│   └── Utils/                             # 工具层
│       ├── KeychainManager.swift           # 安全存储 + 偏好管理
│       ├── SubtitleLoader.swift            # 字幕解析器
│       ├── SwiftDataManager.swift          # 数据持久化层
│       └── PlatformUtils.swift             # 平台检测 + 自适应
│
└── Tests/CloudPlayerTests/                 # 单元测试
```

### 架构分层

```
┌─────────────────────────────────────────────────────────┐
│                     Views (SwiftUI)                      │
│  iOS (NavStack) │ macOS (NavSplitView) │ tvOS (Focus)    │
├─────────────────────────────────────────────────────────┤
│                   ViewModels (MVVM)                      │
│     BrowserViewModel │ PlayerViewModel │ SettingsVM      │
├─────────────────────────────────────────────────────────┤
│                     Services (Actor)                      │
│  Alist │ WebDAV │ LocalFile │ MediaPlayer │ FFmpeg │ Proxy│
├─────────────────────────────────────────────────────────┤
│          Models │ Utils │ SwiftData │ Keychain            │
└─────────────────────────────────────────────────────────┘
```

### 核心数据流

```
用户点击文件
    ↓
BrowserViewModel.getPlaybackURL()
    ↓
AlistService.getDirectLink() → 获取直链 + Header
    ↓
FormatDetector.getPlaybackStrategy()
    ├── directPlay        → AVPlayer 直接播放
    ├── ffmpegDemux       → FFmpeg 解封装 → VideoToolbox → AVPlayer
    └── tryNativeThenFFmpeg → 先尝试原生，失败自动回退
    ↓
    ├── 需要 Header?      → GCDWebServer 创建代理 URL
    └── 直链会过期?       → 设置 30 分钟轮询刷新
    ↓
MediaPlayerService.smartPlay() → 播放
    ↓
PlayerViewModel.saveProgress() → SwiftData 持久化
```

---

## 🎯 播放策略

### 智能格式检测

```swift
.mp4  .mov  .m4v  .m4a  → directPlay        ✅ AVPlayer 原生
.mkv  .avi  .wmv  .flv   → ffmpegDemux       🔧 FFmpeg 解封装
.webm .rmvb .ts   .mts   → ffmpegDemux       🔧 FFmpeg 解封装
.3gp  .ogv  .ogg         → tryNativeThenFFmpeg 🔄 自动回退
```

### 直链代理流程

```
原始直链: https://alist.example.com/d/xxx?sign=xxx
    │ 需要 Header: { Referer, User-Agent }
    ▼
GCDWebServer 创建代理映射
    │
    ▼
代理 URL: http://127.0.0.1:9898/proxy/uuid-xxxx
    │
    ▼
AVPlayer 请求代理 URL
    → GCDWebServer 添加 Header
    → 转发原始直链
    → 返回数据给 AVPlayer
```

### 直链过期处理

```
定时器（30分钟）
    ↓
refreshPlaybackURL()
    → 重新获取直链
    → 创建新代理映射
    → replaceCurrentItem 无感切换
    → 保持当前播放位置和速率
```

---

## 📡 API 参考

### Alist API

| 接口 | 方法 | 用途 |
|------|------|------|
| `/api/auth/login` | `POST` | 登录获取 Token |
| `/api/fs/list` | `POST` | 列出目录内容 |
| `/api/fs/get` | `POST` | 获取文件直链 |
| `/api/fs/search` | `POST` | 搜索文件 |
| `/api/me` | `GET` | 验证 Token 有效性 |

> 详细文档：[Alist API 文档](https://alist.nn.ci/zh/guide/api/)

### WebDAV

| 方法 | 用途 |
|------|------|
| `PROPFIND` | 列出目录内容 |
| `GET` | 下载文件 |
| `OPTIONS` | 验证服务器能力 |

---

## 🔧 核心模块详解

### `MediaPlayerService` — 播放引擎

```swift
// 智能播放（自动选择策略）
mediaPlayerService.smartPlay(
    url: directURL,
    headers: ["Referer": "https://example.com"],
    title: "Movie.mp4",
    resumeTime: 120.0  // 从 2 分钟处续播
)

// 基础控制
mediaPlayerService.play(url:)
mediaPlayerService.pause()
mediaPlayerService.seek(to: 60.0)
mediaPlayerService.setRate(1.5)
mediaPlayerService.setVolume(0.8)
mediaPlayerService.setMuted(false)
```

### `FFmpegService` — 解封装引擎

```swift
// 格式支持检测
let needsFFmpeg = FormatDetector.needsFFmpeg(url)  // .mkv → true
let strategy = FormatDetector.getPlaybackStrategy(for: url)
// → .ffmpegDemux

// 自定义 ResourceLoader 拦截
let asset = FFmpegURLScheme.createFFmpegAsset(for: mkvURL)
// 自动注册 AVAssetResourceLoader → FFmpeg demux → VideoToolbox decode
```

### `GCDWebServerService` — 代理服务器

```swift
// 启动服务器
try await ProxyServiceIntegration.shared.start(port: 9898)

// 创建代理 URL
let proxyURL = await ProxyServiceIntegration.shared.createProxiedURL(
    for: originalURL,
    headers: ["Referer": "https://alist.example.com"]
)

// AVPlayer 通过代理 URL 播放
// 服务器自动添加 Header 并转发
```

### `SwiftDataManager` — 数据持久化

```swift
// 保存播放记录
SwiftDataManager.shared.savePlaybackRecord(record)

// 获取未看完的
let unfinished = SwiftDataManager.shared.fetchUnfinishedRecords()

// 收藏
SwiftDataManager.shared.addFavorite(file, sourceID: id, sourceName: "Server")

// 统计数据
let stats = SwiftDataManager.shared.getStatistics()
// totalFiles: 42, totalPlayTime: 28h, unfinishedCount: 5
```

---

## 📋 开发计划

### ✅ P0 — 基础播放（已完成）
- [x] Alist 连接认证（Token / 密码）
- [x] 目录浏览（/api/fs/list）
- [x] 直链获取与播放（/api/fs/get）
- [x] 本地文件浏览
- [x] 基本播放控制（暂停/继续/进度/音量）
- [x] GCDWebServer 代理（自定义 Header）
- [x] FFmpeg 解封装架构
- [x] SwiftData 持久化
- [x] GitHub Actions CI/CD
- [x] 多平台结构（iOS/macOS/tvOS/visionOS）

### 🚧 P1 — 播放体验
- [ ] 倍速播放（0.25x ~ 3.0x）
- [ ] 外挂字幕（SRT/ASS/VTT）
- [ ] 后台播放 / 画中画
- [ ] 播放位置记忆（SwiftData）
- [ ] 手势控制完善

### 📅 P2 — 网盘生态
- [ ] WebDAV 完整支持
- [ ] HLS/RTMP 流播放
- [ ] 播放历史记录
- [ ] 收藏功能
- [ ] 搜索增强

### 🎯 P3 — Apple 生态整合
- [ ] iCloud 同步
- [ ] Apple TV 焦点导航 UI
- [ ] Shortcuts 集成
- [ ] AirPlay 支持
- [ ] 原生 FFmpeg 桥接

---

## 🧪 测试

```bash
# 运行所有测试
swift test

# 运行特定测试
swift test --filter MediaFileTests
swift test --filter SubtitleLoaderTests
swift test --filter PreferencesManagerTests
```

### CI/CD

GitHub Actions 自动执行：

| Job | 步骤 |
|-----|------|
| `lint` | SwiftLint + SwiftFormat 检查 |
| `build-ios` | iPhone 15 Pro Simulator 编译 |
| `build-macos` | macOS arm64 编译 |
| `build-tvos` | Apple TV 4K 编译 |
| `test` | 全平台单元测试 |
| `release` | 主分支 Release 打包 |

---

## 🤝 贡献指南

1. Fork 项目
2. 创建特性分支：`git checkout -b feature/amazing-feature`
3. 提交更改：`git commit -m 'Add amazing feature'`
4. 推送到分支：`git push origin feature/amazing-feature`
5. 创建 Pull Request

### 代码规范

- 遵循 Swift 命名规范（PascalCase 类型 / camelCase 属性）
- Actor 隔离所有 Service 层
- ViewModel 使用 `@Observable` 宏
- 错误类型实现 `LocalizedError`
- 添加单元测试覆盖

---

## 📄 许可证

MIT License © 2024 CloudPlayer Contributors

---

<div align="center">
  <sub>Built with ❤️ for the Alist community</sub>
</div>