-- Mail-router runtime: mailbox scanning, send queue, event handling,
-- mail-frame hooks, and routing callbacks.

-- ============================================================
-- WGR MAIL ROUTER v0.23
-- ============================================================
WGRMail = {
    frame=nil, rows={}, destinations={}, prepareAll=false,
    waitingForSend=false, preparedRecipient=nil, preparedCount=0, mailboxOpen=false,
    ownsDraft=false, replacingDraft=false,
}
local WGR_MAIL_MAX = ATTACHMENTS_MAX_SEND or 12

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
                else
                    -- Until at least one expected attachment has been
                    -- positively observed, do not erase a freshly-sent
                    -- record merely because inbox population can lag behind
                    -- MAIL_SHOW/MAIL_INBOX_UPDATE.
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

local function WGRMailStatus(text,r,g,b)
    if WGRMail.frame and WGRMail.frame.status then
        WGRMail.frame.status:SetText(text or "")
        WGRMail.frame.status:SetTextColor(r or .85,g or .85,b or .85)
    end
end

local function WGRMailStop(text)
    WGRMail.prepareAll=false
    WGRMail.waitingForSend=false
    WGRMail.preparedRecipient=nil
    WGRMail.preparedCount=0
    if WGRMail.frame and WGRMail.frame.prepareAllButton then
        WGRMail.frame.prepareAllButton:SetText("Prepare All")
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

local function WGRMailDraftClear()
    if WGRMailText(SendMailNameEditBox) ~= "" then return false end
    if WGRMailText(SendMailSubjectEditBox) ~= "" then return false end
    if WGRMailText(SendMailBodyEditBox) ~= "" then return false end
    if WGRMailHasAttachments() then return false end

    if WGRMailMoneyAmount(SendMailMoney) > 0 then
        return false
    end

    if WGRMailMoneyAmount(SendMailCOD) > 0 then
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

    if WGRMailHasAttachments() then
        return false
    end

    return true
end

local function WGRMailClearFields()
    if SendMailNameEditBox then
        SendMailNameEditBox:SetText("")
    end

    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText("")
    end

    if SendMailBodyEditBox then
        SendMailBodyEditBox:SetText("")
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
    WGRMail.ownsDraft = false
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
            if link and IsTransferableContainerItem(bag,slot,link) then
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

    if #WGRMail.destinations==0 then
        WGRMailStatus(
            "No SEND TO / HOLD ON gear in carried bags.",
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

    -- If the Send Mail pane is already the selected mail tab,
    -- continue immediately.
    if PanelTemplates_GetSelectedTab
        and MailFrame
        and PanelTemplates_GetSelectedTab(
            MailFrame
        ) == 2
    then
        if callback then
            callback()
        end
        return
    end

    -- Use Blizzard's actual mail-tab selection function rather
    -- than relying on Button:Click().
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
    end

    -- Give Blizzard one frame to finish changing panes.
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

        SendMailNameEditBox:SetText(destName)
        SendMailSubjectEditBox:SetText("Alt Gear")
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
            SendMailNameEditBox:SetText("")
            SendMailSubjectEditBox:SetText("")
            WGRMailStatus("No items could be attached for "..destName..".",1,.45,.25)
            if fromAll then WGRMailStop("Prepare All stopped: attachment failed.") end
            return
        end

        WGRMail.waitingForSend=true
        WGRMail.preparedRecipient=destName
        WGRMail.preparedCount=attached
        WGRMail.ownsDraft=true
        WGRMailStatus(
            string.format("Prepared %d item%s for %s. Review, then press Send.",
                attached,attached==1 and "" or "s",destName),
            1,.35,.82
        )
        WGRMailScan(
            function()
                WGRMailRefreshOverlays()
            end
        )
    end)
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

local function WGRMailCreateFrame()
    if WGRMail.frame then return WGRMail.frame end
    local f=CreateFrame("Frame","WGRMailRouterFrame",UIParent,"BackdropTemplate")
    f:SetSize(220,430)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    f:SetBackdropColor(.05,.05,.05,.95)

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
        end
    )

    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",f,"TOP",0,-12)
    title:SetText("WBGR Mail Router")
    local sub=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    sub:SetPoint("TOP",title,"BOTTOM",0,-4)
    sub:SetText("Destination  -  Items")

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
        WGRMailShowTracker
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
        104
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

    local all=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    all:SetSize(112,24)
    all:SetPoint("BOTTOM",f,"BOTTOM",0,72)
    all:SetText("Prepare All")
    all:SetScript("OnClick",WGRMailToggleAll)
    f.prepareAllButton=all

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

        if not hasTracked then
            print(
                "|cffffcc00WBGR:|r No WBGR-routed mail is currently tracked for "
                .. tostring(currentName)
                .. "."
            )
            return
        end

        local initialMailCount = 0
        local initialAttachmentCount = 0

        local function IsTrackedWGRMail(
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

        local inboxCount =
            select(
                1,
                GetInboxNumItems()
            )
            or 0

        for mailIndex = 1, inboxCount do
            if IsTrackedWGRMail(
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

        if initialAttachmentCount == 0 then
            print(
                "|cffffcc00WBGR:|r No tracked WBGR-routed attachments were available to retrieve."
            )
            return
        end

        local attempts = 0
        local maxAttempts = 200

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
                if IsTrackedWGRMail(
                    mailIndex
                )
                then
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

                        if itemName then
                            local originalLink =
                                GetInboxItemLink
                                and GetInboxItemLink(
                                    mailIndex,
                                    attachmentIndex
                                )
                                or nil

                            TakeInboxItem(
                                mailIndex,
                                attachmentIndex
                            )

                            -- The mailbox UI can briefly continue reporting the
                            -- attachment after TakeInboxItem() succeeds. The old
                            -- code immediately rescanned and could click/count
                            -- that same attachment more than once. Wait until
                            -- the attachment actually disappears or changes
                            -- before incrementing the retrieved total.
                            local verifyAttempts = 0

                            local function VerifyTaken()
                                if not WGRMail
                                    or not WGRMail.mailboxOpen
                                then
                                    return
                                end

                                verifyAttempts =
                                    verifyAttempts + 1

                                local currentName =
                                    GetInboxItem(
                                        mailIndex,
                                        attachmentIndex
                                    )

                                local currentLink =
                                    currentName
                                    and GetInboxItemLink
                                    and GetInboxItemLink(
                                        mailIndex,
                                        attachmentIndex
                                    )
                                    or nil

                                local stillSame =
                                    currentName ~= nil
                                    and (
                                        originalLink == nil
                                        or currentLink
                                            == originalLink
                                    )

                                if stillSame
                                    and verifyAttempts < 20
                                then
                                    C_Timer.After(
                                        0.10,
                                        VerifyTaken
                                    )
                                    return
                                end

                                -- Do not increment a per-item counter here.
                                -- Blizzard can reindex mail/attachments while
                                -- retrieval is active. The final reported total
                                -- is calculated from tracked attachments before
                                -- retrieval minus tracked attachments remaining
                                -- after the final mailbox rescan.
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

                local finalInboxCount =
                    select(
                        1,
                        GetInboxNumItems()
                    )
                    or 0

                for mailIndex = 1,
                    finalInboxCount
                do
                    if IsTrackedWGRMail(
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

                -- Mailbox state can lag behind the actual item transfer.
                -- Wait until the final tracked-attachment count has dropped
                -- and then remained stable for a pass before logging/removing
                -- the To Do entry.
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

                local totalTaken =
                    math.max(
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

                    print(
                        "|cff33ff99WBGR:|r "
                        .. retrievalText
                    )

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

        frame:ClearAllPoints()

        frame:SetPoint(
            "TOPLEFT",
            MailFrame,
            "TOPRIGHT",
            8,
            -18
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

local function WGRMailHandleMailboxHidden()
    WGRMailDebug(
        "Mailbox hidden; setting mailboxOpen=false."
    )

    WGRMail.mailboxOpen = false

    WGRUpdateOpenRouterButton()

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
end

if MailFrame
    and not MailFrame.__WGRHideHooked
then
    MailFrame:HookScript(
        "OnHide",
        WGRMailHandleMailboxHidden
    )

    MailFrame.__WGRHideHooked =
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

        WGRMail.preparedCount =
            WGRMailCountCurrentDraftItems()
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

            WGRMailPrimeReturn(mailIndex)
        end
    )

    WGRMailReturnPreClickHooked = true
end

local WGRMailEvents=CreateFrame("Frame")

WGRMailInstallReturnPreClickHook()

WGRMailEvents:RegisterEvent("MAIL_SHOW")
WGRMailEvents:RegisterEvent("MAIL_CLOSED")
WGRMailEvents:RegisterEvent("MAIL_SEND_SUCCESS")
WGRMailEvents:RegisterEvent("MAIL_INBOX_UPDATE")
WGRMailEvents:RegisterEvent("MAIL_SEND_INFO_UPDATE")
WGRMailEvents:RegisterEvent("PLAYER_LOGOUT")
WGRMailEvents:RegisterEvent("PLAYER_LOGIN")
WGRMailEvents:SetScript("OnEvent",function(_,event)
    WGRMailDebug(
        "Mail event received: "
            .. tostring(event)
    )

    if event=="MAIL_SHOW" then
        WGRMailInstallReturnPreClickHook()
        WGRMailRefreshReturnCache()
        C_Timer.After(0.35, function()
            if WGRMail and WGRMail.mailboxOpen then
                WGRMailRefreshReturnCache()
            end
        end)

        WGRMail.mailboxOpen=true

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
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT",MailFrame,"TOPRIGHT",8,-18)

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

            if #WGRMail.destinations > 0 then
                f:Show()

                WGRMailStatus(
                    string.format(
                        "Ready. %d destination%s.",
                        #WGRMail.destinations,
                        #WGRMail.destinations==1 and "" or "s"
                    )
                )
            else
                f:Hide()
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

    elseif event=="MAIL_INBOX_UPDATE" then
        WGRMailQueueInboxScan()

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
        if WGRMail then
            WGRMail.returnInboxCache = nil
            WGRMail.pendingReturn = nil
        end
        WGRMailHandleMailboxHidden()

        if WGRRefreshTodoPage then
            WGRRefreshTodoPage()
        end
    elseif event=="MAIL_SEND_SUCCESS" then
        local continue=WGRMail.prepareAll

        local pendingGearDraft =
            WGRMail.pendingGearDraft

        local sentRecipient =
            WGRMail.preparedRecipient
            or WGRMail.pendingSendRecipient
            or (pendingGearDraft and pendingGearDraft.recipient)

        local sentCount =
            tonumber(
                WGRMail.preparedCount
            )
            or 0

        -- preparedCount is continuously synchronized with the actual
        -- outgoing draft while WGR owns it, so manual attachment removals
        -- are reflected in the activity log.

        if sentRecipient then
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

        WGRMail.waitingForSend=false
        WGRMail.preparedRecipient=nil
        WGRMail.preparedCount=0
        WGRMail.pendingSendRecipient=nil
        WGRMail.pendingGearDraft=nil
        WGRMail.ownsDraft=false
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
    elseif event=="PLAYER_LOGIN" then
        WGRCreateMinimapButton()

        C_Timer.After(
            2.0,
            WGRMailShowLoginReminder
        )

    elseif event=="PLAYER_LOGOUT" then
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
-- snapshot current; this secure post-hook supplies the final recipient name
-- and performs a last best-effort capture while the draft is still readable.
if hooksecurefunc and SendMail then
    hooksecurefunc(
        "SendMail",
        function(recipient)
            WGRMail.pendingSendRecipient = recipient

            local current = WGRMail.pendingGearDraft
            if not current or #(current.items or {}) == 0 then
                WGRMailCaptureDraftItems(recipient)
            elseif recipient and recipient ~= "" then
                current.recipient = recipient
            end
        end
    )
end
