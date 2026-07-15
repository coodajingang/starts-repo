import SwiftUI
import AVKit

// MARK: - iOS Player View

/// iOS 播放器视图
public struct iOSPlayerView: View {
    @Bindable var playerViewModel: PlayerViewModel
    @State private var isShowingControls = true
    @State private var controlsTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    // 使用 AVPlayer 的引用
    private var avPlayer: AVPlayer {
        // 通过 MediaPlayerService 获取 AVPlayer 实例
        // 这里使用一个共享的 AVPlayer
        AVPlayer.shared
    }

    public init(playerViewModel: PlayerViewModel) {
        self.playerViewModel = playerViewModel
    }

    public var body: some View {
        ZStack {
            // 视频播放层
            VideoPlayerView(
                state: playerViewModel.state,
                subtitleText: playerViewModel.activeSubtitle?.text
            )
            .edgesIgnoringSafeArea(.all)

            // 控制层
            if isShowingControls {
                PlaybackControlsView(
                    state: playerViewModel.state,
                    subtitleText: nil,
                    onPlayPause: { playerViewModel.togglePlayPause() },
                    onSkipBackward: { playerViewModel.skipBackward() },
                    onSkipForward: { playerViewModel.skipForward() },
                    onSeek: { playerViewModel.seek(to: $0) },
                    onDismiss: {
                        playerViewModel.dismissPlayer()
                        dismiss()
                    }
                )
                .transition(.opacity)
            }
        }
        .statusBarHidden(isShowingControls)
        .onAppear {
            startControlsTimer()
        }
        .onDisappear {
            controlsTask?.cancel()
        }
    }

    private func startControlsTimer() {
        controlsTask?.cancel()
        controlsTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                withAnimation {
                    isShowingControls = false
                }
            }
        }
    }
}

// MARK: - Video Player View

/// 视频播放视图（使用 AVPlayer）
public struct VideoPlayerView: UIViewRepresentable {
    let state: PlaybackState
    let subtitleText: String?

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // 在实际项目中，这里会添加 AVPlayerLayer
        // 由于 AVPlayer 无法直接通过 SwiftUI 完美集成，
        // 这里使用 AVPlayerViewController 或自定义 AVPlayerLayer
    }
}

// MARK: - AVPlayerViewController Representable

/// AVPlayerViewController 包装
public struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - AVPlayer Extension

extension AVPlayer {
    static let shared = AVPlayer()
}

// MARK: - Player View with AVKit

/// 使用 AVKit 的播放器视图
public struct AVKitPlayerView: View {
    @Bindable var playerViewModel: PlayerViewModel
    @State private var player = AVPlayer.shared

    public var body: some View {
        AVPlayerViewControllerRepresentable(player: player)
            .edgesIgnoringSafeArea(.all)
            .onDisappear {
                player.pause()
            }
    }
}