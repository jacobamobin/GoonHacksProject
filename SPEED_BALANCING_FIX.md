# Speed Balancing & Independent Player Control Fix

## Problems Fixed

### Problem 1: Players Too Fast at Rest
**Issue**: AirPod players were flying forward even without moving, leaving CPUs in the dust
**Root Cause**: Default player speed was 1.0x, which is faster than slow/medium CPUs (0.7x-0.85x)

### Problem 2: Both AirPod Players Matching Speed
**Issue**: Two AirPod players moving at exactly the same speed, not independent
**Root Cause**: Each player created their own MotionController, but all CMHeadphoneMotionManagers read from the SAME physical AirPods device

---

## Solutions Implemented

### 1. Reduced Default Player Speed (0.75x)

**Files Changed**:
- `GameModels.swift` (line 35)
- `MotionController.swift` (line 106)
- `BluetoothControllerManager.swift` (line 98)

**Changes**:
```swift
// OLD: Players started at 1.0x speed (too fast!)
var speedInput: CGFloat = 1.0
private var strokingVelocity: Double = 1.0
var smoothedSpeed: Double = 1.0

// NEW: Players start at 0.75x speed (balanced!)
var speedInput: CGFloat = 0.75
private var strokingVelocity: Double = 0.75
var smoothedSpeed: Double = 0.75
```

**Speed Ranges After Fix**:
| Entity | At Rest | Max (Shaking) | Notes |
|--------|---------|---------------|-------|
| **Human (idle)** | 0.75x | 0.75x | Slower than fast CPUs |
| **Human (shaking)** | 0.75x | 1.3x | Can beat all CPUs |
| **CPU (slow)** | 0.7x | 0.77x | Slower than idle humans |
| **CPU (medium)** | 0.85x | 0.94x | Faster than idle humans |
| **CPU (fast)** | 1.0x | 1.12x | Much faster than idle humans |

**Result**: Players must SHAKE to stay competitive with fast CPUs!

---

### 2. Updated Speed Calculation Formula

**Files Changed**:
- `MotionController.swift` (lines 126-136)
- `BluetoothControllerManager.swift` (lines 115-125)

**Changes**:
```swift
// OLD: 1.0x base + up to 50% bonus = 1.0x to 1.5x
if avgAccel < 0.15 {
    rawSpeed = 1.0
} else {
    let bonus = min(0.5, (avgAccel - 0.15) * 0.8)
    rawSpeed = 1.0 + bonus
}

// NEW: 0.75x base + up to 55% bonus = 0.75x to 1.3x
if avgAccel < 0.15 {
    rawSpeed = 0.75
} else {
    let bonus = min(0.55, (avgAccel - 0.15) * 0.85)
    rawSpeed = 0.75 + bonus
}
```

**Acceleration Mapping**:
- `< 0.15G` → 0.75x (at rest, slower than fast CPUs)
- `0.15G` → 0.75x (start of motion detection)
- `0.5G` → ~1.05x (light shaking, beats medium CPUs)
- `0.8G+` → 1.3x (max shaking, beats all CPUs)

---

### 3. Prevented Multiple AirPods Controllers

**File Changed**: `GameCoordinator.swift` (lines 114-146)

**Problem**: Each player created their own `MotionController`, which each created their own `AirPodsMotionController`. But there's only ONE pair of AirPods physically connected, so all controllers read the same motion data!

**Solution**: Only allow ONE AirPods controller to be created per device

```swift
private func setupMotionControllers(for players: [Player]) {
    var airPodsControllerCreated = false

    for player in players {
        if case .human(let deviceId) = player.type {
            // Skip creating multiple AirPods controllers
            if player.controlType == .airPods {
                if airPodsControllerCreated {
                    print("⚠️ Skipping AirPods controller - already exists!")
                    continue
                }
                airPodsControllerCreated = true
            }

            // Create controller...
        }
    }
}
```

**Explanation**:
- You can only have ONE pair of AirPods connected to a Mac
- Creating multiple CMHeadphoneMotionManagers doesn't give you independent control
- They ALL read from the same physical AirPods
- For multiplayer: each player needs their own DEVICE (iPhone/Mac) with their own AirPods

**Result**: Only the first AirPods player gets motion control. Other players should use different devices connected via MultipeerConnectivity.

---

## Competitive Balance

### Race Scenarios

**Scenario 1: Player at Rest vs CPUs**
- Player (idle): 0.75x
- Slow CPU: 0.7x → Player faster
- Medium CPU: 0.85x → Player slower ❌
- Fast CPU: 1.0x → Player slower ❌

**Result**: Idle players fall behind fast CPUs! Must shake to stay competitive.

---

**Scenario 2: Player Light Shaking (0.5G)**
- Player: ~1.05x
- Slow CPU: 0.7x → Player faster ✓
- Medium CPU: 0.85x → Player faster ✓
- Fast CPU: 1.0x → Player faster ✓

**Result**: Light shaking beats all CPUs!

---

**Scenario 3: Player Max Shaking (0.8G+)**
- Player: 1.3x
- All CPUs: max 1.12x

**Result**: Max shaking dominates the race!

---

## Rubber Banding (Still Active)

Players who fall behind get speed boosts:
- **500+ units behind**: 1.3x multiplier
- **250-500 behind**: 1.15x multiplier

**Example**:
- Player idle (0.75x) + 500 units behind (1.3x) = 0.975x effective speed
- Still slower than fast CPUs (1.0x), but catching up!

---

## Testing Checklist

- [x] Single AirPods player: moves at 0.75x when idle
- [x] Single AirPods player: moves at 1.3x when shaking hard
- [x] AirPods player vs fast CPU (1.1x): player must shake to keep up
- [x] Two AirPods players: only first one gets motion control, second is warned
- [x] Remote players (via MultipeerConnectivity): each gets independent control

---

## Summary

**Before**:
- Players at 1.0x even when idle → left CPUs in dust ❌
- Both AirPod players shared motion data → moved in sync ❌

**After**:
- Players at 0.75x when idle → must shake to beat fast CPUs ✓
- Only one AirPods controller → second player warned ✓
- Speed range: 0.75x to 1.3x (competitive and balanced) ✓

**The race is now a true competition**: idle players fall behind, active shakers dominate!

🏊‍♂️💨🏁
