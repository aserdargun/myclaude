import Foundation

protocol LogReaderDelegate: AnyObject {
    func logReader(_ reader: LogReader, didReadEvents events: [UsageEvent])
    func logReader(_ reader: LogReader, didEncounterError error: Error)
}

final class LogReader {
    weak var delegate: LogReaderDelegate?

    private let parser: ParserProtocol
    private let fileManager = FileManager.default
    private var monitorSources: [DispatchSourceFileSystemObject] = []
    private var pollTimer: DispatchSourceTimer?
    private var lastReadPositions: [String: UInt64] = [:]
    private let queue = DispatchQueue(label: "com.myclaude.logreader", qos: .utility)
    private(set) var lastReadTime: Date?
    private(set) var totalEventsRead: Int = 0

    init(parser: ParserProtocol = ClaudeLogParser()) {
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
            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            ) else { continue }

            guard resourceValues.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard ["json", "jsonl", "log", "txt"].contains(ext) || ext.isEmpty else { continue }

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

        let lastPos = lastReadPositions[path] ?? 0

        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        // Get file size
        handle.seekToEndOfFile()
        let fileSize = handle.offsetInFile
        guard fileSize > lastPos else { return }

        // Read new data
        handle.seek(toFileOffset: lastPos)
        let newData = handle.readDataToEndOfFile()
        lastReadPositions[path] = fileSize

        guard !newData.isEmpty else { return }

        let events = parser.parse(data: newData, fromFile: path)
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
