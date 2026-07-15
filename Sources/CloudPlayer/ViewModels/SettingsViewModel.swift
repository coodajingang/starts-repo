import Foundation
import SwiftUI

// MARK: - Settings ViewModel

/// 设置页面 ViewModel
@Observable
public final class SettingsViewModel: Sendable {
    // MARK: - Public Properties

    public var connections: [DriveConnection] = []
    public var selectedConnection: DriveConnection?
    public var isAddingConnection = false
    public var isEditingConnection = false

    // MARK: - Playback Settings

    public var defaultPlaybackSpeed: Float {
        didSet { PreferencesManager.playbackSpeed = defaultPlaybackSpeed }
    }
    public var defaultVolume: Float {
        didSet { PreferencesManager.playbackVolume = defaultVolume }
    }
    public var subtitleEnabled: Bool {
        didSet { PreferencesManager.subtitleEnabled = subtitleEnabled }
    }
    public var subtitleSize: Int {
        didSet { PreferencesManager.subtitleSize = subtitleSize }
    }
    public var backgroundPlayback: Bool {
        didSet { PreferencesManager.enableBackgroundPlayback = backgroundPlayback }
    }
    public var appearanceMode: AppearanceMode {
        didSet { PreferencesManager.appearanceMode = appearanceMode }
    }
    public var autoRefreshInterval: TimeInterval {
        didSet { PreferencesManager.autoRefreshInterval = autoRefreshInterval }
    }

    // MARK: - Connection Form

    public var newConnectionName = ""
    public var newConnectionURL = ""
    public var newConnectionType: DriveSourceType = .alist
    public var newConnectionUsername = ""
    public var newConnectionPassword = ""
    public var newConnectionToken = ""
    public var isTestingConnection = false
    public var connectionTestResult: ConnectionTestResult?

    public enum ConnectionTestResult: Sendable, Equatable {
        case success
        case failure(String)
    }

    // MARK: - Initialization

    public init() {
        // 加载偏好设置
        self.defaultPlaybackSpeed = PreferencesManager.playbackSpeed
        self.defaultVolume = PreferencesManager.playbackVolume
        self.subtitleEnabled = PreferencesManager.subtitleEnabled
        self.subtitleSize = PreferencesManager.subtitleSize
        self.backgroundPlayback = PreferencesManager.enableBackgroundPlayback
        self.appearanceMode = PreferencesManager.appearanceMode
        self.autoRefreshInterval = PreferencesManager.autoRefreshInterval

        // 加载已保存的连接
        self.connections = PreferencesManager.loadConnections()
    }

    // MARK: - Connection Management

    /// 添加新连接
    public func addConnection() async {
        guard !newConnectionURL.isEmpty else { return }

        let connection = DriveConnection(
            name: newConnectionName.isEmpty ? URL(string: newConnectionURL)?.host ?? "新连接" : newConnectionName,
            type: newConnectionType,
            url: newConnectionURL,
            username: newConnectionUsername,
            password: newConnectionPassword,
            token: newConnectionToken.isEmpty ? nil : newConnectionToken
        )

        // 保存凭据到 Keychain
        try? await KeychainManager.shared.saveConnectionCredentials(connection)

        connections.append(connection)
        saveConnections()
        resetConnectionForm()
    }

    /// 更新连接
    public func updateConnection(_ connection: DriveConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        saveConnections()
    }

    /// 删除连接
    public func deleteConnection(at offsets: IndexSet) {
        connections.remove(atOffsets: offsets)
        saveConnections()
    }

    /// 删除连接
    public func deleteConnection(_ connection: DriveConnection) {
        connections.removeAll { $0.id == connection.id }
        saveConnections()
    }

    /// 测试连接
    public func testConnection(url: String, type: DriveSourceType, username: String, password: String, token: String) async {
        isTestingConnection = true
        connectionTestResult = nil

        do {
            switch type {
            case .alist:
                let service = AlistService()
                if !token.isEmpty {
                    await service.configure(baseURL: url, token: token)
                } else {
                    try await service.configureWithPassword(baseURL: url, username: username, password: password)
                }
                let isValid = try await service.validateToken()
                connectionTestResult = isValid ? .success : .failure("Token 无效")
            case .webdav:
                let service = WebDAVService()
                await service.configure(baseURL: url, username: username, password: password)
                let isValid = try await service.verifyConnection()
                connectionTestResult = isValid ? .success : .failure("WebDAV 连接失败")
            case .local:
                connectionTestResult = .success
            }
        } catch {
            connectionTestResult = .failure(error.localizedDescription)
        }

        isTestingConnection = false
    }

    /// 重置连接表单
    public func resetConnectionForm() {
        newConnectionName = ""
        newConnectionURL = ""
        newConnectionType = .alist
        newConnectionUsername = ""
        newConnectionPassword = ""
        newConnectionToken = ""
        connectionTestResult = nil
        isAddingConnection = false
        isEditingConnection = false
        selectedConnection = nil
    }

    // MARK: - Playback Records

    /// 清除所有播放记录
    public func clearAllPlaybackRecords() {
        UserDefaults.standard.removeObject(forKey: "playback_records")
    }

    /// 清除所有缓存
    public func clearAllCaches() {
        URLCache.shared.removeAllCachedResponses()
        clearAllPlaybackRecords()
    }

    // MARK: - Persistence

    private func saveConnections() {
        PreferencesManager.saveConnections(connections)
    }

    /// 加载凭据
    public func loadCredentials(for connection: inout DriveConnection) {
        Task {
            await KeychainManager.shared.loadConnectionCredentials(&connection)
        }
    }

    // MARK: - About

    public var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    public var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "CloudPlayer"
    }
}