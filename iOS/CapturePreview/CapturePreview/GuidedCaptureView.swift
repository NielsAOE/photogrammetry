import SwiftUI
import RealityKit

// MARK: - Guided capture around RealityKit's ObjectCaptureView/ObjectCaptureSession (Swift 6.1 / iOS 18)
// Uses the modern SwiftUI-based ObjectCaptureView(session:) API.
// - No UIKit bridge or delegate needed (the session publishes state you can observe).
// - ObjectCaptureSession writes images to the imagesDirectory you pass to start(...).
// - Controls like startDetecting()/startCapturing()/pause()/resume()/finish() are called directly.
// - You can advance passes with beginNewScanPass() or beginNewScanPassAfterFlip().

public struct GuidedCaptureView: View {
    @Binding var stageFolder: URL

    @StateObject private var model = CaptureModel()

    // UI toggles
    @State private var isPaused = false
    @State private var turntableMode = false
    @State private var exposureLockHint = false

    public init(stageFolder: Binding<URL>) {
        self._stageFolder = stageFolder
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // RealityKit's guided capture UI
            ObjectCaptureView(session: model.session)
                .ignoresSafeArea()
                .task(id: stageFolder) { // (re)start when the target directory changes
                    await model.startSession(imagesDirectory: stageFolder)
                }

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
                    // Session state-driven primary button(s)
                    switch model.session.state {
                    case .ready:
                        Button {
                            model.session.startDetecting()
                        } label: { Label("Continue", systemImage: "arrow.right.circle") }

                    case .detecting:
                        Button {
                            model.session.startCapturing()
                        } label: { Label("Start Capture", systemImage: "camera.viewfinder") }

                    case .capturing:
                        if model.session.userCompletedScanPass {
                            Button {
                                if turntableMode {
                                    model.session.beginNewScanPassAfterFlip()
                                } else {
                                    model.session.beginNewScanPass()
                                }
                            } label: { Label("New Pass", systemImage: "gobackward") }

                            Divider().frame(height: 24)

                            Button { model.session.finish() } label: {
                                Label("Finish", systemImage: "checkmark.circle")
                            }
                        }

                    case .finishing:
                        ProgressView("Saving…")

                    case .completed:
                        Label("Completed", systemImage: "checkmark.seal")

                    case .failed(let error):
                        Label("Failed: \(error.localizedDescription)", systemImage: "xmark.octagon")
                    
                    default:
                        EmptyView()
                    }

                    Spacer()
                    Divider().frame(height: 24)

                    Button {
                        isPaused.toggle()
                        if isPaused { model.session.pause() } else { model.session.resume() }
                    } label: {
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

// MARK: - Model wrapper for the session
@MainActor
final class CaptureModel: ObservableObject {
    let session = ObjectCaptureSession()

    /// Start (or restart) the session pointing to the folder where RealityKit will write images.
    func startSession(imagesDirectory: URL) async {
        var configuration = ObjectCaptureSession.Configuration()
        // Optional: store intermediate snapshots/checkpoints alongside images for faster macOS reconstruction.
        configuration.checkpointDirectory = imagesDirectory.appendingPathComponent("Snapshots", conformingTo: .directory)
        // Optional: allow capturing more images than on-device reconstruction uses
        // when you plan to reconstruct on Mac.
        configuration.isOverCaptureEnabled = true

        do {
            try await session.start(imagesDirectory: imagesDirectory, configuration: configuration)
        } catch {
            print("ObjectCaptureSession start failed:", error)
        }
    }
}
