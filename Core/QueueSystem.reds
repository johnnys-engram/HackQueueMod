// =============================================================================
// HackQueueMod - Core Queue System
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module HackQueueMod.Core
import HackQueueMod.Logging.*

// =============================================================================
// CORE QUEUE DATA STRUCTURES
// =============================================================================

// Queue entry system for v1.63 compatibility
public class QueueModEntry {
    public let action: ref<DeviceAction>;
    public let fingerprint: String;
    public let timestamp: Float;
    public let entryType: Int32;
    public let ramCost: Int32;
}

public func CreateQueueModEntry(action: ref<DeviceAction>, key: String, cost: Int32) -> ref<QueueModEntry> {
    let entry: ref<QueueModEntry> = new QueueModEntry();
    entry.action = action;
    entry.fingerprint = key;
    entry.entryType = 0;
    entry.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
    entry.ramCost = cost;
    return entry;
}

// =============================================================================
// CORE QUEUE SYSTEM CLASSES
// =============================================================================
// QueueModActionQueue class will be added in Phase 2
