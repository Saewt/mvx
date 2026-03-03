import Darwin
import Foundation

public struct TerminalWindowSize: Codable, Equatable {
    public var columns: Int
    public var rows: Int
    public var pixelSize: TerminalPixelSize

    public init(columns: Int = 120, rows: Int = 40, pixelSize: TerminalPixelSize = TerminalPixelSize(width: 0, height: 0)) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        self.pixelSize = pixelSize
    }
}

public enum PtyEvent: Equatable {
    case output(String)
    case agentStatus(SessionAgentStatusUpdate)
    case exited(Int32)
}

public enum PtyTransport: String, Codable, Equatable {
    case bsdPseudoTerminal
}

public final class PtyBridge {
    private static let maxProtocolLogEntries = 500

    public let shellPath: String
    public let prompt: String
    public let transport: PtyTransport = .bsdPseudoTerminal
    public let startupDirectory: URL

    private(set) public var isRunning = false
    private(set) public var windowSize = TerminalWindowSize()
    private(set) public var protocolLog: [String] = []
    private(set) public var lastExitStatus: Int32?

    private var masterFileDescriptor: Int32 = -1
    private var childProcessID: pid_t = 0
    private var shellRuntimeDirectory: URL?

    public init(
        shellPath: String = "/bin/zsh",
        prompt: String = "mvx% ",
        startupDirectory: URL? = nil
    ) {
        self.shellPath = shellPath
        self.prompt = prompt
        self.startupDirectory = startupDirectory ?? Self.resolveStartupDirectory()
    }

    public convenience init(shellPath: String, prompt: String) {
        self.init(shellPath: shellPath, prompt: prompt, startupDirectory: nil)
    }

    deinit {
        terminateIfNeeded()
    }

    public func start() -> [PtyEvent] {
        guard !isRunning else {
            return []
        }

        var master: Int32 = -1
        var slave: Int32 = -1
        var size = makeWindowSize()
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        let didOpenPty = nameBuffer.withUnsafeMutableBufferPointer { buffer in
            openpty(&master, &slave, buffer.baseAddress, nil, &size) == 0
        }

        guard didOpenPty else {
            return [.output("failed to create PTY: \(String(cString: strerror(errno)))\n")]
        }

        let slavePath = String(cString: nameBuffer)
        close(slave)
        let runtimeDirectory = prepareShellRuntimeDirectory()
        guard let pid = spawnShellProcess(master: master, slavePath: slavePath, runtimeDirectory: runtimeDirectory) else {
            close(master)
            removeShellRuntimeDirectory(runtimeDirectory)
            return [.output("failed to launch shell: \(String(cString: strerror(errno)))\n")]
        }
        masterFileDescriptor = master
        childProcessID = pid
        shellRuntimeDirectory = runtimeDirectory
        lastExitStatus = nil
        isRunning = true
        setNonBlocking(master)
        applyWindowSize()
        return drainOutput(timeoutMs: 1_000, stopWhenPromptVisible: true)
    }

    public func write(_ rawInput: String) -> [PtyEvent] {
        guard isRunning else {
            return []
        }

        guard send(rawInput.utf8) else {
            return drainOutput(timeoutMs: 50, stopWhenPromptVisible: false)
        }

        return drainOutput(timeoutMs: 100, stopWhenPromptVisible: false)
    }

    public func pollOutput(timeoutMs: Int = 100, stopWhenPromptVisible: Bool = false) -> [PtyEvent] {
        guard isRunning else {
            return []
        }

        return drainOutput(timeoutMs: timeoutMs, stopWhenPromptVisible: stopWhenPromptVisible)
    }

    public func sendRaw(_ bytes: [UInt8]) {
        guard isRunning, !bytes.isEmpty else {
            return
        }

        _ = send(bytes)
    }

    public func updateWindowSize(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) {
        windowSize = TerminalWindowSize(
            columns: columns,
            rows: rows,
            pixelSize: TerminalPixelSize(width: pixelWidth, height: pixelHeight)
        )
        applyWindowSize()
    }

    public func recordProtocolPacket(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else {
            return
        }

        protocolLog.append(String(decoding: bytes, as: UTF8.self))
        if protocolLog.count > Self.maxProtocolLogEntries {
            protocolLog.removeFirst(protocolLog.count - Self.maxProtocolLogEntries)
        }
    }

    public func terminate() {
        terminateIfNeeded()
    }

    private func send<S: Sequence>(_ bytes: S) -> Bool where S.Element == UInt8 {
        let payload = Array(bytes)
        guard !payload.isEmpty, masterFileDescriptor >= 0 else {
            return false
        }

        var offset = 0
        while offset < payload.count {
            let written = payload.withUnsafeBytes { buffer in
                Darwin.write(masterFileDescriptor, buffer.baseAddress?.advanced(by: offset), payload.count - offset)
            }

            if written > 0 {
                offset += written
                continue
            }

            if written == -1, errno == EINTR {
                continue
            }

            return false
        }

        return true
    }

    private func drainOutput(timeoutMs: Int, stopWhenPromptVisible: Bool) -> [PtyEvent] {
        var payload = Data()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let timeoutNs = UInt64(max(timeoutMs, 1)) * 1_000_000

        while DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNs {
            var descriptor = pollfd(fd: masterFileDescriptor, events: Int16(POLLIN | POLLERR | POLLHUP), revents: 0)
            let ready = withUnsafeMutablePointer(to: &descriptor) {
                Darwin.poll($0, 1, 20)
            }

            if ready == -1 {
                if errno == EINTR {
                    continue
                }
                break
            }

            if ready == 0 {
                if !payload.isEmpty {
                    break
                }
                continue
            }

            if descriptor.revents != 0 {
                readAvailable(into: &payload)
                let sanitized = Self.sanitizeTerminalOutput(String(decoding: payload, as: UTF8.self))
                if stopWhenPromptVisible, sanitized.hasSuffix(prompt) {
                    break
                }
                if descriptor.revents & Int16(POLLHUP | POLLERR) != 0 {
                    break
                }
            }
        }

        let rawOutput = String(decoding: payload, as: UTF8.self)
        var events = Self.extractAgentStatusEvents(from: rawOutput)
        let output = Self.sanitizeTerminalOutput(rawOutput)
        if !output.isEmpty {
            events.append(.output(output))
        }

        if let status = reapIfNeeded() {
            events.append(.exited(status))
        }

        return events
    }

    private func readAvailable(into data: inout Data) {
        guard masterFileDescriptor >= 0 else {
            return
        }

        while true {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(masterFileDescriptor, &buffer, buffer.count)

            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                continue
            }

            if count == 0 {
                break
            }

            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EIO {
                break
            }

            if errno == EINTR {
                continue
            }

            break
        }
    }

    private func applyWindowSize() {
        guard masterFileDescriptor >= 0 else {
            return
        }

        var size = makeWindowSize()
        _ = ioctl(masterFileDescriptor, TIOCSWINSZ, &size)
    }

    private func makeWindowSize() -> winsize {
        winsize(
            ws_row: UInt16(clamping: windowSize.rows),
            ws_col: UInt16(clamping: windowSize.columns),
            ws_xpixel: UInt16(clamping: windowSize.pixelSize.width),
            ws_ypixel: UInt16(clamping: windowSize.pixelSize.height)
        )
    }

    private func setNonBlocking(_ fileDescriptor: Int32) {
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags != -1 else {
            return
        }
        _ = fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK)
    }

    private func prepareShellRuntimeDirectory() -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mvx-zsh-\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let bootstrap = """
            unsetopt PROMPT_PERCENT
            PROMPT_EOL_MARK=''
            PROMPT='\(shellQuoted(prompt))'
            PS1='\(shellQuoted(prompt))'
            """
            try bootstrap.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            return directory
        } catch {
            return nil
        }
    }

    private func removeShellRuntimeDirectory(_ directory: URL?) {
        guard let directory else {
            return
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func spawnShellProcess(master: Int32, slavePath: String, runtimeDirectory: URL?) -> pid_t? {
        var environment = ProcessInfo.processInfo.environment
        environment["ZDOTDIR"] = runtimeDirectory?.path ?? environment["HOME"]
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["SHELL_SESSIONS_DISABLE"] = "1"
        environment["PWD"] = startupDirectory.path
        var arguments: [UnsafeMutablePointer<CChar>?] = [strdup((shellPath as NSString).lastPathComponent), strdup("-i"), nil]
        var envPointers: [UnsafeMutablePointer<CChar>?] = environment
            .map { strdup("\($0.key)=\($0.value)") }
        envPointers.append(nil)

        var fileActions: posix_spawn_file_actions_t? = nil
        var attributes: posix_spawnattr_t? = nil
        var child: pid_t = 0
        var flags: Int16 = 0

        posix_spawn_file_actions_init(&fileActions)
        posix_spawnattr_init(&attributes)

        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attributes)
            for pointer in arguments where pointer != nil {
                free(pointer)
            }
            for pointer in envPointers where pointer != nil {
                free(pointer)
            }
        }

#if os(macOS)
        flags |= Int16(POSIX_SPAWN_SETSID)
#endif
        posix_spawnattr_setflags(&attributes, flags)

        let actionsStatus = startupDirectory.path.withCString { directoryPointer -> Int32 in
            let chdirStatus = posix_spawn_file_actions_addchdir_np(&fileActions, directoryPointer)
            guard chdirStatus == 0 else {
                return chdirStatus
            }

            return slavePath.withCString { pathPointer -> Int32 in
            let closeStatus = posix_spawn_file_actions_addclose(&fileActions, master)
            guard closeStatus == 0 else {
                return closeStatus
            }

            let openStatus = posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, pathPointer, O_RDWR, 0)
            guard openStatus == 0 else {
                return openStatus
            }

            let stdoutStatus = posix_spawn_file_actions_adddup2(&fileActions, STDIN_FILENO, STDOUT_FILENO)
            guard stdoutStatus == 0 else {
                return stdoutStatus
            }

            return posix_spawn_file_actions_adddup2(&fileActions, STDIN_FILENO, STDERR_FILENO)
            }
        }

        guard actionsStatus == 0 else {
            errno = actionsStatus
            return nil
        }

        let spawnStatus = shellPath.withCString { pathPointer in
            posix_spawn(&child, pathPointer, &fileActions, &attributes, &arguments, &envPointers)
        }

        guard spawnStatus == 0 else {
            errno = spawnStatus
            return nil
        }

        return child
    }

    static func resolveStartupDirectory(
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        let inheritedDirectory = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true).standardizedFileURL
        if isUsableStartupDirectory(inheritedDirectory, fileManager: fileManager) {
            return inheritedDirectory
        }

        let preferredHome = homeDirectory.standardizedFileURL
        if isUsableStartupDirectory(preferredHome, fileManager: fileManager) {
            return preferredHome
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
    }

    private func reapIfNeeded() -> Int32? {
        guard childProcessID > 0 else {
            return nil
        }

        var status: Int32 = 0
        let result = waitpid(childProcessID, &status, WNOHANG)

        guard result > 0 else {
            return nil
        }

        let exitStatus = Self.normalizedExitStatus(status)

        childProcessID = 0
        lastExitStatus = exitStatus
        isRunning = false
        if masterFileDescriptor >= 0 {
            close(masterFileDescriptor)
            masterFileDescriptor = -1
        }
        removeShellRuntimeDirectory(shellRuntimeDirectory)
        shellRuntimeDirectory = nil
        return exitStatus
    }

    private func terminateIfNeeded() {
        if childProcessID > 0 {
            _ = kill(childProcessID, SIGHUP)
            var status: Int32 = 0
            _ = waitpid(childProcessID, &status, 0)
            childProcessID = 0
        }

        if masterFileDescriptor >= 0 {
            close(masterFileDescriptor)
            masterFileDescriptor = -1
        }

        removeShellRuntimeDirectory(shellRuntimeDirectory)
        shellRuntimeDirectory = nil
        isRunning = false
    }

    private func shellQuoted(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func isUsableStartupDirectory(_ directory: URL, fileManager: FileManager) -> Bool {
        let standardized = directory.standardizedFileURL
        guard standardized.path != "/" else {
            return false
        }

        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func sanitizeTerminalOutput(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character == "\r" {
                index = text.index(after: index)
                continue
            }

            if character == "\u{001B}" {
                let next = text.index(after: index)
                guard next < text.endIndex else {
                    break
                }

                let marker = text[next]

                if marker == "]" {
                    let payloadStart = text.index(after: next)
                    var cursor = payloadStart
                    var payloadEnd: String.Index?
                    var sequenceEnd: String.Index?

                    while cursor < text.endIndex {
                        if text[cursor] == "\u{0007}" {
                            payloadEnd = cursor
                            sequenceEnd = text.index(after: cursor)
                            break
                        }

                        if text[cursor] == "\u{001B}" {
                            let terminator = text.index(after: cursor)
                            if terminator < text.endIndex, text[terminator] == "\\" {
                                payloadEnd = cursor
                                sequenceEnd = text.index(after: terminator)
                                break
                            }
                        }

                        cursor = text.index(after: cursor)
                    }

                    guard let payloadEnd, let sequenceEnd else {
                        break
                    }

                    let payload = String(text[payloadStart..<payloadEnd])
                    if payload.hasPrefix("8;") {
                        result.append(contentsOf: text[index..<sequenceEnd])
                    }

                    index = sequenceEnd
                    continue
                }

                if marker == "[" {
                    index = text.index(after: next)
                    while index < text.endIndex {
                        let scalar = text[index].unicodeScalars.first?.value ?? 0
                        if scalar >= 0x40 && scalar <= 0x7E {
                            index = text.index(after: index)
                            break
                        }
                        index = text.index(after: index)
                    }
                    continue
                }

                index = text.index(after: next)
                continue
            }

            if let scalar = character.unicodeScalars.first?.value, scalar < 0x20, character != "\n", character != "\t" {
                index = text.index(after: index)
                continue
            }

            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private static func normalizedExitStatus(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        if signal == 0 {
            return (status >> 8) & 0xff
        }
        if signal == 0x7f {
            return status
        }
        return 128 + signal
    }

    private static func extractAgentStatusEvents(from text: String) -> [PtyEvent] {
        var events: [PtyEvent] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "\u{001B}" else {
                index = text.index(after: index)
                continue
            }

            let markerIndex = text.index(after: index)
            guard markerIndex < text.endIndex, text[markerIndex] == "]" else {
                index = markerIndex
                continue
            }

            let payloadStart = text.index(after: markerIndex)
            var cursor = payloadStart
            var payloadEnd: String.Index?
            var sequenceEnd: String.Index?

            while cursor < text.endIndex {
                if text[cursor] == "\u{0007}" {
                    payloadEnd = cursor
                    sequenceEnd = text.index(after: cursor)
                    break
                }

                if text[cursor] == "\u{001B}" {
                    let terminatorIndex = text.index(after: cursor)
                    if terminatorIndex < text.endIndex, text[terminatorIndex] == "\\" {
                        payloadEnd = cursor
                        sequenceEnd = text.index(after: terminatorIndex)
                        break
                    }
                }

                cursor = text.index(after: cursor)
            }

            guard let payloadEnd, let sequenceEnd else {
                break
            }

            let payload = String(text[payloadStart..<payloadEnd])
            if let update = SessionAgentStatusUpdate.parse(payload) {
                events.append(.agentStatus(update))
            }

            index = sequenceEnd
        }

        return events
    }
}
