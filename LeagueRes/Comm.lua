local ADDON, NS = ...
local AceSerializer = LibStub("AceSerializer-3.0")

NS.Comm = {}

local function Send(tbl, channel, target)
  local payload = AceSerializer:Serialize(tbl)
  if not payload then return end

  if not NS.Addon or not NS.Addon.SendCommMessage then return end

  NS.Addon:SendCommMessage(NS.PREFIX, payload, channel, target)
end

function NS.Comm:Broadcast(tbl)
  local channel

  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    channel = "INSTANCE_CHAT"
  elseif IsInRaid() then
    channel = "RAID"
  elseif IsInGroup() then
    channel = "PARTY"
  else
    return
  end

  Send(tbl, channel)
end

function NS.Comm:Whisper(tbl, target)
  if not target or target == "" then return end
  Send(tbl, "WHISPER", target)
end

function NS.Comm:HandleMessage(prefix, message, channel, sender)
  if prefix ~= NS.PREFIX then return end

  local ok, tbl = AceSerializer:Deserialize(message)
  if not ok or type(tbl) ~= "table" then return end

  NS:OnComm(tbl, sender)
end