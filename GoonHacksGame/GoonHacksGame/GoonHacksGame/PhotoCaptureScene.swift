//
//  PhotoCaptureScene.swift
//  GoonHacksGame
//
//  Captures face photos for each human player before the race
//  Uses Vision framework for face detection and auto-capture
//

import SpriteKit
import AVFoundation
import Vision

class PhotoCaptureScene: SKScene {

    // MARK: - Properties

    var gameCoordinator: GameCoordinator?
    var players: [Player] = []

    private var currentPlayerIndex = 0
    private var capturedPhotos: [String: NSImage] = [:]

    // Camera
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureVideoDataOutput?

    // Face detection
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest!
    private var isFaceCentered = false
    private var faceStableFrames = 0
    private let requiredStableFrames = 15  // ~0.5 seconds at 30fps

    // UI
    private var instructionLabel: SKLabelNode!
    private var statusLabel: SKLabelNode!
    private var progressLabel: SKLabelNode!
    private var captureOverlay: SKShapeNode!
    private var centerGuide: SKShapeNode!

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        setupUI()
        setupFaceDetection()

        // Filter to only human players
        let humanPlayers = players.filter { !$0.isCPU }

        if humanPlayers.isEmpty {
            // No human players, skip photo capture
            print("⚠️ No human players, skipping photo capture")
            finishPhotoCapture()
        } else {
            startCameraForPlayer(at: 0)
        }
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        stopCamera()
    }

    // MARK: - Setup

    private func setupUI() {
        // Dark overlay for camera feed
        captureOverlay = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        captureOverlay.fillColor = SKColor(white: 0, alpha: 0.3)
        captureOverlay.strokeColor = .clear
        captureOverlay.zPosition = 10
        addChild(captureOverlay)

        // Center guide circle
        centerGuide = SKShapeNode(circleOfRadius: 150)
        centerGuide.position = CGPoint(x: size.width / 2, y: size.height / 2)
        centerGuide.strokeColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.8)
        centerGuide.lineWidth = 4
        centerGuide.fillColor = .clear
        centerGuide.zPosition = 15
        addChild(centerGuide)

        // Instruction label (top)
        instructionLabel = SKLabelNode(text: "Position your face in the circle")
        instructionLabel.fontSize = 32
        instructionLabel.fontColor = .white
        instructionLabel.position = CGPoint(x: size.width / 2, y: size.height - 80)
        instructionLabel.zPosition = 20
        addChild(instructionLabel)

        // Status label (center, below circle)
        statusLabel = SKLabelNode(text: "Searching for face...")
        statusLabel.fontSize = 24
        statusLabel.fontColor = SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 250)
        statusLabel.zPosition = 20
        addChild(statusLabel)

        // Progress label (top right)
        progressLabel = SKLabelNode(text: "Player 1 / 1")
        progressLabel.fontSize = 20
        progressLabel.fontColor = .white
        progressLabel.position = CGPoint(x: size.width - 150, y: size.height - 50)
        progressLabel.zPosition = 20
        addChild(progressLabel)

        // Skip button (bottom)
        let skipButton = SKLabelNode(text: "[S] Skip Photo")
        skipButton.fontSize = 18
        skipButton.fontColor = SKColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
        skipButton.position = CGPoint(x: size.width / 2, y: 50)
        skipButton.name = "skipButton"
        skipButton.zPosition = 20
        addChild(skipButton)
    }

    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Face detection error: \(error)")
                return
            }

            DispatchQueue.main.async {
                self.processFaceDetectionResults(request.results as? [VNFaceObservation])
            }
        }
    }

    // MARK: - Camera

    private func startCameraForPlayer(at index: Int) {
        let humanPlayers = players.filter { !$0.isCPU }
        guard index < humanPlayers.count else {
            finishPhotoCapture()
            return
        }

        currentPlayerIndex = index
        let player = humanPlayers[index]

        // Update UI
        instructionLabel.text = "\(player.name), position your face in the circle"
        progressLabel.text = "Player \(index + 1) / \(humanPlayers.count)"
        statusLabel.text = "Searching for face..."
        centerGuide.strokeColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.8)

        // Start camera
        setupCamera()
    }

    private func setupCamera() {
        // Request camera permission first
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.startCamera()
                } else {
                    print("❌ Camera permission denied")
                    self?.statusLabel.text = "❌ Camera permission denied - Press S to skip"
                }
            }
        }
    }

    private func startCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }

        captureSession.sessionPreset = .high

        // Get camera device
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ No camera available")
            statusLabel.text = "❌ No camera found - Press S to skip"
            return
        }

        do {
            // Add camera input
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }

            // Add video output for face detection
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }

            // Create preview layer and add to view
            if let view = view {
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                previewLayer?.frame = view.bounds
                previewLayer?.videoGravity = .resizeAspectFill
                view.layer?.insertSublayer(previewLayer!, at: 0)
            }

            // Start session
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
                print("✅ Camera started for photo capture")
            }

        } catch {
            print("❌ Camera setup error: \(error)")
            statusLabel.text = "❌ Camera error - Press S to skip"
        }
    }

    private func stopCamera() {
        captureSession?.stopRunning()
        previewLayer?.removeFromSuperlayer()
        captureSession = nil
        previewLayer = nil
    }

    // MARK: - Face Detection

    private func processFaceDetectionResults(_ observations: [VNFaceObservation]?) {
        guard let faces = observations, !faces.isEmpty else {
            isFaceCentered = false
            faceStableFrames = 0
            statusLabel.text = "Searching for face..."
            centerGuide.strokeColor = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.8)
            return
        }

        // Get first face
        let face = faces[0]

        // Check if face is centered (Vision coordinates are normalized 0-1)
        let faceX = face.boundingBox.midX
        let faceY = face.boundingBox.midY

        // Center is around (0.5, 0.5)
        let distanceFromCenter = sqrt(pow(faceX - 0.5, 2) + pow(faceY - 0.5, 2))
        let isCentered = distanceFromCenter < 0.15  // Within 15% of center

        // Check face size (not too close, not too far)
        let faceSize = max(face.boundingBox.width, face.boundingBox.height)
        let isGoodSize = faceSize > 0.2 && faceSize < 0.6

        if isCentered && isGoodSize {
            isFaceCentered = true
            faceStableFrames += 1

            centerGuide.strokeColor = SKColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 1.0)
            statusLabel.text = "Hold steady... \(faceStableFrames)/\(requiredStableFrames)"

            // Auto-capture when stable
            if faceStableFrames >= requiredStableFrames {
                capturePhoto()
            }
        } else {
            isFaceCentered = false
            faceStableFrames = 0

            if !isCentered {
                statusLabel.text = "Move to center"
            } else if !isGoodSize {
                statusLabel.text = faceSize < 0.2 ? "Move closer" : "Move back"
            }

            centerGuide.strokeColor = SKColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 0.8)
        }
    }

    // MARK: - Photo Capture

    private func capturePhoto() {
        guard let previewLayer = previewLayer else { return }

        // Get current frame as image
        guard let connection = previewLayer.connection,
              let output = videoOutput,
              let sampleBuffer = output.connection(with: .video)?.videoOrientation != nil ? getLastSampleBuffer() : nil else {
            print("❌ Failed to capture photo")
            moveToNextPlayer()
            return
        }

        // Convert sample buffer to NSImage
        if let image = imageFromSampleBuffer(sampleBuffer) {
            savePhotoForCurrentPlayer(image)
        } else {
            print("❌ Failed to convert sample buffer to image")
            moveToNextPlayer()
        }
    }

    private var lastSampleBuffer: CMSampleBuffer?

    private func getLastSampleBuffer() -> CMSampleBuffer? {
        return lastSampleBuffer
    }

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> NSImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func savePhotoForCurrentPlayer(_ image: NSImage) {
        let humanPlayers = players.filter { !$0.isCPU }
        guard currentPlayerIndex < humanPlayers.count else { return }

        let player = humanPlayers[currentPlayerIndex]

        // Crop to circular and resize
        let processedImage = cropToCircle(image, size: 200)

        // Save photo
        capturedPhotos[player.id] = processedImage
        player.faceImage = processedImage

        print("✅ Photo captured for \(player.name)")

        // Flash effect
        statusLabel.text = "✅ Photo captured!"
        centerGuide.strokeColor = SKColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 1.0)

        // Wait briefly then move to next
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.moveToNextPlayer()
        }
    }

    private func cropToCircle(_ image: NSImage, size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        let newImage = NSImage(size: targetSize)

        newImage.lockFocus()

        // Create circular clipping path
        let circlePath = NSBezierPath(ovalIn: NSRect(origin: .zero, size: targetSize))
        circlePath.addClip()

        // Draw image scaled to fit
        let aspectRatio = image.size.width / image.size.height
        var drawRect = NSRect(origin: .zero, size: targetSize)

        if aspectRatio > 1 {
            // Wider - crop sides
            drawRect.size.width = targetSize.height * aspectRatio
            drawRect.origin.x = -(drawRect.size.width - targetSize.width) / 2
        } else {
            // Taller - crop top/bottom
            drawRect.size.height = targetSize.width / aspectRatio
            drawRect.origin.y = -(drawRect.size.height - targetSize.height) / 2
        }

        image.draw(in: drawRect)

        newImage.unlockFocus()

        return newImage
    }

    private func moveToNextPlayer() {
        stopCamera()
        faceStableFrames = 0
        isFaceCentered = false

        let humanPlayers = players.filter { !$0.isCPU }
        let nextIndex = currentPlayerIndex + 1

        if nextIndex < humanPlayers.count {
            // More players to capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startCameraForPlayer(at: nextIndex)
            }
        } else {
            // All done
            finishPhotoCapture()
        }
    }

    private func skipCurrentPlayer() {
        print("⚠️ Skipped photo for player \(currentPlayerIndex + 1)")
        moveToNextPlayer()
    }

    private func finishPhotoCapture() {
        stopCamera()

        print("✅ Photo capture complete! Captured \(capturedPhotos.count) photos")

        // Transition to race scene
        gameCoordinator?.startRace(with: players)
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 1:  // S - Skip
            skipCurrentPlayer()

        case 53:  // ESC - Go back to lobby
            stopCamera()
            gameCoordinator?.returnToLobby()

        default:
            break
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PhotoCaptureScene: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Store last sample buffer for capture
        lastSampleBuffer = sampleBuffer

        // Run face detection
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try imageRequestHandler.perform([faceDetectionRequest])
        } catch {
            print("❌ Face detection error: \(error)")
        }
    }
}
