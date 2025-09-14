// =============================================================================
// HackQueueMod - Catalog Integration Smoke Test
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Core.Test
import JE_HackQueueMod.Logging.*
import JE_HackQueueMod.Core.*
import JE_HackQueueMod.Core.Catalog.*

// =============================================================================
// PHASE 0 SMOKE TEST - Catalog vs Manual Mapping Validation
// =============================================================================

public class CatalogSmokeTest {
    
    // Execute smoke test comparing catalog vs manual mappings
    public static func ExecuteSmokeTest() -> Bool {
        QueueModLog(n"DEBUG", n"TEST", "*** CATALOG SMOKE TEST STARTED ***");
        
        let allTestsPassed: Bool = true;
        
        // Test 1: Catalog initialization
        if !CatalogSmokeTest.TestCatalogInitialization() {
            allTestsPassed = false;
        }
        
        // Test 2: Known quickhack lookups
        if !CatalogSmokeTest.TestKnownQuickhackLookups() {
            allTestsPassed = false;
        }
        
        // Test 3: Category organization
        if !CatalogSmokeTest.TestCategoryOrganization() {
            allTestsPassed = false;
        }
        
        // Test 4: Performance validation
        if !CatalogSmokeTest.TestPerformanceBaseline() {
            allTestsPassed = false;
        }
        
        if allTestsPassed {
            QueueModLog(n"DEBUG", n"TEST", "*** CATALOG SMOKE TEST PASSED - Integration Ready ***");
        } else {
            QueueModLog(n"ERROR", n"TEST", "*** CATALOG SMOKE TEST FAILED - Check errors above ***");
        }
        
        return allTestsPassed;
    }
    
    private static func TestCatalogInitialization() -> Bool {
        QueueModLog(n"DEBUG", n"TEST", "[Test 1] Catalog initialization...");
        
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(GetGameInstance());
        if !IsDefined(playerSystem) {
            QueueModLog(n"ERROR", n"TEST", "[Test 1] FAILED - Cannot get PlayerSystem");
            return false;
        }
        
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            QueueModLog(n"ERROR", n"TEST", "[Test 1] FAILED - Cannot get player");
            return false;
        }
        
        let catalog: ref<NPCQuickhackCatalog> = player.GetNPCQuickhackCatalog();
        if !IsDefined(catalog) {
            QueueModLog(n"ERROR", n"TEST", "[Test 1] FAILED - Catalog is null");
            return false;
        }
        
        let totalHacks: Int32 = catalog.GetTotalHackCount();
        if totalHacks < 1 {
            QueueModLog(n"WARN", n"TEST", s"[Test 1] WARNING - Only \(totalHacks) hacks found (player may lack cyberdeck)");
            return false;
        }
        
        QueueModLog(n"DEBUG", n"TEST", s"[Test 1] PASSED - Catalog initialized with \(totalHacks) quickhacks");
        return true;
    }
    
    private static func TestKnownQuickhackLookups() -> Bool {
        QueueModLog(n"DEBUG", n"TEST", "[Test 2] Known quickhack lookups...");
        
        let catalog: ref<NPCQuickhackCatalog> = GetQuickhackCatalog();
        if !IsDefined(catalog) {
            QueueModLog(n"ERROR", n"TEST", "[Test 2] FAILED - Cannot get catalog");
            return false;
        }
        
        // Test common quickhacks that should be found
        let testQuickhacks: array<String> = ["Reboot Optics", "Overheat", "Short Circuit"];
        let foundCount: Int32 = 0;
        
        let i: Int32 = 0;
        while i < ArraySize(testQuickhacks) {
            let tweakID: TweakDBID = catalog.GetTweakIDForDisplayName(testQuickhacks[i]);
            if TDBID.IsValid(tweakID) {
                QueueModLog(n"DEBUG", n"TEST", s"[Test 2] Found: \(testQuickhacks[i]) -> \(TDBID.ToStringDEBUG(tweakID))");
                foundCount += 1;
            } else {
                QueueModLog(n"DEBUG", n"TEST", s"[Test 2] Not found: \(testQuickhacks[i]) (may not be available to player)");
            }
            i += 1;
        }
        
        if foundCount > 0 {
            QueueModLog(n"DEBUG", n"TEST", s"[Test 2] PASSED - Found \(foundCount)/\(ArraySize(testQuickhacks)) test quickhacks");
            return true;
        } else {
            QueueModLog(n"ERROR", n"TEST", "[Test 2] FAILED - No test quickhacks found");
            return false;
        }
    }
    
    private static func TestCategoryOrganization() -> Bool {
        QueueModLog(n"DEBUG", n"TEST", "[Test 3] Category organization...");
        
        let catalog: ref<NPCQuickhackCatalog> = GetQuickhackCatalog();
        if !IsDefined(catalog) {
            QueueModLog(n"ERROR", n"TEST", "[Test 3] FAILED - Cannot get catalog");
            return false;
        }
        
        // Test category arrays
        let covertHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetHacksInCategory(n"CovertHack");
        let damageHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetHacksInCategory(n"DamageHack");
        let totalCategorized: Int32 = ArraySize(covertHacks) + ArraySize(damageHacks);
        
        QueueModLog(n"DEBUG", n"TEST", s"[Test 3] Covert: \(ArraySize(covertHacks)), Damage: \(ArraySize(damageHacks))");
        
        if totalCategorized > 0 {
            QueueModLog(n"DEBUG", n"TEST", s"[Test 3] PASSED - \(totalCategorized) quickhacks properly categorized");
            return true;
        } else {
            QueueModLog(n"WARN", n"TEST", "[Test 3] WARNING - No categorized quickhacks found");
            return false;
        }
    }
    
    private static func TestPerformanceBaseline() -> Bool {
        QueueModLog(n"DEBUG", n"TEST", "[Test 4] Performance baseline...");
        
        let startTime: Float = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        
        // Test catalog lookup performance
        let catalog: ref<NPCQuickhackCatalog> = GetQuickhackCatalog();
        let testResult: TweakDBID = catalog.GetTweakIDForDisplayName("Overheat");
        
        let endTime: Float = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        let lookupTime: Float = endTime - startTime;
        
        if lookupTime < 0.1 { // 100ms threshold
            QueueModLog(n"DEBUG", n"TEST", s"[Test 4] PASSED - Lookup time: \(lookupTime)s");
            return true;
        } else {
            QueueModLog(n"WARN", n"TEST", s"[Test 4] WARNING - Slow lookup time: \(lookupTime)s");
            return false;
        }
    }
}

// =============================================================================
// DEBUG HOOK - Run smoke test on player initialization
// =============================================================================

@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let result: Bool = wrappedMethod();
    
    // Run smoke test after player is fully initialized
    if IsDefined(this) {
        QueueModLog(n"DEBUG", n"TEST", "[Integration] Player attached - running catalog smoke test...");
        CatalogSmokeTest.ExecuteSmokeTest();
    }
    
    return result;
}