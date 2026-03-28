import Foundation

protocol LogReaderDelegate: AnyObject {
    func logReader(_ reader: LogReader, didReadEvents events: [UsageEvent])
    func logReader(_ reader: LogReader, didEncounterError error: Error)
}

final class LogReader: @unchecked Sendable {
    weak var delegate: LogReaderDelegate?

    private let parser: ParserProtocol
    private let fileManager = FileManager.default
    private var monitorSources: [DispatchSourceFileSystemObject] = []
    private var pollTimer: DispatchSourceTimer?
    private var lastReadPositions: [String: UInt64] = [:]
    private let queue = DispatchQueue(label: "com.myclaude.logreader", qos: .utility)
    private(set) var lastReadTime: Date?
    private(set) var totalEventsRead: Int = 0
    private(set) var isScanning: Bool = false

    /// Max bytes to read from a file on first encounter (tail read).
    /// 512 KB covers ~5 hours of typical Claude Code conversation.
    private let maxInitialReadBytes: UInt64 = 512 * 1024

    init(parser: ParserProtocol = MyClaudeLogParser()) {
        self.parser = parser
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    func start() {
        let paths = Constants.claudeLogPaths
        for path in paths {
            setupMonitor(for: path)
        }
        startPolling()
        // Initial read
        queue.async { [weak self] in
            self?.scanAllLogs()
        }
    }

    func stop() {
        monitorSources.forEach { $0.cancel() }
        monitorSources.removeAll()
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - File System Monitoring

    private func setupMonitor(for path: String) {
        guard fileManager.fileExists(atPath: path) else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scanDirectory(at: path)
        }

        source.setCancelHandler {
            close(fd)
        }

        monitorSources.append(source)
        source.resume()
    }

    // MARK: - Polling fallback

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Constants.logPollInterval,
            repeating: Constants.logPollInterval
        )
        timer.setEventHandler { [weak self] in
            self?.scanAllLogs()
        }
        pollTimer = timer
        timer.resume()
    }

    // MARK: - Scanning

    private func scanAllLogs() {
        isScanning = true
        defer { isScanning = false }
        for path in Constants.claudeLogPaths {
            scanDirectory(at: path)
        }
    }

    private func scanDirectory(at path: String) {
        guard fileManager.fileExists(atPath: path) else { return }

        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: path, isDirectory: &isDir)

        if isDir.boolValue {
            scanDirectoryRecursively(at: path)
        } else {
            readFile(at: path)
        }
    }

    private func scanDirectoryRecursively(at dirPath: String) {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: dirPath),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            // Skip subagent logs — they're duplicates of main conversation data
            if fileURL.path.contains("/subagents/") { continue }

            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            ) else { continue }

            guard resourceValues.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard ext == "jsonl" else { continue }

            // Only read files modified in the last 7 days
            if let modDate = resourceValues.contentModificationDate,
               modDate.timeIntervalSinceNow < -(7 * 24 * 3600) {
                continue
            }

            readFile(at: fileURL.path)
        }
    }

    private func readFile(at path: String) {
        guard fileManager.isReadableFile(atPath: path) else { return }

        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        // Get file size
        handle.seekToEndOfFile()
        let fileSize = handle.offsetInFile
        guard fileSize > 0 else { return }

        let lastPos = lastReadPositions[path]
        let readFrom: UInt64

        if let lastPos {
            // Incremental read from where we left off
            guard fileSize > lastPos else { return }
            readFrom = lastPos
        } else {
            // First time seeing this file — only read the tail
            if fileSize > maxInitialReadBytes {
                readFrom = fileSize - maxInitialReadBytes
            } else {
                readFrom = 0
            }
        }

        handle.seek(toFileOffset: readFrom)
        let newData = handle.readDataToEndOfFile()
        lastReadPositions[path] = fileSize

        guard !newData.isEmpty else { return }

        var events = parser.parse(data: newData, fromFile: path)

        // If we started mid-file on first read, drop the first (likely partial) line
        if lastPos == nil && readFrom > 0 {
            events = Array(events.dropFirst())
        }

        guard !events.isEmpty else { return }

        lastReadTime = Date()
        totalEventsRead += events.count

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.logReader(self, didReadEvents: events)
        }
    }

    // MARK: - Manual refresh

    func forceRefresh() {
        queue.async { [weak self] in
            self?.scanAllLogs()
        }
    }

    func resetReadPositions() {
        queue.async { [weak self] in
            self?.lastReadPositions.removeAll()
            self?.scanAllLogs()
        }
    }
}
