// =============================================================================
// HackQueueMod - Core Queue System (Consolidated)
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Core
import JE_HackQueueMod.Logging.*

// =============================================================================
// CONSTANTS
// =============================================================================

// Queue configuration
public func GetDefaultQueueSize() -> Int32 { return 3; }
public func GetActionEntryType() -> Int32 { return 0; }
public func GetMaxDuplicateCheckIterations() -> Int32 { return 50; }

// =============================================================================
// EVENT CLASSES FOR QUEUE MANAGEMENT
// =============================================================================

public class QueueModEvent extends Event {
    public let eventType: CName;
    public let quickhackData: ref<QuickhackData>;
    public let timestamp: Float;
}

// =============================================================================
// CORE QUEUE DATA STRUCTURES
// =============================================================================

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
    entry.entryType = GetActionEntryType();
    entry.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
    entry.ramCost = cost;
    return entry;
}

// =============================================================================
// HELPER CLASSES FOR QUEUE MANAGEMENT
// =============================================================================

public class QueueModHelper {

    public func PutInQuickHackQueueWithKey(action: ref<DeviceAction>, key: String) -> Bool {
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Queue system activated with key=\(key)");
        if !IsDefined(action) {
            QueueModLog(n"DEBUG", n"QUEUE", "No action provided to queue");
            return false;
        }

        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Attempting to queue action: \(action.GetClassName()) with key=\(key)");

        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            let targetID: EntityID = pa.GetRequesterID();
            let gameInstance: GameInstance = pa.GetExecutor().GetGame();
            let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;
            let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
            if IsDefined(puppet) {
                let queue: ref<QueueModActionQueue> = puppet.GetQueueModActionQueue();
                if IsDefined(queue) {
                    QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] EnqueueWithKey: NPC=\(GetLocalizedText(puppet.GetDisplayName())) key=\(key)");
                    let wasQueued: Bool = queue.PutActionInQueueWithKey(action, key);
                    return wasQueued;
                }
            }
            QueueModLog(n"DEBUG", n"QUEUE", "Puppet has no queue");
            return false;
        }

        QueueModLog(n"DEBUG", n"QUEUE", "Unknown action type - cannot queue");
        return false;
    }
}

// =============================================================================
// CORE QUEUE SYSTEM CLASSES
// =============================================================================

public class QueueModActionQueue {
    private let m_queueEntries: array<ref<QueueModEntry>>;
    private let m_isQueueLocked: Bool;
    private let m_maxQueueSize: Int32;
    
    public func Initialize() -> Void {
        this.m_isQueueLocked = false;
        this.m_maxQueueSize = this.CalculateMaxQueueSize();
    }
    
    private func CalculateMaxQueueSize() -> Int32 {
        // TODO: implement dynamic sizing based on perks/cyberware
        return GetDefaultQueueSize();
    }

    public func PutActionInQueueWithKey(action: ref<DeviceAction>, key: String) -> Bool {
        if !IsDefined(action) {
            QueueModLog(n"ERROR", n"QUEUE", "Cannot queue null action");
            return false;
        }
        
        if Equals(key, "") {
            QueueModLog(n"ERROR", n"QUEUE", "Cannot queue action with null or empty key");
            return false;
        }
        
        if this.m_isQueueLocked {
            QueueModLog(n"DEBUG", n"QUEUE", "Queue is locked - cannot add action");
            return false;
        }
        
        if ArraySize(this.m_queueEntries) >= this.m_maxQueueSize {
            QueueModLog(n"DEBUG", n"QUEUE", s"Queue full (size: \(ArraySize(this.m_queueEntries)), max: \(this.m_maxQueueSize))");
            return false;
        }
        
        // Check for duplicates with bounded iteration
        let i: Int32 = 0;
        let maxIterations: Int32 = GetMaxDuplicateCheckIterations();
        while i < ArraySize(this.m_queueEntries) && i < maxIterations {
            if IsDefined(this.m_queueEntries[i]) && Equals(this.m_queueEntries[i].fingerprint, key) {
                QueueModLog(n"DEBUG", n"QUEUE", s"Duplicate key rejected: \(key)");
                return false;
            }
            i += 1;
        }
        
        // Calculate RAM cost for tracking purposes only
        let ramCost: Int32 = 0;
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        let pa: ref<PuppetAction> = action as PuppetAction;
        
        if IsDefined(sa) {
            ramCost = sa.GetCost();
            QueueModLog(n"DEBUG", n"RAM", s"Calculated RAM cost from ScriptableDeviceAction: \(ramCost)");
        } else if IsDefined(pa) {
            ramCost = pa.GetCost();
            QueueModLog(n"DEBUG", n"RAM", s"Calculated RAM cost from PuppetAction: \(ramCost)");
        } else {
            QueueModLog(n"DEBUG", n"RAM", s"Unknown action type for RAM cost calculation: \(action.GetClassName())");
        }
        
        let entry: ref<QueueModEntry> = CreateQueueModEntry(action, key, ramCost);
        if !IsDefined(entry) {
            QueueModLog(n"ERROR", n"QUEUE", "Failed to create queue entry");
            return false;
        }
        
        // Validate action identity before queuing
        let actionID: TweakDBID = TDBID.None();
        if IsDefined(sa) {
            actionID = sa.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUEUE", s"Queuing ScriptableDeviceAction: \(TDBID.ToStringDEBUG(actionID))");
        } else if IsDefined(pa) {
            actionID = pa.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUEUE", s"Queuing PuppetAction: \(TDBID.ToStringDEBUG(actionID))");
        }
        
        if !TDBID.IsValid(actionID) {
            QueueModLog(n"ERROR", n"QUEUE", "Action has invalid TweakDBID - cannot queue");
            return false;
        }
        
        // Add to queue
        ArrayPush(this.m_queueEntries, entry);
        
        // MAINTAIN CACHE - Add to puppet's cache
        if IsDefined(pa) {
            let targetID: EntityID = pa.GetRequesterID();
            let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(GetGameInstance(), targetID) as ScriptedPuppet;
            if IsDefined(target) {
                target.QueueMod_AddToCache(actionID);
            }
        }
        
        QueueModLog(n"DEBUG", n"QUEUE", s"Entry added: \(key), actionID=\(TDBID.ToStringDEBUG(actionID)), size=\(ArraySize(this.m_queueEntries))");
        return true;
    }

    public func PopNextEntry() -> ref<QueueModEntry> {
        if ArraySize(this.m_queueEntries) == 0 {
            return null;
        }
        
        let entry: ref<QueueModEntry> = this.m_queueEntries[0];
        if !IsDefined(entry) {
            QueueModLog(n"ERROR", n"QUEUE", "Null entry detected - clearing queue for safety");
            this.ClearQueue();
            return null;
        }
        
        ArrayErase(this.m_queueEntries, 0);
        
        // MAINTAIN CACHE - Remove from puppet's cache
        if IsDefined(entry.action) {
            let pa: ref<PuppetAction> = entry.action as PuppetAction;
            if IsDefined(pa) {
                let actionID: TweakDBID = pa.GetObjectActionID();
                let targetID: EntityID = pa.GetRequesterID();
                let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(GetGameInstance(), targetID) as ScriptedPuppet;
                if IsDefined(target) && TDBID.IsValid(actionID) {
                    target.QueueMod_RemoveFromCache(actionID);
                }
            }
        }
        
        QueueModLog(n"DEBUG", n"QUEUE", s"Entry popped: type=\(entry.entryType) fingerprint=\(entry.fingerprint)");
        return entry;
    }

    public func GetQueueSize() -> Int32 {
        return ArraySize(this.m_queueEntries);
    }

    public func ClearQueue() -> Void {
        let queueSize: Int32 = ArraySize(this.m_queueEntries);
        
        // MAINTAIN CACHE - Clear puppet's cache if we have entries
        if ArraySize(this.m_queueEntries) > 0 && IsDefined(this.m_queueEntries[0]) && IsDefined(this.m_queueEntries[0].action) {
            let pa: ref<PuppetAction> = this.m_queueEntries[0].action as PuppetAction;
            if IsDefined(pa) {
                let targetID: EntityID = pa.GetRequesterID();
                let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(GetGameInstance(), targetID) as ScriptedPuppet;
                if IsDefined(target) {
                    target.QueueMod_ClearCache();
                }
            }
        }
        
        ArrayClear(this.m_queueEntries);
        QueueModLog(n"DEBUG", n"QUEUE", s"Queue cleared - \(queueSize) entries removed");
    }

    public func ClearQueue(gameInstance: GameInstance, targetID: EntityID) -> Void {
        // MAINTAIN CACHE - Clear specific puppet's cache  
        let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(gameInstance, targetID) as ScriptedPuppet;
        if IsDefined(target) {
            target.QueueMod_ClearCache();
        }
        
        this.ClearQueue();
    }

    public func LockQueue() -> Void {
        this.m_isQueueLocked = true;
    }

    public func UnlockQueue() -> Void {
        this.m_isQueueLocked = false;
    }

    public func ValidateQueueIntegrity() -> Bool {
        let isValid: Bool = true;
        let i: Int32 = 0;
        let cleanupNeeded: Bool = false;
        
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if !IsDefined(entry) {
                QueueModLog(n"ERROR", n"QUEUE", s"Null entry at index \(i)");
                cleanupNeeded = true;
                isValid = false;
            } else if Equals(entry.entryType, GetActionEntryType()) && !IsDefined(entry.action) {
                QueueModLog(n"ERROR", n"QUEUE", s"Invalid action at index \(i): \(entry.fingerprint)");
                cleanupNeeded = true;
                isValid = false;
            }
            i += 1;
        }
        
        if cleanupNeeded {
            QueueModLog(n"ERROR", n"QUEUE", "Queue corruption detected - executing emergency cleanup");
            this.EmergencyCleanup();
        }
        
        return isValid;
    }

    private func EmergencyCleanup() -> Void {
        let cleanEntries: array<ref<QueueModEntry>>;
        let i: Int32 = 0;
        
        while i < ArraySize(this.m_queueEntries) {
            let entry: ref<QueueModEntry> = this.m_queueEntries[i];
            if IsDefined(entry) {
                if Equals(entry.entryType, GetActionEntryType()) && IsDefined(entry.action) {
                    let sa: ref<ScriptableDeviceAction> = entry.action as ScriptableDeviceAction;
                    if IsDefined(sa) && TDBID.IsValid(sa.GetObjectActionID()) {
                        ArrayPush(cleanEntries, entry);
                    }
                }
            }
            i += 1;
        }
        
        ArrayClear(this.m_queueEntries);
        this.m_queueEntries = cleanEntries;
        
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Emergency cleanup complete - \(ArraySize(this.m_queueEntries)) entries recovered");
    }
}