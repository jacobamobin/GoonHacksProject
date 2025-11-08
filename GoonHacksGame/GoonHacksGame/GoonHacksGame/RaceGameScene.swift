//
//  RaceGameScene.swift
//  GoonHacksGame
//
//  Main racing game scene with vertical track, VISEM physics, and glow theme
//

import SpriteKit
import GameplayKit
import AVFoundation
import MultipeerConnectivity

class RaceGameScene: SKScene {

    // MARK: - Properties

    var gameCoordinator: GameCoordinator?
    var gameState: GameState!
    var fluidField: FluidField!
    var physicsWeights = PhysicsWeights()

    // Scene nodes
    var trackNode: SKNode!
    var racersNode: SKNode!
    var checkpointsNode: SKNode!
    var uiNode: SKNode!
    var videoNode: SKVideoNode?

    // Camera
    var gameCamera: SKCameraNode!

    // Track configuration
    let trackWidth: CGFloat = 800
    let trackHeight: CGFloat = 5000  // Vertical track
    let numCheckpoints = 7  // 7 eliminations for 8 racers

    // Visual effects
    var particleSystems: [UUID: SKEmitterNode] = [:]

    // Timing
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Initialization

    func initializeGame(with players: [Player]) {
        gameState = GameState()

        // Load tracklets
        if TrackletLoader.shared.data == nil {
            TrackletLoader.shared.loadTracklets()
        }

        // Add players
        for player in players {
            gameState.addPlayer(player)
        }

        print("✅ Race initialized with \(players.count) players")
    }

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        setupScene()
        setupCamera()
        setupTrack()
        setupCheckpoints()
        setupRacers()
        setupUI()
        setupFluidField()

        // Start race after short delay
        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in
                self?.startRace()
            }
        ]))
    }

    // MARK: - Setup

    private func setupScene() {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)  // Dark blue
        scaleMode = .aspectFit

        // Create layer nodes
        trackNode = SKNode()
        trackNode.name = "track"
        addChild(trackNode)

        racersNode = SKNode()
        racersNode.name = "racers"
        addChild(racersNode)

        checkpointsNode = SKNode()
        checkpointsNode.name = "checkpoints"
        addChild(checkpointsNode)

        uiNode = SKNode()
        uiNode.name = "ui"
        addChild(uiNode)
    }

    private func setupCamera() {
        gameCamera = SKCameraNode()
        camera = gameCamera
        addChild(gameCamera)

        // Position camera to start at bottom
        gameCamera.position = CGPoint(x: 0, y: size.height / 2)
    }

    private func setupTrack() {
        // Vertical track with glow walls
        createTrackWalls()
        createTrackBackground()
    }

    private func createTrackWalls() {
        let wallWidth: CGFloat = 20
        let glowColor = SKColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.8)

        // Left wall
        let leftWall = SKShapeNode(rectOf: CGSize(width: wallWidth, height: trackHeight))
        leftWall.position = CGPoint(x: -trackWidth / 2, y: trackHeight / 2)
        leftWall.fillColor = glowColor
        leftWall.strokeColor = .clear
        leftWall.glowWidth = 30  // Glow effect
        leftWall.zPosition = 5
        trackNode.addChild(leftWall)

        // Right wall
        let rightWall = SKShapeNode(rectOf: CGSize(width: wallWidth, height: trackHeight))
        rightWall.position = CGPoint(x: trackWidth / 2, y: trackHeight / 2)
        rightWall.fillColor = glowColor
        rightWall.strokeColor = .clear
        rightWall.glowWidth = 30
        rightWall.zPosition = 5
        trackNode.addChild(rightWall)
    }

    private func createTrackBackground() {
        // Grid lines for visual feedback
        let gridSpacing: CGFloat = 200
        let lineColor = SKColor(red: 0.1, green: 0.4, blue: 0.6, alpha: 0.3)

        for i in stride(from: CGFloat(0), through: trackHeight, by: gridSpacing) {
            let line = SKShapeNode(rectOf: CGSize(width: trackWidth, height: 2))
            line.position = CGPoint(x: 0, y: i)
            line.fillColor = lineColor
            line.strokeColor = .clear
            line.zPosition = 1
            trackNode.addChild(line)
        }
    }

    private func setupCheckpoints() {
        // Create evenly-spaced checkpoints
        let spacing = trackHeight / CGFloat(numCheckpoints + 1)

        for i in 0..<numCheckpoints {
            let yPos = spacing * CGFloat(i + 1)
            let checkpoint = Checkpoint(
                id: i,
                yPosition: yPos,
                width: trackWidth
            )
            gameState.checkpoints.append(checkpoint)

            // Visual representation
            createCheckpointNode(checkpoint: checkpoint)
        }
    }

    private func createCheckpointNode(checkpoint: Checkpoint) {
        let checkpointLine = SKShapeNode(rectOf: CGSize(width: checkpoint.width, height: 5))
        checkpointLine.position = CGPoint(x: 0, y: checkpoint.yPosition)
        checkpointLine.fillColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.6)
        checkpointLine.strokeColor = .clear
        checkpointLine.glowWidth = 15
        checkpointLine.zPosition = 10
        checkpointLine.name = "checkpoint_\(checkpoint.id)"
        checkpointsNode.addChild(checkpointLine)

        // Label
        let label = SKLabelNode(text: "CHECKPOINT \(checkpoint.id + 1)")
        label.fontSize = 24
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: checkpoint.yPosition + 30)
        label.zPosition = 11
        checkpointsNode.addChild(label)
    }

    private func setupRacers() {
        // Initialize racers at starting positions
        let startY: CGFloat = 100
        let spacing: CGFloat = trackWidth / CGFloat(gameState.players.count + 1)

        gameState.initializeRacers(startY: startY, spacing: spacing)

        // Create sprite nodes
        for racer in gameState.racers {
            createRacerNode(racer: racer)
        }
    }

    private func createRacerNode(racer: Racer) {
        let racerNode = SKNode()
        racerNode.name = "racer_\(racer.player.id)"
        racerNode.position = racer.position
        racerNode.zPosition = 20

        // Sperm body (will be replaced with proper sprite + face photo)
        let body = createSpermShape()
        racerNode.addChild(body)

        // Player number label
        let numberLabel = SKLabelNode(text: "\(racer.player.playerNumber)")
        numberLabel.fontSize = 20
        numberLabel.fontColor = .white
        numberLabel.position = CGPoint(x: 0, y: -40)
        numberLabel.name = "number"
        racerNode.addChild(numberLabel)

        // Particle trail
        let trail = createParticleTrail(color: playerColor(playerNumber: racer.player.playerNumber))
        racerNode.addChild(trail)

        racersNode.addChild(racerNode)
    }

    private func createSpermShape() -> SKShapeNode {
        // Simple sperm shape (head + tail)
        let head = SKShapeNode(circleOfRadius: 20)
        head.fillColor = .white
        head.strokeColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1.0)
        head.lineWidth = 3
        head.glowWidth = 10
        head.name = "head"

        // Tail (bezier curve)
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: 0, y: -20))
        tailPath.addCurve(
            to: CGPoint(x: 0, y: -60),
            control1: CGPoint(x: -10, y: -35),
            control2: CGPoint(x: 10, y: -45)
        )

        let tail = SKShapeNode(path: tailPath)
        tail.strokeColor = SKColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.8)
        tail.lineWidth = 5
        tail.glowWidth = 5
        tail.name = "tail"

        let container = SKNode()
        container.addChild(head)
        container.addChild(tail)

        return head  // Return head as main shape (simplification for now)
    }

    private func createParticleTrail(color: SKColor) -> SKEmitterNode {
        let trail = SKEmitterNode()
        trail.particleTexture = SKTexture(imageNamed: "spark")  // Will create this
        trail.particleBirthRate = 50
        trail.particleLifetime = 0.5
        trail.particleScale = 0.3
        trail.particleScaleSpeed = -0.2
        trail.particleAlpha = 0.6
        trail.particleAlphaSpeed = -1.0
        trail.particleColor = color
        trail.particleBlendMode = .add
        trail.position = CGPoint(x: 0, y: -25)
        trail.emissionAngle = CGFloat.pi * 1.5  // Downward
        trail.emissionAngleRange = CGFloat.pi * 0.2
        trail.particleSpeed = 50
        trail.particleSpeedRange = 20
        trail.zPosition = -1
        trail.name = "trail"

        return trail
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

    private func setupUI() {
        // Position counter (top left)
        createPositionDisplay()

        // TODO: Add VISEM video player (top right)
        // setupVideoPreview()
    }

    private func createPositionDisplay() {
        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 300), cornerRadius: 10)
        bg.fillColor = SKColor(white: 0.1, alpha: 0.7)
        bg.strokeColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.8)
        bg.lineWidth = 2
        bg.position = CGPoint(x: -size.width / 2 + 120, y: size.height / 2 - 170)
        bg.name = "positionDisplay"

        gameCamera.addChild(bg)  // Attach to camera so it moves with viewport

        // Will populate with player positions during update
    }

    private func setupFluidField() {
        fluidField = FluidField()

        // Tune fluid parameters based on VISEM statistics
        if let globalStats = TrackletLoader.shared.data?.globalStatistics {
            fluidField.flowIntensity = CGFloat(globalStats.meanSpeed) * 100.0
            fluidField.viscosity = 0.2  // Moderate resistance
        }
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        // Initialize time
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            gameState.raceStartTime = currentTime
        }

        let deltaTime = currentTime - lastUpdateTime
        gameState.currentTime = currentTime

        // Update based on game phase
        switch gameState.phase {
        case .lobby, .registration, .photoCapture:
            // No physics updates
            break

        case .raceCountdown:
            // Could add countdown animation
            break

        case .racing:
            updateRacing(deltaTime: deltaTime)

        case .checkpointElimination:
            // Show elimination animation
            break

        case .finished:
            // Show final results
            break
        }

        lastUpdateTime = currentTime
    }

    private func updateRacing(deltaTime: TimeInterval) {
        // Update fluid field
        fluidField.update(deltaTime: deltaTime)

        // Update each racer
        for racer in gameState.activeRacers() {
            // Update racer physics
            racer.update(deltaTime: deltaTime, fluidField: fluidField, weights: physicsWeights)

            // Update sprite node
            if let racerNode = racersNode.childNode(withName: "racer_\(racer.player.id)") {
                racerNode.position = racer.position
                racerNode.zRotation = racer.rotation
            }
        }

        // Check checkpoints
        if let eliminated = gameState.checkCheckpoints() {
            handleEliminations(eliminated)
        }

        // Update camera to follow race
        updateCamera()

        // Update UI
        updatePositionDisplay()
    }

    private func updateCamera() {
        // Follow the leading racer
        let activeRacers = gameState.activeRacers()
        guard !activeRacers.isEmpty else { return }

        let leadY = activeRacers.map { $0.position.y }.max() ?? 0

        // Smooth camera follow
        let targetY = max(size.height / 2, leadY + 200)
        gameCamera.position.y = gameCamera.position.y * 0.95 + targetY * 0.05
    }

    private func updatePositionDisplay() {
        guard let displayNode = gameCamera.childNode(withName: "positionDisplay") else { return }

        // Remove old labels
        displayNode.removeAllChildren()

        // Sort racers by position
        let sorted = gameState.activeRacers().sorted { $0.position.y > $1.position.y }

        for (index, racer) in sorted.enumerated() {
            let label = SKLabelNode(text: "\(index + 1). P\(racer.player.playerNumber)")
            label.fontSize = 18
            label.fontColor = playerColor(playerNumber: racer.player.playerNumber)
            label.horizontalAlignmentMode = .left
            label.position = CGPoint(x: -80, y: 120 - CGFloat(index) * 30)
            displayNode.addChild(label)
        }
    }

    private func handleEliminations(_ eliminated: [Player]) {
        print("🚫 Eliminated: \(eliminated.map { $0.name }.joined(separator: ", "))")

        // Fade out eliminated racer
        for player in eliminated {
            if let racerNode = racersNode.childNode(withName: "racer_\(player.id)") {
                racerNode.run(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.3, duration: 0.5),
                    SKAction.scale(to: 0.5, duration: 0.5)
                ]))
            }
        }

        // Check if race is over (1 racer left)
        if gameState.activeRacers().count == 1 {
            gameState.phase = .finished
            handleRaceFinished()
        }
    }

    private func handleRaceFinished() {
        guard let winner = gameState.activeRacers().first else { return }

        print("🏆 Winner: \(winner.player.name)")

        // Broadcast winner
        MultipeerManager.shared.broadcast(message: .raceFinished(winnerNumber: winner.player.playerNumber))

        // Show winner announcement
        let winnerLabel = SKLabelNode(text: "🏆 WINNER: P\(winner.player.playerNumber)")
        winnerLabel.fontSize = 48
        winnerLabel.fontColor = playerColor(playerNumber: winner.player.playerNumber)
        winnerLabel.position = CGPoint(x: 0, y: 0)
        winnerLabel.zPosition = 100
        gameCamera.addChild(winnerLabel)

        winnerLabel.run(SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 0.5),
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.run { [weak self] in
                // Return to lobby after showing winner
                self?.gameCoordinator?.returnToLobby()
            }
        ]))
    }

    // MARK: - Race Control

    private func startRace() {
        guard gameState != nil else { return }
        gameState.phase = .racing
        gameState.raceStartTime = Date().timeIntervalSince1970
        print("🏁 Race started!")

        // Show countdown
        showCountdown()
    }

    private func showCountdown() {
        let countdownLabel = SKLabelNode(text: "3")
        countdownLabel.fontSize = 120
        countdownLabel.fontColor = .white
        countdownLabel.position = CGPoint(x: 0, y: 0)
        countdownLabel.zPosition = 200
        gameCamera.addChild(countdownLabel)

        let countdown = SKAction.sequence([
            SKAction.run { countdownLabel.text = "3" },
            SKAction.wait(forDuration: 1.0),
            SKAction.run { countdownLabel.text = "2" },
            SKAction.wait(forDuration: 1.0),
            SKAction.run { countdownLabel.text = "1" },
            SKAction.wait(forDuration: 1.0),
            SKAction.run { countdownLabel.text = "GO!" },
            SKAction.scale(to: 2.0, duration: 0.3),
            SKAction.wait(forDuration: 0.5),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ])

        countdownLabel.run(countdown)
    }

    // MARK: - Multiplayer Integration

    func handleRemoteMotionUpdate(playerNumber: Int, steerX: Double, steerY: Double, boost: Bool) {
        // Find player and update their input
        guard let player = gameState?.players.first(where: { $0.playerNumber == playerNumber }) else {
            return
        }

        player.updateSteering(x: steerX, y: steerY)
        if boost {
            _ = player.triggerBoost(currentTime: gameState.currentTime)
        }
    }

    // MARK: - Debug / Test Input

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 0:  // A - Steer left for player 1
            gameState?.players.first?.updateSteering(x: -1.0, y: 0.5)

        case 2:  // D - Steer right for player 1
            gameState?.players.first?.updateSteering(x: 1.0, y: 0.5)

        case 13:  // W - Boost for player 1
            if let player = gameState?.players.first {
                _ = player.triggerBoost(currentTime: gameState.currentTime)
            }

        case 15:  // R - Restart (return to lobby)
            gameCoordinator?.returnToLobby()

        default:
            break
        }
    }
}

// MARK: - MultipeerManagerDelegate

extension RaceGameScene: MultipeerManagerDelegate {
    func didReceiveMessage(_ message: GameMessage, from peer: MCPeerID) {
        switch message {
        case .motionUpdate(let playerNumber, let steerX, let steerY, let boost):
            handleRemoteMotionUpdate(
                playerNumber: playerNumber,
                steerX: steerX,
                steerY: steerY,
                boost: boost
            )

        default:
            break
        }
    }

    func peerConnected(_ peer: MCPeerID) {
        print("✅ Peer connected during race: \(peer.displayName)")
    }

    func peerDisconnected(_ peer: MCPeerID) {
        print("❌ Peer disconnected during race: \(peer.displayName)")
        // TODO: Handle player disconnection
    }
}
