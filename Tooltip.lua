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

local function WGRGetTooltipTrinketCharacterSummary(
    characterName,
    itemLink
)
    if not characterName
        or not itemLink
        or not WGRGetTrinketSpecSummary
    then
        return nil
    end

    local instantInfo = GetInstantItemInfo(itemLink)
    if not instantInfo
        or instantInfo.equipLoc ~= "INVTYPE_TRINKET"
    then
        return nil
    end

    local character = FindCharacterByName(characterName)
    if not character then
        return nil
    end

    return WGRGetTrinketSpecSummary(
        characterName,
        character,
        itemLink
    )
end

local function WGRGetTooltipTrinketUpgradeSummary(
    characterName,
    itemLink
)
    if not characterName
        or not itemLink
        or not WGRGetTrinketTooltipUpgradeSummary
    then
        return nil
    end

    local instantInfo = GetInstantItemInfo(itemLink)
    if not instantInfo
        or instantInfo.equipLoc ~= "INVTYPE_TRINKET"
    then
        return nil
    end

    local character = FindCharacterByName(characterName)
    if not character then
        return nil
    end

    return WGRGetTrinketTooltipUpgradeSummary(
        characterName,
        character,
        itemLink,
        GetItemLevel(itemLink)
    )
end

local function FormatTooltipRecommendation(result, tooltip, displayContext, itemLink)
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
        if result.setupIncomplete == true then
            if isCurrentCharacter then
                return "UPGRADE?  (paired setup incomplete)", 1.00, 0.35, 0.82
            end
            return string.format("SEND TO: %s  (paired setup incomplete)", result.name), 1.00, 0.20, 0.20
        end
        local averageSuffix =
            result.weaponAverage
            and " - weap avg"
            or result.weaponOverAverage
            and " - over weap avg"
            or ""

        local trinketSummary =
            WGRGetTooltipTrinketUpgradeSummary(
                result.name,
                itemLink
            )

        if isCurrentCharacter then
            if trinketSummary and trinketSummary ~= "" then
                return string.format(
                    "UPGRADE? (%s)",
                    trinketSummary
                ),
                    1.00, 0.35, 0.82
            end

            return string.format(
                "UPGRADE?  (+%d ilvl%s)",
                result.upgrade,
                averageSuffix
            ),
                1.00, 0.35, 0.82
        end

        if trinketSummary and trinketSummary ~= "" then
            return string.format(
                "SEND TO: %s  (%s)",
                result.name,
                trinketSummary
            ),
                1.00, 0.20, 0.20
        end

        return string.format(
            "SEND TO: %s  (+%d ilvl%s)",
            result.name,
            result.upgrade,
            averageSuffix
        ),
            1.00, 0.20, 0.20
    end

    if result.kind == "future_upgrade" then
        local averageSuffix =
            result.weaponAverage
            and " - weap avg"
            or result.weaponOverAverage
            and " - over weap avg"
            or ""
        local specSummary =
            WGRGetTooltipTrinketCharacterSummary(
                result.name,
                itemLink
            )
        local specPrefix =
            specSummary
            and specSummary ~= ""
            and (specSummary .. ", ")
            or ""

        -- Future-level gear is storage, not an actionable current upgrade.
        -- If it is already on the intended character, present it with the
        -- same HOLD semantics as other holder gear rather than magenta.
        if isHeldHere then
            return string.format(
                "HOLD HERE  (%sLEVEL %d, +%d ilvl%s)",
                specPrefix,
                result.requiredLevel,
                result.upgrade,
                averageSuffix
            ),
                0.20, 0.60, 1.00
        end
        return string.format(
            "HOLD ON: %s  (%sLEVEL %d, +%d ilvl%s)",
            result.name,
            specPrefix,
            result.requiredLevel,
            result.upgrade,
            averageSuffix
        ),
            0.20, 0.60, 1.00
    end

    if result.kind == "holder" then
        local specSummary =
            WGRGetTooltipTrinketCharacterSummary(
                result.name,
                itemLink
            )
        local suffix =
            specSummary
            and specSummary ~= ""
            and string.format("  (%s)", specSummary)
            or ""

        if isHeldHere then
            return "HOLD HERE" .. suffix, 0.20, 0.60, 1.00
        end
        return string.format("HOLD ON: %s%s", result.name, suffix), 0.20, 0.60, 1.00
    end

    if result.kind == "unresolved" then
        return "WBGR: ROUTING DATA INCOMPLETE", 1.00, 0.75, 0.20
    end

    if result.kind == "unknown" then
        local specSummary =
            WGRGetTooltipTrinketCharacterSummary(
                result.name,
                itemLink
            )
        local suffix =
            specSummary
            and specSummary ~= ""
            and string.format(" (%s)", specSummary)
            or ""

        return string.format(
            "WBGR: CHECK %s%s",
            tostring(result.name or "ROUTING"),
            suffix
        ),
            1.00, 0.75, 0.20
    end

    if result.kind == "sell" or result.kind == "no_current_upgrade" then
        return "NO ROUTING UPGRADE", 0.72, 0.72, 0.72
    end

    return nil
end

local function WGRDetailedSelectedAction(
    option,
    currentCharacter,
    displayContext
)
    if not option
        or option.selected ~= true
    then
        return nil
    end

    if option.kind == "upgrade"
        or option.kind == "incomplete"
    then
        local isCurrent =
            currentCharacter
            and option.name
            and string.lower(tostring(option.name))
                == string.lower(tostring(currentCharacter))

        return isCurrent
            and "UPGRADE?"
            or "SEND TO"
    end

    if option.kind == "holder" then
        local source = displayContext and displayContext.source
        local isSharedWarbandSource = source == "WARBAND_BANK"
        local isCurrent =
            currentCharacter
            and option.name
            and string.lower(tostring(option.name))
                == string.lower(tostring(currentCharacter))

        return isCurrent and not isSharedWarbandSource
            and "HOLD HERE"
            or "HOLD ON"
    end

    if option.kind == "unknown"
        or option.kind == "unresolved"
    then
        return "CHECK"
    end

    return nil
end

local function WGRAddDetailedRoutingTrace(
    tooltip,
    trace,
    result,
    itemLink,
    displayContext
)
    tooltip:AddLine(
        "Routing path:",
        1.00,
        0.82,
        0.00
    )

    if not trace or #trace == 0 then
        tooltip:AddLine(
            "No other meaningful routing candidates",
            0.72,
            0.72,
            0.72
        )
        return
    end

    local currentCharacter =
        UnitName
        and UnitName("player")
        or nil

    for _, option in ipairs(trace) do
        local selectedAction =
            WGRDetailedSelectedAction(
                option,
                currentCharacter,
                displayContext
            )
        local actionText =
            selectedAction
            and ("  - " .. selectedAction)
            or ""
        local specSummary =
            option.name
            and WGRGetTooltipTrinketCharacterSummary(
                option.name,
                itemLink
            )
            or nil

        if option.kind == "upgrade" then
            local belowThreshold = option.meetsThreshold == false
            local suffix

            if option.selected == true then
                suffix =
                    belowThreshold
                    and "below-threshold fallback"
                    or nil
            elseif result and result.kind == "unknown" then
                suffix =
                    belowThreshold
                    and "below threshold; CHECK ahead"
                    or "CHECK ahead"
            elseif belowThreshold then
                suffix =
                    result
                    and result.kind == "upgrade"
                    and result.meetsThreshold == false
                    and "below threshold, lower priority"
                    or "below threshold"
            else
                suffix = "lower priority"
            end

            local usesAverage =
                option.weaponAverage
                and " - weap avg"
                or option.weaponOverAverage
                and " - over weap avg"
                or ""

            local valueText =
                option.name
                and WGRGetTooltipTrinketUpgradeSummary(
                    option.name,
                    itemLink
                )
                or nil

            if not valueText or valueText == "" then
                valueText = string.format(
                    "+%d ilvl%s",
                    tonumber(option.upgrade) or 0,
                    usesAverage
                )
            end

            local detailText = valueText
            if suffix and suffix ~= "" then
                detailText = detailText .. ", " .. suffix
            end

            local line = string.format(
                "%s  (%s)%s",
                tostring(option.name),
                detailText,
                actionText
            )

            if option.selected == true then
                local selectedIsCurrent =
                    currentCharacter
                    and option.name
                    and string.lower(tostring(option.name))
                        == string.lower(tostring(currentCharacter))

                if selectedIsCurrent then
                    tooltip:AddLine(line, 1.00, 0.35, 0.82)
                else
                    tooltip:AddLine(line, 1.00, 0.20, 0.20)
                end
            else
                tooltip:AddLine(line, 1.00, 0.35, 0.82)
            end

        elseif option.kind == "no_upgrade" then
            local prefix =
                specSummary
                and specSummary ~= ""
                and (specSummary .. ", ")
                or ""

            tooltip:AddLine(
                string.format(
                    "%s  (%sno upgrade)",
                    tostring(option.name),
                    prefix
                ),
                0.72,
                0.72,
                0.72
            )

        elseif option.kind == "incomplete" then
            local line = string.format(
                "%s  (paired setup incomplete)%s",
                tostring(option.name),
                actionText
            )

            if option.selected == true
                and selectedAction == "SEND TO"
            then
                tooltip:AddLine(line, 1.00, 0.20, 0.20)
            else
                tooltip:AddLine(line, 1.00, 0.35, 0.82)
            end

        elseif option.kind == "holder" then
            local levelText =
                option.requiredLevel
                and option.level
                and string.format(
                    "LEVEL %d / requires %d",
                    tonumber(option.level) or 0,
                    tonumber(option.requiredLevel) or 0
                )
                or "future use"
            local prefix =
                specSummary
                and specSummary ~= ""
                and (specSummary .. ", ")
                or ""

            tooltip:AddLine(
                string.format(
                    "%s  (%sHOLD: %s)%s",
                    tostring(option.name),
                    prefix,
                    levelText,
                    actionText
                ),
                0.20,
                0.60,
                1.00
            )

        elseif option.kind == "unresolved" then
            local prefix =
                specSummary
                and specSummary ~= ""
                and (specSummary .. ", ")
                or ""

            tooltip:AddLine(
                string.format(
                    "%s  (%sCHECK: future eligibility unresolved)%s",
                    tostring(option.name),
                    prefix,
                    actionText
                ),
                1.00,
                0.55,
                0.10
            )

        elseif option.kind == "unknown" then
            local prefix =
                specSummary
                and specSummary ~= ""
                and (specSummary .. ", ")
                or ""

            tooltip:AddLine(
                string.format(
                    "%s  (%sCHECK: unable to evaluate)%s",
                    tostring(option.name),
                    prefix,
                    actionText
                ),
                1.00,
                0.55,
                0.10
            )
        end
    end
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

    -- v0.65x used the temporary internal name FULL. Treat it as Detailed so
    -- an existing test SavedVariable continues to work after the rename.
    if tooltipStyle == "FULL" then
        tooltipStyle = "DETAILED"
    end

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
            displayContext,
            itemLink
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
            local currentCharacter =
                UnitName
                and UnitName("player")
                or nil
            local isCurrentCharacter =
                currentCharacter
                and string.lower(tostring(result.name))
                    == string.lower(tostring(currentCharacter))

            if result.kind == "upgrade"
                and isCurrentCharacter
            then
                -- Tooltip presentation stays intentionally independent of
                -- Gear Finder's Gold/Magenta ranking. For the logged-in
                -- character, a positive routed candidate is simply an
                -- UPGRADE?; Gear Finder remains the place that says CURRENT
                -- BEST / EQUIP NOW or presents tied-best choices.
                tooltip:AddLine(
                    "|cff00ff00WBGR:|r UPGRADE?",
                    1.00,
                    1.00,
                    1.00
                )
            else
                local verb

                if result.kind == "holder"
                    or result.kind == "future_upgrade"
                then
                    local source =
                        displayContext
                        and displayContext.source
                    local isSharedWarbandSource =
                        source == "WARBAND_BANK"

                    verb =
                        isCurrentCharacter
                        and not isSharedWarbandSource
                        and "HOLD HERE"
                        or "HOLD ON"
                else
                    verb = "SEND TO"
                end

                local targetSuffix =
                    verb == "HOLD HERE"
                    and ""
                    or (" " .. tostring(result.name))

                tooltip:AddLine(
                    "|cff00ff00WBGR:|r "
                    .. verb
                    .. targetSuffix,
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

    if shiftDown then
        tooltip:AddLine(" ")

        if tooltipStyle == "DETAILED" then
            WGRAddDetailedRoutingTrace(
                tooltip,
                alternatives,
                result,
                itemLink,
                displayContext
            )
        elseif alternatives and #alternatives > 0 then
            tooltip:AddLine(
                "Other options:",
                1.00,
                0.82,
                0.00
            )

            for _, option in ipairs(alternatives) do
                if option.kind == "upgrade" then
                    if option.setupIncomplete == true then
                        tooltip:AddLine(
                            string.format(
                                "%s  (Paired setup incomplete)",
                                option.name
                            ),
                            1.00,
                            0.35,
                            0.82
                        )
                    else
                        local belowThreshold =
                            option.meetsThreshold == false
                        local trinketSummary =
                            WGRGetTooltipTrinketUpgradeSummary(
                                option.name,
                                itemLink
                            )
                        local valueText =
                            trinketSummary
                            and trinketSummary ~= ""
                            and trinketSummary
                            or string.format(
                                "+%d ilvl",
                                tonumber(option.upgrade) or 0
                            )

                        tooltip:AddLine(
                            string.format(
                                belowThreshold
                                and "%s  (%s, below threshold)"
                                or "%s  (%s)",
                                option.name,
                                valueText
                            ),
                            1.00,
                            0.35,
                            0.82
                        )
                    end
                elseif option.kind == "holder" then
                    local specSummary =
                        WGRGetTooltipTrinketCharacterSummary(
                            option.name,
                            itemLink
                        )
                    local holdText =
                        specSummary
                        and specSummary ~= ""
                        and string.format("%s, Hold", specSummary)
                        or "Hold"

                    tooltip:AddLine(
                        string.format(
                            "%s  (%s)",
                            option.name,
                            holdText
                        ),
                        0.20,
                        0.60,
                        1.00
                    )
                elseif option.kind == "unresolved" then
                    local specSummary =
                        WGRGetTooltipTrinketCharacterSummary(
                            option.name,
                            itemLink
                        )
                    local prefix =
                        specSummary
                        and specSummary ~= ""
                        and (specSummary .. ", ")
                        or ""

                    tooltip:AddLine(
                        string.format(
                            "%s  (%sHolder unresolved)",
                            option.name,
                            prefix
                        ),
                        1.00,
                        0.55,
                        0.10
                    )
                elseif option.kind == "unknown" then
                    local specSummary =
                        WGRGetTooltipTrinketCharacterSummary(
                            option.name,
                            itemLink
                        )
                    local prefix =
                        specSummary
                        and specSummary ~= ""
                        and (specSummary .. ", ")
                        or ""

                    tooltip:AddLine(
                        string.format(
                            "%s  (%sUnable to evaluate)",
                            option.name,
                            prefix
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

    local configuredTooltipStyle =
        WarboundGearRouterDB
        and WarboundGearRouterDB.interface
        and WarboundGearRouterDB.interface.tooltipStyle
        or "PROMINENT"
    local fullTraceRequested =
        (configuredTooltipStyle == "DETAILED"
            or configuredTooltipStyle == "FULL")
        and IsShiftKeyDown
        and IsShiftKeyDown()
        or false

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

        if WGRItemIsCosmetic
            and WGRItemIsCosmetic(
                itemLink
            )
        then
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
                            fullTraceRequested
                            and BuildSimpleRoutingTrace(
                                newItemLevel,
                                itemMinLevel,
                                GetArmorPriorityList(armorType),
                                { armorSlotID },
                                recommendation
                            )
                            or BuildSimpleAlternatives(
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
                            fullTraceRequested
                            and BuildSimpleRoutingTrace(
                                newItemLevel,
                                itemMinLevel,
                                priorityList,
                                globalSlots,
                                recommendation,
                                comparisonProvider
                            )
                            or BuildSimpleAlternatives(
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
                            fullTraceRequested
                            and BuildOffhandRoutingTrace(
                                itemLink,
                                newItemLevel,
                                itemMinLevel,
                                recommendation
                            )
                            or BuildOffhandAlternatives(
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
                            fullTraceRequested
                            and BuildWeaponRoutingTrace(
                                itemLink,
                                newItemLevel,
                                itemMinLevel,
                                recommendation
                            )
                            or BuildWeaponAlternatives(
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
local cleanupRefreshSerial = 0

-- BAG_UPDATE tells the core which concrete container changed. Keep the same
-- information for Bagnon overlays so ordinary item moves only re-evaluate
-- buttons belonging to the affected containers instead of rebuilding every
-- visible Bagnon button. Full refreshes are still used for routing/config UI
-- changes, startup, and bag visibility changes.
local cleanupDirtyBags = {}

-- Full overlay passes build a lightweight index of visible Bagnon buttons by
-- Blizzard bag/container ID. Incremental BAG_UPDATE refreshes can then jump
-- directly to the affected container buttons instead of walking the entire
-- Bagnon global button namespace again. The index is runtime-only and is
-- conservatively rebuilt on every full overlay refresh.
local bagnonButtonsByBag = {}
local bagnonButtonsByBagSlot = {}
local bagnonOverlaySlotSignatures = {}

local function WGRIndexBagnonButton(button)
    if not button then return end

    local bagID = tonumber(button.bag)
    local slotID = button.GetID and tonumber(button:GetID()) or nil
    if bagID == nil then return end

    local list = bagnonButtonsByBag[bagID]
    if not list then
        list = {}
        bagnonButtonsByBag[bagID] = list
    end

    list[#list + 1] = button

    if slotID and slotID > 0 then
        local bySlot = bagnonButtonsByBagSlot[bagID]
        if not bySlot then
            bySlot = {}
            bagnonButtonsByBagSlot[bagID] = bySlot
        end

        local slotButtons = bySlot[slotID]
        if not slotButtons then
            slotButtons = {}
            bySlot[slotID] = slotButtons
        end

        slotButtons[#slotButtons + 1] = button
    end
end

local function WGRReadOverlayBagSignatures(bagID)
    local signatures = {}
    if not C_Container
        or not C_Container.GetContainerNumSlots
        or not C_Container.GetContainerItemLink
    then
        return signatures
    end

    local slots = C_Container.GetContainerNumSlots(bagID) or 0
    for slotID = 1, slots do
        signatures[slotID] = C_Container.GetContainerItemLink(bagID, slotID) or false
    end
    return signatures
end

local function WGRGetChangedOverlaySlots(bagID)
    local previous = bagnonOverlaySlotSignatures[bagID]
    local current = WGRReadOverlayBagSignatures(bagID)
    bagnonOverlaySlotSignatures[bagID] = current

    if type(previous) ~= "table" then
        return nil, true
    end

    local changed = {}
    local maxSlot = 0
    for slotID in pairs(previous) do
        if slotID > maxSlot then maxSlot = slotID end
    end
    for slotID in pairs(current) do
        if slotID > maxSlot then maxSlot = slotID end
    end

    for slotID = 1, maxSlot do
        if previous[slotID] ~= current[slotID] then
            changed[slotID] = true
        end
    end

    return changed, false
end

function WGRMarkBagnonOverlayBagDirty(bagID)
    bagID = tonumber(bagID)
    if bagID ~= nil then
        cleanupDirtyBags[bagID] = true
    end
end

local function WGRTakeBagnonOverlayDirtyBags()
    local dirty = cleanupDirtyBags
    cleanupDirtyBags = {}
    return dirty
end

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

    if WGRItemIsCosmetic
        and WGRItemIsCosmetic(
            itemLink
        )
    then
        return nil, "unsupported"
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

-- Shared read-only classifier used by Gear Search MAIL tracking so mailed
-- items use the exact same buckets as BAG/PBK/WBK snapshots.
function WGRClassifyHeldGearItem(itemLink)
    return WGRHeldGearClassifyItem(itemLink)
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

-- Runtime-only per-slot caches for Bags and Personal Bank. These keep the
-- persisted heldGearSnapshots format unchanged while allowing a dirty-container
-- refresh to reroute only slots whose item link actually changed.
local WGRHeldSlotCaches = {
    BAGS = {},
    PERSONAL_BANK = {},
}

local function WGRItemLocationIsSoulbound(itemLocation)
    if not itemLocation
        or not C_Item
        or not C_Item.IsBound
    then
        return false
    end

    local ok, isBound = pcall(C_Item.IsBound, itemLocation)
    return ok and isBound == true
end

local function WGRContainerItemIsSoulbound(bagID, slotID)
    if not ItemLocation
        or not ItemLocation.CreateFromBagAndSlot
    then
        return false
    end

    local ok, itemLocation = pcall(
        ItemLocation.CreateFromBagAndSlot,
        ItemLocation,
        bagID,
        slotID
    )

    return ok and WGRItemLocationIsSoulbound(itemLocation)
end

local function WGREquippedItemIsSoulbound(slotID)
    if not ItemLocation
        or not ItemLocation.CreateFromEquipmentSlot
    then
        return false
    end

    local ok, itemLocation = pcall(
        ItemLocation.CreateFromEquipmentSlot,
        ItemLocation,
        slotID
    )

    return ok and WGRItemLocationIsSoulbound(itemLocation)
end

local function WGRHeldGearRawKey(itemLink)
    if not itemLink then return nil end
    local section, category, subtype = WGRHeldGearClassifyItem(itemLink)
    if not section or not category then return nil end
    return table.concat({
        tostring(section),
        tostring(category),
        tostring(subtype or ""),
    }, "\031")
end

local function WGRHeldGearMailContinuityMatches(itemLink)
    if not itemLink or not WarboundGearRouterDB then return false end
    local characterName = UnitName("player")
    if not characterName then return false end
    local byCharacter = WarboundGearRouterDB.gearSearchMailContinuity
    local records = byCharacter and byCharacter[string.lower(characterName)]
    if type(records) ~= "table" then return false end

    local itemID
    if C_Item and C_Item.GetItemInfoInstant then
        itemID = C_Item.GetItemInfoInstant(itemLink)
    end
    itemID = tonumber(itemID) or tonumber(tostring(itemLink):match("item:(%d+)"))
    local gearKey = WGRHeldGearRawKey(itemLink)
    if not itemID or not gearKey then return false end

    local identity = tostring(itemID) .. "\031" .. gearKey
    return (tonumber(records[identity]) or 0) > 0
end

local function WGRHeldGearBuildSlotState(
    bagID,
    slotID,
    itemLink
)
    local state = {
        signature = itemLink or false,
    }

    -- Cross-spec owned-component routing uses committed gear only. A
    -- Warbound/BoE weapon in Bags/PBK is still a routing candidate and must
    -- not raise the destination's routing floor merely because it is sitting
    -- there. Only a physically-confirmed Soulbound weapon/off-hand enters the
    -- owned component cache.
    if itemLink and WGRContainerItemIsSoulbound(bagID, slotID) then
        local weaponKind = GetWeaponKind and GetWeaponKind(itemLink) or nil
        local offhandKind = WGRGetOffhandKind and WGRGetOffhandKind(itemLink) or nil
        if weaponKind or offhandKind == "SHIELD" or offhandKind == "OFFHAND" then
            state.ownedWeaponLink = itemLink
            state.ownedWeaponLevel = tonumber(GetItemLevel(itemLink)) or 0
        end

        local instant = GetInstantItemInfo and GetInstantItemInfo(itemLink) or nil
        if instant and instant.equipLoc == "INVTYPE_TRINKET" then
            state.ownedTrinketLink = itemLink
            state.ownedTrinketLevel = tonumber(GetItemLevel(itemLink)) or 0
        end
    end

    if not itemLink
        or not IsTransferableContainerItem(
            bagID,
            slotID,
            itemLink
        )
    then
        return state
    end

    state.transferable = true

    local recommendation =
        WGRBuildLoadedItemRecommendation
        and WGRBuildLoadedItemRecommendation(itemLink)
        or nil

    local isDispose =
        recommendation
        and (
            recommendation.kind == "sell"
            or recommendation.kind == "no_current_upgrade"
        )

    -- Gear Search location continuity is separate from routing. If WBGR
    -- previously tracked this exact item/category through MAIL, keep indexing
    -- it after retrieval even when the recipient-side recommendation is now
    -- sell/no_current_upgrade. This does not broaden normal BAG/PBK indexing.
    local preserveMailTracked = WGRHeldGearMailContinuityMatches(itemLink)

    if (not isDispose) or preserveMailTracked then
        local section, category, subtype =
            WGRHeldGearClassifyItem(itemLink)

        if section and category then
            state.included = true
            state.section = section
            state.category = category
            state.subtype = subtype
        end
    end

    return state
end

local function WGRHeldGearScanContainerCached(
    cacheGroup,
    bagID,
    forceRoute,
    perfLabel
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

    local groupCache = WGRHeldSlotCaches[cacheGroup]
    if not groupCache then
        groupCache = {}
        WGRHeldSlotCaches[cacheGroup] = groupCache
    end

    local oldCache = groupCache[bagID] or {}
    local newCache = {}
    local slots = C_Container.GetContainerNumSlots(bagID) or 0
    local perfStart = WGRPerfNow and WGRPerfNow() or 0
    local routingMS = 0
    local changedCount = 0
    local routedCount = 0
    local transferableCount = 0

    for slotID = 1, slots do
        local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
        local signature = itemLink or false
        local old = oldCache[slotID]
        local state

        if (not forceRoute)
            and old
            and old.signature == signature
        then
            state = old
        else
            changedCount = changedCount + 1
            local routeStart = WGRPerfNow and WGRPerfNow() or 0
            state = WGRHeldGearBuildSlotState(bagID, slotID, itemLink)
            if state.transferable then
                routedCount = routedCount + 1
            end
            if routeStart > 0 and WGRPerfNow then
                routingMS = routingMS + (WGRPerfNow() - routeStart)
            end
        end

        newCache[slotID] = state

        if state.transferable then
            transferableCount = transferableCount + 1
        end

        if state.included then
            WGRHeldGearAddEntry(
                result,
                state.section,
                state.category,
                state.subtype
            )
        end
    end

    groupCache[bagID] = newCache

    if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
        WGRPerfRecord(
            perfLabel or "held_container_scan",
            WGRPerfNow() - perfStart,
            string.format(
                "bag=%s slots=%d transferable=%d changed=%d routed=%d routing=%.1fms",
                tostring(bagID),
                slots,
                transferableCount,
                changedCount,
                routedCount,
                routingMS
            )
        )
    end

    return result
end

local function WGRAggregateHeldContainerSnapshots(containerSnapshots)
    local result = {
        total = 0,
        entries = {},
        scanned = time(),
    }

    for _, containerSnapshot in pairs(containerSnapshots or {}) do
        if type(containerSnapshot) == "table" then
            result.total = result.total + (tonumber(containerSnapshot.total) or 0)
            for key, count in pairs(containerSnapshot.entries or {}) do
                result.entries[key] =
                    (result.entries[key] or 0) + (tonumber(count) or 0)
            end
        end
    end

    return result
end

local WGRHeldContainerSnapshots = {
    BAGS = {},
    PERSONAL_BANK = {},
}

local function WGRCollectOwnedWeaponsFromHeldCache(cacheGroup)
    local result = {}
    local group = WGRHeldSlotCaches[cacheGroup] or {}

    for bagID, slots in pairs(group) do
        for slotID, state in pairs(slots or {}) do
            if state and state.ownedWeaponLink then
                local level = tonumber(state.ownedWeaponLevel) or 0
                if level <= 0 then
                    level = tonumber(GetItemLevel(state.ownedWeaponLink)) or 0
                    state.ownedWeaponLevel = level
                end

                if level > 0 then
                    result[#result + 1] = {
                        link = state.ownedWeaponLink,
                        level = level,
                        bagID = tonumber(bagID),
                        slotID = tonumber(slotID),
                    }
                end
            end
        end
    end

    return result
end

local function WGRRefreshOwnedWeaponComponentsForCurrentCharacter(
    characterName,
    updateBags,
    updateBank
)
    InitializeDatabase()
    if not characterName then return end

    local key = string.lower(characterName)
    local owned = WarboundGearRouterDB.ownedWeaponComponents[key] or {
        character = characterName,
        bags = {},
        bank = {},
        equipped = {},
    }

    owned.character = characterName

    if updateBags then
        owned.bags = WGRCollectOwnedWeaponsFromHeldCache("BAGS")
        owned.bagsObserved = true
    end

    if updateBank then
        owned.bank = WGRCollectOwnedWeaponsFromHeldCache("PERSONAL_BANK")
        owned.bankObserved = true
    end

    local equipped = {}
    for _, slotID in ipairs({ 16, 17 }) do
        local itemLink = GetInventoryItemLink and GetInventoryItemLink("player", slotID) or nil
        if itemLink and WGREquippedItemIsSoulbound(slotID) then
            local weaponKind = GetWeaponKind and GetWeaponKind(itemLink) or nil
            local offhandKind = WGRGetOffhandKind and WGRGetOffhandKind(itemLink) or nil
            if weaponKind or offhandKind == "SHIELD" or offhandKind == "OFFHAND" then
                equipped[#equipped + 1] = {
                    link = itemLink,
                    level = tonumber(GetItemLevel(itemLink)) or 0,
                    slotID = slotID,
                }
            end
        end
    end

    owned.equipped = equipped
    owned.equippedObserved = true
    owned.updated = time()
    WarboundGearRouterDB.ownedWeaponComponents[key] = owned
end

local function WGRCollectOwnedTrinketsFromHeldCache(cacheGroup)
    local result = {}
    local group = WGRHeldSlotCaches[cacheGroup] or {}

    for bagID, slots in pairs(group) do
        for slotID, state in pairs(slots or {}) do
            if state and state.ownedTrinketLink then
                local level = tonumber(state.ownedTrinketLevel) or 0
                if level <= 0 then
                    level = tonumber(GetItemLevel(state.ownedTrinketLink)) or 0
                    state.ownedTrinketLevel = level
                end

                if level > 0 then
                    result[#result + 1] = {
                        link = state.ownedTrinketLink,
                        level = level,
                        bagID = tonumber(bagID),
                        slotID = tonumber(slotID),
                    }
                end
            end
        end
    end

    return result
end

local function WGRApplyLiveTrinketSpecEligibility(
    records,
    classID
)
    if not WGRGetLiveTrinketSpecEligibilitySnapshot
        or not classID
    then
        return
    end

    for _, data in ipairs(records or {}) do
        if data and data.link then
            local eligibility, complete =
                WGRGetLiveTrinketSpecEligibilitySnapshot(
                    data.link,
                    classID
                )

            data.specEligibility = eligibility or {}
            data.specEligibilityComplete = complete == true
            data.specEligibilityUpdated = time()
        end
    end
end

local function WGRRefreshOwnedTrinketComponentsForCurrentCharacter(
    characterName,
    updateBags,
    updateBank
)
    InitializeDatabase()
    if not characterName then return end

    local key = string.lower(characterName)
    local owned = WarboundGearRouterDB.ownedTrinketComponents[key] or {
        character = characterName,
        bags = {},
        bank = {},
        equipped = {},
    }

    owned.character = characterName

    local classID =
        UnitClass
        and select(3, UnitClass("player"))
        or nil

    if updateBags then
        owned.bags = WGRCollectOwnedTrinketsFromHeldCache("BAGS")
        WGRApplyLiveTrinketSpecEligibility(owned.bags, classID)
        owned.bagsObserved = true
    end

    if updateBank then
        owned.bank = WGRCollectOwnedTrinketsFromHeldCache("PERSONAL_BANK")
        WGRApplyLiveTrinketSpecEligibility(owned.bank, classID)
        owned.bankObserved = true
    end

    local equipped = {}
    for _, slotID in ipairs({ 13, 14 }) do
        local itemLink = GetInventoryItemLink and GetInventoryItemLink("player", slotID) or nil
        if itemLink and WGREquippedItemIsSoulbound(slotID) then
            local instant = GetInstantItemInfo and GetInstantItemInfo(itemLink) or nil
            if instant and instant.equipLoc == "INVTYPE_TRINKET" then
                local level = tonumber(GetItemLevel(itemLink)) or 0
                if level > 0 then
                    equipped[#equipped + 1] = {
                        link = itemLink,
                        level = level,
                        slotID = slotID,
                    }
                end
            end
        end
    end

    WGRApplyLiveTrinketSpecEligibility(equipped, classID)
    owned.equipped = equipped
    owned.equippedObserved = true
    owned.updated = time()
    WarboundGearRouterDB.ownedTrinketComponents[key] = owned
end

local function WGRHeldGearScanBagIDs(
    bagIDs,
    perfLabel
)
    local result = {
        total = 0,
        entries = {},
        scanned = time(),
    }

    local perfStart = WGRPerfNow and WGRPerfNow() or 0
    local routingMS = 0
    local transferableCount = 0
    local slotCount = 0

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
            slotCount = slotCount + 1

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
                transferableCount = transferableCount + 1

                local routeStart = WGRPerfNow and WGRPerfNow() or 0
                local recommendation =
                    WGRBuildLoadedItemRecommendation
                    and WGRBuildLoadedItemRecommendation(
                        itemLink
                    )
                    or nil
                if routeStart > 0 and WGRPerfNow then
                    routingMS = routingMS + (WGRPerfNow() - routeStart)
                end

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

    if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
        local elapsed = WGRPerfNow() - perfStart
        local label = perfLabel or "held_scan"
        WGRPerfRecord(
            label,
            elapsed,
            string.format(
                "slots=%d transferable=%d routing=%.1fms",
                slotCount,
                transferableCount,
                routingMS
            )
        )
        WGRPerfRecord(
            label .. "_routing",
            routingMS,
            string.format("items=%d", transferableCount)
        )
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
    includePersonalBank,
    scanBags,
    scanPersonalBank,
    dirtyBagIDs,
    dirtyPersonalBankBagIDs
)
    local perfStart = WGRPerfNow and WGRPerfNow() or 0
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

    if scanBags == nil then
        scanBags = true
    end

    if scanPersonalBank == nil then
        scanPersonalBank = includePersonalBank and true or false
    end

    if scanBags then
        local bagIDs = WGRHeldGearBagIDs()
        local partial =
            type(dirtyBagIDs) == "table"
            and next(dirtyBagIDs) ~= nil
            and next(WGRHeldContainerSnapshots.BAGS) ~= nil

        if not partial then
            WGRHeldSlotCaches.BAGS = {}
            WGRHeldContainerSnapshots.BAGS = {}
            for _, bagID in ipairs(bagIDs) do
                WGRHeldContainerSnapshots.BAGS[bagID] =
                    WGRHeldGearScanContainerCached(
                        "BAGS",
                        bagID,
                        true,
                        "held_bags_scan"
                    )
            end
        else
            local valid = {}
            for _, bagID in ipairs(bagIDs) do valid[bagID] = true end
            for bagID in pairs(dirtyBagIDs) do
                bagID = tonumber(bagID)
                if bagID and valid[bagID] then
                    WGRHeldContainerSnapshots.BAGS[bagID] =
                        WGRHeldGearScanContainerCached(
                            "BAGS",
                            bagID,
                            false,
                            "held_bags_scan"
                        )
                end
            end
        end

        snapshot.bags =
            WGRAggregateHeldContainerSnapshots(
                WGRHeldContainerSnapshots.BAGS
            )
    end

    if includePersonalBank and scanPersonalBank then
        local bankIDs = WGRHeldGearPersonalBankIDs()
        local hasReadableBank = false

        for _, bagID in ipairs(bankIDs) do
            if (C_Container.GetContainerNumSlots(bagID) or 0) > 0 then
                hasReadableBank = true
                break
            end
        end

        -- Do not erase a useful cached bank snapshot if this event came
        -- from another bank type and Character Bank containers are unavailable.
        if hasReadableBank then
            local partial =
                type(dirtyPersonalBankBagIDs) == "table"
                and next(dirtyPersonalBankBagIDs) ~= nil
                and next(WGRHeldContainerSnapshots.PERSONAL_BANK) ~= nil

            if not partial then
                WGRHeldSlotCaches.PERSONAL_BANK = {}
                WGRHeldContainerSnapshots.PERSONAL_BANK = {}
                for _, bagID in ipairs(bankIDs) do
                    if (C_Container.GetContainerNumSlots(bagID) or 0) > 0 then
                        WGRHeldContainerSnapshots.PERSONAL_BANK[bagID] =
                            WGRHeldGearScanContainerCached(
                                "PERSONAL_BANK",
                                bagID,
                                true,
                                "held_bank_scan"
                            )
                    end
                end
            else
                local valid = {}
                for _, bagID in ipairs(bankIDs) do valid[bagID] = true end
                for bagID in pairs(dirtyPersonalBankBagIDs) do
                    bagID = tonumber(bagID)
                    if bagID
                        and valid[bagID]
                        and (C_Container.GetContainerNumSlots(bagID) or 0) > 0
                    then
                        WGRHeldContainerSnapshots.PERSONAL_BANK[bagID] =
                            WGRHeldGearScanContainerCached(
                                "PERSONAL_BANK",
                                bagID,
                                false,
                                "held_bank_scan"
                            )
                    end
                end
            end

            snapshot.bank =
                WGRAggregateHeldContainerSnapshots(
                    WGRHeldContainerSnapshots.PERSONAL_BANK
                )
        end
    end

    -- Keep the physical owned-weapon cache synchronized with the same
    -- dirty-container work we already performed. No additional bag/bank scan
    -- is introduced here. Equipped slots are only two direct lookups.
    WGRRefreshOwnedWeaponComponentsForCurrentCharacter(
        characterName,
        scanBags == true,
        includePersonalBank and scanPersonalBank == true
    )

    -- Trinkets use the same already-built dirty-slot cache as weapons, so
    -- keeping a Soulbound ownership pool adds no extra container scan.
    WGRRefreshOwnedTrinketComponentsForCurrentCharacter(
        characterName,
        scanBags == true,
        includePersonalBank and scanPersonalBank == true
    )

    snapshot.updated =
        time()

    WarboundGearRouterDB.heldGearSnapshots[
        key
    ] =
        snapshot

    if WGRNotifyGearSearchChanged then
        WGRNotifyGearSearchChanged()
    end

    if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
        WGRPerfRecord(
            "held_snapshot_total",
            WGRPerfNow() - perfStart,
            (scanBags and scanPersonalBank and "bags+personal bank")
                or (scanBags and "bags only")
                or (scanPersonalBank and "personal bank only")
                or "no storage scan"
        )
    end

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

-- Runtime-only per-slot cache for Warband Bank tabs. This keeps the
-- persisted snapshot format unchanged while allowing a dirty-tab refresh to
-- reroute only slots whose item link actually changed. The cache is rebuilt
-- conservatively on a full WBK refresh (bank open/config refresh/reload).
local WGRWarbandSlotCache = {}

local function WGRHeldGearScanWarbandTabCached(bagID)
    local result = {
        total = 0,
        entries = {},
        scanned = time(),
    }

    local perfStart = WGRPerfNow and WGRPerfNow() or 0
    local routingMS = 0
    local transferableCount = 0
    local changedCount = 0
    local routedCount = 0

    if not C_Container
        or not C_Container.GetContainerNumSlots
        or not C_Container.GetContainerItemLink
    then
        return result
    end

    local oldCache = WGRWarbandSlotCache[bagID] or {}
    local newCache = {}
    local slots = C_Container.GetContainerNumSlots(bagID) or 0

    for slotID = 1, slots do
        local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
        local signature = itemLink or false
        local old = oldCache[slotID]
        local state

        if old and old.signature == signature then
            state = old
        else
            changedCount = changedCount + 1
            state = { signature = signature }

            if itemLink
                and IsTransferableContainerItem(
                    bagID,
                    slotID,
                    itemLink
                )
            then
                state.transferable = true
                routedCount = routedCount + 1

                local routeStart = WGRPerfNow and WGRPerfNow() or 0
                local recommendation =
                    WGRBuildLoadedItemRecommendation
                    and WGRBuildLoadedItemRecommendation(itemLink)
                    or nil
                if routeStart > 0 and WGRPerfNow then
                    routingMS = routingMS + (WGRPerfNow() - routeStart)
                end

                local isDispose =
                    recommendation
                    and (
                        recommendation.kind == "sell"
                        or recommendation.kind == "no_current_upgrade"
                    )

                if not isDispose then
                    local section, category, subtype =
                        WGRHeldGearClassifyItem(itemLink)
                    if section and category then
                        state.included = true
                        state.section = section
                        state.category = category
                        state.subtype = subtype
                    end
                end
            end
        end

        newCache[slotID] = state

        if state.transferable then
            transferableCount = transferableCount + 1
        end

        if state.included then
            WGRHeldGearAddEntry(
                result,
                state.section,
                state.category,
                state.subtype
            )
        end
    end

    WGRWarbandSlotCache[bagID] = newCache

    if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
        WGRPerfRecord(
            "warband_tab_scan",
            WGRPerfNow() - perfStart,
            string.format(
                "slots=%d transferable=%d changed=%d routed=%d routing=%.1fms",
                slots,
                transferableCount,
                changedCount,
                routedCount,
                routingMS
            )
        )
        WGRPerfRecord(
            "warband_tab_scan_routing",
            routingMS,
            string.format("items=%d", routedCount)
        )
    end

    return result
end

local function WGRAggregateWarbandTabSnapshots(tabSnapshots)
    local result = {
        total = 0,
        entries = {},
        scanned = time(),
    }

    for _, tabSnapshot in pairs(tabSnapshots or {}) do
        if type(tabSnapshot) == "table" then
            result.total = result.total + (tonumber(tabSnapshot.total) or 0)
            for key, count in pairs(tabSnapshot.entries or {}) do
                result.entries[key] =
                    (result.entries[key] or 0) + (tonumber(count) or 0)
            end
        end
    end

    return result
end

function WGRRefreshWarbandHeldGearSnapshot(dirtyBagIDs)
    local perfStart = WGRPerfNow and WGRPerfNow() or 0
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

    local snapshot =
        WarboundGearRouterDB.heldGearSnapshots["__warband_bank"]
        or {
            character = "Warband Bank",
        }

    snapshot.character = "Warband Bank"

    -- Per-tab snapshots let BAG_UPDATE refresh only the Warband Bank tab that
    -- actually changed. Older saves have only the aggregate snapshot, so the
    -- first refresh after upgrading seeds every readable tab conservatively.
    local tabSnapshots = snapshot.warbandTabs
    local partialRequested = type(dirtyBagIDs) == "table"
    local canRefreshPartial = partialRequested and type(tabSnapshots) == "table"

    if not canRefreshPartial then
        -- A full refresh is authoritative and must not reuse routing results
        -- from an earlier configuration/spec state. Seed the runtime slot
        -- cache again from scratch.
        WGRWarbandSlotCache = {}
        tabSnapshots = {}
        for _, bagID in ipairs(ids) do
            if (C_Container.GetContainerNumSlots(bagID) or 0) > 0 then
                tabSnapshots[bagID] =
                    WGRHeldGearScanWarbandTabCached(bagID)
            end
        end
    else
        local validIDs = {}
        for _, bagID in ipairs(ids) do
            validIDs[bagID] = true
        end

        for bagID in pairs(dirtyBagIDs) do
            bagID = tonumber(bagID)
            if bagID
                and validIDs[bagID]
                and (C_Container.GetContainerNumSlots(bagID) or 0) > 0
            then
                tabSnapshots[bagID] =
                    WGRHeldGearScanWarbandTabCached(bagID)
            end
        end
    end

    snapshot.warbandTabs = tabSnapshots
    snapshot.warband = WGRAggregateWarbandTabSnapshots(tabSnapshots)
    snapshot.updated = time()

    WarboundGearRouterDB.heldGearSnapshots["__warband_bank"] = snapshot

    if WGRNotifyGearSearchChanged then
        WGRNotifyGearSearchChanged()
    end

    if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
        local refreshedTabs = 0
        if canRefreshPartial then
            for bagID in pairs(dirtyBagIDs or {}) do
                if tonumber(bagID) then
                    refreshedTabs = refreshedTabs + 1
                end
            end
        else
            for _ in pairs(tabSnapshots) do
                refreshedTabs = refreshedTabs + 1
            end
        end

        WGRPerfRecord(
            "warband_snapshot_total",
            WGRPerfNow() - perfStart,
            string.format(
                "mode=%s tabs=%d",
                canRefreshPartial and "dirty-tab" or "full",
                refreshedTabs
            )
        )
    end

    return snapshot
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
            mail = 0,
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
            mail = 0,
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
        mail = 0,
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

    -- MAIL is tracked separately from BAG/PBK snapshots. Fold only WBGR's
    -- item-aware tracked gear into the roster summary; unrelated mailbox
    -- attachments are intentionally not counted.
    local mailTracking =
        WarboundGearRouterDB
        and WarboundGearRouterDB.mailGearTracking
        or nil

    if type(mailTracking) == "table" then
        local mailEntry =
            mailTracking[
                string.lower(
                    characterName
                )
            ]

        if type(mailEntry) == "table" then
            for _, item
                in ipairs(
                    mailEntry.items
                    or {}
                )
            do
                local gearKey =
                    type(item) == "table"
                    and item.gearKey
                    or nil

                if gearKey
                    and gearKey ~= ""
                then
                    summary.mail =
                        summary.mail + 1

                    summary.total =
                        summary.total + 1

                    summary.entries[gearKey] =
                        (
                            summary.entries[gearKey]
                            or 0
                        )
                        + 1
                end
            end
        end
    end

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
        and result.kind ~= "unknown"
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
        and result.kind ~= "unknown"
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

    -- A Removed character and that character's Bags/PBK are outside WBGR.
    -- Keep shared Warband Bank handling above available, but never classify
    -- or overlay character-local inventory while logged into a Removed alt.
    local currentName = UnitName("player")
    if currentName
        and WGRIsCharacterRemoved
        and WGRIsCharacterRemoved(currentName)
    then
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

function RefreshBagnonCleanupOverlays(dirtyBags)
    local perfStart = WGRPerfNow and WGRPerfNow() or 0
    local incremental = type(dirtyBags) == "table"
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

    cleanupGeneration = cleanupGeneration + 1

    local generation = cleanupGeneration
    local visible = 0
    local evaluated = 0
    local indexed = 0

    local function ProcessButton(button)
        if not button or not button.IsShown or not button:IsShown() then
            return
        end

        visible = visible + 1

        local bagID = button.bag

        -- Clear affected/reused slots first so empty or changed buttons cannot
        -- retain an old overlay. Unaffected bags deliberately keep their
        -- existing overlay state during an incremental refresh.
        HideCleanupOverlay(button)
        HideWarbankTakeOverlay(button)
        HideGoldEquipOverlay(button)
        HideTiedBestOverlay(button)
        HideDisposeOverlay(button)

        if IsCurrentCharacterBagnonButton(button) then
            local slotID = button.GetID and button:GetID()

            if type(bagID) == "number"
                and type(slotID) == "number"
                and slotID > 0
            then
                evaluated = evaluated + 1
                EvaluateBagnonButton(button, generation)
            end
        end
    end

    if incremental and next(bagnonButtonsByBag) then
        -- Slot-diff fast path. BAG_UPDATE identifies the dirty container; compare
        -- that container's current slot links against the last overlay snapshot
        -- and only re-evaluate Bagnon buttons whose exact bag+slot changed.
        -- If a bag has not been seeded yet, conservatively refresh that bag once.
        for bagID in pairs(dirtyBags) do
            bagID = tonumber(bagID)
            if bagID ~= nil then
                local changedSlots, needsSeed = WGRGetChangedOverlaySlots(bagID)
                local bySlot = bagnonButtonsByBagSlot[bagID]
                local list = bagnonButtonsByBag[bagID]
                local usedFallback = needsSeed or type(bySlot) ~= "table"

                if not usedFallback and changedSlots then
                    for slotID in pairs(changedSlots) do
                        local slotButtons = bySlot[slotID]
                        if slotButtons then
                            for _, button in ipairs(slotButtons) do
                                indexed = indexed + 1
                                if button
                                    and tonumber(button.bag) == bagID
                                    and button.GetID
                                    and tonumber(button:GetID()) == slotID
                                then
                                    ProcessButton(button)
                                end
                            end
                        else
                            -- Bagnon may have recycled/rebuilt frames since the
                            -- last full index. Fall back to the dirty bag rather
                            -- than risk leaving a stale overlay behind.
                            usedFallback = true
                            break
                        end
                    end
                end

                if usedFallback and list then
                    for _, button in ipairs(list) do
                        indexed = indexed + 1
                        if button and tonumber(button.bag) == bagID then
                            ProcessButton(button)
                        end
                    end
                end
            end
        end
    else
        -- Full refresh / conservative fallback. Rebuild the runtime index while
        -- walking Bagnon's global button namespace. Startup and bag-visibility
        -- hooks intentionally use this path so later dirty refreshes are cheap.
        bagnonButtonsByBag = {}
        bagnonButtonsByBagSlot = {}
        bagnonOverlaySlotSignatures = {}
        local misses = 0

        for i = 1, 2500 do
            local button = _G["BagnonContainerItem" .. i]

            if button then
                misses = 0

                if button.IsShown and button:IsShown() then
                    WGRIndexBagnonButton(button)

                    local bagID = button.bag
                    local shouldEvaluate =
                        (not incremental)
                        or (type(bagID) == "number" and dirtyBags[bagID])

                    if shouldEvaluate then
                        ProcessButton(button)
                    end
                end
            else
                misses = misses + 1

                if i > 1000 and misses >= 300 then
                    break
                end
            end
        end
    end

    if not incremental then
        for bagID in pairs(bagnonButtonsByBag) do
            bagnonOverlaySlotSignatures[bagID] = WGRReadOverlayBagSignatures(bagID)
        end
    end

    if perfStart > 0 and WGRPerfNow and WGRPerfRecord then
        WGRPerfRecord(
            "bagnon_overlays",
            WGRPerfNow() - perfStart,
            string.format(
                "visible=%d evaluated=%d mode=%s indexed=%d",
                visible,
                evaluated,
                incremental and "indexed-dirty" or "full",
                indexed
            )
        )
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

        if WGRGearFinderSetMasterPaused then
            WGRGearFinderSetMasterPaused(true)
        end
    else
        -- Route any BAG-only acquisitions/rearrangements that accumulated
        -- while paused and reconcile readable storage before restoring the
        -- expensive presentation layers.
        if WGRRequestInventoryRefresh then
            WGRRequestInventoryRefresh(
                0.05,
                true,
                false
            )
        end

        C_Timer.After(
            0.25,
            function()
                if WGRRoutingIsPaused() then
                    return
                end

                RefreshBagnonCleanupOverlays()

                if WGRGearFinderSetMasterPaused then
                    WGRGearFinderSetMasterPaused(false)
                end
            end
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
                "|cffffff00WBGR PAUSED.|r Live tooltips, overlays, Gear Finder, and BAG-only routing are paused. Storage/mail/spec tracking remains active."
            )
        else
            print(
                "|cff00ff00WBGR ACTIVE.|r Full live routing, tooltips, overlays, and Gear Finder are enabled."
            )
        end
    end
end


function QueueCleanupRefresh(useDirtyBags)
    cleanupRefreshSerial =
        cleanupRefreshSerial + 1

    local serial =
        cleanupRefreshSerial

    C_Timer.After(
        0.25,
        function()
            if serial ~= cleanupRefreshSerial then
                return
            end

            if useDirtyBags then
                local dirty = WGRTakeBagnonOverlayDirtyBags()
                if next(dirty) then
                    RefreshBagnonCleanupOverlays(dirty)
                end
            else
                -- A full refresh supersedes any pending incremental state.
                cleanupDirtyBags = {}
                RefreshBagnonCleanupOverlays()
            end
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


local WGR_TOOLTIP_MAX_RETRIES = 2

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

    if tooltip.__WGRRetryCountItemLink
        ~= itemLink
    then
        tooltip.__WGRRetryCountItemLink =
            itemLink
        tooltip.__WGRRetryCount =
            0
    end

    if (
        tooltip.__WGRRetryCount
        or 0
    ) >= WGR_TOOLTIP_MAX_RETRIES
    then
        return
    end

    tooltip.__WGRRetryCount =
        (
            tooltip.__WGRRetryCount
            or 0
        )
        + 1

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

    local currentName = UnitName("player")
    if currentName
        and WGRIsCharacterRemoved
        and WGRIsCharacterRemoved(currentName)
        and not IsWarbankTooltip(tooltip)
    then
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

    local transferable, transferReason =
        IsTransferableGearTooltip(
            tooltip,
            itemLink
        )

    if not transferable then
        -- Optional informational line for physically bound trinkets. Some
        -- already-Soulbound items can still surface their original BoP binding
        -- metadata first in Blizzard structured tooltip data, so accept both
        -- SOULBOUND and BOP terminal reasons for this display-only feature.
        -- Bound gear remains a terminal routing exclusion; this only
        -- shows which of the current character's effective specs Blizzard
        -- considers the trinket usable for.
        if (
            transferReason == "SOULBOUND"
            or transferReason == "BOP"
        )
            and WarboundGearRouterDB.interface
            and WarboundGearRouterDB.interface.showSoulboundTrinketSpecs == true
            and WGRGetSoulboundTrinketSpecSummary
        then
            local instantInfo =
                GetInstantItemInfo(
                    itemLink
                )

            if instantInfo
                and instantInfo.equipLoc == "INVTYPE_TRINKET"
                and tooltip.__WGRSoulboundTrinketSpecsItemLink ~= itemLink
            then
                local character =
                    currentName
                    and FindCharacterByName(
                        currentName
                    )
                    or nil

                local summary =
                    character
                    and WGRGetSoulboundTrinketSpecSummary(
                        currentName,
                        character,
                        itemLink
                    )
                    or nil

                if summary and summary ~= "" then
                    tooltip:AddLine(
                        "WBGR Specs: " .. summary,
                        1.00,
                        0.35,
                        0.82
                    )
                    tooltip.__WGRSoulboundTrinketSpecsItemLink =
                        itemLink
                    tooltip:Show()
                end
            end
        end

        -- Retry only when the classifier explicitly says Blizzard's item or
        -- binding data is unresolved. Definitive exclusions (Cosmetic,
        -- Soulbound, BoP, non-gear, disabled quality/binding, etc.) must not
        -- force tooltip RefreshData(). Retries are also hard-capped per
        -- tooltip/item by WGRScheduleTooltipRetry().
        if transferReason
            == "UNRESOLVED"
        then
            WGRScheduleTooltipRetry(
                tooltip,
                itemLink
            )
        else
            tooltip.__WGRRetryItemLink =
                nil
        end
        return
    end

    tooltip.__WGRRetryItemLink =
        nil
    tooltip.__WGRRetryCountItemLink =
        itemLink
    tooltip.__WGRRetryCount =
        0

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

                self.__WGRSoulboundTrinketSpecsItemLink =
                    nil

                -- Do not clear retry-count state here. Blizzard RefreshData()
                -- can clear/rebuild the tooltip while the cursor remains on
                -- the same item; clearing the count here would turn the
                -- intended two-retry cap into repeated two-retry cycles.
                -- The pending marker is safe to clear because the scheduled
                -- retry already clears it immediately before RefreshData().
                self.__WGRRetryItemLink =
                    nil

                tooltipSerial =
                    tooltipSerial + 1
            end
        )

        GameTooltip:HookScript(
            "OnHide",
            function(self)
                -- A genuine hover session ended. Allow a fresh bounded retry
                -- budget the next time an item is hovered. Item-link changes
                -- while the tooltip stays shown are handled separately by
                -- WGRScheduleTooltipRetry().
                self.__WGRRetryItemLink =
                    nil
                self.__WGRRetryCountItemLink =
                    nil
                self.__WGRRetryCount =
                    nil
            end
        )
    end
end
