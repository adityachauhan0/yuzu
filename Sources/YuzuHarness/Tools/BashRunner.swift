import Foundation

enum BashRunner {
    static let defaultTimeoutSeconds: TimeInterval = 120

    static func run(
        command: String,
        workingDirectory: String,
        timeoutSeconds: TimeInterval?,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return "Error: \(error.localizedDescription)"
        }

        // Drain both pipes while the command runs; a full pipe buffer blocks the child.
        let stdoutData = PipeDrain(stdoutPipe.fileHandleForReading, onChunk: onOutput)
        let stderrData = PipeDrain(stderrPipe.fileHandleForReading, onChunk: onOutput)

        let limit = timeoutSeconds ?? defaultTimeoutSeconds
        if exited.wait(timeout: .now() + limit) == .timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
            return "Error: command timed out after \(Int(limit)) second(s)"
        }

        let stdout = String(data: stdoutData.finish(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrData.finish(), encoding: .utf8) ?? ""

        var body = stdout
        if !stderr.isEmpty {
            if !body.isEmpty, !body.hasSuffix("\n") {
                body += "\n"
            }
            body += stderr
        }
        return "Ran: \(command)\n\(body)"
    }
}

private final class PipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    private let onChunk: (@Sendable (String) -> Void)?

    init(_ handle: FileHandle, onChunk: (@Sendable (String) -> Void)? = nil) {
        self.handle = handle
        self.onChunk = onChunk
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                done.signal()
            } else {
                lock.withLock { data.append(chunk) }
                if let onChunk, let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                    onChunk(text)
                }
            }
        }
    }

    func finish() -> Data {
        // Another spawned process can inherit the write end and hold EOF back.
        if done.wait(timeout: .now() + 0.5) == .timedOut {
            handle.readabilityHandler = nil
        }
        return lock.withLock { data }
    }
}
