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
    var airPodClaimCount = 0  // Track how many times AirPods have claimed (for "AirPods L", "AirPods R", etc.)

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
    var lastAirPodsStatus: Bool?  // Track last status to only log changes

    // Bluetooth controller manager for multiple devices
    private var bluetoothManager: BluetoothControllerManager!

    // Legacy single motion controller for shake detection
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
        bluetoothManager?.disconnectAll()
        bluetoothManager = nil
    }

    // MARK: - Setup

    private func setupScene() {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)
        scaleMode = .aspectFit
    }

    private func setupUI() {
        // Title
        titleLabel = SKLabelNode(text: "PLAYER SELECT")
        titleLabel.fontSize = 72
        titleLabel.fontName = "SF Pro"
        titleLabel.fontColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1.0)
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 100)
        titleLabel.zPosition = 100
        addChild(titleLabel)

        // Instructions
        instructionLabel = SKLabelNode(text: "CLICK A SLOT TO JOIN")
        instructionLabel.fontSize = 32
        instructionLabel.fontName = "SF Pro"
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
        // Initialize Bluetooth controller manager for multiple devices
        bluetoothManager = BluetoothControllerManager.shared
        bluetoothManager.delegate = self

        // Start discovering Bluetooth devices (AirPods, etc.)
        bluetoothManager.startDiscovery()

        // Legacy shake detector for notification-based shake events
        shakeDetector = MotionController()
        shakeDetector?.start(controlType: .airPods)

        print("🎧 Bluetooth device discovery started - Each shake claims a new slot")
        print("📱 Supported: Multiple AirPods pairs, iOS devices via network")
    }

    private func checkAirPodsStatus() {
        let status = AirPodsDetector.shared.checkAirPodsAvailability()

        // Only log if status changed
        if lastAirPodsStatus != status.available {
            print(status.message)
            lastAirPodsStatus = status.available
        }

        // Update UI with AirPods status
        if status.available {
            let claimedCount = airPodClaimCount
            if claimedCount == 0 {
                instructionLabel.text = "🎧 SHAKE AIRPODS TO JOIN AS LEFT PLAYER (L)"
            } else if claimedCount == 1 {
                instructionLabel.text = "✅ LEFT JOINED | 🎧 SHAKE AGAIN TO JOIN AS RIGHT PLAYER (R)"
            } else {
                instructionLabel.text = "✅ BOTH AIRPODS JOINED | PRESS SPACE TO START"
            }
            instructionLabel.fontColor = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)
        } else {
            instructionLabel.text = "⚠️ NO AIRPODS DETECTED - CONNECT AIRPODS PRO/MAX"
            instructionLabel.fontColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        }

        // Schedule periodic check (every 3 seconds)
        if airPodsCheckTimer == nil {
            airPodsCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.checkAirPodsStatus()
            }
        }
    }

    // MARK: - Shake Detection

    @objc private func handleShakeDetected(_ notification: Notification) {
        print("📳 Shake detected in lobby!")

        // Find first unclaimed slot
        if let nextSlot = playerSlots.first(where: { !$0.isClaimed }) {
            let deviceId = "airpod_\(nextSlot.playerNumber)"
            let deviceName = "AirPod \(nextSlot.playerNumber)"
            claimSlot(playerNumber: nextSlot.playerNumber, deviceId: deviceId, deviceName: deviceName)
        } else {
            print("⚠️ All slots already claimed")
        }
    }

    // MARK: - Slot Management

    func claimSlot(playerNumber: Int, deviceId: String, deviceName: String) {
        guard playerNumber >= 1 && playerNumber <= 8 else { return }

        // Check if slot is already claimed
        guard claimedSlots[playerNumber] == nil else {
            print("⚠️ Slot \(playerNumber) already claimed")
            return
        }

        // Claim the slot (no duplicate device check - allow same AirPods to claim multiple slots)
        claimedSlots[playerNumber] = (deviceId, deviceName)

        // Update slot UI
        if let slot = playerSlots.first(where: { $0.playerNumber == playerNumber }) {
            slot.claim(deviceName: deviceName)
        }

        print("✅ Player \(playerNumber) claimed by '\(deviceName)' (device: \(deviceId))")

        // Broadcast to all peers
        MultipeerManager.shared.broadcast(
            message: .playerClaimed(playerNumber: playerNumber, deviceId: deviceId, deviceName: deviceName)
        )

        checkReadyState()
    }

    func unclaimSlot(playerNumber: Int) {
        guard playerNumber >= 1 && playerNumber <= 8 else { return }

        // Check if slot is already claimed
        guard claimedSlots[playerNumber] != nil else {
            print("⚠️ Slot \(playerNumber) already unclaimed")
            return
        }

        // Unclaim the slot
        claimedSlots[playerNumber] = nil

        // Update slot UI
        if let slot = playerSlots.first(where: { $0.playerNumber == playerNumber }) {
            slot.unclaim()
        }

        print("✅ Player \(playerNumber) unclaimed")

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
        let networkPeers = MultipeerManager.shared.connectedPeers.count
        let bluetoothDevices = bluetoothManager?.connectedCount ?? 0
        let totalConnected = networkPeers + bluetoothDevices
        let claimed = claimedSlots.count

        connectionStatusLabel.text = "Connected: \(totalConnected) devices (\(bluetoothDevices) BT, \(networkPeers) net) | Claimed: \(claimed)/8 slots"

        if claimed >= 2 {
            connectionStatusLabel.fontColor = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)
        }
    }

    // MARK: - Input Handling

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let clickedNode = atPoint(location)
        
        // Check if start button or any of its children was clicked
        // Walk up the parent hierarchy to find if we clicked the start button
        var currentNode: SKNode? = clickedNode
        var isStartButton = false
        
        while let node = currentNode {
            if node.name == "startButton" {
                isStartButton = true
                break
            }
            currentNode = node.parent
        }
        
        if isStartButton {
            if readyToStart {
                print("🎮 Start button clicked!")
                startRace()
            } else {
                print("⚠️ Start button clicked but not ready (need at least 2 players)")
            }
            return  // Don't process as slot click
        }
        
        // Check if a player slot was clicked
        for slot in playerSlots {
            if slot.contains(location) {
                if slot.isClaimed {
                    // Unclaim the slot
                    unclaimSlot(playerNumber: slot.playerNumber)
                } else {
                    // Claim the slot
                    let deviceId = "player_\(slot.playerNumber)"
                    let deviceName = "Player \(slot.playerNumber)"
                    claimSlot(playerNumber: slot.playerNumber, deviceId: deviceId, deviceName: deviceName)
                }
                break
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49:  // Space - Start race
            if readyToStart {
                startRace()
            } else {
                print("⚠️ Need at least 2 players to start (use AirPods shake to claim slots)")
            }

        // REMOVED: Return key claiming - only AirPods shake can claim slots
        // This prevents keyboard from interfering with player slots

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
                let cpuPlayer = Player(
                    id: "cpu_\(i)",
                    playerNumber: i,
                    name: "CPU \(i)",
                    type: .cpu
                )
                players.append(cpuPlayer)
            }
        }

        // Broadcast start message
        MultipeerManager.shared.broadcast(message: .startRace)

        // Transition to photo capture (then race)
        gameCoordinator.startPhotoCapture(with: players)
    }
}

// MARK: - BluetoothControllerDelegate

extension LobbyScene: BluetoothControllerDelegate {
    func didReceiveMotion(from deviceId: String, strokingSpeed: Double, steering: Double, spm: Double) {
        // Motion updates are handled during the race, not in lobby
        // In lobby, we only care about shake detection for claiming slots
        // SPM is tracked but not displayed in lobby
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

    func unclaim() {
        isClaimed = false

        // Reset visuals
        background.fillColor = SKColor(white: 0.2, alpha: 0.8)
        background.strokeColor = SKColor(white: 0.4, alpha: 1.0)
        background.lineWidth = 2
        background.glowWidth = 5

        statusLabel.text = "EMPTY"
        statusLabel.fontColor = SKColor(white: 0.6, alpha: 1.0)

        deviceLabel.run(SKAction.fadeOut(withDuration: 0.3))
    }

    private func playerColor(playerNumber: Int) -> SKColor {
        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0),  // 1: Red
            SKColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0),  // 2: Yellow
            SKColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0),  // 3: Blue
            SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0),  // 4: Green
            SKColor(red: 0.2, green: 0.9, blue: 0.9, alpha: 1.0),  // 5: Cyan
            SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0),  // 6: Orange
            SKColor(red: 0.6, green: 0.2, blue: 1.0, alpha: 1.0),  // 7: Purple
            SKColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0),  // 8: Brown
        ]
        return colors[(playerNumber - 1) % colors.count]
    }
}
