import SwiftUI

// MARK: - visionOS Content View

/// visionOS 主视图
public struct visionOSContentView: View {
    @State private var browserViewModel = BrowserViewModel()
    @State private var playerViewModel: PlayerViewModel?
    @State private var settingsViewModel = SettingsViewModel()
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                visionOSFileBrowserView(
                    browserViewModel: browserViewModel,
                    playerViewModel: playerViewModel
                )
            }
            .tabItem {
                Label("浏览", systemImage: "folder")
            }
            .tag(0)

            NavigationStack {
                visionOSRecentsView(
                    playerViewModel: playerViewModel,
                    browserViewModel: browserViewModel
                )
            }
            .tabItem {
                Label("最近", systemImage: "clock")
            }
            .tag(1)

            NavigationStack {
                visionOSSettingsView(
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
            let playerVM = PlayerViewModel(browserViewModel: browserViewModel)
            playerViewModel = playerVM
        }
        .fullScreenCover(isPresented: Binding(
            get: { playerViewModel?.isPlayerPresented ?? false },
            set: { if !$0 { playerViewModel?.dismissPlayer() } }
        )) {
            if let playerViewModel = playerViewModel {
                visionOSPlayerView(playerViewModel: playerViewModel)
            }
        }
        .tint(.accentColor)
    }
}

// MARK: - visionOS File Browser

/// visionOS 文件浏览器
public struct visionOSFileBrowserView: View {
    @Bindable var browserViewModel: BrowserViewModel
    var playerViewModel: PlayerViewModel?
    @State private var searchText = ""

    public var body: some View {
        Group {
            if case .disconnected = browserViewModel.connectionState {
                visionOSConnectView(browserViewModel: browserViewModel)
            } else {
                VStack(spacing: 0) {
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

                    // 文件列表
                    if browserViewModel.state.isLoading {
                        LoadingView(message: "加载中...")
                    } else if let error = browserViewModel.state.error {
                        ErrorView(message: error) {
                            Task { await browserViewModel.refresh() }
                        }
                    } else if browserViewModel.state.files.isEmpty {
                        EmptyStateView(icon: "folder", title: "空目录", message: "此目录中没有文件")
                    } else {
                        List {
                            ForEach(browserViewModel.state.files) { file in
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
                    }
                }
            }
        }
        .navigationTitle(browserViewModel.connection?.name ?? "CloudPlayer")
        .searchable(text: $searchText, prompt: "搜索文件")
        .onSubmit(of: .search) {
            Task { await browserViewModel.search(keyword: searchText) }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if case .connected = browserViewModel.connectionState {
                    Button(action: {
                        browserViewModel.disconnect()
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
    }
}

// MARK: - visionOS Connect View

/// visionOS 连接界面
public struct visionOSConnectView: View {
    @Bindable var browserViewModel: BrowserViewModel
    @State private var serverURL = ""
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var selectedType: DriveSourceType = .alist
    @State private var isConnecting = false
    @State private var errorMessage: String?

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
                .padding(.top, 40)

            Text("CloudPlayer")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("连接 Alist 或 WebDAV 服务器\n浏览并播放媒体文件")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                Picker("类型", selection: $selectedType) {
                    ForEach(DriveSourceType.allCases.filter { $0 != .local }) { type in
                        Label(type.displayName, systemImage: type.iconName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                TextField("服务器地址", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                if selectedType == .alist {
                    TextField("Token（可选）", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                TextField("用户名（可选）", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                SecureField("密码（可选）", text: $password)
                    .textFieldStyle(.roundedBorder)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: connect) {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isConnecting ? "连接中..." : "连接")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isConnecting || serverURL.isEmpty)
                .buttonStyle(.borderedProminent)

                Button(action: {
                    Task { await browserViewModel.browseLocalFiles() }
                }) {
                    Label("浏览本地文件", systemImage: "internaldrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
            .frame(width: 400)
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

// MARK: - visionOS Recents

/// visionOS 最近播放
public struct visionOSRecentsView: View {
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
                    VStack(alignment: .leading) {
                        Text(record.mediaName)
                            .font(.headline)
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
            }
        }
        .navigationTitle("最近播放")
        .onAppear {
            records = playerViewModel?.getAllPlaybackRecords() ?? []
        }
    }
}

// MARK: - visionOS Settings

/// visionOS 设置视图
public struct visionOSSettingsView: View {
    @Bindable var settingsViewModel: SettingsViewModel
    var browserViewModel: BrowserViewModel

    public var body: some View {
        List {
            Section("服务器") {
                ForEach(settingsViewModel.connections) { connection in
                    HStack {
                        Image(systemName: connection.type.iconName)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(connection.name)
                            Text(connection.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("播放") {
                VStack(alignment: .leading) {
                    Text("默认速度: \(String(format: "%.1f", settingsViewModel.defaultPlaybackSpeed))x")
                    Slider(value: $settingsViewModel.defaultPlaybackSpeed, in: 0.25...3.0, step: 0.25)
                }
                Toggle("字幕", isOn: $settingsViewModel.subtitleEnabled)
            }

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
    }
}

// MARK: - visionOS Player View

/// visionOS 播放器视图
public struct visionOSPlayerView: View {
    @Bindable var playerViewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingControls = true

    public var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)
                .overlay {
                    // 字幕
                    if let subtitle = playerViewModel.activeSubtitle {
                        VStack {
                            Spacer()
                            Text(subtitle.text)
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                                .padding(.bottom, 80)
                        }
                    }
                }

            // 控制层
            if isShowingControls {
                VStack {
                    HStack {
                        Button(action: {
                            playerViewModel.dismissPlayer()
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding()

                    Spacer()

                    HStack(spacing: 32) {
                        Button(action: { playerViewModel.skipBackward() }) {
                            Image(systemName: "gobackward.10")
                                .font(.title)
                        }

                        Button(action: { playerViewModel.togglePlayPause() }) {
                            Image(systemName: playerViewModel.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                        }

                        Button(action: { playerViewModel.skipForward() }) {
                            Image(systemName: "goforward.10")
                                .font(.title)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { isShowingControls = false }
            }
        }
    }
}