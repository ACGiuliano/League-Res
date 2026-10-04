local ADDON, NS = ...
local AceGUI = LibStub("AceGUI-3.0")

NS.UI = {
  frame = nil,
  rollFrame = nil,
  lootPickerFrame = nil,

  mainPanel = nil,
  contentHost = nil,
  raidScroll = nil,

  tabs = {
    my = nil,
    raid = nil,
    lm = nil,
    selected = "my",
  },

  ej = {
    sr1Box = nil,
    sr2Box = nil,
    targetDrop = nil,
    selectedTarget = 1,

    currentLabel = nil,
    srButtons = {},
    srLabels = {},
  },

  picker = {
    tierDrop = nil,
    instanceDrop = nil,
    diffDrop = nil,
    searchBox = nil,
    lootScroll = nil,
    activeSlotLabel = nil,
    closeAfterSelect = true,
  },
}

local function itemLinkFromID(itemID)
  itemID = type(itemID) == "table" and itemID.itemID or itemID
  if not itemID or itemID == 0 then return nil end
  local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID))
  return link
end

local function itemNameFromID(itemID)
  itemID = type(itemID) == "table" and itemID.itemID or itemID
  if not itemID or itemID == 0 then return nil end
  local name = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID)
  return name
end

local function itemIconFromID(itemID)
  itemID = type(itemID) == "table" and itemID.itemID or itemID
  if not itemID or itemID == 0 then return nil end

  if C_Item and C_Item.GetItemIconByID then
    local icon = C_Item.GetItemIconByID(itemID)
    if icon then return icon end
  end

  local _, _, _, _, _, _, _, _, _, texture = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID)
  return texture
end

local function displayLinkOrFallback(itemID, ejLink, ejName)
  if ejLink and ejLink ~= "" then return ejLink end
  if ejName and ejName ~= "" then
    return ("%s (%d, loading link...)"):format(ejName, itemID)
  end

  return ("item:%d (loading...)"):format(itemID)
end

local function makeColoredSlotLabel(slot, isSelected)
  if isSelected then
    return ("|cff00ff00Soft-Res #%d|r"):format(slot)
  end
  return ("Soft-Res #%d"):format(slot)
end

function NS.UI:ShowPanel(which)
  self.tabs.selected = which

  if self.tabs.my then
    self.tabs.my:SetDisabled(which == "my")
  end
  if self.tabs.raid then
    self.tabs.raid:SetDisabled(which == "raid")
  end
  if self.tabs.lm then
    self.tabs.lm:SetDisabled(which == "lm")
  end

  if not self.mainPanel then return end

  self.ej.srButtons = {}
  self.ej.srLabels = {}
  self.ej.currentLabel = nil
  self.mainPanel:ReleaseChildren()
  self.raidScroll = nil

  if which == "my" then
    self.mainPanel:SetLayout("List")
    self:BuildMyPanel(self.mainPanel)
    self:RefreshSRVisuals()
    self:UpdateCurrentSRLabel()

  elseif which == "raid" then
    self.mainPanel:SetLayout("Fill")
    self:BuildRaidPanel(self.mainPanel)
    self:RefreshRaidPanel()

  elseif which == "lm" then
    self.mainPanel:SetLayout("List")
    self:BuildLMPanel(self.mainPanel)
    self:RefreshLMPanel()
  end
end

function NS.UI:OpenMain()
  if self.frame then
    self.frame:Show()
    self:ShowPanel(self.tabs.selected or "my")
    return
  end

  local f = AceGUI:Create("Frame")
  f:SetTitle("LeagueRes")
  f:SetWidth(760)
  f:SetHeight(500)
  f:SetLayout("List")
  f:EnableResize(false)

  f:SetCallback("OnClose", function()
    NS.UI.frame = nil
    NS.UI.contentHost = nil
    NS.UI.mainPanel = nil
    NS.UI.raidScroll = nil
    NS.UI.tabs.my = nil
    NS.UI.tabs.raid = nil
    NS.UI.tabs.lm = nil
    NS.UI.ej.srButtons = {}
    NS.UI.ej.srLabels = {}
    NS.UI.ej.currentLabel = nil
  end)

  self.frame = f

  local tabRow = AceGUI:Create("SimpleGroup")
  tabRow:SetFullWidth(true)
  tabRow:SetLayout("Flow")
  f:AddChild(tabRow)

  local myTab = AceGUI:Create("Button")
  myTab:SetText("My Soft-Res")
  myTab:SetWidth(140)
  myTab:SetCallback("OnClick", function()
    NS.UI:ShowPanel("my")
  end)
  tabRow:AddChild(myTab)
  self.tabs.my = myTab

  local raidTab = AceGUI:Create("Button")
  raidTab:SetText("Raid Status")
  raidTab:SetWidth(140)
  raidTab:SetCallback("OnClick", function()
    NS.UI:ShowPanel("raid")
  end)
  tabRow:AddChild(raidTab)
  self.tabs.raid = raidTab

  local lmTab = AceGUI:Create("Button")
  lmTab:SetText("Loot Master")
  lmTab:SetWidth(140)
  lmTab:SetCallback("OnClick", function()
    NS.UI:ShowPanel("lm")
  end)
  tabRow:AddChild(lmTab)
  self.tabs.lm = lmTab

  local contentHost = AceGUI:Create("SimpleGroup")
  contentHost:SetFullWidth(true)
  contentHost:SetHeight(390)
  contentHost:SetLayout("Fill")
  f:AddChild(contentHost)
  self.contentHost = contentHost

  local panel = AceGUI:Create("InlineGroup")
  panel:SetFullWidth(true)
  panel:SetFullHeight(true)
  panel:SetLayout("Flow")
  contentHost:AddChild(panel)
  self.mainPanel = panel

  self:ShowPanel(self.tabs.selected or "my")
end

function NS.UI:UpdateCurrentSRLabel()
  if not self.ej.currentLabel then return end

  local sr = LeagueResDB.profile.mySR or { 0, 0 }

  local t1, t2 = NS:ReservationText(sr[1]), NS:ReservationText(sr[2])
  self.ej.currentLabel:SetText(("Selected: %s   |   %s"):format(t1, t2))

end

function NS.UI:UpdateLootPickerActiveLabel()
  return
end

function NS.UI:SetSelectedSRSlot(slot)
  self.ej.selectedTarget = slot or 1
  self:RefreshSRVisuals()
  self:UpdateLootPickerActiveLabel()
end

function NS.UI:SetSRSlot(slot, itemID)
  if slot ~= 1 and slot ~= 2 then return end

  local sr = LeagueResDB.profile.mySR or { 0, 0 }
  sr[slot] = NS:Reservation(itemID)
  LeagueResDB.profile.mySR = sr

  self:RefreshSRVisuals()
  self:UpdateCurrentSRLabel()
end

function NS.UI:RefreshSRVisuals()
  local sr = LeagueResDB.profile.mySR or { 0, 0 }

  for slot = 1, 2 do
    local itemID = sr[slot] or 0
    local row = self.ej.srButtons[slot]
    local label = self.ej.srLabels[slot]

    if label then
      if self.ej.selectedTarget == slot then
        label:SetText(("|cff00ff00Soft-Res #%d|r"):format(slot))
      else
        label:SetText(("Soft-Res #%d"):format(slot))
      end
    end

    if row and row.item then
      if itemID ~= 0 then
        local text = NS:ReservationText(itemID)
        local icon = itemIconFromID(itemID) or 134400

        row.item:SetText(text)
        if row.item.SetImage then
          row.item:SetImage(icon)
          row.item:SetImageSize(18, 18)
        end
      else
        row.item:SetText("|cff888888Click to choose an item|r")
        if row.item.SetImage then
          row.item:SetImage(134400)
          row.item:SetImageSize(18, 18)
        end
      end
    end
  end
end

function NS.UI:CreateSRSlotWidget(parent, slot)
  local row = AceGUI:Create("SimpleGroup")
  row:SetFullWidth(true)
  row:SetLayout("Flow")
  parent:AddChild(row)

  local label = AceGUI:Create("Label")
  label:SetWidth(120)
  label:SetText(("Soft-Res #%d"):format(slot))
  row:AddChild(label)
  self.ej.srLabels[slot] = label

  local item = AceGUI:Create("InteractiveLabel")
  item:SetWidth(500)
  item:SetText("Click to choose an item")
  if item.SetImage then
    item:SetImage(134400)
    item:SetImageSize(18, 18)
  end
  item:SetCallback("OnClick", function()
    NS.UI:SetSelectedSRSlot(slot)
    NS.UI:OpenLootPicker()
  end)
  row:AddChild(item)

  local clearBtn = AceGUI:Create("Button")
  clearBtn:SetWidth(90)
  clearBtn:SetText("Clear")
  clearBtn:SetCallback("OnClick", function()
    NS.UI:SetSRSlot(slot, 0)
  end)
  row:AddChild(clearBtn)

  self.ej.srButtons[slot] = {
    row = row,
    item = item,
    clearBtn = clearBtn,
  }
end

function NS.UI:BuildMyPanel(container)
  if not container then return end

  self.ej.srButtons = {}
  self.ej.srLabels = {}
  self.ej.currentLabel = nil
  self.ej.targetDrop = nil

  local info = AceGUI:Create("Label")
  info:SetFullWidth(true)
  info:SetText("Click a Soft-Res row to choose an item from the loot picker. Use Clear to remove an item.")
  container:AddChild(info)

  self:CreateSRSlotWidget(container, 1)
  self:CreateSRSlotWidget(container, 2)

  local btnRow = AceGUI:Create("SimpleGroup")
  btnRow:SetFullWidth(true)
  btnRow:SetLayout("Flow")
  container:AddChild(btnRow)

  local saveBtn = AceGUI:Create("Button")
  saveBtn:SetText("Save Locally")
  saveBtn:SetWidth(150)
  saveBtn:SetCallback("OnClick", function()
    NS.UI:RefreshSRVisuals()
    NS.UI:UpdateCurrentSRLabel()
    print("|cff00ff00LeagueRes:|r Saved.")
  end)
  btnRow:AddChild(saveBtn)

  local submitBtn = AceGUI:Create("Button")
  submitBtn:SetText("Submit to Raid")
  submitBtn:SetWidth(150)
  submitBtn:SetCallback("OnClick", function()
    if NS.State.raid.locked or (NS.State.raid.settings and NS.State.raid.settings.lockSR) then
      print("|cffff0000LeagueRes:|r Soft-res is locked by Loot Master.")
      return
    end

    local sr = LeagueResDB.profile.mySR or { 0, 0 }
    NS:SubmitMySR(sr[1] or 0, sr[2] or 0)
  end)
  btnRow:AddChild(submitBtn)

  local requestBtn = AceGUI:Create("Button")
  requestBtn:SetText("Request Sync")
  requestBtn:SetWidth(150)
  requestBtn:SetCallback("OnClick", function()
    NS:RequestSync()
  end)
  btnRow:AddChild(requestBtn)

  local current = AceGUI:Create("Label")
  current:SetFullWidth(true)
  container:AddChild(current)
  self.ej.currentLabel = current

  self:RefreshSRVisuals()
  self:UpdateCurrentSRLabel()
end

function NS.UI:BuildRaidPanel(container)
  if not container then return end

  local holder = AceGUI:Create("SimpleGroup")
  holder:SetFullWidth(true)
  holder:SetFullHeight(true)
  holder:SetLayout("Fill")
  container:AddChild(holder)

  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("List")
  scroll:SetFullWidth(true)
  scroll:SetFullHeight(true)
  holder:AddChild(scroll)

  self.raidScroll = scroll
end

function NS.UI:RefreshRaidPanel()
  if not self.raidScroll then return end
  self.raidScroll:ReleaseChildren()

  local reservations = NS.State.raid.reservationsByGuid or {}
  local nameByGuid = NS.State.raid.nameByGuid or {}

  local rows = {}
  local itemCounts = {}

  for guid, sr in pairs(reservations) do
    local name = nameByGuid[guid] or guid
    local a = (sr and sr[1]) or 0
    local b = (sr and sr[2]) or 0

    local keyA, keyB = NS:ReservationKey(a), NS:ReservationKey(b)
    if keyA then itemCounts[keyA] = (itemCounts[keyA] or 0) + 1 end
    if keyB and keyB ~= keyA then itemCounts[keyB] = (itemCounts[keyB] or 0) + 1 end

    rows[#rows + 1] = {
      guid = guid,
      name = name,
      sr1 = a,
      sr2 = b,
    }
  end

  table.sort(rows, function(x, y)
    return (x.name or ""):lower() < (y.name or ""):lower()
  end)

  if #rows == 0 then
    local empty = AceGUI:Create("Label")
    empty:SetFullWidth(true)
    empty:SetText("|cff888888No soft-reservations received yet.|r")
    self.raidScroll:AddChild(empty)
    return
  end

  local header = AceGUI:Create("Label")
  header:SetFullWidth(true)
  header:SetText(("|cffffff00%d reservation(s) received.|r"):format(#rows))
  self.raidScroll:AddChild(header)

  local spacer = AceGUI:Create("Label")
  spacer:SetFullWidth(true)
  spacer:SetText(" ")
  self.raidScroll:AddChild(spacer)

  local function addItemWidget(parent, itemID)
    local key = NS:ReservationKey(itemID)
    local count = (key and itemCounts[key]) or 0
    local icon = itemIconFromID(itemID)
    local r = NS:Reservation(itemID)
    local link = r ~= 0 and r.link or nil

    local text
    if itemID == 0 then
      text = "—"
    else
      text = NS:ReservationText(itemID)
      if count > 1 then
        text = ("%s |cffffaa00(%dx reserved)|r"):format(text, count)
      end
    end

    local w = AceGUI:Create("InteractiveLabel")
    w:SetWidth(260)
    w:SetText(text)

    if w.SetImage then
      w:SetImage(icon or 134400)
      w:SetImageSize(16, 16)
    end

    if itemID ~= 0 then
      w:SetCallback("OnClick", function()
        if link and ChatFrame1EditBox then
          ChatEdit_ActivateChat(ChatFrame1EditBox)
          ChatFrame1EditBox:Insert(link)
        end
      end)
    end

    parent:AddChild(w)
  end

  for _, entry in ipairs(rows) do
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    self.raidScroll:AddChild(row)

    local nameLabel = AceGUI:Create("Label")
    nameLabel:SetWidth(180)
    nameLabel:SetText(("|cff00ffcc%s|r"):format(entry.name))
    row:AddChild(nameLabel)

    addItemWidget(row, entry.sr1)
    addItemWidget(row, entry.sr2)
  end
end

function NS.UI:BuildLMPanel(container)
  if not container then return end

  local lmToggle = AceGUI:Create("CheckBox")
  lmToggle:SetLabel("I am Loot Master for this raid (broadcast settings / view all SRs)")
  lmToggle:SetValue(LeagueResDB.profile.isLootMaster and true or false)
  lmToggle:SetFullWidth(true)
  lmToggle:SetCallback("OnValueChanged", function(_, _, val)
    LeagueResDB.profile.isLootMaster = val and true or false
    if val and not NS:CanBroadcastAsLootMaster() then
      print("|cffffaa00LeagueRes:|r You are not leader/assistant; others may ignore your settings.")
    end
  end)
  container:AddChild(lmToggle)

  local settings = LeagueResDB.profile.settings

  local srCount = AceGUI:Create("Slider")
  srCount:SetLabel("Soft-Res slots (UI currently supports 2)")
  srCount:SetSliderValues(1, 4, 1)
  srCount:SetValue(settings.srCount or 2)
  srCount:SetFullWidth(true)
  srCount:SetCallback("OnValueChanged", function(_, _, v)
    settings.srCount = math.floor(v + 0.5)
  end)
  container:AddChild(srCount)

  local allowOpen = AceGUI:Create("CheckBox")
  allowOpen:SetLabel("Allow open roll when nobody soft-res'd the item")
  allowOpen:SetValue(settings.allowOpenIfNoSR and true or false)
  allowOpen:SetFullWidth(true)
  allowOpen:SetCallback("OnValueChanged", function(_, _, v)
    settings.allowOpenIfNoSR = v and true or false
  end)
  container:AddChild(allowOpen)

  local maxWins = AceGUI:Create("EditBox")
  maxWins:SetLabel("Max wins per player (0 = unlimited)")
  maxWins:SetFullWidth(true)
  maxWins:SetText(tostring(settings.maxWins or 0))
  maxWins:SetCallback("OnEnterPressed", function(_, _, txt)
    local n = tonumber(txt) or 0
    settings.maxWins = math.max(0, math.floor(n))
  end)
  container:AddChild(maxWins)

  local lock = AceGUI:Create("CheckBox")
  lock:SetLabel("Lock soft-res changes (prevents submits)")
  lock:SetValue(settings.lockSR and true or false)
  lock:SetFullWidth(true)
  lock:SetCallback("OnValueChanged", function(_, _, v)
    settings.lockSR = v and true or false
  end)
  container:AddChild(lock)

  local btnRow = AceGUI:Create("SimpleGroup")
  btnRow:SetFullWidth(true)
  btnRow:SetLayout("Flow")
  container:AddChild(btnRow)

  local broadcast = AceGUI:Create("Button")
  broadcast:SetText("Broadcast Settings")
  broadcast:SetWidth(170)
  broadcast:SetCallback("OnClick", function()
    NS:BroadcastSettings()
  end)
  btnRow:AddChild(broadcast)

  local dump = AceGUI:Create("Button")
  dump:SetText("Broadcast Full Sync")
  dump:SetWidth(170)
  dump:SetCallback("OnClick", function()
    NS:BroadcastFullSync()
  end)
  btnRow:AddChild(dump)

  local clearAll = AceGUI:Create("Button")
  clearAll:SetText("Clear All Reservations")
  clearAll:SetWidth(170)
  clearAll:SetCallback("OnClick", function()
    NS:ClearAllReservations()
  end)
  btnRow:AddChild(clearAll)
end

function NS.UI:RefreshLMPanel()
  -- reserved for future dynamic LM refresh logic
end

function NS.UI:OpenLootPicker()
  if self.lootPickerFrame then
    self.lootPickerFrame:Show()
    self:UpdateLootPickerActiveLabel()
    self:RefreshEJList(false)
    return
  end

  local f = AceGUI:Create("Frame")
  f:SetTitle("LeagueRes - Loot Picker")
  f:SetWidth(640)
  f:SetHeight(560)
  f:SetLayout("Flow")
  f:EnableResize(false)
  self.lootPickerFrame = f
  f:SetCallback("OnClose", function(widget)
    NS.UI:StopEJRefresh()
    NS.UI.lootPickerFrame = nil
    NS.UI.picker.lootScroll = nil
    NS.UI.picker.tierDrop = nil
    NS.UI.picker.instanceDrop = nil
    NS.UI.picker.diffDrop = nil
    NS.UI.picker.searchBox = nil
    AceGUI:Release(widget)
  end)


  local closeAfter = AceGUI:Create("CheckBox")
  closeAfter:SetLabel("Close after selection")
  closeAfter:SetValue(self.picker.closeAfterSelect and true or false)
  closeAfter:SetFullWidth(true)
  closeAfter:SetCallback("OnValueChanged", function(_, _, v)
    self.picker.closeAfterSelect = v and true or false
  end)
  f:AddChild(closeAfter)

  local row1 = AceGUI:Create("SimpleGroup")
  row1:SetFullWidth(true)
  row1:SetLayout("Flow")
  f:AddChild(row1)

  local tierDrop = AceGUI:Create("Dropdown")
  tierDrop:SetLabel("Tier")
  tierDrop:SetWidth(220)
  row1:AddChild(tierDrop)
  self.picker.tierDrop = tierDrop

  local instDrop = AceGUI:Create("Dropdown")
  instDrop:SetLabel("Raid")
  instDrop:SetWidth(280)
  row1:AddChild(instDrop)
  self.picker.instanceDrop = instDrop

  local row2 = AceGUI:Create("SimpleGroup")
  row2:SetFullWidth(true)
  row2:SetLayout("Flow")
  f:AddChild(row2)

  local diffDrop = AceGUI:Create("Dropdown")
  diffDrop:SetLabel("Difficulty")
  diffDrop:SetWidth(220)
  diffDrop:SetList({})
  row2:AddChild(diffDrop)
  self.picker.diffDrop = diffDrop

  local search = AceGUI:Create("EditBox")
  search:SetLabel("Search loot")
  search:SetWidth(280)
  row2:AddChild(search)
  self.picker.searchBox = search

  local lootScroll = AceGUI:Create("ScrollFrame")
  lootScroll:SetLayout("List")
  lootScroll:SetFullWidth(true)
  lootScroll:SetHeight(340)
  f:AddChild(lootScroll)
  self.picker.lootScroll = lootScroll

  local tiers = NS.EJ:GetRaidTiers()
  local tierList = {}
  for _, t in ipairs(tiers) do
    tierList[t.index] = t.name
  end
  tierDrop:SetList(tierList)

  local savedTier = LeagueResDB.profile.ej and LeagueResDB.profile.ej.tierIndex
  local savedInst = LeagueResDB.profile.ej and LeagueResDB.profile.ej.instanceID
  local savedDiff = LeagueResDB.profile.ej and LeagueResDB.profile.ej.difficultyID

  local defaultTier = savedTier
  if not defaultTier then
    defaultTier = tiers[#tiers] and tiers[#tiers].index or 1
  end

  tierDrop:SetValue(defaultTier)
  diffDrop:SetValue(savedDiff or 14)

  tierDrop:SetCallback("OnValueChanged", function(_, _, tierIndex)
  LeagueResDB.profile.ej.tierIndex = tierIndex

  NS.EJ:InvalidateLootCache()

  NS.UI:RefreshEJInstances()
end)

  instDrop:SetCallback("OnValueChanged", function(_, _, instanceID)
  LeagueResDB.profile.ej.instanceID = instanceID

  NS.EJ:InvalidateLootCache(instanceID)

  NS.UI:RefreshEJDifficulties()
  NS.UI:RefreshEJList(true)
end)

  diffDrop:SetCallback("OnValueChanged", function(_, _, diffID)
  LeagueResDB.profile.ej.difficultyID = diffID

  NS.EJ:InvalidateLootCache(LeagueResDB.profile.ej.instanceID)

  NS.UI:RefreshEJList(true)
end)

  search:SetCallback("OnTextChanged", function()
    NS.UI:RefreshEJList(false)
  end)

  LeagueResDB.profile.ej.tierIndex = defaultTier
  LeagueResDB.profile.ej.instanceID = savedInst

  self:UpdateLootPickerActiveLabel()
  self:RefreshEJInstances()
end

function NS.UI:RefreshEJInstances()
  if not self.picker.instanceDrop or not self.picker.tierDrop then return end

  local tier = self.picker.tierDrop:GetValue()
  if not tier then return end

  local instances = NS.EJ:GetRaidInstancesForTier(tier)
  local list, firstID = {}, nil

  for _, inst in ipairs(instances) do
    list[inst.instanceID] = inst.name
    if not firstID then
      firstID = inst.instanceID
    end
  end

  self.picker.instanceDrop:SetList(list)

  local savedInst = LeagueResDB.profile.ej and LeagueResDB.profile.ej.instanceID
  local chosen = (savedInst and list[savedInst]) and savedInst or firstID

  LeagueResDB.profile.ej.instanceID = chosen
  self.picker.instanceDrop:SetValue(chosen)

  self:RefreshEJDifficulties()
  self:RefreshEJList(true)
end

function NS.UI:RefreshEJDifficulties()
  local list, order = NS.EJ:GetDifficulties(LeagueResDB.profile.ej.instanceID)
  self.picker.diffDrop:SetList(list, order)
  local chosen = LeagueResDB.profile.ej.difficultyID
  if not list[chosen] then chosen = order[1] end
  LeagueResDB.profile.ej.difficultyID = chosen
  self.picker.diffDrop:SetValue(chosen)
end

function NS.UI:RefreshReservationPanels()
  self:RefreshSRVisuals()
  self:UpdateCurrentSRLabel()
  self:RefreshRaidPanel()
end

function NS.UI:StopEJRefresh()
  if self.picker.refreshTimer then self.picker.refreshTimer:Cancel() end
  self.picker.refreshTimer = nil
end

function NS.UI:IsPickerOpen()
  return self.lootPickerFrame and self.lootPickerFrame.frame:IsShown() and self.picker.lootScroll
end

function NS.UI:QueueEJRefresh()
  if not self:IsPickerOpen() or self.picker.refreshTimer then return end
  self.picker.refreshTimer = C_Timer.NewTimer(0.25, function()
    self.picker.refreshTimer = nil
    if self:IsPickerOpen() then self:RefreshEJList(false) end
  end)
end

function NS.UI:RefreshEJList(forceInvalidate)
  if not self:IsPickerOpen() then return end
  if self.picker.refreshing then return end

  local instanceID = LeagueResDB.profile.ej and LeagueResDB.profile.ej.instanceID
  local diffID = LeagueResDB.profile.ej and LeagueResDB.profile.ej.difficultyID or 14
  if not instanceID then return end

  if forceInvalidate then
    self:StopEJRefresh()
    self.picker.retries = 0
    NS.EJ:InvalidateLootCache(instanceID)
  end

  self.picker.refreshing = true
  local loot, pending = NS.EJ:GetInstanceLoot(instanceID, diffID)
  local q = (self.picker.searchBox and self.picker.searchBox:GetText() or ""):lower()

  self.picker.lootScroll:ReleaseChildren()
  self:UpdateLootPickerActiveLabel()

  local shownCount = 0
  for _, it in ipairs(loot) do
    local shown = displayLinkOrFallback(it.itemID, it.link, it.name)
    local nameForSearch = (it.name or shown):lower()

    if q == "" or nameForSearch:find(q, 1, true) then
      shownCount = shownCount + 1
      local btn = AceGUI:Create("Button")
      btn:SetFullWidth(true)
      btn:SetText(shown .. " [" .. NS:DifficultyName(it.difficultyID) .. "]")
      btn:SetDisabled(not it.name or not it.link)
      btn:SetCallback("OnClick", function()
        NS.UI:SetSRSlot(NS.UI.ej.selectedTarget or 1, it)
        if NS.UI.picker.closeAfterSelect and NS.UI.lootPickerFrame then
          NS.UI.lootPickerFrame:Hide()
          NS.UI:StopEJRefresh()
        end
      end)
      self.picker.lootScroll:AddChild(btn)
    end
  end

  if #loot == 0 then
    local lbl = AceGUI:Create("Label")
    lbl:SetFullWidth(true)
    lbl:SetText("Loading loot data... If nothing appears, reselect the raid to retry.")
    self.picker.lootScroll:AddChild(lbl)
  elseif pending or shownCount == 0 then
    local lbl = AceGUI:Create("Label")
    lbl:SetFullWidth(true)
    lbl:SetText(pending and "Some loot is still loading..." or "No items match your search.")
    self.picker.lootScroll:AddChild(lbl)
  end
  self.picker.refreshing = false
  if pending then
    self.picker.retries = (self.picker.retries or 0) + 1
    if self.picker.retries <= 20 then self:QueueEJRefresh() end
  else
    self:StopEJRefresh()
    self.picker.retries = 0
  end

end

function NS.UI:ShowRollPrompt(data)
  if self.rollFrame then
    self.rollFrame:ReleaseChildren()
  else
    self.rollFrame = AceGUI:Create("Frame")
    self.rollFrame:SetTitle("LeagueRes - Loot Roll")
    self.rollFrame:SetWidth(420)
    self.rollFrame:SetHeight(220)
    self.rollFrame:SetLayout("Flow")
    self.rollFrame:EnableResize(false)
  end

  local f = self.rollFrame
  f:SetStatusText(("%s"):format(data.decision or ""))

  local itemLbl = AceGUI:Create("Label")
  itemLbl:SetFullWidth(true)
  itemLbl:SetText(data.itemLink or ("item:" .. tostring(data.itemID)))
  f:AddChild(itemLbl)

  local why = AceGUI:Create("Label")
  why:SetFullWidth(true)
  why:SetText(data.reason or "")
  f:AddChild(why)

  local row = AceGUI:Create("SimpleGroup")
  row:SetFullWidth(true)
  row:SetLayout("Flow")

  local function mkBtn(text, rollType)
    local b = AceGUI:Create("Button")
    b:SetText(text)
    b:SetWidth(95)
    b:SetCallback("OnClick", function()
      if data.rollID then
        RollOnLoot(data.rollID, rollType)
      end
      f:Hide()
    end)
    return b
  end

  row:AddChild(mkBtn("Pass", 0))
  row:AddChild(mkBtn("Need", 1))
  row:AddChild(mkBtn("Greed", 2))
  row:AddChild(mkBtn("DE", 3))

  f:AddChild(row)
  f:Show()
end
