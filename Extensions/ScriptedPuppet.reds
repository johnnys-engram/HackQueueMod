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

@addMethod(ScriptedPuppet)
public func QueueMod_SetActiveVanillaUpload(actionID: TweakDBID) -> Void {
    this.m_activeVanillaUploadID = actionID;
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
    
    if !isOngoingUpload || !this.IsQueueModEnabled() || this.IsQueueModFull() {
        wrappedMethod(puppetActions, commands);
    } else {
        this.BuildQuickHackCommandsForQueue(puppetActions, commands);  
    }
        QuickhackModule.RequestRefreshQuickhackMenu(this.GetGame(), this.GetEntityID());   
}

@addMethod(ScriptedPuppet)
private func BuildQuickHackCommandsForQueue(
    puppetActions: array<ref<PuppetAction>>, 
    out commands: array<ref<QuickhackData>>
) -> Void {
    let playerRef: ref<PlayerPuppet> = GetPlayer(this.GetGame());
    let actionOwnerName: CName = StringToName(this.GetTweakDBFullDisplayName(true));
    let iceLVL: Float = this.GetICELevel();
    let isBreached: Bool = this.IsBreached();
    let playerQHacksList: array<PlayerQuickhackData> = RPGManager.GetPlayerQuickHackListWithQuality(playerRef);
    let actionStartEffects: array<wref<ObjectActionEffect_Record>>;
    let actionCompletionEffects: array<wref<ObjectActionEffect_Record>>;
    let statModifiers: array<wref<StatModifier_Record>>;
    let prereqsToCheck: array<wref<IPrereq_Record>>;
    let targetActivePrereqs: array<wref<ObjectActionPrereq_Record>>;

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
            let interactionChoice: InteractionChoice;

            // Set basic properties first
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
            newCommand.m_networkBreached = isBreached;
            newCommand.m_category = actionRecord.HackCategory();

            // Get completion effects
            ArrayClear(actionCompletionEffects);
            actionRecord.CompletionEffects(actionCompletionEffects);
            newCommand.m_actionCompletionEffects = actionCompletionEffects;

            // Get cooldown info
            ArrayClear(actionStartEffects);
            actionRecord.StartEffects(actionStartEffects);
            let j: Int32 = 0;
            while j < ArraySize(actionStartEffects) {
                if Equals(actionStartEffects[j].StatusEffect().StatusEffectType().Type(), gamedataStatusEffectType.PlayerCooldown) {
                    actionStartEffects[j].StatusEffect().Duration().StatModifiers(statModifiers);
                    newCommand.m_cooldown = RPGManager.CalculateStatModifiers(statModifiers, this.GetGame(), playerRef, Cast<StatsObjectID>(playerRef.GetEntityID()), Cast<StatsObjectID>(playerRef.GetEntityID()));
                    newCommand.m_cooldownTweak = actionStartEffects[j].StatusEffect().GetID();
                    ArrayClear(statModifiers);
                    break; // Break after finding cooldown
                }
                j += 1;
            }
            ArrayClear(statModifiers);

            // Get duration
            newCommand.m_duration = this.GetQuickHackDuration(playerQHacksList[i].actionRecord, EntityGameInterface.GetEntity(this.GetEntity()) as GameObject, Cast<StatsObjectID>(this.GetEntityID()), playerRef.GetEntityID());

            // Find matching action
            let k: Int32 = 0;
            while k < ArraySize(puppetActions) {
                if Equals(actionRecord.ActionName(), puppetActions[k].GetObjectActionRecord().ActionName()) {
                    actionMatchDeck = true;
                    
                    if actionRecord.Priority() >= puppetActions[k].GetObjectActionRecord().Priority() {
                        puppetActions[k].SetObjectActionID(actionRecord.GetID());
                    }
                    
                    matchedAction = puppetActions[k];
                    newCommand.m_costRaw = puppetActions[k].GetBaseCost();
                    newCommand.m_cost = puppetActions[k].GetCost();
                    
                    // Check if action is possible and visible
                    if !puppetActions[k].IsPossible(this) || !puppetActions[k].IsVisible(playerRef) {
                        puppetActions[k].SetInactiveWithReason(false, "LocKey#7019");
                        break;
                    }
                    
                    newCommand.m_uploadTime = puppetActions[k].GetActivationTime();
                    interactionChoice = puppetActions[k].GetInteractionChoice();
                    
                    // Get title from interaction choice if available
                    let l: Int32 = 0;
                    while l < ArraySize(interactionChoice.captionParts.parts) {
                        if IsDefined(interactionChoice.captionParts.parts[l] as InteractionChoiceCaptionStringPart) {
                            newCommand.m_title = GetLocalizedText((interactionChoice.captionParts.parts[l] as InteractionChoiceCaptionStringPart).content);
                        }
                        l += 1;
                    }
                    
                    if puppetActions[k].IsInactive() {
                        break;
                    }
                    
                    // Check cost
                    if !puppetActions[k].CanPayCost() {
                        newCommand.m_actionState = EActionInactivityReson.OutOfMemory;
                        puppetActions[k].SetInactiveWithReason(false, "LocKey#27398");
                    }
                    
                    // Check target active prereqs
                    if actionRecord.GetTargetActivePrereqsCount() > 0 {
                        ArrayClear(targetActivePrereqs);
                        actionRecord.TargetActivePrereqs(targetActivePrereqs);
                        let m: Int32 = 0;
                        while m < ArraySize(targetActivePrereqs) {
                            ArrayClear(prereqsToCheck);
                            targetActivePrereqs[m].FailureConditionPrereq(prereqsToCheck);
                            if !RPGManager.CheckPrereqs(prereqsToCheck, this) {
                                puppetActions[k].SetInactiveWithReason(false, targetActivePrereqs[m].FailureExplanation());
                                break;
                            }
                            m += 1;
                        }
                    }
                    
                    break;
                }
                k += 1;
            }

            // Set final state based on matching and validation
            if !actionMatchDeck {
                newCommand.m_isLocked = true;
                newCommand.m_inactiveReason = "LocKey#10943";
                newCommand.m_actionState = EActionInactivityReson.Invalid;
            } else {
                if IsDefined(matchedAction) {
                    // Check for duplicates in queue
                    let actionID: TweakDBID = matchedAction.GetObjectActionID();
                    let isDuplicate: Bool = ArrayContains(this.m_queuedActionIDs, actionID);
                    
                    if isDuplicate {
                        newCommand.m_isLocked = true;
                        newCommand.m_inactiveReason = "LocKey#40765";
                        newCommand.m_actionState = EActionInactivityReson.Locked;
                        newCommand.m_action = matchedAction;
                    } 
                    else if TDBID.IsValid(newCommand.m_cooldownTweak) && 
                           StatusEffectSystem.ObjectHasStatusEffect(playerRef, newCommand.m_cooldownTweak) {
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
                            newCommand.m_actionState = EActionInactivityReson.Ready;
                            newCommand.m_action = matchedAction;
                        }
                    }
                } else {
                    newCommand.m_isLocked = true;
                    newCommand.m_inactiveReason = "LocKey#10943";
                    newCommand.m_actionState = EActionInactivityReson.Invalid;
                }
            }

            newCommand.m_actionMatchesTarget = actionMatchDeck;
            
            if !newCommand.m_isLocked {
                newCommand.m_actionState = EActionInactivityReson.Ready;
            }

            ArrayPush(commands, newCommand);
        }
        i += 1;
    }

    // Sync action states
    let n: Int32 = 0;
    while n < ArraySize(commands) {
        if commands[n].m_isLocked && IsDefined(commands[n].m_action) {
            let puppetAction: ref<PuppetAction> = commands[n].m_action as PuppetAction;
            if IsDefined(puppetAction) {
                puppetAction.SetInactiveWithReason(false, commands[n].m_inactiveReason);
            }
        }
        n += 1;
    }

    QuickhackModule.SortCommandPriority(commands, this.GetGame());
}

// =============================================================================
// Queue Execution on Upload Completion
// =============================================================================

// Add these fields to ScriptedPuppet
@addField(ScriptedPuppet)
private let m_hackingResistanceMod: ref<gameConstantStatModifierData>;

@addField(ScriptedPuppet)
private let m_mnemonicEffectsActive: Bool;

@wrapMethod(ScriptedPuppet)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    QueueModLog(n"DEBUG", n"QUICKHACK", s"OnUploadProgressStateChanged: \(evt.state)");
    
    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) && 
       Equals(evt.progressBarType, EProgressBarType.UPLOAD) {
        
        if !ScriptedPuppet.IsActive(this) {
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                queue.ClearQueue(this.GetGame(), this.GetEntityID());
                QueueModLog(n"DEBUG", n"QUICKHACK", "Target inactive - queue cleared");
            }
            return result;
        }
        
        // MNEMONIC: Apply on upload START
        if Equals(evt.state, EUploadProgramState.STARTED) && !this.m_mnemonicEffectsActive {
            let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
            if IsDefined(player) {
                let playerID: EntityID = player.GetEntityID();
                
                // Apply mnemonic resistance reduction
                let value: Float = GameInstance.GetStatsSystem(this.GetGame())
                    .GetStatValue(Cast<StatsObjectID>(playerID), gamedataStatType.LowerHackingResistanceOnHack);
                
                if value > 0.00 {
                    this.m_hackingResistanceMod = new gameConstantStatModifierData();
                    this.m_hackingResistanceMod.statType = gamedataStatType.HackingResistance;
                    this.m_hackingResistanceMod.modifierType = gameStatModifierType.Additive;
                    this.m_hackingResistanceMod.value = value * -1.00;
                    GameInstance.GetStatsSystem(this.GetGame()).AddModifier(Cast<StatsObjectID>(this.GetEntityID()), this.m_hackingResistanceMod);
                    QueueModLog(n"DEBUG", n"QUICKHACK", s"Applied mnemonic resistance: -\(value)");
                }
                                
                this.m_mnemonicEffectsActive = true;
            }
        }
        
        // Only process queue/cache for COMPLETED uploads (target is alive)
        if Equals(evt.state, EUploadProgramState.COMPLETED) {
            // MNEMONIC: Remove on upload COMPLETE
            if this.m_mnemonicEffectsActive {
                if IsDefined(this.m_hackingResistanceMod) {
                    GameInstance.GetStatsSystem(this.GetGame()).RemoveModifier(Cast<StatsObjectID>(this.GetEntityID()), this.m_hackingResistanceMod);
                    this.m_hackingResistanceMod = null;
                    QueueModLog(n"DEBUG", n"QUICKHACK", "Removed mnemonic resistance");
                }
                
                this.m_mnemonicEffectsActive = false;
            }
            
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

    if !ScriptedPuppet.IsActive(this) {
        let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
        if IsDefined(queue) && queue.GetQueueSize() > 0 {
            queue.ClearQueue(this.GetGame(), this.GetEntityID());
            QueueModLog(n"DEBUG", n"QUICKHACK", "Target inactive - queue cleared");
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
            QueueModLog(n"DEBUG", n"QUICKHACK", s"Processing PuppetAction RPG for target: \(GetLocalizedText(this.GetDisplayName()))");
            paExec.ProcessRPGAction(this.GetGame());
            
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
        let effectType: gamedataStatusEffectType = evt.staticData.StatusEffectType().Type();
        
        // Check for death, unconscious, or defeated status effects using proper types
        if Equals(effectType, gamedataStatusEffectType.Unconscious) ||
           Equals(effectType, gamedataStatusEffectType.Defeated) ||
           Equals(effectType, gamedataStatusEffectType.DefeatedWithRecover) {
            
            let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
            if IsDefined(queue) && queue.GetQueueSize() > 0 {
                queue.ClearQueue(this.GetGame(), this.GetEntityID());
                QueueModLog(n"DEBUG", n"EVENTS", s"Queue cleared on status effect: \(ToString(effectType))");
            }
        }
    }
    return result;
}