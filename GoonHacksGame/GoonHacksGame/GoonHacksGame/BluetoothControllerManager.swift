//
//  BluetoothControllerManager.swift
//  GoonHacksGame
//
//  Manages multiple Bluetooth devices as individual controllers
//  Each device = one player with accelerometer-based stroking control
//

import Foundation
import CoreMotion
import CoreBluetooth
import Combine

// MARK: - Controller Device

class ControllerDevice: Identifiable {
    let id: String  // Unique device identifier
    let name: String
    var motionController: MotionController?
    var isConnected: Bool = false
    var lastMotionUpdate: Date = Date()

    // Motion state (simplified to accelerometer only)
    var strokingSpeed: Double = 0.5  // 0-1 range
    var tiltSteering: Double = 0.0   // -1 to 1

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Bluetooth Controller Manager

class BluetoothControllerManager: NSObject, ObservableObject {
    static let shared = BluetoothControllerManager()

    // Connected devices
    @Published var devices: [ControllerDevice] = []

    // Delegate for motion updates
    weak var delegate: BluetoothControllerDelegate?

    // Motion manager for iOS/iPadOS, not available on macOS
    #if !os(macOS)
    private let motionManager = CMMotionManager()
    #endif

    // Per-side SPM/smoothing state
    private var leftRecentAccels: [Double] = []
    private var rightRecentAccels: [Double] = []
    private var leftStrokeTimestamps: [Date] = []
    private var rightStrokeTimestamps: [Date] = []
    private var leftWasAboveThreshold: Bool = false
    private var rightWasAboveThreshold: Bool = false
    private var leftLastPeak: Date = Date()
    private var rightLastPeak: Date = Date()
    private var leftSmoothedSpeed: Double = 0.75
    private var rightSmoothedSpeed: Double = 0.75

    // Bluetooth central for device discovery
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [CBPeripheral] = []

    private override init() {
        super.init()
        setupBluetooth()
    }

    // MARK: - Setup

    private func setupBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: .main)
        print("📱 Bluetooth Controller Manager initialized")
    }

    // MARK: - Device Management

    func startDiscovery() {
        print("🔍 Starting Bluetooth device discovery...")

        // Try to connect to available headphone motion
        if #available(iOS 14.0, *) {
            connectToAvailableHeadphones()
        }

        // Also scan for other Bluetooth devices
        if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func stopDiscovery() {
        centralManager?.stopScan()
        print("⏹ Stopped Bluetooth discovery")
    }

    // MARK: - Headphone / Accelerometer setup

    // We use accelerometer/device motion on iOS. On macOS a stub is used.
    @available(iOS 14.0, *)
    private func connectToAvailableHeadphones() {
        #if os(macOS)
        print("⚠️ Motion control not available on macOS")
        return
        #else
        // Check accelerometer availability on iOS devices
        guard motionManager.isAccelerometerAvailable else {
            print("⚠️ Accelerometer not available")
            return
        }

        // Avoid adding duplicate device entries
        if devices.first(where: { $0.id == "airpod_left" }) == nil {
            devices.append(ControllerDevice(id: "airpod_left", name: "AirPod L"))
        }
        if devices.first(where: { $0.id == "airpod_right" }) == nil {
            devices.append(ControllerDevice(id: "airpod_right", name: "AirPod R"))
        }

        motionManager.accelerometerUpdateInterval = 1.0 / 60.0  // 60Hz updates

        // Start accelerometer updates and map to both left/right devices independently
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }

            // Magnitude of acceleration
            let magnitude = sqrt(data.acceleration.x * data.acceleration.x +
                                 data.acceleration.y * data.acceleration.y +
                                 data.acceleration.z * data.acceleration.z)

            // Steering from X axis tilt (-1..1)
            let tilt = max(-1.0, min(1.0, data.acceleration.x * 3.0))

            // Attribute motion to left or right based on tilt sign to avoid shared SPM
            // Lower threshold to be more sensitive to light stroking motions.
            let peakThreshold = 0.18
            let now = Date()

            var leftSPM: Double = 0.0
            var rightSPM: Double = 0.0

            // If user is tilting left, attribute strokes to left device; tilt right -> right device
            if tilt < -0.1 {
                // LEFT active
                self.leftRecentAccels.append(magnitude)
                if self.leftRecentAccels.count > 5 { self.leftRecentAccels.removeFirst() }
                let avg = self.leftRecentAccels.reduce(0, +) / Double(self.leftRecentAccels.count)

                // Peak detection for left
                if avg >= peakThreshold && !self.leftWasAboveThreshold {
                    self.leftWasAboveThreshold = true
                    if now.timeIntervalSince(self.leftLastPeak) > 0.1 {
                        self.leftStrokeTimestamps.append(now)
                        self.leftLastPeak = now
                        if self.leftStrokeTimestamps.count > 20 { self.leftStrokeTimestamps.removeFirst() }
                        if self.leftStrokeTimestamps.count >= 2 {
                            let timeWindow = now.timeIntervalSince(self.leftStrokeTimestamps.first!)
                            if timeWindow > 0 {
                                leftSPM = Double(self.leftStrokeTimestamps.count - 1) / timeWindow * 60.0
                                // Debug: log computed left SPM
                                if Int(leftSPM) > 0 {
                                    print("🔔 Left SPM computed: \(Int(leftSPM)) (avgAccel=\(String(format: "%.3f", avg)))")
                                }
                            }
                        }
                    }
                } else if avg < peakThreshold {
                    self.leftWasAboveThreshold = false
                }

                // Speed mapping for left
                let rawLeftSpeed: Double = avg < 0.15 ? 0.75 : min(1.3, 0.75 + min(0.55, (avg - 0.15) * 0.85))
                self.leftSmoothedSpeed = self.leftSmoothedSpeed * 0.6 + rawLeftSpeed * 0.4

                // Right side decays to baseline
                self.rightRecentAccels.removeAll()
                self.rightWasAboveThreshold = false
                self.rightSmoothedSpeed = max(0.75, self.rightSmoothedSpeed * 0.95)

            } else if tilt > 0.1 {
                // RIGHT active
                self.rightRecentAccels.append(magnitude)
                if self.rightRecentAccels.count > 5 { self.rightRecentAccels.removeFirst() }
                let avg = self.rightRecentAccels.reduce(0, +) / Double(self.rightRecentAccels.count)

                // Peak detection for right
                if avg >= peakThreshold && !self.rightWasAboveThreshold {
                    self.rightWasAboveThreshold = true
                    if now.timeIntervalSince(self.rightLastPeak) > 0.1 {
                        self.rightStrokeTimestamps.append(now)
                        self.rightLastPeak = now
                        if self.rightStrokeTimestamps.count > 20 { self.rightStrokeTimestamps.removeFirst() }
                        if self.rightStrokeTimestamps.count >= 2 {
                            let timeWindow = now.timeIntervalSince(self.rightStrokeTimestamps.first!)
                            if timeWindow > 0 {
                                rightSPM = Double(self.rightStrokeTimestamps.count - 1) / timeWindow * 60.0
                                // Debug: log computed right SPM
                                if Int(rightSPM) > 0 {
                                    print("🔔 Right SPM computed: \(Int(rightSPM)) (avgAccel=\(String(format: "%.3f", avg)))")
                                }
                            }
                        }
                    }
                } else if avg < peakThreshold {
                    self.rightWasAboveThreshold = false
                }

                // Speed mapping for right
                let rawRightSpeed: Double = avg < 0.15 ? 0.75 : min(1.3, 0.75 + min(0.55, (avg - 0.15) * 0.85))
                self.rightSmoothedSpeed = self.rightSmoothedSpeed * 0.6 + rawRightSpeed * 0.4

                // Left side decays to baseline
                self.leftRecentAccels.removeAll()
                self.leftWasAboveThreshold = false
                self.leftSmoothedSpeed = max(0.75, self.leftSmoothedSpeed * 0.95)

            } else {
                // No strong tilt - both relax to baseline
                self.leftRecentAccels.removeAll()
                self.rightRecentAccels.removeAll()
                self.leftWasAboveThreshold = false
                self.rightWasAboveThreshold = false
                self.leftSmoothedSpeed = max(0.75, self.leftSmoothedSpeed * 0.95)
                self.rightSmoothedSpeed = max(0.75, self.rightSmoothedSpeed * 0.95)
            }

            // Send per-device updates
            if let left = self.devices.first(where: { $0.id == "airpod_left" }) {
                // Debug: log left update
                if Int(leftSPM) == 0 {
                    // occasionally log small accel values to help debugging
                    if Int.random(in: 0..<200) == 0 {
                        print("ℹ️ Left update: speed=\(String(format: "%.2f", self.leftSmoothedSpeed)), tilt=\(String(format: "%.2f", tilt)), leftSPM=0")
                    }
                } else {
                    print("📤 Sending left motion: speed=\(String(format: "%.2f", self.leftSmoothedSpeed)), tilt=\(String(format: "%.2f", tilt)), SPM=\(Int(leftSPM))")
                }
                self.delegate?.didReceiveMotion(from: left.id, strokingSpeed: self.leftSmoothedSpeed, steering: tilt, spm: leftSPM)
            }
            if let right = self.devices.first(where: { $0.id == "airpod_right" }) {
                if Int(rightSPM) == 0 {
                    if Int.random(in: 0..<200) == 0 {
                        print("ℹ️ Right update: speed=\(String(format: "%.2f", self.rightSmoothedSpeed)), tilt=\(String(format: "%.2f", tilt)), rightSPM=0")
                    }
                } else {
                    print("📤 Sending right motion: speed=\(String(format: "%.2f", self.rightSmoothedSpeed)), tilt=\(String(format: "%.2f", tilt)), SPM=\(Int(rightSPM))")
                }
                self.delegate?.didReceiveMotion(from: right.id, strokingSpeed: self.rightSmoothedSpeed, steering: tilt, spm: rightSPM)
            }
        }

        print("✅ Started independent accelerometer tracking for AirPods")

        if devices.count > 1 {
            print("✅ Both AirPods set up for independent accelerometer tracking")
        }
        #endif
    }

    // MARK: - Add Device Manually (for testing)

    func addDevice(id: String, name: String) -> ControllerDevice {
        let device = ControllerDevice(id: id, name: name)
        device.isConnected = true
        devices.append(device)

        print("➕ Added device: \(name) (ID: \(id))")
        return device
    }

    func removeDevice(id: String) {
        devices.removeAll { $0.id == id }
        print("➖ Removed device: \(id)")
    }

    // MARK: - Motion Updates

    func updateDeviceMotion(deviceId: String, strokingSpeed: Double, steering: Double, spm: Double = 0.0) {
        guard let device = devices.first(where: { $0.id == deviceId }) else { return }

        device.strokingSpeed = strokingSpeed
        device.tiltSteering = steering
        device.lastMotionUpdate = Date()

        delegate?.didReceiveMotion(from: deviceId, strokingSpeed: strokingSpeed, steering: steering, spm: spm)
    }

    // MARK: - Cleanup

    func disconnectAll() {
        #if !os(macOS)
        motionManager.stopAccelerometerUpdates()
        #endif

        devices.removeAll()
        print("🔌 Disconnected all controllers")
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothControllerManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth powered on")
            startDiscovery()

        case .poweredOff:
            print("❌ Bluetooth powered off")

        case .unauthorized:
            print("⚠️ Bluetooth unauthorized")

        case .unsupported:
            print("❌ Bluetooth not supported")

        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Filter for relevant devices (AirPods, iPhones, etc.)
        guard let name = peripheral.name, !name.isEmpty else { return }

        // Check if we've already discovered this peripheral
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
            print("🔍 Discovered: \(name) (RSSI: \(RSSI))")

            // Auto-connect to AirPods-like devices
            if name.lowercased().contains("airpods") || name.lowercased().contains("beats") {
                print("📱 Found potential controller: \(name)")
            }
        }
    }
}

// MARK: - Delegate Protocol

protocol BluetoothControllerDelegate: AnyObject {
    func didReceiveMotion(from deviceId: String, strokingSpeed: Double, steering: Double, spm: Double)
}

// MARK: - Multi-Device Helper

extension BluetoothControllerManager {
    // Get number of connected controllers
    var connectedCount: Int {
        devices.filter { $0.isConnected }.count
    }

    // Get device by ID
    func device(withId id: String) -> ControllerDevice? {
        devices.first { $0.id == id }
    }

    // Check if device is connected
    func isDeviceConnected(id: String) -> Bool {
        device(withId: id)?.isConnected ?? false
    }
}

// MARK: - iOS Device as Controller (via MultipeerConnectivity)

extension BluetoothControllerManager {
    /// Add an iOS device connected via MultipeerConnectivity as a controller
    func addNetworkDevice(peerId: String, peerName: String) -> ControllerDevice {
        let device = ControllerDevice(id: "network_\(peerId)", name: peerName)
        device.isConnected = true
        devices.append(device)

        print("📲 Added network device: \(peerName)")
        return device
    }

    /// Update motion from network device
    func updateNetworkDeviceMotion(peerId: String, strokingSpeed: Double, steering: Double, boost: Bool) {
        let deviceId = "network_\(peerId)"
        updateDeviceMotion(deviceId: deviceId, strokingSpeed: strokingSpeed, steering: steering)
    }
}

// MARK: - Simple Accelerometer-Only Mode

#if !os(macOS)
class SimpleAccelerometerController {
    private let motionManager = CMMotionManager()
    var onMotionUpdate: ((Double, Double) -> Void)?

    // Smoothing buffers
    private var recentAccels: [Double] = []
    private var smoothedSpeed: Double = 0.5

    init() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            print("❌ Device motion not available")
            return
        }

        // Use DeviceMotion for better data (includes gravity separation)
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            // --- STROKING SPEED (from userAcceleration.y) ---
            let yAccel = abs(motion.userAcceleration.y)

            // Smooth accelerations
            self.recentAccels.append(yAccel)
            if self.recentAccels.count > 5 {
                self.recentAccels.removeFirst()
            }
            let avgAccel = self.recentAccels.reduce(0, +) / Double(self.recentAccels.count)

            // Map to speed with improved sensitivity
            let rawSpeed: Double
            if avgAccel < 0.05 {
                rawSpeed = 0.3
            } else if avgAccel < 0.5 {
                rawSpeed = 0.3 + (avgAccel / 0.5) * 0.7
            } else {
                rawSpeed = 1.0 + min(0.3, (avgAccel - 0.5) * 0.6)
            }

            // Smooth speed
            self.smoothedSpeed = self.smoothedSpeed * 0.7 + rawSpeed * 0.3

            // --- STEERING (from gravity.x) ---
            let gravityX = motion.gravity.x
            let deadzone = 0.15
            var steerX: Double

            if abs(gravityX) < deadzone {
                steerX = 0.0
            } else {
                if gravityX > 0 {
                    steerX = (gravityX - deadzone) / (1.0 - deadzone)
                } else {
                    steerX = (gravityX + deadzone) / (1.0 - deadzone)
                }
                steerX = max(-1.0, min(1.0, steerX))
                let sign = steerX < 0 ? -1.0 : 1.0
                steerX = sign * pow(abs(steerX), 0.7)
            }

            self.onMotionUpdate?(self.smoothedSpeed, steerX)
        }

        print("✅ iOS accelerometer started (improved sensitivity)")
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}
#else
// macOS stub - CMMotionManager not available on macOS
class SimpleAccelerometerController {
    var onMotionUpdate: ((Double, Double) -> Void)?
    
    init() {}
    
    func start() {
        print("⚠️ SimpleAccelerometerController not available on macOS")
        print("   Use AirPods Pro/Max for motion control on macOS")
    }
    
    func stop() {
        // No-op
    }
}
#endif
