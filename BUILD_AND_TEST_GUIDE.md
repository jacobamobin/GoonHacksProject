# 🎮 Sperm Racing - Build & Test Guide

## ✅ Complete Implementation Status

All multiplayer features are now implemented! Here's what we have:

### Core Components ✓
- **MultipeerManager**: Local device discovery and networking
- **LobbyScene**: Player selection with shake-to-claim
- **RaceGameScene**: Full racing with 8-player support
- **GameCoordinator**: Scene transitions and state management
- **MotionController**: AirPods motion with network sync
- **Game Models**: Physics, players, racers, checkpoints

---

## 🏗️ Building the Project

### Step 1: Open Xcode

```bash
cd /Users/jacobmobin/Documents/GoonHacksProject/GoonHacksGame
open GoonHacksGame.xcodeproj
```

### Step 2: Add Files to Project

**Important**: The Swift files were created but may not be in the Xcode project yet.

1. In Xcode, **right-click** on the `GoonHacksGame` folder (the yellow one)
2. Select **"Add Files to GoonHacksGame..."**
3. Navigate to: `GoonHacksGame/GoonHacksGame/GoonHacksGame/`
4. **Select these files** (hold ⌘ to multi-select):
   - `Tracklet.swift` ✓
   - `GameModels.swift` ✓
   - `RaceGameScene.swift` ✓
   - `MotionController.swift` ✓
   - `MultipeerManager.swift` ✓
   - `LobbyScene.swift` ✓
   - `GameCoordinator.swift` ✓
   - `tracklets_for_game.json` ✓

5. **Options**:
   - ✅ Check "Copy items if needed"
   - ✅ Check "Add to targets: GoonHacksGame"
   - Click **"Add"**

### Step 3: Verify Bundle Resources

1. Select the project in the navigator (blue icon at top)
2. Select target: **GoonHacksGame**
3. Go to **"Build Phases"** tab
4. Expand **"Copy Bundle Resources"**
5. **Verify `tracklets_for_game.json` is listed**
   - If not: Click **"+"** → Add `tracklets_for_game.json`

### Step 4: Build

Press **⌘B** (Product → Build)

**Expected**: Build should succeed with 0 errors

---

## 🎮 Testing on Mac (Host Mode)

### Launch the Game

1. Select target: **"My Mac"**
2. Press **⌘R** (Product → Run)

### Expected Behavior

#### Lobby Scene Appears
You should see:
- **Title**: "🏁 SPERM RACING"
- **Instructions**: "SHAKE YOUR AIRPODS TO CLAIM A SLOT!"
- **8 player slots** in 2 rows (4 per row)
- **Connection status**: "Connected: 0 devices | Claimed: 0/8 slots"

#### Testing Player Registration

**Method 1: Keyboard Shortcut (Debug)**
- Press **Return (Enter)** to claim next available slot
- Each press claims P1, P2, P3, etc.
- Slot backgrounds turn colored when claimed
- Status changes to "READY"

**Method 2: Shake Detection (with AirPods)**
- Wear AirPods Pro/Max
- Shake your head vigorously
- Should claim next slot

**Method 3: Manual Claim (for testing)**
In `LobbyScene.swift`, the `handleShakeDetected` function triggers on local shake.

#### Start the Race

Once **2+ slots claimed**:
- **"START RACE" button** appears (green, glowing)
- Click it **OR** press **Space**

#### Race Scene

After transition:
- **Countdown**: "3... 2... 1... GO!"
- **8 racers** start at bottom of vertical track
- **Camera** follows the leader upward
- **Position display** (top-left) shows rankings
- **Glowing track walls** (cyan) on left and right
- **Checkpoints** (red glowing lines) every ~700 points up the track

#### Controls During Race

**Keyboard (Player 1 debug control)**:
- **A**: Steer left
- **D**: Steer right
- **W**: Boost
- **R**: Return to lobby

**AirPods (if connected)**:
- **Tilt left/right**: Steer X-axis
- **Tilt forward/back**: Steer Y-axis
- **Quick shake forward**: Boost
- Motion updates sent at 30Hz to all connected devices

#### Knockout System

- At each checkpoint: **last-place racer eliminated**
- Eliminated racers **fade out** and **shrink**
- After 7 eliminations: **final 1v1**
- Winner announcement: **"🏆 WINNER: P#"**
- Automatically returns to lobby after 4 seconds

---

## 📱 Testing with AirPods (Motion Control)

### Prerequisites

- **AirPods Pro** or **AirPods Max**
- macOS 11.0+ (Big Sur or later)
- AirPods connected to Mac

### Testing Motion Detection

1. **Launch game** (⌘R)
2. **Wear AirPods**
3. In lobby, **shake your head firmly**
   - Should see console: `📳 Shake detected in lobby!`
   - Next available slot should be claimed

4. **Start race** (Return key x2, then Space/click Start)
5. **Tilt your head**:
   - Left/right: Should steer racer horizontally
   - Forward/back: Should add upward/downward force
6. **Quick forward nod/shake**: Boost!

### Troubleshooting Motion

**"AirPods motion not available"**:
- Check macOS version (needs 11.0+)
- Verify AirPods Pro/Max (regular AirPods don't have motion sensors)
- Re-pair AirPods

**No motion detected**:
- Check Console logs (`📳` for shake, steering values)
- Increase shake threshold in `MotionController.swift` → `shakeThreshold`

**Jittery controls**:
- Adjust deadzone in `processSteering()` method
- Current deadzone: 0.1 radians

---

## 🌐 Testing Multiplayer (Multiple Devices)

### Setup

You'll need:
- **1 Mac/iPad** (host)
- **1+ AirPods** or **iPhones** (controllers)
- All on **same Wi-Fi network**

### On Host (Mac)

1. Launch game
2. Lobby appears
3. MultipeerConnectivity **advertises** game session
4. Wait for controllers to connect

### On Controller Devices

**Note**: Controllers need their own app builds. For now, you can:

**Option A: Test with Multiple Macs**
1. Build app on second Mac
2. Launch on both
3. One acts as host (sees lobby first)
4. Other connects automatically

**Option B: Build iOS Companion App (Future)**
- Separate iOS target
- Join game session
- Shake to claim slot
- Send motion data

### Expected Multiplayer Flow

1. **Controller connects** → "Connected: 1 devices"
2. **Controller shakes** → Claims slot remotely
3. **Host starts race** → All devices receive start message
4. **Controllers send motion** → 30 Hz steering/boost updates
5. **Race progresses** → Checkpoints, eliminations synced
6. **Winner announced** → All devices see result

---

## 🐛 Debugging & Console Logs

### Key Log Messages

#### Initialization
```
✅ MultipeerManager initialized: MacBook-Pro
✅ Loaded 100 tracklets
✅ Game coordinator initialized
✅ Lobby scene loaded
```

#### Networking
```
🎮 Started hosting game session
✅ Connected: [DeviceName]
📩 Join request from [DeviceName]
📤 Sent: playerClaimed(...)
📥 Received from [DeviceName]: motionUpdate(...)
```

#### Player Registration
```
📳 Shake detected in lobby!
✅ Player 1 claimed by [DeviceName]
```

#### Race
```
🏁 Starting race with 3 players!
✅ Race initialized with 3 players
✅ Motion controller started for Player 1
🏁 Race started!
💨 Boost! P1
🚫 Eliminated: [CPU 5]
🏆 Winner: Player 1
```

### Common Issues

**❌ "tracklets_for_game.json not found in bundle"**
- Solution: Add JSON to "Copy Bundle Resources" (Step 3 above)

**❌ Build errors: "Cannot find 'MultipeerManager' in scope"**
- Solution: Files not added to project (Step 2 above)

**❌ "AirPods motion not available"**
- Solution: Check macOS version, AirPods model

**❌ No checkpoints appearing**
- Solution: Race started but checkpoints not rendering
- Check console for tracklet loading errors

**❌ Racers not moving**
- Solution: Check physics update loop
- Verify tracklet data loaded successfully

---

## 🎯 Testing Checklist

### Lobby
- [ ] Lobby scene loads
- [ ] 8 player slots visible
- [ ] Shake detection works (keyboard or AirPods)
- [ ] Slots turn colored when claimed
- [ ] Start button appears after 2+ players
- [ ] Connection status updates

### Race
- [ ] Countdown appears (3, 2, 1, GO!)
- [ ] 8 racers spawn at bottom
- [ ] Track walls glow cyan
- [ ] Checkpoints glow red
- [ ] Camera follows leader
- [ ] Position display updates
- [ ] Keyboard controls work (A/D/W)
- [ ] AirPods controls work (tilt/boost)

### Knockout System
- [ ] Checkpoints detect crossings
- [ ] Last-place racer eliminated at each checkpoint
- [ ] Eliminated racers fade and shrink
- [ ] 7 eliminations occur (8 → 1)
- [ ] Winner announcement shows
- [ ] Returns to lobby after win

### Multiplayer
- [ ] Devices discover each other
- [ ] Remote shake claims slot
- [ ] Motion updates sent over network
- [ ] Race starts on all devices simultaneously
- [ ] Race state stays in sync

---

## 🚀 Performance Targets

- **FPS**: 60 on Mac (monitor top-left counter)
- **Network latency**: < 50ms (local Wi-Fi)
- **Motion update rate**: 30 Hz
- **Racer count**: 8 simultaneous without lag

---

## 📝 Quick Start Commands

```bash
# Open project
cd /Users/jacobmobin/Documents/GoonHacksProject/GoonHacksGame
open GoonHacksGame.xcodeproj

# Or build from command line
xcodebuild -project GoonHacksGame.xcodeproj -scheme GoonHacksGame -configuration Debug

# Check tracklets
ls -lh GoonHacksGame/GoonHacksGame/tracklets_for_game.json

# View logs in real-time (if running from CLI)
# Look for ✅, 📳, 🏁, 🚫, 🏆 emojis
```

---

## 🎨 Visual Verification

### Colors
- Background: Dark blue (#0D0D26)
- Track walls: Cyan glow
- Checkpoints: Red glow
- P1: Red
- P2: Blue
- P3: Green
- P4: Yellow
- P5: Pink
- P6: Purple
- P7: Orange
- P8: Cyan

### UI Elements
- Title: Large cyan text
- Player slots: Dark gray boxes with colored borders when claimed
- Start button: Green glowing rectangle
- Position display: Semi-transparent black box (top-left)
- Winner: Large colored text with name

---

## 🔄 Reset / Restart

**During Development**:
- Press **R** during race to return to lobby
- Press **⌘R** in Xcode to restart app
- Clean build folder: **⌘⇧K** (Shift+Cmd+K)

**Full Reset**:
```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/GoonHacksGame-*

# Rebuild
cd /Users/jacobmobin/Documents/GoonHacksProject/GoonHacksGame
xcodebuild clean
```

---

## 📚 Next Steps After Testing

Once basic functionality is verified:

1. **Camera Capture** - Add face photo system
2. **Face Overlays** - Put player photos on sperm sprites
3. **Metal Shaders** - Enhanced glow effects
4. **VISEM Video** - Top-right preview window
5. **iOS Controllers** - Build separate iPhone app
6. **Sound Effects** - Boost, elimination, winner sounds
7. **Particle Polish** - Better trails and effects

---

## ✅ Success Criteria

You'll know everything works when:

1. ✅ Lobby loads without errors
2. ✅ Can claim 8 player slots (keyboard or shake)
3. ✅ Start button appears and works
4. ✅ Race scene transitions smoothly
5. ✅ All 8 racers visible and moving
6. ✅ Keyboard controls steer Player 1
7. ✅ AirPods motion controls work
8. ✅ Checkpoints eliminate last-place racers
9. ✅ Winner is announced correctly
10. ✅ Returns to lobby automatically

---

**Ready to race!** 🏁

If you encounter any issues, check the console logs first. The emoji prefixes make it easy to track what's happening:

- ✅ = Success
- ❌ = Error
- 📳 = Shake/Motion
- 🏁 = Race events
- 🚫 = Elimination
- 🏆 = Winner
- 📤📥 = Network
- 💨 = Boost

Good luck! 🚀
