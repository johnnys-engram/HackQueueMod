// ============================================================================
// QUICKHACK QUEUE MOD - v1.63 SIMPLIFIED VERSION
// Core issue: m_selectedData is null when ApplyQuickHack is called
// Solution: Wrap OnAction to intercept UI_ApplyAndClose before selection issues
// ============================================================================

// ============================================================================
// Core Queue Data Structure
// ============================================================================
class DeviceActionQueue {
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
    }

    public func LockQueue() -> Void {
        this.m_isQueueLocked = true;
    }

    public func UnlockQueue() -> Void {
        this.m_isQueueLocked = false;
    }
}

// ============================================================================
// Target Extensions
// ============================================================================

// ScriptedPuppet queue support
@addField(ScriptedPuppet)
private let m_deviceActionQueue: ref<DeviceActionQueue>;

@addMethod(ScriptedPuppet)
public func GetDeviceActionQueue() -> ref<DeviceActionQueue> {
    if !IsDefined(this.m_deviceActionQueue) {
        this.m_deviceActionQueue = new DeviceActionQueue();
    }
    return this.m_deviceActionQueue;
}

@addMethod(ScriptedPuppet)
public func IsActionQueueEnabled() -> Bool {
    return true;
}

@addMethod(ScriptedPuppet)
public func IsActionQueueFull() -> Bool {
    let queue: ref<DeviceActionQueue> = this.GetDeviceActionQueue();
    return IsDefined(queue) ? queue.GetQueueSize() >= 3 : false;
}

// Device queue support  
@addField(Device)
private let m_deviceActionQueue: ref<DeviceActionQueue>;

@addMethod(Device)
public func GetDeviceActionQueue() -> ref<DeviceActionQueue> {
    if !IsDefined(this.m_deviceActionQueue) {
        this.m_deviceActionQueue = new DeviceActionQueue();
    }
    return this.m_deviceActionQueue;
}

@addMethod(Device)
public func IsActionQueueEnabled() -> Bool {
    return true;
}

@addMethod(Device)
public func IsActionQueueFull() -> Bool {
    let queue: ref<DeviceActionQueue> = this.GetDeviceActionQueue();
    return IsDefined(queue) ? queue.GetQueueSize() >= 3 : false;
}

// ============================================================================
// FIXED: Intercept UI Action Before Selection Issues Occur
// ============================================================================

@wrapMethod(QuickhacksListGameController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    let actionName: CName = ListenerAction.GetName(action);
    let isMinigameActive: Bool = this.GetPlayerControlledObject().GetHudManager().IsHackingMinigameActive();
    
    // Only handle UI_ApplyAndClose when conditions are right
    if !isMinigameActive && !this.m_isUILocked && Equals(actionName, n"UI_ApplyAndClose") {
        LogChannel(n"DEBUG", "[QueueMod] *** UI_ApplyAndClose action intercepted ***");
        
        // Check if we should attempt queueing before calling normal logic
        if this.TryQueueCurrentAction() {
            return true; // Action handled by queue system
        }
        
        // Fall back to normal handling if queueing failed
        LogChannel(n"DEBUG", "[QueueMod] Queue attempt failed, proceeding normally");
    }
    
    return wrappedMethod(action, consumer);
}

@addMethod(QuickhacksListGameController)
private func TryQueueCurrentAction() -> Bool {
    // Get currently selected quickhack using the proven v1.63 pattern
    if !IsDefined(this.m_listController) {
        LogChannel(n"DEBUG", "[QueueMod] No list controller");
        return false;
    }
    
    let selectedIndex: Int32 = this.m_listController.GetSelectedIndex();
    if selectedIndex < 0 {
        LogChannel(n"DEBUG", s"[QueueMod] Invalid selection index: \(selectedIndex)");
        return false;
    }
    
    // Use the exact same pattern as the working v1.63 code: ( ( QuickhacksListItemController )( m_listController.GetItemAt( index ).GetController() ) )
    let quickhackController: QuickhacksListItemController = ( ( QuickhacksListItemController )( this.m_listController.GetItemAt( selectedIndex ).GetController() ) );
    if !IsDefined(quickhackController) {
        LogChannel(n"DEBUG", "[QueueMod] No quickhack controller");
        return false;
    }
    
    let currentData: ref<QuickhackData> = quickhackController.GetData() as QuickhackData;
    if !IsDefined(currentData) || !IsDefined(currentData.m_action) {
        LogChannel(n"DEBUG", "[QueueMod] No valid quickhack data at selection");
        return false;
    }
    
    LogChannel(n"DEBUG", s"[QueueMod] Found valid quickhack: \(currentData.m_title)");
    
    // Check if we have an active upload
    let hasActiveUpload: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance).IsStatPoolAdded(Cast<StatsObjectID>(GameInstance.GetPlayerSystem(this.m_gameInstance).GetLocalPlayerMainGameObject().GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    
    if !hasActiveUpload {
        LogChannel(n"DEBUG", "[QueueMod] No active upload - not queueing");
        return false;
    }
    
    // Check if action is locked
    if currentData.m_isLocked {
        LogChannel(n"DEBUG", "[QueueMod] Action is locked - not queueing");
        return false;
    }
    
    // Get target ID from the quickhack data
    let targetID: EntityID = currentData.m_actionOwner;
    if !EntityID.IsDefined(targetID) {
        LogChannel(n"DEBUG", "[QueueMod] No valid target ID");
        return false;
    }
    
    // Find target object
    let targetObject: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as GameObject;
    if !IsDefined(targetObject) {
        LogChannel(n"DEBUG", "[QueueMod] Cannot find target object");
        return false;
    }
    
    LogChannel(n"DEBUG", s"[QueueMod] Found target: \(targetObject.GetDisplayName())");
    
    // Get queue from target
    let queue: ref<DeviceActionQueue> = this.GetQueueFromTarget(targetObject);
    if !IsDefined(queue) {
        LogChannel(n"DEBUG", "[QueueMod] Target has no queue");
        return false;
    }
    
    // Check if queue is full
    let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
    let device: ref<Device> = targetObject as Device;
    let queueFull: Bool = false;
    
    if IsDefined(puppet) {
        queueFull = puppet.IsActionQueueFull();
    } else if IsDefined(device) {
        queueFull = device.IsActionQueueFull();
    }
    
    if queueFull {
        LogChannel(n"DEBUG", "[QueueMod] Queue is full - not queueing");
        return false;
    }
    
    // Queue the action!
    let wasQueued: Bool = queue.PutActionInQueue(currentData.m_action);
    if wasQueued {
        LogChannel(n"DEBUG", "[QueueMod] Successfully queued action!");
        
        // Apply cooldown and refresh UI  
        this.ApplyCooldownForQueue(currentData);
        this.RefreshUIAfterQueue();
        return true;
    } else {
        LogChannel(n"DEBUG", "[QueueMod] Failed to queue action");
        return false;
    }
}

@addMethod(QuickhacksListGameController)
private func GetQueueFromTarget(target: ref<GameObject>) -> ref<DeviceActionQueue> {
    // Try NPC first
    let puppet: ref<ScriptedPuppet> = target as ScriptedPuppet;
    if IsDefined(puppet) {
        LogChannel(n"DEBUG", "[QueueMod] Target is NPC");
        return puppet.GetDeviceActionQueue();
    }
    
    // Try Device
    let device: ref<Device> = target as Device;
    if IsDefined(device) {
        LogChannel(n"DEBUG", "[QueueMod] Target is Device");
        return device.GetDeviceActionQueue();
    }
    
    LogChannel(n"DEBUG", "[QueueMod] Unknown target type");
    return null;
}

@addMethod(QuickhacksListGameController)
private func ApplyCooldownForQueue(quickhackData: ref<QuickhackData>) -> Void {
    if !IsDefined(quickhackData) || quickhackData.m_cooldown <= 0.0 {
        return;
    }
    
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    
    if IsDefined(player) && TDBID.IsValid(quickhackData.m_cooldownTweak) {
        StatusEffectHelper.ApplyStatusEffect(player, quickhackData.m_cooldownTweak);
        LogChannel(n"DEBUG", s"[QueueMod] Applied cooldown: \(quickhackData.m_cooldown)s");
        this.RegisterCooldownStatPoolUpdate();
    }
}

@addMethod(QuickhacksListGameController)
private func RefreshUIAfterQueue() -> Void {
    if ArraySize(this.m_data) > 0 {
        this.PopulateData(this.m_data);
    }
    
    if IsDefined(this.m_listController) {
        this.m_listController.Refresh();
    }
    
    this.RegisterCooldownStatPoolUpdate();
}

// ============================================================================
// Queue Execution on Upload Complete
// ============================================================================

@wrapMethod(ScriptedPuppet)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    
    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) {
        if Equals(evt.progressBarType, EProgressBarType.UPLOAD) {
            if Equals(evt.state, EUploadProgramState.COMPLETED) {
                LogChannel(n"DEBUG", "[QueueMod] Upload completed on NPC, checking queue");
                
                let queue: ref<DeviceActionQueue> = this.GetDeviceActionQueue();
                if IsDefined(queue) && queue.GetQueueSize() > 0 {
                    let nextAction: ref<DeviceAction> = queue.PopActionInQueue();
                    if IsDefined(nextAction) {
                        LogChannel(n"DEBUG", "[QueueMod] Executing queued action on NPC");
                        
                        // Execute the action using the normal pipeline
                        let scriptableAction: ref<ScriptableDeviceAction> = nextAction as ScriptableDeviceAction;
                        if IsDefined(scriptableAction) {
                            scriptableAction.RegisterAsRequester(this.GetEntityID());
                            
                            // Use v1.63 execution method
                            let quickSlotCmd: ref<QuickSlotCommandUsed> = new QuickSlotCommandUsed();
                            quickSlotCmd.action = scriptableAction;
                            this.OnQuickSlotCommandUsed(quickSlotCmd);
                        }
                    }
                }
            }
        }
    }
    
    return result;
}

// Also handle device upload completion
@wrapMethod(Device)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    
    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) {
        if Equals(evt.progressBarType, EProgressBarType.UPLOAD) {
            if Equals(evt.state, EUploadProgramState.COMPLETED) {
                LogChannel(n"DEBUG", "[QueueMod] Upload completed on Device, checking queue");
                
                let queue: ref<DeviceActionQueue> = this.GetDeviceActionQueue();
                if IsDefined(queue) && queue.GetQueueSize() > 0 {
                    let nextAction: ref<DeviceAction> = queue.PopActionInQueue();
                    if IsDefined(nextAction) {
                        LogChannel(n"DEBUG", "[QueueMod] Executing queued action on Device");
                        
                        let scriptableAction: ref<ScriptableDeviceAction> = nextAction as ScriptableDeviceAction;
                        if IsDefined(scriptableAction) {
                            scriptableAction.RegisterAsRequester(this.GetEntityID());
                            scriptableAction.ProcessRPGAction(this.GetGame());
                        }
                    }
                }
            }
        }
    }
    
    return result;
}

// ============================================================================
// Optional: Allow queue when upload in progress (removes v1.63 blocking)
// ============================================================================

@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(puppetActions: array<ref<PuppetAction>>, out commands: array<ref<QuickhackData>>) -> Void {
    // Call vanilla method first
    wrappedMethod(puppetActions, commands);
    
    // Check if we have an ongoing upload
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame()).IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    
    if isOngoingUpload && this.IsActionQueueEnabled() && !this.IsActionQueueFull() {
        LogChannel(n"DEBUG", "[QueueMod] Unblocking quickhacks for queue on NPC");
        
        let i: Int32 = 0;
        while i < ArraySize(commands) {
            if IsDefined(commands[i]) && commands[i].m_isLocked && Equals(commands[i].m_inactiveReason, "LocKey#27398") {
                // Keep breach protocol blocked (maintain v1.63 behavior)
                if Equals(commands[i].m_type, gamedataObjectActionType.MinigameUpload) {
                    // Keep blocked
                } else if Equals(commands[i].m_type, gamedataObjectActionType.PuppetQuickHack) {
                    // Unblock regular quickhacks for queueing
                    commands[i].m_isLocked = false;
                    commands[i].m_inactiveReason = "";
                    commands[i].m_actionState = EActionInactivityReson.Ready;
                    LogChannel(n"DEBUG", s"[QueueMod] Unblocked quickhack for queue: \(commands[i].m_type)");
                }
            }
            i += 1;
        }
    }
}

@wrapMethod(Device)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
    let originalUploadState: Bool = this.m_isQhackUploadInProgerss;
    
    // Temporarily disable upload blocking if queue has space
    if originalUploadState && this.IsActionQueueEnabled() && !this.IsActionQueueFull() {
        LogChannel(n"DEBUG", s"[QueueMod] Bypassing upload block for device queue: \(this.GetDisplayName())");
        this.m_isQhackUploadInProgerss = false;
    }
    
    wrappedMethod(shouldOpen);
    
    // Restore original state
    this.m_isQhackUploadInProgerss = originalUploadState;
}