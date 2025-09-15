// =============================================================================
// HackQueueMod - UI Controllers
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.UI
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*
import JE_HackQueueMod.Helpers.*
import JE_HackQueueMod.Events.*

// =============================================================================
// QUICKHACKS LIST GAME CONTROLLER EXTENSIONS
// =============================================================================

// UI Controller Fields
@addField(QuickhacksListGameController)
private let m_qmPoolsRegistered: Bool;

@addField(QuickhacksListGameController)
private let m_qmRefreshScheduled: Bool;

@addField(QuickhacksListGameController)
private let m_qmControllerStored: Bool;

// Phase 4: Clear Controller Cache with Proper Repopulation
@addMethod(QuickhacksListGameController)
public func ClearControllerCacheInternal() -> Void {
    QueueModLog(n"DEBUG", n"UI", "[QueueMod] Clearing controller cache with repopulation");
    
    // Store current target for repopulation
    let currentTarget: EntityID = this.m_lastCompiledTarget;
    QueueModLog(n"DEBUG", n"UI", s"[QueueMod] Stored current target: \(EntityID.ToDebugString(currentTarget))");
    
    // Clear m_data array completely
    ArrayClear(this.m_data);
    QueueModLog(n"DEBUG", n"UI", "[QueueMod] Cleared m_data array");
    
    // Reset selected data
    this.m_selectedData = null;
    QueueModLog(n"DEBUG", n"UI", "[QueueMod] Reset m_selectedData");
    
    // Reset last compiled target (field removed - not defined)
    // this.m_lastCompiledTarget = EntityID();
    // QueueModLog(n"DEBUG", "[QueueMod] Reset m_lastCompiledTarget");
    
    // Clear list controller with force flag
    if IsDefined(this.m_listController) {
        this.m_listController.Clear(true);
        QueueModLog(n"DEBUG", n"UI", "[QueueMod] Cleared list controller with force flag");
    }
    
    QueueModLog(n"DEBUG", n"UI", "[QueueMod] Controller cache clearing and repopulation complete");
}

// =============================================================================
// Phase 4.1: UI Upload Detection Methods - v1.63 Compatible
// =============================================================================

@addMethod(QuickhacksListGameController)
private func IsQuickHackCurrentlyUploading() -> Bool {
    // Rule 1: Selected row UI lock (fastest path)
    if this.QueueModSelectedIsUILocked() {
        QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod][Detect] Selected row UI lock indicates upload in progress");
        return true;
    }

    // Rule 1b: Generic lock check for unknown reasons
    if IsDefined(this.m_selectedData) && this.m_selectedData.m_isLocked && 
       NotEquals(this.m_selectedData.m_actionState, EActionInactivityReson.Ready) {
        QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod][Detect] Selected item locked with unknown reason → treating as upload");
        return true;
    }

    // Rule 1c: Full UI lock scan (fallback for timing races)
    if this.QueueModDetectUILock() {
        QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod][Detect] Target indicates upload in progress");
        return true;
    }

    // Rule 2: Target check (only if NPC - devices skip pool)
    if IsDefined(this.m_selectedData) {
        let targetID: EntityID = this.m_selectedData.m_actionOwner;
        if EntityID.IsDefined(targetID) {
            let target: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as GameObject;
            if IsDefined(target) {
                // Log target type for debugging
                QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod][Detect] Target class: \(ToString(target.GetClassName()))");
                
                let puppet: ref<ScriptedPuppet> = target as ScriptedPuppet;
                if IsDefined(puppet) {
                    // Only check StatPool for NPCs (ScriptedPuppets)
                    let uploading: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance)
                        .IsStatPoolAdded(Cast<StatsObjectID>(puppet.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
                    QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod][Detect] NPC upload pool: \(uploading)");
                    return uploading;
                } else {
                    // Device detected - rely only on UI lock (already checked above)
                    QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod][Detect] Device target - UI lock only");
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
        QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod][Detect] Player upload pool (fallback): \(hasUploadPool)");
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
    QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod] StatPool listeners registered (placeholder)");
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
    return Equals(r, "LocKey#27398") || Equals(r, "LocKey#40765") || Equals(r, "LocKey#7020") || Equals(r, "LocKey#7019");
}

@addMethod(QuickhacksListGameController)
private func QueueModDetectUILock() -> Bool {
    let i: Int32 = 0;
    while i < ArraySize(this.m_data) {
        let entry: ref<QuickhackData> = this.m_data[i];
        if IsDefined(entry) && entry.m_isLocked && 
           (Equals(ToString(entry.m_inactiveReason), "LocKey#43809") ||   //Upload in Progress      
            Equals(ToString(entry.m_inactiveReason), "LocKey#7020")) //||   //Quickhack upload in progress…
 //          (Equals(ToString(entry.m_inactiveReason), "LocKey#27398") || //Out of Memory
 //           Equals(ToString(entry.m_inactiveReason), "LocKey#40765") || //Blocked
 //           Equals(ToString(entry.m_inactiveReason), "LocKey#7019")) 
            { //?
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

@wrapMethod(QuickhacksListGameController)
private func ApplyQuickHack() -> Bool {
    QueueModLog(n"DEBUG", n"QUICKHACK", "*** ApplyQuickHack called ***");

    if !IsDefined(this.m_selectedData) {
        QueueModLog(n"DEBUG", n"QUICKHACK", "No selectedData - executing normally");
        return wrappedMethod();
    }

    let actionName: String = GetLocalizedText(this.m_selectedData.m_title);
    let targetID: EntityID = this.m_selectedData.m_actionOwner;
    
    // CRITICAL: Validate all required data before processing
    if Equals(actionName, "") {
        QueueModLog(n"ERROR", n"QUICKHACK", "[QueueMod] Invalid action name - executing normally");
        return wrappedMethod();
    }
    
    if !EntityID.IsDefined(targetID) {
        QueueModLog(n"ERROR", n"QUICKHACK", "[QueueMod] Invalid target ID - executing normally");
        return wrappedMethod();
    }
    
    QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod] Processing: \(actionName) target: \(ToString(targetID))");

    // Check cooldown using the selectedData directly
    if this.QueueModIsOnCooldown(this.m_selectedData) {
        QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod] On cooldown: \(actionName)");
        return wrappedMethod();
    }

    // Check if we should queue FIRST, before touching RAM
    let shouldQueue: Bool = this.IsQuickHackCurrentlyUploading();
    QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Should queue: \(shouldQueue)");

    if shouldQueue {
        // Only deduct RAM if we're actually going to queue
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
        if !IsDefined(playerSystem) {
            QueueModLog(n"ERROR", n"QUICKHACK", "[QueueMod] Cannot get PlayerSystem - executing normally");
            return wrappedMethod();
        }
        
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            QueueModLog(n"ERROR", n"QUICKHACK", "[QueueMod] Cannot get player - executing normally");
            return wrappedMethod();
        }
        
        // SAFER VERSION - separate the casting and negation:
        if this.m_selectedData.m_cost > 0 {
            let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.m_gameInstance);
            if !IsDefined(sps) {
                QueueModLog(n"ERROR", n"RAM", "[QueueMod] Cannot get StatPoolsSystem - executing normally");
                return wrappedMethod();
            }
            
            let freeRam: Float = sps.GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Memory, false);
            if Cast<Float>(this.m_selectedData.m_cost) > freeRam {
                QueueModLog(n"ERROR", n"RAM", s"[QueueMod] Insufficient RAM for \(actionName): \(this.m_selectedData.m_cost) > \(freeRam) - executing normally");
                return wrappedMethod();
            }
        }

        // CRITICAL FIX: Try to use the original action first, fallback to reconstruction
        let actionToQueue: ref<DeviceAction> = null;
        
        // Check if we have a valid action reference
        if IsDefined(this.m_selectedData.m_action) {
            actionToQueue = this.m_selectedData.m_action;
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Using original action: \(actionToQueue.GetClassName())");
        } else {
            // Fallback to reconstruction only if no action reference
            actionToQueue = this.ReconstructActionFromData(this.m_selectedData);
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Reconstructed action from metadata: \(GetLocalizedText(this.m_selectedData.m_title))");
        }
        
        if IsDefined(actionToQueue) {
            // Get player reference for queuing
            let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
            if !IsDefined(playerSystem) {
                QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Cannot get PlayerSystem for queuing");
                return false;
            }
            
            let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
            if !IsDefined(player) {
                QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Cannot get player for queuing");
                return false;
            }
            
            let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();
            if !IsDefined(queueHelper) {
                QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Cannot get QueueModHelper - cannot queue action");
                return false;
            }
            
            let timeSystem: ref<TimeSystem> = GameInstance.GetTimeSystem(this.m_gameInstance);
            if !IsDefined(timeSystem) {
                QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Cannot get TimeSystem for key generation");
                return false;
            }
            
            let uniqueKey: String = s"\(ToString(targetID))::\(actionName)::\(timeSystem.GetSimTime())";
            
            let wasQueued: Bool = queueHelper.PutInQuickHackQueueWithKey(actionToQueue, uniqueKey);
            if wasQueued {
                QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing queued hack: \(actionName) (RAM deducted, queued for execution)");
                QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Queued action: \(actionName) class=\(actionToQueue.GetClassName())");
                this.ApplyQueueModCooldownWithData(this.m_selectedData);
                
                // Fire QueueEvent for state synchronization
                this.QM_FireQueueEvent(n"ItemAdded", this.m_selectedData);
                return true;
            } else {
                QueueModLog(n"ERROR", n"QUEUE", s"[QueueMod] Failed to queue action: \(actionName)");
                return false;
            }
        } else {
            QueueModLog(n"ERROR", n"QUEUE", s"[QueueMod] Cannot queue - no valid action available");
            return false;
        }
    } else {
        // For non-queued hacks, execute normally - let vanilla handle RAM deduction
        QueueModLog(n"DEBUG", n"QUICKHACK", "Executing non-queued hack normally (vanilla handles RAM)");
        return wrappedMethod();
    }
    
    // This should never be reached since shouldQueue=true returns early above
    QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Unexpected code path - shouldQueue was true but we didn't queue");
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
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Cannot find TweakDBID for: \(GetLocalizedText(data.m_title))");
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
    
    QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Reconstructed action: \(GetLocalizedText(data.m_title)) tweakID: \(TDBID.ToStringDEBUG(actionTweakID))");
    
    return puppetAction;
}

@addMethod(QuickhacksListGameController)
private func FindActionTweakID(data: ref<QuickhackData>) -> TweakDBID {
    if !IsDefined(data) {
        return TDBID.None();
    }

    let titleStr: String = GetLocalizedText(data.m_title);
       
    // CRITICAL: Fallback to manual mappings for safety during transition
    QueueModLog(n"DEBUG", n"CATALOG", s"[Integration] Catalog lookup failed, using manual fallback for: \(titleStr)");
    
    // Keep existing manual mappings as comprehensive fallback
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

    // Damage Hacks (separated Contagion from Comms Noise)
    if Equals(titleStr, "Contagion") { return t"QuickHack.ContagionHack"; }

    // Ultimate Hacks
    if Equals(titleStr, "Cyberpsychosis") { return t"QuickHack.MadnessHack"; }
    if Equals(titleStr, "Madness") { return t"QuickHack.MadnessHack"; }
    if Equals(titleStr, "Detonate Grenade") { return t"QuickHack.DetonateGrenadeHack"; }
    if Equals(titleStr, "Brain Melt") { return t"QuickHack.BrainMeltHack"; }
    
    // FALLBACK: Check if we have the action reference directly
    if IsDefined(data.m_action) {
        let actionID: TweakDBID = data.m_action.GetObjectActionID();
        if TDBID.IsValid(actionID) {
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Using action reference directly: \(titleStr) -> \(TDBID.ToStringDEBUG(actionID))");
            return actionID;
        }
    }
    
    QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] No mapping found for quickhack: \(titleStr)");
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
        QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod] Applied cooldown: \(data.m_cooldown)s");
        
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
 
        this.RegisterCooldownStatPoolUpdate();
    }
}

@addMethod(QuickhacksListGameController)
private func QM_FireQueueEvent(eventType: CName, data: ref<QuickhackData>) -> Void {
    // Fire QueueEvent for state synchronization
    QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod][Event] Fired \(ToString(eventType)) for \(GetLocalizedText(data.m_title))");
    
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

// Store controller reference on player for UI access - using OnInitialize
@wrapMethod(QuickhacksListGameController)
protected cb func OnInitialize() -> Bool {
    let result: Bool = wrappedMethod();
    let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.m_gameInstance).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if IsDefined(player) {
        player.SetQuickhacksListGameController(this);
        this.m_qmControllerStored = true;
        QueueModLog(n"DEBUG", n"UI", "[QueueMod] Controller reference stored on player via OnInitialize");
    }
    return result;
}

@addMethod(QuickhacksListGameController)
private func TestActionReferencePreservation(data: ref<QuickhackData>) -> ref<DeviceAction> {
    if !IsDefined(data) {
        QueueModLog(n"DEBUG", n"QUEUE", "[TEST] QuickhackData is null");
        return null;
    }
    
    QueueModLog(n"DEBUG", n"QUEUE", s"[TEST] Testing action preservation for: \(GetLocalizedText(data.m_title))");
    
    // Test 1: Check if m_action exists and is valid
    if IsDefined(data.m_action) {
        QueueModLog(n"DEBUG", n"QUEUE", s"[TEST] ✓ m_action exists: \(data.m_action.GetClassName())");
        
        // Test 2: Check if it has a valid TweakDBID
        let actionID: TweakDBID = data.m_action.GetObjectActionID();
        if TDBID.IsValid(actionID) {
            QueueModLog(n"DEBUG", n"QUEUE", s"[TEST] ✓ Action ID valid: \(TDBID.ToStringDEBUG(actionID))");
            return data.m_action;
        } else {
            QueueModLog(n"DEBUG", n"QUEUE", "[TEST] ✗ Action ID invalid");
        }
    } else {
        QueueModLog(n"DEBUG", n"QUEUE", "[TEST] ✗ m_action is null - data loss confirmed");
    }
    
    return null;
}