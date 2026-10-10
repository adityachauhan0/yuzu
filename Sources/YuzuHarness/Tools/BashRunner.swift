import Foundation

enum BashRunner {
    static let defaultTimeoutSeconds: TimeInterval = 120

    static func run(command: String, workingDirectory: String, timeoutSeconds: TimeInterval?) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error: \(error.localizedDescription)"
        }

        let limit = timeoutSeconds ?? defaultTimeoutSeconds
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + limit) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return "Error: command timed out after \(Int(limit)) second(s)"
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

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
