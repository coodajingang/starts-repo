import SwiftUI

// MARK: - iOS Content View

/// iOS 主视图
public struct iOSContentView: View {
    @State private var browserViewModel = BrowserViewModel()
    @State private var playerViewModel: PlayerViewModel?
    @State private var settingsViewModel = SettingsViewModel()
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FileBrowserView(
                    browserViewModel: browserViewModel,
                    playerViewModel: playerViewModel
                )
            }
            .tabItem {
                Label("浏览", systemImage: "folder")
            }
            .tag(0)

            NavigationStack {
                RecentsView(
                    playerViewModel: playerViewModel,
                    browserViewModel: browserViewModel
                )
            }
            .tabItem {
                Label("最近", systemImage: "clock")
            }
            .tag(1)

            NavigationStack {
                SettingsView(
                    settingsViewModel: settingsViewModel,
                    browserViewModel: browserViewModel
                )
            }
            .tabItem {
                Label("设置", systemImage: "gear")
            }
            .tag(2)
        }
        .onAppear {
            setupViewModels()
        }
        .fullScreenCover(isPresented: Binding(
            get: { playerViewModel?.isPlayerPresented ?? false },
            set: { if !$0 { playerViewModel?.dismissPlayer() } }
        )) {
            if let playerViewModel = playerViewModel {
                iOSPlayerView(playerViewModel: playerViewModel)
            }
        }
        .tint(.accentColor)
    }

    private func setupViewModels() {
        let playerVM = PlayerViewModel(browserViewModel: browserViewModel)
        playerViewModel = playerVM
    }
}

// MARK: - File Browser View

/// iOS 文件浏览器
public struct FileBrowserView: View {
    @Bindable var browserViewModel: BrowserViewModel
    var playerViewModel: PlayerViewModel?
    @State private var searchText = ""
    @State private var isShowingConnections = false
    @State private var isShowingFilePicker = false

    public var body: some View {
        Group {
            if case .disconnected = browserViewModel.connectionState {
                // 未连接状态
                ConnectView(
                    browserViewModel: browserViewModel,
                    isShowingFilePicker: $isShowingFilePicker
                )
            } else {
                // 文件列表
                fileListView
            }
        }
        .navigationTitle(browserViewModel.connection?.name ?? "CloudPlayer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if case .connected = browserViewModel.connectionState {
                    HStack(spacing: 4) {
                        Button(action: {
                            Task { await browserViewModel.refresh() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }

                        Button(action: {
                            browserViewModel.disconnect()
                        }) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索文件")
        .onSubmit(of: .search) {
            Task { await browserViewModel.search(keyword: searchText) }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                browserViewModel.clearSearch()
            }
        }
        .sheet(isPresented: $isShowingConnections) {
            ConnectionsListView(
                browserViewModel: browserViewModel,
                settingsViewModel: SettingsViewModel()
            )
        }
    }

    private var fileListView: some View {
        VStack(spacing: 0) {
            // 面包屑导航
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

            // 文件列表
            if browserViewModel.state.isLoading {
                LoadingView(message: "加载中...")
            } else if let error = browserViewModel.state.error {
                ErrorView(message: error) {
                    Task { await browserViewModel.refresh() }
                }
            } else if browserViewModel.searchResults.isEmpty && !searchText.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "未找到结果", message: "尝试其他关键词")
            } else {
                let files = searchText.isEmpty ? browserViewModel.state.files : browserViewModel.searchResults
                if files.isEmpty {
                    EmptyStateView(icon: "folder", title: "空目录", message: "此目录中没有文件")
                } else {
                    List {
                        // 返回上级
                        if !browserViewModel.state.currentPath.isEmpty {
                            Button(action: {
                                Task { await browserViewModel.navigateUp() }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up")
                                    Text("返回上级")
                                }
                            }
                            .foregroundColor(.accentColor)
                        }

                        ForEach(files) { file in
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
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await browserViewModel.refresh()
                    }
                }
            }
        }
    }
}

// MARK: - Breadcrumb Bar

/// 面包屑导航栏
public struct BreadcrumbBar: View {
    let breadcrumbs: [String]
    let currentPath: String
    var onNavigate: (String) -> Void
    var onNavigateUp: () -> Void

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: onNavigateUp) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .foregroundColor(.accentColor)

                Image(systemName: "house")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .onTapGesture {
                        onNavigate("")
                    }

                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    let path = breadcrumbs[0...index].joined(separator: "/")
                    Text(component)
                        .font(.caption)
                        .foregroundColor(index == breadcrumbs.count - 1 ? .primary : .accentColor)
                        .onTapGesture {
                            onNavigate(path)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.platformSecondaryBackground)
    }
}

// MARK: - Connect View

/// 连接界面
public struct ConnectView: View {
    @Bindable var browserViewModel: BrowserViewModel
    @Binding var isShowingFilePicker: Bool
    @State private var serverURL = ""
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var selectedType: DriveSourceType = .alist
    @State private var isConnecting = false
    @State private var errorMessage: String?

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Logo
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.accentColor)
                    .padding(.top, 40)

                Text("CloudPlayer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("连接你的 Alist 或 WebDAV 服务器\n浏览并播放媒体文件")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // 连接表单
                VStack(spacing: 16) {
                    Picker("服务器类型", selection: $selectedType) {
                        ForEach(DriveSourceType.allCases.filter { $0 != .local }) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("服务器地址", text: $serverURL)
                        #if !os(tvOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                        .textFieldStyle(.roundedBorder)

                    if selectedType == .alist {
                        TextField("Token（可选）", text: $token)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("用户名（可选）", text: $username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    SecureField("密码（可选）", text: $password)
                        .textFieldStyle(.roundedBorder)

                    // 连接按钮
                    Button(action: connect) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isConnecting ? "连接中..." : "连接")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .disabled(isConnecting || serverURL.isEmpty)
                    .buttonStyle(.borderedProminent)

                    // 错误信息
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)

                // 本地文件入口
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal, 32)

                    Text("或者")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        Task { await browserViewModel.browseLocalFiles() }
                    }) {
                        Label("浏览本地文件", systemImage: "internaldrive")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 32)
            }
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        Task {
            switch selectedType {
            case .alist:
                if !token.isEmpty {
                    await browserViewModel.connectToAlist(url: serverURL, token: token)
                } else {
                    await browserViewModel.connectToAlist(url: serverURL, username: username, password: password)
                }
            case .webdav:
                await browserViewModel.connectToWebDAV(url: serverURL, username: username, password: password)
            case .local:
                await browserViewModel.browseLocalFiles()
            }

            isConnecting = false

            if case .error(let msg) = browserViewModel.connectionState {
                errorMessage = msg
            }
        }
    }
}

// MARK: - Recents View

/// 最近播放视图
public struct RecentsView: View {
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
                List {
                    ForEach(records.sorted(by: { $0.lastPlayedAt > $1.lastPlayedAt })) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.mediaName)
                                .font(.headline)
                                .lineLimit(1)

                            HStack {
                                Text(record.sourceName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(record.progress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }

                            ProgressView(value: record.progress)
                                .tint(.accentColor)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        records.remove(atOffsets: indexSet)
                    }
                }
            }
        }
        .navigationTitle("最近播放")
        .onAppear {
            records = playerViewModel?.getAllPlaybackRecords() ?? []
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !records.isEmpty {
                    Button("清除") {
                        playerViewModel?.clearPlaybackRecords()
                        records = []
                    }
                }
            }
        }
    }
}

// MARK: - Settings View

/// 设置视图
public struct SettingsView: View {
    @Bindable var settingsViewModel: SettingsViewModel
    var browserViewModel: BrowserViewModel
    @State private var isAddingConnection = false

    public var body: some View {
        List {
            // 服务器连接
            Section("服务器") {
                if settingsViewModel.connections.isEmpty {
                    Text("暂无已保存的服务器")
                        .foregroundColor(.secondary)
                }

                ForEach(settingsViewModel.connections) { connection in
                    HStack {
                        Image(systemName: connection.type.iconName)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(connection.name)
                                .font(.body)
                            Text(connection.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            settingsViewModel.deleteConnection(connection)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }

                Button(action: { isAddingConnection = true }) {
                    Label("添加服务器", systemImage: "plus")
                }
            }

            // 播放设置
            Section("播放") {
                VStack(alignment: .leading) {
                    Text("默认播放速度")
                    HStack {
                        Slider(value: $settingsViewModel.defaultPlaybackSpeed, in: 0.25...3.0, step: 0.25)
                        Text("\(String(format: "%.1f", settingsViewModel.defaultPlaybackSpeed))x")
                            .font(.caption)
                            .frame(width: 40)
                    }
                }

                Toggle("默认字幕", isOn: $settingsViewModel.subtitleEnabled)

                HStack {
                    Text("字幕大小")
                    Spacer()
                    Stepper("\(settingsViewModel.subtitleSize)", value: $settingsViewModel.subtitleSize, in: 12...48)
                }

                Toggle("后台播放", isOn: $settingsViewModel.backgroundPlayback)
            }

            // 外观
            Section("外观") {
                Picker("主题", selection: $settingsViewModel.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            // 缓存
            Section("缓存") {
                Button("清除播放记录", role: .destructive) {
                    settingsViewModel.clearAllPlaybackRecords()
                }

                Button("清除所有缓存", role: .destructive) {
                    settingsViewModel.clearAllCaches()
                }
            }

            // 关于
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("\(settingsViewModel.appVersion) (\(settingsViewModel.appBuild))")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("设置")
        .sheet(isPresented: $isAddingConnection) {
            NavigationStack {
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
            }
        }
    }
}

// MARK: - Connections List

/// 连接列表
public struct ConnectionsListView: View {
    var browserViewModel: BrowserViewModel
    var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                if settingsViewModel.connections.isEmpty {
                    Text("暂无已保存的连接")
                        .foregroundColor(.secondary)
                }

                ForEach(settingsViewModel.connections) { connection in
                    Button(action: {
                        connect(to: connection)
                    }) {
                        HStack {
                            Image(systemName: connection.type.iconName)
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(connection.name)
                                    .font(.body)
                                Text(connection.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("选择服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func connect(to connection: DriveConnection) {
        dismiss()
        Task {
            switch connection.type {
            case .alist:
                if let token = connection.token, !token.isEmpty {
                    await browserViewModel.connectToAlist(url: connection.url, token: token)
                } else {
                    await browserViewModel.connectToAlist(url: connection.url, username: connection.username, password: connection.password)
                }
            case .webdav:
                await browserViewModel.connectToWebDAV(url: connection.url, username: connection.username, password: connection.password)
            case .local:
                await browserViewModel.browseLocalFiles()
            }
        }
    }
}