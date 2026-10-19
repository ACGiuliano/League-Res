local root = arg[1] or 'work/LeagueRes/'
local currentGuid, raid, instanceDiff = 'Player-A', true, 14
local messages, rolls, timers = {}, {}, {}
local prompts = {}
local tests = 0
local function check(value, message)
  assert(value, message)
  tests = tests + 1
  print('PASS: ' .. message)
end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function UnitGUID(unit) return unit == 'player' and currentGuid or 'Player-B' end
function GetUnitName(unit) return unit == 'player' and 'Alice-Realm' or 'Bob-Realm' end
function IsInRaid() return raid end
function IsInGroup() return raid end
function GetNumGroupMembers() return raid and 2 or 0 end
function GetServerTime() return 1800000000 end
function GetNormalizedRealmName() return 'Realm' end
function UnitExists() return true end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end
function GetDifficultyInfo(id) return ({[14]='Normal',[15]='Heroic',[16]='Mythic',[3]='10 Normal',[4]='25 Normal',[5]='10 Heroic',[6]='25 Heroic'})[id] end
function GetInstanceInfo() return 'Raid', 'raid', instanceDiff end
function GetItemInfo(item) return 'Cached Sword', '|Hitem:100|h[Cached Sword]|h',nil,nil,nil,nil,nil,nil,nil,123 end
C_Item = {GetItemInfo=GetItemInfo,GetItemIconByID=function() return 123 end,RequestLoadItemDataByID=function() end}
C_ChatInfo = {RegisterAddonMessagePrefix=function() end}
C_Timer = {NewTimer=function(delay, callback)
 local t = { callback=callback, Cancel=function(self) self.cancelled=true end }
 timers[#timers+1] = t
 return t
end}
local function drainTimers(limit)
 for n=1,limit do
  local t = table.remove(timers,1)
  if not t then return end
  if not t.cancelled then t.callback() end
 end
end
local function widget()
 local w={ children={}, callbacks={}, shown=true }
 w.frame={IsShown=function() return w.shown end}
 setmetatable(w,{__index=function(_, key)
  if key:match("^[A-Z]") then return function(self,...) self[key..'Args']={...} end end
 end})
 function w:AddChild(child) self.children[#self.children+1]=child end
 function w:ReleaseChildren() self.children={} end
 function w:SetText(text) self.text=text end
 function w:GetText() return self.text or '' end
 function w:SetValue(v) self.value=v end
 function w:GetValue() return self.value end
 function w:SetList(list, order) self.list,self.order=list,order end
 function w:SetCallback(k, cb) self.callbacks[k]=cb end
 function w:SetDisabled(b) self.disabled=b end
 function w:Show() self.shown=true end
 function w:Hide() self.shown=false end
 return w
end
local AceGUI={Create=function() return widget() end,Release=function(w) w.released=true end}
local AceAddon={NewAddon=function()
 return { RegisterComm=function() end,RegisterChatCommand=function() end,RegisterEvent=function() end,
 SendCommMessage=function() end }
end}
function LibStub(name)
 if name=='AceAddon-3.0' then return AceAddon end
 if name=='AceGUI-3.0' then return AceGUI end
 return {Serialize=function(_,data) return data end,Deserialize=function(_,data) return true,data end}
end
local ejInstance, ejDiff, classFilter, slotFilter, searchFilter, ready = 1, 15, 6, 4, true, false
EncounterJournal = {}
function EJ_GetNumTiers() return 1 end
function EJ_GetTierInfo() return 'Tier' end
function EJ_SelectTier() end
function EJ_GetInstanceByIndex(i) if i==1 then return 1,'Modern' elseif i==2 then return 2,'Legacy' end end
function EJ_SelectInstance(id) ejInstance=id end
function EJ_IsValidInstanceDifficulty(id) return (ejInstance==1 and (id==14 or id==15 or id==16)) or (ejInstance==2 and (id==3 or id==4 or id==5 or id==6)) end
function EJ_SetDifficulty(id) ejDiff=id end
function EJ_GetDifficulty() return ejDiff end
function EJ_ResetLootFilter() classFilter=0 end
function EJ_ClearSearch() searchFilter=false end
function EJ_SetLootFilter(class) classFilter=class end
function EJ_GetNumLoot() return ready and 2 or 0 end
Enum={ItemSlotFilterType={NoFilter=0},ItemCreationContext={
 None=0,RaidNormal=3,RaidFinder=4,RaidHeroic=5,RaidMythic=6,Vendor=14,
 RaidNormalExtended=82,RaidHeroicExtended=84,RaidMythicExtended=85,
 RaidHeroicExtended_2=91,RaidHeroicExtended_3=95,
}}
local function contextLink(id,context)
 return '|cnIQ4|Hitem:'..id..':0:0:0:0:0:0:0:80:0:0:'..context..':0|h[Sword]|h'
end
local function itemLink(id,diff)
 local contexts={[14]=3,[15]=5,[16]=6,[17]=4,[3]=3,[4]=3,[5]=5,[6]=5}
 assert(contexts[diff], 'test link needs an explicit difficulty-to-context mapping')
 return contextLink(id,contexts[diff])
end
C_EncounterJournal={SetSlotFilter=function(v) slotFilter=v end,
 GetLootInfoByIndex=function(i)
  if i==1 then return {itemID=100,name='Sword',link=itemLink(100,ejDiff),icon=123} end
  return ready=='partial' and {itemID=101} or {itemID=101,name='Axe',link=itemLink(101,ejDiff),icon=123}
 end}
function GetLootRollItemLink(id) return itemLink(100,id==1 and 14 or 15) end
function GetLootRollItemInfo() return 123,'Sword' end
function RollOnLoot(id,kind) rolls[#rolls+1]={id,kind} end
function SendChatMessage() end
local function loadAddon()
 local ns={}
 for _,file in ipairs({'Data.lua','Comm.lua','EJ.lua','UI.lua','Loot.lua','Core.lua'}) do
  assert(loadfile(root..file))('LeagueRes', ns)
 end
 ns.Addon:OnInitialize()
 ns.Comm.Broadcast=function(_,msg) messages[#messages+1]=ns:Copy(msg) end
 ns.Comm.Whisper=function(_,msg,target) messages[#messages+1]=ns:Copy(msg) end
 ns.UI.ShowRollPrompt=function(_,data) prompts[#prompts+1]=data end
 return ns
end
LeagueResDB={profile={mySR={100,0}}}
local ns=loadAddon()
check(ns.Character.mySR[1].itemID==100 and ns.Character.mySR[1].difficultyID==nil,'legacy selection retained without guessing difficulty')
ns:SubmitMySR(ns.Character.mySR[1],0)
check(ns.State.raid.reservationsByGuid[currentGuid]==nil,'legacy selection requires reselect before submit')
local normal={itemID=100,difficultyID=14,instanceID=1,link=itemLink(100,14),name='Sword'}
local heroic={itemID=100,difficultyID=15,instanceID=1,link=itemLink(100,15),name='Sword'}
ns.UI:SetSRSlot(1,normal)
ns:SubmitMySR(normal,0)
ns.State.raid.winsByGuid[currentGuid]=2
ns.State.raid.locked=true
ns.State.raid.settings={lockSR=true,allowOpenIfNoSR=true,maxWins=0}
ns.State.raid.lootMasterGuid=currentGuid
LeagueResDB.profile.isLootMaster=true
ns.UI:SetSRSlot(1,heroic)
-- Simulate the SavedVariables serialize/deserialize boundary, then fresh Lua modules.
LeagueResDB=ns:Copy(LeagueResDB)
ns=loadAddon()
check(ns.State.raid.reservationsByGuid[currentGuid][1].difficultyID==14,'submitted Normal reservation survives reload')
check(ns.Character.mySR[1].difficultyID==15,'unsubmitted Heroic draft survives independently')
check(ns.State.raid.winsByGuid[currentGuid]==2 and ns.State.raid.locked,'wins and lock survive reload')
check(ns.State.raid.nameByGuid[currentGuid]=='Alice-Realm','saved names survive reload')
ns:OnComm({t='HELLO',v=3},'Bob-Realm')
local sync=messages[#messages]
check(sync.t=='FULLSYNC' and sync.reservations[currentGuid][1].difficultyID==14 and sync.settings.lockSR,'loot master sends saved state on reconnect')
check(ns:LootDifficulty(itemLink(100,15))==15,'loot link difficulty overrides current instance')
check(ns:LootDifficulty('item:100')==14,'old link falls back to actual instance difficulty')
check(ns:MatchesReservation(normal,100,14) and not ns:MatchesReservation(normal,100,15),'same ID has distinct Normal and Heroic eligibility')
check(ns:ReservationKey(normal)~=ns:ReservationKey(heroic),'raid counts distinguish difficulties')
ns.Loot:OnStartLootRoll(1)
check(prompts[#prompts].decision=='ROLL (SR)','submitted Normal SR eligible despite Heroic draft')
ns.Loot:OnStartLootRoll(2)
check(prompts[#prompts].decision=='ROLL (OPEN)','Heroic version is unreserved when only Normal reserved')
ns.State.raid.reservationsByGuid['Player-B']={heroic,0}
ns.Loot:OnStartLootRoll(2)
check(rolls[#rolls][1]==2 and rolls[#rolls][2]==0,'auto-pass only matching Heroic reservation of another player')
local before=#rolls
ns.State.raid.reservationsByGuid['Player-B']={{itemID=100},0}
ns.Loot:OnStartLootRoll(2)
check(#rolls==before and prompts[#prompts].decision=='CHECK DIFFICULTY','unknown legacy difficulty cannot cause auto-pass')
ns:OnComm({t='RESERVE',v=3,guid='Player-B',sr={heroic,0}},'Bob-Realm')
check(ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==nil,'lock rejects incoming reservation edits')
ns:ClearAllReservations()
LeagueResDB=ns:Copy(LeagueResDB)
ns=loadAddon()
check(next(ns.State.raid.reservationsByGuid)==nil,'clear remains cleared after reload')
LeagueResDB.profile.isLootMaster=false
ns.State.raid.lootMasterGuid=nil
ns:OnComm({t='FULLSYNC',v=3,lm='Player-B',term=1,epoch=ns.State.raid.epoch,
 versions={['Player-B']=1},reservations={['Player-B']={heroic,0}},wins={['Player-B']=3},
 names={['Player-B']='Bob-Realm'}},'Bob-Realm')
LeagueResDB=ns:Copy(LeagueResDB)
ns=loadAddon()
check(ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==15 and ns.State.raid.winsByGuid['Player-B']==3,'received full sync persists replaced tables')
ns:OnComm({t='FULLSYNC',v=3,lm='Player-B',term=1,epoch=ns.State.raid.epoch+1,versions={},reservations={}},'Bob-Realm')
check(next(ns.State.raid.reservationsByGuid)==nil,'explicit new clear epoch removes previous reservations')
ns:OnComm({t='FULLSYNC',v=1,reservations={['Player-X']={100,0}}},'Old-Realm')
check(next(ns.State.raid.reservationsByGuid)==nil,'old protocol cannot strip difficulty metadata')
currentGuid='Player-C'
ns=loadAddon()
check(ns.Character.mySR[1]==0 and next(ns.State.raid.reservationsByGuid)==nil,'alternate character starts with separate reservations')
currentGuid='Player-A'
ns=loadAddon()
check(ns.Character.mySR[1].difficultyID==15,'returning character restores its own draft')
LeagueResDB.profile.ej={tierIndex=1,instanceID=1,difficultyID=14}
ready=false
local loot,pending=ns.EJ:GetInstanceLoot(1,14)
check(#loot==0 and pending,'cold Journal returns loading state')
check(classFilter==0 and slotFilter==0 and not searchFilter,'class/spec, slot and search filters reset')
ready='partial'
loot,pending=ns.EJ:GetInstanceLoot(1,14)
check(#loot==2 and pending,'incomplete item metadata remains pending')
ready=true
loot,pending=ns.EJ:GetInstanceLoot(1,14)
check(#loot==2 and not pending and loot[1].name=='Axe','cold/partial result is not permanently cached')
loot,pending=ns.EJ:GetInstanceLoot(1,15)
check(loot[1].difficultyID==15 and loot[1].link==itemLink(101,15),'difficulty switch uses correct Journal link')
loot,pending=ns.EJ:GetInstanceLoot(2,14)
check(#loot==0 and pending,'unsupported difficulty never silently labels loot incorrectly')
local choices=ns.EJ:GetDifficulties(2)
check(choices[3] and choices[6] and not choices[14],'legacy raids expose supported size/difficulty options')
ns.UI:OpenMain()
ns.UI:OpenLootPicker()
check(ns.UI.picker.lootScroll.children[1].text:find('Normal',1,true),'picker labels item difficulty')
ns.UI.picker.instanceDrop.callbacks.OnValueChanged(nil,nil,2)
check(LeagueResDB.profile.ej.difficultyID==3,'changing raid corrects invalid saved difficulty')
ns.UI.picker.instanceDrop.callbacks.OnValueChanged(nil,nil,1)
ready=false
ns.UI:RefreshEJList(true)
check(ns.UI.picker.refreshTimer~=nil,'cold picker schedules an automatic retry')
ready=true
drainTimers(30)
check(ns.UI.picker.lootScroll.children[1].text:find('item:101:',1,true),'automatic retry populates loaded loot')
ns.UI.picker.lootScroll.children[1].callbacks.OnClick()
check(ns.Character.mySR[1].itemID==101 and ns.Character.mySR[1].difficultyID==14,'picker saves item record including difficulty')
check(ns.UI.picker.refreshTimer==nil and not ns.UI:IsPickerOpen(),'selection hides picker and cancels retry')
ns.UI:OpenLootPicker()
ns.UI:ShowPanel('raid')
ns.UI:RefreshReservationPanels()
check(ns.UI.ej.currentLabel==nil and #ns.UI.ej.srButtons==0,'tab switch discards released SR widget references')
ns.UI.lootPickerFrame.callbacks.OnClose(ns.UI.lootPickerFrame)
check(ns.UI.lootPickerFrame==nil and ns.UI.picker.lootScroll==nil,'closing picker releases widgets and pending timers')
ns.UI:OpenLootPicker()
local oldInfo=C_EncounterJournal.GetLootInfoByIndex
C_EncounterJournal.GetLootInfoByIndex=function(i)
 local info=oldInfo(i)
 info.link=itemLink(info.itemID,15)
 return info
end
LeagueResDB.profile.ej.difficultyID=14
ns.UI:RefreshEJList(true)
check(ns.UI.picker.lootScroll.children[1].disabled,'stale Heroic link is disabled in Normal picker')
local timer=ns.UI.picker.refreshTimer
ns.UI:QueueEJRefresh()
ns.UI:QueueEJRefresh()
check(ns.UI.picker.refreshTimer==timer,'bursts of loot events share one pending timer')
C_EncounterJournal.GetLootInfoByIndex=oldInfo
ready=false
ns.UI:RefreshEJList(true)
drainTimers(100)
check(ns.UI.picker.refreshTimer==nil and ns.UI.picker.retries==21,'empty Journal retry loop stops after 20 timers')
ready=true
ns.UI:QueueEJRefresh()
drainTimers(5)
check(ns.UI.picker.lootScroll.children[1].disabled==false,'late loot event recovers after retry timeout')
check(ns:ItemLinkContext(contextLink(100,5))==5,'link parser returns raw item context, not difficulty')
for difficulty,context in pairs({[14]=3,[15]=5,[16]=6,[17]=4}) do
 check(ns:ItemLinkDifficulty(contextLink(100,context))==difficulty,
  'real raid item context '..context..' maps to difficulty '..difficulty)
end
check(ns:ItemLinkDifficulty(contextLink(100,84))==15,'extended Heroic item context maps correctly')
check(ns:ItemLinkDifficulty(contextLink(100,91))==15,'second extended Heroic context maps correctly')
check(ns:ItemLinkDifficulty(contextLink(100,95))==15,'third extended Heroic context maps correctly')
check(ns:ItemLinkDifficulty(contextLink(100,14))==nil,'Vendor context 14 is not mistaken for Normal difficulty 14')
check(ns:ItemLinkDifficulty(contextLink(100,0))==nil,'context zero is treated as unspecified')
check(ns:ItemLinkDifficulty('|cnIQ4|Hitem:268215::::::::90:250::5:0|h[Weapon]|h')==15,
 'modern sparse item link parses Heroic context correctly')
check(ns:ItemLinkDifficulty(itemLink(100,4),4)==4,'legacy 25-player Normal size is preserved')
check(ns:ItemLinkDifficulty(itemLink(100,6),6)==6,'legacy 25-player Heroic size is preserved')
instanceDiff=6
check(ns:LootDifficulty(itemLink(100,6))==6,'loot roll preserves actual legacy Heroic raid difficulty')
instanceDiff=14
LeagueResDB.profile.ej.difficultyID=15
ns.UI.picker.diffDrop:SetValue(15)
ns.UI:RefreshEJList(true)
check(ns.UI.picker.lootScroll.children[1].disabled==false,'real context 5 leaves Heroic picker items enabled')
check(ns.UI.picker.lootScroll.children[1].text:find('Heroic',1,true),'Heroic picker keeps its difficulty label')
C_EncounterJournal.GetLootInfoByIndex=function(i)
 local info=oldInfo(i)
 info.link=nil
 return info
end
ns.UI:RefreshEJList(true)
check(ns.UI.picker.lootScroll.children[1].disabled==false,'known item name and ID remain selectable without a hyperlink')
ns.UI.picker.lootScroll.children[1].callbacks.OnClick()
check(ns.Character.mySR[1].difficultyID==15 and ns.Character.mySR[1].link==nil,
 'selection without hyperlink saves Heroic difficulty')
ns.State.raid.locked=false
ns:SubmitMySR(ns.Character.mySR[1],0)
local pending=ns.Character.pendingSubmission
if pending then
 ns:OnComm({t='ACCEPT',v=3,lm='Player-B',term=ns.State.raid.authorityTerm,
 epoch=ns.State.raid.epoch,guid=currentGuid,seq=pending.seq,sr=pending.sr},'Bob-Realm')
end
check(ns.State.raid.reservationsByGuid[currentGuid][1].difficultyID==15,
 'selection without hyperlink can be submitted')
ns.UI:OpenLootPicker()
C_EncounterJournal.GetLootInfoByIndex=function(i)
 local info=oldInfo(i)
 info.name=nil
 return info
end
ns.UI:RefreshEJList(true)
check(ns.UI.picker.lootScroll.children[1].disabled,'item lacking a name stays disabled')
C_EncounterJournal.GetLootInfoByIndex=oldInfo
local savedEnum=Enum.ItemCreationContext
Enum.ItemCreationContext=nil
check(ns:ItemLinkDifficulty(itemLink(100,15))==nil,'missing context enum does not guess raw context as difficulty')
ns.UI:RefreshEJList(true)
check(ns.UI.picker.lootScroll.children[1].disabled==false,'verified Journal selection works even if context enum is unavailable')
Enum.ItemCreationContext=savedEnum
ns.UI:StopEJRefresh()
-- Submission checks must use live unit IDs, not saved roster history.
local grouped, leader = true, true
local units={
 raid1={guid='Player-A',name='Alice-Realm'},
 raid2={guid='Player-B',name='Bob-Realm'},
 raid3={guid='Player-C',name='Charlie-OtherRealm'},
}
local memberCount=3
function IsInGroup() return grouped end
function IsInRaid() return raid end
function GetNumGroupMembers() return memberCount end
function UnitIsGroupLeader() return leader end
function UnitGUID(unit)
 if unit=='player' then return currentGuid end
 return units[unit] and units[unit].guid
end
function GetUnitName(unit)
 if unit=='player' then return 'Alice-Realm' end
 return units[unit] and units[unit].name
end
raid=true
LeagueResDB.profile.isLootMaster=false
ns.State.raid.lootMasterGuid='Player-B'
ns.State.raid.reservationsByGuid={['Player-A']={normal,0},['Player-B']={0,0},['Departed-Player']={heroic,0}}
ns.State.raid.nameByGuid['Departed-Player']='OldRaider-Realm'
local report=ns:GetSubmissionReport()
check(report.total==3 and report.submitted==2 and #report.missing==1,
 'report counts only current members and explicitly submitted empty selections')
check(report.missing[1]=='Charlie-OtherRealm','missing player comes from current roster with realm')
check(ns:CanCheckSubmissions(),'group leader can check without enabling Loot Master')
ns.State.raid.reservationsByGuid['Player-B']=nil
report=ns:GetSubmissionReport()
check(report.missing[1]=='Bob-Realm' and report.missing[2]=='Charlie-OtherRealm','missing names are alphabetical')
ns.Character.mySR={heroic,normal}
LeagueResDB.profile.mySR=ns.Character.mySR
ns.State.raid.reservationsByGuid['Player-A']=nil
report=ns:GetSubmissionReport()
check(report.submitted==0 and #report.missing==3,'unsubmitted local selections do not count')
local savedPrint=print
local printed={}
print=function(line) printed[#printed+1]=line end
local beforeMessages,beforeRolls=#messages,#rolls
ns:PrintMissingSubmissions()
print=savedPrint
check(#printed==4 and printed[1]:find('0/3',1,true) and printed[2]:find('Alice-Realm',1,true),
 'button prints total plus each missing player locally')
check(#messages==beforeMessages and #rolls==beforeRolls,'checking submissions does not broadcast or change loot rolls')
leader=false
check(not ns:CanCheckSubmissions(),'ordinary group member cannot run leader/LM check')
LeagueResDB.profile.isLootMaster=true
check(ns:CanCheckSubmissions(),'Loot Master can check without group leadership')
LeagueResDB.profile.isLootMaster=false
ns.State.raid.lootMasterGuid=currentGuid
check(ns:CanCheckSubmissions(),'designated Loot Master from sync can check')
ns.State.raid.lootMasterGuid='Player-B'
printed={}
print=function(line) printed[#printed+1]=line end
ns:PrintMissingSubmissions()
print=savedPrint
check(#printed==1 and printed[1]:find('Only the Loot Master',1,true),'unauthorized check explains permission')
leader=true
ns.UI:ShowPanel('lm')
check(ns.UI.missingSRButton and not ns.UI.missingSRButton.disabled,'Loot Master tab contains enabled check button for leader')
leader=false
ns:RebuildRoster()
check(ns.UI.missingSRButton.disabled,'button updates when player loses leadership')
local toggle=ns.UI.mainPanel.children[1]
ns.State.raid.lootMasterGuid=nil
toggle.callbacks.OnValueChanged(nil,nil,true)
check(not ns.UI.missingSRButton.disabled,'Loot Master toggle updates button access immediately')
leader=true
ns.State.raid.reservationsByGuid={['Player-A']={0,0},['Player-B']={normal,0},['Player-C']={heroic,0}}
printed={}
print=function(line) printed[#printed+1]=line end
ns.UI.missingSRButton.callbacks.OnClick()
print=savedPrint
check(#printed==2 and printed[2]:find('Everyone',1,true),'button reports everyone submitted when group is complete')
-- No online-status filtering: disconnected current members still count.
function UnitExists() return false end
ns.State.raid.reservationsByGuid['Player-C']=nil
report=ns:GetSubmissionReport()
check(#report.missing==1 and report.missing[1]=='Charlie-OtherRealm','disconnected group member remains in the report')
units.raid3=nil
printed={}
print=function(line) printed[#printed+1]=line end
ns:PrintMissingSubmissions()
print=savedPrint
check(printed[#printed]:find('still loading',1,true) and not printed[#printed]:find('Everyone',1,true),
 'unresolved roster entry warns instead of reporting everyone submitted')
raid=false
units={party1={guid='Player-B',name='Bob-Realm'},party2={guid='Player-C',name='Charlie-OtherRealm'}}
report=ns:GetSubmissionReport()
check(report.total==3 and report.submitted==2 and report.missing[1]=='Charlie-OtherRealm',
 'party enumeration counts player plus party units exactly once')
ns:RebuildRoster()
check(ns.State.raid.nameByGuid['Player-C']=='Charlie-OtherRealm','roster refresh uses party members correctly')
units.party2={guid='Player-D',name='Dana-Realm'}
report=ns:GetSubmissionReport()
check(report.missing[1]=='Dana-Realm' and #report.missing==1,'next click reflects membership changes and excludes departed player')
grouped=false
ns.UI:RefreshLMPanel()
check(ns.UI.missingSRButton.disabled,'button disables outside a group')
printed={}
print=function(line) printed[#printed+1]=line end
ns:PrintMissingSubmissions()
print=savedPrint
check(#printed==1 and printed[1]:find('Join a group',1,true),'solo check prints a helpful message')
ns.UI:ShowPanel('my')
check(ns.UI.missingSRButton==nil,'switching tabs releases the check-button reference')
print(string.format('%d regression checks passed.',tests))
