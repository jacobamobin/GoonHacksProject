//
//  RaceGameScene.swift
//  GoonHacksGame
//
//  Main racing game scene - completely overhauled for fun gameplay
//

import SpriteKit
import GameplayKit
import AVFoundation
import MultipeerConnectivity

class RaceGameScene: SKScene {

    // MARK: - Properties

    var gameCoordinator: GameCoordinator?
    var gameState: GameState!

    // Scene nodes
    var trackNode: SKNode!
    var racersNode: SKNode!
    var checkpointsNode: SKNode!
    var uiNode: SKNode!

    // Camera
    var gameCamera: SKCameraNode!

    // Timing
    private var lastUpdateTime: TimeInterval = 0
    private var countdownTimeRemaining: Int = 3
    private var countdownLabel: SKLabelNode?

    // Pause menu
    private var isPauseMenuVisible = false
    private var pauseMenu: SKNode?
    private var savedPlayers: [Player] = []

    // Bluetooth controller manager
    private var bluetoothManager: BluetoothControllerManager?

    // MARK: - Initialization

    func initializeGame(with players: [Player]) {
        gameState = GameState()

        // Save players for replay
        savedPlayers = players

        // Add players
        for player in players {
            gameState.addPlayer(player)
        }

        // Initialize race (track, racers, checkpoints)
        gameState.initializeRace()

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
        setupBluetoothControllers()

        // Start with countdown
        startCountdown()
    }

    // MARK: - Setup

    private func setupScene() {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)
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

        // Start at beginning
        gameCamera.setScale(1.5)  // Zoomed out to see more
        gameCamera.position = CGPoint(x: 0, y: 400)
    }

    private func setupTrack() {
        // GLOWING NEON BORDERS - like a fluid racing lane
        let trackPoints = gameState.trackPoints

        // Draw track with GLOWING borders
        for i in 0..<(trackPoints.count - 1) {
            let point = trackPoints[i]
            let nextPoint = trackPoints[i + 1]

            let segmentWidth = point.width

            // GLOWING LEFT BORDER (cyan/electric blue)
            let leftEdge = SKShapeNode(circleOfRadius: 8)
            leftEdge.position = CGPoint(x: point.position.x - segmentWidth/2, y: point.position.y)
            leftEdge.fillColor = SKColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)  // Bright cyan
            leftEdge.strokeColor = .clear
            leftEdge.glowWidth = 20  // Big glow!
            leftEdge.zPosition = 5
            trackNode.addChild(leftEdge)

            // GLOWING RIGHT BORDER (cyan/electric blue)
            let rightEdge = SKShapeNode(circleOfRadius: 8)
            rightEdge.position = CGPoint(x: point.position.x + segmentWidth/2, y: point.position.y)
            rightEdge.fillColor = SKColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)  // Bright cyan
            rightEdge.strokeColor = .clear
            rightEdge.glowWidth = 20  // Big glow!
            rightEdge.zPosition = 5
            trackNode.addChild(rightEdge)

            // Darker fluid background (like swimming pool)
            if i % 3 == 0 {
                let surface = SKShapeNode(rectOf: CGSize(width: segmentWidth - 20, height: abs(nextPoint.position.y - point.position.y) + 10))
                surface.position = CGPoint(x: point.position.x, y: (point.position.y + nextPoint.position.y) / 2)
                surface.fillColor = SKColor(red: 0.05, green: 0.15, blue: 0.25, alpha: 0.4)  // Deep blue water
                surface.strokeColor = .clear
                surface.zPosition = 1
                trackNode.addChild(surface)
            }
        }

        // No obstacles (removed)
    }

    private func setupCheckpoints() {
        for (index, checkpoint) in gameState.checkpoints.enumerated() {
            let isFinish = (index == gameState.checkpoints.count - 1)

            // Checkpoint line
            let width = checkpoint.width * 1.2
            let line = SKShapeNode(rectOf: CGSize(width: width, height: 10))
            line.position = checkpoint.position
            line.fillColor = isFinish ?
                SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.8) :
                SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.6)
            line.strokeColor = .white
            line.lineWidth = 3
            line.glowWidth = 20
            line.zPosition = 15
            line.name = "checkpoint_\(checkpoint.id)"
            checkpointsNode.addChild(line)

            // Label
            let label = SKLabelNode(text: isFinish ? "🏁 FINISH" : "CP\(checkpoint.id + 1)")
            label.fontSize = isFinish ? 36 : 24
            label.fontColor = .white
            label.position = CGPoint(x: checkpoint.position.x, y: checkpoint.position.y + 30)
            label.zPosition = 16
            checkpointsNode.addChild(label)
        }

        // Starting line
        let startLine = SKShapeNode(rectOf: CGSize(width: 600, height: 10))
        startLine.position = CGPoint(x: 0, y: 50)
        startLine.fillColor = SKColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 0.8)
        startLine.strokeColor = .white
        startLine.lineWidth = 3
        startLine.glowWidth = 20
        startLine.zPosition = 15
        trackNode.addChild(startLine)

        let startLabel = SKLabelNode(text: "🏁 START")
        startLabel.fontSize = 36
        startLabel.fontColor = .white
        startLabel.position = CGPoint(x: 0, y: 65)
        startLabel.zPosition = 16
        trackNode.addChild(startLabel)
    }

    private func setupRacers() {
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

        // Add face photo if player has one
        if let faceImage = racer.player.faceImage {
            let faceSprite = SKSpriteNode(texture: SKTexture(image: faceImage))
            faceSprite.size = CGSize(width: 45, height: 45)
            faceSprite.position = CGPoint(x: 0, y: 0)
            faceSprite.zPosition = 1
            faceSprite.name = "face"

            // Circular mask
            let maskNode = SKShapeNode(circleOfRadius: 22.5)
            maskNode.fillColor = .white
            let cropNode = SKCropNode()
            cropNode.maskNode = maskNode
            cropNode.addChild(faceSprite)
            body.addChild(cropNode)
        }

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
        trail.particleBirthRate = 30
        trail.particleLifetime = 0.5
        trail.particleScale = 0.3
        trail.particleScaleSpeed = -0.2
        trail.particleAlpha = 0.6
        trail.particleAlphaSpeed = -1.0
        trail.particleColor = color
        trail.particleColorBlendFactor = 1.0
        trail.particleBlendMode = .add
        trail.position = CGPoint(x: 0, y: -25)
        trail.emissionAngle = CGFloat.pi * 1.5
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
        // Scoreboard (top left)
        createScoreboard()
    }

    private func setupBluetoothControllers() {
        // Use shared Bluetooth manager instance
        bluetoothManager = BluetoothControllerManager.shared
        bluetoothManager?.delegate = self

        print("🎮 Bluetooth controllers ready for race")
        print("📱 Connected devices: \(bluetoothManager?.connectedCount ?? 0)")
    }

    private func createScoreboard() {
        let bg = SKShapeNode(rectOf: CGSize(width: 240, height: 500), cornerRadius: 10)
        bg.fillColor = SKColor(white: 0.1, alpha: 0.8)
        bg.strokeColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.9)
        bg.lineWidth = 3
        bg.position = CGPoint(x: -size.width / 2 + 140, y: size.height / 2 - 270)
        bg.name = "scoreboard"

        gameCamera.addChild(bg)
    }

    // MARK: - Countdown

    private func startCountdown() {
        gameState.phase = .racing
        isPaused = true  // Freeze game during countdown

        countdownLabel = SKLabelNode(text: "3")
        countdownLabel!.fontSize = 120
        countdownLabel!.fontColor = .white
        countdownLabel!.fontName = "Helvetica-Bold"
        countdownLabel!.position = .zero
        countdownLabel!.zPosition = 500
        gameCamera.addChild(countdownLabel!)

        // Animate countdown
        let wait = SKAction.wait(forDuration: 1.0)
        let countdown = SKAction.sequence([
            SKAction.run { [weak self] in
                self?.countdownLabel?.text = "3"
                self?.countdownLabel?.setScale(1.0)
                self?.countdownLabel?.run(SKAction.scale(to: 1.5, duration: 0.3))
            },
            wait,
            SKAction.run { [weak self] in
                self?.countdownLabel?.text = "2"
                self?.countdownLabel?.setScale(1.0)
                self?.countdownLabel?.run(SKAction.scale(to: 1.5, duration: 0.3))
            },
            wait,
            SKAction.run { [weak self] in
                self?.countdownLabel?.text = "1"
                self?.countdownLabel?.setScale(1.0)
                self?.countdownLabel?.run(SKAction.scale(to: 1.5, duration: 0.3))
            },
            wait,
            SKAction.run { [weak self] in
                self?.countdownLabel?.text = "GO!"
                self?.countdownLabel?.setScale(1.0)
                self?.countdownLabel?.fontColor = SKColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 1.0)
                self?.countdownLabel?.run(SKAction.sequence([
                    SKAction.scale(to: 2.0, duration: 0.3),
                    SKAction.wait(forDuration: 0.5),
                    SKAction.fadeOut(withDuration: 0.2)
                ]))
            },
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in
                self?.countdownLabel?.removeFromParent()
                self?.countdownLabel = nil
                self?.startRace()
            }
        ])

        countdownLabel?.run(countdown)
    }

    private func startRace() {
        isPaused = false
        gameState.raceStartTime = Date().timeIntervalSince1970
        // Start motion controllers now that the race has actually started
        gameCoordinator?.startMotionControllers(for: gameState.players)

        print("🏁 RACE STARTED!")
        // Debug: print mapping of players -> device IDs to verify control assignment
        if let players = gameState?.players {
            let mapping = players.map { "P\($0.playerNumber)=\($0.id)" }.joined(separator: ", ")
            print("🔎 Player -> Device mapping: \(mapping)")
        }
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        // Initialize time
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }

        // Don't update if paused or during countdown
        if isPaused || isPauseMenuVisible {
            lastUpdateTime = currentTime
            return
        }

        let deltaTime = min(currentTime - lastUpdateTime, 0.1)  // Cap delta time
        gameState.currentTime = currentTime

        // Update racing
        if gameState.phase == .racing {
            updateRacing(deltaTime: deltaTime)
        }

        lastUpdateTime = currentTime
    }

    private func updateRacing(deltaTime: TimeInterval) {
        // Convert trackPoints to CGPoint array for racer update
        let trackPath = gameState.trackPoints.map { $0.position }

        // Only allow movement if race has started
        guard gameState.raceStartTime != nil else {
            return
        }

        // Update each racer
        for racer in gameState.activeRacers() {
            // Update racer physics
            racer.update(deltaTime: deltaTime, trackPath: trackPath, allRacers: gameState.racers)

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

        // Update camera to follow player group
        updateCamera()

        // Update scoreboard
        updateScoreboard()
    }

    private func updateCamera() {
        let activeRacers = gameState.activeRacers()
        guard !activeRacers.isEmpty else { return }

        // Find bounds of all active racers
        let positions = activeRacers.map { $0.position }
        let minY = positions.map { $0.y }.min() ?? 0
        let maxY = positions.map { $0.y }.max() ?? 0
        let minX = positions.map { $0.x }.min() ?? 0
        let maxX = positions.map { $0.x }.max() ?? 0

        // Center camera on middle of pack
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        // Calculate spread
        let spreadY = maxY - minY
        let spreadX = maxX - minX

        // KEEP EVERYONE ON SCREEN - zoom out if needed (like Mario Kart!)
        let targetZoom: CGFloat
        if spreadY > 800 || spreadX > 600 {
            // Pack is spread out - zoom out
            targetZoom = 2.0
        } else if spreadY > 500 || spreadX > 400 {
            // Medium spread - medium zoom
            targetZoom = 1.7
        } else {
            // Pack is tight - zoom in
            targetZoom = 1.4
        }

        // Smooth zoom
        let currentZoom = gameCamera.xScale
        gameCamera.setScale(currentZoom * 0.95 + targetZoom * 0.05)

        // Smooth follow (bias toward front of pack)
        let targetPos = CGPoint(x: centerX, y: maxY - 200)  // Focus on leaders
        gameCamera.position.x = gameCamera.position.x * 0.9 + targetPos.x * 0.1
        gameCamera.position.y = gameCamera.position.y * 0.9 + targetPos.y * 0.1
    }

    private func updateScoreboard() {
        guard let scoreboardNode = gameCamera.childNode(withName: "scoreboard") else { return }

        // Remove old content
        scoreboardNode.removeAllChildren()

        // Sort racers by position
        let sorted = gameState.activeRacers().sorted { $0.position.y > $1.position.y }

        for (index, racer) in sorted.enumerated() {
            let yPos: CGFloat = 210 - CGFloat(index) * 55  // Increased spacing for SPM labels

            // Position number
            let positionLabel = SKLabelNode(text: "\(index + 1)")
            positionLabel.fontSize = 20
            positionLabel.fontName = "Helvetica-Bold"
            positionLabel.fontColor = .white
            positionLabel.horizontalAlignmentMode = .left
            positionLabel.position = CGPoint(x: -100, y: yPos - 7)
            scoreboardNode.addChild(positionLabel)

            // Face photo or colored circle
            if let faceImage = racer.player.faceImage {
                let faceSprite = SKSpriteNode(texture: SKTexture(image: faceImage))
                faceSprite.size = CGSize(width: 30, height: 30)

                let maskNode = SKShapeNode(circleOfRadius: 15)
                maskNode.fillColor = .white
                let cropNode = SKCropNode()
                cropNode.maskNode = maskNode
                cropNode.addChild(faceSprite)
                cropNode.position = CGPoint(x: -60, y: yPos)
                scoreboardNode.addChild(cropNode)
            } else {
                let colorCircle = SKShapeNode(circleOfRadius: 15)
                colorCircle.fillColor = playerColor(playerNumber: racer.player.playerNumber)
                colorCircle.strokeColor = .white
                colorCircle.lineWidth = 2
                colorCircle.position = CGPoint(x: -60, y: yPos)
                scoreboardNode.addChild(colorCircle)
            }

            // Display name formatting: Humans -> "P# | DeviceName"; CPUs -> "P# | Computer"
            let displayName: String
            if racer.player.isCPU {
                displayName = "P\(racer.player.playerNumber) | Computer"
            } else {
                displayName = "P\(racer.player.playerNumber) | \(racer.player.name)"
            }
            let nameLabel = SKLabelNode(text: displayName)
            nameLabel.fontSize = 16
            nameLabel.fontColor = .white
            nameLabel.horizontalAlignmentMode = .left
            nameLabel.position = CGPoint(x: -35, y: yPos - 6)
            scoreboardNode.addChild(nameLabel)

            // SPM meter (Strokes Per Minute) - only for human players
            if !racer.player.isCPU {
                let spm = Int(racer.player.strokesPerMinute)
                let spmLabel = SKLabelNode(text: "\(spm) SPM")
                spmLabel.fontSize = 12
                spmLabel.fontColor = spm > 0 ? SKColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 1.0) : SKColor(white: 0.5, alpha: 1.0)
                spmLabel.horizontalAlignmentMode = .left
                spmLabel.position = CGPoint(x: -35, y: yPos - 20)
                scoreboardNode.addChild(spmLabel)
            }
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

        // Check if race is over
        if gameState.activeRacers().count == 1 {
            gameState.phase = .finished
            handleRaceFinished()
        }
    }

    private func handleRaceFinished() {
        guard let winner = gameState.activeRacers().first else { return }

        print("🏆 Winner: \(winner.player.name)")

        // Show winner announcement
        let winnerLabel = SKLabelNode(text: "🏆 \(winner.player.name) WINS!")
        winnerLabel.fontSize = 48
        winnerLabel.fontName = "Helvetica-Bold"
        winnerLabel.fontColor = playerColor(playerNumber: winner.player.playerNumber)
        winnerLabel.position = .zero
        winnerLabel.zPosition = 100
        gameCamera.addChild(winnerLabel)

        winnerLabel.run(SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 0.5),
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.run { [weak self] in
                self?.gameCoordinator?.returnToLobby()
            }
        ]))
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        if isPauseMenuVisible {
            handlePauseMenuInput(event)
            return
        }

        switch event.keyCode {
        case 53:  // ESC - Toggle pause
            togglePauseMenu()

        case 0:  // A - Steer left (debug)
            gameState?.players.first?.updateSteering(x: -0.8, y: 0)

        case 2:  // D - Steer right (debug)
            gameState?.players.first?.updateSteering(x: 0.8, y: 0)

        case 13:  // W - Boost (debug)
            if let player = gameState?.players.first {
                _ = player.triggerBoost(currentTime: gameState.currentTime)
            }

        default:
            break
        }
    }

    // MARK: - Pause Menu

    private func togglePauseMenu() {
        if isPauseMenuVisible {
            hidePauseMenu()
        } else {
            showPauseMenu()
        }
    }

    private func showPauseMenu() {
        isPauseMenuVisible = true
        isPaused = true

        pauseMenu = SKNode()
        pauseMenu?.name = "pauseMenu"
        pauseMenu?.zPosition = 1000

        // Dark overlay
        let overlay = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 3))
        overlay.fillColor = SKColor(white: 0, alpha: 0.7)
        overlay.strokeColor = .clear
        overlay.position = .zero
        pauseMenu?.addChild(overlay)

        // Menu background
        let menuBg = SKShapeNode(rectOf: CGSize(width: 500, height: 500), cornerRadius: 20)
        menuBg.fillColor = SKColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 0.95)
        menuBg.strokeColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1.0)
        menuBg.lineWidth = 4
        menuBg.position = .zero
        pauseMenu?.addChild(menuBg)

        // Title
        let titleLabel = SKLabelNode(text: "⏸ PAUSED")
        titleLabel.fontSize = 48
        titleLabel.fontColor = .white
        titleLabel.position = CGPoint(x: 0, y: 180)
        pauseMenu?.addChild(titleLabel)

        // Menu options
        let options = [
            ("1", "Resume Race"),
            ("2", "Replay with Same Players"),
            ("3", "Back to Lobby")
        ]

        for (index, option) in options.enumerated() {
            let yPos: CGFloat = 80 - CGFloat(index) * 70

            let optionLabel = SKLabelNode(text: "[\(option.0)] \(option.1)")
            optionLabel.fontSize = 28
            optionLabel.fontColor = .white
            optionLabel.position = CGPoint(x: 0, y: yPos)
            pauseMenu?.addChild(optionLabel)
        }

        gameCamera.addChild(pauseMenu!)
    }

    private func hidePauseMenu() {
        pauseMenu?.removeFromParent()
        pauseMenu = nil
        isPauseMenuVisible = false
        isPaused = false
    }

    private func handlePauseMenuInput(_ event: NSEvent) {
        switch event.keyCode {
        case 53, 18:  // ESC or 1 - Resume
            hidePauseMenu()

        case 19:  // 2 - Replay
            replayWithSamePlayers()

        case 20:  // 3 - Back to Lobby
            hidePauseMenu()
            gameCoordinator?.returnToLobby()

        default:
            break
        }
    }

    private func replayWithSamePlayers() {
        hidePauseMenu()

        // Reset player states
        for player in savedPlayers {
            player.isEliminated = false
            player.steeringInput = .zero
            player.speedInput = 1.0
            player.boostActive = false
        }

        // Restart
        gameCoordinator?.startRace(with: savedPlayers)
    }

    // MARK: - Multiplayer Integration

    func handleRemoteMotionUpdate(playerNumber: Int, steerX: Double, steerY: Double, boost: Bool) {
        guard let player = gameState?.players.first(where: { $0.playerNumber == playerNumber }) else {
            return
        }

        player.updateSteering(x: steerX, y: steerY)
        if boost {
            _ = player.triggerBoost(currentTime: gameState.currentTime)
        }
    }
}

// MARK: - BluetoothControllerDelegate

extension RaceGameScene: BluetoothControllerDelegate {
    func didReceiveMotion(from deviceId: String, strokingSpeed: Double, steering: Double, spm: Double) {
        // Find ALL players with matching device ID (co-op mode!)
        let matchingPlayers = gameState?.players.filter { $0.id == deviceId } ?? []

        if matchingPlayers.isEmpty {
            // Debug: Player not found
            if Int.random(in: 0..<60) == 0 {
                print("⚠️ Motion from \(deviceId) but no matching player found")
            }
            return
        }

        // Only update if race has started
        guard gameState?.raceStartTime != nil else {
            return
        }

        // Update all matching players (they move together in co-op mode!)
        for player in matchingPlayers {
            player.speedInput = CGFloat(strokingSpeed)
            player.steeringInput = CGVector(dx: steering, dy: 0)
            player.strokesPerMinute = spm
        }

        // Debug logging: print when we have a non-zero SPM, or occasionally sample when SPM==0
        if Int(spm) > 0 {
            let playerNumbers = matchingPlayers.map { "P\($0.playerNumber)" }.joined(separator: ", ")
            print("🎮 \(playerNumbers) <= device \(deviceId): speed=\(String(format: "%.2f", strokingSpeed))x, SPM=\(Int(spm))")
        } else if Int.random(in: 0..<200) == 0 {
            let playerNumbers = matchingPlayers.map { "P\($0.playerNumber)" }.joined(separator: ", ")
            print("ℹ️ (sample) \(playerNumbers) <= device \(deviceId): speed=\(String(format: "%.2f", strokingSpeed))x, SPM=0")
        }
    }
}

// MARK: - MultipeerManagerDelegate

extension RaceGameScene: MultipeerManagerDelegate {
    func didReceiveMessage(_ message: GameMessage, from peer: MCPeerID) {
        switch message {
        case .motionUpdate(let playerNumber, let steerX, let steerY, let boost):
            handleRemoteMotionUpdate(playerNumber: playerNumber, steerX: steerX, steerY: steerY, boost: boost)

        default:
            break
        }
    }

    func peerConnected(_ peer: MCPeerID) {
        print("✅ Peer connected: \(peer.displayName)")
    }

    func peerDisconnected(_ peer: MCPeerID) {
        print("❌ Peer disconnected: \(peer.displayName)")
    }
}

