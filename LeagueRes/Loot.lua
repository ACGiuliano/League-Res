local ADDON, NS = ...

NS.Loot = {}
NS.Loot.announcedRolls = NS.Loot.announcedRolls or {}

local function countReservers(itemID, difficultyID)
  local n = 0
  for _, sr in pairs(NS.State.raid.reservationsByGuid or {}) do
    if NS:MatchesReservation(sr[1], itemID, difficultyID) or NS:MatchesReservation(sr[2], itemID, difficultyID) then
      n = n + 1
    end
  end
  return n
end

local function getReservers(itemID, difficultyID)
  local out = {}

  for guid, sr in pairs(NS.State.raid.reservationsByGuid or {}) do
    if NS:MatchesReservation(sr[1], itemID, difficultyID) or NS:MatchesReservation(sr[2], itemID, difficultyID) then
      local name = (NS.State.raid.nameByGuid and NS.State.raid.nameByGuid[guid]) or guid
      out[#out + 1] = name
    end
  end

  table.sort(out, function(a, b)
    return tostring(a):lower() < tostring(b):lower()
  end)

  return out
end

local function isMine(itemID, difficultyID)
  local sr = NS.State.raid.reservationsByGuid[NS:GetPlayerGuid()] or {0, 0}
  return NS:MatchesReservation(sr[1], itemID, difficultyID) or NS:MatchesReservation(sr[2], itemID, difficultyID)
end

local function myWins()
  local me = NS:GetPlayerGuid()
  return (NS.State.raid.winsByGuid and NS.State.raid.winsByGuid[me]) or 0
end

local function shortItemText(itemID, itemLink, itemName)
  if itemLink and itemLink ~= "" then return itemLink end
  if itemName and itemName ~= "" then return itemName end
  if itemID and itemID ~= 0 then return ("item:%d"):format(itemID) end
  return "unknown item"
end

local function announceReservedItem(itemID, difficultyID, itemLink, itemName)
  if not LeagueResDB or not LeagueResDB.profile or not LeagueResDB.profile.isLootMaster then
    return
  end

  local reservers = getReservers(itemID, difficultyID)
  if #reservers == 0 then return end

  local itemText = shortItemText(itemID, itemLink, itemName)
  local msg = ("[LeagueRes] Reserved: %s -> %s"):format(itemText, table.concat(reservers, ", "))

  if IsInRaid() then
    SendChatMessage(msg, "RAID_WARNING")
  elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    SendChatMessage(msg, "INSTANCE_CHAT")
  elseif IsInGroup() then
    SendChatMessage(msg, "PARTY")
  end
end

function NS.Loot:OnStartLootRoll(rollID)
  local itemLink = GetLootRollItemLink(rollID)
  local _, itemName = GetLootRollItemInfo(rollID)

  local itemID
  if itemLink then
    itemID = NS:NormalizeItemID(itemLink)
  end
  if not itemID then
    return
  end

  local difficultyID = NS:LootDifficulty(itemLink)
  -- Unknown old reservations are never guessed as Normal or Heroic.
  local uncertain = not difficultyID
  for _, sr in pairs(NS.State.raid.reservationsByGuid) do
    for i = 1, 2 do
      local r = NS:Reservation(sr[i])
      if r ~= 0 and r.itemID == itemID and not r.difficultyID then uncertain = true end
    end
  end
  if uncertain then
    NS.UI:ShowRollPrompt({rollID = rollID, itemID = itemID, itemLink = itemLink or itemName,
      decision = "CHECK DIFFICULTY", reason = "Difficulty is unknown. Check reservations before rolling."})
    return
  end

  local settings = NS.State.raid.settings or LeagueResDB.profile.settings or {}
  local reservers = countReservers(itemID, difficultyID)
  local mine = isMine(itemID, difficultyID)

  -- LM announces reserved items once per roll
  if not self.announcedRolls[rollID] then
    self.announcedRolls[rollID] = true
    if reservers > 0 then
      announceReservedItem(itemID, difficultyID, itemLink, itemName)
    end
  end

  local cap = tonumber(settings.maxWins or 0) or 0
  if cap > 0 and myWins() >= cap then
    RollOnLoot(rollID, 0)
    print(("|cffff0000LeagueRes:|r Auto-passed %s (max wins reached)."):format(
      shortItemText(itemID, itemLink, itemName)
    ))
    return
  end

  -- My reserved item: let me choose manually
  if mine then
    NS.UI:ShowRollPrompt({
      rollID = rollID,
      itemID = itemID,
      itemLink = itemLink or itemName,
      decision = "ROLL (SR)",
      reason = "This is one of your soft-res items.",
    })
    return
  end

  -- Nobody reserved it, and open rolling is allowed
  if reservers == 0 and settings.allowOpenIfNoSR then
    NS.UI:ShowRollPrompt({
      rollID = rollID,
      itemID = itemID,
      itemLink = itemLink or itemName,
      decision = "ROLL (OPEN)",
      reason = "Nobody soft-res'd this item; open roll is allowed.",
    })
    return
  end

  -- Someone else reserved it: auto-pass
  if reservers > 0 then
    RollOnLoot(rollID, 0)

    local names = getReservers(itemID, difficultyID)
    local who = (#names > 0) and table.concat(names, ", ") or ("%d player(s)"):format(reservers)

    print(("|cffff0000LeagueRes:|r Auto-passed %s. Reserved by: %s"):format(
      shortItemText(itemID, itemLink, itemName),
      who
    ))
    return
  end

  -- Fallback
  NS.UI:ShowRollPrompt({
    rollID = rollID,
    itemID = itemID,
    itemLink = itemLink or itemName,
    decision = "PASS",
    reason = "Unable to determine roll eligibility.",
  })
end