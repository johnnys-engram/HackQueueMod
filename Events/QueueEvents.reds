// =============================================================================
// HackQueueMod - Queue Events System
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Events
import JE_HackQueueMod.Core.*

// =============================================================================
// EVENT CLASSES FOR QUEUE MANAGEMENT
// =============================================================================

// Queue Event for State Synchronization
public class QueueModEvent extends Event {
    public let eventType: CName;
    public let quickhackData: ref<QuickhackData>;
    public let timestamp: Float;
    
    public func Create(eventType: CName, data: ref<QuickhackData>) -> ref<QueueModEvent> {
        let event: ref<QueueModEvent> = new QueueModEvent();
        event.eventType = eventType;
        event.quickhackData = data;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}

// ✅ CRITICAL FIX: Delay Event Classes for Proper Sequencing
public class QueueModCommandGenEvent extends Event {
    public let targetID: EntityID;
    public let timestamp: Float;
    
    public func Create(targetID: EntityID) -> ref<QueueModCommandGenEvent> {
        let event: ref<QueueModCommandGenEvent> = new QueueModCommandGenEvent();
        event.targetID = targetID;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}

public class QueueModCacheEvent extends Event {
    public let targetID: EntityID;
    public let timestamp: Float;
    
    public func Create(targetID: EntityID) -> ref<QueueModCacheEvent> {
        let event: ref<QueueModCacheEvent> = new QueueModCacheEvent();
        event.targetID = targetID;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}

public class QueueModValidationEvent extends Event {
    public let targetID: EntityID;
    public let timestamp: Float;
    
    public func Create(targetID: EntityID) -> ref<QueueModValidationEvent> {
        let event: ref<QueueModValidationEvent> = new QueueModValidationEvent();
        event.targetID = targetID;
        event.timestamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        return event;
    }
}
