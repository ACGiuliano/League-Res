local ADDON, NS = ...

NS.EJ = {
  cache = {
    tiers = nil,
    instancesByTier = {},      -- [tierIndex] = { {instanceID=, name=} }
    lootByInstance = {},       -- [instanceID][difficultyID] = { {itemID=, link=, name=} }
  },
}

local function EnsureEJLoaded()
  -- Blizzard_EncounterJournal is LoadOnDemand; safe to request.
  if not EncounterJournal then
    pcall(LoadAddOn, "Blizzard_EncounterJournal")
  end
end

function NS.EJ:GetRaidTiers()
  EnsureEJLoaded()
  if self.cache.tiers then return self.cache.tiers end

  local tiers = {}
  local n = (EJ_GetNumTiers and EJ_GetNumTiers()) or 0
  for i = 1, n do
    local name = EJ_GetTierInfo(i)
    if name then
      tiers[#tiers + 1] = { index = i, name = name }
    end
  end

  self.cache.tiers = tiers
  return tiers
end

function NS.EJ:GetRaidInstancesForTier(tierIndex)
  EnsureEJLoaded()
  if self.cache.instancesByTier[tierIndex] then
    return self.cache.instancesByTier[tierIndex]
  end

  EJ_SelectTier(tierIndex)

  local out = {}
  for idx = 1, 200 do
    local instanceID, name = EJ_GetInstanceByIndex(idx, true) -- true = raid
    if not instanceID then break end
    out[#out + 1] = { instanceID = instanceID, name = name }
  end

  table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  self.cache.instancesByTier[tierIndex] = out
  return out
end

function NS.EJ:InvalidateLootCache(instanceID)
  if instanceID then
    self.cache.lootByInstance[instanceID] = nil
  else
    self.cache.lootByInstance = {}
  end
end

function NS.EJ:SelectInstance(instanceID, difficultyID)
  EnsureEJLoaded()
  EJ_SelectInstance(instanceID)

  if EJ_SetDifficulty and difficultyID then
    EJ_SetDifficulty(difficultyID)
  end

  if EJ_SetLootFilter then
    EJ_SetLootFilter(0, 0) -- show ALL classes/specs, may change this to just own class/spec later
  end
end

function NS.EJ:GetInstanceLoot(instanceID, difficultyID)
  EnsureEJLoaded()
  if not instanceID or not difficultyID then return {} end

  self.cache.lootByInstance[instanceID] = self.cache.lootByInstance[instanceID] or {}
  if self.cache.lootByInstance[instanceID][difficultyID] then
    return self.cache.lootByInstance[instanceID][difficultyID]
  end

  self:SelectInstance(instanceID, difficultyID)

  local loot = {}
  local numLoot = (EJ_GetNumLoot and EJ_GetNumLoot()) or 0

  for i = 1, numLoot do
    local info = (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex)
      and C_EncounterJournal.GetLootInfoByIndex(i)
      or nil

    if info and info.itemID then
      loot[#loot + 1] = {
        itemID = info.itemID,
        name   = info.name,
        link   = info.link,  -- may be nil until data is ready
        icon   = info.icon,
        slot   = info.slot,
      }
    end
  end

  -- Dedup by itemID
  local seen, dedup = {}, {}
  for _, it in ipairs(loot) do
    if not seen[it.itemID] then
      seen[it.itemID] = true
      dedup[#dedup + 1] = it
    end
  end

  table.sort(dedup, function(a, b) return (a.name or "") < (b.name or "") end)

  self.cache.lootByInstance[instanceID][difficultyID] = dedup
  return dedup
end