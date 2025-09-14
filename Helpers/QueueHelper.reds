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

// UI Refresh Helper for v1.63
public class QuickhackQueueHelper {
    public static func RefreshQuickhackWheel(action: ref<ScriptableDeviceAction>) -> Void {
        let gameInstance: GameInstance;
        let targetID: EntityID;
        
        if !IsDefined(action) {
            QueueModLog(n"DEBUG", n"UI", "Cannot refresh - action is null");
            return;
        }
        
        // Get the game instance from the action
        gameInstance = GetGameInstance();
        // Note: GetGameInstance() always returns valid instance
        
        // Get the target entity ID (the device/NPC being hacked)
        targetID = action.GetRequesterID();
        if !EntityID.IsDefined(targetID) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Cannot refresh - target ID is invalid");
            return;
        }
        
        QueueModLog(n"DEBUG", n"UI", s"Refreshing UI for target: \(EntityID.ToDebugString(targetID))");
        
        // Use the force refresh bypass method
        QuickhackQueueHelper.ForceQuickhackUIRefresh(gameInstance, targetID);
    }

    // Phase 2: Create Bypass Method - Force UI Refresh with Proper Sequencing
    public static func ForceQuickhackUIRefresh(gameInstance: GameInstance, targetID: EntityID) -> Void {
        // Note: GameInstance parameter is always valid in this context
        
        if !EntityID.IsDefined(targetID) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Cannot force refresh - target ID is invalid");
            return;
        }
        
        QueueModLog(n"DEBUG", n"UI", s"ForceQuickhackUIRefresh called for target: \(EntityID.ToDebugString(targetID))");
        
        // Try vanilla method first (fast path)
        QuickhackModule.RequestRefreshQuickhackMenu(gameInstance, targetID);
        
        // ✅ CRITICAL FIX: Use proper delay event sequencing for v1.63 async processing
        QuickhackQueueHelper.ScheduleSequencedRefresh(gameInstance, targetID);
        
        QueueModLog(n"DEBUG", n"UI", "Force refresh scheduled with proper sequencing");
    }

    // ✅ CRITICAL FIX: Proper Delay Event Sequencing for v1.63
    public static func ScheduleSequencedRefresh(gameInstance: GameInstance, targetID: EntityID) -> Void {
        // Note: GameInstance parameter is always valid in this context
        
        if !EntityID.IsDefined(targetID) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Cannot schedule refresh - target ID is invalid");
            return;
        }
        
        let delaySystem: ref<DelaySystem> = GameInstance.GetDelaySystem(gameInstance);
        if !IsDefined(delaySystem) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Cannot schedule refresh - DelaySystem is null");
            return;
        }
        
        let timeSystem: ref<TimeSystem> = GameInstance.GetTimeSystem(gameInstance);
        if !IsDefined(timeSystem) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Cannot schedule refresh - TimeSystem is null");
            return;
        }
        
        QueueModLog(n"DEBUG", n"UI", s"Scheduling sequenced refresh for: \(EntityID.ToDebugString(targetID))");
        
        // Step 1: Schedule command generation with injection (0.05s delay)
        let genEvent: ref<QueueModCommandGenEvent> = new QueueModCommandGenEvent();
        genEvent.targetID = targetID;
        genEvent.timestamp = timeSystem.GetGameTimeStamp();
        delaySystem.DelayEvent(null, genEvent, 0.05);
        
        // Step 2: Schedule cache clearing with repopulation (0.1s delay)
        let cacheEvent: ref<QueueModCacheEvent> = new QueueModCacheEvent();
        cacheEvent.targetID = targetID;
        cacheEvent.timestamp = timeSystem.GetGameTimeStamp();
        delaySystem.DelayEvent(null, cacheEvent, 0.1);
        
        // Step 3: Schedule fallback validation (0.2s delay)
        let validationEvent: ref<QueueModValidationEvent> = new QueueModValidationEvent();
        validationEvent.targetID = targetID;
        validationEvent.timestamp = timeSystem.GetGameTimeStamp();
        delaySystem.DelayEvent(null, validationEvent, 0.2);
        
        QueueModLog(n"DEBUG", n"UI", "Sequenced refresh scheduled: Gen(0.05s) -> Cache(0.1s) -> Validation(0.2s)");
    }

    // Phase 3: Force Fresh Command Generation with Proper Injection
    public static func ForceFreshCommandGeneration(gameInstance: GameInstance, targetID: EntityID) -> Void {
        QueueModLog(n"DEBUG", n"UI", s"[QueueMod] ForceFreshCommandGeneration called for: \(EntityID.ToDebugString(targetID))");
        
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;
        if !IsDefined(targetObject) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Target not found for fresh command generation");
            return;
        }
        
        // Check if it's a ScriptedPuppet (NPC)
        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if IsDefined(puppet) {
            QueueModLog(n"DEBUG", n"UI", "Forcing fresh puppet commands with injection");
            // Force fresh puppet commands
            let actions: array<ref<PuppetAction>>;
            let commands: array<ref<QuickhackData>>;
            puppet.TranslateChoicesIntoQuickSlotCommands(actions, commands);
            QueueModLog(n"DEBUG", n"UI", s"Generated \(ArraySize(commands)) fresh puppet commands");
            
            // ✅ CRITICAL FIX: Inject commands via RevealInteractionWheel event
            QuickhackQueueHelper.InjectCommandsViaEvent(gameInstance, targetObject, commands);
            return;
        }
        
        // Check if it's a Device
        let device: ref<Device> = targetObject as Device;
        if IsDefined(device) {
            QueueModLog(n"DEBUG", n"UI", "Forcing fresh device commands with injection");
            // Force fresh device commands
            let actions: array<ref<DeviceAction>>;
            let context: GetActionsContext;
            device.GetDevicePS().GetQuickHackActions(actions, context);
            QueueModLog(n"DEBUG", n"UI", s"Generated \(ArraySize(actions)) fresh device commands");
            
            // ✅ CRITICAL FIX: Convert device actions to quickhack commands and inject
            let commands: array<ref<QuickhackData>>;
            QuickhackQueueHelper.ConvertDeviceActionsToCommands(actions, commands);
            QuickhackQueueHelper.InjectCommandsViaEvent(gameInstance, targetObject, commands);
            return;
        }
        
        QueueModLog(n"ERROR", n"UI", s"[QueueMod] Unknown target type: \(ToString(targetObject.GetClassName()))");
    }

    // Critical Missing Piece: Proper Command Injection
    public static func InjectCommandsViaEvent(gameInstance: GameInstance, targetObject: ref<GameObject>, commands: array<ref<QuickhackData>>) -> Void {
        QueueModLog(n"DEBUG", n"UI", s"[QueueMod] Injecting \(ArraySize(commands)) commands via RevealInteractionWheel event");
        
        // Create RevealInteractionWheel event with fresh commands
        let revealEvent: ref<RevealInteractionWheel> = new RevealInteractionWheel();
        revealEvent.commands = commands;  // Use the generated commands
        revealEvent.shouldReveal = true;
        revealEvent.lookAtObject = targetObject;
        
        // Queue the event to inject fresh commands into UI system
        GameInstance.GetUISystem(gameInstance).QueueEvent(revealEvent);
        
        QueueModLog(n"DEBUG", n"UI", "Commands injected successfully via RevealInteractionWheel event");
    }

    // Helper: Convert Device Actions to Quickhack Commands
    public static func ConvertDeviceActionsToCommands(actions: array<ref<DeviceAction>>, out commands: array<ref<QuickhackData>>) -> Void {
        QueueModLog(n"DEBUG", n"UI", s"Converting \(ArraySize(actions)) device actions to quickhack commands");
        
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
                    QueueModLog(n"DEBUG", n"UI", s"[QueueMod] Converted ScriptableDeviceAction: \(TDBID.ToStringDEBUG(sa.GetObjectActionID()))");
                } else {
                    // Fallback for other device action types
                    quickhackData.m_cost = 0;
                    quickhackData.m_title = "Unknown"; // Use String literal
                    quickhackData.m_type = gamedataObjectActionType.MinigameUpload; // Use available enum type
                    QueueModLog(n"DEBUG", n"UI", s"[QueueMod] Converted unknown device action type: \(action.GetClassName())");
                }
                
                ArrayPush(commands, quickhackData);
            }
            i += 1;
        }
        
        QueueModLog(n"DEBUG", n"UI", s"[QueueMod] Converted \(ArraySize(commands)) device actions to commands");
    }

    // Phase 4: Clear Controller Cache
    public static func ClearControllerCache(gameInstance: GameInstance, targetID: EntityID) -> Void {
        QueueModLog(n"DEBUG", n"UI", s"[QueueMod] ClearControllerCache called for: \(EntityID.ToDebugString(targetID))");
        
        // Get the player and controller
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Player not found for cache clearing");
            return;
        }
        
        let controller: ref<QuickhacksListGameController> = player.GetQuickhacksListGameController();
        if !IsDefined(controller) {
            QueueModLog(n"ERROR", n"UI", "[QueueMod] Controller not found for cache clearing");
            return;
        }
        
        // Clear controller cache using the new method
        controller.ClearControllerCacheInternal();
        QueueModLog(n"DEBUG", n"UI", "Controller cache cleared");
    }
}

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

        // Otherwise, fall back to ScriptableDeviceAction (devices, terminals, etc.)
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Queue] Route: Action's internal queue, actionType=\(action.GetClassName())");
            return sa.QueueModQuickHack(action);
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
                    
                    // ✅ ADD THIS: Force refresh UI after queuing
                    if wasQueued {
                        QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing queued hack via NPC queue (RAM deducted, queued for execution)");
                        QuickhackQueueHelper.ForceQuickhackUIRefresh(gameInstance, targetID);
                        QueueModLog(n"DEBUG", n"UI", "Action queued, UI force refreshed");
                    }
                    
                    return wasQueued;
                }
            }
            QueueModLog(n"DEBUG", n"QUEUE", "Puppet has no queue");
            return false;
        }

        // ScriptableDeviceAction with key support
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let queue: ref<QueueModActionQueue> = sa.GetQueueModActionQueue();
            if IsDefined(queue) {
                // FIX: Handle validation failure properly
                if !queue.ValidateQueueIntegrity() {
                    QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Queue validation failed - aborting queue operation");
                    return false; // Don't proceed with corrupted queue
                }
                QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod][Queue] EnqueueWithKey: Action queue key=\(key)");
                let wasQueued: Bool = queue.PutActionInQueueWithKey(action, key);
                if wasQueued {
                    QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing queued hack via device queue (RAM deducted, queued for execution)");
                }
                return wasQueued;
            }
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
