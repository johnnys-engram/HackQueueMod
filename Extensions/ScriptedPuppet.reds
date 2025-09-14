// =============================================================================
// HackQueueMod - ScriptedPuppet Extensions
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Extensions.Puppet
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*
import JE_HackQueueMod.Helpers.*

// =============================================================================
// SCRIPTED PUPPET EXTENSIONS - MOST CRITICAL COMPONENT
// =============================================================================

// ScriptedPuppet extensions
@addField(ScriptedPuppet)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(ScriptedPuppet)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
        this.m_queueModActionQueue.Initialize();
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
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] NPC queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

// =============================================================================
// Phase 3.2: NPC Upload Detection & Queue Processing - v1.63 Compatible Syntax
// =============================================================================

@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(puppetActions: array<ref<PuppetAction>>, out commands: array<ref<QuickhackData>>) -> Void {
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame()).IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    let hasQueued: Bool = IsDefined(this.GetQueueModActionQueue()) && this.GetQueueModActionQueue().GetQueueSize() > 0;
    
    // Call vanilla first
    wrappedMethod(puppetActions, commands);
    
    // Only intervene when queue is active
    if isOngoingUpload || hasQueued {
        let queueEnabled: Bool = this.IsQueueModEnabled();
        let queueFull: Bool = this.IsQueueModFull();

        if queueEnabled && !queueFull {
            // Unlock quickhacks only - breach protocol stays blocked by vanilla logic
            let i: Int32 = 0;
            while i < ArraySize(commands) {
                if IsDefined(commands[i]) && commands[i].m_isLocked && 
                   Equals(commands[i].m_type, gamedataObjectActionType.PuppetQuickHack) &&
                    NotEquals(commands[i].m_type, gamedataObjectActionType.MinigameUpload) {
                    
                    commands[i].m_isLocked = false;
                    commands[i].m_inactiveReason = "";
                    commands[i].m_actionState = EActionInactivityReson.Ready;
                }
                i += 1;
            }
            QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod] Unblocked quickhacks during upload - breach protocol remains blocked");
        }
    }
}

// =============================================================================
// Phase 3.3: Queue Execution on Upload Completion - v1.63 Syntax
// =============================================================================

@wrapMethod(ScriptedPuppet)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    // Let vanilla process first (can't prevent it)
    let result: Bool = wrappedMethod(evt);

    // Only check our queue processing
    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) && 
       Equals(evt.progressBarType, EProgressBarType.UPLOAD) && 
       Equals(evt.state, EUploadProgramState.COMPLETED) {
        
        // Check death NOW before processing OUR queue
        if this.IsDead() || 
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") ||
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
            
            // Clear our queue
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                queue.ClearQueue(this.GetGame(), this.GetEntityID());
                QueueModLog(n"DEBUG", n"QUICKHACK", "Target dead - queue cleared, vanilla hack may still apply");
            }
            return result;
        }
        
        // Process queue only if alive
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) && queue.GetQueueSize() > 0 {
            // FIX 4: Validate before processing - halt execution if validation fails
            if !queue.ValidateQueueIntegrity() {
                QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Queue integrity failed - halting execution and clearing queue");
                queue.ClearQueue(this.GetGame(), this.GetEntityID()); // Clear corrupted queue
                return result;
            }
            
            let entry: ref<QueueModEntry> = queue.PopNextEntry();
            if IsDefined(entry) {
                QueueModLog(n"DEBUG", n"QUICKHACK", s"Upload complete for NPC=\(GetLocalizedText(this.GetDisplayName())) processing queue");
                this.ExecuteQueuedEntry(entry);
            }
        } else {
            QueueModLog(n"DEBUG", n"QUEUE", "No queued entries to execute");
        }
    }

    return result;
}

// =============================================================================
// CRITICAL FIX: Correct Quickhack Execution Context
// Replace the ExecuteQueuedEntry method in ScriptedPuppet
// =============================================================================

@addMethod(ScriptedPuppet)
private func ExecuteQueuedEntry(entry: ref<QueueModEntry>) -> Void {
    if !IsDefined(entry) {
        QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] ExecuteQueuedEntry called with null entry");
        return;
    }
    
    // FIX 4: Validate queue integrity before execution
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if IsDefined(queue) && !queue.ValidateQueueIntegrity() {
        QueueModLog(n"ERROR", n"QUEUE", "[QueueMod] Queue integrity failed during execution - halting");
        queue.ClearQueue(this.GetGame(), this.GetEntityID());
        return;
    }

    // PHASE 1: Validate target is still alive and valid (enhanced death check)
    if !IsDefined(this) || this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
        QueueModLog(n"DEBUG", n"QUICKHACK", "Target invalid/dead/unconscious - clearing queue");
        this.NotifyPlayerQueueCanceled("Target eliminated, queued quickhacks canceled.");
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.ClearQueue(this.GetGame(), this.GetEntityID());
        }
        return;
    }

    // CRITICAL FIX: Get player context for execution
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        QueueModLog(n"ERROR", n"QUICKHACK", "[QueueMod] Cannot find player for quickhack execution");
        return;
    }

    if Equals(entry.entryType, 0) && IsDefined(entry.action) {
        QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing queued action: class=\(entry.action.GetClassName()) on NPC=\(GetLocalizedText(this.GetDisplayName()))");
        
        // Validate action identity before execution
        let actionID: TweakDBID = TDBID.None();
        let saExec: ref<ScriptableDeviceAction> = entry.action as ScriptableDeviceAction;
        let paExec: ref<PuppetAction> = entry.action as PuppetAction;
        
        if IsDefined(saExec) {
            actionID = saExec.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing ScriptableDeviceAction: \(TDBID.ToStringDEBUG(actionID))");
        } else if IsDefined(paExec) {
            actionID = paExec.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing PuppetAction: \(TDBID.ToStringDEBUG(actionID))");
        }
        
        if !TDBID.IsValid(actionID) {
            QueueModLog(n"ERROR", n"QUICKHACK", s"[QueueMod][Exec] Action has invalid TweakDBID - skipping execution");
            return;
        }
        
        // PHASE 3: RAM already deducted on selection (like vanilla behavior)
        // No need to deduct RAM again during execution
        
        // Note: ExecuteQueuedEntryViaUI removed - would cause infinite recursion
        
        // FALLBACK: Direct execution with UI feedback
        // CRITICAL FIX: Use ProcessRPGAction instead of OnQuickSlotCommandUsed for reliable execution
        if IsDefined(saExec) {
            // Ensure action targets this NPC
            saExec.RegisterAsRequester(this.GetEntityID());
            saExec.SetExecutor(player); // CRITICAL: Player executes, NPC receives
            
            // BUG 1 FIX: Lock the queue during execution to prevent race conditions
            this.GetQueueModActionQueue().LockQueue();
            
            // MISSING UI EFFECT: Add UI feedback BEFORE execution
            this.TriggerQuickhackUIFeedback(saExec);
            
            // CRITICAL FIX: Use ProcessRPGAction for reliable post-upload execution
            // BUGFIX: Skip cost validation since RAM already deducted during queuing
            QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod][Exec] Processing RPG action for target: \(GetLocalizedText(this.GetDisplayName()))");
            
            // Direct execution since RAM already deducted during queuing
            saExec.ProcessRPGAction(this.GetGame());
            
            // Check immediately after execution
            if this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || 
               StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
                QueueModLog(n"DEBUG", n"QUICKHACK", "Target died during execution - clearing queue");
                this.GetQueueModActionQueue().ClearQueue(this.GetGame(), this.GetEntityID());
                // Don't try to reverse - just prevent next execution
                return;
            }
            this.GetQueueModActionQueue().UnlockQueue();
            
        } else if IsDefined(paExec) {
            // Ensure action targets this NPC
            paExec.RegisterAsRequester(this.GetEntityID());
            paExec.SetExecutor(player); // CRITICAL: Player executes, NPC receives
            
            // BUG 1 FIX: Lock the queue during execution to prevent race conditions
            this.GetQueueModActionQueue().LockQueue();
            
            // MISSING UI EFFECT: Add UI feedback BEFORE execution
            this.TriggerQuickhackUIFeedback(paExec);
            
            // CRITICAL FIX: Use ProcessRPGAction for reliable post-upload execution
            // BUGFIX: Skip cost validation since RAM already deducted during queuing
            QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod][Exec] Processing PuppetAction RPG for target: \(GetLocalizedText(this.GetDisplayName()))");
            
            // Direct execution since RAM already deducted during queuing
            paExec.ProcessRPGAction(this.GetGame());
            
            // Check immediately after execution
            if this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || 
               StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
                QueueModLog(n"DEBUG", n"QUICKHACK", "Target died during execution - clearing queue");
                this.GetQueueModActionQueue().ClearQueue(this.GetGame(), this.GetEntityID());
                // Don't try to reverse - just prevent next execution
                return;
            }
            this.GetQueueModActionQueue().UnlockQueue();
            
        } else {
            QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod][Exec] Unknown action type: \(entry.action.GetClassName())");
        }
        
        // PHASE 3: Note: Cost restoration not needed since SetCost not available in v1.63
        
    } else {
        QueueModLog(n"ERROR", n"QUEUE", s"[QueueMod] Invalid entry type: \(entry.entryType)");
    }

    // ✅ ADD THIS: Force refresh after execution
    QuickhackQueueHelper.ForceQuickhackUIRefresh(this.GetGame(), this.GetEntityID());
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
        QueueModLog(n"DEBUG", n"UI", s"[QueueMod][HUD] Target \(GetLocalizedText(this.GetDisplayName())) has \(queueSize) queued hacks");
        
        // TODO: Add visual HUD overlay here
        // This would integrate with the game's HUD system to show:
        // - Small stack icons near enemy health bar
        // - Progress bar showing upload progress
        // - Queue count indicator
    }
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
            QueueModLog(n"DEBUG", n"UI", s"[QueueMod][Notification] \(message)");
        }
    }
}

@addMethod(ScriptedPuppet)
private func NotifyPlayerRAMRefunded(amount: Int32) -> Void {
    let message: String = s"RAM refunded: \(amount) units";
    this.NotifyPlayerQueueCanceled(message);
}

@addMethod(ScriptedPuppet)
private func QM_RefundRam(amount: Int32) -> Void {
    let ps: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    let player: ref<PlayerPuppet> = IsDefined(ps) ? ps.GetLocalPlayerMainGameObject() as PlayerPuppet : null;
    if !IsDefined(player) || amount <= 0 { return; }
    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.GetGame());
    let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, Cast<Float>(amount), player, false);
    QueueModLog(n"DEBUG", n"RAM", s"[QueueMod] Refunded RAM (intent): \(amount)");
}

@addMethod(ScriptedPuppet)
private func QM_MapQuickhackToSE(tweak: TweakDBID) -> TweakDBID {
    // Map known quickhacks -> their status effects (v1.63 names)
    // Fallback: return TDBID.None() if unknown (so we can bail safely)
    let s: String = TDBID.ToStringDEBUG(tweak);
    // Common ones used in your logs/tests:
    if StrContains(s, "QuickHack.OverheatHack") { return t"StatusEffect.Overheat"; }
    if StrContains(s, "QuickHack.BlindHack")    { return t"StatusEffect.Blind"; }
    if StrContains(s, "QuickHack.ShortCircuitHack") { return t"StatusEffect.ShortCircuit"; }
    if StrContains(s, "QuickHack.SynapseBurnoutHack") { return t"StatusEffect.SynapseBurnout"; }
    if StrContains(s, "QuickHack.CommsNoiseHack") { return t"StatusEffect.Contagion"; }
    if StrContains(s, "QuickHack.MalfunctionHack") { return t"StatusEffect.CyberwareMalfunction"; }
    if StrContains(s, "QuickHack.SystemCollapseHack") { return t"StatusEffect.SystemReset"; }
    if StrContains(s, "QuickHack.MemoryWipeHack") { return t"StatusEffect.MemoryWipe"; }
    if StrContains(s, "QuickHack.WeaponGlitchHack") { return t"StatusEffect.WeaponMalfunction"; }
    if StrContains(s, "QuickHack.DisableCyberwareHack") { return t"StatusEffect.DisableCyberware"; }
    // Add more as needed
    return TDBID.None();
}

@addMethod(ScriptedPuppet)
private func QM_ApplyQuickhackIntent(tweak: TweakDBID) -> Bool {
    // Try SE-based application first (works for Overheat/Reboot Optics/etc.)
    let seID: TweakDBID = this.QM_MapQuickhackToSE(tweak);
    if TDBID.IsValid(seID) {
        StatusEffectHelper.ApplyStatusEffect(this, seID);
        QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod][Exec] Applied SE for quickhack: \(TDBID.ToStringDEBUG(seID))");
        return true;
    }
    QueueModLog(n"DEBUG", n"QUICKHACK", "No SE mapping for quickhack; skipping");
    return false;
}

// PHASE 1: Death event listener for queue cancellation (v1.63 compatible)
@addMethod(ScriptedPuppet)
protected cb func OnQueueDeathEvent(evt: ref<Event>) -> Bool {
    // Check if this is actually a death-related event
    let eventType: CName = evt.GetClassName();
    QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Event received: \(ToString(eventType)) on \(GetLocalizedText(this.GetDisplayName()))");
    
    // Check for death via status effect or IsDead()
    let isDead: Bool = this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead");
    if isDead {
        QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Death confirmed - clearing queue");
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.ClearQueue(this.GetGame(), this.GetEntityID());  // Refunds all queued RAM
            this.NotifyPlayerQueueCanceled("Target died - queued quickhacks canceled and RAM refunded.");
        }
    }
    return true;
}

// FIX 1: Death Registration - Register death handler in lifecycle
@addMethod(ScriptedPuppet)
protected func OnGameAttached() -> Void {
    // Note: RegisterListener API limited in v1.63, using manual event checking instead
    // Death events will be checked in existing methods (OnUploadProgressStateChanged, ExecuteQueuedEntry)
    QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Death event checking enabled for \(GetLocalizedText(this.GetDisplayName()))");
}

// EVENT-DRIVEN CLEANUP: Proper status effect listener for death/unconscious
@wrapMethod(ScriptedPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    
    // Check if death/unconscious effect
    if IsDefined(evt.staticData) {
        let effectID: TweakDBID = evt.staticData.GetID();
        let effectIDStr: String = TDBID.ToStringDEBUG(effectID);
        
        if StrContains(effectIDStr, "Dead") || StrContains(effectIDStr, "Unconscious") ||
           StrContains(effectIDStr, "BaseStatusEffect.Dead") || StrContains(effectIDStr, "BaseStatusEffect.Unconscious") {
            
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                queue.ClearQueue(this.GetGame(), this.GetEntityID());
                QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Queue cleared on death/unconscious status: \(effectIDStr)");
            }
        }
    }
    return result;
}

// ✅ SIMPLIFIED: Event Handlers for Sequenced Refresh System  
// Note: Custom event types moved to direct QuickhackQueueHelper calls to avoid linter issues
@addMethod(ScriptedPuppet)
protected cb func OnQueueModCommandGenEvent(evt: ref<Event>) -> Bool {
    QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Command generation event received for entity: \(ToString(this.GetEntityID()))");
    
    // Force fresh command generation with injection
    QuickhackQueueHelper.ForceFreshCommandGeneration(this.GetGame(), this.GetEntityID());
    
    QueueModLog(n"DEBUG", n"EVENTS", "Command generation event processing complete");
    return true;
}

@addMethod(ScriptedPuppet)
protected cb func OnQueueModCacheEvent(evt: ref<Event>) -> Bool {
    QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Cache event received for entity: \(ToString(this.GetEntityID()))");
    
    // Clear controller cache with repopulation
    QuickhackQueueHelper.ClearControllerCache(this.GetGame(), this.GetEntityID());
    
    QueueModLog(n"DEBUG", n"EVENTS", "Cache event processing complete");
    return true;
}

@addMethod(ScriptedPuppet)
protected cb func OnQueueModValidationEvent(evt: ref<Event>) -> Bool {
    QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Validation event received for entity: \(ToString(this.GetEntityID()))");
    
    // ✅ SIMPLIFIED: Basic validation logging
    let gameInstance: GameInstance = this.GetGame();
    let targetID: EntityID = this.GetEntityID();
    
    // Get the player and controller for validation
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if IsDefined(player) {
        let controller: ref<QuickhacksListGameController> = player.GetQuickhacksListGameController();
        if IsDefined(controller) {
            // Check if the controller has fresh data for this target
            let hasData: Bool = ArraySize(controller.m_data) > 0;
            let correctTarget: Bool = EntityID.IsDefined(controller.m_lastCompiledTarget) && Equals(controller.m_lastCompiledTarget, targetID);
            
            QueueModLog(n"DEBUG", n"EVENTS", s"[QueueMod] Validation results - Has data: \(hasData), Correct target: \(correctTarget)");
            
            if !hasData || !correctTarget {
                QueueModLog(n"DEBUG", n"EVENTS", "Validation failed - refresh may need retry");
            } else {
                QueueModLog(n"DEBUG", n"EVENTS", "Validation passed - refresh successful");
            }
        }
    }
    
    QueueModLog(n"DEBUG", n"EVENTS", "Validation event processing complete");
    return true;
}

// MISSING UI EFFECT: Trigger vanilla UI feedback for queued quickhacks (v1.63 compatible)
@addMethod(ScriptedPuppet)
private func TriggerQuickhackUIFeedback(action: ref<DeviceAction>) -> Void {
    let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.GetGame()).GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) { 
        QueueModLog(n"DEBUG", n"UI", "No player found for UI feedback");
        return; 
    }
    
    // Use actual quickhack visual effects (v1.63 compatible)
    GameObject.PlaySoundEvent(this, n"ui_quickhack_upload_complete");
    // Note: StartEffectEvent not available on ScriptedPuppet in v1.63
    
    // Audio cue (v1.63 compatible)
    let audioSystem: ref<AudioSystem> = GameInstance.GetAudioSystem(this.GetGame());
    if IsDefined(audioSystem) {
        audioSystem.Play(n"ui_quickhack_execute");
        QueueModLog(n"DEBUG", n"UI", "Played quickhack activation sound");
    }
    
    QueueModLog(n"DEBUG", n"UI", "UI feedback triggered for queued quickhack (v1.63 compatible)");
}