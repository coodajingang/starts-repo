import Foundation
import SwiftData
import SwiftUI

// MARK: - SwiftData Models

/// 连接配置（SwiftData 版本）
@Model
public final class SwiftDataConnection {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var typeRaw: String // DriveSourceType rawValue
    public var url: String
    public var username: String
    public var isActive: Bool
    public var createdAt: Date
    public var lastAccessedAt: Date?

    // 关系
    @Relationship(deleteRule: .cascade) public var playbackRecords: [SwiftDataPlaybackRecord]?

    public var type: DriveSourceType {
        get { DriveSourceType(rawValue: typeRaw) ?? .alist }
        set { typeRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), name: String, type: DriveSourceType, url: String,
                username: String = "", isActive: Bool = true,
                createdAt: Date = Date(), lastAccessedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.url = url
        self.username = username
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    /// 转回 Model 层
    public func toDriveConnection() -> DriveConnection {
        DriveConnection(
            id: id,
            name: name,
            type: type,
            url: url,
            username: username,
            isActive: isActive,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
    }
}

// MARK: - Playback Record (SwiftData)

/// 播放记录（SwiftData 版本）
@Model
public final class SwiftDataPlaybackRecord {
    @Attribute(.unique) public var id: UUID
    public var mediaName: String
    public var mediaPath: String
    public var sourceID: UUID
    public var sourceName: String
    public var duration: Double
    public var position: Double
    public var rate: Float
    public var lastPlayedAt: Date
    public var isFinished: Bool
    public var playCount: Int

    // 外键关系
    public var connection: SwiftDataConnection?

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return position / duration
    }

    public init(id: UUID = UUID(), mediaName: String, mediaPath: String,
                sourceID: UUID, sourceName: String, duration: Double,
                position: Double, rate: Float = 1.0, lastPlayedAt: Date = Date(),
                isFinished: Bool = false, playCount: Int = 1) {
        self.id = id
        self.mediaName = mediaName
        self.mediaPath = mediaPath
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.duration = duration
        self.position = position
        self.rate = rate
        self.lastPlayedAt = lastPlayedAt
        self.isFinished = isFinished
        self.playCount = playCount
    }

    /// 转回 Model 层
    public func toPlaybackRecord() -> PlaybackRecord {
        PlaybackRecord(
            id: id,
            mediaName: mediaName,
            mediaPath: mediaPath,
            sourceID: sourceID,
            sourceName: sourceName,
            duration: duration,
            position: position,
            rate: rate,
            lastPlayedAt: lastPlayedAt,
            isFinished: isFinished
        )
    }
}

// MARK: - Favorite (SwiftData)

/// 收藏
@Model
public final class SwiftDataFavorite {
    @Attribute(.unique) public var id: UUID
    public var mediaName: String
    public var mediaPath: String
    public var sourceID: UUID
    public var sourceName: String
    public var mediaTypeRaw: String
    public var size: Int64
    public var addedAt: Date

    public var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRaw) ?? .unknown }
        set { mediaTypeRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), mediaName: String, mediaPath: String,
                sourceID: UUID, sourceName: String, mediaType: MediaType,
                size: Int64 = 0, addedAt: Date = Date()) {
        self.id = id
        self.mediaName = mediaName
        self.mediaPath = mediaPath
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.mediaTypeRaw = mediaType.rawValue
        self.size = size
        self.addedAt = addedAt
    }
}

// MARK: - Playback History (SwiftData)

/// 播放历史条目
@Model
public final class SwiftDataPlaybackHistory {
    @Attribute(.unique) public var id: UUID
    public var mediaName: String
    public var mediaPath: String
    public var sourceID: UUID
    public var sourceName: String
    public var position: Double
    public var duration: Double
    public var playedAt: Date
    public var isFromHistory: Bool

    public init(id: UUID = UUID(), mediaName: String, mediaPath: String,
                sourceID: UUID, sourceName: String, position: Double,
                duration: Double, playedAt: Date = Date(), isFromHistory: Bool = false) {
        self.id = id
        self.mediaName = mediaName
        self.mediaPath = mediaPath
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.position = position
        self.duration = duration
        self.playedAt = playedAt
        self.isFromHistory = isFromHistory
    }
}

// MARK: - SwiftData Manager

/// SwiftData 管理器 - 统一的数据持久化层
@MainActor
public final class SwiftDataManager: @unchecked Sendable {
    public static let shared = SwiftDataManager()

    private var container: ModelContainer?
    private var context: ModelContext?

    private init() {}

    // MARK: - Setup

    /// 初始化 SwiftData 容器
    /// - Parameter cloudSync: 是否启用 iCloud 同步
    public func setup(cloudSync: Bool = false) {
        let schema = Schema([
            SwiftDataConnection.self,
            SwiftDataPlaybackRecord.self,
            SwiftDataFavorite.self,
            SwiftDataPlaybackHistory.self
        ])

        let configuration: ModelConfiguration
        if cloudSync {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
        }

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = container?.mainContext
            print("[SwiftDataManager] Initialized successfully")
        } catch {
            print("[SwiftDataManager] Failed to initialize: \(error)")
        }
    }

    /// 获取 ModelContext
    public func getContext() -> ModelContext? {
        context
    }

    // MARK: - Connection Operations

    /// 保存连接
    public func saveConnection(_ connection: DriveConnection) {
        guard let context = context else { return }

        let existing = fetchConnection(by: connection.id)
        if let existing = existing {
            // 更新
            existing.name = connection.name
            existing.url = connection.url
            existing.username = connection.username
            existing.isActive = connection.isActive
            existing.lastAccessedAt = Date()
        } else {
            // 新增
            let sdConnection = SwiftDataConnection(
                id: connection.id,
                name: connection.name,
                type: connection.type,
                url: connection.url,
                username: connection.username,
                isActive: connection.isActive,
                createdAt: connection.createdAt,
                lastAccessedAt: Date()
            )
            context.insert(sdConnection)
        }

        saveContext()
    }

    /// 获取所有连接
    public func fetchAllConnections() -> [DriveConnection] {
        guard let context = context else { return [] }
        let descriptor = FetchDescriptor<SwiftDataConnection>(
            sort: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.map { $0.toDriveConnection() } ?? []
    }

    /// 获取单个连接
    public func fetchConnection(by id: UUID) -> SwiftDataConnection? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<SwiftDataConnection>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    /// 删除连接
    public func deleteConnection(_ id: UUID) {
        guard let context = context,
              let connection = fetchConnection(by: id) else { return }
        context.delete(connection)
        saveContext()
    }

    // MARK: - Playback Record Operations

    /// 保存播放记录
    public func savePlaybackRecord(_ record: PlaybackRecord) {
        guard let context = context else { return }

        // 查找是否已有记录
        let descriptor = FetchDescriptor<SwiftDataPlaybackRecord>(
            predicate: #Predicate { $0.mediaPath == record.mediaPath && $0.sourceID == record.sourceID }
        )
        let existing = try? context.fetch(descriptor).first

        if let existing = existing {
            // 更新
            existing.position = record.position
            existing.rate = record.rate
            existing.lastPlayedAt = Date()
            existing.isFinished = record.isFinished
            existing.duration = record.duration
            existing.playCount += 1
        } else {
            // 新增
            let sdRecord = SwiftDataPlaybackRecord(
                mediaName: record.mediaName,
                mediaPath: record.mediaPath,
                sourceID: record.sourceID,
                sourceName: record.sourceName,
                duration: record.duration,
                position: record.position,
                rate: record.rate,
                lastPlayedAt: Date(),
                isFinished: record.isFinished
            )
            context.insert(sdRecord)

            // 同步保存播放历史
            savePlaybackHistory(record)
        }

        saveContext()
    }

    /// 获取所有播放记录
    public func fetchAllPlaybackRecords() -> [PlaybackRecord] {
        guard let context = context else { return [] }
        let descriptor = FetchDescriptor<SwiftDataPlaybackRecord>(
            sort: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.map { $0.toPlaybackRecord() } ?? []
    }

    /// 获取未完成的播放记录（继续播放）
    public func fetchUnfinishedRecords() -> [PlaybackRecord] {
        guard let context = context else { return [] }
        let descriptor = FetchDescriptor<SwiftDataPlaybackRecord>(
            predicate: #Predicate { !$0.isFinished && $0.position > 0 },
            sort: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.map { $0.toPlaybackRecord() } ?? []
    }

    /// 获取特定媒体的播放记录
    public func fetchRecord(for path: String, sourceID: UUID) -> PlaybackRecord? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<SwiftDataPlaybackRecord>(
            predicate: #Predicate { $0.mediaPath == path && $0.sourceID == sourceID }
        )
        return (try? context.fetch(descriptor).first)?.toPlaybackRecord()
    }

    /// 删除播放记录
    public func deletePlaybackRecord(_ id: UUID) {
        guard let context = context else { return }
        let descriptor = FetchDescriptor<SwiftDataPlaybackRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try? context.fetch(descriptor).first {
            context.delete(record)
            saveContext()
        }
    }

    /// 清除所有播放记录
    public func clearAllPlaybackRecords() {
        guard let context = context else { return }
        let descriptor = FetchDescriptor<SwiftDataPlaybackRecord>()
        if let records = try? context.fetch(descriptor) {
            records.forEach { context.delete($0) }
            saveContext()
        }
    }

    // MARK: - Favorite Operations

    /// 收藏
    public func addFavorite(_ file: MediaFile, sourceID: UUID, sourceName: String) {
        guard let context = context else { return }

        let descriptor = FetchDescriptor<SwiftDataFavorite>(
            predicate: #Predicate { $0.mediaPath == file.path && $0.sourceID == sourceID }
        )
        if (try? context.fetch(descriptor).first) != nil {
            return // 已收藏
        }

        let favorite = SwiftDataFavorite(
            mediaName: file.name,
            mediaPath: file.path,
            sourceID: sourceID,
            sourceName: sourceName,
            mediaType: file.mediaType,
            size: file.size
        )
        context.insert(favorite)
        saveContext()
    }

    /// 取消收藏
    public func removeFavorite(_ path: String, sourceID: UUID) {
        guard let context = context else { return }
        let descriptor = FetchDescriptor<SwiftDataFavorite>(
            predicate: #Predicate { $0.mediaPath == path && $0.sourceID == sourceID }
        )
        if let favorite = try? context.fetch(descriptor).first {
            context.delete(favorite)
            saveContext()
        }
    }

    /// 获取所有收藏
    public func fetchAllFavorites() -> [SwiftDataFavorite] {
        guard let context = context else { return [] }
        let descriptor = FetchDescriptor<SwiftDataFavorite>(
            sort: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 检查是否已收藏
    public func isFavorite(_ path: String, sourceID: UUID) -> Bool {
        guard let context = context else { return false }
        let descriptor = FetchDescriptor<SwiftDataFavorite>(
            predicate: #Predicate { $0.mediaPath == path && $0.sourceID == sourceID }
        )
        return (try? context.fetch(descriptor).first) != nil
    }

    // MARK: - Playback History

    /// 保存播放历史
    private func savePlaybackHistory(_ record: PlaybackRecord) {
        guard let context = context else { return }

        // 限制历史记录数量（保留最近 500 条）
        let countDescriptor = FetchDescriptor<SwiftDataPlaybackHistory>()
        if let count = try? context.fetchCount(countDescriptor), count >= 500 {
            // 删除最旧的记录
            let deleteDescriptor = FetchDescriptor<SwiftDataPlaybackHistory>(
                sort: [SortDescriptor(\.playedAt, order: .forward)]
            )
            if let oldest = try? context.fetch(deleteDescriptor).first {
                context.delete(oldest)
            }
        }

        let history = SwiftDataPlaybackHistory(
            mediaName: record.mediaName,
            mediaPath: record.mediaPath,
            sourceID: record.sourceID,
            sourceName: record.sourceName,
            position: record.position,
            duration: record.duration,
            playedAt: Date()
        )
        context.insert(history)
        saveContext()
    }

    /// 获取播放历史
    public func fetchPlaybackHistory(limit: Int = 100) -> [SwiftDataPlaybackHistory] {
        guard let context = context else { return [] }
        var descriptor = FetchDescriptor<SwiftDataPlaybackHistory>(
            sort: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Statistics

    /// 获取统计数据
    public func getStatistics() -> PlaybackStatistics {
        guard let context = context else { return PlaybackStatistics() }

        let allRecords = fetchAllPlaybackRecords()
        let totalPlayTime = allRecords.reduce(0.0) { $0 + $1.position }
        let totalFiles = allRecords.count
        let unfinishedCount = allRecords.filter { !$0.isFinished }.count
        let favoriteCount = fetchAllFavorites().count

        return PlaybackStatistics(
            totalFiles: totalFiles,
            totalPlayTime: totalPlayTime,
            unfinishedCount: unfinishedCount,
            favoriteCount: favoriteCount,
            connectionCount: fetchAllConnections().count
        )
    }

    // MARK: - Context Save

    private func saveContext() {
        guard let context = context else { return }
        do {
            try context.save()
        } catch {
            print("[SwiftDataManager] Save failed: \(error)")
        }
    }

    /// 手动保存
    public func save() {
        saveContext()
    }

    // MARK: - Migration from UserDefaults

    /// 从 UserDefaults 迁移数据到 SwiftData
    public func migrateFromUserDefaults() {
        // 迁移播放记录
        let oldRecords = loadOldPlaybackRecords()
        for record in oldRecords {
            savePlaybackRecord(record)
        }

        // 迁移连接配置
        let oldConnections = PreferencesManager.loadConnections()
        for connection in oldConnections {
            saveConnection(connection)
        }

        print("[SwiftDataManager] Migrated \(oldRecords.count) records and \(oldConnections.count) connections")
    }

    private func loadOldPlaybackRecords() -> [PlaybackRecord] {
        guard let data = UserDefaults.standard.data(forKey: "playback_records"),
              let records = try? JSONDecoder().decode([PlaybackRecord].self, from: data) else {
            return []
        }
        // 清除旧数据
        UserDefaults.standard.removeObject(forKey: "playback_records")
        return records
    }
}

// MARK: - Playback Statistics

public struct PlaybackStatistics: Sendable {
    public let totalFiles: Int
    public let totalPlayTime: Double
    public let unfinishedCount: Int
    public let favoriteCount: Int
    public let connectionCount: Int

    public init(totalFiles: Int = 0, totalPlayTime: Double = 0,
                unfinishedCount: Int = 0, favoriteCount: Int = 0,
                connectionCount: Int = 0) {
        self.totalFiles = totalFiles
        self.totalPlayTime = totalPlayTime
        self.unfinishedCount = unfinishedCount
        self.favoriteCount = favoriteCount
        self.connectionCount = connectionCount
    }

    public var formattedTotalPlayTime: String {
        let hours = Int(totalPlayTime) / 3600
        let minutes = (Int(totalPlayTime) % 3600) / 60
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分钟"
        }
        return "\(minutes) 分钟"
    }
}

// MARK: - SwiftUI View Modifier

/// 注入 SwiftData 容器的 View Modifier
public struct InjectSwiftDataModifier: ViewModifier {
    let cloudSync: Bool

    public func body(content: Content) -> some View {
        content
            .onAppear {
                SwiftDataManager.shared.setup(cloudSync: cloudSync)
                #if DEBUG
                // 开发环境自动迁移
                SwiftDataManager.shared.migrateFromUserDefaults()
                #endif
            }
    }
}

public extension View {
    /// 注入 SwiftData 容器
    func withCloudPlayerData(cloudSync: Bool = false) -> some View {
        modifier(InjectSwiftDataModifier(cloudSync: cloudSync))
    }
}

// MARK: - SwiftData Query Wrapper

/// 方便 SwiftUI 使用的查询包装
@propertyWrapper
public struct SwiftDataQuery<T: PersistentModel>: DynamicProperty {
    @Query private var results: [T]

    public var wrappedValue: [T] {
        results
    }

    public init(sort: [SortDescriptor<T>] = []) {
        _results = Query(sort: sortBy)
    }

    public init(filter: Predicate<T>?, sort: [SortDescriptor<T>] = []) {
        _results = Query(filter: filter, sort: sortBy)
    }
}