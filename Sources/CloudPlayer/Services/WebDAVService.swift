import Foundation

// MARK: - WebDAV Service

/// WebDAV 连接封装
public actor WebDAVService {
    private let session: URLSession
    private var baseURL: String = ""
    private var username: String = ""
    private var password: String = ""

    // MARK: - Initialization

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    public func configure(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.username = username
        self.password = password
    }

    // MARK: - Authentication

    private var authHeader: String {
        let loginString = "\(username):\(password)"
        guard let loginData = loginString.data(using: .utf8) else { return "" }
        return "Basic \(loginData.base64EncodedString())"
    }

    // MARK: - File Operations

    /// 列出目录内容（PROPFIND）
    public func listFiles(path: String) async throws -> [MediaFile] {
        let url = path.isEmpty ? baseURL : "\(baseURL)/\(path)"
        guard let requestURL = URL(string: url) else {
            throw WebDAVError.urlInvalid
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PROPFIND"
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        // WebDAV PROPFIND 请求体
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:getcontentlength/>
                <D:getcontenttype/>
                <D:getlastmodified/>
                <D:resourcetype/>
                <D:iscollection/>
            </D:prop>
        </D:propfind>
        """
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("无效的响应")
        }

        guard httpResponse.statusCode == 207 else {
            switch httpResponse.statusCode {
            case 401: throw WebDAVError.unauthorized
            case 404: throw WebDAVError.notFound
            default: throw WebDAVError.serverError(httpResponse.statusCode)
            }
        }

        return try parsePropfindResponse(data, basePath: path)
    }

    /// 下载文件 URL（返回临时 URL）
    public func getFileDownloadURL(path: String) async throws -> URL {
        let url = path.isEmpty ? baseURL : "\(baseURL)/\(path)"
        guard let requestURL = URL(string: url) else {
            throw WebDAVError.urlInvalid
        }

        // 对于基本认证，可以直接返回 URL 让 AVPlayer 处理
        // 或者返回一个临时代理 URL
        return requestURL
    }

    /// 获取文件内容（用于小文件）
    public func getFileData(path: String) async throws -> Data {
        let url = path.isEmpty ? baseURL : "\(baseURL)/\(path)"
        guard let requestURL = URL(string: url) else {
            throw WebDAVError.urlInvalid
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WebDAVError.downloadFailed
        }

        return data
    }

    /// 验证连接
    public func verifyConnection() async throws -> Bool {
        let url = baseURL
        guard let requestURL = URL(string: url) else {
            throw WebDAVError.urlInvalid
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "OPTIONS"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("CloudPlayer/1.0", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("无效的响应")
        }

        // WebDAV 服务器应返回 DAV 头
        let davHeader = httpResponse.allHeaderFields["DAV"] as? String
        return davHeader != nil && httpResponse.statusCode == 200
    }

    // MARK: - XML Parsing

    private func parsePropfindResponse(_ data: Data, basePath: String) throws -> [MediaFile] {
        let parser = WebDAVXMLParser(data: data, basePath: basePath)
        return try parser.parse()
    }
}

// MARK: - WebDAV XML Parser

private class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let basePath: String
    private var files: [MediaFile] = []
    private var currentElement: String = ""
    private var currentHref: String = ""
    private var currentDisplayName: String = ""
    private var currentContentLength: String = ""
    private var currentContentType: String = ""
    private var currentLastModified: String = ""
    private var isCollection: Bool = false
    private var isInResponse: Bool = false
    private var currentProperties: [String: String] = [:]

    init(data: Data, basePath: String) {
        self.parser = XMLParser(data: data)
        self.basePath = basePath
        super.init()
        self.parser.delegate = self
    }

    func parse() throws -> [MediaFile] {
        guard parser.parse() else {
            if let error = parser.parserError {
                throw WebDAVError.parseError(error.localizedDescription)
            }
            throw WebDAVError.parseError("XML 解析失败")
        }
        return files
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "response" || elementName.hasSuffix("}response") {
            isInResponse = true
            currentHref = ""
            currentDisplayName = ""
            currentContentLength = ""
            currentContentType = ""
            currentLastModified = ""
            isCollection = false
            currentProperties = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch currentElement {
        case "href" where isInResponse,
             "D:href" where isInResponse:
            currentHref = trimmed
        case "displayname" where isInResponse,
             "D:displayname" where isInResponse:
            currentDisplayName = trimmed
        case "getcontentlength" where isInResponse,
             "D:getcontentlength" where isInResponse:
            currentContentLength = trimmed
        case "getcontenttype" where isInResponse,
             "D:getcontenttype" where isInResponse:
            currentContentType = trimmed
        case "getlastmodified" where isInResponse,
             "D:getlastmodified" where isInResponse:
            currentLastModified = trimmed
        case "iscollection" where isInResponse,
             "D:iscollection" where isInResponse:
            isCollection = true
        case "resourcetype" where isInResponse,
             "D:resourcetype" where isInResponse:
            // 后续通过子元素判断
            break
        default:
            break
        }

        currentProperties[currentElement] = trimmed
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "response" || elementName.hasSuffix("}response") {
            guard !currentHref.isEmpty else { return }

            // 跳过根目录自身
            let hrefPath = currentHref.removingPercentEncoding ?? currentHref
            let basePathNormalized = basePath.isEmpty ? "/" : "/\(basePath)/"
            let hrefNormalized = hrefPath.hasSuffix("/") ? hrefPath : "\(hrefPath)/"

            if hrefNormalized == basePathNormalized || hrefNormalized == "/" {
                isInResponse = false
                return
            }

            // 提取文件名
            let name: String
            if !currentDisplayName.isEmpty {
                name = currentDisplayName
            } else {
                let href = currentHref.removingPercentEncoding ?? currentHref
                name = URL(string: href)?.lastPathComponent ?? ""
            }

            guard !name.isEmpty else {
                isInResponse = false
                return
            }

            // 构建相对路径
            let relativePath = currentHref
                .removingPercentEncoding?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? name

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let modified = dateFormatter.date(from: currentLastModified)

            let size = Int64(currentContentLength) ?? 0

            let file = MediaFile(
                name: name,
                path: relativePath,
                isDirectory: isCollection,
                size: size,
                modifiedAt: modified,
                mediaType: isCollection ? .unknown : MediaFile.detectMediaType(from: (name as NSString).pathExtension)
            )

            files.append(file)
            isInResponse = false
        }
    }
}

// MARK: - WebDAV Errors

public enum WebDAVError: LocalizedError, Sendable, Equatable {
    case urlInvalid
    case unauthorized
    case notFound
    case networkError(String)
    case serverError(Int)
    case downloadFailed
    case parseError(String)
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .urlInvalid: return "URL 格式无效"
        case .unauthorized: return "认证失败，请检查用户名和密码"
        case .notFound: return "资源不存在"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .serverError(let code): return "服务器错误 (\(code))"
        case .downloadFailed: return "下载失败"
        case .parseError(let msg): return "解析错误: \(msg)"
        case .notSupported: return "不支持的操作"
        }
    }
}