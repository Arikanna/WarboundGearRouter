-- Tooltip rendering, Shift alternatives, hover refresh, and tooltip hooks.

-- ============================================================
-- TOOLTIP
-- ============================================================

tooltipSerial = 0

local function IsWarbankTooltip(tooltip)
    if not tooltip then
        return false
    end

    local owner =
        tooltip:GetOwner()

    if owner then
        local bag =
            owner.bag

        -- Retail Warband Bank bag IDs are account-bank containers.
        if type(bag) == "number"
            and bag >= 12
            and bag <= 16
        then
            return true
        end
    end

    return false
end

-- ============================================================
local HideWarbankTakeOverlay
local ShowWarbankTakeOverlay

-- CURRENT BEST / GOLD EQUIP STATE
--
-- GOLD is only for an immediately-equippable item whose normal WGR
-- routing recommendation belongs to the currently logged-in character.
-- It never overrides RED SEND TO; an item routed to another character is not
-- eligible for GOLD. In the Warbank, GOLD/ORANGE best-item states supersede MAGENTA.
-- ============================================================

local WGRGoldWinners = {}
local WGRGoldLocationKeys = {}
local WGRTiedBestLocationKeys = {}

local function WGRGoldLocationKey(
    bagID,
    slotID
)
    if type(bagID) ~= "number"
        or type(slotID) ~= "number"
    then
        return nil
    end

    return
        tostring(bagID)
        .. ":"
        .. tostring(slotID)
end

local function WGRIsGoldTooltip(
    tooltip
)
    if not tooltip
        or type(tooltip.GetOwner) ~= "function"
    then
        return false
    end

    local owner =
        tooltip:GetOwner()

    if not owner then
        return false
    end

    local bagID =
        owner.bag

    local slotID =
        owner.GetID
        and owner:GetID()
        or nil

    local key =
        WGRGoldLocationKey(
            bagID,
            slotID
        )

    return key
        and WGRGoldLocationKeys[key] == true
        or false
end

local function WGRIsTiedBestTooltip(
    tooltip
)
    if not tooltip
        or type(tooltip.GetOwner) ~= "function"
    then
        return false
    end

    local owner =
        tooltip:GetOwner()

    if not owner then
        return false
    end

    local bagID =
        owner.bag

    local slotID =
        owner.GetID
        and owner:GetID()
        or nil

    local key =
        WGRGoldLocationKey(
            bagID,
            slotID
        )

    return key
        and WGRTiedBestLocationKeys[key] == true
        or false
end



-- Shared Unique-Equipped replacement logic for routing and Gear Finder.
function WGRGetUniqueEquippedSameItemLevel(characterName, character, itemLink, slotIDs)
    if not itemLink or type(slotIDs) ~= "table" then return nil end
    if not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return nil end

    local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
    if not ok or not data or not data.lines then return nil end
    if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end

    local localizedUnique = _G.ITEM_UNIQUE_EQUIPPABLE or _G.ITEM_UNIQUE_EQUIP or "Unique-Equipped"
    local uniqueEquipped = false

    for _, line in ipairs(data.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
        for _, value in ipairs({ line.leftText, line.rightText }) do
            if value then
                local clean = tostring(value):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                if clean:find("Unique%-Equipped")
                    or (localizedUnique and clean:find(tostring(localizedUnique), 1, true))
                then
                    uniqueEquipped = true
                    break
                end
            end
        end
        if uniqueEquipped then break end
    end

    if not uniqueEquipped then return nil end

    local incomingInfo = GetInstantItemInfo(itemLink)
    local incomingID = incomingInfo and tonumber(incomingInfo.itemID)
        or tonumber(tostring(itemLink):match("item:(%d+)"))
    if not incomingID then return nil end

    local currentName = UnitName("player")
    local isCurrentCharacter = currentName and characterName
        and string.lower(currentName) == string.lower(characterName)

    local bestSameLevel = nil
    for _, slotID in ipairs(slotIDs) do
        local equippedLink = nil
        if isCurrentCharacter then
            equippedLink = GetInventoryItemLink("player", slotID)
        end
        if not equippedLink then
            equippedLink = GetStoredItem(character, slotID)
        end

        if equippedLink then
            local equippedInfo = GetInstantItemInfo(equippedLink)
            local equippedID = equippedInfo and tonumber(equippedInfo.itemID)
                or tonumber(tostring(equippedLink):match("item:(%d+)"))
            if equippedID == incomingID then
                local level = tonumber(GetItemLevel(equippedLink)) or 0
                if level > 0 and (bestSameLevel == nil or level > bestSameLevel) then
                    bestSameLevel = level
                end
            end
        end
    end

    return bestSameLevel
end

local function FormatTooltipRecommendation(result, tooltip, displayContext)
    if not result then return nil end

    local currentCharacter = UnitName("player")
    local isCurrentCharacter = result.name and currentCharacter
        and string.lower(result.name) == string.lower(currentCharacter)

    -- A shared Warband Bank item is assigned to this character, but it is
    -- not physically "here" yet. Reserve HOLD HERE for Bags/PBK (or legacy
    -- contexts where no source is available); WBK should remain HOLD ON.
    local source = displayContext and displayContext.source
    local isSharedWarbandSource = source == "WARBAND_BANK"
    local isHeldHere = isCurrentCharacter and not isSharedWarbandSource

    if result.kind == "upgrade" then
        local averageSuffix =
            result.weaponAverage
            and " - weap avg"
            or result.weaponOverAverage
            and " - over weap avg"
            or ""

        if isCurrentCharacter then
            return string.format(
                "POTENTIAL UPGRADE  (+%d ilvl%s)",
                result.upgrade,
                averageSuffix
            ),
                1.00, 0.35, 0.82
        end
        return string.format(
            "SEND TO: %s  (+%d ilvl%s)",
            result.name,
            result.upgrade,
            averageSuffix
        ),
            0.20, 1.00, 0.20
    end

    if result.kind == "future_upgrade" then
        local averageSuffix =
            result.weaponAverage
            and " - weap avg"
            or result.weaponOverAverage
            and " - over weap avg"
            or ""

        -- Future-level gear is storage, not an actionable current upgrade.
        -- If it is already on the intended character, present it with the
        -- same HOLD semantics as other holder gear rather than magenta.
        if isHeldHere then
            return string.format(
                "HOLD HERE  (LEVEL %d, +%d ilvl%s)",
                result.requiredLevel,
                result.upgrade,
                averageSuffix
            ),
                0.20, 1.00, 0.20
        end
        return string.format(
            "HOLD ON: %s  (LEVEL %d, +%d ilvl%s)",
            result.name,
            result.requiredLevel,
            result.upgrade,
            averageSuffix
        ),
            0.20, 1.00, 0.20
    end

    if result.kind == "holder" then
        if isHeldHere then
            return "HOLD HERE", 0.20, 1.00, 0.20
        end
        return string.format("HOLD ON: %s", result.name), 0.20, 1.00, 0.20
    end

    if result.kind == "unresolved" then
        return "WBGR: ROUTING DATA INCOMPLETE", 1.00, 0.75, 0.20
    end

    if result.kind == "unknown" then
        return string.format("WBGR: CHECK %s", tostring(result.name or "ROUTING")),
            1.00, 0.75, 0.20
    end

    if result.kind == "sell" or result.kind == "no_current_upgrade" then
        return "NO ROUTING UPGRADE", 0.72, 0.72, 0.72
    end

    return nil
end

local function AddWGRLineToTooltip(
    tooltip,
    itemLink,
    result,
    serial,
    alternatives,
    displayContext
)
    InitializeDatabase()

    local tooltipStyle =
        WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.tooltipStyle
        or "PROMINENT"

    local shiftDown =
        IsShiftKeyDown
        and IsShiftKeyDown()

    if tooltipStyle == "MINIMAL"
        and not shiftDown
    then
        return
    end


    if serial ~= tooltipSerial then
        return
    end

    if not tooltip
        or not tooltip:IsShown()
    then
        return
    end

    local _, currentLink =
        tooltip:GetItem()

    if currentLink ~= itemLink then
        return
    end

    if tooltip.__WGRLineAdded then
        return
    end

    local text, r, g, b =
        FormatTooltipRecommendation(
            result,
            tooltip,
            displayContext
        )

    if not text then
        return
    end

    tooltip.__WGRLineAdded = true

        if tooltipStyle == "COMPACT"
        and not shiftDown
    then
        if result
            and result.name
        then
            if result.kind == "upgrade"
                and (
                    displayContext
                    and displayContext.classification == "COMPARE"
                    or WGRIsTiedBestTooltip(
                        tooltip
                    )
                )
            then
                tooltip:AddLine(
                    "|cffff9900WBGR: TIED BEST ILVL: COMPARE|r",
                    1.00,
                    0.60,
                    0.00
                )
            elseif result.kind == "upgrade"
                and (
                    displayContext
                    and displayContext.classification == "BEST"
                    or WGRIsGoldTooltip(
                        tooltip
                    )
                )
            then
                tooltip:AddLine(
                    "|cfffff273WBGR: CURRENT BEST: EQUIP NOW|r",
                    1.00,
                    0.82,
                    0.00
                )
            else
                local verb =
                    result.kind == "holder"
                    and "HOLD ON"
                    or "SEND TO"

                tooltip:AddLine(
                    "|cff00ff00WBGR:|r "
                    .. verb
                    .. " "
                    .. tostring(result.name),
                    1.00,
                    1.00,
                    1.00
                )
            end
        end

        tooltip:Show()

        return
    end

tooltip:AddLine(" ")

    tooltip:AddLine(
        "========== WBGR ==========",
        1.00,
        0.82,
        0.00
    )

    tooltip:AddLine(
        text,
        r,
        g,
        b
    )

    if IsShiftKeyDown() then
        tooltip:AddLine(" ")

        if alternatives and #alternatives > 0 then
            tooltip:AddLine(
                "Other options:",
                1.00,
                0.82,
                0.00
            )

            for _, option in ipairs(alternatives) do
                if option.kind == "upgrade" then
                    local belowThreshold =
                        option.meetsThreshold == false

                    tooltip:AddLine(
                        string.format(
                            belowThreshold
                            and "%s  (+%d ilvl, below threshold)"
                            or "%s  (+%d ilvl)",
                            option.name,
                            option.upgrade
                        ),
                        belowThreshold and 1.00 or 0.20,
                        belowThreshold and 0.82 or 1.00,
                        0.20
                    )
                elseif option.kind == "holder" then
                    tooltip:AddLine(
                        string.format(
                            "%s  (Hold)",
                            option.name
                        ),
                        0.20,
                        1.00,
                        0.20
                    )
                elseif option.kind == "unresolved" then
                    tooltip:AddLine(
                        string.format(
                            "%s  (Holder unresolved)",
                            option.name
                        ),
                        1.00,
                        0.55,
                        0.10
                    )
                elseif option.kind == "unknown" then
                    tooltip:AddLine(
                        string.format(
                            "%s  (Unable to evaluate)",
                            option.name
                        ),
                        1.00,
                        0.55,
                        0.10
                    )
                end
            end
        else
            tooltip:AddLine(
                "No other upgrades",
                0.75,
                0.75,
                0.75
            )
        end
    end

    tooltip:AddLine(
        "=========================",
        1.00,
        0.82,
        0.00
    )

    tooltip:Show()
end

local function WGRRoutingComparisonProviderForJewelry(itemLink, equipLoc, globalSlots)
    local isTrinket = equipLoc == "INVTYPE_TRINKET"
    local isRing = equipLoc == "INVTYPE_FINGER"

    return function(characterName, character)
        if isTrinket or isRing then
            local sameUniqueLevel = WGRGetUniqueEquippedSameItemLevel(
                characterName,
                character,
                itemLink,
                globalSlots
            )

            if sameUniqueLevel then
                return sameUniqueLevel, "known"
            end
        end

        if isTrinket then
            return WGRGetTrinketComparisonLevelForMode(
                characterName,
                character,
                itemLink
            )
        end

        return GetComparisonForSlots(character, globalSlots)
    end
end

local function BuildTooltipRecommendation(
    itemLink,
    callback,
    primaryOnly,
    skipEquippedPreload
)
    local resolved = false

    local function Resolve(
        result,
        alternatives
    )
        if resolved then
            return
        end

        resolved = true

        if callback then
            callback(
                result,
                alternatives
            )
        end
    end

    local function RunWithEquippedData(
        priorityList,
        slotIDs,
        readyCallback
    )
        if skipEquippedPreload then
            readyCallback()
            return
        end

        PreloadItems(
            priorityList,
            slotIDs,
            readyCallback,
            true
        )
    end

    local hoveredItem =
        CreateItemObject(itemLink)

    if not hoveredItem then
        Resolve(nil)
        return
    end

    hoveredItem:ContinueOnItemLoad(
        function()

        local itemName,
              returnedLink,
              itemQuality,
              baseItemLevel,
              itemMinLevel,
              itemType,
              itemSubType,
              stackCount,
              equipLoc =
            C_Item.GetItemInfo(itemLink)

        if not itemName then
            Resolve(nil)
            return
        end

        local newItemLevel =
            GetItemLevel(itemLink)

        if not newItemLevel then
            Resolve(nil)
            return
        end

        -- Armor
        local armorSlotID =
            WGRArmorEquipSlots[equipLoc]

        if armorSlotID then
            local armorType =
                itemSubType

            if not GetArmorPriorityList(armorType) then
                Resolve(nil)
                return
            end

            RunWithEquippedData(
                GetArmorPriorityList(armorType),
                { armorSlotID },
                function()
                    local recommendation =
                        BuildSimpleRecommendation(
                            newItemLevel,
                            itemMinLevel,
                            GetArmorPriorityList(armorType),
                            { armorSlotID }
                        )

                    if primaryOnly then
                        Resolve(recommendation)
                    else
                        Resolve(
                            recommendation,
                            BuildSimpleAlternatives(
                                newItemLevel,
                                itemMinLevel,
                                GetArmorPriorityList(armorType),
                                { armorSlotID },
                                recommendation
                            )
                        )
                    end
                end
            )

            return
        end

        -- Neck / cloak / rings / trinkets
        local globalSlots =
            WGRGlobalEquipSlots[equipLoc]

        if globalSlots then
            local isTrinket =
                equipLoc == "INVTYPE_TRINKET"

            local priorityList =
                isTrinket
                and WGRGetTrinketRoutingPriority(
                    itemLink
                )
                or GetActiveRoutingPriority()

            local comparisonProvider =
                WGRRoutingComparisonProviderForJewelry(
                    itemLink,
                    equipLoc,
                    globalSlots
                )

            RunWithEquippedData(
                priorityList,
                globalSlots,
                function()
                    local recommendation =
                        BuildSimpleRecommendation(
                            newItemLevel,
                            itemMinLevel,
                            priorityList,
                            globalSlots,
                            comparisonProvider
                        )

                    if primaryOnly then
                        Resolve(recommendation)
                    else
                        Resolve(
                            recommendation,
                            BuildSimpleAlternatives(
                                newItemLevel,
                                itemMinLevel,
                                priorityList,
                                globalSlots,
                                recommendation,
                                comparisonProvider
                            )
                        )
                    end
                end
            )

            return
        end

        -- Caster off-hand / shield
        if WGROffhandEquipLocs[equipLoc] then
            RunWithEquippedData(
                GetActiveRoutingPriority(),
                { 16, 17 },
                function()
                    local recommendation =
                        BuildOffhandRecommendation(
                            itemLink,
                            newItemLevel,
                            itemMinLevel
                        )

                    if primaryOnly then
                        Resolve(recommendation)
                    else
                        Resolve(
                            recommendation,
                            BuildOffhandAlternatives(
                                itemLink,
                                newItemLevel,
                                itemMinLevel,
                                recommendation
                            )
                        )
                    end
                end
            )

            return
        end

        -- Weapon
        if IsSupportedWeapon(itemLink) then
            RunWithEquippedData(
                GetActiveRoutingPriority(),
                { 16, 17 },
                function()
                    local recommendation =
                        BuildWeaponRecommendation(
                            itemLink,
                            newItemLevel,
                            itemMinLevel
                        )

                    if primaryOnly then
                        Resolve(recommendation)
                    else
                        Resolve(
                            recommendation,
                            BuildWeaponAlternatives(
                                itemLink,
                                newItemLevel,
                                itemMinLevel,
                                recommendation
                            )
                        )
                    end
                end
            )

            return
        end

        -- Transferable items that are not supported equipment
        -- (recipes, consumables, misc. BoEs, etc.) are simply
        -- not WGR-routing candidates.
        Resolve(nil)
    end)
end


-- ============================================================
-- BAGNON MISPLACED-ITEM OVERLAYS
--
-- Verified Bagnon mapping on this setup:
--   button.bag     = actual container/bag ID
--   button:GetID() = actual slot within that bag
--
-- Only visible Bagnon buttons belonging to the CURRENT character
-- are considered. Warband/account-bank containers are excluded.
-- ============================================================

local cleanupGeneration = 0
local cleanupRefreshPending = false

function WGRBuildLoadedItemRecommendation(
    itemLink
)
    if not itemLink then
        return nil, "invalid"
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

    if not itemName
        or not equipLoc
    then
        return nil, "not_loaded"
    end

    local newItemLevel =
        GetItemLevel(
            itemLink
        )

    if not newItemLevel then
        return nil, "not_loaded"
    end

    local armorSlotID =
        WGRArmorEquipSlots[
            equipLoc
        ]

    if armorSlotID then
        local priorityList =
            GetArmorPriorityList(
                itemSubType
            )

        if not priorityList then
            return nil, "unsupported"
        end

        return
            BuildSimpleRecommendation(
                newItemLevel,
                itemMinLevel,
                priorityList,
                { armorSlotID }
            ),
            "ready"
    end

    local globalSlots =
        WGRGlobalEquipSlots[
            equipLoc
        ]

    if globalSlots then
        local isTrinket =
            equipLoc == "INVTYPE_TRINKET"

        local priorityList =
            isTrinket
            and WGRGetTrinketRoutingPriority(
                itemLink
            )
            or GetActiveRoutingPriority()

        local comparisonProvider =
                WGRRoutingComparisonProviderForJewelry(
                    itemLink,
                    equipLoc,
                    globalSlots
                )

        return
            BuildSimpleRecommendation(
                newItemLevel,
                itemMinLevel,
                priorityList,
                globalSlots,
                comparisonProvider
            ),
            "ready"
    end

    if WGROffhandEquipLocs[
        equipLoc
    ] then
        return
            BuildOffhandRecommendation(
                itemLink,
                newItemLevel,
                itemMinLevel
            ),
            "ready"
    end

    if IsSupportedWeapon(
        itemLink
    ) then
        return
            BuildWeaponRecommendation(
                itemLink,
                newItemLevel,
                itemMinLevel
            ),
            "ready"
    end

    return nil, "unsupported"
end


function WGRBuildItemRecommendation(
    itemLink,
    callback,
    equippedDataPreloaded
)
    return
        BuildTooltipRecommendation(
            itemLink,
            callback,
            true,
            equippedDataPreloaded == true
        )
end


local function EnsureCleanupOverlay(button)
    InitializeDatabase()

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        return nil
    end

    if not button then
        return nil
    end

    if button.__WGRCleanupOverlay then
        return button.__WGRCleanupOverlay
    end

    local overlay =
        CreateFrame(
            "Frame",
            nil,
            button
        )

    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(
        button:GetFrameLevel() + 20
    )
    overlay:EnableMouse(false)

    local thickness = 3

    local function MakeEdge()
        local edge =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        edge:SetColorTexture(
            1.00,
            0.10,
            0.10,
            0.98
        )

        return edge
    end

    local top = MakeEdge()
    top:SetPoint(
        "TOPLEFT",
        overlay,
        "TOPLEFT"
    )
    top:SetPoint(
        "TOPRIGHT",
        overlay,
        "TOPRIGHT"
    )
    top:SetHeight(thickness)

    local bottom = MakeEdge()
    bottom:SetPoint(
        "BOTTOMLEFT",
        overlay,
        "BOTTOMLEFT"
    )
    bottom:SetPoint(
        "BOTTOMRIGHT",
        overlay,
        "BOTTOMRIGHT"
    )
    bottom:SetHeight(thickness)

    local left = MakeEdge()
    left:SetPoint(
        "TOPLEFT",
        overlay,
        "TOPLEFT"
    )
    left:SetPoint(
        "BOTTOMLEFT",
        overlay,
        "BOTTOMLEFT"
    )
    left:SetWidth(thickness)

    local right = MakeEdge()
    right:SetPoint(
        "TOPRIGHT",
        overlay,
        "TOPRIGHT"
    )
    right:SetPoint(
        "BOTTOMRIGHT",
        overlay,
        "BOTTOMRIGHT"
    )
    right:SetWidth(thickness)

    local marker =
        overlay:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )
    marker:SetScale(1.12)

    marker:SetPoint(
        "RIGHT",
        overlay,
        "RIGHT",
        -6,
        0
    )

    marker:SetText("!")
    marker:SetTextColor(
        1.00,
        0.00,
        0.00
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

    overlay.destination = nil
    overlay:Hide()

    button.__WGRCleanupOverlay =
        overlay

    return overlay
end

local function GetDisposeOverlay(
    button
)
    InitializeDatabase()

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        return nil
    end

    if not button then
        return nil
    end

    if not button.WGRDisposeOverlay then
        local overlay =
            CreateFrame(
                "Frame",
                nil,
                button
            )

        overlay:SetAllPoints(button)
        overlay:SetFrameLevel(
            button:GetFrameLevel() + 24
        )
        overlay:EnableMouse(false)

        local fill =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        fill:SetAllPoints(overlay)
        fill:SetColorTexture(
            0.20,
            0.20,
            0.20,
            0.40
        )

        local thickness = 5

        local function MakeEdge()
            local edge =
                overlay:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            edge:SetColorTexture(
                0.88,
                0.88,
                0.88,
                1.00
            )

            return edge
        end

        local top = MakeEdge()
        top:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        top:SetHeight(thickness)

        local bottom = MakeEdge()
        bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        bottom:SetHeight(thickness)

        local left = MakeEdge()
        left:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        left:SetWidth(thickness)

        local right = MakeEdge()
        right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        right:SetWidth(thickness)

        -- Use Blizzard's native gold-coin texture rather than a currency
        -- glyph so the marker is language/region neutral.
        local coinShadow =
            overlay:CreateTexture(
                nil,
                "ARTWORK"
            )

        coinShadow:SetTexture(
            "Interface\\MoneyFrame\\UI-GoldIcon"
        )
        coinShadow:SetVertexColor(
            0.00,
            0.00,
            0.00,
            0.95
        )
        coinShadow:SetSize(
            17,
            17
        )
        coinShadow:SetPoint(
            "RIGHT",
            overlay,
            "RIGHT",
            -2,
            -1
        )

        local coin =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        coin:SetTexture(
            "Interface\\MoneyFrame\\UI-GoldIcon"
        )
        coin:SetSize(
            15,
            15
        )
        coin:SetPoint(
            "RIGHT",
            overlay,
            "RIGHT",
            -3,
            0
        )

        overlay:Hide()

        button.WGRDisposeOverlay =
            overlay
    end

    return button.WGRDisposeOverlay
end

local function HideDisposeOverlay(
    button
)
    if button
        and button.WGRDisposeOverlay
    then
        button.WGRDisposeOverlay:Hide()
    end
end

local function ShowDisposeOverlay(
    button
)
    local overlay =
        GetDisposeOverlay(
            button
        )

    if overlay then
        overlay:Show()
    end
end

function GetGoldEquipOverlay(
    button
)
    InitializeDatabase()

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        return nil
    end

    if not button then
        return nil
    end

    if not button.WGRGoldEquipOverlay then
        local overlay =
            CreateFrame(
                "Frame",
                nil,
                button
            )

        overlay:SetAllPoints(button)
        overlay:SetFrameLevel(
            button:GetFrameLevel() + 23
        )
        overlay:EnableMouse(false)

        local fill =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        fill:SetAllPoints(overlay)
        fill:SetColorTexture(
            1.00,
            0.85,
            0.20,
            0.24
        )

        local thickness = 4

        local function MakeEdge()
            local edge =
                overlay:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            edge:SetColorTexture(
                1.00,
                0.95,
                0.45,
                1.00
            )

            return edge
        end

        local top = MakeEdge()
        top:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        top:SetHeight(thickness)

        local bottom = MakeEdge()
        bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        bottom:SetHeight(thickness)

        local left = MakeEdge()
        left:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        left:SetWidth(thickness)

        local right = MakeEdge()
        right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        right:SetWidth(thickness)

        -- Use WoW's built-in checkbox check texture so the marker
        -- reads as a real checkmark at bag-icon size.
        local marker =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        marker:SetTexture(
            "Interface\\Buttons\\UI-CheckBox-Check"
        )

        marker:SetVertexColor(
            0.20,
            1.00,
            0.20,
            1.00
        )

        marker:SetSize(
            20,
            20
        )

        marker:SetPoint(
            "RIGHT",
            overlay,
            "RIGHT",
            1,
            0
        )

        marker:SetBlendMode(
            "ADD"
        )

        local markerShadow =
            overlay:CreateTexture(
                nil,
                "ARTWORK"
            )

        markerShadow:SetTexture(
            "Interface\\Buttons\\UI-CheckBox-Check"
        )
        markerShadow:SetVertexColor(
            0.00,
            0.00,
            0.00,
            0.95
        )
        markerShadow:SetSize(
            22,
            22
        )
        markerShadow:SetPoint(
            "RIGHT",
            overlay,
            "RIGHT",
            2,
            -1
        )

        overlay:Hide()

        button.WGRGoldEquipOverlay =
            overlay
    end

    return button.WGRGoldEquipOverlay
end

function GetTiedBestOverlay(
    button
)
    InitializeDatabase()

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        return nil
    end

    if not button then
        return nil
    end

    if not button.WGRTiedBestOverlay then
        local overlay =
            CreateFrame(
                "Frame",
                nil,
                button
            )

        overlay:SetAllPoints(button)
        overlay:SetFrameLevel(
            button:GetFrameLevel() + 22
        )
        overlay:EnableMouse(false)

        local fill =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        fill:SetAllPoints(overlay)
        fill:SetColorTexture(
            1.00,
            0.48,
            0.00,
            0.24
        )

        local thickness = 4

        local function MakeEdge()
            local edge =
                overlay:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            edge:SetColorTexture(
                1.00,
                0.60,
                0.00,
                1.00
            )

            return edge
        end

        local top = MakeEdge()
        top:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        top:SetHeight(thickness)

        local bottom = MakeEdge()
        bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        bottom:SetHeight(thickness)

        local left = MakeEdge()
        left:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        left:SetWidth(thickness)

        local right = MakeEdge()
        right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        right:SetWidth(thickness)

        local marker =
            overlay:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormalLarge"
            )

        marker:SetPoint(
            "RIGHT",
            overlay,
            "RIGHT",
            -4,
            0
        )
        marker:SetText("?")
        marker:SetTextColor(
            0.20,
            1.00,
            0.20
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

        overlay:Hide()
        button.WGRTiedBestOverlay = overlay
    end

    return button.WGRTiedBestOverlay
end

function HideTiedBestOverlay(
    button
)
    if button
        and button.WGRTiedBestOverlay
    then
        button.WGRTiedBestOverlay:Hide()
    end
end

function ShowTiedBestOverlay(
    button
)
    HideWarbankTakeOverlay(
        button
    )

    local overlay =
        GetTiedBestOverlay(
            button
        )

    if overlay then
        overlay:Show()
    end
end

function HideGoldEquipOverlay(
    button
)
    if button
        and button.WGRGoldEquipOverlay
    then
        button.WGRGoldEquipOverlay:Hide()
    end
end

function ShowGoldEquipOverlay(
    button
)
    HideWarbankTakeOverlay(
        button
    )

    local overlay =
        GetGoldEquipOverlay(
            button
        )

    if overlay then
        overlay:Show()
    end
end

local function WGRGetGoldGroupForItem(
    itemLink
)
    local info =
        GetInstantItemInfo(
            itemLink
        )

    if not info then
        return nil
    end

    local equipLoc =
        info.equipLoc

    local armorSlotID =
        WGRArmorEquipSlots[
            equipLoc
        ]

    if armorSlotID then
        return
            "ARMOR:"
            .. tostring(
                armorSlotID
            )
    end

    if equipLoc == "INVTYPE_NECK" then
        return "NECK"
    end

    if equipLoc == "INVTYPE_CLOAK" then
        return "CLOAK"
    end

    -- Sequential handling: only one ring/trinket is GOLD at a time.
    -- After it is equipped, the rescan can select the next winner.
    if equipLoc == "INVTYPE_FINGER" then
        return "RING"
    end

    if equipLoc == "INVTYPE_TRINKET" then
        return "TRINKET"
    end

    -- Main-hand and off-hand components are separate groups, allowing
    -- a 1H + Shield / caster Off-Hand pair to be GOLD simultaneously.
    if WGROffhandEquipLocs[
        equipLoc
    ] then
        return "OFFHAND"
    end

    -- Sequential handling for dual-wield: recommend one weapon first.
    if IsSupportedWeapon(
        itemLink
    ) then
        return "WEAPON"
    end

    return nil
end

local function WGRResetGoldWinners()
    WGRGoldWinners = {}
    WGRGoldLocationKeys = {}
    WGRTiedBestLocationKeys = {}
    WGRGoldFinalizeSerial =
        (WGRGoldFinalizeSerial or 0)
        + 1
end

local function WGRGoldBaselineSetupScore(
    baseline
)
    if not baseline
        or not baseline.weaponConfig
    then
        return nil
    end

    local config =
        baseline.weaponConfig

    local main =
        tonumber(
            baseline.mainHandLevel
        )
        or 0

    local off =
        tonumber(
            baseline.offHandLevel
        )
        or 0

    if config == "RANGED"
        or config == "TWO_HAND"
    then
        if main > 0 then
            return main
        end

        return nil
    end

    if config == "DUAL_1H"
        or config == "DUAL_2H"
        or config == "ONE_HAND_PLUS_SHIELD"
        or config == "ONE_HAND_PLUS_OFFHAND"
    then
        if main > 0
            and off > 0
        then
            return
                (
                    main
                    + off
                )
                / 2
        end

        -- Do not let an incomplete setup block a legitimate upgrade.
        return nil
    end

    if main > 0 then
        return main
    end

    return nil
end

local function WGRGoldCandidateWeaponSetupScore(
    itemLink,
    itemLevel,
    baseline
)
    if not itemLink
        or not itemLevel
        or not baseline
    then
        return nil
    end

    local incomingKind =
        GetWeaponKind(
            itemLink
        )

    if not incomingKind then
        return nil
    end

    local config =
        baseline.weaponConfig

    local main =
        tonumber(
            baseline.mainHandLevel
        )
        or 0

    local off =
        tonumber(
            baseline.offHandLevel
        )
        or 0

    -- A 2H/ranged candidate represents the complete resulting weapon setup.
    if incomingKind == "TWO_HAND"
        or incomingKind == "RANGED"
    then
        return itemLevel
    end

    if incomingKind ~= "ONE_HAND" then
        return nil
    end

    -- For an existing dual-1H setup, a new 1H replaces the weaker weapon.
    if config == "DUAL_1H" then
        local partner =
            math.max(
                main,
                off
            )

        if partner > 0 then
            return
                (
                    itemLevel
                    + partner
                )
                / 2
        end

        return nil
    end

    -- For a 1H + shield/off-hand setup, preserve the existing off-hand
    -- component and compare the resulting complete setup.
    if config == "ONE_HAND_PLUS_SHIELD"
        or config == "ONE_HAND_PLUS_OFFHAND"
    then
        if off > 0 then
            return
                (
                    itemLevel
                    + off
                )
                / 2
        end

        return nil
    end

    -- If the currently recorded setup is a single weapon, compare directly.
    if config == "ONE_HAND" then
        return itemLevel
    end

    -- Switching from a complete 2H/ranged setup to only one half of a
    -- multi-piece 1H setup is not yet a complete "equip now" replacement.
    if config == "TWO_HAND"
        or config == "RANGED"
        or config == "DUAL_2H"
    then
        return nil
    end

    return itemLevel
end

local function WGRGoldWeaponIsActualUpgrade(
    itemLink,
    itemLevel
)
    local currentCharacter =
        UnitName(
            "player"
        )

    if not currentCharacter then
        return false
    end

    local character =
        FindCharacterByName(
            currentCharacter
        )

    local classID =
        GetCharacterClassID(
            currentCharacter,
            character
        )

    if not classID then
        return false
    end

    local specIDs =
        WGRGetRoutingSpecIDs(
            currentCharacter,
            character
        )

    local sawComparableSetup =
        false

    for _, specID
        in ipairs(
            specIDs
            or {}
        )
    do
        if WGRItemFitsSpecificSpec(
            itemLink,
            classID,
            specID
        ) == true
            and WGRSpecAllowsWeaponByProfile(
                currentCharacter,
                specID,
                itemLink,
                "WEAPON"
            )
        then
            local baseline =
                WGRGetSpecWeaponBaseline(
                    currentCharacter,
                    specID
                )
                or WGRBuildDataStoreWeaponBaseline(
                    currentCharacter,
                    character,
                    specID
                )

            if baseline
                and (
                    baseline.weaponConfigState == "INITIALIZED"
                    or baseline.weaponConfigState == "INHERITED_COMPLETE"
                    or baseline.weaponConfigState == "DATASTORE_FALLBACK"
                )
            then
                local currentScore =
                    WGRGoldBaselineSetupScore(
                        baseline
                    )

                local candidateScore =
                    WGRGoldCandidateWeaponSetupScore(
                        itemLink,
                        itemLevel,
                        baseline
                    )

                if currentScore
                    and candidateScore
                then
                    sawComparableSetup =
                        true

                    if candidateScore
                        > currentScore
                    then
                        return true
                    end
                end
            end
        end
    end

    -- If WGR has no complete comparable baseline, preserve the existing
    -- recommendation rather than inventing a GOLD-only baseline.
    if not sawComparableSetup then
        return nil
    end

    return false
end

local function WGRFinalizeGoldCandidates(
    generation,
    serial
)
    if generation
        and generation ~= cleanupGeneration
    then
        return
    end

    if serial ~= WGRGoldFinalizeSerial then
        return
    end

    WGRGoldLocationKeys = {}
    WGRTiedBestLocationKeys = {}

    for _, groupData
        in pairs(
            WGRGoldWinners
        )
    do
        local highest =
            nil

        local leaders = {}

        -- First restore every candidate to its normal routing overlay.
        -- GOLD/ORANGE will then replace MAGENTA only on the final leader(s).
        for _, candidate
            in pairs(
                groupData.candidates
                or {}
            )
        do
            HideGoldEquipOverlay(
                candidate.button
            )

            HideTiedBestOverlay(
                candidate.button
            )

            if candidate.isWarbank then
                ShowWarbankTakeOverlay(
                    candidate.button
                )
            end

            if highest == nil
                or candidate.itemLevel > highest
            then
                highest =
                    candidate.itemLevel

                leaders = {
                    candidate,
                }

            elseif candidate.itemLevel == highest then
                leaders[
                    #leaders + 1
                ] =
                    candidate
            end
        end

        if #leaders == 1 then
            local winner =
                leaders[1]

            WGRGoldLocationKeys[
                winner.key
            ] =
                true

            ShowGoldEquipOverlay(
                winner.button
            )

        elseif #leaders > 1 then
            for _, winner
                in ipairs(
                    leaders
                )
            do
                WGRTiedBestLocationKeys[
                    winner.key
                ] =
                    true

                ShowTiedBestOverlay(
                    winner.button
                )
            end
        end
    end
end

local function WGRScheduleGoldFinalize(
    generation
)
    WGRGoldFinalizeSerial =
        (WGRGoldFinalizeSerial or 0)
        + 1

    local serial =
        WGRGoldFinalizeSerial

    C_Timer.After(
        0.15,
        function()
            WGRFinalizeGoldCandidates(
                generation,
                serial
            )
        end
    )
end

local function WGRRegisterGoldCandidate(
    button,
    bagID,
    slotID,
    itemLink,
    result,
    generation
)
    if generation
        and generation ~= cleanupGeneration
    then
        return
    end

    -- Normal routing overlay is allowed to render immediately.
    -- GOLD/ORANGE is finalized only after candidate callbacks settle.
    HideGoldEquipOverlay(
        button
    )

    HideTiedBestOverlay(
        button
    )

    local currentCharacter =
        UnitName(
            "player"
        )

    local belongsToCurrent =
        result
        and result.name
        and currentCharacter
        and string.lower(
            tostring(result.name)
        ) == string.lower(
            tostring(currentCharacter)
        )

    if not belongsToCurrent
        or result.kind ~= "upgrade"
    then
        return
    end

    local group =
        WGRGetGoldGroupForItem(
            itemLink
        )

    if not group then
        return
    end

    local itemLevel =
        GetItemLevel(
            itemLink
        )

    if not itemLevel then
        return
    end

    if IsSupportedWeapon(
        itemLink
    ) then
        local actualWeaponUpgrade =
            WGRGoldWeaponIsActualUpgrade(
                itemLink,
                itemLevel
            )

        if actualWeaponUpgrade == false then
            return
        end
    end

    local key =
        WGRGoldLocationKey(
            bagID,
            slotID
        )

    if not key then
        return
    end

    local groupData =
        WGRGoldWinners[
            group
        ]

    if not groupData then
        groupData = {
            candidates = {},
        }

        WGRGoldWinners[
            group
        ] =
            groupData
    end

    groupData.candidates[
        key
    ] = {
        button = button,
        key = key,
        bagID = bagID,
        slotID = slotID,
        isWarbank =
            type(bagID) == "number"
            and bagID >= 12
            and bagID <= 16,
        itemLink = itemLink,
        itemLevel = itemLevel,
        upgrade = result.upgrade or 0,
    }

    WGRScheduleGoldFinalize(
        generation
    )
end


local function GetWarbankTakeOverlay(
    button
)
    InitializeDatabase()

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        return nil
    end

    if not button then
        return nil
    end

    if not button.WGRWarbankTakeOverlay then
        local overlay =
            CreateFrame(
                "Frame",
                nil,
                button
            )

        overlay:SetAllPoints(button)
        overlay:SetFrameLevel(
            button:GetFrameLevel() + 21
        )
        overlay:EnableMouse(false)

        -- Light blue wash so the item icon stays readable.
        local fill =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        fill:SetAllPoints(overlay)
        fill:SetColorTexture(
            0.85,
            0.05,
            0.75,
            0.24
        )

        -- Strong electric-blue TAKE border.
        local thickness = 4

        local function MakeEdge()
            local edge =
                overlay:CreateTexture(
                    nil,
                    "OVERLAY"
                )

            edge:SetColorTexture(
                1.00,
                0.10,
                0.85,
                1.00
            )

            return edge
        end

        local top = MakeEdge()
        top:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        top:SetHeight(thickness)

        local bottom = MakeEdge()
        bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        bottom:SetHeight(thickness)

        local left = MakeEdge()
        left:SetPoint("TOPLEFT", overlay, "TOPLEFT")
        left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
        left:SetWidth(thickness)

        local right = MakeEdge()
        right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
        right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
        right:SetWidth(thickness)

        -- Magenta now means POTENTIAL UPGRADE in every supported location.
        -- No directional marker is drawn because this is no longer a "take from Warbank" overlay.

        overlay:Hide()

        button.WGRWarbankTakeOverlay =
            overlay
    end

    return button.WGRWarbankTakeOverlay
end

HideWarbankTakeOverlay = function(
    button
)
    if button
        and button.WGRWarbankTakeOverlay
    then
        button.WGRWarbankTakeOverlay:Hide()
    end
end

ShowWarbankTakeOverlay = function(
    button
)
    InitializeDatabase()

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        HideWarbankTakeOverlay(
            button
        )
        return
    end

    local overlay =
        GetWarbankTakeOverlay(button)

    if overlay then
        overlay:Show()
    end
end

local function HideCleanupOverlay(button)
    if button
        and button.__WGRCleanupOverlay
    then
        button.__WGRCleanupOverlay.destination =
            nil

        button.__WGRCleanupOverlay:Hide()
    end
end



-- ============================================================
-- GEAR FINDER TEMPORARY ITEM LOCATOR
--
-- Hovering an item inside Gear Finder briefly highlights the matching
-- physical BAG / Personal Bank / Warband Bank item with a green pulse.
-- This is transient UI only; it does not change routing classification.
-- ============================================================

local WGRGearFinderLocatorOverlays = {}

local function WGRGetGearFinderLocatorOverlay(
    button
)
    if not button then
        return nil
    end

    if button.__WGRGearFinderLocatorOverlay then
        return button.__WGRGearFinderLocatorOverlay
    end

    local overlay =
        CreateFrame(
            "Frame",
            nil,
            button
        )

    overlay:SetAllPoints(
        button
    )

    overlay:SetFrameLevel(
        button:GetFrameLevel() + 45
    )

    overlay:EnableMouse(
        false
    )

    local glow =
        overlay:CreateTexture(
            nil,
            "ARTWORK"
        )

    glow:SetTexture(
        "Interface\\Buttons\\UI-ActionButton-Border"
    )

    glow:SetBlendMode(
        "ADD"
    )

    glow:SetVertexColor(
        0.10,
        1.00,
        0.20,
        1.00
    )

    glow:SetPoint(
        "CENTER",
        overlay,
        "CENTER",
        0,
        0
    )

    glow:SetSize(
        82,
        82
    )

    local thickness = 5

    local function MakeEdge()
        local edge =
            overlay:CreateTexture(
                nil,
                "OVERLAY"
            )

        edge:SetColorTexture(
            0.10,
            1.00,
            0.20,
            1.00
        )

        edge:SetBlendMode(
            "ADD"
        )

        return edge
    end

    local top = MakeEdge()
    top:SetPoint("TOPLEFT", overlay, "TOPLEFT", -3, 3)
    top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 3, 3)
    top:SetHeight(thickness)

    local bottom = MakeEdge()
    bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -3, -3)
    bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 3, -3)
    bottom:SetHeight(thickness)

    local left = MakeEdge()
    left:SetPoint("TOPLEFT", overlay, "TOPLEFT", -3, 3)
    left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -3, -3)
    left:SetWidth(thickness)

    local right = MakeEdge()
    right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 3, 3)
    right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 3, -3)
    right:SetWidth(thickness)

    local pulse =
        overlay:CreateAnimationGroup()

    pulse:SetLooping(
        "REPEAT"
    )

    local fadeDown =
        pulse:CreateAnimation(
            "Alpha"
        )

    fadeDown:SetFromAlpha(
        1.00
    )

    fadeDown:SetToAlpha(
        0.48
    )

    fadeDown:SetDuration(
        0.48
    )

    fadeDown:SetOrder(
        1
    )

    fadeDown:SetSmoothing(
        "IN_OUT"
    )

    local fadeUp =
        pulse:CreateAnimation(
            "Alpha"
        )

    fadeUp:SetFromAlpha(
        0.48
    )

    fadeUp:SetToAlpha(
        1.00
    )

    fadeUp:SetDuration(
        0.48
    )

    fadeUp:SetOrder(
        2
    )

    fadeUp:SetSmoothing(
        "IN_OUT"
    )

    overlay.WGRPulse =
        pulse

    overlay:Hide()

    button.__WGRGearFinderLocatorOverlay =
        overlay

    return overlay
end


function WGRHideGearFinderLocator()
    for _, overlay
        in ipairs(
            WGRGearFinderLocatorOverlays
        )
    do
        if overlay then
            if overlay.WGRPulse
                and overlay.WGRPulse:IsPlaying()
            then
                overlay.WGRPulse:Stop()
            end

            overlay:SetAlpha(
                1.00
            )

            overlay:Hide()
        end
    end

    WGRGearFinderLocatorOverlays = {}
end


function WGRShowGearFinderLocator(
    source,
    bagID,
    slotID,
    itemLink
)
    WGRHideGearFinderLocator()

    InitializeDatabase()

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        return 0
    end

    if source ~= "BAGS"
        and source ~= "PERSONAL_BANK"
        and source ~= "WARBAND_BANK"
    then
        return 0
    end

    if type(bagID) ~= "number"
        or type(slotID) ~= "number"
    then
        return 0
    end

    local matched = 0

    local prefixes = {
        "BagnonContainerItem",
        "BagnonItem",
    }

    for _, prefix
        in ipairs(prefixes)
    do
        local misses = 0

        for i = 1, 2500 do
            local button =
                _G[
                    prefix
                    .. tostring(i)
                ]

            if button then
                misses = 0

                if button.IsShown
                    and button:IsShown()
                    and button.bag == bagID
                    and button.GetID
                    and button:GetID() == slotID
                then
                    local currentLink =
                        C_Container.GetContainerItemLink(
                            bagID,
                            slotID
                        )

                    if currentLink
                        and (
                            not itemLink
                            or currentLink == itemLink
                        )
                    then
                        local overlay =
                            WGRGetGearFinderLocatorOverlay(
                                button
                            )

                        if overlay then
                            WGRGearFinderLocatorOverlays[
                                #WGRGearFinderLocatorOverlays + 1
                            ] =
                                overlay

                            overlay:SetAlpha(
                                1.00
                            )

                            overlay:Show()

                            if overlay.WGRPulse then
                                overlay.WGRPulse:Play()
                            end

                            matched =
                                matched + 1
                        end
                    end
                end
            else
                misses = misses + 1

                if i > 1000
                    and misses >= 300
                then
                    break
                end
            end
        end
    end

    return matched
end



function WGRHideAllGearOverlays()
    WGRHideGearFinderLocator()

    cleanupGeneration =
        cleanupGeneration + 1

    local prefixes = {
        "BagnonContainerItem",
        "BagnonItem",
    }

    for _, prefix
        in ipairs(prefixes)
    do
        for i = 1, 2500 do
            local button =
                _G[
                    prefix
                    .. tostring(i)
                ]

            if button then
                HideCleanupOverlay(
                    button
                )

                HideWarbankTakeOverlay(
                    button
                )

                HideGoldEquipOverlay(
                    button
                )

                HideTiedBestOverlay(
                    button
                )

                HideDisposeOverlay(
                    button
                )
            end
        end
    end
end

local function IsAccountBankBagID(bagID)
    if type(bagID) ~= "number" then
        return false
    end

    if Enum
        and Enum.BagIndex
    then
        for key, value
            in pairs(Enum.BagIndex)
        do
            if type(key) == "string"
                and type(value) == "number"
                and value == bagID
                and key:find(
                    "AccountBank",
                    1,
                    true
                )
            then
                return true
            end
        end
    end

    return false
end

local function IsCurrentCharacterBagnonButton(
    button
)
    if not button then
        return false
    end

    if type(button.GetOwner)
        ~= "function"
    then
        return true
    end

    local ok, owner =
        pcall(
            button.GetOwner,
            button
        )

    if not ok or not owner then
        return true
    end

    if owner.remote == true
        or owner.offline == true
    then
        return false
    end

    local currentName =
        UnitName("player")

    local currentRealm =
        GetRealmName()

    if owner.name
        and currentName
        and string.lower(owner.name)
            ~= string.lower(currentName)
    then
        return false
    end

    if owner.realm
        and currentRealm
        and string.lower(owner.realm)
            ~= string.lower(currentRealm)
    then
        return false
    end

    return true
end

function IsTransferableContainerItem(
    bagID,
    slotID,
    itemLink
)
    if not itemLink
        or type(bagID) ~= "number"
        or type(slotID) ~= "number"
    then
        return false
    end

    if not WGRQualityAllowed(
        itemLink
    ) then
        return false
    end

    if not C_TooltipInfo
        or not C_TooltipInfo.GetBagItem
    then
        return false
    end

    local data =
        C_TooltipInfo.GetBagItem(
            bagID,
            slotID
        )

    if not data
        or not data.lines
    then
        return false
    end

    if TooltipUtil
        and TooltipUtil.SurfaceArgs
    then
        TooltipUtil.SurfaceArgs(data)
    end

    local sawWarbound = false
    local sawBoE = false

    for _, line in ipairs(data.lines) do
        if TooltipUtil
            and TooltipUtil.SurfaceArgs
        then
            TooltipUtil.SurfaceArgs(line)
        end

        for _, text in ipairs({
            line.leftText,
            line.rightText,
        }) do
            if text then
                local clean =
                    tostring(text)
                    :gsub("|c%x%x%x%x%x%x%x%x", "")
                    :gsub("|r", "")
                    :lower()

                if clean:find(
                    "soulbound",
                    1,
                    true
                ) then
                    return false
                end

                if clean:find(
                    "warbound until equipped",
                    1,
                    true
                ) then
                    sawWarbound = true
                end

                if clean:find(
                    "binds when equipped",
                    1,
                    true
                ) then
                    sawBoE = true
                end
            end
        end
    end

    return WGRBindingAllowed(
        sawWarbound,
        sawBoE
    )
end


-- ============================================================
-- ACCOUNT GEAR DIRECTORY / HELD GEAR SNAPSHOTS
-- ============================================================

local WGRHeldGearTankSpecs = {
    [66] = true,
    [73] = true,
    [104] = true,
    [250] = true,
    [268] = true,
    [581] = true,
}

local WGRHeldGearHealerSpecs = {
    [65] = true,
    [105] = true,
    [256] = true,
    [257] = true,
    [264] = true,
    [270] = true,
    [1468] = true,
}

local WGRHeldGearCasterDPSSpecs = {
    [62] = true,
    [63] = true,
    [64] = true,
    [102] = true,
    [258] = true,
    [262] = true,
    [265] = true,
    [266] = true,
    [267] = true,
    [1467] = true,
    [1473] = true,
    [1480] = true,
}

local function WGRHeldGearPrimaryStat(
    itemLink
)
    if not itemLink
        or not C_Item
        or not C_Item.GetItemStats
    then
        return nil
    end

    local stats =
        C_Item.GetItemStats(
            itemLink
        )
        or {}

    local strength =
        tonumber(
            stats.ITEM_MOD_STRENGTH_SHORT
        )
        or 0

    local agility =
        tonumber(
            stats.ITEM_MOD_AGILITY_SHORT
        )
        or 0

    local intellect =
        tonumber(
            stats.ITEM_MOD_INTELLECT_SHORT
        )
        or 0

    local positives = 0
    if strength > 0 then positives = positives + 1 end
    if agility > 0 then positives = positives + 1 end
    if intellect > 0 then positives = positives + 1 end

    if positives > 1 then
        return "Hybrid"
    end

    if intellect > 0 then
        return "Intellect"
    end

    if agility > 0 then
        return "Agility"
    end

    if strength > 0 then
        return "Strength"
    end

    return nil
end

local function WGRHeldGearTrinketRole(
    itemLink
)
    if not itemLink
        or not C_Item
        or not C_Item.DoesItemContainSpec
        or type(WGRClassSpecIDs) ~= "table"
    then
        return "Unclassified"
    end

    local flags = {
        tank = false,
        healer = false,
        caster = false,
        physical = false,
    }

    local sawKnown =
        false

    for classID, specIDs
        in pairs(
            WGRClassSpecIDs
        )
    do
        for _, specID
            in ipairs(
                specIDs
            )
        do
            local ok,
                  fits =
                pcall(
                    C_Item.DoesItemContainSpec,
                    itemLink,
                    classID,
                    specID
                )

            if ok then
                sawKnown = true

                if fits == true then
                    if WGRHeldGearTankSpecs[
                        specID
                    ] then
                        flags.tank = true

                    elseif WGRHeldGearHealerSpecs[
                        specID
                    ] then
                        flags.healer = true

                    elseif WGRHeldGearCasterDPSSpecs[
                        specID
                    ] then
                        flags.caster = true

                    else
                        flags.physical = true
                    end
                end
            end
        end
    end

    if not sawKnown then
        return "Unclassified"
    end

    if flags.tank
        and flags.healer
        and flags.caster
        and flags.physical
    then
        return "General / All Roles"
    end

    if not flags.tank
        and not flags.healer
        and flags.caster
        and flags.physical
    then
        return "General DPS"
    end

    local labels = {}

    if flags.tank then
        labels[#labels + 1] =
            "Tank"
    end

    if flags.healer then
        labels[#labels + 1] =
            "Healer"
    end

    if flags.caster then
        labels[#labels + 1] =
            "Caster DPS"
    end

    if flags.physical then
        labels[#labels + 1] =
            "Physical DPS"
    end

    if #labels == 0 then
        return "Unclassified"
    end

    return table.concat(
        labels,
        " / "
    )
end

local function WGRHeldGearNormalizeSubtype(
    itemSubType
)
    local subtype =
        tostring(
            itemSubType
            or "Other"
        )

    if subtype == "" then
        return "Other"
    end

    return subtype
end

local function WGRHeldGearClassifyItem(
    itemLink
)
    if not itemLink then
        return nil
    end

    local info =
        GetInstantItemInfo(
            itemLink
        )

    if not info
        or not info.classID
    then
        return nil
    end

    local equipLoc =
        info.equipLoc
        or ""

    local subtype =
        WGRHeldGearNormalizeSubtype(
            info.itemSubType
        )

    if equipLoc == "INVTYPE_CLOAK" then
        return
            "Accessories",
            "Cloaks"

    elseif equipLoc == "INVTYPE_NECK" then
        return
            "Accessories",
            "Necks"

    elseif equipLoc == "INVTYPE_FINGER" then
        return
            "Accessories",
            "Rings"

    elseif equipLoc == "INVTYPE_TRINKET" then
        return
            "Trinkets",
            WGRHeldGearTrinketRole(
                itemLink
            )

    elseif equipLoc == "INVTYPE_SHIELD" then
        return
            "Weapons",
            "Shields",
            WGRHeldGearPrimaryStat(
                itemLink
            )
            or "Other"

    elseif equipLoc == "INVTYPE_HOLDABLE" then
        return
            "Weapons",
            "Off-Hands",
            WGRHeldGearPrimaryStat(
                itemLink
            )
            or "Other"
    end

    if info.classID == 4 then
        local armorTypes = {
            Cloth = true,
            Leather = true,
            Mail = true,
            Plate = true,
        }

        if armorTypes[subtype] then
            return
                "Armor",
                subtype
        end

        return nil
    end

    if info.classID ~= 2 then
        return nil
    end

    local subtypeLower =
        string.lower(
            subtype
        )

    local primary =
        WGRHeldGearPrimaryStat(
            itemLink
        )

    if subtypeLower:find(
        "warglaive",
        1,
        true
    ) then
        return
            "Weapons",
            "Warglaives",
            subtype
    end

    if subtypeLower:find(
        "wand",
        1,
        true
    ) then
        return
            "Weapons",
            "1H Intellect",
            "Wand"
    end

    if subtypeLower:find(
        "bow",
        1,
        true
    )
        or subtypeLower:find(
            "gun",
            1,
            true
        )
        or subtypeLower:find(
            "crossbow",
            1,
            true
        )
    then
        return
            "Weapons",
            "Ranged",
            subtype
    end

    local isTwoHand =
        equipLoc
        == "INVTYPE_2HWEAPON"

    local isOneHand =
        equipLoc
        == "INVTYPE_WEAPON"
        or equipLoc
            == "INVTYPE_WEAPONMAINHAND"
        or equipLoc
            == "INVTYPE_WEAPONOFFHAND"

    if not isOneHand
        and not isTwoHand
    then
        return
            "Weapons",
            "Other Weapons",
            subtype
    end

    if isOneHand
        and subtypeLower:find(
            "dagger",
            1,
            true
        )
    then
        if primary == "Intellect" then
            return
                "Weapons",
                "1H Intellect",
                "Dagger"
        end

        if primary == "Agility" then
            return
                "Weapons",
                "Agility Daggers",
                "Dagger"
        end
    end

    local hand =
        isTwoHand
        and "2H "
        or "1H "

    local bucket =
        hand
        .. (
            primary
            or "Other"
        )

    return
        "Weapons",
        bucket,
        subtype
end

local function WGRHeldGearAddEntry(
    location,
    section,
    category,
    subtype
)
    if not location
        or not section
        or not category
    then
        return
    end

    local key =
        tostring(section)
        .. "\031"
        .. tostring(category)
        .. "\031"
        .. tostring(
            subtype
            or ""
        )

    location.entries =
        location.entries
        or {}

    location.entries[key] =
        (
            location.entries[key]
            or 0
        ) + 1

    location.total =
        (
            location.total
            or 0
        ) + 1
end

local function WGRHeldGearScanBagIDs(
    bagIDs
)
    local result = {
        total = 0,
        entries = {},
        scanned = time(),
    }

    if not C_Container
        or not C_Container.GetContainerNumSlots
        or not C_Container.GetContainerItemLink
    then
        return result
    end

    for _, bagID
        in ipairs(
            bagIDs
        )
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
                local recommendation =
                    WGRBuildLoadedItemRecommendation
                    and WGRBuildLoadedItemRecommendation(
                        itemLink
                    )
                    or nil

                local isDispose =
                    recommendation
                    and (
                        recommendation.kind
                            == "sell"
                        or recommendation.kind
                            == "no_current_upgrade"
                    )

                if not isDispose then
                    local section,
                          category,
                          subtype =
                        WGRHeldGearClassifyItem(
                            itemLink
                        )

                    WGRHeldGearAddEntry(
                        result,
                        section,
                        category,
                        subtype
                    )
                end
            end
        end
    end

    return result
end

local function WGRHeldGearBagIDs()
    local ids = {}

    for bagID = 0, 5 do
        ids[#ids + 1] =
            bagID
    end

    return ids
end

local function WGRHeldGearPersonalBankIDs()
    local ids = {}

    if Enum
        and Enum.BagIndex
    then
        for name, bagID
            in pairs(
                Enum.BagIndex
            )
        do
            if type(name) == "string"
                and type(bagID)
                    == "number"
                and name:find(
                    "CharacterBankTab",
                    1,
                    true
                )
            then
                ids[#ids + 1] =
                    bagID
            end
        end
    end

    table.sort(ids)

    -- Legacy/fallback bank bag IDs.
    if #ids == 0 then
        for bagID = 6, 11 do
            ids[#ids + 1] =
                bagID
        end
    end

    return ids
end

function WGRRefreshHeldGearSnapshot(
    includePersonalBank
)
    InitializeDatabase()

    local characterName =
        UnitName("player")

    if not characterName then
        return nil
    end

    local key =
        string.lower(
            characterName
        )

    if WGRIsCharacterRemoved
        and WGRIsCharacterRemoved(
            characterName
        )
    then
        WarboundGearRouterDB.heldGearSnapshots[
            key
        ] = nil
        return nil
    end

    local snapshot =
        WarboundGearRouterDB.heldGearSnapshots[
            key
        ]
        or {
            character =
                characterName,
        }

    snapshot.character =
        characterName

    snapshot.bags =
        WGRHeldGearScanBagIDs(
            WGRHeldGearBagIDs()
        )

    if includePersonalBank then
        local bankIDs =
            WGRHeldGearPersonalBankIDs()

        local hasReadableBank =
            false

        for _, bagID
            in ipairs(
                bankIDs
            )
        do
            if (
                C_Container.GetContainerNumSlots(
                    bagID
                )
                or 0
            ) > 0
            then
                hasReadableBank =
                    true
                break
            end
        end

        -- Do not erase a useful cached bank snapshot if this event came
        -- from another bank type and Character Bank containers are unavailable.
        if hasReadableBank then
            snapshot.bank =
                WGRHeldGearScanBagIDs(
                    bankIDs
                )
        end
    end

    snapshot.updated =
        time()

    WarboundGearRouterDB.heldGearSnapshots[
        key
    ] =
        snapshot

    return snapshot
end

local function WGRHeldGearWarbandBankIDs()
    local ids = {}
    if Enum and Enum.BagIndex then
        for name, bagID in pairs(Enum.BagIndex) do
            if type(name) == "string"
                and type(bagID) == "number"
                and (
                    name:find("AccountBankTab", 1, true)
                    or name:find("WarbandBank", 1, true)
                )
            then
                ids[#ids + 1] = bagID
            end
        end
    end
    table.sort(ids)
    return ids
end

function WGRRefreshWarbandHeldGearSnapshot()
    InitializeDatabase()
    local ids = WGRHeldGearWarbandBankIDs()
    if #ids == 0 then return nil end

    local readable = false
    for _, bagID in ipairs(ids) do
        if (C_Container.GetContainerNumSlots(bagID) or 0) > 0 then
            readable = true
            break
        end
    end
    if not readable then return nil end

    WarboundGearRouterDB.heldGearSnapshots["__warband_bank"] = {
        character = "Warband Bank",
        warband = WGRHeldGearScanBagIDs(ids),
        updated = time(),
    }
    return WarboundGearRouterDB.heldGearSnapshots["__warband_bank"]
end

function WGRGetWarbandHeldGearSummary()
    InitializeDatabase()
    local snapshot = WarboundGearRouterDB.heldGearSnapshots["__warband_bank"]
    local summary = {
        character = "Warband Bank",
        total = 0,
        warband = 0,
        entries = {},
        warbandScanned = nil,
    }
    if not snapshot or not snapshot.warband then return summary end
    summary.total = tonumber(snapshot.warband.total) or 0
    summary.warband = summary.total
    summary.warbandScanned = snapshot.warband.scanned
    for key, count in pairs(snapshot.warband.entries or {}) do
        summary.entries[key] = tonumber(count) or 0
    end
    return summary
end

function WGRGetHeldGearSummary(
    characterName
)
    InitializeDatabase()

    if not characterName then
        return nil
    end

    if WGRIsCharacterRemoved
        and WGRIsCharacterRemoved(
            characterName
        )
    then
        WarboundGearRouterDB.heldGearSnapshots[
            string.lower(
                characterName
            )
        ] = nil

        return {
            character =
                characterName,
            total = 0,
            bags = 0,
            bank = 0,
            entries = {},
        }
    end

    local snapshot =
        WarboundGearRouterDB.heldGearSnapshots[
            string.lower(
                characterName
            )
        ]

    if not snapshot then
        return {
            character =
                characterName,
            total = 0,
            bags = 0,
            bank = 0,
            entries = {},
        }
    end

    local summary = {
        character =
            snapshot.character
            or characterName,
        total = 0,
        bags = 0,
        bank = 0,
        entries = {},
        bagsScanned =
            snapshot.bags
            and snapshot.bags.scanned,
        bankScanned =
            snapshot.bank
            and snapshot.bank.scanned,
    }

    local function Merge(
        location,
        field
    )
        if not location then
            return
        end

        local locationTotal =
            tonumber(
                location.total
            )
            or 0

        summary[field] =
            locationTotal

        summary.total =
            summary.total
            + locationTotal

        for key, count
            in pairs(
                location.entries
                or {}
            )
        do
            summary.entries[key] =
                (
                    summary.entries[key]
                    or 0
                )
                + (
                    tonumber(count)
                    or 0
                )
        end
    end

    Merge(
        snapshot.bags,
        "bags"
    )

    Merge(
        snapshot.bank,
        "bank"
    )

    return summary
end

local function RecommendationBelongsToCurrentCharacter(
    result
)
    if not result
        or not result.name
    then
        return false
    end

    if result.kind ~= "upgrade"
        and result.kind ~= "future_upgrade"
        and result.kind ~= "holder"
    then
        return false
    end

    local current =
        UnitName("player")

    if not current then
        return false
    end

    return string.lower(result.name)
        == string.lower(current)
end

local function RecommendationIsPotentialUpgradeForCurrentCharacter(result)
    if not result or not result.name then return false end
    -- Magenta means an upgrade the current character can equip now.
    -- Future-level recommendations are HOLD items until the level requirement
    -- is actually met, so they must not receive the magenta overlay.
    if result.kind ~= "upgrade" then return false end

    local current = UnitName("player")
    if not current then return false end

    return string.lower(result.name) == string.lower(current)
end

local function RecommendationNeedsMove(
    result
)
    if not result
        or not result.name
    then
        return false
    end

    if result.kind ~= "upgrade"
        and result.kind ~= "future_upgrade"
        and result.kind ~= "holder"
    then
        return false
    end

    local current =
        UnitName("player")

    if not current then
        return false
    end

    return string.lower(result.name)
        ~= string.lower(current)
end

local function EvaluateWarbankButton(button, generation)
    if not button or not button:IsShown() then return end

    HideWarbankTakeOverlay(button)
    HideGoldEquipOverlay(button)
    HideTiedBestOverlay(button)
    HideDisposeOverlay(button)
    HideCleanupOverlay(button)

    local bagID = button.bag
    local slotID = button.GetID and button:GetID()

    if type(bagID) ~= "number" or bagID < 12 or bagID > 16
        or type(slotID) ~= "number" or slotID <= 0
    then
        return
    end

    local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
    if not itemLink or not IsTransferableContainerItem(bagID, slotID, itemLink) then return end

    button.__WGRWarbankBag = bagID
    button.__WGRWarbankSlot = slotID
    button.__WGRWarbankItemLink = itemLink

    BuildTooltipRecommendation(
        itemLink,
        function(result)
            if generation and generation ~= cleanupGeneration then return end
            if not button or not button:IsShown() then return end

            if button.bag ~= button.__WGRWarbankBag
                or button:GetID() ~= button.__WGRWarbankSlot
            then
                HideWarbankTakeOverlay(button)
                return
            end

            local currentLink = C_Container.GetContainerItemLink(
                button.__WGRWarbankBag,
                button.__WGRWarbankSlot
            )
            if currentLink ~= button.__WGRWarbankItemLink then
                HideWarbankTakeOverlay(button)
                return
            end

            local isDispose = result and (
                result.kind == "sell"
                or result.kind == "no_current_upgrade"
            )

            if isDispose then
                HideWarbankTakeOverlay(button)
                ShowDisposeOverlay(button)
                return
            end

            HideDisposeOverlay(button)

            if RecommendationIsPotentialUpgradeForCurrentCharacter(result) then
                ShowWarbankTakeOverlay(button)
            else
                HideWarbankTakeOverlay(button)
            end

            -- No RED overlay in Warband Bank: the item is already account-accessible.
            -- Gold/Orange overlays are retired; Gear Finder owns equip recommendations.
        end,
        true
    )
end

local function EvaluateBagnonButton(button, generation)
    if not button or not button:IsShown() then return end

    HideCleanupOverlay(button)
    HideWarbankTakeOverlay(button)
    HideGoldEquipOverlay(button)
    HideTiedBestOverlay(button)
    HideDisposeOverlay(button)

    local possibleBag = button.bag
    if type(possibleBag) == "number" and possibleBag >= 12 and possibleBag <= 16 then
        EvaluateWarbankButton(button, generation)
        return
    end

    if not IsCurrentCharacterBagnonButton(button) then return end

    local bagID = button.bag
    local slotID = button.GetID and button:GetID()

    if type(bagID) ~= "number" or type(slotID) ~= "number"
        or slotID <= 0 or IsAccountBankBagID(bagID)
    then
        return
    end

    local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
    if not itemLink or not IsTransferableContainerItem(bagID, slotID, itemLink) then return end

    button.__WGRBag = bagID
    button.__WGRSlot = slotID
    button.__WGRItemLink = itemLink

    BuildTooltipRecommendation(
        itemLink,
        function(result)
            if generation ~= cleanupGeneration then return end
            if not button or not button:IsShown() then return end

            if button.bag ~= button.__WGRBag
                or button:GetID() ~= button.__WGRSlot
            then
                HideCleanupOverlay(button)
                HideWarbankTakeOverlay(button)
                return
            end

            local currentLink = C_Container.GetContainerItemLink(
                button.__WGRBag,
                button.__WGRSlot
            )
            if currentLink ~= button.__WGRItemLink then
                HideCleanupOverlay(button)
                HideWarbankTakeOverlay(button)
                return
            end

            local isDispose = result and (
                result.kind == "sell"
                or result.kind == "no_current_upgrade"
            )

            if isDispose then
                HideCleanupOverlay(button)
                HideWarbankTakeOverlay(button)
                ShowDisposeOverlay(button)
                return
            end

            HideDisposeOverlay(button)

            if RecommendationNeedsMove(result) then
                HideWarbankTakeOverlay(button)

                local overlay = EnsureCleanupOverlay(button)
                if overlay then
                    overlay.destination = result.name
                    overlay:Show()
                end
            else
                HideCleanupOverlay(button)

                if RecommendationIsPotentialUpgradeForCurrentCharacter(result) then
                    ShowWarbankTakeOverlay(button)
                else
                    HideWarbankTakeOverlay(button)
                end
            end

            -- Gold/Orange overlays are intentionally retired.
        end,
        true
    )
end

function RefreshBagnonCleanupOverlays()
    InitializeDatabase()

    if WGRRoutingIsPaused() then
        WGRHideAllGearOverlays()
        return 0, 0
    end

    if WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.gearOverlays == false
    then
        WGRHideAllGearOverlays()
        return 0, 0
    end

    cleanupGeneration =
        cleanupGeneration + 1

    local generation =
        cleanupGeneration

    local visible = 0
    local evaluated = 0
    local misses = 0

    -- Bagnon item buttons on this installation can have high
    -- sequence numbers, so scan a generous but cheap global-name range.
    for i = 1, 2500 do
        local button =
            _G[
                "BagnonContainerItem"
                .. i
            ]

        if button then
            misses = 0

            if button.IsShown
                and button:IsShown()
            then
                visible = visible + 1

                -- Always clear first so reused/empty slots cannot
                -- retain an old overlay.
                HideCleanupOverlay(button)
                HideWarbankTakeOverlay(button)
                HideGoldEquipOverlay(button)
                HideTiedBestOverlay(button)
                HideDisposeOverlay(button)

                if IsCurrentCharacterBagnonButton(
                    button
                ) then
                    local bagID =
                        button.bag

                    local slotID =
                        button.GetID
                        and button:GetID()

                    if type(bagID)
                            == "number"
                        and type(slotID)
                            == "number"
                        and slotID > 0
                    then
                        evaluated =
                            evaluated + 1

                        EvaluateBagnonButton(
                            button,
                            generation
                        )
                    end
                end
            end
        else
            misses = misses + 1

            if i > 1000
                and misses >= 300
            then
                break
            end
        end
    end

    return visible, evaluated
end


function WGRUpdateRoutingPauseButton(
    suppliedButton
)
    local button =
        suppliedButton

    if not button then
        button =
            WGRRoutingPauseButton
    end

    if not button then
        return
    end

    local label =
        button.WGRRoutingLabel

    local paused =
        WGRRoutingIsPaused()

    local text =
        paused
        and "WBGR: PAUSED"
        or "WBGR: ACTIVE"

    if label then
        label:SetText(
            text
        )

        label:SetTextColor(
            paused and 1.00 or 0.30,
            paused and 0.30 or 1.00,
            0.20
        )
    end

    -- Keep the template's own text synchronized too, even though
    -- the explicit label frame is the visible text layer.
    button:SetText(
        text
    )
end

function WGRSetRoutingPaused(
    paused,
    quiet
)
    InitializeDatabase()

    WarboundGearRouterDB.interface.routingPaused =
        paused
        and true
        or false

    tooltipSerial =
        tooltipSerial + 1

    if WarboundGearRouterDB.interface.routingPaused then
        WGRHideAllGearOverlays()
    else
        RefreshBagnonCleanupOverlays()
    end

    if WGRGearFinderSetMasterPaused then
        WGRGearFinderSetMasterPaused(
            WarboundGearRouterDB.interface.routingPaused
        )
    end

    if WGRMailSetMasterPaused then
        WGRMailSetMasterPaused(
            WarboundGearRouterDB.interface.routingPaused
        )
    end

    if WGRUpdateOpenRouterButton then
        WGRUpdateOpenRouterButton()
    end

    WGRUpdateRoutingPauseButton(
        WGRRoutingPauseButton
    )

    if not quiet then
        if WarboundGearRouterDB.interface.routingPaused then
            print(
                "|cffffff00WBGR PAUSED.|r Routing, Gear Finder, and Mail Router are disabled. Passive data collection remains active."
            )
        else
            print(
                "|cff00ff00WBGR ACTIVE.|r Routing, Gear Finder, and Mail Router are enabled."
            )
        end
    end
end


function QueueCleanupRefresh()
    if cleanupRefreshPending then
        return
    end

    cleanupRefreshPending = true

    C_Timer.After(
        0.12,
        function()
            cleanupRefreshPending = false
            RefreshBagnonCleanupOverlays()
        end
    )
end

function WGRRoutingConfigurationChanged()
    tooltipSerial =
        tooltipSerial + 1

    if WGRRoutingIsPaused() then
        return
    end

    QueueCleanupRefresh()
end


local bagVisibilityHooksInstalled =
    false

function InstallBagVisibilityHooks()
    if bagVisibilityHooksInstalled then
        return
    end

    bagVisibilityHooksInstalled =
        true

    local function RefreshAfterBagShow()
        C_Timer.After(
            0.20,
            RefreshBagnonCleanupOverlays
        )

        -- Bagnon can finish rebuilding/reusing its buttons a little later.
        C_Timer.After(
            0.60,
            RefreshBagnonCleanupOverlays
        )
    end

    local functionsToHook = {
        "OpenAllBags",
        "ToggleAllBags",
        "ToggleBackpack",
    }

    for _, functionName
        in ipairs(functionsToHook)
    do
        if type(
            _G[functionName]
        ) == "function"
        then
            hooksecurefunc(
                functionName,
                RefreshAfterBagShow
            )
        end
    end
end

function QueueStartupOverlayRefreshes()
    -- The first cleanup pass can happen before Bagnon has constructed
    -- visible item buttons. Repeat a few cheap passes after login/reload.
    C_Timer.After(
        0.50,
        RefreshBagnonCleanupOverlays
    )

    C_Timer.After(
        1.50,
        RefreshBagnonCleanupOverlays
    )

    C_Timer.After(
        3.00,
        RefreshBagnonCleanupOverlays
    )
end

function WGRRenderRecommendationForItemTooltip(
    tooltip,
    itemLink,
    displayContext
)
    if not tooltip
        or not itemLink
        or WGRRoutingIsPaused()
    then
        return
    end

    tooltipSerial =
        tooltipSerial + 1

    local serial =
        tooltipSerial

    tooltip.__WGRLineAdded =
        false

    BuildTooltipRecommendation(
        itemLink,
        function(
            result,
            alternatives
        )
            AddWGRLineToTooltip(
                tooltip,
                itemLink,
                result,
                serial,
                alternatives,
                displayContext
            )
        end
    )
end


local function WGRScheduleTooltipRetry(
    tooltip,
    itemLink
)
    if not tooltip
        or not itemLink
    then
        return
    end

    if tooltip.__WGRRetryItemLink
        == itemLink
    then
        return
    end

    tooltip.__WGRRetryItemLink =
        itemLink

    C_Timer.After(
        0.08,
        function()
            if not tooltip
                or not tooltip:IsShown()
            then
                return
            end

            local _, currentLink =
                tooltip:GetItem()

            if currentLink
                ~= itemLink
            then
                return
            end

            tooltip.__WGRRetryItemLink =
                nil

            if tooltip.__WGRLineAdded then
                return
            end

            if type(tooltip.RefreshData)
                == "function"
            then
                tooltip:RefreshData()
            else
                ProcessTooltip(
                    tooltip
                )
            end
        end
    )
end

function ProcessTooltip(tooltip)
    if not tooltip
        or tooltip ~= GameTooltip
    then
        return
    end

    -- Gear Finder owns the GameTooltip while hovering its virtual item
    -- buttons. Its item was already validated by the bag scanner, and it
    -- explicitly invokes the same WGR renderer below. Avoid a second async
    -- tooltip evaluation from Blizzard's normal tooltip hook.
    if tooltip.__WGRGearFinderManaged then
        local owner =
            tooltip.GetOwner
            and tooltip:GetOwner()

        if owner
            and owner.__WGRGearFinderButton
        then
            return
        end

        -- A normal bag/bank button now owns the tooltip. Never let stale
        -- Gear Finder state suppress or corrupt ordinary item tooltips.
        tooltip.__WGRGearFinderManaged =
            nil
    end

    if WGRRoutingIsPaused() then
        return
    end

    local _, itemLink =
        tooltip:GetItem()

    if not itemLink then
        return
    end

    if WGRItemIsIgnored
        and WGRItemIsIgnored(
            itemLink
        )
    then
        if tooltip.__WGRIgnoredItemLink
            ~= itemLink
        then
            tooltip:AddLine(
                "WBGR: IGNORED",
                0.65,
                0.65,
                0.65
            )
            tooltip.__WGRIgnoredItemLink =
                itemLink
            tooltip:Show()
        end
        return
    end

    if not IsTransferableGearTooltip(
        tooltip,
        itemLink
    )
    then
        WGRScheduleTooltipRetry(
            tooltip,
            itemLink
        )
        return
    end

    tooltip.__WGRRetryItemLink =
        nil

    tooltipSerial =
        tooltipSerial + 1

    local serial =
        tooltipSerial

    tooltip.__WGRLineAdded = false

    local displayContext = nil
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if owner and type(owner.bag) == "number" then
        local bagID = owner.bag
        if bagID >= 12 and bagID <= 16 then
            displayContext = { source = "WARBAND_BANK" }
        else
            -- For HOLD wording we only need to distinguish shared WBK from
            -- character-local Bags/PBK. Bagnon local buttons are "here".
            displayContext = { source = "LOCAL" }
        end
    end

    BuildTooltipRecommendation(
        itemLink,
        function(result, alternatives)
            AddWGRLineToTooltip(
                tooltip,
                itemLink,
                result,
                serial,
                alternatives,
                displayContext
            )
        end
    )
end

local tooltipHookInstalled = false

function InstallTooltipHook()
    if tooltipHookInstalled then
        return
    end

    tooltipHookInstalled = true

    if TooltipDataProcessor
        and
        TooltipDataProcessor.AddTooltipPostCall
        and Enum
        and Enum.TooltipDataType
        and Enum.TooltipDataType.Item
    then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Item,
            function(tooltip)
                ProcessTooltip(tooltip)
            end
        )

    elseif GameTooltip
        and GameTooltip.HookScript
    then
        GameTooltip:HookScript(
            "OnTooltipSetItem",
            function(self)
                ProcessTooltip(self)
            end
        )
    end

    if GameTooltip
        and GameTooltip.HookScript
    then
        GameTooltip:HookScript(
            "OnTooltipCleared",
            function(self)
                self.__WGRLineAdded =
                    false

                self.__WGRGearFinderManaged =
                    nil

                self.__WGRIgnoredItemLink =
                    nil

                self.__WGRRetryItemLink =
                    nil

                tooltipSerial =
                    tooltipSerial + 1
            end
        )
    end
end
