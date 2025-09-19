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

    QueueModLog(n"DEBUG", n"QUEUE", s"=== BUILDING QUEUE COMMANDS FOR \(GetLocalizedText(this.GetDisplayName())) ===");
    QueueModLog(n"DEBUG", n"QUEUE", s"Available quickhacks: \(ArraySize(playerQHacksList)), puppet actions: \(ArraySize(puppetActions))");

    if ArraySize(playerQHacksList) == 0 {
        let newCommand: ref<QuickhackData> = new QuickhackData();
        newCommand.m_title = "LocKey#42171";
        newCommand.m_isLocked = true;
        newCommand.m_actionOwnerName = actionOwnerName;
        newCommand.m_actionState = EActionInactivityReson.Invalid;
        newCommand.m_description = "LocKey#42172";
        ArrayPush(commands, newCommand);
        QueueModLog(n"DEBUG", n"QUEUE", "No quickhacks available - added empty command");
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
            let hackTitle: String = LocKeyToString(actionRecord.ObjectActionUI().Caption());

            QueueModLog(n"DEBUG", n"QUEUE", s"--- Processing quickhack #\(i): \(hackTitle) ---");
            QueueModLog(n"DEBUG", n"QUEUE", s"Action name: \(ToString(actionRecord.ActionName()))");

            // Set basic properties first
            newCommand.m_actionOwnerName = actionOwnerName;
            newCommand.m_actionOwner = this.GetEntityID();
            newCommand.m_title = hackTitle;
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
            QueueModLog(n"DEBUG", n"QUEUE", s"Checking \(ArraySize(actionStartEffects)) start effects for cooldown");
            let j: Int32 = 0;
            while j < ArraySize(actionStartEffects) {
                if Equals(actionStartEffects[j].StatusEffect().StatusEffectType().Type(), gamedataStatusEffectType.PlayerCooldown) {
                    actionStartEffects[j].StatusEffect().Duration().StatModifiers(statModifiers);
                    newCommand.m_cooldown = RPGManager.CalculateStatModifiers(statModifiers, this.GetGame(), playerRef, Cast<StatsObjectID>(playerRef.GetEntityID()), Cast<StatsObjectID>(playerRef.GetEntityID()));
                    newCommand.m_cooldownTweak = actionStartEffects[j].StatusEffect().GetID();
                    QueueModLog(n"DEBUG", n"QUEUE", s"Found cooldown: \(newCommand.m_cooldown)s, tweak: \(TDBID.ToStringDEBUG(newCommand.m_cooldownTweak))");
                    ArrayClear(statModifiers);
                    break; // Break after finding cooldown
                }
                j += 1;
            }
            if newCommand.m_cooldown == 0.00 {
                QueueModLog(n"DEBUG", n"QUEUE", "No cooldown found for this quickhack");
            }
            ArrayClear(statModifiers);

            // Get duration
            newCommand.m_duration = this.GetQuickHackDuration(playerQHacksList[i].actionRecord, EntityGameInterface.GetEntity(this.GetEntity()) as GameObject, Cast<StatsObjectID>(this.GetEntityID()), playerRef.GetEntityID());

            // Find matching action
            QueueModLog(n"DEBUG", n"QUEUE", s"Searching for matching action in \(ArraySize(puppetActions)) puppet actions");
            let k: Int32 = 0;
            while k < ArraySize(puppetActions) {
                if Equals(actionRecord.ActionName(), puppetActions[k].GetObjectActionRecord().ActionName()) {
                    actionMatchDeck = true;
                    QueueModLog(n"DEBUG", n"QUEUE", s"MATCH FOUND: Action \(ToString(actionRecord.ActionName())) at index \(k)");
                    
                    if actionRecord.Priority() >= puppetActions[k].GetObjectActionRecord().Priority() {
                        puppetActions[k].SetObjectActionID(actionRecord.GetID());
                        QueueModLog(n"DEBUG", n"QUEUE", "Updated puppet action with higher priority action record");
                    }
                    
                    matchedAction = puppetActions[k];
                    newCommand.m_costRaw = puppetActions[k].GetBaseCost();
                    newCommand.m_cost = puppetActions[k].GetCost();
                    QueueModLog(n"DEBUG", n"QUEUE", s"Costs: raw=\(newCommand.m_costRaw), final=\(newCommand.m_cost)");
                    
                    // Check if action is possible and visible
                    if !puppetActions[k].IsPossible(this) || !puppetActions[k].IsVisible(playerRef) {
                        puppetActions[k].SetInactiveWithReason(false, "LocKey#7019");
                        QueueModLog(n"DEBUG", n"QUEUE", "Action not possible or not visible - marked inactive");
                        break;
                    }
                    
                    newCommand.m_uploadTime = puppetActions[k].GetActivationTime();
                    interactionChoice = puppetActions[k].GetInteractionChoice();
                    QueueModLog(n"DEBUG", n"QUEUE", s"Upload time: \(newCommand.m_uploadTime)s");
                    
                    // Get title from interaction choice if available
                    let l: Int32 = 0;
                    while l < ArraySize(interactionChoice.captionParts.parts) {
                        if IsDefined(interactionChoice.captionParts.parts[l] as InteractionChoiceCaptionStringPart) {
                            newCommand.m_title = GetLocalizedText((interactionChoice.captionParts.parts[l] as InteractionChoiceCaptionStringPart).content);
                            QueueModLog(n"DEBUG", n"QUEUE", s"Updated title from interaction: \(newCommand.m_title)");
                        }
                        l += 1;
                    }
                    
                    if puppetActions[k].IsInactive() {
                        QueueModLog(n"DEBUG", n"QUEUE", "Puppet action is inactive - breaking");
                        break;
                    }
                    
                    // Check cost
                    if !puppetActions[k].CanPayCost() {
                        newCommand.m_actionState = EActionInactivityReson.OutOfMemory;
                        puppetActions[k].SetInactiveWithReason(false, "LocKey#27398");
                        QueueModLog(n"DEBUG", n"QUEUE", "Cannot pay cost - marked as out of memory");
                    }
                    
                    // Check target active prereqs - BUT SKIP UPLOAD-RELATED ONES FOR QUEUE
                    if actionRecord.GetTargetActivePrereqsCount() > 0 {
                        QueueModLog(n"DEBUG", n"QUEUE", s"Checking \(actionRecord.GetTargetActivePrereqsCount()) target active prereqs");
                        ArrayClear(targetActivePrereqs);
                        actionRecord.TargetActivePrereqs(targetActivePrereqs);
                        let m: Int32 = 0;
                        while m < ArraySize(targetActivePrereqs) {
                            ArrayClear(prereqsToCheck);
                            targetActivePrereqs[m].FailureConditionPrereq(prereqsToCheck);
                            
                            let prereqID: TweakDBID = targetActivePrereqs[m].GetID();
                            let failureText: String = GetLocalizedText(targetActivePrereqs[m].FailureExplanation());
                            QueueModLog(n"DEBUG", n"QUEUE", s"Prereq ID: \(TDBID.ToStringDEBUG(prereqID)) | Failure: \(failureText)");
                            
                            // QUEUE FIX: Skip the upload prereq that blocks queueing
                            if Equals(prereqID, t"Prereqs.QuickHackUploadingPrereq") {
                                QueueModLog(n"DEBUG", n"QUEUE", s"SKIPPING upload prereq: \(TDBID.ToStringDEBUG(prereqID))");
                            } else {
                                if !RPGManager.CheckPrereqs(prereqsToCheck, this) {
                                    puppetActions[k].SetInactiveWithReason(false, targetActivePrereqs[m].FailureExplanation());
                                    QueueModLog(n"DEBUG", n"QUEUE", s"Prereq failed: \(failureText)");
                                    break;
                                }
                            }
                            m += 1;
                        }
                    }
                    
                    break;
                }
                k += 1;
            }
            
            // Set final state based on matching and validation
            QueueModLog(n"DEBUG", n"QUEUE", "=== STATE ASSIGNMENT LOGIC ===");
                        // State logic
            if IsDefined(newCommand.m_category) && Equals(newCommand.m_category.EnumName(), n"NotAHack") {
                newCommand.m_isLocked = true;
                newCommand.m_inactiveReason = "LocKey#40765";
                newCommand.m_actionState = EActionInactivityReson.Locked;
            } 
            if !actionMatchDeck {
                newCommand.m_isLocked = true;
                newCommand.m_inactiveReason = "LocKey#10943";
                newCommand.m_actionState = EActionInactivityReson.Invalid;
                QueueModLog(n"DEBUG", n"QUEUE", "FINAL STATE: LOCKED (no deck match) - Invalid");
            } else {
                if IsDefined(matchedAction) {
                    // Check for duplicates in queue
                    let actionID: TweakDBID = matchedAction.GetObjectActionID();
                    let isDuplicate: Bool = ArrayContains(this.m_queuedActionIDs, actionID);
                    
                    QueueModLog(n"DEBUG", n"QUEUE", s"Action ID: \(TDBID.ToStringDEBUG(actionID))");
                    QueueModLog(n"DEBUG", n"QUEUE", s"Checking duplicates in cache (size: \(ArraySize(this.m_queuedActionIDs)))");
                    QueueModLog(n"DEBUG", n"QUEUE", s"Is duplicate: \(isDuplicate)");
                    
                    if isDuplicate {
                        newCommand.m_isLocked = true;
                        newCommand.m_inactiveReason = "LocKey#40765";
                        newCommand.m_actionState = EActionInactivityReson.Locked;
                        newCommand.m_action = matchedAction;
                        QueueModLog(n"DEBUG", n"QUEUE", "FINAL STATE: LOCKED (duplicate in queue) - Locked");
                    } 
                    else {
                        // Check cooldown status
                        let hasCooldownTweak: Bool = TDBID.IsValid(newCommand.m_cooldownTweak);
                        let isOnCooldown: Bool = false;
                        
                        if hasCooldownTweak {
                            isOnCooldown = StatusEffectSystem.ObjectHasStatusEffect(playerRef, newCommand.m_cooldownTweak);
                            QueueModLog(n"DEBUG", n"QUEUE", s"Cooldown tweak valid: \(hasCooldownTweak)");
                            QueueModLog(n"DEBUG", n"QUEUE", s"Player has cooldown effect: \(isOnCooldown)");
                            QueueModLog(n"DEBUG", n"QUEUE", s"Cooldown tweak ID: \(TDBID.ToStringDEBUG(newCommand.m_cooldownTweak))");
                        } else {
                            QueueModLog(n"DEBUG", n"QUEUE", "No valid cooldown tweak - skipping cooldown check");
                        }
                        
                        if hasCooldownTweak && isOnCooldown {
                            newCommand.m_isLocked = true;
                            newCommand.m_inactiveReason = "LocKey#27399";
                            newCommand.m_actionState = EActionInactivityReson.Locked;
                            newCommand.m_action = matchedAction;
                            QueueModLog(n"DEBUG", n"QUEUE", "FINAL STATE: LOCKED (on cooldown) - Locked");
                        } 
                        else {
                            if matchedAction.IsInactive() {
                                newCommand.m_isLocked = true;
                                newCommand.m_inactiveReason = matchedAction.GetInactiveReason();
                                newCommand.m_actionState = EActionInactivityReson.Locked;
                                newCommand.m_action = matchedAction;
                                QueueModLog(n"DEBUG", n"QUEUE", s"FINAL STATE: LOCKED (action inactive) - reason: \(GetLocalizedText(matchedAction.GetInactiveReason()))");
                            } else {
                                newCommand.m_actionState = EActionInactivityReson.Ready;
                                newCommand.m_action = matchedAction;
                                QueueModLog(n"DEBUG", n"QUEUE", "FINAL STATE: READY - Available for queueing");
                            }
                        }
                    }
                } else {
                    newCommand.m_isLocked = true;
                    newCommand.m_inactiveReason = "LocKey#10943";
                    newCommand.m_actionState = EActionInactivityReson.Invalid;
                    QueueModLog(n"DEBUG", n"QUEUE", "FINAL STATE: LOCKED (no matched action) - Invalid");
                }
            }

            newCommand.m_actionMatchesTarget = actionMatchDeck;
            
            if !newCommand.m_isLocked {
                newCommand.m_actionState = EActionInactivityReson.Ready;
                QueueModLog(n"DEBUG", n"QUEUE", "State override: Setting to Ready (not locked)");
            }

            QueueModLog(n"DEBUG", n"QUEUE", s"Command summary - Title: \(newCommand.m_title), Locked: \(newCommand.m_isLocked), State: \(newCommand.m_actionState), Reason: \(GetLocalizedText(newCommand.m_inactiveReason))");
            ArrayPush(commands, newCommand);
        } else {
            QueueModLog(n"DEBUG", n"QUEUE", s"Skipping non-puppet quickhack: \(LocKeyToString(actionRecord.ObjectActionUI().Caption()))");
        }
        i += 1;
    }

    // Sync action states
    QueueModLog(n"DEBUG", n"QUEUE", "=== SYNCING ACTION STATES ===");
    let n: Int32 = 0;
    while n < ArraySize(commands) {
        if commands[n].m_isLocked && IsDefined(commands[n].m_action) {
            let puppetAction: ref<PuppetAction> = commands[n].m_action as PuppetAction;
            if IsDefined(puppetAction) {
                puppetAction.SetInactiveWithReason(false, commands[n].m_inactiveReason);
                QueueModLog(n"DEBUG", n"QUEUE", s"Synced action state for \(commands[n].m_title): inactive with reason \(GetLocalizedText(commands[n].m_inactiveReason))");
            }
        }
        n += 1;
    }
// Add this right before QuickhackModule.SortCommandPriority(commands, this.GetGame());
QueueModLog(n"DEBUG", n"QUEUE", "=== PRE-SORT COMMAND DATA ===");
let debugIndex: Int32 = 0;
while debugIndex < ArraySize(commands) {
    QueueModLog(n"DEBUG", n"QUEUE", s"[\(debugIndex)] \(commands[debugIndex].m_title)");
    QueueModLog(n"DEBUG", n"QUEUE", s"  State: \(commands[debugIndex].m_actionState), Locked: \(commands[debugIndex].m_isLocked)");
    QueueModLog(n"DEBUG", n"QUEUE", s"  Cost: \(commands[debugIndex].m_cost), Quality: \(commands[debugIndex].m_quality)");
    if IsDefined(commands[debugIndex].m_action) {
        let action: ref<PuppetAction> = commands[debugIndex].m_action as PuppetAction;
        if IsDefined(action) {
            QueueModLog(n"DEBUG", n"QUEUE", s"  Action Priority: \(action.GetObjectActionRecord().Priority())");
        }
    }
    debugIndex += 1;
}
    QueueModLog(n"DEBUG", n"QUEUE", s"Sorting \(ArraySize(commands)) commands by priority");
    QuickhackModule.SortCommandPriority(commands, this.GetGame());
    QueueModLog(n"DEBUG", n"QUEUE", s"=== QUEUE BUILD COMPLETE FOR \(GetLocalizedText(this.GetDisplayName())) ===");
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