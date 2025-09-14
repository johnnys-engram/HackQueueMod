# Known Bugs - HackQueueMod

**Creator:** johnnys-engram  
**Version:** 1.0.0  
**Target:** Cyberpunk 2077 v1.63  
**Last Updated:** Current

## Bug Tracking System

Each bug entry includes:
- **Status:** Confirmed Bug, Fixed, API Limitation, etc.
- **Severity:** Critical, High, Medium, Low
- **Version:** Which version the bug was introduced/fixed
- **Patch:** Specific patch number (if applicable)
- **Commit:** Git commit hash or reference (if applicable)
- **Description:** Detailed bug description
- **Impact:** What the bug affects
- **Solution:** How it was fixed (for fixed bugs)

**Note:** All bugs in v1.0.0 are marked as "Initial release" since this is the first version. Future patches will include specific commit hashes and patch numbers.

## Critical Bugs

### 1. Crippling Movement Cooldown Issue
**Status:** Confirmed Bug  
**Severity:** High  
**Description:** Crippling movement quickhack doesn't activate cooldown in vanilla when used outside the queue system, but other quickhacks do activate cooldowns properly.

**Impact:**
- Players can spam crippling movement without cooldown when not using queue
- Inconsistent behavior compared to other quickhacks
- Potential balance issue

**Workaround:** None currently - To fix

**Investigation Notes:**
- Issue appears to be in base game quickhack system
- May be related to how crippling movement status effect is handled
- Requires deeper investigation into vanilla cooldown system

---

### 2. RAM Costs Not Deducted in Queue
**Status:** Confirmed Bug  
**Severity:** High  
**Description:** RAM costs are not being properly deducted when quickhacks are added to the queue system.

**Impact:**
- Players can queue unlimited quickhacks without RAM restrictions
- Breaks game balance and intended resource management
- May cause performance issues with large queues

**Technical Details:**
- RAM deduction should occur when action is queued
- Current implementation may have timing issues
- Need to verify RAM deduction in `PutActionInQueueWithKey()` method

**Workaround:** Manual RAM management required until fix

---

## API Limitations (v1.63)

### 3. QuickhackItemController API Not Available
**Status:** API Limitation  
**Severity:** Medium  
**Description:** QuickhackItemController API is not available in v1.63, requiring direct widget manipulation instead.

**Impact:**
- More complex UI updates required
- Potential for UI synchronization issues
- Limited control over individual quickhack items

**Workaround:** Using direct widget manipulation with `ForceWheelRedraw()` method

---

### 4. OnUploadCompleted Wrapper Not Available
**Status:** API Limitation  
**Severity:** Medium  
**Description:** OnUploadCompleted wrapper is not available in v1.63 API, limiting upload completion detection.

**Impact:**
- Relies on alternative upload detection methods
- May miss some upload completion events
- Less reliable than preferred implementation

**Workaround:** Using `OnUploadProgressStateChanged` event instead

---

### 5. StatPool Listener API Limited
**Status:** API Limitation  
**Severity:** Low  
**Description:** StatPool listener API is limited in v1.63, preventing proper real-time RAM monitoring.

**Impact:**
- Cannot detect RAM changes in real-time
- Must rely on manual refresh triggers
- Potential for stale UI state

**Workaround:** Manual refresh scheduling and validation

---

## Fixed Bugs (Reference)

### 6. RAM Blocking Bug - FIXED
**Status:** Fixed in v1.0.0  
**Patch:** Initial release - no separate patch  
**Commit:** N/A (part of initial implementation)  
**Description:** Quickhack wheel didn't block low-RAM hacks after queuing/reserving RAM.

**Solution:** Added explicit RAM check in RefreshQueueModUI

---

### 7. Queued Hacks Not Canceling on Death - FIXED
**Status:** Fixed in v1.0.0  
**Patch:** Initial release - no separate patch  
**Commit:** N/A (part of initial implementation)  
**Description:** Queued hacks continued to execute after target death.

**Solution:** Added death event listener and validation

---

### 8. Wheel UI Not Refreshing with Cooldown Text - FIXED
**Status:** Fixed in v1.0.0  
**Patch:** Initial release - no separate patch  
**Commit:** N/A (part of initial implementation)  
**Description:** UI didn't show "recompiling" cooldown text properly.

**Solution:** Added ForceWheelRedraw for immediate updates

---

### 9. RAM Not Immediately Deducted - FIXED
**Status:** Fixed in v1.0.0  
**Patch:** Initial release - no separate patch  
**Commit:** N/A (part of initial implementation)  
**Description:** RAM wasn't deducted immediately on selection during active queue.

**Solution:** Moved RAM deduction before path split

---

### 10. Death/Unconscious Race Condition - FIXED
**Status:** Fixed in v1.0.0  
**Patch:** Initial release - no separate patch  
**Commit:** N/A (part of initial implementation)  
**Description:** Race condition could cause execution on dead/unconscious targets.

**Solution:** Added final death check before ProcessRPGAction execution

---

### 11. Cooldown UI Not Updating - FIXED
**Status:** Fixed in v1.0.0  
**Patch:** Initial release - no separate patch  
**Commit:** N/A (part of initial implementation)  
**Description:** Cooldown UI states didn't update immediately after application.

**Solution:** Added ForceWheelRedraw for immediate visual updates

---

### 12. Intent Pollution Causing Double Execution - FIXED
**Status:** Fixed in v1.0.0  
**Patch:** Initial release - no separate patch  
**Commit:** N/A (part of initial implementation)  
**Description:** Intent storage for non-queued hacks caused double execution.

**Solution:** Removed intent storage for non-queued hacks

---

## Removed/Deprecated Features

### 13. Intent System - REMOVED
**Status:** Removed  
**Description:** Intent system was redundant with queued actions and caused issues.

**Reason:** Simplified architecture and removed double execution bugs

---

### 14. Speed Modifier System - REMOVED
**Status:** Removed  
**Description:** Speed modifier system was incorrectly modifying RAM instead of upload speed.

**Reason:** Incorrect implementation that affected game balance

---

### 15. GC Registration - REMOVED
**Status:** Removed  
**Description:** GC registration was placeholder code providing no actual protection.

**Reason:** Non-functional code that provided false security

---

### 16. Persistence System - REMOVED
**Status:** Removed  
**Description:** Queue persistence across scanner toggles was removed.

**Reason:** Queues shouldn't persist across scanner state changes

---

### 17. Flash Reset Callback - REMOVED
**Status:** Removed  
**Description:** Flash reset callback removed due to v1.63 API limitations.

**Reason:** API not available in v1.63

---

### 18. ExecuteQueuedEntryViaUI - REMOVED
**Status:** Removed  
**Description:** ExecuteQueuedEntryViaUI would cause infinite recursion.

**Reason:** Architecture conflict with ApplyQuickHack wrapper

---

## TODO Items

### 19. Dynamic Queue Size Based on Perks/Cyberware
**Status:** Planned  
**Description:** Queue size should be dynamic based on player perks and cyberware.

**Implementation:** Check perk tree for queue size bonuses, equipped cyberdeck capacity, cyberware modifications

---

### 20. Visual HUD Overlay Integration
**Status:** Planned  
**Description:** Add visual HUD overlays to show queue status.

**Implementation:** Small stack icons near enemy health bar, progress bar showing upload progress, queue count indicator

---

### 21. Proper Notification System
**Status:** Planned  
**Description:** Implement proper notification system for queue events.

**Implementation:** UI notifications for queue cancellations, RAM refunds, execution confirmations

---

### 22. Perk Tree Integration
**Status:** Planned  
**Description:** Integrate with perk trees for queue size bonuses.

**Implementation:** Check specific perks that affect quickhack capabilities

---

### 23. Cyberdeck Queue Capacity Integration
**Status:** Planned  
**Description:** Integrate with cyberdeck modifications for queue capacity.

**Implementation:** Check equipped cyberdeck stats for queue capacity bonuses

---

## Testing Notes

### Known Test Cases
1. **Crippling Movement Test:** Verify cooldown behavior outside queue vs inside queue
2. **RAM Deduction Test:** Verify RAM is properly deducted when queuing actions
3. **Death Detection Test:** Verify queue clears when target dies
4. **UI Refresh Test:** Verify UI updates properly after queue changes
5. **Race Condition Test:** Verify no execution on dead targets

### Edge Cases
- Multiple quickhacks queued simultaneously
- Target death during upload
- RAM exhaustion scenarios
- UI state synchronization during rapid changes
- Mod conflicts with other quickhack modifications

## Reporting Bugs

When reporting new bugs, please include:
1. **Reproduction Steps:** Detailed steps to reproduce the issue
2. **Expected Behavior:** What should happen
3. **Actual Behavior:** What actually happens
4. **Game Version:** Confirm v1.63
5. **Mod Version:** Current HackQueueMod version
6. **Other Mods:** List any other mods that might conflict
7. **Logs:** Include relevant debug log entries

## Contact

For bug reports or questions, contact johnnys-engram or reference this documentation.
