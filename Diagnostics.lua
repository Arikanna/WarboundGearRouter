-- Diagnostic/debug helpers for item, gear, slot, and Warbank inspection.

-- ============================================================
-- ITEM SPEC / ROLE DIAGNOSTIC
-- ============================================================

local function WGRGetDiagnosticSpecInfo(
    specID
)
    if not specID then
        return nil, nil, nil
    end

    if GetSpecializationInfoByID then
        local ok,
              returnedID,
              specName,
              description,
              icon,
              role,
              classFile,
              className =
            pcall(
                GetSpecializationInfoByID,
                specID
            )

        if ok
            and returnedID
        then
            return
                specName,
                role,
                className
                    or classFile
        end
    end

    -- Fallback: scan class specialization tables if the direct helper
    -- is unavailable or returns incomplete data.
    if GetSpecializationInfoForClassID then
        for classID = 1, 20 do
            for specIndex = 1, 8 do
                local ok,
                      returnedID,
                      specName,
                      description,
                      icon,
                      role,
                      recommended,
                      allowedForBoost =
                    pcall(
                        GetSpecializationInfoForClassID,
                        classID,
                        specIndex
                    )

                if ok
                    and returnedID == specID
                then
                    local className =
                        nil

                    if GetClassInfo then
                        local classInfo =
                            GetClassInfo(
                                classID
                            )

                        if type(classInfo)
                            == "table"
                        then
                            className =
                                classInfo.className
                                or classInfo.name
                        elseif type(classInfo)
                            == "string"
                        then
                            className =
                                classInfo
                        end
                    end

                    return
                        specName,
                        role,
                        className
                end
            end
        end
    end

    return nil, nil, nil
end


local function WGRTrinketDiagnosticItemName(itemLink)
    if not itemLink then
        return "(empty)"
    end

    local name =
        C_Item
        and C_Item.GetItemInfo
        and C_Item.GetItemInfo(itemLink)
        or nil

    return name
        or tostring(itemLink)
end

local function WGRTrinketDiagnosticDirectBaseline(
    characterName,
    specID
)
    local baseline =
        WGRGetSpecTrinketBaseline
        and WGRGetSpecTrinketBaseline(
            characterName,
            specID
        )
        or nil

    if not baseline then
        return nil
    end

    return {
        {
            item = baseline.trinket1,
            level = tonumber(
                baseline.trinket1Level
            ) or 0,
        },
        {
            item = baseline.trinket2,
            level = tonumber(
                baseline.trinket2Level
            ) or 0,
        },
    }
end

function WGRRunTrinketBaselineDiagnostic(
    itemToken,
    characterToken
)
    if not itemToken
        or itemToken == ""
    then
        itemToken =
            GetHoveredItem()
    end

    if not itemToken
        or itemToken == ""
    then
        print(
            "Mouse over a trinket and use |cffffff00/wbgr test trinketbaseline [CharacterName]|r."
        )
        return
    end

    local itemReference =
        tonumber(itemToken)
        or itemToken

    local itemObject =
        CreateItemObject(
            itemReference
        )

    if not itemObject then
        print(
            "|cffff5555WBGR: Could not load that item.|r"
        )
        return
    end

    itemObject:ContinueOnItemLoad(
        function()
            local itemName,
                  itemLink,
                  quality,
                  itemLevel,
                  minLevel,
                  itemType,
                  itemSubType,
                  stackCount,
                  equipLoc =
                C_Item.GetItemInfo(
                    itemReference
                )

            if equipLoc ~= "INVTYPE_TRINKET" then
                print(
                    "|cffff5555WBGR: "
                    .. tostring(
                        itemName
                        or itemToken
                    )
                    .. " is not a trinket.|r"
                )
                return
            end

            local characterName =
                characterToken

            if not characterName
                or characterName == ""
            then
                characterName =
                    UnitName("player")
            end

            local character =
                FindCharacterByName(
                    characterName
                )

            if not character then
                print(
                    "|cffff5555WBGR: Character not found: "
                    .. tostring(
                        characterName
                    )
                    .. "|r"
                )
                return
            end

            local classID =
                GetCharacterClassID(
                    characterName,
                    character
                )

            local specIDs =
                WGRGetRoutingSpecIDs(
                    characterName,
                    character
                )
                or {}

            print(
                "|cff00ff00=== WBGR TRINKET BASELINE DIAGNOSTIC ===|r"
            )
            print(
                "Item: "
                .. tostring(
                    itemName
                    or itemLink
                    or itemToken
                )
                .. " | iLvl "
                .. tostring(
                    itemLevel
                    or "?"
                )
            )
            print(
                "Character: "
                .. tostring(
                    characterName
                )
                .. " | Spec Mode: "
                .. tostring(
                    WGRGetEffectiveSpecMode(
                        characterName
                    )
                    or "?"
                )
            )

            if #specIDs == 0 then
                print(
                    "|cffff5555No routing specs are active for this character.|r"
                )
                return
            end

            local finalComparison,
                  finalStatus =
                WGRGetTrinketComparisonLevelForMode(
                    characterName,
                    character,
                    itemLink
                        or itemReference
                )

            for _, specID
                in ipairs(
                    specIDs
                )
            do
                local specName =
                    WGRSpecNamesByID[
                        specID
                    ]
                    or tostring(
                        specID
                    )

                local candidateFits =
                    WGRItemFitsSpecificSpec
                    and WGRItemFitsSpecificSpec(
                        itemLink
                            or itemReference,
                        classID,
                        specID
                    )
                    or nil

                local resolved1,
                      resolved2 =
                    WGRGetResolvedSpecTrinketLevels(
                        characterName,
                        character,
                        specID
                    )

                local comparison,
                      status =
                    WGRGetSpecificSpecTrinketComparisonLevel(
                        characterName,
                        character,
                        itemLink
                            or itemReference,
                        specID
                    )

                print(
                    (
                        candidateFits == true
                        and "|cff00ff00+ |r"
                        or candidateFits == false
                        and "|cff777777- |r"
                        or "|cffffaa00? |r"
                    )
                    .. tostring(
                        specName
                    )
                    .. ": resolved "
                    .. tostring(
                        resolved1
                        or 0
                    )
                    .. " / "
                    .. tostring(
                        resolved2
                        or 0
                    )
                    .. " | compare "
                    .. tostring(
                        comparison
                        or "-"
                    )
                    .. " | "
                    .. tostring(
                        status
                        or "?"
                    )
                )

                local direct =
                    WGRTrinketDiagnosticDirectBaseline(
                        characterName,
                        specID
                    )

                if direct then
                    print(
                        "    Direct saved: "
                        .. WGRTrinketDiagnosticItemName(
                            direct[1].item
                        )
                        .. " ["
                        .. tostring(
                            direct[1].level
                        )
                        .. "] / "
                        .. WGRTrinketDiagnosticItemName(
                            direct[2].item
                        )
                        .. " ["
                        .. tostring(
                            direct[2].level
                        )
                        .. "]"
                    )
                else
                    print(
                        "    Direct saved: (none)"
                    )
                end
            end

            print(
                "|cffffff00Final mode comparison: |r"
                .. tostring(
                    finalComparison
                    or "-"
                )
                .. " | "
                .. tostring(
                    finalStatus
                    or "?"
                )
            )
        end
    )
end

function WGRRunTrinketRoutingDiagnostic(
    itemToken
)
    if not itemToken
        or itemToken == ""
    then
        itemToken =
            GetHoveredItem()
    end

    if not itemToken
        or itemToken == ""
    then
        print(
            "Mouse over a trinket and use |cffffff00/wbgr test trinket|r, or use |cffffff00/wbgr test trinket ITEMID|r."
        )
        return
    end

    local itemObject =
        CreateItemObject(
            tonumber(itemToken)
            or itemToken
        )

    if not itemObject then
        print(
            "|cffff5555WBGR: Could not load that item.|r"
        )
        return
    end

    itemObject:ContinueOnItemLoad(
        function()
            local itemReference =
                tonumber(itemToken)
                or itemToken

            local itemName,
                  itemLink,
                  quality,
                  itemLevel,
                  minLevel,
                  itemType,
                  itemSubType,
                  stackCount,
                  equipLoc =
                C_Item.GetItemInfo(
                    itemReference
                )

            if equipLoc ~= "INVTYPE_TRINKET" then
                print(
                    "|cffff5555WBGR: "
                    .. tostring(
                        itemName
                        or itemToken
                    )
                    .. " is not a trinket.|r"
                )
                return
            end

            print(
                "|cff00ff00=== WBGR TRINKET ELIGIBILITY ===|r"
            )

            print(
                tostring(
                    itemName
                    or itemLink
                    or itemToken
                )
            )

            local specSet,
                  specCount =
                WGRGetItemSpecSet(
                    itemLink
                    or itemReference
                )

            if not specSet
                or specCount == 0
            then
                print(
                    "|cffffff00Blizzard returned no usable spec data; WBGR will use legacy all-character trinket routing for this item.|r"
                )
                return
            end

            print(
                "Blizzard spec IDs: "
                .. tostring(
                    specCount
                )
            )

            for _, characterName
                in ipairs(
                    GetActiveRoutingPriority()
                )
            do
                local character =
                    FindCharacterByName(
                        characterName
                    )

                if character then
                    local matches =
                        WGRCharacterMatchesItemSpecs(
                            characterName,
                            character,
                            specSet
                        )

                    local routingSpecs =
                        WGRGetRoutingSpecIDs(
                            characterName,
                            character
                        )

                    local specNames = {}

                    for _, specID
                        in ipairs(
                            routingSpecs
                            or {}
                        )
                    do
                        specNames[
                            #specNames + 1
                        ] =
                            WGRSpecNamesByID[
                                specID
                            ]
                            or tostring(
                                specID
                            )
                    end

                    print(
                        (
                            matches
                            and "|cff00ff00+ |r"
                            or "|cff777777- |r"
                        )
                        .. tostring(
                            characterName
                        )
                        .. ": "
                        .. (
                            #specNames > 0
                            and table.concat(
                                specNames,
                                ", "
                            )
                            or "no routing spec"
                        )
                    )
                end
            end
        end
    )
end

function WGRRunItemSpecDiagnostic(
    itemToken
)
    if not itemToken
        or itemToken == ""
    then
        itemToken =
            GetHoveredItem()
    end

    if not itemToken
        or itemToken == ""
    then
        print(
            "Mouse over an item and use |cffffff00/wbgr test spec|r, or use |cffffff00/wbgr test spec ITEMID|r."
        )
        return
    end

    local numericID =
        tonumber(
            itemToken
        )

    local itemReference =
        numericID
        or itemToken

    local itemObject =
        CreateItemObject(
            itemReference
        )

    if not itemObject then
        print(
            "|cffff5555WBGR:|r Could not create an item object for "
            .. tostring(
                itemToken
            )
            .. "."
        )
        return
    end

    itemObject:ContinueOnItemLoad(
        function()
            local itemName,
                  itemLink,
                  quality,
                  itemLevel,
                  minLevel,
                  itemType,
                  itemSubType,
                  stackCount,
                  equipLoc =
                C_Item.GetItemInfo(
                    itemReference
                )

            print(
                "|cff00ff00=== WBGR ITEM SPEC DIAGNOSTIC ===|r"
            )

            print(
                "Item: "
                .. tostring(
                    itemName
                    or itemLink
                    or itemToken
                )
                .. "  [ID "
                .. tostring(
                    numericID
                    or "?"
                )
                .. "]"
            )

            local playerName =
                UnitName(
                    "player"
                )

            local _, className =
                UnitClass(
                    "player"
                )

            print(
                "Logged in as: "
                .. tostring(
                    playerName
                    or "Unknown"
                )
                .. " ("
                .. tostring(
                    className
                    or "Unknown class"
                )
                .. ")"
            )

            if not C_Item
                or not C_Item.GetItemSpecInfo
            then
                print(
                    "|cffff5555C_Item.GetItemSpecInfo is unavailable on this client.|r"
                )
                return
            end

            local ok,
                  specResult =
                pcall(
                    C_Item.GetItemSpecInfo,
                    itemReference
                )

            if not ok then
                print(
                    "|cffff5555C_Item.GetItemSpecInfo generated an API error.|r"
                )
                return
            end

            local specIDs = {}

            if type(specResult)
                == "table"
            then
                for _, specID
                    in pairs(
                        specResult
                    )
                do
                    if type(specID)
                        == "number"
                    then
                        table.insert(
                            specIDs,
                            specID
                        )
                    end
                end
            elseif type(specResult)
                == "number"
            then
                table.insert(
                    specIDs,
                    specResult
                )
            end

            table.sort(
                specIDs
            )

            print(
                "Blizzard returned "
                .. tostring(
                    #specIDs
                )
                .. " specialization ID(s)."
            )

            if #specIDs == 0 then
                print(
                    "|cffffff00No specialization data was returned for this item on this character.|r"
                )

                print(
                    "This may mean the item has no spec data, or the API result is filtered by the logged-in class."
                )
                return
            end

            local roleCounts = {
                DAMAGER = 0,
                TANK = 0,
                HEALER = 0,
                NONE = 0,
                UNKNOWN = 0,
            }

            for _, specID
                in ipairs(
                    specIDs
                )
            do
                local specName,
                      role,
                      specClass =
                    WGRGetDiagnosticSpecInfo(
                        specID
                    )

                local normalizedRole =
                    role
                    and tostring(role)
                    or "UNKNOWN"

                if roleCounts[
                    normalizedRole
                ] == nil
                then
                    roleCounts[
                        normalizedRole
                    ] = 0
                end

                roleCounts[
                    normalizedRole
                ] =
                    roleCounts[
                        normalizedRole
                    ] + 1

                print(
                    "  "
                    .. tostring(
                        specID
                    )
                    .. " - "
                    .. tostring(
                        specName
                        or "Unknown Spec"
                    )
                    .. " - "
                    .. tostring(
                        specClass
                        or "Unknown Class"
                    )
                    .. " - "
                    .. normalizedRole
                )
            end

            local roleParts = {}

            for _, roleName
                in ipairs({
                    "DAMAGER",
                    "TANK",
                    "HEALER",
                    "NONE",
                    "UNKNOWN",
                })
            do
                local count =
                    roleCounts[
                        roleName
                    ]
                    or 0

                if count > 0 then
                    table.insert(
                        roleParts,
                        roleName
                        .. "="
                        .. tostring(
                            count
                        )
                    )
                end
            end

            print(
                "Role summary: "
                .. (
                    #roleParts > 0
                    and table.concat(
                        roleParts,
                        ", "
                    )
                    or "none"
                )
            )

            print(
                "|cffaaaaaaRun this same ITEMID on a different class to see whether Blizzard's result changes.|r"
            )
        end
    )
end


-- ============================================================
-- /WGR ITEM
-- ============================================================

function EvaluateItem(itemLink)
    if not itemLink then
        print(
            "|cffff0000No item detected.|r"
        )

        print(
            "Hover over an item and type |cffffff00/wbgr item|r."
        )

        return
    end

    local hoveredItem =
        CreateItemObject(itemLink)

    if not hoveredItem then
        print(
            "|cffff0000Could not create item object.|r"
        )

        return
    end

    hoveredItem:ContinueOnItemLoad(
        function()

            if not IsTransferableGearTooltip(GameTooltip, itemLink) then
                print(
                    "|cffffff00Warbound Gear Router only evaluates Warbound or Bind on Equip gear.|r"
                )

                return
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
            C_Item.GetItemInfo(itemLink)

        if not itemName then
            print(
                "|cffff0000Could not read item information.|r"
            )

            return
        end

        local newItemLevel =
            GetItemLevel(itemLink)

        if not newItemLevel then
            print(
                "|cffff0000Could not determine the item's item level.|r"
            )

            return
        end

        -- Armor
        local armorSlotID =
            WGRArmorEquipSlots[equipLoc]

        if armorSlotID then
            local armorType =
                itemSubType

            if not GetArmorPriorityList(armorType) then
                print(string.format(
                    "|cffff0000Unsupported armor type: %s|r",
                    tostring(armorType)
                ))

                return
            end

            RunEvaluation(
                itemName,
                newItemLevel,
                GetArmorPriorityList(armorType),
                { armorSlotID },
                armorType
            )

            return
        end

        -- Accessories
        local globalSlots =
            WGRGlobalEquipSlots[equipLoc]

        if globalSlots then
            local label =
                "Accessory"

            if equipLoc
                == "INVTYPE_NECK"
            then
                label = "Neck"

            elseif equipLoc
                == "INVTYPE_CLOAK"
            then
                label = "Cloak"

            elseif equipLoc
                == "INVTYPE_FINGER"
            then
                label = "Ring"

            elseif equipLoc
                == "INVTYPE_TRINKET"
            then
                label = "Trinket"
            end

            local priorityList =
                equipLoc == "INVTYPE_TRINKET"
                and WGRGetTrinketRoutingPriority(
                    itemLink
                )
                or GetActiveRoutingPriority()

            RunEvaluation(
                itemName,
                newItemLevel,
                priorityList,
                globalSlots,
                label
            )

            return
        end

        -- Off-hands and shields
        if WGROffhandEquipLocs[equipLoc] then
            PreloadItems(
                GetActiveRoutingPriority(),
                { 16, 17 },
                function()
                    EvaluateOffhand(
                        itemLink,
                        itemName,
                        newItemLevel
                    )
                end,
                false
            )

            return
        end

        -- Weapons
        if IsSupportedWeapon(itemLink) then
            PreloadItems(
                GetActiveRoutingPriority(),
                { 16, 17 },
                function()
                    EvaluateWeapon(
                        itemLink,
                        itemName,
                        newItemLevel
                    )
                end,
                false
            )

            return
        end

        print(string.format(
            "|cffffff00%s|r is not supported yet.",
            itemName
        ))
    end)
end


-- ============================================================
-- /WGR TEST
--
-- Developer/test harness. This intentionally bypasses binding/quality
-- checks so an arbitrary item ID can be used to exercise the same
-- routing/spec/profile functions as normal WGR evaluation.
--
-- Usage:
--   /wgr test ITEMID
--   /wgr test ITEMID ignoreilvl
--   /wgr test ITEMID verbose
--   /wgr test ITEMID ignoreilvl verbose
-- ============================================================

local function WGRTestPrintItemSummary(
    itemLink,
    itemName,
    itemLevel,
    effectiveLevel,
    ignoreIlvl,
    simulatedIlvl
)
    local info =
        GetInstantItemInfo(
            itemLink
        )

    local kind =
        GetWeaponKind(
            itemLink
        )

    local offhandKind =
        WGRGetOffhandKind(
            itemLink
        )

    print(
        "|cff00ff00=== WBGR TEST ===|r"
    )

    print(
        tostring(itemName)
        .. " | Item ID "
        .. tostring(
            info
            and info.itemID
            or "?"
        )
        .. " | ilvl "
        .. tostring(
            itemLevel
            or "?"
        )
    )

    print(
        "EquipLoc: "
        .. tostring(
            info
            and info.equipLoc
            or "?"
        )
        .. " | Subclass: "
        .. tostring(
            info
            and info.itemSubType
            or "?"
        )
        .. " | WBGR kind: "
        .. tostring(
            offhandKind
            or kind
            or "non-weapon"
        )
    )

    if info
        and info.subclassID == WGR_WEAPON_WAND
    then
        print(
            "|cffffff00Wand normalization:|r "
            .. (
                kind == "ONE_HAND"
                and "|cff00ff001H caster weapon (PASS)|r"
                or "|cffff5555NOT normalized as 1H (FAIL)|r"
            )
        )
    end

    if simulatedIlvl then
        print(
            "|cffffff00simulated ilvl:|r "
            .. tostring(simulatedIlvl)
            .. " (real item ilvl "
            .. tostring(itemLevel or "?")
            .. ")."
        )
    elseif ignoreIlvl then
        print(
            "|cffffff00ignoreilvl:|r enabled; testing with effective ilvl "
            .. tostring(effectiveLevel)
            .. "."
        )
    end
end

local function WGRTestVerboseWeaponEligibility(
    itemLink
)
    local info =
        GetInstantItemInfo(
            itemLink
        )

    if not info then
        return
    end

    local offhandKind =
        WGRGetOffhandKind(
            itemLink
        )

    local isWeapon =
        info.classID == WGR_ITEM_CLASS_WEAPON

    if not isWeapon
        and not offhandKind
    then
        return
    end

    print(" ")
    print(
        "|cff00ff00Eligibility diagnostics|r"
    )

    for _, characterName
        in ipairs(
            GetActiveRoutingPriority()
        )
    do
        local character =
            FindCharacterByName(
                characterName
            )

        if character then
            local classID =
                GetCharacterClassID(
                    characterName,
                    character
                )

            local proficiency =
                offhandKind
                and true
                or (
                    classID
                    and WGRClassCanUseWeaponSubtype(
                        classID,
                        itemLink
                    )
                )

            local acceptedSpecs = {}
            local rejectedSpecs = {}

            for _, specID
                in ipairs(
                    WGRGetRoutingSpecIDs(
                        characterName,
                        character
                    )
                    or {}
                )
            do
                local specName =
                    WGRSpecNamesByID[specID]
                    or tostring(specID)

                local apiEligible =
                    WGRItemFitsSpecificSpec(
                        itemLink,
                        classID,
                        specID
                    )

                local comparisonType =
                    offhandKind
                    and "OFFHAND"
                    or "WEAPON"

                local profileEligible =
                    apiEligible == true
                    and WGRSpecAllowsWeaponByProfile(
                        characterName,
                        specID,
                        itemLink,
                        comparisonType
                    )

                if proficiency ~= false
                    and profileEligible
                then
                    acceptedSpecs[
                        #acceptedSpecs + 1
                    ] =
                        specName
                else
                    local reason = nil

                    if proficiency == false then
                        reason = "proficiency"
                    elseif apiEligible == false then
                        reason = "spec"
                    elseif apiEligible == nil then
                        reason = "spec API unavailable"
                    elseif offhandKind then
                        reason = "off-hand profile"
                    else
                        reason = "weapon profile"
                    end

                    rejectedSpecs[
                        #rejectedSpecs + 1
                    ] =
                        specName
                        .. " ("
                        .. reason
                        .. ")"
                end
            end

            if #acceptedSpecs > 0 then
                print(
                    "|cff00ff00+|r "
                    .. characterName
                    .. ": "
                    .. table.concat(
                        acceptedSpecs,
                        ", "
                    )
                )

            elseif #rejectedSpecs > 0 then
                print(
                    "|cff777777-|r "
                    .. characterName
                    .. ": "
                    .. table.concat(
                        rejectedSpecs,
                        ", "
                    )
                )
            end
        end
    end
end



local function WGRTestFindLiveItemLink(
    itemID
)
    if not itemID then
        return nil, nil
    end

    local function MatchContainer(
        bagID,
        label
    )
        if not C_Container
            or not C_Container.GetContainerNumSlots
            or not C_Container.GetContainerItemLink
        then
            return nil, nil
        end

        local slots =
            C_Container.GetContainerNumSlots(
                bagID
            )
            or 0

        for slotID = 1, slots do
            local link =
                C_Container.GetContainerItemLink(
                    bagID,
                    slotID
                )

            if link then
                local foundID =
                    C_Item.GetItemInfoInstant(
                        link
                    )

                if foundID == itemID then
                    return link, label
                end
            end
        end

        return nil, nil
    end

    -- Character bags.
    for bagID = BACKPACK_CONTAINER,
        NUM_BAG_SLOTS
    do
        local link, location =
            MatchContainer(
                bagID,
                "Bags"
            )

        if link then
            return link, location
        end
    end

    -- Reagent bag, if present.
    if Enum
        and Enum.BagIndex
        and Enum.BagIndex.ReagentBag
    then
        local link, location =
            MatchContainer(
                Enum.BagIndex.ReagentBag,
                "Reagent Bag"
            )

        if link then
            return link, location
        end
    end

    -- Personal bank while accessible.
    if WGRGearFinderIsPersonalBankAvailable
        and WGRGearFinderIsPersonalBankAvailable()
    then
        local firstBankBag =
            NUM_BAG_SLOTS + 1

        local lastBankBag =
            NUM_BAG_SLOTS
            + (
                NUM_BANKBAGSLOTS
                or 7
            )

        for bagID = firstBankBag,
            lastBankBag
        do
            local link, location =
                MatchContainer(
                    bagID,
                    "Personal Bank"
                )

            if link then
                return link, location
            end
        end

        if BANK_CONTAINER then
            local link, location =
                MatchContainer(
                    BANK_CONTAINER,
                    "Personal Bank"
                )

            if link then
                return link, location
            end
        end
    end

    -- Warband Bank while accessible. Reuse Gear Finder's scanner so
    -- we do not duplicate account-bank container assumptions here.
    if WGRGearFinderIsWarbandBankAvailable
        and WGRGearFinderIsWarbandBankAvailable()
        and WGRGearFinderScanWarbandBank
    then
        local items =
            WGRGearFinderScanWarbandBank()
            or {}

        for _, item
            in ipairs(items)
        do
            if item.itemLink then
                local foundID =
                    C_Item.GetItemInfoInstant(
                        item.itemLink
                    )

                if foundID == itemID then
                    return
                        item.itemLink,
                        "Warband Bank"
                end
            end
        end
    end

    return nil, nil
end

function WGRRunTestItem(
    itemToken,
    ignoreIlvl,
    verbose,
    simulatedIlvl
)
    if not itemToken
        or itemToken == ""
    then
        print(
            "Usage: |cffffff00/wbgr test ITEMID [ignoreilvl] [verbose] [ilvl NUMBER]|r"
        )
        return
    end

    local itemObject =
        CreateItemObject(
            itemToken
        )

    if not itemObject then
        print(
            "|cffff5555WBGR TEST: Could not create an item from:|r "
            .. tostring(itemToken)
        )
        return
    end

    itemObject:ContinueOnItemLoad(
        function()
            local itemID =
                tonumber(itemToken)

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
                    itemID
                    or itemToken
                )

            local liveItemLink = nil
            local liveItemLocation = nil

            if itemID then
                liveItemLink,
                liveItemLocation =
                    WGRTestFindLiveItemLink(
                        itemID
                    )
            end

            local itemLink =
                liveItemLink
                or returnedLink
                or (
                    itemObject.GetItemLink
                    and itemObject:GetItemLink()
                )
                or itemToken

            if verbose
                and liveItemLink
            then
                print(
                    "|cff00ff00WBGR TEST:|r Using live item link from "
                    .. tostring(
                        liveItemLocation
                        or "accessible storage"
                    )
                    .. "."
                )
            elseif verbose
                and itemID
            then
                print(
                    "|cffffff00WBGR TEST:|r No accessible live copy found; using generic item data."
                )
            end

            if liveItemLink then
                local liveName,
                      liveReturnedLink,
                      liveQuality,
                      liveBaseItemLevel,
                      liveItemMinLevel,
                      liveItemType,
                      liveItemSubType,
                      liveStackCount,
                      liveEquipLoc =
                    C_Item.GetItemInfo(
                        liveItemLink
                    )

                itemName =
                    liveName
                    or itemName

                returnedLink =
                    liveReturnedLink
                    or returnedLink

                itemQuality =
                    liveQuality
                    or itemQuality

                baseItemLevel =
                    liveBaseItemLevel
                    or baseItemLevel

                itemMinLevel =
                    liveItemMinLevel
                    or itemMinLevel

                itemType =
                    liveItemType
                    or itemType

                itemSubType =
                    liveItemSubType
                    or itemSubType

                stackCount =
                    liveStackCount
                    or stackCount

                equipLoc =
                    liveEquipLoc
                    or equipLoc
            end

            if not itemName
                or not itemLink
            then
                print(
                    "|cffff5555WBGR TEST: Item data is still unavailable.|r"
                )
                return
            end

            if verbose then
                print(
                    "|cff00ff00WBGR TEST:|r Resolved required level = "
                    .. tostring(
                        itemMinLevel
                        or 0
                    )
                )
            end

            local realItemLevel =
                GetItemLevel(
                    itemLink
                )
                or baseItemLevel
                or 0

            local effectiveLevel =
                simulatedIlvl
                or (
                    ignoreIlvl
                    and 9999
                    or realItemLevel
                )

            WGRTestPrintItemSummary(
                itemLink,
                itemName,
                realItemLevel,
                effectiveLevel,
                ignoreIlvl,
                simulatedIlvl
            )

            if verbose then
                WGRTestVerboseWeaponEligibility(
                    itemLink
                )
            end

            print(" ")
            print(
                "|cff00ff00Routing result|r"
            )

            local armorSlotID =
                WGRArmorEquipSlots[
                    equipLoc
                ]

            if armorSlotID then
                local armorType =
                    itemSubType

                local priority =
                    GetArmorPriorityList(
                        armorType
                    )

                if not priority then
                    print(
                        "|cffff5555Unsupported armor type:|r "
                        .. tostring(armorType)
                    )
                    return
                end

                RunEvaluation(
                    itemName,
                    effectiveLevel,
                    priority,
                    { armorSlotID },
                    armorType
                )

                return
            end

            local globalSlots =
                WGRGlobalEquipSlots[
                    equipLoc
                ]

            if globalSlots then
                local label =
                    "Accessory"

                if equipLoc == "INVTYPE_NECK" then
                    label = "Neck"
                elseif equipLoc == "INVTYPE_CLOAK" then
                    label = "Cloak"
                elseif equipLoc == "INVTYPE_FINGER" then
                    label = "Ring"
                elseif equipLoc == "INVTYPE_TRINKET" then
                    label = "Trinket"
                end

                local priorityList =
                    equipLoc == "INVTYPE_TRINKET"
                    and WGRGetTrinketRoutingPriority(
                        itemLink
                    )
                    or GetActiveRoutingPriority()

                RunEvaluation(
                    itemName,
                    effectiveLevel,
                    priorityList,
                    globalSlots,
                    label
                )

                return
            end

            if WGROffhandEquipLocs[
                equipLoc
            ] then
                PreloadItems(
                    GetActiveRoutingPriority(),
                    { 16, 17 },
                    function()
                        EvaluateOffhand(
                            itemLink,
                            itemName,
                            effectiveLevel
                        )
                    end,
                    false
                )

                return
            end

            if IsSupportedWeapon(
                itemLink
            ) then
                PreloadItems(
                    GetActiveRoutingPriority(),
                    { 16, 17 },
                    function()
                        EvaluateWeapon(
                            itemLink,
                            itemName,
                            effectiveLevel,
                            itemMinLevel,
                            verbose
                        )
                    end,
                    false
                )

                return
            end

            print(
                "|cffffff00WBGR TEST: Item type is not currently supported by routing.|r"
            )
        end
    )
end


-- ============================================================
-- GEAR DIAGNOSTIC
-- ============================================================

function PrintGear(characterName)
    local character =
        FindCharacterByName(
            characterName
        )

    if not character then
        print(
            "|cffff0000Character not found:|r "
            .. tostring(characterName)
        )

        return
    end

    local name =
        DataStore:GetCharacterName(
            character
        ) or characterName

    local level =
        DataStore:GetCharacterLevel(
            character
        ) or "?"

    local class =
        DataStore:GetCharacterClass(
            character
        ) or "Unknown"

    print(
        "|cff00ff00Warbound Gear Router - Equipment Test|r"
    )

    print(string.format(
        "%s - %s - Level %s",
        name,
        class,
        tostring(level)
    ))

    for _, slotInfo
        in ipairs(WGRDiagnosticSlots)
    do
        local slotID =
            slotInfo[1]

        local slotName =
            slotInfo[2]

        local item =
            GetStoredItem(
                character,
                slotID
            )

        if not item then
            print(string.format(
                "%s: |cff777777Empty|r",
                slotName
            ))
        else
            local itemLevel =
                GetItemLevel(item)

            if itemLevel then
                print(string.format(
                    "%s: %s |cffaaaaaa(ilvl %d)|r",
                    slotName,
                    tostring(item),
                    itemLevel
                ))
            else
                print(string.format(
                    "%s: %s |cffff8800(ilvl unavailable)|r",
                    slotName,
                    tostring(item)
                ))
            end
        end
    end
end


-- ============================================================
-- SLOT DEBUG
-- ============================================================

function DebugCharacterSlot(
    characterName,
    slotID
)
    local character =
        FindCharacterByName(
            characterName
        )

    if not character then
        print(
            "|cffff0000Character not found:|r "
            .. tostring(
                characterName
            )
        )
        return
    end

    slotID =
        tonumber(slotID)

    if not slotID then
        print(
            "|cffff0000Invalid slot ID.|r"
        )
        return
    end

    local storedItem =
        GetStoredItem(
            character,
            slotID
        )

    print(
        "|cff00ff00WBGR Slot Debug|r"
    )

    print(string.format(
        "%s - slot %d",
        characterName,
        slotID
    ))

    print(
        "Raw DataStore value: "
        .. tostring(
            storedItem
        )
    )

    if storedItem == nil then
        print(
            "Stored item: nil / empty"
        )
        return
    end

    print(
        "Lua type: "
        .. type(
            storedItem
        )
    )

    local itemID,
          itemType,
          itemSubType,
          itemEquipLoc,
          icon,
          classID,
          subclassID =
        C_Item.GetItemInfoInstant(
            storedItem
        )

    print(
        "GetItemInfoInstant itemID: "
        .. tostring(
            itemID
        )
    )

    print(
        "EquipLoc: "
        .. tostring(
            itemEquipLoc
        )
    )

    print(
        "ClassID/SubclassID: "
        .. tostring(
            classID
        )
        .. " / "
        .. tostring(
            subclassID
        )
    )

    local itemName,
          itemLink,
          itemQuality,
          baseItemLevel,
          itemMinLevel,
          itemType2,
          itemSubType2,
          stackCount,
          equipLoc2,
          icon2,
          sellPrice,
          classID2,
          subclassID2,
          bindType =
        C_Item.GetItemInfo(
            storedItem
        )

    print(
        "GetItemInfo name: "
        .. tostring(
            itemName
        )
    )

    print(
        "GetItemInfo link: "
        .. tostring(
            itemLink
        )
    )

    print(
        "Base item level: "
        .. tostring(
            baseItemLevel
        )
    )

    print(
        "Required level: "
        .. tostring(
            itemMinLevel
        )
    )

    print(
        "Bind type: "
        .. tostring(
            bindType
        )
    )

    local detailedLevel =
        GetItemLevel(
            storedItem
        )

    print(
        "WBGR stored-item level: "
        .. tostring(
            detailedLevel
        )
    )
end



-- ============================================================
-- WARBANK BUTTON DEBUG
-- ============================================================



-- ============================================================
-- HOVERED WARBANK ITEM BUTTON DEBUG
-- ============================================================




local WGRMail
local WGRMailOpenRouterManual
