# LeagueRes 

**LeagueRes** is a lightweight World of Warcraft addon that implements a soft-reserve (SR) loot system for raids. It helps organize loot distribution by allowing players to reserve items in advance and guiding roll behavior during encounters.

---

##  Features

**Soft-Reserve System**

  * Players can reserve up to 2 items per raid
  * Reservations are visible to the entire raid

  **Raid-Wide Visibility**

  * View all player reservations in a clean UI
  * Automatically synced across the group

  **Loot Master Controls**

  * Broadcast raid settings
  * Lock/unlock soft-res submissions
  * Force full sync to all players

  **Smart Roll Guidance**

  * Highlights when an item is your reserve
  * Suggests pass/roll decisions
  * Automatically passes on reserved items

  **Raid Announcements**

  * Loot Master can announce reserved items and their owners in raid chat

  **Encounter Journal Integration**

  * Browse raid loot directly in-game
  * Select items easily via a built-in loot picker

---

##  Getting Started

1. Install the addon into:

   ```
   World of Warcraft/_retail_/Interface/AddOns/LeagueRes
   ```

2. Launch WoW and enable **LeagueRes** in the AddOns menu.

3. Open the UI:

   ```
   /lr
   ```

---

##  How It Works

1. Players select their soft-reserved items using the UI.
2. Submit reservations to the raid.
3. The Loot Master can:

   * Enable settings
   * Lock reservations
   * Sync data across the raid
     
4. During loot rolls:

   * Reserved players are identified
   * Others automatically pass on reserved loot
   * Loot not reserved is open for anyone to roll

---

##  Commands

| Command               | Description           |
| --------------------- | --------------------- |
| `/lr` or `/leagueres` | Open the LeagueRes UI |


---

##  Loot Master Settings

* **Soft-Res Slots** – Number of allowed reserves (UI currently only supports 2)
* **Allow Open Roll** – Allows rolling if nobody reserved the item
* **Max Wins** – Limit how many items a player can win
* **Lock SR** – Prevent further reservation changes

---

##  Technical Details

* Built using:

* Ace3 (AceAddon, AceComm, AceGUI, AceSerializer)
* Uses WoW Encounter Journal API for loot data
* Syncs data using addon communication channels (RAID/PARTY/INSTANCE)

---

##  Notes

* All players in the raid should have the addon for full functionality
* Loot Master features require raid leader or assistant permissions
* Some loot data may load asynchronously via the Encounter Journal

---

##  Development

This addon is actively being developed and improved.

Planned improvements:

* Enhanced loot filtering
* More flexible SR slot counts
* Improved sync reliability
* Item tooltip visibility directly in the loot picker panel

---

##  Contributing

Feel free to open issues or submit pull requests if you’d like to contribute!

---

##  License

MIT License

