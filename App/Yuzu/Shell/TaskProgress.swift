import Darwin
import SwiftUI
import YuzuHarness

struct TaskStep: Identifiable {
    var id: String
    var title: String
    var status: TodoItem.Status
}

struct MachineSample: Equatable {
    var cpuPercent: Double = 0
    var modelBytes: UInt64 = 0
    var totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    var cpuLabel: String { "\(Int(cpuPercent.rounded()))%" }

    var memoryLabel: String { Self.bytes(modelBytes) }

    /// Share of this Mac's memory held by the process running the model.
    var memoryFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(modelBytes) / Double(totalBytes))
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

@MainActor
final class MachineMonitor: ObservableObject {
    static let shared = MachineMonitor()

    @Published private(set) var sample = MachineSample()
    private var timer: Timer?
    private var previousCPU: (seconds: Double, at: Date)?

    func start() {
        guard timer == nil else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        sample = MachineLoad.read(previous: &previousCPU)
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                var previous = MachineMonitor.shared.previousCPU
                MachineMonitor.shared.sample = MachineLoad.read(previous: &previous)
                MachineMonitor.shared.previousCPU = previous
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

enum MachineLoad {
    static func read(previous: inout (seconds: Double, at: Date)?) -> MachineSample {
        var sample = MachineSample()
        sample.totalBytes = ProcessInfo.processInfo.physicalMemory
        sample.modelBytes = appFootprint()
        if let seconds = processCPUSeconds() {
            let now = Date()
            if let previous {
                let cpuDelta = seconds - previous.seconds
                let wall = now.timeIntervalSince(previous.at)
                let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
                if wall > 0, cores > 0 {
                    sample.cpuPercent = min(100, max(0, cpuDelta / wall / cores * 100))
                }
            }
            previous = (seconds, now)
        }
        return sample
    }

    /// User plus system time of this process. The model runs in-process, so this is its CPU.
    private static func processCPUSeconds() -> Double? {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        func seconds(_ time: time_value_t) -> Double {
            Double(time.seconds) + Double(time.microseconds) / 1_000_000
        }
        return seconds(info.user_time) + seconds(info.system_time)
    }

    private static func appFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }
}

struct TaskProgressBar: View {
    let fraction: Double
    let colors: ThemeColors

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.line)
                Capsule()
                    .fill(colors.accent)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
    }
}

struct MachineMeters: View {
    let sample: MachineSample
    let modelName: String
    let colors: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(modelName)
                .font(.system(size: 13))
                .foregroundStyle(colors.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityID("machine-model", label: modelName)
            meter("CPU", value: sample.cpuLabel, fraction: sample.cpuPercent / 100, id: "machine-cpu")
            meter("RAM", value: sample.memoryLabel, fraction: sample.memoryFraction, id: "machine-ram")
        }
    }

    private func meter(_ title: String, value: String, fraction: Double, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.dim)
                Spacer()
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            TaskProgressBar(fraction: min(1, max(0, fraction)), colors: colors)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityID(id, label: "\(title) \(value)")
    }
}
