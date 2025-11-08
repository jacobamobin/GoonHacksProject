//
//  ViewController.swift
//  GoonHacksGame
//
//  Created by Jacob Mobin on 11/8/25.
//

import Cocoa
import SpriteKit
import GameplayKit

class ViewController: NSViewController {

    @IBOutlet var skView: SKView!

    var gameCoordinator: GameCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure SKView
        if let view = self.skView {
            view.ignoresSiblingOrder = true
            view.showsFPS = true
            view.showsNodeCount = true
            view.showsPhysics = false
        }

        // Create game coordinator
        gameCoordinator = GameCoordinator(view: skView)

        // Load tracklets before starting
        TrackletLoader.shared.loadTracklets()

        // Show lobby
        gameCoordinator?.showLobby()

        print("✅ Game coordinator initialized")
    }
}

