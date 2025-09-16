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
// COST OVERRIDE SYSTEM FOR QUEUED ACTIONS
// =============================================================================

@addField(BaseScriptableAction)
private let m_queueModCostOverride: Bool;

@addMethod(BaseScriptableAction)
public func QueueMod_SetCostOverride(override: Bool) -> Void {
    this.m_queueModCostOverride = override;
}

@wrapMethod(BaseScriptableAction)
public func GetCost() -> Int32 {
    // If this action is marked as queued, return 0 cost to prevent double deduction
    if this.m_queueModCostOverride {
        return 0;
    }
    
    // Otherwise use vanilla cost calculation
    return wrappedMethod();
}


// =============================================================================
// Cooldown Detection and Management
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

// =============================================================================
// Core ApplyQuickHack Integration
// =============================================================================

@wrapMethod(QuickhacksListGameController)
private func ApplyQuickHack() -> Bool {
    QueueModLog(n"DEBUG", n"QUICKHACK", "ApplyQuickHack called");

    if !IsDefined(this.m_selectedData) {
        QueueModLog(n"DEBUG", n"QUICKHACK", "No selectedData - executing normally");
        return wrappedMethod();
    }

    let actionName: String = GetLocalizedText(this.m_selectedData.m_title);
    let targetID: EntityID = this.m_selectedData.m_actionOwner;
    
    // Validate all required data before processing
    if Equals(actionName, "") {
        QueueModLog(n"ERROR", n"QUICKHACK", "Invalid action name - executing normally");
        return wrappedMethod();
    }
    
    if !EntityID.IsDefined(targetID) {
        QueueModLog(n"ERROR", n"QUICKHACK", "Invalid target ID - executing normally");
        return wrappedMethod();
    }
    
    QueueModLog(n"DEBUG", n"QUICKHACK", s"Processing: \(actionName) target: \(ToString(targetID))");

    // Check cooldown using the selectedData directly
    if this.QueueModIsOnCooldown(this.m_selectedData) {
        QueueModLog(n"DEBUG", n"QUICKHACK", s"On cooldown: \(actionName)");
        return wrappedMethod();
    }

    // Check if we should queue FIRST, before touching RAM
    let shouldQueue: Bool = this.QueueMod_IsTargetUploading();
    QueueModLog(n"DEBUG", n"QUEUE", s"Should queue: \(shouldQueue)");

    if shouldQueue {

        // Validate we have necessary systems for queuing
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    
        // Check RAM availability
        if this.m_selectedData.m_cost > 0 {
            let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);            
            let freeRamFloat: Float = sps.GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Memory, false);
            let freeRamInt: Int32 = Cast<Int32>(freeRamFloat);
            let costFloat: Float = Cast<Float>(this.m_selectedData.m_cost);
            let costInt: Int32 = this.m_selectedData.m_cost;
            
            // Always log these values
            QueueModLog(n"DEBUG", n"RAM", s"RAM Check: Cost=\(costInt) (\(costFloat)), Available=\(freeRamInt) (\(freeRamFloat))");
            
            if costFloat > freeRamFloat {
                QueueModLog(n"ERROR", n"RAM", s"Insufficient RAM for \(actionName): \(costInt) > \(freeRamInt) - executing normally");
                return wrappedMethod();
            }
        }

        // Always log the final values here too, outside the cost check
        let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);            
        let freeRamFloat: Float = sps.GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Memory, false);
        let freeRamInt: Int32 = Cast<Int32>(freeRamFloat);
        let costFloat: Float = Cast<Float>(this.m_selectedData.m_cost);
        let costInt: Int32 = this.m_selectedData.m_cost;
        QueueModLog(n"DEBUG", n"RAM", s"Final RAM state: Cost=\(costInt) (\(costFloat)), Available=\(freeRamInt) (\(freeRamFloat))");

        // Try to use the original action first, fallback to reconstruction
        let actionToQueue: ref<DeviceAction> = null;
        
        // DEBUG: Check action availability
        QueueModLog(n"DEBUG", n"QUEUE", s"Action check: IsDefined(m_selectedData.m_action)=\(IsDefined(this.m_selectedData.m_action))");
        
        // Check if we have a valid action reference
        if IsDefined(this.m_selectedData.m_action) {
            actionToQueue = this.m_selectedData.m_action;
            QueueModLog(n"DEBUG", n"QUEUE", s"Using original action: \(actionToQueue.GetClassName())");
        } else {
            QueueModLog(n"ERROR", n"QUEUE", "No action reference - falling back to vanilla");
            return wrappedMethod();
        }
        
        if IsDefined(actionToQueue) {
            let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();          
            let timeSystem: ref<TimeSystem> = GameInstance.GetTimeSystem(this.m_gameInstance);          
            let uniqueKey: String = s"\(ToString(targetID))::\(actionName)::\(timeSystem.GetSimTime())";          
            
            QueueModLog(n"DEBUG", n"QUEUE", s"Attempting to queue with key: \(uniqueKey)");
            let wasQueued: Bool = queueHelper.PutInQuickHackQueueWithKey(actionToQueue, uniqueKey);
            QueueModLog(n"DEBUG", n"QUEUE", s"Queue attempt result: \(wasQueued)");

            if wasQueued {        
                // IMMEDIATELY deduct RAM upon successful queuing to prevent race conditions
                QueueModLog(n"DEBUG", n"RAM", s"RAM deduction path: cost=\(this.m_selectedData.m_cost)");
                if this.m_selectedData.m_cost > 0 {
                    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);
                    let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
                    
                    // Log BEFORE deduction
                    let ramBefore: Float = sps.GetStatPoolValue(oid, gamedataStatPoolType.Memory, false);
                    let ramBeforeInt: Int32 = Cast<Int32>(ramBefore);
                    
                    let costToDeduct: Int32 = this.m_selectedData.m_cost;
                    let ramToDeduct: Float = -Cast<Float>(costToDeduct);
                    
                    QueueModLog(n"DEBUG", n"RAM", s"BEFORE: RAM=\(ramBeforeInt) (\(ramBefore)), Deducting=\(costToDeduct) (\(ramToDeduct))");
                    
                    // Perform deduction
                    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, ramToDeduct, player, true, false);
                    
                    // Log AFTER deduction (immediate check - may show timing issue)
                    let ramAfter: Float = sps.GetStatPoolValue(oid, gamedataStatPoolType.Memory, false);
                    let ramAfterInt: Int32 = Cast<Int32>(ramAfter);
                    let actualDeducted: Int32 = ramBeforeInt - ramAfterInt;
                    
                    QueueModLog(n"DEBUG", n"RAM", s"AFTER: RAM=\(ramAfterInt) (\(ramAfter)), ActualDeducted=\(actualDeducted)");
                    
                    if actualDeducted != costToDeduct {
                        QueueModLog(n"ERROR", n"RAM", s"MISMATCH: Expected=\(costToDeduct), Actual=\(actualDeducted), Difference=\(costToDeduct - actualDeducted)");
                    }
                } else {
                    QueueModLog(n"DEBUG", n"RAM", "Skipping RAM deduction - cost is 0");
                }
                
                this.ApplyQueueModCooldownWithData(this.m_selectedData);
                // Mark action as having cost override to prevent double deduction
                let scriptableAction: ref<BaseScriptableAction> = actionToQueue as BaseScriptableAction;
                if IsDefined(scriptableAction) {
                    scriptableAction.QueueMod_SetCostOverride(true);
                    QueueModLog(n"DEBUG", n"RAM", "Cost override set - ProcessRPGAction will see 0 cost");
                }
                QueueModLog(n"DEBUG", n"QUEUE", s"Queued action: \(actionName) class=\(actionToQueue.GetClassName())");
                
                // Fire QueueEvent for state synchronization
                this.QM_FireQueueEvent(n"ItemAdded", this.m_selectedData);
                return true;
            } else {
                QueueModLog(n"DEBUG", n"QUEUE", s"Failed to queue action: \(actionName) - RAM cost: \(this.m_selectedData.m_cost)");
                return false;
            }
        } else {
            QueueModLog(n"ERROR", n"QUEUE", s"Cannot queue - no valid action available");
            return false;
        }
    } else {
        // FIX 2: For non-queued hacks, execute normally - let vanilla handle everything
        QueueModLog(n"DEBUG", n"QUICKHACK", "Executing non-queued hack normally (vanilla handles all)");
        
        // Execute vanilla first
        let vanillaResult: Bool = wrappedMethod();
        
        // Only cache AND set tracking ID if vanilla execution succeeded
        if vanillaResult && IsDefined(this.m_selectedData.m_action) {
            let puppetAction: ref<PuppetAction> = this.m_selectedData.m_action as PuppetAction;
            if IsDefined(puppetAction) {
                let targetID: EntityID = this.m_selectedData.m_actionOwner;
                let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as ScriptedPuppet;
                if IsDefined(target) {
                    let actionID: TweakDBID = puppetAction.GetObjectActionID();
                    target.QueueMod_SetActiveVanillaUpload(actionID); // Set tracking ID
                    target.QueueMod_AddToCache(actionID);             // Add to cache
                    QueueModLog(n"DEBUG", n"CACHE", s"Cached and tracking vanilla upload: \(TDBID.ToStringDEBUG(actionID))");
                }
            }
        }
        
        return vanillaResult;
    }
    
    // This should never be reached since shouldQueue=true returns early above
    QueueModLog(n"ERROR", n"QUEUE", "Unexpected code path - shouldQueue was true but we didn't queue");
    return wrappedMethod();
}

@addMethod(QuickhacksListGameController)
private func QueueMod_IsTargetUploading() -> Bool {
    if !IsDefined(this.m_selectedData) || !EntityID.IsDefined(this.m_selectedData.m_actionOwner) {
        return false;
    }
    
    let targetID: EntityID = this.m_selectedData.m_actionOwner;
    let target: ref<ScriptedPuppet> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as ScriptedPuppet;
    
    if !IsDefined(target) {
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
    if !IsDefined(data) || data.m_cooldown <= 0.0 {
        return;
    }

    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;

    if IsDefined(player) && TDBID.IsValid(data.m_cooldownTweak) {
        StatusEffectHelper.ApplyStatusEffect(player, data.m_cooldownTweak);
        QueueModLog(n"DEBUG", n"QUICKHACK", s"Applied cooldown: \(data.m_cooldown)s");
        
        // Find and update the specific widget
        let i: Int32 = 0;
        while i < ArraySize(this.m_data) {
            if Equals(this.m_data[i].m_title, data.m_title) {
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