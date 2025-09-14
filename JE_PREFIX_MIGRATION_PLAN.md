# JE_ Prefix Migration Plan

**Creator:** johnnys-engram  
**Target:** HackQueueMod v1.0.0 → v2.0.0  
**Purpose:** Mod safety through namespace isolation

## Overview

The JE_ prefix system will be implemented to prevent conflicts with other mods by creating a unique namespace for all HackQueueMod identifiers.

## Migration Strategy

### Class Renaming
Current classes will be prefixed with `JE_` to ensure uniqueness:

- `QueueModEntry` → `JE_QueueModEntry`
- `QueueModActionQueue` → `JE_QueueModActionQueue`
- `QueueModEvent` → `JE_QueueModEvent`
- `QueueModHelper` → `JE_QueueModHelper`
- `QuickhackQueueHelper` → `JE_QuickhackQueueHelper`
- `QueueModCommandGenEvent` → `JE_QueueModCommandGenEvent`
- `QueueModCacheEvent` → `JE_QueueModCacheEvent`
- `QueueModValidationEvent` → `JE_QueueModValidationEvent`

### Function Renaming
Static and global functions will receive JE_ prefix:

- `CreateQueueModEntry()` → `JE_CreateQueueModEntry()`
- `GetHackQueueModVersion()` → `JE_GetHackQueueModVersion()`
- `GetHackQueueModCreator()` → `JE_GetHackQueueModCreator()`
- `GetHackQueueModTargetVersion()` → `JE_GetHackQueueModTargetVersion()`

### Field Renaming
addField declarations will use JE_ prefix:

- `m_queueModActionQueue` → `m_JE_queueModActionQueue`
- `m_queueModHelper` → `m_JE_queueModHelper`
- `m_qmQuickhackController` → `m_JE_quickhackController`
- `m_qmPoolsRegistered` → `m_JE_poolsRegistered`
- `m_qmRefreshScheduled` → `m_JE_refreshScheduled`
- `m_qmControllerStored` → `m_JE_controllerStored`

### Method Renaming
addMethod declarations will use JE_ prefix:

- `GetQueueModActionQueue()` → `GetJE_QueueModActionQueue()`
- `IsQueueModEnabled()` → `IsJE_QueueModEnabled()`
- `IsQueueModFull()` → `IsJE_QueueModFull()`
- `QueueModQuickHack()` → `JE_QueueModQuickHack()`
- `GetQueueModHelper()` → `GetJE_QueueModHelper()`
- All internal methods starting with `QueueMod*` → `JE_*`

### Debug Channel Renaming
LogChannel calls will use JE_ prefix:

- `LogChannel(n"DEBUG", "[QueueMod] ...")` → `LogChannel(n"DEBUG", "[JE_HackQueue] ...")`
- All debug messages will be updated for consistency

### Event Names
Custom event types will receive JE_ prefix:

- Event system interactions will use `JE_` prefixed event names
- CName constants will be updated: `n"QueueMod*"` → `n"JE_*"`

## Implementation Timeline

### Phase 1: Preparation (v1.1.0)
- Document current architecture
- Create migration scripts
- Backup current implementation
- Test compatibility matrices

### Phase 2: Core Migration (v2.0.0-alpha)
- Rename all classes and functions
- Update all references
- Test basic functionality
- Validate v1.63 compatibility

### Phase 3: Integration Testing (v2.0.0-beta)
- Full integration testing
- Performance validation
- Compatibility with other mods
- Edge case validation

### Phase 4: Release (v2.0.0)
- Final testing and validation
- Documentation updates
- Migration guide for users
- Deprecation notices for old names

## Backward Compatibility

### Compatibility Strategy
- Maintain wrapper functions for one version cycle
- Provide deprecation warnings
- Clear migration documentation
- Gradual phase-out of old identifiers

### User Impact
- No immediate user action required
- Automatic migration on mod update
- Clear communication about changes
- Support for troubleshooting

## Safety Considerations

### Conflict Prevention
- Unique namespace isolation
- Reduced mod interaction conflicts
- Cleaner debugging experience
- Professional naming standards

### Testing Requirements
- Full regression testing
- Multi-mod compatibility testing
- Performance impact analysis
- Memory usage validation

## Development Notes

### Current Status
- **Planning Phase:** Complete
- **Implementation:** Not started
- **Testing:** Pending
- **Release:** Future v2.0.0

### Dependencies
- No new framework dependencies
- Maintains v1.63 compatibility
- redscript 0.5.14 support
- Same technical requirements

## Migration Commands (Future Reference)

```bash
# These commands will be used during migration:
# find . -name "*.reds" -exec sed -i 's/QueueModEntry/JE_QueueModEntry/g' {} \;
# find . -name "*.reds" -exec sed -i 's/QueueModActionQueue/JE_QueueModActionQueue/g' {} \;
# find . -name "*.reds" -exec sed -i 's/\[QueueMod\]/[JE_HackQueue]/g' {} \;
```

## Contact

For questions about the JE_ prefix migration, contact johnnys-engram or reference this documentation.
