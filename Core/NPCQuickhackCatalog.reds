// =============================================================================
// HackQueueMod - NPC Quickhack Catalog System
// Creator: johnnys-engram
// Target: Cyberpunk 2077 v1.63
// Framework: redscript 0.5.14
// =============================================================================

module JE_HackQueueMod.Core.Catalog
import JE_HackQueueMod.Logging.*

// =============================================================================
// V1.63 LOCALIZATION HELPER - Missing from redscript 0.5.14
// =============================================================================

// v1.63 localization helper - avoid naming collision with existing LocKeyToString
public func QueueModLocKeyToString(locKey: CName) -> String {
    // Convert CName to String first, then localize (v1.63 pattern)
    let locKeyStr: String = ToString(locKey);
    return GetLocalizedText(locKeyStr);
}

// =============================================================================
// QUICKHACK CATALOG ENTRY AND CATEGORY ORGANIZATION
// =============================================================================

// Quickhack catalog entry with category classification
public class QuickhackCatalogEntry {
    public let actionID: TweakDBID;
    public let displayName: String;
    public let categoryRecord: ref<HackCategory_Record>; // v1.63 compatible
    public let categoryName: CName;
    public let actionRecord: ref<ObjectAction_Record>;
    public let isDeviceHack: Bool;
    public let isPuppetHack: Bool;
    public let baseCost: Int32;
    public let priority: Int32; // For queue ordering
    
    public func Initialize(record: ref<ObjectAction_Record>) -> Void {
        if !IsDefined(record) {
            return;
        }
        
        this.actionRecord = record;
        this.actionID = record.GetID();
        
        // v1.63 COMPATIBLE localization pattern (from project evidence)
        this.displayName = LocKeyToString(record.ObjectActionUI().Caption());
        
        // Enhanced fallback for v1.63 edge cases
        if Equals(this.displayName, "") || StrContains(this.displayName, "LocKey") {
            // Try alternative localization approach
            let captionStr: String = ToString(record.ObjectActionUI().Caption());
            if NotEquals(captionStr, "") && NotEquals(captionStr, "None") {
                this.displayName = GetLocalizedText(captionStr);
            }
            
            // If still empty, use enhanced fallback with friendly names
            if Equals(this.displayName, "") || StrContains(this.displayName, "LocKey") {
                this.displayName = this.CreateFriendlyName(this.actionID);
            }
            
            QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Using enhanced fallback: \(this.displayName)");
        } else {
            QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Localized display name: \(this.displayName)");
        }
        
        // v1.63 compatible: Use string pattern matching for category detection
        this.categoryRecord = null; // May not be available in v1.63
        this.categoryName = this.DetectCategoryFromID(this.actionID);
        
        // Classify hack type based on ID patterns (v1.63 convention)
        let idStr: String = TDBID.ToStringDEBUG(this.actionID);
        this.isDeviceHack = StrContains(idStr, "DeviceAction");
        this.isPuppetHack = StrContains(idStr, "QuickHack") || !this.isDeviceHack;
        
        // Set priority for category-aware queuing (higher = executed first)
        this.priority = this.CalculatePriority();
        
        QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Registered: \(this.displayName) category=\(ToString(this.categoryName)) priority=\(this.priority)");
    }
    
    // v1.63 compatible: Category detection using string patterns
    private func DetectCategoryFromID(actionID: TweakDBID) -> CName {
        let idStr: String = TDBID.ToStringDEBUG(actionID);
        
        // Pattern matching based on known v1.63 quickhack IDs
        if StrContains(idStr, "Covert") || StrContains(idStr, "BlindHack") || StrContains(idStr, "Ping") || 
           StrContains(idStr, "WhistleHack") || StrContains(idStr, "DistractEnemies") {
            return n"CovertHack";
        } else if StrContains(idStr, "Control") || StrContains(idStr, "WeaponGlitch") || StrContains(idStr, "LocomotionMalfunction") || 
                  StrContains(idStr, "DisableCyberware") || StrContains(idStr, "MemoryWipe") {
            return n"ControlHack";
        } else if StrContains(idStr, "Damage") || StrContains(idStr, "OverheatHack") || StrContains(idStr, "ShortCircuitHack") || 
                  StrContains(idStr, "SynapseBurnout") || StrContains(idStr, "CommsNoise") {
            return n"DamageHack";
        } else if StrContains(idStr, "Ultimate") || StrContains(idStr, "SuicideHack") || StrContains(idStr, "SystemCollapse") || 
                  StrContains(idStr, "MadnessHack") {
            return n"UltimateHack";
        } else if StrContains(idStr, "Vehicle") || StrContains(idStr, "TakeControl") || StrContains(idStr, "ForceBrakes") {
            return n"VehicleHack";
        } else {
            return n"DamageHack"; // Safe default for unknown hacks
        }
    }
    
    private func CalculatePriority() -> Int32 {
        // Priority system for smart queuing: Covert -> Control -> Damage -> Ultimate
        // v1.63 compatible: Use CName instead of enum
        if Equals(this.categoryName, n"CovertHack") {
            return 400; // Highest priority - stealthy setup
        } else if Equals(this.categoryName, n"ControlHack") {
            return 300; // High priority - disabling/control
        } else if Equals(this.categoryName, n"VehicleHack") {
            return 250; // Medium-high priority - vehicle control
        } else if Equals(this.categoryName, n"DamageHack") {
            return 200; // Medium priority - direct damage
        } else if Equals(this.categoryName, n"UltimateHack") {
            return 100; // Lower priority - powerful but should go last
        } else {
            return 150; // Default priority
        }
    }
    
    // Enhanced fallback method for creating friendly display names
    private func CreateFriendlyName(actionID: TweakDBID) -> String {
        let idStr: String = TDBID.ToStringDEBUG(actionID);
        
        // Extract the hack name part (e.g., "QuickHack.OverheatHack" -> "OverheatHack")
        let hackName: String = idStr;
        if StrContains(idStr, ".") {
            let parts: array<String> = StrSplit(idStr, ".");
            if ArraySize(parts) > 1 {
                hackName = parts[ArraySize(parts) - 1];
            }
        }
        
        // Map technical names to friendly display names
        if StrContains(hackName, "BlindLvl2Hack") || StrContains(hackName, "BlindHack") {
            return "Reboot Optics";
        } else if StrContains(hackName, "LocomotionMalfunctionHack") {
            return "Cripple Movement";
        } else if StrContains(hackName, "OverheatHack") {
            return "Overheat";
        } else if StrContains(hackName, "ShortCircuitHack") {
            return "Short Circuit";
        } else if StrContains(hackName, "SynapseBurnoutHack") {
            return "Synapse Burnout";
        } else if StrContains(hackName, "WeaponGlitchHack") {
            return "Weapon Glitch";
        } else if StrContains(hackName, "DisableCyberwareHack") {
            return "Disable Cyberware";
        } else if StrContains(hackName, "MemoryWipeHack") {
            return "Memory Wipe";
        } else if StrContains(hackName, "PingHack") {
            return "Ping";
        } else if StrContains(hackName, "WhistleHack") {
            return "Whistle";
        } else if StrContains(hackName, "DistractEnemiesHack") {
            return "Distract Enemies";
        } else if StrContains(hackName, "CommsNoiseHack") {
            return "Comms Noise";
        } else if StrContains(hackName, "SuicideHack") {
            return "Suicide";
        } else if StrContains(hackName, "SystemCollapseHack") {
            return "System Collapse";
        } else if StrContains(hackName, "MadnessHack") {
            return "Madness";
        } else if StrContains(hackName, "TakeControlHack") {
            return "Take Control";
        } else if StrContains(hackName, "ForceBrakesHack") {
            return "Force Brakes";
        } else {
            // Generic fallback - clean up the technical name
            let cleanName: String = StrReplace(hackName, "Hack", "");
            cleanName = StrReplace(cleanName, "Lvl2", "");
            cleanName = StrReplace(cleanName, "Lvl3", "");
            cleanName = StrReplace(cleanName, "Lvl4", "");
            cleanName = StrReplace(cleanName, "Lvl5", "");
            
            // Simple fallback - just return the cleaned name
            // v1.63 doesn't have reliable string manipulation functions
            return cleanName;
        }
    }
}

// =============================================================================
// MAIN NPC QUICKHACK CATALOG CLASS
// =============================================================================

// Dynamic quickhack catalog with v1.63-compatible array-based storage
public class NPCQuickhackCatalog {
    // v1.63 compatible: Use arrays instead of HashMap
    private let m_allHacks: array<ref<QuickhackCatalogEntry>>;
    private let m_covertHacks: array<ref<QuickhackCatalogEntry>>;
    private let m_controlHacks: array<ref<QuickhackCatalogEntry>>;
    private let m_damageHacks: array<ref<QuickhackCatalogEntry>>;
    private let m_ultimateHacks: array<ref<QuickhackCatalogEntry>>;
    private let m_vehicleHacks: array<ref<QuickhackCatalogEntry>>;
    private let m_deviceHacks: array<ref<QuickhackCatalogEntry>>;
    private let m_isInitialized: Bool;
    private let m_totalHacksFound: Int32;
    
    public func Initialize() -> Void {
        if this.m_isInitialized {
            QueueModLog(n"DEBUG", n"CATALOG", "[Catalog] Already initialized, skipping");
            return;
        }
        
        QueueModLog(n"DEBUG", n"CATALOG", "[Catalog] Building complete quickhack catalog from TweakDB...");
        
        // v1.63 compatible: Initialize arrays instead of HashMap
        ArrayClear(this.m_allHacks);
        ArrayClear(this.m_covertHacks);
        ArrayClear(this.m_controlHacks);
        ArrayClear(this.m_damageHacks);
        ArrayClear(this.m_ultimateHacks);
        ArrayClear(this.m_vehicleHacks);
        ArrayClear(this.m_deviceHacks);
        this.m_totalHacksFound = 0;
        
        this.BuildCompleteCatalog();
        this.m_isInitialized = true;
        
        QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Complete! Found \(this.m_totalHacksFound) quickhacks with category organization");
    }
    
    // Core enumeration method using proven v1.63 RPGManager pattern
    private func BuildCompleteCatalog() -> Void {
        QueueModLog(n"DEBUG", n"CATALOG", "[Catalog] Building catalog from player's available quickhacks...");
        
        // Get player instance using proper v1.63 pattern
        let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(GetGameInstance());
        if !IsDefined(playerSystem) {
            QueueModLog(n"ERROR", n"CATALOG", "[Catalog] Cannot get PlayerSystem for quickhack enumeration");
            return;
        }
        
        let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            QueueModLog(n"ERROR", n"CATALOG", "[Catalog] Cannot get player instance for quickhack enumeration");
            return;
        }
        
        // Use the proven v1.63 method - RPGManager.GetPlayerQuickHackListWithQuality()
        let playerQuickhacks: array<PlayerQuickhackData> = RPGManager.GetPlayerQuickHackListWithQuality(player);
        
        if ArraySize(playerQuickhacks) == 0 {
            QueueModLog(n"DEBUG", n"CATALOG", "[Catalog] No quickhacks available - player may not have cyberdeck equipped");
            return;
        }
        
        // Process each available quickhack
        let i: Int32 = 0;
        while i < ArraySize(playerQuickhacks) {
            if IsDefined(playerQuickhacks[i].actionRecord) {
                this.ProcessQuickhackRecord(playerQuickhacks[i].actionRecord, playerQuickhacks[i].quality);
            }
            i += 1;
        }
        
        QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Player quickhack enumeration complete - processed \(this.m_totalHacksFound) available quickhacks");
        this.LogCategoryBreakdown();
    }
    
    private func ProcessQuickhackRecord(record: ref<ObjectAction_Record>, quality: Int32) -> Void {
        if !IsDefined(record) {
            return;
        }
        
        // CRITICAL FIX: Filter for NPC quickhacks only (exclude device hacks)
        let actionType: gamedataObjectActionType = record.ObjectActionType().Type();
        if Equals(actionType, gamedataObjectActionType.DeviceQuickHack) {
            // Skip device hacks - we only want NPC-targetable quickhacks
            return;
        }
        
        // Additional filter: Only process PuppetQuickHack types
        if NotEquals(actionType, gamedataObjectActionType.PuppetQuickHack) {
            // Skip non-puppet actions
            return;
        }
        
        QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Processing NPC quickhack: \(record.ObjectActionUI().Caption()) type=\(ToString(actionType))");
        
        let entry: ref<QuickhackCatalogEntry> = new QuickhackCatalogEntry();
        entry.Initialize(record);
        
        // Store quality from player's equipment
        entry.baseCost = quality; // Use quality as base cost indicator
        
        // v1.63 compatible: Store in arrays instead of HashMap
        ArrayPush(this.m_allHacks, entry);
        
        // Store by category for smart queuing
        this.AddToCategoryArray(entry);
        
        this.m_totalHacksFound += 1;
    }
    
    // v1.63 compatible: Use categoryName directly for organization
    private func AddToCategoryArray(entry: ref<QuickhackCatalogEntry>) -> Void {
        // Use categoryName directly instead of categoryRecord check
        let categoryName: CName = entry.categoryName;
        
        if Equals(categoryName, n"CovertHack") {
            ArrayPush(this.m_covertHacks, entry);
        } else if Equals(categoryName, n"ControlHack") {
            ArrayPush(this.m_controlHacks, entry);
        } else if Equals(categoryName, n"DamageHack") {
            ArrayPush(this.m_damageHacks, entry);
        } else if Equals(categoryName, n"UltimateHack") {
            ArrayPush(this.m_ultimateHacks, entry);
        } else if Equals(categoryName, n"VehicleHack") {
            ArrayPush(this.m_vehicleHacks, entry);
        } else {
            // Default to device hacks for unknown categories
            ArrayPush(this.m_deviceHacks, entry);
            QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Unknown category '\(ToString(categoryName))' -> DeviceHack fallback");
        }
    }
    
    private func LogCategoryBreakdown() -> Void {
        QueueModLog(n"DEBUG", n"CATALOG", "[Catalog] Category breakdown:");
        
        // v1.63 compatible: Log each category with count using ArraySize
        if ArraySize(this.m_covertHacks) > 0 {
            QueueModLog(n"DEBUG", n"CATALOG", s"  CovertHack: \(ArraySize(this.m_covertHacks)) quickhacks");
        }
        if ArraySize(this.m_controlHacks) > 0 {
            QueueModLog(n"DEBUG", n"CATALOG", s"  ControlHack: \(ArraySize(this.m_controlHacks)) quickhacks");
        }
        if ArraySize(this.m_damageHacks) > 0 {
            QueueModLog(n"DEBUG", n"CATALOG", s"  DamageHack: \(ArraySize(this.m_damageHacks)) quickhacks");
        }
        if ArraySize(this.m_ultimateHacks) > 0 {
            QueueModLog(n"DEBUG", n"CATALOG", s"  UltimateHack: \(ArraySize(this.m_ultimateHacks)) quickhacks");
        }
        if ArraySize(this.m_vehicleHacks) > 0 {
            QueueModLog(n"DEBUG", n"CATALOG", s"  VehicleHack: \(ArraySize(this.m_vehicleHacks)) quickhacks");
        }
        if ArraySize(this.m_deviceHacks) > 0 {
            QueueModLog(n"DEBUG", n"CATALOG", s"  DeviceHack: \(ArraySize(this.m_deviceHacks)) quickhacks");
        }
    }
    
    // =============================================================================
    // PUBLIC CATALOG ACCESS METHODS
    // =============================================================================
    
    // v1.63 compatible: Array-based lookup by display name with fuzzy matching
    public func FindQuickhackByName(displayName: String) -> ref<QuickhackCatalogEntry> {
        if !this.m_isInitialized {
            this.Initialize();
        }
        
        if Equals(displayName, "") {
            return null;
        }
        
        // First pass: Exact match
        let i: Int32 = 0;
        while i < ArraySize(this.m_allHacks) {
            if IsDefined(this.m_allHacks[i]) && Equals(this.m_allHacks[i].displayName, displayName) {
                return this.m_allHacks[i];
            }
            i += 1;
        }
        
        // Second pass: Fuzzy matching for common variations
        let searchName: String = StrLower(displayName);
        let j: Int32 = 0;
        while j < ArraySize(this.m_allHacks) {
            if IsDefined(this.m_allHacks[j]) {
                let hackName: String = StrLower(this.m_allHacks[j].displayName);
                
                // Fuzzy match common variations
                if (Equals(searchName, "overheat") && StrContains(hackName, "overheat")) ||
                   (Equals(searchName, "reboot optics") && StrContains(hackName, "blind")) ||
                   (Equals(searchName, "short circuit") && StrContains(hackName, "short")) ||
                   (Equals(searchName, "synapse burnout") && StrContains(hackName, "synapse")) ||
                   (StrContains(hackName, searchName) && StrLen(searchName) > 3) {
                    QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] Fuzzy match found: '\(displayName)' -> '\(this.m_allHacks[j].displayName)'");
                    return this.m_allHacks[j];
                }
            }
            j += 1;
        }
        
        QueueModLog(n"DEBUG", n"CATALOG", s"[Catalog] No quickhack found for name: \(displayName)");
        return null;
    }
    
    // v1.63 compatible: Array-based lookup by TweakDBID
    public func FindQuickhackByID(actionID: TweakDBID) -> ref<QuickhackCatalogEntry> {
        if !this.m_isInitialized {
            this.Initialize();
        }
        
        if !TDBID.IsValid(actionID) {
            return null;
        }
        
        // Linear search through all hacks
        let i: Int32 = 0;
        while i < ArraySize(this.m_allHacks) {
            if IsDefined(this.m_allHacks[i]) && Equals(this.m_allHacks[i].actionID, actionID) {
                return this.m_allHacks[i];
            }
            i += 1;
        }
        
        return null;
    }
    
    // v1.63 compatible: Return category arrays directly
    public func GetHacksInCategory(category: CName) -> array<ref<QuickhackCatalogEntry>> {
        if !this.m_isInitialized {
            this.Initialize();
        }
        
        if Equals(category, n"CovertHack") {
            return this.m_covertHacks;
        } else if Equals(category, n"ControlHack") {
            return this.m_controlHacks;
        } else if Equals(category, n"DamageHack") {
            return this.m_damageHacks;
        } else if Equals(category, n"UltimateHack") {
            return this.m_ultimateHacks;
        } else if Equals(category, n"VehicleHack") {
            return this.m_vehicleHacks;
        } else if Equals(category, n"DeviceHack") {
            return this.m_deviceHacks;
        }
        
        // Return empty array if category not found
        let emptyArray: array<ref<QuickhackCatalogEntry>>;
        return emptyArray;
    }
    
    // v1.63 compatible: Return the complete array directly
    public func GetAllQuickhacks() -> array<ref<QuickhackCatalogEntry>> {
        if !this.m_isInitialized {
            this.Initialize();
        }
        
        return this.m_allHacks;
    }
    
    // v1.63 compatible: Simple bubble sort implementation
    public func GetHacksByPriority(ascending: Bool) -> array<ref<QuickhackCatalogEntry>> {
        let allHacks: array<ref<QuickhackCatalogEntry>> = this.GetAllQuickhacks();
        let hackCount: Int32 = ArraySize(allHacks);
        
        if hackCount <= 1 {
            return allHacks;
        }
        
        // Simple bubble sort by priority (sufficient for quickhack counts)
        let i: Int32 = 0;
        while i < hackCount - 1 {
            let j: Int32 = 0;
            while j < hackCount - i - 1 {
                let shouldSwap: Bool = false;
                if IsDefined(allHacks[j]) && IsDefined(allHacks[j + 1]) {
                    if ascending {
                        shouldSwap = allHacks[j].priority > allHacks[j + 1].priority;
                    } else {
                        shouldSwap = allHacks[j].priority < allHacks[j + 1].priority;
                    }
                    
                    if shouldSwap {
                        let temp: ref<QuickhackCatalogEntry> = allHacks[j];
                        allHacks[j] = allHacks[j + 1];
                        allHacks[j + 1] = temp;
                    }
                }
                j += 1;
            }
            i += 1;
        }
        
        return allHacks;
    }
    
    public func GetTotalHackCount() -> Int32 {
        if !this.m_isInitialized {
            this.Initialize();
        }
        return this.m_totalHacksFound;
    }
    
    // =============================================================================
    // INTEGRATION POINT - Replace manual FindActionTweakID()
    // =============================================================================
    
    // Critical integration method to replace manual mappings
    public func GetTweakIDForDisplayName(displayName: String) -> TweakDBID {
        let entry: ref<QuickhackCatalogEntry> = this.FindQuickhackByName(displayName);
        if IsDefined(entry) {
            return entry.actionID;
        }
        return TDBID.None();
    }
    
    // =============================================================================
    // SMART QUEUING SUPPORT
    // =============================================================================
    
    // Get recommended queue order for multiple quickhacks
    public func GetOptimalQueueOrder(hackIDs: array<TweakDBID>) -> array<TweakDBID> {
        let entriesWithPriority: array<ref<QuickhackCatalogEntry>>;
        
        // Convert IDs to catalog entries
        let i: Int32 = 0;
        while i < ArraySize(hackIDs) {
            let entry: ref<QuickhackCatalogEntry> = this.FindQuickhackByID(hackIDs[i]);
            if IsDefined(entry) {
                ArrayPush(entriesWithPriority, entry);
            }
            i += 1;
        }
        
        // Sort by priority (descending - highest priority first)
        let j: Int32 = 0;
        while j < ArraySize(entriesWithPriority) - 1 {
            let k: Int32 = 0;
            while k < ArraySize(entriesWithPriority) - j - 1 {
                if entriesWithPriority[k].priority < entriesWithPriority[k + 1].priority {
                    let temp: ref<QuickhackCatalogEntry> = entriesWithPriority[k];
                    entriesWithPriority[k] = entriesWithPriority[k + 1];
                    entriesWithPriority[k + 1] = temp;
                }
                k += 1;
            }
            j += 1;
        }
        
        // Convert back to TweakDBID array
        let orderedIDs: array<TweakDBID>;
        let m: Int32 = 0;
        while m < ArraySize(entriesWithPriority) {
            ArrayPush(orderedIDs, entriesWithPriority[m].actionID);
            m += 1;
        }
        
        return orderedIDs;
    }
}

// =============================================================================
// GLOBAL CATALOG INSTANCE
// =============================================================================

// =============================================================================
// GLOBAL CATALOG SINGLETON - v1.63 Compatible
// =============================================================================

// v1.63 compatible: Get catalog from player instead of global singleton
public func GetQuickhackCatalog() -> ref<NPCQuickhackCatalog> {
    let playerSystem: ref<PlayerSystem> = GameInstance.GetPlayerSystem(GetGameInstance());
    if !IsDefined(playerSystem) {
        QueueModLog(n"ERROR", n"CATALOG", "[Integration] Cannot get PlayerSystem for catalog access");
        return null;
    }
    
    let player: ref<PlayerPuppet> = playerSystem.GetLocalPlayerMainGameObject() as PlayerPuppet;
    if !IsDefined(player) {
        QueueModLog(n"ERROR", n"CATALOG", "[Integration] Cannot get player for catalog access");
        return null;
    }
    
    return player.GetNPCQuickhackCatalog();
}
