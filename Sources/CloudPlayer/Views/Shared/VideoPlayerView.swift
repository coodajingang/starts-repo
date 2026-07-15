import SwiftUI
import AVFoundation
import AVKit

// MARK: - Custom Video Player View

/// 使用 AVPlayerLayer 的完整视频播放视图
/// 支持手势控制、字幕叠加、自动布局
public struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity
    @Binding var isControlsVisible: Bool
    let subtitleText: String?

    public init(
        player: AVPlayer,
        gravity: AVLayerVideoGravity = .resizeAspect,
        isControlsVisible: Binding<Bool> = .constant(true),
        subtitleText: String? = nil
    ) {
        self.player = player
        self.gravity = gravity
        self._isControlsVisible = isControlsVisible
        self.subtitleText = subtitleText
    }

    public func makeUIView(context: Context) -> VideoPlayerUIView {
        let view = VideoPlayerUIView(player: player, gravity: gravity)
        view.delegate = context.coordinator
        view.subtitleText = subtitleText

        // 手势
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        view.addGestureRecognizer(tapGesture)

        let doubleTapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap)
        )
        doubleTapGesture.numberOfTapsRequired = 2
        tapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(doubleTapGesture)

        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinchGesture)

        return view
    }

    public func updateUIView(_ uiView: VideoPlayerUIView, context: Context) {
        uiView.subtitleText = subtitleText
        if uiView.player !== player {
            uiView.player = player
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject {
        let parent: CustomVideoPlayerView

        init(_ parent: CustomVideoPlayerView) {
            self.parent = parent
        }

        @objc func handleTap() {
            withAnimation(.easeInOut(duration: 0.2)) {
                parent.isControlsVisible.toggle()
            }
        }

        @objc func handleDoubleTap() {
            // 双击切换全屏/缩放
            NotificationCenter.default.post(name: .videoPlayerDidDoubleTap, object: nil)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            NotificationCenter.default.post(
                name: .videoPlayerDidPinch,
                object: nil,
                userInfo: ["scale": gesture.scale]
            )
        }
    }
}

// MARK: - VideoPlayerUIView

/// 承载 AVPlayerLayer 的 UIView
public class VideoPlayerUIView: UIView {
    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
            setupPlayerObservers()
        }
    }

    var gravity: AVLayerVideoGravity = .resizeAspect {
        didSet { playerLayer.videoGravity = gravity }
    }

    var subtitleText: String? {
        didSet { subtitleLabel.text = subtitleText }
    }

    weak var delegate: Coordinator?

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 18)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 1, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var timeObserver: Any?
    private var playerItemObservers: [NSKeyValueObservation] = []

    override public class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public init(player: AVPlayer?, gravity: AVLayerVideoGravity = .resizeAspect) {
        self.player = player
        self.gravity = gravity
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = gravity
        playerLayer.contentsScale = UIScreen.main.scale

        addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -60),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32)
        ])

        setupPlayerObservers()
    }

    private func setupPlayerObservers() {
        removeObservers()
        guard let player = player else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            // 字幕更新通过外部绑定处理
        }

        if let currentItem = player.currentItem {
            playerItemObservers.append(
                currentItem.observe(\.status) { [weak self] item, _ in
                    guard let self = self else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.playerLayer.isHidden = false
                    case .failed:
                        self.showError(item.error?.localizedDescription ?? "播放失败")
                    default:
                        break
                    }
                }
            )
        }
    }

    private func removeObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        playerItemObservers.forEach { $0.invalidate() }
        playerItemObservers.removeAll()
    }

    private func showError(_ message: String) {
        let errorLabel = UILabel()
        errorLabel.text = message
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32)
        ])
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    deinit {
        removeObservers()
    }
}

// MARK: - AVPlayerViewController Wrapper (Alternative)

/// 使用 AVPlayerViewController 的包装，支持系统播放控制
public struct SystemPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsPlaybackControls: Bool
    let entersFullScreen: Bool
    let supportsPIP: Bool
    var didDismiss: (() -> Void)?

    public init(
        player: AVPlayer,
        showsPlaybackControls: Bool = true,
        entersFullScreen: Bool = true,
        supportsPIP: Bool = true,
        didDismiss: (() -> Void)? = nil
    ) {
        self.player = player
        self.showsPlaybackControls = showsPlaybackControls
        self.entersFullScreen = entersFullScreen
        self.supportsPIP = supportsPIP
        self.didDismiss = didDismiss
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.entersFullScreenWhenPlaybackBegins = entersFullScreen
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.canStartPictureInPictureAutomaticallyFromInline = supportsPIP
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(didDismiss: didDismiss)
    }

    public class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let didDismiss: (() -> Void)?

        init(didDismiss: (() -> Void)?) {
            self.didDismiss = didDismiss
        }

        public func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            // 画中画开始
        }

        public func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            // 画中画结束
        }

        public func playerViewControllerWillBeginDismissalTransition(_ playerViewController: AVPlayerViewController) {
            didDismiss?()
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let videoPlayerDidDoubleTap = Notification.Name("videoPlayerDidDoubleTap")
    static let videoPlayerDidPinch = Notification.Name("videoPlayerDidPinch")
}

// MARK: - PiP Manager

/// 画中画管理器
@available(iOS 15.0, *)
public class PipManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?

    @Published public var isPIPActive = false
    @Published public var isPIPPossible = false

    public override init() {
        super.init()
        setupPIP()
    }

    private func setupPIP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)

        // 延迟创建，等 AVPlayer 就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.createPIPController()
        }
    }

    private func createPIPController() {
        // 需要从外部传入 AVPlayer
        // 这里通过 Notification 获取
    }

    public func configure(with player: AVPlayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let contentSource = AVPictureInPictureController.ContentSource(
            playerLayer: AVPlayerLayer(player: player)
        )
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self

        pipPossibleObservation = pipController?.observe(
            \.isPictureInPicturePossible,
            options: [.new, .initial]
        ) { [weak self] controller, _ in
            DispatchQueue.main.async {
                self?.isPIPPossible = controller.isPictureInPicturePossible
            }
        }
    }

    public func startPIP() {
        pipController?.startPictureInPicture()
    }

    public func stopPIP() {
        pipController?.stopPictureInPicture()
    }

    public func togglePIP() {
        if isPIPActive {
            stopPIP()
        } else {
            startPIP()
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isPIPActive = true }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isPIPActive = false }
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { self.isPIPActive = false }
        print("[PipManager] Failed to start PiP: \(error)")
    }
}

// MARK: - macOS 视频播放视图

#if os(macOS)
public class MacVideoPlayerView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        playerLayer.frame = bounds
    }
}

public struct MacVideoPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    public func makeNSView(context: Context) -> MacVideoPlayerView {
        let view = MacVideoPlayerView()
        view.player = player
        return view
    }

    public func updateNSView(_ nsView: MacVideoPlayerView, context: Context) {
        nsView.player = player
    }
}
#endif