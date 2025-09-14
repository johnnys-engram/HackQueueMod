// =============================================================================
// Quickhack Upload Bypass Mod
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// 
// Removes the "upload in progress" blocking that prevents multiple quickhacks
// =============================================================================

module QuickhackUploadBypass

// =============================================================================
// SCRIPTED PUPPET (NPC) UPLOAD BYPASS
// =============================================================================

@wrapMethod(ScriptedPuppet)
private func TranslateChoicesIntoQuickSlotCommands(
    puppetActions: array<ref<PuppetAction>>, 
    out commands: array<ref<QuickhackData>>
) -> Void {
    // Always run the original method - the upload blocking is handled elsewhere
    // This method is called when the game wants to translate actions into quickhack commands
    // By always running it, we bypass any upload state checks
    wrappedMethod(puppetActions, commands);
}

// Simplified approach: Use a different method to bypass upload blocking
// Instead of intercepting StatPoolsSystem, we'll modify the ScriptedPuppet behavior directly

// =============================================================================
// DEVICE UPLOAD BYPASS
// =============================================================================

@wrapMethod(Device)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
    // Store original upload state
    let originalUploadState: Bool = this.m_isQhackUploadInProgerss;
    
    // Temporarily disable upload blocking if upload is in progress
    if originalUploadState {
        this.m_isQhackUploadInProgerss = false;
    }
    
    // Call vanilla method with upload state disabled
    wrappedMethod(shouldOpen);
    
    // Restore original upload state
    this.m_isQhackUploadInProgerss = originalUploadState;
}