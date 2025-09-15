// =============================================================================
// HackQueueMod - Core Queue System (Consolidated)
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Core
import JE_HackQueueMod.Logging.*

// =============================================================================
// EVENT CLASSES FOR QUEUE MANAGEMENT
// =============================================================================

// Queue Event for State Synchronization (moved from QueueHelper)
public class QueueModEvent extends Event {
    public let eventType: CName;
    public let quickhackData: ref<QuickhackData>;
    public let timestamp: Float;
}

// =============================================================================
// CORE QUEUE DATA STRUCTURES
// =============================================================================

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

// =============================================================================
// HELPER CLASSES FOR QUEUE MANAGEMENT (moved from QueueHelper)
// =============================================================================

// Core helper with v1.63-compatible patterns
public class QueueModHelper {

    public func PutInQuickHackQueueWithKey(action: ref<DeviceAction>, key: String) -> Bool {
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] *** QUEUE SYSTEM WITH KEY ACTIVATED *** key=\(key)");
        if !IsDefined(action) {
            QueueModLog(n"DEBUG", n"QUEUE", "No action provided to queue");
            return false;
        }

        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Attempting to queue action: \(action.GetClassName()) with key=\(key)");

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
                        QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Queue validation failed - aborting queue operation");
                        return false; // Don't proceed with corrupted queue
                    }
                    QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Queue] EnqueueWithKey: NPC=\(GetLocalizedText(puppet.GetDisplayName())) key=\(key)");
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
        // Base queue size - TODO: implement dynamic sizing based on perks/cyberware
        return 3;
    }

    public func PutActionInQueueWithKey(action: ref<DeviceAction>, key: String) -> Bool {
        // CRITICAL: Comprehensive null and validation checks
        if !IsDefined(action) {
            QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Cannot queue null action");
            return false;
        }
        
        if Equals(key, "") {
            QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Cannot queue action with null or empty key");
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
        
        // Check for duplicates
        let i: Int32 = 0;
        let maxIterations: Int32 = 100;
        while i < ArraySize(this.m_queueEntries) && i < maxIterations {
            if IsDefined(this.m_queueEntries[i]) && Equals(this.m_queueEntries[i].fingerprint, key) {
                QueueModLog(n"DEBUG", n"QUEUE", s"Duplicate key rejected: \(key)");
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
            QueueModLog(n"DEBUG", n"RAM", s"[QueueMod] Calculated RAM cost from ScriptableDeviceAction: \(ramCost)");
        } else if IsDefined(pa) {
            // PuppetActions might have costs too
            ramCost = pa.GetCost();
            QueueModLog(n"DEBUG", n"RAM", s"[QueueMod] Calculated RAM cost from PuppetAction: \(ramCost)");
        } else {
            QueueModLog(n"DEBUG", n"RAM", s"[QueueMod] Unknown action type for RAM cost calculation: \(action.GetClassName())");
        }
        
        let entry: ref<QueueModEntry> = CreateQueueModEntry(action, key, ramCost);
        if !IsDefined(entry) {
            QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Failed to create queue entry");
            return false;
        }
        
        // CRITICAL: Validate action identity before queuing
        let actionID: TweakDBID = TDBID.None();
        if IsDefined(sa) {
            actionID = sa.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Queuing ScriptableDeviceAction: \(TDBID.ToStringDEBUG(actionID))");
        } else if IsDefined(pa) {
            actionID = pa.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Queuing PuppetAction: \(TDBID.ToStringDEBUG(actionID))");
        }
        
        if !TDBID.IsValid(actionID) {
            QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Action has invalid TweakDBID - cannot queue");
            return false;
        }
        
        // PHASE 3: RAM already deducted on selection (like vanilla behavior)
        // No need to validate or deduct RAM again during queuing
        QueueModLog(n"DEBUG", n"RAM", s"[QueueMod] RAM already deducted on selection: \(ramCost)");
        
        ArrayPush(this.m_queueEntries, entry);
        QueueModLog(n"DEBUG", n"QUEUE", s"Entry added atomically: \(key), actionID=\(TDBID.ToStringDEBUG(actionID)), size=\(ArraySize(this.m_queueEntries))");
        return true;
    }

    public func PopNextEntry() -> ref<QueueModEntry> {
        if ArraySize(this.m_queueEntries) == 0 {
            return null;
        }
        
        let entry: ref<QueueModEntry> = this.m_queueEntries[0];
        if !IsDefined(entry) {
            QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Null entry detected - clearing queue for safety");
            this.ClearQueue();
            return null;
        }
        
        ArrayErase(this.m_queueEntries, 0);
        QueueModLog(n"DEBUG", n"QUEUE", s"Entry popped: type=\(entry.entryType) fingerprint=\(entry.fingerprint)");
        return entry;
    }

    public func GetQueueSize() -> Int32 {
        return ArraySize(this.m_queueEntries);
    }

    public func ClearQueue() -> Void {
        // Refund RAM for all queued actions before clearing
        let i: Int32 = 0;
        let queueSize: Int32 = ArraySize(this.m_queueEntries);
        
        // Get player context for RAM refunds (following modding examples)
        let player: ref<PlayerPuppet> = this.QM_GetPlayer(GetGameInstance());
        if IsDefined(player) {
            let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(player.GetGame());
            let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
            
            while i < queueSize {
                let entry: ref<QueueModEntry> = this.m_queueEntries[i];
                if IsDefined(entry) && Equals(entry.entryType, 0) && entry.ramCost > 0 {
                    // Use tracked RAM cost instead of recalculating
                    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, Cast<Float>(entry.ramCost), player, false);
                    QueueModLog(n"DEBUG", n"RAM", s"[QueueMod] Refunded RAM: \(entry.ramCost)");
                }
                i += 1;
            }
        }
        
        ArrayClear(this.m_queueEntries);
        QueueModLog(n"DEBUG", n"QUEUE", s"Queue cleared - RAM refunded for \(queueSize) entries");
    }

    public func ClearQueue(gameInstance: GameInstance, targetID: EntityID) -> Void {
        this.ClearQueue(); // Call the base clear method
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
                QueueModLog(n"ERROR", n"QUEUE", s"[QueueMod] Null entry at index \(i)");
                cleanupNeeded = true;
                isValid = false;
            } else if Equals(entry.entryType, 0) && !IsDefined(entry.action) {
                QueueModLog(n"ERROR", n"QUEUE", s"[QueueMod] Invalid action at index \(i): \(entry.fingerprint)");
                cleanupNeeded = true;
                isValid = false;
            }
            i += 1;
        }
        
        // PHASE 4B: Immediate recovery (v1.63 pattern)
        if cleanupNeeded {
            QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Queue corruption detected - executing emergency cleanup");
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
        
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Emergency cleanup complete - \(ArraySize(this.m_queueEntries)) entries recovered");
    }
    
    // RAM Helper Methods with comprehensive null checks
    private func QM_GetPlayer(game: GameInstance) -> ref<PlayerPuppet> {
        // Note: GameInstance parameter is always valid in this context
        
        let ps: ref<PlayerSystem> = GameInstance.GetPlayerSystem(game);
        if !IsDefined(ps) {
            QueueModLog(n"ERROR", n"RAM", "[QueueMod] Cannot get player - PlayerSystem is null");
            return null;
        }
        
        let player: ref<PlayerPuppet> = ps.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            QueueModLog(n"ERROR", n"RAM", "[QueueMod] Cannot get player - LocalPlayerMainGameObject is null");
            return null;
        }
        
        return player;
    }
    
    private func QM_GetRamCostFromAction(action: ref<ScriptableDeviceAction>) -> Int32 {
        if !IsDefined(action) {
            QueueModLog(n"WARN", n"RAM", "[QueueMod] Cannot get RAM cost - action is null");
            return 0;
        }
        
        let cost: Int32 = action.GetCost();
        return Max(cost, 0); // Safe fallback
    }
}