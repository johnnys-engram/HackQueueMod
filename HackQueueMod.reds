// =============================================================================
// Phase 1: Core Queue Foundation & Phase 2: Target Resolution & Action Binding & Phase 3: Execution Pipeline & Upload Tracking & Phase 4: UI Integration & Queue Management
// =============================================================================

// Basic queue with weak reference pattern for v1.63 stability
// NEW: Composite queue entry (Single Source of Truth)
public class QueueModEntry {
    public let action: ref<DeviceAction>;
    public let fingerprint: String;
    public let timestamp: Float;
    public let entryType: String; // "action" or "intent"
    public let intent: ref<QueueModIntent>; // For intent entries
    public let uploadSpeedModifier: Float; // Speed multiplier for queued uploads
    
    public static func CreateAction(action: ref<DeviceAction>, key: String) -> ref<QueueModEntry> {
        let entry: ref<QueueModEntry> = new QueueModEntry();
        entry.action = action;
        entry.fingerprint = key;
        entry.entryType = "action";
        entry.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        entry.intent = null;
        entry.uploadSpeedModifier = 1.0; // Default speed
        return entry;
    }
    
    public static func CreateIntent(intent: ref<QueueModIntent>) -> ref<QueueModEntry> {
        let entry: ref<QueueModEntry> = new QueueModEntry();
        entry.action = null;
        entry.fingerprint = s"\(ToString(intent.targetID))::\(intent.actionTitle)";
        entry.entryType = "intent";
        entry.timestamp = intent.timestamp;
        entry.intent = intent;
        entry.uploadSpeedModifier = 1.0; // Default speed
        return entry;
    }
    
    public static func CreateActionWithSpeed(action: ref<DeviceAction>, key: String, speedModifier: Float) -> ref<QueueModEntry> {
        let entry: ref<QueueModEntry> = new QueueModEntry();
        entry.action = action;
        entry.fingerprint = key;
        entry.entryType = "action";
        entry.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        entry.intent = null;
        entry.uploadSpeedModifier = speedModifier;
        return entry;
    }
}

// UPDATED: Single array replaces three parallel arrays
public class QueueModActionQueue {
    private let m_queueEntries: array<ref<QueueModEntry>>; // SINGLE SOURCE
    private let m_isQueueLocked: Bool;
    private let m_maxQueueSize: Int32 = 3;

    public func PutActionInQueue(action: ref<DeviceAction>) -> Bool {
        if !IsDefined(action) || this.m_isQueueLocked || ArraySize(this.m_queueEntries) >= this.m_maxQueueSize {
            return false;
        }
        
        // Generate automatic key for keyless operations
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let autoKey: String = s"auto::\(TDBID.ToStringDEBUG(sa.GetObjectActionID()))::\(GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp())";
            return this.PutActionInQueueWithKey(action, autoKey);
        }
        return false;
    }

    public func PutActionInQueueWithKey(action: ref<DeviceAction>, key: String) -> Bool {
        // PHASE 3A: Comprehensive validation (v1.63 IsDefined pattern)
        if !IsDefined(action) || this.m_isQueueLocked || ArraySize(this.m_queueEntries) >= this.m_maxQueueSize {
            return false;
        }
        
        // PHASE 3B: Atomic duplicate check (single pass, early return)
        let i: Int32 = 0;
        let maxIterations: Int32 = 100; // v1.63 safety pattern
        while i < ArraySize(this.m_queueEntries) && i < maxIterations {
            if IsDefined(this.m_queueEntries[i]) && Equals(this.m_queueEntries[i].fingerprint, key) {
                LogChannel(n"DEBUG", s"[QueueMod] Duplicate key rejected: \(key)");
                return false; // Early return prevents corruption
            }
            i += 1;
        }
        
        // PHASE 3C: Atomic insertion (single operation, no intermediate state)
        let entry: ref<QueueModEntry> = QueueModEntry.CreateAction(action, key);
        if !IsDefined(entry) {
            LogChannel(n"ERROR", "[QueueMod] Failed to create queue entry");
            return false;
        }
        
        // Reserve RAM before adding to queue
        if !this.ReserveRAMForAction(action) {
            LogChannel(n"DEBUG", s"[QueueMod] Insufficient RAM to queue action: \(key)");
            return false;
        }
        
        ArrayPush(this.m_queueEntries, entry);
        LogChannel(n"DEBUG", s"[QueueMod] Entry added atomically: \(key), size=\(ArraySize(this.m_queueEntries))");
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
        if IsDefined(entry) && Equals(entry.entryType, "action") && IsDefined(entry.action) {
            return entry.action;
        }
        return null;
    }

    public func GetQueueSize() -> Int32 {
        return ArraySize(this.m_queueEntries);
    }

    public func ClearQueue() -> Void {
        // Refund RAM for all queued actions before clearing
        let i: Int32 = 0;
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if IsDefined(entry) && Equals(entry.entryType, "action") && IsDefined(entry.action) {
                this.RefundRAMForAction(entry.action);
            }
            i += 1;
        }
        
        ArrayClear(this.m_queueEntries);
        LogChannel(n"DEBUG", "[QueueMod] Queue cleared - RAM refunded");
    }

    public func LockQueue() -> Void {
        this.m_isQueueLocked = true;
    }

    public func UnlockQueue() -> Void {
        this.m_isQueueLocked = false;
    }

    // Intent management methods
    public func AddIntent(intent: ref<QueueModIntent>) -> Bool {
        if !IsDefined(intent) || this.m_isQueueLocked || ArraySize(this.m_queueEntries) >= this.m_maxQueueSize {
            return false;
        }
        
        let entry: ref<QueueModEntry> = QueueModEntry.CreateIntent(intent);
        if !IsDefined(entry) {
            return false;
        }
        
        ArrayPush(this.m_queueEntries, entry);
        LogChannel(n"DEBUG", s"[QueueMod] Intent added: \(intent.actionTitle)");
        return true;
    }

    public func ConsumeIntent(targetID: EntityID) -> ref<QueueModIntent> {
        let i: Int32 = 0;
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if IsDefined(entry) && Equals(entry.entryType, "intent") && 
               IsDefined(entry.intent) && Equals(entry.intent.targetID, targetID) {
                ArrayErase(this.m_queueEntries, i);
                LogChannel(n"DEBUG", s"[QueueMod] Intent consumed: \(entry.intent.actionTitle)");
                return entry.intent;
            }
            i += 1;
        }
        return null;
    }

    public func HasIntent(targetID: EntityID) -> Bool {
        let i: Int32 = 0;
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if IsDefined(entry) && Equals(entry.entryType, "intent") && 
               IsDefined(entry.intent) && Equals(entry.intent.targetID, targetID) {
                return true;
            }
            i += 1;
        }
        return false;
    }

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
            } else if Equals(entry.entryType, "action") && !IsDefined(entry.action) {
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
                if Equals(entry.entryType, "action") && IsDefined(entry.action) {
                    // ADD: Validate action is still usable
                    let sa: ref<ScriptableDeviceAction> = entry.action as ScriptableDeviceAction;
                    if IsDefined(sa) && TDBID.IsValid(sa.GetObjectActionID()) {
                        ArrayPush(cleanEntries, entry);
                    }
                } else if Equals(entry.entryType, "intent") && IsDefined(entry.intent) {
                    // ADD: Validate intent is still usable  
                    if TDBID.IsValid(entry.intent.actionTweakID) {
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
    
    // RAM Cost Reservation System (Simplified for v1.63)
    private func ReserveRAMForAction(action: ref<DeviceAction>) -> Bool {
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if !IsDefined(sa) {
            return true; // Non-ScriptableDeviceAction doesn't use RAM
        }
        
        // Get RAM cost from action data
        let ramCost: Int32 = this.GetActionRAMCost(sa);
        if ramCost <= 0 {
            return true; // No RAM cost
        }
        
        // TODO: Implement proper RAM reservation system
        // For now, just log the RAM cost
        LogChannel(n"DEBUG", s"[QueueMod] Would reserve \(ramCost) RAM for queued action");
        return true; // Always allow for now
    }
    
    private func RefundRAMForAction(action: ref<DeviceAction>) -> Void {
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if !IsDefined(sa) {
            return; // Non-ScriptableDeviceAction doesn't use RAM
        }
        
        let ramCost: Int32 = this.GetActionRAMCost(sa);
        if ramCost <= 0 {
            return; // No RAM cost
        }
        
        // TODO: Implement proper RAM refund system
        LogChannel(n"DEBUG", s"[QueueMod] Would refund \(ramCost) RAM for canceled action");
    }
    
    private func GetActionRAMCost(action: ref<ScriptableDeviceAction>) -> Int32 {
        // TODO: Implement proper RAM cost calculation from action data
        // For now, return a default cost
        return 2; // Default RAM cost for quickhacks
    }
    
    // Upload Speed Modifiers (2.0 style)
    private func CalculateUploadSpeedModifier(queuePosition: Int32) -> Float {
        // First hack = full time, subsequent hacks = 20% faster
        if queuePosition <= 0 {
            return 1.0; // First hack at full speed
        }
        
        // Each additional hack is 20% faster (0.8x time)
        let speedModifier: Float = 1.0 - (Cast<Float>(queuePosition) * 0.2);
        return MaxF(speedModifier, 0.3); // Minimum 30% of original time
    }
    
    public func PutActionInQueueWithSpeedModifier(action: ref<DeviceAction>, key: String) -> Bool {
        if !IsDefined(action) || this.m_isQueueLocked || ArraySize(this.m_queueEntries) >= this.m_maxQueueSize {
            return false;
        }
        
        // Calculate speed modifier based on current queue size
        let queuePosition: Int32 = ArraySize(this.m_queueEntries);
        let speedModifier: Float = this.CalculateUploadSpeedModifier(queuePosition);
        
        // Reserve RAM before adding to queue
        if !this.ReserveRAMForAction(action) {
            LogChannel(n"DEBUG", s"[QueueMod] Insufficient RAM to queue action: \(key)");
            return false;
        }
        
        // Create entry with speed modifier
        let entry: ref<QueueModEntry> = QueueModEntry.CreateActionWithSpeed(action, key, speedModifier);
        if !IsDefined(entry) {
            LogChannel(n"ERROR", "[QueueMod] Failed to create queue entry");
            this.RefundRAMForAction(action);
            return false;
        }
        
        ArrayPush(this.m_queueEntries, entry);
        LogChannel(n"DEBUG", s"[QueueMod] Entry added with speed modifier \(speedModifier): \(key), size=\(ArraySize(this.m_queueEntries))");
        return true;
    }
}

public class QueueModIntent {
    public let targetID: EntityID;
    public let actionTweakID: TweakDBID;
    public let actionTitle: String;
    public let timestamp: Float;
    
    public static func Create(target: EntityID, tweakID: TweakDBID, title: String) -> ref<QueueModIntent> {
        let intent: ref<QueueModIntent> = new QueueModIntent();
        intent.targetID = target;
        intent.actionTweakID = tweakID;
        intent.actionTitle = title;
        intent.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return intent;
    }
}

// Global state removed - using per-puppet storage only

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
                    return queue.PutActionInQueueWithKey(action, key);
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

    // Call vanilla first for normal v1.63 behavior
    wrappedMethod(puppetActions, commands);

    // Only intervene when there's an active upload
    LogChannel(n"DEBUG", s"[QueueMod][Debug] Upload check: isOngoingUpload=\(isOngoingUpload)");
    if isOngoingUpload {
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
                        
                        // Try multiple possible lock reasons
                        let isUploadLock: Bool = Equals(ToString(commands[i].m_inactiveReason), "LocKey#27398") || 
                                                 Equals(ToString(commands[i].m_inactiveReason), "LocKey#40765") ||
                                                 Equals(ToString(commands[i].m_inactiveReason), "LocKey#7020") ||
                                                 Equals(ToString(commands[i].m_inactiveReason), "LocKey#7019");
                        if isUploadLock {
                            LogChannel(n"DEBUG", s"[QueueMod][Debug] Found locked command with upload reason: \(GetLocalizedText(commands[i].m_inactiveReason))");
                            
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
    let result: Bool = wrappedMethod(evt);

    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) {
        if Equals(evt.progressBarType, EProgressBarType.UPLOAD) {
            if Equals(evt.state, EUploadProgramState.COMPLETED) {
                let sizeBefore: Int32 = this.GetQueueModActionQueue().GetQueueSize();
                LogChannel(n"DEBUG", s"[QueueMod][Exec] Upload complete for NPC=\(GetLocalizedText(this.GetDisplayName())) queueSizeBefore=\(sizeBefore)");

                // Check THIS puppet's queue for intents and actions
                let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
                if IsDefined(queue) {
                    // CRITICAL: Validate before processing
                    if !queue.ValidateQueueIntegrity() {
                        LogChannel(n"ERROR", "[QueueMod] Queue integrity failed - skipping execution");
                        return result;
                    }
                    
                    if queue.GetQueueSize() > 0 {
                        let entry: ref<QueueModEntry> = queue.PopNextEntry();
                        if IsDefined(entry) {
                            this.ExecuteQueuedEntry(entry);
                        }
                    } else {
                        LogChannel(n"DEBUG", "[QueueMod] No queued entries to execute");
                    }
                }
            }
        }
    }

    return result;
}

@addMethod(ScriptedPuppet)
private func ExecuteQueuedEntry(entry: ref<QueueModEntry>) -> Void {
    if !IsDefined(entry) {
        LogChannel(n"ERROR", "[QueueMod] ExecuteQueuedEntry called with null entry");
        return;
    }

    // Step 4: Handle failures gracefully - check if target is still valid
    if !IsDefined(this) {
        LogChannel(n"DEBUG", "[QueueMod] Target is invalid - clearing queue");
        this.NotifyPlayerQueueCanceled("Target eliminated, queued quickhacks canceled.");
        return;
    }

    if Equals(entry.entryType, "action") && IsDefined(entry.action) {
        // Process action
        LogChannel(n"DEBUG", s"[QueueMod][Exec] Executing queued action: class=\(entry.action.GetClassName()) on NPC=\(GetLocalizedText(this.GetDisplayName()))");
        let saExec: ref<ScriptableDeviceAction> = entry.action as ScriptableDeviceAction;
        if IsDefined(saExec) {
            saExec.RegisterAsRequester(this.GetEntityID());
                            let quickSlotCmd: ref<QuickSlotCommandUsed> = new QuickSlotCommandUsed();
            quickSlotCmd.action = saExec;
                            this.OnQuickSlotCommandUsed(quickSlotCmd);
            LogChannel(n"DEBUG", s"[QueueMod][Exec] Successfully executed queued action: \(entry.action.GetClassName())");
        } else {
            LogChannel(n"DEBUG", s"[QueueMod][Exec] Skip non-ScriptableDeviceAction: class=\(entry.action.GetClassName())");
        }
    } else if Equals(entry.entryType, "intent") && IsDefined(entry.intent) {
        // Process intent  
        LogChannel(n"DEBUG", s"[QueueMod][Intent] Processing stored intent: \(entry.intent.actionTitle)");
        
        // Validate intent data
        if !TDBID.IsValid(entry.intent.actionTweakID) {
            LogChannel(n"ERROR", s"[QueueMod] Invalid intent TweakDBID - clearing queue");
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) {
                queue.ClearQueue();
            }
            return;
        }
        
        let puppetAction: ref<PuppetAction> = new PuppetAction();
        puppetAction.SetObjectActionID(entry.intent.actionTweakID);
        puppetAction.RegisterAsRequester(entry.intent.targetID);
        let quickSlotCmd: ref<QuickSlotCommandUsed> = new QuickSlotCommandUsed();
        quickSlotCmd.action = puppetAction;
        this.OnQuickSlotCommandUsed(quickSlotCmd);
        LogChannel(n"DEBUG", s"[QueueMod][Intent] Successfully executed intent: \(entry.intent.actionTitle)");
                } else {
        LogChannel(n"ERROR", s"[QueueMod] Invalid entry type or missing data: type=\(entry.entryType) action=\(IsDefined(entry.action)) intent=\(IsDefined(entry.intent))");
        // Clear queue on invalid data
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.ClearQueue();
        }
    }

    // Step 3: Sync UI State after execution
    this.RefreshQueueModUI();
}

@addMethod(ScriptedPuppet)
private func RefreshQueueModUI() -> Void {
    // Try to refresh the player's queue UI
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    if IsDefined(playerSystem) {
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();
            if IsDefined(queueHelper) {
                // This will trigger UI refresh if available
                LogChannel(n"DEBUG", "[QueueMod] UI refresh triggered after queue execution");
            }
        }
    }
    
    // Update HUD overlay for this target
    this.UpdateQueueHUDOverlay();
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

// Queue Persistence Across Scanner Toggles
@addMethod(ScriptedPuppet)
public func GetQueueModPersistenceData() -> String {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return "";
    }
    
    let queueSize: Int32 = queue.GetQueueSize();
    if queueSize == 0 {
        return "";
    }
    
    // Serialize queue data for persistence
    let entityIDStr: String = ToString(this.GetEntityID());
    let queueSizeStr: String = ToString(queueSize);
    let persistenceData: String = s"\(entityIDStr)::\(queueSizeStr)";
    LogChannel(n"DEBUG", s"[QueueMod][Persistence] Storing queue data: \(persistenceData)");
    return persistenceData;
}

@addMethod(ScriptedPuppet)
public func RestoreQueueModPersistenceData(data: String) -> Void {
    if Equals(data, "") {
        return;
    }
    
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return;
    }
    
    // Parse persistence data and restore queue state
    LogChannel(n"DEBUG", s"[QueueMod][Persistence] Restoring queue data: \(data)");
    // TODO: Implement proper deserialization and queue restoration
}

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

// =============================================================================
// Phase 2.6: PlayerPuppet Integration for Queue Helper Access
// =============================================================================

// PlayerPuppet integration for queue helper access
@addField(PlayerPuppet)
private let m_queueModHelper: ref<QueueModHelper>;

@addMethod(PlayerPuppet)
public func GetQueueModHelper() -> ref<QueueModHelper> {
    if !IsDefined(this.m_queueModHelper) {
        this.m_queueModHelper = new QueueModHelper();
        LogChannel(n"DEBUG", "[QueueMod] Player loaded - queue system ready");
    }
    return this.m_queueModHelper;
}

// =============================================================================
// Phase 4: UI Integration & Queue Management
// =============================================================================

// =============================================================================
// Phase 4.1: UI Upload Detection Methods - v1.63 Compatible
// =============================================================================

@addMethod(QuickhacksListGameController)
private func IsQuickHackCurrentlyUploading() -> Bool {
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        return false;
    }
    
    // FIX: Primary detection method - StatPool system
    let hasUploadPool: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance).IsStatPoolAdded(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    LogChannel(n"DEBUG", s"[QueueMod][Detect] Player upload pool: \(hasUploadPool)");
    return hasUploadPool;
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

    // Check if we should queue
    let shouldQueue: Bool = this.IsQuickHackCurrentlyUploading();
    LogChannel(n"DEBUG", s"[QueueMod] Should queue: \(shouldQueue)");

    // Additional debug info for upload detection
    if !shouldQueue {
        LogChannel(n"DEBUG", s"[QueueMod][Debug] Upload detection details - UI lock: \(this.QueueModDetectUILock())");
    }

    if shouldQueue {
        // Create PuppetAction from metadata (no m_action dependency)
        let reconstructedAction: ref<PuppetAction> = this.ReconstructActionFromData(this.m_selectedData);
        if IsDefined(reconstructedAction) {
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;

        if IsDefined(player) {
            let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();
            if IsDefined(queueHelper) {
                    let uniqueKey: String = s"\(ToString(targetID))::\(actionName)::\(GameInstance.GetTimeSystem(this.m_gameInstance).GetSimTime())";
                    
                    let wasQueued: Bool = queueHelper.PutInQuickHackQueueWithKey(reconstructedAction, uniqueKey);
                if wasQueued {
                        LogChannel(n"DEBUG", s"[QueueMod] Queued reconstructed: \(actionName)");
                        this.ApplyQueueModCooldownWithData(this.m_selectedData);
                    this.RefreshQueueModUI();
                    return true;
                    }
                }
            }
        }
    }

    // Store intent with metadata (no action dependency)
    this.StoreIntentFromData(this.m_selectedData);
    
    LogChannel(n"DEBUG", "[QueueMod] Executing normally");
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
private func StoreIntentFromData(data: ref<QuickhackData>) -> Void {
    if !IsDefined(data) || !EntityID.IsDefined(data.m_actionOwner) {
        return;
    }

    let targetObject: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, data.m_actionOwner) as GameObject;
    let targetPuppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;

    if IsDefined(targetPuppet) {
        let actionTweakID: TweakDBID = this.FindActionTweakID(data);
        let actionName: String = GetLocalizedText(data.m_title);
        
        let intent: ref<QueueModIntent> = QueueModIntent.Create(
            data.m_actionOwner,
            actionTweakID,
            actionName
        );
        
        let queue: ref<QueueModActionQueue> = targetPuppet.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.AddIntent(intent);
            LogChannel(n"DEBUG", s"[QueueMod] Stored intent from metadata: \(actionName)");
        }
    }
}

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
        this.RegisterCooldownStatPoolUpdate();
    }
}

// UI refresh method
@addMethod(QuickhacksListGameController)
private func RefreshQueueModUI() -> Void {
    if ArraySize(this.m_data) > 0 {
        this.PopulateData(this.m_data);
    }
    if IsDefined(this.m_listController) {
        this.m_listController.Refresh();
    }
    this.RegisterCooldownStatPoolUpdate();
}
