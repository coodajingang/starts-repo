import Foundation
import SwiftUI
import Combine

// MARK: - Browser ViewModel

/// 文件浏览器 ViewModel
@Observable
public final class BrowserViewModel: Sendable {
    // MARK: - Public Properties

    public private(set) var state = BrowseState()
    public private(set) var connection: DriveConnection?
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var searchResults: [MediaFile] = []
    public private(set) var isSearching = false
    public private(set) var recentFiles: [PlaybackRecord] = []

    // MARK: - Private Properties

    private let alistService = AlistService()
    private let webdavService = WebDAVService()
    private let localFileService = LocalFileService()

    // MARK: - Connection Management

    /// 连接到 alist 服务器
    public func connectToAlist(url: String, token: String) async {
        connectionState = .connecting

        let connection = DriveConnection(
            name: URL(string: url)?.host ?? "Alist",
            type: .alist,
            url: url,
            token: token
        )
        self.connection = connection

        await alistService.configure(baseURL: url, token: token)

        do {
            let isValid = try await alistService.validateToken()
            if isValid {
                connectionState = .connected
                state.currentPath = ""
                try await loadCurrentDirectory()
            } else {
                connectionState = .error("Token 无效")
            }
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    /// 连接到 alist 服务器（用户名密码）
    public func connectToAlist(url: String, username: String, password: String) async {
        connectionState = .connecting

        let connection = DriveConnection(
            name: URL(string: url)?.host ?? "Alist",
            type: .alist,
            url: url,
            username: username,
            password: password
        )
        self.connection = connection

        do {
            try await alistService.configureWithPassword(baseURL: url, username: username, password: password)
            connectionState = .connected
            state.currentPath = ""
            try await loadCurrentDirectory()

            // 保存 token
            if let token = connection.token {
                try? await KeychainManager.shared.saveToken(token, for: url)
            }
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    /// 连接到 WebDAV 服务器
    public func connectToWebDAV(url: String, username: String, password: String) async {
        connectionState = .connecting

        let connection = DriveConnection(
            name: URL(string: url)?.host ?? "WebDAV",
            type: .webdav,
            url: url,
            username: username,
            password: password
        )
        self.connection = connection

        await webdavService.configure(baseURL: url, username: username, password: password)

        do {
            let isValid = try await webdavService.verifyConnection()
            if isValid {
                connectionState = .connected
                state.currentPath = ""
                try await loadCurrentDirectory()
            } else {
                connectionState = .error("WebDAV 连接验证失败")
            }
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    /// 浏览本地文件
    public func browseLocalFiles() async {
        connectionState = .connected

        let connection = DriveConnection(
            name: "本地文件",
            type: .local,
            url: "file:///"
        )
        self.connection = connection

        do {
            let roots = await localFileService.getAvailableRoots()
            state.files = roots
            state.currentPath = ""
            state.error = nil
        }
    }

    /// 断开连接
    public func disconnect() {
        connection = nil
        connectionState = .disconnected
        state = BrowseState()
        searchResults = []
    }

    // MARK: - Navigation

    /// 进入目录
    public func navigateToDirectory(_ file: MediaFile) async {
        guard file.isDirectory else { return }
        state.navigateTo(file.path)
        await loadCurrentDirectory()
    }

    /// 返回上级目录
    public func navigateUp() async {
        state.navigateUp()
        await loadCurrentDirectory()
    }

    /// 导航到指定路径
    public func navigateToPath(_ path: String) async {
        state.navigateTo(path)
        await loadCurrentDirectory()
    }

    // MARK: - File Loading

    /// 加载当前目录内容
    private func loadCurrentDirectory() async throws {
        state.isLoading = true
        state.error = nil

        do {
            let files = try await fetchFiles(path: state.currentPath)
            state.files = files
            state.isLoading = false
        } catch {
            state.error = error.localizedDescription
            state.isLoading = false
            throw error
        }
    }

    /// 刷新当前目录
    public func refresh() async {
        await loadCurrentDirectory()
    }

    /// 根据连接类型获取文件列表
    private func fetchFiles(path: String) async throws -> [MediaFile] {
        guard let connection = connection else { return [] }

        switch connection.type {
        case .alist:
            return try await alistService.listFiles(path: path, refresh: true)
        case .webdav:
            return try await webdavService.listFiles(path: path)
        case .local:
            return try let roots = try await localFileService.listFiles(at: path.isEmpty ? "/" : path)
        }
    }

    // MARK: - Media URL Resolution

    /// 获取媒体文件的播放 URL
    public func getPlaybackURL(for file: MediaFile) async throws -> PlaybackURLInfo {
        guard let connection = connection else {
            throw PlaybackError.resourceNotFound
        }

        switch connection.type {
        case .alist:
            let info = try await alistService.getDirectLink(path: file.path)
            return info
        case .webdav:
            let url = try await webdavService.getFileDownloadURL(path: file.path)
            return PlaybackURLInfo(url: url, headers: ["Authorization": "Basic \(basicAuth)"])
        case .local:
            return PlaybackURLInfo(url: URL(fileURLWithPath: file.path))
        }
    }

    private var basicAuth: String {
        guard let connection = connection else { return "" }
        let login = "\(connection.username):\(connection.password)"
        return login.data(using: .utf8)?.base64EncodedString() ?? ""
    }

    // MARK: - Search

    /// 搜索文件
    public func search(keyword: String) async {
        guard !keyword.isEmpty, let connection = connection else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        do {
            switch connection.type {
            case .alist:
                searchResults = try await alistService.searchFiles(keyword: keyword)
            case .webdav, .local:
                // WebDAV 和本地搜索通过过滤器实现
                let allFiles = state.files
                searchResults = allFiles.filter {
                    $0.name.localizedCaseInsensitiveContains(keyword)
                }
            }
        } catch {
            searchResults = []
        }

        isSearching = false
    }

    /// 清除搜索
    public func clearSearch() {
        searchResults = []
        isSearching = false
    }

    // MARK: - Recent Files

    /// 加载最近播放记录
    public func loadRecentFiles() {
        // 从 UserDefaults 加载
        recentFiles = PreferencesManager.loadConnections().flatMap { _ in
            // 实际项目中从 SwiftData/CoreData 加载
            []
        }
    }
}

// MARK: - File Sorting

public enum FileSortOrder: String, Sendable, CaseIterable, Identifiable {
    case name
    case size
    case date
    case type

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .name: return "名称"
        case .size: return "大小"
        case .date: return "日期"
        case .type: return "类型"
        }
    }
}

// MARK: - File Filter

public enum FileFilter: String, Sendable, CaseIterable, Identifiable {
    case all
    case video
    case audio
    case subtitle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "全部"
        case .video: return "视频"
        case .audio: return "音频"
        case .subtitle: return "字幕"
        }
    }
}