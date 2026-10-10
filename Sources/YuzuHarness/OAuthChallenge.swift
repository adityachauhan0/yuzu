import Foundation

public struct OAuthAuthorization: Equatable, Sendable {
    public var authorizationURI: String?
    public var tokenURI: String?

    public init(authorizationURI: String?, tokenURI: String?) {
        self.authorizationURI = authorizationURI
        self.tokenURI = tokenURI
    }
}

public enum OAuthChallenge {
    public static func parse(_ header: String) -> OAuthAuthorization {
        OAuthAuthorization(
            authorizationURI: value("authorization_uri", in: header),
            tokenURI: value("token_uri", in: header)
        )
    }

    /// Pulls `authorization_uri="..."` out of a WWW-Authenticate challenge.
    public static func authorizationURI(from header: String) -> String? {
        parse(header).authorizationURI
    }

    private static func value(_ name: String, in header: String) -> String? {
        guard let match = header.range(
            of: #"\#(name)="([^"]+)""#,
            options: .regularExpression
        ) else {
            return nil
        }
        let raw = String(header[match])
        guard let quote = raw.firstIndex(of: "\"") else { return nil }
        let uri = String(raw[raw.index(after: quote)...].dropLast())
        return uri.isEmpty ? nil : uri
    }
}
