import Foundation
import MultipeerConnectivity
import Observation
import UIKit

@MainActor
@Observable
final class CapturePeer: NSObject {
    // Multipeer constraints: 1–15 chars, lowercase letters/numbers/hyphen
    // https://developer.apple.com/documentation/multipeerconnectivity/mcnearbyservicebrowser/init(peer:servicetype:)
    private let service = "oc-transfer"

    // Internal MPC objects aren’t part of app state — ignore for observation.
    @ObservationIgnored private let peerID = MCPeerID(displayName: UIDevice.current.name)
    @ObservationIgnored private var session: MCSession!
    @ObservationIgnored private var browser: MCNearbyServiceBrowser!

    // UI state
    var isConnected = false
    var connectionStatus = "Not connected"
    var currentSendProgress: Progress?

    override init() {
        super.init()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: service)
        browser.delegate = self
    }

    func startBrowsing() {
        browser.startBrowsingForPeers()
        connectionStatus = "Browsing…"
    }

    func stopBrowsing() { browser.stopBrowsingForPeers() }

    func sendFile(_ url: URL) async throws {
        guard let dest = session.connectedPeers.first else {
            throw NSError(domain: "NoPeers", code: 1)
        }
        let name = url.lastPathComponent
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let progress = session.sendResource(at: url, withName: name, toPeer: dest) { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.connectionStatus = "Send error: \(error.localizedDescription)"
                    } else {
                        self?.connectionStatus = "Sent \(name)"
                    }
                    self?.currentSendProgress = nil
                }
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
            currentSendProgress = progress
        }
    }
}

extension CapturePeer: MCSessionDelegate, MCNearbyServiceBrowserDelegate {
    // Browser
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    // Session state
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected: self.isConnected = true; self.connectionStatus = "Connected to \(peerID.displayName)"
            case .connecting: self.isConnected = false; self.connectionStatus = "Connecting…"
            case .notConnected: self.isConnected = false; self.connectionStatus = "Not connected"
            @unknown default: break
            }
        }
    }

    // Unused
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
