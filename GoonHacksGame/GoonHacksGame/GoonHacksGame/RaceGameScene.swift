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
    var physicsWeights = PhysicsWeights()  // No more fluidField!

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
        setupDynamicTrack()  // NEW: curved track
        setupCheckpoints()
        setupRacers()
        setupUI()

        // Start race immediately - NO COUNTDOWN
        startRace()
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

        // ZOOM OUT MORE - higher number = more zoomed out
        gameCamera.setScale(2.5)

        // Position camera at start
        gameCamera.position = CGPoint(x: 0, y: size.height / 2)
    }

    private func setupDynamicTrack() {
        // Generate curved track path
        let trackPath = TrackGenerator.generateCurvedTrack(
            width: 350,  // Curve width
            height: trackHeight,
            segments: 60,  // Smoothness
            curveIntensity: 0.35  // How curvy
        )

        gameState.trackPath = trackPath

        // Render the track visually
        renderCurvedTrack(trackPath)

        // Generate obstacles
        gameState.obstacles = TrackGenerator.generateObstacles(
            alongPath: trackPath,
            count: 12
        )

        // Render obstacles
        for obstacle in gameState.obstacles {
            let obstacleNode = SKShapeNode(rect: obstacle, cornerRadius: 10)
            obstacleNode.fillColor = SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.6)
            obstacleNode.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
            obstacleNode.lineWidth = 3
            obstacleNode.glowWidth = 10
            obstacleNode.zPosition = 8
            trackNode.addChild(obstacleNode)
        }
    }

    private func renderCurvedTrack(_ path: [CGPoint]) {
        // Draw center line
        let centerLine = SKShapeNode()
        let bezierPath = CGMutablePath()

        if let first = path.first {
            bezierPath.move(to: first)
            for point in path.dropFirst() {
                bezierPath.addLine(to: point)
            }
        }

        centerLine.path = bezierPath
        centerLine.strokeColor = SKColor(red: 0.15, green: 0.7, blue: 1.0, alpha: 0.4)
        centerLine.lineWidth = 3
        centerLine.zPosition = 6
        trackNode.addChild(centerLine)

        // Draw track boundaries (left and right edges)
        let trackWidthRadius: CGFloat = 300

        for i in 0..<path.count {
            let point = path[i]

            // Calculate perpendicular direction for track width
            let nextIndex = min(i + 1, path.count - 1)
            let nextPoint = path[nextIndex]

            let dx = nextPoint.x - point.x
            let dy = nextPoint.y - point.y
            let length = sqrt(dx * dx + dy * dy)

            if length > 0 {
                // Perpendicular vector
                let perpX = -dy / length * trackWidthRadius
                let perpY = dx / length * trackWidthRadius

                // Left edge
                let leftEdge = SKShapeNode(circleOfRadius: 8)
                leftEdge.position = CGPoint(x: point.x + perpX, y: point.y + perpY)
                leftEdge.fillColor = SKColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.5)
                leftEdge.strokeColor = .clear
                leftEdge.glowWidth = 8
                leftEdge.zPosition = 5
                trackNode.addChild(leftEdge)

                // Right edge
                let rightEdge = SKShapeNode(circleOfRadius: 8)
                rightEdge.position = CGPoint(x: point.x - perpX, y: point.y - perpY)
                rightEdge.fillColor = SKColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.5)
                rightEdge.strokeColor = .clear
                rightEdge.glowWidth = 8
                rightEdge.zPosition = 5
                trackNode.addChild(rightEdge)
            }
        }
    }

    private func setupCheckpoints() {
        // Space checkpoints ~30 seconds apart
        // At 200 points/sec, 30s = 6000 points
        let averageSpeed: CGFloat = 200
        let checkpointInterval: CGFloat = 30  // seconds
        let distanceBetweenCheckpoints = averageSpeed * checkpointInterval

        for i in 0..<numCheckpoints {
            // Calculate position along track
            let targetDistance = distanceBetweenCheckpoints * CGFloat(i + 1)
            let ratio = targetDistance / trackHeight
            let pathIndex = min(Int(ratio * CGFloat(gameState.trackPath.count)), gameState.trackPath.count - 1)

            let checkpointPos = gameState.trackPath[pathIndex]

            let checkpoint = Checkpoint(
                id: i,
                position: checkpointPos,
                width: 400
            )
            gameState.checkpoints.append(checkpoint)

            // Visual marker
            let marker = SKShapeNode(circleOfRadius: 60)
            marker.position = checkpointPos
            marker.fillColor = SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.3)
            marker.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
            marker.lineWidth = 5
            marker.glowWidth = 25
            marker.zPosition = 15
            marker.name = "checkpoint_\(i)"
            checkpointsNode.addChild(marker)

            // Label
            let label = SKLabelNode(text: "CP\(i + 1)")
            label.fontSize = 28
            label.fontColor = .white
            label.position = checkpointPos
            label.zPosition = 16
            checkpointsNode.addChild(label)
        }
    }

    private func setupRacers() {
        // Initialize racers with track path
        gameState.initializeRacers(trackPath: gameState.trackPath)

        // Create sprite nodes with COLORS
        for racer in gameState.racers {
            createRacerNode(racer: racer)
        }
    }

    private func createRacerNode(racer: Racer) {
        let racerNode = SKNode()
        racerNode.name = "racer_\(racer.player.id)"
        racerNode.position = racer.position
        racerNode.zPosition = 20

        // Get player color
        let color = playerColor(playerNumber: racer.player.playerNumber)

        // Sperm body with COLOR
        let body = createSpermShape(color: color)
        racerNode.addChild(body)

        // Player number label
        let numberLabel = SKLabelNode(text: "P\(racer.player.playerNumber)")
        numberLabel.fontSize = 16
        numberLabel.fontColor = .white
        numberLabel.position = CGPoint(x: 0, y: -35)
        numberLabel.name = "number"
        racerNode.addChild(numberLabel)

        // Particle trail with player color
        let trail = createParticleTrail(color: color)
        racerNode.addChild(trail)

        racersNode.addChild(racerNode)
    }

    private func createSpermShape(color: SKColor) -> SKShapeNode {
        // Head with player color
        let head = SKShapeNode(circleOfRadius: 25)
        head.fillColor = color
        head.strokeColor = color.withAlphaComponent(0.8)
        head.lineWidth = 4
        head.glowWidth = 15
        head.name = "head"

        return head
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
        case .lobby:
            // No physics updates
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
        // Update each racer
        for racer in gameState.activeRacers() {
            // Update racer physics with track path
            racer.update(deltaTime: deltaTime, trackPath: gameState.trackPath, weights: physicsWeights)

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
        print("🏁 RACE STARTED! GO GO GO!")
        // No countdown - just start!
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
