import Foundation

// MARK: - Drive Source Type

/// 存储源类型
public enum DriveSourceType: String, Codable, Sendable, CaseIterable, Identifiable {
    case alist
    case webdav
    case local

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .alist: return "Alist"
        case .webdav: return "WebDAV"
        case .local: return "本地文件"
        }
    }

    public var iconName: String {
        switch self {
        case .alist: return "cloud.fill"
        case .webdav: return "server.rack"
        case .local: return "internaldrive"
        }
    }
}

// MARK: - Drive Connection

/// 一个存储连接配置
public struct DriveConnection: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var type: DriveSourceType
    public var url: String
    public var username: String
    public var password: String
    public var token: String?
    public var isActive: Bool
    public var createdAt: Date
    public var lastAccessedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        type: DriveSourceType,
        url: String,
        username: String = "",
        password: String = "",
        token: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.username = username
        self.password = password
        self.token = token
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    /// 基础 URL（去掉末尾斜杠）
    public var baseURL: String {
        url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// API 路径前缀
    public var apiPath: String {
        "\(baseURL)/api"
    }

    /// 是否已认证
    public var isAuthenticated: Bool {
        if type == .local { return true }
        if type == .alist { return token != nil && !token!.isEmpty }
        return !username.isEmpty || !password.isEmpty
    }

    public static func == (lhs: DriveConnection, rhs: DriveConnection) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Connection State

/// 连接状态
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var isConnected: Bool {
        self == .connected
    }

    public var isLoading: Bool {
        self == .connecting
    }

    public var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}

// MARK: - Browse State

/// 浏览状态
public struct BrowseState: Sendable {
    public var currentPath: String = ""
    public var files: [MediaFile] = []
    public var isLoading: Bool = false
    public var error: String?
    public var breadcrumbs: [String] = []

    public var pathComponents: [String] {
        currentPath.split(separator: "/").map(String.init)
    }

    public mutating func navigateTo(_ path: String) {
        currentPath = path
        breadcrumbs = pathComponents
        files = []
        error = nil
    }

    public mutating func navigateUp() {
        let components = pathComponents
        if components.count <= 1 {
            currentPath = ""
        } else {
            currentPath = components.dropLast().joined(separator: "/")
        }
        breadcrumbs = pathComponents
        files = []
        error = nil
    }
}