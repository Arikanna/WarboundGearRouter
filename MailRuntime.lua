-- Mail-router runtime: mailbox scanning, send queue, event handling,
-- mail-frame hooks, and routing callbacks.

-- ============================================================
-- WGR MAIL ROUTER v0.23
-- ============================================================
WGRMail = {
    frame=nil, rows={}, destinations={}, prepareAll=false,
    waitingForSend=false, preparedRecipient=nil, preparedSubject=nil, preparedCount=0, mailboxOpen=false,
    preparedAttachmentLinks=nil, preparedAttachmentCounts=nil,
    preparedReady=false, preparedStableSince=nil, preparedStableChecks=0,
    removingPreparedAttachment=false,
    ownsDraft=false, replacingDraft=false,
    preparedDisposalDraft=nil,pendingDisposalSendValid=false,
}
local WGR_MAIL_MAX = ATTACHMENTS_MAX_SEND or 12
local WGR_MAIL_PREPARED_STABLE_SECONDS = 0.30

local function WGRMailResetPreparedReadiness()
    WGRMail.preparedReady = false
    WGRMail.preparedStableSince = nil
    WGRMail.preparedStableChecks = 0
end

local function WGRMailUpdatePreparedReadiness(matches)
    if not matches then
        WGRMailResetPreparedReadiness()
        return false
    end

    if WGRMail.preparedReady then
        return true
    end

    local now = GetTime and GetTime() or 0

    if not WGRMail.preparedStableSince then
        WGRMail.preparedStableSince = now
        WGRMail.preparedStableChecks = 1
        return false
    end

    WGRMail.preparedStableChecks =
        (WGRMail.preparedStableChecks or 0) + 1

    local elapsed = now - WGRMail.preparedStableSince
    if WGRMail.preparedStableChecks >= 2
        and elapsed >= WGR_MAIL_PREPARED_STABLE_SECONDS
    then
        WGRMail.preparedReady = true
        return true
    end

    return false
end

-- Gear Search MAIL tracking is intentionally separate from the existing
-- recipient mail-reminder state. It records physical item location only.
-- Routing destination is recalculated elsewhere and must never overwrite
-- this physical holder/location record.
local function WGRMailNormalizeCharacterName(name)
    if not name or name == "" then
        return nil
    end

    local clean = tostring(name)

    if Ambiguate then
        local ok, shortName = pcall(Ambiguate, clean, "short")
        if ok and shortName and shortName ~= "" then
            clean = shortName
        end
    end

    clean = clean:match("^([^%-]+)") or clean
    clean = strtrim(clean)

    if clean == "" then
        return nil
    end

    return clean
end

local function WGRMailResolveTrackedRecipient(name)
    local shortName = WGRMailNormalizeCharacterName(name)
    if not shortName then
        return nil
    end

    if WGRIsCharacterRemoved and WGRIsCharacterRemoved(shortName) then
        return nil
    end

    local targetKey = string.lower(shortName)

    for _, rosterName in ipairs(GetRoutingPriority and GetRoutingPriority() or {}) do
        local rosterShort = WGRMailNormalizeCharacterName(rosterName)
        if rosterShort and string.lower(rosterShort) == targetKey then
            if not (WGRIsCharacterRemoved and WGRIsCharacterRemoved(rosterName)) then
                return rosterName
            end
        end
    end

    return nil
end

local function WGRMailGearTrackingTable()
    InitializeDatabase()
    WarboundGearRouterDB.mailGearTracking =
        WarboundGearRouterDB.mailGearTracking or {}
    return WarboundGearRouterDB.mailGearTracking
end

local function WGRMailRawGearKeyForItem(itemLink)
    if not itemLink or not WGRClassifyHeldGearItem then
        return nil
    end

    local section, category, subtype =
        WGRClassifyHeldGearItem(itemLink)

    if not section or not category then
        return nil
    end

    return table.concat({
        tostring(section),
        tostring(category),
        tostring(subtype or ""),
    }, "\031")
end

local function WGRMailGearKeyForItem(itemLink)
    if not itemLink then
        return nil
    end

    local recommendation =
        WGRBuildLoadedItemRecommendation
        and WGRBuildLoadedItemRecommendation(itemLink)
        or nil

    if recommendation
        and (
            recommendation.kind == "sell"
            or recommendation.kind == "no_current_upgrade"
        )
    then
        return nil
    end

    return WGRMailRawGearKeyForItem(itemLink)
end

local function WGRMailItemID(itemLink)
    if not itemLink then
        return nil
    end

    if C_Item and C_Item.GetItemInfoInstant then
        local itemID = C_Item.GetItemInfoInstant(itemLink)
        if itemID then
            return tonumber(itemID)
        end
    end

    if GetItemInfoInstant then
        local itemID = GetItemInfoInstant(itemLink)
        if itemID then
            return tonumber(itemID)
        end
    end

    return tonumber(tostring(itemLink):match("item:(%d+)"))
end

local function WGRMailPhysicalIdentityKey(itemLink, gearKey)
    local itemID = WGRMailItemID(itemLink)
    if not itemID or not gearKey then
        return nil
    end

    return tostring(itemID) .. "\031" .. tostring(gearKey)
end

local function WGRMailRememberGearSearchContinuity(characterName, itemLink, gearKey)
    if not characterName or not itemLink or not gearKey then return end
    InitializeDatabase()
    WarboundGearRouterDB.gearSearchMailContinuity =
        WarboundGearRouterDB.gearSearchMailContinuity or {}

    local characterKey = string.lower(characterName)
    local records = WarboundGearRouterDB.gearSearchMailContinuity[characterKey]
    if type(records) ~= "table" then
        records = {}
        WarboundGearRouterDB.gearSearchMailContinuity[characterKey] = records
    end

    local identityKey = WGRMailPhysicalIdentityKey(itemLink, gearKey)
    if identityKey then
        records[identityKey] = (tonumber(records[identityKey]) or 0) + 1
    end
end

local function WGRMailCurrentBagIdentityMultiset()
    local counts = {}

    if not C_Container
        or not C_Container.GetContainerNumSlots
        or not C_Container.GetContainerItemLink
    then
        return counts
    end

    -- Match the same carried-bag range already used by WBGR's held-gear
    -- snapshots. This is a targeted current-character reconciliation pass,
    -- not a cross-character or bank rescan.
    for bagID = 0, 5 do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0

        for slotID = 1, slots do
            local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
            if itemLink then
                local gearKey = WGRMailGearKeyForItem(itemLink)
                local identityKey = WGRMailPhysicalIdentityKey(itemLink, gearKey)

                if identityKey then
                    counts[identityKey] = (counts[identityKey] or 0) + 1
                end
            end
        end
    end

    return counts
end

local function WGRMailCaptureDraftItems(recipientOverride)
    local items = {}

    for index = 1, WGR_MAIL_MAX do
        local itemLink =
            GetSendMailItemLink
            and GetSendMailItemLink(index)
            or nil

        if itemLink then
            local gearKey = WGRMailGearKeyForItem(itemLink)
            if gearKey then
                items[#items + 1] = {
                    itemLink = itemLink,
                    gearKey = gearKey,
                    itemID = WGRMailItemID(itemLink),
                }
            end
        end
    end

    local recipient = recipientOverride

    if (not recipient or recipient == "")
        and SendMailNameEditBox
        and SendMailNameEditBox.GetText
    then
        recipient = strtrim(SendMailNameEditBox:GetText() or "")
    end

    WGRMail.pendingGearDraft = {
        recipient = recipient,
        items = items,
        capturedAt = time(),
    }

    return WGRMail.pendingGearDraft
end

local function WGRMailCommitGearSend(recipient, draft)
    local trackedRecipient =
        WGRMailResolveTrackedRecipient(recipient)

    if not trackedRecipient then
        return false
    end

    local items =
        draft
        and draft.items
        or nil

    if type(items) ~= "table" or #items == 0 then
        return false
    end

    local tracking = WGRMailGearTrackingTable()
    local key = string.lower(trackedRecipient)
    local entry = tracking[key]

    if not entry then
        entry = {
            name = trackedRecipient,
            items = {},
        }
        tracking[key] = entry
    end

    entry.name = trackedRecipient
    entry.items = entry.items or {}

    local sender = UnitName("player")
    local now = time()

    for _, item in ipairs(items) do
        if item.gearKey then
            entry.items[#entry.items + 1] = {
                itemLink = item.itemLink,
                gearKey = item.gearKey,
                itemID = item.itemID or WGRMailItemID(item.itemLink),
                sender = sender,
                sentAt = now,
            }
        end
    end

    entry.updated = now
    entry.seenInInbox = false

    if WGRNotifyGearSearchChanged then
        WGRNotifyGearSearchChanged()
    end

    return true, trackedRecipient
end



local function WGRMailRefreshReturnCache()
    if not WGRMail then return end

    local tracking = WGRMailGearTrackingTable()
    local currentName = WGRMailNormalizeCharacterName(UnitName("player"))
    local currentKey = currentName and string.lower(currentName) or nil
    local currentEntry = currentKey and tracking[currentKey] or nil

    -- Match inbox attachments against already-tracked MAIL state whenever the
    -- current recipient is tracked.  Removed characters intentionally have no
    -- personal WBGR MAIL state, so for them we cache only classifiable gear so
    -- a user-initiated Return can reintroduce qualifying gear to a tracked
    -- original sender without exposing the Removed character in Gear Search.
    local expected = {}
    local expectedSenders = {}
    if currentEntry and type(currentEntry.items) == "table" then
        for _, item in ipairs(currentEntry.items) do
            local identityKey =
                WGRMailPhysicalIdentityKey(item.itemLink, item.gearKey)
            if identityKey then
                expected[identityKey] = (expected[identityKey] or 0) + 1
                expectedSenders[identityKey] = expectedSenders[identityKey] or {}
                expectedSenders[identityKey][#expectedSenders[identityKey] + 1] = item.sender
            end
        end
    end

    local cache = {}
    local inboxCount =
        GetInboxNumItems
        and select(1, GetInboxNumItems())
        or 0

    for mailIndex = 1, inboxCount do
        local sender = nil
        if GetInboxHeaderInfo then
            local _, _, headerSender = GetInboxHeaderInfo(mailIndex)
            sender = headerSender
        end

        local items = {}
        local matched = {}
        for attachmentIndex = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local itemLink =
                GetInboxItemLink
                and GetInboxItemLink(mailIndex, attachmentIndex)
                or nil

            if itemLink then
                local rawGearKey = WGRMailRawGearKeyForItem(itemLink)
                local identityKey =
                    WGRMailPhysicalIdentityKey(itemLink, rawGearKey)

                if currentEntry then
                    local available = identityKey and expected[identityKey] or 0
                    local alreadyMatched = identityKey and matched[identityKey] or 0

                    if identityKey and available > alreadyMatched then
                        local senderList = expectedSenders[identityKey]
                        local originalSender =
                            senderList
                            and senderList[alreadyMatched + 1]
                            or nil

                        items[#items + 1] = {
                            itemLink = itemLink,
                            gearKey = rawGearKey,
                            itemID = WGRMailItemID(itemLink),
                            originalSender = originalSender,
                        }
                        matched[identityKey] = alreadyMatched + 1
                    end
                elseif rawGearKey then
                    items[#items + 1] = {
                        itemLink = itemLink,
                        gearKey = rawGearKey,
                        itemID = WGRMailItemID(itemLink),
                    }
                end
            end
        end

        cache[mailIndex] = {
            sender = sender,
            items = items,
            capturedAt = time(),
        }
    end

    WGRMail.returnInboxCache = cache
end

local function WGRMailPrimeReturn(mailIndex)
    mailIndex = tonumber(mailIndex)
    if not mailIndex or mailIndex < 1 then
        return false
    end

    local cached =
        WGRMail
        and WGRMail.returnInboxCache
        and WGRMail.returnInboxCache[mailIndex]
        or nil

    if not cached or type(cached.items) ~= "table" or #cached.items == 0 then
        return false
    end

    local items = {}
    for _, item in ipairs(cached.items) do
        items[#items + 1] = {
            itemLink = item.itemLink,
            gearKey = item.gearKey,
            itemID = item.itemID,
            originalSender = item.originalSender,
        }
    end

    WGRMail.pendingReturn = {
        mailIndex = mailIndex,
        sender = cached.sender,
        items = items,
        capturedAt = time(),
    }

    return true
end

local function WGRMailPendingReturnStillInInbox(pending)
    if not pending or type(pending.items) ~= "table" or #pending.items == 0 then
        return false
    end

    local targetSender =
        WGRMailNormalizeCharacterName(pending.sender)
    local needed = {}
    for _, item in ipairs(pending.items) do
        local identityKey =
            WGRMailPhysicalIdentityKey(item.itemLink, item.gearKey)
        if identityKey then
            needed[identityKey] = (needed[identityKey] or 0) + 1
        end
    end

    local inboxCount =
        GetInboxNumItems
        and select(1, GetInboxNumItems())
        or 0

    for mailIndex = 1, inboxCount do
        local sender = nil
        if GetInboxHeaderInfo then
            local _, _, headerSender = GetInboxHeaderInfo(mailIndex)
            sender = WGRMailNormalizeCharacterName(headerSender)
        end

        if not targetSender
            or not sender
            or string.lower(sender) == string.lower(targetSender)
        then
            local found = {}
            for attachmentIndex = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local itemLink =
                    GetInboxItemLink
                    and GetInboxItemLink(mailIndex, attachmentIndex)
                    or nil
                if itemLink then
                    local rawGearKey = WGRMailRawGearKeyForItem(itemLink)
                    local identityKey =
                        WGRMailPhysicalIdentityKey(itemLink, rawGearKey)
                    if identityKey then
                        found[identityKey] = (found[identityKey] or 0) + 1
                    end
                end
            end

            local matchesAll = true
            for identityKey, count in pairs(needed) do
                if (found[identityKey] or 0) < count then
                    matchesAll = false
                    break
                end
            end
            if matchesAll then
                return true
            end
        end
    end

    return false
end

local function WGRMailFinalizePendingReturn()
    local pending = WGRMail and WGRMail.pendingReturn or nil
    if not pending then
        return false
    end

    -- MAIL_INBOX_UPDATE can fire before the returned message has fully left
    -- the inbox.  Do not transfer ownership until the staged message is no
    -- longer observable.
    if WGRMailPendingReturnStillInInbox(pending) then
        return false
    end

    local persistedSender = nil
    for _, item in ipairs(pending.items or {}) do
        if item.originalSender then
            persistedSender = item.originalSender
            break
        end
    end

    local sender = persistedSender or pending.sender
    local trackedSender = WGRMailResolveTrackedRecipient(sender)
    local returnDestination =
        WGRMailNormalizeCharacterName(sender)
        or sender

    -- Whether or not the return target is tracked, the pending action is now
    -- complete because the original inbox message is gone.
    WGRMail.pendingReturn = nil

    local returnedItems = pending.items or {}
    if #returnedItems == 0 then
        return false
    end

    local tracking = WGRMailGearTrackingTable()
    local currentName = WGRMailNormalizeCharacterName(UnitName("player"))
    local currentKey = currentName and string.lower(currentName) or nil
    local currentEntry = currentKey and tracking[currentKey] or nil

    -- Remove the returned copies from the current tracked recipient, if any.
    if currentEntry and type(currentEntry.items) == "table" then
        local needed = {}
        for _, returnedItem in ipairs(returnedItems) do
            local identityKey =
                WGRMailPhysicalIdentityKey(returnedItem.itemLink, returnedItem.gearKey)
            if identityKey then
                needed[identityKey] = (needed[identityKey] or 0) + 1
            end
        end

        for index = #currentEntry.items, 1, -1 do
            local item = currentEntry.items[index]
            local identityKey =
                WGRMailPhysicalIdentityKey(item.itemLink, item.gearKey)
            local remaining = identityKey and needed[identityKey] or 0
            if remaining and remaining > 0 then
                table.remove(currentEntry.items, index)
                needed[identityKey] = remaining - 1
            end
        end

        if #(currentEntry.items or {}) == 0 then
            tracking[currentKey] = nil

            -- A successful Return removes the tracked gear from the current
            -- recipient's MAIL state.  Clear that recipient's legacy/message-
            -- level Retrieve Mail reminder at the same transition so To Do
            -- follows the physical MAIL ownership transfer.  Do this silently
            -- rather than using WGRMailMarkChecked(), because a Return is not
            -- a mail retrieval and should not log MAIL_RETRIEVED activity.
            local reminderTracking =
                WarboundGearRouterDB
                and WarboundGearRouterDB.mailTracking
            if reminderTracking and currentKey then
                reminderTracking[currentKey] = nil
            end
        else
            currentEntry.updated = time()
        end
    end

    local committed = false
    local resolvedSender = nil

    -- Re-enter item-aware MAIL tracking only when the return destination is
    -- an Active/Ignored tracked roster character.  A Removed/non-roster
    -- destination intentionally remains outside WBGR after the return.
    if trackedSender then
        committed, resolvedSender =
            WGRMailCommitGearSend(
                trackedSender,
                {
                    recipient = trackedSender,
                    items = returnedItems,
                    capturedAt = time(),
                    returned = true,
                }
            )

        if committed and resolvedSender and WGRMailRecordSend then
            WGRMailRecordSend(resolvedSender)
        end
    end

    -- Recent Activity records the meaningful manual return even when the
    -- destination is Removed/non-roster and therefore leaves WBGR tracking.
    if returnDestination and WGRAddRecentActivity then
        local returnedCount = #returnedItems
        local returningCharacter = WGRMailNormalizeCharacterName(UnitName and UnitName("player") or nil)
            or (UnitName and UnitName("player"))
            or "Current character"
        WGRAddRecentActivity(
            tostring(returningCharacter)
            .. " returned "
            .. tostring(returnedCount)
            .. (returnedCount == 1 and " item to " or " items to ")
            .. tostring(returnDestination)
            .. ".",
            "MAIL_RETURNED"
        )
    end

    if WGRRefreshTodoPage then
        WGRRefreshTodoPage()
    end

    return committed
end

local function WGRMailInboxAttachmentMultiset()
    local actual = {}
    local returned = {}
    local inboxCount =
        GetInboxNumItems
        and select(1, GetInboxNumItems())
        or 0

    for mailIndex = 1, inboxCount do
        local _, _, sender, _, _, _, _, _, _, wasReturned =
            GetInboxHeaderInfo(mailIndex)

        local senderKey =
            string.lower(WGRMailNormalizeCharacterName(sender) or "")

        for attachmentIndex = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local itemLink =
                GetInboxItemLink
                and GetInboxItemLink(mailIndex, attachmentIndex)
                or nil

            if itemLink then
                -- Gear Search tracks the item's searchable gear identity, not
                -- the exact serialized hyperlink. Blizzard can normalize or
                -- rebuild a link between send and receive, so reconciliation
                -- must use the same Gear Search key that was captured on send.
                local gearKey = WGRMailGearKeyForItem(itemLink)

                if gearKey then
                    local matchKey = senderKey .. "\031" .. gearKey
                    actual[matchKey] = (actual[matchKey] or 0) + 1
                end

                if wasReturned then
                    returned[#returned + 1] = {
                        sender = sender,
                        itemLink = itemLink,
                        gearKey = gearKey,
                    }
                end
            end
        end
    end

    return actual, returned, inboxCount
end

function WGRMailReconcileTrackedGearInbox()
    if not WGRMail or not WGRMail.mailboxOpen then
        return
    end

    local currentName = UnitName("player")
    local currentTracked = WGRMailResolveTrackedRecipient(currentName)
    if not currentTracked then
        return
    end

    local tracking = WGRMailGearTrackingTable()
    local currentKey = string.lower(currentTracked)
    local entry = tracking[currentKey]
    local actual, returned, inboxCount = WGRMailInboxAttachmentMultiset()
    local changed = false

    -- Returned mail becomes physically held by the original sender's MAIL.
    -- Move matching outbound records back to the current character when the
    -- inbox explicitly marks them as returned.
    if #returned > 0 then
        for _, returnedItem in ipairs(returned) do
            local returnLink = returnedItem.itemLink
            local returnFrom = WGRMailNormalizeCharacterName(returnedItem.sender)
            local currentShort = WGRMailNormalizeCharacterName(currentTracked)

            for destinationKey, destinationEntry in pairs(tracking) do
                if destinationKey ~= currentKey and type(destinationEntry) == "table" then
                    for index = #(destinationEntry.items or {}), 1, -1 do
                        local item = destinationEntry.items[index]
                        local originalSender = WGRMailNormalizeCharacterName(item.sender)
                        local destinationName = WGRMailNormalizeCharacterName(destinationEntry.name)

                        if (
                                item.itemLink == returnLink
                                or (
                                    item.gearKey
                                    and returnedItem.gearKey
                                    and item.gearKey == returnedItem.gearKey
                                )
                            )
                            and originalSender
                            and currentShort
                            and string.lower(originalSender) == string.lower(currentShort)
                            and (
                                not returnFrom
                                or not destinationName
                                or string.lower(returnFrom) == string.lower(destinationName)
                            )
                        then
                            table.remove(destinationEntry.items, index)

                            entry = entry or {
                                name = currentTracked,
                                items = {},
                            }
                            tracking[currentKey] = entry
                            entry.items = entry.items or {}
                            entry.items[#entry.items + 1] = {
                                itemLink = item.itemLink,
                                gearKey = item.gearKey,
                                itemID = item.itemID or WGRMailItemID(item.itemLink),
                                sender = destinationEntry.name,
                                sentAt = time(),
                                returned = true,
                            }
                            entry.seenInInbox = true
                            changed = true
                            break
                        end
                    end

                    if #(destinationEntry.items or {}) == 0 then
                        tracking[destinationKey] = nil
                    end
                end
            end
        end
    end

    entry = tracking[currentKey]
    if entry and type(entry.items) == "table" then
        local matchedAny = false
        local promotedFromMailToBag = false
        local retained = {}
        local counts = {}
        local bagCounts = WGRMailCurrentBagIdentityMultiset()
        for key, count in pairs(actual) do counts[key] = count end

        for _, item in ipairs(entry.items) do
            local senderKey =
                string.lower(WGRMailNormalizeCharacterName(item.sender) or "")
            local matchKey = senderKey .. "\031" .. tostring(item.gearKey or "")
            local available = counts[matchKey] or 0

            if available > 0 then
                counts[matchKey] = available - 1
                retained[#retained + 1] = item
                matchedAny = true
            elseif entry.seenInInbox ~= true then
                -- Self-heal records created by older test builds when the
                -- attachment was already retrieved before item-aware inbox
                -- reconciliation existed. If the expected mail attachment is
                -- absent but the same tracked gear is physically present in
                -- this character's carried bags, BAG is stronger evidence
                -- than the stale MAIL prediction and the MAIL record can be
                -- retired safely.
                local identityKey =
                    WGRMailPhysicalIdentityKey(
                        item.itemLink,
                        item.gearKey
                    )
                local bagAvailable =
                    identityKey
                    and (bagCounts[identityKey] or 0)
                    or 0

                if bagAvailable > 0 then
                    bagCounts[identityKey] = bagAvailable - 1
                    WGRMailRememberGearSearchContinuity(
                        currentTracked,
                        item.itemLink,
                        item.gearKey
                    )
                    promotedFromMailToBag = true
                    changed = true
                elseif inboxCount == 0
                    and type(item.sentAt) == 'number'
                    and (time() - item.sentAt) > (48 * 60 * 60) then
                    -- Only the actual recipient's opened, empty inbox can
                    -- retire an unobserved delivery, and only once the send
                    -- is well past normal delivery latency. Preserve legacy
                    -- records with no trustworthy sentAt rather than invent
                    -- a timestamp. Recent/in-transit mail remains tracked.
                    changed = true
                else
                    -- A recently sent or undated record cannot be dismissed
                    -- solely because the inbox is currently empty.
                    retained[#retained + 1] = item
                end
            else
                changed = true
            end
        end

        if matchedAny then
            entry.seenInInbox = true
            entry.lastInboxSeenAt = time()
        elseif entry.seenInInbox == true and inboxCount == 0 then
            changed = true
        end

        entry.items = retained
        entry.updated = time()

        if promotedFromMailToBag and WGRRefreshHeldGearSnapshot then
            -- We positively found the former MAIL item in the recipient's
            -- carried bags. Mail/inventory events can report before the normal
            -- held-gear routing state has fully settled, so do one immediate
            -- BAG-only refresh and one short deferred BAG-only refresh. This
            -- rare reconciliation path deliberately avoids PBK/WBK rescans.
            WGRRefreshHeldGearSnapshot(false, true, false)

            if C_Timer and C_Timer.After then
                C_Timer.After(
                    0.35,
                    function()
                        if WGRRefreshHeldGearSnapshot then
                            WGRRefreshHeldGearSnapshot(false, true, false)
                        end
                    end
                )
            end
        end

        if #entry.items == 0 then
            tracking[currentKey] = nil

            -- Item-aware MAIL tracking is authoritative for tracked gear.
            -- This also clears Retrieve Mail To Do for manual sends, which do
            -- not necessarily use the legacy "Alt Gear" mail subject.
            if WGRMailMarkChecked then
                WGRMailMarkChecked(currentTracked)
            elseif WGRRefreshTodoPage then
                WGRRefreshTodoPage()
            end
        end
    end

    if changed and WGRNotifyGearSearchChanged then
        WGRNotifyGearSearchChanged()
    end
end

-- Forward declaration: early draft-clear callbacks rescan before the
-- implementation appears later in this module.
local WGRMailScan
local WGRMailRefreshPreparedSendButton
local WGRMailRefreshPreparedDraftPanel

-- The normal Blizzard Send Mail UI is available only when its frame and
-- Send Mail tab are effectively visible. IsShown() alone is insufficient:
-- replacement mailbox UIs can leave Blizzard child frames in their shown
-- state while hiding a parent, which makes the tab unusable on screen.
local function WGRMailFrameIsEffectivelyVisible(frame)
    if not frame then
        return false
    end

    local visible = nil

    if frame.IsVisible then
        visible = frame:IsVisible() == true
    else
        -- Defensive fallback for stripped test/mocked frames. Retail Frames
        -- have IsVisible(), but IsShown() is still better than assuming a
        -- missing visibility method means the frame is usable.
        visible = frame.IsShown
            and frame:IsShown() == true
    end

    if not visible then
        return false
    end

    -- Replacement mailbox UIs can leave Blizzard's MailFrame hierarchy
    -- technically visible while suppressing it with alpha. IsVisible() does
    -- not account for alpha, so require a genuinely rendered frame too.
    local alpha = nil
    if frame.GetEffectiveAlpha then
        alpha = frame:GetEffectiveAlpha()
    elseif frame.GetAlpha then
        alpha = frame:GetAlpha()
    end

    if type(alpha) == "number" and alpha <= 0.01 then
        return false
    end

    -- Treat a collapsed or effectively zero-scale Blizzard control as
    -- unavailable even if it remains shown in the frame hierarchy.
    if frame.GetEffectiveScale then
        local scale = frame:GetEffectiveScale()
        if type(scale) == "number" and scale <= 0.01 then
            return false
        end
    end

    -- Finally require the frame to intersect the visible UIParent rectangle
    -- when both rectangles are available. This covers replacement UIs that
    -- park Blizzard's mailbox off-screen rather than hiding it.
    if UIParent
        and frame.GetLeft
        and frame.GetRight
        and frame.GetTop
        and frame.GetBottom
        and UIParent.GetLeft
        and UIParent.GetRight
        and UIParent.GetTop
        and UIParent.GetBottom
    then
        local left = frame:GetLeft()
        local right = frame:GetRight()
        local top = frame:GetTop()
        local bottom = frame:GetBottom()
        local parentLeft = UIParent:GetLeft()
        local parentRight = UIParent:GetRight()
        local parentTop = UIParent:GetTop()
        local parentBottom = UIParent:GetBottom()

        if left and right and top and bottom
            and parentLeft and parentRight and parentTop and parentBottom
            and (
                right <= parentLeft
                or left >= parentRight
                or top <= parentBottom
                or bottom >= parentTop
            )
        then
            return false
        end
    end

    return true
end

local function WGRMailUsingBlizzardSendUI()
    return WGRMailFrameIsEffectivelyVisible(MailFrame)
        and WGRMailFrameIsEffectivelyVisible(MailFrameTab2)
end

local function WGRMailStatus(text,r,g,b)
    if WGRMail.frame and WGRMail.frame.status then
        WGRMail.frame.status:SetText(text or "")
        WGRMail.frame.status:SetTextColor(r or .85,g or .85,b or .85)
    end
end

local function WGRMailStop(text)
    -- If WBGR owns an outgoing draft that is hidden behind a replacement
    -- mailbox UI, abandoning Mail Router must return those attachments to
    -- Bags. Never leave an invisible draft armed after Stop/close/error.
    if WGRMail.mailboxOpen
        and WGRMail.ownsDraft
        and not WGRMailUsingBlizzardSendUI()
    then
        for attachmentIndex = WGR_MAIL_MAX, 1, -1 do
            if GetSendMailItem(attachmentIndex) then
                if RemoveSendMailItem then
                    RemoveSendMailItem(attachmentIndex)
                else
                    ClickSendMailItemButton(attachmentIndex)
                end

                if CursorHasItem and CursorHasItem() and ClearCursor then
                    ClearCursor()
                end
            end
        end
    end

    WGRMail.prepareAll=false
    WGRMail.waitingForSend=false
    WGRMail.preparedRecipient=nil
    WGRMail.preparedSubject=nil
    WGRMail.preparedCount=0
    WGRMail.preparedAttachmentLinks=nil
    WGRMail.preparedAttachmentCounts=nil
    WGRMailResetPreparedReadiness()
    WGRMail.preparedDisposalDraft=nil
    WGRMail.pendingDisposalSendValid=false
    WGRMail.pendingSendRecipient=nil
    WGRMail.pendingGearDraft=nil
    WGRMail.ownsDraft=false
    WGRMail.removingPreparedAttachment=false
    if WGRMail.frame and WGRMail.frame.prepareAllButton then
        WGRMail.frame.prepareAllButton:SetText("Prepare All")
    end
    if WGRMailRefreshPreparedSendButton then
        WGRMailRefreshPreparedSendButton()
    end
    if text then WGRMailStatus(text) end
end

local function WGRMailText(box)
    if box and box.GetText then return strtrim(box:GetText() or "") end
    return ""
end

local function WGRMailHasAttachments()
    for i=1,WGR_MAIL_MAX do
        if GetSendMailItem(i) then return true end
    end
    return false
end

local function WGRMailMoneyAmount(frameOrValue)
    if type(frameOrValue) == "number" then
        return frameOrValue
    end

    if frameOrValue
        and MoneyInputFrame_GetCopper
    then
        local ok, amount =
            pcall(
                MoneyInputFrame_GetCopper,
                frameOrValue
            )

        if ok
            and type(amount) == "number"
        then
            return amount
        end
    end

    return 0
end

local function WGRMailCountCurrentDraftItems()
    local count = 0

    for index = 1,
        (
            ATTACHMENTS_MAX_SEND
            or 12
        )
    do
        if GetSendMailItem(
            index
        )
        then
            count =
                count + 1
        end
    end

    return count
end

local function WGRMailCurrentAttachmentSnapshot()
    local links = {}
    local counts = {}

    for index = 1, WGR_MAIL_MAX do
        local link =
            GetSendMailItemLink
            and GetSendMailItemLink(index)
            or nil

        if link then
            links[#links + 1] = link
            counts[link] = (counts[link] or 0) + 1
        end
    end

    return links, counts
end

local function WGRMailStorePreparedAttachmentSnapshot()
    local links, counts =
        WGRMailCurrentAttachmentSnapshot()

    WGRMail.preparedAttachmentLinks = links
    WGRMail.preparedAttachmentCounts = counts
    WGRMail.preparedCount = #links
    WGRMailResetPreparedReadiness()

    return #links
end

local function WGRMailPreparedAttachmentsMatch()
    local expectedLinks =
        WGRMail.preparedAttachmentLinks
    local expectedCounts =
        WGRMail.preparedAttachmentCounts

    if type(expectedLinks) ~= "table"
        or type(expectedCounts) ~= "table"
        or #expectedLinks <= 0
    then
        return false, 0
    end

    local currentLinks, currentCounts =
        WGRMailCurrentAttachmentSnapshot()

    if #currentLinks ~= #expectedLinks then
        return false, #currentLinks
    end

    for link, count in pairs(expectedCounts) do
        if currentCounts[link] ~= count then
            return false, #currentLinks
        end
    end

    for link, count in pairs(currentCounts) do
        if expectedCounts[link] ~= count then
            return false, #currentLinks
        end
    end

    return true, #currentLinks
end

local function WGRMailAttachmentCountsForLinks(links)
    local counts = {}

    for _, link in ipairs(links or {}) do
        counts[link] = (counts[link] or 0) + 1
    end

    return counts
end

local function WGRMailAttachmentSnapshotMatchesLinks(expectedLinks)
    local currentLinks, currentCounts = WGRMailCurrentAttachmentSnapshot()
    local expectedCounts = WGRMailAttachmentCountsForLinks(expectedLinks)

    if #currentLinks ~= #(expectedLinks or {}) then
        return false, currentLinks, currentCounts
    end

    for link, count in pairs(expectedCounts) do
        if currentCounts[link] ~= count then
            return false, currentLinks, currentCounts
        end
    end

    for link, count in pairs(currentCounts) do
        if expectedCounts[link] ~= count then
            return false, currentLinks, currentCounts
        end
    end

    return true, currentLinks, currentCounts
end

local function WGRMailCurrentAttachmentEntries()
    local entries = {}

    for slot = 1, WGR_MAIL_MAX do
        local link = GetSendMailItemLink and GetSendMailItemLink(slot) or nil
        if link then
            entries[#entries + 1] = { slot = slot, link = link }
        end
    end

    return entries
end

local function WGRMailDraftClear()
    -- Blizzard's recipient/subject/body fields are UI-owned state. Only treat
    -- them as part of the draft when the normal Blizzard Send Mail UI is
    -- actually available. Replacement mailbox UIs may never expose these
    -- controls, and WBGR's custom fallback supplies its own recipient/subject
    -- directly to SendMail(). Shared attachments/money/COD are still checked
    -- below for every mailbox UI.
    if WGRMailUsingBlizzardSendUI() then
        if WGRMailText(SendMailNameEditBox) ~= "" then return false end
        if WGRMailText(SendMailSubjectEditBox) ~= "" then return false end
        if WGRMailText(SendMailBodyEditBox) ~= "" then return false end
    end
    if WGRMailHasAttachments() then return false end

    -- Prefer the underlying outgoing-mail state so replacement mailbox UIs
    -- cannot hide money/COD from WBGR's safety check. Fall back to Blizzard's
    -- money widgets for older clients / harnesses.
    if GetSendMailMoney then
        local ok, amount = pcall(GetSendMailMoney)
        if ok and type(amount) == "number" and amount > 0 then
            return false
        end
    elseif WGRMailMoneyAmount(SendMailMoney) > 0 then
        return false
    end

    if GetSendMailCOD then
        local ok, amount = pcall(GetSendMailCOD)
        if ok and type(amount) == "number" and amount > 0 then
            return false
        end
    elseif WGRMailMoneyAmount(SendMailCOD) > 0 then
        return false
    end

    return true
end

local function WGRMailEvaluateItem(
    itemLink
)
    if not itemLink then
        return nil
    end

    local itemName,
          returnedLink,
          itemQuality,
          baseItemLevel,
          itemMinLevel,
          itemType,
          itemSubType,
          stackCount,
          equipLoc =
        C_Item.GetItemInfo(
            itemLink
        )

    -- Mail preparation must never wait indefinitely for item data.
    -- If WoW has not cached this item yet, skip it for this pass.
    if not itemName then
        return nil
    end

    local newItemLevel =
        GetItemLevel(
            itemLink
        )

    if not newItemLevel then
        return nil
    end

    -- Armor
    local armorSlotID =
        WGRArmorEquipSlots[
            equipLoc
        ]

    if armorSlotID then
        local armorType =
            itemSubType

        if not GetArmorPriorityList(armorType) then
            return nil
        end

        return
            BuildSimpleRecommendation(
                newItemLevel,
                itemMinLevel,
                GetArmorPriorityList(armorType),
                {
                    armorSlotID
                }
            )
    end

    -- Neck / cloak / rings / trinkets
    local globalSlots =
        WGRGlobalEquipSlots[
            equipLoc
        ]

    if globalSlots then
        if equipLoc == "INVTYPE_TRINKET" then
            local priorityList =
                WGRGetTrinketRoutingPriority(
                    itemLink
                )

            return
                BuildSimpleRecommendation(
                    newItemLevel,
                    itemMinLevel,
                    priorityList,
                    globalSlots,
                    function(
                        characterName,
                        character
                    )
                        return
                            WGRGetTrinketComparisonLevelForMode(
                                characterName,
                                character,
                                itemLink
                            )
                    end
                )
        end

        return
            BuildSimpleRecommendation(
                newItemLevel,
                itemMinLevel,
                GetActiveRoutingPriority(),
                globalSlots
            )
    end

    -- Caster off-hand / shield
    if WGROffhandEquipLocs[
        equipLoc
    ] then
        return
            BuildOffhandRecommendation(
                itemLink,
                newItemLevel,
                itemMinLevel
            )
    end

    -- Weapon
    if IsSupportedWeapon(
        itemLink
    ) then
        return
            BuildWeaponRecommendation(
                itemLink,
                newItemLevel,
                itemMinLevel
            )
    end

    return nil
end


local function WGRMailOwnedDraftIsCleared()
    if WGRMailUsingBlizzardSendUI() then
        if WGRMailText(
            SendMailNameEditBox
        ) ~= "" then
            return false
        end

        if WGRMailText(
            SendMailSubjectEditBox
        ) ~= "" then
            return false
        end
    end

    if WGRMailHasAttachments() then
        return false
    end

    return true
end

local function WGRMailClearFields()
    if WGRMailUsingBlizzardSendUI() then
        if SendMailNameEditBox then
            SendMailNameEditBox:SetText("")
        end

        if SendMailSubjectEditBox then
            SendMailSubjectEditBox:SetText("")
        end

        if SendMailBodyEditBox then
            SendMailBodyEditBox:SetText("")
        end
    end

    -- Return all attachments to carried bags.
    -- Use Blizzard's outgoing-mail removal API. ClickSendMailItemButton
    -- is intended for placing items into attachment slots and was the
    -- reason switching destinations required a second click.
    for attachmentIndex =
        WGR_MAIL_MAX, 1, -1
    do
        if GetSendMailItem(
            attachmentIndex
        )
        then
            if RemoveSendMailItem then
                RemoveSendMailItem(
                    attachmentIndex
                )
            else
                ClickSendMailItemButton(
                    attachmentIndex
                )
            end

            if CursorHasItem() then
                ClearCursor()
            end
        end
    end

    -- Clear money/COD only when Blizzard exposes these as money input frames.
    if SendMailMoney
        and type(SendMailMoney) == "table"
        and MoneyInputFrame_ResetMoney
    then
        pcall(
            MoneyInputFrame_ResetMoney,
            SendMailMoney
        )
    end

    if SendMailCOD
        and type(SendMailCOD) == "table"
        and MoneyInputFrame_ResetMoney
    then
        pcall(
            MoneyInputFrame_ResetMoney,
            SendMailCOD
        )
    end

    WGRMail.waitingForSend = false
    WGRMail.preparedRecipient = nil
    WGRMail.preparedSubject = nil
    WGRMail.preparedCount = 0
    WGRMail.preparedAttachmentLinks = nil
    WGRMail.preparedAttachmentCounts = nil
    WGRMailResetPreparedReadiness()
    WGRMail.preparedDisposalDraft = nil
    WGRMail.pendingDisposalSendValid = false
    WGRMail.pendingSendRecipient = nil
    WGRMail.pendingGearDraft = nil
    WGRMail.ownsDraft = false
    WGRMail.removingPreparedAttachment = false
    if WGRMailRefreshPreparedSendButton then
        WGRMailRefreshPreparedSendButton()
    end
end

local function WGRMailRefreshOverlays()
    C_Timer.After(
        0.15,
        function()
            RefreshBagnonCleanupOverlays()
        end
    )
end

local function WGRMailClearDraftAndRescan(
    statusText,
    callback
)
    WGRMailClearFields()

    local attempts = 0

    local function ContinueWhenClear()
        if not WGRMail.mailboxOpen then
            return
        end

        attempts =
            attempts + 1

        -- When replacing a draft WGR created, wait only for the
        -- fields and attachments WGR owns. Blizzard may take several
        -- frames to return attachments to bags.
        if not WGRMailOwnedDraftIsCleared() then
            if attempts < 40 then
                C_Timer.After(
                    0.10,
                    ContinueWhenClear
                )
            else
                WGRMailStatus(
                    "Mail attachments are still clearing. Try again.",
                    1.00,
                    0.45,
                    0.25
                )
            end

            return
        end

        -- Allow the returned attachment and BAG_UPDATE events to settle.
        C_Timer.After(
            0.25,
            function()
                if not WGRMail.mailboxOpen then
                    return
                end

                WGRMailScan(
                    function()
                        if not WGRMail.mailboxOpen then
                            return
                        end

                        WGRMailRefreshOverlays()

                        if statusText then
                            WGRMailStatus(
                                statusText
                            )
                        end

                        if callback then
                            C_Timer.After(
                                0.15,
                                callback
                            )
                        end
                    end
                )
            end
        )
    end

    C_Timer.After(
        0.10,
        ContinueWhenClear
    )
end

local function WGRMailDestination(result)
    if not result or not result.name then return nil end
    if result.kind ~= "upgrade"
        and result.kind ~= "future_upgrade"
        and result.kind ~= "holder"
        and result.kind ~= "unknown"
    then
        return nil
    end
    local me=UnitName("player")
    if me and string.lower(me)==string.lower(result.name) then return nil end
    return result.name
end

local function WGRMailPriority(name)
    local wanted =
        string.lower(name or "")

    for index, characterName
        in ipairs(GetActiveRoutingPriority())
    do
        if string.lower(characterName)
            == wanted
        then
            return index
        end
    end

    return 999999
end

local function WGRMailBagItems()
    local items={}
    for bag=0,4 do
        local slots=C_Container.GetContainerNumSlots(bag)
        for slot=1,slots do
            local link=C_Container.GetContainerItemLink(bag,slot)
            if link and IsTransferableContainerItem(bag,slot,link)
                and not (WGRStorageCleanupIsDisposeCopy and
                    WGRStorageCleanupIsDisposeCopy(bag,slot,link)) then
                items[#items+1]={bagID=bag,slotID=slot,itemLink=link}
            end
        end
    end
    return items
end

local function WGRMailCanViewPersonalBank()
    if not C_Bank
        or not Enum
        or not Enum.BankType
        or Enum.BankType.Character == nil
    then
        return false
    end

    if C_Bank.CanViewBank then
        local ok, result =
            pcall(
                C_Bank.CanViewBank,
                Enum.BankType.Character
            )

        if ok then
            return result == true
        end
    end

    if C_Bank.CanUseBank then
        local ok, result =
            pcall(
                C_Bank.CanUseBank,
                Enum.BankType.Character
            )

        if ok then
            return result == true
        end
    end

    return false
end

local function WGRMailCountPersonalBankOutgoing()
    if not WGRMailCanViewPersonalBank() then
        return nil
    end

    if not C_Bank
        or not C_Bank.FetchPurchasedBankTabIDs
    then
        return nil
    end

    local ok, tabIDs =
        pcall(
            C_Bank.FetchPurchasedBankTabIDs,
            Enum.BankType.Character
        )

    if not ok
        or type(tabIDs) ~= "table"
    then
        return nil
    end

    local count = 0

    for _, bagID
        in ipairs(tabIDs)
    do
        local slots =
            C_Container.GetContainerNumSlots(
                bagID
            )
            or 0

        for slotID = 1, slots do
            local itemLink =
                C_Container.GetContainerItemLink(
                    bagID,
                    slotID
                )

            if itemLink
                and IsTransferableContainerItem(
                    bagID,
                    slotID,
                    itemLink
                )
                and not (WGRStorageCleanupIsDisposeCopy and
                    WGRStorageCleanupIsDisposeCopy(bagID,slotID,itemLink))
            then
                local result =
                    WGRMailEvaluateItem(
                        itemLink
                    )

                local destination =
                    WGRMailDestination(
                        result
                    )

                if destination then
                    count = count + 1
                end
            end
        end
    end

    return count
end

local WGRMailPrepareDestination
local WGRMailPrepareNext

function WGRMailUpdateDisposeButtons()
    local frame=WGRMail and WGRMail.frame
    if not frame or not frame.disposeButtons then return false end
    local settings=WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings()
    local has=false
    for binding,button in pairs(frame.disposeButtons) do
        local candidates=settings and settings.enabled and
            WGRStorageCleanupDisposalMailCandidates and
            WGRStorageCleanupDisposalMailCandidates(binding) or {}
        local count=#candidates
        local recipient=settings and (binding=='WARBAND' and
            settings.warboundRecipient or settings.boeRecipient) or nil
        local valid=recipient and recipient~='CURRENT' and recipient~=''
        -- Recipient validation is repeated by the authoritative preparation
        -- function. This UI is only an affordance, not a safety boundary.
        button:SetText(string.format('%s DISPOSE (%d)',
            binding=='WARBAND' and 'Warbound' or 'BoE',count))
        button:SetEnabled(count>0 and valid and WGRMail.mailboxOpen)
        if count>0 then has=true end
    end
    return has
end

local function WGRMailUpdateRows()
    if not WGRMail.frame then return end
    for _,row in ipairs(WGRMail.rows) do row:Hide() end
    for i,d in ipairs(WGRMail.destinations) do
        local row=WGRMail.rows[i]
        if not row then
            row=CreateFrame(
                "Button",
                nil,
                WGRMail.frame.destinationContent,
                "UIPanelButtonTemplate"
            )
            row:SetSize(180,24)
            WGRMail.rows[i]=row
        end
        row:ClearAllPoints()
        row:SetPoint(
            "TOPLEFT",
            WGRMail.frame.destinationContent,
            "TOPLEFT",
            0,
            -((i-1)*27)
        )
        row.destinationName=d.name
        row:SetText(string.format("%s  -  %d",d.name,d.count))
        row:SetScript("OnClick",function(self)
            if WGRMail.prepareAll then
                WGRMailStatus("Stop Prepare All before selecting a destination.",1,.65,.2)
                return
            end
            WGRMailPrepareDestination(self.destinationName,false)
        end)
        row:Show()
    end

    if WGRMail.frame.destinationContent then
        WGRMail.frame.destinationContent:SetHeight(
            math.max(
                1,
                #WGRMail.destinations * 27
            )
        )

        if WGRMail.frame.destinationScroll
            and WGRMail.frame.destinationScroll.UpdateScrollChildRect
        then
            WGRMail.frame.destinationScroll:UpdateScrollChildRect()
        end
    end

    local hasDisposal=WGRMailUpdateDisposeButtons and WGRMailUpdateDisposeButtons()
    if #WGRMail.destinations==0 then
        WGRMailStatus(
            hasDisposal and 'DISPOSE Mail available; review the destination before sending.'
                or 'No SEND TO / HOLD ON gear in carried bags.',
            .65,.65,.65
        )
    elseif not WGRMail.waitingForSend then
        WGRMailStatus(
            string.format(
                "Ready. %d destination%s.",
                #WGRMail.destinations,
                #WGRMail.destinations==1 and "" or "s"
            )
        )
    end
end

local WGRMailTodoSnapshotDirty =
    false

WGRMailScan = function(
    callback
)
    local currentName = UnitName("player")

    -- Removed characters are outside WBGR routing for their personal Bags/PBK.
    -- Keep Mail Router consistent with Gear Finder/tooltips/overlays and do not
    -- discover or route outgoing gear from a Removed character's carried bags.
    if currentName
        and WGRIsCharacterRemoved
        and WGRIsCharacterRemoved(currentName)
    then
        WGRMail.destinations = {}
        WGRMailTodoSnapshotDirty = false

        if WGRUpdateGearTodoSnapshot then
            WGRUpdateGearTodoSnapshot(
                currentName,
                0,
                nil,
                false,
                0
            )
        end

        WGRMailUpdateRows()

        if callback then
            callback()
        end

        return
    end

    local items =
        WGRMailBagItems()

    local grouped = {}

    for _, item
        in ipairs(items)
    do
        local result =
            WGRMailEvaluateItem(
                item.itemLink
            )

        local destination =
            WGRMailDestination(
                result
            )

        if destination then
            grouped[destination] =
                grouped[destination]
                or {
                    items = {},
                }

            table.insert(
                grouped[
                    destination
                ].items,
                {
                    bagID =
                        item.bagID,
                    slotID =
                        item.slotID,
                    itemLink =
                        item.itemLink,
                }
            )
        end
    end

    local list = {}

    for name, data
        in pairs(grouped)
    do
        table.insert(
            list,
            {
                name = name,
                count =
                    #data.items,
                items =
                    data.items,
                priority =
                    WGRMailPriority(
                        name
                    ),
            }
        )
    end

    table.sort(
        list,
        function(a, b)
            if a.priority
                == b.priority
            then
                return a.name
                    < b.name
            end

            return a.priority
                < b.priority
        end
    )

    WGRMail.destinations =
        list

    WGRMailTodoSnapshotDirty =
        false

    local totalOutgoing =
        0

    for _, destination
        in ipairs(
            list
        )
    do
        totalOutgoing =
            totalOutgoing
            + (
                tonumber(
                    destination.count
                )
                or 0
            )
    end

    if WGRUpdateGearTodoSnapshot then
        local personalBankOutgoing =
            WGRMailCountPersonalBankOutgoing()

        WGRUpdateGearTodoSnapshot(
            UnitName("player"),
            totalOutgoing,
            nil,
            false,
            personalBankOutgoing
        )
    end

    WGRMailUpdateRows()

    if callback then
        callback()
    end
end

WGRMailRefreshCurrentTodoSnapshot =
    function(
        force,
        allowPaused
    )
        if WGRRoutingIsPaused
            and WGRRoutingIsPaused()
            and not allowPaused
        then
            return false
        end

        if WGRMail
            and WGRMail.waitingForSend
        then
            return false
        end

        if not force
            and not WGRMailTodoSnapshotDirty
        then
            if WGRRefreshTodoPage then
                WGRRefreshTodoPage()
            end

            return true
        end

        WGRMailScan(
            function()
                if WGRRefreshTodoPage then
                    WGRRefreshTodoPage()
                end
            end
        )

        return true
    end

local function WGRMailGetDestinationRecord(
    destinationName
)
    local wanted =
        string.lower(
            destinationName
            or ""
        )

    for _, destination
        in ipairs(
            WGRMail.destinations
        )
    do
        if string.lower(
            destination.name
        ) == wanted
        then
            return destination
        end
    end

    return nil
end

local function WGRMailFindFor(
    destName,
    callback
)
    local record =
        WGRMailGetDestinationRecord(
            destName
        )

    local candidates =
        record
        and record.items
        or {}

    local matches = {}

    for _, item
        in ipairs(candidates)
    do
        local currentLink =
            C_Container.GetContainerItemLink(
                item.bagID,
                item.slotID
            )

        if currentLink
            == item.itemLink
            and IsTransferableContainerItem(
                item.bagID,
                item.slotID,
                currentLink
            )
            and not (WGRStorageCleanupIsDisposeCopy and
                WGRStorageCleanupIsDisposeCopy(item.bagID,item.slotID,currentLink))
        then
            -- Fresh routing evaluation immediately before attachment.
            local result =
                WGRMailEvaluateItem(
                    currentLink
                )

            local destination =
                WGRMailDestination(
                    result
                )

            if destination
                and string.lower(
                    destination
                ) == string.lower(
                    destName
                )
            then
                table.insert(
                    matches,
                    {
                        bagID =
                            item.bagID,
                        slotID =
                            item.slotID,
                        itemLink =
                            currentLink,
                    }
                )
            end
        end
    end

    table.sort(
        matches,
        function(a, b)
            if a.bagID
                == b.bagID
            then
                return a.slotID
                    < b.slotID
            end

            return a.bagID
                < b.bagID
        end
    )

    callback(
        matches
    )
end

local function WGROpenSendMailTab(
    callback
)
    if not WGRMail.mailboxOpen then
        return
    end

    local usingBlizzardSendUI =
        WGRMailUsingBlizzardSendUI()

    if usingBlizzardSendUI then
        -- If the Send Mail pane is already the selected Blizzard tab,
        -- continue immediately.
        if PanelTemplates_GetSelectedTab
            and PanelTemplates_GetSelectedTab(
                MailFrame
            ) == 2
        then
            if callback then
                callback()
            end
            return
        end

        -- Preserve normal Blizzard-mailbox behavior: switch the visible
        -- Blizzard UI to its Send Mail pane.
        if MailFrameTab_OnClick
            and MailFrameTab2
        then
            MailFrameTab_OnClick(
                MailFrameTab2,
                2
            )
        elseif PanelTemplates_SetTab
            and MailFrame
        then
            PanelTemplates_SetTab(
                MailFrame,
                2
            )

            if InboxFrame then
                InboxFrame:Hide()
            end

            if SendMailFrame then
                SendMailFrame:Show()
            end

            if SetSendMailShowing then
                pcall(SetSendMailShowing, true)
            end
        end
    else
        -- Replacement mailbox UIs do not expose a generic tab-switch API.
        -- Activate Retail's shared outgoing-mail state directly so WBGR can
        -- prepare attachments without knowing the replacement addon's frames.
        if SetSendMailShowing then
            pcall(SetSendMailShowing, true)
        end
    end

    -- Give the client/replacement UI one frame to settle the outgoing-mail
    -- state before scanning/attaching.
    C_Timer.After(
        0.05,
        function()
            if not WGRMail.mailboxOpen then
                return
            end

            if callback then
                callback()
            end
        end
    )
end

local function WGRMailPrepareDestinationInternal(destName,fromAll)
    if not WGRMail.mailboxOpen then return end
    if not WGRMailDraftClear() then
        if WGRMail.ownsDraft then
            local destinationToPrepare =
                destName

            WGRMailStatus(
                "Switching to "
                    .. destinationToPrepare
                    .. "..."
            )

            -- Clear only the draft WGR itself created.
            WGRMailClearFields()

            -- Blizzard returns outgoing attachments/bag slots
            -- asynchronously. A short deterministic delay is more
            -- reliable here than chaining several nested clear callbacks.
            C_Timer.After(
                0.50,
                function()
                    if not WGRMail.mailboxOpen then
                        return
                    end

                    -- Rebuild routing from the now-current bag contents.
                    WGRMailScan(
                        function()
                            if not WGRMail.mailboxOpen then
                                return
                            end

                            WGRMailRefreshOverlays()

                            WGRMailStatus(
                                "Preparing "
                                    .. destinationToPrepare
                                    .. "..."
                            )

                            -- Use the regular external preparation entry
                            -- point so the same validation/error handling
                            -- is used as a normal destination click.
                            WGRMailPrepareDestination(
                                destinationToPrepare,
                                fromAll
                            )
                        end
                    )
                end
            )

            return
        end

        WGRMailStatus(
            "Mail draft contains non-WBGR changes. Clear the draft first.",
            1,.3,.3
        )

        if fromAll then
            WGRMailStop(
                "Prepare All stopped: clear the current mail draft first."
            )
        end

        return
    end

    WGRMailStatus(
        "Validating gear for "
            .. destName
            .. "..."
    )

    WGRMailFindFor(destName,function(items)
        if not WGRMail.mailboxOpen then return end
        if not WGRMailDraftClear() then
            WGRMailStatus(
                "Mail draft changed during validation. Clear the draft first.",
                1,.3,.3
            )

            if fromAll then
                WGRMailStop(
                    "Prepare All stopped: mail draft changed."
                )
            end

            return
        end
        if #items==0 then
            WGRMailStatus("No qualifying gear remains for "..destName..".")
            WGRMailScan(function()
                if WGRMail.prepareAll then C_Timer.After(.2,WGRMailPrepareNext) end
            end)
            return
        end

        local usingBlizzardSendUI = WGRMailUsingBlizzardSendUI()
        if usingBlizzardSendUI then
            SendMailNameEditBox:SetText(destName)
            SendMailSubjectEditBox:SetText("Alt Gear")
        end
        local attached=0
        for i=1,math.min(#items,WGR_MAIL_MAX) do
            local item=items[i]
            local current=C_Container.GetContainerItemLink(item.bagID,item.slotID)
            if current==item.itemLink
                and IsTransferableContainerItem(item.bagID,item.slotID,current)
            then
                C_Container.PickupContainerItem(item.bagID,item.slotID)
                ClickSendMailItemButton(attached+1)
                attached=attached+1
            end
        end

        if attached==0 then
            if usingBlizzardSendUI then
                SendMailNameEditBox:SetText("")
                SendMailSubjectEditBox:SetText("")
            end
            WGRMailStatus("No items could be attached for "..destName..".",1,.45,.25)
            if fromAll then WGRMailStop("Prepare All stopped: attachment failed.") end
            return
        end

        WGRMail.waitingForSend=true
        WGRMail.preparedRecipient=destName
        WGRMail.preparedSubject="Alt Gear"
        WGRMail.preparedCount=attached
        WGRMail.ownsDraft=true
        WGRMailStorePreparedAttachmentSnapshot()
        if usingBlizzardSendUI then
            WGRMailStatus(
                string.format("Prepared %d item%s for %s. Review, then press Send.",
                    attached,attached==1 and "" or "s",destName),
                1,.35,.82
            )
        else
            WGRMailStatus(
                string.format("Prepared %d item%s for %s. Review if desired, then use Send Prepared.",
                    attached,attached==1 and "" or "s",destName),
                1,.35,.82
            )
        end
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
        WGRMailScan(
            function()
                WGRMailRefreshOverlays()
            end
        )
    end)
end


-- v0.68o: explicit, user-reviewed DISPOSE mail preparation. Never call the
-- normal holder routing preparer: it intentionally excludes DISPOSE copies.
-- The user must pick a recipient in Storage Cleanup and must press Send.
function WGRMailPrepareDisposalDraft(recipient,binding)
    if not (WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings().enabled) then
        return false,'Storage Cleanup is OFF' end
    if not WGRMail.mailboxOpen then return false,'Open a mailbox first' end
    if binding~='WARBAND' and binding~='BOE' then
        return false,'Choose a Warbound or BoE disposal group' end
    recipient=recipient and strtrim(tostring(recipient)) or ''
    local target=WGRMailNormalizeCharacterName(recipient)
    local myself=WGRMailNormalizeCharacterName(UnitName and UnitName('player'))
    if not target or target=='CURRENT' or
        (myself and string.lower(target)==string.lower(myself)) then
        return false,'Select a different disposal recipient in Storage Cleanup' end
    if WGRMail.waitingForSend or WGRMail.prepareAll or not WGRMailDraftClear() then
        return false,'Finish or clear the current outgoing mail draft first' end
    if not (WGROpenSendMailTab and WGRStorageCleanupDisposalMailCandidates) then
        return false,'Disposal mail preparation unavailable' end
    -- The list is acquired after Blizzard switches to the Send tab; checking
    -- it earlier could race an inventory movement or a draft change.
    WGROpenSendMailTab(function()
        if not WGRMail.mailboxOpen or not WGRMailDraftClear() or WGRMail.waitingForSend then
            WGRMailStatus('Clear the outgoing mail draft before preparing disposal.',1,.5,.2)
            return
        end
        local usingBlizzardSendUI = WGRMailUsingBlizzardSendUI()
        local candidates=WGRStorageCleanupDisposalMailCandidates(binding)
        if #candidates==0 then
            WGRMailStatus('No verified DISPOSE copies of this binding in Bags.',1,.7,.3)
            print('|cffffaa00WBGR:|r No currently marked/mailable DISPOSE items of this type in Bags.')
            return
        end
        local attached,entries=0,{}
        if usingBlizzardSendUI then
            SendMailNameEditBox:SetText(recipient)
            SendMailSubjectEditBox:SetText('WBGR Disposal')
        end
        for _,item in ipairs(candidates) do
            if attached>=WGR_MAIL_MAX then break end
            local link=C_Container.GetContainerItemLink(item.bagID,item.slotID)
            if link==item.itemLink and
                WGRStorageCleanupGetPhysicalCopyGUID(item.bagID,item.slotID,link)==item.guid and
                WGRStorageCleanupIsDisposeCopy(item.bagID,item.slotID,link) and
                IsTransferableContainerItem(item.bagID,item.slotID,link) then
                C_Container.PickupContainerItem(item.bagID,item.slotID)
                ClickSendMailItemButton(attached+1)
                local attachedLink=GetSendMailItemLink and GetSendMailItemLink(attached+1)
                if attachedLink==link then
                    attached=attached+1
                    entries[#entries+1]={guid=item.guid,itemLink=link}
                else
                    -- Do not prepare a partial ambiguous send. Player must
                    -- clear the draft manually; we never send or delete gear.
                    WGRMailStatus('Attachment could not be verified; clear the draft.',1,.3,.3)
                    print('|cffff5555WBGR:|r Could not verify disposal attachment; clear the mail draft manually.')
                    return
                end
            end
        end
        if attached==0 then
            if usingBlizzardSendUI then
                SendMailNameEditBox:SetText('')
                SendMailSubjectEditBox:SetText('')
            end
            WGRMailStatus('No disposal copies could be attached.',1,.7,.2)
            return
        end
        WGRMail.preparedDisposalDraft={recipient=recipient,entries=entries}
        WGRMail.pendingDisposalSendValid=false
        WGRMail.waitingForSend=true
        WGRMail.preparedRecipient=recipient
        WGRMail.preparedSubject='WBGR Disposal'
        WGRMail.preparedCount=attached
        WGRMail.ownsDraft=true
        WGRMailStorePreparedAttachmentSnapshot()
        local message
        if usingBlizzardSendUI then
            message=string.format('Prepared %d DISPOSE item(s) for %s. Review and press Send; nothing sent automatically.',attached,recipient)
        else
            message=string.format('Prepared %d DISPOSE item(s) for %s. Review if desired, then use Send Prepared; nothing sent automatically.',attached,recipient)
        end
        WGRMailStatus(message,1,.55,.8)
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
    end)
    return true
end

-- Validate the actual send recipient and entire attachment multiset. No
-- attempt is made to recover a physical GUID from Blizzard's mail slots.
local function WGRMailPreparedDisposalMatchesActual(recipient)
    local prepared=WGRMail.preparedDisposalDraft
    if not prepared or not recipient then return false end
    local actual=WGRMailNormalizeCharacterName(recipient)
    local expected=WGRMailNormalizeCharacterName(prepared.recipient)
    if not actual or not expected or string.lower(actual)~=string.lower(expected) then
        return false end
    local counts={}
    for _,entry in ipairs(prepared.entries or {}) do
        counts[entry.itemLink]=(counts[entry.itemLink] or 0)+1
    end
    local n=0
    for slot=1,WGR_MAIL_MAX do
        local link=GetSendMailItemLink and GetSendMailItemLink(slot)
        if link then
            n=n+1
            counts[link]=(counts[link] or 0)-1
            if counts[link]<0 then return false end
        end
    end
    if n~=#(prepared.entries or {}) then return false end
    for _,left in pairs(counts) do if left~=0 then return false end end
    return true
end

WGRMailPrepareDestination=function(
    destName,
    fromAll
)
    if not WGRMail.mailboxOpen then
        return
    end

    WGRMailStatus("Opening Send Mail...")

    WGROpenSendMailTab(
        function()
            WGRMailStatus(
                "Validating gear for "
                    .. destName
                    .. "..."
            )

            local ok, err =
                pcall(
                    WGRMailPrepareDestinationInternal,
                    destName,
                    fromAll
                )

            if not ok then
                WGRMailStatus(
                    "Could not prepare "
                        .. destName
                        .. ". See chat for WBGR error.",
                    1.00, 0.30, 0.30
                )

                print(
                    "|cffff0000WBGR Mail error:|r "
                        .. tostring(err)
                )

                if fromAll then
                    WGRMailStop(
                        "Prepare All stopped: WBGR error."
                    )
                end
            end
        end
    )
end

local function WGRMailRemovePreparedAttachment(preparedIndex)
    if not WGRMail.mailboxOpen
        or WGRMailUsingBlizzardSendUI()
        or not WGRMail.waitingForSend
        or not WGRMail.ownsDraft
    then
        return
    end

    if WGRMail.removingPreparedAttachment then
        WGRMailStatus("Please wait for the previous attachment change to finish.",1,.65,.2)
        return
    end

    -- DISPOSE drafts retain exact physical-copy authorization. Keep those
    -- all-or-nothing in replacement-mailbox mode rather than silently
    -- changing the authorized GUID set from a UI-only attachment removal.
    if WGRMail.preparedDisposalDraft then
        WGRMailStatus("DISPOSE drafts cannot be trimmed here. Clear Draft and prepare a new disposal batch instead.",1,.65,.2)
        return
    end

    local matches = WGRMailPreparedAttachmentsMatch()
    if not matches then
        WGRMailStatus("Prepared attachments changed. Clear Draft and prepare the mail again before editing the batch.",1,.3,.3)
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
        return
    end

    local expectedLinks = WGRMail.preparedAttachmentLinks or {}
    local selectedLink = expectedLinks[preparedIndex]
    if not selectedLink then
        return
    end

    -- Rows are a compact prepared list, while Blizzard attachment slots may
    -- contain gaps. Find the matching occurrence of this exact item link in
    -- the live outgoing slots so duplicate identical links remain safe.
    local occurrence = 0
    for index = 1, preparedIndex do
        if expectedLinks[index] == selectedLink then
            occurrence = occurrence + 1
        end
    end

    local targetSlot = nil
    local seen = 0
    for _, entry in ipairs(WGRMailCurrentAttachmentEntries()) do
        if entry.link == selectedLink then
            seen = seen + 1
            if seen == occurrence then
                targetSlot = entry.slot
                break
            end
        end
    end

    if not targetSlot then
        WGRMailStatus("Could not identify that prepared attachment. Clear Draft and prepare again.",1,.3,.3)
        return
    end

    local expectedAfter = {}
    for index, link in ipairs(expectedLinks) do
        if index ~= preparedIndex then
            expectedAfter[#expectedAfter + 1] = link
        end
    end

    WGRMail.removingPreparedAttachment = true
    if WGRMailRefreshPreparedSendButton then
        WGRMailRefreshPreparedSendButton()
    end

    if RemoveSendMailItem then
        RemoveSendMailItem(targetSlot)
    else
        ClickSendMailItemButton(targetSlot)
        if CursorHasItem and CursorHasItem() and ClearCursor then
            ClearCursor()
        end
    end

    C_Timer.After(
        0.20,
        function()
            WGRMail.removingPreparedAttachment = false

            if not WGRMail.mailboxOpen
                or not WGRMail.waitingForSend
                or not WGRMail.ownsDraft
            then
                return
            end

            local settled, currentLinks, currentCounts =
                WGRMailAttachmentSnapshotMatchesLinks(expectedAfter)

            if not settled then
                WGRMailStatus("Attachment removal did not settle as expected. Clear Draft and prepare again before sending.",1,.3,.3)
                if WGRMailRefreshPreparedSendButton then
                    WGRMailRefreshPreparedSendButton()
                end
                return
            end

            if #currentLinks == 0 then
                WGRMailClearFields()
                WGRMailStatus("Removed the last prepared item. Draft cleared.",.75,.75,.75)
                if WGRMailScan then
                    WGRMailScan(function() WGRMailRefreshOverlays() end)
                end
                return
            end

            WGRMail.preparedAttachmentLinks = currentLinks
            WGRMail.preparedAttachmentCounts = currentCounts
            WGRMail.preparedCount = #currentLinks
            WGRMailResetPreparedReadiness()

            local itemName = nil
            if C_Item and C_Item.GetItemInfo then
                itemName = C_Item.GetItemInfo(selectedLink)
            elseif GetItemInfo then
                itemName = GetItemInfo(selectedLink)
            end

            WGRMailStatus(
                string.format(
                    "Removed %s from this batch. %d item%s remain prepared.",
                    tostring(itemName or "item"),
                    #currentLinks,
                    #currentLinks == 1 and "" or "s"
                ),
                .45,.85,1
            )

            if WGRMailRefreshPreparedSendButton then
                WGRMailRefreshPreparedSendButton()
            end
            if WGRMailScan then
                WGRMailScan(function() WGRMailRefreshOverlays() end)
            end
        end
    )
end

local function WGRMailGetUnderlyingSendAmount(getter)
    if not getter then
        return 0
    end

    local ok, amount = pcall(getter)
    if ok and type(amount) == "number" then
        return amount
    end

    return 0
end

local function WGRMailSendPreparedCustomDraft()
    if not WGRMail.mailboxOpen then
        WGRMailStatus("Open a mailbox first.",1,.3,.3)
        return
    end

    if WGRMailUsingBlizzardSendUI() then
        WGRMailStatus("Use Blizzard's Send button for the normal mailbox.",1,.65,.2)
        return
    end

    if not WGRMail.waitingForSend
        or not WGRMail.ownsDraft
        or not WGRMail.preparedRecipient
        or WGRMail.preparedRecipient == ""
    then
        WGRMailStatus("No WBGR mail draft is prepared.",1,.65,.2)
        return
    end

    local attachmentsMatch, attached =
        WGRMailPreparedAttachmentsMatch()

    if attached <= 0 then
        WGRMailStatus("No attachments remain in the prepared draft.",1,.45,.25)
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
        return
    end

    if not attachmentsMatch then
        WGRMailResetPreparedReadiness()
        WGRMailStatus(
            "Prepared attachments changed. Clear Draft and prepare the mail again before sending.",
            1,.3,.3
        )
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
        return
    end

    -- Replacement mailbox attachment APIs can settle over several UI/event
    -- ticks. Never send merely because one instantaneous snapshot matched;
    -- the exact reviewed set must remain stable first.
    if not WGRMail.preparedReady then
        WGRMailStatus("Prepared attachments are still settling. Try Send Prepared again once it becomes ready.",1,.65,.2)
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
        return
    end

    -- Never let the generic WBGR send button accidentally send money or COD
    -- that a replacement mailbox UI may have configured outside Blizzard's
    -- hidden money widgets.
    if WGRMailGetUnderlyingSendAmount(GetSendMailMoney) > 0
        or WGRMailGetUnderlyingSendAmount(GetSendMailCOD) > 0
    then
        WGRMailStatus("WBGR will not send while money or COD is set in the outgoing draft.",1,.3,.3)
        return
    end

    if not SendMail then
        WGRMailStatus("The game's SendMail function is unavailable.",1,.3,.3)
        return
    end

    local recipient = WGRMail.preparedRecipient
    local subject = WGRMail.preparedSubject or "Alt Gear"

    -- Refresh the exact shared attachment snapshot immediately before the
    -- user-authorized send. The existing secure SendMail post-hook remains
    -- authoritative for the actual recipient supplied to the game.
    WGRMailCaptureDraftItems(recipient)

    if WGRMail.frame and WGRMail.frame.sendPreparedButton then
        WGRMail.frame.sendPreparedButton:Disable()
        WGRMail.frame.sendPreparedButton:SetText("Sending...")
    end

    WGRMailStatus("Sending prepared mail to "..tostring(recipient).."...")

    local ok, err = pcall(
        SendMail,
        recipient,
        subject,
        ""
    )

    if not ok then
        WGRMailStatus("Could not send prepared mail: "..tostring(err),1,.3,.3)
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
    end
end

WGRMailPrepareNext=function()
    if not WGRMail.prepareAll or not WGRMail.mailboxOpen or WGRMail.waitingForSend then return end
    WGRMailScan(function()
        if not WGRMail.prepareAll or not WGRMail.mailboxOpen then return end
        if #WGRMail.destinations==0 then
            WGRMailStop("Prepare All complete.")
            return
        end
        WGRMailPrepareDestination(WGRMail.destinations[1].name,true)
    end)
end

local function WGRMailToggleAll()
    if WGRMail.prepareAll then
        WGRMailStop("Prepare All stopped.")
        return
    end
    if not WGRMailDraftClear() then
        WGRMailStatus("Clear the current mail draft first.",1,.3,.3)
        return
    end
    WGRMail.prepareAll=true
    WGRMail.frame.prepareAllButton:SetText("Stop")
    WGRMailStatus("Prepare All active.")
    WGRMailPrepareNext()
end

local WGRMailUpdateMailboxRouterButton

local function WGRMailGetSavedRouterPosition()
    local interface =
        WarboundGearRouterDB
        and WarboundGearRouterDB.interface

    local position =
        interface
        and interface.mailRouterPosition

    if type(position) ~= "table"
        or type(position.x) ~= "number"
        or type(position.y) ~= "number"
    then
        return nil
    end

    return position
end

local function WGRMailPositionRouterFrame(frame)
    if not frame then return end

    frame:ClearAllPoints()

    local position =
        WGRMailGetSavedRouterPosition()

    if position then
        frame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            position.x,
            position.y
        )
        return
    end

    if MailFrame then
        frame:SetPoint(
            "TOPLEFT",
            MailFrame,
            "TOPRIGHT",
            8,
            -18
        )
    else
        frame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            0,
            0
        )
    end
end

local function WGRMailSaveRouterPosition(frame)
    local interface =
        WarboundGearRouterDB
        and WarboundGearRouterDB.interface

    if not interface
        or not frame
        or not UIParent
        or not frame.GetCenter
        or not UIParent.GetCenter
    then
        return
    end

    local frameX, frameY =
        frame:GetCenter()
    local parentX, parentY =
        UIParent:GetCenter()

    if not frameX
        or not frameY
        or not parentX
        or not parentY
    then
        return
    end

    interface.mailRouterPosition = {
        x = frameX - parentX,
        y = frameY - parentY,
    }
end

local function WGRMailCreateFrame()
    if WGRMail.frame then return WGRMail.frame end
    local f=CreateFrame("Frame","WGRMailRouterFrame",UIParent,"BackdropTemplate")
    f:SetSize(240,540)
    f:SetFrameStrata("DIALOG")
    -- Match the main WBGR window's normal DIALOG priority while allowing
    -- whichever WBGR window the user interacts with to come to the front.
    -- This is intentionally limited to the two WBGR root windows.
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    local solidBackground =
        f:CreateTexture(nil,"BACKGROUND",nil,-8)
    solidBackground:SetPoint("TOPLEFT",f,"TOPLEFT",4,-4)
    solidBackground:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,4)
    solidBackground:SetColorTexture(.02,.02,.02,1)
    f.WGRSolidBackground = solidBackground

    function f:WGRApplyBackgroundOpacity()
        local interface = WarboundGearRouterDB and WarboundGearRouterDB.interface
        local percent = interface and interface.backgroundOpacity or 50
        percent = math.max(0,math.min(100,tonumber(percent) or 50))

        -- Match the main WBGR window's existing opacity curve exactly.
        if percent <= 50 then
            local legacyScale = percent / 50
            self:SetBackdropColor(.05,.05,.05,.96 * legacyScale)
            if self.WGRSolidBackground then
                self.WGRSolidBackground:SetAlpha(0)
            end
        else
            self:SetBackdropColor(.05,.05,.05,.96)
            local solidAlpha = (percent - 50) / 50
            if self.WGRSolidBackground then
                self.WGRSolidBackground:SetAlpha(solidAlpha)
            end
        end
    end

    f:WGRApplyBackgroundOpacity()

    local close =
        CreateFrame(
            "Button",
            nil,
            f,
            "UIPanelCloseButton"
        )

    close:SetPoint(
        "TOPRIGHT",
        f,
        "TOPRIGHT",
        -3,
        -3
    )

    close:SetScript(
        "OnClick",
        function()
            f:Hide()
        end
    )

    f:SetScript(
        "OnHide",
        function()
            if WGRMail.mailboxOpen then
                WGRMailStop(
                    "Mail Router closed."
                )
            end
            if WGRMailUpdateMailboxRouterButton and C_Timer then
                C_Timer.After(0, function()
                    if WGRMailUpdateMailboxRouterButton then
                        WGRMailUpdateMailboxRouterButton()
                    end
                end)
            end
        end
    )

    f:SetScript(
        "OnShow",
        function()
            if f.WGRApplyBackgroundOpacity then
                f:WGRApplyBackgroundOpacity()
            end
            if WGRMail.mailboxRouterButton then
                WGRMail.mailboxRouterButton:Hide()
            end
        end
    )

    local dragHandle =
        CreateFrame(
            "Frame",
            nil,
            f
        )

    dragHandle:SetPoint(
        "TOPLEFT",
        f,
        "TOPLEFT",
        8,
        -6
    )
    dragHandle:SetPoint(
        "TOPRIGHT",
        f,
        "TOPRIGHT",
        -34,
        -6
    )
    dragHandle:SetHeight(42)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript(
        "OnDragStart",
        function()
            f:StartMoving()
        end
    )
    dragHandle:SetScript(
        "OnDragStop",
        function()
            f:StopMovingOrSizing()
            WGRMailSaveRouterPosition(f)
        end
    )

    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",f,"TOP",0,-12)
    title:SetText("WBGR Mail Router")
    local sub=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    sub:SetPoint("TOP",title,"BOTTOM",0,-4)
    sub:SetText("Routing Mail")

    local checkMail=
        CreateFrame(
            "Button",
            nil,
            f,
            "UIPanelButtonTemplate"
        )

    checkMail:SetSize(
        96,
        21
    )

    checkMail:SetPoint(
        "TOP",
        sub,
        "BOTTOM",
        0,
        -5
    )

    checkMail:SetText(
        "Mail Tracker"
    )

    checkMail:SetScript(
        "OnClick",
        function()
            WGRMailShowTracker(true)
        end
    )

    local destinationScroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            f,
            "UIPanelScrollFrameTemplate"
        )

    destinationScroll:SetPoint(
        "TOPLEFT",
        f,
        "TOPLEFT",
        12,
        -100
    )

    destinationScroll:SetPoint(
        "BOTTOMRIGHT",
        f,
        "BOTTOMRIGHT",
        -30,
        214
    )

    local destinationContent =
        CreateFrame(
            "Frame",
            nil,
            destinationScroll
        )

    destinationContent:SetSize(
        180,
        1
    )

    destinationScroll:SetScrollChild(
        destinationContent
    )

    f.destinationScroll =
        destinationScroll

    f.destinationContent =
        destinationContent

    -- Replacement-mailbox mode cannot rely on a third-party Send page to
    -- show WBGR's recipient, subject, or attachments. Reuse the destination
    -- area as a WBGR-owned review panel while a custom draft is prepared.
    local preparedPanel = CreateFrame("Frame",nil,f)
    preparedPanel:SetPoint("TOPLEFT",destinationScroll,"TOPLEFT",0,0)
    preparedPanel:SetPoint("BOTTOMRIGHT",destinationScroll,"BOTTOMRIGHT",0,0)
    preparedPanel:Hide()
    f.preparedPanel = preparedPanel

    local preparedTitle=preparedPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    preparedTitle:SetPoint("TOPLEFT",preparedPanel,"TOPLEFT",0,0)
    preparedTitle:SetText("Prepared Mail")
    f.preparedTitle=preparedTitle

    local preparedRecipient=preparedPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    preparedRecipient:SetPoint("TOPLEFT",preparedTitle,"BOTTOMLEFT",0,-6)
    preparedRecipient:SetPoint("RIGHT",preparedPanel,"RIGHT",0,0)
    preparedRecipient:SetJustifyH("LEFT")
    f.preparedRecipientText=preparedRecipient

    local preparedSubject=preparedPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    preparedSubject:SetPoint("TOPLEFT",preparedRecipient,"BOTTOMLEFT",0,-3)
    preparedSubject:SetPoint("RIGHT",preparedPanel,"RIGHT",0,0)
    preparedSubject:SetJustifyH("LEFT")
    f.preparedSubjectText=preparedSubject

    local preparedCount=preparedPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    preparedCount:SetPoint("TOPLEFT",preparedSubject,"BOTTOMLEFT",0,-3)
    preparedCount:SetPoint("RIGHT",preparedPanel,"RIGHT",0,0)
    preparedCount:SetJustifyH("LEFT")
    f.preparedCountText=preparedCount

    local preparedHint=preparedPanel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    preparedHint:SetPoint("TOPLEFT",preparedCount,"BOTTOMLEFT",0,-3)
    preparedHint:SetPoint("RIGHT",preparedPanel,"RIGHT",0,0)
    preparedHint:SetJustifyH("LEFT")
    preparedHint:SetText("X removes an item from this batch.")
    f.preparedHintText=preparedHint

    local preparedScroll=CreateFrame("ScrollFrame",nil,preparedPanel,"UIPanelScrollFrameTemplate")
    preparedScroll:SetPoint("TOPLEFT",preparedHint,"BOTTOMLEFT",0,-6)
    preparedScroll:SetPoint("BOTTOMRIGHT",preparedPanel,"BOTTOMRIGHT",-20,0)
    local preparedContent=CreateFrame("Frame",nil,preparedScroll)
    preparedContent:SetSize(170,1)
    preparedScroll:SetScrollChild(preparedContent)
    f.preparedScroll=preparedScroll
    f.preparedContent=preparedContent
    f.preparedRows={}

    local disposeTitle=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    disposeTitle:SetPoint('BOTTOM',f,'BOTTOM',0,193)
    disposeTitle:SetText('DISPOSE Mail')
    f.disposeButtons={}
    for _,binding in ipairs({'WARBAND','BOE'}) do
        local button=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
        button:SetSize(210,24)
        button:SetPoint('BOTTOM',f,'BOTTOM',0,binding=='WARBAND' and 163 or 135)
        button:SetText(binding=='WARBAND' and 'Warbound DISPOSE (0)' or 'BoE DISPOSE (0)')
        button:SetScript('OnClick',function()
            local settings=WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings()
            local recipient=settings and (binding=='WARBAND' and
                settings.warboundRecipient or settings.boeRecipient)
            if WGRMailPrepareDisposalDraft then
                local ok,why=WGRMailPrepareDisposalDraft(recipient,binding)
                if not ok then WGRMailStatus(why or 'Cannot prepare disposal mail',1,.6,.2) end
            end
        end)
        f.disposeButtons[binding]=button
    end
    local all=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    all:SetSize(112,24)
    all:SetPoint("BOTTOM",f,"BOTTOM",0,72)
    all:SetText("Prepare All")
    all:SetScript("OnClick",WGRMailToggleAll)
    f.prepareAllButton=all

    local sendPrepared=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    sendPrepared:SetSize(132,24)
    sendPrepared:SetPoint("BOTTOM",f,"BOTTOM",0,103)
    sendPrepared:SetText("Send Prepared")
    sendPrepared:SetScript("OnClick",WGRMailSendPreparedCustomDraft)
    sendPrepared:Hide()
    f.sendPreparedButton=sendPrepared

    local rescan=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    rescan:SetSize(94,24)
    rescan:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",10,42)
    rescan:SetText("Rescan Gear")
    rescan:SetScript("OnClick",function()
        if WGRMail.waitingForSend then
            WGRMailStatus(
                "A mail draft is prepared. Send it, switch destinations, or Clear Draft.",
                1,.65,.2
            )
            return
        end

        WGRMailStatus("Rescanning carried gear...")
        WGRMailScan()
    end)

    local clearDraft=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    clearDraft:SetSize(94,24)
    clearDraft:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-10,42)
    clearDraft:SetText("Clear Draft")
    clearDraft:SetScript("OnClick",function()
        if WGRMailDraftClear() then
            WGRMailStatus("Mail draft is already empty.",.65,.65,.65)
            return
        end

        WGRMailStatus("Clearing mail draft...")

        WGRMailClearDraftAndRescan(
            "Mail draft cleared. Ready."
        )
    end)

    local status=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",10,10)
    status:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-10,10)
    status:SetJustifyH("LEFT")
    status:SetText("Ready.")
    f.status=status

    if UISpecialFrames then
        local alreadyRegistered =
            false

        for _, frameName
            in ipairs(
                UISpecialFrames
            )
        do
            if frameName
                == "WGRMailRouterFrame"
            then
                alreadyRegistered =
                    true
                break
            end
        end

        if not alreadyRegistered then
            table.insert(
                UISpecialFrames,
                "WGRMailRouterFrame"
            )
        end
    end

    f:Hide()
    WGRMail.frame=f
    return f
end

WGRMailRefreshPreparedDraftPanel = function()
    local frame = WGRMail and WGRMail.frame
    if not frame
        or not frame.preparedPanel
        or not frame.destinationScroll
    then
        return
    end

    local show =
        WGRMail.mailboxOpen
        and WGRMail.waitingForSend
        and WGRMail.ownsDraft
        and not WGRMailUsingBlizzardSendUI()

    if not show then
        frame.preparedPanel:Hide()
        frame.destinationScroll:Show()
        return
    end

    frame.destinationScroll:Hide()
    frame.preparedPanel:Show()

    frame.preparedRecipientText:SetText(
        "To: " .. tostring(WGRMail.preparedRecipient or "")
    )
    frame.preparedSubjectText:SetText(
        "Subject: " .. tostring(WGRMail.preparedSubject or "")
    )

    local matches, currentCount =
        WGRMailPreparedAttachmentsMatch()
    local expectedCount =
        type(WGRMail.preparedAttachmentLinks) == "table"
        and #WGRMail.preparedAttachmentLinks
        or 0

    if matches then
        frame.preparedCountText:SetText(
            "Attachments: " .. tostring(expectedCount) .. " (verified)"
        )
        frame.preparedCountText:SetTextColor(.35,1,.35)
    else
        frame.preparedCountText:SetText(
            "Attachments: "
                .. tostring(currentCount)
                .. "/"
                .. tostring(expectedCount)
                .. " - draft changed"
        )
        frame.preparedCountText:SetTextColor(1,.35,.35)
    end

    local links =
        type(WGRMail.preparedAttachmentLinks) == "table"
        and WGRMail.preparedAttachmentLinks
        or {}

    for index, row in ipairs(frame.preparedRows or {}) do
        if index > #links then
            row:Hide()
        end
    end

    local allowTrim = not WGRMail.preparedDisposalDraft
    if frame.preparedHintText then
        frame.preparedHintText:SetText(
            allowTrim
            and "X removes an item from this batch."
            or "DISPOSE batches stay exact; Clear Draft to restage."
        )
    end

    for index, link in ipairs(links) do
        local row = frame.preparedRows[index]
        if not row then
            row = CreateFrame("Frame",nil,frame.preparedContent)
            row:SetSize(165,18)

            row.label = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            row.label:SetPoint("LEFT",row,"LEFT",0,0)
            row.label:SetPoint("RIGHT",row,"RIGHT",-22,0)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)

            row.remove = CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
            row.remove:SetSize(20,18)
            row.remove:SetPoint("RIGHT",row,"RIGHT",0,0)
            row.remove:SetText("X")
            row.remove:SetScript(
                "OnClick",
                function(button)
                    local parent = button:GetParent()
                    if parent and parent.preparedIndex then
                        WGRMailRemovePreparedAttachment(parent.preparedIndex)
                    end
                end
            )
            row.remove:SetScript(
                "OnEnter",
                function(button)
                    GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
                    GameTooltip:SetText("Remove from this prepared batch",1,1,1)
                    GameTooltip:AddLine("Returns this item to Bags. It can be routed again later.",.8,.8,.8,true)
                    GameTooltip:Show()
                end
            )
            row.remove:SetScript("OnLeave",function() GameTooltip:Hide() end)

            frame.preparedRows[index] = row
        end

        row.preparedIndex = index
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",frame.preparedContent,"TOPLEFT",0,-((index-1)*20))

        local itemName = nil
        if C_Item and C_Item.GetItemInfo then
            itemName = C_Item.GetItemInfo(link)
        elseif GetItemInfo then
            itemName = GetItemInfo(link)
        end

        row.label:SetText(tostring(index) .. ". " .. tostring(itemName or link or "Unknown item"))
        if allowTrim then
            row.remove:Show()
            row.remove:SetEnabled(not WGRMail.removingPreparedAttachment)
        else
            row.remove:Hide()
        end
        row:Show()
    end

    frame.preparedContent:SetHeight(math.max(1,#links*20))
end

WGRMailRefreshPreparedSendButton = function()
    local button =
        WGRMail
        and WGRMail.frame
        and WGRMail.frame.sendPreparedButton

    if not button then
        return
    end

    local show =
        WGRMail.mailboxOpen
        and WGRMail.waitingForSend
        and WGRMail.ownsDraft
        and not WGRMailUsingBlizzardSendUI()

    if not show then
        button:Hide()
        button:Enable()
        button:SetText("Send Prepared")
        if WGRMailRefreshPreparedDraftPanel then
            WGRMailRefreshPreparedDraftPanel()
        end
        return
    end

    local matches, count =
        WGRMailPreparedAttachmentsMatch()

    WGRMail.preparedCount = count

    local ready = WGRMailUpdatePreparedReadiness(matches)

    button:Show()

    if WGRMail.removingPreparedAttachment then
        button:SetText("Updating...")
        button:Disable()
    elseif count <= 0 then
        button:SetText("No Attachments")
        button:Disable()
    elseif not matches then
        button:SetText("Draft Changed")
        button:Disable()
    elseif not ready then
        button:SetText("Preparing...")
        button:Disable()
    else
        button:SetText("Send Prepared")
        button:Enable()
    end

    if WGRMailRefreshPreparedDraftPanel then
        WGRMailRefreshPreparedDraftPanel()
    end
end

WGRMailSetMasterPaused =
    function(
        paused
    )
        if not WGRMail then
            return
        end

        WGRMailStop()

        WGRMail.destinations = {}

        if WGRMailUpdateRows then
            WGRMailUpdateRows()
        end

        if paused then
            if WGRMail.frame then
                WGRMail.frame:Hide()
            end
            return
        end

        -- Resume with fresh routing data when a mailbox is already open,
        -- but do not force the Mail Router window open.
        if WGRMail.mailboxOpen
            and WGRMailScan
        then
            WGRMailScan(
                function()
                    if WGRMail.frame
                        and WGRMail.frame:IsShown()
                    then
                        WGRMailUpdateRows()
                    end
                end
            )
        end
    end

WGRMailRetrieveTrackedForCurrent =
    function()
        if not WGRMail
            or not WGRMail.mailboxOpen
        then
            print(
                "|cffffcc00WBGR:|r Open a mailbox first."
            )
            return
        end

        local currentName =
            UnitName("player")

        if not currentName then
            return
        end

        local tracked =
            WGRMailGetTrackedList
            and WGRMailGetTrackedList()
            or {}

        local hasTracked = false

        for _, entry
            in ipairs(tracked)
        do
            if entry.name
                and string.lower(
                    entry.name
                ) == string.lower(
                    currentName
                )
            then
                hasTracked = true
                break
            end
        end

        local currentTracked =
            WGRMailResolveTrackedRecipient(
                currentName
            )

        local gearTracking =
            WGRMailGearTrackingTable()

        local currentGearEntry =
            currentTracked
            and gearTracking[
                string.lower(
                    currentTracked
                )
            ]
            or nil

        -- Prefer the item-aware MAIL ledger whenever it is available. Manual
        -- sends through Blizzard or replacement mailbox UIs do not necessarily
        -- use WBGR's legacy "Alt Gear" subject, but WBGR already records the
        -- expected sender + physical gear identity for each routed item.
        local expectedByKey = {}

        if currentGearEntry
            and type(
                currentGearEntry.items
            ) == "table"
        then
            for _, item
                in ipairs(
                    currentGearEntry.items
                )
            do
                local senderKey =
                    string.lower(
                        WGRMailNormalizeCharacterName(
                            item.sender
                        )
                        or ""
                    )

                local itemID =
                    tonumber(
                        item.itemID
                    )
                    or WGRMailItemID(
                        item.itemLink
                    )

                local gearKey =
                    item.gearKey

                if senderKey ~= ""
                    and itemID
                    and gearKey
                then
                    local matchKey =
                        senderKey
                        .. "\031"
                        .. tostring(
                            itemID
                        )
                        .. "\031"
                        .. tostring(
                            gearKey
                        )

                    expectedByKey[matchKey] =
                        (
                            expectedByKey[matchKey]
                            or 0
                        ) + 1
                end
            end
        end

        local useItemAwareTracking =
            next(
                expectedByKey
            ) ~= nil

        if not hasTracked
            and not useItemAwareTracking
        then
            print(
                "|cffffcc00WBGR:|r No WBGR-routed mail is currently tracked for "
                .. tostring(currentName)
                .. "."
            )
            return
        end

        local function InboxAttachmentMatchKey(
            mailIndex,
            attachmentIndex
        )
            local _, _, sender =
                GetInboxHeaderInfo(
                    mailIndex
                )

            local itemLink =
                GetInboxItemLink
                and GetInboxItemLink(
                    mailIndex,
                    attachmentIndex
                )
                or nil

            if not itemLink then
                return nil
            end

            local senderKey =
                string.lower(
                    WGRMailNormalizeCharacterName(
                        sender
                    )
                    or ""
                )

            local itemID =
                WGRMailItemID(
                    itemLink
                )

            local gearKey =
                WGRMailRawGearKeyForItem(
                    itemLink
                )

            if senderKey == ""
                or not itemID
                or not gearKey
            then
                return nil
            end

            return
                senderKey
                .. "\031"
                .. tostring(
                    itemID
                )
                .. "\031"
                .. tostring(
                    gearKey
                )
        end

        local function CountInboxMatchKey(
            targetKey
        )
            if not targetKey then
                return 0
            end

            local count = 0
            local countInbox =
                select(
                    1,
                    GetInboxNumItems()
                )
                or 0

            for mailIndex = 1, countInbox do
                for attachmentIndex = 1,
                    (
                        ATTACHMENTS_MAX_RECEIVE
                        or 16
                    )
                do
                    if InboxAttachmentMatchKey(
                        mailIndex,
                        attachmentIndex
                    ) == targetKey
                    then
                        count =
                            count + 1
                    end
                end
            end

            return count
        end

        -- Legacy fallback for older tracking records that predate the physical
        -- item-aware MAIL ledger. Keep the old subject/sender rule only when no
        -- item-aware expectation is available for this character.
        local function IsLegacyTrackedWGRMail(
            mailIndex
        )
            local _, _, sender, subject =
                GetInboxHeaderInfo(
                    mailIndex
                )

            return
                subject == "Alt Gear"
                and WGRMailSenderIsTrackedForCurrent
                and WGRMailSenderIsTrackedForCurrent(
                    sender
                )
        end

        local initialMailCount = 0
        local initialAttachmentCount = 0
        local remainingToRetrieve = {}

        local inboxCount =
            select(
                1,
                GetInboxNumItems()
            )
            or 0

        if useItemAwareTracking then
            local availableByKey = {}
            for key, count
                in pairs(
                    expectedByKey
                )
            do
                availableByKey[key] = count
            end

            for mailIndex = 1,
                inboxCount
            do
                local matchedInMail = 0

                for attachmentIndex = 1,
                    (
                        ATTACHMENTS_MAX_RECEIVE
                        or 16
                    )
                do
                    local matchKey =
                        InboxAttachmentMatchKey(
                            mailIndex,
                            attachmentIndex
                        )

                    local available =
                        matchKey
                        and availableByKey[matchKey]
                        or 0

                    if available > 0 then
                        availableByKey[matchKey] =
                            available - 1

                        remainingToRetrieve[matchKey] =
                            (
                                remainingToRetrieve[matchKey]
                                or 0
                            ) + 1

                        matchedInMail =
                            matchedInMail + 1
                        initialAttachmentCount =
                            initialAttachmentCount + 1
                    end
                end

                if matchedInMail > 0 then
                    initialMailCount =
                        initialMailCount + 1
                end
            end
        else
            for mailIndex = 1,
                inboxCount
            do
                if IsLegacyTrackedWGRMail(
                    mailIndex
                )
                then
                    local attachmentCount =
                        0

                    for attachmentIndex = 1,
                        (
                            ATTACHMENTS_MAX_RECEIVE
                            or 16
                        )
                    do
                        if GetInboxItem(
                            mailIndex,
                            attachmentIndex
                        )
                        then
                            attachmentCount =
                                attachmentCount + 1
                        end
                    end

                    if attachmentCount > 0 then
                        initialMailCount =
                            initialMailCount + 1
                        initialAttachmentCount =
                            initialAttachmentCount
                            + attachmentCount
                    end
                end
            end
        end

        if initialAttachmentCount == 0 then
            print(
                "|cffffcc00WBGR:|r No tracked WBGR-routed attachments were available to retrieve."
            )
            return
        end

        local attempts = 0
        local maxAttempts = 200
        local confirmedTaken = 0

        local function TakeNextTrackedAttachment()
            if not WGRMail
                or not WGRMail.mailboxOpen
            then
                return
            end

            attempts =
                attempts + 1

            if attempts > maxAttempts then
                print(
                    "|cffffcc00WBGR:|r Mail retrieval stopped before completion. Reopen the To Do tab and try again."
                )
                return
            end

            local currentInboxCount =
                select(
                    1,
                    GetInboxNumItems()
                )
                or 0

            for mailIndex = 1,
                currentInboxCount
            do
                local legacyMail =
                    not useItemAwareTracking
                    and IsLegacyTrackedWGRMail(
                        mailIndex
                    )

                for attachmentIndex = 1,
                    (
                        ATTACHMENTS_MAX_RECEIVE
                        or 16
                    )
                do
                    local itemName =
                        GetInboxItem(
                            mailIndex,
                            attachmentIndex
                        )

                    local matchKey =
                        useItemAwareTracking
                        and InboxAttachmentMatchKey(
                            mailIndex,
                            attachmentIndex
                        )
                        or nil

                    local itemAwareMatch =
                        useItemAwareTracking
                        and matchKey
                        and (
                            remainingToRetrieve[matchKey]
                            or 0
                        ) > 0

                    if itemName
                        and (
                            legacyMail
                            or itemAwareMatch
                        )
                    then
                        local originalLink =
                            GetInboxItemLink
                            and GetInboxItemLink(
                                mailIndex,
                                attachmentIndex
                            )
                            or nil

                        local originalMatchCount =
                            itemAwareMatch
                            and CountInboxMatchKey(
                                matchKey
                            )
                            or nil

                        TakeInboxItem(
                            mailIndex,
                            attachmentIndex
                        )

                        -- The mailbox UI can briefly continue reporting the
                        -- attachment after TakeInboxItem() succeeds. Wait until
                        -- the attachment actually disappears or changes before
                        -- moving on, so reindexing cannot cause a double-take.
                        local verifyAttempts = 0

                        local function VerifyTaken()
                            if not WGRMail
                                or not WGRMail.mailboxOpen
                            then
                                return
                            end

                            verifyAttempts =
                                verifyAttempts + 1

                            local currentItemName =
                                GetInboxItem(
                                    mailIndex,
                                    attachmentIndex
                                )

                            local currentLink =
                                currentItemName
                                and GetInboxItemLink
                                and GetInboxItemLink(
                                    mailIndex,
                                    attachmentIndex
                                )
                                or nil

                            local verifiedTaken = false

                            if itemAwareMatch
                                and matchKey
                            then
                                local currentMatchCount =
                                    CountInboxMatchKey(
                                        matchKey
                                    )

                                verifiedTaken =
                                    currentMatchCount
                                    < (
                                        originalMatchCount
                                        or 0
                                    )
                            else
                                local stillSame =
                                    currentItemName ~= nil
                                    and (
                                        originalLink == nil
                                        or currentLink
                                            == originalLink
                                    )

                                verifiedTaken =
                                    not stillSame
                            end

                            if not verifiedTaken
                                and verifyAttempts < 20
                            then
                                C_Timer.After(
                                    0.10,
                                    VerifyTaken
                                )
                                return
                            end

                            if not verifiedTaken then
                                print(
                                    "|cffffcc00WBGR:|r Mail retrieval paused because an attachment did not leave the inbox. Try again after the mailbox updates."
                                )
                                return
                            end

                            if itemAwareMatch
                                and matchKey
                            then
                                remainingToRetrieve[matchKey] =
                                    math.max(
                                        0,
                                        (
                                            remainingToRetrieve[matchKey]
                                            or 0
                                        ) - 1
                                    )
                            end

                            confirmedTaken =
                                confirmedTaken + 1

                            C_Timer.After(
                                0.05,
                                TakeNextTrackedAttachment
                            )
                        end

                        C_Timer.After(
                            0.10,
                            VerifyTaken
                        )
                        return
                    end
                end
            end

            local completionAttempt =
                0
            local previousFinalCount =
                nil

            local function FinishRetrieval()
                if not WGRMail
                    or not WGRMail.mailboxOpen
                then
                    return
                end

                completionAttempt =
                    completionAttempt + 1

                local finalAttachmentCount =
                    0

                if not useItemAwareTracking then
                    local finalInboxCount =
                        select(
                            1,
                            GetInboxNumItems()
                        )
                        or 0

                    for mailIndex = 1,
                        finalInboxCount
                    do
                        if IsLegacyTrackedWGRMail(
                            mailIndex
                        )
                        then
                            for attachmentIndex = 1,
                                (
                                    ATTACHMENTS_MAX_RECEIVE
                                    or 16
                                )
                            do
                                if GetInboxItem(
                                    mailIndex,
                                    attachmentIndex
                                )
                                then
                                    finalAttachmentCount =
                                        finalAttachmentCount
                                        + 1
                                end
                            end
                        end
                    end

                    -- Legacy subject-based mail can lag behind the actual item
                    -- transfer. Preserve the old stabilization wait for those
                    -- historical records.
                    if completionAttempt < 20
                        and (
                            finalAttachmentCount
                                >= initialAttachmentCount
                            or previousFinalCount
                                ~= finalAttachmentCount
                        )
                    then
                        previousFinalCount =
                            finalAttachmentCount

                        C_Timer.After(
                            0.15,
                            FinishRetrieval
                        )
                        return
                    end
                end

                local totalTaken =
                    useItemAwareTracking
                    and confirmedTaken
                    or math.max(
                        0,
                        initialAttachmentCount
                        - finalAttachmentCount
                    )

                if totalTaken > 0 then
                    WGRMailPendingRetrievalActivity = {
                        character =
                            currentName,
                        itemCount =
                            totalTaken,
                        mailCount =
                            initialMailCount,
                        activityLogged =
                            true,
                    }

                    local retrievalText =
                        tostring(currentName)
                        .. " retrieved "
                        .. tostring(totalTaken)
                        .. " routed item"
                        .. (
                            totalTaken == 1
                            and ""
                            or "s"
                        )
                        .. " from "
                        .. tostring(initialMailCount)
                        .. " mail"
                        .. (
                            initialMailCount == 1
                            and ""
                            or "s"
                        )
                        .. "."


                    if WGRAddRecentActivity then
                        WGRAddRecentActivity(
                            retrievalText,
                            "MAIL_RETRIEVED",
                            {
                                character =
                                    currentName,
                                itemCount =
                                    totalTaken,
                                mailCount =
                                    initialMailCount,
                            }
                        )
                    end
                end

                if WGRMailReconcileTrackedGearInbox then
                    WGRMailReconcileTrackedGearInbox()
                end

                WGRMailBeginInboxSession()

                if WGRRefreshTodoPage then
                    WGRRefreshTodoPage()
                end
            end

            C_Timer.After(
                0.15,
                FinishRetrieval
            )
        end

        TakeNextTrackedAttachment()
    end

WGRMailOpenRouterManual =
    function()
        if not WGRMail
            or not WGRMail.mailboxOpen
        then
            print(
                "|cffffcc00WBGR:|r Open a mailbox first to use the Mail Router."
            )
            return
        end

        local frame =
            WGRMailCreateFrame()

        WGRMailPositionRouterFrame(
            frame
        )

        frame:Show()

        WGRMailStatus(
            "Scanning carried bags..."
        )

        WGRMailScan(
            function()
                if not WGRMail.mailboxOpen
                    or not frame:IsShown()
                then
                    return
                end

                if #WGRMail.destinations == 0 then
                    WGRMailStatus(
                        "No SEND TO / HOLD ON gear in carried bags.",
                        0.65,
                        0.65,
                        0.65
                    )
                else
                    WGRMailStatus(
                        string.format(
                            "Ready. %d destination%s.",
                            #WGRMail.destinations,
                            #WGRMail.destinations == 1
                                and ""
                                or "s"
                        )
                    )
                end
            end
        )
    end

local function WGRMailGetMailboxMode()
    local interface =
        WarboundGearRouterDB
        and WarboundGearRouterDB.interface

    if interface then
        if interface.mailRouterMailboxMode == "AUTO"
            or interface.mailRouterMailboxMode == "BUTTON"
            or interface.mailRouterMailboxMode == "NONE"
        then
            return interface.mailRouterMailboxMode
        end

        -- Compatibility with v0.71m/n SavedVariables before the three-state
        -- mailbox preference existed.
        if interface.openMailRouterAutomatically == false then
            return "BUTTON"
        end
    end

    return "AUTO"
end

local function WGRMailShouldOpenAutomatically()
    return WGRMailGetMailboxMode() == "AUTO"
end

local function WGRMailShouldShowMailboxButton()
    return WGRMailGetMailboxMode() == "BUTTON"
end

local function WGRMailGetSavedMailboxButtonPosition()
    local interface =
        WarboundGearRouterDB
        and WarboundGearRouterDB.interface

    local position =
        interface
        and interface.mailRouterButtonPosition

    if type(position) ~= "table"
        or type(position.x) ~= "number"
        or type(position.y) ~= "number"
    then
        return nil
    end

    return position
end

local function WGRMailSaveMailboxButtonPosition(button)
    local interface =
        WarboundGearRouterDB
        and WarboundGearRouterDB.interface

    if not interface
        or not button
        or not UIParent
        or not button.GetCenter
        or not UIParent.GetCenter
    then
        return
    end

    local buttonX, buttonY =
        button:GetCenter()
    local parentX, parentY =
        UIParent:GetCenter()

    if not buttonX
        or not buttonY
        or not parentX
        or not parentY
    then
        return
    end

    interface.mailRouterButtonPosition = {
        x = buttonX - parentX,
        y = buttonY - parentY,
    }
end

local function WGRMailUsingBlizzardMailboxButtonAnchor()
    return WGRMailUsingBlizzardSendUI()
end

local function WGRMailPositionMailboxRouterButton(button)
    if not button or button.__WGRDragging then return end

    button:ClearAllPoints()

    if WGRMailUsingBlizzardMailboxButtonAnchor() then
        button:SetPoint(
            "LEFT",
            MailFrameTab2,
            "RIGHT",
            8,
            0
        )
    else
        -- Replacement mailbox UIs (for example TSM) may hide Blizzard's
        -- MailFrame while the real MailInfo interaction is still active. In
        -- that case use an independent, user-movable launcher position.
        local position =
            WGRMailGetSavedMailboxButtonPosition()

        if position then
            button:SetPoint(
                "CENTER",
                UIParent,
                "CENTER",
                position.x,
                position.y
            )
        else
            button:SetPoint(
                "TOP",
                UIParent,
                "TOP",
                0,
                -120
            )
        end
    end
end

local function WGRMailCreateMailboxRouterButton()
    if WGRMail.mailboxRouterButton then
        return WGRMail.mailboxRouterButton
    end

    local button =
        CreateFrame(
            "Button",
            "WGRMailboxRouterButton",
            UIParent,
            "UIPanelButtonTemplate"
        )

    button:SetSize(150, 24)
    button:SetText("WBGR Mail Router")
    button:SetFrameStrata("DIALOG")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:Hide()

    button:SetScript(
        "OnDragStart",
        function(self)
            if WGRMailUsingBlizzardMailboxButtonAnchor() then
                return
            end

            self.__WGRDragging = true
            self:StartMoving()
        end
    )

    button:SetScript(
        "OnDragStop",
        function(self)
            self:StopMovingOrSizing()

            if not WGRMailUsingBlizzardMailboxButtonAnchor() then
                WGRMailSaveMailboxButtonPosition(self)
            end

            local function finishDrag()
                self.__WGRDragging = false
                if WGRMailUpdateMailboxRouterButton then
                    WGRMailUpdateMailboxRouterButton()
                end
            end

            if C_Timer then
                C_Timer.After(0, finishDrag)
            else
                finishDrag()
            end
        end
    )

    button:SetScript(
        "OnClick",
        function(self)
            if self.__WGRDragging then
                return
            end

            if WGRMailOpenRouterManual then
                WGRMailOpenRouterManual()
            end
        end
    )

    button:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("WBGR Mail Router", 1.00, 0.82, 0.00)
            GameTooltip:AddLine(
                "Open the WBGR Mail Router for this mailbox.",
                1.00,
                1.00,
                1.00
            )
            if not WGRMailUsingBlizzardMailboxButtonAnchor() then
                GameTooltip:AddLine(
                    "Drag: Move button",
                    0.75,
                    0.75,
                    0.75
                )
            end
            GameTooltip:Show()
        end
    )

    button:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    WGRMail.mailboxRouterButton = button
    WGRMailPositionMailboxRouterButton(button)
    return button
end

WGRMailUpdateMailboxRouterButton = function()
    local button = WGRMailCreateMailboxRouterButton()
    local routerOpen = WGRMail and WGRMail.frame and WGRMail.frame:IsShown()

    if WGRMail and WGRMail.mailboxOpen and not routerOpen
        and WGRMailShouldShowMailboxButton() then
        WGRMailPositionMailboxRouterButton(button)
        button:Show()
    else
        button:Hide()
    end
end

local function WGRMailGetMailInteractionType()
    return Enum
        and Enum.PlayerInteractionType
        and Enum.PlayerInteractionType.MailInfo
end

local function WGRMailIsMailInteractionType(interactionType)
    local mailType = WGRMailGetMailInteractionType()
    return mailType ~= nil and interactionType == mailType
end

local function WGRMailIsMailboxInteractionActive()
    local mailType = WGRMailGetMailInteractionType()
    if not mailType
        or not C_PlayerInteractionManager
        or not C_PlayerInteractionManager.IsInteractingWithNpcOfType
    then
        return nil
    end

    local ok, active = pcall(
        C_PlayerInteractionManager.IsInteractingWithNpcOfType,
        mailType
    )
    if not ok then
        return nil
    end

    return active == true
end

local function WGRMailHandleMailboxHidden(forceClose, source)
    if not forceClose and WGRMailIsMailboxInteractionActive() == true then
        WGRMailDebug(
            tostring(source or "Mailbox frame")
                .. " hidden while MailInfo interaction remains active; keeping mailboxOpen=true."
        )
        WGRMail.mailboxOpen = true
        WGRUpdateOpenRouterButton()
        WGRMailUpdateMailboxRouterButton()
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
        return false
    end

    WGRMailDebug(
        tostring(source or "Mailbox")
            .. " closed; setting mailboxOpen=false."
    )

    WGRMail.mailboxOpen = false
    if WGRDisposalMailEndInboxSession then WGRDisposalMailEndInboxSession() end

    WGRUpdateOpenRouterButton()
    WGRMailUpdateMailboxRouterButton()

    WGRMailStop()
    WGRMail.ownsDraft = false

    if WGRMail.frame then
        WGRMail.frame:Hide()
    end

    -- MAIL_CLOSED is not guaranteed to be the first/only signal when the
    -- mailbox UI disappears. Refresh To Do from the shared hide handler so
    -- the contextual Send button immediately returns to Mail or WBK.
    if WGRRefreshTodoPage then
        WGRRefreshTodoPage()
    end

    return true
end

if MailFrame
    and not MailFrame.__WGRHideHooked
then
    MailFrame:HookScript(
        "OnHide",
        function()
            -- Replacement mailbox addons such as TSM may hide Blizzard's
            -- MailFrame while the actual Retail MailInfo interaction remains
            -- open. Frame visibility is therefore only a fallback signal.
            WGRMailHandleMailboxHidden(false, "Blizzard MailFrame")
        end
    )

    MailFrame.__WGRHideHooked =
        true
end

if MailFrame
    and not MailFrame.__WGRShowHooked
then
    MailFrame:HookScript(
        "OnShow",
        function()
            -- A replacement mailbox can switch back to Blizzard's MailFrame
            -- without ending the underlying MailInfo interaction. Re-anchor
            -- the manual launcher immediately to the normal Send Mail tab.
            if WGRMail and WGRMail.mailboxOpen then
                WGRMailUpdateMailboxRouterButton()
                if WGRMailRefreshPreparedSendButton then
                    WGRMailRefreshPreparedSendButton()
                end
            end
        end
    )

    MailFrame.__WGRShowHooked =
        true
end

if MailFrameTab2
    and MailFrameTab2.HookScript
    and not MailFrameTab2.__WGRVisibilityHooked
then
    local function WGRMailRefreshMailboxButtonForTabVisibility()
        local function refresh()
            if WGRMail and WGRMail.mailboxOpen then
                WGRMailUpdateMailboxRouterButton()
                if WGRMailRefreshPreparedSendButton then
                    WGRMailRefreshPreparedSendButton()
                end
            end
        end

        -- Defer one frame so parent/interaction visibility changes settle
        -- before deciding between the Blizzard anchor and custom fallback.
        if C_Timer then
            C_Timer.After(0, refresh)
        else
            refresh()
        end
    end

    MailFrameTab2:HookScript(
        "OnShow",
        WGRMailRefreshMailboxButtonForTabVisibility
    )
    MailFrameTab2:HookScript(
        "OnHide",
        WGRMailRefreshMailboxButtonForTabVisibility
    )

    MailFrameTab2.__WGRVisibilityHooked =
        true
end

local WGRMailDraftWatch =
    CreateFrame(
        "Frame"
    )

WGRMailDraftWatch.elapsed =
    0

WGRMailDraftWatch:SetScript(
    "OnUpdate",
    function(
        self,
        elapsed
    )
        if not WGRMail
            or not WGRMail.waitingForSend
            or not WGRMail.ownsDraft
        then
            self.elapsed =
                0
            return
        end

        self.elapsed =
            (
                self.elapsed
                or 0
            )
            + elapsed

        if self.elapsed < 0.10 then
            return
        end

        self.elapsed =
            0

        local previousCount =
            tonumber(WGRMail.preparedCount)
            or 0

        WGRMail.preparedCount =
            WGRMailCountCurrentDraftItems()

        if WGRMailRefreshPreparedSendButton
            and (
                previousCount ~= WGRMail.preparedCount
                or not WGRMailUsingBlizzardSendUI()
            )
        then
            -- Replacement-mailbox drafts need repeated exact-set checks so
            -- Send Prepared only arms after the shared attachment state has
            -- remained stable for the settling window.
            WGRMailRefreshPreparedSendButton()
        end
    end
)

local WGRMailBagTodoRefresh =
    CreateFrame(
        "Frame"
    )

WGRMailBagTodoRefresh:RegisterEvent(
    "BAG_UPDATE_DELAYED"
)

local WGRMailBagTodoRefreshToken =
    0

WGRMailBagTodoRefresh:SetScript(
    "OnEvent",
    function()
        if WGRMail and WGRMail.mailboxOpen and WGRDisposalMailOnInboxChanged then
            C_Timer.After(.18,function()
                if WGRMail.mailboxOpen then WGRDisposalMailOnInboxChanged() end
            end)
        end
        WGRMailTodoSnapshotDirty =
            true

        if WGRRoutingIsPaused
            and WGRRoutingIsPaused()
        then
            return
        end

        if not WGRIsMainWindowShown
            or not WGRIsMainWindowShown()
        then
            return
        end

        -- Do not disturb a prepared outgoing draft. MAIL_SEND_SUCCESS
        -- performs its own authoritative post-send rescan.
        if WGRMail
            and WGRMail.waitingForSend
        then
            return
        end

        WGRMailBagTodoRefreshToken =
            WGRMailBagTodoRefreshToken
            + 1

        local token =
            WGRMailBagTodoRefreshToken

        C_Timer.After(
            0.35,
            function()
                if token
                    ~= WGRMailBagTodoRefreshToken
                then
                    return
                end

                if WGRRoutingIsPaused
                    and WGRRoutingIsPaused()
                then
                    return
                end

                if not WGRIsMainWindowShown
                    or not WGRIsMainWindowShown()
                then
                    return
                end

                if WGRMail
                    and WGRMail.waitingForSend
                then
                    return
                end

                if WGRMailRefreshCurrentTodoSnapshot then
                    WGRMailRefreshCurrentTodoSnapshot(
                        true
                    )
                end
            end
        )
    end
)

local WGRMailReturnApiHooked = false

-- Replacement mailbox UIs commonly bypass Blizzard's OpenMailDeleteButton and
-- call the underlying ReturnInboxItem(mailIndex) API directly.  Observe that
-- game-level return action generically so the existing item-aware return
-- lifecycle can distinguish Return-to-Sender from ordinary retrieval.
local function WGRMailInstallReturnApiHook()
    if WGRMailReturnApiHooked then
        return
    end

    if not hooksecurefunc or not ReturnInboxItem then
        return
    end

    hooksecurefunc(
        "ReturnInboxItem",
        function(mailIndex)
            -- Disposal mail has its own exact-batch return lifecycle. Preserve
            -- that path first; ordinary routed mail uses the cached item-aware
            -- return snapshot. The cache is deliberately consulted before any
            -- refresh because secure hooks run after ReturnInboxItem itself.
            local disposalReturn =
                WGRDisposalMailPrimeReturn
                and WGRDisposalMailPrimeReturn(mailIndex)

            if not disposalReturn then
                local staged = WGRMailPrimeReturn(mailIndex)

                -- Normally MAIL_SHOW / MAIL_INBOX_UPDATE keeps this cache
                -- current. If the user returns a newly-arrived message before
                -- the delayed cache refresh settles, make one best-effort live
                -- refresh while Blizzard may still expose the just-returned row.
                if not staged then
                    WGRMailRefreshReturnCache()
                    WGRMailPrimeReturn(mailIndex)
                end
            end
        end
    )

    WGRMailReturnApiHooked = true
end

local WGRMailReturnPreClickHooked = false

local function WGRMailInstallReturnPreClickHook()
    if WGRMailReturnPreClickHooked then
        return
    end

    if not OpenMailDeleteButton or not OpenMailDeleteButton.HookScript then
        return
    end

    OpenMailDeleteButton:HookScript(
        "PreClick",
        function()
            local mailIndex =
                InboxFrame
                and InboxFrame.openMailID
                or nil

            if not mailIndex then
                return
            end

            -- This Blizzard button serves both Delete and Return. Only stage
            -- a transfer when the open message is actually returnable.
            local canDelete = InboxItemCanDelete and InboxItemCanDelete(mailIndex)
            if canDelete then
                return
            end

            -- Disposal mail has its own return lifecycle. Never also stage
            -- it as ordinary holder mail, especially on a Removed alt.
            local disposalReturn=WGRDisposalMailPrimeReturn and
                WGRDisposalMailPrimeReturn(mailIndex)
            if not disposalReturn then WGRMailPrimeReturn(mailIndex) end
        end
    )

    WGRMailReturnPreClickHooked = true
end

local WGRMailEvents=CreateFrame("Frame")

WGRMailInstallReturnApiHook()
WGRMailInstallReturnPreClickHook()

WGRMailEvents:RegisterEvent("MAIL_SHOW")
WGRMailEvents:RegisterEvent("MAIL_CLOSED")
WGRMailEvents:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
WGRMailEvents:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
WGRMailEvents:RegisterEvent("MAIL_SEND_SUCCESS")
WGRMailEvents:RegisterEvent("MAIL_FAILED")
WGRMailEvents:RegisterEvent("BAG_UPDATE_DELAYED")
WGRMailEvents:RegisterEvent("MAIL_INBOX_UPDATE")
WGRMailEvents:RegisterEvent("MAIL_SEND_INFO_UPDATE")
WGRMailEvents:RegisterEvent("PLAYER_LOGOUT")
WGRMailEvents:RegisterEvent("PLAYER_LOGIN")
WGRMailEvents:SetScript("OnEvent",function(_,event,...)
    local eventArg1 = ...

    WGRMailDebug(
        "Mail event received: "
            .. tostring(event)
    )

    if event=="PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if not WGRMailIsMailInteractionType(eventArg1) then
            return
        end

        -- Retail's player-interaction lifecycle is authoritative for whether
        -- a mailbox is actually open. Custom mailbox addons may replace or
        -- hide Blizzard's MailFrame without ending this MailInfo interaction.
        WGRMail.mailboxOpen = true
        WGRUpdateOpenRouterButton()
        WGRMailDebug(
            "MailInfo interaction opened; mailboxOpen=true."
        )

        if WGRRefreshTodoPage then
            WGRRefreshTodoPage()
        end

    elseif event=="PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if not WGRMailIsMailInteractionType(eventArg1) then
            return
        end

        if WGRMail then
            WGRMail.returnInboxCache = nil
            WGRMail.pendingReturn = nil
        end

        WGRMailHandleMailboxHidden(
            true,
            "MailInfo interaction"
        )

    elseif event=="MAIL_SHOW" then
        WGRMailInstallReturnApiHook()
        WGRMailInstallReturnPreClickHook()
        WGRMailRefreshReturnCache()
        C_Timer.After(0.35, function()
            if WGRMail and WGRMail.mailboxOpen then
                WGRMailRefreshReturnCache()
            end
        end)

        WGRMail.mailboxOpen=true
        -- Keep the manual launcher hidden while Blizzard/custom mailbox UI
        -- finishes positioning and while WBGR decides whether the router will
        -- auto-open. This avoids the fallback button flashing mid-screen and
        -- then jumping to its mailbox anchor.
        WGRMailCreateMailboxRouterButton():Hide()
        if WGRDisposalMailStartInboxSession then
            WGRDisposalMailStartInboxSession()
        end
        WGRUpdateOpenRouterButton()

        if WGRRefreshTodoPage then
            WGRRefreshTodoPage()
        end

        WGRMailDebug(
            "MAIL_SHOW set mailboxOpen=true."
        )

        WGRMailStop()

        if WGRMailBeginInboxSession then
            WGRMailBeginInboxSession()
        end

        if CheckInbox then
            pcall(
                CheckInbox
            )
        end

        WGRMailQueueInboxScan()
        if WGRDisposalMailOnInboxChanged then
            WGRDisposalMailOnInboxChanged()
        end
        if C_Timer and WGRDisposalMailOnInboxChanged then
            C_Timer.After(.60,function()
                if WGRMail.mailboxOpen then WGRDisposalMailOnInboxChanged() end
            end)
        end

        C_Timer.After(
            0.60,
            function()
                if WGRMail
                    and WGRMail.mailboxOpen
                    and WGRMailReconcileTrackedGearInbox
                then
                    WGRMailReconcileTrackedGearInbox()
                end
            end
        )

        local f=WGRMailCreateFrame()
        WGRMailPositionRouterFrame(f)

        -- Do not expose destinations from an earlier scan/character while
        -- the mailbox and carried-bag item data are still settling.
        WGRMail.destinations = {}
        WGRMailUpdateRows()
        f:Hide()

        -- MAIL_SHOW can arrive before all carried item/equipment information
        -- is fully ready. A single delayed pass can still miss uncached items,
        -- so settle the initial destination list across a few short scans.
        local settleAttempt = 0
        local lastSignature = nil

        local function DestinationSignature()
            local parts = {}

            for _, destination
                in ipairs(
                    WGRMail.destinations
                )
            do
                parts[#parts + 1] =
                    string.lower(
                        destination.name
                        or ""
                    )
                    .. ":"
                    .. tostring(
                        destination.count
                        or 0
                    )
            end

            return table.concat(
                parts,
                "|"
            )
        end

        local function FinalizeInitialScan()
            if not WGRMail.mailboxOpen then
                return
            end

            if #WGRMail.destinations > 0 or
                (WGRMailUpdateDisposeButtons and WGRMailUpdateDisposeButtons()) then
                if WGRMailShouldOpenAutomatically() then
                    f:Show()
                else
                    f:Hide()
                end
                WGRMailUpdateMailboxRouterButton()

                WGRMailStatus(#WGRMail.destinations>0 and
                    string.format('Ready. %d holder destination%s.',
                        #WGRMail.destinations,
                        #WGRMail.destinations==1 and '' or 's')
                    or 'Ready. DISPOSE Mail actions available.')
            else
                f:Hide()
                WGRMailUpdateMailboxRouterButton()
            end
        end

        local function SettleInitialScan()
            if not WGRMail.mailboxOpen then
                return
            end

            settleAttempt =
                settleAttempt + 1

            WGRMailScan(
                function()
                    if not WGRMail.mailboxOpen then
                        return
                    end

                    local signature =
                        DestinationSignature()

                    if signature == lastSignature
                        and settleAttempt >= 2
                    then
                        FinalizeInitialScan()
                        return
                    end

                    lastSignature =
                        signature

                    if settleAttempt >= 5 then
                        FinalizeInitialScan()
                        return
                    end

                    C_Timer.After(
                        0.25,
                        SettleInitialScan
                    )
                end
            )
        end

        C_Timer.After(
            0.25,
            SettleInitialScan
        )
    elseif event=="MAIL_SEND_INFO_UPDATE" then
        WGRMailCaptureDraftItems()
        if WGRMail and WGRMail.ownsDraft then
            -- Any attachment-state event restarts the readiness window. A
            -- replacement mailbox may emit several while one batch settles.
            WGRMailResetPreparedReadiness()
            WGRMail.preparedCount = WGRMailCountCurrentDraftItems()
            if WGRMailRefreshPreparedSendButton then
                WGRMailRefreshPreparedSendButton()
            end
        end

    elseif event=="MAIL_INBOX_UPDATE" then
        WGRMailQueueInboxScan()
        if C_Timer and WGRDisposalMailOnInboxChanged then
            C_Timer.After(.25,function()
                if WGRMail.mailboxOpen then WGRDisposalMailOnInboxChanged() end
            end)
        end

        -- A Return is staged before Blizzard processes it.  Finalize that
        -- physical MAIL -> MAIL transfer only after the inbox update settles
        -- and the original message is no longer observable.  Do this before
        -- rebuilding the return cache or normal inbox reconciliation so the
        -- staged sender/item identity cannot be overwritten by shifted rows.
        C_Timer.After(
            0.20,
            function()
                if not (WGRMail and WGRMail.mailboxOpen) then
                    return
                end

                WGRMailFinalizePendingReturn()
                if WGRDisposalMailFinalizeReturn then
                    WGRDisposalMailFinalizeReturn()
                end
                WGRMailRefreshReturnCache()
            end
        )

        C_Timer.After(
            0.35,
            function()
                if WGRMail
                    and WGRMail.mailboxOpen
                    and WGRMailReconcileTrackedGearInbox
                then
                    -- One last return-finalization attempt covers clients
                    -- whose first inbox update fires before the row vanishes.
                    WGRMailFinalizePendingReturn()
                    WGRMailReconcileTrackedGearInbox()
                    WGRMailRefreshReturnCache()
                end
            end
        )

    elseif event=="MAIL_CLOSED" then
        -- MAIL_CLOSED / MailFrame visibility are legacy/fallback signals.
        -- Do not tear down WBGR while Retail still reports an active MailInfo
        -- interaction (for example when TSM replaces Blizzard's MailFrame).
        if WGRMailIsMailboxInteractionActive() == true then
            WGRMailDebug(
                "MAIL_CLOSED received while MailInfo interaction remains active; ignoring legacy close signal."
            )
            WGRMail.mailboxOpen = true
            WGRUpdateOpenRouterButton()
            WGRMailUpdateMailboxRouterButton()
            return
        end

        if WGRDisposalMailEndInboxSession then WGRDisposalMailEndInboxSession() end
        if WGRMail then
            WGRMail.returnInboxCache = nil
            WGRMail.pendingReturn = nil
        end
        WGRMailHandleMailboxHidden(true, "MAIL_CLOSED")

        if WGRRefreshTodoPage then
            WGRRefreshTodoPage()
        end
    elseif event=="MAIL_SEND_SUCCESS" then
        local continue=WGRMail.prepareAll

        local pendingGearDraft =
            WGRMail.pendingGearDraft

        -- Only the argument supplied to WoW's actual SendMail call is
        -- authoritative. The Mail Router's preparedRecipient and an earlier
        -- draft snapshot may be stale after the player edits the recipient.
        -- If the secure SendMail post-hook did not capture a recipient, fail
        -- closed rather than inventing a delivery / Retrieve Mail To Do.
        local sentRecipient = WGRMail.pendingSendRecipient

        local sentCount =
            tonumber(
                WGRMail.preparedCount
            )
            or 0

        -- preparedCount is continuously synchronized with the actual
        -- outgoing draft while WGR owns it, so manual attachment removals
        -- are reflected in the activity log.

        local isDisposalSend=sentRecipient and WGRMail.pendingDisposalSendValid and
            WGRMail.preparedDisposalDraft and
            WGRMailNormalizeCharacterName(sentRecipient) and
            string.lower(WGRMailNormalizeCharacterName(sentRecipient))==
            string.lower(WGRMailNormalizeCharacterName(WGRMail.preparedDisposalDraft.recipient) or '')
        if isDisposalSend and WGRDisposalMailQueueConfirmedSend then
            local verified,pending,queued=WGRDisposalMailQueueConfirmedSend(
                WGRMail.preparedDisposalDraft.entries,sentRecipient,UnitName('player'))
            if not queued then
                print('|cffffaa00WBGR:|r Disposal mail sent, but physical mark authorization changed. No unverified retrieval task created.')
            elseif pending>0 then
                print('|cffffaa00WBGR:|r DISPOSE mail successfully sent; '..
                    tostring(pending)..' copy/copies awaiting Bag GUID departure verification. WBGR will retry; do not collect the mail yet.')
            end
        end
        -- A deliberate disposal send to its configured recipient is NOT a
        -- normal holder delivery. An edited recipient or attachments are
        -- handled by the existing ordinary-mail tracking instead.
        if sentRecipient and not isDisposalSend then
            local trackedGearCommitted, trackedRecipient =
                WGRMailCommitGearSend(
                    sentRecipient,
                    pendingGearDraft
                )

            -- Any qualifying tracked gear mailed to a tracked roster
            -- character needs the same Retrieve Mail To Do reminder, whether
            -- it was sent by WBGR Mail Router or through the normal mail UI.
            -- This remains separate from Gear Search's physical MAIL record.
            if trackedGearCommitted
                and trackedRecipient
                and WGRMailRecordSend
            then
                WGRMailRecordSend(
                    trackedRecipient
                )
            end

            -- Log any successful movement of WBGR-tracked gear into the
            -- tracked roster, whether it was sent through Mail Router or
            -- manually through the normal WoW mail UI.  Count only the
            -- qualifying tracked gear attachments; unrelated attachments in
            -- the same message are intentionally ignored by WBGR.
            if trackedGearCommitted
                and trackedRecipient
                and WGRAddRecentActivity
            then
                local sender =
                    UnitName("player")
                    or "Current character"

                local trackedSentCount = 0

                if pendingGearDraft
                    and type(pendingGearDraft.items) == "table"
                then
                    trackedSentCount =
                        #pendingGearDraft.items
                end

                -- Mail Router already knows its prepared tracked count. Keep
                -- that as a fallback if the persisted draft did not expose
                -- the item list for some reason.
                if trackedSentCount <= 0 then
                    trackedSentCount =
                        tonumber(sentCount)
                        or 0
                end

                if trackedSentCount > 0 then
                    WGRAddRecentActivity(
                        tostring(sender)
                        .. " sent "
                        .. tostring(trackedSentCount)
                        .. " item"
                        .. (
                            trackedSentCount == 1
                            and ""
                            or "s"
                        )
                        .. " to "
                        .. tostring(trackedRecipient)
                        .. ".",
                        "MAIL_SENT"
                    )
                end
            end
        end

        -- A manually overridden destination should not automatically
        -- continue Mail Router's Prepare All sequence.
        if continue
            and WGRMail.preparedRecipient
            and (
                not sentRecipient
                or string.lower(WGRMailNormalizeCharacterName(sentRecipient) or "")
                    ~= string.lower(WGRMailNormalizeCharacterName(WGRMail.preparedRecipient) or "")
            )
        then
            continue = false
            WGRMail.prepareAll = false
            if WGRMail.frame and WGRMail.frame.prepareAllButton then
                WGRMail.frame.prepareAllButton:SetText("Prepare All")
            end
        end

        WGRMail.waitingForSend=false
        WGRMail.preparedRecipient=nil
        WGRMail.preparedSubject=nil
        WGRMail.preparedCount=0
        WGRMail.preparedAttachmentLinks=nil
        WGRMail.preparedAttachmentCounts=nil
        WGRMailResetPreparedReadiness()
        WGRMail.pendingSendRecipient=nil
        WGRMail.pendingGearDraft=nil
        WGRMail.preparedDisposalDraft=nil
        WGRMail.pendingDisposalSendValid=false
        WGRMail.ownsDraft=false
        WGRMail.removingPreparedAttachment=false
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
        C_Timer.After(.35,function()
            if not WGRMail.mailboxOpen then return end
            WGRMailScan(function()
                WGRMailRefreshOverlays()

                if WGRRefreshTodoPage then
                    WGRRefreshTodoPage()
                end

                if continue and WGRMail.prepareAll then
                    C_Timer.After(.2,WGRMailPrepareNext)
                else
                    WGRMailStatus("Mail sent. Ready.")
                end
            end)
        end)
    elseif event=="BAG_UPDATE_DELAYED" then
        if WGRDisposalMailTryConfirmPendingSends then
            -- Empty pending queues return immediately; no surplus scan.
            local confirmed=WGRDisposalMailTryConfirmPendingSends()
            -- Successful background verification is reflected in To Do/Recent Activity; keep chat quiet.
        end
    elseif event=="MAIL_FAILED" then
        -- A later successful attempt must capture its own SendMail argument.
        -- Keep the unsent draft itself available for retry.
        WGRMail.pendingSendRecipient = nil
        WGRMail.pendingDisposalSendValid=false
        if WGRMailRefreshPreparedSendButton then
            WGRMailRefreshPreparedSendButton()
        end
    elseif event=="PLAYER_LOGIN" then
        WGRCreateMinimapButton()
        if WGRDisposalMailResumeSenderPending then
            C_Timer.After(2.0,WGRDisposalMailResumeSenderPending)
        end

        C_Timer.After(
            2.0,
            WGRMailShowLoginReminder
        )

    elseif event=="PLAYER_LOGOUT" then
        if WGRDisposalMailEndInboxSession then WGRDisposalMailEndInboxSession() end
        if WGRMailTodoSnapshotDirty
            and not (
                WGRRoutingIsPaused
                and WGRRoutingIsPaused()
            )
            and not (
                WGRMail
                and WGRMail.waitingForSend
            )
        then
            WGRMailScan()
        end

        WGRMailStop()
    end
end)


-- Capture ordinary/manual sends without replacing or wrapping Blizzard's
-- SendMail function. MAIL_SEND_INFO_UPDATE normally keeps the attachment
-- snapshot current. This secure post-hook records the recipient argument of
-- the actual outgoing API call; neither the suggested routing destination
-- nor the earlier draft's recipient is proof of where the player sent mail.
if hooksecurefunc and SendMail then
    hooksecurefunc(
        "SendMail",
        function(recipient)
            WGRMail.pendingSendRecipient =
                recipient and strtrim(tostring(recipient)) ~= "" and recipient or nil
            WGRMail.pendingDisposalSendValid=
                WGRMailPreparedDisposalMatchesActual(WGRMail.pendingSendRecipient)

            local current = WGRMail.pendingGearDraft
            if not current or #(current.items or {}) == 0 then
                WGRMailCaptureDraftItems(recipient)
            elseif recipient and recipient ~= "" then
                current.recipient = recipient
            end
        end
    )
end
