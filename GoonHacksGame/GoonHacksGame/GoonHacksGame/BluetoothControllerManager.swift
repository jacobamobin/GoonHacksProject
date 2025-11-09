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

    // CoreMotion managers (one per device if possible)
    #if !os(macOS)
    private var primaryMotionManager: CMMotionManager?
    #endif
    private var headphoneManagers: [CMHeadphoneMotionManager] = []

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
        if #available(macOS 11.0, iOS 14.0, *) {
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

    @available(macOS 11.0, iOS 14.0, *)
    private func connectToAvailableHeadphones() {
        // Create motion manager for primary AirPods
        let manager = CMHeadphoneMotionManager()

        if manager.isDeviceMotionAvailable {
            let deviceId = "airpods_primary"
            let device = ControllerDevice(id: deviceId, name: "AirPods")

            // Motion smoothing buffers (captured in closure)
            var recentAccels: [Double] = []
            var smoothedSpeed: Double = 1.0  // Start at 1.0 (normal speed)

            // Start motion updates - SIMPLIFIED for better control
            manager.startDeviceMotionUpdates(to: .main) { [weak self, weak device] motion, error in
                guard let self = self, let device = device, let motion = motion else { return }

                // --- STROKING SPEED (ANY MOTION IN ANY DIRECTION) ---
                let accel = motion.userAcceleration
                let totalAccel = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)

                // Fast smoothing (keep last 3 readings)
                recentAccels.append(totalAccel)
                if recentAccels.count > 3 {
                    recentAccels.removeFirst()
                }
                let avgAccel = recentAccels.reduce(0, +) / Double(recentAccels.count)

                // BALANCED SPEED: At rest slower than fast CPUs, shaking beats everyone
                // No motion = 0.75x (slower than fast CPUs 1.1x), max shaking = 1.3x
                let rawSpeed: Double
                if avgAccel < 0.15 {
                    rawSpeed = 0.75  // At rest = slower than fast CPUs, competitive with medium CPUs
                } else {
                    // ANY motion adds boost - 0.15G to 0.8G gives 0.75x to 1.3x
                    // 0.15G = start of bonus, 0.8G+ = full 55% bonus (0.75 + 0.55 = 1.3)
                    let bonus = min(0.55, (avgAccel - 0.15) * 0.85)
                    rawSpeed = 0.75 + bonus
                }

                // Very light smoothing for responsiveness
                smoothedSpeed = smoothedSpeed * 0.6 + rawSpeed * 0.4
                device.strokingSpeed = smoothedSpeed

                // --- STEERING (ONLY FROM TILT, NOT MOTION) ---
                // gravity.x = tilt orientation (-1 left, +1 right)
                let gravityX = motion.gravity.x
                let deadzone = 0.05  // Very small deadzone
                var steerX: Double

                if abs(gravityX) < deadzone {
                    steerX = 0.0
                } else {
                    // Much stronger amplification for responsive steering
                    steerX = gravityX * 3.0  // Increased from 2.0
                    steerX = max(-1.0, min(1.0, steerX))
                }

                device.tiltSteering = steerX
                device.lastMotionUpdate = Date()
                device.isConnected = true

                // Notify delegate
                self.delegate?.didReceiveMotion(
                    from: device.id,
                    strokingSpeed: smoothedSpeed,
                    steering: steerX
                )
            }

            device.isConnected = true
            devices.append(device)
            headphoneManagers.append(manager)

            print("✅ Connected to primary AirPods (improved sensitivity)")
        }
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

    func updateDeviceMotion(deviceId: String, strokingSpeed: Double, steering: Double) {
        guard let device = devices.first(where: { $0.id == deviceId }) else { return }

        device.strokingSpeed = strokingSpeed
        device.tiltSteering = steering
        device.lastMotionUpdate = Date()

        delegate?.didReceiveMotion(from: deviceId, strokingSpeed: strokingSpeed, steering: steering)
    }

    // MARK: - Cleanup

    func disconnectAll() {
        for manager in headphoneManagers {
            manager.stopDeviceMotionUpdates()
        }

        headphoneManagers.removeAll()
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
    func didReceiveMotion(from deviceId: String, strokingSpeed: Double, steering: Double)
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
