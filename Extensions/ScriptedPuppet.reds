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
// SCRIPTED PUPPET EXTENSIONS
// =============================================================================

@addField(ScriptedPuppet)
private let m_activeVanillaUploadID: TweakDBID;

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
    }
}

@addMethod(ScriptedPuppet)
public func QueueMod_RemoveFromCache(actionID: TweakDBID) -> Void {
    if TDBID.IsValid(actionID) {
        ArrayRemove(this.m_queuedActionIDs, actionID);
    }
}

@addMethod(ScriptedPuppet)
public func QueueMod_ClearCache() -> Void {
    ArrayClear(this.m_queuedActionIDs);
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
        wrappedMethod(puppetActions, commands);
    } else {
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
    let actionStartEffects: array<wref<ObjectActionEffect_Record>>;
    let statModifiers: array<wref<StatModifier_Record>>;

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
        
        if Equals(actionRecord.ObjectActionType().Type(), gamedataObjectActionType.PuppetQuickHack) {
            let newCommand: ref<QuickhackData> = new QuickhackData();
            let actionMatchDeck: Bool = false;
            let matchedAction: ref<PuppetAction>;

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

            // Get cooldown info
            ArrayClear(actionStartEffects);
            actionRecord.StartEffects(actionStartEffects);
            let i1: Int32 = 0;
            while i1 < ArraySize(actionStartEffects) {
                if Equals(actionStartEffects[i1].StatusEffect().StatusEffectType().Type(), gamedataStatusEffectType.PlayerCooldown) {
                    actionStartEffects[i1].StatusEffect().Duration().StatModifiers(statModifiers);
                    newCommand.m_cooldown = RPGManager.CalculateStatModifiers(statModifiers, this.GetGame(), playerRef, Cast<StatsObjectID>(playerRef.GetEntityID()), Cast<StatsObjectID>(playerRef.GetEntityID()));
                    newCommand.m_cooldownTweak = actionStartEffects[i1].StatusEffect().GetID();
                    ArrayClear(statModifiers);
                }
                if newCommand.m_cooldown != 0.00 {
                    break;
                }
                i1 += 1;
            }
            ArrayClear(statModifiers);

            // Set basic properties
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
            
            // State logic
            if IsDefined(newCommand.m_category) && Equals(newCommand.m_category.EnumName(), n"NotAHack") {
                newCommand.m_isLocked = true;
                newCommand.m_inactiveReason = "LocKey#40765";
                newCommand.m_actionState = EActionInactivityReson.Locked;
            } else {
                if actionMatchDeck && IsDefined(matchedAction) {
                    newCommand.m_cost = matchedAction.GetCost();
                    
                    let actionID: TweakDBID = matchedAction.GetObjectActionID();
                    let isDuplicate: Bool = ArrayContains(this.m_queuedActionIDs, actionID);
                    
                    if isDuplicate {
                        newCommand.m_isLocked = true;
                        newCommand.m_inactiveReason = "LocKey#40765";
                        newCommand.m_actionState = EActionInactivityReson.Locked;
                        newCommand.m_action = matchedAction;
                    } 
                    else if newCommand.m_cooldown > 0.00 && StatusEffectSystem.ObjectHasStatusEffect(playerRef, newCommand.m_cooldownTweak) {
                        newCommand.m_isLocked = true;
                        newCommand.m_inactiveReason = "LocKey#27399";
                        newCommand.m_actionState = EActionInactivityReson.Locked;
                        newCommand.m_action = matchedAction;
                    } 
                    else {
                        if matchedAction.IsInactive() {
                            newCommand.m_isLocked = true;
                            newCommand.m_inactiveReason = matchedAction.GetInactiveReason();
                            newCommand.m_actionState = EActionInactivityReson.Locked;
                            newCommand.m_action = matchedAction;
                        } else {
                            if !matchedAction.CanPayCost() {
                                newCommand.m_actionState = EActionInactivityReson.OutOfMemory;
                                newCommand.m_isLocked = true;
                                newCommand.m_inactiveReason = "LocKey#27398";
                                newCommand.m_action = matchedAction;
                            } else {
                                newCommand.m_actionState = EActionInactivityReson.Ready;
                                newCommand.m_action = matchedAction;
                            }
                        }
                    }
                } else {
                    newCommand.m_isLocked = true;
                    newCommand.m_inactiveReason = "LocKey#10943";
                    newCommand.m_actionState = EActionInactivityReson.Invalid;
                }
            }

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

    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) && 
       Equals(evt.progressBarType, EProgressBarType.UPLOAD) {
        
        // Death check first - clear queue immediately for any upload state
        if this.IsDead() || 
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") ||
           StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
            
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                queue.ClearQueue(this.GetGame(), this.GetEntityID());
                QueueModLog(n"DEBUG", n"QUICKHACK", "Target dead - queue cleared");
            }
            return result;
        }
        
        // Only process queue/cache for COMPLETED uploads (target is alive)
        if Equals(evt.state, EUploadProgramState.COMPLETED) {
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                let entry: ref<QueueModEntry> = queue.PopNextEntry();
                if IsDefined(entry) {
                    QueueModLog(n"DEBUG", n"QUICKHACK", s"Upload complete for NPC=\(GetLocalizedText(this.GetDisplayName())) processing queue");
                    this.ExecuteQueuedEntry(entry);
                }
            } else {
                // UNIFIED CLEANUP: Remove completed vanilla action
                if TDBID.IsValid(this.m_activeVanillaUploadID) {
                    this.QueueMod_RemoveFromCache(this.m_activeVanillaUploadID);
                    this.m_activeVanillaUploadID = TDBID.None();
                    QueueModLog(n"DEBUG", n"CACHE", "Vanilla upload completed - removed from cache");
                }
            }
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

    if !IsDefined(this) || this.IsDead() || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Dead") || StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"Unconscious") {
        QueueModLog(n"DEBUG", n"QUICKHACK", "Target invalid/dead/unconscious - clearing queue");
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) {
            queue.ClearQueue(this.GetGame(), this.GetEntityID());
        }
        return;
    }

    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.GetGame());
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        QueueModLog(n"ERROR", n"QUICKHACK", "Cannot find player for quickhack execution");
        return;
    }

    if Equals(entry.entryType, GetActionEntryType()) && IsDefined(entry.action) {
        QueueModLog(n"DEBUG", n"QUICKHACK", s"Executing queued action: class=\(entry.action.GetClassName()) on NPC=\(GetLocalizedText(this.GetDisplayName()))");
        
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
            paExec.RegisterAsRequester(this.GetEntityID());
            paExec.SetExecutor(player);
            
            this.GetQueueModActionQueue().LockQueue();
            
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Processing PuppetAction RPG for target: \(GetLocalizedText(this.GetDisplayName()))");
            paExec.ProcessRPGAction(this.GetGame());

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