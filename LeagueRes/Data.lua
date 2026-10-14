local ADDON, NS = ...

NS.PREFIX = "LeagueRes1" -- addon message prefix (<=16 chars)
NS.PROTOCOL = 3

NS.DEFAULTS = {
  profile = {
    isLootMaster = false,
    settings = {
      srCount = 2,              -- we'll still default to 2; can expand later
      allowOpenIfNoSR = true,
      maxWins = 0,              -- 0 = unlimited
      lockSR = false,
    },
    mySR = { 0, 0 },            -- 0 or {itemID, difficultyID, instanceID, link, name}
    ej = {
      tierIndex = nil,
      instanceID = nil,
      difficultyID = 14,        -- normal raid
    }
  },
}

-- Bound to this character's SavedVariables by Core:OnInitialize.
NS.State = {
  raid = {
    settings = nil,                 -- authoritative settings for this session (from LM)
    reservationsByGuid = {},        -- [guid] = {reservation1, reservation2}
    winsByGuid = {},                -- [guid] = number
    nameByGuid = {},                -- [guid] = "Player-Realm"
    locked = false,
    lootMasterGuid = nil,
    versionsByGuid = {},            -- per-player submission sequence numbers
    epoch = 0,                     -- advances only on an explicit Clear All
    settingsRevision = 0,
    authorityTerm = 0,
    retiredMasters = {},
  },
}

function NS:GetPlayerGuid()
  return UnitGUID("player")
end

function NS:Copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = self:Copy(v) end
  return out
end

function NS:Reservation(item)
  local id = self:NormalizeItemID(type(item) == "table" and item.itemID or item)
  if not id or id <= 0 then return 0 end
  if type(item) ~= "table" then return { itemID = id } end
  return {
    itemID = id, difficultyID = tonumber(item.difficultyID),
    instanceID = tonumber(item.instanceID), link = item.link, name = item.name,
  }
end

function NS:ReservationKey(item)
  local r = self:Reservation(item)
  if r == 0 then return nil end
  return tostring(r.itemID) .. ":" .. tostring(r.difficultyID or "unknown")
end

function NS:MatchesReservation(item, itemID, difficultyID)
  local r = self:Reservation(item)
  return r ~= 0 and r.itemID == itemID and r.difficultyID ~= nil
    and difficultyID ~= nil and r.difficultyID == difficultyID
end

function NS:DifficultyName(id)
  return (id and GetDifficultyInfo and GetDifficultyInfo(id)) or "Choose difficulty again"
end

function NS:ReservationText(item)
  local r = self:Reservation(item)
  if r == 0 then return "—" end
  local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
  local name = r.name or (getInfo and getInfo(r.link or r.itemID))
  -- Never replace a difficulty-specific Journal link with a generic itemID link.
  return (r.link or name or ("item:" .. r.itemID)) .. " [" .. self:DifficultyName(r.difficultyID) .. "]"
end

-- Item links contain an ItemCreationContext, not an instance difficulty ID.
function NS:ItemLinkContext(itemLink)
  local data = itemLink and itemLink:match("item:([^|]+)")
  if data then
    local fields = {}
    for field in (data .. ":"):gmatch("(.-):") do fields[#fields + 1] = field end
    local id = tonumber(fields[12])
    if id and id > 0 then return id end
  end
end

local raidFamilies = {
  [3] = "Normal", [4] = "Normal", [9] = "Normal", [14] = "Normal",
  [5] = "Heroic", [6] = "Heroic", [15] = "Heroic",
  [16] = "Mythic", [7] = "Finder", [17] = "Finder",
}
local modernDifficulties = { Normal = 14, Heroic = 15, Mythic = 16, Finder = 17 }
local contextFamilies, contextEnum

function NS:ItemLinkDifficulty(itemLink, selectedDifficulty)
  local context = self:ItemLinkContext(itemLink)
  local enum = Enum and Enum.ItemCreationContext
  if not context or not enum then return nil end
  if contextEnum ~= enum then
    contextEnum, contextFamilies = enum, {}
    for name, value in pairs(enum) do
      -- Include the Extended variants using the game's current enum values.
      if type(name) == "string" and type(value) == "number" then
        local family = name:match("^Raid(Normal)") or name:match("^Raid(Heroic)")
          or name:match("^Raid(Mythic)") or name:match("^Raid(Finder)")
        if family then contextFamilies[value] = family end
      end
    end
  end
  local family = contextFamilies[context]
  if not family then return nil end
  -- Context alone cannot distinguish a legacy raid's 10/25-player size.
  if selectedDifficulty and raidFamilies[selectedDifficulty] == family then return selectedDifficulty end
  return modernDifficulties[family]
end

function NS:LootDifficulty(itemLink)
  local _, _, difficultyID = GetInstanceInfo()
  local linkDifficulty = self:ItemLinkDifficulty(itemLink, difficultyID)
  if linkDifficulty then return linkDifficulty end
  if difficultyID and difficultyID > 0 then return difficultyID end
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
