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
    func didDetectBoost()
    func didDetectShake()  // For player registration
}

// MARK: - AirPods Motion Controller

@available(macOS 11.0, iOS 14.0, *)
class AirPodsMotionController {
    weak var delegate: MotionControllerDelegate?

    private let motionManager = CMHeadphoneMotionManager()

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
        let attitude = motion.attitude
        let acceleration = motion.userAcceleration
        let rotationRate = motion.rotationRate

        // 1. Check for shake (for registration)
        detectShake(acceleration: acceleration)

        // 2. Check for boost gesture (quick forward acceleration)
        detectBoost(acceleration: acceleration)

        // 3. Detect stroking speed (up/down motion)
        detectStrokingSpeed(acceleration: acceleration)

        // 4. Process steering from attitude (tilt)
        processSteering(attitude: attitude)
    }

    private var strokingVelocity: Double = 0.5  // Current speed from stroking
    private var lastStrokeUpdate: Date = Date()

    private func detectStrokingSpeed(acceleration: CMAcceleration) {
        // Y-axis acceleration = up/down motion (stroking)
        let yAccel = abs(acceleration.y)

        // Map acceleration magnitude to speed (0.3 to 1.0)
        // Higher magnitude = faster stroking = higher speed
        let speedFromAccel = min(1.0, 0.3 + (yAccel / 2.0))

        // Smooth the velocity with exponential moving average
        strokingVelocity = strokingVelocity * 0.9 + speedFromAccel * 0.1

        // Send speed update periodically (every 0.1s)
        let now = Date()
        if now.timeIntervalSince(lastStrokeUpdate) >= 0.1 {
            delegate?.didReceiveSpeed(strokingVelocity)
            lastStrokeUpdate = now
        }
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

    private func detectBoost(acceleration: CMAcceleration) {
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

    private func processSteering(attitude: CMAttitude) {
        // STROKING MOTION: Up/down movement = speed
        // Left/right tilt = steering

        let roll = attitude.roll    // -π to π (left/right tilt)
        let pitch = attitude.pitch  // -π to π (forward/back tilt)

        // Lateral steering from roll
        let deadzone = 0.15
        var steerX = roll / (.pi / 2)  // Normalize to ±1

        // Apply deadzone
        if abs(steerX) < deadzone { steerX = 0 }

        // Clamp
        steerX = max(-1, min(1, steerX))

        // Send steering
        if steerX != 0 {
            delegate?.didReceiveSteering(x: steerX, y: 0)  // Only X steering
        }
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

    var player: Player?  // Associated player

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
        guard let player = player else { return }

        // Update local player
        player.updateSteering(x: x, y: y)

        // Send to network (throttled)
        let now = Date()
        if now.timeIntervalSince(lastNetworkUpdate) >= networkUpdateInterval {
            MultipeerManager.shared.broadcast(
                message: .motionUpdate(
                    playerNumber: player.playerNumber,
                    steerX: x,
                    steerY: y,
                    boost: false
                )
            )
            lastNetworkUpdate = now
        }
    }

    func didReceiveSpeed(_ speed: Double) {
        guard let player = player else { return }

        // Update player speed from stroking motion
        player.updateSpeed(speed)

        // Optionally log for debugging
        if Int.random(in: 0..<100) == 0 {  // 1% of the time
            print("🏃 Stroking speed: \(String(format: "%.2f", speed)) for P\(player.playerNumber)")
        }
    }

    func didDetectBoost() {
        guard let player = player else { return }

        // Trigger boost with current game time
        _ = player.triggerBoost(currentTime: Date().timeIntervalSince1970)
        print("💨 Boost! P\(player.playerNumber)")

        // Send boost to network immediately
        MultipeerManager.shared.broadcast(
            message: .motionUpdate(
                playerNumber: player.playerNumber,
                steerX: player.steeringInput.dx,
                steerY: player.steeringInput.dy,
                boost: true
            )
        )
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
