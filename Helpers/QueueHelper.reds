// =============================================================================
// HackQueueMod - Queue Helpers
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Helpers
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*
import JE_HackQueueMod.Events.*

// =============================================================================
// HELPER CLASSES FOR QUEUE MANAGEMENT
// =============================================================================



// Core helper with v1.63-compatible patterns
public class QueueModHelper {

    public func PutInQuickHackQueue(action: ref<DeviceAction>) -> Bool {
        QueueModLog(n"DEBUG", n"QUEUE", "*** QUEUE SYSTEM ACTIVATED ***");
        if !IsDefined(action) {
            QueueModLog(n"DEBUG", n"QUEUE", "No action provided to queue");
            return false;
        }

        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Attempting to queue action: \(action.GetClassName())");

        // Prefer PuppetAction (NPC) to ensure NPC queue receives the action
        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            let requesterID: EntityID = pa.GetRequesterID();
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Queue] Route: NPC queue, requesterID=\(ToString(requesterID))");
            return this.QueueActionOnPuppet(pa);
        }

        QueueModLog(n"DEBUG", n"QUEUE", "Unknown action type - cannot queue");
        return false;
    }

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

    public func QueueActionOnPuppet(puppetAction: ref<PuppetAction>) -> Bool {
        if !IsDefined(puppetAction) {
            return false;
        }

        let targetID: EntityID = puppetAction.GetRequesterID();
        let gameInstance: GameInstance = puppetAction.GetExecutor().GetGame();
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;

        if !IsDefined(targetObject) {
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Queue] Abort: requester not found, requesterID=\(ToString(targetID))");
            return false;
        }

        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if !IsDefined(puppet) {
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Queue] Abort: requester not a ScriptedPuppet, requesterID=\(ToString(targetID))");
            return false;
        }

        let queue: ref<QueueModActionQueue> = puppet.GetQueueModActionQueue();
        if IsDefined(queue) {
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Queue] Enqueue: NPC=\(GetLocalizedText(puppet.GetDisplayName())) id=\(ToString(puppet.GetEntityID())) action=PuppetAction");
            // Generate a unique key for the action
            let uniqueKey: String = this.GenerateQueueKey(puppetAction);
            return queue.PutActionInQueueWithKey(puppetAction, uniqueKey);
        }

        QueueModLog(n"DEBUG", n"QUEUE", "Puppet has no queue");
        return false;
    }

    public func GetQueueSize(action: ref<DeviceAction>) -> Int32 {
        if !IsDefined(action) {
            return 0;
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
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][TargetResolution] PuppetAction target: \(ToString(targetID)) -> \(IsDefined(targetObject) ? ToString(targetObject.GetClassName()) : "null")");
            return targetObject;
        }

        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][TargetResolution] ScriptableDeviceAction - no direct target resolution needed");
            return null;
        }

        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][TargetResolution] Unknown action type: \(action.GetClassName())");
        return null;
    }

    public func ValidateQueueIntegrity(queue: ref<QueueModActionQueue>) -> Bool {
        if !IsDefined(queue) {
        return false;
    }

        let actionSize: Int32 = queue.GetQueueSize();
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Validation] Queue integrity check - Action count: \(actionSize)");
        
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
