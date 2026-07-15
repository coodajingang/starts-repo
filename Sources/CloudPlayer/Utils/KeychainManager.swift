import Foundation
import KeychainAccess

// MARK: - Keychain Manager

/// Keychain 安全存储管理器
/// 用于存储 alist token、WebDAV 密码等敏感信息
public actor KeychainManager {
    private let keychain: Keychain

    public static let shared = KeychainManager()

    private init() {
        self.keychain = Keychain(service: "com.cloudplayer.keychain")
            .accessibility(.whenUnlockedThisDeviceOnly)
            .synchronizable(false)
    }

    // MARK: - Token Storage

    /// 保存 alist token
    public func saveToken(_ token: String, for serverURL: String) throws {
        let key = "alist_token_\(serverURL.hashValue)"
        try keychain.set(token, key: key)
    }

    /// 读取 alist token
    public func getToken(for serverURL: String) -> String? {
        let key = "alist_token_\(serverURL.hashValue)"
        return try? keychain.get(key)
    }

    /// 删除 token
    public func deleteToken(for serverURL: String) throws {
        let key = "alist_token_\(serverURL.hashValue)"
        try keychain.remove(key)
    }

    // MARK: - Password Storage

    /// 保存密码
    public func savePassword(_ password: String, for serverURL: String, username: String) throws {
        let key = "password_\(serverURL.hashValue)_\(username)"
        try keychain.set(password, key: key)
    }

    /// 读取密码
    public func getPassword(for serverURL: String, username: String) -> String? {
        let key = "password_\(serverURL.hashValue)_\(username)"
        return try? keychain.get(key)
    }

    /// 删除密码
    public func deletePassword(for serverURL: String, username: String) throws {
        let key = "password_\(serverURL.hashValue)_\(username)"
        try keychain.remove(key)
    }

    // MARK: - Generic Storage

    /// 保存任意字符串
    public func save(_ value: String, key: String) throws {
        try keychain.set(value, key: key)
    }

    /// 读取字符串
    public func get(_ key: String) -> String? {
        try? keychain.get(key)
    }

    /// 删除
    public func delete(_ key: String) throws {
        try keychain.remove(key)
    }

    /// 清除所有存储的数据
    public func clearAll() throws {
        try keychain.removeAll()
    }

    // MARK: - Connection Credentials

    /// 保存连接凭据
    public func saveConnectionCredentials(_ connection: DriveConnection) throws {
        switch connection.type {
        case .alist:
            if let token = connection.token {
                try saveToken(token, for: connection.url)
            }
            if !connection.password.isEmpty {
                try savePassword(connection.password, for: connection.url, username: connection.username)
            }
        case .webdav:
            if !connection.password.isEmpty {
                try savePassword(connection.password, for: connection.url, username: connection.username)
            }
        case .local:
            break
        }
    }

    /// 加载连接凭据
    public func loadConnectionCredentials(_ connection: inout DriveConnection) {
        switch connection.type {
        case .alist:
            if let token = getToken(for: connection.url) {
                connection.token = token
            }
            if connection.password.isEmpty {
                connection.password = getPassword(for: connection.url, username: connection.username) ?? ""
            }
        case .webdav:
            if connection.password.isEmpty {
                connection.password = getPassword(for: connection.url, username: connection.username) ?? ""
            }
        case .local:
            break
        }
    }
}

// MARK: - UserDefaults Manager

/// 轻量级偏好设置管理
public struct PreferencesManager {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let playbackSpeed = "playback_speed"
        static let playbackVolume = "playback_volume"
        static let subtitleEnabled = "subtitle_enabled"
        static let subtitleSize = "subtitle_size"
        static let lastSelectedTab = "last_selected_tab"
        static let enableBackgroundPlayback = "enable_background_playback"
        static let connectTimeout = "connect_timeout"
        static let autoRefreshInterval = "auto_refresh_interval"
        static let savedConnections = "saved_connections"
        static let appearanceMode = "appearance_mode"
    }

    // MARK: - Playback Preferences

    public static var playbackSpeed: Float {
        get { defaults.float(forKey: Keys.playbackSpeed).nonZero ?? 1.0 }
        set { defaults.set(newValue, forKey: Keys.playbackSpeed) }
    }

    public static var playbackVolume: Float {
        get { defaults.float(forKey: Keys.playbackVolume).nonZero ?? 1.0 }
        set { defaults.set(newValue, forKey: Keys.playbackVolume) }
    }

    public static var subtitleEnabled: Bool {
        get { defaults.bool(forKey: Keys.subtitleEnabled) }
        set { defaults.set(newValue, forKey: Keys.subtitleEnabled) }
    }

    public static var subtitleSize: Int {
        get { defaults.integer(forKey: Keys.subtitleSize).nonZero ?? 16 }
        set { defaults.set(newValue, forKey: Keys.subtitleSize) }
    }

    // MARK: - General Preferences

    public static var lastSelectedTab: Int {
        get { defaults.integer(forKey: Keys.lastSelectedTab) }
        set { defaults.set(newValue, forKey: Keys.lastSelectedTab) }
    }

    public static var enableBackgroundPlayback: Bool {
        get { defaults.bool(forKey: Keys.enableBackgroundPlayback) }
        set { defaults.set(newValue, forKey: Keys.enableBackgroundPlayback) }
    }

    public static var connectTimeout: TimeInterval {
        get { defaults.double(forKey: Keys.connectTimeout).nonZero ?? 30.0 }
        set { defaults.set(newValue, forKey: Keys.connectTimeout) }
    }

    public static var autoRefreshInterval: TimeInterval {
        get { defaults.double(forKey: Keys.autoRefreshInterval).nonZero ?? 1800.0 }
        set { defaults.set(newValue, forKey: Keys.autoRefreshInterval) }
    }

    public static var appearanceMode: AppearanceMode {
        get {
            let raw = defaults.integer(forKey: Keys.appearanceMode)
            return AppearanceMode(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.appearanceMode) }
    }

    // MARK: - Connection Persistence

    public static func saveConnections(_ connections: [DriveConnection]) {
        if let data = try? JSONEncoder().encode(connections) {
            defaults.set(data, forKey: Keys.savedConnections)
        }
    }

    public static func loadConnections() -> [DriveConnection] {
        guard let data = defaults.data(forKey: Keys.savedConnections),
              let connections = try? JSONDecoder().decode([DriveConnection].self, from: data) else {
            return []
        }
        return connections
    }
}

// MARK: - Appearance Mode

public enum AppearanceMode: Int, Sendable, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - Helpers

private extension Float {
    var nonZero: Float? {
        self == 0 ? nil : self
    }
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}