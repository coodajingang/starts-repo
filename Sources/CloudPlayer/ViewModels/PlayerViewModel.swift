import Foundation
import SwiftUI
import AVFoundation
import Combine

// MARK: - Player ViewModel

/// 播放器 ViewModel
@Observable
public final class PlayerViewModel: Sendable {
    // MARK: - Public Properties

    public private(set) var state = PlaybackState()
    public private(set) var currentMediaFile: MediaFile?
    public private(set) var currentSource: DriveConnection?
    public private(set) var subtitles: [SubtitleLoader.SubtitleEntry] = []
    public private(set) var activeSubtitle: SubtitleLoader.SubtitleEntry?
    public private(set) var availableSubtitleFiles: [MediaFile] = []
    public private(set) var isPlayerPresented = false

    // MARK: - Private Properties

    private let mediaPlayerService = MediaPlayerService()
    private let subtitleLoader = SubtitleLoader()
    private let browserViewModel: BrowserViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var progressSaveTimer: Timer?

    // MARK: - Initialization

    public init(browserViewModel: BrowserViewModel) {
        self.browserViewModel = browserViewModel
        setupObservers()
    }

    private func setupObservers() {
        // 观察播放状态变化，自动保存进度
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.saveProgress()
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Control

    /// 播放媒体文件
    public func play(file: MediaFile, source: DriveConnection) {
        currentMediaFile = file
        currentSource = source

        Task {
            do {
                let playbackInfo = try await browserViewModel.getPlaybackURL(for: file)

                // 检查是否有保存的播放进度
                let savedPosition = loadSavedPosition(for: file, source: source)

                isPlayerPresented = true

                if playbackInfo.needsCustomProxy {
                    // 使用本地代理添加 header
                    let proxyService = ProxyService()
                    let proxyURL = proxyService.createProxiedStreamURL(
                        targetURL: playbackInfo.url,
                        headers: playbackInfo.headers ?? [:]
                    )
                    await mediaPlayerService.play(url: proxyURL, title: file.name)
                } else {
                    await mediaPlayerService.play(
                        url: playbackInfo.url,
                        headers: playbackInfo.headers,
                        title: file.name
                    )
                }

                // 设置直链刷新
                await mediaPlayerService.setURLRefreshHandler { [weak self] in
                    guard let self = self else { return nil }
                    let info = try await self.browserViewModel.getPlaybackURL(for: file)
                    return info.url
                }
                await mediaPlayerService.startURLRefresh()

                // 恢复播放位置
                if savedPosition > 0 {
                    await mediaPlayerService.seek(to: savedPosition, autoPlay: true)
                }

                // 加载字幕
                await loadSubtitles(for: file)

                // 同步播放状态
                syncState()
            } catch {
                state.error = .networkError(error.localizedDescription)
            }
        }
    }

    /// 切换播放/暂停
    public func togglePlayPause() {
        Task {
            await mediaPlayerService.togglePlayPause()
            syncState()
        }
    }

    /// 暂停
    public func pause() {
        Task {
            await mediaPlayerService.pause()
            syncState()
            saveProgress()
        }
    }

    /// 恢复
    public func resume() {
        Task {
            await mediaPlayerService.resume()
            syncState()
        }
    }

    /// 跳转
    public func seek(to time: Double) {
        Task {
            await mediaPlayerService.seek(to: time)
            syncState()
        }
    }

    /// 快进
    public func skipForward(seconds: Double = 10) {
        let newTime = state.currentTime + seconds
        seek(to: newTime)
    }

    /// 快退
    public func skipBackward(seconds: Double = 10) {
        let newTime = state.currentTime - seconds
        seek(to: max(0, newTime))
    }

    /// 设置播放速度
    public func setPlaybackRate(_ rate: Float) {
        Task {
            await mediaPlayerService.setRate(rate)
            syncState()
        }
    }

    /// 设置音量
    public func setVolume(_ volume: Float) {
        Task {
            await mediaPlayerService.setVolume(volume)
            syncState()
        }
    }

    /// 设置静音
    public func setMuted(_ muted: Bool) {
        Task {
            await mediaPlayerService.setMuted(muted)
            syncState()
        }
    }

    /// 关闭播放器
    public func dismissPlayer() {
        saveProgress()
        Task {
            await mediaPlayerService.stop()
            await mediaPlayerService.stopURLRefresh()
        }
        isPlayerPresented = false
        currentMediaFile = nil
        subtitles = []
        activeSubtitle = nil
    }

    // MARK: - Subtitles

    /// 加载字幕
    private func loadSubtitles(for file: MediaFile) async {
        // 查找同目录下字幕文件
        let videoDir = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
        let allFiles = browserViewModel.state.files
        let subtitleFiles = SubtitleLoader.findAssociatedSubtitles(
            for: file.path,
            availableFiles: allFiles
        )
        availableSubtitleFiles = subtitleFiles

        // 自动加载第一个字幕
        if let firstSub = subtitleFiles.first {
            await loadSubtitleFile(firstSub)
        }
    }

    /// 加载字幕文件
    public func loadSubtitleFile(_ file: MediaFile) async {
        do {
            let url = URL(fileURLWithPath: file.path)
            let entries = try await subtitleLoader.loadSubtitles(from: url)
            subtitles = entries
        } catch {
            print("[PlayerViewModel] Subtitle load failed: \(error)")
        }
    }

    /// 手动加载字幕 URL
    public func loadSubtitleURL(_ url: URL) async {
        do {
            let entries = try await subtitleLoader.loadSubtitles(from: url)
            subtitles = entries
        } catch {
            print("[PlayerViewModel] Subtitle load failed: \(error)")
        }
    }

    /// 更新当前字幕
    public func updateActiveSubtitle(at time: Double) {
        activeSubtitle = SubtitleLoader.subtitleAtTime(time, from: subtitles)
    }

    /// 清除字幕
    public func clearSubtitles() {
        subtitles = []
        activeSubtitle = nil
    }

    // MARK: - Progress Persistence

    /// 保存播放进度
    private func saveProgress() {
        guard let file = currentMediaFile,
              let source = currentSource,
              state.duration > 0 else { return }

        let record = PlaybackRecord(
            mediaName: file.name,
            mediaPath: file.path,
            sourceID: source.id,
            sourceName: source.name,
            duration: state.duration,
            position: state.currentTime,
            rate: state.rate,
            isFinished: state.isFinished
        )

        // 存到 UserDefaults（后续可迁移到 SwiftData）
        var records = loadSavedRecords()
        records.removeAll { $0.mediaPath == file.path && $0.sourceID == source.id }
        records.append(record)

        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: "playback_records")
        }
    }

    /// 加载保存的播放位置
    private func loadSavedPosition(for file: MediaFile, source: DriveConnection) -> Double {
        let records = loadSavedRecords()
        return records.first { $0.mediaPath == file.path && $0.sourceID == source.id }?.position ?? 0
    }

    /// 加载所有播放记录
    private func loadSavedRecords() -> [PlaybackRecord] {
        guard let data = UserDefaults.standard.data(forKey: "playback_records"),
              let records = try? JSONDecoder().decode([PlaybackRecord].self, from: data) else {
            return []
        }
        return records
    }

    /// 获取所有播放记录（公开方法）
    public func getAllPlaybackRecords() -> [PlaybackRecord] {
        loadSavedRecords()
    }

    /// 清除播放记录
    public func clearPlaybackRecords() {
        UserDefaults.standard.removeObject(forKey: "playback_records")
    }

    /// 标记为已看完
    public func markAsFinished() {
        guard let file = currentMediaFile,
              let source = currentSource else { return }

        var records = loadSavedRecords()
        records.removeAll { $0.mediaPath == file.path && $0.sourceID == source.id }

        let record = PlaybackRecord(
            mediaName: file.name,
            mediaPath: file.path,
            sourceID: source.id,
            sourceName: source.name,
            duration: state.duration,
            position: state.duration,
            isFinished: true
        )
        records.append(record)

        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: "playback_records")
        }
    }

    // MARK: - State Sync

    /// 同步播放状态
    private func syncState() {
        // 状态已经在 MediaPlayerService 中通过 @Observable 同步
        // 这里做额外的转换
        updateActiveSubtitle(at: state.currentTime)
    }

    /// 定时更新字幕
    public func startSubtitleTimer() {
        Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateActiveSubtitle(at: self.state.currentTime)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Player ViewModel Extension

public extension PlayerViewModel {
    /// 格式化时间
    static func formatTime(_ time: Double) -> String {
        guard !time.isNaN, !time.isInfinite else { return "00:00" }
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}