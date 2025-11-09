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
    // Elimination banner
    private var eliminationLabel: SKLabelNode?

    // Bluetooth controller manager
    private var bluetoothManager: BluetoothControllerManager?
    // Debug overlay
    private var debugOverlay: SKNode?
    private var debugLeftLabel: SKLabelNode?
    private var debugRightLabel: SKLabelNode?
    private var debugLeftSPMLabel: SKLabelNode?
    private var debugRightSPMLabel: SKLabelNode?
    private var debugPeersLabel: SKLabelNode?

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
    setupDebugOverlay()

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
        // Draw continuous left/right borders and lane separators using polylines so edges are not dots
        let leftPath = CGMutablePath()
        let rightPath = CGMutablePath()

        var leftStarted = false
        var rightStarted = false

        // Lane separators (8 lanes) paths
        var lanePaths: [CGMutablePath] = (0..<8).map { _ in CGMutablePath() }
        var laneStarted = [Bool](repeating: false, count: 8)

        for (index, point) in trackPoints.enumerated() {
            let halfWidth = point.width / 2
            let leftX = point.position.x - halfWidth
            let rightX = point.position.x + halfWidth
            let y = point.position.y

            if !leftStarted {
                leftPath.move(to: CGPoint(x: leftX, y: y))
                leftStarted = true
            } else {
                leftPath.addLine(to: CGPoint(x: leftX, y: y))
            }

            if !rightStarted {
                rightPath.move(to: CGPoint(x: rightX, y: y))
                rightStarted = true
            } else {
                rightPath.addLine(to: CGPoint(x: rightX, y: y))
            }

            // Lane separators evenly spaced across track width
            let laneWidth = point.width / 8.0
            for j in 0..<8 {
                let laneX = point.position.x - halfWidth + CGFloat(j) * laneWidth
                if !laneStarted[j] {
                    lanePaths[j].move(to: CGPoint(x: laneX, y: y))
                    laneStarted[j] = true
                } else {
                    lanePaths[j].addLine(to: CGPoint(x: laneX, y: y))
                }
            }
        }

        // Create SKShapeNodes for borders
        let leftBorder = SKShapeNode(path: leftPath)
        leftBorder.strokeColor = SKColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        leftBorder.lineWidth = 8
        leftBorder.glowWidth = 24
        leftBorder.zPosition = 5
        leftBorder.fillColor = .clear
        trackNode.addChild(leftBorder)

        let rightBorder = SKShapeNode(path: rightPath)
        rightBorder.strokeColor = SKColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        rightBorder.lineWidth = 8
        rightBorder.glowWidth = 24
        rightBorder.zPosition = 5
        rightBorder.fillColor = .clear
        trackNode.addChild(rightBorder)

        // Thin lane separators
        for j in 0..<8 {
            let laneNode = SKShapeNode(path: lanePaths[j])
            laneNode.strokeColor = SKColor(white: 1.0, alpha: 0.06)
            laneNode.lineWidth = 2
            laneNode.zPosition = 2
            trackNode.addChild(laneNode)
        }

        // Fluid background patches for depth
        for i in stride(from: 0, to: trackPoints.count - 1, by: 6) {
            let point = trackPoints[i]
            let nextPoint = trackPoints[min(i + 6, trackPoints.count - 1)]
            let segmentWidth = point.width
            let surface = SKShapeNode(rectOf: CGSize(width: segmentWidth - 20, height: abs(nextPoint.position.y - point.position.y) + 10))
            surface.position = CGPoint(x: point.position.x, y: (point.position.y + nextPoint.position.y) / 2)
            surface.fillColor = SKColor(red: 0.05, green: 0.15, blue: 0.25, alpha: 0.4)
            surface.strokeColor = .clear
            surface.zPosition = 1
            trackNode.addChild(surface)
        }

        // No obstacles (removed)
    }

    private func setupCheckpoints() {
        for (index, checkpoint) in gameState.checkpoints.enumerated() {
            let isFinish = (index == gameState.checkpoints.count - 1)

            // Checkpoint line: span edge-to-edge and keep centered
            let width = gameState.trackWidth * 1.02
            let pos = CGPoint(x: 0, y: checkpoint.position.y)

            if isFinish {
                // Draw finish checkerboard stripe
                let checker = createCheckerboardStripe(width: width, height: 18, squareSize: 18)
                checker.position = pos
                checker.zPosition = 20
                checker.name = "checkpoint_\(checkpoint.id)"
                checkpointsNode.addChild(checker)
            } else {
                let line = SKShapeNode(rectOf: CGSize(width: width, height: 10))
                line.position = pos
                line.fillColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.6)
                line.strokeColor = .white
                line.lineWidth = 3
                line.glowWidth = 20
                line.zPosition = 15
                line.name = "checkpoint_\(checkpoint.id)"
                checkpointsNode.addChild(line)
            }

            // Label
            let label = SKLabelNode(text: isFinish ? "🏁 FINISH" : "CP\(checkpoint.id + 1)")
            label.fontSize = isFinish ? 36 : 24
            label.fontColor = .white
            label.position = CGPoint(x: 0, y: pos.y + 30)
            label.zPosition = 16
            checkpointsNode.addChild(label)
        }

        // Starting line - checkerboard style covering track
        let startWidth = gameState.trackWidth * 1.02
        let startChecker = createCheckerboardStripe(width: startWidth, height: 18, squareSize: 18)
        startChecker.position = CGPoint(x: 0, y: 50)
        startChecker.zPosition = 20
        trackNode.addChild(startChecker)

        let startLabel = SKLabelNode(text: "🏁 START")
        startLabel.fontSize = 36
        startLabel.fontColor = .white
        startLabel.position = CGPoint(x: 0, y: 65)
        startLabel.zPosition = 21
        trackNode.addChild(startLabel)
    }

    // Helper: create a checkerboard stripe node spanning width
    private func createCheckerboardStripe(width: CGFloat, height: CGFloat, squareSize: CGFloat) -> SKNode {
        let node = SKNode()

        // Number of squares across (cover slightly more to avoid gaps)
        let cols = Int(ceil(width / squareSize)) + 2
        let startX = -width / 2 - squareSize

        for col in 0..<cols {
            // Alternate color
            let isBlack = (col % 2 == 0)
            let color: SKColor = isBlack ? .black : .white
            let square = SKShapeNode(rectOf: CGSize(width: squareSize, height: height))
            square.fillColor = color
            square.strokeColor = .clear
            square.position = CGPoint(x: startX + CGFloat(col) * squareSize + squareSize / 2, y: 0)
            node.addChild(square)
        }

        return node
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
            faceSprite.size = CGSize(width: 60, height: 60)
            faceSprite.position = CGPoint(x: 0, y: 0)
            faceSprite.zPosition = 1
            faceSprite.name = "face"

            // Circular mask
            let maskNode = SKShapeNode(circleOfRadius: 30)
            maskNode.fillColor = .white
            let cropNode = SKCropNode()
            cropNode.maskNode = maskNode
            cropNode.addChild(faceSprite)
            if let head = body.childNode(withName: "head") {
                head.addChild(cropNode)
            }
        }

        // Player number label
    // Player number shown near the head (slightly above)
    let numberLabel = SKLabelNode(text: "P\(racer.player.playerNumber)")
    numberLabel.fontSize = 18
    numberLabel.fontColor = .white
    numberLabel.position = CGPoint(x: 0, y: 48)
    numberLabel.name = "number"
    racerNode.addChild(numberLabel)

        // Particle trail with player color
        let trail = createParticleTrail(color: color)
        racerNode.addChild(trail)

        racersNode.addChild(racerNode)
    }

    private func createSpermShape(color: SKColor) -> SKNode {
        let spermNode = SKNode()
        spermNode.name = "sperm"

        // Head with player color (increased for high-res screens)
        let head = SKShapeNode(circleOfRadius: 50)
        head.fillColor = color
        head.strokeColor = color.withAlphaComponent(0.8)
        head.lineWidth = 4
        head.glowWidth = 15
        head.name = "head"
        spermNode.addChild(head)
        // Tail - longer and thicker for visibility
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: 0, y: -50))
        tailPath.addCurve(to: CGPoint(x: 0, y: -140), control1: CGPoint(x: -30, y: -80), control2: CGPoint(x: 30, y: -120))

        let tail = SKShapeNode(path: tailPath)
        tail.lineWidth = 12
        tail.strokeColor = color
        tail.glowWidth = 12
        tail.name = "tail"
        spermNode.addChild(tail)

        // Tail animation - use actions that can be sped up by adjusting 'speed' property
        let wiggle = SKAction.sequence([
            SKAction.rotate(byAngle: 0.18, duration: 0.12),
            SKAction.rotate(byAngle: -0.36, duration: 0.24),
            SKAction.rotate(byAngle: 0.18, duration: 0.12)
        ])
        let wiggleForever = SKAction.repeatForever(wiggle)
        tail.run(wiggleForever)

        return spermNode
    }

    private func createParticleTrail(color: SKColor) -> SKEmitterNode {
        let trail = SKEmitterNode()
        trail.particleBirthRate = 45
        trail.particleLifetime = 0.6
        trail.particleScale = 0.45
        trail.particleScaleSpeed = -0.2
        trail.particleAlpha = 0.7
        trail.particleAlphaSpeed = -1.2
        trail.particleColor = color
        trail.particleColorBlendFactor = 1.0
        trail.particleBlendMode = .add
        trail.position = CGPoint(x: 0, y: -130)
        trail.emissionAngle = CGFloat.pi * 1.5
        trail.emissionAngleRange = CGFloat.pi * 0.25
        trail.particleSpeed = 70
        trail.particleSpeedRange = 30
        trail.zPosition = -1
        trail.name = "trail"

        return trail
    }

    private func playerColor(playerNumber: Int) -> SKColor {
        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0),  // 1: Red
            SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),  // 2: Blue
            SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),  // 3: Green
            SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0),  // 4: Yellow
            SKColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 1.0),  // 5: Pink
            SKColor(red: 0.6, green: 0.2, blue: 1.0, alpha: 1.0),  // 6: Purple
            SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0),  // 7: Orange
            SKColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1.0),  // 8: Cyan
        ]
        return colors[(playerNumber - 1) % colors.count]
    }

    private func setupUI() {
        // Scoreboard (top left)
        createScoreboard()

        // Player positions (top of screen)
        let laneWidth = gameState.trackWidth / 8
        let defaultStartX = -gameState.trackWidth / 2 + laneWidth / 2
        for i in 0..<8 {
            let y = size.height / 2 - 50

            // If a racer exists for this player number, anchor the label to the racer's lane offset
            let playerNumber = i + 1
            var x: CGFloat
            if let racer = gameState.racers.first(where: { $0.player.playerNumber == playerNumber }) {
                // Use track start X + laneOffset for accurate alignment
                let trackStartX = gameState.trackPoints.first?.position.x ?? 0
                x = trackStartX + racer.laneOffset
            } else {
                // Fallback to uniform spacing across track
                x = defaultStartX + CGFloat(i) * laneWidth
            }

            let positionNode = SKNode()
            positionNode.position = CGPoint(x: x, y: y)
            positionNode.name = "playerPosition_\(playerNumber)"
            gameCamera.addChild(positionNode)

            let numberLabel = SKLabelNode(text: "P\(playerNumber)")
            numberLabel.fontSize = 20
            numberLabel.fontName = "SF Pro"
            numberLabel.fontColor = gameState.players.first(where: { $0.playerNumber == playerNumber }) != nil ? playerColor(playerNumber: playerNumber) : .gray
            positionNode.addChild(numberLabel)

            let rankLabel = SKLabelNode(text: "-")
            rankLabel.fontSize = 20
            rankLabel.fontName = "SF Pro"
            rankLabel.fontColor = .white
            rankLabel.position = CGPoint(x: 0, y: -30)
            rankLabel.name = "rankLabel"
            positionNode.addChild(rankLabel)
        }

        // Create elimination banner (hidden initially)
        eliminationLabel = SKLabelNode(text: "")
        eliminationLabel?.fontSize = 28
        eliminationLabel?.fontName = "SF Pro"
        eliminationLabel?.fontColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        eliminationLabel?.position = CGPoint(x: 0, y: -size.height / 2 + 60)
        eliminationLabel?.zPosition = 100
        eliminationLabel?.alpha = 0
        if let el = eliminationLabel { gameCamera.addChild(el) }
    }

    private func setupBluetoothControllers() {
        // Use shared Bluetooth manager instance
        bluetoothManager = BluetoothControllerManager.shared
        bluetoothManager?.delegate = self

        print("🎮 Bluetooth controllers ready for race")
        print("📱 Connected devices: \(bluetoothManager?.connectedCount ?? 0)")
    }

    private func setupDebugOverlay() {
        // Small camera-anchored telemetry panel for tuning motion/workflow
        debugOverlay = SKNode()
        debugOverlay?.name = "debugOverlay"
        debugOverlay?.zPosition = 999

        let panel = SKShapeNode(rectOf: CGSize(width: 320, height: 130), cornerRadius: 8)
        panel.fillColor = SKColor(white: 0.05, alpha: 0.75)
        panel.strokeColor = SKColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.9)
        panel.lineWidth = 2
        panel.position = CGPoint(x: size.width / 2 - 180, y: size.height / 2 - 90)
        debugOverlay?.addChild(panel)

        // Labels
        let leftLabel = SKLabelNode(text: "L signal: 0.000")
        leftLabel.fontSize = 12
        leftLabel.horizontalAlignmentMode = .left
        leftLabel.position = CGPoint(x: -150, y: 40)
        panel.addChild(leftLabel)
        debugLeftLabel = leftLabel

        let rightLabel = SKLabelNode(text: "R signal: 0.000")
        rightLabel.fontSize = 12
        rightLabel.horizontalAlignmentMode = .left
        rightLabel.position = CGPoint(x: -150, y: 18)
        panel.addChild(rightLabel)
        debugRightLabel = rightLabel

        let leftSPM = SKLabelNode(text: "L SPM: 0")
        leftSPM.fontSize = 12
        leftSPM.horizontalAlignmentMode = .left
        leftSPM.position = CGPoint(x: -150, y: -4)
        panel.addChild(leftSPM)
        debugLeftSPMLabel = leftSPM

        let rightSPM = SKLabelNode(text: "R SPM: 0")
        rightSPM.fontSize = 12
        rightSPM.horizontalAlignmentMode = .left
        rightSPM.position = CGPoint(x: -150, y: -26)
        panel.addChild(rightSPM)
        debugRightSPMLabel = rightSPM

        let peers = SKLabelNode(text: "Peers: 0")
        peers.fontSize = 12
        peers.horizontalAlignmentMode = .left
        peers.position = CGPoint(x: -150, y: -48)
        panel.addChild(peers)
        debugPeersLabel = peers

        // Camera-anchored
        gameCamera.addChild(debugOverlay!)
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
        // Start motion controllers right at race start so sensors begin feeding immediately,
        // then clear smoothing buffers so the first strokes are responsive.
        gameCoordinator?.startMotionControllers(for: gameState.players)
        bluetoothManager?.resetMotionBuffers()

        isPaused = false
        gameState.raceStartTime = Date().timeIntervalSince1970

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

                // Update tail animation speed based on SPM
                if let tail = racerNode.childNode(withName: "sperm")?.childNode(withName: "tail") {
                    // SPM -> wiggle speed mapping: baseline 0.6, scale up with SPM
                    let spm = racer.player.strokesPerMinute
                    let mapped = 0.6 + min(2.0, CGFloat(spm) / 40.0)
                    tail.speed = CGFloat(mapped)
                }
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

        // Update player positions
        updatePlayerPositions()

        // Update debug overlay values from Bluetooth manager (if present)
        if let mgr = bluetoothManager {
            debugLeftLabel?.text = String(format: "L signal: %.3f", mgr.debugLeftSignal)
            debugRightLabel?.text = String(format: "R signal: %.3f", mgr.debugRightSignal)
            debugLeftSPMLabel?.text = String(format: "L SPM: %d", Int(mgr.debugLeftSPM))
            debugRightSPMLabel?.text = String(format: "R SPM: %d", Int(mgr.debugRightSPM))
            debugPeersLabel?.text = "Peers: \(mgr.debugConnectedPeersCount)"
        }
    }

    private func updatePlayerPositions() {
        let sortedRacers = gameState.racers.sorted { $0.position.y > $1.position.y }
        for (index, racer) in sortedRacers.enumerated() {
            // Update rank label
            if let positionNode = gameCamera.childNode(withName: "playerPosition_\(racer.player.playerNumber)"),
               let rankLabel = positionNode.childNode(withName: "rankLabel") as? SKLabelNode {
                rankLabel.text = "\(index + 1)"

                // Reposition the camera-anchored node so it lines up with the racer's lane.
                // Convert racer's world position into camera-space and set x accordingly.
                if let cam = camera {
                    let pointInCamera = convert(racer.position, to: cam)
                    // Keep the original y of the positionNode (top UI), update x only
                    let currentY = positionNode.position.y
                    positionNode.position = CGPoint(x: pointInCamera.x, y: currentY)
                }
            }
        }
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

        // Show elimination banner for a short time
        if let first = eliminated.first {
            eliminationLabel?.text = "Player \(first.playerNumber) eliminated"
            eliminationLabel?.alpha = 1.0
            eliminationLabel?.run(SKAction.sequence([
                SKAction.wait(forDuration: 2.5),
                SKAction.fadeOut(withDuration: 0.5)
            ]))
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

    override func mouseDown(with event: NSEvent) {
        if isPauseMenuVisible {
            let location = event.location(in: pauseMenu!)
            let clickedNode = pauseMenu!.atPoint(location)

            if clickedNode.name == "resumeButton" {
                hidePauseMenu()
            } else if clickedNode.name == "replayButton" {
                replayWithSamePlayers()
            } else if clickedNode.name == "lobbyButton" {
                hidePauseMenu()
                gameCoordinator?.returnToLobby()
            }
        }
    }

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
        let titleLabel = SKLabelNode(text: "PAUSED")
        titleLabel.fontSize = 48
        titleLabel.fontName = "SF Pro"
        titleLabel.fontColor = .white
        titleLabel.position = CGPoint(x: 0, y: 180)
        pauseMenu?.addChild(titleLabel)

        // Menu options
        let options = [
            ("resumeButton", "Resume Race"),
            ("replayButton", "Replay with Same Players"),
            ("lobbyButton", "Back to Lobby")
        ]

        for (index, option) in options.enumerated() {
            let yPos: CGFloat = 80 - CGFloat(index) * 70

            let optionLabel = SKLabelNode(text: option.1)
            optionLabel.fontSize = 28
            optionLabel.fontName = "SF Pro"
            optionLabel.fontColor = .white
            optionLabel.position = CGPoint(x: 0, y: yPos)
            optionLabel.name = option.0
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
        guard let gameState = gameState, gameState.raceStartTime != nil else {
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

