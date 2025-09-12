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
    
    public static func CreateAction(action: ref<DeviceAction>, key: String) -> ref<QueueModEntry> {
        let entry: ref<QueueModEntry> = new QueueModEntry();
        entry.action = action;
        entry.fingerprint = key;
        entry.entryType = "action";
        entry.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        entry.intent = null;
        return entry;
    }
    
    public static func CreateIntent(intent: ref<QueueModIntent>) -> ref<QueueModEntry> {
        let entry: ref<QueueModEntry> = new QueueModEntry();
        entry.action = null;
        entry.fingerprint = s"\(ToString(intent.targetID))::\(intent.actionTitle)";
        entry.entryType = "intent";
        entry.timestamp = intent.timestamp;
        entry.intent = intent;
        return entry;
    }
}

// UPDATED: Single array replaces three parallel arrays
public class QueueModActionQueue {
    private let m_queueEntries: array<ref<QueueModEntry>>; // SINGLE SOURCE
    private let m_isQueueLocked: Bool;
    private let m_maxQueueSize: Int32 = 3;

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
        
        ArrayPush(this.m_queueEntries, entry);
        LogChannel(n"DEBUG", s"[QueueMod] Entry added atomically: \(key), size=\(ArraySize(this.m_queueEntries))");
        return true;
    }

    public func PopActionInQueue() -> ref<DeviceAction> {
        // PHASE 3D: Atomic pop operation (no intermediate states)
        if ArraySize(this.m_queueEntries) == 0 {
            return null; // Early return, no state change
        }
        
        let entry: ref<QueueModEntry> = this.m_queueEntries[0];
        if !IsDefined(entry) {
            LogChannel(n"ERROR", "[QueueMod] Null entry detected - clearing queue for safety");
            this.ClearQueue(); // v1.63 recovery pattern
            return null;
        }
        
        // Atomic removal - single operation
        ArrayErase(this.m_queueEntries, 0);
        
        // Return action if this was an action entry
        if Equals(entry.entryType, "action") && IsDefined(entry.action) {
            LogChannel(n"DEBUG", s"[QueueMod] Action popped: \(entry.fingerprint)");
            return entry.action;
        }
        
        LogChannel(n"DEBUG", s"[QueueMod] Intent entry popped: \(entry.fingerprint)");
        return null; // Intent entries don't return actions
    }

    public func GetQueueSize() -> Int32 {
        return ArraySize(this.m_queueEntries);
    }

    public func ClearQueue() -> Void {
        ArrayClear(this.m_queueEntries);
        LogChannel(n"DEBUG", "[QueueMod] Queue cleared");
    }

    public func LockQueue() -> Void {
        this.m_isQueueLocked = true;
    }

    public func UnlockQueue() -> Void {
        this.m_isQueueLocked = false;
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
                    ArrayPush(cleanEntries, entry);
                } else if Equals(entry.entryType, "intent") && IsDefined(entry.intent) {
                    ArrayPush(cleanEntries, entry);
                }
            }
            i += 1;
        }
        
        // Atomic replacement
        ArrayClear(this.m_queueEntries);
        this.m_queueEntries = cleanEntries;
        
        LogChannel(n"DEBUG", s"[QueueMod] Emergency cleanup complete - \(ArraySize(this.m_queueEntries)) entries recovered");
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

public class QueueModState {
    public let s_npcUploadOngoing: Bool = false;
    private let s_intentStore: array<ref<QueueModIntent>>;
    
    public func SetNpcUploadOngoing(value: Bool) -> Void {
        this.s_npcUploadOngoing = value;
    }
    
    public func IsNpcUploadOngoing() -> Bool {
        return this.s_npcUploadOngoing;
    }
    
    public func AddIntent(intent: ref<QueueModIntent>) -> Bool {
        if !IsDefined(intent) {
            return false;
        }
        ArrayPush(this.s_intentStore, intent);
        LogChannel(n"DEBUG", s"[QueueMod] Intent stored globally: \(intent.actionTitle) for target: \(ToString(intent.targetID))");
        return true;
    }
    
    public func ConsumeIntent(targetID: EntityID) -> ref<QueueModIntent> {
        LogChannel(n"DEBUG", s"[QueueMod] ConsumeIntent called for target: \(ToString(targetID))");
        LogChannel(n"DEBUG", s"[QueueMod] Stored intents count: \(ArraySize(this.s_intentStore))");
        
        let i: Int32 = 0;
        while i < ArraySize(this.s_intentStore) {
            let intent = this.s_intentStore[i];
            LogChannel(n"DEBUG", s"[QueueMod] Checking intent \(i): target=\(ToString(intent.targetID)) action=\(intent.actionTitle)");
            if Equals(intent.targetID, targetID) {
                ArrayRemove(this.s_intentStore, intent);
                LogChannel(n"DEBUG", "[QueueMod] Intent consumed globally: " + intent.actionTitle);
                return intent;
            }
            i += 1;
        }
        LogChannel(n"DEBUG", "[QueueMod] No matching intent found for target");
        return null;
    }
    
    public func HasIntent(targetID: EntityID) -> Bool {
        let i: Int32 = 0;
        while i < ArraySize(this.s_intentStore) {
            let intent = this.s_intentStore[i];
            if Equals(intent.targetID, targetID) {
                return true;
            }
            i += 1;
        }
        return false;
    }
    
    public func ClearIntents() -> Void {
        ArrayClear(this.s_intentStore);
        LogChannel(n"DEBUG", "[QueueMod] All intents cleared");
    }
    
    public func ListAllIntents() -> Void {
        LogChannel(n"DEBUG", s"[QueueMod] === STORED INTENTS (count: \(ArraySize(this.s_intentStore))) ===");
        let i: Int32 = 0;
        while i < ArraySize(this.s_intentStore) {
            let intent = this.s_intentStore[i];
            LogChannel(n"DEBUG", s"[QueueMod] Intent \(i): target=\(ToString(intent.targetID)) action=\(intent.actionTitle)");
            i += 1;
        }
        LogChannel(n"DEBUG", "[QueueMod] === END INTENTS ===");
    }
}

// Global state instance - using a different approach
public class QueueModGlobalState {
    private let s_instance: ref<QueueModState>;
    
    public func GetInstance() -> ref<QueueModState> {
        if !IsDefined(this.s_instance) {
            this.s_instance = new QueueModState();
        }
        return this.s_instance;
    }
}

// Helper function to get global state
public func GetQueueModGlobalState() -> ref<QueueModState> {
    let globalState: ref<QueueModGlobalState> = new QueueModGlobalState();
    return globalState.GetInstance();
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
                    // Validate integrity before operation (v1.63 pattern)
                    queue.ValidateQueueIntegrity();
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
                // Validate integrity before operation (v1.63 pattern)
                queue.ValidateQueueIntegrity();
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
            let uniqueKey: String = s"\(ToString(puppetAction.GetRequesterID()))::\(TDBID.ToStringDEBUG(puppetAction.GetObjectActionID()))::\(GameInstance.GetTimeSystem(puppetAction.GetExecutor().GetGame()).GetGameTimeStamp())";
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
                    LogChannel(n"DEBUG", s"[QueueMod][Debug] Command \(i): locked=\(commands[i].m_isLocked) reason='\(commands[i].m_inactiveReason)' type=\(ToString(commands[i].m_type))");
                    
                    // Check for any locked command first
                    if commands[i].m_isLocked {
                        LogChannel(n"DEBUG", s"[QueueMod][Debug] Found locked command - checking reason");
                        
                        // Try multiple possible lock reasons
                        let isUploadLock: Bool = Equals(commands[i].m_inactiveReason, "LocKey#27398") || Equals(commands[i].m_inactiveReason, "LocKey#40765");
                        if isUploadLock {
                            LogChannel(n"DEBUG", s"[QueueMod][Debug] Found locked command with upload reason");
                            
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
                if IsDefined(commands[i2]) && commands[i2].m_isLocked && (Equals(commands[i2].m_inactiveReason, "LocKey#27398") || Equals(commands[i2].m_inactiveReason, "LocKey#40765")) && Equals(commands[i2].m_type, gamedataObjectActionType.MinigameUpload) {
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

                // First check for stored intents
                LogChannel(n"DEBUG", s"[QueueMod][Intent] Checking for stored intents for target: \(ToString(this.GetEntityID()))");
                GetQueueModGlobalState().ListAllIntents();
                let intent: ref<QueueModIntent> = GetQueueModGlobalState().ConsumeIntent(this.GetEntityID());
                if IsDefined(intent) {
                    LogChannel(n"DEBUG", s"[QueueMod][Intent] Processing stored intent: \(intent.actionTitle)");
                    
                    // Create a new ScriptableDeviceAction from the intent
                    LogChannel(n"DEBUG", s"[QueueMod][Intent] Executing stored intent: \(intent.actionTitle)");
                    
                    // Try to create a PuppetAction from the intent
                    let puppetAction: ref<PuppetAction> = new PuppetAction();
                    puppetAction.SetObjectActionID(intent.actionTweakID);
                    // Note: PuppetAction doesn't have SetRequesterID, requester is set via context
                    
                    if IsDefined(puppetAction) {
                        // Execute the action via QuickSlotCommandUsed
                        let quickSlotCmd: ref<QuickSlotCommandUsed> = new QuickSlotCommandUsed();
                        quickSlotCmd.action = puppetAction;
                        
                        this.OnQuickSlotCommandUsed(quickSlotCmd);
                        LogChannel(n"DEBUG", s"[QueueMod][Intent] Successfully executed intent: \(intent.actionTitle)");
                    } else {
                        LogChannel(n"DEBUG", s"[QueueMod][Intent] Failed to create PuppetAction from intent: \(intent.actionTitle)");
                    }
                } else {
                    // Fall back to regular queue processing
                    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
                    if IsDefined(queue) {
                        // CRITICAL: Validate before processing
                        if !queue.ValidateQueueIntegrity() {
                            LogChannel(n"ERROR", "[QueueMod] Queue integrity failed - skipping execution");
                            return result;
                        }
                        
                        if queue.GetQueueSize() > 0 {
                            let nextAction: ref<DeviceAction> = queue.PopActionInQueue();
                            if IsDefined(nextAction) {
                                LogChannel(n"DEBUG", s"[QueueMod][Exec] Executing queued action: class=\(nextAction.GetClassName()) on NPC=\(GetLocalizedText(this.GetDisplayName()))");

                                // Execute only ScriptableDeviceAction via QuickSlotCommandUsed
                                let saExec: ref<ScriptableDeviceAction> = nextAction as ScriptableDeviceAction;
                                if IsDefined(saExec) {
                                    // Ensure the NPC is the requester/target context
                                    saExec.RegisterAsRequester(this.GetEntityID());
                                    let quickSlotCmd: ref<QuickSlotCommandUsed> = new QuickSlotCommandUsed();
                                    quickSlotCmd.action = saExec;
                                    this.OnQuickSlotCommandUsed(quickSlotCmd);
                                } else {
                                    LogChannel(n"DEBUG", s"[QueueMod][Exec] Skip non-ScriptableDeviceAction: class=\(nextAction.GetClassName())");
                                }
                            }
                        } else {
                            LogChannel(n"DEBUG", "[QueueMod] No queued actions to execute");
                        }
                    }
                }
            }
        }
    }

    return result;
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
        if IsDefined(entry) && entry.m_isLocked && (Equals(entry.m_inactiveReason, "LocKey#27398") || Equals(entry.m_inactiveReason, "LocKey#40765")) {
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
    LogChannel(n"DEBUG", s"[QueueMod] UI State - m_selectedData: \(IsDefined(this.m_selectedData)), m_listController: \(IsDefined(this.m_listController)), m_data size: \(ArraySize(this.m_data))");

    // FIX: Check if we have valid selected data first
    let currentAction: ref<QuickhackData> = null;
    
    if IsDefined(this.m_selectedData) {
        currentAction = this.m_selectedData;
        LogChannel(n"DEBUG", "[QueueMod] Using m_selectedData");
    } else if IsDefined(this.m_listController) && this.m_listController.HasValidSelection() {
        // Fallback: get from list controller
        let selectedIndex: Int32 = this.m_listController.GetSelectedIndex();
        if selectedIndex >= 0 && selectedIndex < ArraySize(this.m_data) {
            currentAction = this.m_data[selectedIndex];
            LogChannel(n"DEBUG", s"[QueueMod] Fallback: using data from list controller index \(selectedIndex)");
        }
    }
    
    if !IsDefined(currentAction) {
        LogChannel(n"DEBUG", "[QueueMod] No valid selected data available - executing normally");
        return wrappedMethod();
    }

    if !IsDefined(currentAction.m_action) {
        LogChannel(n"DEBUG", "[QueueMod] No action in selected data - checking for stored intent");
        LogChannel(n"DEBUG", s"[QueueMod] Debug - currentAction.m_actionOwner: \(ToString(currentAction.m_actionOwner))");
        LogChannel(n"DEBUG", s"[QueueMod] Debug - currentAction.m_title: \(GetLocalizedText(currentAction.m_title))");
        
        // Check if we have a stored intent for this target
        let intent: ref<QueueModIntent> = GetQueueModGlobalState().ConsumeIntent(currentAction.m_actionOwner);
        if IsDefined(intent) {
            LogChannel(n"DEBUG", s"[QueueMod] Found stored intent for missing action: \(intent.actionTitle)");
            // The intent will be processed when the upload completes
            return wrappedMethod();
        }
        
        LogChannel(n"DEBUG", "[QueueMod] No action in selected data and no stored intent - executing normally");
        return wrappedMethod();
    }
    let actionName: String = GetLocalizedText(currentAction.m_title);
    
    LogChannel(n"DEBUG", s"[QueueMod] Processing: \(actionName)");

    // Cooldown gate first
    if this.QueueModIsOnCooldown(currentAction) {
        LogChannel(n"DEBUG", s"[QueueMod][Decision] Skip: on cooldown (\(actionName))");
        return wrappedMethod();
    }

    // Skip if action is already locked (no point in queuing)
    if currentAction.m_isLocked {
        LogChannel(n"DEBUG", s"[QueueMod][Decision] Skip: action already locked (\(actionName))");
        return wrappedMethod();
    }

    // FIX: Single, reliable upload detection
    let shouldQueue: Bool = this.IsQuickHackCurrentlyUploading();
    LogChannel(n"DEBUG", s"[QueueMod][Decision] Should queue (upload detected): \(shouldQueue)");

    if shouldQueue {
        LogChannel(n"DEBUG", s"[QueueMod] Attempting to queue quickhack: \(actionName)");

        // FIX: Validate critical objects first
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
        if !IsDefined(playerSystem) {
            LogChannel(n"DEBUG", "[QueueMod] PlayerSystem not available");
            return wrappedMethod();
        }

        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            LogChannel(n"DEBUG", "[QueueMod] Player not available");
            return wrappedMethod();
        }

        let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();
        if !IsDefined(queueHelper) {
            LogChannel(n"DEBUG", "[QueueMod] QueueHelper not available");
            return wrappedMethod();
        }

        // FIX: Handle PuppetAction properly (NPC quickhacks)
        let pa: ref<PuppetAction> = currentAction.m_action as PuppetAction;
        let saToQueue: ref<ScriptableDeviceAction> = null;
        let uniqueKey: String = "";
        
        if IsDefined(pa) {
            // PuppetActions ARE ScriptableDeviceActions in v1.63
            saToQueue = pa;
            if !IsDefined(saToQueue) {
                LogChannel(n"DEBUG", "[QueueMod][Queue] PuppetAction cannot cast to ScriptableDeviceAction");
                return wrappedMethod();
            }
            // Use PuppetAction for key generation
            let targetKey: String = ToString(pa.GetRequesterID());
            let actionIdStr: String = TDBID.ToStringDEBUG(saToQueue.GetObjectActionID());
            uniqueKey = s"\(targetKey)::\(actionIdStr)::\(GameInstance.GetTimeSystem(this.m_gameInstance).GetSimTime())";
        } else {
            // FIX: Handle pure ScriptableDeviceAction (devices)
            saToQueue = currentAction.m_action as ScriptableDeviceAction;
            if !IsDefined(saToQueue) {
                LogChannel(n"DEBUG", s"[QueueMod][Queue] Not a queueable action type (class=\(currentAction.m_action.GetClassName()))");
                return wrappedMethod();
            }
            uniqueKey = s"device::\(TDBID.ToStringDEBUG(saToQueue.GetObjectActionID()))::\(GameInstance.GetTimeSystem(this.m_gameInstance).GetSimTime())";
        }
        
        // Execute queue operation
        let wasQueued: Bool = queueHelper.PutInQuickHackQueueWithKey(saToQueue, uniqueKey);
        if wasQueued {
            let actionType: String = IsDefined(pa) ? "NPC" : "Device";
            LogChannel(n"DEBUG", s"[QueueMod] \(actionType) action successfully queued: \(actionName) key=\(uniqueKey)");
            this.ApplyQueueModCooldownWithData(currentAction);
            this.RefreshQueueModUI();
            return true; // Prevent immediate execution - action is queued
        } else {
            let actionType: String = IsDefined(pa) ? "NPC" : "Device";
            LogChannel(n"DEBUG", s"[QueueMod] Failed to queue \(actionType) action - executing normally");
        }
    }

    // Upload detection failed - store intent for later processing
    LogChannel(n"DEBUG", s"[QueueMod] Creating intent for target: \(ToString(currentAction.m_actionOwner)) action: \(actionName)");
    let intent: ref<QueueModIntent> = QueueModIntent.Create(
        currentAction.m_actionOwner,
        currentAction.m_action.GetObjectActionID(),
        actionName
    );
    
    // Store intent in global state for later consumption
    if GetQueueModGlobalState().AddIntent(intent) {
        LogChannel(n"DEBUG", s"[QueueMod] Stored intent: \(actionName) (upload detection lag)");
    }
    
    LogChannel(n"DEBUG", "[QueueMod] Executing action normally (with intent stored)");
    return wrappedMethod();
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
