import Foundation

/// Serializes `ModelTurn.complete` so parent and subagent drains never overlap.
public actor ModelTurnCoordinator {
    public static let shared = ModelTurnCoordinator()

    public func withTurn<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await operation()
    }
}
