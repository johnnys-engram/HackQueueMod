// =============================================================================
// HackQueueMod - Player Extensions
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Extensions.Player
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*
import JE_HackQueueMod.Helpers.*

// =============================================================================
// PLAYERPUPPET EXTENSIONS
// =============================================================================

// PlayerPuppet integration for queue helper access
@addField(PlayerPuppet)
private let m_queueModHelper: ref<QueueModHelper>;

@addField(PlayerPuppet)
private let m_qmQuickhackController: wref<QuickhacksListGameController>;

@addMethod(PlayerPuppet)
public func SetQuickhacksListGameController(controller: wref<QuickhacksListGameController>) -> Void {
    this.m_qmQuickhackController = controller;
}

@addMethod(PlayerPuppet)
public func GetQueueModHelper() -> ref<QueueModHelper> {
    if !IsDefined(this.m_queueModHelper) {
        this.m_queueModHelper = new QueueModHelper();
        QueueModLog(n"DEBUG", n"EVENTS", "[QueueMod] Player loaded - queue system ready");
    }
    return this.m_queueModHelper;
}

@addMethod(PlayerPuppet)
public func GetQuickhacksListGameController() -> ref<QuickhacksListGameController> {
    return this.m_qmQuickhackController;
}