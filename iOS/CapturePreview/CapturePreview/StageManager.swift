import Foundation
import Observation

@MainActor
@Observable
final class StageManager {
    var stageFolder: URL
    var captureCount: Int = 0
    var folderBytes: Int64 = 0
    var lastError: String?

    private var pollTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.temporaryDirectory
        stageFolder = base.appendingPathComponent("OCStage_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stageFolder, withIntermediateDirectories: true)
        } catch {
            lastError = "Failed to create stage folder: \(error.localizedDescription)"
            print("StageManager error:", error)
        }
        startPolling()
    }

    // NOTE (Swift 6.1): `deinit` is nonisolated, so we must not touch
    // main-actor state there. The polling task is written to exit on its own
    // when `self` is released (see `startPolling`).

    @discardableResult
    func resetStage() -> Bool {
        do { try FileManager.default.removeItem(at: stageFolder) } catch {
            lastError = "Failed to remove stage folder: \(error.localizedDescription)"
            print("StageManager error:", error)
            return false
        }
        stageFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("OCStage_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stageFolder, withIntermediateDirectories: true)
        } catch {
            lastError = "Failed to create stage folder: \(error.localizedDescription)"
            print("StageManager error:", error)
            return false
        }
        updateStats()
        return true
    }

    private func startPolling() {
        pollTask?.cancel()
        // Use a weak self that is re-unwrapped every iteration so the task
        // stops automatically once `self` is deallocated (no `deinit` needed).
        pollTask = Task { [weak self] in
            while let strongSelf = self, !Task.isCancelled {
                await MainActor.run { strongSelf.updateStats() }
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    private func updateStats() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: stageFolder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var count = 0
        var bytes: Int64 = 0
        for u in urls {
            if (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false {
                count += 1
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                bytes += Int64(size)
            }
        }
        captureCount = count
        folderBytes = bytes
    }
}
