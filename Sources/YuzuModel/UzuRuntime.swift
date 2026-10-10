import Foundation
import Uzu
import YuzuHarness

public struct InstalledModel: Sendable {
    public var identifier: String
    public var name: String
    public var turn: UzuTurn
}

public enum UzuRuntime {
    /// Asks the local uzu engine which chat model fits this Mac, then downloads it into uzu's cache.
    /// The app bundle does not contain weights.
    public static func installAdvised(
        progress: @MainActor @escaping (String) -> Void
    ) async throws -> InstalledModel {
        let engine = try await Engine.create(config: .create())
        let device = try Device.create()
        let models = try await engine.modelsForChat()
        let candidates = models.map(Self.candidate)
        guard let advised = ModelAdvice.advise(candidates, memoryTotal: device.memoryTotal) else {
            throw UzuTurnError.modelUnavailable("No chat model fits \(device.memoryTotal) bytes of memory")
        }
        guard let model = models.first(where: { $0.identifier == advised.identifier }) else {
            throw UzuTurnError.modelUnavailable(advised.identifier)
        }
        print("UzuRuntime advised \(model.identifier) checkpoint=\(advised.checkpointBytes) memory=\(device.memoryTotal)")
        await progress(model.name())
        try await download(engine: engine, model: model, progress: progress)
        return InstalledModel(
            identifier: model.identifier,
            name: model.name(),
            turn: UzuTurn(engine: engine, model: model)
        )
    }

    static func candidate(_ model: Model) -> ModelCandidate {
        ModelCandidate(
            identifier: model.identifier,
            name: model.name(),
            parameterCount: model.properties?.size ?? 0,
            checkpointBytes: checkpointBytes(model),
            quantizationMethod: model.quantization?.method ?? "",
            bitsPerWeight: Int(model.quantization?.bitsPerWeight ?? 16),
            isChat: model.isChatCapable()
        )
    }

    static func checkpointBytes(_ model: Model) -> Int64 {
        if case .onDevice(let source) = model.accessibility,
           case .registry(_, _, _, let files) = source,
           !files.isEmpty {
            return files.reduce(Int64(0)) { $0 + $1.size }
        }
        let parameters = model.properties?.size ?? 0
        let bits = Int64(model.quantization?.bitsPerWeight ?? 16)
        return parameters * bits / 8
    }

    private static func download(
        engine: Engine,
        model: Model,
        progress: @MainActor @escaping (String) -> Void
    ) async throws {
        let download = try await engine.download(model: model)
        let name = model.name()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await update in download.iterator() {
                    if case .error(let message) = update.phase {
                        throw UzuTurnError.downloadFailed(message)
                    }
                }
            }
            group.addTask {
                var lastPrinted = -1
                while true {
                    if let state = await engine.downloadState(model: model) {
                        if case .downloaded = state.phase {
                            await progress(name)
                            return
                        }
                        if case .error(let message) = state.phase {
                            throw UzuTurnError.downloadFailed(message)
                        }
                        let percent = Int(state.progress() * 100)
                        if percent != lastPrinted {
                            await progress("Downloading \(name) \(percent)%")
                            lastPrinted = percent
                        }
                    }
                    try await Task.sleep(for: .milliseconds(400))
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
