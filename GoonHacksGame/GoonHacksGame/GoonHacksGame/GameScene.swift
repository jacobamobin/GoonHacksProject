//
//  GameScene.swift
//  GoonHacksGame
//
//  Created by Jacob Mobin on 11/8/25.
//

import SpriteKit
import GameplayKit
import AVFoundation

class GameScene: SKScene {
    
    // Camera capture properties
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    var entities = [GKEntity]()
    var graphs = [String : GKGraph]()
    
    private var lastUpdateTime : TimeInterval = 0
    private var label : SKLabelNode?
    private var spinnyNode : SKShapeNode?
    
    override func sceneDidLoad() {
        
        self.lastUpdateTime = 0
        
        // Get label node from scene and store it for use later
        self.label = self.childNode(withName: "//helloLabel") as? SKLabelNode
        if let label = self.label {
            label.alpha = 0.0
            label.run(SKAction.fadeIn(withDuration: 2.0))
        }
        
        // Create shape node to use during mouse interaction
        let w = (self.size.width + self.size.height) * 0.05
        self.spinnyNode = SKShapeNode.init(rectOf: CGSize.init(width: w, height: w), cornerRadius: w * 0.3)
        
        if let spinnyNode = self.spinnyNode {
            spinnyNode.lineWidth = 2.5
            
            spinnyNode.run(SKAction.repeatForever(SKAction.rotate(byAngle: CGFloat(Double.pi), duration: 1)))
            spinnyNode.run(SKAction.sequence([SKAction.wait(forDuration: 0.5),
                                              SKAction.fadeOut(withDuration: 0.5),
                                              SKAction.removeFromParent()]))
        }
        
        // Center the window (macOS)
        self.view?.window?.center()

        // Prepare camera capture
        setupCameraIfNeeded()
    }
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // Ensure window is centered once view is attached
        self.view?.window?.center()
        // Prepare camera capture (ensures we have a view for preview layer)
        setupCameraIfNeeded()
    }
    
    // MARK: - Camera Setup & Capture
    private func setupCameraIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("📸 Camera auth status: \(status.rawValue)")
        switch status {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    print("📸 Camera access prompt result: granted=\(granted)")
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.showCameraDeniedLabel()
                    }
                }
            }
        default:
            showCameraDeniedLabel()
        }
    }

    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showCameraDeniedLabel()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        self.captureSession = session
        self.photoOutput = output

        // Add preview layer to show camera feed
        if let view = self.view {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            // Ensure SpriteKit content stays visible above the preview
            view.wantsLayer = true
            view.layer?.insertSublayer(layer, at: 0)
            self.previewLayer = layer
        } else {
            print("⚠️ No view available for preview layer yet")
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak session] in
            session?.startRunning()
        }
    }

    private func showCameraDeniedLabel() {
        let warn = SKLabelNode(text: "Camera access denied")
        warn.fontSize = 18
        warn.fontColor = .red
        warn.position = CGPoint(x: self.size.width/2, y: self.size.height/2)
        warn.zPosition = 999
        addChild(warn)
        warn.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.2),
            SKAction.wait(forDuration: 2.0),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    private func capturePhoto() {
        guard let photoOutput = self.photoOutput else {
            showCameraDeniedLabel()
            return
        }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func touchDown(atPoint pos : CGPoint) {
        if let n = self.spinnyNode?.copy() as! SKShapeNode? {
            n.position = pos
            n.strokeColor = SKColor.green
            self.addChild(n)
        }
    }
    
    func touchMoved(toPoint pos : CGPoint) {
        if let n = self.spinnyNode?.copy() as! SKShapeNode? {
            n.position = pos
            n.strokeColor = SKColor.blue
            self.addChild(n)
        }
    }
    
    func touchUp(atPoint pos : CGPoint) {
        if let n = self.spinnyNode?.copy() as! SKShapeNode? {
            n.position = pos
            n.strokeColor = SKColor.red
            self.addChild(n)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        self.touchDown(atPoint: event.location(in: self))
    }
    
    override func mouseDragged(with event: NSEvent) {
        self.touchMoved(toPoint: event.location(in: self))
    }
    
    override func mouseUp(with event: NSEvent) {
        self.touchUp(atPoint: event.location(in: self))
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 0x31:
            if let label = self.label {
                label.run(SKAction.init(named: "Pulse")!, withKey: "fadeInOut")
            }
        case 1: // 'S' key on macOS key map
            capturePhoto()
            return
        default:
            print("keyDown: \(event.characters!) keyCode: \(event.keyCode)")
        }
    }
    
    
    override func update(_ currentTime: TimeInterval) {
        // Called before each frame is rendered
        
        // Initialize _lastUpdateTime if it has not already been
        if (self.lastUpdateTime == 0) {
            self.lastUpdateTime = currentTime
        }
        
        // Calculate time since last update
        let dt = currentTime - self.lastUpdateTime
        
        // Update entities
        for entity in self.entities {
            entity.update(deltaTime: dt)
        }
        
        self.lastUpdateTime = currentTime
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if let view = self.view {
            previewLayer?.frame = view.bounds
        }
    }
}

extension GameScene: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = NSImage(data: data) else {
            print("Failed to get image data")
            return
        }
        // Provide quick feedback in-scene
        let saved = SKLabelNode(text: "Photo captured")
        saved.fontSize = 16
        saved.fontColor = .white
        saved.position = CGPoint(x: self.size.width/2, y: self.size.height * 0.8)
        addChild(saved)
        saved.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
        // Show captured image as a sprite for confirmation
        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: 320, height: 240)
        sprite.position = CGPoint(x: self.size.width/2, y: self.size.height/2)
        sprite.zPosition = 1000
        addChild(sprite)
        sprite.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
        print("✅ Photo captured and displayed")
        // TODO: Save `image` to disk or use it as needed
    }
}
