import Foundation

// MARK: - Media File Types

/// 支持的媒体文件类型
public enum MediaType: String, Codable, Sendable {
    case video
    case audio
    case subtitle
    case image
    case unknown

    public var isPlayable: Bool {
        self == .video || self == .audio
    }

    public var iconName: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .subtitle: return "captions.bubble"
        case .image: return "photo"
        case .unknown: return "doc"
        }
    }
}

// MARK: - Media File

/// 代表一个媒体文件或目录（来自 alist / WebDAV / 本地）
public struct MediaFile: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modifiedAt: Date?
    public let mediaType: MediaType
    public let hash: String?
    public let sign: String?
    public let thumb: String?
    public let rawURL: String?

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64 = 0,
        modifiedAt: Date? = nil,
        mediaType: MediaType = .unknown,
        hash: String? = nil,
        sign: String? = nil,
        thumb: String? = nil,
        rawURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
        self.mediaType = mediaType
        self.hash = hash
        self.sign = sign
        self.thumb = thumb
        self.rawURL = rawURL
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - File Extension Helpers

public extension MediaFile {
    static let videoExtensions: Set<String> = [
        "mp4", "mkv", "mov", "avi", "wmv", "flv", "webm", "m4v",
        "ts", "mts", "m2ts", "3gp", "ogv", "rmvb", "vob"
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "aac", "wav", "flac", "ogg", "wma", "m4a", "aiff",
        "alac", "opus", "ac3", "dts"
    ]

    static let subtitleExtensions: Set<String> = [
        "srt", "ass", "ssa", "vtt", "sub", "idx", "pgs", "sup"
    ]

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif"
    ]

    static func detectMediaType(from extension: String) -> MediaType {
        let ext = `extension`.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if subtitleExtensions.contains(ext) { return .subtitle }
        if imageExtensions.contains(ext) { return .image }
        return .unknown
    }

    static func isVideoFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    static func isSubtitleFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return subtitleExtensions.contains(ext)
    }
}

// MARK: - Alist API Response Models

/// alist /api/fs/list 响应
public struct AlistListResponse: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AlistListData?
}

public struct AlistListData: Codable, Sendable {
    public let content: [AlistFileItem]?
    public let total: Int?
    public let readme: String?
    public let write: Bool?
    public let provider: String?
}

public struct AlistFileItem: Codable, Sendable {
    public let name: String
    public let size: Int64
    public let isDir: Bool
    public let modified: String?
    public let hash: String?
    public let sign: String?
    public let thumb: String?
    public let type: Int?
    public let rawURL: String?
    public let readme: String?

    enum CodingKeys: String, CodingKey {
        case name, size
        case isDir = "is_dir"
        case modified, hash, sign, thumb, type
        case rawURL = "raw_url"
        case readme
    }

    public func toMediaFile(parentPath: String) -> MediaFile {
        let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return MediaFile(
            name: name,
            path: path,
            isDirectory: isDir,
            size: size,
            modifiedAt: modified.flatMap { dateFormatter.date(from: $0) },
            mediaType: isDir ? .unknown : MediaFile.detectMediaType(from: (name as NSString).pathExtension),
            hash: hash,
            sign: sign,
            thumb: thumb,
            rawURL: rawURL
        )
    }
}

/// alist /api/fs/get 响应（获取直链）
public struct AlistGetResponse: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AlistGetData?
}

public struct AlistGetData: Codable, Sendable {
    public let url: String?
    public let header: [String: String]?
    public let expire: Int?
    public let sign: String?
    public let rawURL: String?

    enum CodingKeys: String, CodingKey {
        case url, header, expire, sign
        case rawURL = "raw_url"
    }
}

/// alist /api/auth/login 请求/响应
public struct AlistLoginRequest: Codable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct AlistLoginResponse: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AlistTokenData?
}

public struct AlistTokenData: Codable, Sendable {
    public let token: String?
}