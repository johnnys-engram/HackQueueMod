// ============================================================================
// SIMPLE QUEUE FIX - Use UI target data directly, skip complex helper
// ============================================================================

// ============================================================================
// Core Queue Data Structure (Keep this - it works fine)
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
// Target Extensions (Keep these - they work)
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
    return true; // Simple - always enabled for now
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
// FIXED UI INTEGRATION - Use target data directly from UI
// ============================================================================

@wrapMethod(QuickhacksListGameController)
private func ApplyQuickHack() -> Bool {
    LogChannel(n"DEBUG", "[QueueMod] *** ApplyQuickHack called ***");
    
    if !IsDefined(this.m_selectedData) || !IsDefined(this.m_selectedData.m_action) {
        LogChannel(n"DEBUG", "[QueueMod] No selected data or action");
        return wrappedMethod();
    }
    
    // Check if we should queue this action
    let hasActiveUpload: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance).IsStatPoolAdded(Cast<StatsObjectID>(GameInstance.GetPlayerSystem(this.m_gameInstance).GetLocalPlayerMainGameObject().GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    
    if !hasActiveUpload {
        LogChannel(n"DEBUG", "[QueueMod] No active upload - executing normally");
        return wrappedMethod();
    }
    
    // Get target directly from UI data - this is the key fix!
    let targetID: EntityID = this.m_selectedData.m_actionOwner;
    if !EntityID.IsDefined(targetID) {
        LogChannel(n"DEBUG", "[QueueMod] No valid target ID");
        return wrappedMethod();
    }
    
    // Find target object
    let targetObject: ref<GameObject> = GameInstance.FindEntityByID(this.m_gameInstance, targetID) as GameObject;
    if !IsDefined(targetObject) {
        LogChannel(n"DEBUG", "[QueueMod] Cannot find target object");
        return wrappedMethod();
    }
    
    LogChannel(n"DEBUG", s"[QueueMod] Found target: \(targetObject.GetDisplayName())");
    
    // Get queue from target
    let queue: ref<DeviceActionQueue> = this.GetQueueFromTarget(targetObject);
    if !IsDefined(queue) {
        LogChannel(n"DEBUG", "[QueueMod] Target has no queue");
        return wrappedMethod();
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
        LogChannel(n"DEBUG", "[QueueMod] Queue is full - executing normally");
        return wrappedMethod();
    }
    
    // Queue the action!
    let wasQueued: Bool = queue.PutActionInQueue(this.m_selectedData.m_action);
    if wasQueued {
        LogChannel(n"DEBUG", "[QueueMod] Successfully queued action!");
        
        // Apply cooldown and refresh UI
        this.ApplyCooldownForQueue();
        this.RefreshUIAfterQueue();
        return true;
    } else {
        LogChannel(n"DEBUG", "[QueueMod] Failed to queue action");
        return wrappedMethod();
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
private func ApplyCooldownForQueue() -> Void {
    if !IsDefined(this.m_selectedData) || this.m_selectedData.m_cooldown <= 0.0 {
        return;
    }
    
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    
    if IsDefined(player) && TDBID.IsValid(this.m_selectedData.m_cooldownTweak) {
        StatusEffectHelper.ApplyStatusEffect(player, this.m_selectedData.m_cooldownTweak);
        LogChannel(n"DEBUG", s"[QueueMod] Applied cooldown: \(this.m_selectedData.m_cooldown)s");
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