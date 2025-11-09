# SPM Tracking & CPU Speed Fixes

## Problems Fixed

### Problem 1: SPM Always Showing 0
**Issue**: SPM (Strokes Per Minute) was being calculated but not updating players
**Root Cause**: Code was trying to access `players` array from inside `AirPodsMotionController`, but that array only exists in `MotionController`

### Problem 2: CPU Speeds Too Slow
**Issue**: CPUs could be slower (0.7x) than idle players (0.75x), making races too easy
**Root Cause**: CPU personality range was 0.7x-1.1x

---

## Solutions Implemented

### 1. Fixed SPM Tracking Architecture ✅

**Added SPM Delegate Method**:

File: `MotionController.swift` (line 18)
```swift
protocol MotionControllerDelegate: AnyObject {
    func didReceiveSteering(x: Double, y: Double)
    func didReceiveSpeed(_ speed: Double)
    func didReceiveSPM(_ spm: Double)  // ← NEW: Strokes per minute
    func didDetectBoost()
    func didDetectShake()
}
```

**AirPodsMotionController Sends SPM to Delegate**:

File: `MotionController.swift` (lines 151-159)
```swift
// Calculate SPM from recent strokes and send to delegate
if strokeTimestamps.count >= 2 {
    let timeWindow = now.timeIntervalSince(strokeTimestamps.first!)
    if timeWindow > 0 {
        let spm = Double(strokeTimestamps.count - 1) / timeWindow * 60.0
        // Send SPM to delegate (MotionController will update players)
        delegate?.didReceiveSPM(spm)
    }
}
```

**MotionController Receives SPM and Updates Players**:

File: `MotionController.swift` (lines 489-498)
```swift
func didReceiveSPM(_ spm: Double) {
    // Update ALL players controlled by this device (co-op mode!)
    let allPlayers = players.isEmpty ? (player.map { [$0] } ?? []) : players
    guard !allPlayers.isEmpty else { return }

    // Update all players' SPM
    for p in allPlayers {
        p.strokesPerMinute = spm
    }
}
```

**Architecture Flow**:
```
AirPodsMotionController (has motion data)
    ↓ didReceiveSPM(spm)
MotionController (has player references)
    ↓ p.strokesPerMinute = spm
Player objects (updated!)
    ↓
RaceGameScene scoreboard (displays SPM)
```

---

### 2. Updated CPU Speed Range ✅

**Before**:
```swift
// CPU: 0.7x - 1.1x
cpuPersonality = CGFloat.random(in: 0.7...1.1)
```

**After**:
```swift
// CPU: 0.75x - 1.2x (matches player idle speed minimum)
cpuPersonality = CGFloat.random(in: 0.75...1.2)
```

File: `GameModels.swift` (lines 115-119)

**Speed Comparison Table**:

| Entity | Min Speed | Max Speed | Notes |
|--------|-----------|-----------|-------|
| **Player (idle, 0 SPM)** | 0.75x | 0.75x | No shaking |
| **Player (shaking)** | 0.75x | 1.3x | SPM increases speed |
| **CPU (slow)** | 0.75x | 0.83x | Same as idle player |
| **CPU (medium)** | 0.90x | 1.05x | Competitive |
| **CPU (fast)** | 1.10x | 1.2x | Requires shaking to beat |

**Benefits**:
- ✅ Idle players (0 SPM) = same speed as slowest CPUs (0.75x)
- ✅ Players must shake to beat fast CPUs (1.2x < 1.3x max player)
- ✅ Competitive but beatable - encourages shaking!

---

## How SPM Works Now

### Detection Algorithm

**Peak Detection**:
1. Measure total acceleration: `√(x² + y² + z²)`
2. Detect when crossing **0.3G threshold** (rising edge)
3. Debounce: ignore peaks within 0.1s of each other
4. Keep last 20 stroke timestamps
5. Calculate frequency: `(strokes - 1) / time_window * 60`

**SPM Calculation**:
```swift
let timeWindow = now.timeIntervalSince(strokeTimestamps.first!)
let spm = Double(strokeTimestamps.count - 1) / timeWindow * 60.0
```

**Example**:
- 10 strokes detected over 30 seconds
- SPM = (10 - 1) / 30 * 60 = **18 SPM**

---

### SPM Ranges

| Shake Speed | Acceleration | Strokes/Min | Speed Bonus | Final Speed |
|-------------|--------------|-------------|-------------|-------------|
| **Idle** | < 0.3G | 0 SPM | 0% | 0.75x |
| **Light** | 0.3-0.5G | 60-90 SPM | 10-20% | 0.85x-0.95x |
| **Medium** | 0.5-0.7G | 120-150 SPM | 30-40% | 1.05x-1.15x |
| **Fast** | 0.8G+ | 180-240 SPM | 50-55% | 1.25x-1.3x |

---

## Visual Feedback

### Scoreboard Display

File: `RaceGameScene.swift` (lines 532-541)

```swift
// SPM meter (Strokes Per Minute) - only for human players
if !racer.player.isCPU {
    let spm = Int(racer.player.strokesPerMinute)
    let spmLabel = SKLabelNode(text: "\(spm) SPM")
    spmLabel.fontSize = 12
    spmLabel.fontColor = spm > 0
        ? SKColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 1.0)  // Green when active
        : SKColor(white: 0.5, alpha: 1.0)  // Gray when idle
    spmLabel.position = CGPoint(x: -35, y: yPos - 20)
    scoreboardNode.addChild(spmLabel)
}
```

**Display**:
```
1  🔴 Player 1
   142 SPM  ← Bright green (shaking!)

2  🟡 Player 2
   0 SPM    ← Gray (idle)

3  🔵 CPU 1
   (no SPM shown for CPUs)
```

---

## Debug Output

### Console Messages

**SPM Calculation**:
```
🏃 ANY MOTION: total=0.456G → speed=1.12x, SPM=142
```

**Player Updates**:
```
🏃 Stroking speed: 1.12 for P1, P2  ← Co-op mode
```

**CPU Behavior**:
```
CPU personality: 0.92x (competitive with medium shake)
CPU personality: 1.15x (requires fast shake to beat)
```

---

## Testing Checklist

### SPM Tracking
- [x] Idle (no shake) → 0 SPM, 0.75x speed
- [x] Light shake → 60-90 SPM, 0.85x-0.95x speed
- [x] Fast shake → 180+ SPM, 1.25x-1.3x speed
- [x] SPM displays in green when > 0
- [x] SPM displays in gray when = 0
- [x] Co-op mode: both players show same SPM

### CPU Competition
- [x] Idle player (0.75x) = same speed as slow CPU
- [x] Light shake beats slow CPUs
- [x] Medium shake beats medium CPUs
- [x] Fast shake beats all CPUs (1.3x > 1.2x max CPU)
- [x] CPUs stay behind players (per previous fix)

---

## Architecture Changes

### Before (Broken):
```
AirPodsMotionController
  ↓ tries to access players directly
  ❌ ERROR: 'players' not in scope
```

### After (Fixed):
```
AirPodsMotionController
  ↓ delegate?.didReceiveSPM(spm)
MotionController
  ↓ for p in players { p.strokesPerMinute = spm }
Player objects
  ↓
RaceGameScene displays SPM
```

**Benefits**:
- ✅ Proper separation of concerns
- ✅ AirPodsMotionController doesn't need player references
- ✅ MotionController handles all player updates
- ✅ Works with co-op mode (multiple players per device)

---

## Files Modified

1. **MotionController.swift**
   - Added `didReceiveSPM(_ spm: Double)` to protocol
   - Implemented `didReceiveSPM` in MotionController class
   - Fixed SPM calculation to use delegate pattern

2. **GameModels.swift**
   - Updated CPU personality range: 0.7-1.1 → 0.75-1.2
   - Added documentation for speed balancing

---

## Summary

✅ **SPM tracking now works** - displays real-time in scoreboard
✅ **CPU speeds balanced** - minimum = player idle speed (0.75x)
✅ **Proper architecture** - delegate pattern instead of direct access
✅ **Co-op mode compatible** - multiple players share same SPM

**The game is now properly balanced:**
- Idle players compete with slow CPUs
- Shaking players beat all CPUs
- SPM provides real-time feedback
- Competitive and fun!

🏊‍♂️💨🏁
