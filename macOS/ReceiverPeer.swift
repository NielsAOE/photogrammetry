import Foundation
import MultipeerConnectivity

@MainActor
final class ReceiverPeer: NSObject, ObservableObject {
    private let service = "oc-transfer"
    private let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!

    @Published var connectionStatus = "Not connected"
    @Published var receivedFolder: URL?
    private var rootTempDirectory: URL?

    override init() {
        super.init()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: service)
        advertiser.delegate = self
    }

    func startAdvertising() { advertiser.startAdvertisingPeer(); connectionStatus = "Advertising…" }
    func stopAdvertising() { advertiser.stopAdvertisingPeer(); connectionStatus = "Not advertising" }

    func cleanupRootDirectory() {
        guard let root = rootTempDirectory else { return }
        rootTempDirectory = nil
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: root)
        }
    }

    deinit { cleanupRootDirectory() }
}

extension ReceiverPeer: MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    // Invitations
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    // Session state
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: connectionStatus = "Connected to \(peerID.displayName)"
        case .connecting: connectionStatus = "Connecting…"
        case .notConnected: connectionStatus = "Not connected"
        @unknown default: break
        }
    }

    // Receive the ZIP as a resource and expand it with /usr/bin/ditto (with error capture).
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard error == nil, let localURL else { self.connectionStatus = "Receive failed"; return }
        Task.detached(priority: .background) { [weak self] in
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("OC_\(UUID().uuidString)", isDirectory: true)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            let zipURL = root.appendingPathComponent(resourceName)
            try? fm.removeItem(at: zipURL)
            do { try fm.copyItem(at: localURL, to: zipURL) } catch {
                await MainActor.run { self?.connectionStatus = "Copy failed" }
                return
            }

            let expanded = root.appendingPathComponent("expanded", isDirectory: true)
            try? fm.createDirectory(at: expanded, withIntermediateDirectories: true)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zipURL.path, expanded.path]

            let pipe = Pipe(); p.standardError = pipe
            do { try p.run(); p.waitUntilExit() } catch {
                await MainActor.run { self?.connectionStatus = "Unzip failed" }
                return
            }

            if p.terminationStatus != 0 {
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: errData, encoding: .utf8) ?? ""
                await MainActor.run { self?.connectionStatus = "Unzip error (\(p.terminationStatus)): \(msg)" }
                return
            }

            // Remove the archive to reclaim space
            try? fm.removeItem(at: zipURL)

            await MainActor.run {
                self?.receivedFolder = expanded
                self?.rootTempDirectory = root
                self?.connectionStatus = "Received \(resourceName)"
            }
        }
    }

    // Unused
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
}