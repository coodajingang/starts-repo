import XCTest
@testable import CloudPlayer

// MARK: - MediaFile Tests

final class MediaFileTests: XCTestCase {
    func testDetectMediaType() {
        XCTAssertEqual(MediaFile.detectMediaType(from: "mp4"), .video)
        XCTAssertEqual(MediaFile.detectMediaType(from: "mkv"), .video)
        XCTAssertEqual(MediaFile.detectMediaType(from: "avi"), .video)
        XCTAssertEqual(MediaFile.detectMediaType(from: "mp3"), .audio)
        XCTAssertEqual(MediaFile.detectMediaType(from: "flac"), .audio)
        XCTAssertEqual(MediaFile.detectMediaType(from: "srt"), .subtitle)
        XCTAssertEqual(MediaFile.detectMediaType(from: "ass"), .subtitle)
        XCTAssertEqual(MediaFile.detectMediaType(from: "jpg"), .image)
        XCTAssertEqual(MediaFile.detectMediaType(from: "png"), .image)
        XCTAssertEqual(MediaFile.detectMediaType(from: "txt"), .unknown)
        XCTAssertEqual(MediaFile.detectMediaType(from: "pdf"), .unknown)
    }

    func testIsVideoFile() {
        XCTAssertTrue(MediaFile.isVideoFile("movie.mp4"))
        XCTAssertTrue(MediaFile.isVideoFile("movie.MKV"))
        XCTAssertFalse(MediaFile.isVideoFile("song.mp3"))
        XCTAssertFalse(MediaFile.isVideoFile("subtitle.srt"))
    }

    func testIsSubtitleFile() {
        XCTAssertTrue(MediaFile.isSubtitleFile("sub.srt"))
        XCTAssertTrue(MediaFile.isSubtitleFile("sub.ass"))
        XCTAssertFalse(MediaFile.isSubtitleFile("movie.mp4"))
        XCTAssertFalse(MediaFile.isSubtitleFile("song.mp3"))
    }

    func testFileExtension() {
        let file = MediaFile(name: "movie.mp4", path: "/movies/movie.mp4", isDirectory: false)
        XCTAssertEqual(file.fileExtension, "mp4")
    }

    func testFormattedSize() {
        let smallFile = MediaFile(name: "small.txt", path: "/small.txt", isDirectory: false, size: 1024)
        XCTAssertTrue(smallFile.formattedSize.contains("1"))

        let largeFile = MediaFile(name: "large.mp4", path: "/large.mp4", isDirectory: false, size: 1_073_741_824)
        XCTAssertTrue(largeFile.formattedSize.contains("1"))
    }

    func testAlistFileItemToMediaFile() {
        let item = AlistFileItem(
            name: "test.mp4",
            size: 1024,
            isDir: false,
            modified: "2024-01-15T10:30:00Z",
            hash: "abc123",
            sign: "signature",
            thumb: nil,
            type: 1,
            rawURL: nil,
            readme: nil
        )

        let mediaFile = item.toMediaFile(parentPath: "/videos")
        XCTAssertEqual(mediaFile.name, "test.mp4")
        XCTAssertEqual(mediaFile.path, "/videos/test.mp4")
        XCTAssertFalse(mediaFile.isDirectory)
        XCTAssertEqual(mediaFile.size, 1024)
        XCTAssertEqual(mediaFile.mediaType, .video)
    }

    func testAlistFileItemToMediaFileDirectory() {
        let item = AlistFileItem(
            name: "folder",
            size: 0,
            isDir: true,
            modified: nil,
            hash: nil,
            sign: nil,
            thumb: nil,
            type: 0,
            rawURL: nil,
            readme: nil
        )

        let mediaFile = item.toMediaFile(parentPath: "")
        XCTAssertEqual(mediaFile.name, "folder")
        XCTAssertTrue(mediaFile.isDirectory)
        XCTAssertEqual(mediaFile.mediaType, .unknown)
    }
}

// MARK: - DriveConnection Tests

final class DriveConnectionTests: XCTestCase {
    func testAlistConnection() {
        let connection = DriveConnection(
            name: "Test Alist",
            type: .alist,
            url: "https://alist.example.com",
            token: "mytoken"
        )
        XCTAssertEqual(connection.baseURL, "https://alist.example.com")
        XCTAssertEqual(connection.apiPath, "https://alist.example.com/api")
        XCTAssertTrue(connection.isAuthenticated)
    }

    func testWebDAVConnection() {
        let connection = DriveConnection(
            name: "Test WebDAV",
            type: .webdav,
            url: "https://webdav.example.com",
            username: "user",
            password: "pass"
        )
        XCTAssertTrue(connection.isAuthenticated)
    }

    func testLocalConnection() {
        let connection = DriveConnection(
            name: "Local",
            type: .local,
            url: "file:///"
        )
        XCTAssertTrue(connection.isAuthenticated)
    }

    func testUnauthenticatedConnection() {
        let connection = DriveConnection(
            name: "Empty",
            type: .webdav,
            url: "https://example.com"
        )
        XCTAssertFalse(connection.isAuthenticated)
    }

    func testBaseURLTrimming() {
        let connection = DriveConnection(
            name: "Test",
            type: .alist,
            url: "https://example.com/"
        )
        XCTAssertEqual(connection.baseURL, "https://example.com")
    }

    func testConnectionEquality() {
        let id = UUID()
        let conn1 = DriveConnection(id: id, name: "Test", type: .alist, url: "https://example.com")
        let conn2 = DriveConnection(id: id, name: "Renamed", type: .alist, url: "https://example.com")
        XCTAssertEqual(conn1, conn2)
    }
}

// MARK: - PlaybackState Tests

final class PlaybackStateTests: XCTestCase {
    func testInitialState() {
        let state = PlaybackState()
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.currentTime, 0)
        XCTAssertEqual(state.duration, 0)
        XCTAssertEqual(state.rate, 1.0)
        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.isPaused)
    }

    func testProgress() {
        let state = PlaybackState()
        // 不能直接设置，因为它是 let
        // 测试 progress 计算属性
        // 通过修改 currentTime 和 duration 来测试（它们现在是 var）
    }

    func testFormattedTime() {
        // 直接测试 formatTime 方法
        // 由于它是 private 的，我们通过状态来测试
    }
}

// MARK: - SubtitleLoader Tests

final class SubtitleLoaderTests: XCTestCase {
    func testParseSRT() async throws {
        let srtContent = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello World

        2
        00:00:05,000 --> 00:00:08,000
        Second subtitle
        """
        let loader = SubtitleLoader()
        let entries = await loader.loadSubtitles(from: srtContent, format: .srt)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "Hello World")
        XCTAssertEqual(entries[1].text, "Second subtitle")
        XCTAssertEqual(entries[0].startTime, 1.0)
        XCTAssertEqual(entries[0].endTime, 4.0)
    }

    func testEmptySRT() async {
        let loader = SubtitleLoader()
        let entries = await loader.loadSubtitles(from: "", format: .srt)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSubtitleAtTime() {
        let entries = [
            SubtitleLoader.SubtitleEntry(index: 1, startTime: 1.0, endTime: 4.0, text: "First"),
            SubtitleLoader.SubtitleEntry(index: 2, startTime: 5.0, endTime: 8.0, text: "Second")
        ]

        XCTAssertEqual(SubtitleLoader.subtitleAtTime(2.0, from: entries)?.text, "First")
        XCTAssertEqual(SubtitleLoader.subtitleAtTime(6.0, from: entries)?.text, "Second")
        XCTAssertNil(SubtitleLoader.subtitleAtTime(0.5, from: entries))
        XCTAssertNil(SubtitleLoader.subtitleAtTime(9.0, from: entries))
    }

    func testFindAssociatedSubtitles() {
        let videoFile = MediaFile(name: "movie.mp4", path: "/videos/movie.mp4", isDirectory: false)
        let subtitleFiles = [
            MediaFile(name: "movie.srt", path: "/videos/movie.srt", isDirectory: false, mediaType: .subtitle),
            MediaFile(name: "movie.ass", path: "/videos/movie.ass", isDirectory: false, mediaType: .subtitle),
            MediaFile(name: "other.srt", path: "/videos/other.srt", isDirectory: false, mediaType: .subtitle),
            MediaFile(name: "poster.jpg", path: "/videos/poster.jpg", isDirectory: false, mediaType: .image)
        ]

        let found = SubtitleLoader.findAssociatedSubtitles(
            for: videoFile.path,
            availableFiles: subtitleFiles
        )
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains(where: { $0.name == "movie.srt" }))
        XCTAssertTrue(found.contains(where: { $0.name == "movie.ass" }))
    }
}

// MARK: - AlistService Tests

final class AlistServiceTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertEqual(AlistError.urlInvalid.errorDescription, "URL 格式无效")
        XCTAssertEqual(AlistError.unauthorized.errorDescription, "未授权，请重新登录")
        XCTAssertEqual(AlistError.timeout.errorDescription, "请求超时")
        XCTAssertTrue(AlistError.serverError(500).errorDescription?.contains("500") ?? false)
    }

    func testPlaybackErrorDescriptions() {
        XCTAssertEqual(PlaybackError.urlInvalid.errorDescription, "无效的播放地址")
        XCTAssertEqual(PlaybackError.unsupportedFormat.errorDescription, "不支持的格式")
        XCTAssertEqual(PlaybackError.timeout.errorDescription, "请求超时")
    }

    func testWebDAVErrorDescriptions() {
        XCTAssertEqual(WebDAVError.unauthorized.errorDescription, "认证失败，请检查用户名和密码")
        XCTAssertEqual(WebDAVError.notFound.errorDescription, "资源不存在")
    }

    func testLocalFileErrorDescriptions() {
        XCTAssertEqual(LocalFileError.pathNotFound.errorDescription, "路径不存在")
    }
}

// MARK: - PreferencesManager Tests

final class PreferencesManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // 保存原始值
    }

    override func tearDown() {
        super.tearDown()
        // 恢复原始值
    }

    func testDefaultValues() {
        XCTAssertEqual(PreferencesManager.playbackSpeed, 1.0)
        XCTAssertEqual(PreferencesManager.playbackVolume, 1.0)
        XCTAssertTrue(PreferencesManager.subtitleEnabled)
        XCTAssertEqual(PreferencesManager.subtitleSize, 16)
        XCTAssertEqual(PreferencesManager.connectTimeout, 30.0)
        XCTAssertEqual(PreferencesManager.autoRefreshInterval, 1800.0)
        XCTAssertEqual(PreferencesManager.appearanceMode, .system)
    }

    func testSaveAndLoadPlaybackSpeed() {
        PreferencesManager.playbackSpeed = 1.5
        XCTAssertEqual(PreferencesManager.playbackSpeed, 1.5)
        PreferencesManager.playbackSpeed = 1.0 // 恢复
    }

    func testSaveAndLoadConnections() {
        let connections = [
            DriveConnection(name: "Test1", type: .alist, url: "https://test1.com"),
            DriveConnection(name: "Test2", type: .webdav, url: "https://test2.com")
        ]
        PreferencesManager.saveConnections(connections)
        let loaded = PreferencesManager.loadConnections()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Test1")
        XCTAssertEqual(loaded[1].name, "Test2")
    }
}

// MARK: - PlatformUtils Tests

final class PlatformUtilsTests: XCTestCase {
    func testPlatformConstants() {
        XCTAssertGreaterThan(PlatformConstants.minimumTapTarget, 0)
        XCTAssertGreaterThan(PlatformConstants.listRowHeight, 0)
        XCTAssertGreaterThan(PlatformConstants.thumbnailSize.width, 0)
        XCTAssertGreaterThan(PlatformConstants.thumbnailSize.height, 0)
        XCTAssertGreaterThan(PlatformConstants.spacing, 0)
        XCTAssertGreaterThan(PlatformConstants.cornerRadius, 0)
    }

    func testAvailablePlaybackSpeeds() {
        XCTAssertTrue(availablePlaybackSpeeds.contains(1.0))
        XCTAssertTrue(availablePlaybackSpeeds.contains(0.5))
        XCTAssertTrue(availablePlaybackSpeeds.contains(2.0))
        XCTAssertTrue(availablePlaybackSpeeds.contains(3.0))
        XCTAssertFalse(availablePlaybackSpeeds.contains(3.5))
        // 验证排序
        XCTAssertEqual(availablePlaybackSpeeds, availablePlaybackSpeeds.sorted())
    }
}

// MARK: - PlaybackRecord Tests

final class PlaybackRecordTests: XCTestCase {
    func testRecordCreation() {
        let sourceID = UUID()
        let record = PlaybackRecord(
            mediaName: "test.mp4",
            mediaPath: "/videos/test.mp4",
            sourceID: sourceID,
            sourceName: "Test Server",
            duration: 120.0,
            position: 30.0
        )

        XCTAssertEqual(record.mediaName, "test.mp4")
        XCTAssertEqual(record.progress, 0.25, accuracy: 0.001)
        XCTAssertFalse(record.isFinished)
    }

    func testFinishedRecord() {
        let record = PlaybackRecord(
            mediaName: "test.mp4",
            mediaPath: "/videos/test.mp4",
            sourceID: UUID(),
            sourceName: "Test",
            duration: 100.0,
            position: 100.0,
            isFinished: true
        )
        XCTAssertTrue(record.isFinished)
        XCTAssertEqual(record.progress, 1.0)
    }

    func testZeroDuration() {
        let record = PlaybackRecord(
            mediaName: "test.mp4",
            mediaPath: "/videos/test.mp4",
            sourceID: UUID(),
            sourceName: "Test",
            duration: 0,
            position: 0
        )
        XCTAssertEqual(record.progress, 0)
    }
}

// MARK: - MediaPlayerService Tests

final class MediaPlayerServiceTests: XCTestCase {
    func testInitialState() {
        let service = MediaPlayerService()
        XCTAssertEqual(service.state.status, .idle)
        XCTAssertFalse(service.state.isPlaying)
    }

    func testRateValidation() {
        let service = MediaPlayerService()
        // 在 actor 中设置速率
        // 通过 PlaybackState 验证
        XCTAssertEqual(service.state.rate, 1.0)
    }
}