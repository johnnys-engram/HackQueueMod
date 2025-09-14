# HackQueueMod Changelog

## Version 1.0.0 - Initial Release
**Creator:** johnnys-engram  
**Target:** Cyberpunk 2077 v1.63  
**Framework:** redscript 0.5.14

### Core Features
- Queue system for quickhacks during upload/cooldown periods
- RAM management with proper deduction and refunds
- UI integration with quickhack wheel
- Target death detection and queue cleanup
- Support for both NPC and Device targets

### Technical Implementation
- **Phase 1:** Core Queue Foundation & Target Resolution & Action Binding
- **Phase 2:** Execution Pipeline & Upload Tracking  
- **Phase 3:** UI Integration & Queue Management
- **Phase 4:** Polish & Bug Fixes

### Bug Fixes (v1.63)
- Fixed RAM blocking bug where quickhack wheel doesn't block low-RAM hacks after queuing
- Fixed queued hacks not canceling on target death
- Fixed wheel UI not refreshing with "recompiling" cooldown text
- Fixed RAM not immediately deducted on selection during active queue

### Improvements & Fixes (v1.63)
- Enhanced death event listener with proper validation
- Improved UI controller access with fallback methods
- Added RAM validation before deduction
- Fixed cooldown UI state for proper grayed display
- Removed redundant RAM deduction from intent storage
- Updated upload speed modifier to use appropriate stat pool
- Enhanced persistence validation with proper TweakDBID checking

### Architectural Fixes (v1.63)
- **Fix 1:** Death Registration - Added OnGameAttached lifecycle method
- **Fix 2:** RAM Deduction - Moved RAM deduction BEFORE path split
- **Fix 3:** UI Refresh - Added ScheduleUIRefresh for active UI updates
- **Fix 4:** Queue Validation - Enhanced ValidateQueueIntegrity to halt execution

### Critical Bug Fixes (v1.63)
- **Bug 1:** Death/Unconscious Race Condition - Added final death check before execution
- **Bug 2:** Cooldown UI Not Updating - Added ForceWheelRedraw for immediate updates
- **Bug 3:** Event-Driven Cleanup - Added OnStatusEffectApplied listener

### Missing UI Effect Fixes (v1.63)
- **UI Effect 1:** Screen Flash & Sound - Added TriggerQuickhackUIFeedback
- **UI Effect 2:** Vanilla UI Flow - Added ExecuteQueuedEntryViaUI
- **UI Effect 3:** HUD Notifications - Added proper feedback system

### Technical Notes
- Simplified queue entry system for v1.63 compatibility
- Using integer constants for v1.63 compatibility
- Single array replaces three parallel arrays
- Comprehensive validation with atomic operations
- Emergency recovery with event-driven cleanup
- Delay Event Classes for proper sequencing
- UI Refresh Helper for v1.63 compatibility
- Core helper with v1.63-compatible patterns
- Entity Field Extensions using v1.63 pattern
- Device Upload Bypass Wrapper for v1.63
- NPC Upload Detection & Queue Processing with v1.63 syntax
- Queue Execution on Upload Completion with v1.63 syntax
- Player-level upload completion hook (Phase 3)
- ScriptableDeviceAction extensions
- Debug Logging for UI Refresh
- PlayerPuppet Integration for Queue Helper Access
- UI Integration & Queue Management
- UI Upload Detection Methods - v1.63 Compatible
- Cooldown Detection and Management
- Core ApplyQuickHack Integration - DIRECT ACCESS ONLY
- Action Reconstruction Methods
- UI Support Methods

### Removed Features
- Intent system (redundant with queued actions)
- Speed modifier system (was modifying RAM instead of upload speed)
- GC registration (placeholder code provided no actual protection)
- Persistence system (queues shouldn't persist across scanner toggles)
- Flash reset callback (v1.63 API limitations)
- ExecuteQueuedEntryViaUI (would cause infinite recursion)
- ReverseQuickhackEffects (using queue locking instead of rollback)
- OnUploadCompleted wrapper (not available in v1.63 API)

### Framework Dependencies
- **redscript 0.5.14** - Core logic, stats, persistence
- **RED4ext 1.15.0** - Engine access when redscript lacks capability
- **CET 1.25.2** - Runtime overlays, debug only (NOT core logic)
- **TweakXL 1.2.1** - Static data changes only
- **ArchiveXL 1.5.11** - UI/assets only

### Safety Patterns
- Null check EVERY Game.GetPlayer(), vehicle, world object interaction
- Log all hook attempts: LogChannel("ModName", "Hook attempt: " + className)
- Version gate at startup with pin verification
- No heavy logic in CET onUpdate loops - throttle with timers
- ImGui Begin/End calls must be balanced
- Unique hotkey IDs only

### Known Issues
- **Critical Bug:** Crippling movement doesn't activate cooldown in vanilla outside queue
- **Critical Bug:** RAM costs not properly deducted when queuing quickhacks
- See [KNOWN_BUGS.md](KNOWN_BUGS.md) for complete list of known issues and API limitations

### Future Plans
- Implement JE_ prefix system for mod safety
- Dynamic queue size based on perks/cyberware
- Visual HUD overlay integration
- Proper notification system
- Perk tree integration for queue size bonuses
- Cyberdeck queue capacity integration
- Cyberware modifications support
