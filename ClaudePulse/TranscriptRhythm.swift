import Foundation

enum TranscriptRhythm {
    private static let assistantMarker = Array(#""type":"assistant""#.utf8)
    private static let timestampMarker = Array(#""timestamp":""#.utf8)
    private static let chunkSize = 1 << 20

    static func activity(configDirs: [URL], since: Date) -> TranscriptActivity {
        var activity = TranscriptActivity(
            counts: Array(repeating: 0, count: HourOfWeek.count), first: .distantFuture, last: .distantPast, total: 0)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for file in transcripts(in: configDirs, since: since) {
            forEachLine(of: file) { line in
                guard contains(line, assistantMarker), let at = timestamp(in: line, parser: parser), at >= since else { return }
                activity.counts[HourOfWeek.bucket(of: at)] += 1
                activity.first = min(activity.first, at)
                activity.last = max(activity.last, at)
                activity.total += 1
            }
        }
        return activity
    }

    private static func transcripts(in configDirs: [URL], since: Date) -> [URL] {
        let fm = FileManager.default
        return configDirs.flatMap { dir -> [URL] in
            let projects = dir.appendingPathComponent("projects", isDirectory: true)
            let projectDirs = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            return projectDirs.flatMap { project -> [URL] in
                let files = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                return files.filter { file in
                    file.pathExtension == "jsonl"
                        && ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since
                }
            }
        }
    }

    private static func forEachLine(of file: URL, _ body: (ArraySlice<UInt8>) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        var pending: [UInt8] = []
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            pending.append(contentsOf: chunk)
            var lineStart = pending.startIndex
            while let newline = pending[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
                body(pending[lineStart..<newline])
                lineStart = newline + 1
            }
            pending.removeSubrange(..<lineStart)
        }
        if !pending.isEmpty { body(pending[...]) }
    }

    private static func contains(_ line: ArraySlice<UInt8>, _ marker: [UInt8]) -> Bool {
        range(of: marker, in: line) != nil
    }

    private static func range(of marker: [UInt8], in line: ArraySlice<UInt8>) -> Range<Int>? {
        line.withUnsafeBytes { haystack -> Range<Int>? in
            marker.withUnsafeBytes { needle -> Range<Int>? in
                guard let base = haystack.baseAddress,
                      let found = memmem(base, haystack.count, needle.baseAddress, needle.count)
                else { return nil }
                let offset = line.startIndex + base.distance(to: UnsafeRawPointer(found))
                return offset..<(offset + needle.count)
            }
        }
    }

    private static func timestamp(in line: ArraySlice<UInt8>, parser: ISO8601DateFormatter) -> Date? {
        guard let marker = range(of: timestampMarker, in: line),
              let close = line[marker.upperBound...].firstIndex(of: UInt8(ascii: "\""))
        else { return nil }
        return parser.date(from: String(decoding: line[marker.upperBound..<close], as: UTF8.self))
    }
}
