import Foundation
import MultipeerConnectivity

@MainActor
final class CapturePeer: NSObject, ObservableObject {
    private let service = "oc-transfer"
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var browser: MCNearbyServiceBrowser!

    @Published var isConnected = false
    @Published var connectionStatus = "Not connected"
    @Published var currentSendProgress: Progress?

    override init() {
        super.init()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: service)
        browser.delegate = self
    }

    func startBrowsing() { browser.startBrowsingForPeers(); connectionStatus = "Browsing…" }
    func stopBrowsing() { browser.stopBrowsingForPeers() }

    func sendFile(_ url: URL) async throws {
        guard let dest = session.connectedPeers.first else { throw NSError(domain: "NoPeers", code: 1) }
        let name = url.lastPathComponent
        let progress = session.sendResource(at: url, withName: name, toPeer: dest) { [weak self] error in
            Task { @MainActor in
                if let error { self?.connectionStatus = "Send error: \(error.localizedDescription)" }
                self?.currentSendProgress = nil
            }
        }
        currentSendProgress = progress
        // Await completion via KVO on finished
        try await withCheckedThrowingContinuation { cont in
            let obs = progress.observe(\ .isFinished) { _, _ in cont.resume() }
            // Store observation until finish
            _ = obs
        }
        connectionStatus = "Sent \(name)"
    }
}

extension CapturePeer: MCSessionDelegate, MCNearbyServiceBrowserDelegate {
    // Browser
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    // Session state
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: isConnected = true; connectionStatus = "Connected to \(peerID.displayName)"
        case .connecting: isConnected = false; connectionStatus = "Connecting…"
        case .notConnected: isConnected = false; connectionStatus = "Not connected"
        @unknown default: break
        }
    }

    // Unused
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}