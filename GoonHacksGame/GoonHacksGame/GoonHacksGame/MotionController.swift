//
//  MotionController.swift
//  GoonHacksGame
//
//  AirPods and iPhone motion control integration
//  FIXED: Now works on macOS with AirPods Pro/Max
//

import Foundation
import CoreMotion
import Combine

// MARK: - Motion Controller Protocol

protocol MotionControllerDelegate: AnyObject {
    func didReceiveSteering(x: Double, y: Double)
    func didReceiveSpeed(_ speed: Double)  // Stroking speed
    func didReceiveSPM(_ spm: Double)  // Strokes per minute
    func didDetectBoost()
    func didDetectShake()  // For player registration
}

// MARK: - Ear Side (for splitting one motion feed into two independent controllers)
enum EarSide {
    case left
    case right
}

// MARK: - AirPods Motion Controller

@available(macOS 11.0, iOS 14.0, *)
class AirPodsMotionController {
    weak var delegate: MotionControllerDelegate?

    private let motionManager = CMHeadphoneMotionManager()
    var earSide: EarSide?

    // Calibration
    private var calibrationOffset = CMAttitude()
    private var isCalibrated = false

    // Shake detection
    private var previousAcceleration: CMAcceleration?
    private let shakeThreshold: Double = 1.2  // Lowered for easier detection (shaking AirPods in hand)
    private var lastShakeTime: Date = Date()
    private let shakeDebounceInterval: TimeInterval = 0.5  // Prevent multiple detections

    // Boost detection (quick forward tilt)
    private let boostThreshold: Double = 1.5
    private var lastBoostTime: Date = Date()

    var isAvailable: Bool {
        return motionManager.isDeviceMotionAvailable
    }

    var isConnected: Bool {
        return motionManager.isDeviceMotionActive
    }

    func start() {
        guard isAvailable else {
            print("❌ AirPods motion not available")
            print("   - Make sure you have AirPods Pro or AirPods Max")
            print("   - Check they are connected via Bluetooth")
            return
        }

        // IMPORTANT: Start motion updates immediately
        // This prevents auto-disconnect when AirPods are removed from ears
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    print("❌ Motion error: \(error.localizedDescription)")
                }
                return
            }

            self.processMotion(motion)
        }

        print("✅ AirPods motion started")
        print("   - Shake your head to test detection")
        print("   - Tilt to steer, shake forward to boost")
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        print("🛑 AirPods motion stopped")
    }

    func calibrate() {
        isCalibrated = true
        print("✅ AirPods calibrated")
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        let gravity = motion.gravity
        let acceleration = motion.userAcceleration
        let tiltX = gravity.x

        // 1. Check for shake (for registration)
        detectShake(acceleration: acceleration)

        // 2. Check for boost gesture (quick forward tilt) — gate by ear side
        detectBoost(acceleration: acceleration, tiltX: tiltX)

        // 3. Detect stroking speed (up/down motion from acceleration) — gate by ear side
        detectStrokingSpeed(acceleration: acceleration, tiltX: tiltX)

        // 4. Process steering from gravity (tilt orientation) — gate by ear side
        processSteering(gravity: gravity)
    }

    // Stroking speed detection (up/down motion)
    private var strokingVelocity: Double = 0.75  // Start at 0.75x (competitive with medium CPUs)
    private var lastStrokeUpdate: Date = Date()
    private var recentAccelerations: [Double] = []  // For smoothing

    // SPM (Strokes Per Minute) tracking
    private var strokeTimestamps: [Date] = []  // Last 10 stroke peaks
    private var lastPeakTime: Date = Date()
    private var wasAboveThreshold = false

    private func detectStrokingSpeed(acceleration: CMAcceleration, tiltX: Double) {
        // Determine if this controller should be active based on tilt direction
        let active: Bool
        if let side = earSide {
            if side == .left {
                active = tiltX < -0.1
            } else {
                active = tiltX > 0.1
            }
        } else {
            active = true
        }

        // STROKING = UP/DOWN MOTION ONLY (use Y-axis)
        let totalAccel = abs(acceleration.y)

        // Simple smoothing (keep last 3 readings only for faster response)
        recentAccelerations.append(totalAccel)
        if recentAccelerations.count > 3 {
            recentAccelerations.removeFirst()
        }
        let avgAccel = recentAccelerations.reduce(0, +) / Double(recentAccelerations.count)

        // If not active, decay toward baseline and send baseline updates so inactive side doesn't mirror the active one
        if !active {
            strokingVelocity = max(0.75, strokingVelocity * 0.95)
            delegate?.didReceiveSpeed(0.75)
            delegate?.didReceiveSPM(0)
            return
        }

        // PEAK DETECTION for SPM (Strokes Per Minute)
        let peakThreshold = 0.2  // Lowered from 0.3G - motion above this counts as a stroke
        let now = Date()

        // Detect rising edge (crossing threshold)
        if avgAccel >= peakThreshold && !wasAboveThreshold {
            // New stroke detected!
            wasAboveThreshold = true

            // Debounce - ignore peaks within 0.1s of last peak
            if now.timeIntervalSince(lastPeakTime) > 0.1 {
                strokeTimestamps.append(now)
                lastPeakTime = now

                // Keep only last 20 strokes
                if strokeTimestamps.count > 20 {
                    strokeTimestamps.removeFirst()
                }

                // Calculate SPM from recent strokes and send to delegate
                if strokeTimestamps.count >= 2 {
                    let timeWindow = now.timeIntervalSince(strokeTimestamps.first!)
                    if timeWindow > 0 {
                        let spm = Double(strokeTimestamps.count - 1) / timeWindow * 60.0
                        delegate?.didReceiveSPM(spm)
                    }
                }
            }
        } else if avgAccel < peakThreshold {
            wasAboveThreshold = false
        }

        // BALANCED SPEED: At rest slower than fast CPUs, shaking beats everyone
        // No motion = 0.75x, max shaking = 1.3x
        let rawSpeed: Double
        if avgAccel < 0.15 {
            rawSpeed = 0.75
        } else {
            let bonus = min(0.55, (avgAccel - 0.15) * 0.85)
            rawSpeed = 0.75 + bonus
        }

        // Very light smoothing for responsiveness
        strokingVelocity = strokingVelocity * 0.6 + rawSpeed * 0.4

        // Debug logging (every ~1s)
        if Int.random(in: 0..<60) == 0 {
            let spm: Double
            if strokeTimestamps.count >= 2 {
                let timeWindow = now.timeIntervalSince(strokeTimestamps.first!)
                spm = timeWindow > 0 ? Double(strokeTimestamps.count - 1) / timeWindow * 60.0 : 0
            } else {
                spm = 0
            }
            print("🏃 ANY MOTION: total=\(String(format: "%.3f", avgAccel))G → speed=\(String(format: "%.2f", strokingVelocity))x, SPM=\(Int(spm)))")
        }

        // Send speed update
        delegate?.didReceiveSpeed(strokingVelocity)
    }

    private func detectShake(acceleration: CMAcceleration) {
        // Calculate total acceleration magnitude
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )

        // Debounce: prevent multiple rapid detections
        let now = Date()
        guard now.timeIntervalSince(lastShakeTime) >= shakeDebounceInterval else {
            return
        }

        // Debug: log acceleration values periodically
        if Int.random(in: 0..<60) == 0 {  // Log ~1% of the time to avoid spam
            print("📊 Motion: x=\(String(format: "%.2f", acceleration.x)), y=\(String(format: "%.2f", acceleration.y)), z=\(String(format: "%.2f", acceleration.z)), mag=\(String(format: "%.2f", magnitude))")
        }

        if magnitude > shakeThreshold {
            lastShakeTime = now
            print("📳 SHAKE DETECTED! Magnitude: \(String(format: "%.2f", magnitude)) (threshold: \(shakeThreshold))")
            print("   Acceleration: x=\(String(format: "%.2f", acceleration.x)), y=\(String(format: "%.2f", acceleration.y)), z=\(String(format: "%.2f", acceleration.z))")
            delegate?.didDetectShake()
        }

        previousAcceleration = acceleration
    }

    private func detectBoost(acceleration: CMAcceleration, tiltX: Double) {
        // Gate boost by ear side and tilt direction
        if let side = earSide {
            if side == .left && tiltX >= -0.1 { return }
            if side == .right && tiltX <= 0.1 { return }
        }
        // Detect quick forward acceleration (positive Z in headphone space)
        if acceleration.z > boostThreshold || acceleration.y > boostThreshold {
            let now = Date()
            if now.timeIntervalSince(lastBoostTime) > 1.0 {  // 1s cooldown
                print("💨 BOOST detected! Z: \(acceleration.z), Y: \(acceleration.y)")
                delegate?.didDetectBoost()
                lastBoostTime = now
            }
        }
    }

    private func processSteering(gravity: CMAcceleration) {
        // STEERING = ONLY TILT ANGLE (not motion/shaking!)
        // gravity.x shows the tilt: -1 (tilted left) to +1 (tilted right)

        let rawSteerX = gravity.x

        // Very small dead zone for responsive steering
        let deadzone = 0.05  // Reduced from 0.08
        var steerX: Double

        if abs(rawSteerX) < deadzone {
            steerX = 0.0
        } else {
            // Strong amplification for responsive steering
            steerX = rawSteerX * 3.0  // Increased from 2.0
            steerX = max(-1.0, min(1.0, steerX))  // Clamp to -1...1
        }

        // Suppress steering when this side isn't active
        if let side = earSide {
            let active = (side == .left && rawSteerX < -0.1) || (side == .right && rawSteerX > 0.1)
            if !active {
                steerX = 0.0
            }
        }

        // Debug logging (every 30 frames = ~0.5 seconds)
        if Int.random(in: 0..<30) == 0 {
            print("🎮 TILT STEERING: gravity.x=\(String(format: "%.2f", rawSteerX)) → steer=\(String(format: "%.2f", steerX))")
        }

        // Always send steering
        delegate?.didReceiveSteering(x: steerX, y: 0)
    }
}

// MARK: - iPhone Motion Controller

#if !os(macOS)
class iPhoneMotionController {
    weak var delegate: MotionControllerDelegate?

    private let motionManager = CMMotionManager()

    // Shake detection
    private var previousAcceleration: CMAcceleration?
    private let shakeThreshold: Double = 2.5

    // Boost detection
    private let boostThreshold: Double = 1.5
    private var lastBoostTime: Date = Date()

    var isAvailable: Bool {
        return motionManager.isDeviceMotionAvailable
    }

    func start() {
        guard isAvailable else {
            print("❌ iPhone motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    print("❌ Motion error: \(error)")
                }
                return
            }

            self.processMotion(motion)
        }

        print("✅ iPhone motion started")
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        print("🛑 iPhone motion stopped")
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        let attitude = motion.attitude
        let acceleration = motion.userAcceleration

        // 1. Check for shake (for registration)
        detectShake(acceleration: acceleration)

        // 2. Check for boost gesture
        detectBoost(acceleration: acceleration)

        // 3. Process steering from gyro
        processSteering(attitude: attitude)
    }

    private func detectShake(acceleration: CMAcceleration) {
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )

        if magnitude > shakeThreshold {
            delegate?.didDetectShake()
        }

        previousAcceleration = acceleration
    }

    private func detectBoost(acceleration: CMAcceleration) {
        // Detect forward shake/thrust
        if abs(acceleration.y) > boostThreshold {
            let now = Date()
            if now.timeIntervalSince(lastBoostTime) > 1.0 {
                delegate?.didDetectBoost()
                lastBoostTime = now
            }
        }
    }

    private func processSteering(attitude: CMAttitude) {
        // Map device rotation to steering
        let roll = attitude.roll
        let pitch = attitude.pitch

        // Device held in portrait, tilted left/right for X, forward/back for Y
        let deadzone = 0.15
        var steerX = roll / (.pi / 3)
        var steerY = -pitch / (.pi / 4)  // Inverted

        if abs(steerX) < deadzone { steerX = 0 }
        if abs(steerY) < deadzone { steerY = 0 }

        steerX = max(-1, min(1, steerX))
        steerY = max(-1, min(1, steerY))

        delegate?.didReceiveSteering(x: steerX, y: steerY)
    }
}
#else
// macOS stub - CMMotionManager not available on macOS
class iPhoneMotionController {
    weak var delegate: MotionControllerDelegate?
    
    var isAvailable: Bool { return false }
    
    func start() {
        print("⚠️ iPhone motion controller not available on macOS")
        print("   - Use AirPods Pro/Max for motion control on macOS")
        print("   - Or use keyboard controls (A/D for steering, W for boost)")
    }
    
    func stop() {
        // No-op
    }
}
#endif

// MARK: - Motion Controller Facade

class MotionController: MotionControllerDelegate {
    private var airPodsController: AirPodsMotionController?
    private var iPhoneController: iPhoneMotionController?

    var player: Player?  // Primary player (for backwards compatibility)
    var players: [Player] = []  // All players controlled by this device (co-op mode!)
    var earSide: EarSide?

    // Network throttling
    private var lastNetworkUpdate: Date = Date()
    private let networkUpdateInterval: TimeInterval = 1.0 / 30.0  // 30 Hz

    var isAirPodsConnected: Bool {
        if #available(macOS 11.0, iOS 14.0, *) {
            return airPodsController?.isConnected ?? false
        }
        return false
    }

    func start(controlType: ControlType) {
        switch controlType {
        case .airPods:
            if #available(macOS 11.0, iOS 14.0, *) {
                airPodsController = AirPodsMotionController()
                airPodsController?.delegate = self
                airPodsController?.earSide = earSide
                airPodsController?.start()

                // Check if actually available
                if airPodsController?.isAvailable == false {
                    print("⚠️ AirPods motion sensors not detected")
                    print("   Make sure you have AirPods Pro or AirPods Max connected")
                }
            } else {
                print("⚠️ AirPods motion requires macOS 11.0+ or iOS 14.0+")
            }

        case .iPhone:
            iPhoneController = iPhoneMotionController()
            iPhoneController?.delegate = self
            iPhoneController?.start()
        }
    }

    func stop() {
        airPodsController?.stop()
        iPhoneController?.stop()
    }

    // MARK: - MotionControllerDelegate

    func didReceiveSteering(x: Double, y: Double) {
        // Update ALL players controlled by this device (co-op mode!)
        let allPlayers = players.isEmpty ? (player.map { [$0] } ?? []) : players
        guard !allPlayers.isEmpty else { return }

        // Update all local players
        for p in allPlayers {
            p.updateSteering(x: x, y: y)
        }

        // Send to network (throttled) - only send first player's number
        let now = Date()
        if now.timeIntervalSince(lastNetworkUpdate) >= networkUpdateInterval {
            if let firstPlayer = allPlayers.first {
                MultipeerManager.shared.broadcast(
                    message: .motionUpdate(
                        playerNumber: firstPlayer.playerNumber,
                        steerX: x,
                        steerY: y,
                        boost: false
                    )
                )
            }
            lastNetworkUpdate = now
        }
    }

    func didReceiveSpeed(_ speed: Double) {
        // Update ALL players controlled by this device (co-op mode!)
        let allPlayers = players.isEmpty ? (player.map { [$0] } ?? []) : players
        guard !allPlayers.isEmpty else { return }

        // Update all players' speed from stroking motion
        for p in allPlayers {
            p.updateSpeed(speed)
        }

        // Optionally log for debugging
        if Int.random(in: 0..<100) == 0 {  // 1% of the time
            let playerNumbers = allPlayers.map { "P\($0.playerNumber)" }.joined(separator: ", ")
            print("🏃 Stroking speed: \(String(format: "%.2f", speed)) for \(playerNumbers)")
        }
    }

    func didReceiveSPM(_ spm: Double) {
        // Update ALL players controlled by this device (co-op mode!)
        let allPlayers = players.isEmpty ? (player.map { [$0] } ?? []) : players
        guard !allPlayers.isEmpty else { return }

        // Update all players' SPM
        for p in allPlayers {
            p.strokesPerMinute = spm
        }
    }

    func didDetectBoost() {
        // Update ALL players controlled by this device (co-op mode!)
        let allPlayers = players.isEmpty ? (player.map { [$0] } ?? []) : players
        guard !allPlayers.isEmpty else { return }

        let currentTime = Date().timeIntervalSince1970

        // Trigger boost for all players
        for p in allPlayers {
            _ = p.triggerBoost(currentTime: currentTime)
        }

        let playerNumbers = allPlayers.map { "P\($0.playerNumber)" }.joined(separator: ", ")
        print("💨 Boost! \(playerNumbers)")

        // Send boost to network immediately (only for first player)
        if let firstPlayer = allPlayers.first {
            MultipeerManager.shared.broadcast(
                message: .motionUpdate(
                    playerNumber: firstPlayer.playerNumber,
                    steerX: firstPlayer.steeringInput.dx,
                    steerY: firstPlayer.steeringInput.dy,
                    boost: true
                )
            )
        }
    }

    func didDetectShake() {
        print("📳 Shake detected!")

        // Notify local system
        NotificationCenter.default.post(name: .deviceShakeDetected, object: nil)

        // Send shake event to host if we have a player assigned
        if let player = player {
            MultipeerManager.shared.broadcast(
                message: .shakeDetected(deviceId: player.id)
            )
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let deviceShakeDetected = Notification.Name("deviceShakeDetected")
}

// MARK: - AirPods Detection Helper

class AirPodsDetector {
    static let shared = AirPodsDetector()

    private init() {}

    func checkAirPodsAvailability() -> (available: Bool, message: String) {
        if #available(macOS 11.0, iOS 14.0, *) {
            let manager = CMHeadphoneMotionManager()

            if manager.isDeviceMotionAvailable {
                return (true, "✅ AirPods Pro/Max detected and ready")
            } else {
                return (false, "⚠️ No AirPods motion sensors detected. Connect AirPods Pro or Max.")
            }
        } else {
            return (false, "❌ Requires macOS 11.0+ or iOS 14.0+")
        }
    }

    func startMonitoring() {
        // This keeps the connection alive even when AirPods are removed from ears
        if #available(macOS 11.0, iOS 14.0, *) {
            let manager = CMHeadphoneMotionManager()

            if manager.isDeviceMotionAvailable {
                // Start with a dummy handler to keep connection alive
                manager.startDeviceMotionUpdates(to: .main) { _, _ in
                    // No-op - just keeps the connection alive
                }

                print("✅ AirPods connection monitoring started")
                print("   - AirPods will NOT disconnect when removed from ears")
            }
        }
    }
}

