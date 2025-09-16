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

@addField(ScriptedPuppet)
private let m_queuedActionIDs: array<TweakDBID>;

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

// Cache maintenance methods
@addMethod(ScriptedPuppet)
public func QueueMod_AddToCache(actionID: TweakDBID) -> Void {
    if TDBID.IsValid(actionID) && !ArrayContains(this.m_queuedActionIDs, actionID) {
        ArrayPush(this.m_queuedActionIDs, actionID);
        QueueModLog(n"DEBUG", n"QUEUE", s"Added to cache: \(TDBID.ToStringDEBUG(actionID)), cache size: \(ArraySize(this.m_queuedActionIDs))");
    }
}

@addMethod(ScriptedPuppet)
public func QueueMod_RemoveFromCache(actionID: TweakDBID) -> Void {
    if TDBID.IsValid(actionID) {
        ArrayRemove(this.m_queuedActionIDs, actionID);
        QueueModLog(n"DEBUG", n"QUEUE", s"Removed from cache: \(TDBID.ToStringDEBUG(actionID)), cache size: \(ArraySize(this.m_queuedActionIDs))");
    }
}

@addMethod(ScriptedPuppet)
public func QueueMod_ClearCache() -> Void {
    let oldSize: Int32 = ArraySize(this.m_queuedActionIDs);
    ArrayClear(this.m_queuedActionIDs);
    QueueModLog(n"DEBUG", n"QUEUE", s"Cache cleared: \(oldSize) -> 0");
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
    
    if !(isOngoingUpload || hasQueued) || !this.IsQueueModEnabled() || this.IsQueueModFull() {
        // Queue not active - use vanilla behavior
        wrappedMethod(puppetActions, commands);
    } else {
        // Queue is active - build commands manually to preserve action data
        this.BuildQuickHackCommandsForQueue(puppetActions, commands);
        QuickhackModule.RequestRefreshQuickhackMenu(this.GetGame(), this.GetEntityID());    
    }
}

@addMethod(ScriptedPuppet)
private func BuildQuickHackCommandsForQueue(
    puppetActions: array<ref<PuppetAction>>, 
    out commands: array<ref<QuickhackData>>
) -> Void {
    let playerRef: ref<PlayerPuppet> = GetPlayer(this.GetGame());
    let actionOwnerName: CName = StringToName(this.GetTweakDBFullDisplayName(true));
    let iceLVL: Float = this.GetICELevel();
    let playerQHacksList: array<PlayerQuickhackData> = RPGManager.GetPlayerQuickHackListWithQuality(playerRef);

    QueueModLog(n"DEBUG", n"QUEUE", s"Building queue commands, cache size: \(ArraySize(this.m_queuedActionIDs))");

    if ArraySize(playerQHacksList) == 0 {
        let newCommand: ref<QuickhackData> = new QuickhackData();
        newCommand.m_title = "LocKey#42171";
        newCommand.m_isLocked = true;
        newCommand.m_actionOwnerName = actionOwnerName;
        newCommand.m_actionState = EActionInactivityReson.Invalid;
        newCommand.m_description = "LocKey#42172";
        ArrayPush(commands, newCommand);
        return;
    }

    let i: Int32 = 0;
    while i < ArraySize(playerQHacksList) {
        let actionRecord: wref<ObjectAction_Record> = playerQHacksList[i].actionRecord;
        
        // Replace continue with if-else structure
        if Equals(actionRecord.ObjectActionType().Type(), gamedataObjectActionType.PuppetQuickHack) {
            let newCommand: ref<QuickhackData> = new QuickhackData();
            let actionMatchDeck: Bool = false;
            let matchedAction: ref<PuppetAction>;

            // Find matching action in puppetActions array
            let i1: Int32 = 0;
            while i1 < ArraySize(puppetActions) {
                if Equals(actionRecord.ActionName(), puppetActions[i1].GetObjectActionRecord().ActionName()) {
                    actionMatchDeck = true;
                    
                    if actionRecord.Priority() >= puppetActions[i1].GetObjectActionRecord().Priority() {
                        puppetActions[i1].SetObjectActionID(playerQHacksList[i].actionRecord.GetID());
                        matchedAction = puppetActions[i1];
                    } else {
                        actionRecord = puppetActions[i1].GetObjectActionRecord();
                        matchedAction = puppetActions[i1];
                    }
                    
                    newCommand.m_uploadTime = matchedAction.GetActivationTime();
                    newCommand.m_duration = matchedAction.GetDurationValue();
                    break;
                }
                i1 += 1;
            }

            // Rest of the command building logic...
            newCommand.m_actionOwnerName = actionOwnerName;
            newCommand.m_actionOwner = this.GetEntityID();
            newCommand.m_title = LocKeyToString(actionRecord.ObjectActionUI().Caption());
            newCommand.m_description = LocKeyToString(actionRecord.ObjectActionUI().Description());
            newCommand.m_icon = actionRecord.ObjectActionUI().CaptionIcon().TexturePartID().GetID();
            newCommand.m_iconCategory = actionRecord.GameplayCategory().IconName();
            newCommand.m_type = actionRecord.ObjectActionType().Type();
            newCommand.m_isInstant = false;
            newCommand.m_ICELevel = iceLVL;
            newCommand.m_ICELevelVisible = false;
            newCommand.m_actionState = EActionInactivityReson.Locked;
            newCommand.m_quality = playerQHacksList[i].quality;
            newCommand.m_costRaw = BaseScriptableAction.GetBaseCostStatic(playerRef, actionRecord);
            newCommand.m_category = actionRecord.HackCategory();
            newCommand.m_actionMatchesTarget = actionMatchDeck;

            // Replace your current if-else-if chain with this structure:

// Replace your current if-else-if chain with this structure:

// Check for NotAHack category first
if IsDefined(newCommand.m_category) && Equals(newCommand.m_category.EnumName(), n"NotAHack") {
    newCommand.m_isLocked = true;
    newCommand.m_inactiveReason = GetBlockedKey();
    newCommand.m_actionState = EActionInactivityReson.Locked;
} else {
    if actionMatchDeck && IsDefined(matchedAction) {
        newCommand.m_cost = matchedAction.GetCost();
        
        // FAST DUPLICATE CHECK - O(1) performance
        if ArrayContains(this.m_queuedActionIDs, matchedAction.GetObjectActionID()) {
            newCommand.m_isLocked = true;
            newCommand.m_inactiveReason = GetBlockedKey();
            newCommand.m_actionState = EActionInactivityReson.Locked;
            QueueModLog(n"DEBUG", n"QUEUE", s"Blocked duplicate: \(GetLocalizedText(newCommand.m_title))");
        } else {
            // Vanilla structure: Check IsInactive first
            if matchedAction.IsInactive() {
                newCommand.m_isLocked = true;
                newCommand.m_inactiveReason = matchedAction.GetInactiveReason();
                // newCommand.m_actionState stays as Locked (default from above)
                
                // Vanilla action assignment for inactive actions
                if this.HasActiveQuickHackUpload() {
                    newCommand.m_action = matchedAction;
                }
            } else {
                // Action is active - check RAM cost
                if !matchedAction.CanPayCost() {
                    newCommand.m_actionState = EActionInactivityReson.OutOfMemory;
                    newCommand.m_isLocked = true;
                    newCommand.m_inactiveReason = "LocKey#27398";
                }
                
                // REMOVED: Upload check - this is what queue mod handles
                
                // Set action reference using vanilla condition
                if !matchedAction.IsInactive() || this.HasActiveQuickHackUpload() {
                    newCommand.m_action = matchedAction;
                }
            }
        }
    } else {
        // No matching action on cyberdeck
        newCommand.m_isLocked = true;
        newCommand.m_inactiveReason = "LocKey#10943";
        newCommand.m_actionState = EActionInactivityReson.Invalid;
    }
}

// Set final state if not locked
if !newCommand.m_isLocked {
    newCommand.m_actionState = EActionInactivityReson.Ready;
}

            ArrayPush(commands, newCommand);
        }
        i += 1;
    }

    // Sync action states and sort
    let j: Int32 = 0;
    while j < ArraySize(commands) {
        if commands[j].m_isLocked && IsDefined(commands[j].m_action) {
            let puppetAction: ref<PuppetAction> = commands[j].m_action as PuppetAction;
            if IsDefined(puppetAction) {
                puppetAction.SetInactiveWithReason(false, commands[j].m_inactiveReason);
            }
        }
        j += 1;
    }

    QuickhackModule.SortCommandPriority(commands, this.GetGame());
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