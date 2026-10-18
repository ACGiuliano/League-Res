# LeagueRes 1.2.1

This update fixes a reproducible synchronization deadlock that can leave a player waiting for Loot Master confirmation or unable to see the master's reservation list.

## Install and recover the raid list

1. Exit WoW normally. Back up your addon folder and `WTF/Account/<account>/SavedVariables/LeagueRes.lua`.
2. Everyone should replace `Interface/AddOns/LeagueRes` with the `LeagueRes` folder from this ZIP. Keep your SavedVariables. Ace3 is still required.
3. Keep the player who already has the complete list as the Loot Master. That player should open `/lr` → **Loot Master** and click **Broadcast Full Sync**.
4. Affected players should open **Raid Status** and click **Request Sync**. Check that the list matches the master's list. Pending submissions retry against the master's current rules; a locked edit is rejected and the confirmed selection remains.
5. Use **Check Versions** to verify 1.2.1, then **Check Missing SRs** to check the current roster. Have any genuinely missing submitter submit again while reservations are unlocked.

Do not use **Clear All Reservations** to repair synchronization: it intentionally clears the collection. This update retains the master's saved list and does not reset the addon database. During recovery, an affected player's cached raid state is reconciled with the master, so entries that exist only in that player's unrelated stale generation are not retained as accepted raid reservations.

## Changes in 1.2.1

- A sync request carries a persistent unique request number. The master echoes it in a full snapshot with the requesting player's GUID.
- A fresh reply from the accepted Loot Master can repair a player's reset counter when it is ahead of the master. Previously, the player discarded every master reply as stale while the master rejected the player's submissions for having a different counter.
- Older unsolicited snapshots, replies to superseded requests, replies for another player, and replies invalidated by a later known clear cannot authorize that counter repair.
- Full snapshots use the raid/group addon channel, including responses to Request Sync. Recovery no longer depends on an addon whisper arriving. Other group members can also learn the current master from that snapshot.
- Automatic pending-submission retries request current raid state as well as resending the submission. The existing three-retry limit remains, and unanswered selections stay saved as pending.
- A pending submission is retried after counter recovery using the master's current rules. Recovery does not bypass SR locks or sender/authority validation.

The reservation protocol remains version 3. Install 1.2.1 on the master and affected clients to use request-correlated counter recovery. Older version-3 builds do not echo the new request number. Builds without the version-check feature cannot report their exact version.

## Existing features

Difficulty-aware reservations, the item picker fixes, character-specific saved selections and raid state, per-player submission sequence numbers, confirmation receipts, explicit role handoff, Check Missing SRs, and Check Versions remain included. Check Versions collects replies for five seconds and prints different versions and nonresponders locally. A nonresponse can also mean an offline player, missing/disabled addon, older build, or missed message.

SavedVariables are written on normal logout, exit, or `/reload`; a hard crash can lose the newest changes. Data that no client still holds cannot be reconstructed by this update.

## Validation

197 checks pass: 86 existing feature/regression checks and 111 multi-client checks. The added cases reproduce the original counter deadlock and verify recovery, dropped receipts, group-channel snapshots, request correlation, replay protection after a known clear, locked recovery, and bounded retries. Existing coverage includes 20-player convergence, reordered messages, relogs, competing masters, explicit clears, and repeated UI reopening.

These tests execute addon Lua against simulated WoW/Ace APIs. They do not test actual AceComm delivery or run inside WoW. Before raid loot, have two players submit different items, verify confirmation and matching lists, reopen the window, and reload one player. Check that both entries remain.

The tests are included but are not loaded by the addon. From the folder containing the extracted `LeagueRes` folder:

```sh
texlua LeagueRes/tests/regression.lua LeagueRes/
texlua LeagueRes/tests/sync-regression.lua LeagueRes/
```
