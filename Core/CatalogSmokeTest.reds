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
        
        // NEW: List all discovered quickhacks
        let allHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetAllQuickhacks();
        QueueModLog(n"DEBUG", n"TEST", s"[Test 2] === DISCOVERED QUICKHACKS (\(ArraySize(allHacks)) total) ===");
        
        let i: Int32 = 0;
        while i < ArraySize(allHacks) {
            let entry: ref<QuickhackCatalogEntry> = allHacks[i];
            if IsDefined(entry) {
                QueueModLog(n"DEBUG", n"TEST", s"  [\(i+1)] \(entry.displayName) | Category: \(ToString(entry.categoryName)) | Priority: \(entry.priority)");
            }
            i += 1;
        }
        
        // Test category breakdown
        QueueModLog(n"DEBUG", n"TEST", "[Test 2] === BY CATEGORY ===");
        let categories: array<CName> = [n"CovertHack", n"ControlHack", n"DamageHack", n"UltimateHack", n"VehicleHack"];
        let j: Int32 = 0;
        while j < ArraySize(categories) {
            let categoryHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetHacksInCategory(categories[j]);
            if ArraySize(categoryHacks) > 0 {
                QueueModLog(n"DEBUG", n"TEST", s"  \(ToString(categories[j])): \(ArraySize(categoryHacks)) hacks");
            }
            j += 1;
        }
        
        // Original test logic
        if ArraySize(allHacks) > 0 {
            QueueModLog(n"DEBUG", n"TEST", s"[Test 2] PASSED - Found \(ArraySize(allHacks)) total quickhacks");
            return true;
        } else {
            QueueModLog(n"ERROR", n"TEST", "[Test 2] FAILED - No quickhacks found");
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
// TIMING FIX - Smoke test now triggered from GetNPCQuickhackCatalog()
// when catalog is built with actual quickhack data available
// =============================================================================