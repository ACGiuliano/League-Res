local ADDON, NS = ...
local AceAddon = LibStub("AceAddon-3.0")
local LeagueRes = AceAddon:NewAddon("LeagueRes", "AceEvent-3.0", "AceComm-3.0", "AceConsole-3.0")
NS.Addon = LeagueRes

function LeagueRes:OnInitialize()
  LeagueResDB = LeagueResDB or {}
  LeagueResDB.profile = LeagueResDB.profile or {}
  local profile = LeagueResDB.profile
  for k, v in pairs(NS.DEFAULTS.profile) do
    if profile[k] == nil then profile[k] = NS:Copy(v) end
  end
  for k, v in pairs(NS.DEFAULTS.profile.settings) do
    if profile.settings[k] == nil then profile.settings[k] = NS:Copy(v) end
  end

  -- Draft selections and submitted raid state belong to a character, not the account.
  LeagueResDB.characters = LeagueResDB.characters or {}
  local guid = NS:GetPlayerGuid()
  local character = LeagueResDB.characters[guid]
  if not character then
    character = { mySR = {0, 0}, raid = NS:Copy(NS.State.raid) }
    if not LeagueResDB.legacyMigrated then
      character.mySR = NS:Copy(profile.mySR)
      LeagueResDB.legacyMigrated = true
    end
    LeagueResDB.characters[guid] = character
  end
  character.mySR = character.mySR or {0, 0}
  for i = 1, 2 do character.mySR[i] = NS:Reservation(character.mySR[i]) end
  character.raid = character.raid or NS:Copy(NS.State.raid)
  for k, v in pairs(NS.State.raid) do
    if character.raid[k] == nil then character.raid[k] = NS:Copy(v) end
  end
  NS.Character = character
  profile.mySR = character.mySR
  NS.State.raid = character.raid

  C_ChatInfo.RegisterAddonMessagePrefix(NS.PREFIX)
  self:RegisterComm(NS.PREFIX, function(_, msg, channel, sender)
    NS.Comm:HandleMessage(NS.PREFIX, msg, channel, sender)
  end)
  self:RegisterChatCommand("leagueres", function() NS.UI:OpenMain() end)
  self:RegisterChatCommand("lr", function() NS.UI:OpenMain() end)
  print("|cff00ff00LeagueRes loaded.|r Type /lr")
end

function LeagueRes:OnEnable()
  self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    NS:RebuildRoster()
    if NS:IsInRaid() and not NS.wasInRaid then NS:RequestSync() end
    NS.wasInRaid = NS:IsInRaid()
  end)
  self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    NS:RebuildRoster()
    NS:RequestSync()
  end)
  self:RegisterEvent("START_LOOT_ROLL", function(_, rollID) NS.Loot:OnStartLootRoll(rollID) end)
  self:RegisterEvent("CANCEL_LOOT_ROLL", function(_, rollID) NS.Loot.announcedRolls[rollID] = nil end)
  self:RegisterEvent("EJ_LOOT_DATA_RECIEVED", function() NS.UI:QueueEJRefresh() end)
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    NS.UI:QueueEJRefresh()
    NS.UI:RefreshReservationPanels()
  end)
  NS.wasInRaid = NS:IsInRaid()
  NS:RebuildRoster()
  NS:RequestSync()
end

function NS:RebuildRoster()
  -- Keep names for saved reservations, including temporarily disconnected players.
  for i = 1, GetNumGroupMembers() do
    local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
    if UnitExists(unit) then
      local guid, name = UnitGUID(unit), GetUnitName(unit, true)
      if guid and name then NS.State.raid.nameByGuid[guid] = name end
    end
  end
  local me, name = NS:GetPlayerGuid(), GetUnitName("player", true)
  if me and name then NS.State.raid.nameByGuid[me] = name end
  NS.UI:RefreshRaidPanel()
end

function NS:RequestSync()
  if NS:IsInRaid() then NS.Comm:Broadcast({ t = "HELLO", v = NS.PROTOCOL }) end
end

function NS:SubmitMySR(item1, item2)
  if not NS:IsInRaid() then
    print("|cffff0000LeagueRes:|r Not in a raid.")
    return
  end
  if NS.State.raid.locked then
    print("|cffff0000LeagueRes:|r Soft-res is locked by Loot Master.")
    return
  end
  local sr = { NS:Reservation(item1), NS:Reservation(item2) }
  for i = 1, 2 do
    if sr[i] ~= 0 and not sr[i].difficultyID then
      print("|cffffaa00LeagueRes:|r Reselect your old reservations to specify their difficulty before submitting.")
      return
    end
  end
  local guid = NS:GetPlayerGuid()
  NS.State.raid.reservationsByGuid[guid] = NS:Copy(sr)
  NS.State.raid.nameByGuid[guid] = GetUnitName("player", true)
  NS.Comm:Broadcast({ t = "RESERVE", v = NS.PROTOCOL, guid = guid, sr = sr })
  NS.UI:RefreshReservationPanels()
  print("|cff00ff00LeagueRes:|r Submitted soft-res.")
end

function NS:BroadcastSettings()
  if not LeagueResDB.profile.isLootMaster then return end
  local s = NS:Copy(LeagueResDB.profile.settings)
  NS.State.raid.settings = s
  NS.State.raid.locked = s.lockSR and true or false
  NS.State.raid.lootMasterGuid = NS:GetPlayerGuid()
  NS.Comm:Broadcast({ t = "SETTINGS", v = NS.PROTOCOL, settings = s, lm = NS:GetPlayerGuid() })
  NS:BroadcastFullSync()
  NS.UI:RefreshReservationPanels()
  print("|cff00ff00LeagueRes:|r Settings broadcast.")
end

function NS:BroadcastFullSync()
  if not LeagueResDB.profile.isLootMaster then return end
  NS.Comm:Broadcast({
    t = "FULLSYNC", v = NS.PROTOCOL,
    settings = NS.State.raid.settings or LeagueResDB.profile.settings,
    lm = NS:GetPlayerGuid(), reservations = NS.State.raid.reservationsByGuid,
    wins = NS.State.raid.winsByGuid, names = NS.State.raid.nameByGuid,
  })
end

function NS:ClearAllReservations()
  if not LeagueResDB.profile.isLootMaster then return end
  wipe(NS.State.raid.reservationsByGuid)
  NS.UI:RefreshReservationPanels()
  NS:BroadcastFullSync()
  print("|cff00ff00LeagueRes:|r Cleared all soft-res reservations.")
end

function NS:OnComm(msg, sender)
  if msg.v ~= NS.PROTOCOL then
    if not NS.warnedOldVersion then
      NS.warnedOldVersion = true
      print("|cffffaa00LeagueRes:|r Another player has an incompatible version. Everyone must update to 0.3.2.")
    end
    return
  end
  if msg.t == "HELLO" then
    -- HELLO must resend saved, published state, not overwrite it with editable settings.
    if LeagueResDB.profile.isLootMaster then NS:BroadcastFullSync() end
    return
  end
  if msg.t == "SETTINGS" and type(msg.settings) == "table" then
    NS.State.raid.settings = NS:Copy(msg.settings)
    NS.State.raid.locked = msg.settings.lockSR and true or false
    NS.State.raid.lootMasterGuid = msg.lm
  elseif msg.t == "RESERVE" and msg.guid and type(msg.sr) == "table" then
    if NS.State.raid.locked then
      if LeagueResDB.profile.isLootMaster then NS:BroadcastFullSync() end
      return
    end
    NS.State.raid.reservationsByGuid[msg.guid] = { NS:Reservation(msg.sr[1]), NS:Reservation(msg.sr[2]) }
    if sender and sender ~= "" then NS.State.raid.nameByGuid[msg.guid] = sender end
    if LeagueResDB.profile.isLootMaster then NS:BroadcastFullSync() end
  elseif msg.t == "FULLSYNC" then
    if type(msg.settings) == "table" then
      NS.State.raid.settings = NS:Copy(msg.settings)
      NS.State.raid.locked = msg.settings.lockSR and true or false
    end
    if msg.lm then NS.State.raid.lootMasterGuid = msg.lm end
    if type(msg.reservations) == "table" then
      -- Replace, rather than merge: a clear must not resurrect stale saved reservations.
      NS.State.raid.reservationsByGuid = NS:Copy(msg.reservations)
    end
    if type(msg.wins) == "table" then NS.State.raid.winsByGuid = NS:Copy(msg.wins) end
    if type(msg.names) == "table" then NS.State.raid.nameByGuid = NS:Copy(msg.names) end
  else
    return
  end
  NS.UI:RefreshReservationPanels()
end
