//
//  GameModels.swift
//  GoonHacksGame
//
//  Core game models - Simple, fun racing without VISEM
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Player

enum PlayerType {
    case human(deviceId: String)
    case cpu
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
    var speedInput: CGFloat = 0.75  // 0.75 to 1.3 (stroking speed multiplier, starts at 0.75x)
    var boostActive: Bool = false
    var lastBoostTime: TimeInterval = 0

    // Performance metrics
    var strokesPerMinute: Double = 0.0  // SPM - strokes per minute

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

    // Update speed from stroking motion
    func updateSpeed(_ speed: Double) {
        // Map 0-1 input to 0.5-1.5 multiplier
        speedInput = CGFloat(0.5 + speed)  // 0.5x to 1.5x speed
    }

    // Trigger boost
    func triggerBoost(currentTime: TimeInterval, cooldown: TimeInterval = 2.0) -> Bool {
        if currentTime - lastBoostTime >= cooldown {
            boostActive = true
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
    var rotation: CGFloat = 0

    // Physics
    var baseSpeed: CGFloat = 300.0  // Pixels per second
    var currentSpeed: CGFloat = 300.0
    let maxSpeed: CGFloat = 600.0
    let acceleration: CGFloat = 500.0
    let friction: CGFloat = 0.95

    // Lane assignment (so players don't overlap!)
    var laneOffset: CGFloat = 0  // X offset from track centerline

    // CPU AI
    var cpuTargetPoint: CGPoint?
    var cpuPersonality: CGFloat = 1.0  // Speed multiplier for CPU

    // Race state
    var distanceTraveled: CGFloat = 0
    var lastCheckpointPassed: Int = -1
    var finishTime: TimeInterval?
    var lap: Int = 1

    init(player: Player, startPosition: CGPoint, laneOffset: CGFloat = 0) {
        self.player = player
        self.position = startPosition
        self.velocity = .zero
        self.laneOffset = laneOffset  // Assign lane

        // Make CPUs beatable but still competitive
        // CPU speed range: minimum = player idle speed (0.75x), max = 1.0x
        // Players can easily beat CPUs by shaking (up to 1.3x)
        if player.isCPU {
            // CPUs should be competitive but clearly distinct from each other.
            // Increase personality spread so CPU speeds vary more noticeably.
            let base: CGFloat = 0.88
            // Larger deterministic offset so ordering between CPUs is clearer
            let deterministicOffset = 0.02 * CGFloat(player.playerNumber % 6)
            // Increase jitter to allow more per-match variance
            let jitter: CGFloat = CGFloat.random(in: -0.06...0.06)
            // Wider clamp so some CPUs can be noticeably faster or slower
            cpuPersonality = max(0.78, min(1.18, base + deterministicOffset + jitter))
        }
    }

    func update(deltaTime: TimeInterval, trackPath: [CGPoint], allRacers: [Racer]) {
        let dt = CGFloat(deltaTime)

        if player.isCPU {
            updateCPU(trackPath: trackPath, dt: dt, allRacers: allRacers)
        } else {
            updateHuman(dt: dt, trackPath: trackPath, allRacers: allRacers)
        }

        // Update position
        position.x += velocity.dx * dt
        position.y += velocity.dy * dt

        // Update distance
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        distanceTraveled += speed * dt

        // Rotation is handled in update methods (auto-follow path)
    }

    private func updateHuman(dt: CGFloat, trackPath: [CGPoint], allRacers: [Racer]) {
        // SPAM RACE - STAY ON TRACK, JUST SHAKE TO GO FASTER!
        // Like sperm racing upward in a narrow channel

        // Speed entirely controlled by stroking (1.0 - 1.5x)
        var targetSpeed = baseSpeed * player.speedInput

        // RUBBER BANDING - help players who fall behind (like Mario Kart!)
        let maxY = allRacers.map { $0.position.y }.max() ?? position.y
        let distanceBehind = maxY - position.y

        if distanceBehind > 500 {
            // Way behind - big boost
            targetSpeed *= 1.3
        } else if distanceBehind > 250 {
            // Behind - small boost
            targetSpeed *= 1.15
        }

        // Boost
        if player.boostActive {
            currentSpeed = min(maxSpeed, targetSpeed * 2.0)
            player.boostActive = false
        } else {
            currentSpeed = targetSpeed
        }

        // TIGHTLY FOLLOW THE TRACK (like on rails!)
        guard !trackPath.isEmpty else { return }

        // Find current position on track based on Y coordinate
        var nearestIndex = 0
        var nearestDistance: CGFloat = .infinity

        for (index, point) in trackPath.enumerated() {
            let yDist = abs(point.y - position.y)
            if yDist < nearestDistance {
                nearestDistance = yDist
                nearestIndex = index
            }
        }

        // Lock X position to track centerline + lane offset (stay in your lane!)
        let currentTrackPoint = trackPath[nearestIndex]
        position.x = currentTrackPoint.x + laneOffset  // Snap to track + lane!

        // Always move FORWARD (upward) along the track
        let lookAheadIndex = min(nearestIndex + 3, trackPath.count - 1)
        let targetPoint = trackPath[lookAheadIndex]

        // Face upward along the track
        let dx = targetPoint.x - currentTrackPoint.x
        let dy = targetPoint.y - currentTrackPoint.y
        rotation = atan2(dy, dx) - .pi / 2

        // Move UPWARD with speed (always positive Y direction)
        velocity.dx = 0  // No horizontal drift
        velocity.dy = currentSpeed  // Only move upward!

        // Debug logging (occasionally)
        if Int.random(in: 0..<120) == 0 {
            print("🏊 P\(player.playerNumber): Y=\(Int(position.y)) X=\(Int(position.x)) speed=\(String(format: "%.2f", currentSpeed)) speedInput=\(String(format: "%.2f", player.speedInput))")
        }

        // No drag - direct speed control
    }

    private func updateCPU(trackPath: [CGPoint], dt: CGFloat, allRacers: [Racer]) {
        // CPU STAYS ON TRACK (same as human, but different speeds)
        guard !trackPath.isEmpty else { return }

        // Find human players and leader
        let humanRacers = allRacers.filter { !$0.player.isCPU }
        let maxY = allRacers.map { $0.position.y }.max() ?? position.y
        let slowestHumanY = humanRacers.map { $0.position.y }.min() ?? position.y

        // CPU positioning helpers
        let distanceBehind = maxY - position.y
        let distanceAheadOfSlowestHuman = position.y - slowestHumanY

        var speedMultiplier: CGFloat = 1.0

        // If we're slightly ahead of the slowest human, ease off a bit but don't cut dramatically
        if !humanRacers.isEmpty && distanceAheadOfSlowestHuman > 50 {
            // Slight slow down so CPUs don't hog the lead but stay visible
            speedMultiplier = 0.92
        }

        // Rubber-banding: ensure CPUs don't fall off screen and can catch up
        if distanceBehind > 700 {
            speedMultiplier = max(speedMultiplier, 1.6)
        } else if distanceBehind > 500 {
            speedMultiplier = max(speedMultiplier, 1.35)
        } else if distanceBehind > 350 {
            speedMultiplier = max(speedMultiplier, 1.2)
        } else if distanceBehind > 200 {
            speedMultiplier = max(speedMultiplier, 1.1)
        }

        // If dramatically far behind (unexpected), force a catch-up to keep them on-screen
        if position.y < maxY - 1200 {
            speedMultiplier = max(speedMultiplier, 1.8)
        }

        // Find current position on track based on Y coordinate
        var nearestIndex = 0
        var nearestDistance: CGFloat = .infinity

        for (index, point) in trackPath.enumerated() {
            let yDist = abs(point.y - position.y)
            if yDist < nearestDistance {
                nearestDistance = yDist
                nearestIndex = index
            }
        }

        // Lock X position to track centerline + lane offset (stay in your lane!)
        let currentTrackPoint = trackPath[nearestIndex]
        position.x = currentTrackPoint.x + laneOffset  // Snap to track + lane!

        // Always move FORWARD (upward) along the track
        let lookAheadIndex = min(nearestIndex + 3, trackPath.count - 1)
        let targetPoint = trackPath[lookAheadIndex]

        // Face upward along the track
        let dx = targetPoint.x - currentTrackPoint.x
        let dy = targetPoint.y - currentTrackPoint.y
        rotation = atan2(dy, dx) - .pi / 2

    // CPU SPEED: personality variation + rubber banding
    // Make deterministic bias larger so CPUs differ relatively faster
    let deterministicBias = 1.0 + (CGFloat(player.playerNumber) * 0.005)
    // Slightly larger per-frame jitter to create more visible variation
    let perFrameJitter = CGFloat.random(in: -0.03...0.03)
    let speed = baseSpeed * cpuPersonality * speedMultiplier * deterministicBias * (1.0 + perFrameJitter)

        // Move UPWARD with speed (always positive Y direction)
        velocity.dx = 0  // No horizontal drift
        velocity.dy = speed  // Only move upward!

        // No drag - direct speed control
    }
}

// MARK: - Track Generation

struct TrackPoint {
    var position: CGPoint
    var width: CGFloat
}

class TrackGenerator {
    static func generateRacingTrack(length: CGFloat, width: CGFloat) -> [TrackPoint] {
        var points: [TrackPoint] = []

        let segmentCount = 150  // Smooth fluid path
        let segmentHeight = length / CGFloat(segmentCount)

        var currentX: CGFloat = 0
        var currentWidth = width

        for i in 0...segmentCount {
            let y = CGFloat(i) * segmentHeight
            let t = CGFloat(i) / CGFloat(segmentCount)  // 0 to 1

            // SMOOTH WAVY PATH - gentler curves so lanes don't bend strongly to one side
            // Reduce amplitudes and bias toward center to keep the track mostly vertical
            let wave1 = sin(t * 3.0) * 120           // Main wave pattern (reduced)
            let wave2 = cos(t * 6.0 + 1.0) * 60      // Secondary wave (reduced)
            let wave3 = sin(t * 9.0 + 3.0) * 30      // Small variation (reduced)

            var rawX = wave1 + wave2 + wave3
            // Bias toward center (dampen lateral movement)
            currentX = rawX * 0.45

            // Consistent width (simpler track)
            currentWidth = width

            points.append(TrackPoint(position: CGPoint(x: currentX, y: y), width: currentWidth))
        }

        return points
    }

    static func generateObstacles(along trackPoints: [TrackPoint], count: Int) -> [CGRect] {
        var obstacles: [CGRect] = []

        guard trackPoints.count > count else { return [] }

        for i in 0..<count {
            let index = (trackPoints.count / count) * i + Int.random(in: 0...10)
            guard index < trackPoints.count else { continue }

            let point = trackPoints[index]
            let obstacleWidth = CGFloat.random(in: 40...80)
            let obstacleHeight = CGFloat.random(in: 40...80)

            // Random position within track width
            let offsetX = CGFloat.random(in: -point.width/3...point.width/3)

            let obstacle = CGRect(
                x: point.position.x + offsetX - obstacleWidth/2,
                y: point.position.y - obstacleHeight/2,
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
    let position: CGPoint
    let width: CGFloat
    var passed: Bool = false
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
    var trackPoints: [TrackPoint] = []
    var obstacles: [CGRect] = []

    var raceStartTime: TimeInterval? = nil
    var currentTime: TimeInterval = 0

    let trackLength: CGFloat = 30000  // MUCH longer track for ~90s total race
    // Increase track width for high-res displays and wider lanes (makes lanes much more spread out)
    let trackWidth: CGFloat = 1400  // Wider track for 4k / mac screens

    func addPlayer(_ player: Player) {
        players.append(player)
    }

    func initializeRace() {
        // Generate track
        trackPoints = TrackGenerator.generateRacingTrack(length: trackLength, width: trackWidth)

        // NO OBSTACLES - removed for cleaner racing!
        obstacles = []

        // Create racers at starting line - SEPARATE LANES so they don't overlap!
        let startY: CGFloat = 100
        let startTrackPoint = trackPoints.first ?? TrackPoint(position: .zero, width: trackWidth)

    // Assign each racer to a lane (horizontal offset)
    // Use consistent lane width based on the track width so lane dividers and racers line up.
    let lanes = max(players.count, 8)
    let laneWidth: CGFloat = trackWidth / CGFloat(lanes)
    let totalLaneWidth = CGFloat(lanes - 1) * laneWidth
    let startLaneOffset = -totalLaneWidth / 2

        for (index, player) in players.enumerated() {
            // Each racer gets their own lane offset from center
            let laneOffset = startLaneOffset + CGFloat(index) * laneWidth

            // Start at track centerline + lane offset
            let startPos = CGPoint(
                x: startTrackPoint.position.x + laneOffset,
                y: startY
            )

            let racer = Racer(player: player, startPosition: startPos, laneOffset: laneOffset)
            racers.append(racer)

            print("🏁 P\(player.playerNumber) assigned lane \(index + 1) (offset: \(Int(laneOffset)))")
        }

    // Checkpoints ~30 SECONDS APART (baseSpeed 300 * 30s = 9000 units)
        // For 30000 length = 3 checkpoints (at ~10k, ~20k, ~30k)
        let checkpointInterval: CGFloat = 10000  // ~30 seconds at base speed
        for i in 0..<2 {
            let y = checkpointInterval * CGFloat(i + 1)
            let trackPoint = trackPoints.first { $0.position.y >= y } ?? trackPoints.last!
            let checkpoint = Checkpoint(id: i, position: CGPoint(x: trackPoint.position.x, y: y), width: trackWidth)
            checkpoints.append(checkpoint)
        }

        // Finish line at end
        let finishPoint = trackPoints.last!
        checkpoints.append(Checkpoint(id: 2, position: CGPoint(x: finishPoint.position.x, y: trackLength), width: trackWidth))
    }

    func activeRacers() -> [Racer] {
        return racers.filter { !$0.player.isEliminated }
    }

    func checkCheckpoints() -> [Player]? {
        var eliminated: [Player] = []

        for checkpoint in checkpoints where !checkpoint.passed {
            let racersAtCheckpoint = activeRacers().filter { racer in
                racer.position.y >= checkpoint.position.y && racer.lastCheckpointPassed < checkpoint.id
            }

            if !racersAtCheckpoint.isEmpty {
                // Mark checkpoint as passed for these racers
                for racer in racersAtCheckpoint {
                    racer.lastCheckpointPassed = checkpoint.id
                }

                // Prevent double-processing of this checkpoint in subsequent frames
                // by marking it passed (so we only eliminate at most one player here).
                // This ensures a single elimination per checkpoint crossing event.
                if let idx = checkpoints.firstIndex(where: { $0.id == checkpoint.id }) {
                    checkpoints[idx].passed = true
                }

                // Find last place racers (within epsilon), eliminate only ONE at random
                let active = activeRacers()
                guard let minY = active.map({ $0.position.y }).min() else { continue }
                let epsilon: CGFloat = 20  // consider ties within 20 pts
                let tiedLast = active.filter { abs($0.position.y - minY) <= epsilon }
                if let loser = tiedLast.randomElement() {
                    loser.player.isEliminated = true
                    eliminated.append(loser.player)
                }
            }
        }

        return eliminated.isEmpty ? nil : eliminated
    }
}

