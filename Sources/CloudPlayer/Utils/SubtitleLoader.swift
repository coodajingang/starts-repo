import Foundation

// MARK: - Subtitle Loader

/// 字幕加载器
/// 支持 SRT、ASS、VTT 格式的字幕解析
public actor SubtitleLoader {
    // MARK: - Subtitle Entry

    public struct SubtitleEntry: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let index: Int
        public let startTime: Double
        public let endTime: Double
        public let text: String
        public let position: Int?

        public init(id: UUID = UUID(), index: Int, startTime: Double, endTime: Double, text: String, position: Int? = nil) {
            self.id = id
            self.index = index
            self.startTime = startTime
            self.endTime = endTime
            self.text = text
            self.position = position
        }

        public var duration: Double {
            endTime - startTime
        }
    }

    // MARK: - Load Subtitles

    /// 加载字幕文件
    public func loadSubtitles(from url: URL) async throws -> [SubtitleEntry] {
        let data = try await URLSession.shared.data(from: url).0
        guard let content = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .utf16) else {
            throw SubtitleError.invalidEncoding
        }

        return parseSubtitles(content: content, format: detectFormat(from: url.pathExtension))
    }

    /// 加载字幕字符串
    public func loadSubtitles(from content: String, format: SubtitleFormat) -> [SubtitleEntry] {
        parseSubtitles(content: content, format: format)
    }

    /// 从本地文件加载
    public func loadLocalSubtitles(path: String) async throws -> [SubtitleEntry] {
        let url = URL(fileURLWithPath: path)
        return try await loadSubtitles(from: url)
    }

    // MARK: - Format Detection

    private func detectFormat(from ext: String) -> SubtitleFormat {
        switch ext.lowercased() {
        case "srt": return .srt
        case "ass", "ssa": return .ass
        case "vtt": return .vtt
        case "sub": return .sub
        default: return .srt
        }
    }

    // MARK: - Parsing

    private func parseSubtitles(content: String, format: SubtitleFormat) -> [SubtitleEntry] {
        switch format {
        case .srt:
            return parseSRT(content)
        case .ass:
            return parseASS(content)
        case .vtt:
            return parseVTT(content)
        case .sub:
            return parseSubRip(content)
        case .pgs:
            // PGS 是图形字幕格式，暂不支持解析
            return []
        case .unknown:
            // 尝试自动检测
            if content.contains("-->") {
                if content.contains("WEBVTT") {
                    return parseVTT(content)
                }
                return parseSRT(content)
            }
            return parseASS(content)
        }
    }

    // MARK: - SRT Parser

    private func parseSRT(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        let blocks = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)

            guard lines.count >= 3 else { continue }

            // Index
            guard let index = Int(lines[0].trimmingCharacters(in: .whitespaces)) else { continue }

            // Timecode
            let timecodeLine = lines[1].trimmingCharacters(in: .whitespaces)
            guard let (start, end) = parseSRTTimecode(timecodeLine) else { continue }

            // Text
            let text = lines[2...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            entries.append(SubtitleEntry(
                index: index,
                startTime: start,
                endTime: end,
                text: text
            ))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    private func parseSRTTimecode(_ timecode: String) -> (Double, Double)? {
        let components = timecode.components(separatedBy: " --> ")
        guard components.count == 2 else { return nil }

        let start = parseTimecode(components[0])
        let end = parseTimecode(components[1])
        guard let start = start, let end = end else { return nil }

        return (start, end)
    }

    // MARK: - ASS Parser

    private func parseASS(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        var formatMap: [String: Int] = [:]
        var foundEvents = false

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[Events]" {
                foundEvents = true
                continue
            }

            guard foundEvents else { continue }

            if trimmed.hasPrefix("Format:") {
                let parts = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                for (index, part) in parts.enumerated() {
                    formatMap[part] = index
                }
                continue
            }

            if trimmed.hasPrefix("Dialogue:") {
                let parts = parseASSDialogue(trimmed)
                guard let layer = formatMap["Layer"].flatMap({ Int(parts[safe: $0] ?? "0") }),
                      let startStr = parts[safe: formatMap["Start"] ?? 1],
                      let endStr = parts[safe: formatMap["End"] ?? 2],
                      let text = parts[safe: formatMap["Text"] ?? 9] else { continue }

                let start = parseASSTimecode(startStr)
                let end = parseASSTimecode(endStr)
                let cleanedText = cleanASSText(text)

                entries.append(SubtitleEntry(
                    index: layer,
                    startTime: start,
                    endTime: end,
                    text: cleanedText
                ))
            }
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    private func parseASSDialogue(_ line: String) -> [String] {
        // ASS 格式: Dialogue: layer,start,end,style,name,effect,text
        let prefix = "Dialogue:"
        let content = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

        var parts: [String] = []
        var current = ""
        var inBrackets = false

        for char in content {
            if char == "{" { inBrackets = true }
            if char == "}" { inBrackets = false; continue }
            if char == "," && !inBrackets {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))

        return parts
    }

    private func parseASSTimecode(_ timecode: String) -> Double {
        // ASS 格式: H:MM:SS.cc (小时:分钟:秒.百分秒)
        let parts = timecode.components(separatedBy: ":")
        guard parts.count == 3 else { return 0 }

        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0

        let secParts = parts[2].components(separatedBy: ".")
        let seconds = Double(secParts[0]) ?? 0
        let centiseconds = secParts.count > 1 ? (Double(secParts[1]) ?? 0) / 100.0 : 0

        return hours * 3600 + minutes * 60 + seconds + centiseconds
    }

    private func cleanASSText(_ text: String) -> String {
        var cleaned = text
        // 移除 ASS 样式标签
        cleaned = cleaned.replacingOccurrences(of: "\\N", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\\h", with: " ")

        // 移除 {\pos(100,200)} 之类的标签
        while let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.firstIndex(of: "}") {
            cleaned.removeSubrange(start...end)
        }

        // 移除 \b0 \i1 等样式命令
        cleaned = cleaned.replacingOccurrences(of: "\\\\[a-zA-Z][0-9]?", with: "", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - VTT Parser

    private func parseVTT(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        var index = 0

        // 移除 WEBVTT header 和元数据
        var lines = content.components(separatedBy: .newlines)
        if let firstLine = lines.first, firstLine.contains("WEBVTT") {
            lines.removeFirst()
        }

        let text = lines.joined(separator: "\n")
        let blocks = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("NOTE") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            guard lines.count >= 2 else { continue }

            // 找时间轴行
            var timecodeLine: String?
            var textLines: [String] = []

            for line in lines {
                if line.contains("-->") {
                    timecodeLine = line.trimmingCharacters(in: .whitespaces)
                } else if !line.hasPrefix("WEBVTT") {
                    textLines.append(line.trimmingCharacters(in: .whitespaces))
                }
            }

            guard let timecode = timecodeLine,
                  let (start, end) = parseSRTTimecode(timecode) else { continue }

            let text = textLines.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            index += 1
            entries.append(SubtitleEntry(
                index: index,
                startTime: start,
                endTime: end,
                text: text
            ))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - SubRip / MicroDVD Parser

    private func parseSubRip(_ content: String) -> [SubtitleEntry] {
        // MicroDVD 格式: {start_frame}{end_frame}Text
        var entries: [SubtitleEntry] = []
        let lines = content.components(separatedBy: .newlines)

        // 尝试检测帧率
        let fps: Double = 23.976

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{") else { continue }

            let parts = trimmed.components(separatedBy: "}")
            guard parts.count >= 3,
                  let startFrame = Int(parts[0].dropFirst()),
                  let endFrame = Int(parts[1]) else { continue }

            let text = parts[2...].joined(separator: "}")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "|", with: "\n")

            entries.append(SubtitleEntry(
                index: entries.count + 1,
                startTime: Double(startFrame) / fps,
                endTime: Double(endFrame) / fps,
                text: text
            ))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Helpers

    private func parseTimecode(_ timecode: String) -> Double? {
        let cleaned = timecode.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")

        // 支持 HH:MM:SS.mmm 和 MM:SS.mmm 格式
        let parts = cleaned.components(separatedBy: ":")

        switch parts.count {
        case 3:
            // HH:MM:SS.mmm
            let hours = Double(parts[0]) ?? 0
            let minutes = Double(parts[1]) ?? 0
            let seconds = Double(parts[2]) ?? 0
            return hours * 3600 + minutes * 60 + seconds
        case 2:
            // MM:SS.mmm
            let minutes = Double(parts[0]) ?? 0
            let seconds = Double(parts[1]) ?? 0
            return minutes * 60 + seconds
        default:
            return nil
        }
    }

    /// 查询指定时间点的字幕
    public static func subtitleAtTime(_ time: Double, from entries: [SubtitleEntry]) -> SubtitleEntry? {
        entries.first { $0.startTime <= time && $0.endTime >= time }
    }

    /// 获取所有在指定时间范围内的字幕
    public static func subtitlesInRange(from entries: [SubtitleEntry], startTime: Double, endTime: Double) -> [SubtitleEntry] {
        entries.filter { $0.startTime <= endTime && $0.endTime >= startTime }
    }

    /// 自动检测同目录下的字幕文件
    public static func findAssociatedSubtitles(for videoPath: String, availableFiles: [MediaFile]) -> [MediaFile] {
        let videoURL = URL(fileURLWithPath: videoPath)
        let videoName = videoURL.deletingPathExtension().lastPathComponent
        let videoDir = videoURL.deletingLastPathComponent().path

        return availableFiles.filter { file in
            guard MediaFile.isSubtitleFile(file.name) else { return false }
            let fileURL = URL(fileURLWithPath: file.path)
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            // 匹配同名或包含视频名的字幕
            return fileName == videoName || fileName.hasPrefix(videoName)
        }
    }
}

// MARK: - Subtitle Errors

public enum SubtitleError: LocalizedError, Sendable {
    case invalidEncoding
    case parseFailed(String)
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "字幕文件编码不支持"
        case .parseFailed(let msg): return "字幕解析失败: \(msg)"
        case .fileNotFound: return "字幕文件未找到"
        }
    }
}

// MARK: - Array Safe Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}