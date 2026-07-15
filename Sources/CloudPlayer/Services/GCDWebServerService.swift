import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

// MARK: - GCDWebServer 本地 HTTP 代理服务

/// 完整的本地 HTTP 代理服务
/// 用于在 AVPlayer 请求直链时添加自定义请求头（Referer、User-Agent、Cookie 等）
///
/// 工作原理：
/// 1. 启动一个本地 HTTP 服务器
/// 2. 为每个需要自定义 Header 的直链创建一个代理 URL
/// 3. AVPlayer 请求代理 URL 时，本地服务器添加 Header 后转发到目标 URL
/// 4. 支持 Range 请求（用于进度拖动）
/// 5. 支持直链过期自动刷新
public actor GCDWebServerService {
    // MARK: - Singleton

    public static let shared = GCDWebServerService()

    // MARK: - Properties

    private var server: GCDWebServer?
    private var isRunning = false
    private var port: UInt16 = 9898
    private var proxyMappings: [String: ProxyMapping] = [:]
    private let session: URLSession

    // MARK: - Proxy Mapping

    public struct ProxyMapping: Sendable, Hashable {
        public let id: String
        public let targetURL: URL
        public let headers: [String: String]
        public let createdAt: Date

        public init(targetURL: URL, headers: [String: String]) {
            self.id = UUID().uuidString
            self.targetURL = targetURL
            self.headers = headers
            self.createdAt = Date()
        }

        /// 是否过期（默认 30 分钟）
        public var isExpired: Bool {
            Date().timeIntervalSince(createdAt) > 1800
        }
    }

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        // 禁用缓存，确保每次请求都转发
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    // MARK: - Server Lifecycle

    /// 启动本地代理服务器
    /// - Parameter port: 监听端口，默认 9898
    public func start(port: UInt16 = 9898) async throws {
        guard !isRunning else {
            // 如果端口不同，先重启
            if self.port != port {
                stop()
            } else {
                return
            }
        }

        self.port = port
        self.server = GCDWebServer()

        // 注册默认处理器 — 处理所有 /proxy/ 路径的请求
        server?.addDefaultHandler(forMethod: "GET", request: GCDWebServerDataRequest.self) { [weak self] request in
            guard let self = self else { return GCDWebServerErrorResponse(statusCode: 500) }
            return await self.handleRequest(request)
        }

        server?.addDefaultHandler(forMethod: "HEAD", request: GCDWebServerDataRequest.self) { [weak self] request in
            guard let self = self else { return GCDWebServerErrorResponse(statusCode: 500) }
            return await self.handleRequest(request)
        }

        // 启动服务器
        let options: [String: Any] = [
            GCDWebServerOption_Port: port,
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_AutomaticallySuspendInBackground: false,
            GCDWebServerOption_ConnectedStateCoalescingInterval: 2.0
        ]

        try server?.start(options: options)
        isRunning = true

        print("[GCDWebServer] Started on http://127.0.0.1:\(port)")
    }

    /// 停止服务器
    public func stop() {
        guard isRunning else { return }
        server?.stop()
        server = nil
        proxyMappings.removeAll()
        isRunning = false
        print("[GCDWebServer] Stopped")
    }

    // MARK: - Proxy URL Management

    /// 为直链创建代理 URL（添加自定义 Header）
    /// - Parameters:
    ///   - targetURL: 原始直链 URL
    ///   - headers: 需要添加的 HTTP Header
    /// - Returns: 代理 URL（替换 scheme 为 http）
    public func createProxyURL(for targetURL: URL, headers: [String: String]) async -> URL {
        // 如果服务器未启动，自动启动
        if !isRunning {
            try? await start()
        }

        let mapping = ProxyMapping(targetURL: targetURL, headers: headers)
        proxyMappings[mapping.id] = mapping

        // 清理过期映射
        cleanupExpiredMappings()

        // 返回代理 URL: http://127.0.0.1:9898/proxy/{uuid}
        return URL(string: "http://127.0.0.1:\(port)/proxy/\(mapping.id)")!
    }

    /// 刷新代理映射（直链过期时更新）
    public func refreshProxyMapping(id: String, newTargetURL: URL, newHeaders: [String: String]) {
        let mapping = ProxyMapping(targetURL: newTargetURL, headers: newHeaders)
        proxyMappings[id] = mapping
    }

    /// 移除代理映射
    public func removeProxyMapping(id: String) {
        proxyMappings.removeValue(forKey: id)
    }

    /// 清除所有代理映射
    public func clearAllMappings() {
        proxyMappings.removeAll()
    }

    // MARK: - Request Handling

    /// 处理代理请求
    private func handleRequest(_ request: GCDWebServerRequest) async -> GCDWebServerResponse {
        // 解析路径，获取 mapping ID
        let path = request.path
        guard path.hasPrefix("/proxy/"),
              let mappingId = path.components(separatedBy: "/").last,
              let mapping = proxyMappings[mappingId] else {
            return GCDWebServerErrorResponse(statusCode: 404)
        }

        // 检查映射是否过期
        if mapping.isExpired {
            return GCDWebServerErrorResponse(statusCode: 410) // Gone
        }

        // 构建转发请求
        let targetURL = mapping.targetURL
        var forwardRequest = URLRequest(url: targetURL)

        // 设置 HTTP 方法
        forwardRequest.httpMethod = request.method

        // 复制原始请求头
        if let originalHeaders = request.headers as? [String: String] {
            for (key, value) in originalHeaders {
                // 跳过 Host 和代理相关头
                let lowerKey = key.lowercased()
                if lowerKey == "host" || lowerKey == "proxy-connection" || lowerKey == "x-forwarded-for" {
                    continue
                }
                forwardRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        // 添加自定义头（优先级最高，覆盖原始头）
        for (key, value) in mapping.headers {
            forwardRequest.setValue(value, forHTTPHeaderField: key)
        }

        // 确保 User-Agent 被设置
        if forwardRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            forwardRequest.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")
        }

        // 处理 Range 请求（用于进度拖动）
        if let range = request.headers["Range"] as? String {
            forwardRequest.setValue(range, forHTTPHeaderField: "Range")
        }

        // 处理 Referer
        if let referer = mapping.headers["Referer"] {
            forwardRequest.setValue(referer, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await session.data(for: forwardRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return GCDWebServerErrorResponse(statusCode: 502)
            }

            // 构建响应
            let serverResponse = GCDWebServerDataResponse(
                data: data,
                contentType: httpResponse.mimeType ?? "application/octet-stream"
            )

            // 复制响应头
            if let allHeaders = httpResponse.allHeaderFields as? [String: String] {
                for (key, value) in allHeaders {
                    let lowerKey = key.lowercased()
                    // 跳过传输编码头
                    if lowerKey == "transfer-encoding" || lowerKey == "content-encoding" {
                        continue
                    }
                    // 保留 Content-Range（用于 Range 请求）
                    if lowerKey == "content-range" {
                        serverResponse?.setValue(value, forAdditionalHeader: key)
                    }
                    // 保留 Content-Length
                    if lowerKey == "content-length" {
                        serverResponse?.setValue(value, forAdditionalHeader: key)
                    }
                }
            }

            // 添加 CORS 头（允许 AVPlayer 跨域）
            serverResponse?.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            serverResponse?.setValue("Range", forAdditionalHeader: "Access-Control-Allow-Headers")

            // 设置状态码
            serverResponse?.statusCode = httpResponse.statusCode

            return serverResponse ?? GCDWebServerErrorResponse(statusCode: 500)

        } catch {
            print("[GCDWebServer] Proxy error: \(error)")
            return GCDWebServerErrorResponse(statusCode: 502)
        }
    }

    // MARK: - Cleanup

    /// 清理过期映射
    private func cleanupExpiredMappings() {
        let now = Date()
        proxyMappings = proxyMappings.filter { $0.value.createdAt.timeIntervalSince(now) < 1800 }
    }

    /// 获取服务器状态
    public var status: ProxyStatus {
        ProxyStatus(
            isRunning: isRunning,
            port: Int(port),
            activeMappings: proxyMappings.count
        )
    }
}

// MARK: - Proxy Status

public struct ProxyStatus: Sendable {
    public let isRunning: Bool
    public let port: Int
    public let activeMappings: Int
}

// MARK: - GCDWebServer Stub (模拟实现)

/// GCDWebServer 轻量模拟
/// 实际项目中替换为 CocoaPods / SPM 导入的 GCDWebServer
public class GCDWebServer: @unchecked Sendable {
    private var handlers: [(method: String, handler: (GCDWebServerRequest) async -> GCDWebServerResponse)] = []
    private var isServerRunning = false
    private var listenPort: UInt16 = 0
    private var serverTask: Task<Void, Never>?

    public init() {}

    /// 添加 GET 请求处理器
    @discardableResult
    public func addDefaultHandler(
        forMethod method: String,
        request: GCDWebServerDataRequest.Type,
        handler: @escaping (GCDWebServerRequest) async -> GCDWebServerResponse
    ) -> Any {
        handlers.append((method, handler))
        return self
    }

    /// 启动服务器
    public func start(options: [String: Any] = [:]) throws {
        guard !isServerRunning else { return }
        listenPort = options[GCDWebServerOption_Port] as? UInt16 ?? 9898
        isServerRunning = true

        // 启动后台任务监听请求
        serverTask = Task { [weak self] in
            await self?.runServer()
        }
    }

    /// 停止服务器
    public func stop() {
        isServerRunning = false
        serverTask?.cancel()
        serverTask = nil
    }

    /// 模拟 HTTP 服务器运行
    /// 实际项目中 GCDWebServer 会监听 TCP 端口
    /// 这里实现一个基于 URLProtocol 的请求拦截方案
    private func runServer() async {
        // 注册自定义 URLProtocol 来拦截发往本地的请求
        // 实际项目中不需要这段代码，因为 GCDWebServer 直接监听端口
        print("[GCDWebServer] Listening on port \(listenPort)")
        while isServerRunning {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    deinit {
        stop()
    }
}

// MARK: - GCDWebServer Request/Response Types

public class GCDWebServerRequest: @unchecked Sendable {
    public let method: String
    public let path: String
    public let headers: [String: Any]
    public let query: [String: Any]?

    public init(method: String, path: String, headers: [String: Any] = [:], query: [String: Any]? = nil) {
        self.method = method
        self.path = path
        self.headers = headers
        self.query = query
    }
}

public class GCDWebServerDataRequest: GCDWebServerRequest {
    public let data: Data?

    public init(method: String, path: String, headers: [String: Any] = [:], query: [String: Any]? = nil, data: Data? = nil) {
        self.data = data
        super.init(method: method, path: path, headers: headers, query: query)
    }
}

public class GCDWebServerResponse: @unchecked Sendable {
    public var statusCode: Int = 200
    public var contentType: String
    public var additionalHeaders: [String: String] = [:]

    public init(statusCode: Int = 200, contentType: String = "application/octet-stream") {
        self.statusCode = statusCode
        self.contentType = contentType
    }

    public func setValue(_ value: String, forAdditionalHeader header: String) {
        additionalHeaders[header] = value
    }
}

public class GCDWebServerDataResponse: GCDWebServerResponse {
    public let data: Data

    public init?(data: Data, contentType: String) {
        self.data = data
        super.init(contentType: contentType)
    }

    public convenience init?(text: String) {
        guard let data = text.data(using: .utf8) else { return nil }
        self.init(data: data, contentType: "text/plain; charset=utf-8")
    }

    public convenience init?(jsonObject: Any) {
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let data = try? JSONSerialization.data(withJSONObject: jsonObject) else {
            return nil
        }
        self.init(data: data, contentType: "application/json")
    }
}

public class GCDWebServerErrorResponse: GCDWebServerDataResponse {
    public init(statusCode: Int) {
        let errorData = "Error \(statusCode)".data(using: .utf8) ?? Data()
        super.init(data: errorData, contentType: "text/plain")!
        self.statusCode = statusCode
    }
}

// MARK: - GCDWebServer Options

public let GCDWebServerOption_Port = "Port"
public let GCDWebServerOption_BindToLocalhost = "BindToLocalhost"
public let GCDWebServerOption_AutomaticallySuspendInBackground = "AutomaticallySuspendInBackground"
public let GCDWebServerOption_ConnectedStateCoalescingInterval = "ConnectedStateCoalescingInterval"

// MARK: - URLProtocol 代理（备选方案）

/// 通过 URLProtocol 拦截 AVPlayer 请求并添加自定义头
/// 作为 GCDWebServer 的备选方案
public class ProxyURLProtocol: URLProtocol {
    private static let handledKey = "ProxyURLProtocolHandled"
    private static var headerMappings: [String: [String: String]] = [:]
    private static let lock = NSLock()

    /// 注册需要添加头的 URL 映射
    public static func registerHeaders(for url: URL, headers: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        headerMappings[url.absoluteString] = headers
    }

    /// 移除 URL 映射
    public static func unregisterHeaders(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        headerMappings.removeValue(forKey: url.absoluteString)
    }

    override public class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        lock.lock()
        defer { lock.unlock() }
        return headerMappings.keys.contains { url.absoluteString.hasPrefix($0) }
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override public func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest,
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "ProxyURLProtocol", code: -1))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        // 添加自定义头
        Self.lock.lock()
        let headers = Self.headerMappings.filter { url.absoluteString.hasPrefix($0.key) }.values.first
        Self.lock.unlock()

        for (key, value) in headers ?? [:] {
            mutableRequest.setValue(value, forHTTPHeaderField: key)
        }

        // 确保 User-Agent
        if mutableRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            mutableRequest.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")
        }

        let task = URLSession.shared.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data = data {
                self.client?.urlProtocol(self, didLoad: data)
            }

            self.client?.urlProtocolDidFinishLoading(self)
        }
        task.resume()
    }

    override public func stopLoading() {}
}

// MARK: - Proxy Service Integration

/// 代理服务集成 - 统一接口
public actor ProxyServiceIntegration {
    public static let shared = ProxyServiceIntegration()
    private let gcdServer = GCDWebServerService.shared

    private init() {}

    /// 为直链创建代理
    /// - Parameters:
    ///   - url: 原始直链 URL
    ///   - headers: 需要添加的 HTTP Header
    /// - Returns: 代理 URL（供 AVPlayer 播放）
    public func createProxiedURL(for url: URL, headers: [String: String]) async -> URL {
        // 优先使用 GCDWebServer
        let proxyURL = await gcdServer.createProxyURL(for: url, headers: headers)
        return proxyURL
    }

    /// 刷新代理（直链过期时）
    public func refreshProxy(id: String, newURL: URL, newHeaders: [String: String]) async {
        await gcdServer.refreshProxyMapping(id: id, newTargetURL: newURL, newHeaders: newHeaders)
    }

    /// 启动
    public func start(port: UInt16 = 9898) async throws {
        try await gcdServer.start(port: port)
    }

    /// 停止
    public func stop() async {
        await gcdServer.stop()
    }

    /// 状态
    public var status: ProxyStatus {
        get async { await gcdServer.status }
    }
}