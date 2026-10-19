local root = arg[1] or 'work/LeagueRes/'
local clients, queue, clock = {}, {}, 1800000000
local tests = 0
local function check(value, message)
  assert(value, message)
  tests=tests+1
  print('PASS: '..message)
end
local function copy(t)
 if type(t)~='table' then return t end
 local out={} for k,v in pairs(t) do out[k]=copy(v) end return out
end
local function widget()
 local w={children={},callbacks={},shown=true}
 w.frame={IsShown=function() return w.shown end}
 setmetatable(w,{__index=function(_,k) if k:match('^[A-Z]') then return function() end end end})
 function w:AddChild(child) self.children[#self.children+1]=child end
 function w:ReleaseChildren() self.children={} end
 function w:SetText(text) self.text=text end
 function w:SetValue(v) self.value=v end
 function w:GetValue() return self.value end
 function w:GetText() return self.text or '' end
 function w:SetCallback(k,cb) self.callbacks[k]=cb end
 function w:SetDisabled(b) self.disabled=b end
 function w:Show() self.shown=true end
 function w:Hide() self.shown=false end
 return w
end
local roster={'A','B','C'}
local function newClient(id,db,version)
 local env=setmetatable({},{__index=_G})
 env._G=env
 env.print=function(...) end
 env.GetServerTime=function() return clock end
 env.GetTime=function() return clock end
 env.GetNormalizedRealmName=function() return 'Realm' end
 env.LE_PARTY_CATEGORY_INSTANCE=2
 env.IsInGroup=function(category) return category~=2 end
 env.IsInRaid=function() return true end
 env.GetNumGroupMembers=function() return #roster end
 env.UnitGUID=function(unit)
  if unit=='player' then return 'Player-'..id end
  local i=tonumber(unit:match('raid(%d+)'))
  return i and roster[i] and ('Player-'..roster[i])
 end
 env.GetUnitName=function(unit)
  local guid=env.UnitGUID(unit)
  return guid and (guid:sub(8)..'-Realm')
 end
 env.UnitExists=function(unit) return env.UnitGUID(unit)~=nil end
 env.UnitIsGroupLeader=function(unit) return env.UnitGUID(unit)=='Player-A' end
 env.UnitIsGroupAssistant=function(unit) return env.UnitGUID(unit)=='Player-B' end
 env.wipe=function(t) for k in pairs(t) do t[k]=nil end end
 env.C_ChatInfo={RegisterAddonMessagePrefix=function() end}
 env.C_AddOns={GetAddOnMetadata=function(addon,field) return field=='Version' and (version or '1.2') end}
 env.C_Item={GetItemInfo=function() return 'Sword','item:100' end,GetItemIconByID=function() return 123 end}
 env.GetDifficultyInfo=function(id) return id==15 and 'Heroic' or 'Normal' end
 env.C_Timer={NewTimer=function(_,cb) return {Cancel=function(self) self.cancelled=true end,callback=cb} end}
 env.LeagueResDB=copy(db)
 local aceGui={Create=function() return widget() end,Release=function(_,w) w.released=true end}
 env.LibStub=function(name)
  if name=='AceGUI-3.0' then return aceGui end
  if name=='AceAddon-3.0' then return {NewAddon=function()
   return {RegisterComm=function() end,RegisterChatCommand=function() end,RegisterEvent=function() end}
  end} end
  return {}
 end
 local ns={}
 for _,file in ipairs({'Data.lua','Core.lua','UI.lua'}) do assert(loadfile(root..file,'t',env))('LeagueRes',ns) end
 ns.Comm={Broadcast=function(_,msg) queue[#queue+1]={from=id,msg=copy(msg)} end,
  Whisper=function(_,msg,target) queue[#queue+1]={from=id,msg=copy(msg),target=target} end}
 ns.Addon:OnInitialize()
 clients[id]={ns=ns,env=env}
 return clients[id]
end
local function deliver(packet)
 for id,c in pairs(clients) do
  if not packet.target or packet.target==id..'-Realm' then c.ns:OnComm(copy(packet.msg),packet.from..'-Realm') end
 end
end
local function flush()
 local count=0
 while #queue>0 do
  count=count+1 assert(count<500,'sync loop / traffic storm')
  deliver(table.remove(queue,1))
 end
end
local normal={itemID=100,difficultyID=14,name='Sword'}
local heroic={itemID=100,difficultyID=15,name='Sword'}
local A,B,C=newClient('A'),newClient('B'),newClient('C')
A.env.LeagueResDB.profile.isLootMaster=true
A.ns:BroadcastSettings()
flush()
B.ns:SubmitMySR(normal,0)
flush()
check(A.ns.State.raid.reservationsByGuid['Player-B']~=nil,'first player reaches Loot Master')
A.ns:BroadcastFullSync()
local oldSnapshot=table.remove(queue,1)
C.ns:SubmitMySR(heroic,0)
flush()
check(A.ns.State.raid.reservationsByGuid['Player-C']~=nil,'second player reaches Loot Master')
deliver(oldSnapshot)
check(B.ns.State.raid.reservationsByGuid['Player-C']~=nil,'older snapshot must not remove newer player')
-- Multiple submissions in flight and snapshots arriving out of order.
B.ns:SubmitMySR(heroic,normal)
C.ns:SubmitMySR(normal,heroic)
check(B.ns.Character.pendingSubmission~=nil and C.ns.Character.pendingSubmission~=nil,'submissions wait for actual Loot Master confirmation')
check(B.ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==14,'pending edit does not replace previous confirmed SR')
flush()
for id,c in pairs(clients) do
 check(c.ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==15
  and c.ns.State.raid.reservationsByGuid['Player-C'][1].difficultyID==14,
  'simultaneous submissions converge on client '..id)
end
check(not B.ns.Character.pendingSubmission and not C.ns.Character.pendingSubmission,'acceptance clears pending states')
deliver(oldSnapshot)
check(B.ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==15,'older snapshot cannot restore old item choice')
A.ns:BroadcastFullSync()
local currentSnapshot=table.remove(queue,1)
local countBefore=0
for _ in pairs(A.ns.State.raid.reservationsByGuid) do countBefore=countBefore+1 end
deliver({from='A',msg={t='FULLSYNC',v=3,lm='Player-A',term=A.ns.State.raid.authorityTerm,
 epoch=A.ns.State.raid.epoch,settingsRevision=0,settings={lockSR=false},versions={},reservations={}}})
check(B.ns.State.raid.reservationsByGuid['Player-B'] and B.ns.State.raid.reservationsByGuid['Player-C'],
 'empty ordinary snapshot cannot remove received reservations')
check(A.ns.State.raid.reservationsByGuid['Player-C']~=nil,'Loot Master ignores echoed snapshot instead of overwriting own state')
-- Reopen the real UI repeatedly, checking rows and saved state each time.
for i=1,3 do
 B.ns.UI:OpenMain()
 B.ns.UI:ShowPanel('raid')
 check(#B.ns.UI.raidScroll.children==4,'raid list renders both players on reopen '..i)
 local frame=B.ns.UI.frame
 frame.callbacks.OnClose(frame)
 check(frame.released and B.ns.UI.frame==nil,'main frame releases cleanly on close '..i)
end
-- Another client's stale LM checkbox must not create a competing authority.
B.env.LeagueResDB.profile.isLootMaster=true
B.ns.State.raid.lootMasterGuid=nil
B.ns:BroadcastFullSync()
flush()
check(A.ns.State.raid.lootMasterGuid=='Player-A' and B.ns.State.raid.lootMasterGuid=='Player-A'
 and C.ns.State.raid.lootMasterGuid=='Player-A','conflicting LM claims converge to the group leader')
check(not B.env.LeagueResDB.profile.isLootMaster,'losing Loot Master checkbox is disabled automatically')
check(B.ns.State.raid.reservationsByGuid['Player-C']~=nil,'competing Loot Master cannot delete another player')
-- Validate sender identity; message GUIDs are not enough.
deliver({from='C',msg={t='RESERVE',v=3,guid='Player-B',sr={normal,0},seq=999,epoch=A.ns.State.raid.epoch}})
check(A.ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==15,'sender cannot overwrite another player GUID')
deliver({from='C',msg={t='FULLSYNC',v=3,lm='Player-A',term=A.ns.State.raid.authorityTerm,
 epoch=A.ns.State.raid.epoch+1,versions={},reservations={}}})
check(B.ns.State.raid.reservationsByGuid['Player-C']~=nil,'forged authority cannot clear the list')
-- A queued submission sent before the lock must be explicitly rejected.
C.ns:SubmitMySR(heroic,0)
A.env.LeagueResDB.profile.settings.lockSR=true
A.ns:BroadcastSettings()
flush()
check(C.ns.Character.pendingSubmission==nil,'lock-race rejection clears waiting status')
check(C.ns.State.raid.reservationsByGuid['Player-C'][1].difficultyID==14,'lock-race rejection preserves previous confirmed SR')
deliver(currentSnapshot)
check(C.ns.State.raid.locked,'old snapshot cannot unlock current published rules')
-- Locked relog and both-side restoration.
C=newClient('C',C.env.LeagueResDB)
C.ns:RequestSync()
flush()
check(C.ns.State.raid.reservationsByGuid['Player-C'][1].difficultyID==14 and C.ns.State.raid.locked,
 'player reload restores confirmed SR while locked')
A=newClient('A',A.env.LeagueResDB)
A.ns:RequestSync()
flush()
check(A.ns.State.raid.reservationsByGuid['Player-B'] and A.ns.State.raid.reservationsByGuid['Player-C'],
 'Loot Master reload retains the full raid list')
-- Explicit clear introduces a new generation; late packets cannot resurrect it.
A.ns:BroadcastFullSync()
local beforeClear=table.remove(queue,1)
A.ns:ClearAllReservations()
flush()
for id,c in pairs(clients) do check(next(c.ns.State.raid.reservationsByGuid)==nil,'explicit clear reaches client '..id) end
deliver(beforeClear)
check(next(B.ns.State.raid.reservationsByGuid)==nil,'snapshot from before clear cannot resurrect reservations')
A.ns:OnComm({t='RESERVE',v=3,guid='Player-B',sr={normal,0},seq=50,epoch=beforeClear.msg.epoch},'B-Realm')
flush()
check(next(A.ns.State.raid.reservationsByGuid)==nil,'delayed pre-clear submission cannot repopulate the list')
A.env.LeagueResDB.profile.settings.lockSR=false
A.ns:BroadcastSettings()
flush()
B.ns:SubmitMySR(normal,0)
flush()
check(A.ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==14,'fresh post-clear submission succeeds')
C=newClient('C',C.env.LeagueResDB)
C.ns:RequestSync()
flush()
check(C.ns.State.raid.reservationsByGuid['Player-B'] and not C.ns.State.raid.reservationsByGuid['Player-C'],
 'rejoining client receives new clear generation without restoring old SR')
-- Retry / sync recovers a dropped submission without losing other players.
C.ns:SubmitMySR(heroic,0)
queue={} -- simulate losing the outbound message
C.ns:RequestSync()
flush()
check(A.ns.State.raid.reservationsByGuid['Player-B'] and A.ns.State.raid.reservationsByGuid['Player-C']
 and not C.ns.Character.pendingSubmission,'Request Sync retries an unconfirmed submission')
-- A rejection for an older attempt must not cancel the newer pending submission.
C.ns:SubmitMySR(normal,0)
local obsoleteSeq=C.ns.Character.pendingSubmission.seq
queue={}
C.ns:SubmitMySR(heroic,0)
C.ns:OnComm({t='REJECT',v=3,lm='Player-A',term=A.ns.State.raid.authorityTerm,
 epoch=A.ns.State.raid.epoch,guid='Player-C',seq=obsoleteSeq},'A-Realm')
check(C.ns.Character.pendingSubmission and C.ns.Character.pendingSubmission.seq>obsoleteSeq,
 'late rejection cannot cancel a newer attempt')
flush()
check(C.ns.State.raid.reservationsByGuid['Player-C'][1].difficultyID==15,'newer attempt is confirmed after an old rejection')
local count=0 for _ in pairs(A.ns.State.raid.reservationsByGuid) do count=count+1 end
A.ns:OnComm({t='FULLSYNC',v=2,lm='Player-C',reservations={}},'C-Realm')
local newCount=0 for _ in pairs(A.ns.State.raid.reservationsByGuid) do newCount=newCount+1 end
check(newCount==count,'old addon protocol cannot overwrite new reservation state')
-- Role handoff is explicit; a delayed old owner snapshot cannot regain control.
A.ns:BroadcastFullSync()
local oldOwner=table.remove(queue,1)
A.ns:SetLootMaster(false)
flush()
B.ns:SetLootMaster(true)
flush()
check(A.ns.State.raid.lootMasterGuid=='Player-B' and C.ns.State.raid.lootMasterGuid=='Player-B',
 'Loot Master can hand the role to another group member')
deliver(oldOwner)
check(C.ns.State.raid.lootMasterGuid=='Player-B','released owner late snapshot cannot take back the role')
check(B.ns.State.raid.reservationsByGuid['Player-C']~=nil,'role handoff preserves reservations')
-- Pending submissions survive relog and restart their bounded retry timer.
C.ns:SubmitMySR(normal,heroic)
queue={}
C=newClient('C',C.env.LeagueResDB)
check(C.ns.Character.pendingSubmission~=nil,'unconfirmed submission is retained across reload')
C.ns:RequestSync()
check(C.ns.submissionTimer~=nil,'pending reload restarts the confirmation retry timer')
flush()
check(not C.ns.Character.pendingSubmission and B.ns.State.raid.reservationsByGuid['Player-C'][1].difficultyID==14,
 'reloaded pending submission reaches current Loot Master')
-- An owner's saved confirmed entry can repair an incomplete LM list while locked.
B.env.LeagueResDB.profile.settings.lockSR=true
B.ns:BroadcastSettings()
flush()
B.ns.State.raid.reservationsByGuid['Player-C']=nil
B.ns.State.raid.versionsByGuid['Player-C']=nil
C.ns:RequestSync()
flush()
check(B.ns.State.raid.reservationsByGuid['Player-C'] and B.ns.State.raid.locked,
 'confirmed owner state repairs missing LM entry without unlocking changes')
-- Without a designated LM, ordinary peer submissions still save and converge.
clients,queue,roster={},{},{'A','B','C'}
A,B,C=newClient('A'),newClient('B'),newClient('C')
B.ns:SubmitMySR(normal,heroic)
C.ns:SubmitMySR(heroic,normal)
flush()
check(A.ns.State.raid.reservationsByGuid['Player-B'] and A.ns.State.raid.reservationsByGuid['Player-C'],
 'peer mode saves submissions when no Loot Master is designated')
B.ns:SetLootMaster(true)
flush()
check(A.ns.State.raid.lootMasterGuid=='Player-B' and B.ns.State.raid.reservationsByGuid['Player-C'],
 'activating Loot Master retains peer-mode submissions')
-- Partial snapshots and reordered acknowledgements converge for a full 20-player raid.
clients,queue,roster={},{},{}
for i=1,20 do roster[i]=string.char(64+i) end
for _,id in ipairs(roster) do newClient(id) end
clients.A.ns:SetLootMaster(true)
flush()
for _,id in ipairs(roster) do clients[id].ns:SubmitMySR(normal,heroic) end
-- Reverse pending messages to model arrival order independent of submit order.
local reversed={} for i=#queue,1,-1 do reversed[#reversed+1]=queue[i] end queue=reversed
flush()
for id,c in pairs(clients) do
 local total=0 for _ in pairs(c.ns.State.raid.reservationsByGuid) do total=total+1 end
 check(total==20 and not c.ns.Character.pendingSubmission,'20-player raid converges on client '..id)
end
-- Version discovery uses installed metadata and works across reservation protocols.
clients,queue,roster={},{},{'A','B','C','D'}
A,B,C=newClient('A',nil,'1.2'),newClient('B',nil,'1.1'),newClient('C',nil,'1.2')
local D=newClient('D',nil,'1.2')
C.ns.PROTOCOL=2
local oldDComm=D.ns.OnComm
D.ns.OnComm=function(self,msg,sender)
 if msg.t=='VERSION_QUERY' or msg.t=='VERSION_REPLY' then return end
 return oldDComm(self,msg,sender)
end
check(A.ns.VERSION=='1.2' and B.ns.VERSION=='1.1','version check reads the installed TOC metadata')
A.ns.State.raid.reservationsByGuid['Player-B']={normal,0}
A.ns.State.raid.versionsByGuid['Player-B']=1
local printed={}
A.env.print=function(line) printed[#printed+1]=line end
A.ns.UI:OpenMain()
A.ns.UI:ShowPanel('lm')
check(A.ns.UI.versionCheckButton and not A.ns.UI.versionCheckButton.disabled,'group leader has an enabled Check Versions button')
A.ns.UI.versionCheckButton.callbacks.OnClick()
check(A.ns.UI.versionCheckButton.disabled,'check button disables while replies are collected')
flush()
local report=A.ns:BuildVersionReport()
check(report.matching==1 and #report.different==2 and #report.missing==1,'mixed versions, protocol mismatch and no response are separate')
check(report.different[1].name=='B-Realm' and report.different[1].version=='1.1','different-version list includes exact reported version')
check(report.different[2].name=='C-Realm' and report.different[2].protocol==2,'version reply works despite a different reservation protocol')
check(report.missing[1]=='D-Realm','old build with no version handler is listed as no response')
A.ns.versionCheck.timer.callback()
check(A.ns.versionCheck.finished and not A.ns.UI.versionCheckButton.disabled,'timeout prints results and re-enables button')
local foundVersion,foundUnknown=false,false
for _,line in ipairs(printed) do
 if line:find('B-Realm',1,true) and line:find('1.1',1,true) then foundVersion=true end
 if line:find('No version response: D-Realm',1,true) then foundUnknown=true end
end
check(foundVersion and foundUnknown,'local chat output lists mismatched players and nonresponders')
check(A.ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==14 and A.ns.State.raid.versionsByGuid['Player-B']==1,
 'version probing does not mutate reservations')
-- Responses are correlated to the specific check and verified by live sender GUID.
A.ns:CheckVersions()
local prior=A.ns.versionCheck
A.ns:CheckVersions()
local active=A.ns.versionCheck
check(prior.timer.cancelled and prior.request~=active.request,'starting a fresh check cancels the older timer and changes request ID')
A.ns:OnComm({t='VERSION_REPLY',v=2,request=prior.request,version='0.1',protocol=2},'B-Realm')
check(active.replies['Player-B']==nil,'reply to an earlier check is ignored')
A.ns:OnComm({t='VERSION_REPLY',v=2,request=active.request,version='0.1',protocol=2},'Outside-Realm')
check(active.replies['Player-Outside']==nil,'non-group sender cannot enter the version report')
A.ns:OnComm({t='VERSION_REPLY',v=3,request=active.request,version='|cffff0000fake',protocol=3},'B-Realm')
check(active.replies['Player-B']==nil,'formatted or malformed version response is ignored')
flush()
roster={'A','C','D'}
report=A.ns:BuildVersionReport()
check(#report.different==1 and report.different[1].name=='C-Realm','departed player is excluded from the final report')
local E=newClient('E',nil,'1.3')
roster[#roster+1]='E'
report=A.ns:BuildVersionReport()
check(#report.missing==2 and report.missing[2]=='E-Realm','new arrival without a response is reported honestly')
A.ns:FinishVersionCheck(active.request)
local oldReply=active.replies['Player-B']
A.ns:OnComm({t='VERSION_REPLY',v=3,request=active.request,version='9.9',protocol=3},'E-Realm')
check(active.replies['Player-E']==nil,'reply after the final report is ignored')
roster={'A','B'}
B.ns.VERSION='1.2'
A.ns:CheckVersions()
flush()
report=A.ns:BuildVersionReport()
check(report.matching==2 and #report.different==0 and #report.missing==0,'matching versions produce a clean report')
A.ns.versionCheck.timer.callback()
check(printed[#printed]:find('Everyone in the current group',1,true),'all-matching result prints an explicit confirmation')
local beforeQuery=#queue
B.ns:CheckVersions()
check(#queue==beforeQuery,'ordinary member cannot start the leader/LM check')
A.ns.UI:ShowPanel('my')
check(A.ns.UI.versionCheckButton==nil,'tab change discards released version-check button reference')
-- A player may carry a reset counter from a different/older raid session.
clients,queue,roster={},{},{'A','B','C'}
A,B,C=newClient('A'),newClient('B'),newClient('C')
A.ns:SetLootMaster(true)
flush()
C.ns:SubmitMySR(heroic,0)
flush()
B.ns.State.raid.epoch=clock*1000+100
B.ns.State.raid.settingsRevision=100000
B.ns:SubmitMySR(normal,heroic)
flush()
check(A.ns.State.raid.reservationsByGuid['Player-C']~=nil,'Loot Master retains received submissions during counter mismatch')
B.ns:RequestSync()
flush()
check(B.ns.State.raid.epoch==A.ns.State.raid.epoch,'fresh requested master snapshot repairs an ahead-of-master reset counter')
check(B.ns.State.raid.reservationsByGuid['Player-C']~=nil,'affected player receives the master raid list after counter recovery')
check(B.ns.State.raid.settingsRevision==A.ns.State.raid.settingsRevision,
 'counter recovery also reconciles a stale ahead-of-master settings revision')
check(not B.ns.Character.pendingSubmission and A.ns.State.raid.reservationsByGuid['Player-B'],
 'pending submission is retried and confirmed after counter recovery')

-- Recovery is scoped to the latest request and its intended recipient.
local function masterSnapshot(request, recipient, epoch)
 return {from='A',msg={t='FULLSYNC',v=3,lm='Player-A',term=A.ns.State.raid.authorityTerm,
  epoch=epoch,settingsRevision=A.ns.State.raid.settingsRevision,settings={lockSR=false},
  reservations=copy(A.ns.State.raid.reservationsByGuid),versions=copy(A.ns.State.raid.versionsByGuid),
  request=request,requestGuid=recipient}}
end
B.ns.State.raid.epoch=100
B.ns:RequestSync()
local superseded=B.ns.syncRequest.id
queue={}
B.ns:RequestSync()
local latest=B.ns.syncRequest.id
queue={}
deliver(masterSnapshot(nil,nil,0))
check(B.ns.State.raid.epoch==100,'unsolicited older snapshot cannot lower a reset counter')
deliver(masterSnapshot(superseded,'Player-B',0))
check(B.ns.State.raid.epoch==100,'reply to a superseded sync request cannot lower a reset counter')
deliver(masterSnapshot(latest,'Player-C',0))
check(B.ns.State.raid.epoch==100,'reply intended for another player cannot authorize counter recovery')
local recovery=masterSnapshot(latest,'Player-B',0)
deliver(recovery)
flush()
check(B.ns.State.raid.epoch==0,'current recipient-specific reply permits recovery')
B.ns:AdoptEpoch(200)
deliver(recovery)
check(B.ns.State.raid.epoch==200,'replaying a consumed recovery reply cannot undo a later clear')
B.ns:RequestSync()
local beforeNewClear=masterSnapshot(B.ns.syncRequest.id,'Player-B',0)
queue={}
B.ns:AdoptEpoch(300)
deliver(beforeNewClear)
check(B.ns.State.raid.epoch==300,'clear received after a sync request invalidates its lower-counter recovery')
-- A missed initial owner snapshot is repaired without addon whispers.
clients,queue,roster={},{},{'A','B','C'}
A,B,C=newClient('A'),newClient('B'),newClient('C')
A.ns:SetLootMaster(true)
queue={}
B.ns:RequestSync()
local hello=table.remove(queue,1)
deliver(hello)
check(#queue==1 and not queue[1].target and queue[1].msg.t=='FULLSYNC',
 'sync response uses group transport instead of relying on whispers')
flush()
check(B.ns:ActiveLootMaster()=='Player-A' and C.ns:ActiveLootMaster()=='Player-A',
 'group sync response repairs missing owner knowledge on all recipients')
B.ns:SubmitMySR(normal,heroic)
deliver(table.remove(queue,1))
queue={} -- master accepted the submission, but its receipt was dropped
check(B.ns.Character.pendingSubmission~=nil,'dropped receipt leaves the player pending')
B.ns.submissionTimer.callback()
local sentHello=false
for _,packet in ipairs(queue) do if packet.msg.t=='HELLO' then sentHello=true end end
check(sentHello,'automatic confirmation retry also requests current master state')
flush()
check(not B.ns.Character.pendingSubmission and B.ns.State.raid.reservationsByGuid['Player-B'],
 'automatic sync retry confirms a submission after its receipt was dropped')
-- No reply must still stop after the existing bounded retry budget.
B.ns:SubmitMySR(heroic,0)
queue={}
for i=1,3 do
 local timer=B.ns.submissionTimer
 check(timer~=nil,'unanswered submission schedules retry '..i)
 timer.callback()
 queue={}
end
check(not B.ns.submissionTimer and B.ns.Character.pendingSubmission,
 'unanswered sync and submission retries stop after three attempts without discarding pending selections')
-- Syncing to an older counter does not bypass a locked master.
A.env.LeagueResDB.profile.settings.lockSR=true
A.ns:BroadcastSettings()
queue={}
B.ns.State.raid.epoch=500
B.ns.Character.pendingSubmission.epoch=500
B.ns:RequestSync()
flush()
check(not B.ns.Character.pendingSubmission and B.ns.State.raid.locked,
 'counter recovery respects locked rules and rejects the pending edit')
check(B.ns.State.raid.reservationsByGuid['Player-B'][1].difficultyID==14,
 'locked recovery preserves the master confirmed selection')

print(tests..' multi-client checks passed.')
