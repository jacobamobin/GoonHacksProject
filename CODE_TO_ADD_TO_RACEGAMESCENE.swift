// ADD THESE METHODS TO RaceGameScene.swift
// Replace or add as indicated

// REPLACE setupCamera() with this (around line 100):
private func setupCamera() {
    gameCamera = SKCameraNode()
    camera = gameCamera
    addChild(gameCamera)

    // ZOOM OUT MORE - higher number = more zoomed out
    gameCamera.setScale(2.5)

    // Position camera at start
    gameCamera.position = CGPoint(x: 0, y: size.height / 2)
}

// ADD THIS NEW METHOD (after setupCamera):
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

// REPLACE setupCheckpoints() with this:
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

// REPLACE setupRacers() with this:
private func setupRacers() {
    // Initialize racers with track path
    gameState.initializeRacers(trackPath: gameState.trackPath)

    // Create sprite nodes with COLORS
    for racer in gameState.racers {
        createRacerNode(racer: racer)
    }
}

// REPLACE createRacerNode() with this:
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

// ADD player color function:
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

// REPLACE createSpermShape() to accept color:
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

// REPLACE the update loop physics call (around line 370):
// FIND this:
//     racer.update(deltaTime: deltaTime, fluidField: fluidField, weights: physicsWeights)
// REPLACE WITH:
//     racer.update(deltaTime: deltaTime, trackPath: gameState.trackPath, weights: physicsWeights)

// DELETE or comment out setupFluidField() entirely

// REPLACE startRace() to remove countdown:
private func startRace() {
    guard gameState != nil else { return }
    gameState.phase = .racing
    gameState.raceStartTime = Date().timeIntervalSince1970
    print("🏁 RACE STARTED! GO GO GO!")
    // No countdown - just start!
}

// DELETE showCountdown() method entirely
