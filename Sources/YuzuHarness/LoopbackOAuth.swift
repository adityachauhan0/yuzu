import Darwin
import Foundation

public enum LoopbackOAuthError: Error, Equatable {
    case failedToListen
    case missingCode
    case timedOut
}

/// Listens on 127.0.0.1 for the browser redirect and returns the `code` query item.
public final class LoopbackOAuthSession: @unchecked Sendable {
    public let redirectURI: String
    private let waiter: CodeWaiter

    fileprivate init(redirectURI: String, waiter: CodeWaiter) {
        self.redirectURI = redirectURI
        self.waiter = waiter
    }

    public func code() async throws -> String {
        try await waiter.wait()
    }

    public func cancel() {
        waiter.fail(LoopbackOAuthError.timedOut)
    }
}

public enum LoopbackOAuth {
    public static func start(timeout: TimeInterval = 180) throws -> LoopbackOAuthSession {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LoopbackOAuthError.failedToListen }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            close(fd)
            throw LoopbackOAuthError.failedToListen
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            close(fd)
            throw LoopbackOAuthError.failedToListen
        }
        let port = UInt16(bigEndian: actual.sin_port)
        let redirectURI = "http://127.0.0.1:\(port)/callback"
        let waiter = CodeWaiter()
        DispatchQueue.global(qos: .userInitiated).async {
            let client = accept(fd, nil, nil)
            guard client >= 0 else {
                waiter.fail(LoopbackOAuthError.failedToListen)
                close(fd)
                return
            }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = read(client, &buffer, buffer.count)
            let text = count > 0 ? String(bytes: buffer.prefix(count), encoding: .utf8) ?? "" : ""
            let page = "<p>Yuzu received the sign-in. You can close this window.</p>"
            let header = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(page.utf8.count)\r
            Connection: close\r
            \r

            """
            var response = Data(header.utf8)
            response.append(Data(page.utf8))
            response.withUnsafeBytes { raw in
                _ = write(client, raw.baseAddress, raw.count)
            }
            close(client)
            close(fd)
            if let code = Self.code(in: text) {
                waiter.succeed(code)
            } else {
                waiter.fail(LoopbackOAuthError.missingCode)
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
            waiter.fail(LoopbackOAuthError.timedOut)
            close(fd)
        }
        return LoopbackOAuthSession(redirectURI: redirectURI, waiter: waiter)
    }

    public static func code(in request: String) -> String? {
        guard let first = request.split(separator: "\r\n", omittingEmptySubsequences: false).first else {
            return nil
        }
        let pieces = first.split(separator: " ")
        guard pieces.count >= 2 else { return nil }
        let target = String(pieces[1])
        guard let components = URLComponents(string: "http://127.0.0.1" + target) else { return nil }
        return components.queryItems?.first { $0.name == "code" }?.value
    }
}

private final class CodeWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?

    func wait() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func succeed(_ code: String) {
        finish(.success(code))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ next: Result<String, Error>) {
        lock.lock()
        if result != nil {
            lock.unlock()
            return
        }
        result = next
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: next)
    }
}
