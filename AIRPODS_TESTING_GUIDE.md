# 🎧 AirPods Testing Guide

## ✅ Fixes Applied

1. **Removed macOS Platform Guards** - AirPods motion now works on Mac
2. **Auto-Disconnect Prevention** - AirPods stay connected when removed from ears
3. **Real-time Connection Detection** - Lobby shows AirPods status every 2 seconds
4. **Lowered Shake Threshold** - Easier to trigger (2.0 instead of 2.5)
5. **Better Console Logging** - Clear feedback for all motion events

---

## 🔧 Prerequisites

### Hardware Required
- **AirPods Pro** or **AirPods Max** (regular AirPods don't have motion sensors)
- **Mac** running macOS 11.0 Big Sur or later
- Bluetooth enabled

### Software Required
- Xcode project built and running
- AirPods paired with Mac via Bluetooth

---

## 📋 Step-by-Step Testing

### Step 1: Connect AirPods

1. **Put AirPods in your ears** OR **hold them in your hand**
2. **Open Bluetooth Settings** (System Settings → Bluetooth)
3. **Connect AirPods** to your Mac
4. Wait for "Connected" status

### Step 2: Launch Game

```bash
# Build and run in Xcode (⌘R)
# Or from terminal:
cd /Users/jacobmobin/Documents/GoonHacksProject/GoonHacksGame
xcodebuild -project GoonHacksGame.xcodeproj -scheme GoonHacksGame && \
open ~/Library/Developer/Xcode/DerivedData/GoonHacksGame-*/Build/Products/Debug/GoonHacksGame.app
```

### Step 3: Check Connection Status

**In Lobby**, you should see:

✅ **If AirPods are connected**:
```
🎧 AIRPODS DETECTED! SHAKE TO CLAIM SLOT!
```
(Green text)

❌ **If AirPods are NOT connected**:
```
⚠️ NO AIRPODS - USE KEYBOARD (RETURN TO CLAIM)
```
(Orange text)

**In Console** (Xcode debug output), look for:
```
✅ AirPods connection monitoring started
   - AirPods will NOT disconnect when removed from ears
✅ AirPods Pro/Max detected and ready
```

---

## 🧪 Testing Motion Detection

### Test 1: Shake Detection (Player Registration)

**Goal**: Claim a player slot by shaking your head

1. Wear AirPods (or hold them firmly)
2. **Shake your head vigorously** left-right or up-down
3. **Expected Result**:
   - Console: `📳 SHAKE DETECTED! Magnitude: [number > 2.0]`
   - UI: Next available player slot turns colored and shows "READY"
   - Console: `✅ Player [#] claimed by Local Player`

**Troubleshooting**:
- If no detection: Shake harder (magnitude needs to be > 2.0)
- Try different shake patterns:
  - Quick left-right head turn
  - Rapid up-down nod
  - Circular head motion
- Check console for magnitude values

### Test 2: Steering (During Race)

**Goal**: Control racer movement with head tilt

1. Start race (claim 2+ slots, press Space or click Start)
2. Wait for countdown (3, 2, 1, GO!)
3. **Tilt your head**:
   - **Left/Right**: Should steer racer horizontally
   - **Forward/Back**: Should add vertical force

**Expected Console Output**:
```
(Only when tilting beyond deadzone of 0.15 radians)
Steering values being sent to network
```

**Visual Feedback**:
- Your racer (P1) should move left/right when you tilt
- Position display (top-left) should show movement

**Troubleshooting**:
- If no response: Tilt head more (deadzone is 0.15 radians ~8.5 degrees)
- If too sensitive: Increase deadzone in `MotionController.swift` line 136
- If inverted: Roll/pitch mapping might need adjustment

### Test 3: Boost Detection

**Goal**: Trigger boost with quick forward motion

1. During race
2. **Quick forward nod/shake** (like nodding "yes" vigorously)
3. **Expected Result**:
   - Console: `💨 BOOST detected! Z: [value] Y: [value]`
   - Console: `💨 Boost! P[#]`
   - Your racer should get a speed burst

**Triggering Conditions**:
- Z-axis acceleration > 1.5 OR
- Y-axis acceleration > 1.5
- Cooldown: 1 second between boosts

**Troubleshooting**:
- Try different motions:
  - Sharp forward nod
  - Quick upward jerk
  - Rapid shake
- Check console for Z and Y acceleration values

---

## 🐛 Common Issues & Fixes

### Issue 1: "AirPods motion not available"

**Console shows**:
```
❌ AirPods motion not available
   - Make sure you have AirPods Pro or AirPods Max
   - Check they are connected via Bluetooth
```

**Fix**:
1. Check you have **AirPods Pro** or **Max** (regular AirPods don't work)
2. Open **System Settings → Bluetooth**
3. Verify AirPods show "Connected"
4. If connected but not working:
   - Disconnect and reconnect
   - Restart Bluetooth
   - Restart Mac

### Issue 2: AirPods Disconnect When Removed from Ears

**This should NOT happen anymore!**

The fix:
- `AirPodsDetector.startMonitoring()` keeps connection alive
- Called automatically in `LobbyScene.setupMultipeer()`

**To verify it's working**:
1. Connect AirPods and launch game
2. Console should show:
   ```
   ✅ AirPods connection monitoring started
      - AirPods will NOT disconnect when removed from ears
   ```
3. Remove AirPods from ears
4. They should stay connected (check Bluetooth settings)

**If still disconnecting**:
- Check macOS version (needs 11.0+)
- Check Audio settings → Output is still AirPods
- Try restarting the app

### Issue 3: Lobby Says "NO AIRPODS" But They're Connected

**Possible causes**:
1. **Regular AirPods** (not Pro/Max) - won't work
2. **Motion sensors disabled** - check AirPods settings
3. **macOS < 11.0** - upgrade required

**Debug**:
```swift
// In console, look for:
⚠️ No AirPods motion sensors detected. Connect AirPods Pro or Max.
// OR
❌ Requires macOS 11.0+ or iOS 14.0+
```

### Issue 4: Shake Detection Not Working

**Symptoms**: Shaking head doesn't claim slots

**Fixes**:
1. **Lower threshold** (already set to 2.0):
   - Edit `MotionController.swift` line 35
   - Try 1.5 or 1.0 for easier detection

2. **Check console for magnitude**:
   ```
   // When shaking, you should see:
   📳 SHAKE DETECTED! Magnitude: 2.34
   ```
   - If magnitude is < 2.0, shake harder
   - If no magnitude shown, motion isn't being detected at all

3. **Alternative: Use keyboard**:
   - Press **Return (Enter)** to claim next slot

### Issue 5: Steering Not Responding

**Symptoms**: Tilting head doesn't move racer

**Checks**:
1. **Is Player 1 controlled by you?**
   - Only P1 responds to keyboard/AirPods in debug mode
   - Other players are CPU-controlled

2. **Are you past the countdown?**
   - Steering only works after "GO!"

3. **Check console for steering values**:
   - Should see frequent motion updates
   - If none, motion processing failed

4. **Try keyboard instead**:
   - A/D = steer left/right
   - W = boost

---

## 📊 Expected Console Output (Full Test)

### On Launch
```
✅ MultipeerManager initialized: MacBook-Pro
✅ Loaded 100 tracklets
✅ Game coordinator initialized
✅ Lobby scene loaded
🎮 Started hosting game session
✅ AirPods connection monitoring started
   - AirPods will NOT disconnect when removed from ears
✅ AirPods Pro/Max detected and ready
```

### When Shaking (Registration)
```
📳 SHAKE DETECTED! Magnitude: 2.45
📳 Shake detected!
📳 Shake detected in lobby!
✅ Player 1 claimed by Local Player
```

### During Race (Motion Active)
```
🏁 Starting race with 8 players!
✅ Race initialized with 8 players
3... 2... 1... GO!
💨 BOOST detected! Z: 1.73, Y: 0.54
💨 Boost! P1
(Steering updates sent at 30Hz - not logged to avoid spam)
```

### At Checkpoint
```
🚫 Eliminated: CPU 8
🚫 Eliminated: CPU 7
...
🏆 Winner: Player 1
```

---

## 🎮 Gameplay Tips with AirPods

### Best Practices
1. **Wear AirPods** (better detection than holding)
2. **Exaggerated motions** (tilt fully, shake vigorously)
3. **Sit upright** (neutral position for calibration)
4. **Look straight ahead** before tilting

### Control Mapping
| Head Motion | Game Action |
|-------------|-------------|
| Tilt left | Steer left (-X) |
| Tilt right | Steer right (+X) |
| Tilt forward | Steer up (+Y) |
| Tilt back | Steer down (-Y) |
| Quick shake | Boost (1s cooldown) |
| Vigorous shake | Claim player slot |

### Deadzone Info
- **Steering deadzone**: 0.15 radians (~8.5°)
- **Boost threshold**: 1.5 G-force
- **Shake threshold**: 2.0 G-force

---

## 🔍 Debugging Commands

### Check Bluetooth Connection
```bash
# List paired devices
system_profiler SPBluetoothDataType | grep -A 10 "AirPods"

# Check if connected
defaults read /Library/Preferences/com.apple.Bluetooth | grep -i airpods
```

### View Console Logs
In Xcode:
- **View → Debug Area → Show Debug Area** (⌘⇧Y)
- Look for emoji prefixes: ✅ ❌ 📳 💨 🏁 🚫 🏆

### Test AirPods Motion Directly (Python)
```python
# Requires pyobjc
from CoreMotion import CMHeadphoneMotionManager

manager = CMHeadphoneMotionManager.alloc().init()
print(f"Available: {manager.isDeviceMotionAvailable()}")
```

---

## ✅ Success Checklist

- [ ] AirPods Pro/Max connected to Mac
- [ ] Lobby shows "🎧 AIRPODS DETECTED!"
- [ ] Console shows "AirPods connection monitoring started"
- [ ] Shaking head claims player slots
- [ ] Claimed slots turn colored and show "READY"
- [ ] Can start race with 2+ players
- [ ] Tilting head steers racer during race
- [ ] Quick nod triggers boost
- [ ] AirPods stay connected when removed from ears
- [ ] Can complete full race to winner announcement

---

## 🚀 Next Steps

Once AirPods testing is successful:

1. **Test with multiple AirPods** (2+ players with their own AirPods)
2. **Fine-tune thresholds** based on user feedback
3. **Add calibration screen** (zero out neutral position)
4. **Add visual feedback** for tilt angles
5. **Add haptic feedback** (if possible via AirPods audio cues)

---

## 📝 Filing Bug Reports

If issues persist:

1. **Capture console output** (copy all logs)
2. **Note macOS version**: `sw_vers`
3. **Note AirPods model**: Check Bluetooth settings
4. **Describe motion attempted**: "Shook head left-right 3 times"
5. **Expected vs actual**: "Expected slot claim, got nothing"

---

**Good luck testing! Your AirPods should now work perfectly.** 🎧🏁
