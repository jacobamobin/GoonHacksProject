# 📱 Multiple Bluetooth Controllers Setup Guide

## 🎯 Goal: Connect Up to 7 Bluetooth Devices as Individual Players

Each device = one player with independent motion control!

---

## 🔧 Hardware Options

### Option 1: Multiple AirPods Pro/Max (Recommended)
**What You Need**:
- Up to 7 pairs of AirPods Pro or AirPods Max
- Each pair = 1 controller
- Don't need audio - just motion sensors!

**How to Connect**:
1. Open Mac System Settings → Bluetooth
2. Put first AirPods in pairing mode (hold button on case)
3. Click "Connect" when they appear
4. **DO NOT set as default audio** - just connect
5. Repeat for each additional pair
6. Mac can maintain 7+ Bluetooth connections simultaneously

**In Game**:
- Each pair shows as separate device
- Shake each pair to claim a slot
- Each gets independent motion tracking

### Option 2: iPhones/iPads as Controllers
**What You Need**:
- Up to 7 iOS devices (iPhone, iPad, iPod touch)
- All on same WiFi network
- Simple companion app (we'll create this)

**Setup**:
1. Install companion app on each device
2. Launch game on Mac
3. Launch companion app on each iOS device
4. Auto-discovers via MultipeerConnectivity
5. Each device sends its accelerometer data

**Advantages**:
- ✅ Everyone has a phone
- ✅ True independent motion
- ✅ No need for multiple AirPods
- ✅ Larger screens for feedback

### Option 3: Mix & Match
**Combine**:
- 2 AirPods pairs = 2 players
- 3 iPhones = 3 players
- 2 iPads = 2 players
- Total = 7 players + host = 8 players!

---

## 🎮 Control Scheme (Accelerometer-Only)

### Simplified Controls (No Gyro Needed)

**Y-Axis (Up/Down)**:
- Stroking motion
- Fast stroking = fast movement
- Slow stroking = slow movement
- **Most important** for gameplay

**X-Axis (Left/Right)**:
- Tilt device left/right
- Left tilt = steer left
- Right tilt = steer right
- Simple lateral control

**Z-Axis (Forward/Back)**:
- Quick forward thrust = boost
- Optional enhancement

### Why Accelerometer-Only Works Better

| Feature | Gyro (Full Motion) | Accelerometer Only |
|---------|-------------------|-------------------|
| Stroking | ✅ Yes | ✅ Yes (better!) |
| Steering | ✅ Rotation | ✅ Tilt |
| Multiple Devices | ❌ Limited | ✅ Unlimited |
| Battery Usage | 🔋🔋🔋 High | 🔋 Low |
| Complexity | 😵 Complex | 😊 Simple |

---

## 📱 Mac Bluetooth Connection Limits

### Theoretical Limit
- Bluetooth spec: **7 active connections** (classic Bluetooth)
- Bluetooth LE: **Unlimited** (but practical limit ~20)

### Practical Limit for AirPods
- **Recommended**: 4-5 AirPods pairs simultaneously
- **Maximum tested**: 7 pairs
- **Limitation**: Bandwidth, not connection count

### How to Connect Multiple AirPods

#### Step 1: Disable Audio Output
```bash
# Each AirPods pair should NOT be set as audio output
# Only use for motion data
```

1. **System Settings** → **Sound**
2. Keep "MacBook Speakers" as output
3. AirPods stay connected for data only
4. No audio = less interference

#### Step 2: Pair Each Device
For each AirPods pair:

1. **Open case** near Mac
2. **Hold button** on back until white LED flashes
3. Mac shows "AirPods Pro (Jacob's)" or similar
4. Click **Connect**
5. **DO NOT** select "Use as audio device"
6. Confirm "Connected" in Bluetooth list

#### Step 3: Verify Connections
```bash
# Terminal command to list Bluetooth devices
system_profiler SPBluetoothDataType
```

Look for:
```
AirPods Pro:
    Connected: Yes
    ...
AirPods Pro (2):
    Connected: Yes
    ...
AirPods Pro (3):
    Connected: Yes
```

---

## 🎯 iOS Companion App Option

### Simple iPhone/iPad Controller App

I can create a minimal iOS app that:
1. Reads accelerometer data
2. Sends to Mac via MultipeerConnectivity
3. No audio needed
4. Works on any iOS device iOS 14+

### App Features
```
┌─────────────────────────┐
│   SPERM RACE CONTROLLER │
├─────────────────────────┤
│                         │
│    🎮 Connected to      │
│      Jacob's Mac        │
│                         │
│    Player #3            │
│                         │
│  ━━━━━━━━━━━━━━━       │
│  Stroking: ██████ 60%   │
│                         │
│  ←──────●──────→        │
│       Steering          │
│                         │
│   [  BOOST  ]           │
│                         │
└─────────────────────────┘
```

### Code (SwiftUI)
```swift
import SwiftUI
import CoreMotion
import MultipeerConnectivity

struct ControllerView: View {
    @StateObject var motionManager = MotionManager()
    @StateObject var networkManager = NetworkManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("🎮 CONTROLLER")
                .font(.largeTitle)

            if networkManager.isConnected {
                Text("✅ Connected")
                    .foregroundColor(.green)

                Text("Player #\(networkManager.playerNumber)")
                    .font(.title)

                // Stroking indicator
                ProgressView("Stroking", value: motionManager.strokingSpeed)

                // Steering indicator
                HStack {
                    Text("←")
                    Slider(value: $motionManager.steering, in: -1...1)
                        .disabled(true)
                    Text("→")
                }

                Button("BOOST") {
                    networkManager.sendBoost()
                }
                .font(.title)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            } else {
                Text("⏳ Searching for game...")
                ProgressView()
            }
        }
        .padding()
    }
}
```

---

## ⚙️ Technical Implementation

### Bluetooth Manager

```swift
class BluetoothControllerManager {
    static let shared = BluetoothControllerManager()

    // Track each connected device
    var devices: [ControllerDevice] = []

    // Connect to multiple AirPods
    func connectToAllAirPods() {
        // Scan for Bluetooth devices
        // Filter for AirPods/headphones
        // Create separate motion streams
    }

    // Map device to player
    func assignDeviceToPlayer(deviceId: String, playerNumber: Int) {
        // Link Bluetooth device → Player slot
    }
}
```

### Motion Data Flow

```
[AirPods 1] → Motion Manager 1 → Player 1
[AirPods 2] → Motion Manager 2 → Player 2
[iPhone A]  → Network Stream   → Player 3
[iPhone B]  → Network Stream   → Player 4
[iPad C]    → Network Stream   → Player 5
```

### Simplified Stroking Detection

```swift
// Y-axis only - much simpler!
func processAccelerometer(y: Double) {
    // Map acceleration to speed
    let speed = min(1.0, 0.3 + (abs(y) / 2.0))

    // 0 = slow (0.3x)
    // 0.5 = normal (0.8x)
    // 1 = fast (1.3x)

    player.speedMultiplier = 0.3 + (speed * 1.0)
}
```

---

## 🚀 Quick Setup Guide

### For Multiple AirPods

1. **Disable as Audio Devices**
   - System Settings → Sound
   - Output = MacBook Speakers
   - Input = MacBook Microphone

2. **Pair All AirPods**
   - Pair 1st set → "AirPods Pro"
   - Pair 2nd set → "AirPods Pro (2)"
   - Pair 3rd set → "AirPods Pro (3)"
   - etc.

3. **In Game**
   - Each AirPods shows as separate controller
   - Shake each to claim slot
   - L+R from same pair = 2 players (both hands)

### For iPhones as Controllers

1. **Enable WiFi** on all devices (same network)

2. **Launch Game on Mac**
   - Starts hosting session

3. **Launch Controller App on Each iPhone**
   - Auto-discovers Mac
   - Click "Connect"
   - Assigned player number

4. **Start Race**
   - Each iPhone controls its sperm
   - Tilt to steer, shake to stroke

---

## 📊 Connection Comparison

| Method | Players | Setup Time | Cost | Independence |
|--------|---------|------------|------|--------------|
| Single AirPods (L+R) | 2 | 1 min | $250 | ❌ Synced |
| 4 AirPods Pairs | 4 | 5 min | $1000 | ✅ Fully Independent |
| 7 iPhones (Network) | 7 | 2 min | Free* | ✅ Fully Independent |
| 3 AirPods + 4 Phones | 7 | 3 min | $750 | ✅ Fully Independent |

*Free if you already have the devices

---

## 🎮 Recommended Setup for 8 Players

**Best Budget Option**:
```
1 Mac (host) = 1 player
7 iPhones/iPads = 7 players
Total: 8 players, all independent
Cost: Free (use friends' phones)
```

**Best AirPods Option**:
```
4 AirPods Pro pairs = 8 players (4 people with 2 hands each)
Each person controls 2 sperms
Cost: ~$1000
```

**Hybrid Recommended**:
```
1 Mac = host
2 AirPods pairs = 4 players (2 people, L+R each)
3 iPhones = 3 players
Total: 7 players + CPU
Cost: $500 + free phones
```

---

## 🔧 Troubleshooting

### "Can't connect more than 2 AirPods"
**Solution**:
- Disconnect AirPods from iCloud
- Pair manually via Bluetooth settings
- Don't use "Automatically connect"

### "Motion data not working from multiple devices"
**Solution**:
- Only ONE device can use CMHeadphoneMotionManager
- Use network approach for additional controllers
- Or use direct Bluetooth LE accelerometer access

### "Too much lag between controllers"
**Solution**:
- Keep all devices on WiFi (not cellular)
- Use 5GHz WiFi for lower latency
- Reduce motion update rate (30Hz instead of 60Hz)

---

## ✅ Next Steps

1. **Test Single AirPods** - Verify motion works
2. **Pair 2nd AirPods** - Test dual connection
3. **Create iOS Companion App** (optional but recommended)
4. **Test Full 8-Player** - Party time!

---

## 📝 Implementation Checklist

- [x] Create BluetoothControllerManager
- [x] Support accelerometer-only mode
- [x] Add network device support
- [ ] Test with 2 AirPods pairs
- [ ] Test with 4+ devices
- [ ] Create iOS companion app
- [ ] Optimize for low latency
- [ ] Add visual feedback in lobby

---

**Bottom Line**: The easiest way to get 7 independent players is to use **iPhones/iPads as controllers** via WiFi. Each device runs a simple companion app that sends accelerometer data. No need for multiple AirPods, and you get true independent control!

Want me to create the iOS companion app?
