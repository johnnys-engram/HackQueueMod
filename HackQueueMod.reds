// =============================================================================
// HackQueueMod v1.0.0
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// 
// Queue system for quickhacks during upload/cooldown periods
// See CHANGELOG.md for detailed version history and bug fixes
// =============================================================================

// Version constants for mod management
public func GetHackQueueModVersion() -> String {
    return "1.0.0";
}

public func GetHackQueueModCreator() -> String {
    return "johnnys-engram";
}

public func GetHackQueueModTargetVersion() -> String {
    return "Cyberpunk 2077 v1.63";
}

// Queue entry system for v1.63 compatibility
public class QueueModEntry {
    public let action: ref<DeviceAction>;
    public let fingerprint: String;
    public let timestamp: Float;
    public let entryType: Int32;
    public let ramCost: Int32;
}

public func CreateQueueModEntry(action: ref<DeviceAction>, key: String, cost: Int32) -> ref<QueueModEntry> {
    let entry: ref<QueueModEntry> = new QueueModEntry();
    entry.action = action;
    entry.fingerprint = key;
    entry.entryType = 0;
    entry.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
    entry.ramCost = cost;
    return entry;
}

public class QueueModActionQueue {
    private let m_queueEntries: array<ref<QueueModEntry>>;
    private let m_isQueueLocked: Bool;
    private let m_maxQueueSize: Int32;
    
    public func Initialize() -> Void {
        this.m_isQueueLocked = false;
        this.m_maxQueueSize = this.CalculateMaxQueueSize();
        LogChannel(n"DEBUG", s"[QueueMod] Queue initialized with max size: \(this.m_maxQueueSize)");
    }
    
    private func CalculateMaxQueueSize() -> Int32 {
        // Base queue size - TODO: implement dynamic sizing based on perks/cyberware
        return 3;
    }

    public func PutActionInQueue(action: ref<DeviceAction>) -> Bool {
        if !IsDefined(action) || this.m_isQueueLocked || ArraySize(this.m_queueEntries) >= this.m_maxQueueSize {
            return false;
        }
        
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let autoKey: String = s"auto::\(TDBID.ToStringDEBUG(sa.GetObjectActionID()))::\(GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp())";
            return this.PutActionInQueueWithKey(action, autoKey);
        }
        return false;
    }

    public func PutActionInQueueWithKey(action: ref<DeviceAction>, key: String) -> Bool {
        // Validation checks
        if !IsDefined(action) || this.m_isQueueLocked || ArraySize(this.m_queueEntries) >= this.m_maxQueueSize {
            return false;
        }
        
        // Check for duplicates
        let i: Int32 = 0;
        let maxIterations: Int32 = 100;
        while i < ArraySize(this.m_queueEntries) && i < maxIterations {
            if IsDefined(this.m_queueEntries[i]) && Equals(this.m_queueEntries[i].fingerprint, key) {
                LogChannel(n"DEBUG", s"[QueueMod] Duplicate key rejected: \(key)");
                return false;
            }
            i += 1;
        }
        
        // Create and insert entry
        let ramCost: Int32 = 0;
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        let pa: ref<PuppetAction> = action as PuppetAction;
        
        if IsDefined(sa) {
            ramCost = this.QM_GetRamCostFromAction(sa);
        } else if IsDefined(pa) {
            // PuppetActions might have costs too
            ramCost = pa.GetCost();
        }
        
        let entry: ref<QueueModEntry> = CreateQueueModEntry(action, key, ramCost);
        if !IsDefined(entry) {
            LogChannel(n"ERROR", "[QueueMod] Failed to create queue entry");
            return false;
        }
        
        // CRITICAL: Validate action identity before queuing
        let actionID: TweakDBID = TDBID.None();
        if IsDefined(sa) {
            actionID = sa.GetObjectActionID();
            LogChannel(n"DEBUG", s"[QueueMod] Queuing ScriptableDeviceAction: \(TDBID.ToStringDEBUG(actionID))");
        } else if IsDefined(pa) {
            actionID = pa.GetObjectActionID();
            LogChannel(n"DEBUG", s"[QueueMod] Queuing PuppetAction: \(TDBID.ToStringDEBUG(actionID))");
        }
        
        if !TDBID.IsValid(actionID) {
            LogChannel(n"ERROR", "[QueueMod] Action has invalid TweakDBID - cannot queue");
            return false;
        }
        
        // PHASE 3: RAM now deducted on selection, not on queue (for immediate feedback)
        // Note: ReserveRAMForAction removed - RAM deducted in ApplyQuickHack instead
        
        // Note: GC registration removed - was placeholder code
        
        ArrayPush(this.m_queueEntries, entry);
        LogChannel(n"DEBUG", s"[QueueMod] Entry added atomically: \(key), actionID=\(TDBID.ToStringDEBUG(actionID)), size=\(ArraySize(this.m_queueEntries))");
        return true;
    }

    public func PopNextEntry() -> ref<QueueModEntry> {
        if ArraySize(this.m_queueEntries) == 0 {
            return null;
        }
        
        let entry: ref<QueueModEntry> = this.m_queueEntries[0];
        if !IsDefined(entry) {
            LogChannel(n"ERROR", "[QueueMod] Null entry detected - clearing queue for safety");
            this.ClearQueue();
            return null;
        }
        
        ArrayErase(this.m_queueEntries, 0);
        LogChannel(n"DEBUG", s"[QueueMod] Entry popped: type=\(entry.entryType) fingerprint=\(entry.fingerprint)");
        return entry;
    }

    public func PopActionInQueue() -> ref<DeviceAction> {
        let entry: ref<QueueModEntry> = this.PopNextEntry();
        if IsDefined(entry) && Equals(entry.entryType, 0) && IsDefined(entry.action) {
            return entry.action;
        }
        return null;
    }

    public func GetQueueSize() -> Int32 {
        return ArraySize(this.m_queueEntries);
    }
    
    public func GetQueueEntry(index: Int32) -> ref<QueueModEntry> {
        if index >= 0 && index < ArraySize(this.m_queueEntries) {
            return this.m_queueEntries[index];
        }
        return null;
    }

    public func ClearQueue() -> Void {
        // Refund RAM for all queued actions before clearing
        let i: Int32 = 0;
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if IsDefined(entry) && Equals(entry.entryType, 0) && entry.ramCost > 0 {
                // Use tracked RAM cost instead of recalculating
                this.QM_ChangeRam(GetGameInstance(), Cast<Float>(entry.ramCost));
                LogChannel(n"DEBUG", s"[QueueMod] Refunded RAM: \(entry.ramCost)");
            }
            i += 1;
        }
        
        ArrayClear(this.m_queueEntries);
        LogChannel(n"DEBUG", "[QueueMod] Queue cleared - RAM refunded");
    }

    public func ClearQueue(gameInstance: GameInstance, targetID: EntityID) -> Void {
        this.ClearQueue(); // Call the base clear method
        
        // ✅ ADD THIS: Force refresh after clearing
        QuickhackQueueHelper.ForceQuickhackUIRefresh(gameInstance, targetID);
    }

    public func LockQueue() -> Void {
        this.m_isQueueLocked = true;
    }

    public func UnlockQueue() -> Void {
        this.m_isQueueLocked = false;
    }

    // Note: Intent management methods removed - redundant with queued actions

    // PHASE 4: Emergency Recovery with Event-Driven Cleanup
    public func ValidateQueueIntegrity() -> Bool {
        let isValid: Bool = true;
        let i: Int32 = 0;
        let cleanupNeeded: Bool = false;
        
        // PHASE 4A: Comprehensive validation scan
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if !IsDefined(entry) {
                LogChannel(n"ERROR", s"[QueueMod] Null entry at index \(i)");
                cleanupNeeded = true;
                isValid = false;
            } else if Equals(entry.entryType, 0) && !IsDefined(entry.action) {
                LogChannel(n"ERROR", s"[QueueMod] Invalid action at index \(i): \(entry.fingerprint)");
                cleanupNeeded = true;
                isValid = false;
            }
            i += 1;
        }
        
        // PHASE 4B: Immediate recovery (v1.63 pattern)
        if cleanupNeeded {
            LogChannel(n"ERROR", "[QueueMod] Queue corruption detected - executing emergency cleanup");
            this.EmergencyCleanup();
        }
        
        return isValid;
    }

    private func EmergencyCleanup() -> Void {
        // Create clean array with only valid entries
        let cleanEntries: array<ref<QueueModEntry>>;
        let i: Int32 = 0;
        
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if IsDefined(entry) {
                if Equals(entry.entryType, 0) && IsDefined(entry.action) {
                    // ADD: Validate action is still usable
                    let sa: ref<ScriptableDeviceAction> = entry.action as ScriptableDeviceAction;
                    if IsDefined(sa) && TDBID.IsValid(sa.GetObjectActionID()) {
                        ArrayPush(cleanEntries, entry);
                    }
                }
            }
            i += 1;
        }
        
        // Atomic replacement
        ArrayClear(this.m_queueEntries);
        this.m_queueEntries = cleanEntries;
        
        LogChannel(n"DEBUG", s"[QueueMod] Emergency cleanup complete - \(ArraySize(this.m_queueEntries)) entries recovered");
    }
    
    // RAM Cost Reservation System (Real v1.63 Implementation)
    private func ReserveRAMForAction(action: ref<DeviceAction>) -> Bool {
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if !IsDefined(sa) {
            return true; // Non-ScriptableDeviceAction doesn't use RAM
        }
        
        let cost: Int32 = this.QM_GetRamCostFromAction(sa);
        if cost <= 0 {
            return true; // No RAM cost
        }
        
        // Deduct immediately (negative delta)
        if this.QM_ChangeRam(GetGameInstance(), -Cast<Float>(cost)) {
            LogChannel(n"DEBUG", s"[QueueMod] Reserved RAM \(cost)");
            return true;
        }
        return false;
    }
    
    private func RefundRAMForAction(action: ref<DeviceAction>) -> Void {
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if !IsDefined(sa) {
            return; // Non-ScriptableDeviceAction doesn't use RAM
        }
        
        let cost: Int32 = this.QM_GetRamCostFromAction(sa);
        if cost > 0 {
            this.QM_ChangeRam(GetGameInstance(), Cast<Float>(cost));
            LogChannel(n"DEBUG", s"[QueueMod] Refunded RAM \(cost)");
        }
    }
    
    // RAM Helper Methods
    private func QM_GetPlayer(game: GameInstance) -> ref<PlayerPuppet> {
        let ps: ref<PlayerSystem> = GameInstance.GetPlayerSystem(game);
        return IsDefined(ps) ? ps.GetLocalPlayerMainGameObject() as PlayerPuppet : null;
    }
    
    private func QM_GetRamCostFromAction(action: ref<ScriptableDeviceAction>) -> Int32 {
        if !IsDefined(action) {
            return 0;
        }
        let cost: Int32 = action.GetCost();
        return Max(cost, 0); // Safe fallback
    }
    
    private func QM_ChangeRam(game: GameInstance, delta: Float) -> Bool {
        // v1.63-safe: adjust Memory pool directly on player
        let player: ref<PlayerPuppet> = this.QM_GetPlayer(game);
        if !IsDefined(player) {
            return false;
        }
        let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);
        let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
        // Subtract when delta < 0, add back when delta > 0
        sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, delta, player, false);
        return true;
    }
    
    // Note: GC registration removed - placeholder code provided no actual protection
    
    // Note: Speed modifier system removed - was modifying RAM instead of upload speed
}

// Note: QueueModIntent class removed - redundant with queued actions

// Queue Event for State Synchronization
public class QueueModEvent extends Event {
    public let eventType: CName;
    public let quickhackData: ref<QuickhackData>;
    public let timestamp: Float;
    
    public func Create(eventType: CName, data: ref<QuickhackData>) -> ref<QueueModEvent> {
        let event: ref<QueueModEvent> = new QueueModEvent();
        event.eventType = eventType;
        event.quickhackData = data;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}


// Global state removed - using per-puppet storage only

// Note: Flash reset callback removed due to v1.63 API limitations
// Using simplified approach without delayed callback

// ✅ CRITICAL FIX: Delay Event Classes for Proper Sequencing
public class QueueModCommandGenEvent extends Event {
    public let targetID: EntityID;
    public let timestamp: Float;
    
    public func Create(targetID: EntityID) -> ref<QueueModCommandGenEvent> {
        let event: ref<QueueModCommandGenEvent> = new QueueModCommandGenEvent();
        event.targetID = targetID;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}

public class QueueModCacheEvent extends Event {
    public let targetID: EntityID;
    public let timestamp: Float;
    
    public func Create(targetID: EntityID) -> ref<QueueModCacheEvent> {
        let event: ref<QueueModCacheEvent> = new QueueModCacheEvent();
        event.targetID = targetID;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}

public class QueueModValidationEvent extends Event {
    public let targetID: EntityID;
    public let timestamp: Float;
    
    public func Create(targetID: EntityID) -> ref<QueueModValidationEvent> {
        let event: ref<QueueModValidationEvent> = new QueueModValidationEvent();
        event.targetID = targetID;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}


// UI Refresh Helper for v1.63
public class QuickhackQueueHelper {
    public static func RefreshQuickhackWheel(action: ref<ScriptableDeviceAction>) -> Void {
        let gameInstance: GameInstance;
        let targetID: EntityID;
        
        if !IsDefined(action) {
            LogChannel(n"DEBUG", "[QueueMod] Cannot refresh - action is null");
            return;
        }
        
        // Get the game instance from the action
        gameInstance = GetGameInstance();
        
        // Get the target entity ID (the device/NPC being hacked)
        targetID = action.GetRequesterID();
        
        LogChannel(n"DEBUG", s"[QueueMod] Refreshing UI for target: \(EntityID.ToDebugString(targetID))");
        
        // Use the force refresh bypass method
        QuickhackQueueHelper.ForceQuickhackUIRefresh(gameInstance, targetID);
    }

    // Phase 2: Create Bypass Method - Force UI Refresh with Proper Sequencing
    public static func ForceQuickhackUIRefresh(gameInstance: GameInstance, targetID: EntityID) -> Void {
        LogChannel(n"DEBUG", s"[QueueMod] ForceQuickhackUIRefresh called for target: \(EntityID.ToDebugString(targetID))");
        
        // Try vanilla method first (fast path)
        QuickhackModule.RequestRefreshQuickhackMenu(gameInstance, targetID);
        
        // ✅ CRITICAL FIX: Use proper delay event sequencing for v1.63 async processing
        QuickhackQueueHelper.ScheduleSequencedRefresh(gameInstance, targetID);
        
        LogChannel(n"DEBUG", "[QueueMod] Force refresh scheduled with proper sequencing");
    }

    // ✅ CRITICAL FIX: Proper Delay Event Sequencing for v1.63
    public static func ScheduleSequencedRefresh(gameInstance: GameInstance, targetID: EntityID) -> Void {
        LogChannel(n"DEBUG", s"[QueueMod] Scheduling sequenced refresh for: \(EntityID.ToDebugString(targetID))");
        
        // Step 1: Schedule command generation with injection (0.05s delay)
        let genEvent: ref<QueueModCommandGenEvent> = new QueueModCommandGenEvent();
        genEvent.targetID = targetID;
        genEvent.timestamp = GameInstance.GetTimeSystem(gameInstance).GetGameTimeStamp();
        GameInstance.GetDelaySystem(gameInstance).DelayEvent(null, genEvent, 0.05);
        
        // Step 2: Schedule cache clearing with repopulation (0.1s delay)
        let cacheEvent: ref<QueueModCacheEvent> = new QueueModCacheEvent();
        cacheEvent.targetID = targetID;
        cacheEvent.timestamp = GameInstance.GetTimeSystem(gameInstance).GetGameTimeStamp();
        GameInstance.GetDelaySystem(gameInstance).DelayEvent(null, cacheEvent, 0.1);
        
        // Step 3: Schedule fallback validation (0.2s delay)
        let validationEvent: ref<QueueModValidationEvent> = new QueueModValidationEvent();
        validationEvent.targetID = targetID;
        validationEvent.timestamp = GameInstance.GetTimeSystem(gameInstance).GetGameTimeStamp();
        GameInstance.GetDelaySystem(gameInstance).DelayEvent(null, validationEvent, 0.2);
        
        LogChannel(n"DEBUG", "[QueueMod] Sequenced refresh scheduled: Gen(0.05s) -> Cache(0.1s) -> Validation(0.2s)");
    }

    // Phase 3: Force Fresh Command Generation with Proper Injection
    public static func ForceFreshCommandGeneration(gameInstance: GameInstance, targetID: EntityID) -> Void {
        LogChannel(n"DEBUG", s"[QueueMod] ForceFreshCommandGeneration called for: \(EntityID.ToDebugString(targetID))");
        
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;
        if !IsDefined(targetObject) {
            LogChannel(n"ERROR", "[QueueMod] Target not found for fresh command generation");
            return;
        }
        
        // Check if it's a ScriptedPuppet (NPC)
        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if IsDefined(puppet) {
            LogChannel(n"DEBUG", "[QueueMod] Forcing fresh puppet commands with injection");
            // Force fresh puppet commands
            let actions: array<ref<PuppetAction>>;
            let commands: array<ref<QuickhackData>>;
            puppet.TranslateChoicesIntoQuickSlotCommands(actions, commands);
            LogChannel(n"DEBUG", s"[QueueMod] Generated \(ArraySize(commands)) fresh puppet commands");
            
            // ✅ CRITICAL FIX: Inject commands via RevealInteractionWheel event
            QuickhackQueueHelper.InjectCommandsViaEvent(gameInstance, targetObject, commands);
            return;
        }
        
        // Check if it's a Device
        let device: ref<Device> = targetObject as Device;
        if IsDefined(device) {
            LogChannel(n"DEBUG", "[QueueMod] Forcing fresh device commands with injection");
            // Force fresh device commands
            let actions: array<ref<DeviceAction>>;
            let context: GetActionsContext;
            device.GetDevicePS().GetQuickHackActions(actions, context);
            LogChannel(n"DEBUG", s"[QueueMod] Generated \(ArraySize(actions)) fresh device commands");
            
            // ✅ CRITICAL FIX: Convert device actions to quickhack commands and inject
            let commands: array<ref<QuickhackData>>;
            QuickhackQueueHelper.ConvertDeviceActionsToCommands(actions, commands);
            QuickhackQueueHelper.InjectCommandsViaEvent(gameInstance, targetObject, commands);
            return;
        }
        
        LogChannel(n"ERROR", s"[QueueMod] Unknown target type: \(ToString(targetObject.GetClassName()))");
    }

    // Critical Missing Piece: Proper Command Injection
    public static func InjectCommandsViaEvent(gameInstance: GameInstance, targetObject: ref<GameObject>, commands: array<ref<QuickhackData>>) -> Void {
        LogChannel(n"DEBUG", s"[QueueMod] Injecting \(ArraySize(commands)) commands via RevealInteractionWheel event");
        
        // Create RevealInteractionWheel event with fresh commands
        let revealEvent: ref<RevealInteractionWheel> = new RevealInteractionWheel();
        revealEvent.commands = commands;  // Use the generated commands
        revealEvent.shouldReveal = true;
        revealEvent.lookAtObject = targetObject;
        
        // Queue the event to inject fresh commands into UI system
        GameInstance.GetUISystem(gameInstance).QueueEvent(revealEvent);
        
        LogChannel(n"DEBUG", "[QueueMod] Commands injected successfully via RevealInteractionWheel event");
    }

    // Helper: Convert Device Actions to Quickhack Commands
    public static func ConvertDeviceActionsToCommands(actions: array<ref<DeviceAction>>, out commands: array<ref<QuickhackData>>) -> Void {
        LogChannel(n"DEBUG", s"[QueueMod] Converting \(ArraySize(actions)) device actions to quickhack commands");
        
        let i: Int32 = 0;
        while i < ArraySize(actions) {
            let action: ref<DeviceAction> = actions[i];
            if IsDefined(action) {
                // Create QuickhackData from DeviceAction
                let quickhackData: ref<QuickhackData> = new QuickhackData();
                // Note: m_action expects BaseScriptableAction, but DeviceAction may not be compatible
                // Leave m_action null for now - the important data is in title, cost, and type
                
                // Note: DeviceAction API is limited in v1.63, use safe fallbacks
                let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
                if IsDefined(sa) {
                    quickhackData.m_cost = sa.GetCost();
                    quickhackData.m_title = TDBID.ToStringDEBUG(sa.GetObjectActionID()); // Convert to String
                    quickhackData.m_type = gamedataObjectActionType.MinigameUpload; // Use available enum type
                    LogChannel(n"DEBUG", s"[QueueMod] Converted ScriptableDeviceAction: \(TDBID.ToStringDEBUG(sa.GetObjectActionID()))");
                } else {
                    // Fallback for other device action types
                    quickhackData.m_cost = 0;
                    quickhackData.m_title = "Unknown"; // Use String literal
                    quickhackData.m_type = gamedataObjectActionType.MinigameUpload; // Use available enum type
                    LogChannel(n"DEBUG", s"[QueueMod] Converted unknown device action type: \(action.GetClassName())");
                }
                
                ArrayPush(commands, quickhackData);
            }
            i += 1;
        }
        
        LogChannel(n"DEBUG", s"[QueueMod] Converted \(ArraySize(commands)) device actions to commands");
    }

    // Phase 4: Clear Controller Cache
    public static func ClearControllerCache(gameInstance: GameInstance, targetID: EntityID) -> Void {
        LogChannel(n"DEBUG", s"[QueueMod] ClearControllerCache called for: \(EntityID.ToDebugString(targetID))");
        
        // Get the player and controller
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            LogChannel(n"ERROR", "[QueueMod] Player not found for cache clearing");
            return;
        }
        
        let controller: ref<QuickhacksListGameController> = player.GetQuickhacksListGameController();
        if !IsDefined(controller) {
            LogChannel(n"ERROR", "[QueueMod] Controller not found for cache clearing");
            return;
        }
        
        // Clear controller cache using the new method
        controller.ClearControllerCacheInternal();
        LogChannel(n"DEBUG", "[QueueMod] Controller cache cleared");
    }
}

// Core helper with v1.63-compatible patterns
public class QueueModHelper {

    public func PutInQuickHackQueue(action: ref<DeviceAction>) -> Bool {
        LogChannel(n"DEBUG", "[QueueMod] *** QUEUE SYSTEM ACTIVATED ***");
        if !IsDefined(action) {
            LogChannel(n"DEBUG", "[QueueMod] No action provided to queue");
            return false;
        }

        LogChannel(n"DEBUG", s"[QueueMod] Attempting to queue action: \(action.GetClassName())");

        // Prefer PuppetAction (NPC) to ensure NPC queue receives the action
        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            let requesterID: EntityID = pa.GetRequesterID();
            LogChannel(n"DEBUG", s"[QueueMod][Queue] Route: NPC queue, requesterID=\(ToString(requesterID))");
            return this.QueueActionOnPuppet(pa);
        }

        // Otherwise, fall back to ScriptableDeviceAction (devices, terminals, etc.)
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            LogChannel(n"DEBUG", s"[QueueMod][Queue] Route: Action's internal queue, actionType=\(action.GetClassName())");
            return sa.QueueModQuickHack(action);
        }

        LogChannel(n"DEBUG", "[QueueMod] Unknown action type - cannot queue");
        return false;
    }

    public func PutInQuickHackQueueWithKey(action: ref<DeviceAction>, key: String) -> Bool {
        LogChannel(n"DEBUG", s"[QueueMod] *** QUEUE SYSTEM WITH KEY ACTIVATED *** key=\(key)");
        if !IsDefined(action) {
            LogChannel(n"DEBUG", "[QueueMod] No action provided to queue");
            return false;
        }

        LogChannel(n"DEBUG", s"[QueueMod] Attempting to queue action: \(action.GetClassName()) with key=\(key)");

        // Prefer PuppetAction (NPC) for key-based queuing
        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            let targetID: EntityID = pa.GetRequesterID();
            let gameInstance: GameInstance = pa.GetExecutor().GetGame();
            let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;
            let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
            if IsDefined(puppet) {
                let queue: ref<QueueModActionQueue> = puppet.GetQueueModActionQueue();
                if IsDefined(queue) {
                    // FIX: Handle validation failure properly
                    if !queue.ValidateQueueIntegrity() {
                        LogChannel(n"ERROR", "[QueueMod] Queue validation failed - aborting queue operation");
                        return false; // Don't proceed with corrupted queue
                    }
                    LogChannel(n"DEBUG", s"[QueueMod][Queue] EnqueueWithKey: NPC=\(GetLocalizedText(puppet.GetDisplayName())) key=\(key)");
                    let wasQueued: Bool = queue.PutActionInQueueWithKey(action, key);
                    
                    // ✅ ADD THIS: Force refresh UI after queuing
                    if wasQueued {
                        QuickhackQueueHelper.ForceQuickhackUIRefresh(gameInstance, targetID);
                        LogChannel(n"DEBUG", "[QueueMod] Action queued, UI force refreshed");
                    }
                    
                    return wasQueued;
                }
            }
            LogChannel(n"DEBUG", "[QueueMod] Puppet has no queue");
            return false;
        }

        // ScriptableDeviceAction with key support
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let queue: ref<QueueModActionQueue> = sa.GetQueueModActionQueue();
            if IsDefined(queue) {
                // FIX: Handle validation failure properly
                if !queue.ValidateQueueIntegrity() {
                    LogChannel(n"ERROR", "[QueueMod] Queue validation failed - aborting queue operation");
                    return false; // Don't proceed with corrupted queue
                }
                LogChannel(n"DEBUG", s"[QueueMod][Queue] EnqueueWithKey: Action queue key=\(key)");
                return queue.PutActionInQueueWithKey(action, key);
            }
        }

        LogChannel(n"DEBUG", "[QueueMod] Unknown action type - cannot queue");
        return false;
    }

    public func QueueActionOnPuppet(puppetAction: ref<PuppetAction>) -> Bool {
        if !IsDefined(puppetAction) {
            return false;
        }

        let targetID: EntityID = puppetAction.GetRequesterID();
        let gameInstance: GameInstance = puppetAction.GetExecutor().GetGame();
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;

        if !IsDefined(targetObject) {
            LogChannel(n"DEBUG", s"[QueueMod][Queue] Abort: requester not found, requesterID=\(ToString(targetID))");
            return false;
        }

        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if !IsDefined(puppet) {
            LogChannel(n"DEBUG", s"[QueueMod][Queue] Abort: requester not a ScriptedPuppet, requesterID=\(ToString(targetID))");
            return false;
        }

        let queue: ref<QueueModActionQueue> = puppet.GetQueueModActionQueue();
        if IsDefined(queue) {
            LogChannel(n"DEBUG", s"[QueueMod][Queue] Enqueue: NPC=\(GetLocalizedText(puppet.GetDisplayName())) id=\(ToString(puppet.GetEntityID())) action=PuppetAction");
            // Generate a unique key for the action
            let uniqueKey: String = this.GenerateQueueKey(puppetAction);
            return queue.PutActionInQueueWithKey(puppetAction, uniqueKey);
        }

        LogChannel(n"DEBUG", "[QueueMod] Puppet has no queue");
        return false;
    }

    public func GetQueueSize(action: ref<DeviceAction>) -> Int32 {
        if !IsDefined(action) {
            return 0;
        }

        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let q = sa.GetQueueModActionQueue();
            return IsDefined(q) ? q.GetQueueSize() : 0;
        }

        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            return this.GetPuppetQueueSize(pa);
        }

        return 0;
    }

    public func GetPuppetQueueSize(puppetAction: ref<PuppetAction>) -> Int32 {
        if !IsDefined(puppetAction) {
            return 0;
        }

        let targetID: EntityID = puppetAction.GetRequesterID();
        let gameInstance: GameInstance = puppetAction.GetExecutor().GetGame();
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;

        if !IsDefined(targetObject) {
            return 0;
        }

        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if !IsDefined(puppet) {
            return 0;
        }

        let queue: ref<QueueModActionQueue> = puppet.GetQueueModActionQueue();
        return IsDefined(queue) ? queue.GetQueueSize() : 0;
    }

    // Phase 2: Enhanced target resolution and debugging
    public func ResolveTargetFromAction(action: ref<DeviceAction>) -> ref<GameObject> {
        if !IsDefined(action) {
            return null;
        }

        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            let targetID: EntityID = pa.GetRequesterID();
            let gameInstance: GameInstance = pa.GetExecutor().GetGame();
            let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;
            LogChannel(n"DEBUG", s"[QueueMod][TargetResolution] PuppetAction target: \(ToString(targetID)) -> \(IsDefined(targetObject) ? ToString(targetObject.GetClassName()) : "null")");
            return targetObject;
        }

        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            LogChannel(n"DEBUG", s"[QueueMod][TargetResolution] ScriptableDeviceAction - no direct target resolution needed");
            return null;
        }

        LogChannel(n"DEBUG", s"[QueueMod][TargetResolution] Unknown action type: \(action.GetClassName())");
        return null;
    }

    public func ValidateQueueIntegrity(queue: ref<QueueModActionQueue>) -> Bool {
        if !IsDefined(queue) {
        return false;
    }

        let actionSize: Int32 = queue.GetQueueSize();
        LogChannel(n"DEBUG", s"[QueueMod][Validation] Queue integrity check - Action count: \(actionSize)");
        
        // Additional validation can be added here
        return true;
    }

    // Standardized key generation to prevent duplicates
    private func GenerateQueueKey(action: ref<DeviceAction>) -> String {
        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            let targetKey: String = ToString(pa.GetRequesterID());
            let actionIdStr: String = TDBID.ToStringDEBUG(pa.GetObjectActionID());
            return s"npc::\(targetKey)::\(actionIdStr)::\(GameInstance.GetTimeSystem(pa.GetExecutor().GetGame()).GetSimTime())";
        }
        
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            return s"device::\(TDBID.ToStringDEBUG(sa.GetObjectActionID()))::\(GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp())";
        }
        
        return s"unknown::\(GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp())";
    }
}

// =============================================================================
// Phase 1.2: Entity Field Extensions (v1.63 pattern)
// =============================================================================

// Device extensions with unique method names to avoid conflicts
@addField(Device)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(Device)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
    }
    return this.m_queueModActionQueue;
}

@addMethod(Device)
public func IsQueueModEnabled() -> Bool {
    return true;
}

@addMethod(Device)
public func IsQueueModFull() -> Bool {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return false;
    }
    let queueSize: Int32 = queue.GetQueueSize();
    let isFull: Bool = queueSize >= 3;
    if queueSize > 0 {
        LogChannel(n"DEBUG", s"[QueueMod] Device queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

// =============================================================================
// Phase 3.1: Device Upload Bypass Wrapper for v1.63
// =============================================================================

@wrapMethod(Device)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
    let originalUploadState: Bool = this.m_isQhackUploadInProgerss;

    if originalUploadState {
        let queueEnabled: Bool = this.IsQueueModEnabled();
        let queueFull: Bool = this.IsQueueModFull();

        if queueEnabled && !queueFull {
            LogChannel(n"DEBUG", s"[QueueMod] Device bypassing upload block for queue (device: \(this.GetDisplayName()))");
            this.m_isQhackUploadInProgerss = false;
        }
    }

    wrappedMethod(shouldOpen);
    this.m_isQhackUploadInProgerss = originalUploadState;
}

// ScriptedPuppet extensions
@addField(ScriptedPuppet)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(ScriptedPuppet)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
        this.m_queueModActionQueue.Initialize();
    }
    return this.m_queueModActionQueue;
}

@addMethod(ScriptedPuppet)
public func IsQueueModEnabled() -> Bool {
    return true;
}

@addMethod(ScriptedPuppet)
public func IsQueueModFull() -> Bool {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return false;
    }
    let queueSize: Int32 = queue.GetQueueSize();
    let isFull: Bool = queueSize >= 3;
    if queueSize > 0 {
        LogChannel(n"DEBUG", s"[QueueMod] NPC queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

// =============================================================================
// Phase 3.2: NPC Upload Detection & Queue Processing - v1.63 Compatible Syntax
// =============================================================================

@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(puppetActions: array<ref<PuppetAction>>, out commands: array<ref<QuickhackData>>) -> Void {
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame()).IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    let hasQueued: Bool = IsDefined(this.GetQueueModActionQueue()) && this.GetQueueModActionQueue().GetQueueSize() > 0;

    // Call vanilla first for normal v1.63 behavior
    wrappedMethod(puppetActions, commands);

    // Only intervene when there's an active upload
    LogChannel(n"DEBUG", s"[QueueMod][Debug] Upload check: isOngoingUpload=\(isOngoingUpload)");
    if isOngoingUpload || hasQueued {
        let queueEnabled: Bool = this.IsQueueModEnabled();
        let queueFull: Bool = this.IsQueueModFull();

        LogChannel(n"DEBUG", s"[QueueMod] NPC upload detected - queue enabled: \(queueEnabled), queue full: \(queueFull)");

        if queueEnabled && !queueFull {
            LogChannel(n"DEBUG", s"[QueueMod][Unblock] NPC=\(GetLocalizedText(this.GetDisplayName())) reason=upload-in-progress queueEnabled=\(queueEnabled) queueFull=\(queueFull)");

            let i: Int32 = 0;
            let commandsSize: Int32 = ArraySize(commands);
            LogChannel(n"DEBUG", s"[QueueMod][Debug] Processing \(commandsSize) commands for unblocking");
            while i < commandsSize {
                if IsDefined(commands[i]) {
                    LogChannel(n"DEBUG", s"[QueueMod][Debug] Command \(i): locked=\(commands[i].m_isLocked) reason='\(GetLocalizedText(commands[i].m_inactiveReason))' type=\(ToString(commands[i].m_type))");
                    
                    // Check for any locked command first
                    if commands[i].m_isLocked {
                        LogChannel(n"DEBUG", s"[QueueMod][Debug] Found locked command - checking reason");
                        
                        let reasonStr: String = ToString(commands[i].m_inactiveReason);
                        
                        // PHASE 2: Only unblock upload/cooldown, skip RAM
                        let isUploadOrCooldown: Bool = StrContains(reasonStr, "upload") ||  // Upload in progress
                                                       StrContains(reasonStr, "reloading") ||  // Cooldown/recompiling
                                                       StrContains(reasonStr, "cooldown") ||
                                                       Equals(reasonStr, "LocKey#40765") ||  // Reloading
                                                       Equals(reasonStr, "LocKey#27398") ||  // Upload
                                                       Equals(reasonStr, "LocKey#7020") ||
                                                       Equals(reasonStr, "LocKey#7019");
                        let isRamLock: Bool = StrContains(reasonStr, "ram") || Equals(reasonStr, "LocKey#27400");  // RAM insufficient
                        
                        if isUploadOrCooldown && !isRamLock {
                            LogChannel(n"DEBUG", s"[QueueMod][Unblock] Unlocking non-RAM lock: \(reasonStr)");
                            
                            if Equals(commands[i].m_type, gamedataObjectActionType.PuppetQuickHack) || Equals(commands[i].m_type, gamedataObjectActionType.MinigameUpload) {
                                LogChannel(n"DEBUG", s"[QueueMod][Debug] Command type matches - unblocking");
                                commands[i].m_isLocked = false;
                                commands[i].m_inactiveReason = "";
                                commands[i].m_actionState = EActionInactivityReson.Ready;

                                if Equals(commands[i].m_type, gamedataObjectActionType.PuppetQuickHack) {
                                    LogChannel(n"DEBUG", s"[QueueMod] Unblocked quickhack for queue: \(ToString(commands[i].m_type))");
                                } else {
                                    LogChannel(n"DEBUG", s"[QueueMod] Preserved breach protocol access: \(ToString(commands[i].m_type))");
                                }
                            } else {
                                LogChannel(n"DEBUG", s"[QueueMod][Debug] Command type does not match - skipping");
                            }
                        } else if isRamLock {
                            LogChannel(n"DEBUG", s"[QueueMod][Unblock] Skipping RAM lock: \(reasonStr)");
                        } else {
                            LogChannel(n"DEBUG", s"[QueueMod][Debug] Locked command but not upload-related - skipping");
                        }
                    }
                }
                i += 1;
            }
        } else {
            // Preserve breach protocol even if queue disabled/full
            LogChannel(n"DEBUG", "[QueueMod] Queue full/disabled - preserving breach protocol only");

            let i2: Int32 = 0;
            let commandsSize2: Int32 = ArraySize(commands);
            while i2 < commandsSize2 {
                if IsDefined(commands[i2]) && commands[i2].m_isLocked && 
                   (Equals(ToString(commands[i2].m_inactiveReason), "LocKey#27398") || 
                    Equals(ToString(commands[i2].m_inactiveReason), "LocKey#40765") ||
                    Equals(ToString(commands[i2].m_inactiveReason), "LocKey#7020") ||
                    Equals(ToString(commands[i2].m_inactiveReason), "LocKey#7019")) && 
                   !StrContains(ToString(commands[i2].m_inactiveReason), "ram") &&  // PHASE 2: Skip RAM locks
                   Equals(commands[i2].m_type, gamedataObjectActionType.MinigameUpload) {
                    commands[i2].m_isLocked = false;
                    commands[i2].m_inactiveReason = "";
                    commands[i2].m_actionState = EActionInactivityReson.Ready;
                    LogChannel(n"DEBUG", "[QueueMod] Preserved breach protocol (queue full)");
                }
                i2 += 1;
            }
        }
    }
}

// =============================================================================
// Phase 3.3: Queue Execution on Upload Completion - v1.63 Syntax
// =============================================================================

@wrapMethod(ScriptedPuppet)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    // Let vanilla process first (can't prevent it)
    let result: Bool = wrappedMethod(evt);

    // Only check our queue processing
    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) && 
       Equals(evt.progressBarType, EProgressBarType.UPLOAD) && 
       Equals(evt.state, EUploadProgramState.COMPLETED) {
        
        // Check death NOW before processing OUR queue
        if this.IsDead() || 
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") ||
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
            
            // Clear our queue
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                queue.ClearQueue(this.GetGame(), this.GetEntityID());
                LogChannel(n"DEBUG", "[QueueMod] Target dead - queue cleared, vanilla hack may still apply");
            }
            return result;
        }
        
        // Process queue only if alive
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) && queue.GetQueueSize() > 0 {
            // FIX 4: Validate before processing - halt execution if validation fails
            if !queue.ValidateQueueIntegrity() {
                LogChannel(n"ERROR", "[QueueMod] Queue integrity failed - halting execution and clearing queue");
                queue.ClearQueue(this.GetGame(), this.GetEntityID()); // Clear corrupted queue
                return result;
            }
            
            let entry: ref<QueueModEntry> = queue.PopNextEntry();
            if IsDefined(entry) {
                LogChannel(n"DEBUG", s"[QueueMod][Exec] Upload complete for NPC=\(GetLocalizedText(this.GetDisplayName())) processing queue");
                this.ExecuteQueuedEntry(entry);
            }
        } else {
            LogChannel(n"DEBUG", "[QueueMod] No queued entries to execute");
        }
    }

    return result;
}

// =============================================================================
// CRITICAL FIX: Correct Quickhack Execution Context
// Replace the ExecuteQueuedEntry method in ScriptedPuppet
// =============================================================================

@addMethod(ScriptedPuppet)
private func ExecuteQueuedEntry(entry: ref<QueueModEntry>) -> Void {
    if !IsDefined(entry) {
        LogChannel(n"ERROR", "[QueueMod] ExecuteQueuedEntry called with null entry");
        return;
    }
    
    // FIX 4: Validate queue integrity before execution
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if IsDefined(queue) && !queue.ValidateQueueIntegrity() {
        LogChannel(n"ERROR", "[QueueMod] Queue integrity failed during execution - halting");
        queue.ClearQueue(this.GetGame(), this.GetEntityID());
        return;
    }

    // PHASE 1: Validate target is still alive and valid (enhanced death check)
    if !IsDefined(this) || this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
        LogChannel(n"DEBUG", "[QueueMod] Target invalid/dead/unconscious - clearing queue");
        this.NotifyPlayerQueueCanceled("Target eliminated, queued quickhacks canceled.");
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.ClearQueue(this.GetGame(), this.GetEntityID());
        }
        return;
    }

    // CRITICAL FIX: Get player context for execution
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        LogChannel(n"ERROR", "[QueueMod] Cannot find player for quickhack execution");
        return;
    }

    if Equals(entry.entryType, 0) && IsDefined(entry.action) {
        LogChannel(n"DEBUG", s"[QueueMod][Exec] Executing queued action: class=\(entry.action.GetClassName()) on NPC=\(GetLocalizedText(this.GetDisplayName()))");
        
        // Validate action identity before execution
        let actionID: TweakDBID = TDBID.None();
        let saExec: ref<ScriptableDeviceAction> = entry.action as ScriptableDeviceAction;
        let paExec: ref<PuppetAction> = entry.action as PuppetAction;
        
        if IsDefined(saExec) {
            actionID = saExec.GetObjectActionID();
            LogChannel(n"DEBUG", s"[QueueMod][Exec] Executing ScriptableDeviceAction: \(TDBID.ToStringDEBUG(actionID))");
        } else if IsDefined(paExec) {
            actionID = paExec.GetObjectActionID();
            LogChannel(n"DEBUG", s"[QueueMod][Exec] Executing PuppetAction: \(TDBID.ToStringDEBUG(actionID))");
        }
        
        if !TDBID.IsValid(actionID) {
            LogChannel(n"ERROR", s"[QueueMod][Exec] Action has invalid TweakDBID - skipping execution");
            return;
        }
        
        // PHASE 3: Note: SetCost not available in v1.63, RAM already deducted on selection
        // No need to modify cost since RAM was deducted immediately on queue selection
        
        // Note: ExecuteQueuedEntryViaUI removed - would cause infinite recursion
        
        // FALLBACK: Direct execution with UI feedback
        // CRITICAL FIX: Use ProcessRPGAction instead of OnQuickSlotCommandUsed for reliable execution
        if IsDefined(saExec) {
            // Ensure action targets this NPC
            saExec.RegisterAsRequester(this.GetEntityID());
            saExec.SetExecutor(player); // CRITICAL: Player executes, NPC receives
            
            // BUG 1 FIX: Lock the queue during execution to prevent race conditions
            this.GetQueueModActionQueue().LockQueue();
            
            // MISSING UI EFFECT: Add UI feedback BEFORE execution
            this.TriggerQuickhackUIFeedback(saExec);
            
            // CRITICAL FIX: Use ProcessRPGAction for reliable post-upload execution
            LogChannel(n"DEBUG", s"[QueueMod][Exec] Processing RPG action for target: \(GetLocalizedText(this.GetDisplayName()))");
            saExec.ProcessRPGAction(this.GetGame());
            
            // Check immediately after execution
            if this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || 
               StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
                LogChannel(n"DEBUG", "[QueueMod] Target died during execution - clearing queue");
                this.GetQueueModActionQueue().ClearQueue(this.GetGame(), this.GetEntityID());
                // Don't try to reverse - just prevent next execution
                return;
            }
            this.GetQueueModActionQueue().UnlockQueue();
            
        } else if IsDefined(paExec) {
            // Ensure action targets this NPC
            paExec.RegisterAsRequester(this.GetEntityID());
            paExec.SetExecutor(player); // CRITICAL: Player executes, NPC receives
            
            // BUG 1 FIX: Lock the queue during execution to prevent race conditions
            this.GetQueueModActionQueue().LockQueue();
            
            // MISSING UI EFFECT: Add UI feedback BEFORE execution
            this.TriggerQuickhackUIFeedback(paExec);
            
            // CRITICAL FIX: Use ProcessRPGAction for reliable post-upload execution
            LogChannel(n"DEBUG", s"[QueueMod][Exec] Processing PuppetAction RPG for target: \(GetLocalizedText(this.GetDisplayName()))");
            paExec.ProcessRPGAction(this.GetGame());
            
            // Check immediately after execution
            if this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || 
               StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
                LogChannel(n"DEBUG", "[QueueMod] Target died during execution - clearing queue");
                this.GetQueueModActionQueue().ClearQueue(this.GetGame(), this.GetEntityID());
                // Don't try to reverse - just prevent next execution
                return;
            }
            this.GetQueueModActionQueue().UnlockQueue();
            
        } else {
            LogChannel(n"DEBUG", s"[QueueMod][Exec] Unknown action type: \(entry.action.GetClassName())");
        }
        
        // PHASE 3: Note: Cost restoration not needed since SetCost not available in v1.63
        
    } else {
        LogChannel(n"ERROR", s"[QueueMod] Invalid entry type: \(entry.entryType)");
    }

    // ✅ ADD THIS: Force refresh after execution
    QuickhackQueueHelper.ForceQuickhackUIRefresh(this.GetGame(), this.GetEntityID());
}


@addMethod(ScriptedPuppet)
private func UpdateQueueHUDOverlay() -> Void {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return;
    }
    
    let queueSize: Int32 = queue.GetQueueSize();
    if queueSize > 0 {
        // Show queue indicator on target
        LogChannel(n"DEBUG", s"[QueueMod][HUD] Target \(GetLocalizedText(this.GetDisplayName())) has \(queueSize) queued hacks");
        
        // TODO: Add visual HUD overlay here
        // This would integrate with the game's HUD system to show:
        // - Small stack icons near enemy health bar
        // - Progress bar showing upload progress
        // - Queue count indicator
    }
}

// Note: Persistence system removed - queues shouldn't persist across scanner toggles

// Player-Friendly Error Handling
@addMethod(ScriptedPuppet)
private func NotifyPlayerQueueCanceled(message: String) -> Void {
    // Show notification to player
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    if IsDefined(playerSystem) {
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            // TODO: Implement proper notification system
            // This would show a UI notification to the player
            LogChannel(n"DEBUG", s"[QueueMod][Notification] \(message)");
        }
    }
}

@addMethod(ScriptedPuppet)
private func NotifyPlayerRAMRefunded(amount: Int32) -> Void {
    let message: String = s"RAM refunded: \(amount) units";
    this.NotifyPlayerQueueCanceled(message);
}

// Note: Speed modifier and GC registration methods removed - were broken/placeholder code

@addMethod(ScriptedPuppet)
private func QM_RefundRam(amount: Int32) -> Void {
    let ps: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    let player: ref<PlayerPuppet> = IsDefined(ps) ? ps.GetLocalPlayerMainGameObject() as PlayerPuppet : null;
    if !IsDefined(player) || amount <= 0 { return; }
    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.GetGame());
    let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, Cast<Float>(amount), player, false);
    LogChannel(n"DEBUG", s"[QueueMod] Refunded RAM (intent): \(amount)");
}

// Note: ReverseQuickhackEffects removed - using queue locking instead of rollback

@addMethod(ScriptedPuppet)
private func QM_MapQuickhackToSE(tweak: TweakDBID) -> TweakDBID {
    // Map known quickhacks -> their status effects (v1.63 names)
    // Fallback: return TDBID.None() if unknown (so we can bail safely)
    let s: String = TDBID.ToStringDEBUG(tweak);
    // Common ones used in your logs/tests:
    if StrContains(s, "QuickHack.OverheatHack") { return t"StatusEffect.Overheat"; }
    if StrContains(s, "QuickHack.BlindHack")    { return t"StatusEffect.Blind"; }
    if StrContains(s, "QuickHack.ShortCircuitHack") { return t"StatusEffect.ShortCircuit"; }
    if StrContains(s, "QuickHack.SynapseBurnoutHack") { return t"StatusEffect.SynapseBurnout"; }
    if StrContains(s, "QuickHack.CommsNoiseHack") { return t"StatusEffect.Contagion"; }
    if StrContains(s, "QuickHack.MalfunctionHack") { return t"StatusEffect.CyberwareMalfunction"; }
    if StrContains(s, "QuickHack.SystemCollapseHack") { return t"StatusEffect.SystemReset"; }
    if StrContains(s, "QuickHack.MemoryWipeHack") { return t"StatusEffect.MemoryWipe"; }
    if StrContains(s, "QuickHack.WeaponGlitchHack") { return t"StatusEffect.WeaponMalfunction"; }
    if StrContains(s, "QuickHack.DisableCyberwareHack") { return t"StatusEffect.DisableCyberware"; }
    // Add more as needed
    return TDBID.None();
}

@addMethod(ScriptedPuppet)
private func QM_ApplyQuickhackIntent(tweak: TweakDBID) -> Bool {
    // Try SE-based application first (works for Overheat/Reboot Optics/etc.)
    let seID: TweakDBID = this.QM_MapQuickhackToSE(tweak);
    if TDBID.IsValid(seID) {
        StatusEffectHelper.ApplyStatusEffect(this, seID);
        LogChannel(n"DEBUG", s"[QueueMod][Exec] Applied SE for quickhack: \(TDBID.ToStringDEBUG(seID))");
        return true;
    }
    LogChannel(n"DEBUG", "[QueueMod][Exec] No SE mapping for quickhack; skipping");
    return false;
}

// PHASE 1: Death event listener for queue cancellation (v1.63 compatible)
@addMethod(ScriptedPuppet)
protected cb func OnQueueDeathEvent(evt: ref<Event>) -> Bool {
    // Check if this is actually a death-related event
    let eventType: CName = evt.GetClassName();
    LogChannel(n"DEBUG", s"[QueueMod] Event received: \(ToString(eventType)) on \(GetLocalizedText(this.GetDisplayName()))");
    
    // Check for death via status effect or IsDead()
    let isDead: Bool = this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead");
    if isDead {
        LogChannel(n"DEBUG", s"[QueueMod] Death confirmed - clearing queue");
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.ClearQueue(this.GetGame(), this.GetEntityID());  // Refunds all queued RAM
            this.NotifyPlayerQueueCanceled("Target died - queued quickhacks canceled and RAM refunded.");
        }
    }
    return true;
}

// FIX 1: Death Registration - Register death handler in lifecycle
@addMethod(ScriptedPuppet)
protected func OnGameAttached() -> Void {
    // Note: RegisterListener API limited in v1.63, using manual event checking instead
    // Death events will be checked in existing methods (OnUploadProgressStateChanged, ExecuteQueuedEntry)
    LogChannel(n"DEBUG", s"[QueueMod] Death event checking enabled for \(GetLocalizedText(this.GetDisplayName()))");
}

// MEMORY LEAK FIX: Clean up queue on death
// Note: OnDeath method not available in v1.63, using OnStatusEffectApplied instead

// EVENT-DRIVEN CLEANUP: Proper status effect listener for death/unconscious
@wrapMethod(ScriptedPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    
    // Check if death/unconscious effect
    if IsDefined(evt.staticData) {
        let effectID: TweakDBID = evt.staticData.GetID();
        let effectIDStr: String = TDBID.ToStringDEBUG(effectID);
        
        if StrContains(effectIDStr, "Dead") || StrContains(effectIDStr, "Unconscious") ||
           StrContains(effectIDStr, "BaseStatusEffect.Dead") || StrContains(effectIDStr, "BaseStatusEffect.Unconscious") {
            
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                queue.ClearQueue(this.GetGame(), this.GetEntityID());
                LogChannel(n"DEBUG", s"[QueueMod] Queue cleared on death/unconscious status: \(effectIDStr)");
            }
        }
    }
    return result;
}

// ✅ CRITICAL FIX: Event Handlers for Sequenced Refresh System
@addMethod(ScriptedPuppet)
protected cb func OnQueueModCommandGenEvent(evt: ref<QueueModCommandGenEvent>) -> Bool {
    LogChannel(n"DEBUG", s"[QueueMod] Command generation event received for: \(EntityID.ToDebugString(evt.targetID))");
    
    // Check if this event is for us
    if EntityID.IsDefined(evt.targetID) && Equals(evt.targetID, this.GetEntityID()) {
        LogChannel(n"DEBUG", "[QueueMod] Processing command generation for this target");
        
        // Force fresh command generation with injection
        QuickhackQueueHelper.ForceFreshCommandGeneration(this.GetGame(), this.GetEntityID());
        
        LogChannel(n"DEBUG", "[QueueMod] Command generation event processing complete");
    }
    
    return true;
}

@addMethod(ScriptedPuppet)
protected cb func OnQueueModCacheEvent(evt: ref<QueueModCacheEvent>) -> Bool {
    LogChannel(n"DEBUG", s"[QueueMod] Cache event received for: \(EntityID.ToDebugString(evt.targetID))");
    
    // Check if this event is for us
    if EntityID.IsDefined(evt.targetID) && Equals(evt.targetID, this.GetEntityID()) {
        LogChannel(n"DEBUG", "[QueueMod] Processing cache clearing for this target");
        
        // Clear controller cache with repopulation
        QuickhackQueueHelper.ClearControllerCache(this.GetGame(), this.GetEntityID());
        
        LogChannel(n"DEBUG", "[QueueMod] Cache event processing complete");
    }
    
    return true;
}

@addMethod(ScriptedPuppet)
protected cb func OnQueueModValidationEvent(evt: ref<QueueModValidationEvent>) -> Bool {
    LogChannel(n"DEBUG", s"[QueueMod] Validation event received for: \(EntityID.ToDebugString(evt.targetID))");
    
    // Check if this event is for us
    if EntityID.IsDefined(evt.targetID) && Equals(evt.targetID, this.GetEntityID()) {
        LogChannel(n"DEBUG", "[QueueMod] Processing validation for this target");
        
        // ✅ CRITICAL FIX: Fallback validation to retry if refresh failed
        // Note: Call the validation method directly since it's static
        let gameInstance: GameInstance = this.GetGame();
        let targetID: EntityID = this.GetEntityID();
        
        // Get the player and controller for validation
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            let controller: ref<QuickhacksListGameController> = player.GetQuickhacksListGameController();
            if IsDefined(controller) {
                // Check if the controller has fresh data for this target
                let hasData: Bool = ArraySize(controller.m_data) > 0;
                let correctTarget: Bool = EntityID.IsDefined(controller.m_lastCompiledTarget) && Equals(controller.m_lastCompiledTarget, targetID);
                
                LogChannel(n"DEBUG", s"[QueueMod] Validation results - Has data: \(hasData), Correct target: \(correctTarget)");
                
                // If validation failed, retry the refresh sequence
                if !hasData || !correctTarget {
                    LogChannel(n"DEBUG", "[QueueMod] Validation failed - retrying refresh sequence");
                    
                    // Retry with longer delays for v1.63 compatibility
                    let retryGenEvent: ref<QueueModCommandGenEvent> = new QueueModCommandGenEvent();
                    retryGenEvent.targetID = targetID;
                    retryGenEvent.timestamp = GameInstance.GetTimeSystem(gameInstance).GetGameTimeStamp();
                    GameInstance.GetDelaySystem(gameInstance).DelayEvent(null, retryGenEvent, 0.15);
                    
                    let retryCacheEvent: ref<QueueModCacheEvent> = new QueueModCacheEvent();
                    retryCacheEvent.targetID = targetID;
                    retryCacheEvent.timestamp = GameInstance.GetTimeSystem(gameInstance).GetGameTimeStamp();
                    GameInstance.GetDelaySystem(gameInstance).DelayEvent(null, retryCacheEvent, 0.25);
                    
                    LogChannel(n"DEBUG", "[QueueMod] Retry sequence scheduled with extended delays");
                } else {
                    LogChannel(n"DEBUG", "[QueueMod] Validation passed - refresh successful");
                }
            }
        }
        
        LogChannel(n"DEBUG", "[QueueMod] Validation event processing complete");
    }
    
    return true;
}

// MISSING UI EFFECT: Trigger vanilla UI feedback for queued quickhacks (v1.63 compatible)
@addMethod(ScriptedPuppet)
private func TriggerQuickhackUIFeedback(action: ref<DeviceAction>) -> Void {
    let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.GetGame()).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { 
        LogChannel(n"DEBUG", "[QueueMod] No player found for UI feedback");
        return; 
    }
    
    // Use actual quickhack visual effects (v1.63 compatible)
    GameObject.PlaySoundEvent(this, n"ui_quickhack_upload_complete");
    // Note: StartEffectEvent not available on ScriptedPuppet in v1.63
    
    // Audio cue (v1.63 compatible)
    let audioSystem: ref<AudioSystem> = GameInstance.GetAudioSystem(this.GetGame());
    if IsDefined(audioSystem) {
        audioSystem.Play(n"ui_quickhack_execute");
        LogChannel(n"DEBUG", "[QueueMod] Played quickhack activation sound");
    }
    
    LogChannel(n"DEBUG", "[QueueMod] UI feedback triggered for queued quickhack (v1.63 compatible)");
}

// Note: ExecuteQueuedEntryViaUI removed - would cause infinite recursion with ApplyQuickHack wrapper

// Player-level upload completion hook (Phase 3)
// TODO: Implement PlayerPuppet wrapper when available in v1.63
// For now, rely on ScriptedPuppet wrapper for queue execution

// ScriptableDeviceAction extensions
@addField(ScriptableDeviceAction)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(ScriptableDeviceAction)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
    }
    return this.m_queueModActionQueue;
}

@addMethod(ScriptableDeviceAction)
public func IsQueueModEnabled() -> Bool {
    return true;
}

@addMethod(ScriptableDeviceAction)
public func IsQueueModFull() -> Bool {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return false;
    }
    let queueSize: Int32 = queue.GetQueueSize();
    let isFull: Bool = queueSize >= 3;
    if queueSize > 0 {
        LogChannel(n"DEBUG", s"[QueueMod] Action queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

@addMethod(ScriptableDeviceAction)
public func QueueModQuickHack(action: ref<DeviceAction>) -> Bool {
    if !IsDefined(action) {
        return false;
    }
    LogChannel(n"DEBUG", "[QueueMod] ScriptableDeviceAction.QueueModQuickHack called");
    // Generate a unique key for the action
    let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
    if IsDefined(sa) {
        let uniqueKey: String = s"device::\(TDBID.ToStringDEBUG(sa.GetObjectActionID()))::\(GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp())";
        return this.GetQueueModActionQueue().PutActionInQueueWithKey(action, uniqueKey);
    }
    return false;
}

@addMethod(ScriptableDeviceAction)
public func GetQueueModSize() -> Int32 {
    let q: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    return IsDefined(q) ? q.GetQueueSize() : 0;
}

// Note: OnUploadCompleted wrapper removed - not available in v1.63 API
// UI refresh is handled by the ScriptedPuppet upload completion handler instead

// =============================================================================
// Debug Logging for UI Refresh
// =============================================================================

@wrapMethod(QuickhackModule)
public static func RequestRefreshQuickhackMenu(context: GameInstance, requester: EntityID) -> Void {
    LogChannel(n"DEBUG", s"[QueueMod] Vanilla UI Refresh requested for: \(EntityID.ToDebugString(requester))");
    
    wrappedMethod(context, requester);
    
    // Schedule force refresh as backup (v1.63 has aggressive caching)
    LogChannel(n"DEBUG", "[QueueMod] Scheduling force refresh backup for v1.63 compatibility");
    // Use proper sequenced refresh instead of direct calls
    QuickhackQueueHelper.ScheduleSequencedRefresh(context, requester);
}

// =============================================================================
// Phase 2.6: PlayerPuppet Integration for Queue Helper Access
// =============================================================================

// PlayerPuppet integration for queue helper access
@addField(PlayerPuppet)
private let m_queueModHelper: ref<QueueModHelper>;

@addField(PlayerPuppet)
private let m_qmQuickhackController: wref<QuickhacksListGameController>;

@addMethod(PlayerPuppet)
public func SetQuickhacksListGameController(controller: wref<QuickhacksListGameController>) -> Void {
    this.m_qmQuickhackController = controller;
}

@addField(QuickhacksListGameController)
private let m_qmPoolsRegistered: Bool;

@addField(QuickhacksListGameController)
private let m_qmRefreshScheduled: Bool;

// Note: m_qmUseVanillaUI removed - no longer needed without ExecuteQueuedEntryViaUI

@addMethod(PlayerPuppet)
public func GetQueueModHelper() -> ref<QueueModHelper> {
    if !IsDefined(this.m_queueModHelper) {
        this.m_queueModHelper = new QueueModHelper();
        LogChannel(n"DEBUG", "[QueueMod] Player loaded - queue system ready");
    }
    return this.m_queueModHelper;
}

@addMethod(PlayerPuppet)
public func GetQuickhacksListGameController() -> ref<QuickhacksListGameController> {
    return this.m_qmQuickhackController;
}

// =============================================================================
// Phase 4: UI Integration & Queue Management
// =============================================================================

// =============================================================================
// Phase 4.1: UI Upload Detection Methods - v1.63 Compatible
// =============================================================================

@addMethod(QuickhacksListGameController)
private func IsQuickHackCurrentlyUploading() -> Bool {
    // Rule 1: Selected row UI lock (fastest path)
    if this.QueueModSelectedIsUILocked() {
        LogChannel(n"DEBUG", "[QueueMod][Detect] Selected row UI lock indicates upload in progress");
        return true;
    }

    // Rule 1b: Generic lock check for unknown reasons
    if IsDefined(this.m_selectedData) && this.m_selectedData.m_isLocked && 
       NotEquals(this.m_selectedData.m_actionState, EActionInactivityReson.Ready) {
        LogChannel(n"DEBUG", "[QueueMod][Detect] Selected item locked with unknown reason → treating as upload");
        return true;
    }

    // Rule 1c: Full UI lock scan (fallback for timing races)
    if this.QueueModDetectUILock() {
        LogChannel(n"DEBUG", "[QueueMod][Detect] Full UI lock scan indicates upload in progress");
        return true;
    }

    // Rule 2: Target check (only if NPC - devices skip pool)
    if IsDefined(this.m_selectedData) {
        let targetID: EntityID = this.m_selectedData.m_actionOwner;
        if EntityID.IsDefined(targetID) {
            let target: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as GameObject;
            if IsDefined(target) {
                // Log target type for debugging
                LogChannel(n"DEBUG", s"[QueueMod][Detect] Target class: \(ToString(target.GetClassName()))");
                
                let puppet: ref<ScriptedPuppet> = target as ScriptedPuppet;
                if IsDefined(puppet) {
                    // Only check StatPool for NPCs (ScriptedPuppets)
                    let uploading: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance)
                        .IsStatPoolAdded(Cast<StatsObjectID>(puppet.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
                    LogChannel(n"DEBUG", s"[QueueMod][Detect] NPC upload pool: \(uploading)");
                    return uploading;
                } else {
                    // Device detected - rely only on UI lock (already checked above)
                    LogChannel(n"DEBUG", "[QueueMod][Detect] Device target - UI lock only");
                    return false;
                }
            }
        }
    }

    // Rule 4: Fallback to player pool (rare cases)
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if IsDefined(player) {
        let hasUploadPool: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance)
            .IsStatPoolAdded(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
        LogChannel(n"DEBUG", s"[QueueMod][Detect] Player upload pool (fallback): \(hasUploadPool)");
        return hasUploadPool;
    }

    return false;
}

@addMethod(QuickhacksListGameController)
private func QM_RegisterPoolListeners() -> Void {
    if this.m_qmPoolsRegistered {
        return;
    }
    // TODO: Implement StatPool listeners when available in v1.63
    // For now, just mark as registered to avoid repeated calls
    this.m_qmPoolsRegistered = true;
    LogChannel(n"DEBUG", "[QueueMod] StatPool listeners registered (placeholder)");
}

// TODO: Implement StatPool listener when StatPoolValueChangedEvent is available in v1.63
// @addMethod(QuickhacksListGameController)
// protected cb func OnQMStatPoolChanged(evt: ref<StatPoolValueChangedEvent>) -> Bool {
//     // Simple bounce to a refresh
//     this.RefreshQueueModUI();
//     return true;
// }

@addMethod(QuickhacksListGameController)
private func QueueModSelectedIsUILocked() -> Bool {
    if !IsDefined(this.m_selectedData) {
        return false;
    }
    
    let d: ref<QuickhackData> = this.m_selectedData;
    if !d.m_isLocked {
        return false;
    }
    
    let r: String = ToString(d.m_inactiveReason);
    return Equals(r, "LocKey#27398") || Equals(r, "LocKey#40765") || Equals(r, "LocKey#7020") || Equals(r, "LocKey#7019");
}

@addMethod(QuickhacksListGameController)
private func QueueModDetectUILock() -> Bool {
    let i: Int32 = 0;
    while i < ArraySize(this.m_data) {
        let entry: ref<QuickhackData> = this.m_data[i];
        if IsDefined(entry) && entry.m_isLocked && 
           (Equals(ToString(entry.m_inactiveReason), "LocKey#27398") || 
            Equals(ToString(entry.m_inactiveReason), "LocKey#40765") ||
            Equals(ToString(entry.m_inactiveReason), "LocKey#7020") ||
            Equals(ToString(entry.m_inactiveReason), "LocKey#7019")) {
            return true;
        }
        i += 1;
    }
    return false;
}

// =============================================================================
// Phase 4.2: Cooldown Detection and Management
// =============================================================================

@addMethod(QuickhacksListGameController)
private func QueueModIsOnCooldown(data: ref<QuickhackData>) -> Bool {
    if !IsDefined(data) || data.m_cooldown <= 0.0 || !TDBID.IsValid(data.m_cooldownTweak) {
        return false;
    }
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        return false;
    }
    return StatusEffectSystem.ObjectHasStatusEffect(player, data.m_cooldownTweak);
}

@addMethod(QuickhacksListGameController)
private func QueueModIsTargetUploading(data: ref<QuickhackData>) -> Bool {
    if !IsDefined(data) || !IsDefined(data.m_action) {
        return false;
    }
    let puppetAction: ref<PuppetAction> = data.m_action as PuppetAction;
    if IsDefined(puppetAction) {
        let targetID: EntityID = puppetAction.GetRequesterID();
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as GameObject;
        if IsDefined(targetObject) {
            let uploading: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance).IsStatPoolAdded(Cast<StatsObjectID>(targetObject.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
            return uploading;
        }
    }
    return false;
}

// =============================================================================
// Phase 4.3: Core ApplyQuickHack Integration - DIRECT ACCESS ONLY
// =============================================================================

// MAIN ApplyQuickHack wrapper - DIRECT ACCESS ONLY (no cache fallbacks)
@wrapMethod(QuickhacksListGameController)
private func ApplyQuickHack() -> Bool {
    LogChannel(n"DEBUG", "[QueueMod] *** ApplyQuickHack called ***");

    if !IsDefined(this.m_selectedData) {
        LogChannel(n"DEBUG", "[QueueMod] No selectedData - executing normally");
        return wrappedMethod();
    }

    let actionName: String = GetLocalizedText(this.m_selectedData.m_title);
    let targetID: EntityID = this.m_selectedData.m_actionOwner;
    
    LogChannel(n"DEBUG", s"[QueueMod] Processing: \(actionName) target: \(ToString(targetID))");

    // CRITICAL: Don't check m_action - it's null in 1.63
    // Instead, reconstruct from metadata
    if !EntityID.IsDefined(targetID) {
        LogChannel(n"DEBUG", "[QueueMod] Invalid target - executing normally");
        return wrappedMethod();
    }

    // Check cooldown using the selectedData directly
    if this.QueueModIsOnCooldown(this.m_selectedData) {
        LogChannel(n"DEBUG", s"[QueueMod] On cooldown: \(actionName)");
        return wrappedMethod();
    }

    // FIX 2: RAM Deduction - Move BEFORE path split to ensure ALL paths deduct RAM
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    
    if IsDefined(player) && this.m_selectedData.m_cost > 0 {
        let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);
        let freeRam: Float = sps.GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Memory, false);
        if Cast<Float>(this.m_selectedData.m_cost) > freeRam {
            LogChannel(n"ERROR", s"[QueueMod] Insufficient RAM for \(actionName): \(this.m_selectedData.m_cost) > \(freeRam)");
            return false;
        }
        sps.RequestChangingStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Memory, -Cast<Float>(this.m_selectedData.m_cost), player, false);
        LogChannel(n"DEBUG", s"[QueueMod] RAM deducted: \(this.m_selectedData.m_cost)");
    }

    // Check if we should queue
    let shouldQueue: Bool = this.IsQuickHackCurrentlyUploading();
    LogChannel(n"DEBUG", s"[QueueMod] Should queue: \(shouldQueue)");

    // Additional debug info for upload detection
    LogChannel(n"DEBUG", s"[QueueMod][Debug] Upload detection details - UI lock: \(this.QueueModDetectUILock())");
    
    // Show target info for debugging
    if IsDefined(this.m_selectedData) {
        let targetID: EntityID = this.m_selectedData.m_actionOwner;
        LogChannel(n"DEBUG", s"[QueueMod][Debug] Target ID: \(ToString(targetID))");
    }

    if shouldQueue {
        // CRITICAL FIX: Try to use the original action first, fallback to reconstruction
        let actionToQueue: ref<DeviceAction> = null;
        
        // Check if we have a valid action reference
        if IsDefined(this.m_selectedData.m_action) {
            actionToQueue = this.m_selectedData.m_action;
            LogChannel(n"DEBUG", s"[QueueMod] Using original action: \(actionToQueue.GetClassName())");
        } else {
            // Fallback to reconstruction only if no action reference
            actionToQueue = this.ReconstructActionFromData(this.m_selectedData);
            LogChannel(n"DEBUG", s"[QueueMod] Reconstructed action from metadata: \(GetLocalizedText(this.m_selectedData.m_title))");
        }
        
        if IsDefined(actionToQueue) {
            // Note: RAM already deducted before path split, no need to deduct again
            let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();
            if IsDefined(queueHelper) {
                let uniqueKey: String = s"\(ToString(targetID))::\(actionName)::\(GameInstance.GetTimeSystem(this.m_gameInstance).GetSimTime())";
                
                let wasQueued: Bool = queueHelper.PutInQuickHackQueueWithKey(actionToQueue, uniqueKey);
                if wasQueued {
                    LogChannel(n"DEBUG", s"[QueueMod] Queued action: \(actionName) class=\(actionToQueue.GetClassName())");
                    this.ApplyQueueModCooldownWithData(this.m_selectedData);
                    
                    // Fire QueueEvent for state synchronization
                    this.QM_FireQueueEvent(n"ItemAdded", this.m_selectedData);
                    
                    // ✅ ADD THIS: Force refresh UI to show new state
                    QuickhackQueueHelper.ForceQuickhackUIRefresh(this.m_gameInstance, targetID);
                    LogChannel(n"DEBUG", "[QueueMod] Action queued, UI force refreshed");
                    return true;
                }
            }
        }
    }

    // CRITICAL FIX: Don't store intents for non-queued hacks at all
    // This prevents intent pollution that causes double execution
    // Intents should only be stored when we actually want to queue something
    if !shouldQueue {
        // For non-queued hacks, just execute normally without storing any intent
        LogChannel(n"DEBUG", "[QueueMod] Executing non-queued hack normally (no intent storage)");
        return wrappedMethod();
    }
    
    // This should never be reached since shouldQueue=true returns early above
    LogChannel(n"ERROR", "[QueueMod] Unexpected code path - shouldQueue was false but we didn't execute");
    return wrappedMethod();
}

// =============================================================================
// Phase 2: Action Reconstruction Methods
// =============================================================================

@addMethod(QuickhacksListGameController)
private func ReconstructActionFromData(data: ref<QuickhackData>) -> ref<PuppetAction> {
    if !IsDefined(data) || !EntityID.IsDefined(data.m_actionOwner) {
        return null;
    }

    // Find the TweakDBID from the UI data
    let actionTweakID: TweakDBID = this.FindActionTweakID(data);
    if !TDBID.IsValid(actionTweakID) {
        LogChannel(n"DEBUG", s"[QueueMod] Cannot find TweakDBID for: \(GetLocalizedText(data.m_title))");
        return null;
    }

    // Create fresh PuppetAction
    let puppetAction: ref<PuppetAction> = new PuppetAction();
    puppetAction.SetObjectActionID(actionTweakID);
    
    // CRITICAL FIX: Set up action with proper target context
    let targetObject: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, data.m_actionOwner) as GameObject;
    if IsDefined(targetObject) {
        // Set the executor context for proper target resolution
        puppetAction.SetExecutor(targetObject);
        // Register the action against the target
        puppetAction.RegisterAsRequester(data.m_actionOwner);
    }
    
    LogChannel(n"DEBUG", s"[QueueMod] Reconstructed action: \(GetLocalizedText(data.m_title)) tweakID: \(TDBID.ToStringDEBUG(actionTweakID))");
    
    return puppetAction;
}

@addMethod(QuickhacksListGameController)
private func FindActionTweakID(data: ref<QuickhackData>) -> TweakDBID {
    if !IsDefined(data) {
        return TDBID.None();
    }

    // Derive from title (common pattern)
    let titleStr: String = GetLocalizedText(data.m_title);
    
    // Common quickhack mappings for 1.63
    if Equals(titleStr, "Reboot Optics") {
        return t"QuickHack.BlindHack";
    }
    if Equals(titleStr, "Overheat") {
        return t"QuickHack.OverheatHack";
    }
    if Equals(titleStr, "Short Circuit") {
        return t"QuickHack.ShortCircuitHack";
    }
    if Equals(titleStr, "Synapse Burnout") {
        return t"QuickHack.SynapseBurnoutHack";
    }
    if Equals(titleStr, "Distract Enemies") {
        return t"QuickHack.SuicideHack";
    }
    if Equals(titleStr, "Cyberware Malfunction") {
        return t"QuickHack.MalfunctionHack";
    }
    if Equals(titleStr, "System Reset") {
        return t"QuickHack.SystemCollapseHack";
    }
    if Equals(titleStr, "Contagion") {
        return t"QuickHack.CommsNoiseHack";
    }
    if Equals(titleStr, "Memory Wipe") {
        return t"QuickHack.MemoryWipeHack";
    }
    if Equals(titleStr, "Weapon Glitch") {
        return t"QuickHack.WeaponGlitchHack";
    }
    if Equals(titleStr, "Disable Cyberware") {
        return t"QuickHack.DisableCyberwareHack";
    }
    if Equals(titleStr, "Berserk") {
        return t"QuickHack.BerserkHack";
    }
    if Equals(titleStr, "Suicide") {
        return t"QuickHack.SuicideHack";
    }

    LogChannel(n"DEBUG", s"[QueueMod] Unknown quickhack title: \(titleStr)");
    return TDBID.None();
}

@addMethod(QuickhacksListGameController)
private func QM_ChangeRamForPlayer(delta: Float) -> Bool {
    let ps: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = IsDefined(ps) ? ps.GetLocalPlayerMainGameObject() as PlayerPuppet : null;
    if !IsDefined(player) { return false; }
    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);
    let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, delta, player, false);
    return true;
}

// Note: StoreIntentFromData removed - intent system was redundant

// =============================================================================
// Phase 4.4: UI Support Methods
// =============================================================================

// Cooldown application for queued actions
@addMethod(QuickhacksListGameController)
private func ApplyQueueModCooldownWithData(data: ref<QuickhackData>) -> Void {
    if !IsDefined(data) || data.m_cooldown <= 0.0 {
        return;
    }

    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;

    if IsDefined(player) && TDBID.IsValid(data.m_cooldownTweak) {
        StatusEffectHelper.ApplyStatusEffect(player, data.m_cooldownTweak);
        LogChannel(n"DEBUG", s"[QueueMod] Applied cooldown: \(data.m_cooldown)s");
        
        // Find and update the specific widget
        let i: Int32 = 0;
        while i < ArraySize(this.m_data) {
            if Equals(this.m_data[i].m_title, data.m_title) {
                // Update data
                this.m_data[i].m_isLocked = true;
                this.m_data[i].m_inactiveReason = "LocKey#40765";
                break;
            }
            i += 1;
        }
        
        // BUG 2 FIX: Force immediate visual update
        this.ForceWheelRedraw();
        
        // Force UI refresh after cooldown application
        this.RegisterCooldownStatPoolUpdate();
        LogChannel(n"DEBUG", "[QueueMod] Cooldown applied - wheel redrawn for recompiling");
    }
}

@addMethod(QuickhacksListGameController)
private func QM_FireQueueEvent(eventType: CName, data: ref<QuickhackData>) -> Void {
    // Fire QueueEvent for state synchronization
    LogChannel(n"DEBUG", s"[QueueMod][Event] Fired \(ToString(eventType)) for \(GetLocalizedText(data.m_title))");
    
    // Create and fire queue event for UI synchronization
    let queueEvent: ref<QueueModEvent> = new QueueModEvent();
    queueEvent.eventType = eventType;
    queueEvent.quickhackData = data;
    queueEvent.timestamp = GameInstance.GetTimeSystem(this.m_gameInstance).GetGameTimeStamp();
    
    // Fire the event to notify QueueStateSynchronizer
    GameInstance.GetUISystem(this.m_gameInstance).QueueEvent(queueEvent);
    
    // Also trigger immediate UI refresh
    // Note: UI refresh now handled by QuickhackModule.RequestRefreshQuickhackMenu
}

// UI refresh method
// FIX 3: UI Refresh Scheduler - Active refresh for async state changes
@addMethod(QuickhacksListGameController)
private func ScheduleUIRefresh() -> Void {
    if this.m_qmRefreshScheduled {
        return; // Already scheduled
    }
    
    this.m_qmRefreshScheduled = true;
    
    // Note: DelayEvent API limited in v1.63, using immediate refresh as fallback
    // In production, implement proper delay system when API is available
    // Note: UI refresh now handled by QuickhackModule.RequestRefreshQuickhackMenu
    this.m_qmRefreshScheduled = false;
    LogChannel(n"DEBUG", "[QueueMod] UI refresh executed immediately (v1.63 fallback)");
}

// BUG 2 FIX: Force widget state invalidation for cooldowns (v1.63 compatible)
@addMethod(QuickhacksListGameController)
private func ForceWidgetStateUpdate(index: Int32, isLocked: Bool, reason: String) -> Void {
    // v1.63 compatible approach - force widget state changes via list controller refresh
    LogChannel(n"DEBUG", s"[QueueMod] Forcing widget state update at index \(index): locked=\(isLocked)");
    
    // Force the entire list to refresh to show updated states
    if IsDefined(this.m_listController) {
        this.m_listController.Refresh();
        LogChannel(n"DEBUG", "[QueueMod] List controller refreshed for widget state update");
    }
}

// BUG 2 FIX: Force wheel redraw for immediate visual updates (v1.63 compatible)
@addMethod(QuickhacksListGameController)
private func ForceWheelRedraw() -> Void {
    // Force complete data reload (v1.63 compatible approach)
    let tempData: array<ref<QuickhackData>> = this.m_data;
    ArrayClear(this.m_data);
    if IsDefined(this.m_listController) {
        this.m_listController.Clear();
    }
    
    // Re-add with updated states
    this.m_data = tempData;
    this.PopulateData(this.m_data);
    
    // Trigger parent widget invalidation
    let rootWidget: ref<inkWidget> = this.GetRootWidget();
    if IsDefined(rootWidget) {
        rootWidget.SetVisible(false);
        rootWidget.SetVisible(true);
        LogChannel(n"DEBUG", "[QueueMod] Forced parent widget visibility toggle");
    }
    
    LogChannel(n"DEBUG", "[QueueMod] Wheel redraw completed with data array manipulation");
}

// Note: QuickhackItemController API not available in v1.63
// Using direct widget manipulation instead


// Store controller reference on player during first UI refresh call
@addField(QuickhacksListGameController)
private let m_qmControllerStored: Bool;

// Phase 4: Clear Controller Cache with Proper Repopulation
@addMethod(QuickhacksListGameController)
public func ClearControllerCacheInternal() -> Void {
    LogChannel(n"DEBUG", "[QueueMod] Clearing controller cache with repopulation");
    
    // Store current target for repopulation
    let currentTarget: EntityID = this.m_lastCompiledTarget;
    LogChannel(n"DEBUG", s"[QueueMod] Stored current target: \(EntityID.ToDebugString(currentTarget))");
    
    // Clear m_data array completely
    ArrayClear(this.m_data);
    LogChannel(n"DEBUG", "[QueueMod] Cleared m_data array");
    
    // Reset selected data
    this.m_selectedData = null;
    LogChannel(n"DEBUG", "[QueueMod] Reset m_selectedData");
    
    // Reset last compiled target (field removed - not defined)
    // this.m_lastCompiledTarget = EntityID();
    // LogChannel(n"DEBUG", "[QueueMod] Reset m_lastCompiledTarget");
    
    // Clear list controller with force flag
    if IsDefined(this.m_listController) {
        this.m_listController.Clear(true);
        LogChannel(n"DEBUG", "[QueueMod] Cleared list controller with force flag");
    }
    
    // ✅ CRITICAL FIX: Repopulate with fresh data if we had a valid target
    if EntityID.IsDefined(currentTarget) {
        LogChannel(n"DEBUG", "[QueueMod] Repopulating with fresh data for stored target");
        this.RepopulateWithFreshData(currentTarget);
    } else {
        LogChannel(n"DEBUG", "[QueueMod] No valid target to repopulate");
    }
    
    LogChannel(n"DEBUG", "[QueueMod] Controller cache clearing and repopulation complete");
}

// ✅ CRITICAL FIX: Repopulate with Fresh Data
@addMethod(QuickhacksListGameController)
public func RepopulateWithFreshData(targetID: EntityID) -> Void {
    LogChannel(n"DEBUG", s"[QueueMod] Repopulating with fresh data for: \(EntityID.ToDebugString(targetID))");
    
    let targetObject: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as GameObject;
    if !IsDefined(targetObject) {
        LogChannel(n"ERROR", "[QueueMod] Target not found for repopulation");
        return;
    }
    
    // Check if it's a ScriptedPuppet (NPC)
    let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
    if IsDefined(puppet) {
        LogChannel(n"DEBUG", "[QueueMod] Repopulating puppet data");
        // Generate fresh puppet commands
        let actions: array<ref<PuppetAction>>;
        let commands: array<ref<QuickhackData>>;
        puppet.TranslateChoicesIntoQuickSlotCommands(actions, commands);
        
        // Update controller data with fresh commands
        this.m_data = commands;
        this.m_lastCompiledTarget = targetID;
        
        // Repopulate the UI
        this.PopulateData(commands);
        LogChannel(n"DEBUG", s"[QueueMod] Repopulated with \(ArraySize(commands)) puppet commands");
        return;
    }
    
    // Check if it's a Device
    let device: ref<Device> = targetObject as Device;
    if IsDefined(device) {
        LogChannel(n"DEBUG", "[QueueMod] Repopulating device data");
        // Generate fresh device commands
        let actions: array<ref<DeviceAction>>;
        let context: GetActionsContext;
        device.GetDevicePS().GetQuickHackActions(actions, context);
        
        // Convert to QuickhackData and update controller
        let commands: array<ref<QuickhackData>>;
        QuickhackQueueHelper.ConvertDeviceActionsToCommands(actions, commands);
        
        this.m_data = commands;
        this.m_lastCompiledTarget = targetID;
        
        // Repopulate the UI
        this.PopulateData(commands);
        LogChannel(n"DEBUG", s"[QueueMod] Repopulated with \(ArraySize(commands)) device commands");
        return;
    }
    
        LogChannel(n"ERROR", s"[QueueMod] Unknown target type for repopulation: \(ToString(targetObject.GetClassName()))");
    }


// Store controller reference on player for UI access - using OnInitialize
@wrapMethod(QuickhacksListGameController)
protected cb func OnInitialize() -> Bool {
    let result: Bool = wrappedMethod();
    let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.m_gameInstance).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if IsDefined(player) {
        player.SetQuickhacksListGameController(this);
        this.m_qmControllerStored = true;
        LogChannel(n"DEBUG", "[QueueMod] Controller reference stored on player via OnInitialize");
    }
    return result;
}
