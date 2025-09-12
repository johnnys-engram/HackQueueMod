// ============================================================================
// CP2077 v1.63 Hack Queue Mod v4 - COMPLETE ANNOTATED VERSION
// Full source attribution and folder structure documentation
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
        LogChannel(n"DEBUG", "[QueueMod] Queue cleared");
    }

    public func LockQueue() -> Void {
        this.m_isQueueLocked = true;
    }

    public func UnlockQueue() -> Void {
        this.m_isQueueLocked = false;
    }
}

// ============================================================================
// Core Queue Helper System
// ============================================================================
class QuickHackableQueueHelper {

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
            return sa.QueueQuickHack(action);
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
        
        let queue: ref<DeviceActionQueue> = puppet.GetDeviceActionQueue();
        if IsDefined(queue) {
            LogChannel(n"DEBUG", "[QueueMod] Successfully queued PuppetAction");
            return queue.PutActionInQueue(puppetAction);
        }
        
        LogChannel(n"DEBUG", "[QueueMod] Puppet has no queue");
        return false;
    }

    public func PopFromQuickHackQueue(action: ref<DeviceAction>) -> ref<DeviceAction> {
        if !IsDefined(action) {
            return null;
        }
        
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let q = sa.GetDeviceActionQueue();
            return IsDefined(q) ? q.PopActionInQueue() : null;
        }
        
        let pa: ref<PuppetAction> = action as PuppetAction;
        if IsDefined(pa) {
            return this.PopFromPuppetQueue(pa);
        }
        
        return null;
    }
    
    public func PopFromPuppetQueue(puppetAction: ref<PuppetAction>) -> ref<DeviceAction> {
        if !IsDefined(puppetAction) {
            return null;
        }
        
        let targetID: EntityID = puppetAction.GetRequesterID();
        let gameInstance: GameInstance = puppetAction.GetExecutor().GetGame();
        let targetObject: ref<GameObject> = GameInstance.FindEntityByID(gameInstance, targetID) as GameObject;
        
        if !IsDefined(targetObject) {
            return null;
        }
        
        let puppet: ref<ScriptedPuppet> = targetObject as ScriptedPuppet;
        if !IsDefined(puppet) {
            return null;
        }
        
        let queue: ref<DeviceActionQueue> = puppet.GetDeviceActionQueue();
        return IsDefined(queue) ? queue.PopActionInQueue() : null;
    }

    public func GetQueueSize(action: ref<DeviceAction>) -> Int32 {
        if !IsDefined(action) {
            return 0;
        }
        
        let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
        if IsDefined(sa) {
            let q = sa.GetDeviceActionQueue();
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
        
        let queue: ref<DeviceActionQueue> = puppet.GetDeviceActionQueue();
        return IsDefined(queue) ? queue.GetQueueSize() : 0;
    }
}

// ============================================================================
// GameObject Base Extensions
// Source: tools/redmod/scripts/core/gameObject.script (was .ws in v1.63)
// Changes: cyberpunk_changes_1.63_to_2.0_minified.txt shows .ws -> .script renames
// Added in v2.0 for queue system - base class for Device and ScriptedPuppet
// ============================================================================
@addField(GameObject)
private let m_currentlyUploadingAction: ref<ScriptableDeviceAction>;

@addMethod(GameObject)
public func GetCurrentlyUploadingAction() -> ref<ScriptableDeviceAction> {
    return this.m_currentlyUploadingAction;
}

@addMethod(GameObject)
public func SetCurrentlyUploadingAction(action: ref<ScriptableDeviceAction>) -> Void {
    this.m_currentlyUploadingAction = action;
}

// ============================================================================
// ScriptableDeviceAction Extensions
// Source: tools/redmod/scripts/cyberpunk/actions/ (inferred from action system)
// Project files: deviceBase_v163_vs_v20.unified_minified.diff shows ProcessRPGAction changes
// Added in v2.0 for queue support
// ============================================================================
@addField(ScriptableDeviceAction)
private let m_deviceActionQueue: ref<DeviceActionQueue>;

@addMethod(ScriptableDeviceAction)
public func GetDeviceActionQueue() -> ref<DeviceActionQueue> {
    if !IsDefined(this.m_deviceActionQueue) {
        this.m_deviceActionQueue = new DeviceActionQueue();
    }
    return this.m_deviceActionQueue;
}

@addMethod(ScriptableDeviceAction)
public func QueueQuickHack(action: ref<DeviceAction>) -> Bool {
    if !IsDefined(action) {
        return false;
    }
    LogChannel(n"DEBUG", "[QueueMod] ScriptableDeviceAction.QueueQuickHack called");
    return this.GetDeviceActionQueue().PutActionInQueue(action);
}

@addMethod(ScriptableDeviceAction)
public func GetQuickHackQueueSize() -> Int32 {
    let q: ref<DeviceActionQueue> = this.GetDeviceActionQueue();
    return IsDefined(q) ? q.GetQueueSize() : 0;
}

// ============================================================================
// Device Extensions  
// Source: tools/redmod/scripts/cyberpunk/devices/deviceBase.script
// Project files: deviceBase_v1.63_minified.script, deviceBase_v163_vs_v20.unified_minified.diff
// Original SendQuickhackCommands exists in Device class hierarchy
// ============================================================================
@addField(Device)
private let m_currentlyUploadingAction: wref<ScriptableDeviceAction>;

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

// ============================================================================
// Device SendQuickhackCommands Wrapper
// Source: tools/redmod/scripts/cyberpunk/devices/deviceBase.script  
// Original method: Device.SendQuickhackCommands() - exists in Device hierarchy
// Project files: deviceBase_v163_vs_v20.unified_minified.diff
// Purpose: Bypass upload blocking for devices when queue has space
// ============================================================================
@wrapMethod(Device)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
    let originalUploadState: Bool = this.m_isQhackUploadInProgerss;
    
    if originalUploadState {
        let queueEnabled: Bool = this.IsActionQueueEnabled();
        let queueFull: Bool = this.IsActionQueueFull();
        
        if queueEnabled && !queueFull {
            LogChannel(n"DEBUG", s"[QueueMod] Device bypassing upload block for queue (device: \(this.GetDisplayName()))");
            this.m_isQhackUploadInProgerss = false;
        }
    }
    
    wrappedMethod(shouldOpen);
    this.m_isQhackUploadInProgerss = originalUploadState;
}

// ============================================================================
// ScriptedPuppet Extensions (PRIMARY FOCUS - NPCs)
// Source: tools/redmod/scripts/cyberpunk/player/scriptedPuppet.script
// Project files: scriptedPuppet_v1.63_minified.script, scriptedPuppet_1.61_to_2.0_minified.diff  
// This is the main target - NPC queue system
// ============================================================================
@addField(ScriptedPuppet)
private let m_currentlyUploadingAction: wref<ScriptableDeviceAction>;

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

// ============================================================================
// ScriptedPuppet TranslateChoicesIntoQuickSlotCommands Wrapper - CRITICAL NPC METHOD
// Source: tools/redmod/scripts/cyberpunk/player/scriptedPuppet.script
// Project files: scriptedPuppet_v1.63_minified.script, scriptedPuppet_1.61_to_2.0_minified.diff
// Original v1.63: private func TranslateChoicesIntoQuickSlotCommands(puppetActions: array<ref<PuppetAction>>, out commands: array<ref<QuickhackData>>)
// v2.0 changes: Added queue system integration and selective blocking logic
// Purpose: Restore v1.63 breach protocol blocking behavior while allowing quickhack queueing
// ============================================================================
@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(puppetActions: array<ref<PuppetAction>>, out commands: array<ref<QuickhackData>>) -> Void {
    let isOngoingUpload: Bool = GameInstance.GetStatPoolsSystem(this.GetGame()).IsStatPoolAdded(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    
    // Always call vanilla method first to get normal v1.63 blocking behavior
    wrappedMethod(puppetActions, commands);
    
    // Apply v1.63-compatible queue modifications
    if isOngoingUpload {
        let queueEnabled: Bool = this.IsActionQueueEnabled();
        let queueFull: Bool = this.IsActionQueueFull();
        
        // Only modify when queue is enabled and has space
        if queueEnabled && !queueFull {
            LogChannel(n"DEBUG", s"[QueueMod] NPC selective unblocking for queue (NPC: \(this.GetDisplayName()))");
            
            let i: Int32 = 0;
            let commandsSize: Int32 = ArraySize(commands);
            while i < commandsSize {
                if IsDefined(commands[i]) && commands[i].m_isLocked && Equals(commands[i].m_inactiveReason, "LocKey#27398") {
                    
                    // Restore v1.63 behavior: Breach Protocol (MinigameUpload) ALWAYS stays blocked
                    if Equals(commands[i].m_type, gamedataObjectActionType.MinigameUpload) {
                        // Keep blocked - this is correct v1.63 behavior
                        LogChannel(n"DEBUG", "[QueueMod] Keeping breach protocol blocked (v1.63 behavior)");
                    }
                    // Only unblock actual quickhacks for queueing
                    else if Equals(commands[i].m_type, gamedataObjectActionType.DeviceQuickHack) || 
                             Equals(commands[i].m_type, gamedataObjectActionType.PuppetQuickHack) {
                        
                        commands[i].m_isLocked = false;
                        commands[i].m_inactiveReason = "";
                        commands[i].m_actionState = EActionInactivityReson.Ready;
                        LogChannel(n"DEBUG", s"[QueueMod] Unblocked quickhack for queue: \(commands[i].m_type)");
                    }
                }
                i += 1;
            }
        } else {
            LogChannel(n"DEBUG", "[QueueMod] Queue full or disabled - using vanilla v1.63 blocking");
        }
    }
}

// ============================================================================
// ScriptedPuppet OnUploadProgressStateChanged Wrapper
// Source: tools/redmod/scripts/cyberpunk/player/scriptedPuppet.script  
// Project files: scriptedPuppet_v1.63_minified.script, gameplayRoleComponent_v1.63_minified.script
// Original v1.63: protected event OnUploadProgressStateChanged(evt: UploadProgramProgressEvent) {} - EMPTY
// v2.0 changes: Added queue execution logic when upload completes
// Purpose: Auto-execute next queued action when current upload finishes
// ============================================================================
@wrapMethod(ScriptedPuppet)
protected cb func OnUploadProgressStateChanged(evt: ref<UploadProgramProgressEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    
    // Handle queue execution when quickhack upload completes
    if Equals(evt.progressBarContext, EProgressBarContext.QuickHack) {
        if Equals(evt.progressBarType, EProgressBarType.UPLOAD) {
            if Equals(evt.state, EUploadProgramState.COMPLETED) {
                
                LogChannel(n"DEBUG", "[QueueMod] Upload completed, checking for queued actions");
                
                let queue: ref<DeviceActionQueue> = this.GetDeviceActionQueue();
                if IsDefined(queue) && queue.GetQueueSize() > 0 {
                    
                    let nextAction: ref<DeviceAction> = queue.PopActionInQueue();
                    if IsDefined(nextAction) {
                        LogChannel(n"DEBUG", "[QueueMod] Executing next queued action on NPC");
                        
                        let scriptableAction: ref<ScriptableDeviceAction> = nextAction as ScriptableDeviceAction;
                        if IsDefined(scriptableAction) {
                            // Execute the queued action
                            scriptableAction.RegisterAsRequester(this.GetEntityID());
                            
                            // Use v1.63 compatible execution - no GameplayRoleComponent parameter
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

// ============================================================================
// PlayerPuppet Integration
// Source: tools/redmod/scripts/cyberpunk/player/playerPuppet.script (inferred)
// Purpose: Provide queue helper access for UI integration
// ============================================================================
@addField(PlayerPuppet)
private let m_queueHelper: ref<QuickHackableQueueHelper>;

@addMethod(PlayerPuppet)
public func GetQueueHelper() -> ref<QuickHackableQueueHelper> {
    if !IsDefined(this.m_queueHelper) {
        this.m_queueHelper = new QuickHackableQueueHelper();
        LogChannel(n"DEBUG", "[QueueMod] Player loaded - queue system ready");
    }
    return this.m_queueHelper;
}

// ============================================================================
// UI Integration - QuickhacksListGameController 
// Source: tools/redmod/scripts/cyberpunk/UI/quickhacks/quickhacksListGameController.script
// Project files: quickhacks_v1.63_minified.script
// Original v1.63: private function ApplyQuickHack() -> Bool - exists in UI controller
// Purpose: Detect when to queue actions vs execute normally
// ============================================================================
@wrapMethod(QuickhacksListGameController)
private func ApplyQuickHack() -> Bool {
    LogChannel(n"DEBUG", "[QueueMod] *** ApplyQuickHack called ***");
    
    if !IsDefined(this.m_selectedData) {
        LogChannel(n"DEBUG", "[QueueMod] No selected data - UI state issue");
        return wrappedMethod();
    }
    
    if !IsDefined(this.m_selectedData.m_action) {
        LogChannel(n"DEBUG", "[QueueMod] No action in selected data - UI state issue");
        return wrappedMethod();
    }
    
    // Get readable action name using localization
    let actionName: String = GetLocalizedText(this.m_selectedData.m_title);
    LogChannel(n"DEBUG", s"[QueueMod] ApplyQuickHack for: \(actionName)");
    
    // Check if we should queue this action
    let shouldQueue: Bool = this.ShouldQueueAction(this.m_selectedData);
    LogChannel(n"DEBUG", s"[QueueMod] Should queue: \(shouldQueue)");
    
    if shouldQueue {
        LogChannel(n"DEBUG", s"[QueueMod] Attempting to queue quickhack: \(actionName)");
        
        // Get player and queue helper
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        
        if IsDefined(player) {
            let queueHelper: ref<QuickHackableQueueHelper> = player.GetQueueHelper();
            if IsDefined(queueHelper) {
                let wasQueued: Bool = queueHelper.PutInQuickHackQueue(this.m_selectedData.m_action);
                
                if wasQueued {
                    LogChannel(n"DEBUG", "[QueueMod] Action successfully queued");
                    this.ApplyCooldownForQueue();
                    this.RefreshUIAfterQueue();
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

@addMethod(QuickhacksListGameController)
private func ShouldQueueAction(data: ref<QuickhackData>) -> Bool {
    if !IsDefined(data) || !IsDefined(data.m_action) {
        return false;
    }
    
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(this.m_gameInstance);
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    
    if !IsDefined(player) {
        return false;
    }
    
    let hasActiveUpload: Bool = GameInstance.GetStatPoolsSystem(this.m_gameInstance).IsStatPoolAdded(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.QuickHackUpload);
    
    return hasActiveUpload;
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
// WRAPPER METHOD SUMMARY AND SOURCES
// ============================================================================
/*
COMPLETE WRAPPER ANALYSIS:

1. @wrapMethod(Device) SendQuickhackCommands
   Source: tools/redmod/scripts/cyberpunk/devices/deviceBase.script
   Files: deviceBase_v1.63_minified.script, deviceBase_v163_vs_v20.unified_minified.diff
   
2. @wrapMethod(ScriptedPuppet) TranslateChoicesIntoQuickSlotCommands
   Source: tools/redmod/scripts/cyberpunk/player/scriptedPuppet.script  
   Files: scriptedPuppet_v1.63_minified.script, scriptedPuppet_1.61_to_2.0_minified.diff
   
3. @wrapMethod(ScriptedPuppet) OnUploadProgressStateChanged  
   Source: tools/redmod/scripts/cyberpunk/player/scriptedPuppet.script
   Files: scriptedPuppet_v1.63_minified.script, gameplayRoleComponent_v1.63_minified.script
   
4. @wrapMethod(QuickhacksListGameController) ApplyQuickHack
   Source: tools/redmod/scripts/cyberpunk/UI/quickhacks/quickhacksListGameController.script
   Files: quickhacks_v1.63_minified.script

COMMUNITY MOD WRAPPERS (not used in this version):
- @wrapMethod(BaseScriptableAction) GetActivationTime - modexamplefor1.63syntax (44).reds  
- @wrapMethod(ScriptableDeviceAction) ProcessRPGAction - deviceBase_v163_vs_v20.unified_minified.diff

FOCUS: This implementation prioritizes NPC (ScriptedPuppet) queue functionality while 
maintaining v1.63 compatibility and original breach protocol blocking behavior.

v1.63 Action Types:
- gamedataObjectActionType.DeviceQuickHack
- gamedataObjectActionType.PuppetQuickHack  
- gamedataObjectActionType.MinigameUpload (Breach Protocol)
- gamedataObjectActionType.Direct
- gamedataObjectActionType.Remote
- gamedataObjectActionType.Item
- gamedataObjectActionType.Payment

NOTE: VehicleQuickHack does NOT exist in v1.63 - added in v2.0 only.
*/