//
//  GameCoordinator.swift
//  GoonHacksGame
//
//  Manages game flow and scene transitions
//

import SpriteKit

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

        // Set up motion controllers for human players
        setupMotionControllers(for: players)

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
        for player in players {
            if case .human(let deviceId) = player.type {
                let controller = MotionController()
                controller.player = player

                // Start AirPods motion
                controller.start(controlType: .airPods)

                motionControllers[deviceId] = controller

                print("🎮 Motion controller started for \(player.name)")
            }
        }
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
