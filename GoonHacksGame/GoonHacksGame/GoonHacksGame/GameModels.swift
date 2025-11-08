//
//  GameModels.swift
//  GoonHacksGame
//
//  Core game models - COMPLETE OVERHAUL for fun gameplay
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Player

enum PlayerType {
    case human(deviceId: String)
    case cpu(trackletId: String)
}

enum ControlType {
    case airPods
    case iPhone
}

class Player {
    let id: String
    let playerNumber: Int  // 1-8
    var name: String
    var type: PlayerType
    var controlType: ControlType?
    var faceImage: NSImage?
    var isEliminated: Bool = false

    // Motion input state
    var steeringInput: CGVector = .zero  // -1 to 1 in x, y
    var speedInput: CGFloat = 0.5  // 0 to 1 (stroking speed)
    var boostInput: Bool = false
    var lastBoostTime: TimeInterval = 0

    init(id: String, playerNumber: Int, name: String, type: PlayerType) {
        self.id = id
        self.playerNumber = playerNumber
        self.name = name
        self.type = type
    }

    var isCPU: Bool {
        if case .cpu = type {
            return true
        }
        return false
    }

    // Update steering from device motion
    func updateSteering(x: Double, y: Double) {
        steeringInput = CGVector(
            dx: max(-1.0, min(1.0, x)),
            dy: max(-1.0, min(1.0, y))
        )
    }

    // Update speed from stroking motion (up/down)
    func updateSpeed(_ speed: Double) {
        speedInput = CGFloat(max(0.0, min(1.0, speed)))
    }

    // Trigger boost
    func triggerBoost(currentTime: TimeInterval, cooldown: TimeInterval = 1.5) -> Bool {
        if currentTime - lastBoostTime >= cooldown {
            boostInput = true
            lastBoostTime = currentTime
            return true
        }
        return false
    }
}

// MARK: - Racer (In-game entity)

class Racer {
    let player: Player
    var position: CGPoint
    var velocity: CGVector
    var tracklet: Tracklet?
    var trackletTime: Double = 0.0

    // Track following
    var currentSegment: Int = 0
    var trackPath: [CGPoint] = []

    // Visual
    var rotation: CGFloat = 0
    var scale: CGFloat = 1.0

    // Race state
    var distanceTraveled: CGFloat = 0
    var lastCheckpointPassed: Int = -1
    var finishTime: TimeInterval?

    // Speed state
    var baseSpeed: CGFloat = 150.0  // Base forward speed
    var currentSpeed: CGFloat = 150.0

    init(player: Player, startPosition: CGPoint) {
        self.player = player
        self.position = startPosition
        self.velocity = .zero

        // Assign tracklet for CPU players
        if case .cpu(let trackletId) = player.type {
            self.tracklet = TrackletLoader.shared.data?.tracklets.first { $0.id == trackletId }

            // Set CPU speed based on tracklet statistics
            if let tracklet = tracklet {
                let speedScale: CGFloat = 200.0  // Scale factor for VISEM speeds
                baseSpeed = CGFloat(tracklet.statistics.meanSpeed) * speedScale
                currentSpeed = baseSpeed
            }
        }
    }

    // Update physics - SIMPLIFIED AND FIXED
    func update(deltaTime: TimeInterval, trackPath: [CGPoint], weights: PhysicsWeights) {
        // 1. Calculate forward movement along track
        let forwardMovement = calculateForwardMovement(deltaTime: deltaTime, trackPath: trackPath, weights: weights)

        // 2. Apply lateral steering
        let lateralMovement = applyLateralSteering(weights: weights)

        // 3. Apply boost
        if player.boostInput {
            currentSpeed = baseSpeed * 2.0
            player.boostInput = false
        } else {
            currentSpeed = baseSpeed
        }

        // 4. Update position
        position = CGPoint(
            x: position.x + forwardMovement.dx * deltaTime + lateralMovement.dx * deltaTime,
            y: position.y + forwardMovement.dy * deltaTime + lateralMovement.dy * deltaTime
        )

        // 5. Update velocity for rendering
        velocity = CGVector(
            dx: forwardMovement.dx + lateralMovement.dx,
            dy: forwardMovement.dy + lateralMovement.dy
        )

        // 6. Update rotation
        if let nextPoint = getNextTrackPoint(trackPath: trackPath) {
            let dx = nextPoint.x - position.x
            let dy = nextPoint.y - position.y
            rotation = atan2(dy, dx)
        }

        // 7. Track distance
        distanceTraveled += currentSpeed * deltaTime
    }

    private func calculateForwardMovement(deltaTime: TimeInterval, trackPath: [CGPoint], weights: PhysicsWeights) -> CGVector {
        // Get next point on track
        guard let nextPoint = getNextTrackPoint(trackPath: trackPath) else {
            return CGVector(dx: 0, dy: currentSpeed)  // Default: move up
        }

        // Direction to next point
        let dx = nextPoint.x - position.x
        let dy = nextPoint.y - position.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance < 10 {
            // Move to next segment
            currentSegment = min(currentSegment + 1, trackPath.count - 1)
        }

        if distance > 0 {
            // Normalize and apply speed
            let speedMod = CGFloat(player.speedInput) + 0.5  // 0.5 to 1.5 multiplier
            let effectiveSpeed = currentSpeed * speedMod

            return CGVector(
                dx: (dx / distance) * effectiveSpeed,
                dy: (dy / distance) * effectiveSpeed
            )
        }

        return .zero
    }

    private func applyLateralSteering(weights: PhysicsWeights) -> CGVector {
        // Only apply horizontal steering
        return CGVector(
            dx: player.steeringInput.dx * weights.steerMultiplier,
            dy: 0  // No vertical input override - follow track
        )
    }

    private func getNextTrackPoint(trackPath: [CGPoint]) -> CGPoint? {
        guard currentSegment < trackPath.count else { return nil }
        return trackPath[currentSegment]
    }
}

// MARK: - Physics Configuration

struct PhysicsWeights {
    var maxSpeed: CGFloat = 300.0
    var steerMultiplier: CGFloat = 150.0  // Lateral steering strength
    var baseForwardSpeed: CGFloat = 200.0  // Default forward speed
}

// MARK: - Track Generator (Dynamic curved track)

class TrackGenerator {
    static func generateCurvedTrack(
        width: CGFloat,
        height: CGFloat,
        segments: Int,
        curveIntensity: CGFloat
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        let segmentHeight = height / CGFloat(segments)

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0

        for i in 0...segments {
            let y = currentY

            // Add curves using sine wave
            let frequency: CGFloat = 0.3
            let amplitude = width * curveIntensity
            let phase = CGFloat(i) * frequency

            let x = sin(phase) * amplitude

            points.append(CGPoint(x: x, y: y))

            currentY += segmentHeight
        }

        return points
    }

    static func generateObstacles(alongPath path: [CGPoint], count: Int) -> [CGRect] {
        var obstacles: [CGRect] = []

        let step = path.count / count

        for i in 0..<count {
            let index = min(i * step, path.count - 1)
            let point = path[index]

            let obstacleWidth: CGFloat = CGFloat.random(in: 40...80)
            let obstacleHeight: CGFloat = CGFloat.random(in: 30...60)

            // Offset to sides
            let xOffset = CGFloat.random(in: -200...200)

            let obstacle = CGRect(
                x: point.x + xOffset - obstacleWidth / 2,
                y: point.y - obstacleHeight / 2,
                width: obstacleWidth,
                height: obstacleHeight
            )

            obstacles.append(obstacle)
        }

        return obstacles
    }
}

// MARK: - Checkpoint

struct Checkpoint {
    let id: Int
    let position: CGPoint  // Position on track
    let width: CGFloat
    var racersPassed: Set<String> = []

    func contains(position: CGPoint) -> Bool {
        let distance = sqrt(
            pow(position.x - self.position.x, 2) +
            pow(position.y - self.position.y, 2)
        )
        return distance < 50  // Within 50 points
    }
}

// MARK: - Game State

enum GamePhase {
    case lobby
    case racing
    case checkpointElimination
    case finished
}

class GameState {
    var phase: GamePhase = .lobby
    var players: [Player] = []
    var racers: [Racer] = []
    var checkpoints: [Checkpoint] = []
    var trackPath: [CGPoint] = []
    var obstacles: [CGRect] = []
    var currentCheckpoint: Int = 0
    var raceStartTime: TimeInterval = 0
    var currentTime: TimeInterval = 0

    // Add player (up to 8)
    func addPlayer(_ player: Player) -> Bool {
        guard players.count < 8 else { return false }
        players.append(player)
        return true
    }

    // Fill remaining slots with CPU players
    func fillWithCPU() {
        while players.count < 8 {
            guard let tracklet = TrackletLoader.shared.randomTracklet() else { break }

            let cpuPlayer = Player(
                id: UUID().uuidString,
                playerNumber: players.count + 1,
                name: "CPU \(players.count + 1)",
                type: .cpu(trackletId: tracklet.id)
            )
            players.append(cpuPlayer)
        }
    }

    // Initialize racers at start positions
    func initializeRacers(trackPath: [CGPoint]) {
        self.trackPath = trackPath
        racers.removeAll()

        guard let startPoint = trackPath.first else { return }

        for (index, player) in players.enumerated() {
            let xOffset = (CGFloat(index) - 3.5) * 60  // Spread across start line
            let racer = Racer(
                player: player,
                startPosition: CGPoint(x: startPoint.x + xOffset, y: startPoint.y)
            )
            racer.trackPath = trackPath
            racers.append(racer)
        }
    }

    // Check checkpoint crossing
    func checkCheckpoints() -> [Player]? {
        guard currentCheckpoint < checkpoints.count else { return nil }

        let checkpoint = checkpoints[currentCheckpoint]
        var newPasses: [Player] = []

        for racer in racers where !racer.player.isEliminated {
            if checkpoint.contains(position: racer.position) &&
               !checkpoint.racersPassed.contains(racer.player.id) {
                checkpoints[currentCheckpoint].racersPassed.insert(racer.player.id)
                newPasses.append(racer.player)
                racer.lastCheckpointPassed = currentCheckpoint
            }
        }

        // Check if all active racers passed
        let activeRacers = racers.filter { !$0.player.isEliminated }
        if checkpoint.racersPassed.count >= activeRacers.count {
            return eliminateLastPlace()
        }

        return nil
    }

    // Eliminate last racer at checkpoint
    private func eliminateLastPlace() -> [Player] {
        let activeRacers = racers.filter { !$0.player.isEliminated }

        // Sort by distance traveled
        let sorted = activeRacers.sorted { $0.distanceTraveled > $1.distanceTraveled }

        // Eliminate last player
        if let lastPlace = sorted.last {
            lastPlace.player.isEliminated = true
            currentCheckpoint += 1
            return [lastPlace.player]
        }

        return []
    }

    // Get active (non-eliminated) racers
    func activeRacers() -> [Racer] {
        return racers.filter { !$0.player.isEliminated }
    }
}
