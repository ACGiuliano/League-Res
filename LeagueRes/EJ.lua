local ADDON, NS = ...

NS.EJ = { cache = { tiers = nil, instancesByTier = {}, lootByInstance = {} } }
local function EnsureEJLoaded()
  if not EncounterJournal then
    local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if loader then pcall(loader, "Blizzard_EncounterJournal") end
  end
end

function NS.EJ:GetRaidTiers()
  EnsureEJLoaded()
  if self.cache.tiers then return self.cache.tiers end
  local tiers = {}
  for i = 1, (EJ_GetNumTiers and EJ_GetNumTiers()) or 0 do
    local name = EJ_GetTierInfo(i)
    if name then tiers[#tiers + 1] = { index = i, name = name } end
  end
  if #tiers > 0 then self.cache.tiers = tiers end
  return tiers
end

function NS.EJ:GetRaidInstancesForTier(tierIndex)
  EnsureEJLoaded()
  if self.cache.instancesByTier[tierIndex] then return self.cache.instancesByTier[tierIndex] end
  EJ_SelectTier(tierIndex)
  local out = {}
  for idx = 1, 200 do
    local instanceID, name = EJ_GetInstanceByIndex(idx, true)
    if not instanceID then break end
    out[#out + 1] = { instanceID = instanceID, name = name }
  end
  table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  if #out > 0 then self.cache.instancesByTier[tierIndex] = out end
  return out
end

function NS.EJ:InvalidateLootCache(instanceID)
  if instanceID then self.cache.lootByInstance[instanceID] = nil
  else self.cache.lootByInstance = {} end
end

function NS.EJ:GetDifficulties(instanceID)
  EnsureEJLoaded()
  if not instanceID then return {}, {} end
  EJ_SelectInstance(instanceID)
  local list, order = {}, {}
  -- Include legacy raid sizes as well as modern difficulties.
  for _, id in ipairs({14, 15, 16, 17, 3, 4, 5, 6, 7, 9}) do
    if EJ_IsValidInstanceDifficulty(id) then
      list[id] = NS:DifficultyName(id) .. " (" .. id .. ")"
      order[#order + 1] = id
    end
  end
  return list, order
end

function NS.EJ:SelectInstance(instanceID, difficultyID)
  EnsureEJLoaded()
  local tier = LeagueResDB.profile.ej.tierIndex
  if tier then EJ_SelectTier(tier) end
  EJ_SelectInstance(instanceID)
  if not EJ_IsValidInstanceDifficulty(difficultyID) then return false end
  EJ_SetDifficulty(difficultyID)
  if EJ_GetDifficulty and EJ_GetDifficulty() ~= difficultyID then return false end
  -- Filters are global and may have been changed in Blizzard's Journal.
  if EJ_ResetLootFilter then EJ_ResetLootFilter() end
  if EJ_ClearSearch then EJ_ClearSearch() end
  EJ_SetLootFilter(0, 0)
  if C_EncounterJournal and C_EncounterJournal.SetSlotFilter then
    C_EncounterJournal.SetSlotFilter(Enum and Enum.ItemSlotFilterType and Enum.ItemSlotFilterType.NoFilter or 0)
  end
  return true
end

function NS.EJ:GetInstanceLoot(instanceID, difficultyID)
  if not instanceID or not difficultyID then return {}, true end
  if not self:SelectInstance(instanceID, difficultyID) then return {}, true end
  local loot, seen = {}, {}
  local numLoot = EJ_GetNumLoot()
  local pending = numLoot == 0
  for i = 1, numLoot do
    local info = C_EncounterJournal.GetLootInfoByIndex(i)
    -- A delayed response to the previous difficulty must not be selectable.
    local linkDifficulty = info and NS:ItemLinkDifficulty(info.link)
    local wrongDifficulty = linkDifficulty and linkDifficulty ~= difficultyID
    if not info or not info.itemID or not info.name or not info.link then pending = true end
    if wrongDifficulty then pending = true end
    if info and info.itemID and not seen[info.itemID] then
      seen[info.itemID] = true
      loot[#loot + 1] = {
        itemID = info.itemID, name = info.name, link = not wrongDifficulty and info.link or nil,
        icon = info.icon, slot = info.slot,
        instanceID = instanceID, difficultyID = difficultyID,
      }
      if (not info.name or not info.link) and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(info.itemID)
      end
    end
  end
  table.sort(loot, function(a, b) return (a.name or "") < (b.name or "") end)
  -- Re-read the Journal each time. A partial snapshot must never become final.
  return loot, pending
end
