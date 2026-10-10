import Foundation

/// One chat model the advisor can see. Checkpoint size is what uzu compares to total memory.
public struct ModelCandidate: Sendable, Equatable {
    public var identifier: String
    public var name: String
    public var parameterCount: Int64
    public var checkpointBytes: Int64
    public var quantizationMethod: String
    public var bitsPerWeight: Int
    public var isChat: Bool

    public init(
        identifier: String,
        name: String,
        parameterCount: Int64,
        checkpointBytes: Int64,
        quantizationMethod: String,
        bitsPerWeight: Int,
        isChat: Bool
    ) {
        self.identifier = identifier
        self.name = name
        self.parameterCount = parameterCount
        self.checkpointBytes = checkpointBytes
        self.quantizationMethod = quantizationMethod
        self.bitsPerWeight = bitsPerWeight
        self.isChat = isChat
    }
}

/// Same ordering uzu uses in `resolve_model_shorthand`: mirai-m first, then the largest
/// checkpoint that still fits in total memory. Weights are never bundled with the app.
public enum ModelAdvice {
    /// uzu allows any checkpoint up to total RAM. That selects a model with no room left to run.
    /// Half the RAM stays free for the system and the context cache.
    public static let weightMemoryFraction = 0.5

    public static func advise(_ models: [ModelCandidate], memoryTotal: Int64) -> ModelCandidate? {
        guard memoryTotal > 0 else { return nil }
        let ceiling = Int64(Double(memoryTotal) * weightMemoryFraction)
        let fitting = models.filter { candidate in
            candidate.isChat && candidate.checkpointBytes > 0 && candidate.checkpointBytes <= ceiling
        }
        return fitting.sorted { left, right in
            let priority = quantizationPriority(left.quantizationMethod) - quantizationPriority(right.quantizationMethod)
            if priority != 0 { return priority < 0 }
            if left.parameterCount != right.parameterCount {
                return left.parameterCount > right.parameterCount
            }
            if left.bitsPerWeight != right.bitsPerWeight {
                return left.bitsPerWeight > right.bitsPerWeight
            }
            return left.identifier < right.identifier
        }.first
    }

    private static func quantizationPriority(_ method: String) -> Int {
        if method.caseInsensitiveCompare("mirai-m") == .orderedSame { return 0 }
        if method.caseInsensitiveCompare("mirai-s") == .orderedSame { return 1 }
        return 2
    }
}
