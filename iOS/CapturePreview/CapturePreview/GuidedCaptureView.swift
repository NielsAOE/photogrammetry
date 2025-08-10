// MARK: - File: GuidedCaptureView.swift
import SwiftUI
import RealityKit
import Observation

public struct GuidedCaptureView: View {
    @Binding var stageFolder: URL
    @State private var model = CaptureModel()

    // UI toggles
    @State private var isPaused = false
    @State private var turntableMode = false
    @State private var exposureLockHint = false

    public init(stageFolder: Binding<URL>) { self._stageFolder = stageFolder }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ObjectCaptureView(session: model.session)
                .ignoresSafeArea()
                .task(id: stageFolder) {
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
                    switch model.session.state {
                    case .ready:
                        Button { model.session.startDetecting() } label: { Label("Continue", systemImage: "arrow.right.circle") }
                    case .detecting:
                        Button { model.session.startCapturing() } label: { Label("Start Capture", systemImage: "camera.viewfinder") }
                    case .capturing:
                        if model.session.userCompletedScanPass {
                            Button {
                                if turntableMode { model.session.beginNewScanPassAfterFlip() }
                                else { model.session.beginNewScanPass() }
                            } label: { Label("New Pass", systemImage: "gobackward") }
                            Divider().frame(height: 24)
                            Button { model.session.finish() } label: { Label("Finish", systemImage: "checkmark.circle") }
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
                    } label: { Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.circle" : "pause.circle") }

                    Divider().frame(height: 24)
                    Button { turntableMode.toggle() } label: { Label(turntableMode ? "Turntable On" : "Turntable Off", systemImage: "dial.max") }
                    Divider().frame(height: 24)
                    Button { exposureLockHint.toggle() } label: { Label(exposureLockHint ? "Exposure Hint On" : "Exposure Hint Off", systemImage: "camera.aperture") }
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

@MainActor
@Observable
final class CaptureModel {
    let session = ObjectCaptureSession()

    func startSession(imagesDirectory: URL) async {
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = imagesDirectory.appendingPathComponent("Snapshots", conformingTo: .directory)
        configuration.isOverCaptureEnabled = true
        do {
            try await session.start(imagesDirectory: imagesDirectory, configuration: configuration)
        } catch {
            print("ObjectCaptureSession start failed:", error)
        }
    }
}
