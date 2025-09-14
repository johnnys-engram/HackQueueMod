// =============================================================================
// HackQueueMod v1.0.0
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// 
// Queue system for quickhacks during upload/cooldown periods
// =============================================================================

// Import separated modules with JE_ prefix
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*
import JE_HackQueueMod.Events.*
import JE_HackQueueMod.Helpers.*

// =============================================================================
// ✅ LOGGING FUNCTIONS MIGRATED TO Core/Logging.reds
// =============================================================================

// ✅ QUEUE DATA CLASSES MIGRATED TO Core/QueueSystem.reds

// ✅ QUEUE SYSTEM CLASSES MIGRATED TO Core/QueueSystem.reds

// ✅ EVENT CLASSES MIGRATED TO Events/QueueEvents.reds


// ✅ HELPER CLASSES MIGRATED TO Helpers/QueueHelper.reds
// UI Refresh Helper for v1.63 - MIGRATED
// QuickhackQueueHelper and QueueModHelper classes have been moved to Helpers/QueueHelper.reds

// =============================================================================
// Debug Logging for UI Refresh (keep this wrapper)
// =============================================================================

@wrapMethod(QuickhackModule)
public static func RequestRefreshQuickhackMenu(context: GameInstance, requester: EntityID) -> Void {
    QueueModLog(n"DEBUG", n"UI", s"Vanilla UI Refresh requested for: \(EntityID.ToDebugString(requester))");
    
    wrappedMethod(context, requester);
    
    // Schedule force refresh as backup (v1.63 has aggressive caching)
    QueueModLog(n"DEBUG", n"UI", "Scheduling force refresh backup for v1.63 compatibility");
    QuickhackQueueHelper.ScheduleSequencedRefresh(context, requester);
}