# Sperm Racing - Implementation Guide

## 🎮 Game Overview
**Knockout multiplayer racing game** where up to 8 players control sperm avatars using AirPods motion or iPhone gyros. Races use VISEM-tracked sperm trajectories for realistic fluid physics. Each checkpoint eliminates the last-place racer until one champion remains.

---

## ✅ Completed (Phase 1 - Core Foundation)

### 1. Data Pipeline ✓
- **Tracklet Extraction**: Python script extracts 100 high-quality sperm tracklets from VISEM dataset
  - File: `visem-tracking-main/extract_tracklets_for_game.py`
  - Output: `tracklets_for_game.json` (100 trajectories with velocities, accelerations, statistics)
  - Statistics:
    - Mean speed: 0.1190 (normalized coords/frame @ 30fps)
    - Mean straightness: 0.7724 (good for racing)
    - P95 speed: 0.2253

### 2. Swift Data Models ✓
- **Tracklet.swift**: Load and parse VISEM tracklet data
  - `TrackletData`, `Tracklet`, `TrackletStatistics`, `GlobalStatistics`
  - `TrackletLoader` singleton for accessing tracklet library
  - Position/velocity helpers for tracklet playback

- **GameModels.swift**: Core game entities
  - `Player`: Human or CPU player with motion input state
  - `Racer`: In-game entity with physics, position, velocity
  - `Checkpoint`: Vertical track checkpoints for eliminations
  - `GameState`: Manages game phase, players, race progress
  - `FluidField`: Procedural flow field for ambient motion
  - `PhysicsWeights`: Tunable parameters for motion blending

### 3. Main Game Scene ✓
- **RaceGameScene.swift**: Complete vertical racing implementation
  - Vertical track (5000pt high, 800pt wide)
  - 7 checkpoints (for 8-player knockout)
  - Glow-themed track walls and grid
  - Camera following lead racer
  - Particle trail system for each racer
  - Position display UI (top-left)
  - Physics simulation combining:
    - Tracklet-driven base motion (40%)
    - Player steering input (40%)
    - Fluid field forces (20%)
  - Knockout elimination at checkpoints
  - Winner announcement
  - Debug keyboard controls (Space, A/D, W for boost)

### 4. Motion Control System ✓
- **MotionController.swift**: AirPods & iPhone motion integration
  - `AirPodsMotionController`: CMHeadphoneMotionManager
    - Roll/pitch -> steering (X/Y)
    - Quick acceleration -> boost
    - Shake detection -> player registration
  - `iPhoneMotionController`: CMMotionManager (gyro)
    - Device tilt -> steering
    - Forward shake -> boost
    - Shake detection -> registration
  - Unified `MotionController` facade
  - Deadzone, smoothing, cooldown logic

### 5. Updated ViewController ✓
- Loads `RaceGameScene` instead of demo scene
- 1920x1080 resolution
- Shows FPS and node count

---

## 🚧 Next Steps (Phase 2 - Multiplayer & Polish)

### Priority 1: Multiplayer Networking

#### 1. MultipeerConnectivity Manager
Create `MultipeerManager.swift`:
- Service discovery (Bonjour)
- Peer-to-peer messaging
- Host device (Mac/iPad) advertises game session
- Controller devices (iPhones/AirPods) browse and connect
- Message protocol:
  ```swift
  enum GameMessage: Codable {
      case joinRequest(deviceId: String, deviceType: String)
      case playerAssigned(playerNumber: Int)
      case motionUpdate(steerX: Double, steerY: Double, boost: Bool)
      case shakeDetected(deviceId: String)
      case photoData(playerNumber: Int, imageData: Data)
      case raceStart
      case checkpoint(id: Int, eliminated: [Int])
      case raceFinished(winnerNumber: Int)
  }
  ```

#### 2. Player Registration Flow
Implement shake-to-claim in `RaceGameScene`:
1. Lobby phase: Show "Waiting for players..."
2. Connected devices shake to claim player slots (1-8)
3. On shake: Assign next available player number
4. Visual feedback: Slot lights up with player color
5. Proceed to photo capture when ready

#### 3. Camera Capture System
Create `PhotoCaptureManager.swift`:
- Use AVFoundation for camera
- Face detection (Vision framework)
- Crop to face region
- Compression for network transfer
- Display countdown: "Player 1, look at the camera! 3... 2... 1... 📸"

### Priority 2: Visual Polish

#### 4. Face Photo Overlay
Update `RaceGameScene.createSpermShape()`:
- Replace white circle head with `SKSpriteNode`
- Load player's face image
- Circular mask for sperm head
- Maintain glow outline

#### 5. Metal Shaders for Glow
Create `Shaders.metal`:
- Glow shader for track walls
- Particle additive blending
- Flow field visualization (optional debug overlay)
- Winner spotlight effect

#### 6. Particle Effects Enhancement
- Boost trail burst
- Elimination "poof" effect
- Checkpoint crossing spark
- Finish line fireworks

### Priority 3: VISEM Integration

#### 7. Video Preview
- Load sample VISEM video (`.mp4` from dataset)
- Display in top-right corner using `SKVideoNode`
- 320x240 inset with glow border
- Play on loop during race

#### 8. Data-Driven Track Features
Generate obstacles/flow zones from VISEM statistics:
- High-density regions → turbulence zones
- Cluster detections → obstacles
- Use `sperm_counts_per_frame.csv` to vary difficulty

---

## 🏗️ Project Structure

```
GoonHacksProject/
├── GoonHacksGame/
│   ├── GoonHacksGame.xcodeproj
│   └── GoonHacksGame/
│       ├── AppDelegate.swift
│       ├── ViewController.swift           # ✅ Updated
│       ├── Tracklet.swift                 # ✅ Data models
│       ├── GameModels.swift               # ✅ Game entities
│       ├── RaceGameScene.swift            # ✅ Main scene
│       ├── MotionController.swift         # ✅ Motion input
│       ├── MultipeerManager.swift         # ⏳ TODO
│       ├── PhotoCaptureManager.swift      # ⏳ TODO
│       ├── Shaders.metal                  # ⏳ TODO
│       ├── tracklets_for_game.json        # ✅ VISEM data
│       └── Assets.xcassets/
│
└── visem-tracking-main/
    ├── extract_tracklets_for_game.py      # ✅ Extraction script
    ├── tracklets_for_game.json            # ✅ Output data
    ├── data_preparation_scripts/
    │   ├── sperm_all_BBs.csv             # Source data
    │   └── sperm_counts_per_frame.csv
    └── sample_YOLO_models/               # Not needed for game
```

---

## 🎯 Immediate Action Items

### To Build & Test Current Implementation:

1. **Open Xcode Project**
   ```bash
   open GoonHacksGame/GoonHacksGame.xcodeproj
   ```

2. **Add Files to Project**
   - Drag `Tracklet.swift`, `GameModels.swift`, `RaceGameScene.swift`, `MotionController.swift` into Xcode
   - Add `tracklets_for_game.json` to Bundle Resources
   - Ensure target membership is checked

3. **Build & Run**
   - macOS target
   - Press Space to start race
   - Use A/D for steering, W for boost
   - Watch 8 racers (2 "human", 6 CPU) race up the track

4. **Expected Behavior**
   - Vertical track with glowing walls
   - 8 racers starting at bottom
   - Camera follows leader
   - Position display in top-left
   - CPU racers move based on VISEM tracklets
   - Checkpoints eliminate last-place racers
   - Winner announcement at end

### Known Issues to Fix:
- Particle textures missing (will show warnings, safe to ignore)
- GameScene.sks file not needed anymore
- Need to handle case where tracklet data doesn't load

---

## 📱 iOS Companion App (Controller)

For full multiplayer, create separate iOS target:

### Features:
1. **Discovery Screen**
   - Scan for game sessions
   - Connect to host Mac/iPad

2. **Registration Screen**
   - "Shake to claim a player slot!"
   - Show assigned player number

3. **Photo Capture**
   - Camera view
   - "Look at the screen and smile!"
   - Countdown timer

4. **Controller Screen**
   - Large "BOOST" button
   - Tilt visualization
   - Position indicator
   - Elimination status

5. **Results Screen**
   - Final standings
   - Winner celebration

---

## 🎨 Visual Theme Reference

### Colors
- Background: Dark blue (#0D0D26)
- Track walls: Cyan glow (#33CCFF)
- Checkpoints: Red glow (#FF4D4D)
- Player colors: Red, Blue, Green, Yellow, Pink, Purple, Orange, Cyan

### Effects
- Glow intensity: 10-30pt blur
- Particle trails: Additive blend mode
- Camera shake on boost
- Slow-motion on elimination

---

## 🔧 Technical Specifications

### Performance Targets
- 60 FPS (macOS)
- 30 FPS (iOS devices)
- < 100ms network latency for controls

### Physics Parameters
```swift
PhysicsWeights(
    tracklet: 0.4,        // VISEM-driven motion
    player: 0.4,          // Player control authority
    fluid: 0.2,           // Ambient flow
    maxSpeed: 500.0,      // Points per second
    steerMultiplier: 200.0
)
```

### Network Protocol
- MultipeerConnectivity (local Wi-Fi/Bluetooth)
- Reliable delivery for state sync
- Unreliable delivery for motion updates (higher frequency)

---

## 🐛 Debugging Tools

### Keyboard Shortcuts (Development)
- **Space**: Start race
- **A**: Steer left (Player 1)
- **D**: Steer right (Player 1)
- **W**: Boost (Player 1)
- **R**: Restart race
- **T**: Toggle tracklet visualization
- **F**: Toggle fluid field overlay

### Console Logging
- `✅` Success/initialization
- `🏁` Race events
- `🚫` Eliminations
- `🏆` Winner
- `❌` Errors
- `📳` Motion events

---

## 📊 VISEM Data Integration Details

### Tracklet Format
```json
{
  "id": "unique_track_id",
  "video_id": "38",
  "class": 0,  // 0=sperm, 1=cluster, 2=small_or_pinhead
  "positions": [[x, y], ...],  // Normalized 0-1
  "velocities": [[vx, vy, magnitude], ...],
  "statistics": {
    "mean_speed": 0.15,
    "straightness": 0.85,
    ...
  }
}
```

### Usage in Game
1. **CPU Racers**: Play back tracklet velocities with time-warping
2. **Fluid Field**: Base flow patterns on aggregate motion statistics
3. **Track Generation**: Use video frame density maps for obstacle placement
4. **Difficulty Tuning**: Scale speeds based on global statistics

---

## 🚀 Launch Checklist

- [ ] Xcode project builds without errors
- [ ] Tracklet data loads successfully
- [ ] Race starts and camera follows
- [ ] Checkpoints eliminate racers
- [ ] Winner is announced correctly
- [ ] MultipeerConnectivity works
- [ ] Shake registration functions
- [ ] Face photos capture and display
- [ ] Motion controls feel responsive
- [ ] Glow effects render properly
- [ ] Video preview plays smoothly
- [ ] 8-player race completes without crashes

---

## 📚 Resources

### Code References
- AirPods Motion: https://github.com/tukuyo/AirPodsPro-Motion-Sampler
- MultipeerConnectivity: Apple Developer Docs
- SpriteKit Shaders: Metal Shading Language Guide

### Dataset
- VISEM Tracking: https://huggingface.co/datasets/SimulaMet-HOST/VISEM-Tracking

---

**Status**: Core foundation complete. Ready for multiplayer implementation and visual polish.

**Next Session**: Implement MultipeerManager and test device discovery.
