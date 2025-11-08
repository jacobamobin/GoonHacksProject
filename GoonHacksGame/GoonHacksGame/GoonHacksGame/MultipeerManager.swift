//
//  MultipeerManager.swift
//  GoonHacksGame
//
//  Local multiplayer networking for device discovery and communication
//

import Foundation
import MultipeerConnectivity

// MARK: - Game Messages

enum GameMessage: Codable {
    case joinRequest(deviceId: String, deviceName: String)
    case playerAssigned(playerNumber: Int)
    case shakeDetected(deviceId: String)
    case playerClaimed(playerNumber: Int, deviceId: String, deviceName: String)
    case motionUpdate(playerNumber: Int, steerX: Double, steerY: Double, boost: Bool)
    case startRace
    case checkpointPassed(checkpointId: Int, eliminated: [Int])
    case raceFinished(winnerNumber: Int)
    case requestRestart
}

// MARK: - Multipeer Manager

protocol MultipeerManagerDelegate: AnyObject {
    func didReceiveMessage(_ message: GameMessage, from peer: MCPeerID)
    func peerConnected(_ peer: MCPeerID)
    func peerDisconnected(_ peer: MCPeerID)
}

class MultipeerManager: NSObject {
    static let shared = MultipeerManager()

    weak var delegate: MultipeerManagerDelegate?

    // MultipeerConnectivity components
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // Configuration
    private let serviceType = "spermracing"  // Must be 15 chars or less
    private let maxPeers = 8

    // State
    var isHost = false
    var connectedPeers: [MCPeerID] = []

    private override init() {
        super.init()
        setupPeer()
    }

    private func setupPeer() {
        // Create peer ID with device name
        let deviceName = ProcessInfo.processInfo.hostName
        peerID = MCPeerID(displayName: deviceName)

        // Create session
        session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .none
        )
        session.delegate = self

        print("✅ MultipeerManager initialized: \(deviceName)")
    }

    // MARK: - Host (Mac/iPad)

    func startHosting() {
        isHost = true

        // Start advertising
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["host": "true"],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        print("🎮 Started hosting game session")
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        print("🛑 Stopped hosting")
    }

    // MARK: - Client (AirPods/iPhone Controller)

    func startBrowsing() {
        isHost = false

        // Start browsing for hosts
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        print("🔍 Browsing for game sessions...")
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        print("🛑 Stopped browsing")
    }

    // MARK: - Messaging

    func send(message: GameMessage, to peers: [MCPeerID]? = nil) {
        let targetPeers = peers ?? session.connectedPeers

        guard !targetPeers.isEmpty else {
            print("⚠️ No peers to send message to")
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)

            try session.send(
                data,
                toPeers: targetPeers,
                with: .reliable
            )

            // Debug logging
            switch message {
            case .motionUpdate:
                break  // Don't spam logs
            default:
                print("📤 Sent: \(message)")
            }

        } catch {
            print("❌ Failed to send message: \(error)")
        }
    }

    func broadcast(message: GameMessage) {
        send(message: message, to: session.connectedPeers)
    }

    // MARK: - Disconnect

    func disconnect() {
        session.disconnect()
        stopHosting()
        stopBrowsing()
        connectedPeers.removeAll()
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch state {
            case .connected:
                print("✅ Connected: \(peerID.displayName)")
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.delegate?.peerConnected(peerID)

            case .connecting:
                print("🔄 Connecting: \(peerID.displayName)")

            case .notConnected:
                print("❌ Disconnected: \(peerID.displayName)")
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
                self.delegate?.peerDisconnected(peerID)

            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(GameMessage.self, from: data)

            DispatchQueue.main.async { [weak self] in
                // Debug logging
                switch message {
                case .motionUpdate:
                    break  // Don't spam logs
                default:
                    print("📥 Received from \(peerID.displayName): \(message)")
                }

                self?.delegate?.didReceiveMessage(message, from: peerID)
            }

        } catch {
            print("❌ Failed to decode message: \(error)")
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations if we have room
        if session.connectedPeers.count < maxPeers - 1 {
            print("📩 Auto-accepting invitation from \(peerID.displayName)")
            invitationHandler(true, session)
        } else {
            print("⚠️ Rejected invitation from \(peerID.displayName) - session full")
            invitationHandler(false, nil)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🔍 Found peer: \(peerID.displayName)")

        // Auto-invite found hosts
        if info?["host"] == "true" {
            print("📤 Inviting host: \(peerID.displayName)")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("❌ Lost peer: \(peerID.displayName)")
    }
}
