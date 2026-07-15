import Foundation
import AVFoundation
import Combine

// MARK: - Media Player Service

/// AVPlayer 封装服务
@Observable
public final class MediaPlayerService: NSObject, Sendable {
    // MARK: - Public Properties

    public private(set) var state = PlaybackState()
    public private(set) var currentItem: AVPlayerItem?
    public private(set) var currentURL: URL?

    // MARK: - Private Properties

    private let player: AVPlayer
    private var timeObserver: Any?
    private var itemObservers: [NSKeyValueObservation] = []
    private var playerObservers: [NSKeyValueObservation] = []
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTimer: Timer?
    private var refreshURL: (() async throws -> URL?)?

    // MARK: - Initialization

    override public init() {
        self.player = AVPlayer()
        self.state = PlaybackState()
        super.init()
        setupPlayerObservers()
        setupAudioSession()
    }

    deinit {
        removeTimeObserver()
        removePlayerObservers()
        refreshTimer?.invalidate()
    }

    // MARK: - Playback Control

    /// 播放 URL
    public func play(url: URL, headers: [String: String]? = nil, title: String? = nil) {
        pause()

        currentURL = url

        let asset: AVURLAsset

        if let headers = headers, !headers.isEmpty {
            // 使用自定义 header
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            asset = AVURLAsset(url: url, options: options)
        } else {
            asset = AVURLAsset(url: url)
        }

        let playerItem = AVPlayerItem(asset: asset)
        currentItem = playerItem
        setupItemObservers(playerItem)

        state.status = .loading
        state.isPlaying = false
        state.isPaused = false
        state.metadata = PlaybackMetadata(title: title ?? url.lastPathComponent)

        player.replaceCurrentItem(with: playerItem)
        player.play()
    }

    /// 恢复播放位置
    public func play(url: URL, headers: [String: String]? = nil, title: String? = nil, resumeTime: Double) {
        play(url: url, headers: headers, title: title)
        seek(to: resumeTime, autoPlay: true)
    }

    /// 便捷播放（无 header）
    public func play(url: URL, title: String? = nil, resumeTime: Double = 0) {
        play(url: url, headers: nil, title: title)
        if resumeTime > 0 {
            seek(to: resumeTime, autoPlay: true)
        }
    }

    /// 暂停
    public func pause() {
        player.pause()
        state.isPlaying = false
        state.isPaused = true
        state.status = .paused
    }

    /// 恢复播放
    public func resume() {
        player.play()
        state.isPlaying = true
        state.isPaused = false
        state.status = .playing
    }

    /// 切换播放/暂停
    public func togglePlayPause() {
        if state.isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// 停止
    public func stop() {
        pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        currentURL = nil
        state = PlaybackState()
        removeItemObservers()
    }

    /// 跳转到指定时间
    public func seek(to time: Double, autoPlay: Bool = true) {
        guard let currentItem = currentItem,
              currentItem.status == .readyToPlay else { return }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        state.isSeeking = true

        currentItem.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            self.state.isSeeking = false
            if autoPlay && !self.state.isPlaying {
                self.resume()
            }
        }
    }

    /// 快进/快退
    public func skip(by seconds: Double) {
        let newTime = state.currentTime + seconds
        seek(to: max(0, min(newTime, state.duration)))
    }

    /// 设置播放速度
    public func setRate(_ rate: Float) {
        guard rate >= 0.25 && rate <= 3.0 else { return }
        player.rate = rate
        state.rate = rate
    }

    /// 设置音量
    public func setVolume(_ volume: Float) {
        player.volume = max(0, min(1, volume))
        state.volume = player.volume
    }

    /// 设置静音
    public func setMuted(_ muted: Bool) {
        player.isMuted = muted
        state.isMuted = muted
    }

    // MARK: - URL Refresh

    /// 设置直链刷新回调
    public func setURLRefreshHandler(_ handler: @escaping () async throws -> URL?) {
        refreshURL = handler
    }

    /// 开始定期刷新直链
    public func startURLRefresh(interval: TimeInterval = 1800) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.refreshPlaybackURL()
            }
        }
    }

    /// 停止直链刷新
    public func stopURLRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshPlaybackURL() async {
        guard let refreshURL = refreshURL else { return }

        do {
            if let newURL = try await refreshURL() {
                let currentRate = player.rate
                let currentTime = state.currentTime

                let asset = AVURLAsset(url: newURL)
                let playerItem = AVPlayerItem(asset: asset)
                currentItem = playerItem
                setupItemObservers(playerItem)

                player.replaceCurrentItem(with: playerItem)
                seek(to: currentTime, autoPlay: currentRate > 0)
            }
        } catch {
            // 刷新失败，保持当前播放
            print("[MediaPlayerService] URL refresh failed: \(error)")
        }
    }

    // MARK: - Picture in Picture

    #if os(iOS) || os(tvOS) || os(visionOS)
    public var isPIPAvailable: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }
    #else
    public var isPIPAvailable: Bool { false }
    #endif

    // MARK: - Background Playback

    private func setupAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .longFormVideo,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            print("[MediaPlayerService] Audio session setup failed: \(error)")
        }
        #endif
    }

    // MARK: - Smart Play (Integration)

    /// 智能播放 — 自动选择最佳播放策略
    /// 1. AVPlayer 原生支持 → 直链播放
    /// 2. 需要自定义 Header → GCDWebServer 代理
    /// 3. 格式不支持 → FFmpeg 解封装 + VideoToolbox 硬解码
    /// - Parameters:
    ///   - url: 媒体文件 URL
    ///   - headers: 需要的 HTTP Header
    ///   - title: 显示标题
    ///   - resumeTime: 恢复播放时间
    public func smartPlay(
        url: URL,
        headers: [String: String]? = nil,
        title: String? = nil,
        resumeTime: Double = 0
    ) {
        let strategy = FormatDetector.getPlaybackStrategy(for: url)

        switch strategy {
        case .directPlay:
            // 直接播放
            if let headers = headers, !headers.isEmpty {
                playWithProxy(url: url, headers: headers, title: title, resumeTime: resumeTime)
            } else {
                play(url: url, title: title, resumeTime: resumeTime)
            }

        case .ffmpegDemux:
            // 需要 FFmpeg 解封装
            playWithFFmpeg(url: url, headers: headers, title: title, resumeTime: resumeTime)

        case .tryNativeThenFFmpeg:
            // 优先尝试原生，设置回调在失败时回退
            playWithFallback(url: url, headers: headers, title: title, resumeTime: resumeTime)
        }
    }

    /// 通过 GCDWebServer 代理播放
    private func playWithProxy(
        url: URL,
        headers: [String: String],
        title: String? = nil,
        resumeTime: Double = 0
    ) {
        Task {
            do {
                // 创建代理 URL
                let proxyURL = await ProxyServiceIntegration.shared.createProxiedURL(
                    for: url,
                    headers: headers
                )

                // 设置直链刷新（代理 URL 也需刷新）
                setURLRefreshHandler { [weak self] in
                    guard let self = self else { return nil }
                    // 重新获取直链后创建新代理
                    return proxyURL
                }
                startURLRefresh()

                await MainActor.run {
                    play(url: proxyURL, title: title, resumeTime: resumeTime)
                }
            } catch {
                print("[MediaPlayerService] Proxy play failed, falling back to direct: \(error)")
                await MainActor.run {
                    play(url: url, headers: headers, title: title, resumeTime: resumeTime)
                }
            }
        }
    }

    /// 通过 FFmpeg 解封装播放
    private func playWithFFmpeg(
        url: URL,
        headers: [String: String]? = nil,
        title: String? = nil,
        resumeTime: Double = 0
    ) {
        Task {
            do {
                // 创建 FFmpeg AVURLAsset（注册自定义 ResourceLoader）
                let asset = FFmpegURLScheme.createFFmpegAsset(for: url)
                let playerItem = AVPlayerItem(asset: asset)

                await MainActor.run {
                    pause()
                    currentURL = url
                    currentItem = playerItem
                    setupItemObservers(playerItem)

                    state.status = .loading
                    state.metadata = PlaybackMetadata(title: title ?? url.lastPathComponent)

                    player.replaceCurrentItem(with: playerItem)

                    if resumeTime > 0 {
                        seek(to: resumeTime, autoPlay: true)
                    } else {
                        player.play()
                    }
                }
            }
        }
    }

    /// 带回退的播放
    private func playWithFallback(
        url: URL,
        headers: [String: String]? = nil,
        title: String? = nil,
        resumeTime: Double = 0
    ) {
        // 先尝试原生播放
        if let headers = headers, !headers.isEmpty {
            playWithProxy(url: url, headers: headers, title: title, resumeTime: resumeTime)
        } else {
            play(url: url, title: title, resumeTime: resumeTime)
        }

        // 设置失败回退
        // 如果 AVPlayer 播放失败，自动切换到 FFmpeg
        let fallbackItem = currentItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self,
                  let item = fallbackItem,
                  item.status == .failed else { return }

            print("[MediaPlayerService] Native playback failed, falling back to FFmpeg")
            self.playWithFFmpeg(url: url, headers: headers, title: title, resumeTime: resumeTime)
        }
    }

    // MARK: - Now Playing Info

    public func updateNowPlayingInfo(title: String, artist: String? = nil, artworkData: Data? = nil) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.rate,
            MPMediaItemPropertyPlaybackDuration: state.duration
        ]

        if let artist = artist {
            info[MPMediaItemPropertyArtist] = artist
        }

        if let artworkData = artworkData,
           let image = UIImage(data: artworkData) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: image.size,
                requestHandler: { _ in image }
            )
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    // MARK: - KVO Observers

    private func setupPlayerObservers() {
        // 播放速率观察
        let timeInterval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.state.currentTime = time.seconds
            self.state.duration = self.currentItem?.duration.seconds ?? 0
        }

        // 播放状态观察
        playerObservers.append(player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            guard let self = self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.state.status = .playing
                self.state.isPlaying = true
                self.state.isPaused = false
            case .paused:
                self.state.status = .paused
                self.state.isPlaying = false
                self.state.isPaused = true
            case .waitingToPlayAtSpecifiedRate:
                self.state.status = .buffering
                self.state.isBuffering = true
            @unknown default:
                break
            }
        })
    }

    private func setupItemObservers(_ item: AVPlayerItem) {
        removeItemObservers()

        itemObservers.append(item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                self.state.status = .ready
                self.state.duration = item.duration.seconds
                self.state.isBuffering = false
            case .failed:
                self.state.status = .failed(.decodingError)
                self.state.error = .decodingError
            case .unknown:
                self.state.status = .loading
            @unknown default:
                break
            }
        })

        itemObservers.append(item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
            self?.state.isBuffering = true
        })

        itemObservers.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            self?.state.isBuffering = !item.isPlaybackLikelyToKeepUp
        })

        // 播放结束通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func removeItemObservers() {
        itemObservers.forEach { $0.invalidate() }
        itemObservers.removeAll()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private func removePlayerObservers() {
        playerObservers.forEach { $0.invalidate() }
        playerObservers.removeAll()
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        state.isFinished = true
        state.status = .ended
        state.isPlaying = false
    }
}

// MARK: - Import for Now Playing

#if os(iOS) || os(tvOS) || os(visionOS)
import MediaPlayer
import UIKit
#endif