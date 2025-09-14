// =============================================================================
// HackQueueMod - Device Extensions
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Extensions.Device
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*

// =============================================================================
// DEVICE AND SCRIPTABLE DEVICE ACTION EXTENSIONS
// =============================================================================

// Device extensions
@addField(Device)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(Device)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
    }
    return this.m_queueModActionQueue;
}

@addMethod(Device)
public func IsQueueModEnabled() -> Bool {
    return true;
}

@addMethod(Device)
public func IsQueueModFull() -> Bool {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return false;
    }
    let queueSize: Int32 = queue.GetQueueSize();
    let isFull: Bool = queueSize >= 3; // Default max queue size
    if queueSize > 0 {
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Device queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

// =============================================================================
// Phase 3.1: Device Upload Bypass Wrapper for v1.63
// =============================================================================

@wrapMethod(Device)
protected func SendQuickhackCommands(shouldOpen: Bool) -> Void {
    let originalUploadState: Bool = this.m_isQhackUploadInProgerss;

    if originalUploadState {
        let queueEnabled: Bool = this.IsQueueModEnabled();
        let queueFull: Bool = this.IsQueueModFull();

        if queueEnabled && !queueFull {
            QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Device bypassing upload block for queue (device: \(this.GetDisplayName()))");
            this.m_isQhackUploadInProgerss = false;
        }
    }

    wrappedMethod(shouldOpen);
    this.m_isQhackUploadInProgerss = originalUploadState;
}

// ScriptableDeviceAction extensions
@addField(ScriptableDeviceAction)
private let m_queueModActionQueue: ref<QueueModActionQueue>;

@addMethod(ScriptableDeviceAction)
public func GetQueueModActionQueue() -> ref<QueueModActionQueue> {
    if !IsDefined(this.m_queueModActionQueue) {
        this.m_queueModActionQueue = new QueueModActionQueue();
    }
    return this.m_queueModActionQueue;
}

@addMethod(ScriptableDeviceAction)
public func IsQueueModEnabled() -> Bool {
    return true;
}

@addMethod(ScriptableDeviceAction)
public func IsQueueModFull() -> Bool {
    let queue: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    if !IsDefined(queue) {
        return false;
    }
    let queueSize: Int32 = queue.GetQueueSize();
    let isFull: Bool = queueSize >= 3;
    if queueSize > 0 {
        QueueModLog(n"DEBUG", n"QUEUE", s"[QueueMod] Action queue size: \(queueSize), Full: \(isFull)");
    }
    return isFull;
}

@addMethod(ScriptableDeviceAction)
public func QueueModQuickHack(action: ref<DeviceAction>) -> Bool {
    if !IsDefined(action) {
        return false;
    }
    QueueModLog(n"DEBUG", n"QUEUE", "ScriptableDeviceAction.QueueModQuickHack called");
    // Generate a unique key for the action
    let sa: ref<ScriptableDeviceAction> = action as ScriptableDeviceAction;
    if IsDefined(sa) {
        let uniqueKey: String = s"device::\(TDBID.ToStringDEBUG(sa.GetObjectActionID()))::\(GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp())";
        return this.GetQueueModActionQueue().PutActionInQueueWithKey(action, uniqueKey);
    }
    return false;
}

@addMethod(ScriptableDeviceAction)
public func GetQueueModSize() -> Int32 {
    let q: ref<QueueModActionQueue> = this.GetQueueModActionQueue();
    return IsDefined(q) ? q.GetQueueSize() : 0;
}
