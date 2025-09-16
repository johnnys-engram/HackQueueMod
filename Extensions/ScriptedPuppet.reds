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
// CONSTANTS
// =============================================================================

// LocKey constants for better maintainability
public func GetUploadInProgressKey() -> String { return "LocKey#7020"; }
public func GetOutOfMemoryKey() -> String { return "LocKey#27398"; }
public func GetInvalidActionKey() -> String { return "LocKey#7019"; }
public func GetBlockedKey() -> String { return "LocKey#40765"; }

// =============================================================================
// SCRIPTED PUPPET EXTENSIONS
// =============================================================================

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
    let isFull: Bool = queueSize >= GetDefaultQueueSize();
    
    // Only log when size changes
    if queueSize != this.m_lastQueueSizeLogged {
        QueueModLog(n"DEBUG", n"QUEUE", s"NPC queue size changed: \(queueSize), Full: \(isFull)");
        this.m_lastQueueSizeLogged = queueSize;
    }
    return isFull;
}

// =============================================================================
// NPC Upload Detection & Queue Processing
// =============================================================================

@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(
    puppetActions: array<ref<PuppetAction>>, 
    out commands: array<ref<QuickhackData>>
) -> Void {
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame())
        .IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    let hasQueued: Bool = IsDefined(this.GetQueueModActionQueue()) 
        && this.GetQueueModActionQueue().GetQueueSize() > 0;
    
    // Call vanilla first - all values, costs, cooldowns, prereqs set correctly
    wrappedMethod(puppetActions, commands);
    
    if (isOngoingUpload || hasQueued) && this.IsQueueModEnabled() && !this.IsQueueModFull() {
        let i: Int32 = 0;
        while i < ArraySize(commands) {
            let cmd = commands[i];
            if IsDefined(cmd) 
                && cmd.m_isLocked 
                && Equals(cmd.m_type, gamedataObjectActionType.PuppetQuickHack) 
                && Equals(cmd.m_inactiveReason, GetUploadInProgressKey()) {

                // Unlock upload-blocked command
                cmd.m_isLocked = false;
                cmd.m_inactiveReason = "";
                cmd.m_actionState = EActionInactivityReson.Ready;
                
                // NOW check RAM cost using the command's stored cost values
                // cmd.m_cost is the final calculated cost after all modifiers
                let playerMemory: Float = GameInstance.GetStatPoolsSystem(this.GetGame())
                    .GetStatPoolValue(Cast<StatsObjectID>(GetPlayer(this.GetGame()).GetEntityID()), gamedataStatPoolType.Memory, false);

                if IsDefined(cmd.m_category) && Equals(cmd.m_category.EnumName(), n"NotAHack") {
                    cmd.m_isLocked = true;
                    cmd.m_inactiveReason = GetBlockedKey();
                    cmd.m_actionState = EActionInactivityReson.Locked;
                }
                
                if Cast<Float>(cmd.m_cost) > playerMemory {
                    // Re-lock due to insufficient RAM
                    cmd.m_isLocked = true;
                    cmd.m_inactiveReason = GetOutOfMemoryKey(); // "Insufficient RAM Available"
                    cmd.m_actionState = EActionInactivityReson.OutOfMemory;
                    
                    QueueModLog(n"DEBUG", n"RAM_BLOCK", s"Blocked \(GetLocalizedText(cmd.m_title)) - Cost:\(cmd.m_cost) Available:\(playerMemory)");
                } else {
                    QueueModLog(n"DEBUG", n"RAM_OK", s"Allowed \(GetLocalizedText(cmd.m_title)) - Cost:\(cmd.m_cost) Available:\(playerMemory)");
                }
            }
            i += 1;
        }
 
        QuickhackModule.RequestRefreshQuickhackMenu(this.GetGame(), this.GetEntityID());     
          
        // Sync PuppetAction states with corrected command states
        let j: Int32 = 0;
        while j < ArraySize(commands) {
            if IsDefined(commands[j]) && IsDefined(commands[j].m_action) {
                let puppetAction: ref<PuppetAction> = commands[j].m_action as PuppetAction;
                if IsDefined(puppetAction) {
                    if commands[j].m_isLocked {
                        puppetAction.SetInactiveWithReason(false, commands[j].m_inactiveReason);
                    } else {
                        puppetAction.SetInactiveWithReason(true, "");
                    }
                }
            }
            j += 1;
        }
        
    }
}

// =============================================================================
// Queue Execution on Upload Completion
// =============================================================================

@wrapMethod(ScriptedPuppet)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);

    // Only check our queue processing
    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) && 
       Equals(evt.progressBarType, EProgressBarType.UPLOAD) && 
       Equals(evt.state, EUploadProgramState.COMPLETED) {
        
        // Check death before processing queue
        if this.IsDead() || 
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") ||
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
            
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
// Quickhack Execution
// =============================================================================

@addMethod(ScriptedPuppet)
private func ExecuteQueuedEntry(entry: ref<QueueModEntry>) -> Void {
    if !IsDefined(entry) {
        QueueModLog(n"ERROR", n"QUEUE", "ExecuteQueuedEntry called with null entry");
        return;
    }

    // Validate target is still alive and valid
    if !IsDefined(this) || this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
        QueueModLog(n"DEBUG", n"QUICKHACK", "Target invalid/dead/unconscious - clearing queue");
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.ClearQueue(this.GetGame(), this.GetEntityID());
        }
        return;
    }

    // Get player context for execution
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        QueueModLog(n"ERROR", n"QUICKHACK", "Cannot find player for quickhack execution");
        return;
    }

    if Equals(entry.entryType, GetActionEntryType()) && IsDefined(entry.action) {
        QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing queued action: class=\(entry.action.GetClassName()) on NPC=\(GetLocalizedText(this.GetDisplayName()))");
        
        // Validate action identity before execution
        let actionID: TweakDBID = TDBID.None();
        let paExec: ref<PuppetAction> = entry.action as PuppetAction;
        
        if IsDefined(paExec) {
            actionID = paExec.GetObjectActionID();
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing PuppetAction: \(TDBID.ToStringDEBUG(actionID))");
        }
        
        if !TDBID.IsValid(actionID) {
            QueueModLog(n"ERROR", n"QUICKHACK", "Action has invalid TweakDBID - skipping execution");
            return;
        }

        if IsDefined(paExec) {
            // Ensure action targets this NPC
            paExec.RegisterAsRequester(this.GetEntityID());
            paExec.SetExecutor(player);
            
            // Lock the queue during execution to prevent race conditions
            this.GetQueueModActionQueue().LockQueue();
            
            // Use ProcessRPGAction for reliable post-upload execution
            // Cost override ensures no double deduction
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Processing PuppetAction RPG for target: \(GetLocalizedText(this.GetDisplayName()))");

            paExec.ProcessRPGAction(this.GetGame());

            // Check immediately after execution
            if this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || 
               StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
                QueueModLog(n"DEBUG", n"QUICKHACK", "Target died during execution - clearing queue");
                this.GetQueueModActionQueue().ClearQueue(this.GetGame(), this.GetEntityID());
                return;
            }
            this.GetQueueModActionQueue().UnlockQueue();
            
        } else {
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Unknown action type: \(entry.action.GetClassName())");
        }
              
    } else {
        QueueModLog(n"ERROR", n"QUEUE", s"Invalid entry type: \(entry.entryType)");
    }
}

// Event-driven cleanup for death/unconscious status effects
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
                QueueModLog(n"DEBUG", n"EVENTS", s"Queue cleared on death/unconscious status: \(effectIDStr)");
            }
        }
    }
    return result;
}