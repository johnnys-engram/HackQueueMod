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
// QUICKHACKS LIST GAME CONTROLLER EXTENSIONS
// =============================================================================

@addMethod(QuickhacksListGameController)
private func IsQuickHackCurrentlyUploading() -> Bool {
    // Rule 1: Selected row UI lock (fastest path)
    if this.QueueModSelectedIsUILocked() {
        QueueModLog(n"DEBUG", n"EVENTS", "Selected row UI lock indicates upload in progress");
        return true;
    }

    // Rule 1b: Generic lock check for unknown reasons
    if IsDefined(this.m_selectedData) && this.m_selectedData.m_isLocked && 
       NotEquals(this.m_selectedData.m_actionState, EActionInactivityReson.Ready) {
        QueueModLog(n"DEBUG", n"EVENTS", "Selected item locked with unknown reason - treating as upload");
        return true;
    }

    // Rule 1c: Full UI lock scan (fallback for timing races)
    if this.QueueModDetectUILock() {
        QueueModLog(n"DEBUG", n"EVENTS", "Target indicates upload in progress");
        return true;
    }

    // Rule 2: Target check (only if NPC - devices skip pool)
    if IsDefined(this.m_selectedData) {
        let targetID: EntityID = this.m_selectedData.m_actionOwner;
        if EntityID.IsDefined(targetID) {
            let target: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as GameObject;
            if IsDefined(target) {
                QueueModLog(n"DEBUG", n"EVENTS", s"Target class: \(ToString(target.GetClassName()))");
                
                let puppet: ref<ScriptedPuppet> = target as ScriptedPuppet;
                if IsDefined(puppet) {
                    // Only check StatPool for NPCs (ScriptedPuppets)
                    let uploading: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance)
                        .IsStatPoolAdded(Cast<StatsObjectID>(puppet.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
                    QueueModLog(n"DEBUG", n"EVENTS", s"NPC upload pool: \(uploading)");
                    return uploading;
                } else {
                    // Device detected - rely only on UI lock (already checked above)
                    QueueModLog(n"DEBUG", n"EVENTS", "Device target - UI lock only");
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
        QueueModLog(n"DEBUG", n"EVENTS", s"Player upload pool (fallback): \(hasUploadPool)");
        return hasUploadPool;
    }

    return false;
}

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
    return Equals(r, GetOutOfMemoryKey()) || Equals(r, GetBlockedKey()) || Equals(r, GetUploadInProgressKey()) || Equals(r, GetInvalidActionKey());
}

@addMethod(QuickhacksListGameController)
private func QueueModDetectUILock() -> Bool {
    let i: Int32 = 0;
    while i < ArraySize(this.m_data) {
        let entry: ref<QuickhackData> = this.m_data[i];
        if IsDefined(entry) && entry.m_isLocked && 
           (Equals(ToString(entry.m_inactiveReason), GetUploadProgressKey()) ||
            Equals(ToString(entry.m_inactiveReason), GetUploadInProgressKey())) {
            return true;
        }
        i += 1;
    }
    return false;
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
    let shouldQueue: Bool = this.IsQuickHackCurrentlyUploading();
    QueueModLog(n"DEBUG", n"QUEUE", s"Should queue: \(shouldQueue)");

    if shouldQueue {

        // Validate we have necessary systems for queuing
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    
        // Check RAM availability
        if this.m_selectedData.m_cost > 0 {
            let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);            
            let freeRam: Float = sps.GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Memory, false);
            if Cast<Float>(this.m_selectedData.m_cost) > freeRam {
                QueueModLog(n"ERROR", n"RAM", s"Insufficient RAM for \(actionName): \(this.m_selectedData.m_cost) > \(freeRam) - executing normally");
                return wrappedMethod();
            }
        }

        // Try to use the original action first, fallback to reconstruction
        let actionToQueue: ref<DeviceAction> = null;
        
        // Check if we have a valid action reference
        if IsDefined(this.m_selectedData.m_action) {
            actionToQueue = this.m_selectedData.m_action;
            QueueModLog(n"DEBUG", n"QUEUE", s"Using original action: \(actionToQueue.GetClassName())");
        } else {
            // Fallback to reconstruction only if no action reference
            actionToQueue = this.ReconstructActionFromData(this.m_selectedData);
            QueueModLog(n"DEBUG", n"QUEUE", s"Reconstructed action from metadata: \(GetLocalizedText(this.m_selectedData.m_title))");
        }
        
        if IsDefined(actionToQueue) {
            let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();          
            let timeSystem: ref<TimeSystem> = GameInstance.GetTimeSystem(this.m_gameInstance);          
            let uniqueKey: String = s"\(ToString(targetID))::\(actionName)::\(timeSystem.GetSimTime())";          
            let wasQueued: Bool = queueHelper.PutInQuickHackQueueWithKey(actionToQueue, uniqueKey);

            if wasQueued {        
                // IMMEDIATELY deduct RAM upon successful queuing to prevent race conditions
                if this.m_selectedData.m_cost > 0 {
                    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);
                    let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
                    let ramToDeduct: Float = -Cast<Float>(this.m_selectedData.m_cost);
                    
                    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, ramToDeduct, player, true, false);
                    QueueModLog(n"DEBUG", n"RAM", s"Deducted RAM immediately upon queuing: \(this.m_selectedData.m_cost)");
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
                QueueModLog(n"ERROR", n"QUEUE", s"Failed to queue action: \(actionName)");
                return false;
            }
        } else {
            QueueModLog(n"ERROR", n"QUEUE", s"Cannot queue - no valid action available");
            return false;
        }
    } else {
        // For non-queued hacks, execute normally - let vanilla handle everything
        QueueModLog(n"DEBUG", n"QUICKHACK", "Executing non-queued hack normally (vanilla handles all)");
        return wrappedMethod();
    }
    
    // This should never be reached since shouldQueue=true returns early above
    QueueModLog(n"ERROR", n"QUEUE", "Unexpected code path - shouldQueue was true but we didn't queue");
    return wrappedMethod();
}

// =============================================================================
// Action Reconstruction Methods
// =============================================================================

@addMethod(QuickhacksListGameController)
private func ReconstructActionFromData(data: ref<QuickhackData>) -> ref<PuppetAction> {
    if !IsDefined(data) || !EntityID.IsDefined(data.m_actionOwner) {
        return null;
    }

    // Find the TweakDBID from the UI data
    let actionTweakID: TweakDBID = this.FindActionTweakID(data);
    if !TDBID.IsValid(actionTweakID) {
        QueueModLog(n"DEBUG", n"QUEUE", s"Cannot find TweakDBID for: \(GetLocalizedText(data.m_title))");
        return null;
    }

    // Create fresh PuppetAction
    let puppetAction: ref<PuppetAction> = new PuppetAction();
    puppetAction.SetObjectActionID(actionTweakID);
    
    // Set up action with proper target context
    let targetObject: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, data.m_actionOwner) as GameObject;
    if IsDefined(targetObject) {
        // Set the executor context for proper target resolution
        puppetAction.SetExecutor(targetObject);
        // Register the action against the target
        puppetAction.RegisterAsRequester(data.m_actionOwner);
    }
    
    QueueModLog(n"DEBUG", n"QUEUE", s"Reconstructed action: \(GetLocalizedText(data.m_title)) tweakID: \(TDBID.ToStringDEBUG(actionTweakID))");
    
    return puppetAction;
}

@addMethod(QuickhacksListGameController)
private func FindActionTweakID(data: ref<QuickhackData>) -> TweakDBID {
    if !IsDefined(data) {
        return TDBID.None();
    }

    let titleStr: String = GetLocalizedText(data.m_title);
       
    QueueModLog(n"DEBUG", n"CATALOG", s"Using manual fallback for: \(titleStr)");
    
    // Manual mappings for comprehensive fallback
    if Equals(titleStr, "Reboot Optics") { return t"QuickHack.BlindHack"; }
    if Equals(titleStr, "Overheat") { return t"QuickHack.OverheatHack"; }
    if Equals(titleStr, "Short Circuit") { return t"QuickHack.ShortCircuitHack"; }
    if Equals(titleStr, "Synapse Burnout") { return t"QuickHack.SynapseBurnoutHack"; }
    if Equals(titleStr, "Cyberware Malfunction") { return t"QuickHack.MalfunctionHack"; }
    if Equals(titleStr, "System Reset") { return t"QuickHack.SystemCollapseHack"; }
    if Equals(titleStr, "Memory Wipe") { return t"QuickHack.MemoryWipeHack"; }
    if Equals(titleStr, "Weapon Glitch") { return t"QuickHack.WeaponGlitchHack"; }
    if Equals(titleStr, "Disable Cyberware") { return t"QuickHack.DisableCyberwareHack"; }
    if Equals(titleStr, "Berserk") { return t"QuickHack.BerserkHack"; }
    if Equals(titleStr, "Suicide") { return t"QuickHack.SuicideHack"; }

    // Covert Hacks
    if Equals(titleStr, "Ping") { return t"QuickHack.PingHack"; }
    if Equals(titleStr, "Whistle") { return t"QuickHack.WhistleHack"; }
    if Equals(titleStr, "Distract Enemies") { return t"QuickHack.DistractEnemiesHack"; }

    // Control Hacks  
    if Equals(titleStr, "Cripple Movement") { return t"QuickHack.LocomotionMalfunctionHack"; }
    if Equals(titleStr, "Call Backup") { return t"QuickHack.CallBackupHack"; }
    if Equals(titleStr, "Friendly Mode") { return t"QuickHack.FriendlyModeHack"; }
    if Equals(titleStr, "Comms Noise") { return t"QuickHack.CommsNoiseHack"; }

    // Damage Hacks
    if Equals(titleStr, "Contagion") { return t"QuickHack.ContagionHack"; }

    // Ultimate Hacks
    if Equals(titleStr, "Cyberpsychosis") { return t"QuickHack.MadnessHack"; }
    if Equals(titleStr, "Madness") { return t"QuickHack.MadnessHack"; }
    if Equals(titleStr, "Detonate Grenade") { return t"QuickHack.DetonateGrenadeHack"; }
    if Equals(titleStr, "Brain Melt") { return t"QuickHack.BrainMeltHack"; }
    
    // Fallback: Check if we have the action reference directly
    if IsDefined(data.m_action) {
        let actionID: TweakDBID = data.m_action.GetObjectActionID();
        if TDBID.IsValid(actionID) {
            QueueModLog(n"DEBUG", n"QUEUE", s"Using action reference directly: \(titleStr) -> \(TDBID.ToStringDEBUG(actionID))");
            return actionID;
        }
    }
    
    QueueModLog(n"DEBUG", n"QUEUE", s"No mapping found for quickhack: \(titleStr)");
    return TDBID.None();
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