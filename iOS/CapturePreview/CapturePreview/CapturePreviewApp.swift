// MARK: - File: CapturePreviewApp.swift
import SwiftUI

@main
struct CapturePreviewApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var peer = CapturePeer()

    var body: some Scene {
        WindowGroup {
            ContentView(peer: peer)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                break
            case .inactive, .background:
                peer.stopBrowsing()
            @unknown default:
                break
            }
        }
    }
}
