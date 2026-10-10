import Foundation

public enum Delivery: String, Sendable, Codable {
    case steer
    case queue
}

public enum SessionStatus: String, Sendable, Equatable, Codable {
    case idle
    case running
    case waitingPermission = "waiting_permission"
}

public enum PermissionEffect: String, Sendable, Equatable, Codable {
    case allow
    case deny
    case ask
}

public struct PermissionRule: Sendable, Equatable, Codable {
    public var action: String
    public var resource: String
    public var effect: PermissionEffect

    public init(action: String, resource: String, effect: PermissionEffect) {
        self.action = action
        self.resource = resource
        self.effect = effect
    }
}

public enum PermissionReply: Sendable {
    case once
    case always
    case reject
}

public protocol HarnessClient: Sendable {
    func prompt(_ text: String, delivery: Delivery) async
    func cancel() async
    func replyPermission(_ id: String, _ reply: PermissionReply) async
    func setAgent(_ id: String) async
}
