// HackQueue_UploadBypass.reds
module HackQueueMod

@replaceMethod(ScriptedPuppet)
private final func TranslateChoicesIntoQuickSlotCommands(puppetActions: array<ref<PuppetAction>>, out commands: array<ref<QuickhackData>>) -> Void {
    let actionCompletionEffects: array<wref<ObjectActionEffect_Record>>;
    let actionMatchDeck: Bool;
    let actionRecord: wref<ObjectAction_Record>;
    let actionStartEffects: array<wref<ObjectActionEffect_Record>>;
    let i: Int32;
    let i1: Int32;
    let i2: Int32;
    let interactionChoice: InteractionChoice;
    let newCommand: ref<QuickhackData>;
    let prereqsToCheck: array<wref<IPrereq_Record>>;
    let statModifiers: array<wref<StatModifier_Record>>;
    let targetActivePrereqs: array<wref<ObjectActionPrereq_Record>>;
    let playerRef: ref<PlayerPuppet> = GetPlayer(this.GetGame());
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame()).IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    let iceLVL: Float = this.GetICELevel();
    let actionOwnerName: CName = StringToName(this.GetTweakDBFullDisplayName(true));
    let isBreached: Bool = this.IsBreached();
    let playerQHacksList: array<PlayerQuickhackData> = RPGManager.GetPlayerQuickHackListWithQuality(playerRef);
    
    if ArraySize(playerQHacksList) == 0 {
        newCommand = new QuickhackData();
        newCommand.m_title = "LocKey#42171";
        newCommand.m_isLocked = true;
        newCommand.m_actionOwnerName = actionOwnerName;
        newCommand.m_actionState = EActionInactivityReson.Invalid;
        newCommand.m_description = "LocKey#42172";
        ArrayPush(commands, newCommand);
    } else {
        i = 0;
        while i < ArraySize(playerQHacksList) {
            newCommand = new QuickhackData();
            ArrayClear(actionStartEffects);
            actionRecord = playerQHacksList[i].actionRecord;
            if NotEquals(actionRecord.ObjectActionType().Type(), gamedataObjectActionType.PuppetQuickHack) {
            } else {
                newCommand.m_actionOwnerName = actionOwnerName;
                newCommand.m_title = LocKeyToString(actionRecord.ObjectActionUI().Caption());
                newCommand.m_description = LocKeyToString(actionRecord.ObjectActionUI().Description());
                newCommand.m_icon = actionRecord.ObjectActionUI().CaptionIcon().TexturePartID().GetID();
                newCommand.m_iconCategory = actionRecord.GameplayCategory().IconName();
                newCommand.m_type = actionRecord.ObjectActionType().Type();
                newCommand.m_actionOwner = this.GetEntityID();
                newCommand.m_isInstant = false;
                newCommand.m_ICELevel = iceLVL;
                newCommand.m_ICELevelVisible = true;
                newCommand.m_actionState = EActionInactivityReson.Locked;
                newCommand.m_quality = playerQHacksList[i].quality;
                newCommand.m_costRaw = BaseScriptableAction.GetBaseCostStatic(playerRef, actionRecord);
                newCommand.m_networkBreached = isBreached;
                newCommand.m_category = actionRecord.HackCategory();
                ArrayClear(actionCompletionEffects);
                actionRecord.CompletionEffects(actionCompletionEffects);
                newCommand.m_actionCompletionEffects = actionCompletionEffects;
                actionRecord.StartEffects(actionStartEffects);
                i1 = 0;
                while i1 < ArraySize(actionStartEffects) {
                    if Equals(actionStartEffects[i1].StatusEffect().StatusEffectType().Type(), gamedataStatusEffectType.PlayerCooldown) {
                        actionStartEffects[i1].StatusEffect().Duration().StatModifiers(statModifiers);
                        newCommand.m_cooldown = RPGManager.CalculateStatModifiers(statModifiers, this.GetGame(), playerRef, Cast<StatsObjectID>(playerRef.GetEntityID()), Cast<StatsObjectID>(playerRef.GetEntityID()));
                        newCommand.m_cooldownTweak = actionStartEffects[i1].StatusEffect().GetID();
                        ArrayClear(statModifiers);
                    };
                    if newCommand.m_cooldown != 0.00 {
                        break;
                    };
                    i1 += 1;
                };
                ArrayClear(statModifiers);
                newCommand.m_duration = this.GetQuickHackDuration(playerQHacksList[i].actionRecord, EntityGameInterface.GetEntity(this.GetEntity()) as GameObject, Cast<StatsObjectID>(this.GetEntityID()), playerRef.GetEntityID());
                actionMatchDeck = false;
                i1 = 0;
                while i1 < ArraySize(puppetActions) {
                    if Equals(actionRecord.ActionName(), puppetActions[i1].GetObjectActionRecord().ActionName()) {
                        actionMatchDeck = true;
                        if actionRecord.Priority() >= puppetActions[i1].GetObjectActionRecord().Priority() {
                            puppetActions[i1].SetObjectActionID(actionRecord.GetID());
                        };
                        newCommand.m_costRaw = puppetActions[i1].GetBaseCost();
                        newCommand.m_cost = puppetActions[i1].GetCost();
                        if !puppetActions[i1].IsPossible(this) || !puppetActions[i1].IsVisible(playerRef) {
                            puppetActions[i1].SetInactiveWithReason(false, "LocKey#7019");
                            break;
                        };
                        newCommand.m_uploadTime = puppetActions[i1].GetActivationTime();
                        interactionChoice = puppetActions[i1].GetInteractionChoice();
                        i2 = 0;
                        while i2 < ArraySize(interactionChoice.captionParts.parts) {
                            if IsDefined(interactionChoice.captionParts.parts[i2] as InteractionChoiceCaptionStringPart) {
                                newCommand.m_title = GetLocalizedText((interactionChoice.captionParts.parts[i2] as InteractionChoiceCaptionStringPart).content);
                            };
                            i2 += 1;
                        };
                        if puppetActions[i1].IsInactive() {
                            break;
                        };
                        if !puppetActions[i1].CanPayCost() {
                            newCommand.m_actionState = EActionInactivityReson.OutOfMemory;
                            puppetActions[i1].SetInactiveWithReason(false, "LocKey#27398");
                        };
                        if actionRecord.GetTargetActivePrereqsCount() > 0 {
                            ArrayClear(targetActivePrereqs);
                            actionRecord.TargetActivePrereqs(targetActivePrereqs);
                            i2 = 0;
                            while i2 < ArraySize(targetActivePrereqs) {
                                ArrayClear(prereqsToCheck);
                                targetActivePrereqs[i2].FailureConditionPrereq(prereqsToCheck);
                                if !RPGManager.CheckPrereqs(prereqsToCheck, this) {
                                    puppetActions[i1].SetInactiveWithReason(false, targetActivePrereqs[i2].FailureExplanation());
                                    break;
                                };
                                i2 += 1;
                            };
                        };
                        
                        // MODIFICATION: Removed the upload blocking check
                        // Original line was: if isOngoingUpload { puppetActions[i1].SetInactiveWithReason(false, "LocKey#7020"); };
                        
                        break;
                    };
                    i1 += 1;
                };
                if !actionMatchDeck {
                    newCommand.m_isLocked = true;
                    newCommand.m_inactiveReason = "LocKey#10943";
                } else {
                    if puppetActions[i1].IsInactive() {
                        newCommand.m_isLocked = true;
                        newCommand.m_inactiveReason = puppetActions[i1].GetInactiveReason();
                    } else {
                        newCommand.m_actionState = EActionInactivityReson.Ready;
                        newCommand.m_action = puppetActions[i1];
                    };
                };
                newCommand.m_actionMatchesTarget = actionMatchDeck;
                ArrayPush(commands, newCommand);
            };
            i += 1;
        };
    };
    i = 0;
    while i < ArraySize(commands) {
        if commands[i].m_isLocked && IsDefined(commands[i].m_action) {
            (commands[i].m_action as PuppetAction).SetInactiveWithReason(false, commands[i].m_inactiveReason);
        };
        i += 1;
    };
    QuickhackModule.SortCommandPriority(commands, this.GetGame());
}