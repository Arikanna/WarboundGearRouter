
SLASH_WARBOUNDGEARROUTER1 = "/wbgr"
SLASH_WARBOUNDGEARROUTER2 = "/wgr"

-- ============================================================
-- EVENTS
-- ============================================================

local eventFrame =
    CreateFrame("Frame")

eventFrame:RegisterEvent(
    "PLAYER_ENTERING_WORLD"
)

eventFrame:RegisterEvent(
    "PLAYER_SPECIALIZATION_CHANGED"
)

eventFrame:RegisterEvent(
    "PLAYER_EQUIPMENT_CHANGED"
)

eventFrame:RegisterEvent(
    "MODIFIER_STATE_CHANGED"
)

eventFrame:RegisterEvent(
    "ADDON_LOADED"
)

eventFrame:RegisterEvent(
    "BAG_UPDATE"
)

eventFrame:RegisterEvent(
    "BAG_UPDATE_DELAYED"
)

eventFrame:RegisterEvent(
    "BANKFRAME_OPENED"
)

eventFrame:RegisterEvent(
    "BANKFRAME_CLOSED"
)

-- Coalesce bursts of bag/bank events into one expensive inventory refresh.
-- BAG_UPDATE tells us which storage actually changed; BAG_UPDATE_DELAYED then
-- performs one trailing-edge refresh for only those dirty storage groups.
local inventoryRefreshSerial = 0
local inventoryDirty = {
    bags = false,
    personalBank = false,
    warbandBank = false,
    bagIDs = {},
    personalBankBagIDs = {},
    warbandBagIDs = {},
    unknown = false,
}

-- While paused, bank moves can arrive as separate BAG_UPDATE bursts. Keep a
-- short grace window after PBK/WBK activity so a trailing BAG-only update is
-- treated as the second half of the same deliberate storage movement instead
-- of being mistaken for ordinary loot/bag sorting.
local pausedStorageBoundaryUntil = 0

local function WGRArmPausedStorageBoundary()
    local now = GetTime and GetTime() or 0
    pausedStorageBoundaryUntil = now + 1.25
end

local function WGRPausedStorageBoundaryActive()
    local now = GetTime and GetTime() or 0
    return pausedStorageBoundaryUntil > now
end

local function WGRClassifyBagID(bagID)
    bagID = tonumber(bagID)
    if bagID == nil then
        return "unknown"
    end

    -- Backpack + equipped bag slots.
    if bagID >= 0 and bagID <= 5 then
        return "bags"
    end

    if Enum and Enum.BagIndex then
        for name, enumBagID in pairs(Enum.BagIndex) do
            if enumBagID == bagID and type(name) == "string" then
                if name:find("AccountBankTab", 1, true)
                    or name:find("WarbandBank", 1, true)
                then
                    return "warbandBank"
                end

                if name:find("CharacterBankTab", 1, true) then
                    return "personalBank"
                end
            end
        end
    end

    -- Legacy/fallback personal-bank bag IDs. Unknown IDs remain conservative.
    if bagID >= 6 and bagID <= 11 then
        return "personalBank"
    end

    return "unknown"
end

local function WGRMarkInventoryDirty(bagID)
    if WGRMarkBagnonOverlayBagDirty then
        WGRMarkBagnonOverlayBagDirty(bagID)
    end

    local group = WGRClassifyBagID(bagID)
    if group == "bags" then
        inventoryDirty.bags = true
        local numericBagID = tonumber(bagID)
        if numericBagID ~= nil then
            inventoryDirty.bagIDs[numericBagID] = true
        end
    elseif group == "personalBank" then
        inventoryDirty.personalBank = true
        local numericBagID = tonumber(bagID)
        if numericBagID ~= nil then
            inventoryDirty.personalBankBagIDs[numericBagID] = true
        end
    elseif group == "warbandBank" then
        inventoryDirty.warbandBank = true
        local numericBagID = tonumber(bagID)
        if numericBagID ~= nil then
            inventoryDirty.warbandBagIDs[numericBagID] = true
        end
    else
        inventoryDirty.unknown = true
    end
end

local function WGRTakeInventoryDirtySnapshot(forceAll)
    local dirtyWarbandBagIDs = {}
    for bagID in pairs(inventoryDirty.warbandBagIDs) do
        dirtyWarbandBagIDs[bagID] = true
    end

    local dirtyBagIDs = {}
    for bagID in pairs(inventoryDirty.bagIDs) do
        dirtyBagIDs[bagID] = true
    end

    local dirtyPersonalBankBagIDs = {}
    for bagID in pairs(inventoryDirty.personalBankBagIDs) do
        dirtyPersonalBankBagIDs[bagID] = true
    end

    local dirty = {
        bags = inventoryDirty.bags,
        personalBank = inventoryDirty.personalBank,
        warbandBank = inventoryDirty.warbandBank,
        bagIDs = dirtyBagIDs,
        personalBankBagIDs = dirtyPersonalBankBagIDs,
        warbandBagIDs = dirtyWarbandBagIDs,
        unknown = inventoryDirty.unknown,
    }

    inventoryDirty.bags = false
    inventoryDirty.personalBank = false
    inventoryDirty.warbandBank = false
    inventoryDirty.bagIDs = {}
    inventoryDirty.personalBankBagIDs = {}
    inventoryDirty.warbandBagIDs = {}
    inventoryDirty.unknown = false

    if forceAll or dirty.unknown then
        dirty.bags = true
        dirty.personalBank = true
        dirty.warbandBank = true
        dirty.bagIDs = nil
        dirty.personalBankBagIDs = nil
        dirty.warbandBagIDs = nil
    end

    -- BAG_UPDATE_DELAYED should normally follow one or more BAG_UPDATE events.
    -- If it does not, keep the old conservative behavior rather than risk stale data.
    if not dirty.bags
        and not dirty.personalBank
        and not dirty.warbandBank
    then
        dirty.bags = true
        dirty.personalBank = true
        dirty.warbandBank = true
        dirty.warbandBagIDs = nil
    end

    return dirty
end

local function WGRScheduleInventoryRefresh(delay, forceAll, allowWhenPaused)
    inventoryRefreshSerial =
        inventoryRefreshSerial + 1

    local serial =
        inventoryRefreshSerial

    C_Timer.After(
        delay or 0.30,
        function()
            if serial ~= inventoryRefreshSerial then
                return
            end

            local paused =
                WGRRoutingIsPaused
                and WGRRoutingIsPaused()

            -- Paused mode defers ordinary BAG-only churn. Explicit storage
            -- management/spec/equipment events may opt into lightweight
            -- snapshot/routing maintenance without waking presentation layers.
            if paused and not allowWhenPaused then
                return
            end

            local dirty = WGRTakeInventoryDirtySnapshot(forceAll)
            local perfStart = WGRPerfNow and WGRPerfNow() or 0

            if WGRBeginRoutingEvaluationCache then WGRBeginRoutingEvaluationCache() end

            if WGRRefreshHeldGearSnapshot
                and (dirty.bags or dirty.personalBank)
            then
                WGRRefreshHeldGearSnapshot(
                    dirty.personalBank,
                    dirty.bags,
                    dirty.personalBank,
                    dirty.bagIDs,
                    dirty.personalBankBagIDs
                )
            end

            if dirty.warbandBank
                and WGRRefreshWarbandHeldGearSnapshot
            then
                WGRRefreshWarbandHeldGearSnapshot(
                    dirty.warbandBagIDs
                )
            end

            if (not paused) and WGRRefreshRosterIfOpen then
                WGRRefreshRosterIfOpen()
            end

            if paused and WGRMailRefreshCurrentTodoSnapshot then
                -- Keep the current carried-outgoing To Do snapshot accurate
                -- while paused. PBK/elsewhere routed gear remains future
                -- Gather Routed Gear work.
                WGRMailRefreshCurrentTodoSnapshot(true, true)
            end

            if WGREndRoutingEvaluationCache then WGREndRoutingEvaluationCache() end

            if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
                local detail = string.format(
                    "bags=%s personal=%s warband=%s",
                    dirty.bags and "yes" or "no",
                    dirty.personalBank and "yes" or "no",
                    dirty.warbandBank and "yes" or "no"
                )
                WGRPerfRecord(
                    "inventory_refresh_total",
                    WGRPerfNow() - perfStart,
                    detail
                )
            end
        end
    )
end

function WGRRequestInventoryRefresh(delay, forceAll, allowWhenPaused)
    WGRScheduleInventoryRefresh(delay, forceAll, allowWhenPaused)
end

-- Forward declaration: PLAYER_ENTERING_WORLD can call this before the
-- implementation appears later in the file.
WGRCreateMinimapButton = nil

eventFrame:SetScript(
    "OnEvent",
    function(self, event, unit)

        if event
            == "PLAYER_ENTERING_WORLD"
        then
            -- Fresh login can expose the active spec before equipped
            -- weapon/item data is ready. Keep retrying for a short period
            -- and stop as soon as a valid baseline is captured.
            WGRQueueStartupBaselineCapture()

            InstallTooltipHook()
            InstallBagVisibilityHooks()
            QueueCleanupRefresh()
            QueueStartupOverlayRefreshes()
            WGRCreateMinimapButton()

            C_Timer.After(
                3.25,
                function()
                    if WGRRefreshHeldGearSnapshot then
                        WGRRefreshHeldGearSnapshot(
                            false
                        )
                    end
                end
            )

        elseif event
            ==
            "PLAYER_SPECIALIZATION_CHANGED"
        then
            if not unit
                or unit == "player"
            then
                -- Save only the newly active spec after the switch.
                -- The outgoing spec was already maintained while it
                -- was active through login/equipment-change saves.
                C_Timer.After(
                    0.35,
                    SaveCurrentSpec
                )

                if WGRRoutingIsPaused and WGRRoutingIsPaused() then
                    WGRScheduleInventoryRefresh(0.85, true, true)
                end
            end

        elseif event
            ==
            "PLAYER_EQUIPMENT_CHANGED"
        then
            -- Continuously maintain the baseline for whichever spec is
            -- actually active while this equipment is being worn.
            C_Timer.After(
                0.20,
                SaveCurrentSpec
            )

            C_Timer.After(
                0.75,
                SaveCurrentSpec
            )

            if WGRRoutingIsPaused and WGRRoutingIsPaused() then
                WGRScheduleInventoryRefresh(0.90, true, true)
            end

        elseif event
            ==
            "MODIFIER_STATE_CHANGED"
        then
            if GameTooltip
                and GameTooltip:IsShown()
            then
                GameTooltip.__WGRLineAdded =
                    false

                GameTooltip.__WGRIgnoredItemLink =
                    nil

                tooltipSerial =
                    tooltipSerial + 1

                local owner =
                    GameTooltip:GetOwner()

                -- Gear Finder buttons are virtual item buttons. Re-run their
                -- own tooltip builder so Shift expansion does not clear the
                -- managed state or strand the tooltip until the next hover.
                if owner
                    and owner.__WGRGearFinderButton
                    and owner.WGRShowTooltip
                then
                    owner:WGRShowTooltip()
                -- Retail bank tooltips carry important item context in the
                -- tooltip data itself. Ask Blizzard to rebuild those in place.
                elseif type(GameTooltip.RefreshData)
                    == "function"
                then
                    GameTooltip:RefreshData()
                elseif owner
                    and owner.bag ~= nil
                then
                    GameTooltip:SetOwner(
                        owner,
                        GameTooltip:GetAnchorType()
                    )

                    ProcessTooltip(
                        GameTooltip
                    )
                end
            end

        elseif event == "ADDON_LOADED" then
            InstallBagVisibilityHooks()
            QueueCleanupRefresh()

            C_Timer.After(
                0.50,
                RefreshBagnonCleanupOverlays
            )

        elseif event == "BAG_UPDATE" then
            WGRMarkInventoryDirty(unit)

            if WGRRoutingIsPaused and WGRRoutingIsPaused() then
                local changedGroup = WGRClassifyBagID(unit)
                if changedGroup == "personalBank"
                    or changedGroup == "warbandBank"
                then
                    WGRArmPausedStorageBoundary()
                end
            end

        elseif event == "BAG_UPDATE_DELAYED" then
            local paused =
                WGRRoutingIsPaused
                and WGRRoutingIsPaused()

            if paused then
                local changedGroups = 0
                if inventoryDirty.bags then changedGroups = changedGroups + 1 end
                if inventoryDirty.personalBank then changedGroups = changedGroups + 1 end
                if inventoryDirty.warbandBank then changedGroups = changedGroups + 1 end

                local mailboxOpen = WGRMail and WGRMail.mailboxOpen

                -- Loot and BAG-to-BAG sorting stay deferred while paused. A
                -- PBK/WBK change is deliberate management and arms a short
                -- grace window so a trailing BAG-only event from the same move
                -- is still processed. This avoids intermittent stale To Do
                -- state without waking broad presentation work.
                local storageDirty =
                    inventoryDirty.personalBank
                    or inventoryDirty.warbandBank

                local trailingBoundaryBag =
                    inventoryDirty.bags
                    and WGRPausedStorageBoundaryActive()

                if changedGroups >= 2
                    or storageDirty
                    or trailingBoundaryBag
                    or (inventoryDirty.bags and mailboxOpen)
                then
                    WGRScheduleInventoryRefresh(0.30, false, true)
                end
            else
                -- Active mode keeps the normal overlay/UI behavior.
                QueueCleanupRefresh(true)
                WGRScheduleInventoryRefresh(0.30)
            end

        elseif event == "BANKFRAME_OPENED" then
            QueueCleanupRefresh()

            if (not WGRRoutingIsPaused
                    or not WGRRoutingIsPaused())
                and WGRRefreshTodoPage
            then
                WGRRefreshTodoPage()
            end

            -- Opening a bank can make previously unreadable storage visible,
            -- so do one conservative full refresh here. Subsequent item moves
            -- are storage-aware through BAG_UPDATE.
            WGRScheduleInventoryRefresh(
                0.35,
                true,
                WGRRoutingIsPaused and WGRRoutingIsPaused()
            )

        elseif event == "BANKFRAME_CLOSED" then
            QueueCleanupRefresh()

            if (not WGRRoutingIsPaused
                    or not WGRRoutingIsPaused())
                and WGRRefreshTodoPage
            then
                WGRRefreshTodoPage()
            end
        end
    end
)

InstallTooltipHook()
InstallBagVisibilityHooks()
QueueStartupOverlayRefreshes()


-- ============================================================
-- WGR MINIMAP LAUNCHER
-- ============================================================

local WGRMinimapButton =
    nil

local function WGRAtan2(
    y,
    x
)
    if math.atan2 then
        return math.atan2(
            y,
            x
        )
    end

    if x > 0 then
        return math.atan(
            y / x
        )
    end

    if x < 0
        and y >= 0
    then
        return math.atan(
            y / x
        ) + math.pi
    end

    if x < 0
        and y < 0
    then
        return math.atan(
            y / x
        ) - math.pi
    end

    if x == 0
        and y > 0
    then
        return math.pi / 2
    end

    if x == 0
        and y < 0
    then
        return -math.pi / 2
    end

    return 0
end

local function WGRPositionMinimapButton()
    if not WGRMinimapButton
        or not Minimap
    then
        return
    end

    InitializeDatabase()

    local angle =
        WarboundGearRouterDB.minimap.angle
        or 225

    local radius =
        108

    local radians =
        math.rad(
            angle
        )

    WGRMinimapButton:ClearAllPoints()

    WGRMinimapButton:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(radians)
            * radius,
        math.sin(radians)
            * radius
    )
end

WGRCreateMinimapButton = function()
    if WGRMinimapButton
        or not Minimap
    then
        return
    end

    InitializeDatabase()

    local button =
        CreateFrame(
            "Button",
            "WGRMinimapButton",
            Minimap
        )

    button:SetSize(
        32,
        32
    )

    button:SetFrameStrata(
        "MEDIUM"
    )

    button:SetFrameLevel(
        8
    )

    button:RegisterForClicks(
        "LeftButtonUp"
    )

    button:RegisterForDrag(
        "LeftButton"
    )

    local icon =
        button:CreateTexture(
            nil,
            "ARTWORK"
        )

    icon:SetTexture(
        "Interface\\AddOns\\WarboundGearRouter\\WBGRIcon"
    )

    icon:SetSize(
        32,
        32
    )

    icon:SetPoint(
        "CENTER"
    )

    button.icon =
        icon

    button:SetScript(
        "OnClick",
        function()
            WGRToggleMainWindow()
        end
    )

    button:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(
                self,
                "ANCHOR_LEFT"
            )

            GameTooltip:AddLine(
                "Warbound Gear Router",
                1.00,
                0.82,
                0.00
            )

            local tracked =
                WGRMailGetTrackedList()

            GameTooltip:AddLine(
                string.format(
                    "%d character%s with mail waiting",
                    #tracked,
                    #tracked == 1
                        and ""
                        or "s"
                ),
                1.00,
                1.00,
                1.00
            )

            if #tracked > 0 then
                GameTooltip:AddLine(
                    "Soonest: "
                        .. tracked[1].name
                        .. " - "
                        .. WGRMailFormatRemaining(
                            tracked[1].remaining
                        ),
                    1.00,
                    0.82,
                    0.20
                )
            end

            GameTooltip:AddLine(
                "Left-click: Open WBGR",
                0.75,
                0.75,
                0.75
            )

            GameTooltip:AddLine(
                "Drag: Move button",
                0.75,
                0.75,
                0.75
            )

            GameTooltip:Show()
        end
    )

    button:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    button:SetScript(
        "OnDragStart",
        function(self)
            self:SetScript(
                "OnUpdate",
                function()
                    local minimapX,
                          minimapY =
                        Minimap:GetCenter()

                    local cursorX,
                          cursorY =
                        GetCursorPosition()

                    local scale =
                        UIParent:GetEffectiveScale()

                    cursorX =
                        cursorX / scale

                    cursorY =
                        cursorY / scale

                    local angle =
                        math.deg(
                            WGRAtan2(
                                cursorY
                                    - minimapY,
                                cursorX
                                    - minimapX
                            )
                        )

                    WarboundGearRouterDB.minimap.angle =
                        angle

                    WGRPositionMinimapButton()
                end
            )
        end
    )

    button:SetScript(
        "OnDragStop",
        function(self)
            self:SetScript(
                "OnUpdate",
                nil
            )

            WGRPositionMinimapButton()
        end
    )

    WGRMinimapButton =
        button

    WGRPositionMinimapButton()

    button:SetShown(
        WarboundGearRouterDB.minimap.shown
            ~= false
    )
end
