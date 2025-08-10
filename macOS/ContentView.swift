import SwiftUI
import RealityKit
import AppKit

struct ContentView: View {
    @StateObject private var peer = ReceiverPeer()
    @State private var stagedFolder: URL?
    @State private var status = "Waiting…"
    @State private var detail: PhotogrammetrySession.Request.Detail = .full
    @State private var format: ModelFormat = .usdz

    @State private var reconSession: PhotogrammetrySession?
    @State private var outputURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Receiver & High‑Quality Reconstruct").font(.title2)
            Text(peer.connectionStatus).font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Advertise to iPhone") { peer.startAdvertising() }
                Button("Stop Advertising") { peer.stopAdvertising() }
                Button("Open Folder…") { openFolder() }
                Picker("Quality", selection: $detail) {
                    Text("Medium").tag(PhotogrammetrySession.Request.Detail.medium)
                    Text("Full").tag(PhotogrammetrySession.Request.Detail.full)
                    Text("RAW").tag(PhotogrammetrySession.Request.Detail.raw)
                }.pickerStyle(.segmented)
                Picker("Format", selection: $format) {
                    Text("USDZ").tag(ModelFormat.usdz)
                    Text("OBJ+Textures").tag(ModelFormat.obj)
                }.pickerStyle(.segmented)
                Spacer()
                Button("Reconstruct") { Task { await reconstruct() } }.disabled(stagedFolder == nil || reconSession != nil)
                if reconSession != nil { Button(role: .destructive, action: cancel) { Text("Cancel") } }
            }

            HStack(spacing: 12) {
                if let folder = stagedFolder { Text("Images: \(countImages(in: folder)) • Size: \(byteString(folderBytes(folder)))") }
                Spacer()
                if let url = outputURL { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                if let url = outputURL, format == .usdz { Button("Open in Preview") { NSWorkspace.shared.open(url) } }
            }.font(.subheadline).foregroundStyle(.secondary)

            Text(status)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)
            Spacer()
        }
        .padding()
        .frame(minWidth: 820, minHeight: 480)
        .onReceive(peer.$receivedFolder) { folder in
            if let folder {
                let filtered = filterToImages(folder)
                stagedFolder = filtered
                status = "Received files: \(countImages(in: filtered))"
            }
        }
    }

    func openFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let url = p.url { stagedFolder = filterToImages(url) }
    }

    func cancel() { reconSession?.cancel() }

    func reconstruct() async {
        guard let input = stagedFolder else { return }
        let minFree: Int64 = 1_000 * 1_024 * 1_024 // 1 GB safety for HQ runs
        guard deviceFreeBytes() > minFree else { status = "Low disk space"; return }

        status = "Starting…"
        outputURL = nil
        do {
            var cfg = PhotogrammetrySession.Configuration()
            cfg.sampleOrdering = .unordered
            cfg.isObjectMaskingEnabled = true

            guard let saveURL = askForSaveURL(format: format) else { status = "Cancelled"; return }

            let session = try PhotogrammetrySession(input: input, configuration: cfg)
            reconSession = session
            let req = PhotogrammetrySession.Request.modelFile(url: saveURL, detail: detail)

            let outputs = Task {
                for await e in session.outputs {
                    switch e {
                    case .requestProgress(_, let f): status = "Building… \(Int(f*100))%"
                    case .requestComplete(_, let r):
                        if case .modelFile(let url) = r {
                            outputURL = url
                            status = "Done → \(url.path(percentEncoded: false))\n\n" + (format == .obj ? "OBJ comes with .mtl + textures in the same folder." : "")
                        }
                    case .error(let err), .requestError(_, let err): status = "Error: \(err.localizedDescription)"
                    default: break
                    }
                }
            }
            try session.process(requests: [req])
            _ = try await outputs.value
        } catch is CancellationError {
            status = "Cancelled"
        } catch { status = "Failed: \(error.localizedDescription)" }
        reconSession = nil
    }

    func askForSaveURL(format: ModelFormat) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        switch format {
        case .usdz:
            panel.allowedFileTypes = ["usdz"]
            panel.nameFieldStringValue = "Model.usdz"
        case .obj:
            panel.allowedFileTypes = ["obj"]
            panel.nameFieldStringValue = "Model.obj"
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func deviceFreeBytes() -> Int64 {
        (try? FileManager.default.attributesOfFileSystem(forPath: "/")[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    func folderBytes(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var bytes: Int64 = 0
        for case let u as URL in en {
            if ((try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) {
                bytes += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return bytes
    }

    func countImages(in folder: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { ["jpg","jpeg","png","heic"].contains($0.pathExtension.lowercased()) }
            .count) ?? 0
    }

    func filterToImages(_ folder: URL) -> URL {
        // Create a filtered temp dir with only supported image files to reduce surprises.
        let fm = FileManager.default
        let filtered = fm.temporaryDirectory.appendingPathComponent("OC_Filtered_\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: filtered, withIntermediateDirectories: true)
        if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for f in files where ["jpg","jpeg","png","heic"].contains(f.pathExtension.lowercased()) {
                let dest = filtered.appendingPathComponent(f.lastPathComponent)
                try? fm.copyItem(at: f, to: dest)
            }
        }
        return filtered
    }

    func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter(); formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

enum ModelFormat { case usdz, obj }