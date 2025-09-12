Let me fix the debug test:
CORRECTED NPC Quickhack Queue Debug Test Block
EXPECTED FLOW:
Start quickhack on NPC → While uploading, queue more quickhacks on SAME NPC → First completes → Next queued action auto-executes on same NPC
TEST 1: Single NPC Queue Detection

Start any quickhack upload on NPC A
While it's uploading, try to use another quickhack on the SAME NPC A

Expected Logs:

[QueueMod] *** ApplyQuickHack called ***
[QueueMod] Should queue: true
[QueueMod] *** QUEUE SYSTEM ACTIVATED ***
[QueueMod] Attempting to queue action: [ActionClassName]
[QueueMod] Queueing PuppetAction

Questions:

Do you see "ApplyQuickHack called" when trying second hack on same NPC? Y/N
Do you see "Should queue: true"? Y/N
Do you see "QUEUE SYSTEM ACTIVATED"? Y/N
Can you even select quickhacks on the same NPC during upload? Y/N
Any error messages in console? Y/N - describe:

TEST 2: Same NPC Queue Storage
Continue from Test 1
Questions:
6. Do you see "Successfully queued PuppetAction"? Y/N
7. Do you see "Added action to queue. Size now: 1"? Y/N
8. Does the second quickhack go on cooldown immediately? Y/N
9. What happens when you try to quickhack the same NPC during upload?
TEST 3: Queue Execution on Same NPC
Let the initial upload complete on the same NPC
Questions:
10. Do you see "Upload completed, checking for queued actions"? Y/N
11. Does the queued quickhack automatically execute on the same NPC? Y/N
12. Do you see the queue size decrease? Y/N
13. What actually happens when the first quickhack finishes?
OVERALL:
14. Can you even access quickhacks on an NPC that's already being hacked? Y/N
15. Does the quickhack wheel show during an ongoing upload on that NPC? Y/N
16. At what point does the system fail?
17. Additional observations:
Thanks for the correction - this makes way more sense!