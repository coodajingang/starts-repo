import Foundation
import AVFoundation

// MARK: - Playback State

/// 播放器状态
@Observable
public final class PlaybackState: Sendable {
    public var status: PlaybackStatus = .idle
    public var currentTime: Double = 0
    public var duration: Double = 0
    public var rate: Float = 1.0
    public var volume: Float = 1.0
    public var isMuted: Bool = false
    public var isSeeking: Bool = false
    public var isPlaying: Bool = false
    public var isPaused: Bool = false
    public var isBuffering: Bool = false
    public var isFinished: Bool = false
    public var error: PlaybackError?
    public var metadata: PlaybackMetadata?

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    public var remainingTime: Double {
        duration - currentTime
    }

    public var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    public var formattedDuration: String {
        formatTime(duration)
    }

    public var formattedRemainingTime: String {
        "-\(formatTime(remainingTime))"
    }

    private func formatTime(_ time: Double) -> String {
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

// MARK: - Playback Status

public enum PlaybackStatus: Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case seeking
    case buffering
    case ended
    case failed(PlaybackError)

    public var isPlayable: Bool {
        self == .playing || self == .paused || self == .ready
    }
}

// MARK: - Playback Error

public enum PlaybackError: LocalizedError, Sendable, Equatable {
    case urlInvalid
    case networkError(String)
    case unsupportedFormat
    case decodingError
    case resourceNotFound
    case timeout
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .urlInvalid: return "无效的播放地址"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .unsupportedFormat: return "不支持的格式"
        case .decodingError: return "解码错误"
        case .resourceNotFound: return "资源未找到"
        case .timeout: return "请求超时"
        case .unknown(let msg): return "未知错误: \(msg)"
        }
    }
}

// MARK: - Playback Metadata

public struct PlaybackMetadata: Sendable, Equatable {
    public let title: String
    public let subtitle: String?
    public let artworkData: Data?
    public let availableSubtitles: [SubtitleTrack]
    public let availableAudioTracks: [AudioTrack]

    public init(
        title: String,
        subtitle: String? = nil,
        artworkData: Data? = nil,
        availableSubtitles: [SubtitleTrack] = [],
        availableAudioTracks: [AudioTrack] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artworkData = artworkData
        self.availableSubtitles = availableSubtitles
        self.availableAudioTracks = availableAudioTracks
    }
}

// MARK: - Subtitle Track

public struct SubtitleTrack: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let language: String?
    public let url: URL?
    public let format: SubtitleFormat
    public let isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        language: String? = nil,
        url: URL? = nil,
        format: SubtitleFormat = .srt,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.url = url
        self.format = format
        self.isDefault = isDefault
    }
}

public enum SubtitleFormat: String, Sendable, Equatable {
    case srt
    case ass
    case vtt
    case sub
    case pgs
    case unknown
}

// MARK: - Audio Track

public struct AudioTrack: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let language: String?
    public let isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        language: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.isDefault = isDefault
    }
}

// MARK: - Playback Record

/// 播放记录（用于持久化）
public struct PlaybackRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let mediaName: String
    public let mediaPath: String
    public let sourceID: UUID
    public let sourceName: String
    public let duration: Double
    public let position: Double
    public let rate: Float
    public let lastPlayedAt: Date
    public let isFinished: Bool

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return position / duration
    }

    public init(
        id: UUID = UUID(),
        mediaName: String,
        mediaPath: String,
        sourceID: UUID,
        sourceName: String,
        duration: Double,
        position: Double,
        rate: Float = 1.0,
        lastPlayedAt: Date = Date(),
        isFinished: Bool = false
    ) {
        self.id = id
        self.mediaName = mediaName
        self.mediaPath = mediaPath
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.duration = duration
        self.position = position
        self.rate = rate
        self.lastPlayedAt = lastPlayedAt
        self.isFinished = isFinished
    }
}

// MARK: - Playback URL Info

/// 解析后的播放 URL 信息
public struct PlaybackURLInfo: Sendable {
    public let url: URL
    public let headers: [String: String]?
    public let expirationDate: Date?
    public let needsCustomProxy: Bool

    public init(
        url: URL,
        headers: [String: String]? = nil,
        expirationDate: Date? = nil,
        needsCustomProxy: Bool = false
    ) {
        self.url = url
        self.headers = headers
        self.expirationDate = expirationDate
        self.needsCustomProxy = needsCustomProxy
    }

    public var isExpired: Bool {
        guard let expirationDate else { return false }
        return Date() > expirationDate
    }
}

// MARK: - Playback Speed

public let availablePlaybackSpeeds: [Float] = [
    0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0
]