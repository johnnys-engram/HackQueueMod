# Debug Logging Guide for HackQueueMod

## 🎯 **Quick Setup for RAM & Quickhack Debugging**

### Current Settings (Perfect for your needs):
```redscript
let DEBUG_QUEUE_MOD: Bool = true;
let DEBUG_RAM: Bool = true;          // ✅ RAM operations
let DEBUG_QUICKHACK: Bool = true;    // ✅ Quickhack activation/execution  
let DEBUG_UI: Bool = false;          // ❌ UI operations (disabled - no more UI spam!)
let DEBUG_QUEUE: Bool = false;       // ❌ Queue operations (disabled)
let DEBUG_EVENTS: Bool = false;      // ❌ Event handling (disabled)
```

**✅ FIXED**: All UI refresh spam has been moved to the "UI" category and is now filtered out!

## 📋 **Logging Categories Explained**

### 🔋 **DEBUG_RAM** (Currently ENABLED)
Shows:
- RAM deduction when quickhacks are selected
- RAM refunds when actions are cleared
- RAM changes during queue operations
- Insufficient RAM errors

Example output:
```
[RAM] RAM deducted for quickhack: 8
[RAM] Changed RAM by: -8.0 (new total should be updated)
[RAM] Refunded RAM: 8
```

### ⚡ **DEBUG_QUICKHACK** (Currently ENABLED)
Shows:
- Quickhack execution when upload completes
- Action processing (ScriptableDeviceAction vs PuppetAction)
- Target validation during execution
- Execution failures and errors

Example output:
```
[QUICKHACK] Upload complete for NPC=Gang Member processing queue
[QUICKHACK] Executing queued action: class=ScriptableDeviceAction on NPC=Gang Member
[QUICKHACK] Executing ScriptableDeviceAction: QuickHack.OverheatHack
```

### 🖥️ **DEBUG_UI** (Currently DISABLED)
Shows:
- UI refresh operations
- Wheel redraws
- Controller cache operations
- UI state changes

### 📦 **DEBUG_QUEUE** (Currently DISABLED)
Shows:
- Queue add/remove operations
- Queue validation
- Queue integrity checks
- Queue size changes

### 📡 **DEBUG_EVENTS** (Currently DISABLED)
Shows:
- Event handling callbacks
- Status effect applications
- Death detection events
- Upload progress events

## 🔧 **How to Change Settings**

### To focus ONLY on RAM issues:
```redscript
let DEBUG_RAM: Bool = true;
let DEBUG_QUICKHACK: Bool = false;
let DEBUG_UI: Bool = false;
let DEBUG_QUEUE: Bool = false;
let DEBUG_EVENTS: Bool = false;
```

### To focus ONLY on quickhack execution:
```redscript
let DEBUG_RAM: Bool = false;
let DEBUG_QUICKHACK: Bool = true;
let DEBUG_UI: Bool = false;
let DEBUG_QUEUE: Bool = false;
let DEBUG_EVENTS: Bool = false;
```

### To see everything (development mode):
```redscript
let DEBUG_RAM: Bool = true;
let DEBUG_QUICKHACK: Bool = true;
let DEBUG_UI: Bool = true;
let DEBUG_QUEUE: Bool = true;
let DEBUG_EVENTS: Bool = true;
```

### To disable all debug logs (production mode):
```redscript
let DEBUG_QUEUE_MOD: Bool = false;
// All other flags are ignored when DEBUG_QUEUE_MOD is false
```

## 📍 **Where to Edit**

Edit the flags in `HackQueueMod.reds` at lines 33-38:
```redscript
public func QueueModLog(level: CName, category: CName, message: String) -> Void {
    // Development debug flags - set to false for production builds
    let DEBUG_QUEUE_MOD: Bool = true;
    let DEBUG_RAM: Bool = true;          // ← Change this
    let DEBUG_QUICKHACK: Bool = true;    // ← Change this
    let DEBUG_UI: Bool = false;          // ← Change this
    let DEBUG_QUEUE: Bool = false;       // ← Change this
    let DEBUG_EVENTS: Bool = false;      // ← Change this
```

## 🎯 **Current Perfect Setup for Your Needs**

You currently have:
- ✅ **RAM operations** - You'll see all RAM deduction/refund operations
- ✅ **Quickhack execution** - You'll see when quickhacks actually execute
- ❌ **UI noise** - No UI refresh spam
- ❌ **Queue noise** - No queue operation spam
- ❌ **Event noise** - No event handling spam

This gives you clean, focused logs showing exactly what you want: RAM operations and quickhack activation!
