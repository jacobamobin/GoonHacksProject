//
//  GameModels.swift
//  GoonHacksGame
//
//  Core game models for Sperm Racing multiplayer
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Player

enum PlayerType {
    case human(deviceId: String)  // Connected device
    case cpu(trackletId: String)  // AI controlled by tracklet
}

enum ControlType {
    case airPods  // CMHeadphoneMotionManager
    case iPhone   // CMMotionManager (gyro)
}

class Player {
    let id: String
    let playerNumber: Int  // 1-8
    var name: String
    var type: PlayerType
    var controlType: ControlType?
    var faceImage: NSImage?  // Captured photo
    var isEliminated: Bool = false

    // Motion input state
    var steeringInput: CGVector = .zero  // -1 to 1 in x, y
    var boostInput: Bool = false
    var lastBoostTime: TimeInterval = 0

    init(id: String, playerNumber: Int, name: String, type: PlayerType) {
        self.id = id
        self.playerNumber = playerNumber
        self.name = name
        self.type = type
    }

    // Update steering from device motion
    func updateSteering(x: Double, y: Double) {
        // Clamp to [-1, 1]
        steeringInput = CGVector(
            dx: max(-1.0, min(1.0, x)),
            dy: max(-1.0, min(1.0, y))
        )
    }

    // Trigger boost (with cooldown check)
    func triggerBoost(currentTime: TimeInterval, cooldown: TimeInterval = 1.0) -> Bool {
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
    var position: CGPoint  // Current world position
    var velocity: CGVector // Current velocity
    var baseVelocity: CGVector = .zero  // From tracklet playback
    var tracklet: Tracklet?  // For CPU racers
    var trackletTime: Double = 0.0  // 0.0-1.0 normalized time

    // Visual
    var rotation: CGFloat = 0  // Sprite rotation
    var scale: CGFloat = 1.0

    // Race state
    var distanceTraveled: CGFloat = 0
    var lastCheckpointPassed: Int = -1
    var finishTime: TimeInterval?

    init(player: Player, startPosition: CGPoint) {
        self.player = player
        self.position = startPosition
        self.velocity = .zero

        // Assign tracklet for CPU players
        if case .cpu(let trackletId) = player.type {
            self.tracklet = TrackletLoader.shared.data?.tracklets.first { $0.id == trackletId }
        }
    }

    // Update physics (called each frame)
    func update(deltaTime: TimeInterval, fluidField: FluidField, weights: PhysicsWeights) {
        // 1. Get data-driven base velocity
        if let tracklet = tracklet {
            updateFromTracklet(deltaTime: deltaTime)
        }

        // 2. Apply player steering
        let playerForce = applyPlayerInput(weights: weights)

        // 3. Apply fluid forces
        let fluidForce = fluidField.vectorAt(position: position)

        // 4. Combine forces
        let totalForce = CGVector(
            dx: weights.tracklet * baseVelocity.dx +
                weights.player * playerForce.dx +
                weights.fluid * fluidForce.dx,
            dy: weights.tracklet * baseVelocity.dy +
                weights.player * playerForce.dy +
                weights.fluid * fluidForce.dy
        )

        // 5. Update velocity (with max speed clamp)
        velocity = CGVector(
            dx: totalForce.dx,
            dy: totalForce.dy
        )

        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        if speed > weights.maxSpeed {
            let scale = weights.maxSpeed / speed
            velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
        }

        // 6. Update position
        position = CGPoint(
            x: position.x + velocity.dx * deltaTime,
            y: position.y + velocity.dy * deltaTime
        )

        // 7. Update rotation to face movement direction
        if speed > 0.01 {
            rotation = atan2(velocity.dy, velocity.dx)
        }

        // 8. Track distance
        distanceTraveled += sqrt(
            velocity.dx * velocity.dx + velocity.dy * velocity.dy
        ) * deltaTime
    }

    private func updateFromTracklet(deltaTime: TimeInterval) {
        guard let tracklet = tracklet else { return }

        // Advance tracklet time (loop if needed)
        trackletTime += deltaTime / Double(tracklet.length) * 30.0  // 30 fps
        if trackletTime >= 1.0 {
            trackletTime -= 1.0
        }

        // Get velocity from tracklet
        let index = Int(trackletTime * Double(tracklet.velocities.count - 1))
        if let vel = tracklet.velocity(at: index) {
            baseVelocity = vel
        }
    }

    private func applyPlayerInput(weights: PhysicsWeights) -> CGVector {
        var force = player.steeringInput

        // Apply boost multiplier
        if player.boostInput {
            force = CGVector(dx: force.dx * 2.0, dy: force.dy * 2.0)
            player.boostInput = false  // Consume boost
        }

        return CGVector(
            dx: force.dx * weights.steerMultiplier,
            dy: force.dy * weights.steerMultiplier
        )
    }
}

// MARK: - Physics Configuration

struct PhysicsWeights {
    var tracklet: CGFloat = 0.4     // Weight of data-driven base motion
    var player: CGFloat = 0.4       // Weight of player input
    var fluid: CGFloat = 0.2        // Weight of fluid simulation
    var maxSpeed: CGFloat = 500.0   // Max speed (points per second)
    var steerMultiplier: CGFloat = 200.0  // Steering force multiplier
}

// MARK: - Fluid Field (Procedural flow field)

class FluidField {
    var viscosity: CGFloat = 0.1
    var flowIntensity: CGFloat = 50.0
    var noiseScale: CGFloat = 0.01
    var time: TimeInterval = 0

    func update(deltaTime: TimeInterval) {
        time += deltaTime
    }

    // Get flow vector at position
    func vectorAt(position: CGPoint) -> CGVector {
        // Simple Perlin-like noise for flow field
        // In production, use a proper noise library or Metal compute shader
        let noiseX = sin(position.x * noiseScale + time) * cos(position.y * noiseScale)
        let noiseY = cos(position.x * noiseScale) * sin(position.y * noiseScale + time)

        return CGVector(
            dx: noiseX * flowIntensity * (1.0 - viscosity),
            dy: noiseY * flowIntensity * (1.0 - viscosity)
        )
    }
}

// MARK: - Checkpoint

struct Checkpoint {
    let id: Int
    let yPosition: CGFloat  // Vertical position on track
    let width: CGFloat      // Track width at checkpoint
    var racersPassed: Set<String> = []  // Player IDs who passed

    func contains(position: CGPoint) -> Bool {
        return position.y >= yPosition - 20 && position.y <= yPosition + 20
    }
}

// MARK: - Game State

enum GamePhase {
    case lobby           // Waiting for players
    case registration    // Shake to claim
    case photoCapture    // Taking player photos
    case raceCountdown   // 3, 2, 1, GO!
    case racing          // Active race
    case checkpointElimination  // Showing who got knocked out
    case finished        // Race over
}

class GameState {
    var phase: GamePhase = .lobby
    var players: [Player] = []
    var racers: [Racer] = []
    var checkpoints: [Checkpoint] = []
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
    func initializeRacers(startY: CGFloat, spacing: CGFloat) {
        racers.removeAll()

        for (index, player) in players.enumerated() {
            let xPosition = CGFloat(index - players.count / 2) * spacing
            let racer = Racer(
                player: player,
                startPosition: CGPoint(x: xPosition, y: startY)
            )
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
