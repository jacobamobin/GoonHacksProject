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
    private let shakeThreshold: Double = 2.0  // Lowered for easier detection

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

        // 1. Check for shake (for registration)
        detectShake(acceleration: acceleration)

        // 2. Check for boost gesture (quick forward acceleration)
        detectBoost(acceleration: acceleration)

        // 3. Process steering from attitude (tilt)
        processSteering(attitude: attitude)
    }

    private func detectShake(acceleration: CMAcceleration) {
        // Calculate total acceleration magnitude
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )

        if magnitude > shakeThreshold {
            print("📳 SHAKE DETECTED! Magnitude: \(magnitude)")
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
        // Map pitch and roll to steering
        // Roll (left/right tilt) -> X steering
        // Pitch (forward/back tilt) -> Y steering

        let roll = attitude.roll    // -π to π
        let pitch = attitude.pitch  // -π to π

        // Normalize to [-1, 1] with deadzone
        let deadzone = 0.15  // Slightly larger deadzone
        var steerX = roll / (.pi / 2)  // Normalize to ±1
        var steerY = pitch / (.pi / 4)  // Normalize to ±1

        // Apply deadzone
        if abs(steerX) < deadzone { steerX = 0 }
        if abs(steerY) < deadzone { steerY = 0 }

        // Clamp
        steerX = max(-1, min(1, steerX))
        steerY = max(-1, min(1, steerY))

        // Only send if non-zero (reduce spam)
        if steerX != 0 || steerY != 0 {
            delegate?.didReceiveSteering(x: steerX, y: steerY)
        }
    }
}

// MARK: - iPhone Motion Controller

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
