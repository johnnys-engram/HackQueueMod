// =============================================================================
// HackQueueMod - ScriptedPuppet Extensions
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Extensions.Puppet
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*

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

@addField(ScriptedPuppet)
private let m_lastQueueSizeLogged: Int32;

@addMethod(ScriptedPuppet)
public func IsQueueModFull() -> Bool {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return false;
    }
    let queueSize: Int32 = queue.GetQueueSize();
    let isFull: Bool = queueSize >= 3;
    
    // Only log when size changes
    if queueSize != this.m_lastQueueSizeLogged {
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] NPC queue size changed: \(queueSize), Full: \(isFull)");
        this.m_lastQueueSizeLogged = queueSize;
    }
    return isFull;
}

// =============================================================================
// Phase 3.2: NPC Upload Detection & Queue Processing - v1.63 Compatible Syntax
// =============================================================================

// Just add this ONE method to your ScriptedPuppet.reds file:
@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(
    puppetActions: array<ref<PuppetAction>>, 
    out commands: array<ref<QuickhackData>>
) -> Void {
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame())
        .IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    let hasQueued: Bool = IsDefined(this.GetQueueModActionQueue()) 
        && this.GetQueueModActionQueue().GetQueueSize() > 0;
    
    // Call vanilla first → all values, costs, cooldowns, prereqs set correctly
    wrappedMethod(puppetActions, commands);
    
    if (isOngoingUpload || hasQueued) && this.IsQueueModEnabled() && !this.IsQueueModFull() {
        let i: Int32 = 0;
        while i < ArraySize(commands) {
            let cmd = commands[i];
            if IsDefined(cmd) 
                && cmd.m_isLocked 
                && Equals(cmd.m_type, gamedataObjectActionType.PuppetQuickHack) 
                && Equals(cmd.m_inactiveReason, "LocKey#7020") {

                // Unlock upload-blocked command
                cmd.m_isLocked = false;
                cmd.m_inactiveReason = "";
                cmd.m_actionState = EActionInactivityReson.Ready;
                
                // Re-validate with other checks
                this.RevalidateCommandExcludingUpload(cmd, puppetActions);
            }
            i += 1;
        }
 
        QuickhackModule.RequestRefreshQuickhackMenu(this.GetGame(), this.GetEntityID());     
          
        // Sync PuppetAction states (critical vanilla requirement)
        let j: Int32 = 0;
        while j < ArraySize(commands) {
            if IsDefined(commands[j]) && commands[j].m_isLocked && IsDefined(commands[j].m_action) {
                let puppetAction: ref<PuppetAction> = commands[j].m_action as PuppetAction;
                if IsDefined(puppetAction) {
                    puppetAction.SetInactiveWithReason(false, commands[j].m_inactiveReason);
                }
            }
            j += 1;
        }
        
        QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod] Upload bypass with re-validation complete");
    }
}

@addMethod(ScriptedPuppet)
private func RevalidateCommandExcludingUpload(
    cmd: ref<QuickhackData>, 
    puppetActions: array<ref<PuppetAction>>
) -> Void {
    if !IsDefined(cmd) || !IsDefined(cmd.m_action) {
        return;
    }
    
    let action: ref<PuppetAction> = cmd.m_action as PuppetAction;
    if !IsDefined(action) {
        return;
    }
    
    // Re-run vanilla validation checks (excluding upload)
    
    // 1. Cost check
    if !action.CanPayCost() {
        cmd.m_isLocked = true;
        cmd.m_actionState = EActionInactivityReson.OutOfMemory;
        cmd.m_inactiveReason = "LocKey#27398";
        return;
    }
    
    // 2. Possibility/visibility check  
    let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
    if !IsDefined(player) || !action.IsPossible(this) || !action.IsVisible(player) {
        cmd.m_isLocked = true;
        cmd.m_actionState = EActionInactivityReson.Invalid;
        cmd.m_inactiveReason = "LocKey#7019";
        return;
    }
    
    // 3. Check if action became inactive
    if action.IsInactive() {
        cmd.m_isLocked = true;
        cmd.m_inactiveReason = action.GetInactiveReason();
        return;
    }
    
    // 4. Target active prereqs (simplified)
    let actionRecord: ref<ObjectAction_Record> = action.GetObjectActionRecord();
    if IsDefined(actionRecord) && actionRecord.GetTargetActivePrereqsCount() > 0 {
        let targetActivePrereqs: array<wref<ObjectActionPrereq_Record>>;
        actionRecord.TargetActivePrereqs(targetActivePrereqs);
        
        let i: Int32 = 0;
        while i < ArraySize(targetActivePrereqs) {
            if IsDefined(targetActivePrereqs[i]) {
                let prereqsToCheck: array<wref<IPrereq_Record>>;
                targetActivePrereqs[i].FailureConditionPrereq(prereqsToCheck);
                if !RPGManager.CheckPrereqs(prereqsToCheck, this) {
                    cmd.m_isLocked = true;
                    cmd.m_inactiveReason = targetActivePrereqs[i].FailureExplanation();
                    return;
                }
            }
            i += 1;
        }
    }
    
    // If we get here, all validation passed - command stays unlocked
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
        let paExec: ref<PuppetAction> = entry.action as PuppetAction;
        
        if IsDefined(paExec) {
            actionID = paExec.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing PuppetAction: \(TDBID.ToStringDEBUG(actionID))");
        }
        
        if !TDBID.IsValid(actionID) {
            QueueModLog(n"ERROR", n"QUICKHACK", s"[QueueMod][Exec] Action has invalid TweakDBID - skipping execution");
            return;
        }

        // CRITICAL FIX: Use ProcessRPGAction instead of OnQuickSlotCommandUsed for reliable execution
         if IsDefined(paExec) {
            // Ensure action targets this NPC
            paExec.RegisterAsRequester(this.GetEntityID());
            paExec.SetExecutor(player); // CRITICAL: Player executes, NPC receives
            
            // BUG 1 FIX: Lock the queue during execution to prevent race conditions
            this.GetQueueModActionQueue().LockQueue();
            
            // CRITICAL FIX: Use ProcessRPGAction for reliable post-upload execution
            // BUGFIX: Skip cost validation since RAM already deducted during queuing
            QueueModLog(n"DEBUG", n"QUICKHACK", s"[QueueMod][Exec] Processing PuppetAction RPG for target: \(GetLocalizedText(this.GetDisplayName()))");
            
            // Direct execution since RAM already deducted during queuing
            let originalRamCost: Int32 = paExec.GetCost(); // This will be the TweakDB cost

             paExec.ProcessRPGAction(this.GetGame());

            // Immediately refund the double-deduction
            if originalRamCost > 0 {
                this.QM_RefundRAM(originalRamCost);
                QueueModLog(n"DEBUG", n"RAM", s"[QueueMod] Refunded ProcessRPGAction RAM: \(originalRamCost)");
            }

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
              
    } else {
        QueueModLog(n"ERROR", n"QUEUE", s"[QueueMod] Invalid entry type: \(entry.entryType)");
    }
}

@addMethod(ScriptedPuppet)
private final func QM_RefundRAM(amount: Int32) -> Bool {
    let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.GetGame()).GetLocalPlayerControlledGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        return false;
    }
    
    let sps: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(this.GetGame());
    let oid: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
    
    if !sps.IsStatPoolAdded(oid, gamedataStatPoolType.Memory) {
        return false;
    }
    
    let refundAmount: Float = Cast<Float>(amount);
    
    // CORRECT v1.63 signature: (oid, poolType, value, instigator, useOldValue, isPercentage)
    sps.RequestChangingStatPoolValue(oid, gamedataStatPoolType.Memory, refundAmount, player, true, false);
    
    return true;
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