import SwiftUI
import RealityKit
import UIKit
import Observation

struct ContentView: View {
    @State private var stage = StageManager()
    @State private var peer = CapturePeer()

    @State private var isProcessing = false
    @State private var progressText = "Idle"
    @State private var previewURL: URL?

    // AirDrop fallback
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var shareZipURL: URL?

    // Cancellation
    @State private var previewSession: PhotogrammetrySession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GuidedCaptureView(stageFolder: $stage.stageFolder)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    Button { Task { await reconstructPreview() } } label: {
                        Label("Build Preview (Reduced)", systemImage: "cube.transparent")
                    }
                    .disabled(isProcessing)

                    if isProcessing {
                        ProgressView(progressText).frame(minWidth: 120)
                        Button(role: .destructive) { cancelPreview() } label: { Label("Cancel", systemImage: "xmark.circle") }
                    }

                    if let url = previewURL {
                        ShareLink(item: url) { Label("Share Preview USDZ", systemImage: "square.and.arrow.up") }
                    }

                    Spacer()

                    Button { _ = stage.resetStage() } label: { Label("Reset Stage", systemImage: "trash") }
                }

                // Stats row
                HStack(spacing: 12) {
                    Label("Shots: \(stage.captureCount)", systemImage: "camera")
                    Label("Size: \(byteString(stage.folderBytes))", systemImage: "externaldrive")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Divider().padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Send to Mac for High Quality").font(.headline)
                    Text(peer.connectionStatus).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { peer.startBrowsing() } label: { Label("Find Mac", systemImage: "dot.radiowaves.left.and.right") }
                        Button { Task { await sendToMac() } } label: { Label("Send via Multipeer (ZIP)", systemImage: "macbook.and.iphone") }
                            .disabled(stage.captureCount == 0 || !peer.isConnected)
                        if let p = peer.currentSendProgress {
                            ProgressView(value: p.fractionCompleted) { Text("Sending…") }
                                .frame(width: 120)
                        }
                        Spacer()
                        Button { Task { await shareViaAirDropFallback() } } label: { Label("AirDrop (ZIP)", systemImage: "airplayaudio") }
                            .disabled(stage.captureCount == 0)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Capture & Preview")
            .sheet(isPresented: $showShareSheet, onDismiss: {
                if let url = shareZipURL {
                    try? FileManager.default.removeItem(at: url)
                    shareZipURL = nil
                }
                shareItems = []
            }) { ShareSheet(activityItems: shareItems) }
            .onDisappear { peer.stopBrowsing() }
            .alert("Stage Error", isPresented: Binding<Bool>(
                get: { stage.lastError != nil },
                set: { _ in stage.lastError = nil }
            )) {
                Button("OK", role: .cancel) { stage.lastError = nil }
            } message: { Text(stage.lastError ?? "") }
        }
    }

    func deviceFreeBytes() -> Int64 {
        (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - On-device preview (iOS supports .reduced)
    func reconstructPreview() async {
        guard stage.captureCount > 0 else { return }
        let minFree: Int64 = 200 * 1_024 * 1_024 // 200 MB safety
        guard deviceFreeBytes() > minFree else { progressText = "Low disk space"; return }

        isProcessing = true
        progressText = "Preparing…"
        UIApplication.shared.isIdleTimerDisabled = true
        defer { isProcessing = false; UIApplication.shared.isIdleTimerDisabled = false; previewSession = nil }

        do {
            var cfg = PhotogrammetrySession.Configuration()
            cfg.sampleOrdering = .unordered
            cfg.isObjectMaskingEnabled = true

            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("Preview-\(UUID().uuidString).usdz")
            let session = try PhotogrammetrySession(input: stage.stageFolder, configuration: cfg)
            previewSession = session
            let req = PhotogrammetrySession.Request.modelFile(url: out, detail: .reduced)

            let outputs = Task { @MainActor in
                for try await e in session.outputs {
                    switch e {
                    case .requestProgress(_, let f):
                        progressText = "Building… \(Int(f * 100))%"
                    case .requestComplete(_, let result):
                        if case .modelFile(let url) = result { previewURL = url }
                    case .requestError(_, let err):
                        progressText = "Error: \(err.localizedDescription)"
                    case .processingComplete:
                        break
                    default:
                        break
                    }
                }
            }

            try session.process(requests: [req])
            _ = try await outputs.value
            progressText = previewURL == nil ? "No output" : "Done"
        } catch is CancellationError {
            progressText = "Cancelled"
        } catch {
            progressText = "Failed: \(error.localizedDescription)"
        }
    }

    func cancelPreview() { previewSession?.cancel() }

    // MARK: - Multipeer send (ZIP via sendResource) with progress
    func sendToMac() async {
        do {
            let zipURL = try SimpleZip.zipFolder(at: stage.stageFolder, zipName: "CaptureSet-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: zipURL) }
            try await peer.sendFile(zipURL)
        } catch { print("Multipeer zip send failed:", error) }
    }

    // MARK: - AirDrop fallback (ZIP)
    func shareViaAirDropFallback() async {
        do {
            let zipURL = try SimpleZip.zipFolder(at: stage.stageFolder, zipName: "CaptureSet-\(UUID().uuidString).zip")
            shareZipURL = zipURL
            shareItems = [zipURL]
            showShareSheet = true
        } catch { print("AirDrop fallback zip failed:", error) }
    }

    // MARK: - Utils
    func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
