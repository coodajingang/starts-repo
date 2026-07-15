import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

// MARK: - FFmpeg Demuxer Protocol

/// FFmpeg 解封装器协议
/// 用于处理 AVPlayer 原生不支持的格式
public protocol FFmpegDemuxerProtocol: AnyObject, Sendable {
    /// 打开媒体文件
    func open(url: URL) async throws -> MediaFormatInfo
    /// 读取下一帧
    func readNextFrame() async throws -> VideoFrame?
    /// 跳转到指定时间
    func seek(to time: Double) async throws
    /// 获取字幕轨道
    func getSubtitleTracks() -> [SubtitleTrackInfo]
    /// 获取音频轨道
    func getAudioTracks() -> [AudioTrackInfo]
    /// 关闭
    func close()
}

// MARK: - Media Format Info

/// 媒体格式信息
public struct MediaFormatInfo: Sendable, Equatable {
    public let duration: Double
    public let bitRate: Int64
    public let videoStreams: [VideoStreamInfo]
    public let audioStreams: [AudioStreamInfo]
    public let subtitleStreams: [SubtitleStreamInfo]
    public let metadata: [String: String]

    public init(
        duration: Double = 0,
        bitRate: Int64 = 0,
        videoStreams: [VideoStreamInfo] = [],
        audioStreams: [AudioStreamInfo] = [],
        subtitleStreams: [SubtitleStreamInfo] = [],
        metadata: [String: String] = [:]
    ) {
        self.duration = duration
        self.bitRate = bitRate
        self.videoStreams = videoStreams
        self.audioStreams = audioStreams
        self.subtitleStreams = subtitleStreams
        self.metadata = metadata
    }
}

// MARK: - Stream Info

public struct VideoStreamInfo: Sendable, Equatable {
    public let index: Int
    public let codec: String
    public let width: Int
    public let height: Int
    public let frameRate: Double
    public let bitRate: Int64
    public let isHardwareAccelerated: Bool

    public init(index: Int = 0, codec: String = "", width: Int = 0, height: Int = 0,
                frameRate: Double = 0, bitRate: Int64 = 0, isHardwareAccelerated: Bool = false) {
        self.index = index
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitRate = bitRate
        self.isHardwareAccelerated = isHardwareAccelerated
    }
}

public struct AudioStreamInfo: Sendable, Equatable {
    public let index: Int
    public let codec: String
    public let sampleRate: Int
    public let channels: Int
    public let bitRate: Int64
    public let language: String?

    public init(index: Int = 0, codec: String = "", sampleRate: Int = 0, channels: Int = 0,
                bitRate: Int64 = 0, language: String? = nil) {
        self.index = index
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
        self.language = language
    }
}

public struct SubtitleStreamInfo: Sendable, Equatable {
    public let index: Int
    public let codec: String
    public let language: String?
    public let isForced: Bool

    public init(index: Int = 0, codec: String = "", language: String? = nil, isForced: Bool = false) {
        self.index = index
        self.codec = codec
        self.language = language
        self.isForced = isForced
    }
}

public struct AudioTrackInfo: Sendable, Equatable {
    public let index: Int
    public let title: String
    public let language: String?
}

public struct SubtitleTrackInfo: Sendable, Equatable {
    public let index: Int
    public let title: String
    public let language: String?
}

// MARK: - Video Frame

/// 解码后的视频帧
public struct VideoFrame: Sendable {
    public let pixelBuffer: CVPixelBuffer?
    public let presentationTime: CMTime
    public let duration: CMTime
    public let isKeyFrame: Bool

    public init(pixelBuffer: CVPixelBuffer?, presentationTime: CMTime, duration: CMTime, isKeyFrame: Bool = false) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        self.duration = duration
        self.isKeyFrame = isKeyFrame
    }
}

// MARK: - FFmpeg Service (Wrapper)

/// FFmpeg 服务封装
/// 负责管理 FFmpeg 解封装 + VideoToolbox 硬解码的生命周期
public actor FFmpegService {
    private var demuxer: FFmpegDemuxerProtocol?
    private var isRunning = false

    public init() {}

    /// 打开媒体文件
    public func open(url: URL) async throws -> MediaFormatInfo {
        close()
        let demuxer = try await createDemuxer(for: url)
        self.demuxer = demuxer
        isRunning = true
        return try await demuxer.open(url: url)
    }

    /// 读取下一帧
    public func readNextFrame() async throws -> VideoFrame? {
        guard let demuxer = demuxer, isRunning else { return nil }
        return try await demuxer.readNextFrame()
    }

    /// 跳转
    public func seek(to time: Double) async throws {
        try await demuxer?.seek(to: time)
    }

    /// 获取字幕
    public func getSubtitleTracks() -> [SubtitleTrackInfo] {
        demuxer?.getSubtitleTracks() ?? []
    }

    /// 获取音轨
    public func getAudioTracks() -> [AudioTrackInfo] {
        demuxer?.getAudioTracks() ?? []
    }

    /// 关闭
    public func close() {
        demuxer?.close()
        demuxer = nil
        isRunning = false
    }

    /// 是否在运行
    public var isActive: Bool { isRunning }

    // MARK: - Demuxer Factory

    private func createDemuxer(for url: URL) async throws -> FFmpegDemuxerProtocol {
        let ext = url.pathExtension.lowercased()

        // 判断是否需要 FFmpeg 解封装
        if needsFFmpegDemuxing(ext) {
            // 使用 FFmpeg demuxer（需要导入 FFmpeg 框架）
            return try await NativeFFmpegDemuxer(url: url)
        }

        // 其他格式直接使用 AVPlayer
        throw FFmpegError.notNeeded
    }

    private func needsFFmpegDemuxing(_ ext: String) -> Bool {
        // AVPlayer 原生不友好或需要特殊处理的格式
        let unsupportedFormats: Set<String> = [
            "mkv", "avi", "wmv", "flv", "webm", "rmvb", "ts", "mts",
            "ogg", "ogv", "3gp", "mov" // 部分编码需要
        ]
        return unsupportedFormats.contains(ext)
    }
}

// MARK: - Native FFmpeg Demuxer (Stub)

/// 原生 FFmpeg 解封装器实现
/// 实际项目中通过桥接 C FFmpeg 库实现
public class NativeFFmpegDemuxer: FFmpegDemuxerProtocol {
    private let url: URL
    private var formatContext: UnsafeMutableRawPointer? // AVFormatContext*
    private var videoCodecContext: UnsafeMutableRawPointer?
    private var audioCodecContext: UnsafeMutableRawPointer?
    private var videoStreamIndex: Int32 = -1
    private var audioStreamIndex: Int32 = -1
    private var formatInfo = MediaFormatInfo()

    public init(url: URL) throws {
        self.url = url
    }

    public func open(url: URL) async throws -> MediaFormatInfo {
        // 实际实现会调用 FFmpeg C API:
        // avformat_open_input()
        // avformat_find_stream_info()
        // avcodec_find_decoder()
        // avcodec_open2()

        // 模拟解析结果
        formatInfo = MediaFormatInfo(
            duration: 0,
            bitRate: 0,
            videoStreams: [
                VideoStreamInfo(
                    index: 0, codec: "h264",
                    width: 1920, height: 1080,
                    frameRate: 23.976, bitRate: 8_000_000
                )
            ],
            audioStreams: [
                AudioStreamInfo(
                    index: 1, codec: "aac",
                    sampleRate: 48000, channels: 2,
                    bitRate: 256_000, language: "eng"
                )
            ]
        )
        return formatInfo
    }

    public func readNextFrame() async throws -> VideoFrame? {
        // 实际实现:
        // av_read_frame() -> AVPacket
        // avcodec_send_packet() / avcodec_receive_frame()
        // VideoToolbox: VTDecompressionSessionDecodeFrame()
        // 返回 CVPixelBuffer
        return nil
    }

    public func seek(to time: Double) async throws {
        // av_seek_frame()
    }

    public func getSubtitleTracks() -> [SubtitleTrackInfo] {
        []
    }

    public func getAudioTracks() -> [AudioTrackInfo] {
        formatInfo.audioStreams.map {
            AudioTrackInfo(index: $0.index, title: $0.codec, language: $0.language)
        }
    }

    public func close() {
        // avformat_close_input()
        // avcodec_close()
        // av_frame_free()
    }
}

// MARK: - AVAssetResourceLoader Delegate

/// 通过 AVAssetResourceLoader 拦截请求，用 FFmpeg 解封装后喂给 AVPlayer
public class FFmpegResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private let ffmpegService: FFmpegService
    private var pendingRequests: [AVAssetResourceLoadingRequest] = []
    private let queue = DispatchQueue(label: "com.cloudplayer.resourceloader", qos: .userInitiated)

    public init(ffmpegService: FFmpegService) {
        self.ffmpegService = ffmpegService
        super.init()
    }

    // MARK: - AVAssetResourceLoaderDelegate

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        queue.async { [weak self] in
            self?.handleLoadingRequest(loadingRequest)
        }
        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        queue.async { [weak self] in
            self?.pendingRequests.removeAll { $0 == loadingRequest }
        }
    }

    // MARK: - Request Handling

    private func handleLoadingRequest(_ request: AVAssetResourceLoadingRequest) {
        guard let url = request.request.url else {
            request.finishLoading(with: NSError(domain: "FFmpegResourceLoader", code: -1))
            return
        }

        // 自定义协议处理
        // 1. 拦截请求
        // 2. 用 FFmpeg 解封装
        // 3. 将数据重新封装为 MP4/MOV 格式
        // 4. 通过 AVAssetResourceLoadingDataRequest 返回

        // 处理数据请求
        if let dataRequest = request.dataRequest {
            handleDataRequest(dataRequest, for: request, url: url)
        }

        // 处理内容信息请求
        if let contentRequest = request.contentInformationRequest {
            handleContentInformationRequest(contentRequest, for: request)
        }
    }

    private func handleDataRequest(
        _ dataRequest: AVAssetResourceLoadingDataRequest,
        for request: AVAssetResourceLoadingRequest,
        url: URL
    ) {
        let requestedOffset = dataRequest.requestedOffset
        let requestedLength = dataRequest.requestedLength

        // 实际实现中，这里会从 FFmpeg 解封装后的数据读取
        // 重新封装为 ISO-BMFF (MP4) 格式片段
        // 通过 AVAssetResourceLoadingDataRequest.respond(with:) 返回

        // 模拟：标记完成
        // 实际项目中，需要实现完整的 MP4 重新封装
        request.finishLoading()
    }

    private func handleContentInformationRequest(
        _ request: AVAssetResourceLoadingContentInformationRequest,
        for loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // 设置内容类型
        request.contentType = AVFileType.mp4.rawValue
        request.contentLength = 0 // 动态流
        request.isByteRangeAccessSupported = true
    }
}

// MARK: - Custom URL Scheme

/// 注册自定义 URL Scheme 用于 FFmpeg 解封装
public struct FFmpegURLScheme {
    public static let customScheme = "cloudplayer-ffmpeg"

    /// 创建自定义 URL 以触发 FFmpeg 解封装
    public static func createFFmpegURL(for originalURL: URL) -> URL {
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        components?.scheme = customScheme
        return components?.url ?? originalURL
    }

    /// 创建自定义 AVURLAsset 以使用 FFmpeg 解封装
    public static func createFFmpegAsset(for originalURL: URL) -> AVURLAsset {
        let ffmpegURL = createFFmpegURL(for: originalURL)
        let asset = AVURLAsset(url: ffmpegURL)

        // 注册 ResourceLoader 代理
        let ffmpegService = FFmpegService()
        let delegate = FFmpegResourceLoaderDelegate(ffmpegService: ffmpegService)
        asset.resourceLoader.setDelegate(delegate, queue: .main)

        // 关联 delegate 防止被释放
        objc_setAssociatedObject(
            asset,
            UnsafeRawPointer(bitPattern: "ffmpegDelegate".hashValue)!,
            delegate,
            .OBJC_ASSOCIATION_RETAIN
        )

        return asset
    }
}

// MARK: - VideoToolbox Decoder

/// VideoToolbox 硬解码管理器
public class VideoToolboxDecoder: @unchecked Sendable {
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let queue = DispatchQueue(label: "com.cloudplayer.videotoolbox", qos: .userInitiated)

    public init() {}

    /// 创建解码会话
    public func createDecodeSession(
        codecType: CMVideoCodecType,
        width: Int32,
        height: Int32
    ) -> Bool {
        let formatDescription = createFormatDescription(
            codecType: codecType,
            width: width,
            height: height
        )
        guard let formatDescription = formatDescription else { return false }
        self.formatDescription = formatDescription

        let decoderSpecification: [NSString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true,
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: false
        ]

        let destinationPixelBufferAttributes: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferOpenGLCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        var sessionOut: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &sessionOut
        )

        guard status == noErr, let session = sessionOut else {
            print("[VideoToolbox] Failed to create session: \(status)")
            return false
        }

        self.session = session
        return true
    }

    /// 解码一帧
    public func decodeFrame(
        _ data: Data,
        presentationTime: CMTime,
        duration: CMTime
    ) async throws -> CVPixelBuffer? {
        guard let session = session else {
            throw VideoToolboxError.sessionNotReady
        }

        return try await withCheckedThrowingContinuation { continuation in
            let sampleBuffer = createSampleBuffer(
                data: data,
                formatDescription: formatDescription!,
                presentationTime: presentationTime,
                duration: duration
            )

            guard let sampleBuffer = sampleBuffer else {
                continuation.resume(throwing: VideoToolboxError.bufferCreationFailed)
                return
            }

            var infoFlags = VTDecodeInfoFlags()
            var outputBuffer: CVImageBuffer?

            let status = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: [.enableAsynchronousDecompression],
                infoFlagsOut: &infoFlags,
                outputHandler: { status, _, imageBuffer, presentationTimeStamp, _ in
                    guard status == noErr, let imageBuffer = imageBuffer else {
                        continuation.resume(throwing: VideoToolboxError.decodeFailed(status))
                        return
                    }
                    continuation.resume(returning: imageBuffer as? CVPixelBuffer)
                }
            )

            if status != noErr {
                continuation.resume(throwing: VideoToolboxError.decodeFailed(status))
            }
        }
    }

    // MARK: - Helpers

    private func createFormatDescription(
        codecType: CMVideoCodecType,
        width: Int32,
        height: Int32
    ) -> CMVideoFormatDescription? {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codecType,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        return status == noErr ? formatDescription : nil
    }

    private func createSampleBuffer(
        data: Data,
        formatDescription: CMFormatDescription,
        presentationTime: CMTime,
        duration: CMTime
    ) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else {
            return nil
        }

        let dataBytes = data.withUnsafeBytes { $0.baseAddress! }
        CMBlockBufferReplaceDataBytes(
            with: dataBytes,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: data.count
        )

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: [data.count],
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }

    deinit {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
        }
    }
}

// MARK: - Errors

public enum FFmpegError: LocalizedError, Sendable {
    case notNeeded
    case initializationFailed(String)
    case demuxingFailed(String)
    case decodingFailed(String)
    case unsupportedFormat
    case resourceNotFound

    public var errorDescription: String? {
        switch self {
        case .notNeeded: return "无需 FFmpeg 处理"
        case .initializationFailed(let msg): return "FFmpeg 初始化失败: \(msg)"
        case .demuxingFailed(let msg): return "解封装失败: \(msg)"
        case .decodingFailed(let msg): return "解码失败: \(msg)"
        case .unsupportedFormat: return "不支持的格式"
        case .resourceNotFound: return "资源未找到"
        }
    }
}

public enum VideoToolboxError: LocalizedError, Sendable {
    case sessionNotReady
    case bufferCreationFailed
    case decodeFailed(OSStatus)
    case formatUnsupported

    public var errorDescription: String? {
        switch self {
        case .sessionNotReady: return "解码器未就绪"
        case .bufferCreationFailed: return "缓冲区创建失败"
        case .decodeFailed(let status): return "解码失败: \(status)"
        case .formatUnsupported: return "不支持的编码格式"
        }
    }
}

// MARK: - Format Detector

/// 格式检测器，决定是否使用 FFmpeg 解封装
public struct FormatDetector {
    /// 需要 FFmpeg 解封装的格式
    private static let ffmpegRequiredFormats: Set<String> = [
        "mkv", "avi", "wmv", "flv", "webm", "rmvb", "ts", "mts", "m2ts"
    ]

    /// AVPlayer 原生支持的格式
    private static let nativeSupportedFormats: Set<String> = [
        "mp4", "m4v", "mov", "m4a", "mp3", "aac", "wav", "m3u8", "ts"
    ]

    /// 判断是否需要 FFmpeg 解封装
    public static func needsFFmpeg(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ffmpegRequiredFormats.contains(ext)
    }

    /// 判断 AVPlayer 是否原生支持
    public static func isNativeSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return nativeSupportedFormats.contains(ext)
    }

    /// 获取最佳播放策略
    public static func getPlaybackStrategy(for url: URL) -> PlaybackStrategy {
        if needsFFmpeg(url) {
            return .ffmpegDemux
        } else if isNativeSupported(url) {
            return .directPlay
        } else {
            return .tryNativeThenFFmpeg
        }
    }
}

public enum PlaybackStrategy: String, Sendable {
    case directPlay = "AVPlayer 直接播放"
    case ffmpegDemux = "FFmpeg 解封装后播放"
    case tryNativeThenFFmpeg = "优先原生，失败回退 FFmpeg"
}