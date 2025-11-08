//
//  LobbyScene.swift
//  GoonHacksGame
//
//  Player selection lobby with shake-to-claim
//

import SpriteKit
import CoreMotion
import MultipeerConnectivity

class LobbyScene: SKScene {

    // MARK: - Properties

    var gameCoordinator: GameCoordinator!

    // Player slots (1-8)
    var playerSlots: [PlayerSlotNode] = []
    var claimedSlots: [Int: (deviceId: String, deviceName: String)] = [:]  // playerNumber: deviceInfo

    // UI elements
    var titleLabel: SKLabelNode!
    var instructionLabel: SKLabelNode!
    var startButton: SKShapeNode!
    var startButtonLabel: SKLabelNode!
    var connectionStatusLabel: SKLabelNode!

    // State
    var isWaitingForPlayers = true
    var readyToStart = false

    // AirPods status check timer
    var airPodsCheckTimer: Timer?
    
    // Motion controller for shake detection
    private var shakeDetector: MotionController?

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        setupScene()
        setupUI()
        setupPlayerSlots()
        setupMultipeer()

        // Start listening for shake events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShakeDetected),
            name: .deviceShakeDetected,
            object: nil
        )
    }

    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self)
        airPodsCheckTimer?.invalidate()
        airPodsCheckTimer = nil
        shakeDetector?.stop()
        shakeDetector = nil
    }

    // MARK: - Setup

    private func setupScene() {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)
        scaleMode = .aspectFit
    }

    private func setupUI() {
        // Title
        titleLabel = SKLabelNode(text: "🏁 SPERM RACING")
        titleLabel.fontSize = 72
        titleLabel.fontColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1.0)
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 100)
        titleLabel.zPosition = 100
        addChild(titleLabel)

        // Instructions
        instructionLabel = SKLabelNode(text: "SHAKE YOUR AIRPODS TO CLAIM A SLOT!")
        instructionLabel.fontSize = 32
        instructionLabel.fontColor = .white
        instructionLabel.position = CGPoint(x: size.width / 2, y: size.height - 180)
        instructionLabel.zPosition = 100
        addChild(instructionLabel)

        // Animate instructions
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.8),
            SKAction.scale(to: 1.0, duration: 0.8)
        ])
        instructionLabel.run(SKAction.repeatForever(pulse))

        // Connection status
        connectionStatusLabel = SKLabelNode(text: "Waiting for devices...")
        connectionStatusLabel.fontSize = 20
        connectionStatusLabel.fontColor = SKColor(white: 0.7, alpha: 1.0)
        connectionStatusLabel.position = CGPoint(x: size.width / 2, y: 80)
        connectionStatusLabel.zPosition = 100
        addChild(connectionStatusLabel)

        // Start button (initially hidden)
        createStartButton()
    }

    private func createStartButton() {
        startButton = SKShapeNode(rectOf: CGSize(width: 300, height: 80), cornerRadius: 20)
        startButton.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.8)
        startButton.strokeColor = SKColor(red: 0.3, green: 1.0, blue: 0.4, alpha: 1.0)
        startButton.lineWidth = 4
        startButton.glowWidth = 20
        startButton.position = CGPoint(x: size.width / 2, y: 150)
        startButton.zPosition = 100
        startButton.name = "startButton"
        startButton.alpha = 0  // Hidden initially
        addChild(startButton)

        startButtonLabel = SKLabelNode(text: "START RACE")
        startButtonLabel.fontSize = 36
        startButtonLabel.fontColor = .white
        startButtonLabel.verticalAlignmentMode = .center
        startButtonLabel.zPosition = 101
        startButton.addChild(startButtonLabel)
    }

    private func setupPlayerSlots() {
        let slotWidth: CGFloat = 200
        let slotHeight: CGFloat = 150
        let spacing: CGFloat = 20
        let totalWidth = (slotWidth + spacing) * 4 - spacing
        let startX = (size.width - totalWidth) / 2 + slotWidth / 2

        for i in 0..<8 {
            let row = i / 4
            let col = i % 4

            let x = startX + CGFloat(col) * (slotWidth + spacing)
            let y = size.height / 2 + 100 - CGFloat(row) * (slotHeight + spacing)

            let slot = PlayerSlotNode(
                playerNumber: i + 1,
                size: CGSize(width: slotWidth, height: slotHeight)
            )
            slot.position = CGPoint(x: x, y: y)
            slot.zPosition = 50
            addChild(slot)

            playerSlots.append(slot)
        }
    }

    private func setupMultipeer() {
        // Host mode - advertise the game
        MultipeerManager.shared.delegate = self
        MultipeerManager.shared.startHosting()

        // Start AirPods monitoring to prevent auto-disconnect
        AirPodsDetector.shared.startMonitoring()

        // Start shake detection for player registration
        setupShakeDetection()

        // Check AirPods status
        checkAirPodsStatus()

        updateConnectionStatus()
    }
    
    private func setupShakeDetection() {
        // Create a motion controller specifically for shake detection in lobby
        shakeDetector = MotionController()
        shakeDetector?.start(controlType: .airPods)
        
        print("🎧 Shake detection started for player registration")
    }

    private func checkAirPodsStatus() {
        let status = AirPodsDetector.shared.checkAirPodsAvailability()
        print(status.message)

        // Update UI with AirPods status
        if status.available {
            instructionLabel.text = "🎧 AIRPODS DETECTED! SHAKE TO CLAIM SLOT!"
            instructionLabel.fontColor = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)
        } else {
            instructionLabel.text = "⚠️ NO AIRPODS - USE KEYBOARD (RETURN TO CLAIM)"
            instructionLabel.fontColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        }

        // Schedule periodic check (every 2 seconds)
        if airPodsCheckTimer == nil {
            airPodsCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkAirPodsStatus()
            }
        }
    }

    // MARK: - Shake Detection

    @objc private func handleShakeDetected(_ notification: Notification) {
        print("📳 Shake detected in lobby!")

        // Find first unclaimed slot
        if let nextSlot = playerSlots.first(where: { !$0.isClaimed }) {
            claimSlot(playerNumber: nextSlot.playerNumber, deviceId: "local", deviceName: "Local Player")
        }
    }

    // MARK: - Slot Management

    func claimSlot(playerNumber: Int, deviceId: String, deviceName: String) {
        guard playerNumber >= 1 && playerNumber <= 8 else { return }
        guard claimedSlots[playerNumber] == nil else {
            print("⚠️ Slot \(playerNumber) already claimed")
            return
        }

        // Claim the slot
        claimedSlots[playerNumber] = (deviceId, deviceName)

        // Update slot UI
        if let slot = playerSlots.first(where: { $0.playerNumber == playerNumber }) {
            slot.claim(deviceName: deviceName)
        }

        print("✅ Player \(playerNumber) claimed by \(deviceName)")

        // Broadcast to all peers
        MultipeerManager.shared.broadcast(
            message: .playerClaimed(playerNumber: playerNumber, deviceId: deviceId, deviceName: deviceName)
        )

        checkReadyState()
    }

    private func checkReadyState() {
        // Need at least 2 players to start
        let humanPlayers = claimedSlots.count

        if humanPlayers >= 2 && !readyToStart {
            readyToStart = true
            showStartButton()
        } else if humanPlayers < 2 && readyToStart {
            readyToStart = false
            hideStartButton()
        }

        updateConnectionStatus()
    }

    private func showStartButton() {
        startButton.run(SKAction.fadeIn(withDuration: 0.3))

        // Pulse animation
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        startButton.run(SKAction.repeatForever(pulse), withKey: "pulse")
    }

    private func hideStartButton() {
        startButton.removeAction(forKey: "pulse")
        startButton.run(SKAction.fadeOut(withDuration: 0.3))
    }

    private func updateConnectionStatus() {
        let connected = MultipeerManager.shared.connectedPeers.count
        let claimed = claimedSlots.count

        connectionStatusLabel.text = "Connected: \(connected) devices | Claimed: \(claimed)/8 slots"

        if claimed >= 2 {
            connectionStatusLabel.fontColor = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)
        }
    }

    // MARK: - Input Handling

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)

        if let node = atPoint(location) as? SKShapeNode, node.name == "startButton" {
            if readyToStart {
                startRace()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49:  // Space
            if readyToStart {
                startRace()
            }

        case 36:  // Return
            // Debug: claim next slot
            if let nextSlot = playerSlots.first(where: { !$0.isClaimed }) {
                claimSlot(
                    playerNumber: nextSlot.playerNumber,
                    deviceId: "debug_\(nextSlot.playerNumber)",
                    deviceName: "Debug P\(nextSlot.playerNumber)"
                )
            }

        default:
            break
        }
    }

    // MARK: - Start Race

    private func startRace() {
        print("🏁 Starting race with \(claimedSlots.count) players!")

        // Create players list
        var players: [Player] = []

        for (playerNumber, info) in claimedSlots.sorted(by: { $0.key < $1.key }) {
            let player = Player(
                id: info.deviceId,
                playerNumber: playerNumber,
                name: info.deviceName,
                type: .human(deviceId: info.deviceId)
            )
            players.append(player)
        }

        // Fill remaining slots with CPU
        for i in 1...8 {
            if claimedSlots[i] == nil {
                if let tracklet = TrackletLoader.shared.randomTracklet() {
                    let cpuPlayer = Player(
                        id: "cpu_\(i)",
                        playerNumber: i,
                        name: "CPU \(i)",
                        type: .cpu(trackletId: tracklet.id)
                    )
                    players.append(cpuPlayer)
                }
            }
        }

        // Broadcast start message
        MultipeerManager.shared.broadcast(message: .startRace)

        // Transition to race
        gameCoordinator.startRace(with: players)
    }
}

// MARK: - MultipeerManagerDelegate

extension LobbyScene: MultipeerManagerDelegate {
    func didReceiveMessage(_ message: GameMessage, from peer: MCPeerID) {
        switch message {
        case .joinRequest(let deviceId, let deviceName):
            print("📩 Join request from \(deviceName)")
            // Auto-accept - find next slot
            if let nextSlot = playerSlots.first(where: { !$0.isClaimed }) {
                claimSlot(playerNumber: nextSlot.playerNumber, deviceId: deviceId, deviceName: deviceName)

                // Send confirmation
                MultipeerManager.shared.send(
                    message: .playerAssigned(playerNumber: nextSlot.playerNumber),
                    to: [peer]
                )
            }

        case .shakeDetected(let deviceId):
            print("📳 Shake from \(deviceId)")
            // Find next unclaimed slot
            if let nextSlot = playerSlots.first(where: { !$0.isClaimed }) {
                claimSlot(
                    playerNumber: nextSlot.playerNumber,
                    deviceId: deviceId,
                    deviceName: peer.displayName
                )
            }

        default:
            break
        }
    }

    func peerConnected(_ peer: MCPeerID) {
        updateConnectionStatus()
    }

    func peerDisconnected(_ peer: MCPeerID) {
        updateConnectionStatus()

        // Remove any claimed slots for this peer
        // (simplified - in production, track peer:slot mapping)
    }
}

// MARK: - Player Slot Node

class PlayerSlotNode: SKNode {
    let playerNumber: Int
    var isClaimed = false

    private var background: SKShapeNode!
    private var numberLabel: SKLabelNode!
    private var statusLabel: SKLabelNode!
    private var deviceLabel: SKLabelNode!

    init(playerNumber: Int, size: CGSize) {
        self.playerNumber = playerNumber
        super.init()

        setupVisuals(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupVisuals(size: CGSize) {
        // Background
        background = SKShapeNode(rectOf: size, cornerRadius: 15)
        background.fillColor = SKColor(white: 0.2, alpha: 0.8)
        background.strokeColor = SKColor(white: 0.4, alpha: 1.0)
        background.lineWidth = 2
        background.glowWidth = 5
        addChild(background)

        // Player number
        numberLabel = SKLabelNode(text: "P\(playerNumber)")
        numberLabel.fontSize = 48
        numberLabel.fontColor = playerColor(playerNumber: playerNumber)
        numberLabel.position = CGPoint(x: 0, y: 20)
        numberLabel.verticalAlignmentMode = .center
        addChild(numberLabel)

        // Status
        statusLabel = SKLabelNode(text: "EMPTY")
        statusLabel.fontSize = 20
        statusLabel.fontColor = SKColor(white: 0.6, alpha: 1.0)
        statusLabel.position = CGPoint(x: 0, y: -20)
        statusLabel.verticalAlignmentMode = .center
        addChild(statusLabel)

        // Device label (hidden initially)
        deviceLabel = SKLabelNode(text: "")
        deviceLabel.fontSize = 16
        deviceLabel.fontColor = .white
        deviceLabel.position = CGPoint(x: 0, y: -45)
        deviceLabel.verticalAlignmentMode = .center
        deviceLabel.alpha = 0
        addChild(deviceLabel)
    }

    func claim(deviceName: String) {
        isClaimed = true

        // Update visuals
        background.fillColor = playerColor(playerNumber: playerNumber).withAlphaComponent(0.3)
        background.strokeColor = playerColor(playerNumber: playerNumber)
        background.lineWidth = 4
        background.glowWidth = 15

        statusLabel.text = "READY"
        statusLabel.fontColor = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)

        deviceLabel.text = deviceName
        deviceLabel.run(SKAction.fadeIn(withDuration: 0.3))

        // Animation
        run(SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.2),
            SKAction.scale(to: 1.0, duration: 0.2)
        ]))
    }

    private func playerColor(playerNumber: Int) -> SKColor {
        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0),  // Red
            SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),  // Blue
            SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),  // Green
            SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0),  // Yellow
            SKColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 1.0),  // Pink
            SKColor(red: 0.6, green: 0.2, blue: 1.0, alpha: 1.0),  // Purple
            SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0),  // Orange
            SKColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1.0),  // Cyan
        ]
        return colors[(playerNumber - 1) % colors.count]
    }
}
