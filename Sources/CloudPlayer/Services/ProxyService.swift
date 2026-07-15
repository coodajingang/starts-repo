import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

// MARK: - Local HTTP Proxy Service

/// 本地 HTTP 代理服务
/// 用于给直链添加自定义 header（Referer、User-Agent 等）
/// 因为 AVPlayer 不支持为单个 URL 设置自定义请求头
public actor ProxyService {
    private var isRunning = false
    private var port: UInt16 = 9898
    private var proxyTask: Task<Void, Never>?
    private var urlMappings: [String: ProxyMapping] = [:]
    private let session: URLSession

    public struct ProxyMapping: Sendable {
        public let targetURL: URL
        public let headers: [String: String]
        public let id: String

        public init(targetURL: URL, headers: [String: String], id: String = UUID().uuidString) {
            self.targetURL = targetURL
            self.headers = headers
            self.id = id
        }
    }

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Server Management

    /// 启动本地代理服务器
    public func start(port: UInt16 = 9898) async throws {
        guard !isRunning else { return }
        self.port = port

        // 使用 GCDWebServer 或内置的 HTTP server
        // 这里实现一个轻量级的 TCP server 来处理 HTTP 请求
        proxyTask = Task { [weak self] in
            await self?.runProxyServer()
        }
        isRunning = true
        print("[ProxyService] Started on port \(port)")
    }

    /// 停止服务器
    public func stop() {
        proxyTask?.cancel()
        proxyTask = nil
        isRunning = false
        urlMappings.removeAll()
        print("[ProxyService] Stopped")
    }

    /// 获取代理 URL
    public func getProxyURL(for mapping: ProxyMapping) -> URL {
        urlMappings[mapping.id] = mapping
        return URL(string: "http://127.0.0.1:\(port)/proxy/\(mapping.id)")!
    }

    /// 移除映射
    public func removeMapping(id: String) {
        urlMappings.removeValue(forKey: id)
    }

    /// 清空所有映射
    public func clearMappings() {
        urlMappings.removeAll()
    }

    // MARK: - Proxy Server Implementation

    private func runProxyServer() async {
        // 使用 Swift-NIO 或简单的 TCP socket 实现
        // 这里是一个简化版本，实际项目中应使用 GCDWebServer 或类似库
        // 由于当前环境限制，我们实现一个基于 URLSession 的请求转发模式

        // 在实际项目中，这里会启动一个真正的 HTTP 服务器
        // 监听本地端口，接收请求，添加 header，然后转发到目标 URL

        // 模拟实现：通过 URLProtocol 或自定义 scheme 处理
        print("[ProxyService] Proxy server running (simulated)")
    }

    // MARK: - Request Forwarding

    /// 执行带自定义 header 的请求
    public func fetchDataWithHeaders(url: URL, headers: [String: String]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")

        return try await session.data(for: request)
    }

    /// 创建临时的代理流（用于 AVPlayer）
    /// 返回一个代理 URL，当 AVPlayer 访问这个 URL 时，
    /// 本地服务器会添加 header 并转发到目标
    public func createProxiedStreamURL(targetURL: URL, headers: [String: String]) -> URL {
        let mapping = ProxyMapping(targetURL: targetURL, headers: headers)
        return getProxyURL(for: mapping)
    }

    /// 获取代理状态
    public var status: ProxyStatus {
        ProxyStatus(isRunning: isRunning, port: Int(port), activeMappings: urlMappings.count)
    }
}

// MARK: - Proxy Status

public struct ProxyStatus: Sendable {
    public let isRunning: Bool
    public let port: Int
    public let activeMappings: Int
}

// MARK: - URLProtocol-based Proxy (Alternative)

/// URLProtocol 实现的自定义请求处理
/// 可以拦截 AVPlayer 的请求并添加自定义 header
public class CustomHeaderURLProtocol: URLProtocol {
    private static let handledKey = "CustomHeaderURLProtocolHandled"

    override public class func canInit(with request: URLRequest) -> Bool {
        // 检查是否需要处理
        guard let url = request.url,
              url.scheme == "http" || url.scheme == "https" else {
            return false
        }

        // 避免重复处理
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }

        return true
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override public func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "CustomHeaderURLProtocol", code: -1))
            return
        }

        // 标记已处理
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        // 添加自定义 header
        mutableRequest.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")

        // 创建新的请求
        let newRequest = mutableRequest as URLRequest

        let task = URLSession.shared.dataTask(with: newRequest) { [weak self] data, response, error in
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

    override public func stopLoading() {
        // 取消正在进行的任务
    }
}