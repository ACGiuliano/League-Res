local ADDON, NS = ...

NS.PREFIX = "LeagueRes1" -- addon message prefix (<=16 chars)

NS.DEFAULTS = {
  profile = {
    isLootMaster = false,
    settings = {
      srCount = 2,              -- we'll still default to 2; can expand later
      allowOpenIfNoSR = true,
      maxWins = 0,              -- 0 = unlimited
      lockSR = false,
    },
    mySR = { 0, 0 },            -- itemIDs
    ej = {
      tierIndex = nil,
      instanceID = nil,
      difficultyID = 14,        -- normal raid
    }
  },
}

-- Runtime state (not saved)
NS.State = {
  raid = {
    settings = nil,                 -- authoritative settings for this session (from LM)
    reservationsByGuid = {},        -- [guid] = {itemID1, itemID2}
    winsByGuid = {},                -- [guid] = number
    nameByGuid = {},                -- [guid] = "Player-Realm"
    locked = false,
    lootMasterGuid = nil,
  },
}

function NS:GetPlayerGuid()
  return UnitGUID("player")
end

function NS:IsInRaid()
  return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid()
end

function NS:CanBroadcastAsLootMaster()
  return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function NS:NormalizeItemID(item)
  if type(item) == "number" then return item end
  if type(item) ~= "string" then return nil end

  local id = item:match("item:(%d+)")
  if id then return tonumber(id) end

  if item:match("^%d+$") then return tonumber(item) end

  return nil
end