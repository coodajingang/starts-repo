import SwiftUI

// MARK: - CloudPlayer App

/// CloudPlayer 主入口
/// 按平台路由到对应的 ContentView
/// 初始化 SwiftData、GCDWebServer、FFmpeg 等服务
@main
public struct CloudPlayerApp: App {
    @State private var isInitialized = false

    public init() {}

    public var body: some Scene {
        #if os(macOS)
        WindowGroup {
            content
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await initializeServices()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            macOSSettingsView(
                settingsViewModel: SettingsViewModel(),
                browserViewModel: BrowserViewModel()
            )
            .frame(width: 500, height: 400)
        }
        #elseif os(tvOS)
        WindowGroup {
            content
                .task {
                    await initializeServices()
                }
        }
        #elseif os(visionOS)
        WindowGroup {
            content
                .task {
                    await initializeServices()
                }
        }
        #else
        // iOS (iPhone & iPad)
        WindowGroup {
            content
                .task {
                    await initializeServices()
                }
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if isInitialized {
            #if os(macOS)
            macOSContentView()
            #elseif os(tvOS)
            tvOSContentView()
            #elseif os(visionOS)
            visionOSContentView()
            #else
            iOSContentView()
            #endif
        } else {
            SplashView()
        }
    }

    /// 初始化所有后台服务
    private func initializeServices() async {
        // 1. 初始化 SwiftData
        await MainActor.run {
            SwiftDataManager.shared.setup(cloudSync: false)

            #if DEBUG
            // 开发环境从 UserDefaults 迁移数据
            SwiftDataManager.shared.migrateFromUserDefaults()
            #endif
        }

        // 2. 启动 GCDWebServer 代理服务
        do {
            try await ProxyServiceIntegration.shared.start(port: 9898)
        } catch {
            print("[CloudPlayerApp] GCDWebServer start failed: \(error)")
        }

        // 3. 初始化 FFmpeg 服务
        let ffmpegService = FFmpegService()
        _ = ffmpegService // 预初始化

        // 4. 配置音频会话
        #if os(iOS) || os(tvOS) || os(visionOS)
        configureAudioSession()
        #endif

        await MainActor.run {
            isInitialized = true
        }
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .longFormVideo,
                options: [.allowAirPlay, .allowBluetoothA2DP, .allowBluetooth]
            )
            try session.setActive(true)
        } catch {
            print("[CloudPlayerApp] Audio session config failed: \(error)")
        }
    }
    #endif
}

// MARK: - Splash View

/// 启动画面
public struct SplashView: View {
    @State private var isAnimating = false

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)

            Text("CloudPlayer")
                .font(.largeTitle)
                .fontWeight(.bold)

            ProgressView()
                .scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformBackground)
        .onAppear {
            isAnimating = true
        }
    }
}