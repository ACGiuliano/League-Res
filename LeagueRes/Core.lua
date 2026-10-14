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
  character.submissionSequence = math.max(character.submissionSequence or 0, character.raid.versionsByGuid[guid] or 0)
  for owner in pairs(character.raid.reservationsByGuid) do
    if character.raid.versionsByGuid[owner] == nil then character.raid.versionsByGuid[owner] = 0 end
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

function NS:GetCurrentGroupRoster()
  if not IsInGroup() then return {}, 0 end
  local total = GetNumGroupMembers()
  if total == 0 then return {}, 0 end
  local members, seen = {}, {}
  local function addUnit(unit)
    -- Disconnected members still count if they remain in the group.
    local guid = UnitGUID(unit)
    if guid and not seen[guid] then
      seen[guid] = true
      members[#members + 1] = { guid = guid, name = GetUnitName(unit, true) or guid }
    end
  end
  if IsInRaid() then
    for i = 1, total do addUnit("raid" .. i) end
  else
    addUnit("player")
    for i = 1, total - 1 do addUnit("party" .. i) end
  end
  table.sort(members, function(a, b) return a.name:lower() < b.name:lower() end)
  return members, total
end

function NS:RebuildRoster()
  -- Keep saved names, but use only the live roster when checking submissions.
  for _, member in ipairs(self:GetCurrentGroupRoster()) do
    NS.State.raid.nameByGuid[member.guid] = member.name
  end
  local me, name = NS:GetPlayerGuid(), GetUnitName("player", true)
  if me and name then NS.State.raid.nameByGuid[me] = name end
  NS.UI:RefreshRaidPanel()
  NS.UI:RefreshLMPanel()
end

function NS:CanCheckSubmissions()
  return IsInGroup() and (LeagueResDB.profile.isLootMaster
    or NS.State.raid.lootMasterGuid == NS:GetPlayerGuid()
    or UnitIsGroupLeader("player")) and true or false
end

function NS:GetSubmissionReport()
  local members, total = self:GetCurrentGroupRoster()
  local report = { total = total, submitted = 0, missing = {}, unresolved = total - #members }
  for _, member in ipairs(members) do
    -- An explicitly submitted empty selection counts as a submission.
    if type(NS.State.raid.reservationsByGuid[member.guid]) == "table" then
      report.submitted = report.submitted + 1
    else
      report.missing[#report.missing + 1] = member.name
    end
  end
  return report
end

function NS:PrintMissingSubmissions()
  if not IsInGroup() then
    print("|cffffaa00LeagueRes:|r Join a group before checking submissions.")
    return
  end
  if not self:CanCheckSubmissions() then
    print("|cffffaa00LeagueRes:|r Only the Loot Master or group leader can check missing submissions.")
    return
  end
  local report = self:GetSubmissionReport()
  if report.total == 0 then
    print("|cffffaa00LeagueRes:|r The group roster is still loading. Check again shortly.")
    return
  end
  print(("|cff00ff00LeagueRes:|r %d/%d group members have submitted; %d missing."):format(
    report.submitted, report.total, #report.missing))
  for _, name in ipairs(report.missing) do
    print("|cffffaa00LeagueRes:|r Missing SR submission: " .. name)
  end
  if report.unresolved > 0 then
    print(("|cffffaa00LeagueRes:|r %d roster entry/entries are still loading. Check again shortly."):format(report.unresolved))
  elseif #report.missing == 0 then
    print("|cff00ff00LeagueRes:|r Everyone in the current group has submitted.")
  end
end

-- Sender identities come from live group units, never from a message's claimed GUID.
function NS:GroupUnitForGuid(guid)
  if not IsInGroup() or not guid then return nil end
  if guid == self:GetPlayerGuid() then return "player" end
  local prefix = IsInRaid() and "raid" or "party"
  for i = 1, GetNumGroupMembers() do
    if UnitGUID(prefix .. i) == guid then return prefix .. i end
  end
end

function NS:SenderGuid(sender)
  if type(sender) ~= "string" then return nil end
  local function fullName(name)
    if not name then return nil end
    if not name:find("-", 1, true) then
      name = name .. "-" .. GetNormalizedRealmName()
    end
    return name:gsub("%s", ""):lower()
  end
  local wanted = fullName(sender)
  if wanted == fullName(GetUnitName("player", true)) then return self:GetPlayerGuid() end
  for _, member in ipairs(self:GetCurrentGroupRoster()) do
    if fullName(member.name) == wanted then return member.guid end
  end
end

function NS:ActiveLootMaster()
  local guid = NS.State.raid.lootMasterGuid
  return self:GroupUnitForGuid(guid) and guid or nil
end

function NS:IsActiveLootMaster()
  local owner = self:ActiveLootMaster()
  return LeagueResDB.profile.isLootMaster and (not owner or owner == self:GetPlayerGuid())
end

local function stamp(previous)
  return math.max((previous or 0) + 1, GetServerTime() * 1000)
end

function NS:ClaimLootMaster()
  if not self:IsActiveLootMaster() then
    print("|cffffaa00LeagueRes:|r Another Loot Master is active. Only that player can publish settings or clear reservations.")
    return false
  end
  local state = NS.State.raid
  if state.lootMasterGuid ~= self:GetPlayerGuid() or state.authorityTerm == 0 then
    state.authorityTerm = stamp(math.max(state.authorityTerm, NS.Character.roleSequence or 0))
    NS.Character.roleSequence = state.authorityTerm
  end
  state.lootMasterGuid = self:GetPlayerGuid()
  if not state.settings then
    state.settings = self:Copy(LeagueResDB.profile.settings)
    state.locked = state.settings.lockSR and true or false
  end
  return true
end

function NS:SetLootMaster(enabled)
  if enabled then
    if self:ActiveLootMaster() and self:ActiveLootMaster() ~= self:GetPlayerGuid() then
      LeagueResDB.profile.isLootMaster = false
      print("|cffffaa00LeagueRes:|r Another Loot Master is already active.")
    else
      LeagueResDB.profile.isLootMaster = true
      if self:ClaimLootMaster() then self:BroadcastFullSync() end
    end
  else
    if self:ActiveLootMaster() == self:GetPlayerGuid() then
      local state = NS.State.raid
      state.retiredMasters[self:GetPlayerGuid()] = state.authorityTerm
      NS.Comm:Broadcast({ t = "RELEASE", v = NS.PROTOCOL, lm = self:GetPlayerGuid(), term = state.authorityTerm })
      state.lootMasterGuid = nil
    end
    LeagueResDB.profile.isLootMaster = false
  end
  NS.UI:RefreshReservationPanels()
end

function NS:AcceptAuthority(guid, term)
  if not self:GroupUnitForGuid(guid) or type(term) ~= "number" then return false end
  local state = NS.State.raid
  if term <= (state.retiredMasters[guid] or -1) then return false end
  local current = self:ActiveLootMaster()
  if current == guid then
    if term < state.authorityTerm then return false end
  elseif current then
    local function rank(owner)
      local unit = self:GroupUnitForGuid(owner)
      if UnitIsGroupLeader(unit) then return 2 end
      if UnitIsGroupAssistant(unit) then return 1 end
      return 0
    end
    -- Deterministic tie-break if two clients claim the role at the same time.
    local incomingRank, currentRank = rank(guid), rank(current)
    if incomingRank < currentRank or (incomingRank == currentRank and guid > current) then return false end
  end
  local changed = state.lootMasterGuid ~= guid or state.authorityTerm ~= term
  if changed then state.settingsRevision = -1 end
  state.lootMasterGuid, state.authorityTerm = guid, term
  if guid ~= self:GetPlayerGuid() and LeagueResDB.profile.isLootMaster then
    LeagueResDB.profile.isLootMaster = false
    print("|cffffaa00LeagueRes:|r Another player is the active Loot Master; your Loot Master checkbox was disabled.")
  end
  return true, changed
end

function NS:CancelSubmissionRetry()
  if NS.submissionTimer then NS.submissionTimer:Cancel() end
  NS.submissionTimer = nil
end

function NS:SendPendingSubmission()
  local pending = NS.Character.pendingSubmission
  if not pending or pending.epoch ~= NS.State.raid.epoch then return end
  NS.Comm:Broadcast({ t = "RESERVE", v = NS.PROTOCOL, guid = self:GetPlayerGuid(),
    sr = pending.sr, seq = pending.seq, epoch = pending.epoch })
end

function NS:RetrySubmission()
  self:CancelSubmissionRetry()
  if not NS.Character.pendingSubmission then return end
  NS.submissionRetries = (NS.submissionRetries or 0) + 1
  if NS.submissionRetries > 3 then
    print("|cffffaa00LeagueRes:|r Still waiting for Loot Master confirmation. Use Request Sync or Submit to Raid to retry.")
    return
  end
  NS.submissionTimer = C_Timer.NewTimer(2, function()
    NS.submissionTimer = nil
    NS:SendPendingSubmission()
    NS:RetrySubmission()
  end)
end

function NS:MergeReservation(guid, sr, seq)
  if type(sr) ~= "table" or type(seq) ~= "number" or seq < 0 then return false end
  local state = NS.State.raid
  local previous = state.versionsByGuid[guid]
  if previous and seq <= previous and state.reservationsByGuid[guid] then return false end
  state.reservationsByGuid[guid] = { self:Reservation(sr[1]), self:Reservation(sr[2]) }
  state.versionsByGuid[guid] = seq
  if guid == self:GetPlayerGuid() then
    NS.Character.submissionSequence = math.max(NS.Character.submissionSequence or 0, seq)
    local pending = NS.Character.pendingSubmission
    if pending and pending.epoch == state.epoch and seq >= pending.seq then
      NS.Character.pendingSubmission = nil
      self:CancelSubmissionRetry()
      print("|cff00ff00LeagueRes:|r Soft-res confirmed by Loot Master.")
    end
  end
  return true
end

function NS:AdoptEpoch(epoch)
  local state = NS.State.raid
  if type(epoch) ~= "number" or epoch < state.epoch then return false end
  if epoch > state.epoch then
    -- A new epoch represents an explicit Clear All, including when reconnecting.
    state.epoch = epoch
    wipe(state.reservationsByGuid)
    wipe(state.versionsByGuid)
    NS.Character.pendingSubmission = nil
    self:CancelSubmissionRetry()
  end
  return true
end

function NS:RequestSync()
  if not self:IsInRaid() then return end
  local me, state = self:GetPlayerGuid(), NS.State.raid
  NS.Comm:Broadcast({ t = "HELLO", v = NS.PROTOCOL, epoch = state.epoch,
    guid = me, sr = state.reservationsByGuid[me], seq = state.versionsByGuid[me] })
  self:SendPendingSubmission()
  if NS.Character.pendingSubmission and not NS.submissionTimer then
    NS.submissionRetries = 0
    self:RetrySubmission()
  end
end

function NS:SubmitMySR(item1, item2)
  if not self:IsInRaid() then
    print("|cffff0000LeagueRes:|r Not in a raid.")
    return
  end
  if NS.State.raid.locked then
    print("|cffff0000LeagueRes:|r Soft-res is locked by Loot Master.")
    return
  end
  local sr = { self:Reservation(item1), self:Reservation(item2) }
  for i = 1, 2 do
    if sr[i] ~= 0 and not sr[i].difficultyID then
      print("|cffffaa00LeagueRes:|r Reselect your old reservations to specify their difficulty before submitting.")
      return
    end
  end
  local me, state = self:GetPlayerGuid(), NS.State.raid
  local seq = (NS.Character.submissionSequence or 0) + 1
  NS.Character.submissionSequence = seq
  state.nameByGuid[me] = GetUnitName("player", true)
  if self:IsActiveLootMaster() then self:ClaimLootMaster() end
  if self:ActiveLootMaster() and not self:IsActiveLootMaster() then
    NS.Character.pendingSubmission = { sr = self:Copy(sr), seq = seq, epoch = state.epoch }
    NS.submissionRetries = 0
    self:SendPendingSubmission()
    self:RetrySubmission()
    print("|cffffaa00LeagueRes:|r Sent soft-res; waiting for Loot Master confirmation.")
  else
    self:MergeReservation(me, sr, seq)
    NS.Comm:Broadcast({ t = "RESERVE", v = NS.PROTOCOL, guid = me, sr = sr, seq = seq, epoch = state.epoch })
    if self:IsActiveLootMaster() then self:BroadcastReservation(me) end
    print("|cff00ff00LeagueRes:|r Submitted soft-res.")
  end
  NS.UI:RefreshReservationPanels()
end

function NS:BroadcastSettings()
  if not self:ClaimLootMaster() then return end
  local state = NS.State.raid
  state.settings = self:Copy(LeagueResDB.profile.settings)
  state.locked = state.settings.lockSR and true or false
  state.settingsRevision = stamp(state.settingsRevision)
  self:BroadcastFullSync()
  NS.UI:RefreshReservationPanels()
  print("|cff00ff00LeagueRes:|r Settings broadcast.")
end

function NS:BroadcastReservation(guid)
  local state = NS.State.raid
  NS.Comm:Broadcast({ t = "ACCEPT", v = NS.PROTOCOL, lm = self:GetPlayerGuid(),
    term = state.authorityTerm, epoch = state.epoch, guid = guid,
    sr = state.reservationsByGuid[guid], seq = state.versionsByGuid[guid], name = state.nameByGuid[guid] })
end

function NS:BroadcastFullSync(target)
  if not self:ClaimLootMaster() then return end
  local state = NS.State.raid
  local msg = { t = "FULLSYNC", v = NS.PROTOCOL, lm = self:GetPlayerGuid(), term = state.authorityTerm,
    epoch = state.epoch, settingsRevision = state.settingsRevision,
    settings = state.settings or LeagueResDB.profile.settings,
    reservations = state.reservationsByGuid, versions = state.versionsByGuid,
    wins = state.winsByGuid, names = state.nameByGuid }
  if target then NS.Comm:Whisper(msg, target) else NS.Comm:Broadcast(msg) end
end

function NS:ClearAllReservations()
  if not self:ClaimLootMaster() then return end
  self:AdoptEpoch(stamp(NS.State.raid.epoch))
  self:BroadcastFullSync()
  NS.UI:RefreshReservationPanels()
  print("|cff00ff00LeagueRes:|r Cleared all soft-res reservations.")
end

function NS:OnComm(msg, sender)
  if msg.v ~= NS.PROTOCOL then
    if not NS.warnedOldVersion then
      NS.warnedOldVersion = true
      print("|cffffaa00LeagueRes:|r Incompatible addon version detected. Everyone must update to 1.2.")
    end
    return
  end
  local senderGuid = self:SenderGuid(sender)
  if not senderGuid or senderGuid == self:GetPlayerGuid() then return end
  local state = NS.State.raid
  if msg.t == "RELEASE" then
    if state.lootMasterGuid == senderGuid and msg.lm == senderGuid and msg.term == state.authorityTerm then
      state.retiredMasters[senderGuid] = msg.term
      state.lootMasterGuid = nil
      NS.UI:RefreshReservationPanels()
    end
    return
  end
  if msg.t == "HELLO" then
    if self:IsActiveLootMaster() then
      self:ClaimLootMaster()
      -- Recover already confirmed state from its owner, never an unsubmitted draft.
      if msg.epoch == state.epoch and msg.guid == senderGuid and type(msg.sr) == "table"
        and type(msg.seq) == "number" and not state.reservationsByGuid[senderGuid] then
        self:MergeReservation(senderGuid, msg.sr, msg.seq)
        state.nameByGuid[senderGuid] = sender
      end
      self:BroadcastFullSync(sender)
      NS.UI:RefreshReservationPanels()
    end
    return
  end
  if msg.t == "RESERVE" then
    if msg.guid ~= senderGuid or type(msg.sr) ~= "table" or type(msg.seq) ~= "number" then return end
    if self:IsActiveLootMaster() then
      self:ClaimLootMaster()
      if msg.epoch ~= state.epoch or (state.locked and (state.versionsByGuid[senderGuid] or -1) ~= msg.seq) then
        NS.Comm:Whisper({t = "REJECT", v = NS.PROTOCOL, lm = self:GetPlayerGuid(), term = state.authorityTerm,
          epoch = state.epoch, guid = senderGuid, seq = msg.seq}, sender)
        self:BroadcastFullSync(sender)
      else
        self:MergeReservation(senderGuid, msg.sr, msg.seq)
        state.nameByGuid[senderGuid] = sender
        self:BroadcastReservation(senderGuid)
      end
    elseif not self:ActiveLootMaster() and msg.epoch == state.epoch and not state.locked then
      self:MergeReservation(senderGuid, msg.sr, msg.seq)
      state.nameByGuid[senderGuid] = sender
    end
  elseif msg.t == "FULLSYNC" or msg.t == "ACCEPT" or msg.t == "REJECT" then
    if msg.lm ~= senderGuid then return end
    if type(msg.epoch) ~= "number" or msg.epoch < state.epoch then return end
    -- Only claims/snapshots can establish authority, not a delayed receipt from another LM.
    if msg.t ~= "FULLSYNC" and self:ActiveLootMaster() ~= senderGuid then return end
    local accepted, changed = self:AcceptAuthority(senderGuid, msg.term)
    if not accepted then
      if msg.t == "FULLSYNC" and self:IsActiveLootMaster() then self:BroadcastFullSync(sender) end
      return
    end
    if not self:AdoptEpoch(msg.epoch) then return end
    if msg.t == "FULLSYNC" then
      if type(msg.settings) == "table" and type(msg.settingsRevision) == "number"
        and msg.settingsRevision >= state.settingsRevision then
        state.settings = self:Copy(msg.settings)
        state.locked = msg.settings.lockSR and true or false
        state.settingsRevision = msg.settingsRevision
      end
      if type(msg.reservations) == "table" and type(msg.versions) == "table" then
        for guid, sr in pairs(msg.reservations) do self:MergeReservation(guid, sr, msg.versions[guid]) end
      end
      if type(msg.names) == "table" then
        for guid, name in pairs(msg.names) do state.nameByGuid[guid] = name end
      end
      if type(msg.wins) == "table" then state.winsByGuid = self:Copy(msg.wins) end
      if changed then self:RequestSync() end
    elseif msg.t == "ACCEPT" then
      if msg.guid then
        self:MergeReservation(msg.guid, msg.sr, msg.seq)
        if type(msg.name) == "string" then state.nameByGuid[msg.guid] = msg.name end
      end
    else
      local pending = NS.Character.pendingSubmission
      if msg.guid == self:GetPlayerGuid() and pending and pending.seq == msg.seq then
        NS.Character.pendingSubmission = nil
        self:CancelSubmissionRetry()
        print("|cffffaa00LeagueRes:|r Submission was not accepted. Request Sync to check the current raid rules.")
      end
    end
  else
    return
  end
  NS.UI:RefreshReservationPanels()
end
