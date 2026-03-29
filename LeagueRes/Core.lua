local ADDON, NS = ...
local AceAddon = LibStub("AceAddon-3.0")

local LeagueRes = AceAddon:NewAddon("LeagueRes", "AceEvent-3.0", "AceComm-3.0", "AceConsole-3.0")
NS.Addon = LeagueRes

function LeagueRes:OnInitialize()
  LeagueResDB = LeagueResDB or {}
  LeagueResDB.profile = LeagueResDB.profile or {}

  -- merge defaults 
  for k, v in pairs(NS.DEFAULTS.profile) do
    if LeagueResDB.profile[k] == nil then
      LeagueResDB.profile[k] = v
    end
  end
  for k, v in pairs(NS.DEFAULTS.profile.settings) do
    if LeagueResDB.profile.settings[k] == nil then
      LeagueResDB.profile.settings[k] = v
    end
  end
  if not LeagueResDB.profile.mySR then
    LeagueResDB.profile.mySR = {0, 0}
  end
  if not LeagueResDB.profile.ej then
    LeagueResDB.profile.ej = { tierIndex=nil, instanceID=nil, difficultyID=14 }
  end

  C_ChatInfo.RegisterAddonMessagePrefix(NS.PREFIX)

  self:RegisterComm(NS.PREFIX, function(_, msg, channel, sender)
    NS.Comm:HandleMessage(NS.PREFIX, msg, channel, sender)
  end)

  self:RegisterChatCommand("leagueres", function() NS.UI:OpenMain() end)
  self:RegisterChatCommand("lr", function() NS.UI:OpenMain() end)

  print("|cff00ff00LeagueRes loaded.|r Type /lr")
end

function LeagueRes:OnEnable()
  self:RegisterEvent("GROUP_ROSTER_UPDATE", function() NS:RebuildRoster() end)
  self:RegisterEvent("START_LOOT_ROLL", function(_, rollID) NS.Loot:OnStartLootRoll(rollID) end)

  -- EJ loot can arrive async; refresh the list if open
  self:RegisterEvent("EJ_LOOT_DATA_RECEIVED", function()
    if NS.UI and NS.UI.RefreshEJList then
      NS.UI:RefreshEJList(true)
    end
  end)

  NS:RebuildRoster()
  NS:RequestSync()
end

-- === Core behaviors ===

function NS:RebuildRoster()
  wipe(NS.State.raid.nameByGuid)

  if not IsInGroup() then return end

  local n = GetNumGroupMembers()
  if n == 0 then return end

  for i = 1, n do
    local unit = "raid" .. i
    if UnitExists(unit) then
      local guid = UnitGUID(unit)
      local name = GetUnitName(unit, true)
      if guid and name then
        NS.State.raid.nameByGuid[guid] = name
      end
    end
  end

  local me = UnitGUID("player")
  local myName = GetUnitName("player", true)
  if me and myName then
    NS.State.raid.nameByGuid[me] = myName
  end
end

function NS:RequestSync()
  if not NS:IsInRaid() then return end
  NS.Comm:Broadcast({ t = "HELLO", v = 1 })
end

function NS:SubmitMySR(id1, id2)
  if not NS:IsInRaid() then
    print("|cffff0000LeagueRes:|r Not in a raid.")
    return
  end

  NS.Comm:Broadcast({
    t = "RESERVE",
    v = 1,
    guid = NS:GetPlayerGuid(),
    sr = { id1 or 0, id2 or 0 }
  })

  NS.State.raid.reservationsByGuid[NS:GetPlayerGuid()] = { id1 or 0, id2 or 0 }
  NS.State.raid.nameByGuid[NS:GetPlayerGuid()] = GetUnitName("player", true)

  if NS.UI and NS.UI.RefreshRaidPanel then
  NS.UI:RefreshRaidPanel()
  end

  print("|cff00ff00LeagueRes:|r Submitted soft-res.")
end

function NS:BroadcastSettings()
  if not LeagueResDB.profile.isLootMaster then
    print("|cffff0000LeagueRes:|r Enable Loot Master checkbox first.")
    return
  end

  local s = LeagueResDB.profile.settings
  NS.State.raid.settings = s
  NS.State.raid.locked = s.lockSR and true or false
  NS.State.raid.lootMasterGuid = NS:GetPlayerGuid()

  NS.Comm:Broadcast({ t = "SETTINGS", v = 1, settings = s, lm = NS:GetPlayerGuid() })
  NS:BroadcastFullSync()

  print("|cff00ff00LeagueRes:|r Settings broadcast.")
end

function NS:BroadcastFullSync()
  if not LeagueResDB.profile.isLootMaster then
    print("|cffff0000LeagueRes:|r Enable Loot Master checkbox first.")
    return
  end

  NS.Comm:Broadcast({
    t = "FULLSYNC",
    v = 1,
    settings = LeagueResDB.profile.settings,
    lm = NS:GetPlayerGuid(),
    reservations = NS.State.raid.reservationsByGuid,
    wins = NS.State.raid.winsByGuid,
  })

  print("|cff00ff00LeagueRes:|r Full sync broadcast.")
end

function NS:OnComm(msg, sender)
  print("LeagueRes received:", msg.t or "nil", "from", sender or "unknown")
  if msg.t == "HELLO" then
    if LeagueResDB.profile.isLootMaster then
      NS:BroadcastSettings()
      NS:BroadcastFullSync()
    end
    return
  end

  if msg.t == "SETTINGS" and msg.settings then
  NS.State.raid.settings = msg.settings
  NS.State.raid.locked = msg.settings.lockSR and true or false
  NS.State.raid.lootMasterGuid = msg.lm

  if NS.UI and NS.UI.RefreshRaidPanel then
    NS.UI:RefreshRaidPanel()
  end

  return
end

if msg.t == "RESERVE" and msg.guid and msg.sr then
  NS.State.raid.reservationsByGuid[msg.guid] = { msg.sr[1] or 0, msg.sr[2] or 0 }

  -- store sender name if we have it
  if sender and sender ~= "" then
    NS.State.raid.nameByGuid[msg.guid] = sender
  end

  -- refresh UI if open
  if NS.UI and NS.UI.RefreshRaidPanel then
    NS.UI:RefreshRaidPanel()
  end

  -- if I'm the loot master, rebroadcast the authoritative full state
  if LeagueResDB and LeagueResDB.profile and LeagueResDB.profile.isLootMaster then
    NS:BroadcastFullSync()
  end

  return
end

  if msg.t == "FULLSYNC" then
  if msg.settings then
    NS.State.raid.settings = msg.settings
    NS.State.raid.locked = msg.settings.lockSR and true or false
  end
  if msg.lm then NS.State.raid.lootMasterGuid = msg.lm end
  if type(msg.reservations) == "table" then
    NS.State.raid.reservationsByGuid = msg.reservations
  end
  if type(msg.wins) == "table" then
    NS.State.raid.winsByGuid = msg.wins
  end

  if NS.UI and NS.UI.RefreshRaidPanel then
    NS.UI:RefreshRaidPanel()
  end

  return
  end
end