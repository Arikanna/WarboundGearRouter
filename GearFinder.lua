-- Read-only Gear Finder.
-- This module owns inventory aggregation/classification and its page UI.
-- It never depends on Bagnon or another bag addon, and does not move items.

local WGRGearFinderGeneration = 0
local WGRGearFinderRefreshToken = 0
local WGRGearFinderFrame = nil
local WGRGearFinderBagSignature = nil
local WGRGearFinderPersonalBankSignature = nil
local WGRGearFinderPersonalBankOpen = false
local WGRGearFinderWarbandBankSignature = nil
local WGRGearFinderWarbandBankOpen = false
local WGRGearFinderPollElapsed = 0
local WGRGearFinderHoveredButton = nil
local WGRGearFinderConfirmThreshold = 10

local function WGRGearFinderEnsureDepositSettings()
    WarboundGearRouterDB =
        WarboundGearRouterDB
        or {}

    WarboundGearRouterDB.gearFinder =
        WarboundGearRouterDB.gearFinder
        or {}

    local settings =
        WarboundGearRouterDB.gearFinder

    if settings.depositLocation == nil then
        settings.depositLocation =
            "FIRST_AVAILABLE"
    end

    settings.customDepositTabs =
        settings.customDepositTabs
        or {}

    return settings
end

StaticPopupDialogs[
    "WGR_CONFIRM_MOVE_TO_BAGS"
] = {
    text =
        "Move %d %s to your bags?",
    button1 =
        YES,
    button2 =
        NO,
    OnAccept =
        function(
            self,
            data
        )
            if data
                and data.callback
            then
                data.callback()
            end
        end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local WGRGearFinderColors = {
    BEST = { 1.00, 0.82, 0.00 },
    COMPARE = { 1.00, 0.50, 0.10 },
    OTHER = { 1.00, 0.20, 0.85 },
    HELD = { 0.30, 0.70, 1.00 },
    ONWARD = { 1.00, 0.20, 0.20 },
    DISPOSE = { 0.65, 0.65, 0.65 },
}

local function WGRGearFinderCurrentName()
    return UnitName("player")
end

local function WGRGearFinderHasTrackedMail()
    local currentName =
        WGRGearFinderCurrentName()

    if not currentName
        or not WGRMailGetTrackedList
    then
        return false
    end

    local currentKey =
        string.lower(
            currentName
        )

    for _, entry
        in ipairs(
            WGRMailGetTrackedList()
            or {}
        )
    do
        if entry.name
            and string.lower(
                entry.name
            ) == currentKey
        then
            return true
        end
    end

    return false
end

local function WGRGearFinderSameCharacter(
    a,
    b
)
    return
        a
        and b
        and string.lower(a)
            == string.lower(b)
end

local function WGRGearFinderGetItemLevel(
    itemLink
)
    if not itemLink then
        return nil
    end

    local level =
        C_Item
        and C_Item.GetDetailedItemLevelInfo
        and C_Item.GetDetailedItemLevelInfo(
            itemLink
        )

    if not level
        or level <= 0
    then
        level =
            GetItemLevel(
                itemLink
            )
    end

    return tonumber(level)
end

local function WGRGearFinderIsSupportedGear(
    itemLink
)
    local info =
        GetInstantItemInfo(
            itemLink
        )

    if not info then
        return false
    end

    local equipLoc =
        info.equipLoc

    if not equipLoc
        or equipLoc == ""
    then
        return false
    end

    if WGRArmorEquipSlots[
        equipLoc
    ] then
        return true
    end

    if WGRGlobalEquipSlots[
        equipLoc
    ] then
        return true
    end

    if WGROffhandEquipLocs[
        equipLoc
    ] then
        return true
    end

    if IsSupportedWeapon(
        itemLink
    ) then
        return true
    end

    return false
end

local function WGRGearFinderGetSlotGroup(
    itemLink
)
    local info =
        GetInstantItemInfo(
            itemLink
        )

    if not info then
        return nil, nil
    end

    local equipLoc =
        info.equipLoc

    local armorSlot =
        WGRArmorEquipSlots[
            equipLoc
        ]

    if armorSlot then
        return
            "SLOT:" .. tostring(armorSlot),
            equipLoc
    end

    if equipLoc == "INVTYPE_NECK" then
        return "NECK", equipLoc
    end

    if equipLoc == "INVTYPE_CLOAK" then
        return "CLOAK", equipLoc
    end

    if equipLoc == "INVTYPE_FINGER" then
        return "RING", equipLoc
    end

    if equipLoc == "INVTYPE_TRINKET" then
        return "TRINKET", equipLoc
    end

    if WGROffhandEquipLocs[
        equipLoc
    ] then
        local offKind = WGRGetOffhandKind(itemLink)
        if offKind == "SHIELD" then
            return "SHIELD", equipLoc
        end
        return "OFFHAND", equipLoc
    end

    if IsSupportedWeapon(
        itemLink
    ) then
        local weaponKind = GetWeaponKind(itemLink)
        if weaponKind == "ONE_HAND" then
            return "ONE_HAND", equipLoc
        elseif weaponKind == "RANGED" then
            return "RANGED_WEAPON", equipLoc
        end
        return "TWO_HAND", equipLoc
    end

    return nil, equipLoc
end

local WGRGearFinderGroupOrder = {
    ["SLOT:1"] = 10,   -- Head
    ["NECK"] = 20,
    ["SLOT:3"] = 30,   -- Shoulder
    ["CLOAK"] = 40,
    ["SLOT:5"] = 50,   -- Chest
    ["SLOT:6"] = 60,   -- Waist
    ["SLOT:7"] = 70,   -- Legs
    ["SLOT:8"] = 80,   -- Feet
    ["SLOT:9"] = 90,   -- Wrist
    ["SLOT:10"] = 100, -- Hands
    ["RING"] = 110,
    ["TRINKET"] = 120,
    ["TWO_HAND"] = 130,
    ["RANGED_WEAPON"] = 135,
    ["ONE_HAND"] = 140,
    ["OFFHAND"] = 150,
    ["SHIELD"] = 160,
}

local WGRGearFinderGroupLabels = {
    ["SLOT:1"] = "Head",
    ["NECK"] = "Neck",
    ["SLOT:3"] = "Shoulder",
    ["CLOAK"] = "Back",
    ["SLOT:5"] = "Chest",
    ["SLOT:6"] = "Waist",
    ["SLOT:7"] = "Legs",
    ["SLOT:8"] = "Feet",
    ["SLOT:9"] = "Wrist",
    ["SLOT:10"] = "Hands",
    ["RING"] = "Ring",
    ["TRINKET"] = "Trinket",
    ["TWO_HAND"] = "2H",
    ["RANGED_WEAPON"] = "Ranged",
    ["ONE_HAND"] = "1H",
    ["OFFHAND"] = "Off Hand",
    ["SHIELD"] = "Shield",
}

local function WGRGearFinderGetGroupLabel(
    group
)
    return
        WGRGearFinderGroupLabels[group]
        or "Gear"
end

local function WGRGearFinderIsWeaponGroup(group)
    return group == "TWO_HAND"
        or group == "RANGED_WEAPON"
        or group == "ONE_HAND"
        or group == "OFFHAND"
        or group == "SHIELD"
        -- Backward compatibility for any older/in-memory records.
        or group == "WEAPON"
end

local function WGRGearFinderBuildGroups(
    records
)
    local groupsByKey = {}
    local groups = {}

    for _, record
        in ipairs(records)
    do
        local key =
            record.group
            or "OTHER"

        local group =
            groupsByKey[key]

        if not group then
            group = {
                key = key,
                label =
                    WGRGearFinderGetGroupLabel(
                        key
                    ),
                order =
                    WGRGearFinderGroupOrder[key]
                    or 999,
                records = {},
            }

            groupsByKey[key] = group
            groups[#groups + 1] = group
        end

        group.records[
            #group.records + 1
        ] =
            record
    end

    table.sort(
        groups,
        function(a, b)
            if a.order ~= b.order then
                return a.order < b.order
            end

            return a.label < b.label
        end
    )

    return groups
end

local function WGRGearFinderGetSelectedSpecs(
    characterName,
    character
)
    local result = {}

    local specIDs =
        WGRGetRoutingSpecIDs(
            characterName,
            character
        )
        or {}

    local current =
        GetCurrentSpecInfo()

    for _, specID
        in ipairs(specIDs)
    do
        result[#result + 1] = {
            id = specID,
            name =
                WGRSpecNamesByID[
                    specID
                ]
                or tostring(specID),
            current =
                current
                and tonumber(current.id)
                    == tonumber(specID)
                or false,
        }
    end

    return result
end

local function WGRGearFinderSharedComparison(
    character,
    equipLoc
)
    local slotIDs =
        WGRGlobalEquipSlots[
            equipLoc
        ]

    if not slotIDs then
        local armorSlot =
            WGRArmorEquipSlots[
                equipLoc
            ]

        if armorSlot then
            slotIDs = {
                armorSlot,
            }
        end
    end

    if not slotIDs then
        return nil, "not_usable"
    end

    return
        GetComparisonForSlots(
            character,
            slotIDs
        )
end

local function WGRGearFinderSpecificSpecComparison(
    characterName,
    character,
    itemLink,
    equipLoc,
    specID
)
    if equipLoc == "INVTYPE_TRINKET"
        or equipLoc == "INVTYPE_FINGER"
    then
        local slots =
            equipLoc == "INVTYPE_TRINKET"
            and { 13, 14 }
            or { 11, 12 }

        local sameUniqueLevel =
            WGRGetUniqueEquippedSameItemLevel
            and WGRGetUniqueEquippedSameItemLevel(
                characterName,
                character,
                itemLink,
                slots
            )
            or nil

        if sameUniqueLevel then
            return sameUniqueLevel, "known"
        end
    end

    if equipLoc == "INVTYPE_TRINKET" then
        return
            WGRGetSpecificSpecTrinketComparisonLevel(
                characterName,
                character,
                itemLink,
                specID
            )
    end

    if WGROffhandEquipLocs[
        equipLoc
    ] then
        return
            WGRGetSpecificSpecWeaponComparisonLevel(
                characterName,
                character,
                itemLink,
                "OFFHAND",
                specID
            )
    end

    if IsSupportedWeapon(
        itemLink
    ) then
        return
            WGRGetSpecificSpecWeaponComparisonLevel(
                characterName,
                character,
                itemLink,
                "WEAPON",
                specID
            )
    end

    -- Armor, cloak, neck, and rings intentionally remain ilvl-only in WGR.
    -- Their physical equipped baseline is shared across selected specs.
    return
        WGRGearFinderSharedComparison(
            character,
            equipLoc
        )
end

local function WGRGearFinderSpecFitsItem(
    characterName,
    character,
    itemLink,
    equipLoc,
    specID
)
    if equipLoc == "INVTYPE_TRINKET" then
        local _, status =
            WGRGetSpecificSpecTrinketComparisonLevel(
                characterName,
                character,
                itemLink,
                specID
            )

        return status == "known"
    end

    if WGROffhandEquipLocs[
        equipLoc
    ]
        or IsSupportedWeapon(
            itemLink
        )
    then
        local comparisonType =
            WGROffhandEquipLocs[
                equipLoc
            ]
            and "OFFHAND"
            or "WEAPON"

        local _, status =
            WGRGetSpecificSpecWeaponComparisonLevel(
                characterName,
                character,
                itemLink,
                comparisonType,
                specID
            )

        return status == "known"
    end

    -- WGR intentionally evaluates ordinary armor/jewelry by item level, not
    -- secondary-stat or role optimization, so all selected specs share them.
    return true
end

local function WGRGearFinderScanBags()
    local items = {}

    local currentName = WGRGearFinderCurrentName()
    if currentName
        and WGRIsCharacterRemoved
        and WGRIsCharacterRemoved(currentName)
    then
        return items
    end

    for bagID = 0, 4 do
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
                and WGRGearFinderIsSupportedGear(
                    itemLink
                )
                and IsTransferableContainerItem(
                    bagID,
                    slotID,
                    itemLink
                )
            then
                items[#items + 1] = {
                    itemLink = itemLink,
                    bagID = bagID,
                    slotID = slotID,
                    source = "BAGS",
                }
            end
        end
    end

    return items
end

local function WGRGearFinderGetBankTabIDs(
    bankType
)
    if not C_Bank
        or not C_Bank.FetchPurchasedBankTabIDs
        or not Enum
        or not Enum.BankType
        or bankType == nil
    then
        return nil
    end

    return C_Bank.FetchPurchasedBankTabIDs(
        bankType
    )
end

local function WGRGearFinderGetPersonalBankTabIDs()
    return
        WGRGearFinderGetBankTabIDs(
            Enum.BankType.Character
        )
end

local function WGRGearFinderGetWarbandBankTabIDs()
    if not Enum
        or not Enum.BankType
        or Enum.BankType.Account == nil
    then
        return nil
    end

    return
        WGRGearFinderGetBankTabIDs(
            Enum.BankType.Account
        )
end

local function WGRGearFinderGetPurchasedWarbandTabs()
    local result = {}
    local tabIDs =
        WGRGearFinderGetWarbandBankTabIDs()

    if type(tabIDs) ~= "table" then
        return result
    end

    for index, bagID
        in ipairs(tabIDs)
    do
        result[
            #result + 1
        ] = {
            index =
                index,
            bagID =
                bagID,
        }
    end

    return result
end

local function WGRGearFinderCanViewBankType(
    bankType
)
    if not C_Bank
        or bankType == nil
    then
        return false
    end

    if C_Bank.CanViewBank then
        local ok, result =
            pcall(
                C_Bank.CanViewBank,
                bankType
            )

        if ok then
            return result == true
        end
    end

    if C_Bank.CanUseBank then
        local ok, result =
            pcall(
                C_Bank.CanUseBank,
                bankType
            )

        if ok then
            return result == true
        end
    end

    if C_Bank.FetchPurchasedBankTabData then
        local ok, data =
            pcall(
                C_Bank.FetchPurchasedBankTabData,
                bankType
            )

        if ok then
            return data ~= nil
        end
    end

    return false
end

local function WGRGearFinderIsPersonalBankAvailable()
    if not Enum
        or not Enum.BankType
        or Enum.BankType.Character == nil
    then
        return false
    end

    return
        WGRGearFinderCanViewBankType(
            Enum.BankType.Character
        )
end

local function WGRGearFinderScanPersonalBank()
    local items = {}

    local currentName = WGRGearFinderCurrentName()
    if currentName
        and WGRIsCharacterRemoved
        and WGRIsCharacterRemoved(currentName)
    then
        return items
    end

    local tabIDs =
        WGRGearFinderGetPersonalBankTabIDs()

    if type(tabIDs) ~= "table" then
        return items
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
            local itemLink =
                C_Container.GetContainerItemLink(
                    bagID,
                    slotID
                )

            if itemLink
                and WGRGearFinderIsSupportedGear(
                    itemLink
                )
                and IsTransferableContainerItem(
                    bagID,
                    slotID,
                    itemLink
                )
            then
                items[#items + 1] = {
                    itemLink = itemLink,
                    bagID = bagID,
                    slotID = slotID,
                    source = "PERSONAL_BANK",
                }
            end
        end
    end

    return items
end

local function WGRGearFinderIsWarbandBankAvailable()
    if not Enum
        or not Enum.BankType
        or Enum.BankType.Account == nil
    then
        return false
    end

    return
        WGRGearFinderCanViewBankType(
            Enum.BankType.Account
        )
end

function WGRGearFinderIsWarbandBankOpen()
    return
        WGRGearFinderWarbandBankOpen
            == true
end

local function WGRGearFinderWarbandBindingAllowed(
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
        TooltipUtil.SurfaceArgs(
            data
        )
    end

    local sawWarbound = false
    local sawBoE = false

    for _, line
        in ipairs(data.lines)
    do
        if TooltipUtil
            and TooltipUtil.SurfaceArgs
        then
            TooltipUtil.SurfaceArgs(
                line
            )
        end

        for _, text
            in ipairs({
                line.leftText,
                line.rightText,
            })
        do
            if text then
                local clean =
                    tostring(text)
                    :gsub(
                        "|c%x%x%x%x%x%x%x%x",
                        ""
                    )
                    :gsub(
                        "|r",
                        ""
                    )
                    :lower()

                if clean:find(
                    "soulbound",
                    1,
                    true
                )
                then
                    return false
                end

                if clean:find(
                    "warbound until equipped",
                    1,
                    true
                )
                then
                    sawWarbound = true
                end

                if clean:find(
                    "binds when equipped",
                    1,
                    true
                )
                then
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

local function WGRGearFinderScanWarbandBank()
    local items = {}
    local tabIDs =
        WGRGearFinderGetWarbandBankTabIDs()

    if type(tabIDs) ~= "table" then
        return items
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
            local itemLink =
                C_Container.GetContainerItemLink(
                    bagID,
                    slotID
                )

            if itemLink
                and WGRGearFinderIsSupportedGear(
                    itemLink
                )
                and WGRQualityAllowed(
                    itemLink
                )
                and WGRGearFinderWarbandBindingAllowed(
                    bagID,
                    slotID,
                    itemLink
                )
            then
                items[#items + 1] = {
                    itemLink = itemLink,
                    bagID = bagID,
                    slotID = slotID,
                    source = "WARBAND_BANK",
                }
            end
        end
    end

    return items
end


local function WGRGearFinderBuildBagSignature()
    local parts = {}

    for bagID = 0, 4 do
        local slots =
            C_Container.GetContainerNumSlots(
                bagID
            )
            or 0

        parts[#parts + 1] =
            "B"
            .. tostring(bagID)
            .. ":"
            .. tostring(slots)

        for slotID = 1, slots do
            local info =
                C_Container.GetContainerItemInfo(
                    bagID,
                    slotID
                )

            if info
                and info.itemID
            then
                parts[#parts + 1] =
                    tostring(slotID)
                    .. ":"
                    .. tostring(info.itemID)
                    .. ":"
                    .. tostring(
                        info.stackCount
                        or 1
                    )
            else
                parts[#parts + 1] =
                    tostring(slotID)
                    .. ":0"
            end
        end
    end

    return table.concat(
        parts,
        "|"
    )
end


local function WGRGearFinderBuildPersonalBankSignature()
    local tabIDs =
        WGRGearFinderGetPersonalBankTabIDs()

    if type(tabIDs) ~= "table" then
        return nil
    end

    local parts = {}

    for _, bagID
        in ipairs(tabIDs)
    do
        local slots =
            C_Container.GetContainerNumSlots(
                bagID
            )
            or 0

        parts[#parts + 1] =
            "PB"
            .. tostring(bagID)
            .. ":"
            .. tostring(slots)

        for slotID = 1, slots do
            local info =
                C_Container.GetContainerItemInfo(
                    bagID,
                    slotID
                )

            if info
                and info.itemID
            then
                parts[#parts + 1] =
                    tostring(slotID)
                    .. ":"
                    .. tostring(info.itemID)
                    .. ":"
                    .. tostring(
                        info.stackCount
                        or 1
                    )
            else
                parts[#parts + 1] =
                    tostring(slotID)
                    .. ":0"
            end
        end
    end

    return table.concat(
        parts,
        "|"
    )
end


local function WGRGearFinderBuildWarbandBankSignature()
    local tabIDs =
        WGRGearFinderGetWarbandBankTabIDs()

    if type(tabIDs) ~= "table" then
        return nil
    end

    local parts = {}

    for _, bagID
        in ipairs(tabIDs)
    do
        local slots =
            C_Container.GetContainerNumSlots(
                bagID
            )
            or 0

        parts[#parts + 1] =
            "WB"
            .. tostring(bagID)
            .. ":"
            .. tostring(slots)

        for slotID = 1, slots do
            local info =
                C_Container.GetContainerItemInfo(
                    bagID,
                    slotID
                )

            if info
                and info.itemID
            then
                parts[#parts + 1] =
                    tostring(slotID)
                    .. ":"
                    .. tostring(info.itemID)
                    .. ":"
                    .. tostring(
                        info.stackCount
                        or 1
                    )
            else
                parts[#parts + 1] =
                    tostring(slotID)
                    .. ":0"
            end
        end
    end

    return table.concat(
        parts,
        "|"
    )
end

local function WGRGearFinderSortItems(
    a,
    b
)
    local aLevel =
        tonumber(a.itemLevel)
        or 0

    local bLevel =
        tonumber(b.itemLevel)
        or 0

    if aLevel ~= bLevel then
        return aLevel > bLevel
    end

    return tostring(a.itemLink)
        < tostring(b.itemLink)
end

local function WGRGearFinderOpportunityCount(
    candidates,
    group,
    character,
    specID,
    threshold
)
    if #candidates == 0 then
        return 0
    end

    if group ~= "RING"
        and group ~= "TRINKET"
    then
        return 1
    end

    local baselines = {}

    if group == "RING" then
        for _, slotID
            in ipairs(
                { 11, 12 }
            )
        do
            local item =
                GetStoredItem(
                    character,
                    slotID
                )

            baselines[#baselines + 1] =
                item
                and (
                    GetItemLevel(
                        item
                    )
                    or 0
                )
                or 0
        end
    else
        local first,
              second =
            WGRGetResolvedSpecTrinketLevels(
                WGRGearFinderCurrentName(),
                character,
                specID
            )

        baselines = {
            tonumber(first) or 0,
            tonumber(second) or 0,
        }
    end

    table.sort(baselines)

    local levels = {}

    for _, candidate
        in ipairs(candidates)
    do
        levels[#levels + 1] =
            tonumber(
                candidate.itemLevel
            )
            or 0
    end

    table.sort(
        levels,
        function(a, b)
            return a > b
        end
    )

    local count = 0
    local used = {}

    for _, baseline
        in ipairs(baselines)
    do
        local chosenIndex = nil

        for index, level
            in ipairs(levels)
        do
            if not used[index]
                and level > baseline
                and (
                    level - baseline
                ) >= threshold
            then
                chosenIndex = index
                break
            end
        end

        if chosenIndex then
            used[chosenIndex] = true
            count = count + 1
        end
    end

    return count
end


local function WGRGearFinderLocationCode(source)
    if source == "BAGS" then return "BAG" end
    if source == "PERSONAL_BANK" then return "PBK" end
    if source == "WARBAND_BANK" then return "WBK" end
    if source == "EQUIPPED" then return "EQ" end
    return nil
end

local function WGRGearFinderKnownItemMatches(
    candidateLink,
    targetLink,
    targetLevel
)
    if not candidateLink
        or not targetLink
    then
        return false
    end

    if candidateLink == targetLink then
        return true
    end

    local candidateInfo =
        GetInstantItemInfo(
            candidateLink
        )

    local targetInfo =
        GetInstantItemInfo(
            targetLink
        )

    local candidateID =
        candidateInfo
        and tonumber(candidateInfo.itemID)

    local targetID =
        targetInfo
        and tonumber(targetInfo.itemID)

    if not candidateID
        or not targetID
        or candidateID ~= targetID
    then
        return false
    end

    local expectedLevel =
        tonumber(targetLevel)
        or 0

    if expectedLevel <= 0 then
        return true
    end

    local candidateLevel =
        tonumber(
            GetItemLevel(
                candidateLink
            )
        )
        or 0

    return candidateLevel
        == expectedLevel
end

local function WGRGearFinderFindKnownItemLocation(
    itemLink,
    itemLevel
)
    if not itemLink then
        return nil, nil, nil
    end

    -- Weapon KEEP records can represent the currently equipped main/off hand.
    for _, slotID in ipairs({ 16, 17 }) do
        local equipped =
            GetInventoryItemLink(
                "player",
                slotID
            )

        if WGRGearFinderKnownItemMatches(
            equipped,
            itemLink,
            itemLevel
        ) then
            return
                "EQUIPPED",
                nil,
                slotID
        end
    end

    for bagID = 0, 4 do
        local slots =
            C_Container.GetContainerNumSlots(
                bagID
            )
            or 0

        for slotID = 1, slots do
            local candidate =
                C_Container.GetContainerItemLink(
                    bagID,
                    slotID
                )

            if WGRGearFinderKnownItemMatches(
                candidate,
                itemLink,
                itemLevel
            ) then
                return
                    "BAGS",
                    bagID,
                    slotID
            end
        end
    end

    if WGRGearFinderIsPersonalBankAvailable() then
        for _, bagID
            in ipairs(
                WGRGearFinderGetPersonalBankTabIDs()
                or {}
            )
        do
            local slots =
                C_Container.GetContainerNumSlots(
                    bagID
                )
                or 0

            for slotID = 1, slots do
                local candidate =
                    C_Container.GetContainerItemLink(
                        bagID,
                        slotID
                    )

                if WGRGearFinderKnownItemMatches(
                    candidate,
                    itemLink,
                    itemLevel
                ) then
                    return
                        "PERSONAL_BANK",
                        bagID,
                        slotID
                end
            end
        end
    end

    if WGRGearFinderIsWarbandBankAvailable() then
        for _, tab
            in ipairs(
                WGRGearFinderGetPurchasedWarbandTabs()
                or {}
            )
        do
            local bagID =
                tab.bagID

            local slots =
                C_Container.GetContainerNumSlots(
                    bagID
                )
                or 0

            for slotID = 1, slots do
                local candidate =
                    C_Container.GetContainerItemLink(
                        bagID,
                        slotID
                    )

                if WGRGearFinderKnownItemMatches(
                    candidate,
                    itemLink,
                    itemLevel
                ) then
                    return
                        "WARBAND_BANK",
                        bagID,
                        slotID
                end
            end
        end
    end

    -- The saved/offspec setup proves the character owns this item, but its
    -- exact physical location may be unavailable while the relevant bank is
    -- closed. Leave it unknown rather than incorrectly claiming EQ.
    return "OWNED", nil, nil
end

local function WGRGearFinderMakeOwnedWeaponRecord(itemLink, itemLevel, slotRole)
    if not itemLink or (tonumber(itemLevel) or 0) <= 0 then return nil end
    local source, bagID, slotID =
        WGRGearFinderFindKnownItemLocation(
            itemLink,
            itemLevel
        )
    return {
        itemLink = itemLink,
        itemLevel = tonumber(itemLevel) or 0,
        source = source,
        bagID = bagID,
        slotID = slotID,
        ownedBaseline = true,
        slotRole = slotRole,
        classification = "OWNED",
    }
end

local function WGRGearFinderWeaponPieceFitsConfig(record, config, role)
    if not record or not record.itemLink then return false end
    local weaponKind = GetWeaponKind(record.itemLink)
    local offKind = WGRGetOffhandKind(record.itemLink)

    if config == "RANGED" then
        return role == "MAIN" and weaponKind == "RANGED"
    elseif config == "TWO_HAND" then
        return role == "MAIN" and weaponKind == "TWO_HAND"
    elseif config == "DUAL_2H" then
        return weaponKind == "TWO_HAND"
    elseif config == "DUAL_1H" then
        return weaponKind == "ONE_HAND"
    elseif config == "ONE_HAND_PLUS_SHIELD" then
        if role == "MAIN" then return weaponKind == "ONE_HAND" end
        return offKind == "SHIELD"
    elseif config == "ONE_HAND_PLUS_OFFHAND" then
        if role == "MAIN" then return weaponKind == "ONE_HAND" end
        return offKind == "OFFHAND"
    end

    return false
end

local function WGRGearFinderWeaponRecordKey(record)
    if record.ownedBaseline then
        return "OWN:" .. tostring(record.slotRole or "?") .. ":" .. tostring(record.itemLink)
    end
    return tostring(record.source) .. ":" .. tostring(record.bagID) .. ":" .. tostring(record.slotID)
end

local function WGRGearFinderBestWeaponSetupsForConfig(pieces, config, overallBaseline, threshold)
    local main = {}
    local off = {}
    local ownedMainLevel = 0
    local ownedOffLevel = 0

    for _, piece in ipairs(pieces) do
        if piece.ownedBaseline then
            local level = tonumber(piece.itemLevel) or 0
            if piece.slotRole == "MAIN" then
                ownedMainLevel = math.max(ownedMainLevel, level)
            elseif piece.slotRole == "OFF" then
                ownedOffLevel = math.max(ownedOffLevel, level)
            end
        end
    end

    for _, piece in ipairs(pieces) do
        if WGRGearFinderWeaponPieceFitsConfig(piece, config, "MAIN") then
            main[#main + 1] = piece
        end
        if config == "DUAL_1H" or config == "DUAL_2H" then
            if WGRGearFinderWeaponPieceFitsConfig(piece, config, "OFF") then
                off[#off + 1] = piece
            end
        elseif config ~= "RANGED" and config ~= "TWO_HAND" then
            if WGRGearFinderWeaponPieceFitsConfig(piece, config, "OFF") then
                off[#off + 1] = piece
            end
        end
    end

    local setups = {}

    local function candidateImprovesComponent(piece, role)
        if not piece or piece.ownedBaseline then return true end
        local level = tonumber(piece.itemLevel) or 0

        if config == "RANGED" or config == "TWO_HAND" then
            return ownedMainLevel <= 0 or level > ownedMainLevel
        end

        if config == "ONE_HAND_PLUS_OFFHAND"
            or config == "ONE_HAND_PLUS_SHIELD"
        then
            if role == "MAIN" then
                return ownedMainLevel <= 0 or level > ownedMainLevel
            end
            return ownedOffLevel <= 0 or level > ownedOffLevel
        end

        if config == "DUAL_1H" or config == "DUAL_2H" then
            if ownedMainLevel > 0 and ownedOffLevel > 0 then
                return level > math.min(ownedMainLevel, ownedOffLevel)
            end
            return level > 0
        end

        return true
    end

    local function addSetup(a, b)
        if not a then return end
        if b and WGRGearFinderWeaponRecordKey(a) == WGRGearFinderWeaponRecordKey(b) then return end
        -- A loose paired-weapon component is only actionable if it improves
        -- the component position it would replace.  The complete setup score
        -- is still used below for the actual +ilvl comparison.
        if not candidateImprovesComponent(a, "MAIN") then return end
        if b and not candidateImprovesComponent(b, "OFF") then return end
        -- A weapon that the routing engine has assigned to the current
        -- character remains actionable even when it is the below-threshold
        -- fallback upgrade.  Gear Finder must follow routing ownership rather
        -- than independently rejecting that item on threshold a second time.
        if not a.ownedBaseline and not (a.meetsThreshold or a.routedUpgrade) then return end
        if b and not b.ownedBaseline and not (b.meetsThreshold or b.routedUpgrade) then return end

        local hasCandidate = not a.ownedBaseline or (b and not b.ownedBaseline)
        if not hasCandidate then return end

        local score
        if config == "RANGED" or config == "TWO_HAND" then
            score = tonumber(a.itemLevel) or 0
        else
            if not b then return end
            score = ((tonumber(a.itemLevel) or 0) + (tonumber(b.itemLevel) or 0)) / 2
        end

        setups[#setups + 1] = {
            main = a,
            off = b,
            score = score,
            upgrade = score - (tonumber(overallBaseline) or 0),
            -- Gold/Best weapon recommendations are threshold-qualified
            -- complete setups only. Routed fallback components remain useful
            -- and are shown under Other Useful Gear (magenta), but routing
            -- ownership alone must not promote a below-threshold setup to Gold.
            qualifies =
                (score - (tonumber(overallBaseline) or 0)) >= threshold,
        }
    end

    if config == "RANGED" or config == "TWO_HAND" then
        for _, a in ipairs(main) do addSetup(a, nil) end
    else
        for _, a in ipairs(main) do
            for _, b in ipairs(off) do addSetup(a, b) end
        end
    end

    table.sort(setups, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return WGRGearFinderWeaponRecordKey(a.main) < WGRGearFinderWeaponRecordKey(b.main)
    end)

    return setups
end

local function WGRGearFinderBuildWeaponDisplay(characterName, character, specID, candidates)
    local threshold = WGRGetCharacterThreshold(characterName)
    local overallBaseline = WGRGetEffectiveSpecWeaponBaseline(characterName, character, specID)
    overallBaseline = tonumber(overallBaseline) or 0
    local configs = WGRGetAllowedSpecWeaponConfigs(characterName, specID) or {}

    -- Routing decides which loose weapon pieces belong to this character.
    -- Gear Finder's job begins after that: combine every routed candidate with
    -- known Soulbound baseline pieces, evaluate complete legal setups, and
    -- present only the best equip result(s).
    local routedCandidates = {}
    for _, record in ipairs(candidates or {}) do
        if record.routedUpgrade or record.meetsThreshold then
            record.weaponState = "OTHER"
            record.classification = "OTHER"
            routedCandidates[#routedCandidates + 1] = record
        end
    end

    if #routedCandidates == 0 then
        return nil
    end

    local allComplete = {}
    local knownByConfig = {}

    for _, config in ipairs(configs) do
        local known, knownStatus = WGRGetKnownWeaponSetupForConfig(
            characterName,
            character,
            specID,
            config
        )

        local pieces = {}
        local ownedMain, ownedOff
        if known then
            ownedMain = WGRGearFinderMakeOwnedWeaponRecord(known.mainHand, known.mainHandLevel, "MAIN")
            ownedOff = WGRGearFinderMakeOwnedWeaponRecord(known.offHand, known.offHandLevel, "OFF")
            if ownedMain then pieces[#pieces + 1] = ownedMain end
            if ownedOff then pieces[#pieces + 1] = ownedOff end
        end
        for _, candidate in ipairs(routedCandidates) do
            pieces[#pieces + 1] = candidate
        end

        knownByConfig[config] = {
            known = known,
            knownStatus = knownStatus,
            ownedMain = ownedMain,
            ownedOff = ownedOff,
        }

        local setups = WGRGearFinderBestWeaponSetupsForConfig(
            pieces,
            config,
            overallBaseline,
            threshold
        )
        for _, setup in ipairs(setups) do
            if setup.qualifies and setup.score > overallBaseline then
                setup.config = config
                allComplete[#allComplete + 1] = setup
            end
        end
    end

    local bestScore = nil
    for _, setup in ipairs(allComplete) do
        if not bestScore or setup.score > bestScore then
            bestScore = setup.score
        end
    end

    if not bestScore then
        -- No complete improvement yet. The routed loose pieces remain in
        -- OTHER USEFUL GEAR (magenta) until a compatible partner arrives or
        -- routing later sends them onward. No weapon recommendation section
        -- is needed for this spec yet.
        return nil
    end

    local winningSetups = {}
    for _, setup in ipairs(allComplete) do
        if math.abs(setup.score - bestScore) < 0.001 then
            winningSetups[#winningSetups + 1] = setup
        end
    end

    local winningState = "BEST"
    local usedCandidateKeys = {}

    local function markPiece(piece)
        if not piece or piece.ownedBaseline then return end
        piece.weaponState = winningState
        piece.classification = winningState
        usedCandidateKeys[WGRGearFinderWeaponRecordKey(piece)] = true
    end
    for _, setup in ipairs(winningSetups) do
        markPiece(setup.main)
        markPiece(setup.off)
    end

    local function addUnique(list, piece)
        if not piece then return end
        local key = WGRGearFinderWeaponRecordKey(piece)
        for _, existing in ipairs(list) do
            if WGRGearFinderWeaponRecordKey(existing) == key then return end
        end
        list[#list + 1] = piece
    end

    -- Preserve the user's configured order, but include only configurations
    -- that tie for the best complete effective weapon ilvl.
    local configDisplays = {}
    for _, config in ipairs(configs) do
        local winningForConfig = {}
        for _, setup in ipairs(winningSetups) do
            if setup.config == config then
                winningForConfig[#winningForConfig + 1] = setup
            end
        end

        if #winningForConfig > 0 then
            local knownData = knownByConfig[config] or {}
            local display = {
                config = config,
                known = knownData.known,
                knownStatus = knownData.knownStatus,
                ownedMain = knownData.ownedMain,
                ownedOff = knownData.ownedOff,
                mainOptions = {},
                offOptions = {},
                score = bestScore,
                upgrade = bestScore - overallBaseline,
            }
            for _, setup in ipairs(winningForConfig) do
                addUnique(display.mainOptions, setup.main)
                addUnique(display.offOptions, setup.off)
            end
            configDisplays[#configDisplays + 1] = display
        end
    end

    return {
        baseline = overallBaseline,
        threshold = threshold,
        configs = configDisplays,
        winningState = winningState,
        bestScore = bestScore,
        hasCompleteUpgrade = true,
        usedCandidateKeys = usedCandidateKeys,
    }
end


-- Rings and trinkets are sequential two-slot recommendations in Gear Finder.
-- If a candidate is Unique-Equipped and an identical item is already equipped,
-- it is not a legal choice for the remaining slot.  Filtering it here lets the
-- next-best legal candidate naturally rise into Gold after an equip/rescan.
local function WGRGearFinderItemID(itemLink)
    if not itemLink then return nil end

    if C_Item and C_Item.GetItemInfoInstant then
        local itemID = C_Item.GetItemInfoInstant(itemLink)
        if itemID then return tonumber(itemID) end
    end

    if GetItemInfoInstant then
        local itemID = GetItemInfoInstant(itemLink)
        if itemID then return tonumber(itemID) end
    end

    return tonumber(tostring(itemLink):match("item:(%d+)"))
end

local function WGRGearFinderItemIsUniqueEquipped(itemLink)
    if not itemLink or not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then
        return false
    end

    local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
    if not ok or not data or not data.lines then
        return false
    end

    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(data)
    end

    local localizedUnique =
        _G.ITEM_UNIQUE_EQUIPPABLE
        or _G.ITEM_UNIQUE_EQUIP
        or "Unique-Equipped"

    for _, line in ipairs(data.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then
            TooltipUtil.SurfaceArgs(line)
        end

        for _, value in ipairs({ line.leftText, line.rightText }) do
            if value then
                local clean = tostring(value)
                    :gsub("|c%x%x%x%x%x%x%x%x", "")
                    :gsub("|r", "")

                if clean:find("Unique%-Equipped")
                    or (
                        localizedUnique
                        and clean:find(tostring(localizedUnique), 1, true)
                    )
                then
                    return true
                end
            end
        end
    end

    return false
end

local function WGRGearFinderConflictsWithEquippedUnique(record, group)
    if not record or not record.itemLink then return false end
    if group ~= "TRINKET" and group ~= "RING" then return false end

    local currentName = WGRGearFinderCurrentName()
    local character = currentName and FindCharacterByName(currentName) or nil
    local slots = group == "TRINKET" and { 13, 14 } or { 11, 12 }

    local equippedSameLevel = WGRGetUniqueEquippedSameItemLevel
        and WGRGetUniqueEquippedSameItemLevel(
            currentName,
            character,
            record.itemLink,
            slots
        )
        or nil

    if not equippedSameLevel then return false end

    -- Equal/lower duplicates cannot fill the second slot. A higher-ilvl copy
    -- is a legal replacement and remains eligible for threshold/fallback logic.
    return (tonumber(record.itemLevel) or 0) <= (tonumber(equippedSameLevel) or 0)
end

local function WGRGearFinderClassify(
    records,
    specs,
    character
)
    local bySpec = {}
    local other = {}
    local held = {}
    local onward = {}
    local dispose = {}
    local currentName =
        WGRGearFinderCurrentName()

    for _, spec
        in ipairs(specs)
    do
        bySpec[spec.id] = {
            best = {},
            compare = {},
            groups = {},
            weaponCandidates = {},
            weaponDisplay = nil,
            count = 0,
        }
    end

    for _, record
        in ipairs(records)
    do
        local recommendation =
            record.recommendation

        if recommendation
            and (
                recommendation.kind == "sell"
                or recommendation.kind == "no_current_upgrade"
            )
        then
            record.classification =
                "DISPOSE"

            dispose[
                #dispose + 1
            ] =
                record

        elseif recommendation
            and recommendation.name
            and not WGRGearFinderSameCharacter(
                recommendation.name,
                currentName
            )
            and (
                recommendation.kind == "upgrade"
                or recommendation.kind == "future_upgrade"
                or recommendation.kind == "holder"
            )
        then
            record.classification =
                "ONWARD"

            onward[#onward + 1] =
                record

        elseif recommendation
            and recommendation.name
            and WGRGearFinderSameCharacter(
                recommendation.name,
                currentName
            )
        then
            if recommendation.kind == "holder"
                or recommendation.kind == "future_upgrade"
            then
                -- Gear already on its intended holder is not an actionable
                -- current-character upgrade. Future-level gear also stays in
                -- HOLD state until the character can actually equip it.
                -- Keep both out of Other Useful Gear (magenta).
                record.classification =
                    "HELD"

                held[#held + 1] =
                    record
            else
                local contributed = false

                for _, spec
                    in ipairs(specs)
                do
                    if WGRGearFinderSpecFitsItem(
                        currentName,
                        character,
                        record.itemLink,
                        record.equipLoc,
                        spec.id
                    )
                    then
                        local isWeapon =
                            WGRGearFinderIsWeaponGroup(
                                record.group
                            )

                        local upgrade = nil
                        local status = nil
                        local usesWeaponAverage = false

                        if isWeapon then
                            local comparisonType =
                                (record.group == "OFFHAND"
                                    or record.group == "SHIELD")
                                and "OFFHAND"
                                or "WEAPON"

                            upgrade,
                            status,
                            usesWeaponAverage =
                                WGRGetIncomingWeaponUpgradeForSpecificSpec(
                                    currentName,
                                    character,
                                    record.itemLink,
                                    record.itemLevel,
                                    comparisonType,
                                    spec.id
                                )
                        else
                            local baseline
                            baseline, status =
                                WGRGearFinderSpecificSpecComparison(
                                    currentName,
                                    character,
                                    record.itemLink,
                                    record.equipLoc,
                                    spec.id
                                )

                            if status == "known"
                                and baseline ~= nil
                            then
                                upgrade =
                                    (
                                        tonumber(
                                            record.itemLevel
                                        )
                                        or 0
                                    )
                                    - (
                                        tonumber(
                                            baseline
                                        )
                                        or 0
                                    )
                            end
                        end

                        if status == "known"
                            and upgrade ~= nil
                        then
                            upgrade = tonumber(upgrade) or 0

                            -- Routing has already decided that this item belongs
                            -- to the current character. For weapons, do not reject a
                            -- routed component merely because its raw ilvl is below
                            -- the spec's effective *setup* baseline; it may combine
                            -- with another piece to form the best complete setup.
                            if upgrade > 0
                                or WGRGearFinderIsWeaponGroup(record.group)
                            then
                                local specRecord = {
                                    itemLink =
                                        record.itemLink,
                                    itemLevel =
                                        record.itemLevel,
                                    bagID =
                                        record.bagID,
                                    slotID =
                                        record.slotID,
                                    source =
                                        record.source,
                                    equipLoc =
                                        record.equipLoc,
                                    group =
                                        record.group,
                                    upgrade =
                                        upgrade,
                                    weaponAverage =
                                        usesWeaponAverage == true,
                                    meetsThreshold =
                                        upgrade
                                        >= WGRGetCharacterThreshold(
                                            currentName
                                        ),
                                    routedUpgrade = true,
                                    routingMeetsThreshold =
                                        recommendation.meetsThreshold ~= false,
                                }

                                local bucket =
                                    bySpec[
                                        spec.id
                                    ]

                                if WGRGearFinderIsWeaponGroup(record.group) then
                                    table.insert(
                                        bucket.weaponCandidates,
                                        specRecord
                                    )
                                else
                                    bucket.groups[
                                        record.group
                                    ] =
                                        bucket.groups[
                                            record.group
                                        ]
                                        or {}

                                    table.insert(
                                        bucket.groups[
                                            record.group
                                        ],
                                        specRecord
                                    )
                                end

                                contributed =
                                    true
                            end
                        end
                    end
                end

                if not contributed then
                    record.classification =
                        "OTHER"

                    other[#other + 1] =
                        record
                end
            end
        end
    end

    local threshold =
        WGRGetCharacterThreshold(
            currentName
        )

    for _, spec
        in ipairs(specs)
    do
        local bucket =
            bySpec[
                spec.id
            ]

        for group, candidates
            in pairs(
                bucket.groups
            )
        do
            table.sort(
                candidates,
                WGRGearFinderSortItems
            )

            local qualified = {}

            for _, candidate
                in ipairs(candidates)
            do
                local blockedByUniqueEquipped =
                    WGRGearFinderConflictsWithEquippedUnique(
                        candidate,
                        group
                    )

                candidate.blockedByUniqueEquipped =
                    blockedByUniqueEquipped

                if candidate.meetsThreshold
                    and not blockedByUniqueEquipped
                then
                    qualified[
                        #qualified + 1
                    ] =
                        candidate
                end
            end

            if #qualified > 0 then
                local bestLevel =
                    qualified[1].itemLevel

                local tied = {}

                for _, candidate
                    in ipairs(qualified)
                do
                    if candidate.itemLevel
                        == bestLevel
                    then
                        tied[#tied + 1] =
                            candidate
                    end
                end

                -- Gear Finder no longer uses a separate Orange/COMPARE
                -- state. Every item tied for the best result is a Gold/Best
                -- recommendation; the UI tells the player to CHOOSE ONE.
                for _, candidate in ipairs(tied) do
                    candidate.classification = "BEST"
                    bucket.best[#bucket.best + 1] = candidate
                end

                bucket.count =
                    bucket.count
                    + WGRGearFinderOpportunityCount(
                        qualified,
                        group,
                        character,
                        spec.id,
                        threshold
                    )
            end

            local promoted = {}

            for _, candidate
                in ipairs(bucket.best)
            do
                promoted[
                    tostring(candidate.bagID)
                    .. ":"
                    .. tostring(candidate.slotID)
                    .. ":"
                    .. tostring(spec.id)
                ] = true
            end

            for _, candidate
                in ipairs(bucket.compare)
            do
                promoted[
                    tostring(candidate.bagID)
                    .. ":"
                    .. tostring(candidate.slotID)
                    .. ":"
                    .. tostring(spec.id)
                ] = true
            end

            for _, candidate
                in ipairs(candidates)
            do
                local key =
                    tostring(candidate.bagID)
                    .. ":"
                    .. tostring(candidate.slotID)
                    .. ":"
                    .. tostring(spec.id)

                if not promoted[key] then
                    candidate.specName =
                        spec.name

                    candidate.classification =
                        "OTHER"

                    other[
                        #other + 1
                    ] =
                        candidate
                end
            end
        end

        bucket.weaponDisplay =
            WGRGearFinderBuildWeaponDisplay(
                currentName,
                character,
                spec.id,
                bucket.weaponCandidates
            )

        local usedWeaponKeys =
            bucket.weaponDisplay
            and bucket.weaponDisplay.usedCandidateKeys
            or {}

        for _, candidate in ipairs(bucket.weaponCandidates) do
            local key = WGRGearFinderWeaponRecordKey(candidate)
            if not usedWeaponKeys[key] then
                candidate.specName = spec.name
                candidate.classification = "OTHER"
                other[#other + 1] = candidate
            end
        end

        if bucket.weaponDisplay
            and bucket.weaponDisplay.hasCompleteUpgrade
        then
            bucket.count = bucket.count + 1
        end

        table.sort(
            bucket.best,
            WGRGearFinderSortItems
        )

        table.sort(
            bucket.compare,
            WGRGearFinderSortItems
        )
    end

    -- OTHER USEFUL GEAR is a physical-item list, not a per-spec list.
    -- Collapse repeated spec records for the same actual bag/bank slot.
    do
        local uniqueOther = {}
        local seenOther = {}

        for _, record in ipairs(other) do
            local key

            if record.bagID ~= nil
                and record.slotID ~= nil
            then
                key =
                    tostring(record.source or "UNKNOWN")
                    .. ":"
                    .. tostring(record.bagID)
                    .. ":"
                    .. tostring(record.slotID)
            else
                key =
                    tostring(record.source or "UNKNOWN")
                    .. ":"
                    .. tostring(record.itemLink or record)
            end

            local existing =
                seenOther[key]

            if not existing then
                seenOther[key] =
                    record

                uniqueOther[
                    #uniqueOther + 1
                ] =
                    record
            else
                -- Preserve the strongest displayed upgrade if the same item
                -- was evaluated differently by multiple selected specs.
                if (tonumber(record.upgrade) or 0)
                    > (tonumber(existing.upgrade) or 0)
                then
                    existing.upgrade =
                        record.upgrade
                end

                if record.specName
                    and existing.specName
                    and record.specName
                        ~= existing.specName
                then
                    existing.specName =
                        "Multiple specs"
                elseif record.specName
                    and not existing.specName
                then
                    existing.specName =
                        record.specName
                end
            end
        end

        other =
            uniqueOther
    end

    table.sort(
        other,
        WGRGearFinderSortItems
    )

    table.sort(
        held,
        WGRGearFinderSortItems
    )

    table.sort(
        onward,
        WGRGearFinderSortItems
    )

    table.sort(
        dispose,
        WGRGearFinderSortItems
    )

    return {
        bySpec = bySpec,
        other = other,
        held = held,
        onward = onward,
        dispose = dispose,
    }
end

local function WGRGearFinderItemTexture(
    itemLink
)
    local icon =
        C_Item
        and C_Item.GetItemIconByID
        and C_Item.GetItemIconByID(
            itemLink
        )

    if not icon then
        local info =
            GetInstantItemInfo(
                itemLink
            )

        icon =
            info
            and info.icon
            or nil
    end

    return icon
end

local function WGRGearFinderReleaseTooltip()
    WGRGearFinderHoveredButton =
        nil

    if WGRHideGearFinderLocator then
        WGRHideGearFinderLocator()
    end

    if not GameTooltip then
        return
    end

    if GameTooltip.__WGRGearFinderManaged then
        GameTooltip.__WGRGearFinderManaged =
            nil

        GameTooltip:Hide()
    end
end

local function WGRGearFinderClearChildren(
    frame
)
    if not frame
        or not frame.WGRChildren
    then
        return
    end

    for _, child
        in ipairs(
            frame.WGRChildren
        )
    do
        if child.__WGRGearFinderButton then
            if WGRGearFinderHoveredButton
                == child
            then
                WGRGearFinderHoveredButton =
                    nil
            end

            child:EnableMouse(
                false
            )

            child:SetScript(
                "OnEnter",
                nil
            )

            child:SetScript(
                "OnLeave",
                nil
            )

            child.WGRShowTooltip =
                nil
        end

        child:Hide()
        child:SetParent(nil)
    end

    frame.WGRChildren = {}
end

local WGRGearFinderTrackChild

local function WGRGearFinderCollectEmptyBagSlots()
    local result = {}

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

            if not info then
                result[
                    #result + 1
                ] = {
                    bagID =
                        bagID,
                    slotID =
                        slotID,
                }
            end
        end
    end

    return result
end

local function WGRGearFinderCollectEmptyPersonalBankSlots()
    local result = {}

    for _, bagID
        in ipairs(
            WGRGearFinderGetPersonalBankTabIDs()
            or {}
        )
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

            if not info then
                result[#result + 1] = {
                    bagID = bagID,
                    slotID = slotID,
                }
            end
        end
    end

    return result
end

local function WGRGearFinderCollectEmptyWarbandSlots()
    local result = {}
    local purchased =
        WGRGearFinderGetPurchasedWarbandTabs()

    local settings =
        WGRGearFinderEnsureDepositSettings()

    local allowedBagIDs = {}

    if settings.depositLocation
        == "FIRST_AVAILABLE"
    then
        for _, tab
            in ipairs(purchased)
        do
            allowedBagIDs[
                #allowedBagIDs + 1
            ] =
                tab.bagID
        end

    elseif settings.depositLocation
        == "CUSTOM"
    then
        for _, tab
            in ipairs(purchased)
        do
            if settings.customDepositTabs[
                tab.index
            ] == true
            then
                allowedBagIDs[
                    #allowedBagIDs + 1
                ] =
                    tab.bagID
            end
        end

    else
        local selectedIndex =
            tonumber(
                tostring(
                    settings.depositLocation
                ):match(
                    "^TAB_(%d+)$"
                )
            )

        if selectedIndex then
            for _, tab
                in ipairs(purchased)
            do
                if tab.index
                    == selectedIndex
                then
                    allowedBagIDs[1] =
                        tab.bagID
                    break
                end
            end
        end
    end

    for _, bagID
        in ipairs(allowedBagIDs)
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

            if not info then
                result[
                    #result + 1
                ] = {
                    bagID =
                        bagID,
                    slotID =
                        slotID,
                }
            end
        end
    end

    return result
end

local function WGRGearFinderPhysicalRecordKey(
    record
)
    if not record then
        return nil
    end

    if record.bagID ~= nil
        and record.slotID ~= nil
    then
        return
            tostring(
                record.source
                or "UNKNOWN"
            )
            .. ":"
            .. tostring(
                record.bagID
            )
            .. ":"
            .. tostring(
                record.slotID
            )
    end

    return
        tostring(
            record.source
            or "UNKNOWN"
        )
        .. ":"
        .. tostring(
            record.itemLink
            or record
        )
end

local function WGRGearFinderUniquePhysicalRecords(
    records
)
    local result = {}
    local seen = {}

    for _, record
        in ipairs(
            records
            or {}
        )
    do
        local key =
            WGRGearFinderPhysicalRecordKey(
                record
            )

        if key
            and not seen[key]
        then
            seen[key] = true
            result[
                #result + 1
            ] =
                record
        end
    end

    return result
end

local WGRGearFinderBulkMoveLimit =
    20

local WGRGearFinderBulkMoveBusy =
    false

local function WGRGearFinderRecordNeedsBagMove(
    record
)
    return record
        and (
            record.source == "PERSONAL_BANK"
            or record.source == "WARBAND_BANK"
        )
        and record.bagID ~= nil
        and record.slotID ~= nil
end

local function WGRGearFinderCountMovableRecords(
    records
)
    local count = 0

    for _, record
        in ipairs(
            WGRGearFinderUniquePhysicalRecords(
                records
            )
        )
    do
        if WGRGearFinderRecordNeedsBagMove(
            record
        )
        then
            count = count + 1
        end
    end

    return count
end

local function WGRGearFinderRecordNeedsWarbandDeposit(
    record
)
    return record
        and (
            record.source == "BAGS"
            or record.source == "PERSONAL_BANK"
        )
        and record.bagID ~= nil
        and record.slotID ~= nil
end

local function WGRGearFinderCountDepositableRecords(
    records
)
    local count = 0

    for _, record
        in ipairs(
            WGRGearFinderUniquePhysicalRecords(
                records
            )
        )
    do
        if WGRGearFinderRecordNeedsWarbandDeposit(
            record
        )
        then
            count = count + 1
        end
    end

    return count
end

local function WGRGearFinderRecordNeedsPersonalBankMove(record)
    return record
        and (
            record.source == "BAGS"
            or record.source == "WARBAND_BANK"
        )
        and record.bagID ~= nil
        and record.slotID ~= nil
end

local function WGRGearFinderCountPersonalBankMovableRecords(records)
    local count = 0
    for _, record in ipairs(WGRGearFinderUniquePhysicalRecords(records)) do
        if WGRGearFinderRecordNeedsPersonalBankMove(record) then
            count = count + 1
        end
    end
    return count
end

local function WGRGearFinderMoveRecordsToPersonalBank(records, description)
    if not WGRGearFinderIsPersonalBankAvailable() then
        print("|cffff5555WBGR:|r Open the Personal Bank before moving items.")
        return
    end

    local totalRequested = WGRGearFinderCountPersonalBankMovableRecords(records)
    local requested = math.min(totalRequested, WGRGearFinderBulkMoveLimit)
    if requested == 0 then
        print("|cff33ff99WBGR:|r Nothing in " .. tostring(description or "this group") .. " needs to be moved to the Personal Bank.")
        return
    end

    local destinations = WGRGearFinderCollectEmptyPersonalBankSlots()
    local destinationIndex, processed, moved, unavailable = 1, 0, 0, 0
    local bankFull = false

    for _, record in ipairs(WGRGearFinderUniquePhysicalRecords(records)) do
        if WGRGearFinderRecordNeedsPersonalBankMove(record) then
            if processed >= requested then break end
            processed = processed + 1
            local currentLink = C_Container.GetContainerItemLink(record.bagID, record.slotID)
            if not currentLink or currentLink ~= record.itemLink then
                unavailable = unavailable + 1
            else
                local destination = destinations[destinationIndex]
                if not destination then bankFull = true; break end
                destinationIndex = destinationIndex + 1
                if CursorHasItem and CursorHasItem() then ClearCursor() end
                C_Container.PickupContainerItem(record.bagID, record.slotID)
                if CursorHasItem and CursorHasItem() then
                    C_Container.PickupContainerItem(destination.bagID, destination.slotID)
                    if not CursorHasItem() then moved = moved + 1
                    else ClearCursor(); unavailable = unavailable + 1 end
                else
                    unavailable = unavailable + 1
                end
            end
        end
    end

    local message = "|cff33ff99WBGR:|r Moved " .. tostring(moved) .. " of " .. tostring(requested) .. " " .. tostring(description or "items") .. " to the Personal Bank."
    if bankFull then message = message .. " Personal Bank is full."
    elseif unavailable > 0 then message = message .. " " .. tostring(unavailable) .. " item(s) could not be moved." end
    print(message)

    if moved > 0 and WGRAddRecentActivity then
        WGRAddRecentActivity(tostring(UnitName("player") or "Current character") .. " moved " .. tostring(moved) .. " character gear item" .. (moved == 1 and "" or "s") .. " to the Personal Bank.", "MOVE_PERSONAL_BANK")
    end
    WGRScheduleGearFinderRefresh(0.20)
end

local function WGRGearFinderCreatePersonalBankButton(parent, records, x, y)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(220, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local function RefreshButtonText()
        local count = tonumber(WGRGearFinderCountPersonalBankMovableRecords(records)) or 0
        local batch = math.min(count, WGRGearFinderBulkMoveLimit)
        button:SetText("Move " .. tostring(batch) .. " to Personal Bank (" .. tostring(count) .. " total)")
        if count == 0 or not WGRGearFinderPersonalBankOpen then button:Disable() else button:Enable() end
        return count
    end
    RefreshButtonText()
    button:SetScript("OnClick", function()
        if WGRGearFinderBulkMoveBusy then return end

        local count =
            RefreshButtonText()

        if count <= 0 then return end

        local function DoMove()
            local freshCount =
                WGRGearFinderCountPersonalBankMovableRecords(
                    records
                )

            if freshCount <= 0 then
                RefreshButtonText()
                return
            end

            WGRGearFinderBulkMoveBusy = true
            button:Disable()

            WGRGearFinderMoveRecordsToPersonalBank(
                records,
                "character gear item(s)"
            )

            C_Timer.After(
                0.45,
                function()
                    WGRGearFinderBulkMoveBusy = false
                    RefreshButtonText()
                end
            )
        end

        StaticPopupDialogs[
            "WGR_CONFIRM_MOVE_TO_PERSONAL_BANK"
        ] = StaticPopupDialogs[
            "WGR_CONFIRM_MOVE_TO_PERSONAL_BANK"
        ] or {
            text =
                "Move %d items to %s's Personal Bank?",
            button1 = YES,
            button2 = NO,
            OnAccept =
                function(
                    self,
                    data
                )
                    if data
                        and data.callback
                    then
                        data.callback()
                    end
                end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }

        local batch =
            math.min(
                tonumber(count)
                or 0,
                WGRGearFinderBulkMoveLimit
            )

        StaticPopup_Show(
            "WGR_CONFIRM_MOVE_TO_PERSONAL_BANK",
            batch,
            tostring(
                UnitName("player")
                or "this character"
            ),
            {
                callback =
                    DoMove,
            }
        )
    end)
    WGRGearFinderTrackChild(parent, button)
    return button
end

local function WGRGearFinderMoveRecordsToBags(
    records,
    description
)
    local totalRequested =
        WGRGearFinderCountMovableRecords(
            records
        )

    local requested =
        math.min(
            totalRequested,
            WGRGearFinderBulkMoveLimit
        )

    if requested == 0 then
        print(
            "|cff33ff99WBGR:|r Nothing in "
                .. tostring(description or "this group")
                .. " needs to be moved to bags."
        )
        return
    end

    local moved = 0
    local unavailable = 0
    local bagsFull = false

    local emptyBagSlots =
        WGRGearFinderCollectEmptyBagSlots()

    local destinationIndex = 1
    local processed = 0
    local processed = 0

    for _, record
        in ipairs(
            WGRGearFinderUniquePhysicalRecords(
                records
            )
        )
    do
        if WGRGearFinderRecordNeedsBagMove(
            record
        )
        then
            if processed >= requested then
                break
            end

            processed = processed + 1
            local currentLink =
                C_Container.GetContainerItemLink(
                    record.bagID,
                    record.slotID
                )

            -- Gear Finder is a snapshot. Never move a different item if the
            -- bank changed since the last refresh.
            if not currentLink
                or currentLink ~= record.itemLink
            then
                unavailable =
                    unavailable + 1
            else
                local destination =
                    emptyBagSlots[
                        destinationIndex
                    ]

                if not destination then
                    bagsFull = true
                    break
                end

                destinationIndex =
                    destinationIndex + 1

                local targetBag =
                    destination.bagID

                local targetSlot =
                    destination.slotID

                if CursorHasItem
                    and CursorHasItem()
                then
                    ClearCursor()
                end

                C_Container.PickupContainerItem(
                    record.bagID,
                    record.slotID
                )

                if CursorHasItem
                    and CursorHasItem()
                then
                    C_Container.PickupContainerItem(
                        targetBag,
                        targetSlot
                    )

                    if not CursorHasItem()
                    then
                        moved = moved + 1
                    else
                        -- Do not leave an item attached to the cursor.
                        ClearCursor()
                        unavailable =
                            unavailable + 1
                    end
                else
                    unavailable =
                        unavailable + 1
                end
            end
        end
    end

    local message =
        "|cff33ff99WBGR:|r Moved "
        .. tostring(moved)
        .. " of "
        .. tostring(requested)
        .. " "
        .. tostring(description or "items")
        .. " to bags."

    if bagsFull then
        message =
            message
            .. " Bags are full."
    elseif unavailable > 0 then
        message =
            message
            .. " "
            .. tostring(unavailable)
            .. " item(s) could not be moved."
    end

    print(message)

    if moved > 0
        and WGRAddRecentActivity
    then
        WGRAddRecentActivity(
            tostring(
                UnitName("player")
                or "Current character"
            )
            .. " moved "
            .. tostring(moved)
            .. " item"
            .. (
                moved == 1
                and ""
                or "s"
            )
            .. " to bags.",
            "MOVE_TO_BAGS"
        )
    end

    WGRScheduleGearFinderRefresh(
        0.20
    )
end

local function WGRGearFinderDepositRecordsToWarband(
    records,
    description
)
    if not WGRGearFinderIsWarbandBankAvailable() then
        print(
            "|cffff5555WBGR:|r Open the Warband Bank before moving items."
        )
        return
    end

    local totalRequested =
        WGRGearFinderCountDepositableRecords(
            records
        )

    local requested =
        math.min(
            totalRequested,
            WGRGearFinderBulkMoveLimit
        )

    if requested == 0 then
        print(
            "|cff33ff99WBGR:|r Nothing in "
                .. tostring(description or "this group")
                .. " needs to be moved."
        )
        return
    end

    local moved = 0
    local unavailable = 0
    local warbandFull = false

    local emptyWarbandSlots =
        WGRGearFinderCollectEmptyWarbandSlots()

    local destinationIndex = 1
    local processed = 0

    for _, record
        in ipairs(
            WGRGearFinderUniquePhysicalRecords(
                records
            )
        )
    do
        if WGRGearFinderRecordNeedsWarbandDeposit(
            record
        )
        then
            if processed
                >= requested
            then
                break
            end

            processed =
                processed + 1
            local currentLink =
                C_Container.GetContainerItemLink(
                    record.bagID,
                    record.slotID
                )

            if not currentLink
                or currentLink ~= record.itemLink
            then
                unavailable =
                    unavailable + 1
            else
                local destination =
                    emptyWarbandSlots[
                        destinationIndex
                    ]

                if not destination then
                    warbandFull = true
                    break
                end

                destinationIndex =
                    destinationIndex + 1

                local targetBag =
                    destination.bagID

                local targetSlot =
                    destination.slotID

                if CursorHasItem
                    and CursorHasItem()
                then
                    ClearCursor()
                end

                C_Container.PickupContainerItem(
                    record.bagID,
                    record.slotID
                )

                if CursorHasItem
                    and CursorHasItem()
                then
                    C_Container.PickupContainerItem(
                        targetBag,
                        targetSlot
                    )

                    if not CursorHasItem() then
                        moved = moved + 1
                    else
                        ClearCursor()
                        unavailable =
                            unavailable + 1
                    end
                else
                    unavailable =
                        unavailable + 1
                end
            end
        end
    end

    local message =
        "|cff33ff99WBGR:|r Moved "
        .. tostring(moved)
        .. " of "
        .. tostring(requested)
        .. " "
        .. tostring(description or "items")
        .. " to the Warband Bank."

    if warbandFull then
        message =
            message
            .. " Warband Bank is full."
    elseif unavailable > 0 then
        message =
            message
            .. " "
            .. tostring(unavailable)
            .. " item(s) could not be moved."
    end

    print(message)

    if moved > 0
        and WGRAddRecentActivity
    then
        WGRAddRecentActivity(
            tostring(
                UnitName("player")
                or "Current character"
            )
            .. " moved "
            .. tostring(moved)
            .. " item"
            .. (
                moved == 1
                and ""
                or "s"
            )
            .. " to the Warband Bank.",
            "DEPOSIT_WARBANK"
        )
    end

    WGRScheduleGearFinderRefresh(
        0.20
    )
end

local function WGRGearFinderCreateMoveButton(
    parent,
    records,
    x,
    y,
    baseText,
    description,
    alwaysConfirm
)
    local button =
        CreateFrame(
            "Button",
            nil,
            parent,
            "UIPanelButtonTemplate"
        )

    button:SetSize(
        220,
        22
    )

    button:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        x,
        y
    )

    local function RefreshButtonText()
        local movable =
            WGRGearFinderCountMovableRecords(
                records
            )

        movable =
            tonumber(movable)
            or 0

        local batch =
            math.min(
                movable,
                WGRGearFinderBulkMoveLimit
            )

        button:SetText(
            "Move "
                .. tostring(batch)
                .. " to Bags ("
                .. tostring(movable)
                .. " total)"
        )

        if movable == 0 then
            button:Disable()
        else
            button:Enable()
        end

        return movable
    end

    RefreshButtonText()

    button:SetScript(
        "OnClick",
        function()
            if WGRGearFinderBulkMoveBusy then
                return
            end

            local movable =
                RefreshButtonText()

            if movable <= 0 then
                return
            end

            local shouldConfirm =
                alwaysConfirm == true
                or movable
                    > WGRGearFinderConfirmThreshold

            local function DoMove()
                local freshCount =
                    WGRGearFinderCountMovableRecords(
                        records
                    )

                if freshCount <= 0 then
                    RefreshButtonText()
                    return
                end

                WGRGearFinderBulkMoveBusy =
                    true

                button:Disable()

                WGRGearFinderMoveRecordsToBags(
                    records,
                    description
                )

                C_Timer.After(
                    0.45,
                    function()
                        WGRGearFinderBulkMoveBusy =
                            false

                        RefreshButtonText()
                    end
                )
            end

            if not shouldConfirm then
                DoMove()
                return
            end

            local batch =
                math.min(
                    tonumber(movable)
                        or 0,
                    WGRGearFinderBulkMoveLimit
                )

            local dialog =
                StaticPopup_Show(
                    "WGR_CONFIRM_MOVE_TO_BAGS",
                    batch,
                    tostring(
                        description
                        or "item(s)"
                    ),
                    {
                        callback =
                            DoMove,
                    }
                )

            if not dialog then
                print(
                    "|cffff5555WBGR:|r Unable to open move confirmation."
                )
            end
        end
    )

    WGRGearFinderTrackChild(
        parent,
        button
    )

    return button
end

local function WGRGearFinderCreateDepositButton(
    parent,
    records,
    x,
    y,
    baseText,
    description,
    alwaysConfirm
)
    local button =
        CreateFrame(
            "Button",
            nil,
            parent,
            "UIPanelButtonTemplate"
        )

    button:SetSize(
        220,
        22
    )

    button:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        x,
        y
    )

    local function RefreshButtonText()
        local count =
            WGRGearFinderCountDepositableRecords(
                records
            )

        count =
            tonumber(count)
            or 0

        local batch =
            math.min(
                count,
                WGRGearFinderBulkMoveLimit
            )

        button:SetText(
            "Move "
                .. tostring(batch)
                .. " to Warbank ("
                .. tostring(count)
                .. " total)"
        )

        if count == 0
            or not WGRGearFinderWarbandBankOpen
        then
            button:Disable()
        else
            button:Enable()
        end

        return count
    end

    RefreshButtonText()

    button:SetScript(
        "OnClick",
        function()
            if WGRGearFinderBulkMoveBusy then
                return
            end

            local count =
                RefreshButtonText()

            if count <= 0 then
                return
            end

            local shouldConfirm =
                alwaysConfirm == true
                or count
                    > WGRGearFinderConfirmThreshold

            local function DoDeposit()
                local freshCount =
                    WGRGearFinderCountDepositableRecords(
                        records
                    )

                if freshCount <= 0 then
                    RefreshButtonText()
                    return
                end

                WGRGearFinderBulkMoveBusy =
                    true

                button:Disable()

                WGRGearFinderDepositRecordsToWarband(
                    records,
                    description
                )

                C_Timer.After(
                    0.45,
                    function()
                        WGRGearFinderBulkMoveBusy =
                            false

                        RefreshButtonText()
                    end
                )
            end

            if not shouldConfirm then
                DoDeposit()
                return
            end

            StaticPopupDialogs[
                "WGR_CONFIRM_DEPOSIT_TO_WARBAND"
            ] = StaticPopupDialogs[
                "WGR_CONFIRM_DEPOSIT_TO_WARBAND"
            ] or {
                text =
                    "Move %d %s to the Warband Bank?",
                button1 =
                    YES,
                button2 =
                    NO,
                OnAccept =
                    function(
                        self,
                        data
                    )
                        if data
                            and data.callback
                        then
                            data.callback()
                        end
                    end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }

            local batch =
                math.min(
                    tonumber(count)
                        or 0,
                    WGRGearFinderBulkMoveLimit
                )

            StaticPopup_Show(
                "WGR_CONFIRM_DEPOSIT_TO_WARBAND",
                batch,
                tostring(
                    description
                    or "item(s)"
                ),
                {
                    callback =
                        DoDeposit,
                }
            )
        end
    )

    WGRGearFinderTrackChild(
        parent,
        button
    )

    return button
end

WGRGearFinderTrackChild =
function(
    parent,
    child
)
    parent.WGRChildren =
        parent.WGRChildren
        or {}

    parent.WGRChildren[
        #parent.WGRChildren + 1
    ] =
        child
end

local function WGRGearFinderDepositLocationLabel(
    value
)
    if value == "FIRST_AVAILABLE" then
        return "First Available Slot"
    end

    if value == "CUSTOM" then
        return "Custom"
    end

    local index =
        tonumber(
            tostring(value):match(
                "^TAB_(%d+)$"
            )
        )

    if index then
        return "Tab "
            .. tostring(index)
    end

    return "First Available Slot"
end

local function WGRGearFinderCustomDepositSummary()
    local settings =
        WGRGearFinderEnsureDepositSettings()

    local selected = {}

    for _, tab
        in ipairs(
            WGRGearFinderGetPurchasedWarbandTabs()
        )
    do
        if settings.customDepositTabs[
            tab.index
        ] == true
        then
            selected[
                #selected + 1
            ] =
                tostring(tab.index)
        end
    end

    if #selected == 0 then
        return "No tabs selected"
    end

    return "Tabs "
        .. table.concat(
            selected,
            ", "
        )
end

local function WGRGearFinderShowCustomDepositPanel(
    frame
)
    local settings =
        WGRGearFinderEnsureDepositSettings()

    local panel =
        frame.WGRCustomDepositPanel

    if not panel then
        panel =
            CreateFrame(
                "Frame",
                nil,
                UIParent,
                "BackdropTemplate"
            )

        panel:SetSize(
            310,
            240
        )

        panel:SetFrameStrata(
            "DIALOG"
        )
        panel:SetFrameLevel(
            100
        )
        panel:SetBackdrop({
            bgFile =
                "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile =
                "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = {
                left = 4,
                right = 4,
                top = 4,
                bottom = 4,
            },
        })
        panel:SetBackdropColor(
            0.05,
            0.05,
            0.05,
            0.97
        )

        panel:EnableMouse(
            true
        )
        panel:SetClampedToScreen(
            true
        )

        local title =
            panel:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormalLarge"
            )
        title:SetPoint(
            "TOP",
            panel,
            "TOP",
            0,
            -14
        )
        title:SetText(
            "Custom Warband Deposit Tabs"
        )

        panel.checkboxes = {}

        local save =
            CreateFrame(
                "Button",
                nil,
                panel,
                "UIPanelButtonTemplate"
            )
        save:SetSize(
            90,
            24
        )
        save:SetPoint(
            "BOTTOMLEFT",
            panel,
            "BOTTOMLEFT",
            52,
            16
        )
        save:SetText(
            "Save"
        )

        local cancel =
            CreateFrame(
                "Button",
                nil,
                panel,
                "UIPanelButtonTemplate"
            )
        cancel:SetSize(
            90,
            24
        )
        cancel:SetPoint(
            "BOTTOMRIGHT",
            panel,
            "BOTTOMRIGHT",
            -52,
            16
        )
        cancel:SetText(
            "Cancel"
        )
        cancel:SetScript(
            "OnClick",
            function()
                panel:Hide()
            end
        )

        save:SetScript(
            "OnClick",
            function()
                local anySelected = false

                for _, check
                    in ipairs(
                        panel.checkboxes
                    )
                do
                    local selected =
                        check:GetChecked()
                        == true

                    settings.customDepositTabs[
                        check.WGRTabIndex
                    ] =
                        selected

                    if selected then
                        anySelected = true
                    end
                end

                if not anySelected then
                    print(
                        "|cffff5555WBGR:|r Select at least one Warband Bank tab."
                    )
                    return
                end

                settings.depositLocation =
                    "CUSTOM"

                panel:Hide()

                WGRScheduleGearFinderRefresh(
                    0.05
                )
            end
        )

        frame.WGRCustomDepositPanel =
            panel
    end

    for _, check
        in ipairs(
            panel.checkboxes
            or {}
        )
    do
        check:Hide()
    end

    panel.checkboxes = {}

    local y = -50

    for _, tab
        in ipairs(
            WGRGearFinderGetPurchasedWarbandTabs()
        )
    do
        local check =
            CreateFrame(
                "CheckButton",
                nil,
                panel,
                "UICheckButtonTemplate"
            )

        check:SetPoint(
            "TOPLEFT",
            panel,
            "TOPLEFT",
            28,
            y
        )
        check.text:SetText(
            "Tab "
                .. tostring(tab.index)
        )
        check:SetChecked(
            settings.customDepositTabs[
                tab.index
            ] == true
        )
        check.WGRTabIndex =
            tab.index

        panel.checkboxes[
            #panel.checkboxes + 1
        ] =
            check

        y = y - 28
    end

    panel:ClearAllPoints()

    local dropdown =
        frame.gearFinderDepositDropdown

    if dropdown
        and dropdown:IsShown()
    then
        panel:SetPoint(
            "TOPLEFT",
            dropdown,
            "TOPLEFT",
            0,
            0
        )
    else
        panel:SetPoint(
            "TOPLEFT",
            frame,
            "TOPLEFT",
            200,
            -120
        )
    end

    panel:Show()
end

local function WGRGearFinderActionItemName(record)
    if not record or not record.itemLink then return "item" end
    return (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(record.itemLink))
        or GetItemInfo(record.itemLink)
        or "item"
end

local function WGRGearFinderRecordItemID(itemLink)
    if not itemLink then return nil end
    local info = GetInstantItemInfo(itemLink)
    if info and info.itemID then return tonumber(info.itemID) end
    return tonumber(tostring(itemLink):match("item:(%d+)"))
end

local function WGRGearFinderChooseTargetEquipSlot(record)
    if not record then return nil end
    if tonumber(record.targetEquipSlot) then
        return tonumber(record.targetEquipSlot)
    end

    local equipLoc = record.equipLoc
    local armorSlot = equipLoc and WGRArmorEquipSlots[equipLoc]
    if armorSlot then return armorSlot end

    if WGROffhandEquipLocs[equipLoc] then return 17 end

    if IsSupportedWeapon(record.itemLink) then return 16 end

    local slots = equipLoc and WGRGlobalEquipSlots[equipLoc]
    if type(slots) ~= "table" or #slots == 0 then return nil end
    if #slots == 1 then return slots[1] end

    -- Rings and trinkets: if this is a higher version of an item already
    -- equipped, replace that physical copy. Otherwise replace the weaker slot.
    local incomingID = WGRGearFinderRecordItemID(record.itemLink)
    local sameItemSlot = nil
    local sameItemLevel = nil
    local weakestSlot = slots[1]
    local weakestLevel = nil

    for _, slotID in ipairs(slots) do
        local equippedLink = GetInventoryItemLink("player", slotID)
        local level = equippedLink and (tonumber(GetItemLevel(equippedLink)) or 0) or 0
        if weakestLevel == nil or level < weakestLevel then
            weakestLevel = level
            weakestSlot = slotID
        end

        if equippedLink and incomingID
            and WGRGearFinderRecordItemID(equippedLink) == incomingID
        then
            if sameItemLevel == nil or level < sameItemLevel then
                sameItemLevel = level
                sameItemSlot = slotID
            end
        end
    end

    return sameItemSlot or weakestSlot
end

local function WGRGearFinderEquipBagSlot(
    bagID,
    slotID,
    targetSlot,
    itemLink
)
    if InCombatLockdown
        and InCombatLockdown()
    then
        print("|cffff5555WBGR:|r Cannot equip gear while in combat.")
        return false
    end

    if type(bagID) ~= "number"
        or type(slotID) ~= "number"
        or not targetSlot
    then
        print("|cffff5555WBGR:|r Could not equip item: target slot is unknown.")
        return false
    end

    local currentLink =
        C_Container.GetContainerItemLink(
            bagID,
            slotID
        )

    if not currentLink
        or (
            itemLink
            and not WGRGearFinderKnownItemMatches(
                currentLink,
                itemLink
            )
        )
    then
        print("|cffff5555WBGR:|r Could not equip item: its location changed. Refresh Gear Finder.")
        return false
    end

    if not C_Item
        or not C_Item.EquipItemByName
    then
        print("|cffff5555WBGR:|r Could not equip item: EquipItemByName is unavailable.")
        return false
    end

    local itemName =
        WGRGearFinderActionItemName(
            { itemLink = currentLink }
        )

    print(
        "|cff33ff99WBGR:|r Equip requested for "
        .. tostring(itemName)
        .. "."
    )

    C_Item.EquipItemByName(
        currentLink,
        targetSlot
    )

    -- Bind-on-equip confirmation can legitimately keep the item unequipped
    -- until the player confirms, so do not report failure here.
    WGRScheduleGearFinderRefresh(0.50)

    return true
end

local function WGRGearFinderHandleRecommendationAction(record)
    if not record or not record.itemLink then
        return
    end

    local itemName =
        WGRGearFinderActionItemName(
            record
        )

    local targetSlot =
        WGRGearFinderChooseTargetEquipSlot(
            record
        )

    if not targetSlot then
        print(
            "|cffff5555WBGR:|r Could not equip "
            .. tostring(itemName)
            .. ": target slot is unknown."
        )
        return
    end

    if InCombatLockdown
        and InCombatLockdown()
    then
        print(
            "|cffff5555WBGR:|r Cannot move or equip "
            .. tostring(itemName)
            .. " while in combat."
        )
        return
    end

    -- If the item is already in Bags, this is the second click:
    -- attempt to equip it into Gear Finder's intended slot.
    if record.source == "BAGS" then
        print(
            "|cff33ff99WBGR:|r Equipping "
            .. tostring(itemName)
            .. "..."
        )

        WGRGearFinderEquipBagSlot(
            record.bagID,
            record.slotID,
            targetSlot,
            record.itemLink
        )

        return
    end

    -- Otherwise first click is retrieval only.
    if record.source == "WARBAND_BANK" then
        if not WGRGearFinderIsWarbandBankAvailable() then
            print(
                "|cffff5555WBGR:|r Open the Warband Bank to retrieve "
                .. tostring(itemName)
                .. "."
            )
            return
        end
    elseif record.source == "PERSONAL_BANK" then
        if not WGRGearFinderIsPersonalBankAvailable() then
            print(
                "|cffff5555WBGR:|r Open the Personal Bank to retrieve "
                .. tostring(itemName)
                .. "."
            )
            return
        end
    else
        print(
            "|cffff5555WBGR:|r Could not retrieve "
            .. tostring(itemName)
            .. ": location is unknown."
        )
        return
    end

    local currentLink =
        C_Container.GetContainerItemLink(
            record.bagID,
            record.slotID
        )

    if not currentLink
        or not WGRGearFinderKnownItemMatches(
            currentLink,
            record.itemLink
        )
    then
        print(
            "|cffff5555WBGR:|r Could not retrieve "
            .. tostring(itemName)
            .. ": its location changed. Refresh Gear Finder."
        )
        return
    end

    local destinations =
        WGRGearFinderCollectEmptyBagSlots()

    local destination =
        destinations
        and destinations[1]

    if not destination then
        print(
            "|cffff5555WBGR:|r Could not retrieve "
            .. tostring(itemName)
            .. ": Bags are full."
        )
        return
    end

    if CursorHasItem
        and CursorHasItem()
    then
        ClearCursor()
    end

    C_Container.PickupContainerItem(
        record.bagID,
        record.slotID
    )

    if not (
        CursorHasItem
        and CursorHasItem()
    ) then
        print(
            "|cffff5555WBGR:|r Could not retrieve "
            .. tostring(itemName)
            .. "."
        )
        return
    end

    C_Container.PickupContainerItem(
        destination.bagID,
        destination.slotID
    )

    if CursorHasItem
        and CursorHasItem()
    then
        ClearCursor()

        print(
            "|cffff5555WBGR:|r Could not move "
            .. tostring(itemName)
            .. " to Bags."
        )
        return
    end

    print(
        "|cff33ff99WBGR:|r Moved "
        .. tostring(itemName)
        .. " to Bags. Click Equip to equip it."
    )

    WGRScheduleGearFinderRefresh(
        0.20
    )
end


local function WGRGearFinderCreateRecommendationActionButton(
    parent,
    x,
    y,
    width,
    text,
    record,
    targetSlot
)
    local button =
        CreateFrame(
            "Button",
            nil,
            parent,
            "UIPanelButtonTemplate"
        )

    local iconWidth =
        record
        and record.compactWeapon
        and 32
        or 34

    local requestedWidth =
        tonumber(width)
        or iconWidth

    local buttonWidth =
        math.min(
            requestedWidth,
            iconWidth
        )

    button:SetSize(
        buttonWidth,
        14
    )

    button:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        x,
        y
    )

    local actionText =
        text
        or "Equip"

    if record then
        if record.source == "BAGS" then
            actionText = "Equip"
        elseif record.source == "PERSONAL_BANK"
            or record.source == "WARBAND_BANK"
        then
            actionText = "Get"
        end
    end

    button:SetText(
        actionText
    )

    local fontString =
        button:GetFontString()

    if fontString then
        local font,
              _,
              flags =
            fontString:GetFont()

        if font then
            fontString:SetFont(
                font,
                9,
                flags
            )
        end
    end

    button:SetScript(
        "OnClick",
        function()
            if record then
                record.targetEquipSlot =
                    targetSlot
                    or record.targetEquipSlot

                WGRGearFinderHandleRecommendationAction(
                    record
                )
            end
        end
    )

    WGRGearFinderTrackChild(
        parent,
        button
    )

    return button
end


local function WGRGearFinderCreateItemButton(
    parent,
    record,
    x,
    y,
    labelText
)
    local button =
        CreateFrame(
            "Button",
            nil,
            parent
        )

    button:SetSize(
        record.compactWeapon and 42 or 42,
        54
    )

    button.__WGRGearFinderButton =
        true

    button:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        x,
        y
    )

    local icon =
        button:CreateTexture(
            nil,
            "ARTWORK"
        )


    icon:SetSize(
        record.compactWeapon and 32 or 34,
        record.compactWeapon and 32 or 34
    )

    icon:SetPoint(
        "TOP",
        button,
        "TOP",
        0,
        0
    )

    icon:SetTexture(
        WGRGearFinderItemTexture(
            record.itemLink
        )
    )

    local label =
        button:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    label:SetPoint(
        "TOP",
        icon,
        "BOTTOM",
        0,
        -1
    )

    label:SetWidth(
        record.compactWeapon and 44 or 44
    )

    label:SetJustifyH(
        "CENTER"
    )

    label:SetText(
        labelText
        or (
            record.upgrade
            and (
                "+"
                .. tostring(
                    math.floor(
                        record.upgrade
                    )
                )
            )
            or ""
        )
    )

    local function ShowGearFinderTooltip(
        self
    )
        -- Shift/modifier refreshes can rebuild this virtual tooltip while it
        -- is already visible. Clear the previous tooltip first so WGR's
        -- routing block replaces the old block instead of being appended a
        -- second time. This restores the earlier single-tooltip behavior.
        if GameTooltip:IsShown() then
            GameTooltip:Hide()
        end

        GameTooltip:ClearLines()
        GameTooltip.__WGRLineAdded = false
        GameTooltip.__WGRIgnoredItemLink = nil

        GameTooltip:SetOwner(
            self,
            "ANCHOR_RIGHT"
        )

        local usedContainerTooltip =
            false

        if (
            record.source == "BAGS"
            or record.source == "PERSONAL_BANK"
            or record.source == "WARBAND_BANK"
        )
            and type(record.bagID) == "number"
            and type(record.slotID) == "number"
            and GameTooltip.SetBagItem
        then
            local currentLink =
                C_Container.GetContainerItemLink(
                    record.bagID,
                    record.slotID
                )

            if currentLink
                and currentLink == record.itemLink
            then
                -- Use Blizzard's actual bag-slot tooltip path so tooltip
                -- addons receive the same underlying container context they
                -- get when the user hovers the physical item in a bag.
                GameTooltip:SetBagItem(
                    record.bagID,
                    record.slotID
                )

                usedContainerTooltip =
                    true
            end
        end

        if not usedContainerTooltip then
            -- Fallback for a moved item, stale location, or future sources
            -- that do not expose a direct container tooltip path.
            GameTooltip:SetHyperlink(
                record.itemLink
            )
        end


        -- Set this after SetBagItem/SetHyperlink. Blizzard may clear tooltip
        -- state while rebuilding the item tooltip, which previously caused
        -- Gear Finder's managed state to disappear until Shift refreshed it.
        GameTooltip.__WGRGearFinderManaged =
            true

        if record.specName then
            GameTooltip:AddLine(
                "Useful for "
                .. record.specName,
                0.85,
                0.85,
                0.85
            )
        end

        GameTooltip:Show()

        -- Gear Finder should show the same routing information as the physical
        -- item immediately. Shift still expands the normal WGR alternatives.
        if WGRRenderRecommendationForItemTooltip then
            WGRRenderRecommendationForItemTooltip(
                GameTooltip,
                record.itemLink,
                {
                    source = record.source,
                    classification = record.classification,
                }
            )
        end
    end

    button.WGRShowTooltip =
        ShowGearFinderTooltip

    button:RegisterForClicks(
        "LeftButtonUp",
        "RightButtonUp"
    )

    button:SetScript(
        "OnClick",
        function(
            self,
            mouseButton
        )
            if record.ownedBaseline
                or mouseButton ~= "RightButton"
            then
                return
            end

            MenuUtil.CreateContextMenu(
                self,
                function(
                    ownerRegion,
                    rootDescription
                )
                    local itemName =
                        C_Item.GetItemInfo(
                            record.itemLink
                        )
                        or "This item"

                    rootDescription:CreateTitle(
                        itemName
                    )

                    rootDescription:CreateButton(
                        "Ignore this item in WBGR",
                        function()
                            local locationText =
                                "Location unknown"

                            if record.source == "BAGS" then
                                locationText =
                                    tostring(
                                        WGRGearFinderCurrentName()
                                        or "Current Character"
                                    )
                                    .. " — Bags"
                            elseif record.source == "PERSONAL_BANK" then
                                locationText =
                                    tostring(
                                        WGRGearFinderCurrentName()
                                        or "Current Character"
                                    )
                                    .. " — Personal Bank"
                            elseif record.source == "WARBAND_BANK" then
                                locationText =
                                    "Warband Bank"
                            end

                            WGRSetItemIgnored(
                                record.itemLink,
                                true,
                                locationText
                            )

                            print(
                                "|cffaaaaaaWBGR:|r Ignoring "
                                .. tostring(itemName)
                                .. "."
                            )
                        end
                    )
                end
            )
        end
    )

    button:SetScript(
        "OnEnter",
        function(
            self
        )
            WGRGearFinderHoveredButton =
                self

            if WGRShowGearFinderLocator then
                WGRShowGearFinderLocator(
                    record.source,
                    record.bagID,
                    record.slotID,
                    record.itemLink
                )
            end

            ShowGearFinderTooltip(
                self
            )
        end
    )

    button:SetScript(
        "OnLeave",
        function(
            self
        )
            if WGRGearFinderHoveredButton
                == self
            then
                WGRGearFinderHoveredButton =
                    nil
            end

            if WGRHideGearFinderLocator then
                WGRHideGearFinderLocator()
            end

            GameTooltip.__WGRGearFinderManaged =
                nil

            GameTooltip:Hide()
        end
    )

    WGRGearFinderTrackChild(
        parent,
        button
    )

    return button
end

local function WGRGearFinderAddHeading(
    parent,
    text,
    y,
    color
)
    local heading =
        parent:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    heading:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        0,
        y
    )

    heading:SetText(
        text
    )

    if color then
        heading:SetTextColor(
            color[1],
            color[2],
            color[3]
        )
    end

    WGRGearFinderTrackChild(
        parent,
        heading
    )

    return heading
end

local function WGRGearFinderRender(
    frame,
    scan,
    specs
)
    if not frame
        or not frame.gearFinderContent
    then
        return
    end

    local content =
        frame.gearFinderContent

    WGRGearFinderReleaseTooltip()

    WGRGearFinderClearChildren(
        content
    )

    local characterName =
        WGRGearFinderCurrentName()

    local character =
        FindCharacterByName(
            characterName
        )

    local classified =
        WGRGearFinderClassify(
            scan,
            specs,
            character
        )

    local specParts = {}

    for _, spec
        in ipairs(specs)
    do
        local count =
            classified.bySpec[
                spec.id
            ].count
            or 0

        local text =
            spec.name
            .. (
                spec.current
                and " (Current)"
                or ""
            )

        if count > 0 then
            text =
                text
                .. " "
                .. tostring(count)
        else
            text =
                text
                .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
        end

        specParts[
            #specParts + 1
        ] =
            text
    end

    frame.gearFinderSpecStatus:SetText(
        "Specs: "
        .. (
            #specParts > 0
            and table.concat(
                specParts,
                "  \194\183  "
            )
            or "No routed specs available"
        )
    )

    -- The scan controller owns gearFinderSummary. Keeping this render
    -- path silent prevents overlapping intermediate status text.

    local y = -4
    local rowLabelWidth = 118
    local contentWidth = 860

    do
        local settings =
            WGRGearFinderEnsureDepositSettings()

        local label =
            content:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )
        label:SetPoint(
            "TOPLEFT",
            content,
            "TOPLEFT",
            8,
            y
        )
        label:SetText(
            "Warband Bank Move Location:"
        )
        WGRGearFinderTrackChild(
            content,
            label
        )

        local dropdown =
            CreateFrame(
                "Frame",
                nil,
                content,
                "UIDropDownMenuTemplate"
            )
        dropdown:SetPoint(
            "TOPLEFT",
            content,
            "TOPLEFT",
            166,
            y + 6
        )
        UIDropDownMenu_SetWidth(
            dropdown,
            170
        )
        UIDropDownMenu_SetText(
            dropdown,
            WGRGearFinderDepositLocationLabel(
                settings.depositLocation
            )
        )

        frame.gearFinderDepositDropdown =
            dropdown

        UIDropDownMenu_Initialize(
            dropdown,
            function(
                self,
                level
            )
                local first =
                    UIDropDownMenu_CreateInfo()

                first.text =
                    "First Available Slot"
                first.checked =
                    settings.depositLocation
                    == "FIRST_AVAILABLE"
                first.func =
                    function()
                        settings.depositLocation =
                            "FIRST_AVAILABLE"
                        WGRScheduleGearFinderRefresh(
                            0.05
                        )
                    end

                UIDropDownMenu_AddButton(
                    first,
                    level
                )

                for _, tab
                    in ipairs(
                        WGRGearFinderGetPurchasedWarbandTabs()
                    )
                do
                    local tabIndex =
                        tab.index

                    local tabValue =
                        "TAB_"
                        .. tostring(tabIndex)

                    local info =
                        UIDropDownMenu_CreateInfo()

                    info.text =
                        "Tab "
                        .. tostring(tabIndex)
                    info.checked =
                        settings.depositLocation
                        == tabValue
                    info.func =
                        function()
                            settings.depositLocation =
                                tabValue
                            WGRScheduleGearFinderRefresh(
                                0.05
                            )
                        end

                    UIDropDownMenu_AddButton(
                        info,
                        level
                    )
                end

                local custom =
                    UIDropDownMenu_CreateInfo()

                custom.text =
                    "Custom"
                custom.checked =
                    settings.depositLocation
                    == "CUSTOM"
                custom.func =
                    function()
                        WGRGearFinderShowCustomDepositPanel(
                            frame
                        )
                    end

                UIDropDownMenu_AddButton(
                    custom,
                    level
                )
            end
        )

        WGRGearFinderTrackChild(
            content,
            dropdown
        )

        if settings.depositLocation
            == "CUSTOM"
        then
            local summary =
                content:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlightSmall"
                )
            summary:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                372,
                y
            )
            summary:SetTextColor(
                0.70,
                0.70,
                0.70
            )
            summary:SetText(
                WGRGearFinderCustomDepositSummary()
            )
            WGRGearFinderTrackChild(
                content,
                summary
            )
        end

        y = y - 34
    end

    local activeSpecs = {}

    for _, spec
        in ipairs(specs)
    do
        local bucket =
            classified.bySpec[
                spec.id
            ]

        if #bucket.best > 0
            or #bucket.compare > 0
            or bucket.weaponDisplay ~= nil
        then
            activeSpecs[
                #activeSpecs + 1
            ] =
                spec
        end
    end

    do
        local centerX = contentWidth / 2
        local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText("CURRENT CHARACTER")
        label:SetTextColor(1.00, 0.82, 0.00)
        label:SetPoint("TOP", content, "TOPLEFT", centerX, y)
        WGRGearFinderTrackChild(content, label)
        local gap = math.max(110, (label:GetStringWidth() / 2) + 18)

        local leftLine = content:CreateTexture(nil, "ARTWORK")
        leftLine:SetColorTexture(1.00, 0.82, 0.00, 0.78)
        leftLine:SetHeight(2)
        leftLine:SetPoint("LEFT", content, "TOPLEFT", 8, y - 7)
        leftLine:SetPoint("RIGHT", content, "TOPLEFT", centerX - gap, y - 7)
        WGRGearFinderTrackChild(content, leftLine)

        local rightLine = content:CreateTexture(nil, "ARTWORK")
        rightLine:SetColorTexture(1.00, 0.82, 0.00, 0.78)
        rightLine:SetHeight(2)
        rightLine:SetPoint("LEFT", content, "TOPLEFT", centerX + gap, y - 7)
        rightLine:SetPoint("RIGHT", content, "TOPLEFT", contentWidth - 8, y - 7)
        WGRGearFinderTrackChild(content, rightLine)
        y = y - 28
    end

    if #activeSpecs == 0 then
        WGRGearFinderAddHeading(
            content,
            "BEST UPGRADES",
            y,
            WGRGearFinderColors.BEST
        )

        local empty =
            content:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        empty:SetPoint(
            "TOPLEFT",
            content,
            "TOPLEFT",
            rowLabelWidth,
            y
        )

        empty:SetTextColor(
            0.70,
            0.70,
            0.70
        )

        empty:SetText(
            "No threshold-qualified upgrades found."
        )

        WGRGearFinderTrackChild(
            content,
            empty
        )

        y = y - 42
    else
        local specLeft =
            8

        local specArea =
            contentWidth
            - 16

        local columnWidth =
            math.floor(
                specArea
                / #activeSpecs
            )

        local function CollectSpecRowRecords(
            key
        )
            local result = {}

            for _, spec
                in ipairs(activeSpecs)
            do
                local list =
                    classified.bySpec[
                        spec.id
                    ][key]
                    or {}

                for _, record
                    in ipairs(list)
                do
                    result[
                        #result + 1
                    ] =
                        record
                end
            end

            return result
        end

        local function RenderSpecRow(
            title,
            key,
            color
        )
            local rowRecords =
                CollectSpecRowRecords(
                    key
                )

            if #rowRecords == 0 then
                return
            end

            WGRGearFinderAddHeading(
                content,
                title,
                y,
                color
            )

            WGRGearFinderCreateMoveButton(
                content,
                rowRecords,
                156,
                y + 4,
                "Move All to Bags",
                title .. " item(s)",
                true
            )

            WGRGearFinderCreateDepositButton(
                content,
                rowRecords,
                384,
                y + 4,
                "Move to Warbank",
                title .. " item(s)",
                true
            )

            WGRGearFinderCreatePersonalBankButton(
                content,
                rowRecords,
                612,
                y + 4
            )

            -- Give the section controls their own line. Spec headings and
            -- gear begin below it so the buttons never overlap Holy/etc.
            y = y - 30

            for index, spec
                in ipairs(activeSpecs)
            do
                local heading =
                    content:CreateFontString(
                        nil,
                        "OVERLAY",
                        "GameFontNormalSmall"
                    )

                heading:SetPoint(
                    "TOPLEFT",
                    content,
                    "TOPLEFT",
                    specLeft
                        + (
                            (index - 1)
                            * columnWidth
                        ),
                    y
                )

                heading:SetWidth(
                    columnWidth - 4
                )

                heading:SetJustifyH(
                    "CENTER"
                )

                heading:SetText(
                    spec.name
                    .. (
                        spec.current
                        and " (Current)"
                        or ""
                    )
                )

                WGRGearFinderTrackChild(
                    content,
                    heading
                )
            end

            y = y - 20

            local specContentTop = y + 16
            local maxHeight = 58

            for specIndex, spec
                in ipairs(activeSpecs)
            do
                local list =
                    classified.bySpec[
                        spec.id
                    ][key]

                local groups =
                    WGRGearFinderBuildGroups(
                        list
                    )

                local x =
                    specLeft
                    + (
                        (specIndex - 1)
                        * columnWidth
                    )
                    + 4

                local startX = x
                local lineY = y
                local iconSpacing = 38
                local iconRowHeight = (key == "best") and 68 or 58
                local labelHeight = 14
                local groupGap = 8
                local iconsPerLine =
                    math.max(
                        1,
                        math.floor(
                            (columnWidth - 8)
                            / iconSpacing
                        )
                    )
                local usedHeight = 0

                -- Each gear category owns the full width of its spec column.
                -- Its icons wrap downward inside that column before the next
                -- category begins. This prevents long groups (especially
                -- trinkets) from spilling into the neighboring spec column.
                for _, group
                    in ipairs(groups)
                do
                    local label =
                        content:CreateFontString(
                            nil,
                            "OVERLAY",
                            "GameFontHighlightSmall"
                        )

                    label:SetPoint(
                        "TOPLEFT",
                        content,
                        "TOPLEFT",
                        startX,
                        lineY
                    )

                    label:SetWidth(
                        columnWidth - 8
                    )
                    label:SetJustifyH("CENTER")

                    label:SetTextColor(
                        0.65,
                        0.65,
                        0.65
                    )

                    label:SetText(
                        group.label
                    )

                    WGRGearFinderTrackChild(
                        content,
                        label
                    )

                    local multipleChoices = #group.records > 1
                    local actionHeight = multipleChoices and 14 or 20
                    local selectHeight = multipleChoices and 20 or 0

                    if multipleChoices then
                        local action = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        action:SetPoint("TOPLEFT", content, "TOPLEFT", startX, lineY - labelHeight)
                        action:SetWidth(columnWidth - 8)
                        action:SetJustifyH("CENTER")
                        action:SetTextColor(0.88, 0.88, 0.88)
                        action:SetText("CHOOSE ONE")
                        WGRGearFinderTrackChild(content, action)
                    else
                        WGRGearFinderCreateRecommendationActionButton(
                            content,
                            startX
                                + math.max(
                                    0,
                                    math.floor(
                                        ((columnWidth - 8) - iconSpacing)
                                        / 2
                                    )
                                )
                                + math.floor((42 - 34) / 2),
                            lineY - labelHeight,
                            34,
                            "Equip",
                            group.records[1],
                            nil
                        )
                    end

                    local rowCount =
                        math.max(
                            1,
                            math.ceil(
                                #group.records
                                / iconsPerLine
                            )
                        )

                    local effectiveRowHeight = iconRowHeight + (multipleChoices and 20 or 0)

                    for itemIndex, record
                        in ipairs(group.records)
                    do
                        local zeroIndex = itemIndex - 1
                        local itemColumn = zeroIndex % iconsPerLine
                        local itemRow = math.floor(zeroIndex / iconsPerLine)
                        local rowStartIndex = itemRow * iconsPerLine + 1
                        local rowItems = math.min(iconsPerLine, #group.records - rowStartIndex + 1)
                        local rowWidth = rowItems * iconSpacing
                        local centeredStartX = startX + math.max(0, math.floor(((columnWidth - 8) - rowWidth) / 2))
                        local itemX = centeredStartX + (itemColumn * iconSpacing)
                        local itemY = lineY - labelHeight - actionHeight - selectHeight - (itemRow * effectiveRowHeight)

                        if multipleChoices then
                            WGRGearFinderCreateRecommendationActionButton(
                                content,
                                itemX + math.floor((42 - 34) / 2),
                                itemY + 19,
                                34,
                                "Equip",
                                record,
                                nil
                            )
                        end

                        WGRGearFinderCreateItemButton(
                            content,
                            record,
                            itemX,
                            itemY,
                            tostring(
                                WGRGearFinderLocationCode(record.source)
                                or "?"
                            )
                                .. "\n+"
                                .. tostring(math.floor(record.upgrade or 0))
                        )
                    end

                    local groupHeight =
                        labelHeight
                        + actionHeight
                        + selectHeight
                        + (rowCount * effectiveRowHeight)
                        + groupGap

                    lineY =
                        lineY
                        - groupHeight
                    usedHeight =
                        usedHeight
                        + groupHeight
                end

                maxHeight =
                    math.max(
                        maxHeight,
                        usedHeight
                    )
            end

            if #activeSpecs > 1 then
                for dividerIndex = 1, (#activeSpecs - 1) do
                    local divider =
                        content:CreateTexture(
                            nil,
                            "ARTWORK"
                        )

                    if key == "best" then
                        divider:SetColorTexture(1.00, 0.82, 0.00, 0.85)
                    else
                        divider:SetColorTexture(1.00, 0.50, 0.00, 0.85)
                    end
                    divider:SetWidth(2)
                    divider:SetPoint(
                        "TOPLEFT",
                        content,
                        "TOPLEFT",
                        specLeft
                            + (dividerIndex * columnWidth)
                            - 2,
                        specContentTop
                    )
                    divider:SetHeight(
                        math.max(
                            42,
                            maxHeight + 8
                        )
                    )

                    WGRGearFinderTrackChild(
                        content,
                        divider
                    )
                end
            end

            y =
                y
                - maxHeight
                - 12
        end

        RenderSpecRow(
            "BEST UPGRADES",
            "best",
            WGRGearFinderColors.BEST
        )


        local function WeaponLabelForRecord(record)
            local code = WGRGearFinderLocationCode(record.source)
            -- Instructions above the icon (KEEP/EQUIP/CHOOSE ONE) describe
            -- the item's role. The compact line below the icon is location
            -- only. A retained baseline can be known even when its physical
            -- location cannot currently be verified because that bank is
            -- closed, in which case show ?.
            if record.ownedBaseline then
                return code or "?"
            end
            return code or "?"
        end

        local function WeaponActionForOptions(options)
            local count = #(options or {})
            if count > 1 then return "CHOOSE ONE" end
            if count == 1 and options[1].ownedBaseline then return "KEEP" end
            if count == 1 then return "EQUIP" end
            return ""
        end

        local function AddWeaponActionLabel(left, topY, width, text)
            if not text or text == "" then return end
            local action = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            action:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                left,
                topY - 2
            )
            action:SetWidth(width)
            action:SetJustifyH("CENTER")
            action:SetTextColor(0.88, 0.88, 0.88)
            action:SetText(text)
            WGRGearFinderTrackChild(content, action)
        end

        local function AddWeaponSingleAction(left, topY, width, options, targetSlot)
            local text = WeaponActionForOptions(options)
            if text == "KEEP" then
                local keepWidth = 32

                AddWeaponActionLabel(
                    left
                        + math.floor((width - 36) / 2)
                        + math.floor((42 - keepWidth) / 2),
                    topY,
                    keepWidth,
                    "KEEP"
                )

                return 18
            elseif text == "EQUIP" then
                WGRGearFinderCreateRecommendationActionButton(
                    content,
                    left
                        + math.floor((width - 36) / 2)
                        + math.floor((42 - 32) / 2),
                    topY,
                    32,
                    "Equip",
                    options[1],
                    targetSlot
                )
                return 20
            elseif text == "CHOOSE ONE" then
                AddWeaponActionLabel(left, topY, width, "CHOOSE ONE")
                return 14
            end
            return 0
        end

        local anyWeapons = false
        for _, spec in ipairs(activeSpecs) do
            local display = classified.bySpec[spec.id].weaponDisplay
            if display and display.hasCompleteUpgrade and #(display.configs or {}) > 0 then
                anyWeapons = true
                break
            end
        end

        if anyWeapons then
            WGRGearFinderAddHeading(
                content,
                "WEAPONS",
                y,
                WGRGearFinderColors.BEST
            )
            y = y - 22

            for index, spec in ipairs(activeSpecs) do
                local heading = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                heading:SetPoint(
                    "TOPLEFT",
                    content,
                    "TOPLEFT",
                    specLeft + ((index - 1) * columnWidth),
                    y
                )
                heading:SetWidth(columnWidth - 4)
                heading:SetJustifyH("CENTER")
                heading:SetText(spec.name .. (spec.current and " (Current)" or ""))
                WGRGearFinderTrackChild(content, heading)
            end
            y = y - 20

            local sectionTop = y + 16
            local maxUsed = 48

            local function RenderSetupUpgrade(left, lineY, width, amount, state)
                local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                text:SetPoint("TOPLEFT", content, "TOPLEFT", left, lineY)
                text:SetWidth(width)
                text:SetJustifyH("CENTER")
                local c = state == "COMPARE"
                    and WGRGearFinderColors.COMPARE
                    or WGRGearFinderColors.BEST
                text:SetTextColor(c[1], c[2], c[3])
                text:SetText("+" .. tostring(math.floor((tonumber(amount) or 0) + 0.0001)))
                WGRGearFinderTrackChild(content, text)
            end

            for specIndex, spec in ipairs(activeSpecs) do
                local display = classified.bySpec[spec.id].weaponDisplay
                local left = specLeft + ((specIndex - 1) * columnWidth)
                local lineY = y
                local used = 0

                if display and display.hasCompleteUpgrade then
                    local renderedConfigs = 0
                    for _, cfg in ipairs(display.configs or {}) do
                        local hasContent = #cfg.mainOptions > 0 or #cfg.offOptions > 0
                        if hasContent then
                            renderedConfigs = renderedConfigs + 1
                            if renderedConfigs > 1 then
                                local orText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                                orText:SetPoint("TOPLEFT", content, "TOPLEFT", left, lineY)
                                orText:SetWidth(columnWidth - 4)
                                orText:SetJustifyH("CENTER")
                                orText:SetTextColor(0.62, 0.62, 0.62)
                                orText:SetText("OR")
                                WGRGearFinderTrackChild(content, orText)
                                lineY = lineY - 17
                                used = used + 17
                            end

                            local configTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                            configTitle:SetPoint("TOPLEFT", content, "TOPLEFT", left + 2, lineY)
                            configTitle:SetWidth(columnWidth - 8)
                            configTitle:SetJustifyH("CENTER")
                            local tc = display.winningState == "COMPARE"
                                and WGRGearFinderColors.COMPARE
                                or WGRGearFinderColors.BEST
                            configTitle:SetTextColor(tc[1], tc[2], tc[3])
                            configTitle:SetText(WGRWeaponConfigLabels[cfg.config] or cfg.config)
                            WGRGearFinderTrackChild(content, configTitle)
                            lineY = lineY - 18
                            used = used + 18

                            local paired = cfg.config ~= "RANGED" and cfg.config ~= "TWO_HAND"

                            if not paired then
                                local count = #cfg.mainOptions
                                local multipleChoices = count > 1
                                local actionHeight = AddWeaponSingleAction(
                                    left + 2,
                                    lineY,
                                    columnWidth - 8,
                                    cfg.mainOptions,
                                    16
                                )
                                local selectHeight = multipleChoices and 20 or 0
                                local itemsTopY = lineY - actionHeight - selectHeight
                                local optionStep = 36
                                local maxPerRow = math.max(1, math.min(4, math.floor((columnWidth - 12) / optionStep)))
                                local rows = math.max(1, math.ceil(count / maxPerRow))
                                local rowStep = 55 + (multipleChoices and 20 or 0)

                                for i, record in ipairs(cfg.mainOptions) do
                                    local row = math.floor((i - 1) / maxPerRow)
                                    local col = (i - 1) % maxPerRow
                                    local rowCount = math.min(maxPerRow, count - (row * maxPerRow))
                                    local rowWidth = rowCount * optionStep
                                    local startX = left + math.floor((columnWidth - rowWidth) / 2)
                                    local itemX = startX + (col * optionStep)
                                    local itemY = itemsTopY - (row * rowStep)
                                    record.compactWeapon = true
                                    record.targetEquipSlot = 16

                                    if multipleChoices then
                                        WGRGearFinderCreateRecommendationActionButton(
                                            content,
                                            itemX + math.floor((42 - 32) / 2),
                                            itemY + 19,
                                            32,
                                            "Equip",
                                            record,
                                            16
                                        )
                                    end

                                    WGRGearFinderCreateItemButton(
                                        content,
                                        record,
                                        itemX,
                                        itemY,
                                        WeaponLabelForRecord(record)
                                    )
                                end

                                local blockHeight = actionHeight + selectHeight + (rows * rowStep)
                                lineY = lineY - blockHeight
                                used = used + blockHeight
                            else
                                -- Paired setups remain two independent choice groups.
                                -- Left actions always target Main Hand; right actions target Off Hand.
                                local perSide = 2
                                local mainRows = math.max(1, math.ceil(#cfg.mainOptions / perSide))
                                local offRows = math.max(1, math.ceil(#cfg.offOptions / perSide))
                                local rows = math.max(mainRows, offRows)
                                local optionStep = 36
                                local sideWidth = math.min(88, math.max(optionStep, math.floor((columnWidth - 28) / 2)))
                                local plusWidth = 20
                                local totalWidth = (sideWidth * 2) + plusWidth
                                local groupLeft = left + math.max(2, math.floor((columnWidth - totalWidth) / 2))
                                local mainLeft = groupLeft
                                local plusLeft = groupLeft + sideWidth
                                local offLeft = plusLeft + plusWidth

                                local mainMultiple = #cfg.mainOptions > 1
                                local offMultiple = #cfg.offOptions > 1
                                local mainActionHeight = AddWeaponSingleAction(mainLeft, lineY, sideWidth, cfg.mainOptions, 16)
                                local offActionHeight = AddWeaponSingleAction(offLeft, lineY, sideWidth, cfg.offOptions, 17)
                                local actionHeight = math.max(mainActionHeight, offActionHeight)
                                local selectHeight = (mainMultiple or offMultiple) and 20 or 0
                                local itemsTopY = lineY - actionHeight - selectHeight
                                local rowStep = 55 + ((mainMultiple or offMultiple) and 20 or 0)

                                local function RenderSide(options, sideLeft, targetSlot, multipleChoices)
                                    for i, record in ipairs(options) do
                                        local row = math.floor((i - 1) / perSide)
                                        local col = (i - 1) % perSide
                                        local rowCount = math.min(perSide, #options - (row * perSide))
                                        local rowWidth = rowCount * optionStep
                                        local startX = sideLeft + math.floor((sideWidth - rowWidth) / 2)
                                        local itemX = startX + (col * optionStep)
                                        local itemY = itemsTopY - (row * rowStep)
                                        record.compactWeapon = true
                                        record.targetEquipSlot = targetSlot

                                        if multipleChoices then
                                            WGRGearFinderCreateRecommendationActionButton(
                                                content,
                                                itemX + math.floor((42 - 32) / 2),
                                                itemY + 19,
                                                32,
                                                "Equip",
                                                record,
                                                targetSlot
                                            )
                                        end

                                        WGRGearFinderCreateItemButton(
                                            content,
                                            record,
                                            itemX,
                                            itemY,
                                            WeaponLabelForRecord(record)
                                        )
                                    end
                                end

                                RenderSide(cfg.mainOptions, mainLeft, 16, mainMultiple)
                                RenderSide(cfg.offOptions, offLeft, 17, offMultiple)

                                local plus = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                                plus:SetPoint(
                                    "TOPLEFT",
                                    content,
                                    "TOPLEFT",
                                    plusLeft,
                                    itemsTopY - math.floor(((rows * rowStep) - 18) / 2)
                                )
                                plus:SetWidth(plusWidth)
                                plus:SetJustifyH("CENTER")
                                plus:SetTextColor(0.72, 0.72, 0.72)
                                plus:SetText("+")
                                WGRGearFinderTrackChild(content, plus)

                                local blockHeight = actionHeight + selectHeight + (rows * rowStep)
                                lineY = lineY - blockHeight
                                used = used + blockHeight
                            end

                            RenderSetupUpgrade(
                                left + 2,
                                lineY,
                                columnWidth - 8,
                                cfg.upgrade,
                                display.winningState
                            )
                            lineY = lineY - 19
                            used = used + 19
                        end
                    end
                end

                maxUsed = math.max(maxUsed, used)
            end

            if #activeSpecs > 1 then
                for dividerIndex = 1, (#activeSpecs - 1) do
                    local divider = content:CreateTexture(nil, "ARTWORK")
                    divider:SetColorTexture(0.76, 0.66, 0.22, 0.65)
                    divider:SetWidth(2)
                    divider:SetPoint(
                        "TOPLEFT",
                        content,
                        "TOPLEFT",
                        specLeft + (dividerIndex * columnWidth) - 2,
                        sectionTop
                    )
                    divider:SetHeight(math.max(42, maxUsed + 8))
                    WGRGearFinderTrackChild(content, divider)
                end
            end

            y = y - maxUsed - 14
        end
    end

    local function WGRGearFinderAddMajorDivider(labelText, yPos, red, green, blue)
        local centerX = contentWidth / 2
        local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText(labelText)
        label:SetTextColor(red, green, blue)
        label:SetPoint("TOP", content, "TOPLEFT", centerX, yPos)
        WGRGearFinderTrackChild(content, label)

        local gap = math.max(110, (label:GetStringWidth() / 2) + 18)

        local leftLine = content:CreateTexture(nil, "ARTWORK")
        leftLine:SetColorTexture(red, green, blue, 0.78)
        leftLine:SetHeight(2)
        leftLine:SetPoint("LEFT", content, "TOPLEFT", 8, yPos - 7)
        leftLine:SetPoint("RIGHT", content, "TOPLEFT", centerX - gap, yPos - 7)
        WGRGearFinderTrackChild(content, leftLine)

        local rightLine = content:CreateTexture(nil, "ARTWORK")
        rightLine:SetColorTexture(red, green, blue, 0.78)
        rightLine:SetHeight(2)
        rightLine:SetPoint("LEFT", content, "TOPLEFT", centerX + gap, yPos - 7)
        rightLine:SetPoint("RIGHT", content, "TOPLEFT", contentWidth - 8, yPos - 7)
        WGRGearFinderTrackChild(content, rightLine)

        return yPos - 28
    end

    local function AddSectionMovementButtons(
        records,
        yPos,
        moveAllowed,
        depositAllowed,
        description
    )
        local x = 156

        if moveAllowed then
            WGRGearFinderCreateMoveButton(
                content,
                records,
                x,
                yPos + 4,
                "Move All to Bags",
                description,
                true
            )

            x = x + 228
        end

        if depositAllowed then
            WGRGearFinderCreateDepositButton(
                content,
                records,
                x,
                yPos + 4,
                "Move to Warbank",
                description,
                true
            )
        end
    end

    local function RenderFullWidthSection(
        title,
        records,
        color,
        movementOptions
    )
        WGRGearFinderAddHeading(
            content,
            title
                .. " ("
                .. tostring(#records)
                .. ")",
            y,
            color
        )

        if movementOptions then
            AddSectionMovementButtons(
                records,
                y,
                movementOptions.moveToBags == true,
                movementOptions.depositToWarband == true,
                title .. " item(s)"
            )
        end

        y = y - (
            movementOptions
            and 28
            or 22
        )

        if #records == 0 then
            local empty =
                content:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlightSmall"
                )

            empty:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                10,
                y
            )

            empty:SetTextColor(
                0.60,
                0.60,
                0.60
            )

            empty:SetText(
                "None"
            )

            WGRGearFinderTrackChild(
                content,
                empty
            )

            y = y - 70
            return
        end

        local groups =
            WGRGearFinderBuildGroups(
                records
            )

        local startX = 8
        local x = startX
        local lineY = y
        local lineHeight = 72
        local usedLines = 1
        local maxX = contentWidth - 8

        for _, group
            in ipairs(groups)
        do
            local groupWidth =
                math.max(
                    44,
                    #group.records * 38
                )

            if x > startX
                and (
                    x
                    + groupWidth
                    > maxX
                )
            then
                x = startX
                lineY =
                    lineY
                    - lineHeight
                usedLines =
                    usedLines + 1
            end

            local label =
                content:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlightSmall"
                )

            label:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                x,
                lineY
            )

            label:SetTextColor(
                0.65,
                0.65,
                0.65
            )

            label:SetText(
                group.label
            )

            WGRGearFinderTrackChild(
                content,
                label
            )

            for itemIndex, record
                in ipairs(group.records)
            do
                WGRGearFinderCreateItemButton(
                    content,
                    record,
                    x
                        + (
                            (itemIndex - 1)
                            * 38
                        ),
                    lineY - 14,
                    record.upgrade
                        and (
                            "+"
                            .. tostring(
                                math.floor(
                                    record.upgrade
                                )
                            )
                        )
                        or ""
                )
            end

            x =
                x
                + groupWidth
                + 18
        end

        y =
            y
            - (
                usedLines
                * lineHeight
            )
            - 12
    end

    local function RenderSendOnwardsSection(
        records
    )
        if #records == 0 then
            WGRGearFinderAddHeading(
                content,
                "None",
                y,
                WGRGearFinderColors.ONWARD
            )
            y = y - 42
            return
        end

        WGRGearFinderAddHeading(
            content,
            "SEND ONWARDS ("
                .. tostring(#records)
                .. ")",
            y,
            WGRGearFinderColors.ONWARD
        )

        WGRGearFinderCreateMoveButton(
            content,
            records,
            156,
            y + 4,
            "Move All to Bags",
            "SEND ONWARDS item(s)",
            true
        )

        WGRGearFinderCreateDepositButton(
            content,
            records,
            396,
            y + 4,
            "Move to Warbank",
            "SEND ONWARDS item(s)",
            true
        )

        y = y - 40

        local byRecipient = {}
        local recipientNames = {}

        for _, record
            in ipairs(records)
        do
            local recipient =
                record.recommendation
                and record.recommendation.name
                or "Unknown"

            if not byRecipient[
                recipient
            ] then
                byRecipient[
                    recipient
                ] = {}

                recipientNames[
                    #recipientNames + 1
                ] =
                    recipient
            end

            table.insert(
                byRecipient[
                    recipient
                ],
                record
            )
        end

        -- SEND ONWARDS is an action list, so recipient is the primary
        -- grouping. Preserve WGR's routing priority rather than alphabetizing.
        local function NormalizeRecipientName(
            name
        )
            if not name then
                return ""
            end

            return string.lower(
                tostring(name)
            )
        end

        local priority = {}
        local activePriority =
            GetActiveRoutingPriority()
            or {}

        for index, name
            in ipairs(activePriority)
        do
            priority[
                NormalizeRecipientName(
                    name
                )
            ] =
                index
        end

        table.sort(
            recipientNames,
            function(
                a,
                b
            )
                local ai =
                    priority[
                        NormalizeRecipientName(
                            a
                        )
                    ]
                    or 9999

                local bi =
                    priority[
                        NormalizeRecipientName(
                            b
                        )
                    ]
                    or 9999

                if ai ~= bi then
                    return ai < bi
                end

                return tostring(a)
                    < tostring(b)
            end
        )

        local startX = 8
        local maxX = contentWidth - 8
        local lineHeight = 72

        for _, recipient
            in ipairs(recipientNames)
        do
            local recipientLabel =
                content:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontNormalSmall"
                )

            recipientLabel:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                8,
                y
            )

            recipientLabel:SetWidth(
                150
            )

            recipientLabel:SetJustifyH(
                "LEFT"
            )

            recipientLabel:SetText(
                recipient
            )

            WGRGearFinderTrackChild(
                content,
                recipientLabel
            )

            WGRGearFinderCreateMoveButton(
                content,
                byRecipient[
                    recipient
                ],
                156,
                y + 4,
                "Move to Bags",
                "item(s) for "
                    .. tostring(recipient),
                false
            )

            WGRGearFinderCreateDepositButton(
                content,
                byRecipient[
                    recipient
                ],
                396,
                y + 4,
                "Move to Warbank",
                "item(s) for "
                    .. tostring(recipient),
                false
            )

            local groups =
                WGRGearFinderBuildGroups(
                    byRecipient[
                        recipient
                    ]
                )

            local x = startX
            local lineY = y - 30
            local usedLines = 1

            for _, group
                in ipairs(groups)
            do
                local groupWidth =
                    math.max(
                        44,
                        #group.records * 38
                    )

                if x > startX
                    and (
                        x
                        + groupWidth
                        > maxX
                    )
                then
                    x = startX
                    lineY =
                        lineY
                        - lineHeight
                    usedLines =
                        usedLines + 1
                end

                local slotLabel =
                    content:CreateFontString(
                        nil,
                        "OVERLAY",
                        "GameFontHighlightSmall"
                    )

                slotLabel:SetPoint(
                    "TOPLEFT",
                    content,
                    "TOPLEFT",
                    x,
                    lineY
                )

                slotLabel:SetTextColor(
                    0.65,
                    0.65,
                    0.65
                )

                slotLabel:SetText(
                    group.label
                )

                WGRGearFinderTrackChild(
                    content,
                    slotLabel
                )

                for itemIndex, record
                    in ipairs(group.records)
                do
                    WGRGearFinderCreateItemButton(
                        content,
                        record,
                        x
                            + (
                                (itemIndex - 1)
                                * 38
                            ),
                        lineY - 14,
                        record.upgrade
                            and (
                                "+"
                                .. tostring(
                                    math.floor(
                                        record.upgrade
                                    )
                                )
                            )
                            or ""
                    )
                end

                x =
                    x
                    + groupWidth
                    + 18
            end

            y =
                y
                - 30
                - (
                    usedLines
                    * lineHeight
                )
                - 18
        end

        y = y - 4
    end

    local function RenderDisposeSection(
        records
    )
        if not records
            or #records == 0
        then
            return
        end

        WGRGearFinderAddHeading(
            content,
            "SELL / DISPOSE ("
                .. tostring(#records)
                .. ")",
            y,
            WGRGearFinderColors.DISPOSE
        )

        WGRGearFinderCreateMoveButton(
            content,
            records,
            156,
            y + 4,
            "Move All to Bags",
            "SELL / DISPOSE item(s)",
            true
        )

        WGRGearFinderCreateDepositButton(
            content,
            records,
            396,
            y + 4,
            "Move to Warbank",
            "SELL / DISPOSE item(s)",
            true
        )

        y = y - 28

        local groups =
            WGRGearFinderBuildGroups(
                records
            )

        local startX = 8
        local x = startX
        local lineY = y
        local lineHeight = 72
        local usedLines = 1
        local maxX = contentWidth - 8

        for _, group
            in ipairs(groups)
        do
            local groupWidth =
                math.max(
                    44,
                    #group.records * 38
                )

            if x > startX
                and x + groupWidth > maxX
            then
                x = startX
                lineY = lineY - lineHeight
                usedLines = usedLines + 1
            end

            local label =
                content:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlightSmall"
                )

            label:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                x,
                lineY
            )

            label:SetTextColor(
                0.65,
                0.65,
                0.65
            )

            label:SetText(
                group.label
            )

            WGRGearFinderTrackChild(
                content,
                label
            )

            for itemIndex, record
                in ipairs(group.records)
            do
                WGRGearFinderCreateItemButton(
                    content,
                    record,
                    x + ((itemIndex - 1) * 38),
                    lineY - 14,
                    record.upgrade
                        and (
                            "+"
                            .. tostring(
                                math.floor(
                                    record.upgrade
                                )
                            )
                        )
                        or ""
                )
            end

            x = x + groupWidth + 18
        end

        y =
            y
            - (usedLines * lineHeight)
            - 12
    end

    if #classified.other > 0 then
        WGRGearFinderAddHeading(
            content,
            "OTHER USEFUL GEAR",
            y,
            WGRGearFinderColors.OTHER
        )

        WGRGearFinderCreateMoveButton(
            content,
            classified.other,
            156,
            y + 4,
            "Move All to Bags",
            "OTHER USEFUL GEAR item(s)",
            true
        )

        WGRGearFinderCreateDepositButton(
            content,
            classified.other,
            384,
            y + 4,
            "Move to Warbank",
            "OTHER USEFUL GEAR item(s)",
            true
        )

        WGRGearFinderCreatePersonalBankButton(
            content,
            classified.other,
            612,
            y + 4
        )

        y = y - 28

        local otherGroups =
            WGRGearFinderBuildGroups(
                classified.other
            )

        local otherStartX = 8
        local otherX = otherStartX
        local otherLineY = y
        local otherLineHeight = 72
        local otherUsedLines = 1
        local otherMaxX = contentWidth - 8

        for _, group
            in ipairs(otherGroups)
        do
        local groupWidth =
            math.max(
                44,
                #group.records * 38
            )

        if otherX > otherStartX
            and otherX + groupWidth > otherMaxX
        then
            otherX = otherStartX
            otherLineY =
                otherLineY
                - otherLineHeight
            otherUsedLines =
                otherUsedLines + 1
        end

        local label =
            content:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

        label:SetPoint(
            "TOPLEFT",
            content,
            "TOPLEFT",
            otherX,
            otherLineY
        )

        label:SetTextColor(
            0.65,
            0.65,
            0.65
        )

        label:SetText(
            group.label
        )

        WGRGearFinderTrackChild(
            content,
            label
        )

        for itemIndex, record
            in ipairs(group.records)
        do
            WGRGearFinderCreateItemButton(
                content,
                record,
                otherX + ((itemIndex - 1) * 38),
                otherLineY - 14,
                record.upgrade
                    and (
                        "+"
                        .. tostring(
                            math.floor(
                                record.upgrade
                            )
                        )
                    )
                    or ""
            )
        end

            otherX =
                otherX
                + groupWidth
                + 18
        end

        y =
            y
            - (otherUsedLines * otherLineHeight)
            - 12
    end

    if classified.held
        and #classified.held > 0
    then
        WGRGearFinderAddHeading(
            content,
            "HOLD / STORAGE ("
                .. tostring(#classified.held)
                .. ")",
            y,
            WGRGearFinderColors.HELD
        )

        WGRGearFinderCreateMoveButton(
            content,
            classified.held,
            156,
            y + 4,
            "Move All to Bags",
            "HOLD / STORAGE item(s)",
            true
        )

        WGRGearFinderCreateDepositButton(
            content,
            classified.held,
            384,
            y + 4,
            "Move to Warbank",
            "HOLD / STORAGE item(s)",
            true
        )

        WGRGearFinderCreatePersonalBankButton(
            content,
            classified.held,
            612,
            y + 4
        )

        y = y - 28

        local heldGroups =
            WGRGearFinderBuildGroups(
                classified.held
            )

        local heldStartX = 8
        local heldX = heldStartX
        local heldLineY = y
        local heldLineHeight = 72
        local heldUsedLines = 1
        local heldMaxX = contentWidth - 8

        for _, group
            in ipairs(heldGroups)
        do
            local groupWidth =
                math.max(
                    44,
                    #group.records * 38
                )

            if heldX > heldStartX
                and heldX + groupWidth > heldMaxX
            then
                heldX = heldStartX
                heldLineY =
                    heldLineY
                    - heldLineHeight
                heldUsedLines =
                    heldUsedLines + 1
            end

            local label =
                content:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlightSmall"
                )

            label:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                heldX,
                heldLineY
            )

            label:SetTextColor(
                0.65,
                0.65,
                0.65
            )

            label:SetText(
                group.label
            )

            WGRGearFinderTrackChild(
                content,
                label
            )

            for itemIndex, record
                in ipairs(group.records)
            do
                WGRGearFinderCreateItemButton(
                    content,
                    record,
                    heldX + ((itemIndex - 1) * 38),
                    heldLineY - 14,
                    ""
                )
            end

            heldX =
                heldX
                + groupWidth
                + 18
        end

        y =
            y
            - (heldUsedLines * heldLineHeight)
            - 12
    end

    y = WGRGearFinderAddMajorDivider(
        "OUTGOING GEAR",
        y,
        1.00,
        0.22,
        0.22
    )

    RenderSendOnwardsSection(
        classified.onward
    )

    RenderDisposeSection(
        classified.dispose
    )

    content:SetHeight(
        math.max(
            1,
            -y + 20
        )
    )

    frame.gearFinderLastResults =
        classified

    if WGRUpdateGearTodoSnapshot then
        local uniqueOnward =
            WGRGearFinderUniquePhysicalRecords(
                classified.onward
            )

        local carriedSendCount = 0
        local warbankSendCount = 0

        for _, record
            in ipairs(uniqueOnward)
        do
            if record.source == "BAGS" then
                carriedSendCount =
                    carriedSendCount + 1
            elseif record.source
                == "WARBAND_BANK"
            then
                warbankSendCount =
                    warbankSendCount + 1
            end
        end

        -- HOLD/STORAGE items assigned to the current character are only
        -- truly "here" once they are in that character's Bags or Personal
        -- Bank. If they are still in the shared Warband Bank, keep a To Do
        -- retrieval/distribution reminder active for them.
        for _, record
            in ipairs(
                WGRGearFinderUniquePhysicalRecords(
                    classified.held or {}
                )
            )
        do
            if record.source == "WARBAND_BANK" then
                warbankSendCount =
                    warbankSendCount + 1
            end
        end

        WGRUpdateGearTodoSnapshot(
            WGRGearFinderCurrentName(),
            carriedSendCount,
            warbankSendCount,
            WGRGearFinderWarbandBankOpen
                == true
        )
    end
end

function WGRGearFinderDepositCurrentOutgoingToWarband()
    if not WGRGearFinderIsWarbandBankAvailable() then
        print(
            "|cffff5555WBGR:|r Open the Warband Bank before depositing routed items."
        )
        return
    end

    local frame =
        WGRGearFinderFrame

    if not frame
        or not frame.gearFinderPage
    then
        print(
            "|cffff5555WBGR:|r Gear Finder is not ready yet."
        )
        return
    end

    -- Force a fresh classification so the To Do action never deposits from
    -- stale routing results. The scan may complete asynchronously while item
    -- data loads, so wait for gearFinderLastResults to be repopulated.
    frame.gearFinderLastResults = nil
    WGRRefreshGearFinder(
        frame
    )

    local attempts = 0

    local function TryDeposit()
        attempts =
            attempts + 1

        local classified =
            frame.gearFinderLastResults

        if classified
            and classified.onward
        then
            local carried = {}

            for _, record
                in ipairs(
                    WGRGearFinderUniquePhysicalRecords(
                        classified.onward
                    )
                )
            do
                if record.source == "BAGS" then
                    carried[#carried + 1] =
                        record
                end
            end

            if #carried == 0 then
                print(
                    "|cff33ff99WBGR:|r No routed bag items currently need to be deposited."
                )
                if WGRRefreshTodoPage then
                    WGRRefreshTodoPage()
                end
                return
            end

            WGRGearFinderDepositRecordsToWarband(
                carried,
                "routed item(s)"
            )
            return
        end

        if attempts < 30 then
            C_Timer.After(
                0.10,
                TryDeposit
            )
        else
            print(
                "|cffff5555WBGR:|r Gear scan did not finish in time. Try Deposit to WBK again."
            )
        end
    end

    C_Timer.After(
        0.05,
        TryDeposit
    )
end

function WGRScheduleGearFinderRefresh(
    delay
)
    if WGRRoutingIsPaused
        and WGRRoutingIsPaused()
    then
        return
    end

    local frame =
        WGRGearFinderFrame

    if not frame
        or not frame.gearFinderPage
        or not frame.gearFinderPage:IsShown()
    then
        return
    end

    -- Trailing-edge debounce: every inventory event advances the token.
    -- Earlier scheduled callbacks become stale, so the refresh happens
    -- only after the final event in the burst has had time to settle.
    WGRGearFinderRefreshToken =
        WGRGearFinderRefreshToken + 1

    local token =
        WGRGearFinderRefreshToken

    C_Timer.After(
        delay or 0.20,
        function()
            if token
                ~= WGRGearFinderRefreshToken
            then
                return
            end

            local currentFrame =
                WGRGearFinderFrame

            if currentFrame
                and currentFrame.gearFinderPage
                and currentFrame.gearFinderPage:IsShown()
            then
                WGRRefreshGearFinder(
                    currentFrame
                )
            end
        end
    )
end

local WGRGearFinderPreloadSlots = {
    1,  -- Head
    2,  -- Neck
    3,  -- Shoulder
    5,  -- Chest
    6,  -- Waist
    7,  -- Legs
    8,  -- Feet
    9,  -- Wrist
    10, -- Hands
    11, -- Ring 1
    12, -- Ring 2
    13, -- Trinket 1
    14, -- Trinket 2
    15, -- Back
    16, -- Main hand
    17, -- Off hand
}

local function WGRGearFinderPreloadEquippedData(
    callback
)
    PreloadItems(
        GetActiveRoutingPriority(),
        WGRGearFinderPreloadSlots,
        callback,
        true
    )
end

function WGRRefreshGearFinder(
    frame
)
    frame =
        frame
        or WGRGearFinderFrame

    if not frame
        or not frame.gearFinderPage
    then
        return
    end

    if WGRRoutingIsPaused
        and WGRRoutingIsPaused()
    then
        if WGRGearFinderSetMasterPaused then
            WGRGearFinderSetMasterPaused(
                true
            )
        end
        return
    end

    frame.gearFinderSummary:SetText(
        "Scanning gear..."
    )

    if WGRRefreshIgnoredItemLocations then
        WGRRefreshIgnoredItemLocations()
    end

    WGRGearFinderGeneration =
        WGRGearFinderGeneration
        + 1

    local generation =
        WGRGearFinderGeneration

    local characterName =
        WGRGearFinderCurrentName()

    local character =
        FindCharacterByName(
            characterName
        )

    if not characterName
        or not character
    then
        frame.gearFinderSummary:SetText(
            "Unable to read the current character from DataStore."
        )
        return
    end

    local specs =
        WGRGearFinderGetSelectedSpecs(
            characterName,
            character
        )

    local bagItems =
        WGRGearFinderScanBags()

    local items = {}

    for _, item
        in ipairs(bagItems)
    do
        items[#items + 1] =
            item
    end

    local bagCount =
        #bagItems

    local personalBankCount =
        0

    local warbandBankCount =
        0

    WGRGearFinderBagSignature =
        WGRGearFinderBuildBagSignature()

    WGRGearFinderPersonalBankOpen =
        WGRGearFinderIsPersonalBankAvailable()

    if frame.UpdateGearFinderSourceStatus then
        frame.UpdateGearFinderSourceStatus()
    end

    if WGRGearFinderPersonalBankOpen then
        local bankItems =
            WGRGearFinderScanPersonalBank()

        personalBankCount =
            #bankItems

        for _, item
            in ipairs(bankItems)
        do
            items[#items + 1] =
                item
        end

        WGRGearFinderPersonalBankSignature =
            WGRGearFinderBuildPersonalBankSignature()
    end

    WGRGearFinderWarbandBankOpen =
        WGRGearFinderIsWarbandBankAvailable()

    if frame.UpdateGearFinderSourceStatus then
        frame.UpdateGearFinderSourceStatus()
    end

    if WGRGearFinderWarbandBankOpen then
        local warbandItems =
            WGRGearFinderScanWarbandBank()

        warbandBankCount =
            #warbandItems

        for _, item
            in ipairs(warbandItems)
        do
            items[#items + 1] =
                item
        end

        WGRGearFinderWarbandBankSignature =
            WGRGearFinderBuildWarbandBankSignature()
    end

    frame.gearFinderSummary:SetText(
        "Scanning gear..."
    )


    if #items == 0 then
        WGRGearFinderRender(
            frame,
            {},
            specs
        )
        frame.gearFinderSummary:SetText(
            "Scan Complete: 0 eligible gear items"
        )
        return
    end

    local records = {}

    -- Group physical copies by exact item link. Routing depends on the item
    -- and current WGR state, not on which bank slot holds an identical copy.
    -- Evaluate each unique link once, then fan the result back out to every
    -- physical copy so Gear Finder still displays all actual items.
    local itemsByLink = {}
    local uniqueLinks = {}

    for _, item
        in ipairs(items)
    do
        local link =
            item.itemLink

        if not itemsByLink[link] then
            itemsByLink[link] = {}
            uniqueLinks[#uniqueLinks + 1] =
                link
        end

        itemsByLink[link][
            #itemsByLink[link] + 1
        ] =
            item
    end

    local totalUnique =
        #uniqueLinks

    frame.gearFinderSummary:SetText(
        "Scanning gear..."
    )


    if totalUnique == 0 then
        WGRGearFinderRender(
            frame,
            {},
            specs
        )
        frame.gearFinderSummary:SetText(
            "Scan Complete: 0 eligible gear items"
        )
        return
    end

    local function BeginRouting()
        if generation
            ~= WGRGearFinderGeneration
        then
            return
        end

        local index = 1
        local completed = 0
        local notLoaded = 0
        local slowestMS = 0
        local slowestItem = nil

        local function FinishAll()
            if generation
                ~= WGRGearFinderGeneration
            then
                return
            end

            WGRGearFinderRender(
                frame,
                records,
                specs
            )

            frame.gearFinderSummary:SetText(
                string.format(
                    "Scan Complete: %d eligible gear item%s",
                    #records,
                    #records == 1
                        and ""
                        or "s"
                )
            )
        end

        local function EvaluateCurrentItem()
            if generation
                ~= WGRGearFinderGeneration
            then
                return
            end

            if index > totalUnique then
                FinishAll()
                return
            end

            local itemLink =
                uniqueLinks[
                    index
                ]

            local itemName =
                C_Item.GetItemNameByID
                and C_Item.GetItemNameByID(
                    itemLink
                )
                or nil

            if not itemName then
                local name =
                    C_Item.GetItemInfo(
                        itemLink
                    )

                itemName =
                    name
                    or tostring(itemLink)
            end

            local group =
                WGRGearFinderGetSlotGroup(
                    itemLink
                )

            local displayIndex =
                index

            frame.gearFinderSummary:SetText(
                "Scanning gear..."
            )

            C_Timer.After(
                0,
                function()
                    if generation
                        ~= WGRGearFinderGeneration
                    then
                        return
                    end

                    local started =
                        debugprofilestop
                        and debugprofilestop()
                        or 0

                    local ok,
                          recommendation,
                          status =
                        pcall(
                            WGRBuildLoadedItemRecommendation,
                            itemLink
                        )

                    local finished =
                        debugprofilestop
                        and debugprofilestop()
                        or started

                    local elapsedMS =
                        math.max(
                            0,
                            finished - started
                        )

                    if elapsedMS > slowestMS then
                        slowestMS =
                            elapsedMS
                        slowestItem =
                            tostring(itemName)
                    end

                    if not ok then
                        print(
                            "|cffff3333WBGR Gear Finder diagnostic error on "
                            .. tostring(itemName)
                            .. ": "
                            .. tostring(recommendation)
                            .. "|r"
                        )

                        status =
                            "error"
                        recommendation =
                            nil
                    end

                    if elapsedMS >= 250 then
                        print(
                            string.format(
                                "|cffffff00WBGR Gear Finder slow item: %.1f ms - %s|r",
                                elapsedMS,
                                tostring(itemName)
                            )
                        )
                    end

                    if status == "ready"
                        or status == "unsupported"
                    then
                        local resultGroup,
                              equipLoc =
                            WGRGearFinderGetSlotGroup(
                                itemLink
                            )

                        local level =
                            WGRGearFinderGetItemLevel(
                                itemLink
                            )

                        if resultGroup
                            and level
                        then
                            local copies =
                                itemsByLink[
                                    itemLink
                                ]
                                or {}

                            for _, item
                                in ipairs(copies)
                            do
                                records[
                                    #records + 1
                                ] = {
                                    itemLink =
                                        item.itemLink,
                                    itemLevel =
                                        level,
                                    bagID =
                                        item.bagID,
                                    slotID =
                                        item.slotID,
                                    source =
                                        item.source,
                                    group =
                                        resultGroup,
                                    equipLoc =
                                        equipLoc,
                                    recommendation =
                                        recommendation,
                                }
                            end
                        end

                    elseif status == "not_loaded" then
                        notLoaded =
                            notLoaded + 1
                    end

                    completed =
                        completed + 1

                    index =
                        index + 1

                    C_Timer.After(
                        0,
                        EvaluateCurrentItem
                    )
                end
            )
        end

        EvaluateCurrentItem()
    end

    WGRGearFinderPreloadEquippedData(
        BeginRouting
    )
end

function WGRCreateGearFinderPage(
    frame,
    pageTop
)
    local page =
        CreateFrame(
            "Frame",
            nil,
            frame
        )

    page:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        18,
        pageTop
    )

    page:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -18,
        18
    )

    frame.gearFinderPage =
        page

    WGRGearFinderFrame =
        frame

    local title =
        page:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    title:SetPoint(
        "TOPLEFT",
        page,
        "TOPLEFT",
        0,
        0
    )

    title:SetText(
        "Gear Finder"
    )

    local refresh =
        CreateFrame(
            "Button",
            nil,
            page,
            "UIPanelButtonTemplate"
        )

    refresh:SetSize(
        110,
        23
    )

    refresh:SetPoint(
        "TOPRIGHT",
        page,
        "TOPRIGHT",
        0,
        -2
    )

    refresh:SetText(
        "Refresh Gear"
    )

    frame.gearFinderRefreshButton =
        refresh

    local ignoreHint =
        CreateFrame(
            "Frame",
            nil,
            page
        )

    ignoreHint:SetSize(
        190,
        18
    )

    ignoreHint:SetPoint(
        "TOPRIGHT",
        refresh,
        "BOTTOMRIGHT",
        0,
        -4
    )

    ignoreHint:EnableMouse(
        true
    )

    local ignoreHintText =
        ignoreHint:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    ignoreHintText:SetAllPoints(
        ignoreHint
    )
    ignoreHintText:SetJustifyH(
        "RIGHT"
    )
    ignoreHintText:SetTextColor(
        0.70,
        0.70,
        0.70
    )
    ignoreHintText:SetText(
        "Right-click an item to ignore it"
    )

    ignoreHint:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(
                self,
                "ANCHOR_RIGHT"
            )
            GameTooltip:SetText(
                "Ignore Items"
            )
            GameTooltip:AddLine(
                "Right-click any Gear Finder item to exclude that item ID from WBGR routing.",
                1.00,
                1.00,
                1.00,
                true
            )
            GameTooltip:AddLine(
                "To restore it later, use Settings > Eligible Gear > Ignored Items.",
                0.75,
                0.75,
                0.75,
                true
            )
            GameTooltip:Show()
        end
    )

    ignoreHint:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    frame.gearFinderIgnoreHint =
        ignoreHint

    refresh:SetScript(
        "OnClick",
        function()
            WGRRefreshGearFinder(
                frame
            )
        end
    )

    local sourceStatus =
        page:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    sourceStatus:SetPoint(
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -7
    )

    sourceStatus:SetTextColor(
        0.78,
        0.78,
        0.78
    )

    sourceStatus:SetText(
        "Sources: Equipped |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t  |  Bags |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
    )

    frame.gearFinderSourceStatus =
        sourceStatus

    local function UpdateGearFinderSourceStatus()
        local mailStatus = ""

        if WGRGearFinderHasTrackedMail() then
            mailStatus =
                "  |  Mail |TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t Not Retrieved"
        end

        sourceStatus:SetText(
            "Sources: Equipped |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
            .. "  |  Bags |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
            .. "  |  Personal Bank "
            .. (
                WGRGearFinderPersonalBankOpen
                and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
                or "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t"
            )
            .. "  |  Warband Bank "
            .. (
                WGRGearFinderWarbandBankOpen
                and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
                or "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t"
            )
            .. mailStatus
        )
    end

    frame.UpdateGearFinderSourceStatus =
        UpdateGearFinderSourceStatus

    UpdateGearFinderSourceStatus()

    local specStatus =
        page:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    specStatus:SetPoint(
        "TOPLEFT",
        sourceStatus,
        "BOTTOMLEFT",
        0,
        -5
    )

    specStatus:SetPoint(
        "RIGHT",
        page,
        "RIGHT",
        -4,
        0
    )

    specStatus:SetJustifyH(
        "LEFT"
    )

    specStatus:SetTextColor(
        0.85,
        0.85,
        0.85
    )

    specStatus:SetText(
        "Specs: waiting for scan"
    )

    frame.gearFinderSpecStatus =
        specStatus

    local summary =
        page:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    summary:SetPoint(
        "TOPLEFT",
        specStatus,
        "BOTTOMLEFT",
        0,
        -5
    )

    summary:SetTextColor(
        0.65,
        0.65,
        0.65
    )

    summary:SetText(
        "Open Gear Finder to scan carried gear."
    )

    frame.gearFinderSummary =
        summary

    local scroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            page,
            "UIPanelScrollFrameTemplate"
        )

    scroll:SetPoint(
        "TOPLEFT",
        summary,
        "BOTTOMLEFT",
        0,
        -12
    )

    scroll:SetPoint(
        "BOTTOMRIGHT",
        page,
        "BOTTOMRIGHT",
        -26,
        0
    )

    local content =
        CreateFrame(
            "Frame",
            nil,
            scroll
        )

    content:SetWidth(
        860
    )

    content:SetHeight(
        1
    )

    scroll:SetScrollChild(
        content
    )

    frame.gearFinderScroll =
        scroll

    frame.gearFinderContent =
        content

    page:SetScript(
        "OnShow",
        function()
            WGRGearFinderPollElapsed = 0

            WGRRefreshGearFinder(
                frame
            )
        end
    )

    page:SetScript(
        "OnHide",
        function()
            WGRGearFinderReleaseTooltip()
        end
    )

    page:SetScript(
        "OnUpdate",
        function(
            self,
            elapsed
        )
            WGRGearFinderPollElapsed =
                WGRGearFinderPollElapsed
                + (
                    elapsed
                    or 0
                )

            if WGRGearFinderPollElapsed < 0.60 then
                return
            end

            WGRGearFinderPollElapsed = 0

            local signature =
                WGRGearFinderBuildBagSignature()

            local changed =
                false

            if WGRGearFinderBagSignature == nil then
                WGRGearFinderBagSignature =
                    signature

            elseif signature
                ~= WGRGearFinderBagSignature
            then
                WGRGearFinderBagSignature =
                    signature
                changed =
                    true
            end

            local bankAvailable =
                WGRGearFinderIsPersonalBankAvailable()

            if bankAvailable
                ~= WGRGearFinderPersonalBankOpen
            then
                WGRGearFinderPersonalBankOpen =
                    bankAvailable

                WGRGearFinderPersonalBankSignature =
                    nil

                if frame.UpdateGearFinderSourceStatus then
                    frame.UpdateGearFinderSourceStatus()
                end

                changed =
                    true
            end

            if WGRGearFinderPersonalBankOpen then
                local bankSignature =
                    WGRGearFinderBuildPersonalBankSignature()

                if WGRGearFinderPersonalBankSignature == nil then
                    WGRGearFinderPersonalBankSignature =
                        bankSignature

                elseif bankSignature
                    ~= WGRGearFinderPersonalBankSignature
                then
                    WGRGearFinderPersonalBankSignature =
                        bankSignature
                    changed =
                        true
                end
            end

            local warbandAvailable =
                WGRGearFinderIsWarbandBankAvailable()

            if warbandAvailable
                ~= WGRGearFinderWarbandBankOpen
            then
                WGRGearFinderWarbandBankOpen =
                    warbandAvailable

                WGRGearFinderWarbandBankSignature =
                    nil

                if frame.UpdateGearFinderSourceStatus then
                    frame.UpdateGearFinderSourceStatus()
                end

                if warbandAvailable
                    and frame.gearFinderSummary
                then
                    frame.gearFinderSummary:SetText(
                        "Scanning gear..."
                    )
                end

                changed =
                    true
            end

            if WGRGearFinderWarbandBankOpen then
                local warbandSignature =
                    WGRGearFinderBuildWarbandBankSignature()

                if WGRGearFinderWarbandBankSignature == nil then
                    WGRGearFinderWarbandBankSignature =
                        warbandSignature

                elseif warbandSignature
                    ~= WGRGearFinderWarbandBankSignature
                then
                    WGRGearFinderWarbandBankSignature =
                        warbandSignature
                    changed =
                        true
                end
            end

            if changed then
                WGRScheduleGearFinderRefresh(
                    0.12
                )
            end
        end
    )

    -- Add the Gear Search sub-view only after the Recommendations view
    -- has installed its own scripts and controls.
    if WGRCreateGearSearchView then
        WGRCreateGearSearchView(
            frame,
            page,
            {
                title = title,
                refresh = refresh,
                ignoreHint = ignoreHint,
                sourceStatus = sourceStatus,
                specStatus = specStatus,
                summary = summary,
                scroll = scroll,
            }
        )
    end

    page:Hide()

    if WGRRoutingIsPaused
        and WGRRoutingIsPaused()
    then
        WGRGearFinderSetMasterPaused(
            true
        )
    end

    return page
end

function WGRGearFinderSetMasterPaused(
    paused
)
    local frame =
        WGRGearFinderFrame

    if not frame then
        return
    end

    if frame.gearFinderRefreshButton then
        frame.gearFinderRefreshButton:SetEnabled(
            not paused
        )
    end

    if paused then
        WGRGearFinderGeneration =
            WGRGearFinderGeneration
            + 1

        WGRGearFinderRefreshToken =
            WGRGearFinderRefreshToken
            + 1

        WGRGearFinderReleaseTooltip()

        if frame.gearFinderContent then
            WGRGearFinderClearChildren(
                frame.gearFinderContent
            )
        end

        frame.gearFinderLastResults =
            nil

        if frame.gearFinderSourceStatus then
            frame.gearFinderSourceStatus:SetText(
                "Sources: paused"
            )
        end

        if frame.gearFinderSpecStatus then
            frame.gearFinderSpecStatus:SetText(
                "Specs: paused"
            )
        end

        if frame.gearFinderSummary then
            frame.gearFinderSummary:SetText(
                "WBGR is paused. Resume WBGR to use Gear Finder."
            )
        end
    else
        if frame.UpdateGearFinderSourceStatus then
            frame.UpdateGearFinderSourceStatus()
        end

        if frame.gearFinderSummary then
            frame.gearFinderSummary:SetText(
                "Scanning gear..."
            )
        end

        WGRRefreshGearFinder(
            frame
        )
    end
end

local WGRIgnoredLocationEventFrame =
    CreateFrame(
        "Frame"
    )

WGRIgnoredLocationEventFrame:RegisterEvent(
    "BAG_UPDATE_DELAYED"
)
WGRIgnoredLocationEventFrame:RegisterEvent(
    "PLAYERBANKSLOTS_CHANGED"
)
WGRIgnoredLocationEventFrame:RegisterEvent(
    "BANKFRAME_OPENED"
)
WGRIgnoredLocationEventFrame:RegisterEvent(
    "BANKFRAME_CLOSED"
)

WGRIgnoredLocationEventFrame:SetScript(
    "OnEvent",
    function()
        if WGRRefreshIgnoredItemLocations then
            C_Timer.After(
                0.10,
                WGRRefreshIgnoredItemLocations
            )
        end
    end
)

-- ============================================================
-- GEAR FINDER MODIFIER TOOLTIP REFRESH
-- ============================================================
-- Gear Finder intentionally does not participate in WGR's Shift-expanded
-- routing tooltip system. Its virtual item buttons always show one standard
-- item tooltip; Shift behavior remains exclusive to physical bag/bank slots.

-- ============================================================
-- LIVE GEAR FINDER REFRESH
-- ============================================================

local WGRGearFinderEventFrame =
    CreateFrame(
        "Frame"
    )

WGRGearFinderEventFrame:RegisterEvent(
    "BAG_UPDATE"
)

WGRGearFinderEventFrame:RegisterEvent(
    "BAG_UPDATE_DELAYED"
)

WGRGearFinderEventFrame:RegisterEvent(
    "PLAYER_EQUIPMENT_CHANGED"
)

WGRGearFinderEventFrame:RegisterEvent(
    "PLAYER_SPECIALIZATION_CHANGED"
)

WGRGearFinderEventFrame:RegisterEvent(
    "BANKFRAME_OPENED"
)

WGRGearFinderEventFrame:RegisterEvent(
    "BANKFRAME_CLOSED"
)

WGRGearFinderEventFrame:RegisterEvent(
    "PLAYERBANKSLOTS_CHANGED"
)

WGRGearFinderEventFrame:RegisterEvent(
    "PLAYER_ENTERING_WORLD"
)

WGRGearFinderEventFrame:SetScript(
    "OnEvent",
    function(
        self,
        event,
        arg1
    )
        if event == "PLAYER_SPECIALIZATION_CHANGED"
            and arg1
            and arg1 ~= "player"
        then
            return
        end

        if event == "BANKFRAME_OPENED" then
            WGRGearFinderPersonalBankOpen =
                WGRGearFinderIsPersonalBankAvailable()

            WGRGearFinderWarbandBankOpen =
                WGRGearFinderIsWarbandBankAvailable()

            local frame =
                WGRGearFinderFrame

            if frame
                and frame.UpdateGearFinderSourceStatus
            then
                frame.UpdateGearFinderSourceStatus()
            end

            if WGRRefreshTodoPage then
                WGRRefreshTodoPage()
            end

        elseif event == "BANKFRAME_CLOSED" then
            WGRGearFinderPersonalBankOpen =
                false

            WGRGearFinderWarbandBankOpen =
                false

            WGRGearFinderPersonalBankSignature =
                nil
            WGRGearFinderWarbandBankSignature =
                nil

            local frame =
                WGRGearFinderFrame

            if frame
                and frame.UpdateGearFinderSourceStatus
            then
                frame.UpdateGearFinderSourceStatus()
            end

            -- C_Bank.CanViewBank can lag the close event briefly. The tracked
            -- flags above are authoritative for contextual To Do actions.
            if WGRRefreshTodoPage then
                WGRRefreshTodoPage()
            end
        end

        local delay =
            0.15

        if event == "PLAYER_ENTERING_WORLD" then
            delay = 0.40
        elseif event == "BAG_UPDATE"
            or event == "BAG_UPDATE_DELAYED"
            or event == "PLAYERBANKSLOTS_CHANGED"
            or event == "BANKFRAME_OPENED"
            or event == "BANKFRAME_CLOSED"
        then
            delay = 0.30
        end

        WGRScheduleGearFinderRefresh(
            delay
        )
    end
)
