import Foundation

@MainActor
final class StageManager: ObservableObject {
    @Published var stageFolder: URL
    @Published var captureCount: Int = 0
    @Published var folderBytes: Int64 = 0

    private var timer: Timer?

    init() {
        let base = FileManager.default.temporaryDirectory
        stageFolder = base.appendingPathComponent("OCStage_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stageFolder, withIntermediateDirectories: true)
        startPolling()
    }

    deinit { timer?.invalidate() }

    func resetStage() {
        try? FileManager.default.removeItem(at: stageFolder)
        stageFolder = FileManager.default.temporaryDirectory.appendingPathComponent("OCStage_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stageFolder, withIntermediateDirectories: true)
        updateStats()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.updateStats() }
    }

    private func updateStats() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: stageFolder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
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