// DeviceHack_UploadBypass.reds
module HackQueueMod

@replaceMethod(Device)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
    let quickSlotsManagerNotification: ref<RevealInteractionWheel>;
    let context: GetActionsContext;
    let actions: array<ref<DeviceAction>>;
    let commands: array<ref<QuickhackData>>;
    
    quickSlotsManagerNotification = new RevealInteractionWheel();
    quickSlotsManagerNotification.lookAtObject = this;
    quickSlotsManagerNotification.shouldReveal = shouldOpen;
    
    if shouldOpen {
        context = this.GetDevicePS().GenerateContext(gamedeviceRequestType.Remote, Device.GetInteractionClearance(), this.GetPlayerMainObject(), this.GetEntityID());
        this.GetDevicePS().GetRemoteActions(actions, context);
        
        // MODIFICATION: Removed the upload blocking check
        // Original lines were:
        // if this.m_isQhackUploadInProgerss {
        //     ScriptableDeviceComponentPS.SetActionsInactiveAll(actions, "LocKey#7020");
        // }
        
        this.TranslateActionsIntoQuickSlotCommands(actions, commands);
        quickSlotsManagerNotification.commands = commands;
    };
    
    HUDManager.SetQHDescriptionVisibility(this.GetGame(), shouldOpen);
    GameInstance.GetUISystem(this.GetGame()).QueueEvent(quickSlotsManagerNotification);
}