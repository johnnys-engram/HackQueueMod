// =============================================================================
// HackQueueMod - UI Controllers
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.UI
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*

// =============================================================================
// CONSTANTS
// =============================================================================

// UI LocKey constants for better maintainability
public func GetUploadProgressKey() -> String { return "LocKey#43809"; }
public func GetUploadInProgressKey() -> String { return "LocKey#7020"; }
public func GetOutOfMemoryKey() -> String { return "LocKey#27398"; }
public func GetBlockedKey() -> String { return "LocKey#40765"; }
public func GetInvalidActionKey() -> String { return "LocKey#7019"; }

// =============================================================================
// ENHANCED COST OVERRIDE SYSTEM FOR QUEUED ACTIONS
// Target-specific cost override to prevent interference between multiple queues
// =============================================================================

@addField(BaseScriptableAction)
private let m_queueModCostOverrideTargets: array<EntityID>;

@addMethod(BaseScriptableAction)
public func QueueMod_SetCostOverrideForTarget(targetID: EntityID, override: Bool) -> Void {
    if (override) {
        // Add target to override list if not already present
        if (!ArrayContains(this.m_queueModCostOverrideTargets, targetID)) {
            ArrayPush(this.m_queueModCostOverrideTargets, targetID);
        }
    } else {
        // Remove target from override list
        ArrayRemove(this.m_queueModCostOverrideTargets, targetID);
    }
}

@addMethod(BaseScriptableAction)
public func QueueMod_HasCostOverrideForTarget(targetID: EntityID) -> Bool {
    return ArrayContains(this.m_queueModCostOverrideTargets, targetID);
}

@addMethod(BaseScriptableAction)
public func QueueMod_ClearCostOverrideForTarget(targetID: EntityID) -> Void {
    ArrayRemove(this.m_queueModCostOverrideTargets, targetID);
}

@wrapMethod(BaseScriptableAction)
public func GetCost() -> Int32 {
    // Check if this action has cost override for its target
    // Use the action's actual target (requester) for the override check
    let targetID: EntityID = this.GetRequesterID();
    if (EntityID.IsDefined(targetID) && this.QueueMod_HasCostOverrideForTarget(targetID)) {
        return 0;
    }
    
    // Otherwise use vanilla cost calculation
    return wrappedMethod();
}

// =============================================================================
// CLEANUP COST OVERRIDE AFTER ACTION EXECUTION
// =============================================================================

@wrapMethod(BaseScriptableAction)
public func ProcessRPGAction(gameInstance: GameInstance) -> Void {
    let targetID: EntityID = this.GetRequesterID();
    
    // Execute the action first
    wrappedMethod(gameInstance);
    
    // Clear cost override after execution to prevent interference
    if (EntityID.IsDefined(targetID)) {
        this.QueueMod_ClearCostOverrideForTarget(targetID);
    }
}

// =============================================================================
// Cooldown Detection and Management
// =============================================================================

@addMethod(QuickhacksListGameController)
private func QueueModIsOnCooldown(data: ref<QuickhackData>) -> Bool {
    if (!IsDefined(data) || data.m_cooldown <= 0.0 || !TDBID.IsValid(data.m_cooldownTweak)) {
        return false;
    }
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if (!IsDefined(player)) {
        return false;
    }
    return StatusEffectSystem.ObjectHasStatusEffect(player, data.m_cooldownTweak);
}

// =============================================================================
// Core ApplyQuickHack Integration - REFACTORED
// =============================================================================

@wrapMethod(QuickhacksListGameController)
private func ApplyQuickHack() -> Bool {
    QueueModLog(n"DEBUG", n"QUICKHACK", "ApplyQuickHack called");

    // Basic validation - respect vanilla locked state
    if (!IsDefined(this.m_selectedData) || this.m_selectedData.m_isLocked) {
        QueueModLog(n"DEBUG", n"QUICKHACK", "Action locked or invalid - skipping");
        return false;
    }

    // Check if we should queue
    let shouldQueue: Bool = this.QueueMod_IsTargetUploading();
    QueueModLog(n"DEBUG", n"QUEUE", s"Should queue: \(shouldQueue)");

    if (shouldQueue) {
        return this.QueueMod_HandleQueuedExecution();
    } else {
        // Execute vanilla and handle caching
        QueueModLog(n"DEBUG", n"QUICKHACK", "Executing vanilla");
        let vanillaResult: Bool = wrappedMethod();
        
        // Cache tracking for vanilla uploads
        if (vanillaResult && IsDefined(this.m_selectedData.m_action)) {
            let puppetAction: ref<PuppetAction> = this.m_selectedData.m_action as PuppetAction;
            if (IsDefined(puppetAction)) {
                let targetID: EntityID = this.m_selectedData.m_actionOwner;
                let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as ScriptedPuppet;
                if (IsDefined(target)) {
                    let actionID: TweakDBID = puppetAction.GetObjectActionID();
                    target.QueueMod_SetActiveVanillaUpload(actionID);
                    target.QueueMod_AddToCache(actionID);
                    QueueModLog(n"DEBUG", n"CACHE", s"Cached vanilla upload: \(TDBID.ToStringDEBUG(actionID))");
                }
            }
        }
        
        return vanillaResult;
    }
}

@addMethod(QuickhacksListGameController)
private func QueueMod_HandleQueuedExecution() -> Bool {
    let actionName: String = GetLocalizedText(this.m_selectedData.m_title);
    let targetID: EntityID = this.m_selectedData.m_actionOwner;
    let actionToQueue: ref<DeviceAction> = this.m_selectedData.m_action;
    
    QueueModLog(n"DEBUG", n"QUICKHACK", s"Queuing: \(actionName)");

    // Get live cost from action (includes all game reductions)
    let scriptableAction: ref<BaseScriptableAction> = actionToQueue as BaseScriptableAction;
    let liveCost: Int32;
    if (IsDefined(scriptableAction)) {
        liveCost = scriptableAction.GetCost();
    } else {
        liveCost = this.m_selectedData.m_cost;
    }
    
    QueueModLog(n"DEBUG", n"RAM", s"Live cost: \(liveCost), UI cost: \(this.m_selectedData.m_cost)");

    // Check if we can afford it
    let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.m_gameInstance).GetLocalPlayerMainGameObject() as PlayerPuppet;

    // Set target-specific cost override BEFORE any operations
    if (IsDefined(scriptableAction)) {
        scriptableAction.QueueMod_SetCostOverrideForTarget(targetID, true);
    }

    // Try to queue
    let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();
    let uniqueKey: String = s"\(ToString(targetID))::\(actionName)::\(GameInstance.GetTimeSystem(this.m_gameInstance).GetSimTime())";
    let wasQueued: Bool = queueHelper.PutInQuickHackQueueWithKey(actionToQueue, uniqueKey);

    if (wasQueued) {
        // Deduct RAM and apply effects
        this.QueueMod_DeductRAM(player, liveCost);
        this.ApplyQueueModCooldownWithData(this.m_selectedData);
        this.QM_FireQueueEvent(n"ItemAdded", this.m_selectedData);
        
        QueueModLog(n"DEBUG", n"QUEUE", s"Successfully queued: \(actionName) for target: \(ToString(targetID))");
        return true;
    } else {
        // Failed to queue - clear target-specific override
        if (IsDefined(scriptableAction)) {
            scriptableAction.QueueMod_ClearCostOverrideForTarget(targetID);
        }
        QueueModLog(n"ERROR", n"QUEUE", s"Failed to queue: \(actionName)");
        return false;
    }
}

@addMethod(QuickhacksListGameController)
private func QueueMod_CanAffordCost(player: ref<PlayerPuppet>, cost: Int32) -> Bool {
    if (cost <= 0) {
        return true;
    }
    
    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);
    let availableRAM: Float = sps.GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Memory, false);
    
    return Cast<Float>(cost) <= availableRAM;
}

@addMethod(QuickhacksListGameController)
private func QueueMod_DeductRAM(player: ref<PlayerPuppet>, cost: Int32) -> Void {
    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);
    let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
    let beforeRAM: Float = sps.GetStatPoolValue(oid, gamedataStatPoolType.Memory, false);
    
    QueueModLog(n"DEBUG", n"RAM", s"=== RAM DEDUCTION DEBUG ===");
    QueueModLog(n"DEBUG", n"RAM", s"Input cost: \(cost)");
    QueueModLog(n"DEBUG", n"RAM", s"RAM before: \(beforeRAM)");
    
    if (cost <= 0) {
        QueueModLog(n"ERROR", n"RAM", s"INVALID COST: \(cost) - this would ADD RAM instead of subtract!");
        return;
    }
    
    let ramToDeduct: Float = -Cast<Float>(cost);
    QueueModLog(n"DEBUG", n"RAM", s"Calculated ramToDeduct: \(ramToDeduct)");
    
    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, ramToDeduct, player, true, false);
    
    let afterRAM: Float = sps.GetStatPoolValue(oid, gamedataStatPoolType.Memory, false);
    let actualChange: Float = afterRAM - beforeRAM;
    QueueModLog(n"DEBUG", n"RAM", s"RAM after: \(afterRAM)");
    QueueModLog(n"DEBUG", n"RAM", s"Actual change: \(actualChange)");
    QueueModLog(n"DEBUG", n"RAM", s"=== END RAM DEBUG ===");
}

@addMethod(QuickhacksListGameController)
private func QueueMod_IsTargetUploading() -> Bool {
    if (!IsDefined(this.m_selectedData) || !EntityID.IsDefined(this.m_selectedData.m_actionOwner)) {
        return false;
    }
    
    let targetID: EntityID = this.m_selectedData.m_actionOwner;
    let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as ScriptedPuppet;
    
    if (!IsDefined(target)) {
        return false;
    }
    
    // Same check as TranslateChoicesIntoQuickSlotCommands
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance)
        .IsStatPoolAdded(Cast<StatsObjectID>(target.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    
    return isOngoingUpload;
}

// Cooldown application for queued actions
@addMethod(QuickhacksListGameController)
private func ApplyQueueModCooldownWithData(data: ref<QuickhackData>) -> Void {
    if (!IsDefined(data) || data.m_cooldown <= 0.0) {
        return;
    }

    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;

    if (IsDefined(player) && TDBID.IsValid(data.m_cooldownTweak)) {
        StatusEffectHelper.ApplyStatusEffect(player, data.m_cooldownTweak);
        QueueModLog(n"DEBUG", n"QUICKHACK", s"Applied cooldown: \(data.m_cooldown)s");
        
        // Find and update the specific widget
        let i: Int32 = 0;
        while (i < ArraySize(this.m_data)) {
            if (Equals(this.m_data[i].m_title, data.m_title)) {
                // Update data
                this.m_data[i].m_isLocked = true;
                this.m_data[i].m_inactiveReason = GetBlockedKey();
                break;
            }
            i += 1;
        }
    }
}

@addMethod(QuickhacksListGameController)
private func QM_FireQueueEvent(eventType: CName, data: ref<QuickhackData>) -> Void {
    // Fire QueueEvent for state synchronization
    QueueModLog(n"DEBUG", n"EVENTS", s"Fired \(ToString(eventType)) for \(GetLocalizedText(data.m_title))");
    
    // Create and fire queue event for UI synchronization
    let queueEvent: ref<QueueModEvent> = new QueueModEvent();
    queueEvent.eventType = eventType;
    queueEvent.quickhackData = data;
    queueEvent.timestamp = GameInstance.GetTimeSystem(this.m_gameInstance).GetGameTimeStamp();
    
    // Fire the event to notify QueueStateSynchronizer
    GameInstance.GetUISystem(this.m_gameInstance).QueueEvent(queueEvent);
}