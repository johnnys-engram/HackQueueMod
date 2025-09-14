// =============================================================================
// HackQueueMod - Logging Module
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module HackQueueMod.Logging

// =============================================================================
// SCOPED LOGGING SYSTEM FOR FOCUSED DEBUGGING
// =============================================================================
// 
// USAGE GUIDE:
// To focus on specific areas, set the relevant flag to true:
// - DEBUG_RAM = true     → See RAM operations (deduction, refunds, changes)
// - DEBUG_QUICKHACK = true → See quickhack execution and activation
// - DEBUG_UI = true      → See UI refresh and wheel operations  
// - DEBUG_QUEUE = true   → See queue operations (add/remove/process)
// - DEBUG_EVENTS = true  → See event handling and callbacks
//
// EXAMPLE: To debug only RAM issues, set:
// let DEBUG_RAM: Bool = true;
// let DEBUG_QUICKHACK: Bool = false;
// let DEBUG_UI: Bool = false;
// let DEBUG_QUEUE: Bool = false;
// let DEBUG_EVENTS: Bool = false;
// =============================================================================

// MIGRATION PHASE 1: Now active - originals removed from main file
public func QueueModLog(level: CName, category: CName, message: String) -> Void {
    // Development debug flags - set to false for production builds
    let DEBUG_QUEUE_MOD: Bool = true;
    let DEBUG_RAM: Bool = true;          // RAM operations
    let DEBUG_QUICKHACK: Bool = true;    // Quickhack activation/execution
    let DEBUG_UI: Bool = false;          // UI operations
    let DEBUG_QUEUE: Bool = false;       // Queue operations
    let DEBUG_EVENTS: Bool = false;      // Event handling
    
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
    }
    
    // Format: [CATEGORY] message
    let formattedMessage: String = s"[\(ToString(category))] \(message)";
    LogChannel(level, formattedMessage);
}

// Legacy function for backward compatibility
public func QueueModLog(level: CName, message: String) -> Void {
    QueueModLog(level, n"GENERAL", message);
}

// Version constants for mod management
public func GetHackQueueModVersion() -> String {
    return "1.0.0";
}

public func GetHackQueueModCreator() -> String {
    return "johnnys-engram";
}

public func GetHackQueueModTargetVersion() -> String {
    return "Cyberpunk 2077 v1.63";
}
