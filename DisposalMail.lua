-- v0.68r: Disposal mail requires physical-GUID proof or explicit per-copy recovery.
-- No routing decisions, automatic mailing, vendor actions or item-link-based
-- guesses about duplicate physical copies occur in this module.
local function DName(name)
    if not name then return nil end
    local s=tostring(name)
    if Ambiguate then
        local ok,value=pcall(Ambiguate,s,'short')
        if ok and value and value~='' then s=value end
    end
    s=s:match('^([^%-]+)') or s
    s=s:match('^%s*(.-)%s*$')
    return s~='' and s or nil
end
local function DKey(name)
    local s=DName(name)
    return s and string.lower(s) or nil
end
local function DNow()
    return (GetServerTime and GetServerTime()) or (time and time()) or 0
end
local function DTable()
    InitializeDatabase()
    local db=WarboundGearRouterDB
    if type(db.storageCleanupDisposalMail)~='table' then
        db.storageCleanupDisposalMail={nextId=0,batches={}}
    end
    local t=db.storageCleanupDisposalMail
    if type(t.batches)~='table' then t.batches={} end
    if type(t.pendingSends)~='table' then t.pendingSends={} end
    return t
end
local function DPending(batch)
    local n=0
    for _,item in ipairs(batch.items or {}) do
        if item.state~='RECEIVED' then n=n+1 end
    end
    return n
end

-- Record ONLY confirmed actual SendMail results. It is a TRANSFER, never a
-- completed disposal. Original source GUIDs identify physical copies at
-- preparation time; newly received items will need their own verified GUID.
function WGRDisposalMailRecordSend(entries,recipient,sender)
    if type(entries)~='table' or #entries==0 then return 0 end
    recipient=DName(recipient);sender=DName(sender)
    if not recipient or not sender then return 0 end
    local stored,items={},{}
    for _,entry in ipairs(entries) do
        if type(entry)=='table' and type(entry.guid)=='string' and
            type(entry.itemLink)=='string' and not stored[entry.guid] then
            stored[entry.guid]=true
            items[#items+1]={sourceGUID=entry.guid,itemLink=entry.itemLink,
                state='IN_TRANSIT'}
        end
    end
    if #items==0 then return 0 end
    local db=DTable();db.nextId=(tonumber(db.nextId) or 0)+1
    db.batches[#db.batches+1]={id=db.nextId,recipient=recipient,sender=sender,
        sentAt=DNow(),subject='WBGR Disposal',items=items,observed=false}
    if WGRRefreshTodoPage then WGRRefreshTodoPage() end
    return #items
end

-- v0.68q: a successful, exact SendMail may fire before outgoing GUIDs
-- disappear from WoW's Bag API. This durable *confirmation queue* is NOT the
-- IN TRANSIT ledger or a retrieval To Do. Only a later positive GUID-departure
-- observation may retire the original mark and create the recipient ledger.
-- Keeping a bounded retry schedule AND the pending record means a slow Bag
-- update or a reload does not silently lose the attempted reconciliation.
local DRetryDelays={0.20,0.65,1.50,3.00,6.00}
local DRetrySerial=0

local function DPendingSenderCount(sender)
    local n=0
    for _,pending in ipairs(DTable().pendingSends) do
        if DKey(pending.sender)==DKey(sender) then
            n=n+#(pending.entries or {})
        end
    end
    return n
end

function WGRDisposalMailTryConfirmPendingSends()
    -- BAG_UPDATE_DELAYED is frequent. With no pending send this is just a
    -- table check; do not initialize the DB or scan any bag slots.
    local raw=WarboundGearRouterDB and WarboundGearRouterDB.storageCleanupDisposalMail
    if type(raw)~='table' or type(raw.pendingSends)~='table' or
        #raw.pendingSends==0 then return 0,0 end
    local tableState=DTable()
    local sender=DKey(UnitName and UnitName('player'))
    if not sender then return 0,0 end
    local completed=0
    for i=#tableState.pendingSends,1,-1 do
        local pending=tableState.pendingSends[i]
        if DKey(pending.sender)==sender and type(pending.entries)=='table' then
            local n,confirmed
            if WGRStorageCleanupCompleteDisposalMail then
                n,confirmed=WGRStorageCleanupCompleteDisposalMail(
                    pending.entries,pending.recipient)
            end
            if type(n)=='number' and n>0 and type(confirmed)=='table' then
                local done={}
                for _,entry in ipairs(confirmed) do
                    done[entry.guid]=true
                end
                local remaining={}
                for _,entry in ipairs(pending.entries) do
                    if not done[entry.guid] then remaining[#remaining+1]=entry end
                end
                pending.entries=remaining
                completed=completed+#confirmed
            end
            if #pending.entries==0 then
                table.remove(tableState.pendingSends,i)
            end
        end
    end
    return completed,DPendingSenderCount(sender)
end

local function DScheduleRetries()
    -- No perpetual background scans: only five short deferred checks per
    -- confirmed send. Later sender login/mailbox/BAG_UPDATE can also retry.
    if not (C_Timer and C_Timer.After) then return end
    DRetrySerial=DRetrySerial+1
    local serial=DRetrySerial
    for _,delay in ipairs(DRetryDelays) do
        C_Timer.After(delay,function()
            if serial~=DRetrySerial then return end
            local confirmed,pending=WGRDisposalMailTryConfirmPendingSends()
            -- Routine successful reconciliation is reflected in To Do/Recent Activity; keep chat quiet.
            if pending==0 then DRetrySerial=DRetrySerial+1 end
        end)
    end
end

function WGRDisposalMailQueueConfirmedSend(entries,recipient,sender)
    recipient=DName(recipient);sender=DName(sender)
    if not recipient or not sender or type(entries)~='table' or #entries==0 or
        not WGRStorageCleanupValidateOutgoingDisposalMailEntry then
        return 0,0,false
    end
    local verified,seen={},{}
    for _,entry in ipairs(entries) do
        if type(entry)=='table' and not seen[entry.guid] and
            WGRStorageCleanupValidateOutgoingDisposalMailEntry(entry,sender) then
            verified[#verified+1]={guid=entry.guid,itemLink=entry.itemLink}
            seen[entry.guid]=true
        else
            -- An exact SendMail draft is necessary but not sufficient. If
            -- saved GUID marks changed, never queue an incomplete batch.
            return 0,0,false
        end
    end
    local state=DTable()
    for _,pending in ipairs(state.pendingSends) do
        for _,entry in ipairs(pending.entries or {}) do
            if seen[entry.guid] then return 0,0,false end
        end
    end
    state.nextId=(tonumber(state.nextId) or 0)+1
    state.pendingSends[#state.pendingSends+1]={id=state.nextId,
        entries=verified,recipient=recipient,sender=sender,sentAt=DNow()}
    local confirmed,remaining=WGRDisposalMailTryConfirmPendingSends()
    if remaining>0 then DScheduleRetries() end
    return confirmed,remaining,true
end

-- Retry only when the original sending character can be observed. Do not
-- reconstruct old v0.68o/p mail sends from link-only audit history.
function WGRDisposalMailResumeSenderPending()
    local pending=DPendingSenderCount(UnitName and UnitName('player'))
    if pending==0 then return end
    local confirmed,remaining=WGRDisposalMailTryConfirmPendingSends()
    -- Routine successful reconciliation is reflected in To Do/Recent Activity; keep chat quiet.
    if remaining>0 then
        DScheduleRetries()
        print('|cffffaa00WBGR:|r '..remaining..' confirmed DISPOSE mail send copy/copies are still awaiting physical Bag GUID verification. No recipient retrieval has been assumed.')
    end
end

function WGRDisposalMailPendingList()
    local groups={}
    for _,batch in ipairs(DTable().batches) do
        local n=DPending(batch)
        if n>0 then
            local recipient=batch.returnedTo or batch.recipient
            local key=DKey(recipient)
            if key then
                local g=groups[key]
                if not g then
                    g={name=recipient,count=0,oldest=batch.sentAt,
                        returned=not not batch.returnedTo,tokens={}}
                    groups[key]=g
                end
                g.count=g.count+n
                g.tokens[#g.tokens+1]=tostring(batch.id)..':'..tostring(n)
                g.oldest=math.min(tonumber(g.oldest) or DNow(),
                    tonumber(batch.sentAt) or DNow())
                if batch.returnedTo then g.returned=true end
            end
        end
    end
    local list={}
    for _,group in pairs(groups) do
        table.sort(group.tokens)
        group.token=table.concat(group.tokens,',')
        list[#list+1]=group
    end
    table.sort(list,function(a,b) return a.oldest<b.oldest end)
    return list
end

local DSession=nil
local DPendingReturn=nil
local function DBagCopies()
    local list={}
    if not (C_Container and C_Container.GetContainerNumSlots and
        C_Container.GetContainerItemLink and WGRStorageCleanupGetPhysicalCopyGUID) then
        return list
    end
    for bag=0,4 do
        for slot=1,(C_Container.GetContainerNumSlots(bag) or 0) do
            local link=C_Container.GetContainerItemLink(bag,slot)
            if link then
                local guid=WGRStorageCleanupGetPhysicalCopyGUID(bag,slot,link)
                if guid then
                    list[guid]={bag=bag,slot=slot,link=link,guid=guid}
                end
            end
        end
    end
    return list
end
function WGRDisposalMailStartInboxSession()
    local owner=DKey(UnitName and UnitName('player'))
    -- Repeated MAIL_SHOW signals for a still-open session must NOT treat
    -- freshly retrieved physical copies as pre-existing Bags inventory.
    if DSession and DSession.owner==owner then return end
    DSession={owner=owner,originalBag=DBagCopies(),claimed={},
        observedMessages={},startedAt=DNow()}
end
function WGRDisposalMailEndInboxSession() DSession=nil; DPendingReturn=nil end

local function DInboxMessages()
    local messages={}
    if not (GetInboxNumItems and GetInboxHeaderInfo and GetInboxItemLink) then
        return messages
    end
    local n=select(1,GetInboxNumItems()) or 0
    for i=1,n do
        local _,_,sender,subject=GetInboxHeaderInfo(i)
        if type(subject)=='string' and subject:find('WBGR Disposal',1,true) then
            local links={};local counts={}
            for j=1,(ATTACHMENTS_MAX_RECEIVE or 16) do
                local link=GetInboxItemLink(i,j)
                if link then
                    links[#links+1]=link;counts[link]=(counts[link] or 0)+1
                end
            end
            messages[#messages+1]={sender=DKey(sender),subject=subject,
                counts=counts,number=#links}
        end
    end
    return messages
end
local function DMatch(batch,message,isReturn)
    if isReturn then
        return message.subject~='WBGR Disposal' and
            message.subject:find('WBGR Disposal',1,true) and
            (not message.sender or message.sender==DKey(batch.recipient))
    end
    return message.subject=='WBGR Disposal' and
        message.sender==DKey(batch.sender)
end

-- The inbox does not expose source GUIDs, so recognize a matching sender,
-- WBGR Disposal subject and physical item-link multiset. Never claim an item
-- before the message was observed with attachments in THIS mailbox session.
-- Only newly observed bag GUIDs may be adopted; if proof is unavailable the
-- To Do deliberately stays pending for manual reconciliation.
function WGRDisposalMailReconcileInbox()
    if not DSession or DSession.owner~=DKey(UnitName and UnitName('player')) then
        return 0
    end
    local messages=DInboxMessages()
    local bags=DBagCopies()
    local completed=0
    for _,batch in ipairs(DTable().batches) do
        local owner=DKey(batch.returnedTo or batch.recipient)
        if owner==DSession.owner and DPending(batch)>0 then
            local isReturn=not not batch.returnedTo
            local visible={}
            for _,message in ipairs(messages) do
                if DMatch(batch,message,isReturn) then
                    for link,n in pairs(message.counts) do
                        visible[link]=(visible[link] or 0)+n
                    end
                end
            end
            -- Recognize matching attachments ONLY if all observed copies can
            -- be accounted for in the planned transfer (no unrelated mail).
            local outstanding={}
            for _,item in ipairs(batch.items or {}) do
                if item.state~='RECEIVED' then
                    outstanding[item.itemLink]=(outstanding[item.itemLink] or 0)+1
                end
            end
            local matches=true
            for link,n in pairs(visible) do
                if n>(outstanding[link] or 0) then matches=false end
            end
            if matches then
                for link,n in pairs(visible) do
                    if n>0 then
                        batch.observed=true
                        batch.observedLinks=batch.observedLinks or {}
                        batch.observedLinks[link]=math.max(batch.observedLinks[link] or 0,n)
                    end
                end
            end
            if batch.observed and batch.observedLinks then
                local allowed={}
                for link,original in pairs(batch.observedLinks) do
                    allowed[link]=math.max(0,original-(visible[link] or 0))
                end
                for _,item in ipairs(batch.items or {}) do
                    local link=item.itemLink
                    if item.state~='RECEIVED' and (allowed[link] or 0)>0 then
                        for guid,copy in pairs(bags) do
                            if copy.link==link and not DSession.originalBag[guid] and
                                not DSession.claimed[guid] then
                                local ok=(WGRStorageCleanupAdoptReceivedDisposalCopy and
                                    WGRStorageCleanupAdoptReceivedDisposalCopy(copy.bag,copy.slot,link,
                                        isReturn and 'RETURNED_DISPOSAL_MAIL' or 'RECEIVED_DISPOSAL_MAIL'))
                                if ok then
                                    DSession.claimed[guid]=true
                                    item.receivedGUID=guid
                                    item.state='RECEIVED'
                                    item.receivedAt=DNow()
                                    item.receivedBy=UnitName and UnitName('player')
                                    allowed[link]=allowed[link]-1
                                    completed=completed+1
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if completed>0 then
        if WGRRefreshTodoPage then WGRRefreshTodoPage() end
        if WGRMailRefreshCurrentTodoSnapshot then
            WGRMailRefreshCurrentTodoSnapshot(true,true) end
    end
    return completed
end

-- A returned message can be recognized without deleting or finalizing its
-- original tracked copies. If return metadata is ambiguous, leave its task
-- with the original recipient rather than pretending the mail was received.
function WGRDisposalMailObserveReturns()
    if not DSession then return end
    local messages=DInboxMessages()
    for _,batch in ipairs(DTable().batches) do
        if DPending(batch)>0 and not batch.returnedTo and
            DKey(batch.sender)==DSession.owner then
            for _,message in ipairs(messages) do
                if DMatch(batch,message,true) and message.number>0 then
                    batch.returnedTo=batch.sender
                    batch.observed=false
                    batch.observedLinks=nil
                    break
                end
            end
        end
    end
end

-- Track an explicit Blizzard Return action while the original message is
-- still visible. A normal inbox removal is NEVER assumed to be a return.
function WGRDisposalMailPrimeReturn(mailIndex)
    if not DSession or not GetInboxHeaderInfo then return false end
    local _,_,sender,subject=GetInboxHeaderInfo(mailIndex)
    if subject~='WBGR Disposal' then return false end
    local senderKey=DKey(sender)
    for _,batch in ipairs(DTable().batches) do
        if not batch.returnedTo and DPending(batch)>0 and
            DSession.owner==DKey(batch.recipient) and
            senderKey==DKey(batch.sender) then
            local needed={}
            for _,item in ipairs(batch.items) do
                if item.state~='RECEIVED' then
                    needed[item.itemLink]=(needed[item.itemLink] or 0)+1
                end
            end
            local actual={}
            for j=1,(ATTACHMENTS_MAX_RECEIVE or 16) do
                local link=GetInboxItemLink and GetInboxItemLink(mailIndex,j)
                if link then actual[link]=(actual[link] or 0)+1 end
            end
            local exact=true
            for link,n in pairs(needed) do
                if actual[link]~=n then exact=false end
            end
            for link,n in pairs(actual) do
                if needed[link]~=n then exact=false end
            end
            if exact then
                DPendingReturn={batchId=batch.id,sender=senderKey,needed=needed}
                return true
            end
        end
    end
    return false
end
function WGRDisposalMailFinalizeReturn()
    if not DPendingReturn then return false end
    local matched={}
    for _,message in ipairs(DInboxMessages()) do
        if message.subject=='WBGR Disposal' and
            message.sender==DPendingReturn.sender then
            local exact=true
            for link,n in pairs(DPendingReturn.needed) do
                if message.counts[link]~=n then exact=false end
            end
            for link,n in pairs(message.counts) do
                if DPendingReturn.needed[link]~=n then exact=false end
            end
            if exact then return false end
        end
    end
    for _,batch in ipairs(DTable().batches) do
        if batch.id==DPendingReturn.batchId and DPending(batch)>0 then
            batch.returnedTo=batch.sender
            batch.observed=false
            batch.observedLinks=nil
        end
    end
    DPendingReturn=nil
    if WGRRefreshTodoPage then WGRRefreshTodoPage() end
    return true
end

function WGRDisposalMailOnInboxChanged()
    if not DSession then return end
    WGRDisposalMailObserveReturns()
    WGRDisposalMailReconcileInbox()
end

-- v0.68r: Diagnostic and USER-ASSERTED recovery for a physical copy whose
-- original mail-to-Bags evidence was lost (for example after mailbox reopen).
-- Never infer a copy solely from an item link. The user specifies an exact
-- live bag/slot and confirms its GUID in the Blizzard popup; no automatic
-- disposal or routing override is allowed for upgrades/KEEP or unknown GUIDs.
local function DPhysicalRecoveryCandidate(bag,slot,batchId,expectedGUID)
    if not (WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings().enabled) then
        return nil,'Enable Storage Cleanup first.'
    end
    bag=tonumber(bag);slot=tonumber(slot)
    if not bag or bag<0 or bag>4 or not slot or slot<1 or slot%1~=0 then
        return nil,'Specify an exact Bags location (bag 0-4, slot).' end
    if not (C_Container and C_Container.GetContainerItemLink and
        WGRStorageCleanupGetPhysicalCopyGUID) then return nil,'Live Bag APIs unavailable.' end
    local link=C_Container.GetContainerItemLink(bag,slot)
    local guid=link and WGRStorageCleanupGetPhysicalCopyGUID(bag,slot,link)
    if not guid or not link or (expectedGUID and expectedGUID~=guid) then
        return nil,'Physical item or its GUID changed. Nothing recovered.' end
    local marks=WarboundGearRouterDB and WarboundGearRouterDB.storageCleanupDisposalMarks
    if marks and marks[guid] then
        return nil,'This physical copy already has a KEEP/DISPOSE decision; no recovery.' end
    local owner=DKey(UnitName and UnitName('player'))
    local matches={}
    for _,batch in ipairs(DTable().batches) do
        if owner==DKey(batch.returnedTo or batch.recipient) and
            (not batchId or batch.id==tonumber(batchId)) then
            for index,item in ipairs(batch.items or {}) do
                if item.state~='RECEIVED' and item.itemLink==link then
                    matches[#matches+1]={batch=batch,index=index}
                    break -- just one candidate per batch even for identical links
                end
            end
        end
    end
    if #matches~=1 then
        return nil,#matches==0 and 'No matching pending DISPOSE mail copy for this character and item.'
            or 'Several pending batches match; specify a batch ID.'
    end
    for _,batch in ipairs(DTable().batches) do
        for _,item in ipairs(batch.items or {}) do
            if item.receivedGUID==guid then return nil,'This physical GUID was already claimed.' end
        end
    end
    local result=matches[1]
    result.bag=bag;result.slot=slot;result.link=link;result.guid=guid
    return result
end

function WGRDisposalMailReviewCurrentCopies()
    local owner=DKey(UnitName and UnitName('player'))
    if not owner then return end
    local pending={};local total=0
    for _,batch in ipairs(DTable().batches) do
        if owner==DKey(batch.returnedTo or batch.recipient) then
            for _,item in ipairs(batch.items or {}) do
                if item.state~='RECEIVED' then
                    pending[item.itemLink]=pending[item.itemLink] or {}
                    pending[item.itemLink][#pending[item.itemLink]+1]=batch.id
                    total=total+1
                end
            end
        end
    end
    print('|cffffff00WBGR DISPOSE mail recovery:|r '..total..' pending physical copies.')
    if total==0 then return end
    print('Only select a copy you personally verified came from this DISPOSE mail. Do not choose another identical KEEP/holder item.')
    local found=0
    for guid,copy in pairs(DBagCopies()) do
        if pending[copy.link] then
            found=found+1
            local ids={};local used={}
            for _,id in ipairs(pending[copy.link]) do
                if not used[id] then ids[#ids+1]=id;used[id]=true end
            end
            table.sort(ids)
            print('Bag '..copy.bag..' slot '..copy.slot..': '..copy.link..
                ' (candidate batch '..table.concat(ids,',')..'; exact physical GUID available)')
        end
    end
    if found==0 then print('No matching physical items currently in Bags.') end
    print('After visually checking the exact copy, use /wbgr recoverdispose <bag> <slot> [batchID]. Confirmation is required.')
end

function WGRDisposalMailRequestManualRecovery(bag,slot,batchId)
    local candidate,reason=DPhysicalRecoveryCandidate(bag,slot,batchId)
    if not candidate then return false,reason end
    if not (StaticPopupDialogs and StaticPopup_Show) then
        return false,'Confirmation UI unavailable; no recovery performed.' end
    -- Register lazily: the slash command is usable before opening WBGR's
    -- main window and must never silently act without confirmation.
    if not StaticPopupDialogs['WGR_CONFIRM_DISPOSAL_MAIL_RECOVERY'] then
        StaticPopupDialogs['WGR_CONFIRM_DISPOSAL_MAIL_RECOVERY']={
            text='Manually confirm DISPOSE mail receipt for %s?\n\nOnly confirm if you personally verified THIS exact physical item came from the pending disposal mail. Identical existing gear must NOT be claimed. This creates a DISPOSE mark and closes one mail-ledger copy, but does not sell or disenchant anything.',
            button1='Confirm Copy',button2='Cancel',
            OnAccept=function(self,data)
                local ok,message=WGRDisposalMailCommitManualRecovery(data)
                print((ok and '|cff33ff99WBGR:|r ' or '|cffffaa00WBGR:|r ')..tostring(message))
            end,
            timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        }
    end
    local id=candidate.batch.id
    local data={bag=candidate.bag,slot=candidate.slot,batchId=id,
        guid=candidate.guid,link=candidate.link}
    StaticPopup_Show('WGR_CONFIRM_DISPOSAL_MAIL_RECOVERY',
        candidate.link..' (bag '..candidate.bag..', slot '..candidate.slot..
        ', batch '..id..')',nil,data)
    return true,'Confirm the exact physical copy in the Blizzard dialog.'
end

function WGRDisposalMailCommitManualRecovery(data)
    if type(data)~='table' then return false,'No physical copy selected.' end
    local candidate,reason=DPhysicalRecoveryCandidate(
        data.bag,data.slot,data.batchId,data.guid)
    if not candidate or candidate.link~=data.link then
        return false,reason or 'Item link changed.' end
    if not WGRStorageCleanupAdoptReceivedDisposalCopy then
        return false,'DISPOSE adoption unavailable.' end
    local ok,why=WGRStorageCleanupAdoptReceivedDisposalCopy(
        candidate.bag,candidate.slot,candidate.link,'MANUAL_DISPOSAL_MAIL_RECOVERY')
    if not ok then return false,why or 'Physical copy not eligible for DISPOSE.' end
    local item=candidate.batch.items[candidate.index]
    item.state='RECEIVED';item.receivedGUID=candidate.guid
    item.receivedBy=UnitName and UnitName('player')
    item.receivedAt=DNow();item.manualRecovery=true
    if DSession then DSession.claimed[candidate.guid]=true end
    if WGRMailRefreshCurrentTodoSnapshot then
        WGRMailRefreshCurrentTodoSnapshot(true,true)
    end
    if WGRRefreshTodoPage then WGRRefreshTodoPage() end
    return true,'Physical copy manually reconciled (not sold or disenchanted).'
end

function WGRDisposalMailDiagnoseCurrent()
    local owner=DKey(UnitName and UnitName('player'))
    local session=DSession and DSession.owner==owner
    local bags=DBagCopies()
    local messages=session and DInboxMessages() or {}
    local found=0
    for _,batch in ipairs(DTable().batches) do
        if DKey(batch.returnedTo or batch.recipient)==owner and DPending(batch)>0 then
            found=found+1
            local visible={};local matched=0
            for _,message in ipairs(messages) do
                if DMatch(batch,message,not not batch.returnedTo) then
                    matched=matched+1
                    for link,n in pairs(message.counts) do
                        visible[link]=(visible[link] or 0)+n
                    end
                end
            end
            local matching,new,baseline=0,0,0
            for guid,copy in pairs(bags) do
                for _,item in ipairs(batch.items) do
                    if item.state~='RECEIVED' and item.itemLink==copy.link then
                        matching=matching+1
                        if session and DSession.originalBag[guid] then
                            baseline=baseline+1
                        elseif session then new=new+1 end
                        break
                    end
                end
            end
            local orig=0;local left=0
            for _,n in pairs(batch.observedLinks or {}) do orig=orig+n end
            for _,n in pairs(visible) do left=left+n end
            print('DISPOSE batch '..batch.id..': pending='..DPending(batch)..
                ' observed='..tostring(batch.observed)..' original='..orig..
                ' visible='..left..' matchedMail='..matched..
                ' bagMatches='..matching..' newGUIDs='..new..
                ' baselineGUIDs='..baseline..' session='..tostring(session))
        end
    end
    if found==0 then print('WBGR: No pending DISPOSE mail for current character.') end
    if not session then print('WBGR: No active mailbox baseline; automatic receipt proof unavailable.') end
end
