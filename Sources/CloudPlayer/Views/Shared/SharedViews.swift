import SwiftUI

// MARK: - File Row View

/// 文件列表行组件
public struct FileRowView: View {
    let file: MediaFile
    var onTap: (() -> Void)?
    var onPlay: (() -> Void)?

    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    public var body: some View {
        Button(action: {
            if file.isDirectory {
                onTap?()
            } else {
                onPlay?()
            }
        }) {
            HStack(spacing: 12) {
                // 图标
                iconView
                    .frame(width: 40, height: 40)
                    .background(file.isDirectory ? Color.accentColor.opacity(0.1) : Color.platformSecondaryBackground)
                    .cornerRadius(8)

                // 文件信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    if !file.isDirectory {
                        HStack(spacing: 8) {
                            Text(file.formattedSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let modified = file.modifiedAt {
                                Text(modified, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                if !file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(0.5)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        #endif
    }

    @ViewBuilder
    private var iconView: some View {
        if file.isDirectory {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundColor(.accentColor)
        } else {
            Image(systemName: file.mediaType.iconName)
                .font(.title3)
                .foregroundColor(iconColor)
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

// MARK: - Loading View

/// 加载状态视图
public struct LoadingView: View {
    let message: String

    public init(message: String = "加载中...") {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error View

/// 错误状态视图
public struct ErrorView: View {
    let message: String
    var retryAction: (() -> Void)?

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text("出错了")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let retryAction = retryAction {
                Button(action: retryAction) {
                    Label("重试", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View

/// 空状态视图
public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    public init(icon: String = "tray", title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text(title)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Connection Form View

/// 连接编辑表单
public struct ConnectionFormView: View {
    @Binding var name: String
    @Binding var url: String
    @Binding var type: DriveSourceType
    @Binding var username: String
    @Binding var password: String
    @Binding var token: String
    var isTesting: Bool
    var testResult: SettingsViewModel.ConnectionTestResult?
    var onTest: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void

    public var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section("基本信息") {
                    Picker("类型", selection: $type) {
                        ForEach(DriveSourceType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }

                    TextField("名称", text: $name)

                    TextField("服务器地址", text: $url)
                        #if !os(tvOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                        .placeholder(when: url.isEmpty) {
                            Text("https://example.com")
                                .foregroundColor(.secondary)
                        }
                }

                // 认证信息
                Section("认证") {
                    if type == .alist {
                        TextField("Token（可选）", text: $token)
                            #if !os(tvOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                    }

                    TextField("用户名（可选）", text: $username)
                        #if !os(tvOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif

                    SecureField("密码（可选）", text: $password)
                }

                // 测试连接
                Section {
                    Button(action: onTest) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isTesting ? "测试中..." : "测试连接")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isTesting || url.isEmpty)

                    if let result = testResult {
                        HStack {
                            switch result {
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("连接成功")
                                    .foregroundColor(.green)
                            case .failure(let error):
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle(type == .alist ? "添加 Alist" : "添加 WebDAV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: onSave)
                        .disabled(url.isEmpty)
                }
            }
        }
    }
}

// MARK: - Placeholder Modifier

extension View {
    func placeholder<Content: View>(when shouldShow: Bool, alignment: Alignment = .leading, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            if shouldShow {
                placeholder()
            }
            self
        }
    }
}

// MARK: - Media Info View

/// 媒体信息预览视图
public struct MediaInfoView: View {
    let file: MediaFile

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.name)
                .font(.headline)
                .lineLimit(2)

            if !file.isDirectory {
                HStack(spacing: 12) {
                    Label(file.formattedSize, systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let modified = file.modifiedAt {
                        Label(modified, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(file.fileExtension.uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

// MARK: - Playback Control Overlay

/// 播放控制覆盖层
public struct PlaybackControlsView: View {
    let state: PlaybackState
    let subtitleText: String?
    var onPlayPause: () -> Void
    var onSkipBackward: () -> Void
    var onSkipForward: () -> Void
    var onSeek: (Double) -> Void
    var onDismiss: () -> Void

    @State private var isShowingControls = true
    @State private var dragOffset: Double = 0

    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    public var body: some View {
        ZStack {
            // 点击切换控制层显示
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingControls.toggle()
                    }
                }

            // 控制层
            if isShowingControls {
                VStack {
                    // 顶部栏
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        #if os(tvOS)
                        .focusable()
                        #endif

                        Spacer()

                        Text(state.metadata?.title ?? "")
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer()

                    // 字幕显示
                    if let subtitleText = subtitleText, !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(.system(size: CGFloat(PreferencesManager.subtitleSize)))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 80)
                    }

                    // 底部控制栏
                    VStack(spacing: 8) {
                        // 进度条
                        ProgressSliderView(
                            currentTime: state.currentTime,
                            duration: state.duration,
                            onSeek: onSeek
                        )

                        // 时间显示
                        HStack {
                            Text(state.formattedCurrentTime)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text(state.formattedRemainingTime)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal)

                        // 控制按钮
                        HStack(spacing: 24) {
                            // 速度
                            Text("\(String(format: "%.1f", state.rate))x")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))

                            // 后退
                            Button(action: onSkipBackward) {
                                Image(systemName: "gobackward.10")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            #if os(tvOS)
                            .focusable()
                            #endif

                            // 播放/暂停
                            Button(action: onPlayPause) {
                                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                            }
                            #if os(tvOS)
                            .focusable()
                            .prefersDefaultFocus(true)
                            #endif

                            // 前进
                            Button(action: onSkipForward) {
                                Image(systemName: "goforward.10")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            #if os(tvOS)
                            .focusable()
                            #endif

                            // 音量
                            Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal)
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
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingControls.toggle()
            }
        }
    }
}

// MARK: - Progress Slider

/// 进度条滑块
public struct ProgressSliderView: View {
    let currentTime: Double
    let duration: Double
    var onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景条
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)
                    .cornerRadius(2)

                // 进度条
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(isDragging ? dragProgress : progress), height: 4)
                    .cornerRadius(2)

                // 拖动滑块
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(x: geometry.size.width * CGFloat(isDragging ? dragProgress : progress) - 6)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                dragProgress = max(0, min(1, value.location.x / geometry.size.width))
                            }
                            .onEnded { value in
                                isDragging = false
                                let time = dragProgress * duration
                                onSeek(time)
                            }
                    )
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .frame(height: 24)
    }
}

// MARK: - Speed Picker

/// 倍速选择器
public struct SpeedPickerView: View {
    @Binding var selectedSpeed: Float
    let speeds: [Float] = availablePlaybackSpeeds

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(speeds, id: \.self) { speed in
                    Button(action: {
                        selectedSpeed = speed
                    }) {
                        Text("\(String(format: "%.1f", speed))x")
                            .font(.caption)
                            .fontWeight(speed == selectedSpeed ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(speed == selectedSpeed ? Color.accentColor : Color.platformSecondaryBackground)
                            .foregroundColor(speed == selectedSpeed ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}