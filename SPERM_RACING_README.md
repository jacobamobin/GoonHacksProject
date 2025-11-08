# 🏁 Sperm Racing - Knockout Multiplayer Game

A local multiplayer party game where up to 8 players control sperm avatars using **AirPods motion sensors** or **iPhone gyroscopes**. Featuring knockout-style racing with physics driven by real sperm cell tracking data from the VISEM dataset.

---

## 🎮 How to Play

1. **Connect**: Up to 8 players join using AirPods or iPhones
2. **Register**: Shake your device to claim a player slot (1-8)
3. **Smile**: Camera captures your face for your racer avatar
4. **Race**: Tilt to steer, shake forward to boost
5. **Survive**: At each checkpoint, the last-place racer is eliminated
6. **Win**: Be the last racer standing!

---

## ✨ Features

### Implemented ✅
- **Vertical racing track** with glow effects
- **VISEM-driven physics** - realistic sperm motion from real microscopy data
- **Hybrid control system**:
  - 40% data-driven base motion (tracklet playback)
  - 40% player steering input
  - 20% fluid simulation
- **Knockout elimination** system with 7 checkpoints
- **8-player racing** (human + CPU)
- **AirPods & iPhone motion control** ready
- **100 tracklet library** extracted from VISEM dataset

### In Progress 🚧
- MultipeerConnectivity for device discovery
- Shake-to-claim player registration
- Face photo capture and overlay
- Metal shaders for enhanced glow
- VISEM video preview window

---

## 🚀 Quick Start

### Prerequisites
- macOS 12.0+ / iOS 15.0+
- Xcode 14+
- AirPods Pro/Max (optional, for motion control)

### Build Instructions

1. **Open the project**:
   ```bash
   cd GoonHacksProject/GoonHacksGame
   open GoonHacksGame.xcodeproj
   ```

2. **Add resource files to Xcode**:
   - Select project in navigator
   - Right-click on `GoonHacksGame` folder → Add Files
   - Add: `tracklets_for_game.json`
   - Ensure "Copy items if needed" is checked
   - Add to target: GoonHacksGame

3. **Build & Run**:
   - Select "My Mac" as target
   - Press ⌘R to run

4. **Test the game**:
   - Press **Space** to start race
   - Use **A/D** to steer Player 1
   - Press **W** for boost
   - Watch the knockout racing in action!

---

## 📁 Project Structure

```
GoonHacksProject/
├── SPERM_RACING_README.md         # This file
├── IMPLEMENTATION_GUIDE.md        # Detailed development guide
│
├── GoonHacksGame/                 # Swift/SpriteKit game
│   └── GoonHacksGame/
│       ├── Tracklet.swift         # VISEM data models
│       ├── GameModels.swift       # Game entities & physics
│       ├── RaceGameScene.swift    # Main racing scene
│       ├── MotionController.swift # AirPods/iPhone control
│       └── tracklets_for_game.json # VISEM tracklet data
│
└── visem-tracking-main/           # Dataset & extraction
    ├── extract_tracklets_for_game.py
    └── data_preparation_scripts/
```

---

## 🎯 Game Mechanics

### Physics Simulation
Each racer's motion is a weighted blend of:

| Component | Weight | Description |
|-----------|--------|-------------|
| **Tracklet Motion** | 40% | Replays real sperm trajectories from VISEM |
| **Player Input** | 40% | Tilt steering + boost control |
| **Fluid Field** | 20% | Procedural flow simulation |

### Controls

#### AirPods
- **Tilt left/right**: Steer X-axis
- **Tilt forward/back**: Steer Y-axis
- **Quick forward shake**: Boost (1s cooldown)
- **Strong shake**: Claim player slot (registration)

#### iPhone
- **Device tilt**: Steering
- **Forward shake**: Boost
- **Shake**: Claim player slot

#### Keyboard (Debug)
- **Space**: Start race
- **A/D**: Steer left/right
- **W**: Boost

### Knockout System
- Race has **7 checkpoints** for 8 players
- At each checkpoint: **last-place racer eliminated**
- Eliminated racers fade out and scale down
- Final 1v1 determines the winner

---

## 📊 VISEM Dataset Integration

### What is VISEM?
**VISEM-Tracking** is a research dataset of sperm cell microscopy videos with YOLOv5-based detection and tracking. We use this data to create realistic motion for CPU-controlled racers and fluid dynamics.

### Extracted Statistics
- **100 tracklets** extracted from 1176 total tracks
- **Mean speed**: 0.119 (normalized coordinates per frame)
- **Mean straightness**: 0.772 (0=circular, 1=straight line)
- **Data format**: JSON with positions, velocities, accelerations

### How It's Used
1. **CPU Racers**: Play back real sperm trajectories with time-warping
2. **Fluid Simulation**: Flow intensity based on mean speed statistics
3. **Track Design**: Future - use density maps for obstacles
4. **Difficulty Scaling**: Speed tuning based on P95 percentile

---

## 🎨 Visual Theme

### Glow Aesthetic
- **Dark blue background** (#0D0D26)
- **Cyan glowing track walls** (#33CCFF)
- **Red checkpoint lines** with pulse effect
- **Additive particle trails** for each racer
- **Player-colored sprites** (8 vibrant colors)

### Planned Effects
- Metal shaders for enhanced glow
- Boost trail burst
- Elimination particle explosion
- Winner spotlight
- Fluid flow field visualization

---

## 🛠️ Development Roadmap

### ✅ Phase 1: Core Foundation (COMPLETE)
- Data extraction pipeline
- Swift game models
- Basic racing scene
- Motion control system
- Physics simulation

### 🚧 Phase 2: Multiplayer (IN PROGRESS)
- MultipeerConnectivity networking
- Device discovery and pairing
- Shake-to-claim registration
- Face photo capture
- Real-time control sync

### 📋 Phase 3: Polish
- Metal shaders
- Enhanced particle effects
- VISEM video preview
- UI/UX refinement
- Sound effects & music

### 🎯 Phase 4: Advanced Features
- Betting system (virtual tokens)
- Track editor
- Replay system
- Tournament mode
- Leaderboards

---

## 🐛 Known Issues

- [ ] Particle textures show warnings (missing "spark" texture)
- [ ] Need to add tracklets JSON to bundle resources manually
- [ ] Camera permissions not yet in Info.plist
- [ ] No graceful handling of missing tracklet data
- [ ] CPU racers need smarter tracklet selection

---

## 📖 Documentation

- **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)**: Detailed technical guide
- **[VISEM Dataset](https://huggingface.co/datasets/SimulaMet-HOST/VISEM-Tracking)**: Source data
- **[AirPods Motion Sample](https://github.com/tukuyo/AirPodsPro-Motion-Sampler)**: Reference code

---

## 🙏 Credits

- **VISEM-Tracking Dataset**: SimulaMet-HOST team
- **YOLOv5**: Ultralytics
- **AirPods Motion Reference**: tukuyo/AirPodsPro-Motion-Sampler
- **Game Concept**: GoonHacks 2025

---

## 📄 License

Research and educational use. VISEM dataset has its own license terms.

---

## 🎉 Let's Race!

Built with Swift, SpriteKit, CoreMotion, and real sperm tracking data. Because why not? 🚀
