import Foundation
import SwiftyJSON

// MARK: - Alist API Client

/// alist API 封装
public actor AlistService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private var baseURL: String = ""
    private var token: String = ""

    // MARK: - Initialization

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Configuration

    public func configure(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
    }

    public func configureWithPassword(baseURL: String, username: String, password: String) async throws {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let token = try await login(username: username, password: password)
        self.token = token
    }

    // MARK: - Auth

    /// 登录获取 token
    public func login(username: String, password: String) async throws -> String {
        let url = "\(baseURL)/api/auth/login"
        let body = AlistLoginRequest(username: username, password: password)
        let response: AlistLoginResponse = try await postRequest(url: url, body: body)

        guard response.code == 200, let token = response.data?.token else {
            throw AlistError.loginFailed(response.message)
        }
        return token
    }

    /// 验证 token 是否有效
    public func validateToken() async throws -> Bool {
        let url = "\(baseURL)/api/me"
        let response: AlistListResponse = try await getRequest(url: url)
        return response.code == 200
    }

    // MARK: - File Operations

    /// 列出目录内容
    public func listFiles(path: String, password: String? = nil, refresh: Bool = false) async throws -> [MediaFile] {
        let url = "\(baseURL)/api/fs/list"
        var parameters: [String: Any] = [
            "path": path.isEmpty ? "/" : path,
            "refresh": refresh
        ]
        if let password = password {
            parameters["password"] = password
        }

        let response: AlistListResponse = try await postRequest(url: url, body: parameters)

        guard response.code == 200, let data = response.data else {
            throw AlistError.apiError(response.message)
        }

        return data.content?.map { $0.toMediaFile(parentPath: path) } ?? []
    }

    /// 获取直链
    public func getDirectLink(path: String, password: String? = nil) async throws -> PlaybackURLInfo {
        let url = "\(baseURL)/api/fs/get"
        var parameters: [String: Any] = [
            "path": path.isEmpty ? "/" : path
        ]
        if let password = password {
            parameters["password"] = password
        }

        let response: AlistGetResponse = try await postRequest(url: url, body: parameters)

        guard response.code == 200, let data = response.data, let urlString = data.url else {
            throw AlistError.directLinkFailed(response.message)
        }

        guard let directURL = URL(string: urlString) else {
            throw AlistError.urlInvalid
        }

        let expiration: Date?
        if let expire = data.expire, expire > 0 {
            expiration = Date(timeIntervalSince1970: TimeInterval(expire))
        } else {
            expiration = nil
        }

        // 判断是否需要自定义 header proxy
        let needsProxy = data.header != nil && !data.header!.isEmpty

        return PlaybackURLInfo(
            url: directURL,
            headers: data.header,
            expirationDate: expiration,
            needsCustomProxy: needsProxy
        )
    }

    /// 搜索文件
    public func searchFiles(keyword: String, path: String? = nil, page: Int = 1, perPage: Int = 50) async throws -> [MediaFile] {
        let url = "\(baseURL)/api/fs/search"
        var parameters: [String: Any] = [
            "parent": path ?? "/",
            "name": keyword,
            "page": page,
            "per_page": perPage
        ]

        struct SearchResponse: Codable, Sendable {
            let code: Int
            let message: String
            let data: SearchData?
        }

        struct SearchData: Codable, Sendable {
            let content: [AlistFileItem]?
            let total: Int?
        }

        let response: SearchResponse = try await postRequest(url: url, body: parameters)

        guard response.code == 200 else {
            throw AlistError.apiError(response.message)
        }

        let parentPath = path ?? ""
        return response.data?.content?.map { $0.toMediaFile(parentPath: parentPath) } ?? []
    }

    /// 获取服务器信息
    public func getServerInfo() async throws -> AlistServerInfo {
        let url = "\(baseURL)/api/admin/settings"

        struct SettingsResponse: Codable, Sendable {
            let code: Int
            let message: String
            let data: [SettingItem]?
        }

        struct SettingItem: Codable, Sendable {
            let key: String
            let value: String?
        }

        let response: SettingsResponse = try await getRequest(url: url)

        var info = AlistServerInfo()
        if let settings = response.data {
            for setting in settings {
                switch setting.key {
                case "version": info.version = setting.value ?? ""
                case "site_title": info.title = setting.value ?? ""
                default: break
                }
            }
        }
        return info
    }

    // MARK: - Network Helpers

    private func getRequest<T: Decodable>(url: String) async throws -> T {
        guard let url = URL(string: url) else {
            throw AlistError.urlInvalid
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try decoder.decode(T.self, from: data)
    }

    private func postRequest<T: Decodable>(url: String, body: some Encodable) async throws -> T {
        guard let url = URL(string: url) else {
            throw AlistError.urlInvalid
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let encoded = try JSONEncoder().encode(AnyEncodable(body))
        request.httpBody = encoded

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try decoder.decode(T.self, from: data)
    }

    private func postRequest(url: String, body: [String: Any]) async throws -> AlistListResponse {
        guard let url = URL(string: url) else {
            throw AlistError.urlInvalid
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try decoder.decode(AlistListResponse.self, from: data)
    }

    private func postRequest(url: String, body: [String: Any]) async throws -> AlistGetResponse {
        guard let url = URL(string: url) else {
            throw AlistError.urlInvalid
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try decoder.decode(AlistGetResponse.self, from: data)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AlistError.networkError("无效的响应")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw AlistError.unauthorized
        case 403:
            throw AlistError.forbidden
        case 404:
            throw AlistError.notFound
        case 408:
            throw AlistError.timeout
        case 500...599:
            throw AlistError.serverError(httpResponse.statusCode)
        default:
            throw AlistError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Alist Server Info

public struct AlistServerInfo: Sendable {
    public var version: String = ""
    public var title: String = ""
}

// MARK: - Alist Errors

public enum AlistError: LocalizedError, Sendable, Equatable {
    case urlInvalid
    case loginFailed(String)
    case unauthorized
    case forbidden
    case notFound
    case timeout
    case networkError(String)
    case serverError(Int)
    case apiError(String)
    case directLinkFailed(String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .urlInvalid: return "URL 格式无效"
        case .loginFailed(let msg): return "登录失败: \(msg)"
        case .unauthorized: return "未授权，请重新登录"
        case .forbidden: return "禁止访问"
        case .notFound: return "资源不存在"
        case .timeout: return "请求超时"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .serverError(let code): return "服务器错误 (\(code))"
        case .apiError(let msg): return "API 错误: \(msg)"
        case .directLinkFailed(let msg): return "获取直链失败: \(msg)"
        case .decodingFailed: return "数据解析失败"
        }
    }
}

// MARK: - Helper: AnyEncodable

/// 包装任意 Encodable 值
private struct AnyEncodable: Encodable {
    private let value: Encodable

    init(_ value: Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}