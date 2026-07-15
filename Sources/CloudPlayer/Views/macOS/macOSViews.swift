import SwiftUI

// MARK: - macOS Content View

/// macOS 主视图（使用 NavigationSplitView）
public struct macOSContentView: View {
    @State private var browserViewModel = BrowserViewModel()
    @State private var playerViewModel: PlayerViewModel?
    @State private var settingsViewModel = SettingsViewModel()
    @State private var sidebarSelection: SidebarItem? = .browse
    @State private var isShowingPlayer = false

    public enum SidebarItem: String, CaseIterable, Identifiable {
        case browse = "浏览"
        case recents = "最近播放"
        case settings = "设置"

        public var id: String { rawValue }

        var icon: String {
            switch self {
            case .browse: return "folder"
            case .recents: return "clock"
            case .settings: return "gear"
            }
        }
    }

    public init() {
        setupViewModels()
    }

    public var body: some View {
        NavigationSplitView {
            // 侧边栏
            List(SidebarItem.allCases, selection: $sidebarSelection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
            .navigationTitle("CloudPlayer")
        } content: {
            // 内容区域
            switch sidebarSelection {
            case .browse:
                macOSFileBrowserView(
                    browserViewModel: browserViewModel,
                    playerViewModel: playerViewModel
                )
            case .recents:
                macOSRecentsView(
                    playerViewModel: playerViewModel,
                    browserViewModel: browserViewModel
                )
            case .settings:
                macOSSettingsView(
                    settingsViewModel: settingsViewModel,
                    browserViewModel: browserViewModel
                )
            case nil:
                EmptyStateView(icon: "play.circle", title: "CloudPlayer", message: "选择一个功能开始使用")
            }
        } detail: {
            // 详情区域（播放器）
            if isShowingPlayer, let playerViewModel = playerViewModel {
                macOSPlayerView(playerViewModel: playerViewModel)
            } else {
                EmptyStateView(icon: "film", title: "选择文件播放", message: "从左侧浏览文件开始播放")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            let playerVM = PlayerViewModel(browserViewModel: browserViewModel)
            playerViewModel = playerVM
        }
        .onChange(of: playerViewModel?.isPlayerPresented ?? false) { _, newValue in
            isShowingPlayer = newValue
        }
    }

    private func setupViewModels() {
        // 初始化 ViewModel
    }
}

// MARK: - macOS File Browser

/// macOS 文件浏览器
public struct macOSFileBrowserView: View {
    @Bindable var browserViewModel: BrowserViewModel
    var playerViewModel: PlayerViewModel?
    @State private var searchText = ""
    @State private var isShowingConnectSheet = false

    public var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                if case .connected = browserViewModel.connectionState {
                    Button(action: { Task { await browserViewModel.navigateUp() } }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(browserViewModel.state.currentPath.isEmpty)

                    Button(action: { Task { await browserViewModel.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                Spacer()

                if case .disconnected = browserViewModel.connectionState {
                    Button("连接服务器") {
                        isShowingConnectSheet = true
                    }
                } else if case .connected = browserViewModel.connectionState {
                    Button("断开") {
                        browserViewModel.disconnect()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // 面包屑
            if !browserViewModel.state.breadcrumbs.isEmpty {
                BreadcrumbBar(
                    breadcrumbs: browserViewModel.state.breadcrumbs,
                    currentPath: browserViewModel.state.currentPath,
                    onNavigate: { path in
                        Task { await browserViewModel.navigateToPath(path) }
                    },
                    onNavigateUp: {
                        Task { await browserViewModel.navigateUp() }
                    }
                )
            }

            // 内容
            if case .disconnected = browserViewModel.connectionState {
                macConnectView
            } else if browserViewModel.state.isLoading {
                LoadingView(message: "加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = browserViewModel.state.error {
                ErrorView(message: error) {
                    Task { await browserViewModel.refresh() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let files = searchText.isEmpty ? browserViewModel.state.files : browserViewModel.searchResults
                if files.isEmpty {
                    EmptyStateView(icon: "folder", title: "空目录", message: "此目录中没有文件")
                } else {
                    List(files) { file in
                        FileRowView(
                            file: file,
                            onTap: {
                                Task { await browserViewModel.navigateToDirectory(file) }
                            },
                            onPlay: {
                                if let connection = browserViewModel.connection,
                                   let playerVM = playerViewModel {
                                    playerVM.play(file: file, source: connection)
                                }
                            }
                        )
                    }
                    .listStyle(.inset)
                }
            }
        }
        .navigationTitle(browserViewModel.connection?.name ?? "文件浏览器")
        .searchable(text: $searchText, prompt: "搜索文件")
        .onSubmit(of: .search) {
            Task { await browserViewModel.search(keyword: searchText) }
        }
        .sheet(isPresented: $isShowingConnectSheet) {
            macConnectSheetView(browserViewModel: browserViewModel)
        }
    }

    private var macConnectView: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("CloudPlayer")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("连接 Alist 或 WebDAV 服务器，浏览并播放媒体文件")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("连接服务器") {
                isShowingConnectSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()
                .frame(width: 200)

            Button("浏览本地文件") {
                Task { await browserViewModel.browseLocalFiles() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func macConnectSheetView(browserViewModel: BrowserViewModel) -> some View {
        ConnectView(
            browserViewModel: browserViewModel,
            isShowingFilePicker: .constant(false)
        )
        .frame(width: 400, height: 500)
    }
}

// MARK: - macOS Recents

/// macOS 最近播放
public struct macOSRecentsView: View {
    var playerViewModel: PlayerViewModel?
    var browserViewModel: BrowserViewModel
    @State private var records: [PlaybackRecord] = []

    public var body: some View {
        Group {
            if records.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "暂无播放记录",
                    message: "播放视频后，记录会出现在这里"
                )
            } else {
                List(records.sorted(by: { $0.lastPlayedAt > $1.lastPlayedAt })) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.mediaName)
                                .font(.headline)
                            Text(record.sourceName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("\(Int(record.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(record.lastPlayedAt, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("最近播放")
        .onAppear {
            records = playerViewModel?.getAllPlaybackRecords() ?? []
        }
        .toolbar {
            ToolbarItem {
                Button("清除记录") {
                    playerViewModel?.clearPlaybackRecords()
                    records = []
                }
            }
        }
    }
}

// MARK: - macOS Settings

/// macOS 设置视图
public struct macOSSettingsView: View {
    @Bindable var settingsViewModel: SettingsViewModel
    var browserViewModel: BrowserViewModel
    @State private var isAddingConnection = false

    public var body: some View {
        TabView {
            // 服务器
            Form {
                Section("服务器连接") {
                    if settingsViewModel.connections.isEmpty {
                        Text("暂无已保存的服务器")
                            .foregroundColor(.secondary)
                    }

                    ForEach(settingsViewModel.connections) { connection in
                        HStack {
                            Image(systemName: connection.type.iconName)
                                .foregroundColor(.accentColor)
                            Text(connection.name)
                            Text(connection.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("删除") {
                                settingsViewModel.deleteConnection(connection)
                            }
                        }
                    }

                    Button("添加服务器") {
                        isAddingConnection = true
                    }
                }
            }
            .tabItem {
                Label("服务器", systemImage: "server.rack")
            }

            // 播放
            Form {
                VStack(alignment: .leading) {
                    Text("默认播放速度: \(String(format: "%.1f", settingsViewModel.defaultPlaybackSpeed))x")
                    Slider(value: $settingsViewModel.defaultPlaybackSpeed, in: 0.25...3.0, step: 0.25)
                }

                Toggle("默认开启字幕", isOn: $settingsViewModel.subtitleEnabled)

                HStack {
                    Text("字幕大小: \(settingsViewModel.subtitleSize)")
                    Stepper("", value: $settingsViewModel.subtitleSize, in: 12...48)
                }
            }
            .tabItem {
                Label("播放", systemImage: "play")
            }

            // 外观
            Form {
                Picker("主题", selection: $settingsViewModel.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            .tabItem {
                Label("外观", systemImage: "paintbrush")
            }

            // 高级
            Form {
                Button("清除播放记录") {
                    settingsViewModel.clearAllPlaybackRecords()
                }

                Button("清除所有缓存") {
                    settingsViewModel.clearAllCaches()
                }

                Divider()

                HStack {
                    Text("版本")
                    Spacer()
                    Text("\(settingsViewModel.appVersion) (\(settingsViewModel.appBuild))")
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("高级", systemImage: "gearshape.2")
            }
        }
        .navigationTitle("设置")
        .frame(width: 500, height: 400)
        .sheet(isPresented: $isAddingConnection) {
            ConnectionFormView(
                name: $settingsViewModel.newConnectionName,
                url: $settingsViewModel.newConnectionURL,
                type: $settingsViewModel.newConnectionType,
                username: $settingsViewModel.newConnectionUsername,
                password: $settingsViewModel.newConnectionPassword,
                token: $settingsViewModel.newConnectionToken,
                isTesting: settingsViewModel.isTestingConnection,
                testResult: settingsViewModel.connectionTestResult,
                onTest: {
                    Task {
                        await settingsViewModel.testConnection(
                            url: settingsViewModel.newConnectionURL,
                            type: settingsViewModel.newConnectionType,
                            username: settingsViewModel.newConnectionUsername,
                            password: settingsViewModel.newConnectionPassword,
                            token: settingsViewModel.newConnectionToken
                        )
                    }
                },
                onSave: {
                    Task { await settingsViewModel.addConnection() }
                    isAddingConnection = false
                },
                onCancel: {
                    settingsViewModel.resetConnectionForm()
                    isAddingConnection = false
                }
            )
            .frame(width: 400, height: 500)
        }
    }
}

// MARK: - macOS Player View

/// macOS 播放器视图
public struct macOSPlayerView: View {
    @Bindable var playerViewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        ZStack {
            // 视频播放区域
            Color.black
                .overlay {
                    if let subtitle = playerViewModel.activeSubtitle {
                        Text(subtitle.text)
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                            .padding(.bottom, 60)
                    }
                }

            // 控制栏
            VStack {
                Spacer()

                // 播放控制
                HStack(spacing: 16) {
                    Button(action: { playerViewModel.skipBackward() }) {
                        Image(systemName: "gobackward.10")
                    }

                    Button(action: { playerViewModel.togglePlayPause() }) {
                        Image(systemName: playerViewModel.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                    }

                    Button(action: { playerViewModel.skipForward() }) {
                        Image(systemName: "goforward.10")
                    }

                    // 进度
                    Slider(
                        value: Binding(
                            get: { playerViewModel.state.currentTime },
                            set: { playerViewModel.seek(to: $0) }
                        ),
                        in: 0...max(playerViewModel.state.duration, 1)
                    )

                    Text(playerViewModel.state.formattedCurrentTime)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 速度
                    Picker("速度", selection: Binding(
                        get: { playerViewModel.state.rate },
                        set: { playerViewModel.setPlaybackRate($0) }
                    )) {
                        ForEach(availablePlaybackSpeeds, id: \.self) { speed in
                            Text("\(String(format: "%.1f", speed))x").tag(speed)
                        }
                    }
                    .frame(width: 80)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(playerViewModel.currentMediaFile?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("关闭") {
                    playerViewModel.dismissPlayer()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}