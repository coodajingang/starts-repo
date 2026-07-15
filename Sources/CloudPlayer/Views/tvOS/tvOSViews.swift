import SwiftUI

// MARK: - tvOS Content View

/// tvOS 主视图（焦点导航）
public struct tvOSContentView: View {
    @State private var browserViewModel = BrowserViewModel()
    @State private var playerViewModel: PlayerViewModel?
    @State private var settingsViewModel = SettingsViewModel()
    @State private var selectedSection: TVSection = .browse

    public enum TVSection: String, CaseIterable, Identifiable {
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

    public init() {}

    public var body: some View {
        TabView(selection: $selectedSection) {
            tvOSFileBrowserView(
                browserViewModel: browserViewModel,
                playerViewModel: playerViewModel
            )
            .tabItem {
                Label("浏览", systemImage: "folder")
            }
            .tag(TVSection.browse)

            tvOSRecentsView(
                playerViewModel: playerViewModel,
                browserViewModel: browserViewModel
            )
            .tabItem {
                Label("最近", systemImage: "clock")
            }
            .tag(TVSection.recents)

            tvOSSettingsView(
                settingsViewModel: settingsViewModel,
                browserViewModel: browserViewModel
            )
            .tabItem {
                Label("设置", systemImage: "gear")
            }
            .tag(TVSection.settings)
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
                tvOSPlayerView(playerViewModel: playerViewModel)
            }
        }
    }
}

// MARK: - tvOS File Browser

/// tvOS 文件浏览器
public struct tvOSFileBrowserView: View {
    @Bindable var browserViewModel: BrowserViewModel
    var playerViewModel: PlayerViewModel?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    public var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text(browserViewModel.connection?.name ?? "CloudPlayer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                if case .connected = browserViewModel.connectionState {
                    Button(action: {
                        browserViewModel.disconnect()
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)
            .padding(.bottom, 20)

            // 搜索
            if case .connected = browserViewModel.connectionState {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索文件", text: $searchText)
                        .focused($isSearchFocused)
                        .onSubmit {
                            Task { await browserViewModel.search(keyword: searchText) }
                        }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 20)
            }

            // 连接状态
            if case .disconnected = browserViewModel.connectionState {
                tvOSConnectView(browserViewModel: browserViewModel)
            } else if case .connecting = browserViewModel.connectionState {
                ProgressView("连接中...")
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .error(let msg) = browserViewModel.connectionState {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)
                    Text(msg)
                        .font(.title3)
                    Button("重试") {
                        Task { await browserViewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 文件列表
                tvOSFileList(
                    browserViewModel: browserViewModel,
                    playerViewModel: playerViewModel
                )
            }
        }
        .background(Color.black)
    }
}

// MARK: - tvOS File List

/// tvOS 文件列表
public struct tvOSFileList: View {
    @Bindable var browserViewModel: BrowserViewModel
    var playerViewModel: PlayerViewModel?

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 40)
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // 面包屑
            if !browserViewModel.state.breadcrumbs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task { await browserViewModel.navigateToPath("") }
                        }) {
                            Image(systemName: "house")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        ForEach(Array(browserViewModel.state.breadcrumbs.enumerated()), id: \.offset) { index, component in
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            let path = browserViewModel.state.breadcrumbs[0...index].joined(separator: "/")
                            Button(action: {
                                Task { await browserViewModel.navigateToPath(path) }
                            }) {
                                Text(component)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 20)
                }
            }

            // 文件网格
            ScrollView {
                if browserViewModel.state.isLoading {
                    ProgressView("加载中...")
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                } else if browserViewModel.state.files.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "folder")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                        Text("空目录")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 400)
                } else {
                    LazyVGrid(columns: columns, spacing: 40) {
                        // 返回上级
                        if !browserViewModel.state.currentPath.isEmpty {
                            Button(action: {
                                Task { await browserViewModel.navigateUp() }
                            }) {
                                VStack(spacing: 16) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 48))
                                    Text("返回上级")
                                        .font(.title3)
                                }
                                .frame(width: 280, height: 200)
                                .background(Color.platformSecondaryBackground)
                                .cornerRadius(16)
                            }
                            .buttonStyle(.card)
                        }

                        // 文件
                        ForEach(browserViewModel.state.files) { file in
                            Button(action: {
                                if file.isDirectory {
                                    Task { await browserViewModel.navigateToDirectory(file) }
                                } else if let connection = browserViewModel.connection,
                                          let playerVM = playerViewModel {
                                    playerVM.play(file: file, source: connection)
                                }
                            }) {
                                tvOSFileCard(file: file)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 60)
                }
            }
        }
    }
}

// MARK: - tvOS File Card

/// tvOS 文件卡片
public struct tvOSFileCard: View {
    let file: MediaFile

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(file.isDirectory ? Color.accentColor.opacity(0.2) : Color.platformSecondaryBackground)

                Image(systemName: file.isDirectory ? "folder.fill" : file.mediaType.iconName)
                    .font(.system(size: 48))
                    .foregroundColor(file.isDirectory ? .accentColor : iconColor)
            }
            .frame(width: 280, height: 160)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.title3)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !file.isDirectory {
                    Text(file.formattedSize)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 280, alignment: .leading)
        }
    }

    private var iconColor: Color {
        switch file.mediaType {
        case .video: return .blue
        case .audio: return .orange
        case .subtitle: return .green
        case .image: return .purple
        case .unknown: return .gray
        }
    }
}

// MARK: - tvOS Connect View

/// tvOS 连接界面
public struct tvOSConnectView: View {
    @Bindable var browserViewModel: BrowserViewModel
    @State private var serverURL = ""
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var selectedType: DriveSourceType = .alist
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field {
        case url, token, username, password, connect, local
    }

    public var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.accentColor)

            Text("CloudPlayer")
                .font(.system(size: 48, weight: .bold))

            Text("连接 Alist 或 WebDAV 服务器\n浏览并播放媒体文件")
                .font(.title2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // 连接表单
            VStack(spacing: 24) {
                // 类型选择
                Picker("类型", selection: $selectedType) {
                    ForEach(DriveSourceType.allCases.filter { $0 != .local }) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 400)

                // URL
                TextField("服务器地址", text: $serverURL)
                    .focused($focusedField, equals: .url)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 500)

                if selectedType == .alist {
                    TextField("Token（可选）", text: $token)
                        .focused($focusedField, equals: .token)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 500)
                }

                TextField("用户名（可选）", text: $username)
                    .focused($focusedField, equals: .username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 500)

                SecureField("密码（可选）", text: $password)
                    .focused($focusedField, equals: .password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 500)

                // 错误信息
                if let error = errorMessage {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                }

                // 连接按钮
                Button(action: connect) {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isConnecting ? "连接中..." : "连接")
                            .font(.title2)
                    }
                    .frame(width: 300, height: 60)
                }
                .focused($focusedField, equals: .connect)
                .disabled(isConnecting || serverURL.isEmpty)
                .buttonStyle(.borderedProminent)

                // 本地文件
                Button(action: {
                    Task { await browserViewModel.browseLocalFiles() }
                }) {
                    Label("浏览本地文件", systemImage: "internaldrive")
                        .font(.title2)
                        .frame(width: 300, height: 60)
                }
                .focused($focusedField, equals: .local)
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - tvOS Recents

/// tvOS 最近播放
public struct tvOSRecentsView: View {
    var playerViewModel: PlayerViewModel?
    var browserViewModel: BrowserViewModel
    @State private var records: [PlaybackRecord] = []

    public var body: some View {
        VStack(spacing: 20) {
            Text("最近播放")
                .font(.largeTitle)
                .fontWeight(.bold)

            if records.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "clock")
                        .font(.system(size: 80))
                        .foregroundColor(.secondary)
                    Text("暂无播放记录")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(records.sorted(by: { $0.lastPlayedAt > $1.lastPlayedAt })) { record in
                            Button(action: {
                                // 恢复播放
                            }) {
                                HStack(spacing: 24) {
                                    Image(systemName: "film")
                                        .font(.title)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 60)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.mediaName)
                                            .font(.title2)
                                            .lineLimit(1)
                                        Text(record.sourceName)
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing) {
                                        Text("\(Int(record.progress * 100))%")
                                            .font(.title3)
                                            .foregroundColor(.accentColor)
                                        ProgressView(value: record.progress)
                                            .frame(width: 100)
                                    }
                                }
                                .padding(.horizontal, 40)
                                .padding(.vertical, 16)
                                .background(Color.platformSecondaryBackground)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
        }
        .padding(.top, 40)
        .onAppear {
            records = playerViewModel?.getAllPlaybackRecords() ?? []
        }
    }
}

// MARK: - tvOS Settings

/// tvOS 设置视图
public struct tvOSSettingsView: View {
    @Bindable var settingsViewModel: SettingsViewModel
    var browserViewModel: BrowserViewModel

    public var body: some View {
        VStack(spacing: 30) {
            Text("设置")
                .font(.largeTitle)
                .fontWeight(.bold)

            ScrollView {
                VStack(spacing: 24) {
                    // 服务器
                    SectionView(title: "服务器") {
                        ForEach(settingsViewModel.connections) { connection in
                            HStack {
                                Image(systemName: connection.type.iconName)
                                    .foregroundColor(.accentColor)
                                Text(connection.name)
                                    .font(.title3)
                                Spacer()
                                Text(connection.url)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.platformSecondaryBackground)
                            .cornerRadius(12)
                        }
                    }

                    // 播放
                    SectionView(title: "播放") {
                        VStack(spacing: 16) {
                            HStack {
                                Text("默认速度")
                                    .font(.title3)
                                Spacer()
                                Picker("", selection: $settingsViewModel.defaultPlaybackSpeed) {
                                    ForEach(availablePlaybackSpeeds, id: \.self) { speed in
                                        Text("\(String(format: "%.1f", speed))x").tag(speed)
                                    }
                                }
                                .frame(width: 200)
                            }

                            Toggle("字幕", isOn: $settingsViewModel.subtitleEnabled)
                                .font(.title3)
                        }
                        .padding()
                        .background(Color.platformSecondaryBackground)
                        .cornerRadius(12)
                    }

                    // 关于
                    SectionView(title: "关于") {
                        HStack {
                            Text("版本")
                                .font(.title3)
                            Spacer()
                            Text("\(settingsViewModel.appVersion) (\(settingsViewModel.appBuild))")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.platformSecondaryBackground)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 60)
            }
        }
        .padding(.top, 40)
    }
}

// MARK: - Section View

/// tvOS 分组视图
public struct SectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.leading, 4)

            content
        }
    }
}

// MARK: - tvOS Player View

/// tvOS 播放器视图
public struct tvOSPlayerView: View {
    @Bindable var playerViewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingControls = true

    public var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            // 字幕
            if let subtitle = playerViewModel.activeSubtitle {
                VStack {
                    Spacer()
                    Text(subtitle.text)
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 100)
                        .padding(.bottom, 100)
                }
            }

            // 控制层
            if isShowingControls {
                VStack {
                    // 顶部栏
                    HStack {
                        Button(action: {
                            playerViewModel.dismissPlayer()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.title)
                                .padding(16)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(playerViewModel.currentMediaFile?.name ?? "")
                            .font(.title2)
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                    Spacer()

                    // 底部控制栏
                    VStack(spacing: 16) {
                        // 进度条
                        ProgressSliderView(
                            currentTime: playerViewModel.state.currentTime,
                            duration: playerViewModel.state.duration,
                            onSeek: { playerViewModel.seek(to: $0) }
                        )

                        HStack {
                            Text(playerViewModel.state.formattedCurrentTime)
                            Spacer()
                            Text(playerViewModel.state.formattedRemainingTime)
                        }
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))

                        // 控制按钮
                        HStack(spacing: 40) {
                            Button(action: { playerViewModel.skipBackward(seconds: 15) }) {
                                Image(systemName: "gobackward.15")
                                    .font(.title)
                            }

                            Button(action: { playerViewModel.togglePlayPause() }) {
                                Image(systemName: playerViewModel.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 60))
                            }

                            Button(action: { playerViewModel.skipForward(seconds: 15) }) {
                                Image(systemName: "goforward.15")
                                    .font(.title)
                            }
                        }
                        .foregroundColor(.white)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 40)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            // 自动隐藏控制层
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    isShowingControls = false
                }
            }
        }
        .onPlayPauseCommand {
            playerViewModel.togglePlayPause()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                playerViewModel.skipBackward(seconds: 15)
            case .right:
                playerViewModel.skipForward(seconds: 15)
            default:
                break
            }
        }
    }
}