//
//  TitleScene.swift
//  GoonHacksGame
//
//  Created by Jules on 11/9/25.
//

import SpriteKit

class TitleScene: SKScene {

    // MARK: - Properties

    var gameCoordinator: GameCoordinator!

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        setupScene()
        setupUI()
    }

    // MARK: - Setup

    private func setupScene() {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)
        scaleMode = .aspectFit
    }

    private func setupUI() {
        // Title
        let titleLabel = SKLabelNode(text: "GO ON RACER")
        titleLabel.fontSize = 96
        titleLabel.fontName = "SF Pro"
        titleLabel.fontColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1.0)
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100)
        titleLabel.zPosition = 100
        addChild(titleLabel)

        // Animation
        let scaleUp = SKAction.scale(to: 1.1, duration: 1.0)
        let scaleDown = SKAction.scale(to: 1.0, duration: 1.0)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        titleLabel.run(SKAction.repeatForever(pulse))

        // Start button
        let startButton = SKLabelNode(text: "Click to Start")
        startButton.fontSize = 36
        startButton.fontName = "SF Pro"
        startButton.fontColor = .white
        startButton.position = CGPoint(x: size.width / 2, y: size.height / 2 - 100)
        startButton.zPosition = 100
        startButton.name = "startButton"
        addChild(startButton)
    }

    // MARK: - Input Handling

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let clickedNode = atPoint(location)

        if clickedNode.name == "startButton" {
            gameCoordinator.showLobby()
        }
    }
}
