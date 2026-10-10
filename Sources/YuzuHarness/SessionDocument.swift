import Foundation

public struct SessionDocument: Codable, Equatable, Sendable {
    public var id: String
    public var projectPath: String
    public var modelIdentifier: String
    public var messages: [StoredMessage]

    public init(id: String, projectPath: String, modelIdentifier: String, messages: [StoredMessage]) {
        self.id = id
        self.projectPath = projectPath
        self.modelIdentifier = modelIdentifier
        self.messages = messages
    }
}
