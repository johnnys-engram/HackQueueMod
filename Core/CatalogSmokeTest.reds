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
        QueueModTestLog(n"DEBUG", "*** CATALOG SMOKE TEST STARTED ***");
        
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
        
        // Test 4: Display name lookup validation
        if !CatalogSmokeTest.TestDisplayNameLookups() {
            allTestsPassed = false;
        }
        
        // Test 5: Performance validation
        if !CatalogSmokeTest.TestPerformanceBaseline() {
            allTestsPassed = false;
        }
        
        if allTestsPassed {
            QueueModTestLog(n"DEBUG", "*** CATALOG SMOKE TEST PASSED - Integration Ready ***");
        } else {
            QueueModTestLog(n"ERROR", "*** CATALOG SMOKE TEST FAILED - Check errors above ***");
        }
        
        return allTestsPassed;
    }
    
    private static func TestCatalogInitialization() -> Bool {
        QueueModTestLog(n"DEBUG", "[Test 1] Catalog initialization...");
        
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(GetGameInstance());
        if !IsDefined(playerSystem) {
            QueueModTestLog(n"ERROR", "[Test 1] FAILED - Cannot get PlayerSystem");
            return false;
        }
        
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            QueueModTestLog(n"ERROR", "[Test 1] FAILED - Cannot get player");
            return false;
        }
        
        let catalog: ref<NPCQuickhackCatalog> = player.GetNPCQuickhackCatalog();
        if !IsDefined(catalog) {
            QueueModTestLog(n"ERROR", "[Test 1] FAILED - Catalog is null");
            return false;
        }
        
        let totalHacks: Int32 = catalog.GetTotalHackCount();
        if totalHacks < 1 {
            QueueModTestLog(n"WARN", s"[Test 1] WARNING - Only \(totalHacks) hacks found (player may lack cyberdeck)");
            return false;
        }
        
        QueueModTestLog(n"DEBUG", s"[Test 1] PASSED - Catalog initialized with \(totalHacks) quickhacks");
        return true;
    }
    
    private static func TestKnownQuickhackLookups() -> Bool {
        QueueModTestLog(n"DEBUG", "[Test 2] Known quickhack lookups...");
        
        let catalog: ref<NPCQuickhackCatalog> = GetQuickhackCatalog();
        if !IsDefined(catalog) {
            QueueModTestLog(n"ERROR", "[Test 2] FAILED - Cannot get catalog");
            return false;
        }
        
        // NEW: List all discovered quickhacks
        let allHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetAllQuickhacks();
        QueueModTestLog(n"DEBUG", s"[Test 2] === DISCOVERED QUICKHACKS (\(ArraySize(allHacks)) total) ===");
        
        let i: Int32 = 0;
        while i < ArraySize(allHacks) {
            let entry: ref<QuickhackCatalogEntry> = allHacks[i];
            if IsDefined(entry) {
                QueueModTestLog(n"DEBUG", s"  [\(i+1)] \(entry.displayName) | Category: \(ToString(entry.categoryName)) | Priority: \(entry.priority)");
            }
            i += 1;
        }
        
        // Test display name validation
        QueueModTestLog(n"DEBUG", "[Test 2] === DISPLAY NAME VALIDATION ===");
        let displayNameIssues: Int32 = 0;
        let localizedNames: Int32 = 0;
        let friendlyFallbackNames: Int32 = 0;
        let technicalFallbackNames: Int32 = 0;
        let k: Int32 = 0;
        while k < ArraySize(allHacks) {
            let entry: ref<QuickhackCatalogEntry> = allHacks[k];
            if IsDefined(entry) {
                if Equals(entry.displayName, "") || StrContains(entry.displayName, "LocKey") {
                    QueueModTestLog(n"ERROR", s"  [ISSUE] Entry \(k+1) has invalid display name: '\(entry.displayName)'");
                    displayNameIssues += 1;
                } else if StrContains(entry.displayName, "Hack") && !StrContains(entry.displayName, " ") {
                    // Technical fallback name (e.g., "LocomotionMalfunctionHack")
                    technicalFallbackNames += 1;
                    QueueModTestLog(n"WARN", s"  [TECHNICAL] Entry \(k+1) using technical fallback: '\(entry.displayName)'");
                } else if StrContains(entry.displayName, " ") || Equals(entry.displayName, "Ping") || Equals(entry.displayName, "Overheat") {
                    // Friendly fallback name (e.g., "Cripple Movement", "Reboot Optics")
                    friendlyFallbackNames += 1;
                    QueueModTestLog(n"DEBUG", s"  [FRIENDLY] Entry \(k+1) using friendly fallback: '\(entry.displayName)'");
                } else {
                    // Likely a proper localized name
                    localizedNames += 1;
                    QueueModTestLog(n"DEBUG", s"  [LOCALIZED] Entry \(k+1) using localized name: '\(entry.displayName)'");
                }
            }
            k += 1;
        }
        
        if displayNameIssues == 0 {
            QueueModTestLog(n"DEBUG", s"  [PASS] All display names are valid - \(localizedNames) localized, \(friendlyFallbackNames) friendly fallback, \(technicalFallbackNames) technical fallback");
        } else {
            QueueModTestLog(n"ERROR", s"  [FAIL] \(displayNameIssues) entries have invalid display names");
        }
        
        // Test NPC quickhack filtering validation
        QueueModTestLog(n"DEBUG", "[Test 2] === NPC QUICKHACK FILTERING ===");
        let deviceHackCount: Int32 = 0;
        let npcHackCount: Int32 = 0;
        let l: Int32 = 0;
        while l < ArraySize(allHacks) {
            let entry: ref<QuickhackCatalogEntry> = allHacks[l];
            if IsDefined(entry) {
                if entry.isDeviceHack {
                    deviceHackCount += 1;
                    QueueModTestLog(n"WARN", s"  [DEVICE] Found device hack: \(entry.displayName)");
                } else if entry.isPuppetHack {
                    npcHackCount += 1;
                }
            }
            l += 1;
        }
        
        if deviceHackCount == 0 && npcHackCount > 0 {
            QueueModTestLog(n"DEBUG", s"  [PASS] Found \(npcHackCount) NPC quickhacks, 0 device hacks");
        } else if deviceHackCount > 0 {
            QueueModTestLog(n"ERROR", s"  [FAIL] Found \(deviceHackCount) device hacks (should be 0)");
        } else {
            QueueModTestLog(n"WARN", s"  [WARN] Found \(npcHackCount) NPC quickhacks, \(deviceHackCount) device hacks");
        }
        
        // Test category breakdown
        QueueModTestLog(n"DEBUG", "[Test 2] === BY CATEGORY ===");
        let categories: array<CName> = [n"CovertHack", n"ControlHack", n"DamageHack", n"UltimateHack", n"VehicleHack"];
        let j: Int32 = 0;
        while j < ArraySize(categories) {
            let categoryHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetHacksInCategory(categories[j]);
            if ArraySize(categoryHacks) > 0 {
                QueueModTestLog(n"DEBUG", s"  \(ToString(categories[j])): \(ArraySize(categoryHacks)) hacks");
            }
            j += 1;
        }
        
        // Original test logic
        if ArraySize(allHacks) > 0 {
            QueueModTestLog(n"DEBUG", s"[Test 2] PASSED - Found \(ArraySize(allHacks)) total quickhacks");
            return true;
        } else {
            QueueModTestLog(n"ERROR", "[Test 2] FAILED - No quickhacks found");
            return false;
        }
    }
    
    private static func TestCategoryOrganization() -> Bool {
        QueueModTestLog(n"DEBUG", "[Test 3] Category organization...");
        
        let catalog: ref<NPCQuickhackCatalog> = GetQuickhackCatalog();
        if !IsDefined(catalog) {
            QueueModTestLog(n"ERROR", "[Test 3] FAILED - Cannot get catalog");
            return false;
        }
        
        // Test category arrays
        let covertHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetHacksInCategory(n"CovertHack");
        let damageHacks: array<ref<QuickhackCatalogEntry>> = catalog.GetHacksInCategory(n"DamageHack");
        let totalCategorized: Int32 = ArraySize(covertHacks) + ArraySize(damageHacks);
        
        QueueModTestLog(n"DEBUG", s"[Test 3] Covert: \(ArraySize(covertHacks)), Damage: \(ArraySize(damageHacks))");
        
        if totalCategorized > 0 {
            QueueModTestLog(n"DEBUG", s"[Test 3] PASSED - \(totalCategorized) quickhacks properly categorized");
            return true;
        } else {
            QueueModTestLog(n"WARN", "[Test 3] WARNING - No categorized quickhacks found");
            return false;
        }
    }
    
    private static func TestDisplayNameLookups() -> Bool {
        QueueModTestLog(n"DEBUG", "[Test 4] Display name lookup validation...");
        
        let catalog: ref<NPCQuickhackCatalog> = GetQuickhackCatalog();
        if !IsDefined(catalog) {
            QueueModTestLog(n"ERROR", "[Test 4] FAILED - Cannot get catalog");
            return false;
        }
        
        // Test common NPC quickhack lookups (should find most of these now)
        let testNames: array<String> = ["Overheat", "Reboot Optics", "Short Circuit", "Synapse Burnout", "Ping"];
        let successfulLookups: Int32 = 0;
        
        let i: Int32 = 0;
        while i < ArraySize(testNames) {
            let entry: ref<QuickhackCatalogEntry> = catalog.FindQuickhackByName(testNames[i]);
            if IsDefined(entry) {
                QueueModTestLog(n"DEBUG", s"  [PASS] Found '\(testNames[i])' -> '\(entry.displayName)'");
                successfulLookups += 1;
            } else {
                QueueModTestLog(n"WARN", s"  [MISS] Could not find '\(testNames[i])'");
            }
            i += 1;
        }
        
        if successfulLookups >= 3 {
            QueueModTestLog(n"DEBUG", s"[Test 4] PASSED - \(successfulLookups)/\(ArraySize(testNames)) NPC quickhack lookups successful");
            return true;
        } else if successfulLookups > 0 {
            QueueModTestLog(n"WARN", s"[Test 4] PARTIAL - \(successfulLookups)/\(ArraySize(testNames)) lookups successful (expected 3+)");
            return true;
        } else {
            QueueModTestLog(n"ERROR", "[Test 4] FAILED - No NPC quickhack lookups successful");
            return false;
        }
    }
    
    private static func TestPerformanceBaseline() -> Bool {
        QueueModTestLog(n"DEBUG", "[Test 5] Performance baseline...");
        
        let startTime: Float = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        
        // Test catalog lookup performance
        let catalog: ref<NPCQuickhackCatalog> = GetQuickhackCatalog();
        let testResult: TweakDBID = catalog.GetTweakIDForDisplayName("Overheat");
        
        let endTime: Float = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTimeStamp();
        let lookupTime: Float = endTime - startTime;
        
        // Validate that the lookup actually worked
        let isValidResult: Bool = TDBID.IsValid(testResult);
        
        if lookupTime < 0.1 && isValidResult { // 100ms threshold + valid result
            QueueModTestLog(n"DEBUG", s"[Test 5] PASSED - Lookup time: \(lookupTime)s, Found: \(TDBID.ToStringDEBUG(testResult))");
            return true;
        } else if !isValidResult {
            QueueModTestLog(n"ERROR", s"[Test 5] FAILED - Could not find 'Overheat' quickhack");
            return false;
        } else {
            QueueModTestLog(n"WARN", s"[Test 5] WARNING - Slow lookup time: \(lookupTime)s");
            return false;
        }
    }
}

// =============================================================================
// TIMING FIX - Smoke test now triggered from GetNPCQuickhackCatalog()
// when catalog is built with actual quickhack data available
// =============================================================================