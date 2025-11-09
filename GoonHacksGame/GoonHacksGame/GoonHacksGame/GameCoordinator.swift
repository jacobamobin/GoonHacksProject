//
//  GameCoordinator.swift
//  GoonHacksGame
//
//  Manages game flow and scene transitions
//

import SpriteKit
import AVFoundation

class GameCoordinator {
    weak var view: SKView?

    private var currentScene: SKScene?
    private var lobbyScene: LobbyScene?
    private var photoCaptureScene: PhotoCaptureScene?
    private var raceScene: RaceGameScene?

    // Motion controllers per player
    private var motionControllers: [String: MotionController] = [:]  // deviceId: controller

    init(view: SKView) {
        self.view = view
    }

    // MARK: - Scene Management

    func showLobby() {
        guard let view = view else { return }

        // Create lobby scene
        lobbyScene = LobbyScene(size: CGSize(width: 1920, height: 1080))
        lobbyScene?.gameCoordinator = self
        lobbyScene?.scaleMode = .aspectFit

        // Present
        view.presentScene(lobbyScene)
        currentScene = lobbyScene

        // Set up as MultipeerManager delegate
        MultipeerManager.shared.delegate = lobbyScene

        print("✅ Lobby scene loaded")
    }

    func startPhotoCapture(with players: [Player]) {
        guard let view = view else { return }

        // Check if there are any human players
        let humanPlayers = players.filter { !$0.isCPU }

        if humanPlayers.isEmpty {
            // No human players, skip photo capture and go straight to race
            print("⚠️ No human players, skipping photo capture")
            startRace(with: players)
            return
        }

        // If the app does not have camera authorization, skip photo capture
        // to avoid prompting the user for permission and interrupting gameplay.
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus != .authorized {
            print("⚠️ Camera not authorized (status=\(authStatus)). Skipping photo capture")
            startRace(with: players)
            return
        }

        print("📸 Transitioning to photo capture for \(humanPlayers.count) players")

        // Create photo capture scene
        photoCaptureScene = PhotoCaptureScene(size: CGSize(width: 1920, height: 1080))
        photoCaptureScene?.gameCoordinator = self
        photoCaptureScene?.scaleMode = .aspectFit
        photoCaptureScene?.players = players

        // Transition
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(photoCaptureScene!, transition: transition)
        currentScene = photoCaptureScene

        print("✅ Photo capture scene loaded")
    }

    func startRace(with players: [Player]) {
        guard let view = view else { return }

        print("🏁 Transitioning to race with \(players.count) players")

        // Create race scene
        raceScene = RaceGameScene(size: CGSize(width: 1920, height: 1080))
        raceScene?.gameCoordinator = self
        raceScene?.scaleMode = .aspectFit

        // Initialize game state with players
        raceScene?.initializeGame(with: players)

        // NOTE: motion controllers will be started when the race actually begins
        // (after the countdown) to avoid applying motion before the race starts.
        // RaceGameScene.startRace() will call `startMotionControllers(for:)` on
        // the coordinator when it sets the race start time.

        // Transition
        let transition = SKTransition.fade(withDuration: 1.0)
        view.presentScene(raceScene!, transition: transition)
        currentScene = raceScene

        // Set race scene as delegate
        MultipeerManager.shared.delegate = raceScene

        print("✅ Race scene loaded")
    }

    func returnToLobby() {
        // Clean up motion controllers
        for (_, controller) in motionControllers {
            controller.stop()
        }
        motionControllers.removeAll()

        // Show lobby
        showLobby()
    }

    // MARK: - Motion Control Setup

    private func setupMotionControllers(for players: [Player]) {
        // SHARED AIRPODS SUPPORT: Multiple players can use the same AirPods (they move together!)
        // This allows "co-op" mode where 2 players wear the same AirPods and race as a team
        var sharedControllers: [String: MotionController] = [:]

        for player in players {
            if case .human(let deviceId) = player.type {
                // If this is an AirPod device, prefer the centralized
                // BluetoothControllerManager on platforms where it provides
                // motion data (iOS). On macOS the Bluetooth manager uses a
                // stub and does not provide accelerometer updates, so we
                // create a local MotionController instead to read from
                // the headphone motion or device motion APIs.
                #if !os(macOS)
                if deviceId.hasPrefix("airpod_") {
                    print("🎮 Using BluetoothControllerManager for \(player.name) (device: \(deviceId))")
                    continue
                }
                #else
                // On macOS, fall through and create a MotionController for AirPods
                // so that SPM and stroking speed are available.
                #endif

                // Check if we already have a controller for this deviceId
                if let existingController = sharedControllers[deviceId] {
                    // Share the controller - add this player to the controller's player list
                    existingController.players.append(player)
                    motionControllers[player.id] = existingController
                    print("🎮 Shared motion controller with \(player.name) (co-op mode! Now \(existingController.players.count) players)")
                } else {
                    // Create new controller for non-AirPod devices (e.g. networked iOS)
                    let controller = MotionController()
                    
                    // Assign ear side based on deviceId for independent control
                    if deviceId == "airpod_left" {
                        controller.earSide = .left
                    } else if deviceId == "airpod_right" {
                        controller.earSide = .right
                    }

                    controller.player = player
                    controller.players = [player]  // Initialize with first player

                    // Start appropriate motion controller
                    if let controlType = player.controlType {
                        controller.start(controlType: controlType)
                    } else {
                        controller.start(controlType: .airPods)  // Default
                    }

                    motionControllers[player.id] = controller
                    sharedControllers[deviceId] = controller

                    print("🎮 Motion controller started for \(player.name) (\(player.controlType == .airPods ? "AirPods" : "iPhone"))")
                }
            }
        }
    }

    // Public entrypoint used by RaceGameScene when the race actually starts.
    // Motion controllers are intentionally started only after the countdown
    // finishes so players/CPUs don't react before the race begins.
    func startMotionControllers(for players: [Player]) {
        setupMotionControllers(for: players)
    }

    // MARK: - Motion Updates from Network

    func handleMotionUpdate(playerNumber: Int, steerX: Double, steerY: Double, boost: Bool) {
        // Forward to race scene
        raceScene?.handleRemoteMotionUpdate(
            playerNumber: playerNumber,
            steerX: steerX,
            steerY: steerY,
            boost: boost
        )
    }
}

