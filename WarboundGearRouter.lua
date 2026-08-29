
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
    "BAG_UPDATE_DELAYED"
)

eventFrame:RegisterEvent(
    "BANKFRAME_OPENED"
)

eventFrame:RegisterEvent(
    "BANKFRAME_CLOSED"
)

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

        elseif event == "BAG_UPDATE_DELAYED" then
            QueueCleanupRefresh()

            C_Timer.After(
                0.10,
                function()
                    if WGRRefreshHeldGearSnapshot then
                        WGRRefreshHeldGearSnapshot(
                            true
                        )
                    end

                    if WGRRefreshWarbandHeldGearSnapshot then
                        WGRRefreshWarbandHeldGearSnapshot()
                    end

                    if WGRRefreshRosterIfOpen then
                        WGRRefreshRosterIfOpen()
                    end
                end
            )

        elseif event == "BANKFRAME_OPENED" then
            QueueCleanupRefresh()

            if WGRRefreshTodoPage then
                WGRRefreshTodoPage()
            end

            C_Timer.After(
                0.35,
                function()
                    if WGRRefreshHeldGearSnapshot then
                        WGRRefreshHeldGearSnapshot(
                            true
                        )
                    end

                    if WGRRefreshWarbandHeldGearSnapshot then
                        WGRRefreshWarbandHeldGearSnapshot()
                    end

                    if WGRRefreshRosterIfOpen then
                        WGRRefreshRosterIfOpen()
                    end
                end
            )

        elseif event == "BANKFRAME_CLOSED" then
            QueueCleanupRefresh()

            if WGRRefreshTodoPage then
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
