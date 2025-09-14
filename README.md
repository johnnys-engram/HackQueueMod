# HackQueueMod

**Creator:** johnnys-engram  
**Version:** 1.0.0  
**Target:** Cyberpunk 2077 v1.63  
**Framework:** redscript 0.5.14

## Description

HackQueueMod allows players to queue quickhacks during upload/cooldown periods in Cyberpunk 2077 v1.63. When a quickhack is uploading or on cooldown, you can select additional quickhacks to queue up for automatic execution once the current upload completes.

## Features

- **Queue System:** Queue up to 3 quickhacks per target during upload/cooldown
- **RAM Management:** Proper RAM deduction and refunds with validation
- **UI Integration:** Seamless integration with the quickhack wheel interface
- **Death Detection:** Automatic queue cleanup when targets die
- **Multi-Target Support:** Works with both NPCs and devices
- **Cooldown Handling:** Maintains proper cooldown states and UI feedback

## Requirements

- **Game Version:** Cyberpunk 2077 v1.63 (NOT 2.0+)
- **redscript:** 0.5.14 exactly
- **RED4ext:** 1.15.0
- **CET:** 1.25.2
- **TweakXL:** 1.2.1
- **ArchiveXL:** 1.5.11

## Installation

1. Ensure you have the required modding frameworks installed
2. Place `HackQueueMod.reds` in your `r6/scripts/` directory
3. Launch the game and enjoy queued quickhacks!

## How It Works

1. **Upload Detection:** The mod detects when a quickhack is uploading or on cooldown
2. **Queue Interface:** Additional quickhacks become available for selection during this time
3. **RAM Reservation:** RAM is deducted immediately when queuing (not on execution)
4. **Automatic Execution:** Queued quickhacks execute automatically when the current upload completes
5. **Cleanup:** Queues are cleared if the target dies or becomes unconscious

## Technical Architecture

The mod uses a multi-phase implementation approach:

- **Phase 1:** Core queue foundation and target resolution
- **Phase 2:** Execution pipeline and upload tracking  
- **Phase 3:** UI integration and queue management
- **Phase 4:** Polish and bug fixes

## Safety Features

- Comprehensive null checking for all game object interactions
- Queue integrity validation with emergency cleanup
- Death/unconscious detection with automatic queue clearing
- RAM validation to prevent negative values
- Race condition prevention with queue locking

## Compatibility

This mod is specifically designed for Cyberpunk 2077 v1.63 and uses v1.63-compatible API patterns. It will NOT work with version 2.0+ due to significant API changes.

## Known Issues

⚠️ **Important:** See [KNOWN_BUGS.md](KNOWN_BUGS.md) for a comprehensive list of known issues and bugs.

### Critical Known Bugs:
- **Crippling Movement Cooldown:** Doesn't activate cooldown in vanilla outside queue (but other quickhacks do)
- **RAM Deduction:** RAM costs not properly deducted when queuing quickhacks

## Troubleshooting

- **Queue not working:** Ensure you're on v1.63 and have all required frameworks
- **RAM issues:** Check that you have sufficient RAM for queued quickhacks
- **UI not updating:** Try closing and reopening the quickhack wheel
- **Performance issues:** The mod is optimized for v1.63's constraints
- **Known bugs:** Check KNOWN_BUGS.md for documented issues and workarounds

## Future Development

- JE_ prefix system for enhanced mod safety
- Dynamic queue size based on perks and cyberware
- Visual HUD overlays for queue status
- Enhanced notification system
- Integration with perk trees and cyberdeck modifications

## Credits

**Creator:** johnnys-engram  
**Framework:** redscript community  
**Testing:** CP2077 v1.63 modding community

## License

This mod is provided as-is for the Cyberpunk 2077 v1.63 modding community. Use at your own risk.
