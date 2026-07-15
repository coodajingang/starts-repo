import Foundation
import UniformTypeIdentifiers

// MARK: - Local File Service

/// 本地文件浏览服务
public actor LocalFileService {
    // MARK: - Directory Listing

    /// 列出本地目录内容
    public func listFiles(at path: String) throws -> [MediaFile] {
        let url = URL(fileURLWithPath: path.isEmpty ? "/" : path)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalFileError.pathNotFound
        }

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { fileURL -> MediaFile? in
            let resourceValues = try? fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])

            let isDirectory = resourceValues?.isDirectory ?? false
            let fileSize = resourceValues?.fileSize ?? 0
            let modifiedDate = resourceValues?.contentModificationDate

            let name = fileURL.lastPathComponent
            let ext = fileURL.pathExtension

            // 跳过隐藏文件
            guard !name.hasPrefix(".") else { return nil }

            return MediaFile(
                name: name,
                path: fileURL.path,
                isDirectory: isDirectory,
                size: Int64(fileSize),
                modifiedAt: modifiedDate,
                mediaType: isDirectory ? .unknown : MediaFile.detectMediaType(from: ext),
                rawURL: fileURL.absoluteString
            )
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 获取本地文件 URL
    public func fileURL(for path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    /// 检查文件是否存在
    public func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// 获取可浏览的根目录
    public func getAvailableRoots() -> [MediaFile] {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let documentDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let downloadDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let desktopDir = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
        let movieDir = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
        let musicDir = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first

        var roots: [MediaFile] = []

        if let doc = documentDir {
            roots.append(MediaFile(
                name: "文档",
                path: doc.path,
                isDirectory: true,
                mediaType: .unknown
            ))
        }

        if let download = downloadDir {
            roots.append(MediaFile(
                name: "下载",
                path: download.path,
                isDirectory: true,
                mediaType: .unknown
            ))
        }

        if let desktop = desktopDir {
            roots.append(MediaFile(
                name: "桌面",
                path: desktop.path,
                isDirectory: true,
                mediaType: .unknown
            ))
        }

        if let movie = movieDir {
            roots.append(MediaFile(
                name: "视频",
                path: movie.path,
                isDirectory: true,
                mediaType: .unknown
            ))
        }

        if let music = musicDir {
            roots.append(MediaFile(
                name: "音乐",
                path: music.path,
                isDirectory: true,
                mediaType: .unknown
            ))
        }

        // 添加外部卷宗
        if let volumes = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: [.isVolumeKey],
            options: [.skipsHiddenFiles]
        ) {
            for volume in volumes {
                let name = volume.lastPathComponent
                guard !name.hasPrefix(".") else { continue }
                roots.append(MediaFile(
                    name: "卷宗: \(name)",
                    path: volume.path,
                    isDirectory: true,
                    mediaType: .unknown
                ))
            }
        }

        return roots
    }

    /// 获取文件的 UTType
    public func getFileType(at path: String) -> UTType? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        return UTType(filenameExtension: ext)
    }
}

// MARK: - Local File Errors

public enum LocalFileError: LocalizedError, Sendable, Equatable {
    case pathNotFound
    case permissionDenied
    case readError(String)

    public var errorDescription: String? {
        switch self {
        case .pathNotFound: return "路径不存在"
        case .permissionDenied: return "没有访问权限"
        case .readError(let msg): return "读取错误: \(msg)"
        }
    }
}