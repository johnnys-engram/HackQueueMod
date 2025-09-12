// =============================================================================
// CP2077 v1.63 Hack Queue Mod – CLEAN v1.63 IMPLEMENTATION (+ UI persistence fix)
// =============================================================================

// =============================================================================
// Core Queue Data Structure
// =============================================================================
public class QueueModActionQueue {
    private let m_actionQueue: array<ref<DeviceAction>>;
    private let m_isQueueLocked: Bool;

    public func PutActionInQueue(action: ref<DeviceAction>) -> Bool {
        if !IsDefined(action) || this.m_isQueueLocked {
            return false;
        }
        ArrayPush(this.m_actionQueue, action);
        LogChannel(n"DEBUG", s"[QueueMod] Added action to queue. Size now: \(this.GetQueueSize())");
        return true;
    }

    public func PopActionInQueue() -> ref<DeviceAction> {
        if ArraySize(this.m_actionQueue) > 0 {
            let nextAction: ref<DeviceAction> = this.m_actionQueue[0];
            ArrayErase(this.m_actionQueue, 0);
            LogChannel(n"DEBUG", s"[QueueMod] Popped action from queue. Size now: \(this.GetQueueSize())");
            return nextAction;
        }
        return null;
    }

    public func GetQueueSize() -> Int32 {
        return ArraySize(this.m_actionQueue);
    }

    public func ClearQueue() -> Void {
        ArrayClear(this.m_actionQueue);
        LogChannel(n"DEBUG", "[QueueMod] Queue cleared");
    }

    public func LockQueue() -> Void {
        this.m_isQueueLocked = true;
    }

    public func UnlockQueue() -> Void {
        this.m_isQueueLocked = false;
    }
}

// =============================================================================
// Core Queue Helper System
// =============================================================================
public class QueueModHelper {

    public func PutInQuickHackQueue(action: ref<DeviceAction>) -> Bool {
        LogChannel(n"DEBUG", "[QueueMod] *** QUEUE SYSTEM ACTIVATED ***");
        if !IsDefined(action) {
            LogChannel(n"DEBUG", "[QueueMod] No action provided to queue");
            return false;
        }

        LogChannel(n"DEBUG", s"[QueueMod] Attempting to queue action: \(action.GetClassName())");

        // Try ScriptableDeviceAction first (for Devices)
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            LogChannel(n"DEBUG", "[QueueMod] Queueing ScriptableDeviceAction");
            return sa.QueueModQuickHack(action);
        }

        // Try PuppetAction (for NPCs)
        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            LogChannel(n"DEBUG", "[QueueMod] Queueing PuppetAction");
            return this.QueueActionOnPuppet(pa);
        }

        LogChannel(n"DEBUG", "[QueueMod] Unknown action type - cannot queue");
        return false;
    }

    public func QueueActionOnPuppet(puppetAction: ref<PuppetAction>) -> Bool {
        if !IsDefined(puppetAction) {
            return false;
        }

        let targetID: EntityID = puppetAction.GetRequesterID();
        let gameInstance: GameInstance = puppetAction.GetExecutor().GetGame();
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;

        if !IsDefined(targetObject) {
            LogChannel(n"DEBUG", "[QueueMod] Cannot find target object for puppet action");
            return false;
        }

        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if !IsDefined(puppet) {
            LogChannel(n"DEBUG", "[QueueMod] Target is not a ScriptedPuppet");
            return false;
        }

        let queue: ref<QueueModActionQueue> = puppet.GetQueueModActionQueue();
        if IsDefined(queue) {
            LogChannel(n"DEBUG", "[QueueMod] Successfully queued PuppetAction");
            return queue.PutActionInQueue(puppetAction);
        }

        LogChannel(n"DEBUG", "[QueueMod] Puppet has no queue");
        return false;
    }

    public func GetQueueSize(action: ref<DeviceAction>) -> Int32 {
        if !IsDefined(action) {
            return 0;
        }

        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let q = sa.GetQueueModActionQueue();
            return IsDefined(q) ? q.GetQueueSize() : 0;
        }

        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            return this.GetPuppetQueueSize(pa);
        }

        return 0;
    }

    public func GetPuppetQueueSize(puppetAction: ref<PuppetAction>) -> Int32 {
        if !IsDefined(puppetAction) {
            return 0;
        }

        let targetID: EntityID = puppetAction.GetRequesterID();
        let gameInstance: GameInstance = puppetAction.GetExecutor().GetGame();
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;

        if !IsDefined(targetObject) {
            return 0;
        }

        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if !IsDefined(puppet) {
            return 0;
        }

        let queue: ref<QueueModActionQueue> = puppet.GetQueueModActionQueue();
        return IsDefined(queue) ? queue.GetQueueSize() : 0;
    }
}

// =============================================================================
// ScriptableDeviceAction Extensions - Using unique method names
// =============================================================================
@addField(ScriptableDeviceAction)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(ScriptableDeviceAction)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
    }
    return this.m_queueModActionQueue;
}

@addMethod(ScriptableDeviceAction)
public func QueueModQuickHack(action: ref<DeviceAction>) -> Bool {
    if !IsDefined(action) {
        return false;
    }
    LogChannel(n"DEBUG", "[QueueMod] ScriptableDeviceAction.QueueModQuickHack called");
    return this.GetQueueModActionQueue().PutActionInQueue(action);
}

@addMethod(ScriptableDeviceAction)
public func GetQueueModSize() -> Int32 {
    let q: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    return IsDefined(q) ? q.GetQueueSize() : 0;
}

// =============================================================================
// Device Extensions - Using unique method names
// =============================================================================
@addField(Device)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(Device)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
    }
    return this.m_queueModActionQueue;
}

@addMethod(Device)
public func IsQueueModEnabled() -> Bool {
    return true;
}

@addMethod(Device)
public func IsQueueModFull() -> Bool {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return false;
    }

    let queueSize: Int32 = queue.GetQueueSize();
    let isFull: Bool = queueSize >= 3;

    if queueSize > 0 {
        LogChannel(n"DEBUG", s"[QueueMod] Device queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

// =============================================================================
// Device SendQuickhackCommands Wrapper
// =============================================================================
@wrapMethod(Device)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
    let originalUploadState: Bool = this.m_isQhackUploadInProgerss;

    if originalUploadState {
        let queueEnabled: Bool = this.IsQueueModEnabled();
        let queueFull: Bool = this.IsQueueModFull();

        if queueEnabled && !queueFull {
            LogChannel(n"DEBUG", s"[QueueMod] Device bypassing upload block for queue (device: \(this.GetDisplayName()))");
            this.m_isQhackUploadInProgerss = false;
        }
    }

    wrappedMethod(shouldOpen);
    this.m_isQhackUploadInProgerss = originalUploadState;
}

// =============================================================================
// ScriptedPuppet Extensions - Using unique method names
// =============================================================================
@addField(ScriptedPuppet)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(ScriptedPuppet)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
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
        LogChannel(n"DEBUG", s"[QueueMod] NPC queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

// =============================================================================
// ScriptedPuppet TranslateChoicesIntoQuickSlotCommands Wrapper - v1.63 syntax
// =============================================================================
@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(puppetActions: array<ref<PuppetAction>>, out commands: array<ref<QuickhackData>>) -> Void {
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame()).IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);

    // Call vanilla first for normal v1.63 behavior
    wrappedMethod(puppetActions, commands);

    // Only intervene when there's an active upload
    if isOngoingUpload {
        let queueEnabled: Bool = this.IsQueueModEnabled();
        let queueFull: Bool = this.IsQueueModFull();

        LogChannel(n"DEBUG", s"[QueueMod] NPC upload detected - queue enabled: \(queueEnabled), queue full: \(queueFull)");

        if queueEnabled && !queueFull {
            LogChannel(n"DEBUG", s"[QueueMod] NPC selective unblocking for queue (NPC: \(this.GetDisplayName()))");

            let i: Int32 = 0;
            let commandsSize: Int32 = ArraySize(commands);
            while i < commandsSize {
                if IsDefined(commands[i]) && commands[i].m_isLocked && Equals(commands[i].m_inactiveReason, "LocKey#27398") {
                    if Equals(commands[i].m_type, gamedataObjectActionType.PuppetQuickHack) || Equals(commands[i].m_type, gamedataObjectActionType.MinigameUpload) {
                        commands[i].m_isLocked = false;
                        commands[i].m_inactiveReason = "";
                        commands[i].m_actionState = EActionInactivityReson.Ready;

                        if Equals(commands[i].m_type, gamedataObjectActionType.PuppetQuickHack) {
                            LogChannel(n"DEBUG", s"[QueueMod] Unblocked quickhack for queue: \(commands[i].m_type)");
                        } else {
                            LogChannel(n"DEBUG", s"[QueueMod] Preserved breach protocol access: \(commands[i].m_type)");
                        }
                    }
                }
                i += 1;
            }
        } else {
            // Preserve breach protocol even if queue disabled/full
            LogChannel(n"DEBUG", "[QueueMod] Queue full/disabled - preserving breach protocol only");

            let i2: Int32 = 0;
            let commandsSize2: Int32 = ArraySize(commands);
            while i2 < commandsSize2 {
                if IsDefined(commands[i2]) && commands[i2].m_isLocked && Equals(commands[i2].m_inactiveReason, "LocKey#27398") && Equals(commands[i2].m_type, gamedataObjectActionType.MinigameUpload) {
                    commands[i2].m_isLocked = false;
                    commands[i2].m_inactiveReason = "";
                    commands[i2].m_actionState = EActionInactivityReson.Ready;
                    LogChannel(n"DEBUG", "[QueueMod] Preserved breach protocol (queue full)");
                }
                i2 += 1;
            }
        }
    }
}

// =============================================================================
// ScriptedPuppet OnUploadProgressStateChanged Wrapper - v1.63 syntax
// =============================================================================
@wrapMethod(ScriptedPuppet)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);

    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) {
        if Equals(evt.progressBarType, EProgressBarType.UPLOAD) {
            if Equals(evt.state, EUploadProgramState.COMPLETED) {
                LogChannel(n"DEBUG", "[QueueMod] Upload completed, checking for queued actions");

                let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
                if IsDefined(queue) && queue.GetQueueSize() > 0 {
                    let nextAction: ref<DeviceAction> = queue.PopActionInQueue();
                    if IsDefined(nextAction) {
                        LogChannel(n"DEBUG", "[QueueMod] Executing next queued action on NPC");

                        let scriptableAction: ref<ScriptableDeviceAction> = nextAction as ScriptableDeviceAction;
                        if IsDefined(scriptableAction) {
                            scriptableAction.RegisterAsRequester(this.GetEntityID());
                            let quickSlotCmd: ref<QuickSlotCommandUsed> = new QuickSlotCommandUsed();
                            quickSlotCmd.action = scriptableAction;
                            this.OnQuickSlotCommandUsed(quickSlotCmd);
                        }
                    }
                } else {
                    LogChannel(n"DEBUG", "[QueueMod] No queued actions to execute");
                }
            }
        }
    }

    return result;
}

// =============================================================================
// PlayerPuppet Integration
// =============================================================================
@addField(PlayerPuppet)
private let m_queueModHelper: ref<QueueModHelper>;

@addMethod(PlayerPuppet)
public func GetQueueModHelper() -> ref<QueueModHelper> {
    if !IsDefined(this.m_queueModHelper) {
        this.m_queueModHelper = new QueueModHelper();
        LogChannel(n"DEBUG", "[QueueMod] Player loaded - queue system ready");
    }
    return this.m_queueModHelper;
}

// =============================================================================
// UI Integration – QuickhacksListGameController (with UI DATA PERSISTENCE FIX)
// =============================================================================
@addField(QuickhacksListGameController)
private let m_queueModActionCache: array<ref<QuickhackData>>;

@addField(QuickhacksListGameController)
private let m_queueModLastValidAction: ref<QuickhackData>;

@addMethod(QuickhacksListGameController)
private func CacheQueueModAction(data: ref<QuickhackData>) -> Void {
    if !IsDefined(data) || !IsDefined(data.m_action) {
        return;
    }
    this.m_queueModLastValidAction = data;
    ArrayPush(this.m_queueModActionCache, data);
    if ArraySize(this.m_queueModActionCache) > 5 {
        ArrayErase(this.m_queueModActionCache, 0);
    }
    LogChannel(n"DEBUG", s"[QueueMod] Cached action: \(GetLocalizedText(data.m_title))");
}

@addMethod(QuickhacksListGameController)
private func GetValidQueueModAction() -> ref<QuickhackData> {
    if IsDefined(this.m_selectedData) && IsDefined(this.m_selectedData.m_action) {
        this.CacheQueueModAction(this.m_selectedData);
        return this.m_selectedData;
    }
    if IsDefined(this.m_queueModLastValidAction) && IsDefined(this.m_queueModLastValidAction.m_action) {
        LogChannel(n"DEBUG", "[QueueMod] Using cached action fallback");
        return this.m_queueModLastValidAction;
    }
    let i: Int32 = ArraySize(this.m_queueModActionCache) - 1;
    while i >= 0 {
        let cachedData = this.m_queueModActionCache[i];
        if IsDefined(cachedData) && IsDefined(cachedData.m_action) {
            LogChannel(n"DEBUG", "[QueueMod] Using cache search fallback");
            return cachedData;
        }
        i -= 1;
    }
    return null;
}

@addMethod(QuickhacksListGameController)
private func IsQuickHackCurrentlyUploading() -> Bool {
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        return false;
    }
    let hasUploadPool: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance).IsStatPoolAdded(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    return hasUploadPool;
}

@addMethod(QuickhacksListGameController)
private func CleanupQueueModCache() -> Void {
    let validCache: array<ref<QuickhackData>>;
    let i: Int32 = 0;
    while i < ArraySize(this.m_queueModActionCache) {
        let entry = this.m_queueModActionCache[i];
        if IsDefined(entry) && IsDefined(entry.m_action) {
            ArrayPush(validCache, entry);
        }
        i += 1;
    }
    this.m_queueModActionCache = validCache;
}

// MAIN ApplyQuickHack wrapper with persistence-aware version
@wrapMethod(QuickhacksListGameController)
private func ApplyQuickHack() -> Bool {
    LogChannel(n"DEBUG", "[QueueMod] *** ApplyQuickHack called ***");

    let actionData: ref<QuickhackData> = this.GetValidQueueModAction();

    if !IsDefined(actionData) {
        LogChannel(n"DEBUG", "[QueueMod] No valid action data available - executing normally");
        return wrappedMethod();
    }

    if !IsDefined(actionData.m_action) {
        LogChannel(n"DEBUG", "[QueueMod] Action reference is null - executing normally");
        return wrappedMethod();
    }

    let actionName: String = GetLocalizedText(actionData.m_title);
    LogChannel(n"DEBUG", s"[QueueMod] ApplyQuickHack for: \(actionName)");

    let shouldQueue: Bool = this.IsQuickHackCurrentlyUploading();
    LogChannel(n"DEBUG", s"[QueueMod] Should queue: \(shouldQueue)");

    if shouldQueue {
        LogChannel(n"DEBUG", s"[QueueMod] Attempting to queue quickhack: \(actionName)");

        this.CacheQueueModAction(actionData);

        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;

        if IsDefined(player) {
            let queueHelper: ref<QueueModHelper> = player.GetQueueModHelper();
            if IsDefined(queueHelper) {
                let wasQueued: Bool = queueHelper.PutInQuickHackQueue(actionData.m_action);
                if wasQueued {
                    LogChannel(n"DEBUG", "[QueueMod] Action successfully queued");
                    this.ApplyQueueModCooldownWithData(actionData);
                    this.RefreshQueueModUI();
                    return true;
                } else {
                    LogChannel(n"DEBUG", "[QueueMod] Failed to queue - executing normally");
                }
            }
        }
    }

    LogChannel(n"DEBUG", "[QueueMod] Executing action normally");
    return wrappedMethod();
}

// Cooldown method with data-param version
@addMethod(QuickhacksListGameController)
private func ApplyQueueModCooldownWithData(data: ref<QuickhackData>) -> Void {
    if !IsDefined(data) || data.m_cooldown <= 0.0 {
        return;
    }

    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;

    if IsDefined(player) && TDBID.IsValid(data.m_cooldownTweak) {
        StatusEffectHelper.ApplyStatusEffect(player, data.m_cooldownTweak);
        LogChannel(n"DEBUG", s"[QueueMod] Applied cooldown: \(data.m_cooldown)s");
        this.RegisterCooldownStatPoolUpdate();
    }
}

// Cleanup method to be called manually when needed
@addMethod(QuickhacksListGameController)
private func InitializeQueueModCache() -> Void {
    if ArraySize(this.m_queueModActionCache) == 0 {
        ArrayClear(this.m_queueModActionCache);
        this.m_queueModLastValidAction = null;
        LogChannel(n"DEBUG", "[QueueMod] Cache initialized");
    }
}

// Manual cache management - called when selection changes
@addMethod(QuickhacksListGameController)
private func OnQueueModSelectionChange() -> Void {
    if IsDefined(this.m_selectedData) && IsDefined(this.m_selectedData.m_action) {
        this.CacheQueueModAction(this.m_selectedData);
    }
}

// UI refresh method
@addMethod(QuickhacksListGameController)
private func RefreshQueueModUI() -> Void {
    if ArraySize(this.m_data) > 0 {
        this.PopulateData(this.m_data);
    }
    if IsDefined(this.m_listController) {
        this.m_listController.Refresh();
    }
    this.RegisterCooldownStatPoolUpdate();
}