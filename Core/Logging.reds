// =============================================================================
// HackQueueMod - Logging Module (PRUNED)
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Logging

// =============================================================================
// SCOPED LOGGING SYSTEM FOR FOCUSED DEBUGGING
// =============================================================================

public func QueueModLog(level: CName, category: CName, message: String) -> Void {
    // Development debug flags - set to false for production builds
    let DEBUG_QUEUE_MOD: Bool = true;    // Master debug switch
    let DEBUG_RAM: Bool = true;          // RAM operations
    let DEBUG_QUICKHACK: Bool = true;   // Quickhack activation/execution
    let DEBUG_UI: Bool = false;          // UI operations
    let DEBUG_QUEUE: Bool = true;       // Queue operations
    let DEBUG_EVENTS: Bool = false;      // Event handling
    let DEBUG_TEST: Bool = false;         // Smoke test and validation output
    
    // Skip if debug disabled
    if Equals(level, n"DEBUG") && !DEBUG_QUEUE_MOD {
        return;
    }
    
    // Category-based filtering
    if Equals(level, n"DEBUG") {
        if Equals(category, n"RAM") && !DEBUG_RAM { return; }
        if Equals(category, n"QUICKHACK") && !DEBUG_QUICKHACK { return; }
        if Equals(category, n"UI") && !DEBUG_UI { return; }
        if Equals(category, n"QUEUE") && !DEBUG_QUEUE { return; }
        if Equals(category, n"EVENTS") && !DEBUG_EVENTS { return; }
        if Equals(category, n"TEST") && !DEBUG_TEST { return; }
    }
    
    // Format: [CATEGORY] message
    let formattedMessage: String = s"[\(ToString(category))] \(message)";
    LogChannel(level, formattedMessage);
}