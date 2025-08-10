import SwiftUI
import UIKit
import RealityKit

/// Guided capture around ObjectCaptureView/ObjectCaptureSession
struct GuidedCaptureView: View {
    @Binding var stageFolder: URL

    @State private var isPaused = false
    @State private var turntableMode = false
    @State private var exposureLockHint = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ObjectCaptureContainer(stageFolder: $stageFolder,
                                   isPaused: $isPaused,
                                   turntableMode: $turntableMode)

            // Guidance card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().frame(width: 6, height: 6)
                    Text(turntableMode ? "Turntable: rotate a bit between shots" : "Walk around the object")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                if exposureLockHint {
                    Text("Tip: keep lighting constant; avoid exposure shifts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(8)

            // Bottom toolbar
            VStack { Spacer()
                HStack(spacing: 16) {
                    Button { isPaused.toggle() } label: {
                        Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.circle" : "pause.circle")
                    }
                    Divider().frame(height: 24)
                    Button { turntableMode.toggle() } label: {
                        Label(turntableMode ? "Turntable On" : "Turntable Off", systemImage: "dial.max")
                    }
                    Divider().frame(height: 24)
                    Button { exposureLockHint.toggle() } label: {
                        Label(exposureLockHint ? "Exposure Hint On" : "Exposure Hint Off", systemImage: "camera.aperture")
                    }
                    Spacer()
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }
}

struct ObjectCaptureContainer: UIViewControllerRepresentable {
    @Binding var stageFolder: URL
    @Binding var isPaused: Bool
    @Binding var turntableMode: Bool

    func makeUIViewController(context: Context) -> ObjectCaptureViewController {
        let vc = ObjectCaptureViewController()
        vc.stageURL = stageFolder
        return vc
    }

    func updateUIViewController(_ uiViewController: ObjectCaptureViewController, context: Context) {
        uiViewController.isPaused = isPaused
        uiViewController.turntableMode = turntableMode
        uiViewController.stageURL = stageFolder
    }
}

final class ObjectCaptureViewController: UIViewController, RealityKit.ObjectCaptureSessionDelegate {
    private var captureView: ObjectCaptureView<EmptyView>!
    private var session: RealityKit.ObjectCaptureSession!

    // Provided by SwiftUI
    var stageURL: URL = FileManager.default.temporaryDirectory

    // controls
    var isPaused: Bool = false
    var turntableMode: Bool = false

    private var lastSaveTime: TimeInterval = 0
    private let minIntervalTurntable: TimeInterval = 0.8

    private let hudLabel = UILabel()

    // Background writer
    private let ioQueue = DispatchQueue(label: "oc.writer.queue")

    override func viewDidLoad() {
        super.viewDidLoad()

        session = RealityKit.ObjectCaptureSession()
        session.delegate = self
        session.sampleBufferCaptureEnabled = true
        session.isObjectMaskingEnabled = true

        captureView = ObjectCaptureView(session: session)
        captureView.frame = view.bounds
        captureView.autoresizingMask = [UIView.AutoresizingMask.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)

        // HUD
        hudLabel.text = ""
        hudLabel.textColor = .white
        hudLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        hudLabel.layer.cornerRadius = 8
        hudLabel.clipsToBounds = true
        hudLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hudLabel)
        NSLayoutConstraint.activate([
            hudLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hudLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -70)
        ])

        Task { @MainActor in
            do { try await session.start(imagesDirectory: stageURL) }
            catch { print("ObjectCapture start failed:", error) }
        }
    }

    // MARK: - ObjectCaptureSessionDelegate
    func objectCaptureSession(_ session: RealityKit.ObjectCaptureSession, didAdd sample: RealityKit.ObjectCaptureSession.Sample) {
        if isPaused { return }
        if turntableMode {
            let now = CACurrentMediaTime()
            if now - lastSaveTime < minIntervalTurntable { return }
            lastSaveTime = now
            DispatchQueue.main.async { [weak self] in self?.hudLabel.text = "Capture saved — rotate a bit…" }
        }
        guard let data = sample.photoDataRepresentation() else { return }
        let target = stageURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        let bytes = data // capture now; write off-thread below
        ioQueue.async {
            do { try bytes.write(to: target, options: Data.WritingOptions.atomic) }
            catch { print("Write failed:", error) }
        }
    }

    func objectCaptureSession(_ session: RealityKit.ObjectCaptureSession, didChange state: RealityKit.ObjectCaptureSession.CaptureState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .initializing: self?.hudLabel.text = "Initializing…"
            case .ready: self?.hudLabel.text = "Ready"
            case .running: self?.hudLabel.text = "Capturing…"
            case .paused: self?.hudLabel.text = "Paused"
            case .completed: self?.hudLabel.text = "Completed"
            case .failed(let error): self?.hudLabel.text = "Failed: \(error.localizedDescription)"
            @unknown default: self?.hudLabel.text = ""
            }
        }
    }
}