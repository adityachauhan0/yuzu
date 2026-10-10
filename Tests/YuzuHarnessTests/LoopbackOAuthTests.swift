import Foundation
import Testing
import YuzuHarness

struct LoopbackOAuthTests {
    @Test func redirectReturnsTheCode() async throws {
        let session = try LoopbackOAuth.start(timeout: 5)
        let url = URL(string: session.redirectURI + "?code=yuzu-code")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("close this window"))
        let code = try await session.code()
        #expect(code == "yuzu-code")
    }

    @Test func requestWithoutACodeIsIgnored() {
        #expect(LoopbackOAuth.code(in: "GET /callback HTTP/1.1\r\n\r\n") == nil)
        #expect(LoopbackOAuth.code(in: "GET /callback?code=abc HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n") == "abc")
    }
}

private final class TokenEndpointProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
        }
        Self.body = String(decoding: data, as: UTF8.self)
        let json = Data(#"{"access_token":"tok-1","token_type":"Bearer"}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: json)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct OAuthTokenExchangeTests {
    @Test func exchangesTheCodeForAnAccessToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TokenEndpointProtocol.self]
        let session = URLSession(configuration: configuration)
        let token = try await OAuthTokenExchange.accessToken(
            tokenURI: "https://example.test/token",
            code: "abc",
            redirectURI: "http://127.0.0.1:9/callback",
            codeVerifier: "verifier",
            session: session
        )
        #expect(token == "tok-1")
        #expect(TokenEndpointProtocol.body.contains("grant_type=authorization_code"))
        #expect(TokenEndpointProtocol.body.contains("code=abc"))
        #expect(TokenEndpointProtocol.body.contains("code_verifier=verifier"))
    }

    @Test func keychainRoundTripsTheToken() throws {
        try KeychainTokenStore.save("tok-1", account: "yuzu-oauth-test")
        #expect(KeychainTokenStore.load(account: "yuzu-oauth-test") == "tok-1")
    }
}
