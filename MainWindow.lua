-- Main WGR window, roster/settings tabs, and mailed-gear tracker UI/state.

-- ============================================================
-- WGR MAILED-GEAR TRACKER
-- ============================================================

local WGR_MAIL_LIFETIME =
    30 * 24 * 60 * 60

local WGR_MAIL_YELLOW =
    7 * 24 * 60 * 60

local WGR_MAIL_ORANGE =
    3 * 24 * 60 * 60

local WGR_MAIL_RED =
    24 * 60 * 60

local WGRMailTracker = {
    frame = nil,
    rows = {},
    loginReminderShown = false,
}

local WGR_RECENT_ACTIVITY_LIMIT =
    50

function WGRAddRecentActivity(
    text,
    activityType
)
    if not text
        or text == ""
    then
        return
    end

    InitializeDatabase()

    local activity =
        WarboundGearRouterDB.recentActivity

    table.insert(
        activity,
        1,
        {
            timestamp =
                time(),
            type =
                activityType
                or "INFO",
            text =
                tostring(text),
        }
    )

    while #activity
        > WGR_RECENT_ACTIVITY_LIMIT
    do
        table.remove(
            activity
        )
    end

    if WGRRefreshTodoPage then
        WGRRefreshTodoPage()
    end
end

function WGRRefreshTodoPage()
    local frame =
        WGRMailTracker.frame

    if frame
        and frame.UpdateTodoPage
    then
        frame.UpdateTodoPage()
    end
end


local WGR_MAIL_DEBUG =
    false

function WGRMailDebug(
    text
)
    if not WGR_MAIL_DEBUG then
        return
    end

    print(
        "|cff66ccffWBGR MAIL DEBUG:|r "
        .. tostring(
            text
        )
    )
end


local function WGRMailTrackingTable()
    InitializeDatabase()

    WarboundGearRouterDB.mailTracking =
        WarboundGearRouterDB.mailTracking
        or {}

    return
        WarboundGearRouterDB.mailTracking
end

function WGRMailRecordSend(
    recipient
)
    if not recipient
        or recipient == ""
    then
        return
    end

    local tracking =
        WGRMailTrackingTable()

    local key =
        string.lower(
            recipient
        )

    local entry =
        tracking[key]

    if not entry then
        entry = {
            name = recipient,
            sends = {},
        }

        tracking[key] =
            entry
    end

    entry.name =
        recipient

    table.insert(
        entry.sends,
        {
            timestamp =
                time(),
            sender =
                UnitName(
                    "player"
                ),
        }
    )

    WGRRefreshTodoPage()
end

local function WGRMailMarkChecked(
    recipient
)
    if not recipient then
        return
    end

    local tracking =
        WGRMailTrackingTable()

    local key =
        string.lower(
            recipient
        )

    local existed =
        tracking[key]
        ~= nil

    tracking[key] =
        nil

    if existed
        and WGRAddRecentActivity
    then
        local pending =
            WGRMailPendingRetrievalActivity

        if pending
            and pending.character
            and string.lower(
                tostring(
                    pending.character
                )
            ) == string.lower(
                tostring(
                    recipient
                )
            )
        then
            if not pending.activityLogged then
                WGRAddRecentActivity(
                    tostring(recipient)
                    .. " retrieved "
                    .. tostring(
                        pending.itemCount
                        or 0
                    )
                    .. " routed item"
                    .. (
                        (pending.itemCount or 0)
                        == 1
                        and ""
                        or "s"
                    )
                    .. " from "
                    .. tostring(
                        pending.mailCount
                        or 0
                    )
                    .. " mail"
                    .. (
                        (pending.mailCount or 0)
                        == 1
                        and ""
                        or "s"
                    )
                    .. ".",
                    "MAIL_RETRIEVED"
                )
            end

            WGRMailPendingRetrievalActivity =
                nil
        else
            WGRAddRecentActivity(
                tostring(recipient)
                .. " retrieved routed mail.",
                "MAIL_RETRIEVED"
            )
        end
    end

    WGRRefreshTodoPage()

    if WGRScheduleGearFinderRefresh then
        WGRScheduleGearFinderRefresh(
            0.10
        )
    end
end

local function WGRMailOldestTimestamp(
    entry
)
    if not entry
        or type(entry.sends)
            ~= "table"
        or #entry.sends == 0
    then
        return nil
    end

    local oldest =
        nil

    for _, sendRecord
        in ipairs(
            entry.sends
        )
    do
        local timestamp =
            nil

        if type(sendRecord)
            == "number"
        then
            -- Backward compatibility with v0.25/v0.25a.
            timestamp =
                sendRecord

        elseif type(sendRecord)
            == "table"
        then
            timestamp =
                sendRecord.timestamp
        end

        if type(timestamp)
                == "number"
            and (
                not oldest
                or timestamp < oldest
            )
        then
            oldest =
                timestamp
        end
    end

    return oldest
end

local function WGRMailTimeRemaining(
    entry
)
    local oldest =
        WGRMailOldestTimestamp(
            entry
        )

    if not oldest then
        return nil
    end

    return
        (oldest
            + WGR_MAIL_LIFETIME)
        - time()
end

function WGRMailFormatRemaining(
    seconds
)
    if not seconds then
        return "Unknown"
    end

    if seconds <= 0 then
        return "EXPIRED"
    end

    local days =
        math.floor(
            seconds / 86400
        )

    local hours =
        math.floor(
            (seconds % 86400)
            / 3600
        )

    if days > 0 then
        return string.format(
            "%dd %dh left",
            days,
            hours
        )
    end

    local minutes =
        math.max(
            0,
            math.floor(
                (seconds % 3600)
                / 60
            )
        )

    return string.format(
        "%dh %dm left",
        hours,
        minutes
    )
end

local function WGRMailUrgencyColor(
    seconds
)
    if not seconds
        or seconds <= WGR_MAIL_RED
    then
        return
            1.00, 0.20, 0.20
    end

    if seconds
        <= WGR_MAIL_ORANGE
    then
        return
            1.00, 0.55, 0.10
    end

    if seconds
        <= WGR_MAIL_YELLOW
    then
        return
            1.00, 0.85, 0.15
    end

    return
        0.90, 0.90, 0.90
end

function WGRMailGetTrackedList()
    local tracking =
        WGRMailTrackingTable()

    local list = {}

    for _, entry
        in pairs(tracking)
    do
        local remaining =
            WGRMailTimeRemaining(
                entry
            )

        if remaining then
            table.insert(
                list,
                {
                    name =
                        entry.name,
                    remaining =
                        remaining,
                    oldest =
                        WGRMailOldestTimestamp(
                            entry
                        ),
                }
            )
        end
    end

    table.sort(
        list,
        function(a, b)
            return a.remaining
                < b.remaining
        end
    )

    return list
end


local function WGRNormalizeMailName(
    name
)
    if not name then
        return nil
    end

    if Ambiguate then
        local ok, shortName =
            pcall(
                Ambiguate,
                name,
                "short"
            )

        if ok
            and shortName
            and shortName ~= ""
        then
            return string.lower(
                shortName
            )
        end
    end

    local short =
        tostring(name):match(
            "^([^%-]+)"
        )
        or tostring(name)

    return string.lower(
        short
    )
end

function WGRMailSenderIsTrackedForCurrent(
    sender
)
    local currentName =
        UnitName("player")

    if not currentName
        or not sender
    then
        return false
    end

    local tracking =
        WGRMailTrackingTable()

    local entry =
        tracking[
            string.lower(
                currentName
            )
        ]

    if not entry then
        return false
    end

    local normalizedSender =
        WGRNormalizeMailName(
            sender
        )

    if not normalizedSender then
        return false
    end

    for _, sendRecord
        in ipairs(
            entry.sends
            or {}
        )
    do
        if type(sendRecord)
            == "table"
            and sendRecord.sender
            and WGRNormalizeMailName(
                sendRecord.sender
            ) == normalizedSender
        then
            return true
        end
    end

    return false
end

local function WGRMailExpectedSenderCounts(
    entry
)
    local counts = {}
    local total = 0
    local legacyCount = 0

    if not entry
        or type(entry.sends)
            ~= "table"
    then
        return counts, total, legacyCount
    end

    for _, sendRecord
        in ipairs(
            entry.sends
        )
    do
        if type(sendRecord)
            == "table"
        then
            local sender =
                WGRNormalizeMailName(
                    sendRecord.sender
                )

            if sender then
                counts[sender] =
                    (counts[sender] or 0)
                    + 1

                total =
                    total + 1
            else
                -- Some short-lived development builds stored structured
                -- send records without a usable sender identity. Treat those
                -- the same as the older numeric legacy records so an empty
                -- recipient mailbox can safely purge the stale reminder.
                legacyCount =
                    legacyCount + 1
            end

        elseif type(sendRecord)
            == "number"
        then
            -- Old v0.25/v0.25a records lack sender identity,
            -- so automatic pickup detection cannot safely clear them.
            legacyCount =
                legacyCount + 1
        end
    end

    return counts, total, legacyCount
end

local WGRMailUpdateTrackerFrame

function WGRMailBeginInboxSession()
    local currentName =
        UnitName(
            "player"
        )

    if not currentName then
        return
    end

    local tracking =
        WGRMailTrackingTable()

    local entry =
        tracking[
            string.lower(
                currentName
            )
        ]

    if not entry then
        return
    end

    entry.seenInInbox =
        false

    entry.maxSeenTrackedMails =
        0

    entry.lastInboxSeenAt =
        nil
end

local function WGRMailScanTrackedInbox()
    if not WGRMail
        or not WGRMail.mailboxOpen
    then
        WGRMailDebug(
            "Inbox scan skipped: mailbox is not open."
        )
        return
    end

    local currentName =
        UnitName(
            "player"
        )

    if not currentName then
        WGRMailDebug(
            "Inbox scan skipped: current character name unavailable."
        )
        return
    end

    local tracking =
        WGRMailTrackingTable()

    local key =
        string.lower(
            currentName
        )

    local entry =
        tracking[key]

    if not entry then
        WGRMailDebug(
            "No tracked mail entry exists for "
                .. currentName
                .. "."
        )
        return
    end

    WGRMailDebug(
        "Tracked recipient found: "
            .. currentName
    )

    local expectedSenders,
          expectedCount,
          legacyCount =
        WGRMailExpectedSenderCounts(
            entry
        )

    WGRMailDebug(
        string.format(
            "Expected tracked sends: %d; legacy sends without sender data: %d.",
            expectedCount or 0,
            legacyCount or 0
        )
    )

    if legacyCount > 0 then
        local inboxCount =
            GetInboxNumItems
            and select(
                1,
                GetInboxNumItems()
            )
            or 0

        if inboxCount == 0 then
            WGRMailDebug(
                "Mailbox is empty; clearing stale legacy mail-tracking record for "
                    .. currentName
                    .. "."
            )

            -- Legacy senderless records cannot be matched safely to individual
            -- inbox messages.  An entirely empty mailbox is the one state that
            -- proves no tracked legacy mail can remain, so purge only this
            -- character's stale reminder without treating it as a retrieval.
            tracking[key] = nil

            WGRRefreshTodoPage()

            if WGRScheduleGearFinderRefresh then
                WGRScheduleGearFinderRefresh(
                    0.10
                )
            end

            return
        end

        WGRMailDebug(
            "Automatic clearing disabled for this character because one or more tracked sends are legacy records without sender identity."
        )
        return
    end

    if expectedCount <= 0 then
        WGRMailDebug(
            "No sender-aware tracked sends are available for automatic pickup detection."
        )
        return
    end

    local inboxCount =
        GetInboxNumItems
        and select(
            1,
            GetInboxNumItems()
        )
        or 0

    WGRMailDebug(
        "Inbox reports "
            .. tostring(
                inboxCount
            )
            .. " message(s)."
    )

    -- Self-heal sender-aware tracking that was never observed in the
    -- recipient inbox. Same-account mail should arrive immediately, but keep
    -- a short grace period so a transient mailbox/API race cannot erase a
    -- legitimate freshly-sent reminder. Only clear when the entire mailbox
    -- is empty and every sender-aware tracked send is at least 15 minutes old.
    if inboxCount == 0
        and entry.seenInInbox ~= true
    then
        local newestTrackedSendAt = nil
        local allTrackedSendsTimestamped = true

        for _, sendRecord
            in ipairs(
                entry.sends
                or {}
            )
        do
            if type(sendRecord) == "table"
                and WGRNormalizeMailName(
                    sendRecord.sender
                )
            then
                local sendTimestamp =
                    tonumber(
                        sendRecord.timestamp
                    )

                if sendTimestamp then
                    newestTrackedSendAt =
                        math.max(
                            newestTrackedSendAt
                                or sendTimestamp,
                            sendTimestamp
                        )
                else
                    allTrackedSendsTimestamped = false
                    break
                end
            end
        end

        local staleGraceSeconds = 15 * 60
        local now = time()

        if allTrackedSendsTimestamped
            and newestTrackedSendAt
            and (now - newestTrackedSendAt)
                >= staleGraceSeconds
        then
            WGRMailDebug(
                "Mailbox is empty and never-seen tracked mail is older than the 15-minute grace period; clearing stale mail reminder for "
                    .. currentName
                    .. "."
            )

            tracking[key] = nil

            WGRRefreshTodoPage()

            if WGRScheduleGearFinderRefresh then
                WGRScheduleGearFinderRefresh(
                    0.10
                )
            end

            return
        end
    end

    local matchingWithItems =
        0

    local matchingWithoutItems =
        0

    for inboxIndex = 1,
        (inboxCount or 0)
    do
        local packageIcon,
              stationeryIcon,
              sender,
              subject,
              money,
              CODAmount,
              daysLeft,
              hasItem =
            GetInboxHeaderInfo(
                inboxIndex
            )

        local normalizedSender =
            WGRNormalizeMailName(
                sender
            )

        local senderExpected =
            normalizedSender
            and expectedSenders[
                normalizedSender
            ]

        if subject == "Alt Gear"
            and senderExpected
        then
            WGRMailDebug(
                string.format(
                    "Matching Alt Gear found: inbox=%d sender=%s hasItem=%s daysLeft=%s.",
                    inboxIndex,
                    tostring(sender),
                    tostring(hasItem),
                    tostring(daysLeft)
                )
            )

            if hasItem then
                matchingWithItems =
                    matchingWithItems + 1
            else
                matchingWithoutItems =
                    matchingWithoutItems + 1
            end
        end
    end

    WGRMailDebug(
        string.format(
            "Matching tracked mail with attachments: %d; matching tracked mail without attachments: %d.",
            matchingWithItems,
            matchingWithoutItems
        )
    )

    entry.maxSeenTrackedMails =
        math.max(
            entry.maxSeenTrackedMails
                or 0,
            matchingWithItems
        )

    if matchingWithItems > 0 then
        if not entry.seenInInbox then
            WGRMailDebug(
                "Recorded tracked mail as seen in inbox."
            )
        else
            WGRMailDebug(
                "Tracked mail is still present with attachments."
            )
        end

        entry.seenInInbox =
            true

        entry.lastInboxSeenAt =
            time()

        return
    end

    if entry.seenInInbox then
        WGRMailDebug(
            "Previously seen tracked mail no longer has attachments."
        )
    else
        WGRMailDebug(
            "No tracked mail with attachments has been positively seen yet, so the reminder will not be cleared."
        )
    end

    if entry.seenInInbox == true
        and (
            entry.maxSeenTrackedMails
                or 0
        ) >= expectedCount
        and entry.lastInboxSeenAt
    then
        WGRMailDebug(
            "All expected tracked mails were previously observed; clearing mail reminder automatically."
        )

        WGRMailMarkChecked(
            currentName
        )

        print(
            "|cff00ff00WBGR MAIL:|r "
            .. currentName
            .. "'s tracked Alt Gear mail has been collected. Mail reminder cleared automatically."
        )

        -- Keep an already-open Check Mail window in sync immediately.
        -- Do not require the user to rerun /wgr mailcheck.
        if WGRMailTracker.frame
            and WGRMailTracker.frame:IsShown()
        then
            WGRMailUpdateTrackerFrame()

            C_Timer.After(
                0.10,
                function()
                    if WGRMailTracker.frame
                        and WGRMailTracker.frame:IsShown()
                    then
                        WGRMailUpdateTrackerFrame()
                    end
                end
            )
        end
    else
        WGRMailDebug(
            string.format(
                "Reminder retained. seenInInbox=%s, maxSeenTrackedMails=%s, expectedCount=%s.",
                tostring(entry.seenInInbox),
                tostring(
                    entry.maxSeenTrackedMails
                        or 0
                ),
                tostring(
                    expectedCount
                )
            )
        )
    end
end

function WGRMailQueueInboxScan()
    WGRMailDebug(
        "Queueing inbox scan. WGRMail="
            .. tostring(
                WGRMail ~= nil
            )
            .. " mailboxOpen="
            .. tostring(
                WGRMail
                and WGRMail.mailboxOpen
            )
    )

    C_Timer.After(
        0.25,
        function()
            WGRMailDebug(
                "0.25s inbox timer fired. mailboxOpen="
                    .. tostring(
                        WGRMail
                        and WGRMail.mailboxOpen
                    )
            )

            if not WGRMail then
                WGRMailDebug(
                    "0.25s scan aborted: WGRMail table is nil."
                )
                return
            end

            if not WGRMail.mailboxOpen then
                WGRMailDebug(
                    "0.25s scan aborted: mailboxOpen is false."
                )
                return
            end

            WGRMailDebug(
                "0.25s scan calling WGRMailScanTrackedInbox()."
            )

            local ok, err =
                pcall(
                    WGRMailScanTrackedInbox
                )

            if not ok then
                WGRMailDebug(
                    "0.25s scan ERROR: "
                        .. tostring(err)
                )
            end
        end
    )

    C_Timer.After(
        0.75,
        function()
            WGRMailDebug(
                "0.75s inbox timer fired. mailboxOpen="
                    .. tostring(
                        WGRMail
                        and WGRMail.mailboxOpen
                    )
            )

            if not WGRMail then
                WGRMailDebug(
                    "0.75s scan aborted: WGRMail table is nil."
                )
                return
            end

            if not WGRMail.mailboxOpen then
                WGRMailDebug(
                    "0.75s scan aborted: mailboxOpen is false."
                )
                return
            end

            WGRMailDebug(
                "0.75s scan calling WGRMailScanTrackedInbox()."
            )

            local ok, err =
                pcall(
                    WGRMailScanTrackedInbox
                )

            if not ok then
                WGRMailDebug(
                    "0.75s scan ERROR: "
                        .. tostring(err)
                )
            end
        end
    )
end

local WGRMainActiveTab =
    "MAIL"

local WGRClassDisplayNames = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    MONK = "Monk",
    DRUID = "Druid",
    DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}


local WGRClassAbbreviations = {
    Warrior = "WAR", Paladin = "PAL", Hunter = "HUN",
    Rogue = "ROG", Priest = "PRI", ["Death Knight"] = "DK",
    Shaman = "SHM", Mage = "MAG", Warlock = "WL",
    Monk = "MNK", Druid = "DRU", ["Demon Hunter"] = "DH",
    Evoker = "EVO",
}

local WGRSpecAbbreviations = {
    ["Beast Mastery"] = "BM", Marksmanship = "MM", Survival = "SV",
    Retribution = "Ret", Protection = "Prot", Holy = "Holy",
    Discipline = "Disc", Shadow = "Shadow", Blood = "Blood",
    Frost = "Frost", Unholy = "Unholy", Elemental = "Ele",
    Enhancement = "Enh", Restoration = "Resto", Arcane = "Arc",
    Fire = "Fire", Affliction = "Aff", Demonology = "Demo",
    Destruction = "Dest", Brewmaster = "Brew", Mistweaver = "MW",
    Windwalker = "WW", Balance = "Bal", Feral = "Feral",
    Guardian = "Guard", Havoc = "Havoc", Vengeance = "Veng",
    Devastation = "Dev", Preservation = "Pres", Augmentation = "Aug",
    Assassination = "Assn", Outlaw = "Outlaw", Subtlety = "Sub",
    Arms = "Arms", Fury = "Fury",
}


local function WGRGetRosterClassName(
    characterName,
    character
)
    local remembered =
        GetRememberedSpec(
            characterName
        )

    if remembered
        and remembered.class
    then
        return
            WGRClassDisplayNames[
                remembered.class
            ]
            or remembered.class
    end

    if character
        and DataStore.GetCharacterClass
    then
        local className =
            DataStore:GetCharacterClass(
                character
            )

        if className then
            return className
        end
    end

    return "Unknown"
end

local function WGRRefreshGearFinderIfOpen()
    if WGRScheduleGearFinderRefresh then
        WGRScheduleGearFinderRefresh(
            0.10
        )
    end
end

function WGRUpdateOpenRouterButton()
    local frame =
        WGRMailTracker.frame

    if not frame
        or not frame.openRouterButton
    then
        return
    end

    local mailboxOpen =
        WGRMail
        and WGRMail.mailboxOpen

    frame.openRouterButton:SetEnabled(
        mailboxOpen
        and true
        or false
    )

    if frame.routerRequirement then
        frame.routerRequirement:SetShown(
            not mailboxOpen
        )

        frame.routerRequirement:SetText(
            "Open a mailbox to use the Mail Router."
        )
    end
end

local function WGRUpdateMailTabLabel(
    count
)
    local frame =
        WGRMailTracker.frame

    if frame
        and frame.tabs
        and frame.tabs.MAIL
    then
        if frame.tabs.MAIL.label then
            frame.tabs.MAIL.label:SetText(
                string.format(
                    "To Do (%d)",
                    count or 0
                )
            )
        end
    end
end

local function WGRMailReminderText(
    list
)
    local lines = {}

    for _, entry
        in ipairs(list)
    do
        table.insert(
            lines,
            entry.name
                .. " - "
                .. WGRMailFormatRemaining(
                    entry.remaining
                )
        )
    end

    return table.concat(
        lines,
        "\n"
    )
end

local WGRTodoClassSpecs = {
    WARRIOR = {
        { id = 71, name = "Arms" },
        { id = 72, name = "Fury" },
        { id = 73, name = "Protection" },
    },
    PALADIN = {
        { id = 65, name = "Holy" },
        { id = 66, name = "Protection" },
        { id = 70, name = "Retribution" },
    },
    HUNTER = {
        { id = 253, name = "Beast Mastery" },
        { id = 254, name = "Marksmanship" },
        { id = 255, name = "Survival" },
    },
    ROGUE = {
        { id = 259, name = "Assassination" },
        { id = 260, name = "Outlaw" },
        { id = 261, name = "Subtlety" },
    },
    PRIEST = {
        { id = 256, name = "Discipline" },
        { id = 257, name = "Holy" },
        { id = 258, name = "Shadow" },
    },
    DEATHKNIGHT = {
        { id = 250, name = "Blood" },
        { id = 251, name = "Frost" },
        { id = 252, name = "Unholy" },
    },
    SHAMAN = {
        { id = 262, name = "Elemental" },
        { id = 263, name = "Enhancement" },
        { id = 264, name = "Restoration" },
    },
    MAGE = {
        { id = 62, name = "Arcane" },
        { id = 63, name = "Fire" },
        { id = 64, name = "Frost" },
    },
    WARLOCK = {
        { id = 265, name = "Affliction" },
        { id = 266, name = "Demonology" },
        { id = 267, name = "Destruction" },
    },
    MONK = {
        { id = 268, name = "Brewmaster" },
        { id = 270, name = "Mistweaver" },
        { id = 269, name = "Windwalker" },
    },
    DRUID = {
        { id = 102, name = "Balance" },
        { id = 103, name = "Feral" },
        { id = 104, name = "Guardian" },
        { id = 105, name = "Restoration" },
    },
    DEMONHUNTER = {
        { id = 577, name = "Havoc" },
        { id = 581, name = "Vengeance" },
    },
    EVOKER = {
        { id = 1467, name = "Devastation" },
        { id = 1468, name = "Preservation" },
        { id = 1473, name = "Augmentation" },
    },
}

local WGRTodoClassTokenByName = {
    Warrior = "WARRIOR",
    Paladin = "PALADIN",
    Hunter = "HUNTER",
    Rogue = "ROGUE",
    Priest = "PRIEST",
    ["Death Knight"] = "DEATHKNIGHT",
    Shaman = "SHAMAN",
    Mage = "MAGE",
    Warlock = "WARLOCK",
    Monk = "MONK",
    Druid = "DRUID",
    ["Demon Hunter"] = "DEMONHUNTER",
    Evoker = "EVOKER",
}

local function WGRTodoPriorityPositions()
    local positions = {}

    for index, name
        in ipairs(
            GetActiveRoutingPriority()
            or {}
        )
    do
        positions[
            string.lower(
                tostring(name)
            )
        ] =
            index
    end

    return positions
end

local function WGRTodoLatestMailSendToken(
    name
)
    local tracking =
        WGRMailTrackingTable()

    local entry =
        tracking[
            string.lower(
                tostring(name)
            )
        ]

    if not entry
        or type(entry.sends)
            ~= "table"
    then
        return "0:0"
    end

    local latest = 0

    for _, send
        in ipairs(entry.sends)
    do
        latest =
            math.max(
                latest,
                tonumber(
                    send.timestamp
                )
                or 0
            )
    end

    return
        tostring(latest)
        .. ":"
        .. tostring(
            #entry.sends
        )
end

local function WGRTodoIsDismissed(
    dismissKey
)
    if not dismissKey then
        return false
    end

    InitializeDatabase()

    return
        WarboundGearRouterDB.todoDismissals[
            dismissKey
        ]
        ~= nil
end

local function WGRTodoSelectedSpecs(
    characterName,
    character
)
    local remembered =
        GetRememberedSpec(
            characterName
        )

    local classToken =
        remembered
        and remembered.class
        or nil

    if not classToken then
        local className =
            WGRGetRosterClassName(
                characterName,
                character
            )

        classToken =
            WGRTodoClassTokenByName[
                className
            ]
    end

    local classSpecs =
        WGRTodoClassSpecs[
            classToken
            or ""
        ]
        or {}

    local mode =
        WGRGetEffectiveSpecMode(
            characterName
        )

    if mode == "CURRENT" then
        if remembered
            and remembered.specID
        then
            for _, spec
                in ipairs(classSpecs)
            do
                if spec.id
                    == remembered.specID
                then
                    return {
                        spec
                    }
                end
            end

            return {
                {
                    id =
                        remembered.specID,
                    name =
                        remembered.specName
                        or tostring(
                            remembered.specID
                        ),
                }
            }
        end

        return {}
    end

    if mode == "CUSTOM" then
        local custom =
            WGRGetCustomSpecs(
                characterName
            )
            or {}

        local result = {}

        for _, spec
            in ipairs(classSpecs)
        do
            if custom[
                tostring(spec.id)
            ] == true
            then
                result[
                    #result + 1
                ] =
                    spec
            end
        end

        return result
    end

    return classSpecs
end

local function WGRTodoMissingSpecs(
    characterName,
    character
)
    local selected =
        WGRTodoSelectedSpecs(
            characterName,
            character
        )

    if #selected == 0 then
        return {}
    end

    local key =
        string.lower(
            tostring(
                characterName
            )
        )

    local baselines =
        WarboundGearRouterDB.specWeaponBaselines[
            key
        ]
        or {}

    local missing = {}

    for _, spec
        in ipairs(selected)
    do
        local baseline =
            baselines[
                tostring(spec.id)
            ]

        -- A To Do initialization reminder should reflect the same effective
        -- complete weapon baseline used by routing and the Custom Weapons UI,
        -- not just the raw per-spec record.  Preserve the existing behavior
        -- that an inherited partial setup is sufficient to stop initialization
        -- nagging while WGR waits for future routed gear.
        local routingReady =
            baseline
            and baseline.weaponConfigState
                == "INITIALIZED"

        if WGRGetEffectiveSpecWeaponBaseline then
            local effectiveLevel =
                WGRGetEffectiveSpecWeaponBaseline(
                    characterName,
                    character,
                    spec.id
                )

            if (tonumber(effectiveLevel) or 0) > 0 then
                routingReady = true
            end
        end

        if not routingReady
            and WGRGetInheritedWeaponBaselineForRouting
        then
            local inherited =
                WGRGetInheritedWeaponBaselineForRouting(
                    characterName,
                    spec.id
                )

            if inherited
                and (
                    inherited.weaponConfigState
                        == "INHERITED_COMPLETE"
                    or inherited.weaponConfigState
                        == "INHERITED_PARTIAL"
                )
            then
                routingReady = true
            end
        end

        local acceptedIncomplete =
            WarboundGearRouterDB.acceptedIncompleteWeaponBaselines
            and WarboundGearRouterDB.acceptedIncompleteWeaponBaselines[key]
            and WarboundGearRouterDB.acceptedIncompleteWeaponBaselines[key][tostring(spec.id)] == true

        if not routingReady and not acceptedIncomplete then
            missing[
                #missing + 1
            ] =
                spec
        end
    end

    return missing
end

local function WGRTodoSpecDismissKey(
    characterName,
    missing
)
    local key =
        string.lower(
            tostring(
                characterName
            )
        )

    local attempts =
        WarboundGearRouterDB.todoSpecAttempts[
            key
        ]
        or {}

    local parts = {}

    for _, spec
        in ipairs(missing)
    do
        parts[
            #parts + 1
        ] =
            tostring(spec.id)
            .. ":"
            .. tostring(
                attempts[
                    tostring(spec.id)
                ]
                or 0
            )
    end

    table.sort(parts)

    return
        "INIT:"
        .. key
        .. ":"
        .. table.concat(
            parts,
            ","
        )
end

local function WGRTodoBuildList()
    InitializeDatabase()

    local todo = {}
    local priority =
        WGRTodoPriorityPositions()

    -- Priority 1: routed mail retrieval, soonest expiration first.
    for _, entry
        in ipairs(
            WGRMailGetTrackedList()
        )
    do
        local dismissKey =
            "MAIL:"
            .. string.lower(
                tostring(entry.name)
            )
            .. ":"
            .. WGRTodoLatestMailSendToken(
                entry.name
            )

        if not WGRTodoIsDismissed(
            dismissKey
        )
        then
            todo[
                #todo + 1
            ] = {
                kind =
                    "MAIL_RETRIEVE",
                priority =
                    1,
                sortValue =
                    entry.remaining
                    or math.huge,
                character =
                    entry.name,
                title =
                    tostring(entry.name)
                    .. " — Retrieve Mail",
                detail =
                    "WBGR gear is waiting in the mailbox.",
                urgency =
                    "Time Remaining: "
                    .. WGRMailFormatRemaining(
                        entry.remaining
                    ),
                remaining =
                    entry.remaining,
                dismissKey =
                    dismissKey,
            }
        end
    end

    -- Priority 2: missing selected-spec baselines, global priority order.
    for _, characterName
        in ipairs(
            GetActiveRoutingPriority()
            or {}
        )
    do
        local character =
            FindCharacterByName(
                characterName
            )

        local missing =
            WGRTodoMissingSpecs(
                characterName,
                character
            )

        if #missing > 0 then
            local names = {}

            for _, spec
                in ipairs(missing)
            do
                names[
                    #names + 1
                ] =
                    spec.name
            end

            local dismissKey =
                WGRTodoSpecDismissKey(
                    characterName,
                    missing
                )

            if not WGRTodoIsDismissed(
                dismissKey
            )
            then
                local plural =
                    #names > 1

                todo[
                    #todo + 1
                ] = {
                    kind =
                        "INITIALIZE_SPECS",
                    priority =
                        2,
                    sortValue =
                        priority[
                            string.lower(
                                tostring(
                                    characterName
                                )
                            )
                        ]
                        or 9999,
                    character =
                        characterName,
                    title =
                        tostring(characterName)
                        .. " — Initialize "
                        .. table.concat(
                            names,
                            ", "
                        ),
                    detail =
                        "Log onto "
                        .. tostring(characterName)
                        .. ", switch to "
                        .. (
                            plural
                            and "each listed spec"
                            or tostring(names[1])
                        )
                        .. ", and equip the gear you want WBGR to use.",
                    urgency =
                        "ASAP — Routing setup incomplete",
                    dismissKey =
                        dismissKey,
                }
            end
        end
    end

    -- Priority 3: carried outgoing gear by character, global priority order.
    for _, characterName
        in ipairs(
            GetActiveRoutingPriority()
            or {}
        )
    do
        local key =
            string.lower(
                tostring(
                    characterName
                )
            )

        local snapshot =
            WarboundGearRouterDB.todoGearSnapshots[
                key
            ]

        if snapshot
            and (
                tonumber(
                    snapshot.sendCount
                )
                or 0
            ) > 0
        then
            local count =
                tonumber(
                    snapshot.sendCount
                )
                or 0

            local dismissKey =
                "SEND:"
                .. key
                .. ":"
                .. tostring(
                    snapshot.scanID
                    or 0
                )

            if not WGRTodoIsDismissed(
                dismissKey
            )
            then
                todo[
                    #todo + 1
                ] = {
                    kind =
                        "SEND_CHARACTER",
                    priority =
                        3,
                    sortValue =
                        priority[key]
                        or 9999,
                    character =
                        characterName,
                    count =
                        count,
                    title =
                        tostring(characterName)
                        .. " — Send "
                        .. tostring(count)
                        .. " Item"
                        .. (
                            count == 1
                            and ""
                            or "s"
                        ),
                    detail =
                        tostring(count)
                        .. " routed item"
                        .. (
                            count == 1
                            and " is"
                            or "s are"
                        )
                        .. " ready to send to other characters."
                        .. "\nOpen a mailbox, or deposit them in the Warband Bank.",
                    dismissKey =
                        dismissKey,
                    action =
                        "SEND_CONTEXT",
                }
            end
        end
    end

    -- Lowest-priority current Warband Bank routing snapshot.
    local warbank =
        WarboundGearRouterDB.todoWarbankSnapshot

    if warbank
        and (
            tonumber(
                warbank.sendCount
            )
            or 0
        ) > 0
    then
        local count =
            tonumber(
                warbank.sendCount
            )
            or 0

        local dismissKey =
            "WARBANK:"
            .. tostring(
                warbank.scanID
                or 0
            )

        if not WGRTodoIsDismissed(
            dismissKey
        )
        then
            todo[
                #todo + 1
            ] = {
                kind =
                    "SEND_WARBANK",
                priority =
                    5,
                sortValue =
                    9999,
                character =
                    "Warband Bank",
                count =
                    count,
                title =
                    "Warband Bank — Send "
                    .. tostring(count)
                    .. " Item"
                    .. (
                        count == 1
                        and ""
                        or "s"
                    ),
                detail =
                    tostring(count)
                    .. " routed item"
                    .. (
                        count == 1
                        and " is"
                        or "s are"
                    )
                    .. " waiting safely in the Warband Bank.",
                dismissKey =
                    dismissKey,
                action =
                    "GEAR_FINDER",
            }
        end
    end

    local sortMode =
        WarboundGearRouterDB.todoSortMode
        or "URGENCY"

    local function UrgencyLess(
        a,
        b
    )
        if a.priority
            ~= b.priority
        then
            return
                a.priority
                < b.priority
        end

        if a.sortValue
            ~= b.sortValue
        then
            return
                a.sortValue
                < b.sortValue
        end

        return
            tostring(
                a.character
                or a.title
            )
            <
            tostring(
                b.character
                or b.title
            )
    end

    table.sort(
        todo,
        function(a, b)
            if sortMode
                == "URGENCY"
            then
                return UrgencyLess(
                    a,
                    b
                )
            end

            local aName =
                string.lower(
                    tostring(
                        a.character
                        or ""
                    )
                )

            local bName =
                string.lower(
                    tostring(
                        b.character
                        or ""
                    )
                )

            if sortMode
                == "PRIORITY"
            then
                local aPriority =
                    priority[aName]
                    or 9999

                local bPriority =
                    priority[bName]
                    or 9999

                if aPriority
                    ~= bPriority
                then
                    return
                        aPriority
                        < bPriority
                end
            elseif aName
                ~= bName
            then
                return
                    aName
                    < bName
            end

            if aName
                ~= bName
            then
                return
                    aName
                    < bName
            end

            -- Within each character, preserve the existing urgency order.
            return UrgencyLess(
                a,
                b
            )
        end
    )

    return todo
end

function WGRDismissTodoEntry(
    entry
)
    if not entry
        or not entry.dismissKey
    then
        return
    end

    InitializeDatabase()

    WarboundGearRouterDB.todoDismissals[
        entry.dismissKey
    ] = {
        timestamp =
            time(),
        title =
            entry.title,
        kind =
            entry.kind,
    }

    WGRAddRecentActivity(
        tostring(
            entry.title
            or "To Do"
        )
        .. " reminder was manually dismissed.",
        "TODO_DISMISSED"
    )

    WGRRefreshTodoPage()
end

function WGRUpdateGearTodoSnapshot(
    characterName,
    sendCount,
    warbankCount,
    warbankObserved
)
    InitializeDatabase()

    WarboundGearRouterDB.todoScanSerial =
        (
            WarboundGearRouterDB.todoScanSerial
            or 0
        )
        + 1

    local scanID =
        WarboundGearRouterDB.todoScanSerial

    if characterName then
        WarboundGearRouterDB.todoGearSnapshots[
            string.lower(
                tostring(characterName)
            )
        ] = {
            name =
                characterName,
            sendCount =
                tonumber(sendCount)
                or 0,
            scanID =
                scanID,
            updated =
                time(),
        }
    end

    if warbankObserved then
        WarboundGearRouterDB.todoWarbankSnapshot = {
            sendCount =
                tonumber(warbankCount)
                or 0,
            scanID =
                scanID,
            updated =
                time(),
        }
    end

    WGRRefreshTodoPage()
end

function WGRMailShowLoginReminder()
    if WGRMailTracker.loginReminderShown then
        return
    end

    WGRMailTracker.loginReminderShown =
        true

    local list =
        WGRMailGetTrackedList()

    if #list == 0 then
        return
    end

    local currentName =
        UnitName(
            "player"
        )

    local currentEntry =
        nil

    local urgent = {}

    for _, entry
        in ipairs(list)
    do
        if currentName
            and string.lower(
                entry.name
            ) == string.lower(
                currentName
            )
        then
            currentEntry =
                entry
        end

        if entry.remaining
            <= WGR_MAIL_YELLOW
        then
            table.insert(
                urgent,
                entry
            )
        end
    end

    if currentEntry then
        local remainingText =
            WGRMailFormatRemaining(
                currentEntry.remaining
            )

        local r, g, b =
            WGRMailUrgencyColor(
                currentEntry.remaining
            )

        local countdownColor =
            string.format(
                "%02x%02x%02x",
                math.floor(r * 255),
                math.floor(g * 255),
                math.floor(b * 255)
            )

        print(
            "|cffffd100========== WBGR MAIL ==========|r"
        )

        print(
            "|cffffffff"
            .. currentEntry.name
            .. " has alt gear waiting! |r"
            .. "|cff"
            .. countdownColor
            .. remainingText
            .. ".|r"
        )

        print(
            "|cffffd100==============================|r"
        )
    end

    if not currentEntry
        and #urgent == 0
    then
        return
    end

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.mailReminderPopups
            == false
    then
        return
    end

    local popupList =
        {}

    if #urgent > 0 then
        popupList =
            urgent
    elseif currentEntry then
        popupList = {
            currentEntry
        }
    end

    StaticPopupDialogs[
        "WGR_MAIL_REMINDER"
    ] = {
        text =
            "WBGR Mail Reminder\n\n%s",
        button1 =
            OKAY,
        timeout =
            0,
        whileDead =
            true,
        hideOnEscape =
            true,
        preferredIndex =
            3,
    }

    StaticPopup_Show(
        "WGR_MAIL_REMINDER",
        WGRMailReminderText(
            popupList
        )
    )
end

local function WGRShowMainTab(
    tabKey
)
    local frame =
        WGRMailTracker.frame

    if not frame then
        return
    end

    tabKey =
        tabKey
        or "MAIL"

    WGRMainActiveTab =
        tabKey

    frame.mailPage:SetShown(
        tabKey == "MAIL"
    )

    frame.gearFinderPage:SetShown(
        tabKey == "GEAR_FINDER"
    )

    frame.rosterPage:SetShown(
        tabKey == "ROSTER"
    )

    frame.settingsPage:SetShown(
        tabKey == "SETTINGS"
    )

    frame.aboutPage:SetShown(
        tabKey == "ABOUT"
    )

    for key, tab
        in pairs(
            frame.tabs
        )
    do
        if key == tabKey then
            tab:Disable()

            tab:SetBackdropColor(
                0.16,
                0.16,
                0.16,
                1.00
            )

            if tab.label then
                tab.label:SetTextColor(
                    1.00,
                    0.82,
                    0.00
                )
            end
        else
            tab:Enable()

            tab:SetBackdropColor(
                0.04,
                0.04,
                0.04,
                0.92
            )

            if tab.label then
                tab.label:SetTextColor(
                    0.78,
                    0.78,
                    0.78
                )
            end
        end
    end

    if tabKey == "MAIL" then
        WGRMailUpdateTrackerFrame()

    elseif tabKey == "GEAR_FINDER" then
        WGRRefreshGearFinder(
            frame
        )

    elseif tabKey == "ROSTER" then
        if frame.UpdateRoster then
            frame.UpdateRoster()
        end

    elseif tabKey == "SETTINGS" then
        if frame.UpdateGlobalWeaponOverrideHelp then
            frame.UpdateGlobalWeaponOverrideHelp()
        end
    end
end

WGRMailUpdateTrackerFrame =
    function()
        WGRRefreshTodoPage()
    end

if not StaticPopupDialogs["WGR_CONFIRM_RESET_ALL_SPEC_MODES"] then
    StaticPopupDialogs["WGR_CONFIRM_RESET_ALL_SPEC_MODES"] = {
        text =
            "Reset all character Spec Modes to Default?\n\nThis removes every per-character Spec Mode override. All characters will follow the Default Spec Mode selected in Settings > Routing. Custom spec selections are not deleted.",
        button1 = "Reset Specs",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept =
            function(self, data)
                InitializeDatabase()

                for key, override
                    in pairs(WarboundGearRouterDB.characterOverrides)
                do
                    if type(override) == "table" then
                        override.specMode = nil

                        if not next(override) then
                            WarboundGearRouterDB.characterOverrides[key] = nil
                        end
                    end
                end

                if data
                    and data.frame
                    and data.frame.UpdateRoster
                then
                    data.frame.UpdateRoster()
                end

                print(
                    "|cff00ff00WBGR:|r All character Spec Modes reset to Default."
                )
            end,
    }
end

if not StaticPopupDialogs["WGR_CONFIRM_UNDERMAX_ALL_SPECS"] then
    StaticPopupDialogs["WGR_CONFIRM_UNDERMAX_ALL_SPECS"] = {
        text =
            "Set every under-max character to All Specs?\n\nThis will replace each under-max character's current per-character Spec Mode choice, including Current or Custom, with All Specs. Custom spec selections are not deleted, but will not be used unless that character is later changed back to Custom.",
        button1 = "Set to All Specs",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept =
            function(self, data)
                InitializeDatabase()

                local changed = 0

                for _, characterName
                    in ipairs(GetRoutingPriority())
                do
                    local character =
                        FindCharacterByName(characterName)

                    local level =
                        character
                        and DataStore:GetCharacterLevel(character)
                        or 0

                    if level > 0
                        and level < WGR_MAX_LEVEL
                    then
                        WGRSetCharacterSpecMode(
                            characterName,
                            "ALL"
                        )

                        changed =
                            changed + 1
                    end
                end

                if data
                    and data.frame
                    and data.frame.UpdateRoster
                then
                    data.frame.UpdateRoster()
                end

                print(
                    "|cff00ff00WBGR:|r "
                    .. tostring(changed)
                    .. " under-max character Spec Modes set to All Specs."
                )
            end,
    }
end

if not StaticPopupDialogs["WGR_CONFIRM_RESET_ALL_WEAPONS"] then
    StaticPopupDialogs["WGR_CONFIRM_RESET_ALL_WEAPONS"] = {
        text =
            "Reset all character Weapon Eligibility settings to Default?\n\nThis removes every per-character Weapons mode override. All characters will follow the Default Weapon Eligibility selected in Settings > Routing. Custom per-spec weapon selections are not deleted.",
        button1 = "Reset Weapons",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept =
            function(self, data)
                InitializeDatabase()
                WarboundGearRouterDB.weaponModes = {}

                if data
                    and data.frame
                    and data.frame.UpdateRoster
                then
                    data.frame.UpdateRoster()
                end

                if data
                    and data.frame
                    and data.frame.UpdateGlobalWeaponOverrideHelp
                then
                    data.frame.UpdateGlobalWeaponOverrideHelp()
                end

                RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()

                print(
                    "|cff00ff00WBGR:|r All character Weapon Eligibility settings reset to Default."
                )
            end,
    }
end

if not StaticPopupDialogs["WGR_CONFIRM_RESET_CHARACTER_THRESHOLDS"] then
    StaticPopupDialogs["WGR_CONFIRM_RESET_CHARACTER_THRESHOLDS"] = {
        text =
            "Reset all character iLvl upgrade thresholds to Default?\n\nThis clears only character-specific threshold overrides. All characters will use the Default iLvl Upgrade Threshold. Spec Mode and all other character settings are unchanged.",
        button1 = "Reset Thresholds",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept =
            function(self, data)
                InitializeDatabase()

                for _, override
                    in pairs(
                        WarboundGearRouterDB.characterOverrides
                    )
                do
                    if type(override) == "table" then
                        override.upgradeThreshold =
                            nil
                    end
                end

                if data
                    and data.frame
                    and data.frame.UpdateRoster
                then
                    data.frame.UpdateRoster()
                end

                print(
                    "|cff00ff00WBGR:|r All character iLvl upgrade thresholds reset to Default."
                )
            end,
    }
end

if not StaticPopupDialogs["WGR_CONFIRM_SET_PRIORITY_FROM_VIEW"] then
    StaticPopupDialogs["WGR_CONFIRM_SET_PRIORITY_FROM_VIEW"] = {
        text =
            "Set routing priority from the current roster view?\n\nThis will replace the full routing priority with the order currently displayed. WBGR will save your current priority first so Restore Previous can undo this change.",
        button1 = "Set Priority",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept =
            function(self, data)
                if not data
                    or type(data.view) ~= "table"
                    or #data.view == 0
                then
                    return
                end

                WGRSavePriorityBackup(
                    "Priority before Set From Current View"
                )

                WarboundGearRouterDB.routingPriority =
                    WGRCopyList(
                        data.view
                    )

                -- The displayed order is now the routing priority.
                -- Return to Priority / Ascending so the result is explicit
                -- rather than leaving a stale secondary-sort label active.
                WarboundGearRouterDB.interface.rosterViewSort =
                    "PRIORITY"

                WarboundGearRouterDB.interface.rosterSortDirections.PRIORITY =
                    "ASC"

                if data.updateViewDropdown then
                    data.updateViewDropdown()
                end

                if data.updateDirectionDropdown then
                    data.updateDirectionDropdown()
                end

                if data.frame
                    and data.frame.UpdateRoster
                then
                    data.frame.UpdateRoster()
                end

                WGRMailUpdateTrackerFrame()

                print(
                    "|cff00ff00WBGR:|r Routing priority set from the current roster view."
                )
            end,
    }
end

if not StaticPopupDialogs["WGR_CONFIRM_RESTORE_PRIORITY"] then
    StaticPopupDialogs["WGR_CONFIRM_RESTORE_PRIORITY"] = {
        text =
            "Restore the previous routing priority?\n\nYour current routing order will be replaced. WBGR will keep the current order as the new backup so you can restore again if needed.",
        button1 = "Restore",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept =
            function(self, data)
                if WGRRestorePriorityBackup() then
                    if data
                        and data.frame
                        and data.frame.UpdateRoster
                    then
                        data.frame.UpdateRoster()
                    end

                    WGRMailUpdateTrackerFrame()

                    print(
                        "|cff00ff00WBGR:|r Previous routing priority restored."
                    )
                end
            end,
    }
end

if not StaticPopupDialogs["WGR_CONFIRM_REMOVE_CHARACTER"] then
    StaticPopupDialogs["WGR_CONFIRM_REMOVE_CHARACTER"] = {
        text =
            "Remove %s from Warbound Gear Router?\n\nThis removes the character from WBGR only. It does not delete the WoW character. You can restore the character later from the Roster page.",
        button1 = "Remove",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept =
            function(self, data)
                if not data
                    or not data.characterName
                then
                    return
                end

                if WGRRemoveCharacter(
                    data.characterName
                )
                then
                    if data.frame
                        and data.frame.UpdateRoster
                    then
                        data.frame.UpdateRoster()
                    end

                    if data.frame
                        and data.frame.UpdateRemovedCharacters
                    then
                        data.frame.UpdateRemovedCharacters()
                    end

                    WGRMailUpdateTrackerFrame()

                    print(
                        "|cff00ff00WBGR:|r "
                        .. data.characterName
                        .. " removed from the WBGR roster."
                    )
                end
            end,
    }
end

-- ============================================================
-- ROSTER HELD-GEAR UI HELPERS
-- Kept outside WGRMailCreateTrackerFrame to avoid WoW Lua's
-- 200-local-variable compiler limit in that large UI function.
-- ============================================================

local function WGRRosterWarbandHeldGearSummary()
    local getter = _G.WGRGetWarbandHeldGearSummary
    if type(getter) ~= "function" then return nil end
    local ok, summary = pcall(getter)
    if not ok then return nil end
    return summary
end

local function WGRRosterHeldGearSummary(
    characterName
)
    local getter =
        _G.WGRGetHeldGearSummary

    if type(getter) ~= "function" then
        return nil
    end

    local ok,
          summary =
        pcall(
            getter,
            characterName
        )

    if not ok then
        return nil
    end

    return summary
end


local WGRHeldGearArmorOrder = {
    "Cloth",
    "Leather",
    "Mail",
    "Plate",
}

local WGRHeldGearAccessoryOrder = {
    "Cloaks",
    "Necks",
    "Rings",
}

local WGRHeldGearWeaponOrder = {
    "2H Strength",
    "2H Agility",
    "2H Intellect",
    "2H Hybrid",
    "2H Other",
    "1H Strength",
    "1H Agility",
    "Agility Daggers",
    "1H Intellect",
    "1H Hybrid",
    "1H Other",
    "Warglaives",
    "Shields",
    "Off-Hands",
    "Ranged",
    "Other Weapons",
}

local function WGRHeldGearAgeText(
    timestamp
)
    timestamp =
        tonumber(timestamp)

    if not timestamp
        or timestamp <= 0
    then
        return "not scanned yet"
    end

    local age =
        math.max(
            0,
            time() - timestamp
        )

    if age < 60 then
        return "just now"
    end

    if age < 3600 then
        return
            tostring(
                math.floor(
                    age / 60
                )
            )
            .. "m ago"
    end

    if age < 86400 then
        return
            tostring(
                math.floor(
                    age / 3600
                )
            )
            .. "h ago"
    end

    return
        tostring(
            math.floor(
                age / 86400
            )
        )
        .. "d ago"
end

local function WGRHeldGearBuildTree(
    summary
)
    local tree = {
        Armor = {},
        Accessories = {},
        Trinkets = {},
        Weapons = {},
    }

    for key, count
        in pairs(
            summary.entries
            or {}
        )
    do
        local section,
              category,
              subtype =
            strsplit(
                "\031",
                key
            )

        if section
            and category
        then
            tree[section] =
                tree[section]
                or {}

            if section
                == "Weapons"
            then
                tree.Weapons[category] =
                    tree.Weapons[category]
                    or {
                        total = 0,
                        subtypes = {},
                    }

                local record =
                    tree.Weapons[
                        category
                    ]

                record.total =
                    record.total
                    + count

                if subtype
                    and subtype ~= ""
                then
                    record.subtypes[subtype] =
                        (
                            record.subtypes[
                                subtype
                            ]
                            or 0
                        )
                        + count
                end
            else
                tree[section][category] =
                    (
                        tree[section][category]
                        or 0
                    )
                    + count
            end
        end
    end

    return tree
end

local function WGRShowHeldGearTooltip(
    owner,
    characterName,
    suppliedSummary
)
    if not GameTooltip then
        return
    end

    local summary =
        suppliedSummary
        or WGRRosterHeldGearSummary(
            characterName
        )

    if not summary
        or (
            tonumber(
                summary.total
            )
            or 0
        ) <= 0
    then
        return
    end

    GameTooltip:SetOwner(
        owner,
        "ANCHOR_RIGHT"
    )

    GameTooltip:AddLine(
        tostring(characterName)
            .. " — Stored WBGR Gear",
        1.00,
        0.82,
        0.00
    )

    GameTooltip:AddDoubleLine(
        "Total",
        tostring(
            summary.total
        ),
        0.85, 0.85, 0.85,
        1.00, 1.00, 1.00
    )

    if summary.warband ~= nil then
        GameTooltip:AddDoubleLine(
            "Warband Bank",
            tostring(summary.warband or 0),
            0.75, 0.75, 0.75,
            1.00, 1.00, 1.00
        )
    else
        GameTooltip:AddDoubleLine(
            "Bags",
            tostring(summary.bags or 0),
            0.75, 0.75, 0.75,
            1.00, 1.00, 1.00
        )
        GameTooltip:AddDoubleLine(
            "Personal Bank",
            tostring(summary.bank or 0),
            0.75, 0.75, 0.75,
            1.00, 1.00, 1.00
        )
    end

    local tree =
        WGRHeldGearBuildTree(
            summary
        )

    local function AddSectionTitle(
        text
    )
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            text,
            0.45,
            0.85,
            1.00
        )
    end

    local armorShown = false

    for _, label
        in ipairs(
            WGRHeldGearArmorOrder
        )
    do
        local count =
            tree.Armor[label]
            or 0

        if count > 0 then
            if not armorShown then
                AddSectionTitle(
                    "Armor"
                )
                armorShown = true
            end

            GameTooltip:AddDoubleLine(
                label,
                tostring(count),
                0.82, 0.82, 0.82,
                1.00, 1.00, 1.00
            )
        end
    end

    local accessoriesShown =
        false

    for _, label
        in ipairs(
            WGRHeldGearAccessoryOrder
        )
    do
        local count =
            tree.Accessories[
                label
            ]
            or 0

        if count > 0 then
            if not accessoriesShown then
                AddSectionTitle(
                    "Accessories"
                )
                accessoriesShown =
                    true
            end

            GameTooltip:AddDoubleLine(
                label,
                tostring(count),
                0.82, 0.82, 0.82,
                1.00, 1.00, 1.00
            )
        end
    end

    local trinketKeys = {}

    for label, count
        in pairs(
            tree.Trinkets
        )
    do
        if count > 0 then
            trinketKeys[
                #trinketKeys + 1
            ] =
                label
        end
    end

    table.sort(
        trinketKeys
    )

    if #trinketKeys > 0 then
        if not accessoriesShown then
            AddSectionTitle(
                "Accessories"
            )
            accessoriesShown =
                true
        end

        local trinketTotal = 0

        for _, label
            in ipairs(
                trinketKeys
            )
        do
            trinketTotal =
                trinketTotal
                + (
                    tree.Trinkets[
                        label
                    ]
                    or 0
                )
        end

        GameTooltip:AddDoubleLine(
            "Trinkets",
            tostring(
                trinketTotal
            ),
            0.82, 0.82, 0.82,
            1.00, 1.00, 1.00
        )

        for _, label
            in ipairs(
                trinketKeys
            )
        do
            GameTooltip:AddDoubleLine(
                "  " .. label,
                tostring(
                    tree.Trinkets[
                        label
                    ]
                ),
                0.68, 0.68, 0.68,
                0.92, 0.92, 0.92
            )
        end
    end

    local weaponShown =
        false

    for _, bucket
        in ipairs(
            WGRHeldGearWeaponOrder
        )
    do
        local record =
            tree.Weapons[
                bucket
            ]

        if record
            and record.total > 0
        then
            if not weaponShown then
                AddSectionTitle(
                    "Weapons"
                )
                weaponShown =
                    true
            end

            GameTooltip:AddDoubleLine(
                bucket,
                tostring(
                    record.total
                ),
                0.82, 0.82, 0.82,
                1.00, 1.00, 1.00
            )

            local subtypeNames = {}

            for subtype, count
                in pairs(
                    record.subtypes
                )
            do
                if count > 0 then
                    subtypeNames[
                        #subtypeNames + 1
                    ] =
                        subtype
                end
            end

            table.sort(
                subtypeNames
            )

            if #subtypeNames > 1
                or (
                    #subtypeNames == 1
                    and subtypeNames[1]
                        ~= bucket
                )
            then
                for _, subtype
                    in ipairs(
                        subtypeNames
                    )
                do
                    GameTooltip:AddDoubleLine(
                        "  " .. subtype,
                        tostring(
                            record.subtypes[
                                subtype
                            ]
                        ),
                        0.68, 0.68, 0.68,
                        0.92, 0.92, 0.92
                    )
                end
            end
        end
    end

    GameTooltip:AddLine(" ")

    if summary.warband ~= nil then
        GameTooltip:AddLine(
            "Warband Bank scanned: "
                .. WGRHeldGearAgeText(summary.warbandScanned),
            0.55, 0.55, 0.55
        )
    else
        GameTooltip:AddLine(
            "Bags scanned: "
                .. WGRHeldGearAgeText(summary.bagsScanned),
            0.55, 0.55, 0.55
        )
        GameTooltip:AddLine(
            "Personal Bank scanned: "
                .. WGRHeldGearAgeText(summary.bankScanned),
            0.55, 0.55, 0.55
        )
    end

    GameTooltip:Show()
end


local function WGRBuildAboutSubtabs(
    aboutPage,
    aboutDescription
)
    local aboutTabs = {}

    local function CreateAboutTab(
        key,
        label,
        x
    )
        local button =
            CreateFrame(
                "Button",
                nil,
                aboutPage,
                "BackdropTemplate"
            )

        button:SetSize(
            180,
            26
        )

        button:SetBackdrop(
            {
                bgFile =
                    "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile =
                    "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 9,
                insets = {
                    left = 3,
                    right = 3,
                    top = 3,
                    bottom = 3,
                },
            }
        )

        button:SetBackdropColor(
            0.04,
            0.04,
            0.04,
            0.92
        )

        button:SetPoint(
            "TOPLEFT",
            aboutDescription,
            "BOTTOMLEFT",
            x,
            -18
        )

        button.label =
            button:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )
        button.label:SetPoint(
            "CENTER",
            button,
            "CENTER",
            0,
            0
        )
        button.label:SetText(
            label
        )

        button:SetScript(
            "OnEnter",
            function(self)
                if not self.selected then
                    self:SetBackdropColor(
                        0.12,
                        0.12,
                        0.12,
                        0.96
                    )
                end
            end
        )

        button:SetScript(
            "OnLeave",
            function(self)
                if not self.selected then
                    self:SetBackdropColor(
                        0.04,
                        0.04,
                        0.04,
                        0.92
                    )
                end
            end
        )

        aboutTabs[key] =
            button

        return button
    end

    local commandsTab =
        CreateAboutTab(
            "COMMANDS",
            "Useful Commands",
            0
        )

    local gearTab =
        CreateAboutTab(
            "GEAR",
            "Gear Reference",
            188
        )

    local commandsPanel =
        CreateFrame(
            "Frame",
            nil,
            aboutPage
        )

    commandsPanel:SetPoint(
        "TOPLEFT",
        aboutDescription,
        "BOTTOMLEFT",
        0,
        -58
    )
    commandsPanel:SetPoint(
        "BOTTOMRIGHT",
        aboutPage,
        "BOTTOMRIGHT",
        -28,
        18
    )

    local commandsTitle =
        commandsPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )
    commandsTitle:SetPoint(
        "TOPLEFT",
        0,
        0
    )
    commandsTitle:SetText(
        "Useful Commands"
    )

    local commands = {
        {"/wbgr", "Open Warbound Gear Router."},
        {"/wbgr mailrouter", "Open the Mail Router while at a mailbox."},
        {"/wbgr cleanup", "Rescan and refresh WBGR gear overlays."},
        {"/wbgr pause", "Pause live tooltips, overlays, Gear Finder, and BAG-only routing while keeping tracking active."},
        {"/wbgr resume", "Resume live routing and rebuild overlays."},
        {"/wbgr help", "Show normal WBGR command help."},
    }

    for i, command in ipairs(commands) do
        local commandText =
            commandsPanel:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )
        commandText:SetPoint(
            "TOPLEFT",
            0,
            -32 - ((i - 1) * 24)
        )
        commandText:SetWidth(
            210
        )
        commandText:SetJustifyH(
            "LEFT"
        )
        commandText:SetText(
            command[1]
        )

        local description =
            commandsPanel:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlight"
            )
        description:SetPoint(
            "TOPLEFT",
            225,
            -32 - ((i - 1) * 24)
        )
        description:SetWidth(
            900
        )
        description:SetJustifyH(
            "LEFT"
        )
        description:SetText(
            command[2]
        )
    end

    local gearPanel =
        CreateFrame(
            "Frame",
            nil,
            aboutPage
        )

    gearPanel:SetPoint(
        "TOPLEFT",
        aboutDescription,
        "BOTTOMLEFT",
        0,
        -58
    )
    gearPanel:SetPoint(
        "BOTTOMRIGHT",
        aboutPage,
        "BOTTOMRIGHT",
        -20,
        14
    )

    local gearScroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            gearPanel,
            "UIPanelScrollFrameTemplate"
        )
    gearScroll:SetPoint(
        "TOPLEFT",
        0,
        -32
    )
    gearScroll:SetPoint(
        "BOTTOMRIGHT",
        -28,
        0
    )

    local gearContent =
        CreateFrame(
            "Frame",
            nil,
            gearScroll
        )
    gearContent:SetWidth(
        1260
    )
    gearContent:SetHeight(
        1
    )
    gearScroll:SetScrollChild(
        gearContent
    )

    local gearReference = {
        {
            class = "Death Knight",
            specs = {
                {"Blood","Plate","Tank",{"2H Str: Axe/Mace/Sword"}},
                {"Frost","Plate","DPS / Physical DPS",{"2H Str: Axe/Mace/Sword","Dual 1H Str: Axe/Mace/Sword"}},
                {"Unholy","Plate","DPS / Physical DPS",{"2H Str: Axe/Mace/Sword"}},
            },
        },
        {
            class = "Demon Hunter",
            specs = {
                {"Devourer","Leather","DPS / Caster DPS",{"Dual 1H Int: Warglaive/Axe/Dagger/Fist/Sword"}},
                {"Havoc","Leather","DPS / Physical DPS",{"Dual 1H Agil: Warglaive/Axe/Fist/Sword"}},
                {"Vengeance","Leather","Tank",{"Dual 1H Agil: Warglaive/Axe/Fist/Sword"}},
            },
        },
        {
            class = "Druid",
            specs = {
                {"Balance","Leather","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Mace + Off-hand"}},
                {"Feral","Leather","DPS / Physical DPS",{"2H Agil: Staff/Polearm"}},
                {"Guardian","Leather","Tank",{"2H Agil: Staff/Polearm"}},
                {"Restoration","Leather","Healer",{"2H Int: Staff","1H Int: Dagger/Mace + Off-hand"}},
            },
        },
        {
            class = "Evoker",
            specs = {
                {"Augmentation","Mail","DPS / Caster DPS",{"2H Int: Staff","1H Int: Axe/Dagger/Mace/Sword + Off-hand"}},
                {"Devastation","Mail","DPS / Caster DPS",{"2H Int: Staff","1H Int: Axe/Dagger/Mace/Sword + Off-hand"}},
                {"Preservation","Mail","Healer",{"2H Int: Staff","1H Int: Axe/Dagger/Mace/Sword + Off-hand"}},
            },
        },
        {
            class = "Hunter",
            specs = {
                {"Beast Mastery","Mail","DPS / Physical DPS",{"Ranged: Bow/Crossbow/Gun"}},
                {"Marksmanship","Mail","DPS / Physical DPS",{"Ranged: Bow/Crossbow/Gun"}},
                {"Survival","Mail","DPS / Physical DPS",{"2H Agil: Staff/Polearm","Dual 1H Agil: Axe/Sword"}},
            },
        },
        {
            class = "Mage",
            specs = {
                {"Arcane","Cloth","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Sword/Wand + Off-hand"}},
                {"Fire","Cloth","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Sword/Wand + Off-hand"}},
                {"Frost","Cloth","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Sword/Wand + Off-hand"}},
            },
        },
        {
            class = "Monk",
            specs = {
                {"Brewmaster","Leather","Tank",{"2H Agil: Staff/Polearm","Dual 1H Agil: Axe/Mace/Sword/Fist"}},
                {"Mistweaver","Leather","Healer",{"2H Int: Staff","1H Int: Mace/Sword + Off-hand"}},
                {"Windwalker","Leather","DPS / Physical DPS",{"2H Agil: Staff/Polearm","Dual 1H Agil: Axe/Mace/Sword/Fist"}},
            },
        },
        {
            class = "Paladin",
            specs = {
                {"Holy","Plate","Healer",{"1H Int: Axe/Mace/Sword + Shield"}},
                {"Protection","Plate","Tank",{"1H Str: Axe/Mace/Sword + Shield"}},
                {"Retribution","Plate","DPS / Physical DPS",{"2H Str: Axe/Mace/Sword"}},
            },
        },
        {
            class = "Priest",
            specs = {
                {"Discipline","Cloth","Healer",{"2H Int: Staff","1H Int: Dagger/Mace/Wand + Off-hand"}},
                {"Holy","Cloth","Healer",{"2H Int: Staff","1H Int: Dagger/Mace/Wand + Off-hand"}},
                {"Shadow","Cloth","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Mace/Wand + Off-hand"}},
            },
        },
        {
            class = "Rogue",
            specs = {
                {"Assassination","Leather","DPS / Physical DPS",{"Agility Daggers: Dagger/Dagger"}},
                {"Outlaw","Leather","DPS / Physical DPS",{"Dual 1H Agil: Axe/Mace/Sword/Fist/Dagger"}},
                {"Subtlety","Leather","DPS / Physical DPS",{"Agility Daggers: Dagger/Dagger"}},
            },
        },
        {
            class = "Shaman",
            specs = {
                {"Elemental","Mail","DPS / Caster DPS",{"2H Int: Staff","1H Int: Axe/Dagger/Mace + Shield"}},
                {"Enhancement","Mail","DPS / Physical DPS",{"Dual 1H Agil: Axe/Mace/Fist"}},
                {"Restoration","Mail","Healer",{"2H Int: Staff","1H Int: Axe/Dagger/Mace + Shield"}},
            },
        },
        {
            class = "Warlock",
            specs = {
                {"Affliction","Cloth","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Sword/Wand + Off-hand"}},
                {"Demonology","Cloth","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Sword/Wand + Off-hand"}},
                {"Destruction","Cloth","DPS / Caster DPS",{"2H Int: Staff","1H Int: Dagger/Sword/Wand + Off-hand"}},
            },
        },
        {
            class = "Warrior",
            specs = {
                {"Arms","Plate","DPS / Physical DPS",{"2H Str: Axe/Mace/Sword"}},
                {"Fury","Plate","DPS / Physical DPS",{"Dual 2H Str: Axe/Mace/Sword","Dual 1H Str: Axe/Mace/Sword"}},
                {"Protection","Plate","Tank",{"1H Str: Axe/Mace/Sword + Shield"}},
            },
        },
    }

    local y =
        0

    local function AddHeader(
        text,
        x,
        width
    )
        local fs =
            gearPanel:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )
        fs:SetPoint(
            "TOPLEFT",
            x,
            y
        )
        fs:SetWidth(
            width
        )
        fs:SetJustifyH(
            "LEFT"
        )
        fs:SetText(
            text
        )
    end

    AddHeader("Class", 0, 125)
    AddHeader("Spec", 132, 125)
    AddHeader("Role", 264, 165)
    AddHeader("Armor", 436, 70)
    AddHeader("Weapons", 514, 730)

    -- Headers stay fixed above the scroll child.
    y = 0

    for _, classInfo
        in ipairs(
            gearReference
        )
    do
        for specIndex, specInfo
            in ipairs(
                classInfo.specs
            )
        do
            local lineCount =
                math.max(
                    1,
                    #specInfo[4]
                )

            local rowHeight =
                lineCount == 1
                and 30
                or 42

            local classText =
                gearContent:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontNormal"
                )
            classText:SetPoint(
                "TOPLEFT",
                0,
                y
            )
            classText:SetWidth(
                125
            )
            classText:SetJustifyH(
                "LEFT"
            )
            classText:SetText(
                specIndex == 1
                and classInfo.class
                or ""
            )
            classText:SetTextColor(
                1.00,
                1.00,
                1.00
            )

            local specText =
                gearContent:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontNormal"
                )
            specText:SetPoint(
                "TOPLEFT",
                132,
                y
            )
            specText:SetWidth(
                125
            )
            specText:SetJustifyH(
                "LEFT"
            )
            specText:SetText(
                specInfo[1]
            )
            specText:SetTextColor(
                1.00,
                1.00,
                1.00
            )

            local roleText =
                gearContent:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlight"
                )
            roleText:SetPoint(
                "TOPLEFT",
                264,
                y
            )
            roleText:SetWidth(
                165
            )
            roleText:SetJustifyH(
                "LEFT"
            )
            roleText:SetText(
                specInfo[3]
            )

            local armorText =
                gearContent:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlight"
                )
            armorText:SetPoint(
                "TOPLEFT",
                436,
                y
            )
            armorText:SetWidth(
                70
            )
            armorText:SetJustifyH(
                "LEFT"
            )
            armorText:SetText(
                specInfo[2]
            )

            local weaponText =
                gearContent:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlight"
                )
            weaponText:SetPoint(
                "TOPLEFT",
                514,
                y
            )
            weaponText:SetWidth(
                730
            )
            weaponText:SetJustifyH(
                "LEFT"
            )
            weaponText:SetText(
                table.concat(
                    specInfo[4],
                    "\n"
                )
            )

            y =
                y - rowHeight
        end

        y =
            y - 8
    end

    local notesTitle =
        gearContent:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )
    notesTitle:SetPoint(
        "TOPLEFT",
        0,
        y
    )
    notesTitle:SetText(
        "WBGR Notes"
    )

    y =
        y - 30

    local notesText =
        gearContent:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )
    notesText:SetPoint(
        "TOPLEFT",
        0,
        y
    )
    notesText:SetWidth(
        1240
    )
    notesText:SetJustifyH(
        "LEFT"
    )
    notesText:SetJustifyV(
        "TOP"
    )
    notesText:SetText(
        "Demon Hunter: The global Warglaive-only preference can restrict otherwise eligible generic 1H weapons. Custom Weapons can override it.\n\n"
        .. "Fury Warrior: WBGR supports both Dual 2H and Dual 1H setups. Global and per-character weapon preferences determine which setup is preferred.\n\n"
        .. "Rogue: WBGR can preferentially route Agility Daggers to Rogues when that global preference is enabled."
    )

    local notesHeight =
        math.ceil(
            notesText:GetStringHeight()
            or 0
        )

    gearContent:SetHeight(
        math.abs(y)
        + notesHeight
        + 30
    )

    local function ShowAboutSubtab(
        key
    )
        commandsPanel:SetShown(
            key == "COMMANDS"
        )
        gearPanel:SetShown(
            key == "GEAR"
        )

        for tabKey, button
            in pairs(
                aboutTabs
            )
        do
            local selected =
                tabKey == key

            button.selected =
                selected

            if selected then
                button.label:SetTextColor(
                    1.00,
                    0.82,
                    0.00
                )
                button:SetBackdropColor(
                    0.10,
                    0.10,
                    0.10,
                    0.98
                )
            else
                button.label:SetTextColor(
                    1.00,
                    1.00,
                    1.00
                )
                button:SetBackdropColor(
                    0.04,
                    0.04,
                    0.04,
                    0.92
                )
            end
        end
    end

    commandsTab:SetScript(
        "OnClick",
        function()
            ShowAboutSubtab(
                "COMMANDS"
            )
        end
    )

    gearTab:SetScript(
        "OnClick",
        function()
            ShowAboutSubtab(
                "GEAR"
            )
        end
    )

    ShowAboutSubtab(
        "COMMANDS"
    )
end


local function WGRMailCreateTrackerFrame()
    if WGRMailTracker.frame then
        return
            WGRMailTracker.frame
    end

    local frame =
        CreateFrame(
            "Frame",
            "WGRCheckMailFrame",
            UIParent,
            "BackdropTemplate"
        )

    -- Register immediately so repeated minimap clicks can never
    -- stack duplicate main-window backdrops.
    WGRMailTracker.frame =
        frame

    InitializeDatabase()

    local savedPosition =
        WarboundGearRouterDB.mainWindow

    local minimumWindowHeight = 470
    local maximumWindowHeight = math.max(
        minimumWindowHeight,
        math.floor((UIParent:GetHeight() or 900) - 40)
    )
    local savedHeight = tonumber(savedPosition.height) or minimumWindowHeight
    savedHeight = math.max(
        minimumWindowHeight,
        math.min(maximumWindowHeight, savedHeight)
    )

    frame:SetSize(
        950,
        savedHeight
    )

    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(
            950,
            minimumWindowHeight,
            950,
            maximumWindowHeight
        )
    else
        frame:SetMinResize(950, minimumWindowHeight)
        frame:SetMaxResize(950, maximumWindowHeight)
    end

    frame:SetPoint(
        savedPosition.point
            or "CENTER",
        UIParent,
        savedPosition.relativePoint
            or "CENTER",
        savedPosition.x
            or 360,
        savedPosition.y
            or 100
    )

    frame:SetFrameStrata(
        "DIALOG"
    )

    frame:SetMovable(
        true
    )

    frame:EnableMouse(
        true
    )

    frame:SetClampedToScreen(
        true
    )

    frame:SetBackdrop(
        {
            bgFile =
                "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile =
                "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = {
                left = 4,
                right = 4,
                top = 4,
                bottom = 4,
            },
        }
    )

    local solidBackground =
        frame:CreateTexture(
            nil,
            "BACKGROUND",
            nil,
            -8
        )

    solidBackground:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        4,
        -4
    )

    solidBackground:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -4,
        4
    )

    solidBackground:SetColorTexture(
        0.02,
        0.02,
        0.02,
        1
    )

    frame.WGRSolidBackground =
        solidBackground

    function frame:WGRApplyBackgroundOpacity()
        local percent =
            WarboundGearRouterDB.interface.backgroundOpacity
            or 50

        percent =
            math.max(
                0,
                math.min(
                    100,
                    percent
                )
            )

        if percent <= 50 then
            local legacyScale =
                percent / 50

            self:SetBackdropColor(
                0.05,
                0.05,
                0.05,
                0.96 * legacyScale
            )

            if self.WGRSolidBackground then
                self.WGRSolidBackground:SetAlpha(
                    0
                )
            end
        else
            self:SetBackdropColor(
                0.05,
                0.05,
                0.05,
                0.96
            )

            local solidAlpha =
                (percent - 50)
                / 50

            if self.WGRSolidBackground then
                self.WGRSolidBackground:SetAlpha(
                    solidAlpha
                )
            end
        end
    end

    frame:WGRApplyBackgroundOpacity()

    local close =
        CreateFrame(
            "Button",
            nil,
            frame,
            "UIPanelCloseButton"
        )

    close:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -3,
        -3
    )

    local title =
        frame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    title:SetPoint(
        "TOP",
        frame,
        "TOP",
        0,
        -12
    )

    title:SetText(
        "Warbound Gear Router"
    )

    local routingPauseButton =
        CreateFrame(
            "Button",
            nil,
            frame,
            "UIPanelButtonTemplate"
        )

    routingPauseButton:SetSize(
        150,
        22
    )

    routingPauseButton:SetPoint(
        "TOP",
        frame,
        "TOP",
        0,
        -34
    )

    -- Draw the state text on a child frame above the button template.
    -- The red button artwork can otherwise cover font regions created
    -- directly on the template.
    local routingPauseLabelFrame =
        CreateFrame(
            "Frame",
            nil,
            routingPauseButton
        )

    routingPauseLabelFrame:SetAllPoints(
        routingPauseButton
    )

    routingPauseLabelFrame:SetFrameLevel(
        routingPauseButton:GetFrameLevel()
        + 10
    )

    routingPauseLabelFrame:EnableMouse(
        false
    )

    local routingPauseLabel =
        routingPauseLabelFrame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    routingPauseLabel:SetPoint(
        "CENTER",
        routingPauseLabelFrame,
        "CENTER",
        0,
        0
    )

    routingPauseLabel:SetJustifyH(
        "CENTER"
    )

    routingPauseLabel:SetJustifyV(
        "MIDDLE"
    )

    routingPauseLabel:SetText(
        WGRRoutingIsPaused()
        and "WBGR: PAUSED"
        or "WBGR: ACTIVE"
    )

    routingPauseLabel:SetTextColor(
        WGRRoutingIsPaused()
        and 1.00
        or 0.30,
        WGRRoutingIsPaused()
        and 0.30
        or 1.00,
        0.20
    )

    routingPauseButton.WGRRoutingLabel =
        routingPauseLabel

    routingPauseButton.WGRRoutingLabelFrame =
        routingPauseLabelFrame

    routingPauseButton:SetScript(
        "OnClick",
        function(self)
            WGRSetRoutingPaused(
                not WGRRoutingIsPaused()
            )

            WGRUpdateRoutingPauseButton(
                self
            )
        end
    )

    routingPauseButton:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(
                self,
                "ANCHOR_RIGHT"
            )
            GameTooltip:SetText(
                "Master WBGR Toggle"
            )
            GameTooltip:AddLine(
                "Pause live tooltips, overlays, Gear Finder, and BAG-only routing. Storage/mail/spec tracking stays active.",
                1.00,
                1.00,
                1.00,
                true
            )
            GameTooltip:Show()
        end
    )

    routingPauseButton:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    frame.routingPauseButton =
        routingPauseButton

    WGRRoutingPauseButton =
        routingPauseButton

    WGRUpdateRoutingPauseButton(
        routingPauseButton
    )

    -- Draggable title/header area.
    local dragHandle =
        CreateFrame(
            "Frame",
            nil,
            frame
        )

    dragHandle:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        8,
        -4
    )

    dragHandle:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -36,
        -4
    )

    dragHandle:SetHeight(
        38
    )

    dragHandle:EnableMouse(
        true
    )

    dragHandle:RegisterForDrag(
        "LeftButton"
    )

    dragHandle:SetScript(
        "OnDragStart",
        function()
            frame:StartMoving()
        end
    )

    dragHandle:SetScript(
        "OnDragStop",
        function()
            frame:StopMovingOrSizing()

            local point,
                  relativeTo,
                  relativePoint,
                  xOfs,
                  yOfs =
                frame:GetPoint(
                    1
                )

            -- Update only the position fields so user-selected window
            -- height and any future window preferences are preserved.
            WarboundGearRouterDB.mainWindow.point =
                point or "CENTER"
            WarboundGearRouterDB.mainWindow.relativePoint =
                relativePoint or "CENTER"
            WarboundGearRouterDB.mainWindow.x =
                xOfs or 0
            WarboundGearRouterDB.mainWindow.y =
                yOfs or 0
            WarboundGearRouterDB.mainWindow.height =
                frame:GetHeight() or minimumWindowHeight
        end
    )

    -- Vertical resize grip.  The window can grow downward/upward from its
    -- original 470px height, but cannot be made smaller than the established
    -- layout.  Width remains fixed so approved page layouts do not shift.
    local resizeGrip =
        CreateFrame(
            "Button",
            nil,
            frame
        )

    resizeGrip:SetSize(
        22,
        22
    )
    resizeGrip:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -5,
        5
    )
    resizeGrip:SetFrameLevel(
        frame:GetFrameLevel() + 20
    )

    -- Draw a compact corner-connected resize grip.  Each diagonal spans
    -- between the bottom and right edges so the control reads as part of the
    -- window frame instead of as three floating slash marks.
    local gripLines = {}
    local gripInsets = { 5, 9, 13 }

    for index, inset in ipairs(gripInsets) do
        local line = resizeGrip:CreateTexture(nil, "OVERLAY")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetSize(inset * 1.4142, 1.0)
        line:SetRotation(math.rad(45))
        line:SetPoint(
            "CENTER",
            resizeGrip,
            "BOTTOMRIGHT",
            -(inset / 2),
            inset / 2
        )
        line:SetVertexColor(
            0.48,
            0.45,
            0.36,
            0.85
        )
        gripLines[index] = line
    end

    local function SetResizeGripHighlight(highlighted)
        local r, g, b, a

        if highlighted then
            r, g, b, a = 0.82, 0.68, 0.24, 1.00
        else
            r, g, b, a = 0.48, 0.45, 0.36, 0.85
        end

        for _, line in ipairs(gripLines) do
            line:SetVertexColor(r, g, b, a)
        end
    end

    resizeGrip:SetScript(
        "OnEnter",
        function(self)
            SetResizeGripHighlight(true)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Resize WBGR")
            GameTooltip:AddLine(
                "Drag to make the window taller or return it to its original height.",
                1.00,
                1.00,
                1.00,
                true
            )
            GameTooltip:Show()
        end
    )
    resizeGrip:SetScript(
        "OnLeave",
        function()
            SetResizeGripHighlight(false)
            GameTooltip:Hide()
        end
    )

    resizeGrip:SetScript(
        "OnMouseDown",
        function(_, button)
            if button ~= "LeftButton" then
                return
            end

            frame:StartSizing("BOTTOM")
        end
    )

    resizeGrip:SetScript(
        "OnMouseUp",
        function()
            frame:StopMovingOrSizing()

            -- Defensive clamp for clients where SetResizeBounds is unavailable
            -- or behaves differently under UI scaling.
            local height = math.max(
                minimumWindowHeight,
                math.min(
                    maximumWindowHeight,
                    frame:GetHeight() or minimumWindowHeight
                )
            )
            frame:SetHeight(height)
            WarboundGearRouterDB.mainWindow.height = height
        end
    )

    frame.resizeGrip = resizeGrip

    local function CreateWGRDropdown(parent, width, height)
        local button =
            CreateFrame(
                "Button",
                nil,
                parent,
                "BackdropTemplate"
            )

        button:SetSize(width, height or 22)

        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })

        button:SetBackdropColor(0.08, 0.08, 0.08, 0.95)

        local text =
            button:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        text:SetPoint("LEFT", button, "LEFT", 8, 0)
        text:SetPoint("RIGHT", button, "RIGHT", -25, 0)
        text:SetJustifyH("LEFT")

        local arrow =
            button:CreateTexture(
                nil,
                "ARTWORK"
            )

        arrow:SetSize(16, 16)
        arrow:SetPoint("RIGHT", button, "RIGHT", -5, 0)
        arrow:SetTexture(
            "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"
        )

        button.valueText = text
        button.arrow = arrow

        button.SetValueText =
            function(self, value)
                self.valueText:SetText(value or "")
            end

        return button
    end

    -- Self-contained WGR navigation tabs.
    -- Avoid load-on-demand Blizzard CharacterFrame templates.
    local function CreateWGRTab(
        label,
        width
    )
        local tab =
            CreateFrame(
                "Button",
                nil,
                frame,
                "BackdropTemplate"
            )

        tab:SetSize(
            width,
            28
        )

        tab:SetBackdrop(
            {
                bgFile =
                    "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile =
                    "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 10,
                insets = {
                    left = 3,
                    right = 3,
                    top = 3,
                    bottom = 3,
                },
            }
        )

        tab:SetBackdropColor(
            0.04,
            0.04,
            0.04,
            0.92
        )

        local text =
            tab:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )

        text:SetPoint(
            "CENTER",
            tab,
            "CENTER",
            0,
            0
        )

        text:SetText(
            label
        )

        tab.label =
            text

        tab:SetScript(
            "OnEnter",
            function(self)
                if self:IsEnabled() then
                    self:SetBackdropColor(
                        0.12,
                        0.12,
                        0.12,
                        0.96
                    )
                end
            end
        )

        tab:SetScript(
            "OnLeave",
            function(self)
                if self:IsEnabled() then
                    self:SetBackdropColor(
                        0.04,
                        0.04,
                        0.04,
                        0.92
                    )
                end
            end
        )

        return tab
    end

    -- Five equal-width main tabs centered across the window.
    local tabWidth =
        160

    local tabGap =
        16

    local tabTotalWidth =
        (tabWidth * 5)
        + (tabGap * 4)

    local tabStartX =
        math.floor(
            (
                frame:GetWidth()
                - tabTotalWidth
            )
            / 2
        )

    local tabMail =
        CreateWGRTab(
            "To Do (0)",
            tabWidth
        )

    tabMail:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        tabStartX,
        -62
    )

    local tabGearFinder =
        CreateWGRTab(
            "Gear Finder",
            tabWidth
        )

    tabGearFinder:SetPoint(
        "LEFT",
        tabMail,
        "RIGHT",
        tabGap,
        0
    )

    local tabRoster =
        CreateWGRTab(
            "Roster",
            tabWidth
        )

    tabRoster:SetPoint(
        "LEFT",
        tabGearFinder,
        "RIGHT",
        tabGap,
        0
    )

    local tabSettings =
        CreateWGRTab(
            "Settings",
            tabWidth
        )

    tabSettings:SetPoint(
        "LEFT",
        tabRoster,
        "RIGHT",
        tabGap,
        0
    )

    local tabAbout =
        CreateWGRTab(
            "About",
            tabWidth
        )

    tabAbout:SetPoint(
        "LEFT",
        tabSettings,
        "RIGHT",
        tabGap,
        0
    )

    frame.tabs = {
        MAIL =
            tabMail,
        GEAR_FINDER =
            tabGearFinder,
        ROSTER =
            tabRoster,
        SETTINGS =
            tabSettings,
        ABOUT =
            tabAbout,
    }

    -- Content starts well below tabs.
    local pageTop =
        -92

    WGRCreateGearFinderPage(
        frame,
        pageTop
    )

    -- ========================================================
    -- TO DO / RECENT ACTIVITY PAGE
    -- ========================================================
    local mailPage =
        CreateFrame(
            "Frame",
            nil,
            frame
        )

    mailPage:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        18,
        pageTop
    )

    mailPage:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -18,
        18
    )

    frame.mailPage =
        mailPage

    local todoWidth =
        520

    local dividerX =
        540

    local todoTitle =
        mailPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    todoTitle:SetPoint(
        "TOPLEFT",
        mailPage,
        "TOPLEFT",
        0,
        0
    )

    todoTitle:SetText(
        "To Do"
    )

    local todoSummary =
        mailPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    todoSummary:SetPoint(
        "TOPLEFT",
        todoTitle,
        "BOTTOMLEFT",
        0,
        -5
    )

    todoSummary:Hide()

    todoSummary:SetWidth(
        340
    )

    todoSummary:SetJustifyH(
        "LEFT"
    )

    todoSummary:SetTextColor(
        0.72,
        0.72,
        0.72
    )

    local todoSortLabel =
        mailPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    todoSortLabel:SetPoint(
        "TOPLEFT",
        todoTitle,
        "BOTTOMLEFT",
        0,
        -8
    )

    todoSortLabel:SetText(
        "Sort:"
    )

    local todoSortDropdown =
        CreateFrame(
            "Frame",
            nil,
            mailPage,
            "UIDropDownMenuTemplate"
        )

    todoSortDropdown:SetPoint(
        "LEFT",
        todoSortLabel,
        "RIGHT",
        -8,
        -1
    )

    UIDropDownMenu_SetWidth(
        todoSortDropdown,
        88
    )

    local todoSortLabels = {
        URGENCY = "Urgency",
        PRIORITY = "Priority",
        NAME = "Name",
    }

    local function WGRRefreshTodoSortDropdown()
        local mode =
            WarboundGearRouterDB.todoSortMode
            or "URGENCY"

        UIDropDownMenu_SetText(
            todoSortDropdown,
            todoSortLabels[mode]
            or "Urgency"
        )
    end

    UIDropDownMenu_Initialize(
        todoSortDropdown,
        function()
            for _, mode
                in ipairs({
                    "URGENCY",
                    "PRIORITY",
                    "NAME",
                })
            do
                local info =
                    UIDropDownMenu_CreateInfo()

                info.text =
                    todoSortLabels[mode]

                info.checked =
                    WarboundGearRouterDB.todoSortMode
                    == mode

                info.func =
                    function()
                        WarboundGearRouterDB.todoSortMode =
                            mode

                        WGRRefreshTodoSortDropdown()

                        if frame.UpdateTodoPage then
                            frame.UpdateTodoPage()
                        end
                    end

                UIDropDownMenu_AddButton(
                    info
                )
            end
        end
    )

    WGRRefreshTodoSortDropdown()

    local openRouter =
        CreateFrame(
            "Button",
            nil,
            mailPage,
            "UIPanelButtonTemplate"
        )

    openRouter:SetSize(
        124,
        23
    )

    openRouter:SetPoint(
        "TOPRIGHT",
        mailPage,
        "TOPLEFT",
        todoWidth,
        -2
    )

    openRouter:SetText(
        "Open Mail Router"
    )

    openRouter:SetScript(
        "OnClick",
        function()
            if WGRMailOpenRouterManual then
                WGRMailOpenRouterManual()
            end
        end
    )

    openRouter:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(
                self,
                "ANCHOR_RIGHT"
            )

            GameTooltip:AddLine(
                "Open Mail Router",
                1.00,
                0.82,
                0.00
            )

            if WGRMail
                and WGRMail.mailboxOpen
            then
                GameTooltip:AddLine(
                    "Reopen the WBGR Mail Router for this character.",
                    1.00,
                    1.00,
                    1.00
                )
            else
                GameTooltip:AddLine(
                    "Open a mailbox to use the Mail Router.",
                    0.85,
                    0.85,
                    0.85
                )
            end

            GameTooltip:Show()
        end
    )

    openRouter:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    frame.openRouterButton =
        openRouter

    local routerRequirement =
        mailPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    routerRequirement:SetPoint(
        "TOPRIGHT",
        openRouter,
        "BOTTOMRIGHT",
        0,
        -3
    )

    routerRequirement:SetTextColor(
        0.62,
        0.62,
        0.62
    )

    routerRequirement:SetText(
        "Open a mailbox to use the Mail Router."
    )

    frame.routerRequirement =
        routerRequirement

    local divider =
        mailPage:CreateTexture(
            nil,
            "ARTWORK"
        )

    divider:SetColorTexture(
        1.00,
        1.00,
        1.00,
        0.28
    )

    divider:SetWidth(
        1
    )

    divider:SetPoint(
        "TOPLEFT",
        mailPage,
        "TOPLEFT",
        dividerX,
        -2
    )

    divider:SetPoint(
        "BOTTOMLEFT",
        mailPage,
        "BOTTOMLEFT",
        dividerX,
        0
    )

    local activityTitle =
        mailPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    activityTitle:SetPoint(
        "TOPLEFT",
        mailPage,
        "TOPLEFT",
        dividerX + 18,
        0
    )

    activityTitle:SetText(
        "Recent Activity"
    )

    local activitySummary =
        mailPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    activitySummary:SetPoint(
        "TOPLEFT",
        activityTitle,
        "BOTTOMLEFT",
        0,
        -5
    )

    activitySummary:SetTextColor(
        0.58,
        0.58,
        0.58
    )

    activitySummary:SetText(
        ""
    )

    local todoScroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            mailPage,
            "UIPanelScrollFrameTemplate"
        )

    todoScroll:SetPoint(
        "TOPLEFT",
        todoSortLabel,
        "BOTTOMLEFT",
        0,
        -14
    )

    todoScroll:SetPoint(
        "BOTTOMRIGHT",
        mailPage,
        "BOTTOMLEFT",
        todoWidth - 22,
        0
    )

    local todoContent =
        CreateFrame(
            "Frame",
            nil,
            todoScroll
        )

    todoContent:SetWidth(
        todoWidth - 48
    )

    todoContent:SetHeight(
        1
    )

    todoScroll:SetScrollChild(
        todoContent
    )

    local activityScroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            mailPage,
            "UIPanelScrollFrameTemplate"
        )

    activityScroll:SetPoint(
        "TOPLEFT",
        activityTitle,
        "BOTTOMLEFT",
        0,
        -12
    )

    activityScroll:SetPoint(
        "BOTTOMRIGHT",
        mailPage,
        "BOTTOMRIGHT",
        -22,
        0
    )

    local activityContent =
        CreateFrame(
            "Frame",
            nil,
            activityScroll
        )

    activityContent:SetWidth(
        292
    )

    activityContent:SetHeight(
        1
    )

    activityScroll:SetScrollChild(
        activityContent
    )

    frame.todoScroll =
        todoScroll
    frame.todoContent =
        todoContent
    frame.activityScroll =
        activityScroll
    frame.activityContent =
        activityContent
    frame.todoRows =
        {}
    frame.activityRows =
        {}

    if not StaticPopupDialogs[
        "WGR_CONFIRM_DISMISS_TODO"
    ]
    then
        StaticPopupDialogs[
            "WGR_CONFIRM_DISMISS_TODO"
        ] = {
            text =
                "Dismiss this To Do?\n\n%s\n\nWBGR still detects this task as incomplete. Dismissing it only hides the current reminder; a future trigger can create it again.",
            button1 =
                "Dismiss Anyway",
            button2 =
                "Cancel",
            OnAccept =
                function(
                    self,
                    data
                )
                    if data
                        and data.entry
                    then
                        WGRDismissTodoEntry(
                            data.entry
                        )
                    end
                end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local function CreateTodoRow(
        index
    )
        local row =
            CreateFrame(
                "Frame",
                nil,
                todoContent
            )

        row:SetSize(
            todoWidth - 52,
            76
        )

        local title =
            row:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )

        title:SetPoint(
            "TOPLEFT",
            row,
            "TOPLEFT",
            2,
            -2
        )

        title:SetWidth(
            305
        )

        title:SetJustifyH(
            "LEFT"
        )

        local detail =
            row:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        detail:SetPoint(
            "TOPLEFT",
            title,
            "BOTTOMLEFT",
            0,
            -4
        )

        detail:SetWidth(
            305
        )

        detail:SetJustifyH(
            "LEFT"
        )

        detail:SetJustifyV(
            "TOP"
        )

        detail:SetTextColor(
            0.78,
            0.78,
            0.78
        )

        local urgency =
            row:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        urgency:SetPoint(
            "TOPLEFT",
            detail,
            "BOTTOMLEFT",
            0,
            -4
        )

        urgency:SetWidth(
            305
        )

        urgency:SetJustifyH(
            "LEFT"
        )

        local action =
            CreateFrame(
                "Button",
                nil,
                row,
                "UIPanelButtonTemplate"
            )

        action:SetSize(
            132,
            23
        )

        action:SetPoint(
            "TOPRIGHT",
            row,
            "TOPRIGHT",
            -2,
            -4
        )

        local actionHelp =
            row:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        actionHelp:SetPoint(
            "TOPRIGHT",
            row,
            "TOPRIGHT",
            -2,
            -31
        )

        actionHelp:SetWidth(
            124
        )

        actionHelp:SetJustifyH(
            "RIGHT"
        )

        actionHelp:SetTextColor(
            0.58,
            0.58,
            0.58
        )

        actionHelp:Hide()

        local dismiss =
            CreateFrame(
                "Button",
                nil,
                row,
                "UIPanelButtonTemplate"
            )

        dismiss:SetSize(
            72,
            20
        )

        dismiss:SetPoint(
            "TOPRIGHT",
            action,
            "BOTTOMRIGHT",
            0,
            -6
        )

        dismiss:SetText(
            "Dismiss"
        )

        local line =
            row:CreateTexture(
                nil,
                "ARTWORK"
            )

        line:SetColorTexture(
            1.00,
            1.00,
            1.00,
            0.09
        )

        line:SetHeight(
            1
        )

        line:SetPoint(
            "BOTTOMLEFT",
            row,
            "BOTTOMLEFT",
            0,
            1
        )

        line:SetPoint(
            "BOTTOMRIGHT",
            row,
            "BOTTOMRIGHT",
            0,
            1
        )

        row.title =
            title
        row.detail =
            detail
        row.urgency =
            urgency
        row.action =
            action
        row.actionHelp =
            actionHelp
        row.dismiss =
            dismiss

        frame.todoRows[
            index
        ] =
            row

        return row
    end

    local function CreateActivityRow(
        index
    )
        local row =
            CreateFrame(
                "Frame",
                nil,
                activityContent
            )

        row:SetSize(
            286,
            22
        )

        local text =
            row:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        text:SetPoint(
            "TOPLEFT",
            row,
            "TOPLEFT",
            2,
            -2
        )

        text:SetWidth(
            280
        )

        text:SetJustifyH(
            "LEFT"
        )

        text:SetJustifyV(
            "TOP"
        )

        text:SetTextColor(
            0.55,
            0.55,
            0.55
        )

        row.text =
            text

        frame.activityRows[
            index
        ] =
            row

        return row
    end

    frame.UpdateTodoPage =
        function()
            InitializeDatabase()

            local entries =
                WGRTodoBuildList()

            WGRUpdateMailTabLabel(
                #entries
            )

            todoSummary:SetText(
                string.format(
                    "%d action%s need attention",
                    #entries,
                    #entries == 1
                        and ""
                        or "s"
                )
            )

            local currentName =
                UnitName("player")

            for index, entry
                in ipairs(entries)
            do
                local row =
                    frame.todoRows[
                        index
                    ]
                    or CreateTodoRow(
                        index
                    )

                row:ClearAllPoints()
                row:SetPoint(
                    "TOPLEFT",
                    todoContent,
                    "TOPLEFT",
                    0,
                    -(
                        (index - 1)
                        * 70
                    )
                )

                row.title:SetText(
                    entry.title
                    or "To Do"
                )

                local baseDetail =
                    entry.detail
                    or ""

                row.detail:SetText(
                    baseDetail
                )

                row.urgency:SetText(
                    entry.urgency
                    or ""
                )

                if entry.kind
                    == "MAIL_RETRIEVE"
                then
                    local r, g, b =
                        WGRMailUrgencyColor(
                            entry.remaining
                        )

                    row.urgency:SetTextColor(
                        r,
                        g,
                        b
                    )
                elseif entry.kind
                    == "INITIALIZE_SPECS"
                then
                    row.urgency:SetTextColor(
                        1.00,
                        0.72,
                        0.20
                    )
                else
                    row.urgency:SetTextColor(
                        0.62,
                        0.62,
                        0.62
                    )
                end

                row.action:Hide()
                row.actionHelp:SetText(
                    ""
                )
                row.actionHelp:Hide()

                if entry.kind
                    == "MAIL_RETRIEVE"
                then
                    row.action:Show()
                    row.action:SetText(
                        "Retrieve Mail"
                    )

                    local isCurrent =
                        currentName
                        and string.lower(
                            tostring(
                                currentName
                            )
                        )
                        == string.lower(
                            tostring(
                                entry.character
                            )
                        )

                    local mailboxOpen =
                        WGRMail
                        and WGRMail.mailboxOpen

                    row.action:SetEnabled(
                        isCurrent
                        and mailboxOpen
                    )

                    if not isCurrent then
                        row.detail:SetText(
                            baseDetail
                            .. "\nLog onto "
                            .. tostring(
                                entry.character
                            )
                            .. " and open a mailbox."
                        )
                    elseif not mailboxOpen then
                        row.detail:SetText(
                            baseDetail
                            .. "\nOpen a mailbox first."
                        )
                    end

                    row.action:SetScript(
                        "OnClick",
                        function()
                            if WGRMailRetrieveTrackedForCurrent then
                                WGRMailRetrieveTrackedForCurrent()
                            end
                        end
                    )

                elseif entry.action
                    == "SEND_CONTEXT"
                then
                    row.action:Show()

                    local isCurrent =
                        currentName
                        and string.lower(
                            tostring(
                                currentName
                            )
                        )
                        == string.lower(
                            tostring(
                                entry.character
                            )
                        )

                    local mailboxOpen =
                        WGRMail
                        and WGRMail.mailboxOpen

                    local warbandOpen =
                        WGRGearFinderIsWarbandBankOpen
                        and WGRGearFinderIsWarbandBankOpen()

                    row.action:SetScript(
                        "OnEnter",
                        function(self)
                            GameTooltip:SetOwner(
                                self,
                                "ANCHOR_RIGHT"
                            )

                            if mailboxOpen then
                                GameTooltip:AddLine(
                                    "Open Mail Router",
                                    1.00,
                                    0.82,
                                    0.00
                                )
                                GameTooltip:AddLine(
                                    "Open the Mail Router for this character's routed items.",
                                    1.00,
                                    1.00,
                                    1.00
                                )
                            elseif warbandOpen then
                                GameTooltip:AddLine(
                                    "Deposit to WBK",
                                    1.00,
                                    0.82,
                                    0.00
                                )
                                GameTooltip:AddLine(
                                    "Deposit this character's routed items into the Warband Bank.",
                                    1.00,
                                    1.00,
                                    1.00
                                )
                            else
                                GameTooltip:AddLine(
                                    "Mail or WBK",
                                    1.00,
                                    0.82,
                                    0.00
                                )
                                GameTooltip:AddLine(
                                    "Open a mailbox or the Warband Bank to continue.",
                                    0.85,
                                    0.85,
                                    0.85
                                )
                            end

                            GameTooltip:Show()
                        end
                    )

                    row.action:SetScript(
                        "OnLeave",
                        function()
                            GameTooltip:Hide()
                        end
                    )

                    if not isCurrent then
                        row.action:SetText(
                            "Mail or WBK"
                        )
                        row.action:Disable()
                        row.detail:SetText(
                            baseDetail
                            .. "\nLog onto "
                            .. tostring(
                                entry.character
                            )
                            .. " first."
                        )
                        row.action:SetScript(
                            "OnClick",
                            nil
                        )
                    elseif mailboxOpen then
                        row.action:SetText(
                            "Open Mail Router"
                        )
                        row.action:Enable()
                        row.action:SetScript(
                            "OnClick",
                            function()
                                if WGRMailOpenRouterManual then
                                    WGRMailOpenRouterManual()
                                end
                            end
                        )
                    elseif warbandOpen then
                        row.action:SetText(
                            "Deposit to WBK"
                        )
                        row.action:Enable()
                        row.action:SetScript(
                            "OnClick",
                            function()
                                if WGRGearFinderDepositCurrentOutgoingToWarband then
                                    WGRGearFinderDepositCurrentOutgoingToWarband()
                                end
                            end
                        )
                    else
                        row.action:SetText(
                            "Mail or WBK"
                        )
                        row.action:Disable()
                        row.action:SetScript(
                            "OnClick",
                            nil
                        )
                    end

                elseif entry.action
                    == "GEAR_FINDER"
                then
                    row.action:Show()
                    row.action:SetText(
                        "Open Gear Finder"
                    )
                    row.action:Enable()
                    row.detail:SetText(
                        baseDetail
                        .. "\nOpen Gear Finder and scan the Warband Bank to update this count."
                    )
                    row.action:SetScript(
                        "OnClick",
                        function()
                            WGRShowMainTab(
                                "GEAR_FINDER"
                            )
                        end
                    )
                end

                row.dismiss:SetScript(
                    "OnClick",
                    function()
                        StaticPopup_Show(
                            "WGR_CONFIRM_DISMISS_TODO",
                            entry.title
                                or "This task",
                            nil,
                            {
                                entry =
                                    entry,
                            }
                        )
                    end
                )

                row:Show()
            end

            for index =
                #entries + 1,
                #frame.todoRows
            do
                frame.todoRows[
                    index
                ]:Hide()
            end

            todoContent:SetHeight(
                math.max(
                    1,
                    #entries * 70
                )
            )

            if todoScroll.UpdateScrollChildRect then
                todoScroll:UpdateScrollChildRect()
            end

            if #entries == 0 then
                todoSummary:SetText(
                    "Nothing needs attention."
                )
            end

            local activity =
                WarboundGearRouterDB.recentActivity
                or {}

            for index, entry
                in ipairs(activity)
            do
                local row =
                    frame.activityRows[
                        index
                    ]
                    or CreateActivityRow(
                        index
                    )

                row:ClearAllPoints()
                row:SetPoint(
                    "TOPLEFT",
                    activityContent,
                    "TOPLEFT",
                    0,
                    -(
                        (index - 1)
                        * 24
                    )
                )

                row.text:SetText(
                    entry.text
                    or ""
                )

                row:Show()
            end

            for index =
                #activity + 1,
                #frame.activityRows
            do
                frame.activityRows[
                    index
                ]:Hide()
            end

            activityContent:SetHeight(
                math.max(
                    1,
                    #activity * 24
                )
            )

            if activityScroll.UpdateScrollChildRect then
                activityScroll:UpdateScrollChildRect()
            end

            if #activity == 0 then
                activitySummary:SetText(
                    "No recent activity yet."
                )
            else
                activitySummary:SetText(
                    ""
                )
            end

            WGRUpdateOpenRouterButton()
        end

    mailPage:SetScript(
        "OnShow",
        function()
            frame.UpdateTodoPage()
        end
    )

    frame.UpdateTodoPage()

    local WGRRosterSortLabels = {
        PRIORITY = "Priority",
        HOLDERS = "Gear Holders",
        NAME = "Name",
        LEVEL = "Level",
        CLASS = "Class",
        PLAYTIME = "Playtime",
        ILVL = "Item Level",
        STATUS = "Status",
    }

    local function WGRRosterPriorityIndex(priority)
        local positions = {}

        for index, name in ipairs(priority) do
            positions[string.lower(name)] = index
        end

        return positions
    end

    local function WGRRosterLevel(characterName)
        local character = FindCharacterByName(characterName)

        if character
            and DataStore
            and DataStore.GetCharacterLevel
        then
            return DataStore:GetCharacterLevel(character) or 0
        end

        return 0
    end

    local function WGRRosterClass(characterName)
        local character = FindCharacterByName(characterName)
        return WGRGetRosterClassName(characterName, character) or ""
    end

    local function WGRRosterPlaytime(characterName)
        local character = FindCharacterByName(characterName)

        if character
            and DataStore
            and DataStore.GetRealPlayTime
        then
            return DataStore:GetRealPlayTime(character) or 0
        end

        return 0
    end


    local WGRAverageItemLevelSlots = {
        1,  -- Head
        2,  -- Neck
        3,  -- Shoulder
        5,  -- Chest
        6,  -- Waist
        7,  -- Legs
        8,  -- Feet
        9,  -- Wrist
        10, -- Hands
        11, -- Finger 1
        12, -- Finger 2
        13, -- Trinket 1
        14, -- Trinket 2
        15, -- Back
        16, -- Main Hand
        17, -- Off Hand
    }

    local function WGRRosterItemLevel(characterName)
        local character =
            FindCharacterByName(
                characterName
            )

        if not character then
            return 0
        end

        -- Prefer a DataStore-native average if the installed version
        -- exposes one.
        if DataStore
            and DataStore.GetAverageItemLevel
        then
            local ok, value =
                pcall(
                    DataStore.GetAverageItemLevel,
                    DataStore,
                    character
                )

            if ok
                and tonumber(value)
                and tonumber(value) > 0
            then
                return tonumber(value)
            end
        end

        local total = 0
        local count = 0
        local mainHandLevel = nil
        local mainHandTwoHanded = false

        for _, slotID
            in ipairs(
                WGRAverageItemLevelSlots
            )
        do
            local item =
                GetStoredItem(
                    character,
                    slotID
                )

            if item then
                local level =
                    GetItemLevel(
                        item
                    )

                if level then
                    total =
                        total + level
                    count =
                        count + 1

                    if slotID == 16 then
                        mainHandLevel =
                            level

                        local _, _, _, equipLoc =
                            GetInstantItemInfo(
                                item
                            )

                        mainHandTwoHanded =
                            equipLoc == "INVTYPE_2HWEAPON"
                            or equipLoc == "INVTYPE_RANGED"
                            or equipLoc == "INVTYPE_RANGEDRIGHT"
                    end
                else
                    -- Unknown saved item: treat as empty for a stable
                    -- low-geared-first sort rather than inventing ilvl.
                    count =
                        count + 1
                end
            else
                if slotID == 17
                    and mainHandTwoHanded
                    and mainHandLevel
                then
                    -- A two-handed weapon effectively fills the weapon
                    -- setup for average-item-level purposes.
                    total =
                        total + mainHandLevel
                    count =
                        count + 1
                else
                    count =
                        count + 1
                end
            end
        end

        if count <= 0 then
            return 0
        end

        return total / count
    end

    local function WGRFormatRosterPlaytime(seconds)
        seconds =
            tonumber(seconds)
            or 0

        if seconds <= 0 then
            return "?"
        end

        local hours =
            math.floor(
                (seconds / 3600)
                + 0.5
            )

        if hours < 24 then
            return
                tostring(hours)
                .. "h"
        end

        local days =
            math.floor(
                (hours / 24)
                + 0.5
            )

        return
            tostring(days)
            .. "d"
    end

    local function WGRGetRosterView(priority)
        local view = {}

        for _, name in ipairs(priority) do
            table.insert(view, name)
        end

        local mode =
            WarboundGearRouterDB.interface.rosterViewSort
            or "PRIORITY"

        if mode == "PRIORITY" then
            local directions =
                WarboundGearRouterDB.interface.rosterSortDirections
                or {}

            if directions.PRIORITY == "DESC" then
                local reversed = {}

                for i = #view, 1, -1 do
                    table.insert(
                        reversed,
                        view[i]
                    )
                end

                return reversed
            end

            return view
        end

        local priorityIndex =
            WGRRosterPriorityIndex(priority)

        if mode == "HOLDERS" then
            table.sort(
                view,
                function(a, b)
                    local aSummary =
                        WGRRosterHeldGearSummary(
                            a
                        )

                    local bSummary =
                        WGRRosterHeldGearSummary(
                            b
                        )

                    local aHolder =
                        aSummary
                        and (
                            tonumber(
                                aSummary.total
                            )
                            or 0
                        ) > 0
                        or false

                    local bHolder =
                        bSummary
                        and (
                            tonumber(
                                bSummary.total
                            )
                            or 0
                        ) > 0
                        or false

                    if aHolder
                        ~= bHolder
                    then
                        return aHolder
                    end

                    return
                        (
                            priorityIndex[
                                string.lower(a)
                            ]
                            or 9999
                        )
                        <
                        (
                            priorityIndex[
                                string.lower(b)
                            ]
                            or 9999
                        )
                end
            )

            return view
        end

        table.sort(
            view,
            function(a, b)
                local aKey
                local bKey

                if mode == "NAME" then
                    aKey = string.lower(a)
                    bKey = string.lower(b)
                elseif mode == "LEVEL" then
                    aKey = WGRRosterLevel(a)
                    bKey = WGRRosterLevel(b)
                elseif mode == "CLASS" then
                    aKey = string.lower(WGRRosterClass(a))
                    bKey = string.lower(WGRRosterClass(b))
                elseif mode == "PLAYTIME" then
                    aKey = WGRRosterPlaytime(a)
                    bKey = WGRRosterPlaytime(b)
                elseif mode == "ILVL" then
                    aKey = WGRRosterItemLevel(a)
                    bKey = WGRRosterItemLevel(b)
                elseif mode == "STATUS" then
                    aKey = WGRIsCharacterIgnored(a) and 1 or 0
                    bKey = WGRIsCharacterIgnored(b) and 1 or 0
                end

                if aKey == bKey then
                    return
                        (priorityIndex[string.lower(a)] or 9999)
                        <
                        (priorityIndex[string.lower(b)] or 9999)
                end

                local directions =
                    WarboundGearRouterDB.interface.rosterSortDirections
                    or {}

                local direction =
                    directions[mode]
                    or "ASC"

                if direction == "DESC" then
                    return aKey > bKey
                end

                return aKey < bKey
            end
        )

        return view
    end

    -- ========================================================
    -- ROSTER PAGE
    -- ========================================================
    local rosterPage =
        CreateFrame(
            "Frame",
            nil,
            frame
        )

    rosterPage:SetAllPoints(
        mailPage
    )

    rosterPage:Hide()

    frame.rosterPage =
        rosterPage

    local rosterTitle =
        rosterPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    rosterTitle:SetPoint(
        "TOPLEFT",
        rosterPage,
        "TOPLEFT",
        0,
        0
    )

    rosterTitle:SetText(
        "Global Routing Priority"
    )

    local rosterCount =
        rosterPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    rosterCount:SetPoint(
        "TOPRIGHT",
        rosterPage,
        "TOPRIGHT",
        -6,
        0
    )

    rosterCount:SetTextColor(
        0.72,
        0.72,
        0.72
    )

    rosterCount:SetText(
        tostring(#GetRoutingPriority())
            .. " characters"
    )

    frame.rosterCount =
        rosterCount

    local rosterViewLabel =
        rosterPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    rosterViewLabel:SetPoint(
        "TOPLEFT",
        rosterPage,
        "TOPLEFT",
        0,
        -66
    )

    rosterViewLabel:SetText(
        "View / Sort By"
    )

    local rosterViewDropdown =
        CreateWGRDropdown(
            rosterPage,
            130,
            22
        )

    rosterViewDropdown:SetPoint(
        "LEFT",
        rosterViewLabel,
        "RIGHT",
        12,
        0
    )

    local WGRUpdateDirectionDropdown

    local function WGRUpdateRosterViewDropdown()
        local mode =
            WarboundGearRouterDB.interface.rosterViewSort
            or "PRIORITY"

        rosterViewDropdown:SetValueText(
            WGRRosterSortLabels[mode]
            or "Priority"
        )
    end

    rosterViewDropdown:SetScript(
        "OnClick",
        function(self)
            MenuUtil.CreateContextMenu(
                self,
                function(ownerRegion, rootDescription)
                    rootDescription:CreateTitle(
                        "View / Sort By"
                    )

                    for _, mode in ipairs({
                        "PRIORITY",
                        "HOLDERS",
                        "NAME",
                        "LEVEL",
                        "CLASS",
                        "PLAYTIME",
                        "ILVL",
                        "STATUS",
                    }) do
                        local value = mode

                        rootDescription:CreateRadio(
                            WGRRosterSortLabels[value],
                            function()
                                return
                                    WarboundGearRouterDB.interface.rosterViewSort
                                    == value
                            end,
                            function()
                                WarboundGearRouterDB.interface.rosterViewSort =
                                    value
                                WGRUpdateRosterViewDropdown()
                                WGRUpdateDirectionDropdown()
                                frame.UpdateRoster()
                            end
                        )
                    end
                end
            )
        end
    )

    WGRUpdateRosterViewDropdown()

    local directionLabel =
        rosterPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    directionLabel:SetPoint(
        "LEFT",
        rosterViewDropdown,
        "RIGHT",
        18,
        0
    )

    directionLabel:SetText(
        "Direction"
    )

    local directionDropdown =
        CreateWGRDropdown(
            rosterPage,
            120,
            22
        )

    directionDropdown:SetPoint(
        "LEFT",
        directionLabel,
        "RIGHT",
        10,
        0
    )

    local directionNames = {
        ASC = "Ascending",
        DESC = "Descending",
    }

    WGRUpdateDirectionDropdown = function()
        local mode =
            WarboundGearRouterDB.interface.rosterViewSort
            or "PRIORITY"

        local directions =
            WarboundGearRouterDB.interface.rosterSortDirections
            or {}

        if mode == "HOLDERS" then
            directionDropdown:SetValueText(
                "Priority order"
            )
            directionDropdown:Disable()
            return
        end

        directionDropdown:Enable()

        local direction =
            directions[mode]
            or "ASC"

        directionDropdown:SetValueText(
            directionNames[direction]
            or "Ascending"
        )
    end

    directionDropdown:SetScript(
        "OnClick",
        function(self)
            MenuUtil.CreateContextMenu(
                self,
                function(ownerRegion, rootDescription)
                    rootDescription:CreateTitle(
                        "Sort Direction"
                    )

                    local mode =
                        WarboundGearRouterDB.interface.rosterViewSort
                        or "PRIORITY"

                    for _, direction
                        in ipairs({
                            "ASC",
                            "DESC",
                        })
                    do
                        local value =
                            direction

                        rootDescription:CreateRadio(
                            directionNames[value],
                            function()
                                local directions =
                                    WarboundGearRouterDB.interface.rosterSortDirections
                                    or {}

                                return
                                    directions[mode]
                                    == value
                            end,
                            function()
                                WarboundGearRouterDB.interface.rosterSortDirections =
                                    WarboundGearRouterDB.interface.rosterSortDirections
                                    or {}

                                WarboundGearRouterDB.interface.rosterSortDirections[mode] =
                                    value

                                WGRUpdateDirectionDropdown()
                                frame.UpdateRoster()
                            end
                        )
                    end
                end
            )
        end
    )

    WGRUpdateDirectionDropdown()

    local rosterViewHelp =
        rosterPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    rosterViewHelp:SetPoint(
        "LEFT",
        directionDropdown,
        "RIGHT",
        14,
        0
    )

    rosterViewHelp:SetTextColor(
        0.68,
        0.68,
        0.68
    )

    rosterViewHelp:SetText(
        "View sorting does not change priority."
    )

    local priorityToolsLabel =
        rosterPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    priorityToolsLabel:SetPoint(
        "TOPLEFT",
        rosterPage,
        "TOPLEFT",
        0,
        -38
    )

    priorityToolsLabel:SetText(
        "Priority Tools"
    )

    local restorePriorityButton =
        CreateFrame(
            "Button",
            nil,
            rosterPage,
            "UIPanelButtonTemplate"
        )

    restorePriorityButton:SetSize(
        142,
        22
    )

    restorePriorityButton:SetPoint(
        "LEFT",
        priorityToolsLabel,
        "RIGHT",
        10,
        0
    )

    restorePriorityButton:SetText(
        "Restore Previous"
    )

    frame.restorePriorityButton =
        restorePriorityButton

    local setPriorityFromViewButton =
        CreateFrame(
            "Button",
            nil,
            rosterPage,
            "UIPanelButtonTemplate"
        )

    setPriorityFromViewButton:SetSize(
        158,
        22
    )

    setPriorityFromViewButton:SetPoint(
        "LEFT",
        restorePriorityButton,
        "RIGHT",
        8,
        0
    )

    setPriorityFromViewButton:SetText(
        "Set From Current View"
    )

    frame.setPriorityFromViewButton =
        setPriorityFromViewButton

    local dragHint =
        rosterPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    dragHint:SetPoint(
        "LEFT",
        setPriorityFromViewButton,
        "RIGHT",
        10,
        0
    )

    dragHint:SetTextColor(
        0.68,
        0.68,
        0.68
    )

    dragHint:SetText(
        ""
    )

    local function WGRUpdatePriorityTools()
        local hasBackup =
            WGRHasPriorityBackup()

        restorePriorityButton:SetEnabled(
            hasBackup
        )

        if hasBackup then
            restorePriorityButton:SetAlpha(
                1.00
            )
        else
            restorePriorityButton:SetAlpha(
                0.45
            )
        end

        local priority =
            GetRoutingPriority()

        local view =
            WGRGetRosterView(
                priority
            )

        local differs =
            not WGRPriorityListsEqual(
                priority,
                view
            )

        setPriorityFromViewButton:SetEnabled(
            differs
        )

        setPriorityFromViewButton:SetAlpha(
            differs
            and 1.00
            or 0.45
        )
    end

    frame.UpdatePriorityTools =
        WGRUpdatePriorityTools

    setPriorityFromViewButton:SetScript(
        "OnClick",
        function()
            local priority =
                GetRoutingPriority()

            local view =
                WGRGetRosterView(
                    priority
                )

            if WGRPriorityListsEqual(
                priority,
                view
            )
            then
                return
            end

            StaticPopup_Show(
                "WGR_CONFIRM_SET_PRIORITY_FROM_VIEW",
                nil,
                nil,
                {
                    frame =
                        frame,
                    view =
                        WGRCopyList(
                            view
                        ),
                    updateViewDropdown =
                        WGRUpdateRosterViewDropdown,
                    updateDirectionDropdown =
                        WGRUpdateDirectionDropdown,
                }
            )
        end
    )

    setPriorityFromViewButton:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(
                self,
                "ANCHOR_RIGHT"
            )

            GameTooltip:AddLine(
                "Set Priority From Current View",
                1.00,
                0.82,
                0.00
            )

            GameTooltip:AddLine(
                "Replaces routing priority with the order currently displayed in the roster. Your current priority is backed up first.",
                0.85,
                0.85,
                0.85,
                true
            )

            GameTooltip:Show()
        end
    )

    setPriorityFromViewButton:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    restorePriorityButton:SetScript(
        "OnClick",
        function()
            if not WGRHasPriorityBackup() then
                return
            end

            StaticPopup_Show(
                "WGR_CONFIRM_RESTORE_PRIORITY",
                nil,
                nil,
                {
                    frame =
                        frame,
                }
            )
        end
    )

    restorePriorityButton:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(
                self,
                "ANCHOR_RIGHT"
            )

            GameTooltip:AddLine(
                "Restore Previous Priority",
                1.00,
                0.82,
                0.00
            )

            if WGRHasPriorityBackup() then
                GameTooltip:AddLine(
                    WGRPriorityBackupDescription(),
                    0.85,
                    0.85,
                    0.85
                )

                GameTooltip:AddLine(
                    "Restoring swaps the current and previous orders, so you can restore again if needed.",
                    0.70,
                    0.70,
                    0.70,
                    true
                )
            else
                GameTooltip:AddLine(
                    "No priority backup is available yet.",
                    0.70,
                    0.70,
                    0.70
                )
            end

            GameTooltip:Show()
        end
    )

    restorePriorityButton:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    WGRUpdatePriorityTools()

    local rosterColumns =
        CreateFrame(
            "Frame",
            nil,
            rosterPage
        )

    rosterColumns:SetSize(
        880,
        18
    )

    rosterColumns:SetPoint(
        "TOPLEFT",
        rosterPage,
        "TOPLEFT",
        0,
        -94
    )

    local function AddRosterHeader(
        text,
        x,
        width,
        justify
    )
        local label =
            rosterColumns:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormalSmall"
            )

        label:SetPoint(
            "LEFT",
            rosterColumns,
            "LEFT",
            x,
            0
        )

        label:SetWidth(
            width
        )

        label:SetJustifyH(
            justify or "LEFT"
        )

        label:SetText(
            text
        )

        return label
    end

    AddRosterHeader("#", 26, 24, "RIGHT")
    AddRosterHeader("Character", 54, 86, "LEFT")
    AddRosterHeader("Cls", 182, 36, "CENTER")
    AddRosterHeader("Spec", 222, 46, "CENTER")
    AddRosterHeader("Lvl", 272, 32, "CENTER")
    AddRosterHeader("iLvl", 308, 38, "CENTER")
    AddRosterHeader("Playtime", 350, 54, "CENTER")
    AddRosterHeader("Spec Mode", 408, 96, "CENTER")
    AddRosterHeader("Weapons", 510, 112, "CENTER")
    AddRosterHeader("Threshold", 628, 80, "CENTER")
    AddRosterHeader("Priority", 716, 74, "CENTER")
    AddRosterHeader("Status", 803, 76, "CENTER")

    local rosterScroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            rosterPage,
            "UIPanelScrollFrameTemplate"
        )

    rosterScroll:SetPoint(
        "TOPLEFT",
        rosterColumns,
        "BOTTOMLEFT",
        0,
        -10
    )

    rosterScroll:SetPoint(
        "BOTTOMRIGHT",
        rosterPage,
        "BOTTOMRIGHT",
        -26,
        34
    )

    local rosterContent =
        CreateFrame(
            "Frame",
            nil,
            rosterScroll
        )

    rosterContent:SetSize(
        880,
        math.max(
            1,
            #GetRoutingPriority() * 26
        )
    )

    rosterScroll:SetScrollChild(
        rosterContent
    )

    frame.rosterContent =
        rosterContent

    frame.customSpecsPanel =
        CreateFrame(
            "Frame",
            nil,
            frame,
            "BackdropTemplate"
        )

    frame.customSpecsPanel:SetSize(
        250,
        170
    )

    frame.customSpecsPanel:SetBackdrop(
        {
            bgFile =
                "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile =
                "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 10,
            insets = {
                left = 4,
                right = 4,
                top = 4,
                bottom = 4,
            },
        }
    )

    frame.customSpecsPanel:SetBackdropColor(
        0.02,
        0.02,
        0.02,
        1.00
    )

    frame.customSpecsPanel.solidBackground =
        frame.customSpecsPanel:CreateTexture(
            nil,
            "BACKGROUND",
            nil,
            -8
        )

    frame.customSpecsPanel.solidBackground:SetPoint(
        "TOPLEFT",
        frame.customSpecsPanel,
        "TOPLEFT",
        5,
        -5
    )

    frame.customSpecsPanel.solidBackground:SetPoint(
        "BOTTOMRIGHT",
        frame.customSpecsPanel,
        "BOTTOMRIGHT",
        -5,
        5
    )

    frame.customSpecsPanel.solidBackground:SetColorTexture(
        0.015,
        0.015,
        0.015,
        1.00
    )

    frame.customSpecsPanel:SetFrameStrata(
        "FULLSCREEN_DIALOG"
    )
    frame.customSpecsPanel:SetFrameLevel(
        frame:GetFrameLevel() + 50
    )

    frame.customSpecsPanel:Hide()

    frame.customSpecsPanel.title =
        frame.customSpecsPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    frame.customSpecsPanel.title:SetPoint(
        "TOPLEFT",
        frame.customSpecsPanel,
        "TOPLEFT",
        12,
        -12
    )

    frame.customSpecsPanel.summary =
        frame.customSpecsPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    frame.customSpecsPanel.summary:SetPoint(
        "TOPLEFT",
        frame.customSpecsPanel,
        "TOPLEFT",
        12,
        -126
    )

    frame.customSpecsPanel.summary:SetWidth(
        205
    )

    frame.customSpecsPanel.summary:SetJustifyH(
        "LEFT"
    )

    frame.customSpecsPanel.summary:SetTextColor(
        0.72,
        0.72,
        0.72
    )

    frame.customSpecsPanel.done =
        CreateFrame(
            "Button",
            nil,
            frame.customSpecsPanel,
            "UIPanelButtonTemplate"
        )

    frame.customSpecsPanel.done:SetSize(
        70,
        22
    )

    frame.customSpecsPanel.done:SetPoint(
        "BOTTOMRIGHT",
        frame.customSpecsPanel,
        "BOTTOMRIGHT",
        -10,
        10
    )

    frame.customSpecsPanel.done:SetText(
        "Done"
    )

    frame.customSpecsPanel.done:SetScript(
        "OnClick",
        function()
            frame.customSpecsPanel:Hide()
        end
    )

    frame.customSpecsPanel.checks =
        {}

    frame.UpdateCustomSpecsPanel =
        function()
            local characterName =
                frame.customSpecsPanel.characterName

            if not characterName then
                return
            end

            local character =
                FindCharacterByName(
                    characterName
                )

            frame.customSpecsPanel.summary:SetText(
                "Using: "
                .. WGRCustomSpecsSummary(
                    characterName,
                    character
                )
            )

            for _, data
                in ipairs(
                    frame.customSpecsPanel.checks
                )
            do
                if data.check:IsShown()
                    and data.check.WGRSpecID
                then
                    local selected =
                        WGRGetCustomSpecs(
                            characterName
                        )

                    data.check:SetChecked(
                        selected
                        and selected[
                            tostring(
                                data.check.WGRSpecID
                            )
                        ]
                        == true
                        or false
                    )
                end
            end
        end

    frame.ShowCustomSpecsPanel =
        function(
            characterName,
            anchorButton
        )
            if not characterName
                or not anchorButton
            then
                return
            end

            frame.customSpecsPanel.characterName =
                characterName

            frame.customSpecsPanel:ClearAllPoints()

            local panelWidth =
                frame.customSpecsPanel:GetWidth()

            local anchorRight =
                anchorButton:GetRight()

            local screenWidth =
                UIParent:GetWidth()

            local rightEdge =
                anchorRight
                and (
                    anchorRight
                    + panelWidth
                    + 12
                )
                or 0

            if rightEdge
                > (
                    screenWidth
                    - 20
                )
            then
                frame.customSpecsPanel:SetPoint(
                    "TOPRIGHT",
                    anchorButton,
                    "TOPLEFT",
                    -8,
                    8
                )
            else
                frame.customSpecsPanel:SetPoint(
                    "TOPLEFT",
                    anchorButton,
                    "TOPRIGHT",
                    8,
                    8
                )
            end

            frame.customSpecsPanel.title:SetText(
                characterName
                .. " - Custom Specs"
            )

            for _, data
                in ipairs(
                    frame.customSpecsPanel.checks
                )
            do
                data.check:Hide()
                data.label:Hide()
            end

            local character =
                FindCharacterByName(
                    characterName
                )

            local classID =
                GetCharacterClassID(
                    characterName,
                    character
                )

            local specIDs =
                classID
                and WGRClassSpecIDs[
                    classID
                ]
                or {}

            for index, specID
                in ipairs(
                    specIDs
                )
            do
                local data =
                    frame.customSpecsPanel.checks[
                        index
                    ]

                if not data then
                    data = {}

                    data.check =
                        CreateFrame(
                            "CheckButton",
                            nil,
                            frame.customSpecsPanel,
                            "UICheckButtonTemplate"
                        )

                    data.label =
                        frame.customSpecsPanel:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlight"
                        )

                    data.label:SetPoint(
                        "LEFT",
                        data.check,
                        "RIGHT",
                        2,
                        0
                    )

                    data.check:SetScript(
                        "OnClick",
                        function(self)
                            WGRSetCustomSpecEnabled(
                                frame.customSpecsPanel.characterName,
                                self.WGRSpecID,
                                self:GetChecked()
                                    and true
                                    or false
                            )

                            frame.UpdateCustomSpecsPanel()
                            RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
                        end
                    )

                    frame.customSpecsPanel.checks[
                        index
                    ] =
                        data
                end

                data.check.WGRSpecID =
                    specID

                data.check:ClearAllPoints()

                data.check:SetPoint(
                    "TOPLEFT",
                    frame.customSpecsPanel,
                    "TOPLEFT",
                    10,
                    -34 - ((index - 1) * 28)
                )

                data.label:SetText(
                    WGRSpecNamesByID[
                        specID
                    ]
                    or tostring(
                        specID
                    )
                )

                data.check:Show()
                data.label:Show()
            end

            local summaryY =
                -42
                - (#specIDs * 28)

            frame.customSpecsPanel.summary:ClearAllPoints()
            frame.customSpecsPanel.summary:SetPoint(
                "TOPLEFT",
                frame.customSpecsPanel,
                "TOPLEFT",
                12,
                summaryY
            )

            frame.customSpecsPanel:SetHeight(
                102
                + (#specIDs * 28)
            )

            frame.UpdateCustomSpecsPanel()
            frame.customSpecsPanel:Show()
        end

    if not StaticPopupDialogs["WGR_CONFIRM_RESET_SPEC_WEAPON_BASELINE"] then
        StaticPopupDialogs["WGR_CONFIRM_RESET_SPEC_WEAPON_BASELINE"] = {
            text =
                "Reset %s weapon baseline?\n\nWBGR will erase its saved weapon data for this spec and rebuild it from your currently equipped weapons. If required components are missing, WBGR will try to inherit compatible weapon data from another recorded spec. Anything that cannot be recorded or inherited will be set to 0.",
            button1 = "Reset",
            button2 = "Cancel",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(self, data)
                if not data then return end
                local ok, reason = WGRResetCurrentSpecWeaponBaseline(
                    data.characterName,
                    data.specID
                )

                if not ok then
                    if reason == "item_data_pending" then
                        print("|cffff5555WBGR:|r Weapon item data is still loading. Please try Reset again in a moment.")
                    elseif reason == "not_current_spec" then
                        print("|cffff5555WBGR:|r Switch to that specialization before resetting its weapon baseline.")
                    else
                        print("|cffff5555WBGR:|r Log into that character before resetting its weapon baseline.")
                    end
                    return
                end

                RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()

                if data.frame and data.frame.UpdateRoster then
                    data.frame.UpdateRoster()
                end

                if data.frame
                    and data.frame.ShowCustomWeaponsPanel
                    and data.frame.customWeaponsPanel
                    and data.frame.customWeaponsPanel.anchorButton
                then
                    data.frame.ShowCustomWeaponsPanel(
                        data.characterName,
                        data.frame.customWeaponsPanel.anchorButton
                    )
                end
            end,
        }
    end

    -- Custom weapon preferences panel
    frame.customWeaponsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.customWeaponsPanel:SetSize(640, 220)
    frame.customWeaponsPanel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=10,insets={left=4,right=4,top=4,bottom=4}})
    frame.customWeaponsPanel:SetBackdropColor(0.02,0.02,0.02,1)
    frame.customWeaponsPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    frame.customWeaponsPanel:SetFrameLevel(frame:GetFrameLevel()+50)
    frame.customWeaponsPanel:SetPropagateKeyboardInput(true)
    frame.customWeaponsPanel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame.customWeaponsPanel:Hide()
    frame.customWeaponsPanel.title=frame.customWeaponsPanel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    frame.customWeaponsPanel.title:SetPoint("TOPLEFT",12,-12)
    frame.customWeaponsPanel.rows={}
    frame.customWeaponsPanel.done=CreateFrame("Button",nil,frame.customWeaponsPanel,"UIPanelButtonTemplate")
    frame.customWeaponsPanel.done:SetSize(70,22)
    frame.customWeaponsPanel.done:SetPoint("BOTTOMRIGHT",-10,10)
    frame.customWeaponsPanel.done:SetText("Done")
    frame.customWeaponsPanel.done:SetScript("OnClick",function() frame.customWeaponsPanel:Hide() end)

    frame.ShowCustomWeaponsPanel=function(characterName,anchorButton)
        local character=FindCharacterByName(characterName)
        local specIDs=WGRGetRoutingSpecIDs(characterName,character)
        frame.customWeaponsPanel.characterName=characterName
        frame.customWeaponsPanel.anchorButton=anchorButton
        frame.customWeaponsPanel:ClearAllPoints()
        frame.customWeaponsPanel:SetPoint("TOPRIGHT",anchorButton,"TOPLEFT",-8,8)
        frame.customWeaponsPanel.title:SetText(characterName.." - Custom Weapons")
        for _,r in ipairs(frame.customWeaponsPanel.rows) do r.frame:Hide() end
        for i,specID in ipairs(specIDs) do
            local r=frame.customWeaponsPanel.rows[i]
            if not r then
                r={}; r.frame=CreateFrame("Frame",nil,frame.customWeaponsPanel); r.frame:SetSize(610,72)
                r.name=r.frame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); r.name:SetPoint("TOPLEFT",0,0); r.name:SetWidth(105); r.name:SetJustifyH("LEFT")
                r.drop=CreateWGRDropdown(r.frame,150,22); r.drop:SetPoint("TOPLEFT",108,4)
                r.eligible=r.frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); r.eligible:SetPoint("TOPLEFT",108,-20); r.eligible:SetWidth(170); r.eligible:SetJustifyH("LEFT"); r.eligible:SetTextColor(.7,.7,.7)
                r.override=r.frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); r.override:SetPoint("TOPLEFT",108,-38); r.override:SetWidth(170); r.override:SetJustifyH("LEFT"); r.override:SetTextColor(.95,.78,.15)
                r.baselineTitle=r.frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); r.baselineTitle:SetPoint("TOPLEFT",300,0); r.baselineTitle:SetWidth(200); r.baselineTitle:SetJustifyH("LEFT"); r.baselineTitle:SetText("Current Baseline:")
                r.baselineValue=r.frame:CreateFontString(nil,"OVERLAY","GameFontHighlight"); r.baselineValue:SetPoint("TOPLEFT",300,-18); r.baselineValue:SetWidth(220); r.baselineValue:SetJustifyH("LEFT")
                r.reset=CreateFrame("Button",nil,r.frame,"UIPanelButtonTemplate"); r.reset:SetSize(66,20); r.reset:SetPoint("TOPLEFT",300,-38); r.reset:SetText("Reset")
                frame.customWeaponsPanel.rows[i]=r
            end
            r.frame:ClearAllPoints(); r.frame:SetPoint("TOPLEFT",frame.customWeaponsPanel,"TOPLEFT",12,-38-((i-1)*76)); r.frame:Show()
            r.name:SetText(WGRSpecNamesByID[specID] or tostring(specID))
            local pref=WGRGetCustomWeaponPreference(characterName,specID)
            r.drop:SetValueText(pref=="ALL" and "All Eligible" or (WGRWeaponConfigLabels[pref] or pref))
            r.eligible:SetText("Eligible: "..WGRConfigListText(specID))

            local effectiveLevel, effectiveBaseline =
                WGRGetEffectiveSpecWeaponBaseline(
                    characterName,
                    character,
                    specID
                )

            local storedBaseline =
                WarboundGearRouterDB.specWeaponBaselines
                and WarboundGearRouterDB.specWeaponBaselines[string.lower(characterName or "")]
                and WarboundGearRouterDB.specWeaponBaselines[string.lower(characterName or "")][tostring(specID)]
                or nil

            local displayConfig =
                effectiveBaseline and effectiveBaseline.weaponConfig
                or storedBaseline and storedBaseline.weaponConfig
                or nil

            local configText =
                displayConfig
                and (WGRWeaponConfigLabels[displayConfig] or tostring(displayConfig))
                or "Not initialized"

            local inherited =
                (effectiveBaseline and effectiveBaseline.inherited == true)
                or (storedBaseline and storedBaseline.resetInherited == true)

            local incomplete =
                not effectiveLevel
                or effectiveLevel <= 0
                or (storedBaseline and storedBaseline.weaponConfigState == "PARTIAL")

            local warning = inherited or incomplete
            local levelText = tostring(math.floor((tonumber(effectiveLevel) or 0) + 0.5))
            r.baselineValue:SetText(
                levelText
                .. (warning and " |TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14:0:0|t" or "")
                .. " ("
                .. configText
                .. ")"
            )

            r.baselineValue:EnableMouse(true)
            r.baselineValue:SetScript("OnEnter", function(self)
                if not warning then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if incomplete then
                    GameTooltip:SetText("Incomplete or uninitialized baseline", 1, .82, 0)
                    if storedBaseline and storedBaseline.weaponConfigState == "PARTIAL" then
                        GameTooltip:AddLine("WBGR has only part of this weapon setup recorded. Missing components are treated as 0 until the setup can be completed or inherited.", 1, 1, 1, true)
                    else
                        GameTooltip:AddLine("WBGR does not have a complete weapon baseline recorded for this spec.", 1, 1, 1, true)
                    end
                else
                    GameTooltip:SetText("Inherited baseline", 1, .82, 0)
                end
                if inherited then
                    local source =
                        (effectiveBaseline and effectiveBaseline.inheritedFromSpecName)
                        or (storedBaseline and storedBaseline.inheritedFromSpecName)
                        or "another spec"
                    GameTooltip:AddLine("This baseline uses compatible weapon data inherited from "..tostring(source)..".", 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            r.baselineValue:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local playerName = UnitName("player")
            local currentSpec = GetCurrentSpecInfo()
            local canReset =
                playerName
                and string.lower(playerName) == string.lower(characterName or "")
                and currentSpec
                and tonumber(currentSpec.id) == tonumber(specID)

            r.reset:SetEnabled(canReset and true or false)
            r.reset:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if canReset then
                    GameTooltip:SetText("Reset weapon baseline", 1, .82, 0)
                    GameTooltip:AddLine("Erase this spec's saved weapon baseline and rebuild it from the gear currently equipped for this spec. Missing components may be inherited; anything still missing becomes 0.", 1, 1, 1, true)
                else
                    GameTooltip:SetText("Reset unavailable", 1, .82, 0)
                    GameTooltip:AddLine("Log into this character and switch to this specialization before resetting its weapon baseline.", 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            r.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local rowSpecID = specID
            r.reset:SetScript("OnClick", function()
                StaticPopup_Show(
                    "WGR_CONFIRM_RESET_SPEC_WEAPON_BASELINE",
                    WGRSpecNamesByID[rowSpecID] or tostring(rowSpecID),
                    nil,
                    {
                        frame = frame,
                        characterName = characterName,
                        specID = rowSpecID,
                    }
                )
            end)

            local overrideText=""
            local classID=GetCharacterClassID(characterName,character)

            if WGRCustomSelectionOverridesGlobal(characterName,specID) then
                if specID==72 then
                    if pref=="DUAL_1H" then
                        overrideText="Allows Dual 1H despite the global Dual 2H preference."
                    else
                        overrideText="Allows Dual 1H and Dual 2H despite the global Dual 2H preference."
                    end
                elseif specID==577 or specID==581 or specID==1480 then
                    overrideText=(specID == 1480 and "Allows generic 1H Intellect weapons despite the global Warglaive preference." or "Allows generic 1H Agility weapons despite the global Warglaive preference.")
                end
            end

            r.override:SetText(overrideText)
            r.drop:SetScript("OnClick",function(self)
                MenuUtil.CreateContextMenu(self,function(owner,root)
                    root:CreateTitle((WGRSpecNamesByID[specID] or tostring(specID)).." Weapons")
                    local choices={{"ALL","All Eligible"}}
                    for _,cfg in ipairs(WGRSpecEligibleWeaponConfigs[specID] or {}) do choices[#choices+1]={cfg,WGRWeaponConfigLabels[cfg] or cfg} end
                    for _,choice in ipairs(choices) do local value,label=choice[1],choice[2]
                        root:CreateRadio(label,function() return WGRGetCustomWeaponPreference(characterName,specID)==value end,function()
                            WGRSetCustomWeaponPreference(characterName,specID,value)
                            self:SetValueText(value=="ALL" and "All Eligible" or (WGRWeaponConfigLabels[value] or value))
                            frame.UpdateRoster(); RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
                            if frame.UpdateGlobalWeaponOverrideHelp then frame.UpdateGlobalWeaponOverrideHelp() end

                            local updatedPref=WGRGetCustomWeaponPreference(characterName,specID)
                            r.eligible:SetText("Eligible: "..WGRConfigListText(specID))

                            local updatedOverride=""
                            local updatedClassID=GetCharacterClassID(characterName,character)

                            if WGRCustomSelectionOverridesGlobal(characterName,specID) then
                                if specID==72 then
                                    if updatedPref=="DUAL_1H" then
                                        updatedOverride="Allows Dual 1H despite the global Dual 2H preference."
                                    else
                                        updatedOverride="Allows Dual 1H and Dual 2H despite the global Dual 2H preference."
                                    end
                                elseif specID==577 or specID==581 or specID==1480 then
                                    updatedOverride=(specID == 1480 and "Allows generic 1H Intellect weapons despite the global Warglaive preference." or "Allows generic 1H Agility weapons despite the global Warglaive preference.")
                                end
                            end

                            r.override:SetText(updatedOverride)
                        end)
                    end
                end)
            end)
        end
        frame.customWeaponsPanel:SetHeight(76+(#specIDs*76))
        frame.customWeaponsPanel:SetPropagateKeyboardInput(true)
        frame.customWeaponsPanel:Show()
    end

    -- Custom threshold editor
    -- Small WGR-owned panel anchored beside the dropdown that launched it.
    frame.customThresholdPanel =
        CreateFrame(
            "Frame",
            nil,
            frame,
            "BackdropTemplate"
        )

    frame.customThresholdPanel:SetSize(
        285,
        118
    )

    frame.customThresholdPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = {
            left = 4,
            right = 4,
            top = 4,
            bottom = 4,
        },
    })

    frame.customThresholdPanel:SetBackdropColor(
        0.02,
        0.02,
        0.02,
        1.00
    )

    frame.customThresholdPanel:SetFrameStrata(
        "FULLSCREEN_DIALOG"
    )

    frame.customThresholdPanel:SetFrameLevel(
        frame:GetFrameLevel() + 50
    )

    frame.customThresholdPanel:SetPropagateKeyboardInput(
        true
    )

    frame.customThresholdPanel:Hide()

    frame.customThresholdPanel.title =
        frame.customThresholdPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    frame.customThresholdPanel.title:SetPoint(
        "TOPLEFT",
        frame.customThresholdPanel,
        "TOPLEFT",
        12,
        -12
    )

    frame.customThresholdPanel.label =
        frame.customThresholdPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    frame.customThresholdPanel.label:SetPoint(
        "TOPLEFT",
        frame.customThresholdPanel,
        "TOPLEFT",
        12,
        -43
    )

    frame.customThresholdPanel.label:SetText(
        "iLvl threshold:"
    )

    frame.customThresholdPanel.editBox =
        CreateFrame(
            "EditBox",
            nil,
            frame.customThresholdPanel,
            "InputBoxTemplate"
        )

    frame.customThresholdPanel.editBox:SetSize(
        70,
        22
    )

    frame.customThresholdPanel.editBox:SetPoint(
        "LEFT",
        frame.customThresholdPanel.label,
        "RIGHT",
        10,
        0
    )

    frame.customThresholdPanel.editBox:SetAutoFocus(
        false
    )

    frame.customThresholdPanel.editBox:SetNumeric(
        true
    )

    frame.customThresholdPanel.editBox:SetMaxLetters(
        3
    )

    frame.customThresholdPanel.setButton =
        CreateFrame(
            "Button",
            nil,
            frame.customThresholdPanel,
            "UIPanelButtonTemplate"
        )

    frame.customThresholdPanel.setButton:SetSize(
        90,
        22
    )

    frame.customThresholdPanel.setButton:SetPoint(
        "BOTTOMRIGHT",
        frame.customThresholdPanel,
        "BOTTOMRIGHT",
        -82,
        10
    )

    frame.customThresholdPanel.setButton:SetText(
        "Set"
    )

    frame.customThresholdPanel.cancelButton =
        CreateFrame(
            "Button",
            nil,
            frame.customThresholdPanel,
            "UIPanelButtonTemplate"
        )

    frame.customThresholdPanel.cancelButton:SetSize(
        70,
        22
    )

    frame.customThresholdPanel.cancelButton:SetPoint(
        "LEFT",
        frame.customThresholdPanel.setButton,
        "RIGHT",
        6,
        0
    )

    frame.customThresholdPanel.cancelButton:SetText(
        "Cancel"
    )

    frame.WGRHideCustomThresholdPanel = function()
        frame.customThresholdPanel:Hide()
        frame.customThresholdPanel.editBox:ClearFocus()
    end

    frame.WGRAcceptCustomThreshold = function()
        local panel =
            frame.customThresholdPanel

        local value =
            tonumber(
                panel.editBox:GetText()
            )

        if value == nil then
            print(
                "|cffff5555WBGR:|r Threshold must be a number."
            )
            return
        end

        value =
            math.max(
                0,
                math.floor(
                    value + 0.5
                )
            )

        if panel.characterName then
            WGRSetCharacterThreshold(
                panel.characterName,
                value
            )

            if frame.UpdateRoster then
                frame.UpdateRoster()
            end
        else
            WGRSetGlobalUpgradeThreshold(
                value
            )

            if panel.updateDropdown then
                panel.updateDropdown()
            end

            if frame.UpdateRoster then
                frame.UpdateRoster()
            end
        end

        RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
        frame.WGRHideCustomThresholdPanel()
    end

    frame.customThresholdPanel.setButton:SetScript(
        "OnClick",
        frame.WGRAcceptCustomThreshold
    )

    frame.customThresholdPanel.cancelButton:SetScript(
        "OnClick",
        frame.WGRHideCustomThresholdPanel
    )

    frame.customThresholdPanel.editBox:SetScript(
        "OnEnterPressed",
        frame.WGRAcceptCustomThreshold
    )

    frame.customThresholdPanel.editBox:SetScript(
        "OnEscapePressed",
        frame.WGRHideCustomThresholdPanel
    )

    frame.customThresholdPanel:SetScript(
        "OnKeyDown",
        function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                frame.WGRHideCustomThresholdPanel()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end
    )

    frame.ShowCustomThresholdPanel =
        function(
            characterName,
            anchorButton,
            updateDropdown
        )
            if not anchorButton then
                return
            end

            local panel =
                frame.customThresholdPanel

            panel.characterName =
                characterName

            panel.updateDropdown =
                updateDropdown

            if characterName then
                panel.title:SetText(
                    characterName
                    .. " - Custom Threshold"
                )

                panel.editBox:SetText(
                    tostring(
                        WGRGetCharacterThresholdOverride(
                            characterName
                        )
                        or WGRGetGlobalUpgradeThreshold()
                    )
                )
            else
                panel.title:SetText(
                    "Default - Custom Threshold"
                )

                panel.editBox:SetText(
                    tostring(
                        WGRGetGlobalUpgradeThreshold()
                    )
                )
            end

            panel:ClearAllPoints()

            local panelWidth =
                panel:GetWidth()

            local anchorRight =
                anchorButton:GetRight()

            local screenWidth =
                UIParent:GetWidth()

            if anchorRight
                and screenWidth
                and (
                    anchorRight
                    + panelWidth
                    + 12
                ) <= screenWidth
            then
                panel:SetPoint(
                    "TOPLEFT",
                    anchorButton,
                    "TOPRIGHT",
                    8,
                    6
                )
            else
                panel:SetPoint(
                    "TOPRIGHT",
                    anchorButton,
                    "TOPLEFT",
                    -8,
                    6
                )
            end

            panel:SetPropagateKeyboardInput(
                true
            )

            panel:Show()
            panel.editBox:SetFocus()
            panel.editBox:HighlightText()
        end

    frame.rosterRows = {}

    local insertionPreview =
        rosterContent:CreateTexture(
            nil,
            "OVERLAY"
        )

    insertionPreview:SetColorTexture(
        1.00,
        0.82,
        0.00,
        1.00
    )

    insertionPreview:SetHeight(
        3
    )

    insertionPreview:Hide()

    frame.insertionPreview =
        insertionPreview

    local function WGRUpdateInsertionPreview()
        if not frame.WGRDraggedCharacter then
            insertionPreview:Hide()
            return
        end

        local priority =
            GetRoutingPriority()

        local slot =
            WGRGetRosterInsertSlot(
                rosterContent,
                #priority
            )

        if not slot then
            insertionPreview:Hide()
            return
        end

        frame.WGRCurrentInsertSlot =
            slot

        local yOffset =
            -((slot - 1) * 34)

        insertionPreview:ClearAllPoints()

        insertionPreview:SetPoint(
            "TOPLEFT",
            rosterContent,
            "TOPLEFT",
            24,
            yOffset
        )

        insertionPreview:SetPoint(
            "TOPRIGHT",
            rosterContent,
            "TOPRIGHT",
            -4,
            yOffset
        )

        insertionPreview:Show()
    end

    local function WGRAutoScrollRosterWhileDragging(
        elapsed
    )
        if not frame.WGRDraggedCharacter
            or not rosterScroll
        then
            return
        end

        local scale =
            rosterScroll:GetEffectiveScale()
            or 1

        local _, cursorY =
            GetCursorPosition()

        cursorY =
            cursorY / scale

        local top =
            rosterScroll:GetTop()

        local bottom =
            rosterScroll:GetBottom()

        if not top
            or not bottom
        then
            return
        end

        local edgeZone = 42
        local direction = 0
        local strength = 0

        if cursorY > top - edgeZone
            and cursorY <= top + 8
        then
            direction = -1
            strength =
                math.min(
                    1,
                    math.max(
                        0,
                        (
                            cursorY
                            - (top - edgeZone)
                        ) / edgeZone
                    )
                )
        elseif cursorY < bottom + edgeZone
            and cursorY >= bottom - 8
        then
            direction = 1
            strength =
                math.min(
                    1,
                    math.max(
                        0,
                        (
                            (bottom + edgeZone)
                            - cursorY
                        ) / edgeZone
                    )
                )
        end

        if direction == 0
            or strength <= 0
        then
            return
        end

        local current =
            rosterScroll:GetVerticalScroll()
            or 0

        local maximum =
            rosterScroll:GetVerticalScrollRange()
            or 0

        if maximum <= 0 then
            return
        end

        -- Slow near the inner edge, faster as the cursor pushes farther
        -- toward the top/bottom boundary.
        local pixelsPerSecond =
            85
            + (235 * strength)

        local nextScroll =
            current
            + (
                direction
                * pixelsPerSecond
                * (elapsed or 0)
            )

        nextScroll =
            math.max(
                0,
                math.min(
                    maximum,
                    nextScroll
                )
            )

        if math.abs(nextScroll - current)
            >= 0.25
        then
            rosterScroll:SetVerticalScroll(
                nextScroll
            )
        end
    end

    local dragPreviewFrame =
        CreateFrame(
            "Frame",
            nil,
            rosterPage
        )

    dragPreviewFrame:SetScript(
        "OnUpdate",
        function(self, elapsed)
            WGRAutoScrollRosterWhileDragging(
                elapsed
            )

            WGRUpdateInsertionPreview()
        end
    )

    frame.dragPreviewFrame =
        dragPreviewFrame

    local restoreRemovedButton =
        CreateFrame(
            "Button",
            nil,
            rosterPage,
            "UIPanelButtonTemplate"
        )

    restoreRemovedButton:SetSize(
        190,
        24
    )

    restoreRemovedButton:SetPoint(
        "BOTTOMLEFT",
        rosterPage,
        "BOTTOMLEFT",
        0,
        0
    )

    restoreRemovedButton:SetText(
        "Restore Removed Characters"
    )

    restoreRemovedButton:Hide()

    frame.restoreRemovedButton =
        restoreRemovedButton

    local removedPanel =
        CreateFrame(
            "Frame",
            nil,
            rosterPage,
            "BackdropTemplate"
        )

    removedPanel:SetPoint(
        "TOPLEFT",
        rosterPage,
        "TOPLEFT",
        18,
        -18
    )

    removedPanel:SetPoint(
        "BOTTOMRIGHT",
        rosterPage,
        "BOTTOMRIGHT",
        -18,
        18
    )

    removedPanel:SetBackdrop({
        bgFile =
            "Interface\\Buttons\\WHITE8X8",
        edgeFile =
            "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {
            left = 4,
            right = 4,
            top = 4,
            bottom = 4,
        },
    })

    removedPanel:SetBackdropColor(
        0.04,
        0.04,
        0.04,
        0.98
    )

    removedPanel:SetFrameLevel(
        rosterPage:GetFrameLevel() + 20
    )

    removedPanel:Hide()

    frame.removedPanel =
        removedPanel

    local removedTitle =
        removedPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    removedTitle:SetPoint(
        "TOPLEFT",
        removedPanel,
        "TOPLEFT",
        14,
        -14
    )

    removedTitle:SetText(
        "Removed Characters"
    )

    local removedHelp =
        removedPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    removedHelp:SetPoint(
        "TOPLEFT",
        removedTitle,
        "BOTTOMLEFT",
        0,
        -6
    )

    removedHelp:SetTextColor(
        0.70,
        0.70,
        0.70
    )

    removedHelp:SetText(
        "Removed characters stay excluded from routing and automatic discovery until restored."
    )

    local removedClose =
        CreateFrame(
            "Button",
            nil,
            removedPanel,
            "UIPanelButtonTemplate"
        )

    removedClose:SetSize(
        76,
        23
    )

    removedClose:SetPoint(
        "TOPRIGHT",
        removedPanel,
        "TOPRIGHT",
        -12,
        -12
    )

    removedClose:SetText(
        "Close"
    )

    removedClose:SetScript(
        "OnClick",
        function()
            removedPanel:Hide()
        end
    )

    local removedScroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            removedPanel,
            "UIPanelScrollFrameTemplate"
        )

    removedScroll:SetPoint(
        "TOPLEFT",
        removedHelp,
        "BOTTOMLEFT",
        0,
        -14
    )

    removedScroll:SetPoint(
        "BOTTOMRIGHT",
        removedPanel,
        "BOTTOMRIGHT",
        -30,
        14
    )

    local removedContent =
        CreateFrame(
            "Frame",
            nil,
            removedScroll
        )

    removedContent:SetSize(
        560,
        1
    )

    removedScroll:SetScrollChild(
        removedContent
    )

    frame.removedRows = {}

    frame.UpdateRemovedCharacters =
        function()
            local removed =
                WGRGetRemovedCharacters()

            restoreRemovedButton:SetShown(
                #removed > 0
            )

            for _, row
                in ipairs(
                    frame.removedRows
                )
            do
                row:Hide()
            end

            removedContent:SetHeight(
                math.max(
                    1,
                    #removed * 34
                )
            )

            for index, record
                in ipairs(
                    removed
                )
            do
                local row =
                    frame.removedRows[
                        index
                    ]

                if not row then
                    row =
                        CreateFrame(
                            "Frame",
                            nil,
                            removedContent
                        )

                    row:SetSize(
                        560,
                        30
                    )

                    local nameText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlight"
                        )

                    nameText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        2,
                        0
                    )

                    nameText:SetWidth(
                        300
                    )

                    nameText:SetJustifyH(
                        "LEFT"
                    )

                    row.nameText =
                        nameText

                    local restore =
                        CreateFrame(
                            "Button",
                            nil,
                            row,
                            "UIPanelButtonTemplate"
                        )

                    restore:SetSize(
                        90,
                        23
                    )

                    restore:SetPoint(
                        "RIGHT",
                        row,
                        "RIGHT",
                        -4,
                        0
                    )

                    restore:SetText(
                        "Restore"
                    )

                    row.restore =
                        restore

                    frame.removedRows[
                        index
                    ] =
                        row
                end

                row:ClearAllPoints()

                row:SetPoint(
                    "TOPLEFT",
                    removedContent,
                    "TOPLEFT",
                    0,
                    -((index - 1) * 34)
                )

                row.nameText:SetText(
                    record.name
                )

                local restoreName =
                    record.name

                row.restore:SetScript(
                    "OnClick",
                    function()
                        if WGRRestoreRemovedCharacter(
                            restoreName
                        )
                        then
                            frame.UpdateRemovedCharacters()
                            frame.UpdateRoster()
                            WGRMailUpdateTrackerFrame()

                            print(
                                "|cff00ff00WBGR:|r "
                                .. restoreName
                                .. " restored to the WBGR roster."
                            )
                        end
                    end
                )

                row:Show()
            end

            if #removed == 0 then
                removedPanel:Hide()
            end
        end

    restoreRemovedButton:SetScript(
        "OnClick",
        function()
            frame.UpdateRemovedCharacters()
            removedPanel:Show()
        end
    )

    if not WGRHasPriorityBackup()
        and WarboundGearRouterDB.priorityBackup == false
    then
        WGRSavePriorityBackup(
            "Safety snapshot before priority-management changes"
        )
    end

    if frame.UpdatePriorityTools then
        frame.UpdatePriorityTools()
    end

    frame.warbandRosterRow =
        CreateFrame(
            "Frame",
            nil,
            rosterContent
        )

    frame.warbandRosterRow:SetSize(880, 32)

    frame.warbandRosterRow.bg =
        frame.warbandRosterRow:CreateTexture(
            nil,
            "BACKGROUND"
        )
    frame.warbandRosterRow.bg:SetAllPoints()
    frame.warbandRosterRow.bg:SetColorTexture(
        0.08, 0.14, 0.20, 0.55
    )

    frame.warbandRosterRow.nameText =
        frame.warbandRosterRow:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )
    frame.warbandRosterRow.nameText:SetPoint(
        "LEFT",
        frame.warbandRosterRow,
        "LEFT",
        54,
        0
    )
    frame.warbandRosterRow.nameText:SetText("Warband Bank")
    frame.warbandRosterRow.nameText:SetTextColor(
        0.35, 0.80, 1.00
    )

    frame.warbandRosterRow.heldGearButton =
        CreateFrame(
            "Button",
            nil,
            frame.warbandRosterRow
        )
    frame.warbandRosterRow.heldGearButton:SetSize(20, 20)
    frame.warbandRosterRow.heldGearButton:SetPoint(
        "LEFT",
        frame.warbandRosterRow,
        "LEFT",
        158,
        0
    )
    frame.warbandRosterRow.heldGearButton.icon =
        frame.warbandRosterRow.heldGearButton:CreateTexture(
            nil,
            "ARTWORK"
        )
    frame.warbandRosterRow.heldGearButton.icon:SetAllPoints()
    frame.warbandRosterRow.heldGearButton.icon:SetTexture(
        "Interface\\Buttons\\Button-Backpack-Up"
    )
    frame.warbandRosterRow.heldGearButton.count =
        frame.warbandRosterRow.heldGearButton:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )
    frame.warbandRosterRow.heldGearButton.count:SetPoint(
        "BOTTOMRIGHT",
        frame.warbandRosterRow.heldGearButton,
        "BOTTOMRIGHT",
        2,
        -1
    )
    frame.warbandRosterRow.heldGearButton.count:SetTextColor(
        1.00, 0.82, 0.00
    )
    frame.warbandRosterRow.heldGearButton.count:SetShadowColor(
        0.00, 0.00, 0.00, 1.00
    )
    frame.warbandRosterRow.heldGearButton.count:SetShadowOffset(1, -1)
    frame.warbandRosterRow.heldGearButton:SetScript(
        "OnEnter",
        function(self)
            WGRShowHeldGearTooltip(
                self,
                "Warband Bank",
                WGRRosterWarbandHeldGearSummary()
            )
        end
    )
    frame.warbandRosterRow.heldGearButton:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    frame.UpdateRoster =
        function()
            local priority =
                GetRoutingPriority()

            local view =
                WGRGetRosterView(
                    priority
                )

            local priorityIndex =
                WGRRosterPriorityIndex(
                    priority
                )

            frame.WGRWarbandHeldSummary =
                WGRRosterWarbandHeldGearSummary()
            frame.WGRWarbandHeldCount =
                frame.WGRWarbandHeldSummary
                and tonumber(
                    frame.WGRWarbandHeldSummary.total
                )
                or 0

            frame.WGRWarbandRosterPosition =
                #view + 1

            if (
                WarboundGearRouterDB.interface.rosterViewSort
                or "PRIORITY"
            ) == "HOLDERS"
                and frame.WGRWarbandHeldCount > 0
            then
                frame.WGRWarbandRosterPosition =
                    1

                frame.WGRHolderScanIndex =
                    1

                while frame.WGRHolderScanIndex
                    <= #view
                do
                    frame.WGRHolderScanSummary =
                        WGRRosterHeldGearSummary(
                            view[
                                frame.WGRHolderScanIndex
                            ]
                        )

                    if frame.WGRHolderScanSummary
                        and (
                            tonumber(
                                frame.WGRHolderScanSummary.total
                            )
                            or 0
                        ) > 0
                    then
                        frame.WGRWarbandRosterPosition =
                            frame.WGRWarbandRosterPosition
                            + 1

                        frame.WGRHolderScanIndex =
                            frame.WGRHolderScanIndex
                            + 1
                    else
                        break
                    end
                end

                frame.WGRHolderScanIndex =
                    nil
                frame.WGRHolderScanSummary =
                    nil
            end

            rosterContent:SetHeight(
                math.max(
                    1,
                    (#view + 1) * 34
                )
            )

            if frame.rosterCount then
                frame.rosterCount:SetText(
                    tostring(#priority)
                        .. " characters"
                )
            end

            if frame.UpdateRemovedCharacters then
                frame.UpdateRemovedCharacters()
            end

            if frame.UpdatePriorityTools then
                frame.UpdatePriorityTools()
            end

            -- Hide old rows first. They will be reused below.
            for _, oldRow
                in ipairs(
                    frame.rosterRows
                )
            do
                oldRow:Hide()
            end

            for index, characterName
                in ipairs(
                    view
                )
            do
                local row =
                    frame.rosterRows[
                        index
                    ]

                if not row then
                    row =
                        CreateFrame(
                            "Frame",
                            nil,
                            rosterContent
                        )

                    row:SetSize(
                        880,
                        32
                    )

                    local dragHighlight =
                        row:CreateTexture(
                            nil,
                            "BACKGROUND",
                            nil,
                            1
                        )

                    dragHighlight:SetAllPoints(
                        row
                    )

                    dragHighlight:SetColorTexture(
                        0.20,
                        0.70,
                        1.00,
                        0.22
                    )

                    dragHighlight:Hide()

                    row.dragHighlight =
                        dragHighlight

                    local highlight =
                        row:CreateTexture(
                            nil,
                            "BACKGROUND"
                        )

                    highlight:SetAllPoints(
                        row
                    )

                    highlight:SetColorTexture(
                        1.00,
                        0.82,
                        0.00,
                        0.12
                    )

                    highlight:Hide()

                    row.highlight =
                        highlight

                    local dragHandle =
                        CreateFrame(
                            "Button",
                            nil,
                            row
                        )

                    dragHandle:SetSize(
                        24,
                        24
                    )

                    dragHandle:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        0,
                        0
                    )

                    dragHandle:RegisterForDrag(
                        "LeftButton"
                    )

                    local gripBars = {}

                    for barIndex = 1, 3 do
                        local bar =
                            dragHandle:CreateTexture(
                                nil,
                                "ARTWORK"
                            )

                        bar:SetColorTexture(
                            0.78,
                            0.78,
                            0.78,
                            0.95
                        )

                        bar:SetSize(
                            12,
                            2
                        )

                        bar:SetPoint(
                            "CENTER",
                            dragHandle,
                            "CENTER",
                            0,
                            (2 - barIndex) * 4
                        )

                        gripBars[
                            barIndex
                        ] =
                            bar
                    end

                    dragHandle.gripBars =
                        gripBars

                    row.dragHandle =
                        dragHandle

                    local priorityText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    priorityText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        26,
                        0
                    )

                    priorityText:SetWidth(
                        24
                    )

                    priorityText:SetJustifyH(
                        "RIGHT"
                    )

                    row.priorityText =
                        priorityText

                    local nameText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlight"
                        )

                    nameText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        54,
                        0
                    )

                    nameText:SetWidth(
                        112
                    )

                    nameText:SetJustifyH(
                        "LEFT"
                    )

                    row.nameText =
                        nameText

                    row.heldGearButton =
                        CreateFrame(
                            "Button",
                            nil,
                            row
                        )

                    row.heldGearButton:SetSize(
                        20,
                        20
                    )

                    row.heldGearButton:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        158,
                        0
                    )

                    row.heldGearButton.icon =
                        row.heldGearButton:CreateTexture(
                            nil,
                            "ARTWORK"
                        )

                    row.heldGearButton.icon:SetAllPoints(
                        row.heldGearButton
                    )

                    row.heldGearButton.icon:SetTexture(
                        "Interface\\Buttons\\Button-Backpack-Up"
                    )

                    row.heldGearButton.count =
                        row.heldGearButton:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    row.heldGearButton.count:SetPoint(
                        "BOTTOMRIGHT",
                        row.heldGearButton,
                        "BOTTOMRIGHT",
                        2,
                        -1
                    )

                    row.heldGearButton.count:SetTextColor(
                        1.00,
                        0.82,
                        0.00
                    )

                    row.heldGearButton.count:SetShadowColor(
                        0.00,
                        0.00,
                        0.00,
                        1.00
                    )

                    row.heldGearButton.count:SetShadowOffset(
                        1,
                        -1
                    )

                    row.heldGearButton:Hide()

                    local classText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    classText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        182,
                        0
                    )

                    classText:SetWidth(
                        36
                    )

                    classText:SetJustifyH(
                        "CENTER"
                    )

                    row.classText =
                        classText

                    local specText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    specText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        222,
                        0
                    )

                    specText:SetWidth(
                        46
                    )

                    specText:SetJustifyH(
                        "CENTER"
                    )

                    row.specText =
                        specText

                    local levelText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    levelText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        272,
                        0
                    )

                    levelText:SetWidth(
                        32
                    )

                    levelText:SetJustifyH(
                        "CENTER"
                    )

                    row.levelText =
                        levelText

                    local itemLevelText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    itemLevelText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        308,
                        0
                    )

                    itemLevelText:SetWidth(
                        38
                    )

                    itemLevelText:SetJustifyH(
                        "CENTER"
                    )

                    row.itemLevelText =
                        itemLevelText

                    local playtimeText =
                        row:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    playtimeText:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        350,
                        0
                    )

                    playtimeText:SetWidth(
                        54
                    )

                    playtimeText:SetJustifyH(
                        "CENTER"
                    )

                    row.playtimeText =
                        playtimeText

                    local specModeButton =
                        CreateWGRDropdown(
                            row,
                            96,
                            22
                        )

                    specModeButton:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        408,
                        0
                    )

                    row.specModeButton =
                        specModeButton

                    local weaponModeButton =
                        CreateWGRDropdown(
                            row,
                            112,
                            22
                        )

                    weaponModeButton:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        510,
                        0
                    )

                    row.weaponModeButton =
                        weaponModeButton

                    local thresholdDropdown =
                        CreateWGRDropdown(
                            row,
                            80,
                            22
                        )

                    thresholdDropdown:SetPoint(
                        "LEFT",
                        row,
                        "LEFT",
                        628,
                        0
                    )

                    row.thresholdDropdown =
                        thresholdDropdown

                    -- Large, font-independent priority controls.
                    local upButton =
                        CreateFrame(
                            "Button",
                            nil,
                            row
                        )

                    upButton:SetSize(
                        30,
                        30
                    )

                    upButton:SetPoint(
                        "RIGHT",
                        row,
                        "RIGHT",
                        -122,
                        0
                    )

                    upButton:SetNormalTexture(
                        "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up"
                    )

                    upButton:SetPushedTexture(
                        "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down"
                    )

                    upButton:SetDisabledTexture(
                        "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled"
                    )

                    row.upButton =
                        upButton

                    local downButton =
                        CreateFrame(
                            "Button",
                            nil,
                            row
                        )

                    downButton:SetSize(
                        30,
                        30
                    )

                    downButton:SetPoint(
                        "RIGHT",
                        row,
                        "RIGHT",
                        -88,
                        0
                    )

                    downButton:SetNormalTexture(
                        "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"
                    )

                    downButton:SetPushedTexture(
                        "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down"
                    )

                    downButton:SetDisabledTexture(
                        "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled"
                    )

                    row.downButton =
                        downButton

                    local statusDropdown =
                        CreateWGRDropdown(
                            row,
                            76,
                            22
                        )

                    statusDropdown:SetPoint(
                        "RIGHT",
                        row,
                        "RIGHT",
                        -1,
                        0
                    )

                    row.statusDropdown =
                        statusDropdown

                    frame.rosterRows[
                        index
                    ] =
                        row
                end

                row:ClearAllPoints()

                row:SetPoint(
                    "TOPLEFT",
                    rosterContent,
                    "TOPLEFT",
                    0,
                    -(
                        (
                            index
                            - 1
                            + (
                                index
                                    >= frame.WGRWarbandRosterPosition
                                and 1
                                or 0
                            )
                        )
                        * 34
                    )
                )

                local character =
                    FindCharacterByName(
                        characterName
                    )

                local remembered =
                    GetRememberedSpec(
                        characterName
                    )

                local actualPriority =
                    priorityIndex[
                        string.lower(
                            characterName
                        )
                    ] or index

                row.priorityText:SetText(
                    tostring(actualPriority)
                )

                row.nameText:SetText(
                    characterName
                )

                row.WGRCharacterName =
                    characterName

                row.WGRHeldGearSummary =
                    WGRRosterHeldGearSummary(
                        characterName
                    )

                row.WGRHeldGearCount =
                    row.WGRHeldGearSummary
                    and tonumber(
                        row.WGRHeldGearSummary.total
                    )
                    or 0

                if row.heldGearButton then
                    row.heldGearButton:SetShown(
                        row.WGRHeldGearCount > 0
                    )

                    row.heldGearButton.count:SetText(
                        row.WGRHeldGearCount > 0
                        and tostring(
                            row.WGRHeldGearCount
                        )
                        or ""
                    )

                    row.heldGearButton:SetScript(
                        "OnEnter",
                        function(self)
                            WGRShowHeldGearTooltip(
                                self,
                                characterName
                            )
                        end
                    )

                    row.heldGearButton:SetScript(
                        "OnLeave",
                        function()
                            GameTooltip:Hide()
                        end
                    )
                end

                row.dragHandle:SetScript(
                    "OnDragStart",
                    function(self)
                        local mode =
                            WarboundGearRouterDB.interface.rosterViewSort
                            or "PRIORITY"

                        local direction =
                            WarboundGearRouterDB.interface.rosterSortDirections
                            and WarboundGearRouterDB.interface.rosterSortDirections.PRIORITY
                            or "ASC"

                        if mode ~= "PRIORITY"
                            or direction ~= "ASC"
                        then
                            return
                        end

                        frame.WGRDraggedCharacter =
                            row.WGRCharacterName

                        frame.WGRDraggedRow =
                            row

                        if row.dragHighlight then
                            row.dragHighlight:Show()
                        end

                        frame.WGRCurrentInsertSlot =
                            nil

                        WGRUpdateInsertionPreview()
                    end
                )

                row.dragHandle:SetScript(
                    "OnDragStop",
                    function(self)
                        if row.dragHighlight then
                            row.dragHighlight:Hide()
                        end

                        local draggedCharacter =
                            frame.WGRDraggedCharacter

                        frame.WGRDraggedCharacter =
                            nil
                        frame.WGRDraggedRow =
                            nil

                        insertionPreview:Hide()

                        if not draggedCharacter then
                            return
                        end

                        insertionPreview:Hide()

                        local priority =
                            GetRoutingPriority()

                        local insertSlot =
                            frame.WGRCurrentInsertSlot
                            or WGRGetRosterInsertSlot(
                                rosterContent,
                                #priority
                            )

                        frame.WGRCurrentInsertSlot =
                            nil

                        if not insertSlot then
                            return
                        end

                        local currentIndex = nil

                        for index, name
                            in ipairs(priority)
                        do
                            if string.lower(name)
                                == string.lower(
                                    draggedCharacter
                                )
                            then
                                currentIndex =
                                    index
                                break
                            end
                        end

                        if not currentIndex then
                            return
                        end

                        if insertSlot == currentIndex
                            or insertSlot == currentIndex + 1
                        then
                            return
                        end

                        WGRSavePriorityBackup(
                            "Priority before drag-and-drop move"
                        )

                        if WGRMovePriorityToSlot(
                            draggedCharacter,
                            insertSlot
                        )
                        then
                            frame.UpdateRoster()
                            WGRMailUpdateTrackerFrame()

                            print(
                                "|cff00ff00WBGR:|r Moved "
                                .. draggedCharacter
                                .. " to priority "
                                .. tostring(
                                    (
                                        WGRRosterPriorityIndex(
                                            GetRoutingPriority()
                                        )[
                                            string.lower(
                                                draggedCharacter
                                            )
                                        ]
                                    )
                                    or "?"
                                )
                                .. "."
                            )
                        end
                    end
                )

                row.dragHandle:SetScript(
                    "OnEnter",
                    function(self)
                        if self.gripBars then
                            for _, bar
                                in ipairs(
                                    self.gripBars
                                )
                            do
                                bar:SetColorTexture(
                                    1.00,
                                    0.82,
                                    0.00,
                                    1.00
                                )
                            end
                        end

                        GameTooltip:SetOwner(
                            self,
                            "ANCHOR_RIGHT"
                        )

                        GameTooltip:AddLine(
                            "Drag to Reorder",
                            1.00,
                            0.82,
                            0.00
                        )

                        GameTooltip:AddLine(
                            "Drag this handle to move the character in Priority / Ascending view.",
                            0.85,
                            0.85,
                            0.85,
                            true
                        )

                        GameTooltip:Show()
                    end
                )

                row.dragHandle:SetScript(
                    "OnLeave",
                    function(self)
                        if self.gripBars then
                            for _, bar
                                in ipairs(
                                    self.gripBars
                                )
                            do
                                bar:SetColorTexture(
                                    0.78,
                                    0.78,
                                    0.78,
                                    0.95
                                )
                            end
                        end

                        GameTooltip:Hide()
                    end
                )

                local classID =
                    GetCharacterClassID(
                        characterName,
                        character
                    )

                local classInfo =
                    classID
                    and C_CreatureInfo
                    and C_CreatureInfo.GetClassInfo
                    and C_CreatureInfo.GetClassInfo(
                        classID
                    )

                local classColor =
                    classInfo
                    and classInfo.classFile
                    and RAID_CLASS_COLORS[
                        classInfo.classFile
                    ]

                if classColor then
                    row.nameText:SetTextColor(
                        classColor.r,
                        classColor.g,
                        classColor.b
                    )
                else
                    row.nameText:SetTextColor(
                        1.00,
                        1.00,
                        1.00
                    )
                end

                local currentName =
                    UnitName(
                        "player"
                    )

                if row.highlight then
                    row.highlight:SetShown(
                        currentName
                        and string.lower(
                            currentName
                        ) == string.lower(
                            characterName
                        )
                    )
                end

                local fullClassName =
                    WGRGetRosterClassName(
                        characterName,
                        character
                    )

                row.classText:SetText(
                    WGRClassAbbreviations[fullClassName]
                    or fullClassName
                )

                local fullSpecName =
                    remembered
                    and remembered.specName
                    or nil

                row.specText:SetText(
                    fullSpecName
                    and (
                        WGRSpecAbbreviations[fullSpecName]
                        or fullSpecName
                    )
                    or "?"
                )

                row.levelText:SetText(
                    tostring(
                        WGRRosterLevel(
                            characterName
                        )
                    )
                )

                local rosterItemLevel =
                    WGRRosterItemLevel(
                        characterName
                    )

                row.itemLevelText:SetText(
                    rosterItemLevel > 0
                    and tostring(
                        math.floor(
                            rosterItemLevel
                            + 0.5
                        )
                    )
                    or "?"
                )

                row.playtimeText:SetText(
                    WGRFormatRosterPlaytime(
                        WGRRosterPlaytime(
                            characterName
                        )
                    )
                )

                row.specModeButton:SetValueText(
                    WGRGetCharacterSpecModeDisplay(
                        characterName
                    )
                )

                row.specModeButton:SetScript(
                    "OnClick",
                    function(self)
                        MenuUtil.CreateContextMenu(
                            self,
                            function(ownerRegion, rootDescription)
                                rootDescription:CreateTitle(
                                    characterName
                                    .. " Spec Mode"
                                )

                                rootDescription:CreateRadio(
                                    "Global ("
                                        .. (
                                            WGRSpecModeLabels[
                                                WarboundGearRouterDB.routingSettings.specMode
                                            ]
                                            or "Current Spec Only"
                                        )
                                        .. ")",
                                    function()
                                        local override =
                                            WGRGetCharacterOverride(
                                                characterName
                                            )

                                        return not override
                                            or not override.specMode
                                    end,
                                    function()
                                        WGRSetCharacterSpecMode(
                                            characterName,
                                            "GLOBAL"
                                        )

                                        frame.customSpecsPanel:Hide()
                                        frame.UpdateRoster()
                                    end
                                )

                                for _, mode
                                    in ipairs({
                                        "CURRENT",
                                        "ALL",
                                        "CUSTOM",
                                    })
                                do
                                    local value =
                                        mode

                                    rootDescription:CreateRadio(
                                        WGRSpecModeLabels[value],
                                        function()
                                            local override =
                                                WGRGetCharacterOverride(
                                                    characterName
                                                )

                                            return override
                                                and override.specMode
                                                    == value
                                        end,
                                        function()
                                            WGRSetCharacterSpecMode(
                                                characterName,
                                                value
                                            )

                                            frame.UpdateRoster()

                                            if value == "CUSTOM" then
                                                C_Timer.After(
                                                    0.05,
                                                    function()
                                                        frame.ShowCustomSpecsPanel(
                                                            characterName,
                                                            self
                                                        )
                                                    end
                                                )
                                            else
                                                frame.customSpecsPanel:Hide()
                                            end
                                        end
                                    )
                                end

                                if WGRGetEffectiveSpecMode(
                                    characterName
                                ) == "CUSTOM"
                                then
                                    rootDescription:CreateDivider()

                                    rootDescription:CreateButton(
                                        "Edit Custom Specs...",
                                        function()
                                            C_Timer.After(
                                                0.05,
                                                function()
                                                    frame.ShowCustomSpecsPanel(
                                                        characterName,
                                                        self
                                                    )
                                                end
                                            )
                                        end
                                    )
                                end
                            end
                        )
                    end
                )

                local weaponMode=WGRGetCharacterWeaponMode(characterName)
                row.weaponModeButton:SetValueText(WGRWeaponModeLabels[weaponMode] or "All Eligible")
                row.weaponModeButton:SetScript("OnEnter",function(self)
                    if WGRGetCharacterWeaponMode(characterName)=="SAVED" then
                        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                        GameTooltip:SetText("Saved Setup",1,0.82,0)
                        GameTooltip:AddLine(
                            "Uses the weapon setup you last equipped for each spec. If a spec has no saved setup, WBGR uses the best compatible setup already saved on that character. If only part of a compatible setup is available, WBGR uses that partial setup. If no compatible setup is known, WBGR uses All Eligible weapons for that spec.",
                            1,1,1,true
                        )

                        local character =
                            FindCharacterByName(characterName)

                        local specIDs =
                            WGRGetRoutingSpecIDs(
                                characterName,
                                character
                            )

                        local addedInherited = false

                        for _, specID
                            in ipairs(specIDs or {})
                        do
                            local profile,
                                  baseline =
                                WGRGetSpecWeaponProfile(
                                    characterName,
                                    specID
                                )

                            if profile == "SAVED_SETUP"
                                and baseline
                                and baseline.inherited
                            then
                                if not addedInherited then
                                    GameTooltip:AddLine(" ")
                                    addedInherited = true
                                end

                                GameTooltip:AddLine(
                                    (
                                        WGRSpecNamesByID[specID]
                                        or tostring(specID)
                                    )
                                    .. ": "
                                    .. (
                                        WGRDescribeInheritedBaseline(baseline)
                                        or "Inherited setup"
                                    ),
                                    1,0.82,0,true
                                )
                            elseif profile == "ALL_ELIGIBLE"
                                and not WGRGetSpecWeaponBaseline(
                                    characterName,
                                    specID
                                )
                            then
                                if not addedInherited then
                                    GameTooltip:AddLine(" ")
                                    addedInherited = true
                                end

                                GameTooltip:AddLine(
                                    (
                                        WGRSpecNamesByID[specID]
                                        or tostring(specID)
                                    )
                                    .. ": No compatible saved setup; using All Eligible.",
                                    0.8,0.8,0.8,true
                                )
                            end
                        end

                        GameTooltip:Show()
                    end
                end)
                row.weaponModeButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
                row.weaponModeButton:SetScript("OnClick",function(self)
                    MenuUtil.CreateContextMenu(self,function(owner,root)
                        root:CreateTitle(characterName.." Weapons")
                        for _,mode in ipairs({"ALL","SAVED","CUSTOM"}) do local value=mode
                            root:CreateRadio(WGRWeaponModeLabels[value],function() return WGRGetCharacterWeaponMode(characterName)==value end,function()
                                WGRSetCharacterWeaponMode(characterName,value)
                                frame.UpdateRoster(); RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()

                                if frame.UpdateGlobalWeaponOverrideHelp then
                                    frame.UpdateGlobalWeaponOverrideHelp()
                                end

                                if value=="CUSTOM" then
                                    C_Timer.After(.05,function() frame.ShowCustomWeaponsPanel(characterName,self) end)
                                else
                                    frame.customWeaponsPanel:Hide()
                                end
                            end)
                        end
                        if WGRGetCharacterWeaponMode(characterName)=="CUSTOM" then
                            root:CreateDivider(); root:CreateButton("Edit Custom Weapons...",function() C_Timer.After(.05,function() frame.ShowCustomWeaponsPanel(characterName,self) end) end)
                        end
                    end)
                end)

                row.thresholdDropdown:SetValueText(
                    WGRGetCharacterThresholdDisplay(
                        characterName
                    )
                )

                row.thresholdDropdown:SetScript(
                    "OnClick",
                    function(self)
                        MenuUtil.CreateContextMenu(
                            self,
                            function(ownerRegion, rootDescription)
                                rootDescription:CreateTitle(
                                    characterName
                                        .. " Upgrade Threshold"
                                )

                                rootDescription:CreateRadio(
                                    "Global (+"
                                        .. tostring(
                                            WGRGetGlobalUpgradeThreshold()
                                        )
                                        .. ")",
                                    function()
                                        return
                                            WGRGetCharacterThresholdOverride(
                                                characterName
                                            ) == nil
                                    end,
                                    function()
                                        WGRSetCharacterThreshold(
                                            characterName,
                                            "GLOBAL"
                                        )
                                        frame.UpdateRoster()
                                    end
                                )

                                for _, threshold
                                    in ipairs(
                                        WGRThresholdChoices
                                    )
                                do
                                    local value =
                                        threshold

                                    rootDescription:CreateRadio(
                                        "+"
                                            .. tostring(
                                                value
                                            ),
                                        function()
                                            return
                                                WGRGetCharacterThresholdOverride(
                                                    characterName
                                                ) == value
                                        end,
                                        function()
                                            WGRSetCharacterThreshold(
                                                characterName,
                                                value
                                            )
                                            frame.UpdateRoster()
                                        end
                                    )
                                end

                                rootDescription:CreateDivider()

                                rootDescription:CreateButton(
                                    "Custom...",
                                    function()
                                        C_Timer.After(
                                            0.05,
                                            function()
                                                frame.ShowCustomThresholdPanel(
                                                    characterName,
                                                    self
                                                )
                                            end
                                        )
                                    end
                                )
                            end
                        )
                    end
                )

                local priorityView =
                    (
                        WarboundGearRouterDB.interface.rosterViewSort
                        or "PRIORITY"
                    ) == "PRIORITY"

                local priorityAscending =
                    (
                        WarboundGearRouterDB.interface.rosterSortDirections
                        and WarboundGearRouterDB.interface.rosterSortDirections.PRIORITY
                        or "ASC"
                    ) == "ASC"

                row.dragHandle:SetEnabled(
                    priorityView
                    and priorityAscending
                )

                row.dragHandle:SetAlpha(
                    priorityView
                    and priorityAscending
                    and 1.00
                    or 0.30
                )

                row.upButton:SetEnabled(
                    priorityView
                    and priorityAscending
                    and actualPriority > 1
                )

                row.downButton:SetEnabled(
                    priorityView
                    and priorityAscending
                    and actualPriority < #priority
                )

                local ignored =
                    WGRIsCharacterIgnored(
                        characterName
                    )

                if ignored then
                    row.statusDropdown:SetValueText(
                        "Ignored"
                    )

                    row:SetAlpha(
                        0.42
                    )
                else
                    row.statusDropdown:SetValueText(
                        "Active"
                    )

                    row:SetAlpha(
                        1.00
                    )
                end

                row.statusDropdown:SetScript(
                    "OnClick",
                    function(self)
                        MenuUtil.CreateContextMenu(
                            self,
                            function(ownerRegion, rootDescription)
                                rootDescription:CreateTitle(
                                    characterName
                                        .. " Status"
                                )

                                rootDescription:CreateRadio(
                                    "Active",
                                    function()
                                        return
                                            not WGRIsCharacterIgnored(
                                                characterName
                                            )
                                    end,
                                    function()
                                        WGRSetCharacterIgnored(
                                            characterName,
                                            false
                                        )

                                        frame.UpdateRoster()
                                    end
                                )

                                rootDescription:CreateRadio(
                                    "Ignored",
                                    function()
                                        return
                                            WGRIsCharacterIgnored(
                                                characterName
                                            )
                                    end,
                                    function()
                                        WGRSetCharacterIgnored(
                                            characterName,
                                            true
                                        )

                                        frame.UpdateRoster()
                                    end
                                )

                                rootDescription:CreateButton(
                                    "Removed",
                                    function()
                                        StaticPopup_Show(
                                            "WGR_CONFIRM_REMOVE_CHARACTER",
                                            characterName,
                                            nil,
                                            {
                                                characterName =
                                                    characterName,
                                                frame =
                                                    frame,
                                            }
                                        )
                                    end
                                )
                            end
                        )
                    end
                )

                row.upButton:SetScript(
                    "OnClick",
                    function()
                        if WGRMovePriority(
                            characterName,
                            -1
                        )
                        then
                            frame.UpdateRoster()
                        end
                    end
                )

                row.downButton:SetScript(
                    "OnClick",
                    function()
                        if WGRMovePriority(
                            characterName,
                            1
                        )
                        then
                            frame.UpdateRoster()
                        end
                    end
                )


                row:Show()
            end

            frame.warbandRosterRow:ClearAllPoints()
            frame.warbandRosterRow:SetPoint(
                "TOPLEFT",
                rosterContent,
                "TOPLEFT",
                0,
                -(
                    (frame.WGRWarbandRosterPosition - 1)
                    * 34
                )
            )
            frame.warbandRosterRow.heldGearButton:SetShown(
                frame.WGRWarbandHeldCount > 0
            )
            frame.warbandRosterRow.heldGearButton.count:SetText(
                frame.WGRWarbandHeldCount > 0
                and tostring(frame.WGRWarbandHeldCount)
                or ""
            )
            frame.warbandRosterRow:Show()

            if rosterScroll.UpdateScrollChildRect then
                rosterScroll:UpdateScrollChildRect()
            end
        end

    -- ========================================================
    -- SETTINGS PAGE
    -- ========================================================
    local settingsPage =
        CreateFrame(
            "Frame",
            nil,
            frame
        )

    settingsPage:SetAllPoints(
        mailPage
    )

    settingsPage:Hide()

    frame.settingsPage =
        settingsPage

    local settingsTitle =
        settingsPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    settingsTitle:SetPoint(
        "TOPLEFT",
        settingsPage,
        "TOPLEFT",
        0,
        0
    )
    settingsTitle:SetText("Settings")

    local settingsTabs = {}
    local settingsPanels = {}

    local function CreateSettingsPanel(key)
        local panel =
            CreateFrame(
                "Frame",
                nil,
                settingsPage
            )

        panel:SetPoint(
            "TOPLEFT",
            settingsPage,
            "TOPLEFT",
            0,
            -78
        )

        panel:SetPoint(
            "BOTTOMRIGHT",
            settingsPage,
            "BOTTOMRIGHT",
            0,
            0
        )

        panel:Hide()
        settingsPanels[key] = panel
        return panel
    end

    local eligiblePanel =
        CreateSettingsPanel("ELIGIBLE")

    local routingPanel =
        CreateSettingsPanel("ROUTING")

    local appearancePanel =
        CreateSettingsPanel("APPEARANCE")

    local interfacePanel =
        CreateSettingsPanel("INTERFACE")

    local activeSettingsTab = "ELIGIBLE"

    local function WGRShowSettingsTab(key)
        activeSettingsTab = key

        for panelKey, panel
            in pairs(settingsPanels)
        do
            panel:SetShown(
                panelKey == key
            )
        end

        for tabKey, button
            in pairs(settingsTabs)
        do
            if button.label then
                if tabKey == key then
                    button.label:SetTextColor(
                        1.00,
                        0.82,
                        0.00
                    )

                    button:SetBackdropColor(
                        0.10,
                        0.10,
                        0.10,
                        0.98
                    )
                else
                    button.label:SetTextColor(
                        1.00,
                        1.00,
                        1.00
                    )

                    button:SetBackdropColor(
                        0.04,
                        0.04,
                        0.04,
                        0.92
                    )
                end
            end
        end
    end

    local function CreateSettingsTab(
        key,
        text,
        x,
        width
    )
        local button =
            CreateFrame(
                "Button",
                nil,
                settingsPage,
                "BackdropTemplate"
            )

        button:SetSize(
            width,
            26
        )

        button:SetPoint(
            "TOPLEFT",
            settingsPage,
            "TOPLEFT",
            x,
            -36
        )

        button:SetBackdrop(
            {
                bgFile =
                    "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile =
                    "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 9,
                insets = {
                    left = 3,
                    right = 3,
                    top = 3,
                    bottom = 3,
                },
            }
        )

        button:SetBackdropColor(
            0.04,
            0.04,
            0.04,
            0.92
        )

        local label =
            button:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )

        label:SetPoint(
            "CENTER",
            button,
            "CENTER",
            0,
            0
        )

        label:SetText(
            text
        )

        button.label =
            label

        button:SetScript(
            "OnClick",
            function()
                WGRShowSettingsTab(
                    key
                )
            end
        )

        button:SetScript(
            "OnEnter",
            function(self)
                if activeSettingsTab ~= key then
                    self:SetBackdropColor(
                        0.12,
                        0.12,
                        0.12,
                        0.96
                    )
                end
            end
        )

        button:SetScript(
            "OnLeave",
            function(self)
                if activeSettingsTab ~= key then
                    self:SetBackdropColor(
                        0.04,
                        0.04,
                        0.04,
                        0.92
                    )
                end
            end
        )

        settingsTabs[key] =
            button
    end

    CreateSettingsTab(
        "ELIGIBLE",
        "Eligible Gear",
        0,
        150
    )

    CreateSettingsTab(
        "ROUTING",
        "Routing",
        152,
        120
    )

    CreateSettingsTab(
        "APPEARANCE",
        "Appearance",
        274,
        135
    )

    CreateSettingsTab(
        "INTERFACE",
        "Interface",
        411,
        120
    )

    -- ELIGIBLE GEAR
    local eligibleTitle =
        eligiblePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    eligibleTitle:SetPoint(
        "TOPLEFT",
        eligiblePanel,
        "TOPLEFT",
        0,
        0
    )
    eligibleTitle:SetText("Eligible Gear")

    local qualityLabel =
        eligiblePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    qualityLabel:SetPoint(
        "TOPLEFT",
        eligibleTitle,
        "BOTTOMLEFT",
        0,
        -14
    )
    qualityLabel:SetText("Minimum Item Quality:")

    local qualityNames = {
        [0] = "Poor (Gray)",
        [1] = "Common (White)",
        [2] = "Uncommon (Green)",
        [3] = "Rare (Blue)",
        [4] = "Epic (Purple)",
    }

    local qualityDropdown =
        CreateWGRDropdown(
            eligiblePanel,
            165,
            22
        )

    qualityDropdown:SetPoint(
        "LEFT",
        qualityLabel,
        "RIGHT",
        14,
        0
    )

    local function WGRUpdateQualityDropdown()
        qualityDropdown:SetValueText(
            qualityNames[
                WarboundGearRouterDB.eligibleGear.minimumQuality
            ] or "Uncommon (Green)"
        )
    end

    qualityDropdown:SetScript(
        "OnClick",
        function(self)
            MenuUtil.CreateContextMenu(
                self,
                function(ownerRegion, rootDescription)
                    rootDescription:CreateTitle(
                        "Minimum Item Quality"
                    )

                    for quality = 0, 4 do
                        local value = quality

                        rootDescription:CreateRadio(
                            qualityNames[value],
                            function()
                                return
                                    WarboundGearRouterDB.eligibleGear.minimumQuality
                                    == value
                            end,
                            function()
                                WarboundGearRouterDB.eligibleGear.minimumQuality =
                                    value
                                WGRUpdateQualityDropdown()
                                RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
                            end
                        )
                    end
                end
            )
        end
    )

    WGRUpdateQualityDropdown()

    local includeLabel =
        eligiblePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    includeLabel:SetPoint(
        "TOPLEFT",
        qualityLabel,
        "BOTTOMLEFT",
        0,
        -25
    )
    includeLabel:SetText("Include:")

    local warboundCheck =
        CreateFrame(
            "CheckButton",
            nil,
            eligiblePanel,
            "UICheckButtonTemplate"
        )

    warboundCheck:SetPoint(
        "LEFT",
        includeLabel,
        "RIGHT",
        10,
        0
    )

    local warboundLabel =
        eligiblePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    warboundLabel:SetPoint(
        "LEFT",
        warboundCheck,
        "RIGHT",
        2,
        0
    )
    warboundLabel:SetText("Warbound")

    local boeCheck =
        CreateFrame(
            "CheckButton",
            nil,
            eligiblePanel,
            "UICheckButtonTemplate"
        )

    boeCheck:SetPoint(
        "LEFT",
        warboundLabel,
        "RIGHT",
        28,
        0
    )

    local boeLabel =
        eligiblePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    boeLabel:SetPoint(
        "LEFT",
        boeCheck,
        "RIGHT",
        2,
        0
    )
    boeLabel:SetText("Bind on Equip")

    warboundCheck:SetChecked(
        WarboundGearRouterDB.eligibleGear.warbound
    )

    boeCheck:SetChecked(
        WarboundGearRouterDB.eligibleGear.boe
    )

    local function WGRUpdateEligibleGear()
        WarboundGearRouterDB.eligibleGear.warbound =
            warboundCheck:GetChecked()
            and true
            or false

        WarboundGearRouterDB.eligibleGear.boe =
            boeCheck:GetChecked()
            and true
            or false

        RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
    end

    warboundCheck:SetScript(
        "OnClick",
        WGRUpdateEligibleGear
    )

    boeCheck:SetScript(
        "OnClick",
        WGRUpdateEligibleGear
    )

    if not StaticPopupDialogs[
        "WGR_CONFIRM_UNIGNORE_ITEM"
    ]
    then
        StaticPopupDialogs[
            "WGR_CONFIRM_UNIGNORE_ITEM"
        ] = {
            text =
                "Stop ignoring %s?\n\nLast Known Location: %s\n\nWBGR will begin routing all copies of this item again.",
            button1 =
                "Unignore",
            button2 =
                "Cancel",
            OnAccept =
                function(
                    self,
                    data
                )
                    if data
                        and data.itemID
                    then
                        WGRSetItemIgnored(
                            data.itemID,
                            false
                        )
                    end
                end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local ignoredTitle =
        eligiblePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    ignoredTitle:SetPoint(
        "TOPLEFT",
        includeLabel,
        "BOTTOMLEFT",
        0,
        -34
    )

    ignoredTitle:SetText(
        "Ignored Items:"
    )

    local ignoredHelp =
        eligiblePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    ignoredHelp:SetPoint(
        "LEFT",
        ignoredTitle,
        "RIGHT",
        10,
        0
    )

    ignoredHelp:SetTextColor(
        0.68,
        0.68,
        0.68
    )

    ignoredHelp:SetText(
        "Right-click an item in Gear Finder to ignore it."
    )

    local ignoredScroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            eligiblePanel,
            "UIPanelScrollFrameTemplate"
        )

    ignoredScroll:SetPoint(
        "TOPLEFT",
        ignoredTitle,
        "BOTTOMLEFT",
        0,
        -10
    )

    ignoredScroll:SetSize(
        650,
        150
    )

    local ignoredContent =
        CreateFrame(
            "Frame",
            nil,
            ignoredScroll
        )

    ignoredContent:SetWidth(
        620
    )
    ignoredContent:SetHeight(
        1
    )

    ignoredScroll:SetScrollChild(
        ignoredContent
    )

    local ignoredRows = {}

    local function WGRIgnoredLocationForItem(
        itemID,
        savedLocation
    )
        local locations = {}
        local seen = {}

        local function AddLocation(text)
            if text
                and text ~= ""
                and not seen[text]
            then
                seen[text] = true
                locations[#locations + 1] =
                    text
            end
        end

        local currentName =
            UnitName("player")
            or "Current Character"

        for bagID = 0, 4 do
            local slots =
                C_Container.GetContainerNumSlots(
                    bagID
                )
                or 0

            for slotID = 1, slots do
                local info =
                    C_Container.GetContainerItemInfo(
                        bagID,
                        slotID
                    )

                if info
                    and info.itemID == itemID
                then
                    AddLocation(
                        currentName
                        .. " — Bags"
                    )
                    break
                end
            end
        end

        local function ScanBankType(
            bankType,
            label
        )
            if not C_Bank
                or not C_Bank.FetchPurchasedBankTabIDs
                or bankType == nil
            then
                return
            end

            local ok, tabIDs =
                pcall(
                    C_Bank.FetchPurchasedBankTabIDs,
                    bankType
                )

            if not ok
                or type(tabIDs) ~= "table"
            then
                return
            end

            for _, bagID
                in ipairs(tabIDs)
            do
                local slots =
                    C_Container.GetContainerNumSlots(
                        bagID
                    )
                    or 0

                for slotID = 1, slots do
                    local info =
                        C_Container.GetContainerItemInfo(
                            bagID,
                            slotID
                        )

                    if info
                        and info.itemID == itemID
                    then
                        AddLocation(label)
                        break
                    end
                end
            end
        end

        if Enum
            and Enum.BankType
        then
            ScanBankType(
                Enum.BankType.Character,
                currentName
                    .. " — Personal Bank"
            )

            ScanBankType(
                Enum.BankType.Account,
                "Warband Bank"
            )
        end

        if #locations == 0 then
            AddLocation(
                savedLocation
                or "Unknown"
            )
        end

        return table.concat(
            locations,
            " • "
        )
    end

    local function WGRCreateIgnoredRow(index)
        local row =
            CreateFrame(
                "Frame",
                nil,
                ignoredContent
            )

        row:SetSize(
            610,
            44
        )

        row:SetPoint(
            "TOPLEFT",
            ignoredContent,
            "TOPLEFT",
            0,
            -(
                (index - 1)
                * 46
            )
        )

        local icon =
            row:CreateTexture(
                nil,
                "ARTWORK"
            )
        icon:SetSize(34, 34)
        icon:SetPoint(
            "LEFT",
            row,
            "LEFT",
            0,
            0
        )

        local name =
            row:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )
        name:SetPoint(
            "TOPLEFT",
            icon,
            "TOPRIGHT",
            8,
            -2
        )
        name:SetWidth(390)
        name:SetJustifyH("LEFT")

        local location =
            row:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )
        location:SetPoint(
            "TOPLEFT",
            name,
            "BOTTOMLEFT",
            0,
            -3
        )
        location:SetWidth(390)
        location:SetJustifyH("LEFT")
        location:SetTextColor(
            0.62,
            0.62,
            0.62
        )

        local remove =
            CreateFrame(
                "Button",
                nil,
                row,
                "UIPanelButtonTemplate"
            )
        remove:SetSize(86, 22)
        remove:SetPoint(
            "RIGHT",
            row,
            "RIGHT",
            -8,
            0
        )
        remove:SetText("Unignore")

        row.icon = icon
        row.name = name
        row.location = location
        row.remove = remove

        ignoredRows[index] = row
        return row
    end

    WGRRefreshIgnoredItemsUI =
        function()
            local entries =
                WGRGetIgnoredItems
                and WGRGetIgnoredItems()
                or {}

            for index, entry
                in ipairs(entries)
            do
                local row =
                    ignoredRows[index]
                    or WGRCreateIgnoredRow(index)

                local texture =
                    entry.itemLink
                    and C_Item.GetItemIconByID(
                        entry.itemLink
                    )
                    or C_Item.GetItemIconByID(
                        entry.itemID
                    )

                row.icon:SetTexture(texture)

                local itemName =
                    entry.name
                    or (
                        "Item "
                        .. tostring(entry.itemID)
                    )

                row.name:SetText(itemName)

                local liveLocation =
                    WGRIgnoredLocationForItem(
                        entry.itemID,
                        entry.lastKnownLocation
                    )

                entry.lastKnownLocation =
                    liveLocation

                row.location:SetText(
                    "Last Known Location: "
                    .. liveLocation
                )

                row.remove:SetScript(
                    "OnClick",
                    function()
                        StaticPopup_Show(
                            "WGR_CONFIRM_UNIGNORE_ITEM",
                            itemName,
                            liveLocation
                                or entry.lastKnownLocation
                                or "Unknown",
                            {
                                itemID =
                                    entry.itemID,
                            }
                        )
                    end
                )

                row:Show()
            end

            for index =
                #entries + 1,
                #ignoredRows
            do
                ignoredRows[index]:Hide()
            end

            ignoredContent:SetHeight(
                math.max(
                    1,
                    #entries * 46
                )
            )

            if #entries == 0 then
                ignoredHelp:SetText(
                    "None. Right-click an item in Gear Finder to ignore it."
                )
            else
                ignoredHelp:SetText(
                    tostring(#entries)
                    .. " ignored item"
                    .. (
                        #entries == 1
                        and ""
                        or "s"
                    )
                    .. " (alphabetical)"
                )
            end
        end

    WGRRefreshIgnoredItemsUI()

    WGRRefreshIgnoredItemLocations =
        function()
            if WGRRefreshIgnoredItemsUI then
                WGRRefreshIgnoredItemsUI()
            end
        end

    -- ROUTING
    local routingTitle =
        routingPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    routingTitle:SetPoint(
        "TOPLEFT",
        routingPanel,
        "TOPLEFT",
        0,
        0
    )
    routingTitle:SetText("Routing")

    -- Spec Modes -------------------------------------------------
    local specSection =
        routingPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )
    specSection:SetPoint("TOPLEFT", routingTitle, "BOTTOMLEFT", 0, -1)
    specSection:SetText("")

    local specModeLabel =
        routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    specModeLabel:SetPoint("TOPLEFT",routingTitle,"BOTTOMLEFT",0,-10)
    specModeLabel:SetText("Default Spec Mode:")

    local specModeDropdown = CreateWGRDropdown(routingPanel,175,22)
    specModeDropdown:SetPoint("LEFT",specModeLabel,"RIGHT",14,0)

    local function WGRUpdateGlobalSpecModeDropdown()
        local mode=WarboundGearRouterDB.routingSettings.specMode or "CURRENT"
        if mode=="CUSTOM" then
            mode="CURRENT"
            WarboundGearRouterDB.routingSettings.specMode=mode
        end
        specModeDropdown:SetValueText(WGRSpecModeLabels[mode] or "Current Spec Only")
    end

    specModeDropdown:SetScript("OnClick",function(self)
        MenuUtil.CreateContextMenu(self,function(ownerRegion,rootDescription)
            rootDescription:CreateTitle("Default Spec Mode")
            for _,mode in ipairs({"CURRENT","ALL"}) do
                local value=mode
                rootDescription:CreateRadio(
                    WGRSpecModeLabels[value],
                    function() return WarboundGearRouterDB.routingSettings.specMode==value end,
                    function()
                        WarboundGearRouterDB.routingSettings.specMode=value
                        WGRUpdateGlobalSpecModeDropdown()
                        if frame.UpdateRoster then frame.UpdateRoster() end
                    end
                )
            end
        end)
    end)
    WGRUpdateGlobalSpecModeDropdown()

    local function WGRSizeResetButtonToText(
        button
    )
        local textRegion =
            button
            and button:GetFontString()

        local textWidth =
            textRegion
            and textRegion:GetStringWidth()
            or 0

        button:SetSize(
            math.ceil(
                textWidth
            ) + 24,
            22
        )
    end

    local resetSpecModesButton=CreateFrame("Button",nil,routingPanel,"UIPanelButtonTemplate")
    resetSpecModesButton:SetPoint("LEFT",specModeDropdown,"RIGHT",10,0)
    resetSpecModesButton:SetText("Reset All Specs to Default")
    WGRSizeResetButtonToText(resetSpecModesButton)
    resetSpecModesButton:SetScript("OnClick",function()
        StaticPopup_Show("WGR_CONFIRM_RESET_ALL_SPEC_MODES",nil,nil,{frame=frame})
    end)

    local specModeHelp=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    specModeHelp:SetPoint("TOPLEFT",specModeLabel,"BOTTOMLEFT",0,-8)
    specModeHelp:SetWidth(760)
    specModeHelp:SetJustifyH("LEFT")
    specModeHelp:SetTextColor(.68,.68,.68)
    specModeHelp:SetText(
        "Configure Custom Specs in the Roster."
    )

    local belowMaxLabel=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    belowMaxLabel:SetPoint("TOPLEFT",specModeHelp,"BOTTOMLEFT",0,-12)
    belowMaxLabel:SetText("Below Max Level Spec Mode:")

    local underMaxAllSpecsButton=CreateFrame("Button",nil,routingPanel,"UIPanelButtonTemplate")
    underMaxAllSpecsButton:SetSize(120,22)
    underMaxAllSpecsButton:SetPoint("LEFT",belowMaxLabel,"RIGHT",14,0)
    underMaxAllSpecsButton:SetText("Set to All Specs")
    underMaxAllSpecsButton:SetScript("OnClick",function()
        StaticPopup_Show("WGR_CONFIRM_UNDERMAX_ALL_SPECS",nil,nil,{frame=frame})
    end)

    local belowMaxHelp=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    belowMaxHelp:SetPoint("TOPLEFT",belowMaxLabel,"BOTTOMLEFT",0,-7)
    belowMaxHelp:SetWidth(760)
    belowMaxHelp:SetJustifyH("LEFT")
    belowMaxHelp:SetTextColor(.68,.68,.68)
    belowMaxHelp:SetText(
        "Lets lower-level characters collect gear for all class specs."
    )

    -- Weapon Eligibility -----------------------------------------
    local weaponSection=routingPanel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    weaponSection:SetPoint("TOPLEFT",belowMaxHelp,"BOTTOMLEFT",0,-1)
    weaponSection:SetText("")

    local weaponDefaultLabel=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    weaponDefaultLabel:SetPoint("TOPLEFT",belowMaxHelp,"BOTTOMLEFT",0,-12)
    weaponDefaultLabel:SetText("Default Weapon Eligibility:")

    local weaponDefaultDropdown=CreateWGRDropdown(routingPanel,150,22)
    weaponDefaultDropdown:SetPoint("LEFT",weaponDefaultLabel,"RIGHT",14,0)

    local function WGRUpdateDefaultWeaponDropdown()
        local mode=WarboundGearRouterDB.routingSettings.weaponMode or "ALL"
        if mode~="ALL" and mode~="SAVED" then
            mode="ALL"
            WarboundGearRouterDB.routingSettings.weaponMode=mode
        end
        weaponDefaultDropdown:SetValueText(WGRWeaponModeLabels[mode] or "All Eligible")
    end

    weaponDefaultDropdown:SetScript("OnClick",function(self)
        MenuUtil.CreateContextMenu(self,function(ownerRegion,rootDescription)
            rootDescription:CreateTitle("Default Weapon Eligibility")
            for _,mode in ipairs({"ALL","SAVED"}) do
                local value=mode
                rootDescription:CreateRadio(
                    WGRWeaponModeLabels[value],
                    function() return (WarboundGearRouterDB.routingSettings.weaponMode or "ALL")==value end,
                    function()
                        local oldDefault=WarboundGearRouterDB.routingSettings.weaponMode or "ALL"
                        WarboundGearRouterDB.routingSettings.weaponMode=value
                        -- Existing characters following the old default remain followers.
                        for key,savedMode in pairs(WarboundGearRouterDB.weaponModes) do
                            if savedMode==value then
                                WarboundGearRouterDB.weaponModes[key]=nil
                            elseif savedMode==nil then
                                WarboundGearRouterDB.weaponModes[key]=nil
                            end
                        end
                        WGRUpdateDefaultWeaponDropdown()
                        if frame.UpdateRoster then frame.UpdateRoster() end
                        if frame.UpdateGlobalWeaponOverrideHelp then frame.UpdateGlobalWeaponOverrideHelp() end
                        RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
                    end
                )
            end
        end)
    end)
    WGRUpdateDefaultWeaponDropdown()

    local resetWeaponsButton=CreateFrame("Button",nil,routingPanel,"UIPanelButtonTemplate")
    resetWeaponsButton:SetPoint("LEFT",weaponDefaultDropdown,"RIGHT",10,0)
    resetWeaponsButton:SetText("Reset All Weapons to Default")
    WGRSizeResetButtonToText(resetWeaponsButton)
    resetWeaponsButton:SetScript("OnClick",function()
        StaticPopup_Show("WGR_CONFIRM_RESET_ALL_WEAPONS",nil,nil,{frame=frame})
    end)

    local weaponDefaultHelp=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    weaponDefaultHelp:SetPoint("TOPLEFT",weaponDefaultLabel,"BOTTOMLEFT",0,-8)
    weaponDefaultHelp:SetWidth(760)
    weaponDefaultHelp:SetJustifyH("LEFT")
    weaponDefaultHelp:SetTextColor(.68,.68,.68)
    weaponDefaultHelp:SetText(
        "Saved Setup only routes weapons matching what you're using."
    )

    -- Global Overrides -------------------------------------------
    local overrideSection=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    overrideSection:SetPoint("TOPLEFT",weaponDefaultHelp,"BOTTOMLEFT",0,-12)
    overrideSection:SetText("Overrides:")

    local rogueOverrideX=82
    local dhOverrideX=400
    local furyOverrideX=680

    local rogueOverrideHelpWidth=285
    local dhOverrideHelpWidth=245
    local furyOverrideHelpWidth=205

    local rogueDaggerCheck=CreateFrame("CheckButton",nil,routingPanel,"UICheckButtonTemplate")
    rogueDaggerCheck:SetPoint("LEFT",overrideSection,"LEFT",rogueOverrideX,0)
    rogueDaggerCheck:SetChecked(WarboundGearRouterDB.routingSettings.prioritizeRogueAgilityDaggers==true)
    local rogueDaggerLabel=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    rogueDaggerLabel:SetPoint("LEFT",rogueDaggerCheck,"RIGHT",2,0)
    rogueDaggerLabel:SetWidth(275)
    rogueDaggerLabel:SetJustifyH("LEFT")
    rogueDaggerLabel:SetText("Prioritize Eligible Rogues for Agility Daggers")
    rogueDaggerCheck:SetScript("OnClick",function(self)
        WarboundGearRouterDB.routingSettings.prioritizeRogueAgilityDaggers=self:GetChecked() and true or false
        RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
        if frame.UpdateGlobalWeaponOverrideHelp then frame.UpdateGlobalWeaponOverrideHelp() end
    end)

    local rogueOverrideHelp=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    rogueOverrideHelp:SetPoint("TOPLEFT",rogueDaggerCheck,"BOTTOMLEFT",28,-2)
    rogueOverrideHelp:SetWidth(rogueOverrideHelpWidth)
    rogueOverrideHelp:SetJustifyH("LEFT")
    rogueOverrideHelp:SetTextColor(.85,.72,.25)

    local dhGlaiveCheck=CreateFrame("CheckButton",nil,routingPanel,"UICheckButtonTemplate")
    dhGlaiveCheck:SetPoint("LEFT",overrideSection,"LEFT",dhOverrideX,0)
    dhGlaiveCheck:SetChecked(WarboundGearRouterDB.routingSettings.preferWarglaivesForDemonHunters==true)
    local dhGlaiveLabel=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    dhGlaiveLabel:SetPoint("LEFT",dhGlaiveCheck,"RIGHT",2,0)
    dhGlaiveLabel:SetWidth(235)
    dhGlaiveLabel:SetJustifyH("LEFT")
    dhGlaiveLabel:SetText("Demon Hunters only get Warglaives")
    dhGlaiveCheck:SetScript("OnClick",function(self)
        WarboundGearRouterDB.routingSettings.preferWarglaivesForDemonHunters=self:GetChecked() and true or false
        RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
        if frame.UpdateGlobalWeaponOverrideHelp then frame.UpdateGlobalWeaponOverrideHelp() end
    end)

    local dhOverrideHelp=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    dhOverrideHelp:SetPoint("TOPLEFT",dhGlaiveCheck,"BOTTOMLEFT",28,-2)
    dhOverrideHelp:SetWidth(dhOverrideHelpWidth)
    dhOverrideHelp:SetJustifyH("LEFT")
    dhOverrideHelp:SetTextColor(.85,.72,.25)

    local furyCheck=CreateFrame("CheckButton",nil,routingPanel,"UICheckButtonTemplate")
    furyCheck:SetPoint("LEFT",overrideSection,"LEFT",furyOverrideX,0)
    furyCheck:SetChecked(WarboundGearRouterDB.routingSettings.preferDual2HForFury==true)
    local furyLabel=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    furyLabel:SetPoint("LEFT",furyCheck,"RIGHT",2,0)
    furyLabel:SetWidth(195)
    furyLabel:SetJustifyH("LEFT")
    furyLabel:SetText("Fury Warriors only get Dual 2H")
    furyCheck:SetScript("OnClick",function(self)
        WarboundGearRouterDB.routingSettings.preferDual2HForFury=self:GetChecked() and true or false
        RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
        if frame.UpdateGlobalWeaponOverrideHelp then frame.UpdateGlobalWeaponOverrideHelp() end
    end)

    local furyOverrideHelp=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    furyOverrideHelp:SetPoint("TOPLEFT",furyCheck,"BOTTOMLEFT",28,-2)
    furyOverrideHelp:SetWidth(furyOverrideHelpWidth)
    furyOverrideHelp:SetJustifyH("LEFT")
    furyOverrideHelp:SetTextColor(.85,.72,.25)

    local function WGRUpdateGlobalWeaponOverrideHelp()
        local dh=WGRGetGlobalWeaponOverrideNames("DH")
        local fury=WGRGetGlobalWeaponOverrideNames("FURY")

        rogueOverrideHelp:SetText("")
        dhOverrideHelp:SetText(#dh>0 and ("Custom overrides: "..table.concat(dh, ", ")) or "")
        furyOverrideHelp:SetText(#fury>0 and ("Custom overrides: "..table.concat(fury, ", ")) or "")
    end
    frame.UpdateGlobalWeaponOverrideHelp=WGRUpdateGlobalWeaponOverrideHelp
    WGRUpdateGlobalWeaponOverrideHelp()

    -- Upgrade Threshold ------------------------------------------
    local thresholdSection=routingPanel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    thresholdSection:SetPoint("TOPLEFT",overrideSection,"BOTTOMLEFT",0,-42)
    thresholdSection:SetText("")

    local thresholdLabel=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    thresholdLabel:SetPoint("TOPLEFT",overrideSection,"BOTTOMLEFT",0,-42)
    thresholdLabel:SetText("Default iLvl Upgrade Threshold:")

    local thresholdDropdown=CreateWGRDropdown(routingPanel,110,22)
    thresholdDropdown:SetPoint("LEFT",thresholdLabel,"RIGHT",14,0)

    local function WGRUpdateGlobalThresholdDropdown()
        thresholdDropdown:SetValueText("+"..tostring(WGRGetGlobalUpgradeThreshold()))
    end

    thresholdDropdown:SetScript("OnClick",function(self)
        MenuUtil.CreateContextMenu(self,function(ownerRegion,rootDescription)
            rootDescription:CreateTitle("Default iLvl Upgrade Threshold")
            for _,threshold in ipairs(WGRThresholdChoices) do
                local value=threshold
                rootDescription:CreateRadio(
                    "+"..tostring(value),
                    function() return WGRGetGlobalUpgradeThreshold()==value end,
                    function()
                        WGRSetGlobalUpgradeThreshold(value)
                        WGRUpdateGlobalThresholdDropdown()
                        if frame.UpdateRoster then frame.UpdateRoster() end
                        RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
                    end
                )
            end

            rootDescription:CreateDivider()

            rootDescription:CreateButton(
                "Custom...",
                function()
                    C_Timer.After(
                        0.05,
                        function()
                            frame.ShowCustomThresholdPanel(
                                nil,
                                self,
                                WGRUpdateGlobalThresholdDropdown
                            )
                        end
                    )
                end
            )
        end)
    end)
    WGRUpdateGlobalThresholdDropdown()

    local resetThresholdsButton=CreateFrame("Button",nil,routingPanel,"UIPanelButtonTemplate")
    resetThresholdsButton:SetPoint("LEFT",thresholdDropdown,"RIGHT",14,0)
    resetThresholdsButton:SetText("Reset All Thresholds to Default")
    WGRSizeResetButtonToText(resetThresholdsButton)
    resetThresholdsButton:SetScript("OnClick",function()
        StaticPopup_Show("WGR_CONFIRM_RESET_CHARACTER_THRESHOLDS",nil,nil,{frame=frame})
    end)

    local resetThresholdsHelp=routingPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    resetThresholdsHelp:SetPoint("TOPLEFT",thresholdLabel,"BOTTOMLEFT",0,-8)
    resetThresholdsHelp:SetTextColor(.68,.68,.68)
    resetThresholdsHelp:SetText("Sets the minimum for a priority upgrade. Smaller upgrades may still be routed.")

    -- APPEARANCE
    local appearanceTitle =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    appearanceTitle:SetPoint(
        "TOPLEFT",
        appearancePanel,
        "TOPLEFT",
        0,
        0
    )
    appearanceTitle:SetText("Appearance")

    local tooltipLabel =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    tooltipLabel:SetPoint(
        "TOPLEFT",
        appearanceTitle,
        "BOTTOMLEFT",
        0,
        -14
    )
    tooltipLabel:SetText("Tooltip Style:")

    local tooltipNames = {
        PROMINENT = "Prominent",
        COMPACT = "Compact",
        MINIMAL = "Minimal",
    }

    local tooltipDropdown =
        CreateWGRDropdown(
            appearancePanel,
            135,
            22
        )

    tooltipDropdown:SetPoint(
        "LEFT",
        tooltipLabel,
        "RIGHT",
        14,
        0
    )

    local tooltipDescriptions = {
        PROMINENT =
            "Shows the full WBGR recommendation prominently in the normal tooltip.",
        COMPACT =
            "Shows a smaller WBGR recommendation in the normal tooltip.",
        MINIMAL =
            "Shows WBGR routing details only with Shift + Hover.",
    }

    local tooltipDescription =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    tooltipDescription:SetPoint(
        "LEFT",
        tooltipDropdown,
        "RIGHT",
        14,
        0
    )
    tooltipDescription:SetWidth(
        390
    )
    tooltipDescription:SetJustifyH(
        "LEFT"
    )
    tooltipDescription:SetTextColor(
        0.68,
        0.68,
        0.68
    )

    local function WGRUpdateTooltipDropdown()
        local mode =
            WarboundGearRouterDB.interface.tooltipStyle
            or "PROMINENT"

        tooltipDropdown:SetValueText(
            tooltipNames[mode]
            or "Prominent"
        )

        tooltipDescription:SetText(
            tooltipDescriptions[mode]
            or tooltipDescriptions.PROMINENT
        )
    end

    tooltipDropdown:SetScript(
        "OnClick",
        function(self)
            MenuUtil.CreateContextMenu(
                self,
                function(ownerRegion, rootDescription)
                    rootDescription:CreateTitle(
                        "Tooltip Style"
                    )

                    for _, mode
                        in ipairs({
                            "PROMINENT",
                            "COMPACT",
                            "MINIMAL",
                        })
                    do
                        local value = mode

                        rootDescription:CreateRadio(
                            tooltipNames[value],
                            function()
                                return
                                    WarboundGearRouterDB.interface.tooltipStyle
                                    == value
                            end,
                            function()
                                WarboundGearRouterDB.interface.tooltipStyle =
                                    value
                                WGRUpdateTooltipDropdown()
                            end
                        )
                    end
                end
            )
        end
    )

    WGRUpdateTooltipDropdown()

    local tooltipTip =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    tooltipTip:SetPoint(
        "TOPLEFT",
        tooltipLabel,
        "BOTTOMLEFT",
        0,
        -14
    )
    tooltipTip:SetWidth(
        650
    )
    tooltipTip:SetJustifyH(
        "LEFT"
    )
    tooltipTip:SetTextColor(
        0.68,
        0.68,
        0.68
    )
    tooltipTip:SetText(
        "Tip: Hold Shift while hovering over gear with a WBGR recommendation to view the full routing details."
    )

    local backgroundOpacityLabel =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    backgroundOpacityLabel:SetPoint(
        "TOPLEFT",
        tooltipTip,
        "BOTTOMLEFT",
        0,
        -24
    )

    backgroundOpacityLabel:SetText(
        "Background Opacity:"
    )

    local backgroundOpacitySlider =
        CreateFrame(
            "Slider",
            nil,
            appearancePanel,
            "OptionsSliderTemplate"
        )

    backgroundOpacitySlider:SetPoint(
        "LEFT",
        backgroundOpacityLabel,
        "RIGHT",
        14,
        0
    )

    backgroundOpacitySlider:SetSize(
        220,
        18
    )

    backgroundOpacitySlider:SetMinMaxValues(
        0,
        100
    )

    backgroundOpacitySlider:SetValueStep(
        1
    )

    backgroundOpacitySlider:SetObeyStepOnDrag(
        true
    )

    backgroundOpacitySlider.Low:SetText(
        "0"
    )

    backgroundOpacitySlider.High:SetText(
        "100"
    )

    backgroundOpacitySlider.Text:SetText(
        ""
    )

    local backgroundOpacityValue =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    backgroundOpacityValue:SetPoint(
        "LEFT",
        backgroundOpacitySlider,
        "RIGHT",
        12,
        0
    )

    local initialOpacity =
        WarboundGearRouterDB.interface.backgroundOpacity
        or 50

    backgroundOpacitySlider:SetValue(
        initialOpacity
    )

    backgroundOpacityValue:SetText(
        tostring(
            math.floor(
                initialOpacity
                + 0.5
            )
        )
        .. "%"
    )

    backgroundOpacitySlider:SetScript(
        "OnValueChanged",
        function(
            self,
            value
        )
            local rounded =
                math.floor(
                    value
                    + 0.5
                )

            WarboundGearRouterDB.interface.backgroundOpacity =
                rounded

            backgroundOpacityValue:SetText(
                tostring(rounded)
                .. "%"
            )

            if frame.WGRApplyBackgroundOpacity then
                frame:WGRApplyBackgroundOpacity()
            end
        end
    )

    local gearOverlaysLabel =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    gearOverlaysLabel:SetPoint(
        "TOPLEFT",
        backgroundOpacityLabel,
        "BOTTOMLEFT",
        0,
        -34
    )

    gearOverlaysLabel:SetText(
        "Gear Overlays:"
    )

    local overlayCheck =
        CreateFrame(
            "CheckButton",
            nil,
            appearancePanel,
            "UICheckButtonTemplate"
        )

    overlayCheck:SetPoint(
        "LEFT",
        gearOverlaysLabel,
        "RIGHT",
        10,
        0
    )

    local overlayLabel =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    overlayLabel:SetPoint(
        "LEFT",
        overlayCheck,
        "RIGHT",
        2,
        0
    )

    overlayLabel:SetText(
        "Enable"
    )

    overlayCheck:SetChecked(
        WarboundGearRouterDB.interface.gearOverlays
        ~= false
    )

    overlayCheck:SetScript(
        "OnClick",
        function(self)
            WarboundGearRouterDB.interface.gearOverlays =
                self:GetChecked()
                and true
                or false

            if WarboundGearRouterDB.interface.gearOverlays then
                RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
            else
                WGRHideAllGearOverlays()
            end
        end
    )

    local refreshOverlayButton =
        CreateFrame(
            "Button",
            nil,
            appearancePanel,
            "UIPanelButtonTemplate"
        )

    refreshOverlayButton:SetSize(
        155,
        22
    )

    refreshOverlayButton:SetPoint(
        "LEFT",
        overlayLabel,
        "RIGHT",
        18,
        0
    )

    refreshOverlayButton:SetText(
        "Refresh Gear Overlays"
    )

    refreshOverlayButton:SetScript(
        "OnClick",
        function()
            if WGRRoutingIsPaused() then
                print(
                    "|cffffff00WBGR routing is paused.|r Resume routing before refreshing overlays."
                )
                return
            end

            RefreshBagnonCleanupOverlays()
                WGRRefreshGearFinderIfOpen()
        end
    )

    -- Gear overlays currently target Bagnon's item buttons. Keep the user's
    -- saved preference intact if Bagnon is unavailable so overlays return
    -- automatically if Bagnon is enabled again later.
    local bagnonAvailable =
        C_AddOns
        and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded(
            "Bagnon"
        )
        or false

    local overlayCompatibilityText =
        appearancePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontDisableSmall"
        )

    overlayCompatibilityText:SetPoint(
        "TOPLEFT",
        gearOverlaysLabel,
        "BOTTOMLEFT",
        0,
        -5
    )

    overlayCompatibilityText:SetText(
        "Requires Bagnon."
    )

    overlayCompatibilityText:SetShown(
        not bagnonAvailable
    )

    if not bagnonAvailable then
        overlayCheck:Disable()
        refreshOverlayButton:Disable()

        overlayLabel:SetTextColor(
            0.50,
            0.50,
            0.50
        )
    end

    local overlayLegend =
        CreateFrame(
            "Frame",
            nil,
            appearancePanel
        )

    overlayLegend:SetPoint(
        "TOPLEFT",
        gearOverlaysLabel,
        "BOTTOMLEFT",
        0,
        bagnonAvailable
            and -8
            or -22
    )

    overlayLegend:SetSize(
        690,
        96
    )

    local function CreateLegendSample(
        parent,
        xOffset,
        yOffset,
        borderR,
        borderG,
        borderB,
        markerType,
        markerR,
        markerG,
        markerB,
        text
    )
        local sample =
            CreateFrame(
                "Frame",
                nil,
                parent,
                "BackdropTemplate"
            )

        sample:SetSize(
            24,
            24
        )

        sample:SetPoint(
            "TOPLEFT",
            parent,
            "TOPLEFT",
            xOffset,
            yOffset
        )

        sample:SetBackdrop({
            bgFile =
                "Interface\\Buttons\\WHITE8X8",
            edgeFile =
                "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })

        sample:SetBackdropColor(
            0.04,
            0.04,
            0.04,
            0.85
        )

        sample:SetBackdropBorderColor(
            borderR,
            borderG,
            borderB,
            1.00
        )

        if markerType == "EXCLAMATION"
            or markerType == "QUESTION"
        then
            local marker =
                sample:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontNormalLarge"
                )

            marker:SetPoint(
                "CENTER",
                sample,
                "CENTER",
                0,
                0
            )

            marker:SetText(
                markerType == "EXCLAMATION"
                and "!"
                or "?"
            )

            marker:SetTextColor(
                markerR,
                markerG,
                markerB
            )
            marker:SetShadowColor(
                0.00,
                0.00,
                0.00,
                1.00
            )
            marker:SetShadowOffset(
                1,
                -1
            )

        elseif markerType == "ARROW" then
            local shaftShadow =
                sample:CreateTexture(
                    nil,
                    "ARTWORK"
                )
            shaftShadow:SetColorTexture(
                0.00, 0.00, 0.00, 0.95
            )
            shaftShadow:SetSize(
                14,
                5
            )
            shaftShadow:SetPoint(
                "RIGHT",
                sample,
                "RIGHT",
                -3,
                -1
            )

            local shaft =
                sample:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            shaft:SetColorTexture(
                markerR,
                markerG,
                markerB,
                1.00
            )

            shaft:SetSize(
                12,
                3
            )

            shaft:SetPoint(
                "RIGHT",
                sample,
                "RIGHT",
                -4,
                0
            )

            local arrowTop =
                sample:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            arrowTop:SetColorTexture(
                markerR,
                markerG,
                markerB,
                1.00
            )

            arrowTop:SetSize(
                8,
                3
            )

            arrowTop:SetPoint(
                "RIGHT",
                shaft,
                "LEFT",
                3,
                2
            )

            arrowTop:SetRotation(
                math.rad(45)
            )

            local arrowBottom =
                sample:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            arrowBottom:SetColorTexture(
                markerR,
                markerG,
                markerB,
                1.00
            )

            arrowBottom:SetSize(
                8,
                3
            )

            arrowBottom:SetPoint(
                "RIGHT",
                shaft,
                "LEFT",
                3,
                -2
            )

            arrowBottom:SetRotation(
                math.rad(-45)
            )

        elseif markerType == "COIN" then
            local markerShadow =
                sample:CreateTexture(
                    nil,
                    "ARTWORK"
                )

            markerShadow:SetTexture(
                "Interface\\MoneyFrame\\UI-GoldIcon"
            )
            markerShadow:SetVertexColor(
                0.00,
                0.00,
                0.00,
                0.95
            )
            markerShadow:SetSize(
                18,
                18
            )
            markerShadow:SetPoint(
                "CENTER",
                sample,
                "CENTER",
                1,
                -1
            )

            local marker =
                sample:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            marker:SetTexture(
                "Interface\\MoneyFrame\\UI-GoldIcon"
            )
            marker:SetSize(
                16,
                16
            )
            marker:SetPoint(
                "CENTER",
                sample,
                "CENTER",
                0,
                0
            )

        elseif markerType == "CHECK" then
            local markerShadow =
                sample:CreateTexture(
                    nil,
                    "ARTWORK"
                )
            markerShadow:SetTexture(
                "Interface\\Buttons\\UI-CheckBox-Check"
            )
            markerShadow:SetVertexColor(
                0.00, 0.00, 0.00, 0.95
            )
            markerShadow:SetSize(
                22,
                22
            )
            markerShadow:SetPoint(
                "CENTER",
                sample,
                "CENTER",
                1,
                -1
            )

            local marker =
                sample:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            marker:SetTexture(
                "Interface\\Buttons\\UI-CheckBox-Check"
            )

            marker:SetVertexColor(
                markerR,
                markerG,
                markerB,
                1.00
            )

            marker:SetSize(
                20,
                20
            )

            marker:SetPoint(
                "CENTER",
                sample,
                "CENTER",
                0,
                0
            )

            marker:SetBlendMode(
                "ADD"
            )
        end

        local label =
            parent:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        label:SetPoint(
            "LEFT",
            sample,
            "RIGHT",
            10,
            0
        )

        label:SetWidth(
            265
        )

        label:SetJustifyH(
            "LEFT"
        )

        label:SetText(
            text
        )
    end

    local currentCharacterLegendTitle =
        overlayLegend:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    currentCharacterLegendTitle:SetPoint(
        "TOPLEFT",
        overlayLegend,
        "TOPLEFT",
        0,
        0
    )
    currentCharacterLegendTitle:SetText(
        "Current Character"
    )

    local outgoingGearLegendTitle =
        overlayLegend:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    outgoingGearLegendTitle:SetPoint(
        "TOPLEFT",
        overlayLegend,
        "TOPLEFT",
        350,
        0
    )
    outgoingGearLegendTitle:SetText(
        "Outgoing Gear"
    )

    CreateLegendSample(
        overlayLegend,
        0,
        -22,
        1.00, 0.10, 0.85,
        nil,
        1.00, 0.20, 0.90,
        "|cffff33ddMagenta|r = Potential Upgrade"
    )

    CreateLegendSample(
        overlayLegend,
        0,
        -50,
        0.10, 1.00, 0.20,
        nil,
        0.10, 1.00, 0.20,
        "|cff33ff55Green Pulse|r = Locate from Gear Finder"
    )

    CreateLegendSample(
        overlayLegend,
        350,
        -22,
        1.00, 0.00, 0.00,
        "EXCLAMATION",
        1.00, 0.00, 0.00,
        "|cffff3333Red|r = Send Onwards"
    )

    CreateLegendSample(
        overlayLegend,
        350,
        -50,
        0.68, 0.68, 0.68,
        "COIN",
        1.00, 0.82, 0.10,
        "|cffaaaaaaGray|r = Sell / Dispose"
    )

    -- INTERFACE
    local interfaceTitle =
        interfacePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    interfaceTitle:SetPoint(
        "TOPLEFT",
        interfacePanel,
        "TOPLEFT",
        0,
        0
    )
    interfaceTitle:SetText("Interface")

    local minimapCheck =
        CreateFrame(
            "CheckButton",
            nil,
            interfacePanel,
            "UICheckButtonTemplate"
        )

    minimapCheck:SetPoint(
        "TOPLEFT",
        interfaceTitle,
        "BOTTOMLEFT",
        -4,
        -10
    )

    local minimapLabel =
        interfacePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    minimapLabel:SetPoint(
        "LEFT",
        minimapCheck,
        "RIGHT",
        2,
        0
    )

    minimapLabel:SetText(
        "Show Minimap Button"
    )

    minimapCheck:SetChecked(
        WarboundGearRouterDB.minimap.shown
        ~= false
    )

    minimapCheck:SetScript(
        "OnClick",
        function(self)
            WarboundGearRouterDB.minimap.shown =
                self:GetChecked()
                and true
                or false

            if WGRMinimapButton then
                WGRMinimapButton:SetShown(
                    WarboundGearRouterDB.minimap.shown
                )
            end
        end
    )

    local mailReminderCheck =
        CreateFrame(
            "CheckButton",
            nil,
            interfacePanel,
            "UICheckButtonTemplate"
        )

    mailReminderCheck:SetPoint(
        "TOPLEFT",
        minimapCheck,
        "BOTTOMLEFT",
        0,
        -8
    )

    local mailReminderLabel =
        interfacePanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    mailReminderLabel:SetPoint(
        "LEFT",
        mailReminderCheck,
        "RIGHT",
        2,
        0
    )

    mailReminderLabel:SetText(
        "Enable Mail Reminder Popups"
    )

    mailReminderCheck:SetChecked(
        WarboundGearRouterDB.interface.mailReminderPopups
        ~= false
    )

    mailReminderCheck:SetScript(
        "OnClick",
        function(self)
            WarboundGearRouterDB.interface.mailReminderPopups =
                self:GetChecked()
                and true
                or false
        end
    )

    WGRShowSettingsTab(
        activeSettingsTab
    )

    -- ========================================================
    -- ABOUT PAGE
    -- ========================================================
    local aboutPage =
        CreateFrame(
            "Frame",
            nil,
            frame
        )

    aboutPage:SetAllPoints(
        mailPage
    )

    aboutPage:Hide()

    frame.aboutPage =
        aboutPage

    local aboutTitle =
        aboutPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    aboutTitle:SetPoint(
        "TOPLEFT",
        aboutPage,
        "TOPLEFT",
        0,
        0
    )

    aboutTitle:SetText(
        "Warbound Gear Router"
    )

    local versionLabel =
        aboutPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    versionLabel:SetPoint(
        "TOPLEFT",
        aboutTitle,
        "BOTTOMLEFT",
        0,
        -10
    )

    versionLabel:SetText(
        "Version"
    )

    local versionValue =
        aboutPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    versionValue:SetPoint(
        "LEFT",
        versionLabel,
        "RIGHT",
        10,
        0
    )

    versionValue:SetText(
        WGRGetAddonMetadata(
            "Version",
            "Unknown"
        )
    )

    local authorLabel =
        aboutPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    authorLabel:SetPoint(
        "TOPLEFT",
        versionLabel,
        "BOTTOMLEFT",
        0,
        -8
    )

    authorLabel:SetText(
        "Author"
    )

    local authorValue =
        aboutPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    authorValue:SetPoint(
        "LEFT",
        authorLabel,
        "RIGHT",
        10,
        0
    )

    authorValue:SetText(
        WGRGetAddonMetadata(
            "Author",
            "Unknown"
        )
    )

    local aboutDescription =
        aboutPage:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    aboutDescription:SetPoint(
        "TOPLEFT",
        authorLabel,
        "BOTTOMLEFT",
        0,
        -18
    )

    aboutDescription:SetPoint(
        "RIGHT",
        aboutPage,
        "RIGHT",
        -6,
        0
    )

    aboutDescription:SetJustifyH(
        "LEFT"
    )

    aboutDescription:SetText(
        "Route, equip, and manage Warbound gear across your characters using item level to recommend upgrades."
    )

    WGRBuildAboutSubtabs(
        aboutPage,
        aboutDescription
    )

    tabMail:SetScript(
        "OnClick",
        function()
            if frame.customWeaponsPanel then
                frame.customWeaponsPanel:Hide()
            end
            WGRShowMainTab(
                "MAIL"
            )
        end
    )

    tabGearFinder:SetScript(
        "OnClick",
        function()
            if frame.customWeaponsPanel then
                frame.customWeaponsPanel:Hide()
            end
            WGRShowMainTab(
                "GEAR_FINDER"
            )
        end
    )

    tabRoster:SetScript(
        "OnClick",
        function()
            if frame.customWeaponsPanel then
                frame.customWeaponsPanel:Hide()
            end
            WGRShowMainTab(
                "ROSTER"
            )
        end
    )

    tabSettings:SetScript(
        "OnClick",
        function()
            if frame.customWeaponsPanel then
                frame.customWeaponsPanel:Hide()
            end
            WGRShowMainTab(
                "SETTINGS"
            )
        end
    )

    tabAbout:SetScript(
        "OnClick",
        function()
            if frame.customWeaponsPanel then
                frame.customWeaponsPanel:Hide()
            end
            WGRShowMainTab(
                "ABOUT"
            )
        end
    )

    if UISpecialFrames then
        local alreadyRegistered =
            false

        for _, frameName
            in ipairs(
                UISpecialFrames
            )
        do
            if frameName
                == "WGRCheckMailFrame"
            then
                alreadyRegistered =
                    true
                break
            end
        end

        if not alreadyRegistered then
            table.insert(
                UISpecialFrames,
                "WGRCheckMailFrame"
            )
        end
    end

    frame:Hide()

    frame:SetScript(
        "OnShow",
        function()
            C_Timer.After(
                0,
                function()
                    if not frame:IsShown() then
                        return
                    end

                    if WGRRoutingIsPaused
                        and WGRRoutingIsPaused()
                    then
                        if WGRRefreshTodoPage then
                            WGRRefreshTodoPage()
                        end
                    elseif WGRMailRefreshCurrentTodoSnapshot then
                        WGRMailRefreshCurrentTodoSnapshot(
                            true
                        )
                    end
                end
            )
        end
    )

    WGRMailTracker.frame =
        frame

    WGRMailUpdateTrackerFrame()

    WGRShowMainTab(
        "MAIL"
    )

    return frame
end

function WGRIsMainWindowShown()
    return
        WGRMailTracker.frame
        and WGRMailTracker.frame:IsShown()
        or false
end

function WGRRefreshRosterIfOpen()
    local perfStart = WGRPerfNow and WGRPerfNow() or 0
    local frame =
        WGRMailTracker.frame

    if not frame
        or not frame:IsShown()
        or not frame.UpdateRoster
    then
        return
    end

    frame.UpdateRoster()

    if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
        WGRPerfRecord(
            "roster_refresh",
            WGRPerfNow() - perfStart
        )
    end
end

function WGRMailShowTracker()
    local frame =
        WGRMailCreateTrackerFrame()

    WGRShowMainTab(
        "MAIL"
    )

    frame:Show()
end

function WGRToggleMainWindow()
    local frame =
        WGRMailCreateTrackerFrame()

    if frame:IsShown() then
        frame:Hide()
    else
        WGRShowMainTab(
            "MAIL"
        )

        frame:Show()
    end
end
