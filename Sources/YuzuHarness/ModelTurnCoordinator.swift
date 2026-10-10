import Foundation
import os

public actor ModelTurnCoordinator {
    public static let shared = ModelTurnCoordinator()

    public func withTurn<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await operation()
    }
}

/// The epoch each model instance last answered. One model serves every session in the window,
/// so a session whose epoch is not the last one served must send its whole projected history.
public final class ModelEpochLedger: Sendable {
    public static let shared = ModelEpochLedger()

    private let served = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: String]())

    public func lastEpoch(of model: any ModelTurn) -> String? {
        served.withLock { $0[ObjectIdentifier(model)] }
    }

    public func record(_ epochID: String, for model: any ModelTurn) {
        served.withLock { $0[ObjectIdentifier(model)] = epochID }
    }

    public func forget(_ model: any ModelTurn) {
        served.withLock { $0[ObjectIdentifier(model)] = nil }
    }
}
