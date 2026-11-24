-- Storage Cleanup is an opt-in, non-destructive review layer over WBGR routing.
-- Never make a new routing decision from this file; routing recommendations
-- and the existing eligibility helpers decide which items we may examine.

-- The master setting is OFF for existing installations and new users.
-- Legacy retain/futureScope/retention/minimumLevel values from the prototype
-- intentionally do not enable Cleanup or change the now fixed BEST policy.
-- Automatic holder-bound filtering is a separate, future opt-in feature.
local function WGRStorageCleanupDefaults()
    InitializeDatabase()
    local db = WarboundGearRouterDB
    if type(db.storageCleanup) ~= "table" then db.storageCleanup = {} end
    local settings = db.storageCleanup
    if settings.enabled ~= true then settings.enabled = false end
    settings.automaticFilter = false -- not implemented; never activate by migration
    -- v0.71k: disposal-method suggestions were presentation-only and are now
    -- obsolete. Cleanup routes verified surplus; the user chooses how to dispose
    -- of it manually. Remove the old saved preferences during normal migration.
    settings.warboundAction = nil
    settings.boeAction = nil
    settings.warboundRecipient = settings.warboundRecipient or "CURRENT"
    settings.boeRecipient = settings.boeRecipient or "CURRENT"
    -- Remove obsolete prototype settings; the master toggle now means BEST.
    settings.retain = nil
    settings.futureScope = nil
    settings.retention = nil
    settings.minimumLevel = nil
    return settings
end

function WGRStorageCleanupGetSettings()
    return WGRStorageCleanupDefaults()
end


-- v0.68j: Deliberate, per-physical-copy disposal overrides. GUIDs are the
-- only persistent identity: identical item links MUST NOT share a status.
-- Failure to resolve a GUID is a refusal to mark, never a slot-only guess.
local function WGRStorageCleanupCurrentCopy(bagID,slotID,expectedLink)
    if type(bagID)~='number' or type(slotID)~='number' or
        not (C_Container and C_Container.GetContainerItemLink) then
        return nil,nil,'Unknown physical slot'
    end
    local link=C_Container.GetContainerItemLink(bagID,slotID)
    if not link or (expectedLink and expectedLink~=link) then
        return nil,nil,'Item no longer occupies that slot'
    end
    if not (ItemLocation and ItemLocation.CreateFromBagAndSlot and
        C_Item and C_Item.GetItemGUID) then
        return nil,nil,'WoW item GUID API unavailable'
    end
    local ok,location=pcall(ItemLocation.CreateFromBagAndSlot,ItemLocation,bagID,slotID)
    if not ok or not location then return nil,nil,'Item location unavailable' end
    local success,guid=pcall(C_Item.GetItemGUID,location)
    if not success or not guid or guid=='' then
        return nil,nil,'Physical-copy GUID unavailable'
    end
    return tostring(guid),link,nil
end

-- Verify a physical copy before/after a multi-frame surplus evaluation.
-- This read never mutates the mark table and never guesses a duplicate slot.
function WGRStorageCleanupGetPhysicalCopyGUID(bagID,slotID,expectedLink)
    local guid=WGRStorageCleanupCurrentCopy(bagID,slotID,expectedLink)
    return guid
end

-- v0.68y: Frozen movement verification must observe PHYSICAL slots, not the
-- Cleanup eligibility scanner.  Immediately after a bank transfer WoW may
-- expose the item link/GUID before tooltip/binding data is ready; filtering
-- through IsTransferableContainerItem can therefore hide a move that really
-- completed.  This raw snapshot is deliberately read-only and is used only
-- to prove exact GUID relocation / aggregate physical counts.
function WGRStorageCleanupSnapshotAccessiblePhysical()
    local result={slots={},positions={},counts={},bagCounts={},byGUID={},guidCollisions={},pbk=false,wbk=false}
    if not (C_Container and C_Container.GetContainerNumSlots and
        C_Container.GetContainerItemLink) then return result end

    local function Scan(bagID,location,source)
        local count=C_Container.GetContainerNumSlots(bagID) or 0
        for slotID=1,count do
            local link=C_Container.GetContainerItemLink(bagID,slotID)
            if link then
                local item={itemLink=link,bagID=bagID,slotID=slotID,
                    location=location,source=source}
                item.guid=WGRStorageCleanupGetPhysicalCopyGUID(bagID,slotID,link)
                local key=tostring(source)..':'..tostring(bagID)..':'..
                    tostring(slotID)..':'..tostring(link)
                result.slots[key]=item
                local pos=tostring(source)..':'..tostring(bagID)..':'..tostring(slotID)
                result.positions[pos]=item
                result.counts[link]=(result.counts[link] or 0)+1
                if source=='BAGS' then
                    result.bagCounts[link]=(result.bagCounts[link] or 0)+1
                end
                if item.guid then
                    if result.byGUID[item.guid] then
                        result.byGUID[item.guid]=nil
                        result.guidCollisions[item.guid]=true
                    elseif not result.guidCollisions[item.guid] then
                        result.byGUID[item.guid]=item
                    end
                end
            end
        end
    end

    for bagID=0,4 do Scan(bagID,'BAG','BAGS') end

    result.pbk=WGRGearFinderIsPersonalBankOpen and
        WGRGearFinderIsPersonalBankOpen() or false
    result.wbk=WGRGearFinderIsWarbandBankOpen and
        WGRGearFinderIsWarbandBankOpen() or false

    local function Tabs(bankType)
        if not (C_Bank and C_Bank.FetchPurchasedBankTabIDs) or bankType==nil then return {} end
        local ids=C_Bank.FetchPurchasedBankTabIDs(bankType)
        return type(ids)=='table' and ids or {}
    end

    if result.pbk and Enum and Enum.BankType then
        for _,bagID in ipairs(Tabs(Enum.BankType.Character)) do
            Scan(bagID,'PBK','PERSONAL_BANK')
        end
    end
    if result.wbk and Enum and Enum.BankType then
        for _,bagID in ipairs(Tabs(Enum.BankType.Account)) do
            Scan(bagID,'WBK','WARBAND_BANK')
        end
    end
    return result
end

-- v0.68z: Resolve a WBGR-controlled frozen transfer without assuming that
-- Warband Bank preserves C_Item.GetItemGUID across the bank boundary. Exact
-- GUID relocation wins when observable. Otherwise the transfer is accepted
-- only by an exact source-vacated/new-destination-slot delta with no count
-- ambiguity. Exported so regression tests exercise the production resolver.
function WGRStorageCleanupResolveControlledTransfer(before,after,selected,destination,positionKey,moveResult)
    local function DefaultPositionKey(item)
        if not item or item.source==nil or item.bagID==nil or item.slotID==nil then return nil end
        return tostring(item.source)..':'..tostring(item.bagID)..':'..tostring(item.slotID)
    end
    positionKey=positionKey or DefaultPositionKey
    local resolved,unresolved,usedPositions={},{},{}
    local beforePositions=before and before.positions or {}
    local afterPositions=after and after.positions or {}
    -- v0.72ap legacy frozen-batch resolver: the old controlled mover reported the exact WBK
    -- destination slot for cursor transfers that WoW accepted.  Prefer that
    -- proof before requiring the source container API to report empty; after
    -- BAG/PBK -> WBK moves the source slot can remain transiently visible
    -- even when the newly empty target slot has already received the item.
    local manifestBySource={}
    local manifest=type(moveResult)=='table' and moveResult.manifest or nil
    for _,move in ipairs(type(manifest)=='table' and manifest or {}) do
        if move and move.success and move.source~=nil and move.sourceBagID~=nil
            and move.sourceSlotID~=nil and move.itemLink then
            local sourceKey=table.concat({tostring(move.source),tostring(move.sourceBagID),
                tostring(move.sourceSlotID),tostring(move.itemLink)},':')
            manifestBySource[sourceKey]=move
        end
    end
    for _,entry in ipairs(selected or {}) do
        local sourcePos=positionKey(entry.record)
        local prior=sourcePos and beforePositions[sourcePos]
        if not prior or prior.itemLink~=entry.record.itemLink then
            return nil,'selected source was not present in the pre-move snapshot'
        end
        local sourceKey=table.concat({tostring(entry.record.source),tostring(entry.record.bagID),
            tostring(entry.record.slotID),tostring(entry.record.itemLink)},':')
        local move=manifestBySource[sourceKey]
        local manifestResolved=false
        if move and move.destination==destination and move.targetBagID~=nil
            and move.targetSlotID~=nil then
            local targetProbe={source=destination,bagID=move.targetBagID,slotID=move.targetSlotID}
            local targetPos=positionKey(targetProbe)
            local live=targetPos and afterPositions[targetPos] or nil
            if targetPos and not beforePositions[targetPos] and live
                and live.source==destination and live.itemLink==entry.record.itemLink
                and not usedPositions[targetPos] then
                usedPositions[targetPos]=true
                resolved[#resolved+1]={entry=entry,live=live,proof='MOVE_MANIFEST'}
                manifestResolved=true
            end
        end
        if not manifestResolved then
            if afterPositions[sourcePos] then
                return nil,'selected source slot did not vacate'
            end
            local guid=entry.sourceGUID
            local live=guid and after.byGUID and after.byGUID[guid] or nil
            local livePos=live and positionKey(live) or nil
            if live and not (after.guidCollisions and after.guidCollisions[guid])
                and live.source==destination and live.itemLink==entry.record.itemLink
                and livePos and not beforePositions[livePos] and not usedPositions[livePos] then
                usedPositions[livePos]=true
                resolved[#resolved+1]={entry=entry,live=live,proof='GUID'}
            else
                unresolved[#unresolved+1]=entry
            end
        end
    end
    if #unresolved==0 then return resolved,nil end
    local candidatesByLink={}
    for pos,live in pairs(afterPositions) do
        if live.source==destination and not beforePositions[pos] and not usedPositions[pos] then
            local list=candidatesByLink[live.itemLink]
            if not list then list={};candidatesByLink[live.itemLink]=list end
            list[#list+1]={pos=pos,live=live}
        end
    end
    local unresolvedByLink={}
    for _,entry in ipairs(unresolved) do
        local link=entry.record.itemLink
        local list=unresolvedByLink[link]
        if not list then list={};unresolvedByLink[link]=list end
        list[#list+1]=entry
    end
    for link,entries in pairs(unresolvedByLink) do
        local candidates=candidatesByLink[link] or {}
        if #candidates~=#entries then
            return nil,'new destination slot delta is ambiguous for '..tostring(link)
        end
        table.sort(candidates,function(a,b) return a.pos<b.pos end)
        table.sort(entries,function(a,b) return tostring(a.origin)<tostring(b.origin) end)
        for i,entry in ipairs(entries) do
            local candidate=candidates[i]
            usedPositions[candidate.pos]=true
            resolved[#resolved+1]={entry=entry,live=candidate.live,proof='SLOT_DELTA'}
        end
    end
    return resolved,nil
end

function WGRStorageCleanupFrozenUnselectedIntact(session,selected,before,after,physicalKey,positionKey)
    local function DefaultPhysicalKey(item)
        if not item or item.source==nil or item.bagID==nil or item.slotID==nil or not item.itemLink then return nil end
        return tostring(item.source)..':'..tostring(item.bagID)..':'..tostring(item.slotID)..':'..tostring(item.itemLink)
    end
    local function DefaultPositionKey(item)
        if not item or item.source==nil or item.bagID==nil or item.slotID==nil then return nil end
        return tostring(item.source)..':'..tostring(item.bagID)..':'..tostring(item.slotID)
    end
    physicalKey=physicalKey or DefaultPhysicalKey
    positionKey=positionKey or DefaultPositionKey
    local selectedOrigins={}
    for _,entry in ipairs(selected or {}) do selectedOrigins[entry.origin]=true end
    local beforePositions=before and before.positions or {}
    local afterPositions=after and after.positions or {}
    local function Unchanged(item)
        local pos=positionKey(item)
        local prior=pos and beforePositions[pos]
        local live=pos and afterPositions[pos]
        if not prior or not live or prior.itemLink~=item.itemLink or live.itemLink~=item.itemLink then
            return false
        end
        if prior.guid and live.guid and prior.guid~=live.guid then return false end
        return true
    end
    for _,item in ipairs(session and session.keep or {}) do
        if not Unchanged(item) then return false,'a protected KEEP slot changed during transfer' end
    end
    for _,original in ipairs(session and session.surplus or {}) do
        local origin=physicalKey(original)
        if not selectedOrigins[origin] then
            local staged=session.staged and session.staged[origin]
            if staged then
                if not Unchanged(staged) then return false,'an unselected staged slot changed during transfer' end
            elseif not (session.moved and session.moved[origin]) then
                if not Unchanged(original) then return false,'an unselected SURPLUS slot changed during transfer' end
            end
        end
    end
    return true
end

-- Resolve the exact item under the mouse from generic WoW button metadata.
-- This deliberately has NO bag-addon integration.  Only a live, uniquely
-- identified Blizzard bag/slot and matching item are accepted; the GUID is
-- rechecked by the existing mark/clear operations below.
function WGRStorageCleanupHoveredPhysicalCopy()
    local hovered=GetHoveredItem and GetHoveredItem() or nil
    local frames={}
    if GetMouseFoci then
        local ok,result=pcall(GetMouseFoci)
        if ok and type(result)=='table' then frames=result end
    end
    if #frames==0 and GetMouseFocus then
        local ok,frame=pcall(GetMouseFocus)
        if ok and frame then frames={frame} end
    end
    local candidates={}
    local unique={}
    local function Field(frame,key,method)
        local value=frame and frame[key]
        if type(value)=='number' then return value end
        if method and frame and type(frame[method])=='function' then
            local ok,result=pcall(frame[method],frame)
            if ok and type(result)=='number' then return result end
        end
    end
    for _,focus in ipairs(frames) do
        local depth=0
        local frame=focus
        local originalSlot=Field(focus,'slotID','GetSlotID') or
            Field(focus,'slot','GetID')
        while frame and depth<5 do
            local bag=Field(frame,'bagID','GetBagID') or Field(frame,'bag','GetBag')
            local slot=Field(frame,'slotID','GetSlotID') or
                Field(frame,'slot','GetID') or originalSlot
            if type(bag)=='number' and type(slot)=='number' then
                local guid,link=WGRStorageCleanupCurrentCopy(bag,slot,hovered)
                if guid then
                    local key=tostring(bag)..':'..tostring(slot)
                    if not unique[key] then
                        candidates[#candidates+1]={bag=bag,slot=slot,link=link,guid=guid}
                        unique[key]=true
                    end
                end
            end
            depth=depth+1
            frame=(frame.GetParent and frame:GetParent()) or nil
        end
    end
    if #candidates==1 then
        return candidates[1].bag,candidates[1].slot,candidates[1].link
    end
    return nil,nil,(#candidates>1 and 'Multiple hovered item slots; use the WBGR right-click menu'
        or 'Cannot identify a physical item under the cursor; use WBGR right-click')
end

local function WGRStorageCleanupMarkGeneration()
    local saved=WarboundGearRouterDB and WarboundGearRouterDB.storageCleanupInventory
    local monitoring=saved and saved.monitoring
    -- v0.72n: DISPOSE/automatic-mark lifetime is deliberately separate from
    -- saved-inventory confidence. Turning Cleanup OFF must still make old
    -- disposal marks inactive even when the user later chooses to trust the
    -- previously saved inventory snapshots. Older databases used the inventory
    -- generation for both jobs, so fall back to it during migration.
    return tonumber(monitoring and monitoring.markGeneration) or
        tonumber(monitoring and monitoring.generation) or 0
end

-- Automatic approvals remain session-only. A display re-audit must not
-- revoke a proven status, but a relevant *physical* change must. Each mark
-- holds the global and equipment-slot epoch current when it was verified.
-- No persisted epoch can make a stale mark active on reload; the live table
-- below is still mandatory for automatic marks.
local WGRStorageCleanupActiveAutoMarks={}
local WGRStorageCleanupAutoGlobalEpoch=0
local WGRStorageCleanupAutoGroupEpoch={}

local function WGRStorageCleanupApprovalGroup(link)
    -- Broader than the future-use allocator by design: every shield shares
    -- the same dependency, as do all weapons of a given equip location.
    -- Ambiguous item data invalidates ALL approvals rather than guessing.
    local equipLoc
    if C_Item and C_Item.GetItemInfo then
        local _,_,_,_,_,_,_,_,location=C_Item.GetItemInfo(link)
        equipLoc=location
    end
    if type(equipLoc)=='string' and equipLoc~='' then return equipLoc end
    return nil
end

local function WGRStorageCleanupApprovalStamp(group)
    if not group then return nil end
    return tostring(WGRStorageCleanupAutoGlobalEpoch)..':'..
        tostring(WGRStorageCleanupAutoGroupEpoch[group] or 0)
end

local function WGRStorageCleanupInvalidateApprovalGroups(changedGroups,all)
    if all then
        WGRStorageCleanupAutoGlobalEpoch=WGRStorageCleanupAutoGlobalEpoch+1
    else
        for group in pairs(changedGroups or {}) do
            WGRStorageCleanupAutoGroupEpoch[group]=(WGRStorageCleanupAutoGroupEpoch[group] or 0)+1
        end
    end
    -- Only refresh when at least one live automatic mark was affected.
    local invalidated=false
    for guid,mark in pairs(WGRStorageCleanupActiveAutoMarks) do
        if mark and (all or (changedGroups and changedGroups[mark.approvalGroup])) then
            WGRStorageCleanupActiveAutoMarks[guid]=nil
            invalidated=true
        end
    end
    if invalidated then
        local function refresh()
            if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
            if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.1) end
            if WGRMailRefreshCurrentTodoSnapshot then
                WGRMailRefreshCurrentTodoSnapshot(true,true)
            elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0,refresh) else
            -- Avoid unexpected recursion if an audit runs inside UI rendering;
            -- the next ordinary refresh still observes the invalid status.
        end
    end
end

local function WGRStorageCleanupMarkTable()
    InitializeDatabase()
    local db=WarboundGearRouterDB
    if type(db.storageCleanupDisposalMarks)~='table' then
        db.storageCleanupDisposalMarks={}
    end
    return db.storageCleanupDisposalMarks
end

-- v0.72bf: WoW can expose a different item GUID for the same stored physical
-- copy after a character switch/relog, especially for shared Warband Bank
-- items. GUID remains the primary identity, but persistent MANUAL KEEP/DISPOSE
-- now records an exact last-known location as a conservative session-boundary
-- fallback. We re-key only when the same item link still occupies that exact
-- slot, the owner scope matches (Bags/PBK) or the location is shared WBK, and
-- the old GUID is not still visible elsewhere. This preserves user intent
-- without ever assigning a mark by item link alone.
local function WGRStorageCleanupBagSource(bagID,sourceHint)
    -- v0.72bg: bank bag IDs are not a durable identity by themselves. Callers
    -- that already know whether a slot came from PBK or WBK must pass that
    -- source through instead of asking this helper to infer it again.
    if sourceHint=='BAGS' or sourceHint=='PERSONAL_BANK' or sourceHint=='WARBAND_BANK' then
        return sourceHint
    end
    bagID=tonumber(bagID)
    if bagID and bagID>=0 and bagID<=4 then return 'BAGS' end
    if not (C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType) then
        return nil
    end
    local function Contains(bankType)
        if bankType==nil then return false end
        local ok,ids=pcall(C_Bank.FetchPurchasedBankTabIDs,bankType)
        if not ok or type(ids)~='table' then return false end
        for _,id in ipairs(ids) do if tonumber(id)==bagID then return true end end
        return false
    end
    local personal=Contains(Enum.BankType.Character)
    local shared=Contains(Enum.BankType.Account)
    if personal==shared then return nil end -- unknown or ambiguous: fail closed
    return shared and 'WARBAND_BANK' or 'PERSONAL_BANK'
end

local function WGRStorageCleanupPersistentManualRecord(mark)
    return type(mark)=='table' and (mark.mode=='KEEP' or mark.mode=='DISPOSE') and
        (mark.reason==nil or mark.reason=='MANUAL' or
         mark.reason=='MANUAL_DISPOSAL_MAIL_RECOVERY')
end

local function WGRStorageCleanupManualOwnerForSource(source,currentName)
    if source=='WARBAND_BANK' then return 'Shared Warbank' end
    return currentName
end

local function WGRStorageCleanupLegacyExactPBKConflict(mark,bagID,slotID,link)
    -- v0.72bf briefly wrote some WBK marks as owner/PBK because it inferred
    -- bank type from bagID. Before repairing such a record, make sure the old
    -- owner really does NOT have this exact link in the exact saved PBK slot.
    -- If it does, the record is ambiguous and must remain unresolved.
    if type(mark)~='table' or not mark.owner or mark.owner=='Shared Warbank' then return false end
    local saved=WarboundGearRouterDB and WarboundGearRouterDB.storageCleanupInventory
    for _,char in pairs(type(saved)=='table' and saved.characters or {}) do
        if type(char)=='table' and type(char.name)=='string' and
            tostring(char.name):lower()==tostring(mark.owner):lower() then
            local pbk=char.sections and char.sections.PBK
            for _,entry in ipairs(type(pbk)=='table' and pbk.items or {}) do
                if tonumber(entry.bagID)==tonumber(bagID) and
                    tonumber(entry.slotID)==tonumber(slotID) and entry.itemLink==link then
                    return true
                end
            end
        end
    end
    return false
end

-- v0.72bm: Item hyperlink fields linkLevel and specializationID belong to the
-- viewing character, not the physical gear. Live evidence: a saved WBK item
-- was rendered 90:253 on Arikannah and 81:265 on Blissandra. Normalize ONLY
-- these two fields for exact source + bank-tab + slot reconciliation. Every
-- physical attribute (itemID, enchant/gems, bonus IDs, modifiers) stays exact.
-- Never use normalized payload alone to find a different slot/copy.
local function WGRStorageCleanupComparableWBKItemPayload(link)
    if type(link)~='string' then return nil end
    local payload=link:match('|H(item:[^|]+)|h') or link:match('^(item:[^|]+)$')
    if not payload or payload:sub(1,5)~='item:' then return nil end
    local start=1
    -- 9 colons precede the viewing character's linkLevel field.
    for _=1,9 do
        local colon=payload:find(':',start,true)
        if not colon then return nil end
        start=colon+1
    end
    local afterLevel=payload:find(':',start,true)
    if not afterLevel or not payload:sub(start,afterLevel-1):match('^%d+$') then return nil end
    local afterSpec=payload:find(':',afterLevel+1,true)
    if not afterSpec or not payload:sub(afterLevel+1,afterSpec-1):match('^%d+$') then return nil end
    return payload:sub(1,start-1)..'<linkLevel>:<specializationID>'..payload:sub(afterSpec)
end

local function WGRStorageCleanupSameWBKItemExceptViewingContext(savedLink,liveLink)
    if savedLink==liveLink then return true end
    local saved=WGRStorageCleanupComparableWBKItemPayload(savedLink)
    return saved~=nil and saved==WGRStorageCleanupComparableWBKItemPayload(liveLink)
end

local function WGRStorageCleanupRebindSessionManualOverride(guid,link,bagID,slotID,sourceHint)
    local source=WGRStorageCleanupBagSource(bagID,sourceHint)
    if not source then return nil end
    local marks=WGRStorageCleanupMarkTable()
    if marks[guid] then return marks[guid] end
    local currentName=(UnitName and UnitName('player')) or nil
    local candidateGUID,candidate
    for savedGUID,mark in pairs(marks) do
        if tostring(savedGUID)~=tostring(guid) and WGRStorageCleanupPersistentManualRecord(mark)
            and ((source=='WARBAND_BANK' and WGRStorageCleanupSameWBKItemExceptViewingContext(mark.link,link))
                or (source~='WARBAND_BANK' and mark.link==link))
            and tonumber(mark.lastBag)==tonumber(bagID)
            and tonumber(mark.lastSlot)==tonumber(slotID) then
            local sourceOK=(mark.lastSource==nil or mark.lastSource==source)
            -- v0.72bg repair for the v0.72bf bank-source inference bug. Only
            -- explicit live WBK context may reinterpret a legacy unversioned
            -- PBK-looking record, and only when the old owner's exact saved PBK
            -- slot does not corroborate that PBK identity.
            if not sourceOK and source=='WARBAND_BANK' and
                tonumber(mark.identitySourceVersion or 0)<1 and
                not WGRStorageCleanupLegacyExactPBKConflict(mark,bagID,slotID,link) then
                sourceOK=true
            end
            local ownerOK=source=='WARBAND_BANK' or
                (currentName and mark.owner and
                 tostring(mark.owner):lower()==tostring(currentName):lower())
            if sourceOK and ownerOK then
                if candidate then return nil end -- more than one plausible saved copy
                candidateGUID=tostring(savedGUID)
                candidate=mark
            end
        end
    end
    if not candidate then return nil end

    -- If the old GUID is still physically visible, the marked copy moved and
    -- an identical replacement now occupies the old slot. Never steal the mark.
    local snapshot=WGRStorageCleanupSnapshotAccessiblePhysical and
        WGRStorageCleanupSnapshotAccessiblePhysical() or nil
    if snapshot and snapshot.byGUID and snapshot.byGUID[candidateGUID] then return nil end

    local rebound={}
    for key,value in pairs(candidate) do rebound[key]=value end
    rebound.link=link -- current-character representation; do not retain stale viewing-character fields
    rebound.lastBag=bagID
    rebound.lastSlot=slotID
    rebound.lastSource=source
    rebound.markedBy=rebound.markedBy or rebound.owner
    rebound.owner=WGRStorageCleanupManualOwnerForSource(source,currentName) or rebound.owner
    rebound.identitySourceVersion=1
    marks[guid]=rebound
    marks[candidateGUID]=nil
    WGRStorageCleanupActiveAutoMarks[candidateGUID]=nil
    WGRStorageCleanupActiveAutoMarks[guid]=nil
    return rebound
end

function WGRStorageCleanupGetCopyMark(bagID,slotID,expectedLink,sourceHint)
    local guid,link=WGRStorageCleanupCurrentCopy(bagID,slotID,expectedLink)
    if not guid then return nil end
    local marks=WGRStorageCleanupMarkTable()
    local mark=marks[guid]
    local authoritativeSource=WGRStorageCleanupBagSource(bagID,sourceHint)
    -- Exact GUID is primary identity. If a v0.72bf manual record is found by
    -- that exact GUID, authoritative live source may safely repair its old
    -- PBK/WBK metadata immediately; there is no physical-copy guess here.
    if mark and authoritativeSource and WGRStorageCleanupPersistentManualRecord(mark) and
        tonumber(mark.identitySourceVersion or 0)<1 then
        mark.markedBy=mark.markedBy or mark.owner
        mark.lastSource=authoritativeSource
        mark.owner=WGRStorageCleanupManualOwnerForSource(authoritativeSource,
            (UnitName and UnitName('player')) or nil) or mark.owner
        mark.identitySourceVersion=1
    end
    if not mark then
        mark=WGRStorageCleanupRebindSessionManualOverride(guid,link,bagID,slotID,sourceHint)
    end
    if type(mark)=='table' and (mark.link==link or
        (authoritativeSource=='WARBAND_BANK' and
         WGRStorageCleanupPersistentManualRecord(mark) and
         WGRStorageCleanupSameWBKItemExceptViewingContext(mark.link,link))) then
        -- Same GUID plus normalized payload proves this is the same copy.
        -- Refresh the presentation link so saved stock accounting stays aligned.
        if mark.link~=link then mark.link=link end
        local generation=WGRStorageCleanupMarkGeneration()
        -- Markings made before an OFF interval cannot silently resume.
        -- A stale DISPOSE is never re-enabled after interrupted tracking.
        -- A manual KEEP is protective and remains safe across that gap.
        local manual=(mark.reason==nil or mark.reason=='MANUAL' or
            mark.reason=='MANUAL_DISPOSAL_MAIL_RECOVERY')
        if not manual and not WGRStorageCleanupGetSettings().enabled then return nil end
        if mark.generation~=generation and mark.mode~='KEEP' and not manual then return nil end
        if mark.reason=='AUTO_VERIFIED' then
            if WGRStorageCleanupActiveAutoMarks[guid]~=mark or
                not mark.approvalGroup or
                mark.approvedGroupStamp~=WGRStorageCleanupApprovalStamp(mark.approvalGroup) then
                return nil
            end
        end
        return mark.mode,mark,guid
    end
    return nil
end

function WGRStorageCleanupIsDisposeCopy(bagID,slotID,expectedLink,sourceHint)
    local mode,mark=WGRStorageCleanupGetCopyMark(bagID,slotID,expectedLink,sourceHint)
    if mode~='DISPOSE' then return false end
    -- A recipient deliberately excluded from the normal roster has no
    -- current-upgrade routing to override. DISPOSE mail received on that
    -- Removed destination is explicitly user-directed disposal stock.
    if mark and (mark.reason=='RECEIVED_DISPOSAL_MAIL' or
        mark.reason=='RETURNED_DISPOSAL_MAIL' or
        mark.reason=='MANUAL_DISPOSAL_MAIL_RECOVERY') and
        WGRIsCharacterRemoved and WGRIsCharacterRemoved(UnitName('player')) then
        return true
    end
    -- Explicit manual DISPOSE is the player's decision, including when
    -- roster changes make the copy an immediate upgrade. Automatic/staged
    -- approvals remain limited by the original routing checks below.
    if mark and (mark.reason==nil or mark.reason=='MANUAL' or
        mark.reason=='MANUAL_DISPOSAL_MAIL_RECOVERY') then return true end
    local recommendation,status
    if WGRBuildLoadedItemRecommendation then
        recommendation,status=WGRBuildLoadedItemRecommendation(expectedLink or C_Container.GetContainerItemLink(bagID,slotID))
    end
    return status=='ready' and recommendation and (recommendation.kind=='holder'
        or recommendation.kind=='sell' or recommendation.kind=='no_current_upgrade')
end

function WGRStorageCleanupSetCopyMark(bagID,slotID,mode,reason,suppressRefresh,verifiedProof,sourceHint)
    -- Manual overrides are a core Recommendations feature, independent of
    -- the optional Storage Cleanup scanner. Auto-verified marks are not.
    if reason=='AUTO_VERIFIED' and not WGRStorageCleanupGetSettings().enabled then
        return false,'Storage Cleanup is OFF'
    end
    if WGRRoutingIsPaused and WGRRoutingIsPaused() then return false,'WBGR routing is paused' end
    if WGRIsCharacterRemoved and WGRIsCharacterRemoved(UnitName('player')) then
        return false,'Removed characters cannot assign WBGR disposal statuses'
    end
    -- v0.72be: Mark All already completed a routing/account proof during the
    -- explicit Cleanup scan. On a newly logged-in character the ordinary item
    -- recommendation cache can briefly return not_loaded again even though the
    -- scan-approved physical copy is unchanged. A verifiedProof may therefore
    -- reuse the recommendation captured by that fresh scan, but ONLY when the
    -- live slot still contains the exact expected link + physical GUID. Normal
    -- manual KEEP/DISPOSE callers do not supply this proof and retain the old
    -- live-recommendation requirement.
    local proof=type(verifiedProof)=='table' and verifiedProof or nil
    sourceHint=(proof and proof.source) or sourceHint
    local source=WGRStorageCleanupBagSource(bagID,sourceHint)
    local expectedLink=proof and proof.link or nil
    local guid,link,errorText=WGRStorageCleanupCurrentCopy(bagID,slotID,expectedLink)
    if not guid then return false,errorText end
    if proof and (not proof.guid or tostring(proof.guid)~=tostring(guid)) then
        return false,'Physical copy changed since Cleanup scan'
    end
    if mode~='DISPOSE' and mode~='KEEP' and mode~='CLEAR' then return false,'Invalid status' end
    local marks=WGRStorageCleanupMarkTable()
    local generation=WGRStorageCleanupMarkGeneration()
    local prior=marks[guid]
    if mode=='CLEAR' then
        if not marks[guid] then return false,'This copy has no manual override' end
        marks[guid]=nil
        WGRStorageCleanupActiveAutoMarks[guid]=nil
    else
        -- Both commands and menus use ONE value, never independent flags.
        -- Manual KEEP blocks automatic DISPOSE without replacing normal routing.
        local recommendation,status
        if proof and mode=='DISPOSE' and reason=='MANUAL'
            and type(proof.recommendation)=='table' then
            recommendation=proof.recommendation
            status='ready'
        elseif WGRBuildLoadedItemRecommendation then
            recommendation,status=WGRBuildLoadedItemRecommendation(link)
        end
        local manual=(reason==nil or reason=='MANUAL' or
            reason=='MANUAL_DISPOSAL_MAIL_RECOVERY')
        if not (status=='ready' and recommendation and
            (recommendation.kind=='holder' or recommendation.kind=='sell'
             or recommendation.kind=='no_current_upgrade' or
             (manual and (recommendation.kind=='upgrade' or
                 recommendation.kind=='future_upgrade')))) then
            return false,'No eligible, resolved gear recommendation for this copy'
        end
        local auto=reason=='AUTO_VERIFIED'
        local group=WGRStorageCleanupApprovalGroup(link)
        -- A mark without a known equipment group has no trustworthy proof.
        if auto and not group then return false,'Item equipment group unavailable' end
        local currentName=(UnitName and UnitName('player')) or nil
        marks[guid]={mode=mode,link=link,
            owner=WGRStorageCleanupManualOwnerForSource(source,currentName) or currentName,
            markedBy=currentName,
            originalRecipient=recommendation.name,reason=reason or 'MANUAL',
            lastBag=bagID,lastSlot=slotID,lastSource=source,
            identitySourceVersion=source and 1 or nil,
            approvalGroup=auto and group or nil,
            approvedGroupStamp=auto and WGRStorageCleanupApprovalStamp(group) or nil,
            generation=generation,markedAt=(GetServerTime and GetServerTime()) or (time and time()) or 0}
        WGRStorageCleanupActiveAutoMarks[guid]=auto and marks[guid] or nil
    end
    -- A deliberate KEEP/DISPOSE/clear changes the stock available to other
    -- approvals of this category; it must never affect unrelated shields/
    -- leggings. Bulk AUTO_VERIFIED marks were proved together in one check.
    if reason~='AUTO_VERIFIED' then
        local oldGroup=prior and WGRStorageCleanupApprovalGroup(prior.link)
        local newGroup=WGRStorageCleanupApprovalGroup(link)
        if (not prior or oldGroup) and newGroup then
            local changed={[newGroup]=true}
            if oldGroup then changed[oldGroup]=true end
            WGRStorageCleanupInvalidateApprovalGroups(changed,false)
        else
            WGRStorageCleanupInvalidateApprovalGroups(nil,true)
        end
    end
    if not suppressRefresh then
        if WGRRefreshCopyOverlay then WGRRefreshCopyOverlay(bagID,slotID) end
        if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.1) end
        if WGRMailRefreshCurrentTodoSnapshot then
            WGRMailRefreshCurrentTodoSnapshot(true,true)
        elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
    end
    -- Manual KEEP/DISPOSE is a core Recommendations override. Prime the
    -- lightweight movement tracker immediately so a subsequent Bags/PBK/WBK
    -- transfer can preserve this exact physical decision even if WBK changes
    -- the item's GUID at the bank boundary.
    if reason~='AUTO_VERIFIED' and WGRStorageCleanupPrimeManualOverrideMovementSnapshot then
        WGRStorageCleanupPrimeManualOverrideMovementSnapshot()
    end
    return true,link
end

-- v0.68x: Account-verified bank surplus becomes an actionable reminder
-- only after the user deliberately stages the exact physical copy into Bags
-- and the original GUID is confirmed at the destination.  A local-only
-- SURPLUS estimate, matching item link, or unverified move is never enough.
function WGRStorageCleanupConfirmVerifiedStagedCopy(bagID,slotID,link,sourceGUID)
    if not sourceGUID or not link then return false,'Unverified staging identity' end
    local physical=WGRStorageCleanupGetPhysicalCopyGUID(bagID,slotID,link)
    if not physical or physical~=sourceGUID then
        return false,'Physical GUID changed during staging'
    end
    local mode=WGRStorageCleanupGetCopyMark(bagID,slotID,link)
    if mode=='KEEP' then return false,'Protected KEEP copy' end
    if mode=='DISPOSE' then return true,'Already marked DISPOSE' end
    return WGRStorageCleanupSetCopyMark(bagID,slotID,
        'DISPOSE','STAGED_VERIFIED_SURPLUS',true)
end

-- v0.68z: Warband Bank withdrawal may not expose the same item GUID at the
-- destination even when WBGR can prove its own controlled transfer by source
-- disappearance + destination slot delta.  Once that transaction has been
-- proven by the frozen mover, persist disposal intent on the CURRENT Bag GUID.
-- This function intentionally does not accept an old/source GUID as proof.
function WGRStorageCleanupConfirmVerifiedStagedArrival(bagID,slotID,link)
    if not link then return false,'Unverified staging arrival' end
    local physical=WGRStorageCleanupGetPhysicalCopyGUID(bagID,slotID,link)
    if not physical then return false,'Destination physical GUID unavailable' end
    local mode=WGRStorageCleanupGetCopyMark(bagID,slotID,link)
    if mode=='KEEP' then return false,'Protected KEEP copy' end
    if mode=='DISPOSE' then return true,'Already marked DISPOSE' end
    return WGRStorageCleanupSetCopyMark(bagID,slotID,
        'DISPOSE','STAGED_VERIFIED_SURPLUS',true)
end

-- Clear only WBGR's staging-generated mark after a verified Return.  The
-- staged Bag GUID can legitimately cease to exist when crossing WBK, so the
-- cleanup is keyed to the GUID that was marked BEFORE movement rather than
-- requiring GUID continuity at the destination. Manual/received DISPOSE and
-- KEEP records are never removed by this helper.
function WGRStorageCleanupClearVerifiedStageByGUID(sourceGUID,expectedLink)
    if not sourceGUID then return false,'Missing staged source GUID' end
    local marks=WGRStorageCleanupMarkTable()
    local mark=marks[sourceGUID]
    if not mark or mark.mode~='DISPOSE' or mark.reason~='STAGED_VERIFIED_SURPLUS' then
        return false,'Not a staging-generated DISPOSE mark'
    end
    if expectedLink and mark.link~=expectedLink then
        return false,'Staged item link changed'
    end
    local group=WGRStorageCleanupApprovalGroup(mark.link)
    marks[sourceGUID]=nil
    WGRStorageCleanupActiveAutoMarks[sourceGUID]=nil
    if group then
        WGRStorageCleanupInvalidateApprovalGroups({[group]=true},false)
    else
        WGRStorageCleanupInvalidateApprovalGroups(nil,true)
    end
    return true
end

-- The explicit frozen-batch Return action cancels only WBGR's own staged
-- mark.  Manual user DISPOSE, Received-via-Mail and KEEP remain untouched.
function WGRStorageCleanupClearVerifiedStageOnReturn(bagID,slotID,link,sourceGUID)
    if not sourceGUID or not link or
        WGRStorageCleanupGetPhysicalCopyGUID(bagID,slotID,link)~=sourceGUID then
        return false,'Physical GUID changed during return'
    end
    local mode,mark=WGRStorageCleanupGetCopyMark(bagID,slotID,link)
    if mode=='DISPOSE' and mark and mark.reason=='STAGED_VERIFIED_SURPLUS' then
        return WGRStorageCleanupClearCopyOverride(bagID,slotID,'DISPOSE')
    end
    return false,'Not a staging-generated DISPOSE mark'
end

-- Slash/menu clearing is mode-specific. /unkeep must not clear DISPOSE,
-- /undispose must not clear KEEP. Both restore AUTO without recalculating.
function WGRStorageCleanupClearCopyOverride(bagID,slotID,expectedMode,sourceHint)
    local mode=WGRStorageCleanupGetCopyMark(bagID,slotID,nil,sourceHint)
    if mode~=expectedMode then
        -- Allow explicitly clearing an old DISPOSE record that became
        -- inactive during a monitoring gap. Never reactivate it first.
        local guid=WGRStorageCleanupCurrentCopy(bagID,slotID)
        local saved=guid and WGRStorageCleanupMarkTable()[guid]
        if not saved or saved.mode~=expectedMode then
            return false,'Copy is not marked '..tostring(expectedMode)
        end
    end
    return WGRStorageCleanupSetCopyMark(bagID,slotID,'CLEAR','MANUAL',nil,nil,sourceHint)
end

-- v0.72bi TEST: read-only account persistence diagnostics. No mark mutation,
-- no inference by item-link alone, no ordinary user-facing chat spam.
function WGRStorageCleanupDiagnoseManualWBK()
    local db=WarboundGearRouterDB or {}
    local marks=type(db.storageCleanupDisposalMarks)=='table' and db.storageCleanupDisposalMarks or {}
    local all,manual,wbk,pbk,bag,unknown=0,0,0,0,0,0
    local byGUID,byExact,byLink={},{},{}
    local saved={}
    for guid,mark in pairs(marks) do
        all=all+1
        if WGRStorageCleanupPersistentManualRecord(mark) then
            manual=manual+1
            local source=mark.lastSource
            if source=='WARBAND_BANK' then
                wbk=wbk+1
                saved[#saved+1]={guid=tostring(guid),mark=mark}
                byGUID[tostring(guid)]=mark
                local key=tostring(mark.lastBag)..':'..tostring(mark.lastSlot)..':'..tostring(mark.link)
                byExact[key]=(byExact[key] or 0)+1
                byLink[tostring(mark.link)]=(byLink[tostring(mark.link)] or 0)+1
            elseif source=='PERSONAL_BANK' then pbk=pbk+1
            elseif source=='BAGS' then bag=bag+1
            else unknown=unknown+1 end
        end
    end
    print('|cff33ff99WBGR MARKDIAG:|r character='..tostring(UnitName and UnitName('player'))..
        ' stored marks='..all..' manual='..manual..' WBK='..wbk..
        ' PBK='..pbk..' BAG='..bag..' unknown='..unknown)
    print('|cff33ff99WBGR MARKDIAG:|r DB='..tostring(db)..
        ' markTable='..tostring(marks)..' (session-only identifiers)')
    local open=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen()
    if not open then
        print('|cffffaa00WBGR MARKDIAG:|r WBK not recognized as open; open Warband Bank and rerun.');return
    end
    local bankType=Enum and Enum.BankType and Enum.BankType.Account
    local tabs
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and bankType then
        local ok,result=pcall(C_Bank.FetchPurchasedBankTabIDs,bankType)
        if ok and type(result)=='table' then tabs=result end
    end
    if not tabs then
        print('|cffffaa00WBGR MARKDIAG:|r Purchased WBK tabs unavailable.');return
    end
    local live,exactGUID,exactPosition,linkOnly,unmatched,noGUID=0,0,0,0,0,0
    local details={}
    for _,tab in ipairs(tabs) do
        for slot=1,(C_Container.GetContainerNumSlots(tab) or 0) do
            local link=C_Container.GetContainerItemLink(tab,slot)
            if link then
                live=live+1
                local guid=WGRStorageCleanupGetPhysicalCopyGUID(tab,slot,link)
                if not guid then noGUID=noGUID+1 end
                local key=tostring(tab)..':'..tostring(slot)..':'..tostring(link)
                if guid and byGUID[guid] and byGUID[guid].link==link then
                    exactGUID=exactGUID+1
                elseif byExact[key] then exactPosition=exactPosition+1
                elseif byLink[tostring(link)] then
                    linkOnly=linkOnly+1
                    if #details<6 then details[#details+1]='link elsewhere tab='..tostring(tab)..
                        ' slot='..tostring(slot)..' item='..(tostring(link):match('item:(%d+)') or '?') end
                else unmatched=unmatched+1 end
            end
        end
    end
    print('|cff33ff99WBGR MARKDIAG:|r WBK live='..live..' matchingGUID='..exactGUID..
        ' matchingExactSlotLink='..exactPosition..' linkOnlyElsewhere='..linkOnly..
        ' noSavedLink='..unmatched..' noGUID='..noGUID)
    for _,detail in ipairs(details) do print('|cffaaaaaaWBGR MARKDIAG:|r '..detail) end
    -- v0.72bj: distinguish a truly different live bank view from full-link
    -- drift or tab-index drift. Compare item IDs ONLY for diagnostics; never
    -- use this evidence to grant or migrate a manual status.
    local savedIDs,savedSlots,savedTabs={}, {}, {}
    for _,entry in ipairs(saved) do
        local mark=entry.mark
        local itemID=tostring(mark.link or ''):match('item:(%d+)')
        if itemID then savedIDs[itemID]=(savedIDs[itemID] or 0)+1 end
        savedSlots[tostring(mark.lastBag)..':'..tostring(mark.lastSlot)]=entry
        savedTabs[tostring(mark.lastBag)]=(savedTabs[tostring(mark.lastBag)] or 0)+1
    end
    local seenIDs,seenLiveSlots,seenSameIDAtSlot,seenDifferentLinkAtSlot=0,0,0,0
    local liveIDCounts,liveTabCounts,differences={},{},{}
    for _,tab in ipairs(tabs) do
        for slot=1,(C_Container.GetContainerNumSlots(tab) or 0) do
            local link=C_Container.GetContainerItemLink(tab,slot)
            if link then
                local itemID=tostring(link):match('item:(%d+)')
                if itemID then liveIDCounts[itemID]=(liveIDCounts[itemID] or 0)+1 end
                liveTabCounts[tostring(tab)]=(liveTabCounts[tostring(tab)] or 0)+1
                local record=savedSlots[tostring(tab)..':'..tostring(slot)]
                if record then
                    seenLiveSlots=seenLiveSlots+1
                    local savedID=tostring(record.mark.link or ''):match('item:(%d+)')
                    if savedID and savedID==itemID then
                        seenSameIDAtSlot=seenSameIDAtSlot+1
                        if record.mark.link~=link then
                            seenDifferentLinkAtSlot=seenDifferentLinkAtSlot+1
                        end
                    end
                    if #differences<4 then
                        differences[#differences+1]='slot tab='..tostring(tab)..
                            ' slot='..tostring(slot)..' savedID='..tostring(savedID or '?')..
                            ' liveID='..tostring(itemID or '?')..
                            ' fullLinkEqual='..tostring(record.mark.link==link)
                    end
                end
            end
        end
    end
    for itemID,count in pairs(savedIDs) do
        if liveIDCounts[itemID] then seenIDs=seenIDs+math.min(count,liveIDCounts[itemID]) end
    end
    local function tabSummary(counts)
        local rows={}
        for tab,count in pairs(counts) do rows[#rows+1]=tostring(tab)..'='..tostring(count) end
        table.sort(rows)
        return table.concat(rows,',')
    end
    print('|cff33ff99WBGR MARKDIAG2:|r savedItems='..#saved..
        ' itemIDOverlap='..seenIDs..' savedSlotOccupied='..seenLiveSlots..
        ' sameItemIDAtSlot='..seenSameIDAtSlot..
        ' differingFullLinks='..seenDifferentLinkAtSlot)
    print('|cff33ff99WBGR MARKDIAG2:|r savedTabs={'..tabSummary(savedTabs)..
        '} liveTabs={'..tabSummary(liveTabCounts)..'}')

    -- v0.72bk: diagnose the actual hyperlink payload without treating item ID
    -- or tab/slot as a safe substitute for physical-copy identity. Read-only.
    -- Display text, pipe escapes and per-character item-string fields can
    -- differ; showing payloads lets us choose a minimal, justified rule.
    local samples=0
    local function itemPayload(link)
        local value=tostring(link or '')
        return value:match('|H(item:[^|]+)|h') or value:match('(item:[^|]+)') or '?'
    end
    local function short(value)
        value=tostring(value or '?')
        if #value>220 then return value:sub(1,220)..'...[truncated]' end
        return value
    end
    for _,entry in ipairs(saved) do
        if samples>=2 then break end
        local mark=entry.mark
        local tab,slot=tonumber(mark.lastBag),tonumber(mark.lastSlot)
        if tab and slot then
            local liveLink=C_Container.GetContainerItemLink(tab,slot)
            if liveLink and mark.link~=liveLink then
                samples=samples+1
                local savedPayload=itemPayload(mark.link)
                local livePayload=itemPayload(liveLink)
                print('|cff33ff99WBGR MARKDIAG3:|r tab='..tab..' slot='..slot..
                    ' payloadEqual='..tostring(savedPayload==livePayload))
                print('|cffaaaaaaWBGR MARKDIAG3 saved:|r '..short(savedPayload))
                print('|cffaaaaaaWBGR MARKDIAG3 live:|r '..short(livePayload))
            end
        end
    end

    for _,detail in ipairs(differences) do
        print('|cffaaaaaaWBGR MARKDIAG2:|r '..detail)
    end
    table.sort(saved,function(a,b)
        return tostring(a.mark.lastBag)..':'..tostring(a.mark.lastSlot)..':'..a.guid <
            tostring(b.mark.lastBag)..':'..tostring(b.mark.lastSlot)..':'..b.guid
    end)
    for i=1,math.min(4,#saved) do
        local m=saved[i].mark
        print('|cffaaaaaaWBGR MARKDIAG saved:|r tab='..tostring(m.lastBag)..
            ' slot='..tostring(m.lastSlot)..' item='..(tostring(m.link):match('item:(%d+)') or '?')..
            ' mode='..tostring(m.mode)..' owner='..tostring(m.owner)..
            ' source='..tostring(m.lastSource))
    end
end

function WGRStorageCleanupListManualOverrides()
    local results={}
    for guid,record in pairs(WGRStorageCleanupMarkTable()) do
        -- This panel is for explicit user overrides, not WBGR workflow state.
        -- STAGED_VERIFIED_SURPLUS / received-mail marks are shown through the
        -- live Cleanup/To Do surfaces and must not inflate Manual Overrides.
        local manualReason=record and (record.reason==nil or
            record.reason=='MANUAL' or record.reason=='MANUAL_DISPOSAL_MAIL_RECOVERY')
        if type(guid)=='string' and type(record)=='table'
            and manualReason
            and (record.mode=='KEEP' or record.mode=='DISPOSE') then
            results[#results+1]={guid=guid,mode=record.mode,link=record.link,
                owner=record.owner,lastBag=record.lastBag,lastSlot=record.lastSlot,
                reason=record.reason,
                inactive=false}
        end
    end
    table.sort(results,function(a,b)
        local ak=tostring(a.mode)..tostring(a.owner)..tostring(a.link)..a.guid
        local bk=tostring(b.mode)..tostring(b.owner)..tostring(b.link)..b.guid
        return ak<bk
    end)
    return results
end

-- Clearing a record by GUID is safe even when the holder is offline. This
-- never guesses where a copy is, moves it, or sets a new override remotely.
function WGRStorageCleanupClearSavedOverride(guid,expectedMode)
    local records=WGRStorageCleanupMarkTable()
    local item=records[guid]
    if not item or item.mode~=expectedMode then
        return false,'Saved override has changed'
    end
    records[guid]=nil
    WGRStorageCleanupActiveAutoMarks[guid]=nil
    local group=WGRStorageCleanupApprovalGroup(item.link)
    if group then
        WGRStorageCleanupInvalidateApprovalGroups({[group]=true},false)
    else
        WGRStorageCleanupInvalidateApprovalGroups(nil,true)
    end
    if WGRMailRefreshCurrentTodoSnapshot then WGRMailRefreshCurrentTodoSnapshot(true,true) end
    if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
    return true,item.link
end


-- v0.72ad: explicit manual KEEP/DISPOSE belongs to the physical copy, not
-- to a particular container GUID representation. WBK may expose a new GUID
-- after a Bags/PBK/WBK transfer. Re-key a manual override only after the
-- destination physical slot is known exactly; never infer from itemID/link
-- alone. Automatic/staging marks keep their stricter existing lifecycle.
local function WGRStorageCleanupIsPersistentManualOverride(mark)
    return type(mark)=='table' and (mark.mode=='KEEP' or mark.mode=='DISPOSE') and
        (mark.reason==nil or mark.reason=='MANUAL' or
         mark.reason=='MANUAL_DISPOSAL_MAIL_RECOVERY')
end

function WGRStorageCleanupTransferManualOverrideByGUID(sourceGUID,bagID,slotID,expectedLink,suppressRefresh,destinationSource)
    if type(sourceGUID)~='string' or sourceGUID=='' then return false,'Missing source GUID' end
    local marks=WGRStorageCleanupMarkTable()
    local source=marks[sourceGUID]
    if not WGRStorageCleanupIsPersistentManualOverride(source) then
        return false,'Source copy has no persistent manual override'
    end
    local destinationGUID,link,errorText=WGRStorageCleanupCurrentCopy(bagID,slotID,expectedLink or source.link)
    local destinationScope=WGRStorageCleanupBagSource(bagID,destinationSource)
    if not destinationGUID then return false,errorText end
    if link~=source.link then return false,'Destination item link changed' end
    if destinationGUID==sourceGUID then
        source.lastBag=bagID;source.lastSlot=slotID
        source.lastSource=destinationScope
        source.markedBy=source.markedBy or source.owner
        source.owner=WGRStorageCleanupManualOwnerForSource(destinationScope,(UnitName and UnitName('player')) or nil) or source.owner
        source.identitySourceVersion=destinationScope and 1 or source.identitySourceVersion
        return true,link,destinationGUID
    end
    if marks[destinationGUID] then
        return false,'Destination copy already has an override'
    end
    local moved={}
    for key,value in pairs(source) do moved[key]=value end
    moved.lastBag=bagID;moved.lastSlot=slotID
    moved.lastSource=destinationScope
    moved.markedBy=moved.markedBy or moved.owner
    moved.owner=WGRStorageCleanupManualOwnerForSource(destinationScope,(UnitName and UnitName('player')) or nil) or moved.owner
    moved.identitySourceVersion=destinationScope and 1 or moved.identitySourceVersion
    marks[destinationGUID]=moved
    marks[sourceGUID]=nil
    WGRStorageCleanupActiveAutoMarks[sourceGUID]=nil
    WGRStorageCleanupActiveAutoMarks[destinationGUID]=nil
    if not suppressRefresh then
        if WGRRefreshCopyOverlay then WGRRefreshCopyOverlay(bagID,slotID) end
        if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
        if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.1) end
        if WGRMailRefreshCurrentTodoSnapshot then
            WGRMailRefreshCurrentTodoSnapshot(true,true)
        elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
    end
    return true,link,destinationGUID
end

-- Preserve manual overrides across ordinary user-driven Bags/PBK/WBK moves
-- too. This deliberately fails closed on ambiguity: total accessible count for
-- the link must be unchanged, every GUID that disappeared for that link must
-- have carried the same class of persistent manual override, and the number of
-- newly appearing GUIDs must match exactly. Bank open/close, sales, destruction,
-- or mixed marked/unmarked duplicate movement therefore never guesses.
function WGRStorageCleanupReconcileManualOverrideMovement(before,after)
    if type(before)~='table' or type(after)~='table' then return 0,false end
    local marks=WGRStorageCleanupMarkTable()
    local oldByGUID=before.byGUID or {}
    local newByGUID=after.byGUID or {}
    local function Count(snapshot,link)
        if snapshot.counts and snapshot.counts[link]~=nil then return snapshot.counts[link] end
        local count=0
        for _,item in pairs(snapshot.byGUID or {}) do
            if item and item.itemLink==link then count=count+1 end
        end
        return count
    end
    local links={}
    for guid,item in pairs(oldByGUID) do
        local mark=marks[tostring(guid)]
        if item and item.itemLink and WGRStorageCleanupIsPersistentManualOverride(mark)
            and not newByGUID[guid] then
            links[item.itemLink]=true
        end
    end
    local moved=0
    local unresolved=false
    for link in pairs(links) do
        local resolvedThisLink=false
        if Count(before,link)==Count(after,link) then
            local lost,new={},{ }
            local lostAll=0
            for guid,item in pairs(oldByGUID) do
                if item and item.itemLink==link and not newByGUID[guid] then
                    lostAll=lostAll+1
                    local mark=marks[tostring(guid)]
                    if WGRStorageCleanupIsPersistentManualOverride(mark) then
                        lost[#lost+1]={guid=tostring(guid),mark=mark,item=item}
                    end
                end
            end
            for guid,item in pairs(newByGUID) do
                if item and item.itemLink==link and not oldByGUID[guid] then
                    new[#new+1]={guid=tostring(guid),item=item}
                end
            end
            -- No unmarked/mixed disappearing duplicate may participate.
            if #lost>0 and lostAll==#lost and #new==#lost then
                local mode=lost[1].mark.mode
                local compatible=true
                for _,entry in ipairs(lost) do
                    if entry.mark.mode~=mode then compatible=false;break end
                end
                for _,entry in ipairs(new) do
                    if marks[entry.guid] then compatible=false;break end
                end
                if compatible then
                    table.sort(lost,function(a,b) return a.guid<b.guid end)
                    table.sort(new,function(a,b)
                        local ai=a.item;local bi=b.item
                        local ak=tostring(ai.source)..':'..tostring(ai.bagID)..':'..tostring(ai.slotID)..':'..a.guid
                        local bk=tostring(bi.source)..':'..tostring(bi.bagID)..':'..tostring(bi.slotID)..':'..b.guid
                        return ak<bk
                    end)
                    -- Validate all live destinations before mutating any mark.
                    for index,entry in ipairs(new) do
                        local liveGUID,liveLink=WGRStorageCleanupCurrentCopy(
                            entry.item.bagID,entry.item.slotID,link)
                        if liveGUID~=entry.guid or liveLink~=link then compatible=false;break end
                    end
                    if compatible then
                        local copies={}
                        for index,entry in ipairs(lost) do
                            local copy={}
                            for key,value in pairs(entry.mark) do copy[key]=value end
                            local destination=new[index]
                            copy.lastBag=destination.item.bagID
                            copy.lastSlot=destination.item.slotID
                            copy.lastSource=destination.item.source or
                                WGRStorageCleanupBagSource(destination.item.bagID)
                            copy.markedBy=copy.markedBy or copy.owner
                            copy.owner=WGRStorageCleanupManualOwnerForSource(copy.lastSource,(UnitName and UnitName('player')) or nil) or copy.owner
                            copy.identitySourceVersion=copy.lastSource and 1 or copy.identitySourceVersion
                            copies[index]={old=entry.guid,new=destination.guid,mark=copy,
                                oldItem=entry.item,newItem=destination.item,
                                bagID=destination.item.bagID,slotID=destination.item.slotID}
                        end
                        for _,entry in ipairs(copies) do marks[entry.old]=nil end
                        for _,entry in ipairs(copies) do
                            marks[entry.new]=entry.mark
                            WGRStorageCleanupActiveAutoMarks[entry.old]=nil
                            WGRStorageCleanupActiveAutoMarks[entry.new]=nil
                            if WGRRefreshCopyOverlay then WGRRefreshCopyOverlay(entry.bagID,entry.slotID) end
                            -- v0.72av: manual drag/drop reconciliation already
                            -- proved an exact old GUID -> exact new GUID mapping.
                            -- Tell the visible Storage Cleanup manual audit about
                            -- that same physical relocation so its displayed row
                            -- and movement controls follow the item too. This is
                            -- presentation-only; it does not refresh or re-authorize
                            -- the stale cleanup decision.
                            if WGRStorageCleanupNotifyManualOverrideMoved then
                                WGRStorageCleanupNotifyManualOverrideMoved(
                                    entry.oldItem,entry.newItem,entry.old,entry.new)
                            end
                            moved=moved+1
                        end
                        resolvedThisLink=true
                    end
                end
            end
        end
        -- v0.72au: a marked GUID disappearing is evidence of a possible
        -- manual move, but the first post-move bank snapshot can be incomplete
        -- or expose the destination link before its new GUID is readable. Keep
        -- the pre-move snapshot alive and retry instead of advancing the
        -- baseline and permanently losing the exact-copy relationship.
        if not resolvedThisLink then unresolved=true end
    end
    if moved>0 then
        -- v0.72aw: exact-copy reconciliation already updated marks/rows.
        -- Batch the expensive overlay/Recommendations/To Do work at the
        -- trailing edge of a burst of manual moves instead of rebuilding the
        -- UI after every individual drag. The visible Cleanup row has its own
        -- lightweight debounced redraw in GearSearch.lua.
        if WGRStorageCleanupScheduleManualMoveRefresh then
            WGRStorageCleanupScheduleManualMoveRefresh()
        else
            if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
            if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.25) end
            if WGRMailRefreshCurrentTodoSnapshot then
                WGRMailRefreshCurrentTodoSnapshot(true,true)
            elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
            if WGRStorageCleanupRefreshVisibleAudit then
                WGRStorageCleanupRefreshVisibleAudit()
            end
        end
    end
    return moved,unresolved
end

local WGRStorageCleanupManualMovementSnapshot=nil
local WGRStorageCleanupManualMovementPlayer=nil
local WGRStorageCleanupManualMovementSerial=0
local WGRStorageCleanupManualMovementRetryToken=0
local WGRStorageCleanupManualMoveRefreshToken=0
function WGRStorageCleanupScheduleManualMoveRefresh()
    WGRStorageCleanupManualMoveRefreshToken=WGRStorageCleanupManualMoveRefreshToken+1
    local token=WGRStorageCleanupManualMoveRefreshToken
    local function Refresh()
        if token~=WGRStorageCleanupManualMoveRefreshToken then return end
        if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
        -- Gear Finder already has its own trailing-edge debounce. Use a
        -- slightly longer delay here so rapid manual bank moves collapse into
        -- one Recommendations rebuild instead of one rebuild per item.
        if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.20) end
        if WGRMailRefreshCurrentTodoSnapshot then
            WGRMailRefreshCurrentTodoSnapshot(true,true)
        elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
        -- v0.72ax: one final visible Cleanup redraw at the trailing edge of a
        -- burst. Exact-copy reconciliation and mark re-keying have already
        -- finished by this point; this only lets the row/buttons reread their
        -- durable KEEP/DISPOSE state after the destination slot settles.
        if WGRStorageCleanupRefreshVisibleAudit then
            WGRStorageCleanupRefreshVisibleAudit()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.22,Refresh)
    else
        Refresh()
    end
end
function WGRStorageCleanupPrimeManualOverrideMovementSnapshot()
    WGRStorageCleanupManualMovementRetryToken=WGRStorageCleanupManualMovementRetryToken+1
    if not next(WGRStorageCleanupMarkTable()) then
        WGRStorageCleanupManualMovementSnapshot=nil
        WGRStorageCleanupManualMovementPlayer=nil
        return
    end
    local player=(UnitGUID and UnitGUID('player')) or (UnitName and UnitName('player')) or nil
    WGRStorageCleanupManualMovementPlayer=player
    WGRStorageCleanupManualMovementSnapshot=WGRStorageCleanupSnapshotAccessiblePhysical and
        WGRStorageCleanupSnapshotAccessiblePhysical() or nil
end

if type(CreateFrame)=='function' then
    local frame=CreateFrame('Frame')
    for _,event in ipairs({'PLAYER_ENTERING_WORLD','BAG_UPDATE_DELAYED','BANKFRAME_OPENED',
        'BANKFRAME_CLOSED','PLAYERBANKSLOTS_CHANGED'}) do frame:RegisterEvent(event) end
    frame:SetScript('OnEvent',function(_,event)
        WGRStorageCleanupManualMovementSerial=WGRStorageCleanupManualMovementSerial+1
        local serial=WGRStorageCleanupManualMovementSerial
        if event=='PLAYER_ENTERING_WORLD' then
            WGRStorageCleanupManualMovementSnapshot=nil
            WGRStorageCleanupManualMovementPlayer=nil
            WGRStorageCleanupManualMovementRetryToken=WGRStorageCleanupManualMovementRetryToken+1
        end

        local function StoreSnapshot(current,player)
            WGRStorageCleanupManualMovementSnapshot=current
            WGRStorageCleanupManualMovementPlayer=player
        end

        -- v0.72au: manual drag/drop is not controlled by WBGR, so bank APIs
        -- can briefly hide the destination GUID. If an exact persistent mark
        -- disappeared but reconciliation is unresolved, retry against the SAME
        -- pre-move snapshot. Only advance the baseline after the move resolves
        -- or the bounded settle window expires. This is never a link-only guess.
        local retryDelays={0.20,0.50,0.95,1.55}
        local function Retry(before,player,token,attempt)
            if token~=WGRStorageCleanupManualMovementRetryToken then return end
            local livePlayer=(UnitGUID and UnitGUID('player')) or (UnitName and UnitName('player')) or nil
            if livePlayer~=player or not next(WGRStorageCleanupMarkTable()) then return end
            local current=WGRStorageCleanupSnapshotAccessiblePhysical and
                WGRStorageCleanupSnapshotAccessiblePhysical() or nil
            if not current then return end
            local _,unresolved=WGRStorageCleanupReconcileManualOverrideMovement(before,current)
            if unresolved and attempt<#retryDelays and C_Timer and C_Timer.After then
                C_Timer.After(retryDelays[attempt+1],function()
                    Retry(before,player,token,attempt+1)
                end)
                return
            end
            StoreSnapshot(current,player)
        end

        local function Capture()
            if serial~=WGRStorageCleanupManualMovementSerial then return end
            if not next(WGRStorageCleanupMarkTable()) then
                WGRStorageCleanupManualMovementSnapshot=nil
                WGRStorageCleanupManualMovementPlayer=nil
                WGRStorageCleanupManualMovementRetryToken=WGRStorageCleanupManualMovementRetryToken+1
                return
            end
            local player=(UnitGUID and UnitGUID('player')) or (UnitName and UnitName('player')) or nil
            local current=WGRStorageCleanupSnapshotAccessiblePhysical and
                WGRStorageCleanupSnapshotAccessiblePhysical() or nil
            local before=WGRStorageCleanupManualMovementSnapshot
            if current and before and player==WGRStorageCleanupManualMovementPlayer then
                local _,unresolved=WGRStorageCleanupReconcileManualOverrideMovement(before,current)
                if unresolved and C_Timer and C_Timer.After then
                    WGRStorageCleanupManualMovementRetryToken=WGRStorageCleanupManualMovementRetryToken+1
                    local token=WGRStorageCleanupManualMovementRetryToken
                    C_Timer.After(retryDelays[1],function() Retry(before,player,token,1) end)
                    return
                end
            end
            StoreSnapshot(current,player)
        end
        if C_Timer and C_Timer.After then
            -- v0.72aw: BAG_UPDATE_DELAYED has already coalesced the raw bag
            -- events. Start exact-copy reconciliation sooner; the existing
            -- retry window still handles destinations whose GUID is not ready.
            C_Timer.After(event=='PLAYER_ENTERING_WORLD' and 1.8 or 0.25,Capture)
        else Capture() end
    end)
end

-- v0.69c: A staging-generated DISPOSE mark belongs to one physical GUID. Once
-- that GUID is gone after an actual sale/destruction, retaining the saved mark
-- is both UI clutter and overly conservative account-stock evidence. Reconcile
-- ONLY STAGED_VERIFIED_SURPLUS records here; explicit user KEEP/DISPOSE and
-- mail-transfer records remain untouched.
--
-- requireFull=true is used by an explicit Storage Cleanup scan and requires
-- both PBK + WBK open, giving complete current-character storage visibility.
-- requireFull=false is reserved for a live merchant session: only staged marks
-- last observed in Bags are eligible, because a merchant sale can only consume
-- the Bag copy WBGR staged for disposal.
function WGRStorageCleanupPruneMissingStagedDisposeMarks(requireFull)
    if not WGRStorageCleanupGetSettings().enabled then return 0,'Storage Cleanup is OFF' end
    local snapshot=WGRStorageCleanupSnapshotAccessiblePhysical and
        WGRStorageCleanupSnapshotAccessiblePhysical() or nil
    if not snapshot then return 0,'Physical inventory unavailable' end
    if requireFull and not (snapshot.pbk and snapshot.wbk) then
        return 0,'PBK and WBK must both be open'
    end
    local live={}
    for _,item in pairs(snapshot.positions or {}) do
        if item and item.guid then live[tostring(item.guid)]=true end
    end
    local owner=(type(UnitName)=='function' and UnitName('player')) or nil
    if not owner then return 0,'Current character unavailable' end
    local marks=WGRStorageCleanupMarkTable()
    local removed=0
    local changedGroups={}
    local changedAll=false
    for guid,mark in pairs(marks) do
        if type(mark)=='table' and mark.mode=='DISPOSE'
            and mark.reason=='STAGED_VERIFIED_SURPLUS'
            and mark.owner==owner and not live[tostring(guid)] then
            local eligible=requireFull
            if not eligible then
                local bag=tonumber(mark.lastBag)
                eligible=bag~=nil and bag>=0 and bag<=4
            end
            if eligible then
                marks[guid]=nil
                WGRStorageCleanupActiveAutoMarks[guid]=nil
                local group=WGRStorageCleanupApprovalGroup(mark.link)
                if group then changedGroups[group]=true else changedAll=true end
                removed=removed+1
            end
        end
    end
    if removed>0 then
        WGRStorageCleanupInvalidateApprovalGroups(changedGroups,changedAll)
        if WGRMailRefreshCurrentTodoSnapshot then
            WGRMailRefreshCurrentTodoSnapshot(true,true)
        elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
        if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
        if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.1) end
    end
    return removed
end

-- Reconcile completed staged sales promptly instead of waiting for the next
-- full holder audit. BAG_UPDATE_DELAYED is used so the sold slot and buyback
-- transaction have settled. A manually moved bank item cannot be mistaken for
-- a sale here because bank + merchant interaction is not the staging workflow.
if type(CreateFrame)=='function' then
    local WGRStorageCleanupMerchantReconcileFrame=CreateFrame('Frame')
    if WGRStorageCleanupMerchantReconcileFrame and
        WGRStorageCleanupMerchantReconcileFrame.RegisterEvent then
        WGRStorageCleanupMerchantReconcileFrame:RegisterEvent('MERCHANT_SHOW')
        WGRStorageCleanupMerchantReconcileFrame:RegisterEvent('MERCHANT_CLOSED')
        WGRStorageCleanupMerchantReconcileFrame:RegisterEvent('BAG_UPDATE_DELAYED')
        local merchantOpen=false
        local merchantSession=0
        local merchantCleared=0
        local function addReconciled()
            local count=WGRStorageCleanupPruneMissingStagedDisposeMarks(false)
            if count and count>0 then merchantCleared=merchantCleared+count end
        end
        local function printMerchantSummary(session)
            if session~=merchantSession then return end
            addReconciled()
            if merchantCleared>0 then
                print('|cff33ff99WBGR:|r Cleared '..merchantCleared..
                    ' completed staged disposal record(s) during this vendor session.')
            end
            merchantCleared=0
        end
        WGRStorageCleanupMerchantReconcileFrame:SetScript('OnEvent',function(_,event)
            if event=='MERCHANT_SHOW' then
                merchantSession=merchantSession+1
                merchantOpen=true
                merchantCleared=0
                return
            end
            if event=='MERCHANT_CLOSED' then
                local session=merchantSession
                merchantOpen=false
                local function finish() printMerchantSummary(session) end
                if C_Timer and C_Timer.After then C_Timer.After(0.20,finish) else finish() end
                return
            end
            if event~='BAG_UPDATE_DELAYED' or not merchantOpen then return end
            local session=merchantSession
            local function reconcile()
                if not merchantOpen or session~=merchantSession then return end
                addReconciled()
            end
            if C_Timer and C_Timer.After then C_Timer.After(0.20,reconcile) else reconcile() end
        end)
    end
end

-- Saved PBK inventory intentionally has no durable physical GUID. A disposal
-- mark can therefore implicate ONE matching saved physical copy, not every
-- identical copy in that owner's inventory. Count qualifying GUID-keyed marks
-- conservatively: the account allocator withholds up to this many observed
-- copies of the same owner/link; it never chooses WHICH copy is marked.
-- Caller must account for copies across all relevant saved sections once.
function WGRStorageCleanupStockPossibleDisposeCount(stock)
    if type(stock)~='table' then return nil end
    local count=0
    for guid,mark in pairs(WGRStorageCleanupMarkTable()) do
        local sourceMatch=true
        if type(mark)=='table' and WGRStorageCleanupPersistentManualRecord(mark) and mark.lastSource then
            if mark.lastSource=='WARBAND_BANK' then
                sourceMatch=stock.cleanupOwner=='Shared Warbank' and stock.cleanupLocation=='WBK'
            elseif mark.lastSource=='PERSONAL_BANK' then
                sourceMatch=mark.owner==stock.cleanupOwner and stock.cleanupLocation=='PBK'
            elseif mark.lastSource=='BAGS' then
                sourceMatch=mark.owner==stock.cleanupOwner and stock.cleanupLocation=='BAG'
            end
        end
        if type(mark)=='table' and mark.mode=='DISPOSE' and sourceMatch and
            mark.generation==WGRStorageCleanupMarkGeneration() and
            (mark.owner==stock.cleanupOwner or mark.lastSource=='WARBAND_BANK') and mark.link==stock.itemLink then
            if mark.reason~='AUTO_VERIFIED' or
                (WGRStorageCleanupActiveAutoMarks[guid]==mark and
                 mark.approvalGroup and
                 mark.approvedGroupStamp==WGRStorageCleanupApprovalStamp(mark.approvalGroup)) then
                count=count+1
            end
        end
    end
    return count
end

-- Retain the old boolean helper for callers that cannot account for physical
-- saved-copy multiplicity. Such callers must remain conservatively fail-closed.
function WGRStorageCleanupStockPossiblyMarkedDispose(stock)
    local count=WGRStorageCleanupStockPossibleDisposeCount(stock)
    return count==nil or count>0
end

-- Explicit Check Surplus may mark only copies proved redundant using current
-- verified stock in the matching category. Other account-wide gaps are merely
-- warnings and can never be used as proof of an available retained copy.
function WGRStorageCleanupApplyVerifiedAutoMarks(report)
    local result={applied=0,withheld=0,protected=0}
    if type(report)~='table' then return result end
    local possibles=report.possible or {}
    local verified={}
    for _,item in ipairs(report.verifiedPossible or {}) do
        local key=tostring(item.bagID)..':'..tostring(item.slotID)..':'..tostring(item.itemLink)
        verified[key]=true
    end
    -- Only per-group trusted, unallocated physical copies may be marked.
    -- report.provisional is an account-level warning, never an all-or-none
    -- disposal switch. report.blocked applies to relevant groups only.
    for _,candidate in ipairs(possibles) do
        local key=tostring(candidate.bagID)..':'..tostring(candidate.slotID)..':'..tostring(candidate.itemLink)
        local mode=WGRStorageCleanupGetCopyMark(candidate.bagID,candidate.slotID,candidate.itemLink)
        if mode=='KEEP' then
            result.protected=result.protected+1
        elseif mode~='DISPOSE' then
            local currentGUID=WGRStorageCleanupGetPhysicalCopyGUID(
                candidate.bagID,candidate.slotID,candidate.itemLink)
            if verified[key] and candidate.guid and currentGUID==candidate.guid then
                -- WGRStorageCleanupSetCopyMark rechecks exact GUID, current
                -- normal routing and +1-upgrade protection at commit time.
                local ok=WGRStorageCleanupSetCopyMark(candidate.bagID,candidate.slotID,
                    'DISPOSE','AUTO_VERIFIED',true)
                if ok then
                    result.applied=result.applied+1
                    if WGRRefreshCopyOverlay then
                        WGRRefreshCopyOverlay(candidate.bagID,candidate.slotID)
                    end
                else result.withheld=result.withheld+1 end
            else
                result.withheld=result.withheld+1
            end
        end
    end
    if result.applied>0 then
        if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.1) end
        if WGRMailRefreshCurrentTodoSnapshot then WGRMailRefreshCurrentTodoSnapshot(true,true)
        elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
    end
    return result
end

-- Confirmation can occur later than MAIL_SEND_SUCCESS: WoW sometimes still
-- exposes outgoing GUIDs in Bags at that event. Preserve only the previously
-- prepared, exact-GUID DISPOSE entries until the physical departure is visible.
function WGRStorageCleanupValidateOutgoingDisposalMailEntry(entry,sender)
    if type(entry)~='table' or type(entry.guid)~='string' or
        type(entry.itemLink)~='string' or not sender then return false end
    if not WGRStorageCleanupGetSettings().enabled then return false end
    local mark=WGRStorageCleanupMarkTable()[entry.guid]
    return type(mark)=='table' and mark.mode=='DISPOSE' and
        mark.link==entry.itemLink and mark.owner==sender and
        mark.generation==WGRStorageCleanupMarkGeneration()
end

-- Confirm a user-reviewed, explicitly prepared disposal-mail transfer after
-- WoW reports MAIL_SEND_SUCCESS. A false/edited draft MUST NOT call this.
-- Never delete an unrelated copy's mark merely because its link is identical.
function WGRStorageCleanupCompleteDisposalMail(entries,recipient)
    if type(entries)~='table' or #entries==0 or not recipient then return 0 end
    local marks=WGRStorageCleanupMarkTable()
    local completed,changed={},{}
    for _,entry in ipairs(entries) do
        local mark=type(entry)=='table' and marks[entry.guid]
        if mark and mark.mode=='DISPOSE' and mark.link==entry.itemLink and
            mark.owner==(UnitName and UnitName('player')) and
            mark.generation==WGRStorageCleanupMarkGeneration() then
            -- Sent items can no longer occupy their original bag GUID. If
            -- they do, refuse to clear rather than guess what was mailed.
            local present,uncertain=false,false
            if C_Container and C_Container.GetContainerNumSlots and
                C_Container.GetContainerItemLink and
                WGRStorageCleanupGetPhysicalCopyGUID then
                for bag=0,4 do
                    local slots=C_Container.GetContainerNumSlots(bag)
                    if type(slots)~='number' then
                        uncertain=true;break
                    end
                    for slot=1,slots do
                        -- Only identical links need GUID checks. If WoW
                        -- temporarily cannot identify one such copy, it
                        -- could be the outgoing one: fail closed and retry.
                        if C_Container.GetContainerItemLink(bag,slot)==entry.itemLink then
                            local liveGuid=WGRStorageCleanupGetPhysicalCopyGUID(bag,slot,entry.itemLink)
                            if not liveGuid then uncertain=true end
                            if liveGuid==entry.guid then present=true;break end
                        end
                    end
                    if present then break end
                end
            else uncertain=true end
            if not present and not uncertain then
                marks[entry.guid]=nil
                WGRStorageCleanupActiveAutoMarks[entry.guid]=nil
                completed[#completed+1]=entry
                local group=WGRStorageCleanupApprovalGroup(entry.itemLink)
                if group then changed[group]=true end
            end
        end
    end
    if #completed>0 then
        WarboundGearRouterDB.storageCleanupDisposalTransfers=
            WarboundGearRouterDB.storageCleanupDisposalTransfers or {}
        local log=WarboundGearRouterDB.storageCleanupDisposalTransfers
        for _,entry in ipairs(completed) do
            log[#log+1]={itemLink=entry.itemLink,recipient=recipient,
                sentAt=(GetServerTime and GetServerTime()) or (time and time()) or 0}
        end
        while #log>50 do table.remove(log,1) end
        -- v0.68p: a sent item remains pending, not disposed. The persistent
        -- recipient-side ledger exists even when the recipient is Removed.
        if WGRDisposalMailRecordSend then
            WGRDisposalMailRecordSend(completed,recipient,UnitName and UnitName('player'))
        end
        WGRStorageCleanupInvalidateApprovalGroups(changed,not next(changed))
        if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
        if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(.1) end
        if WGRMailRefreshCurrentTodoSnapshot then
            WGRMailRefreshCurrentTodoSnapshot(true,true)
        elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
    end
    -- Second return is the exact set of GUIDs reconciled. The older numeric
    -- return remains unchanged for existing callers and regression tests.
    return #completed,completed
end

-- A verified inbound disposal-mail transfer uses a NEW physical GUID on
-- the receiving character. This does not silently apply marks to other copies
-- with the same link. Removed disposal alts may receive this previously
-- authorized status without joining the active routing roster.
function WGRStorageCleanupAdoptReceivedDisposalCopy(bagID,slotID,expectedLink,reason)
    local guid,link=WGRStorageCleanupCurrentCopy(bagID,slotID,expectedLink)
    if not guid or not link then return false,'Received physical copy unavailable' end
    local marks=WGRStorageCleanupMarkTable()
    local existing=marks[guid]
    if existing and existing.mode=='KEEP' then
        return false,'Physical copy already protected with KEEP'
    end
    if existing and existing.mode=='DISPOSE' and existing.link==link then
        return true
    end
    -- Never suppress an immediate usable upgrade even after a disposal-mail
    -- transfer. Leave the inbound reminder for review instead.
    -- Preserve BOTH return values. Lua's `fn and fn(link)` expression
    -- collapses multiple returns to one, so `status` was always nil and
    -- ordinary non-Removed recipients could never adopt a verified receipt.
    local recommendation,status
    if WGRBuildLoadedItemRecommendation then
        recommendation,status=WGRBuildLoadedItemRecommendation(link)
    end
    local removed=WGRIsCharacterRemoved and
        WGRIsCharacterRemoved(UnitName and UnitName('player'))
    if not removed and (status~='ready' or not recommendation or
        (recommendation.kind~='holder' and recommendation.kind~='sell' and
         recommendation.kind~='no_current_upgrade')) then
        return false,'New recipient has an immediate equipment upgrade or unresolved routing'
    end
    marks[guid]={mode='DISPOSE',link=link,owner=UnitName and UnitName('player'),
        reason=reason or 'RECEIVED_DISPOSAL_MAIL',
        generation=WGRStorageCleanupMarkGeneration(),lastBag=bagID,lastSlot=slotID,
        markedAt=(GetServerTime and GetServerTime()) or (time and time()) or 0}
    if WGRRefreshCopyOverlay then WGRRefreshCopyOverlay(bagID,slotID) end
    if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(.1) end
    return true
end

-- Shared wording for all WBGR physical-copy tooltip surfaces.
function WGRStorageCleanupDisposeReasonLabel(mark)
    local reason=mark and mark.reason
    if reason=='AUTO_VERIFIED' then return 'Verified Surplus' end
    if reason=='STAGED_VERIFIED_SURPLUS' then return 'Verified Staged Surplus' end
    if reason=='MANUAL_DISPOSAL_MAIL_RECOVERY' then return 'Mail Recovery' end
    if reason=='RECEIVED_DISPOSAL_MAIL' or reason=='RETURNED_DISPOSAL_MAIL' then
        return 'Received via Mail'
    end
    return 'Manual Override'
end

-- The To Do display uses live accessible slots for current character only.
-- Unknown/offline inventories are never assumed empty.
function WGRStorageCleanupCountCurrentMarked(source)
    if not WGRStorageCleanupGetSettings().enabled then return 0 end
    if not next(WGRStorageCleanupMarkTable()) then return 0 end
    local ids={}
    if source=='BAGS' then
        for bag=0,4 do ids[#ids+1]=bag end
    elseif source=='PERSONAL_BANK' then
        if not (WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen()) then return 0 end
        if WGRStorageCleanupPersonalBankTabIDs then
            ids=WGRStorageCleanupPersonalBankTabIDs() or {}
        else
            -- No guess about PBK bag indices when the adapter is unavailable.
            return 0
        end
    end
    local count=0
    local guids={}
    for _,bag in ipairs(ids) do
        local slots=C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
        for slot=1,slots do
            local link=C_Container and C_Container.GetContainerItemLink and
                C_Container.GetContainerItemLink(bag,slot)
            -- Existing global Ignore is an intentional exclusion from WBGR's
            -- action reminders; it never clears the GUID-specific DISPOSE mark.
            if link and WGRStorageCleanupIsDisposeCopy(bag,slot,link) and
                not (WGRItemIsIgnored and WGRItemIsIgnored(link)) then
                count=count+1
                -- Build a physical-copy signature for dismissal identity,
                -- not a link-only/slot-only summary.  Never use it to decide
                -- routing or physical disposal.
                local guid=WGRStorageCleanupGetPhysicalCopyGUID and
                    WGRStorageCleanupGetPhysicalCopyGUID(bag,slot)
                if guid then guids[#guids+1]=guid end
            end
        end
    end
    table.sort(guids)
    local hash=5381
    for _,guid in ipairs(guids) do
        for i=1,#guid do
            hash=(hash*33+guid:byte(i))%2147483647
        end
        hash=(hash*33+124)%2147483647
    end
    return count,tostring(count)..'-'..tostring(hash)
end

-- v0.69a: Retention quality tie-breaker. Item level remains absolute: these
-- properties are consulted ONLY when two physical copies have the same ilvl.
-- We intentionally use current Retail concepts only: total sockets, Leech,
-- Speed, Avoidance, and Indestructible. Blizzard's internal stat tokens for
-- current Leech/Indestructible retain historical names (LIFESTEAL/STURDINESS);
-- those tokens are API implementation details, not support for old mechanics.
--
-- Total sockets are compared generically rather than special-casing jewelry.
-- If every ring/neck has the same natural socket count, that field simply ties
-- and the tertiary hierarchy decides. If a future expansion changes that, the
-- same logic automatically favors the socketed copy.
local WGRStorageCleanupRetentionProfileCache={}
local WGRStorageCleanupRetentionStatKeys={
    leech={'ITEM_MOD_CR_LIFESTEAL_SHORT','ITEM_MOD_LEECH_RATING_SHORT','ITEM_MOD_LEECH_SHORT'},
    speed={'ITEM_MOD_CR_SPEED_SHORT','ITEM_MOD_SPEED_RATING_SHORT','ITEM_MOD_SPEED_SHORT'},
    avoidance={'ITEM_MOD_CR_AVOIDANCE_SHORT','ITEM_MOD_AVOIDANCE_RATING_SHORT','ITEM_MOD_AVOIDANCE_SHORT'},
    indestructible={'ITEM_MOD_CR_STURDINESS_SHORT','ITEM_MOD_INDESTRUCTIBLE_SHORT'},
}

local function WGRStorageCleanupPositiveStat(stats,keys)
    if type(stats)~='table' then return false end
    for _,key in ipairs(keys or {}) do
        if tonumber(stats[key]) and tonumber(stats[key])>0 then return true end
    end
    return false
end

function WGRStorageCleanupGetRetentionBonusProfile(itemOrLink)
    local item=type(itemOrLink)=='table' and itemOrLink or nil
    local link=tostring(item and item.itemLink or itemOrLink or '')
    if link=='' then
        return {known=false,sockets=0,leech=false,speed=false,avoidance=false,indestructible=false}
    end
    if item and type(item.cleanupRetentionBonusProfile)=='table'
        and item.cleanupRetentionBonusProfileLink==link then
        return item.cleanupRetentionBonusProfile
    end
    -- Persisted observations let closed-bank/account snapshots retain the exact
    -- physical-copy bonus facts even if Blizzard item data is temporarily cold.
    if item and item.retentionBonusKnown==true then
        local profile={known=true,sockets=tonumber(item.retentionSockets) or 0,
            leech=item.retentionLeech==true,speed=item.retentionSpeed==true,
            avoidance=item.retentionAvoidance==true,
            indestructible=item.retentionIndestructible==true}
        item.cleanupRetentionBonusProfile=profile
        item.cleanupRetentionBonusProfileLink=link
        return profile
    end
    local cached=WGRStorageCleanupRetentionProfileCache[link]
    if cached and cached.known then
        if item then
            item.cleanupRetentionBonusProfile=cached
            item.cleanupRetentionBonusProfileLink=link
        end
        return cached
    end
    local sockets,stats
    if C_Item and type(C_Item.GetItemNumSockets)=='function' then
        local ok,value=pcall(C_Item.GetItemNumSockets,link)
        if ok then sockets=tonumber(value) end
    end
    if C_Item and type(C_Item.GetItemStats)=='function' then
        local ok,value=pcall(C_Item.GetItemStats,link)
        if ok and type(value)=='table' then stats=value end
    end
    local profile={
        known=sockets~=nil and type(stats)=='table',
        sockets=tonumber(sockets) or 0,
        leech=WGRStorageCleanupPositiveStat(stats,WGRStorageCleanupRetentionStatKeys.leech),
        speed=WGRStorageCleanupPositiveStat(stats,WGRStorageCleanupRetentionStatKeys.speed),
        avoidance=WGRStorageCleanupPositiveStat(stats,WGRStorageCleanupRetentionStatKeys.avoidance),
        indestructible=WGRStorageCleanupPositiveStat(stats,WGRStorageCleanupRetentionStatKeys.indestructible),
    }
    -- Cache only complete facts. A cold/uncached API result must be retried on
    -- the next scan rather than turning a temporary nil into a durable plain item.
    if profile.known then WGRStorageCleanupRetentionProfileCache[link]=profile end
    if item then
        item.cleanupRetentionBonusProfile=profile
        item.cleanupRetentionBonusProfileLink=link
    end
    return profile
end

function WGRStorageCleanupRetentionBonusSummary(itemOrLink)
    local p=WGRStorageCleanupGetRetentionBonusProfile(itemOrLink)
    if not p.known then return nil,'Bonus data unavailable' end
    local out={}
    if (tonumber(p.sockets) or 0)>0 then
        out[#out+1]=(p.sockets==1 and '1 Socket' or (tostring(p.sockets)..' Sockets'))
    end
    if p.leech then out[#out+1]='Leech' end
    if p.speed then out[#out+1]='Speed' end
    if p.avoidance then out[#out+1]='Avoidance' end
    if p.indestructible then out[#out+1]='Indestructible' end
    return #out>0 and table.concat(out,', ') or 'None',nil
end

local function WGRStorageCleanupRetentionBetter(a,b)
    local ap,bp=WGRStorageCleanupGetRetentionBonusProfile(a),WGRStorageCleanupGetRetentionBonusProfile(b)
    -- Complete profiles sort ahead for determinism; an unknown profile that
    -- crosses the actual KEEP/SURPLUS boundary is protected below.
    if ap.known~=bp.known then return ap.known end
    if ap.known then
        local as,bs=tonumber(ap.sockets) or 0,tonumber(bp.sockets) or 0
        if as~=bs then return as>bs end
        for _,key in ipairs({'leech','speed','avoidance','indestructible'}) do
            if ap[key]~=bp[key] then return ap[key]==true end
        end
    end
    return nil
end

-- Storage Cleanup retention planner. This is NOT a routing or movement engine.
-- One demand represents a character/category or character/routed-spec. Demands
-- arrive in the saved Roster order. The first eligible demand always selects
-- the best available physical item. Required-level tiers are considered
-- independently, but a lower-tier item only remains useful until replaced by
-- something strictly better at a later tier. No arbitrary ilvl threshold.
--
-- demand: {name,level,owned={...},capacity?,specID?}
-- item:   {itemLevel,minLevel,cleanupCandidates={...},
--          cleanupSpecCandidates={[name]={[specID]=true}},cleanupUniqueKey?}
-- Spec matches and ring/trinket unique restrictions come from GearSearch's
-- read-only eligibility/tooltip analysis; uncertain cases are REVIEW there.
function WGRStorageCleanupPlanGroup(records, demands, defaultCapacity, cooperate, noCrossDemandSharing)
    local ordered,levels,seenLevels={}, {}, {}
    for _,item in ipairs(records or {}) do
        if cooperate then cooperate() end
        ordered[#ordered+1]=item
        local level=tonumber(item.minLevel) or 0
        if not seenLevels[level] then
            levels[#levels+1]=level
            seenLevels[level]=true
        end
    end
    table.sort(ordered,function(a,b)
        local al,bl=tonumber(a.itemLevel) or 0,tonumber(b.itemLevel) or 0
        if al~=bl then return al>bl end
        -- Equal-ilvl retention hierarchy: Socket > Leech > Speed > Avoidance
        -- > Indestructible. The helper compares total socket count, so natural
        -- jewelry sockets cancel automatically when every copy has them.
        local better=WGRStorageCleanupRetentionBetter(a,b)
        if better~=nil then return better end
        -- Prefer an existing holder PBK copy over WBK ONLY for the same item
        -- ID, ilvl and retention-bonus tier. Different itemLinks can represent
        -- the same underlying item with different instance/bonus encodings;
        -- ordering links first made the v0.72w preference unreachable in live
        -- equal-gear cases. Across distinct item IDs, keep the original link
        -- ordering: no change to which different gear piece has priority.
        local function physicalItemID(item)
            local explicit=tonumber(item.itemID)
            if explicit and explicit>0 then return explicit end
            local link=tostring(item.itemLink or '')
            return tonumber(link:match('item:(%d+)'))
        end
        local aid,bid=physicalItemID(a),physicalItemID(b)
        if aid and bid and aid==bid then
            local ap,bp=WGRStorageCleanupGetRetentionBonusProfile(a),
                        WGRStorageCleanupGetRetentionBonusProfile(b)
            local sameBonus=ap.known and bp.known and
                (tonumber(ap.sockets) or 0)==(tonumber(bp.sockets) or 0) and
                ap.leech==bp.leech and ap.speed==bp.speed and
                ap.avoidance==bp.avoidance and
                ap.indestructible==bp.indestructible
            if sameBonus then
                local function holderPBK(item)
                    return item.cleanupLocation=='PBK'
                        and item.cleanupOwner~=nil
                        and tostring(item.cleanupOwner)~=''
                        and tostring(item.cleanupOwner)~='Shared Warbank'
                end
                local ah,bh=holderPBK(a),holderPBK(b)
                if ah~=bh then return ah end
            end
        end
        local an,bn=tostring(a.itemLink or a.itemName or ''),tostring(b.itemLink or b.itemName or '')
        if an~=bn then return an<bn end
        -- Same-link fallback (v0.72w): holder-local PBK before WBK, even when
        -- item-ID extraction is unavailable, retaining legacy test semantics.
        local function existingHolderStock(item)
            return item.cleanupLocation=='PBK'
                and item.cleanupOwner~=nil
                and tostring(item.cleanupOwner)~=''
                and tostring(item.cleanupOwner)~='Shared Warbank'
        end
        local ah,bh=existingHolderStock(a),existingHolderStock(b)
        if ah~=bh then return ah end
        if a.bagID~=b.bagID then return (tonumber(a.bagID) or 0)<(tonumber(b.bagID) or 0) end
        return (tonumber(a.slotID) or 0)<(tonumber(b.slotID) or 0)
    end)
    table.sort(levels)

    local reserved,assigned={},{}
    local byName={}  -- physical items allocated to a character, shared across specs
    local floors={}
    for i,d in ipairs(demands or {}) do
        local key=i
        floors[key]={}
        local capacity=tonumber(d.capacity) or tonumber(defaultCapacity) or 1
        for slot=1,capacity do floors[key][slot]=tonumber((d.owned or {})[slot]) or 0 end
    end
    local function eligible(item,d)
        local compatible=false
        for _,name in ipairs(item.cleanupCandidates or {}) do
            if name==d.name then compatible=true;break end
        end
        if not compatible then return false end
        if d.eligibleSpecIDs then
            local matched=false
            for specID in pairs(d.eligibleSpecIDs) do
                if item.cleanupSpecCandidates and item.cleanupSpecCandidates[d.name]
                    and item.cleanupSpecCandidates[d.name][specID] then
                    matched=true;break
                end
            end
            if not matched then return false end
        elseif d.specID and not (item.cleanupSpecCandidates
            and item.cleanupSpecCandidates[d.name]
            and item.cleanupSpecCandidates[d.name][d.specID]) then return false end
        return true
    end
    local function legal(item,list)
        if not item.cleanupUniqueKey then return true end
        for _,previous in ipairs(list or {}) do
            if previous~=item and previous.cleanupUniqueKey==item.cleanupUniqueKey then
                return false
            end
        end
        return true
    end
    for _,level in ipairs(levels) do
        if cooperate then cooperate() end
        -- The order here is intentional: roster priority before spec/slot.
        for demandIndex,d in ipairs(demands or {}) do
            if cooperate then cooperate() end
            -- Restrictions apply to a simultaneously equipped pair, not to
            -- a future upgrade held for a different level milestone.
            floors[demandIndex]._selected={}
            floors[demandIndex]._used={}
            local charLevel=tonumber(d.level) or 0
            local capacity=tonumber(d.capacity) or tonumber(defaultCapacity) or 1
            local charItems=byName[d.name] or {}
            byName[d.name]=charItems
            -- Existing reservations for this character may also satisfy
            -- another routed spec: do not reserve duplicate physical copies.
            local specItems={}
            for _,other in ipairs(charItems) do
                if not noCrossDemandSharing and eligible(other,d)
                    and (tonumber(other.minLevel) or 0)<=level then
                    specItems[#specItems+1]=other
                end
            end
            for slot=1,capacity do
                local floor=floors[demandIndex][slot]
                -- A previously allocated item may fill this spec's slot,
                -- even if it was chosen while evaluating another spec.
                local shared=nil
                for _,other in ipairs(specItems) do
                    local used=false
                    for _,value in pairs(floors[demandIndex]._used or {}) do
                        if value==other then used=true;break end
                    end
                    if not used and (tonumber(other.itemLevel) or 0)>floor
                        and legal(other,floors[demandIndex]._selected or {}) then
                        if not shared or other.itemLevel>shared.itemLevel then shared=other end
                    end
                end
                if shared then
                    floors[demandIndex]._used=floors[demandIndex]._used or {}
                    floors[demandIndex]._selected=floors[demandIndex]._selected or {}
                    floors[demandIndex]._used[slot]=shared
                    floors[demandIndex]._selected[slot]=shared
                    floors[demandIndex][slot]=tonumber(shared.itemLevel) or 0
                    floor=floors[demandIndex][slot]
                end
                local winner=nil
                for ix,item in ipairs(ordered) do
                    if cooperate and ix%8==0 then cooperate() end
                    if not reserved[item] and (tonumber(item.minLevel) or 0)==level
                        and eligible(item,d)
                        and (tonumber(item.itemLevel) or 0)>floor
                        and legal(item,floors[demandIndex]._selected or {}) then
                        winner=item
                        break
                    end
                end
                if winner then
                    reserved[winner]=true
                    assigned[winner]={name=d.name,level=math.max(level,charLevel),specID=d.specID,
                        retentionRole=d.retentionRole}
                    charItems[#charItems+1]=winner
                    floors[demandIndex][slot]=tonumber(winner.itemLevel) or 0
                    floors[demandIndex]._selected=floors[demandIndex]._selected or {}
                    floors[demandIndex]._selected[slot]=winner
                    floors[demandIndex]._used=floors[demandIndex]._used or {}
                    floors[demandIndex]._used[slot]=winner
                end
            end
        end
    end
    -- If Blizzard could not provide bonus facts for one member of an equal-ilvl
    -- tie, never let that uncertainty decide which physical copy is disposable.
    -- Only a tie that actually straddles the KEEP/SURPLUS boundary is protected;
    -- lower-ilvl stock that is wholly obsolete remains safely surplus.
    local byItemLevel={}
    for _,item in ipairs(ordered) do
        local ilvl=tonumber(item.itemLevel) or 0
        local bucket=byItemLevel[ilvl]
        if not bucket then bucket={items={},unknown=false,kept=0,unkept=0};byItemLevel[ilvl]=bucket end
        bucket.items[#bucket.items+1]=item
        if not WGRStorageCleanupGetRetentionBonusProfile(item).known then bucket.unknown=true end
        if reserved[item] then bucket.kept=bucket.kept+1 else bucket.unkept=bucket.unkept+1 end
    end
    local bonusProtected={}
    for _,bucket in pairs(byItemLevel) do
        if bucket.unknown and bucket.kept>0 and bucket.unkept>0 then
            for _,item in ipairs(bucket.items) do
                if not reserved[item] then
                    reserved[item]=true
                    bonusProtected[item]=true
                end
            end
        end
    end
    return reserved,assigned,bonusProtected
end


-- ============================================================
-- Optional detailed inventory snapshots (v0.67q, automatically observed).
--
-- These records are observations, NOT routing allocations or disposal flags.
-- Passive updates never re-run the retention planner or change a frozen batch.
-- Never consume them in the routing engine or the KEEP/SURPLUS planner.
-- The current character's bags are observable at any time; PBK and WBK
-- are updated only while the corresponding bank is genuinely accessible.
-- In particular, a closed bank must never be written as an empty bank.
-- ============================================================
local function WGRStorageCleanupSnapshotTime()
    if type(GetServerTime) == 'function' then return GetServerTime() end
    if type(time) == 'function' then return time() end
    return nil
end

local function WGRStorageCleanupSnapshotIdentity()
    local name = (type(UnitName)=='function' and UnitName('player')) or 'Unknown'
    local realm = (type(GetNormalizedRealmName)=='function' and GetNormalizedRealmName())
        or (type(GetRealmName)=='function' and GetRealmName()) or ''
    local guid = type(UnitGUID)=='function' and UnitGUID('player') or nil
    -- The GUID is more robust than a character's name after renaming or transfer.
    local key = guid or (tostring(name)..'-'..tostring(realm))
    return key,name,realm,guid
end

-- Session-only physical-identity evidence for BAG observations. Do NOT save
-- GUIDs in the historical snapshot schema: a saved last-seen position is not
-- evidence that a physical copy still occupies that position after relog.
-- Weak section keys let old observations be collected when superseded.
local WGRStorageCleanupBagSnapshotIdentities=setmetatable({},{__mode='k'})
local function WGRStorageCleanupCaptureBagIdentities(section)
    local groups={}
    local seenGUID={}
    for _,item in ipairs(section.items or {}) do
        local group=type(item.equipLoc)=='string' and item.equipLoc~='' and item.equipLoc or nil
        if group then
            local record=groups[group]
            if not record then record={valid=true,bySlot={}};groups[group]=record end
            -- Verify the live item link as well as the physical WoW GUID.
            -- A missing or duplicate GUID cannot establish a safe relocation.
            local guid=WGRStorageCleanupCurrentCopy(item.bagID,item.slotID,item.itemLink)
            if not guid then
                record.valid=false
            else
                local slot=tostring(item.bagID)..':'..tostring(item.slotID)
                if seenGUID[guid] or record.bySlot[slot] then
                    record.valid=false
                    if seenGUID[guid] then seenGUID[guid].valid=false end
                end
                seenGUID[guid]=record
                record.bySlot[slot]=guid
            end
        end
    end
    WGRStorageCleanupBagSnapshotIdentities[section]=groups
end

local function WGRStorageCleanupSnapshotSection(records,classification,location,scannedAt)
    local entries={}
    local complete=true
    for _,item in ipairs(records or {}) do
        if item.location == location then
            local link=tostring(item.itemLink or '')
            local name,_,_,_,required,_,_,_,equipLoc
            if C_Item and type(C_Item.GetItemInfo)=='function' then
                name,_,_,_,required,_,_,_,equipLoc=C_Item.GetItemInfo(link)
            end
            local ilvl=tonumber(item.itemLevel)
            if not ilvl and type(GetItemLevel)=='function' then ilvl=tonumber(GetItemLevel(link)) end
            if not ilvl or ilvl<=0 or not name then complete=false end
            local retention=WGRStorageCleanupGetRetentionBonusProfile(item)
            entries[#entries+1]={
                itemLink=link,
                itemID=tonumber(link:match('item:(%d+)')),
                itemName=tostring(item.itemName or name or link),
                itemLevel=ilvl or 0,
                requiredLevel=tonumber(item.minLevel) or tonumber(required) or 0,
                binding=item.binding or 'UNKNOWN',
                category=tostring(item.cleanupGroupLabel or equipLoc or 'Other'),
                equipLoc=equipLoc or '',
                location=location,
                bagID=item.bagID,
                slotID=item.slotID,
                retentionBonusKnown=retention.known==true,
                retentionSockets=tonumber(retention.sockets) or 0,
                retentionLeech=retention.leech==true,
                retentionSpeed=retention.speed==true,
                retentionAvoidance=retention.avoidance==true,
                retentionIndestructible=retention.indestructible==true,
                lastAudit=classification[item] or 'OBSERVED',
                -- v0.71d: Display-only explanation from the latest explicit
                -- Cleanup classification. This is presentation metadata only;
                -- it is never consumed by routing, retention, or disposal proof.
                retentionReason=(classification[item]=='KEEP' and
                    type(item.cleanupReason)=='string' and item.cleanupReason~='')
                    and item.cleanupReason or nil,
            }
        end
    end
    table.sort(entries,function(a,b)
        if a.category~=b.category then return a.category<b.category end
        if a.itemLevel~=b.itemLevel then return a.itemLevel>b.itemLevel end
        if a.itemLink~=b.itemLink then return a.itemLink<b.itemLink end
        if a.bagID~=b.bagID then return (a.bagID or 0)<(b.bagID or 0) end
        return (a.slotID or 0)<(b.slotID or 0)
    end)
    local section={items=entries,scannedAt=scannedAt,complete=complete}
    -- Only BAG-to-BAG movements get this exemption. Transfers across BAG,
    -- PBK and WBK remain real source changes and use the old conservative path.
    if location=='BAG' then WGRStorageCleanupCaptureBagIdentities(section) end
    return section
end

-- Ephemeral revision for presentation caches. This is not SavedVariables
-- schema and has no effect on routing or retention decisions.
local WGRStorageCleanupInventoryRevision=0
function WGRStorageCleanupGetInventoryRevision()
    return WGRStorageCleanupInventoryRevision
end

-- Removed Roster characters are outside WBGR, including Cleanup's
-- personal inventory history. This helper uses the SAME Roster membership
-- authority as the normal router, not level or ignored status.
local function WGRStorageCleanupIsRemoved(name)
    return type(name)=='string' and name~=''
        and WGRIsCharacterRemoved and WGRIsCharacterRemoved(name)==true
end

local WGRStorageCleanupPrunedOnLoad=false
local function WGRStorageCleanupForgetRemoved(name)
    local db=WarboundGearRouterDB
    local saved=db and db.storageCleanupInventory
    if type(saved)~='table' or type(saved.characters)~='table' then return false end
    local changed=false
    for key,record in pairs(saved.characters) do
        if type(record)=='table' and type(record.name)=='string'
            and (name==nil or string.lower(record.name)==string.lower(name))
            and WGRStorageCleanupIsRemoved(record.name) then
            saved.characters[key]=nil
            changed=true
        end
    end
    if changed then
        WGRStorageCleanupInventoryRevision=WGRStorageCleanupInventoryRevision+1
    end
    return changed
end

-- Called by the Roster's Remove action; also prune any legacy historical
-- observations the first time snapshots are read after login.
function WGRStorageCleanupForgetRemovedCharacter(name)
    return WGRStorageCleanupForgetRemoved(name)
end

function WGRStorageCleanupGetInventorySnapshots()
    local db=WarboundGearRouterDB
    local snapshots=db and db.storageCleanupInventory
    if type(snapshots)~='table' then return nil end
    if not WGRStorageCleanupPrunedOnLoad then
        WGRStorageCleanupPrunedOnLoad=true
        WGRStorageCleanupForgetRemoved(nil)
    end
    return snapshots
end

-- v0.68f: A complete last-known observation does not expire with age.
-- Monitoring interruptions affect confidence for a future disposal decision,
-- but do NOT turn hundreds of otherwise usable records into item-level REVIEW.
-- Old v0.68e observations have no generation: treat them as provisional, never
-- silently claim they were observed through uninterrupted monitoring.
local function WGRStorageCleanupEnsureMonitoring()
    local db=WarboundGearRouterDB
    if type(db.storageCleanupInventory)~='table' then
        db.storageCleanupInventory={schemaVersion=1,characters={}}
    end
    local saved=db.storageCleanupInventory
    if type(saved.characters)~='table' then saved.characters={} end
    if type(saved.monitoring)~='table' then
        saved.monitoring={generation=0,
            enabled=WGRStorageCleanupGetSettings().enabled == true}
    end
    local monitor=saved.monitoring
    monitor.generation=math.max(0,math.floor(tonumber(monitor.generation) or 0))
    -- v0.72n: old builds used one generation for both saved-inventory trust
    -- and DISPOSE-mark lifetime. Preserve the current mark state on migration,
    -- then advance markGeneration independently on every OFF transition.
    if monitor.markGeneration==nil then monitor.markGeneration=monitor.generation end
    monitor.markGeneration=math.max(0,math.floor(tonumber(monitor.markGeneration) or monitor.generation))
    monitor.resumePolicyVersion=math.max(0,math.floor(tonumber(monitor.resumePolicyVersion) or 0))
    return saved,monitor
end

local WGR_STORAGE_CLEANUP_RESUME_POLICY_VERSION=1

function WGRStorageCleanupNeedsResumePolicyMigration()
    local saved,monitor=WGRStorageCleanupEnsureMonitoring()
    return (tonumber(monitor.resumePolicyVersion) or 0)<WGR_STORAGE_CLEANUP_RESUME_POLICY_VERSION
end

local function WGRStorageCleanupForEachSavedSection(callback)
    local saved=WGRStorageCleanupGetInventorySnapshots and WGRStorageCleanupGetInventorySnapshots()
    if type(saved)~='table' or type(callback)~='function' then return end
    for _,char in pairs(saved.characters or {}) do
        local sections=type(char)=='table' and char.sections
        if type(sections)=='table' then
            callback(sections.BAG,char,'BAG')
            callback(sections.PBK,char,'PBK')
        end
    end
    callback(saved.warbank,nil,'WBK')
end

-- One-time v0.72n recovery: older builds could make an otherwise valid saved
-- section provisional solely because the master toggle advanced the inventory
-- generation. Numeric trackingGeneration means WBGR really observed that
-- section under the modern tracker; legacy/unknown sections have no generation
-- and are intentionally never promoted by this recovery.
function WGRStorageCleanupHasRecoverableToggleProvisionalData()
    local saved,monitor=WGRStorageCleanupEnsureMonitoring()
    if (tonumber(monitor.resumePolicyVersion) or 0)>=WGR_STORAGE_CLEANUP_RESUME_POLICY_VERSION then
        return false
    end
    local current=monitor.generation
    local found=false
    WGRStorageCleanupForEachSavedSection(function(section)
        if found or type(section)~='table' then return end
        local generation=tonumber(section.trackingGeneration)
        if generation~=nil and generation~=current then found=true end
    end)
    return found
end

function WGRStorageCleanupResolveOldToggleVerification(useExisting)
    local saved,monitor=WGRStorageCleanupEnsureMonitoring()
    local promoted=0
    if useExisting==true then
        local current=monitor.generation
        WGRStorageCleanupForEachSavedSection(function(section)
            if type(section)~='table' then return end
            local generation=tonumber(section.trackingGeneration)
            if generation~=nil and generation~=current then
                section.trackingGeneration=current
                promoted=promoted+1
            end
        end)
        if promoted>0 then
            WGRStorageCleanupInventoryRevision=WGRStorageCleanupInventoryRevision+1
        end
    end
    monitor.resumePolicyVersion=WGR_STORAGE_CLEANUP_RESUME_POLICY_VERSION
    return promoted
end

-- v0.72n: turning Storage Cleanup OFF is now a pause, not an automatic loss
-- of saved-inventory confidence. On re-enable the UI asks the user whether to
-- keep the existing data or check everything again. Only CHECK_AGAIN advances
-- the inventory generation. DISPOSE/automatic marks remain fail-closed across
-- every OFF interval through the separate markGeneration above.
function WGRStorageCleanupSetEnabled(enabled,resumeMode)
    local settings=WGRStorageCleanupGetSettings()
    enabled=enabled == true
    local saved,monitor=WGRStorageCleanupEnsureMonitoring()
    if settings.enabled==enabled then return false end
    if not enabled then
        settings.enabled=false
        monitor.enabled=false
        monitor.resumeChoiceRequired=true
        monitor.markGeneration=monitor.markGeneration+1
        monitor.lastInterruptedAt=WGRStorageCleanupSnapshotTime()
        monitor.interruptions=(tonumber(monitor.interruptions) or 0)+1
        WGRStorageCleanupInventoryRevision=WGRStorageCleanupInventoryRevision+1
        WGRStorageCleanupInvalidateApprovalGroups(nil,true)
        return true,'PAUSED'
    end

    -- Programmatic callers that do not provide the UI choice fail closed and
    -- preserve the old conservative behavior. The normal checkbox always passes
    -- an explicit mode after the user answers the popup.
    if resumeMode~='USE_EXISTING' and resumeMode~='CHECK_AGAIN' then
        resumeMode='CHECK_AGAIN'
    end
    if resumeMode=='CHECK_AGAIN' then
        monitor.generation=monitor.generation+1
    end
    settings.enabled=true
    monitor.enabled=true
    monitor.resumeChoiceRequired=false
    monitor.lastResumedAt=WGRStorageCleanupSnapshotTime()
    WGRStorageCleanupInventoryRevision=WGRStorageCleanupInventoryRevision+1
    return true,resumeMode
end

-- Compare PHYSICAL evidence, not UI classifications or scan timestamps.
-- This does not rely on third-party bag button metadata. The same records are
-- used for explicit scans and passive observations, so a re-audit of unchanged
-- gear cannot accidentally expire an automatic approval.
local function WGRStorageCleanupChangedSection(previous,current,groups)
    if type(previous)~='table' then return true,true end
    if previous.complete~=current.complete or
        previous.trackingGeneration~=current.trackingGeneration then
        return true,true
    end
    local oldIDs=WGRStorageCleanupBagSnapshotIdentities[previous]
    local newIDs=WGRStorageCleanupBagSnapshotIdentities[current]
    local trusted={}
    if oldIDs and newIDs then
        for group,prior in pairs(oldIDs) do
            local nextGroup=newIDs[group]
            if prior.valid and nextGroup and nextGroup.valid then
                trusted[group]=true
            end
        end
    end
    local function fingerprint(item,ids)
        local group=item.equipLoc
        local slot=tostring(item.bagID)..':'..tostring(item.slotID)
        local guid=trusted[group] and ids and ids[group] and ids[group].bySlot[slot]
        -- A trustworthy physical GUID, not a Bag slot, identifies a copy.
        -- Link, level and binding STILL participate in the comparison, so
        -- changed properties cannot silently reuse old approval confidence.
        local identity=guid and ('GUID:'..guid) or ('SLOT:'..slot)
        return table.concat({identity,tostring(item.itemLink or ''),
            tostring(item.itemLevel or ''),tostring(item.requiredLevel or ''),
            tostring(item.binding or ''),tostring(item.equipLoc or '')},'|')
    end
    local old={}
    for _,item in ipairs(previous.items or {}) do
        local key=fingerprint(item,oldIDs);old[key]=(old[key] or 0)+1
    end
    local changed=false
    local global=false
    local function record(item)
        local group=type(item.equipLoc)=='string' and item.equipLoc~='' and item.equipLoc or nil
        if group then groups[group]=true else global=true end
    end
    for _,item in ipairs(current.items or {}) do
        local key=fingerprint(item,newIDs)
        if old[key] and old[key]>0 then old[key]=old[key]-1
        else changed=true;record(item) end
    end
    for _,item in ipairs(previous.items or {}) do
        local key=fingerprint(item,oldIDs)
        if old[key] and old[key]>0 then
            old[key]=old[key]-1;changed=true;record(item)
        end
    end
    -- If reliable category GUID evidence disappears, fail closed even if the
    -- slot/link display appears identical (it may now be a different copy).
    -- Categories with no session identity baseline retain the original
    -- location-sensitive comparison above, never a link-only move inference.
    if oldIDs and newIDs then
        for group,prior in pairs(oldIDs) do
            local later=newIDs[group]
            if (not prior.valid or not later or not later.valid) and
                (later or prior) then
                changed=true;groups[group]=true
            end
        end
        for group,later in pairs(newIDs) do
            if not oldIDs[group] and not later.valid then
                changed=true;groups[group]=true
            end
        end
    end
    return changed,global
end

-- Both explicit audits and passive event observations write physical inventory
-- only. Only an explicit audit supplies historical KEEP/SURPLUS labels.
local function WGRStorageCleanupWriteObservedSnapshot(records,pbkOpen,wbkOpen,classification)
    if not WGRStorageCleanupGetSettings().enabled then return end
    -- A Removed alt cannot recreate records even through an explicit scan.
    if WGRStorageCleanupIsRemoved((type(UnitName)=='function' and UnitName('player')) or nil) then return end
    local saved,monitor=WGRStorageCleanupEnsureMonitoring()
    saved.schemaVersion=1
    local key,name,realm,guid=WGRStorageCleanupSnapshotIdentity()
    local char=saved.characters[key]
    if type(char)~='table' then char={sections={}};saved.characters[key]=char end
    if type(char.sections)~='table' then char.sections={} end
    char.name=name;char.realm=realm;char.guid=guid
    local stamp=WGRStorageCleanupSnapshotTime()
    char.lastSeen=stamp
    local explicitClassification=classification~=nil
    classification=classification or {}
    local changedGroups={}
    local changedAll=false
    local function observe(location,previous)
        local section=WGRStorageCleanupSnapshotSection(records,classification,location,stamp)
        -- Passive observations update physical presence only. Preserve the
        -- latest explicit retention explanation while the same link remains in
        -- the same observed physical position; movements naturally drop it
        -- until the next explicit Cleanup scan/account check.
        if not explicitClassification and type(previous)=='table' then
            local old={}
            for _,entry in ipairs(previous.items or {}) do
                local k=tostring(entry.bagID)..'\031'..tostring(entry.slotID)..'\031'..tostring(entry.itemLink)
                if entry.retentionReason then old[k]=entry.retentionReason end
            end
            for _,entry in ipairs(section.items or {}) do
                local k=tostring(entry.bagID)..'\031'..tostring(entry.slotID)..'\031'..tostring(entry.itemLink)
                entry.retentionReason=old[k]
            end
        end
        section.trackingGeneration=monitor.generation
        local _,global=WGRStorageCleanupChangedSection(previous,section,changedGroups)
        if global then changedAll=true end
        return section
    end
    char.sections.BAG=observe('BAG',char.sections.BAG)
    if pbkOpen then char.sections.PBK=observe('PBK',char.sections.PBK) end
    if wbkOpen then saved.warbank=observe('WBK',saved.warbank) end
    -- The preview cache revision still tracks every snapshot write. Approval
    -- confidence tracks only actual changes in physical inventory/trust.
    WGRStorageCleanupInventoryRevision=WGRStorageCleanupInventoryRevision+1
    if changedAll or next(changedGroups) then
        WGRStorageCleanupInvalidateApprovalGroups(changedGroups,changedAll)
    end
end


-- An explicit Cleanup scan can include its historical labels. A frozen batch
-- never invokes the planner from the passive inventory tracker.
function WGRStorageCleanupSaveInventorySnapshot(records,pbkOpen,wbkOpen,keep,surplus,review)
    local classification={}
    for _,item in ipairs(keep or {}) do classification[item]='KEEP' end
    for _,item in ipairs(surplus or {}) do classification[item]='SURPLUS' end
    for _,item in ipairs(review or {}) do classification[item]='REVIEW' end
    return WGRStorageCleanupWriteObservedSnapshot(records,pbkOpen,wbkOpen,classification)
end


-- v0.71d: After the authoritative account-wide pass remaps the current live
-- inventory, refresh only the display explanation stored on matching snapshot
-- rows. This deliberately does not bump the inventory revision or approval
-- generation: changing prose must never invalidate or create disposal proof.
-- v0.71e: Persist display-only account-wide retention explanations onto the
-- matching saved holder/WBK rows. Entries included with reason=nil are cleared
-- because the latest full display allocation did not retain them. This changes
-- prose only: do not bump inventory revisions, approval groups, or routing.
function WGRStorageCleanupUpdateAccountSnapshotRetentionReasons(details)
    local saved=WGRStorageCleanupGetInventorySnapshots and WGRStorageCleanupGetInventorySnapshots()
    if type(saved)~='table' or type(details)~='table' then return end
    local mapped={}
    local CLEAR={}
    local function key(owner,location,bagID,slotID,link)
        return table.concat({string.lower(tostring(owner or '')),tostring(location or ''),
            tostring(bagID),tostring(slotID),tostring(link or '')},'\031')
    end
    for _,detail in ipairs(details) do
        if type(detail)=='table' and detail.owner and detail.location
            and detail.bagID~=nil and detail.slotID~=nil and detail.itemLink then
            local k=key(detail.owner,detail.location,detail.bagID,detail.slotID,detail.itemLink)
            if detail.reason==nil then mapped[k]=CLEAR
            else mapped[k]=tostring(detail.reason) end
        end
    end
    local function updateSection(section,owner,location)
        if type(section)~='table' then return end
        for _,entry in ipairs(section.items or {}) do
            local v=mapped[key(owner,location,entry.bagID,entry.slotID,entry.itemLink)]
            if v~=nil then
                if v==CLEAR then entry.retentionReason=nil
                else entry.retentionReason=v end
            end
        end
    end
    for _,char in pairs(saved.characters or {}) do
        if type(char)=='table' and type(char.name)=='string' then
            local sections=char.sections or {}
            updateSection(sections.BAG,char.name,'BAG')
            updateSection(sections.PBK,char.name,'PBK')
        end
    end
    updateSection(saved.warbank,'Shared Warbank','WBK')
end


function WGRStorageCleanupUpdateSnapshotRetentionReasons(records,keep)
    local saved=WGRStorageCleanupGetInventorySnapshots and WGRStorageCleanupGetInventorySnapshots()
    if type(saved)~='table' then return end
    local keepReason,seen={},{}
    local function key(location,bagID,slotID,link)
        return table.concat({tostring(location or ''),tostring(bagID),
            tostring(slotID),tostring(link or '')},'\031')
    end
    for _,item in ipairs(records or {}) do
        if item and item.location and item.bagID~=nil and item.slotID~=nil and item.itemLink then
            seen[key(item.location,item.bagID,item.slotID,item.itemLink)]=true
        end
    end
    for _,item in ipairs(keep or {}) do
        if item and item.location and item.bagID~=nil and item.slotID~=nil and item.itemLink
            and type(item.cleanupReason)=='string' and item.cleanupReason~='' then
            keepReason[key(item.location,item.bagID,item.slotID,item.itemLink)]=item.cleanupReason
        end
    end
    local _,_,_,guid=WGRStorageCleanupSnapshotIdentity()
    local function updateSection(section,location)
        if type(section)~='table' then return end
        for _,entry in ipairs(section.items or {}) do
            local k=key(location,entry.bagID,entry.slotID,entry.itemLink)
            if seen[k] then entry.retentionReason=keepReason[k] end
        end
    end
    local char
    if guid and type(saved.characters)=='table' then char=saved.characters[guid] end
    if not char and type(saved.characters)=='table' then
        local name=(type(UnitName)=='function' and UnitName('player')) or ''
        for _,candidate in pairs(saved.characters) do
            if type(candidate)=='table' and tostring(candidate.name):lower()==tostring(name):lower() then
                char=candidate;break
            end
        end
    end
    if char and type(char.sections)=='table' then
        updateSection(char.sections.BAG,'BAG')
        updateSection(char.sections.PBK,'PBK')
    end
    updateSection(saved.warbank,'WBK')
end

-- Called by debounced physical inventory events, without any routing or
-- KEEP/SURPLUS calculation. OBSERVED means the audit status is unverified;
-- never treat it as a disposal instruction.
function WGRStorageCleanupSaveObservedInventorySnapshot(records,pbkOpen,wbkOpen)
    return WGRStorageCleanupWriteObservedSnapshot(records,pbkOpen,wbkOpen,nil)
end


-- v0.67u: READ-ONLY account inventory enumeration, separating observed
-- future-use holder stock from max-level incoming/pending-routing gear.
-- This deliberately does not classify or modify any physical inventory,
-- routing decisions, frozen transfers, or persistent disposal status.
-- A saved location is only a historical observation, NEVER disposal proof.
function WGRStorageCleanupGetAccountSnapshotCandidates()
    local result={records={},incoming={},scannedCharacters=0,scannedItems=0,
        incomingCount=0,maxLevelCharacters=0,incomingStale=0,incomingUnverified=0,
        incomingIncompleteSections=0,incomingStaleSections=0,
        staleSections=0,incompleteSections=0,missingLevelingCharacters=0,
        provisionalSections=0,provisionalItems=0,incomingProvisionalSections=0,
        incomingProvisionalItems=0,
        unresolvedBindings=0,skippedMaxLevelItems=0,sharedItems=0}
    local saved=WGRStorageCleanupGetInventorySnapshots()
    if not WGRStorageCleanupGetSettings().enabled or not saved then
        result.unavailable=true
        return result
    end
    local now=WGRStorageCleanupSnapshotTime()
    local _,monitor=WGRStorageCleanupEnsureMonitoring()
    local currentGeneration=monitor.generation
    local seenNames={}
    local maxLevel=tonumber(WGR_MAX_LEVEL) or 90
    -- Max-level character inventories are incoming/pending-routing observations,
    -- never confirmed future-use holder supply. This distinction must survive
    -- cross-character snapshots and must not change routing or disposal logic.
    local function addSection(section,owner,location,ownerUnverified,isIncoming)
        if type(section)~='table' then
            if isIncoming then result.incomingIncompleteSections=result.incomingIncompleteSections+1
            else result.incompleteSections=result.incompleteSections+1 end
            return
        end
        if section.complete==false then
            if isIncoming then result.incomingIncompleteSections=result.incomingIncompleteSections+1
            else result.incompleteSections=result.incompleteSections+1 end
        end
        local stamp=tonumber(section.scannedAt)
        -- Age alone is NOT a reason to distrust an offline character's gear.
        -- Only malformed/implausible observation timestamps are invalid.
        local stale=not stamp or stamp<=0 or (now and stamp>now+300)
        if stale then
            if isIncoming then result.incomingStaleSections=result.incomingStaleSections+1
            else result.staleSections=result.staleSections+1 end
        end
        -- Section generation is assigned only when WBGR ACTUALLY observed
        -- that location while monitoring was enabled. Legacy sections and
        -- anything last observed before a pause remain provisional. Never
        -- infer that a disabled addon observed an inventory change.
        local provisional=tonumber(section.trackingGeneration)~=currentGeneration
        if provisional then
            if isIncoming then result.incomingProvisionalSections=result.incomingProvisionalSections+1
            else result.provisionalSections=result.provisionalSections+1 end
        end
        for _,entry in ipairs(section.items or {}) do
            if isIncoming then
                result.incomingCount=result.incomingCount+1
            else
                result.scannedItems=result.scannedItems+1
                if location=='WBK' then result.sharedItems=result.sharedItems+1 end
            end
            local copy={}
            for key,value in pairs(entry) do copy[key]=value end
            copy.itemLink=entry.itemLink
            copy.itemLevel=tonumber(entry.itemLevel) or 0
            copy.minLevel=tonumber(entry.requiredLevel) or 0
            copy.itemName=entry.itemName
            copy.bagID=entry.bagID
            copy.slotID=entry.slotID
            copy.cleanupOwner=owner
            copy.cleanupLocation=location
            copy.cleanupScanStale=stale or section.complete==false or ownerUnverified
            copy.cleanupTrackingProvisional=provisional
            if provisional then
                if isIncoming then result.incomingProvisionalItems=result.incomingProvisionalItems+1
                else result.provisionalItems=result.provisionalItems+1 end
            end
            if isIncoming then
                -- Not a routed upgrade, KEEP, or disposal recommendation.
                -- Include any physical gear observation for visibility; its
                -- eventual role must be determined by the normal router.
                copy.cleanupSupplyRole='INCOMING_UNEVALUATED'
                if stale then result.incomingStale=result.incomingStale+1 end
                if copy.cleanupScanStale or copy.itemLevel<=0
                    or (copy.binding~='WARBAND' and copy.binding~='BOE') then
                    result.incomingUnverified=result.incomingUnverified+1
                end
                result.incoming[#result.incoming+1]=copy
            else
                copy.cleanupSupplyRole='HOLDER_OBSERVED'
                if copy.binding~='WARBAND' and copy.binding~='BOE' then
                    result.unresolvedBindings=result.unresolvedBindings+1
                end
                result.records[#result.records+1]=copy
            end
        end
    end
    for _,char in pairs(saved.characters or {}) do
        if type(char)=='table' and type(char.name)=='string' and char.name~=''
            and not WGRStorageCleanupIsRemoved(char.name) then
            local name=char.name
            seenNames[string.lower(name)]=true
            result.scannedCharacters=result.scannedCharacters+1
            local character=FindCharacterByName and FindCharacterByName(name)
            local level=character and WGRGetCharacterLevel and tonumber(WGRGetCharacterLevel(character))
            -- Level-90 characters such as Arikanna accumulate incoming
            -- equipment, but do NOT create future demand or provide confirmed
            -- holder stock. BAG/PBK here remain a separate read-only pool.
            if level and level>=maxLevel then
                result.maxLevelCharacters=result.maxLevelCharacters+1
                for _,location in ipairs({'BAG','PBK'}) do
                    addSection((char.sections or {})[location],name,location,false,true)
                end
            else
                if not level then result.incompleteSections=result.incompleteSections+1 end
                for _,location in ipairs({'BAG','PBK'}) do
                    addSection((char.sections or {})[location],name,location,not level)
                end
            end
        end
    end
    -- One global snapshot of WBK: never repeat it for every logged-in alt.
    if saved.warbank then addSection(saved.warbank,'Shared Warbank','WBK')
    else result.incompleteSections=result.incompleteSections+1 end
    for _,name in ipairs(GetActiveRoutingPriority and GetActiveRoutingPriority() or {}) do
        local char=FindCharacterByName and FindCharacterByName(name)
        local level=char and WGRGetCharacterLevel and tonumber(WGRGetCharacterLevel(char))
        if not level or level<maxLevel then
            if not seenNames[string.lower(tostring(name))] then
                result.missingLevelingCharacters=result.missingLevelingCharacters+1
            end
        end
    end
    return result
end
