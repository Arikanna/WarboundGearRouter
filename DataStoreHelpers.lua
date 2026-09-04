-- Low-level DataStore, item-info, and transferable-item helpers.
-- Kept behavior-identical to the v0.56f monolith during extraction.

-- ============================================================
-- DATASTORE HELPERS
-- ============================================================

local WGRDataStoreCharacterIndex =
    nil

-- Scoped routing-evaluation cache. Expensive held-gear/bank scans evaluate
-- many items against the same roster. Cache DataStore reads only for the
-- duration of one consolidated scan so correctness is preserved while
-- avoiding repeated character/slot/item lookups.
local WGRRoutingEvaluationCache = nil
local WGRRoutingEvaluationCacheDepth = 0

function WGRBeginRoutingEvaluationCache()
    WGRRoutingEvaluationCacheDepth = WGRRoutingEvaluationCacheDepth + 1
    if WGRRoutingEvaluationCacheDepth == 1 then
        WGRRoutingEvaluationCache = { levels = {}, stored = {}, itemLevels = {}, specs = {} }
    end
end

function WGREndRoutingEvaluationCache()
    if WGRRoutingEvaluationCacheDepth <= 0 then return end
    WGRRoutingEvaluationCacheDepth = WGRRoutingEvaluationCacheDepth - 1
    if WGRRoutingEvaluationCacheDepth == 0 then
        WGRRoutingEvaluationCache = nil
    end
end

function WGRGetRoutingEvaluationCache()
    return WGRRoutingEvaluationCache
end

function WGRGetCharacterLevel(character)
    if not character then return 0 end
    local cache = WGRRoutingEvaluationCache
    if cache then
        local v = cache.levels[character]
        if v ~= nil then return v end
        v = (DataStore and DataStore.GetCharacterLevel and DataStore:GetCharacterLevel(character)) or 0
        cache.levels[character] = v
        return v
    end
    return (DataStore and DataStore.GetCharacterLevel and DataStore:GetCharacterLevel(character)) or 0
end

local function WGRBuildDataStoreCharacterIndex()
    if not DataStore
        or not DataStore.GetCharacters
        or not DataStore.GetCharacterName
    then
        return nil
    end

    local index = {}

    for _, character
        in pairs(
            DataStore:GetCharacters()
        )
    do
        local name =
            DataStore:GetCharacterName(
                character
            )

        if name
            and name ~= ""
        then
            local key =
                string.lower(
                    name
                )

            -- Preserve the old lookup behavior of accepting the first
            -- matching character returned by DataStore.
            if not index[key] then
                index[key] =
                    character
            end
        end
    end

    WGRDataStoreCharacterIndex =
        index

    return index
end

function FindCharacterByName(searchName)
    if not searchName
        or searchName == ""
    then
        return nil
    end

    local key =
        string.lower(
            searchName
        )

    local index =
        WGRDataStoreCharacterIndex
        or WGRBuildDataStoreCharacterIndex()

    if not index then
        return nil
    end

    local character =
        index[key]

    if character then
        return character
    end

    -- DataStore can gain characters after WGR's first lookup during
    -- login/reload. Rebuild once on a miss so newly available characters
    -- become visible without making every lookup a full roster scan.
    index =
        WGRBuildDataStoreCharacterIndex()

    return
        index
        and index[key]
        or nil
end

function GetStoredItem(character, slotID)
    if not character or not slotID then return nil end
    local cache = WGRRoutingEvaluationCache
    if cache then
        local byChar = cache.stored[character]
        if not byChar then byChar = {}; cache.stored[character] = byChar end
        if byChar[slotID] ~= nil then
            return byChar[slotID] ~= false and byChar[slotID] or nil
        end
        local item = DataStore.GetInventoryItem and DataStore:GetInventoryItem(character, slotID) or nil
        byChar[slotID] = item or false
        return item
    end
    if DataStore.GetInventoryItem then return DataStore:GetInventoryItem(character, slotID) end
    return nil
end

function GetItemLevel(item)
    if not item then return nil end
    local cache = WGRRoutingEvaluationCache
    local cacheKey = tostring(item)
    if cache and cache.itemLevels[cacheKey] ~= nil then
        return cache.itemLevels[cacheKey] ~= false and cache.itemLevels[cacheKey] or nil
    end

    -- DataStore inventory values represent stored equipment links.
    -- C_Item.GetDetailedItemLevelInfo() can return a scaled/current-context
    -- value for these legacy/leveling items, which is not the actual ilvl
    -- of the item the character has equipped.
    --
    -- For routing comparisons, use the item's normal item info/base ilvl.
    local itemName,
          itemLink,
          itemQuality,
          baseItemLevel =
        C_Item.GetItemInfo(item)

    if baseItemLevel
        and baseItemLevel > 0
    then
        if cache then cache.itemLevels[cacheKey] = baseItemLevel end
        return baseItemLevel
    end

    -- Fallback for older API behavior.
    local _, _, _, fallbackLevel =
        GetItemInfo(item)

    if fallbackLevel
        and fallbackLevel > 0
    then
        if cache then cache.itemLevels[cacheKey] = fallbackLevel end
        return fallbackLevel
    end

    if cache then cache.itemLevels[cacheKey] = false end
    return nil
end

function GetInstantItemInfo(item)
    if not item
        or not C_Item
        or not C_Item.GetItemInfoInstant
    then
        return nil
    end

    local itemID,
          itemType,
          itemSubType,
          itemEquipLoc,
          icon,
          classID,
          subclassID =
        C_Item.GetItemInfoInstant(item)

    return {
        itemID = itemID,
        itemType = itemType,
        itemSubType = itemSubType,
        equipLoc = itemEquipLoc,
        classID = classID,
        subclassID = subclassID,
    }
end

function CreateItemObject(item)
    if not item or not Item then
        return nil
    end

    if type(item) == "number" then
        return Item:CreateFromItemID(item)
    end

    if type(item) == "string" then
        if item:find("|Hitem:")
            or item:find("^item:")
        then
            return Item:CreateFromItemLink(item)
        end

        local itemID = tonumber(item)

        if itemID then
            return Item:CreateFromItemID(itemID)
        end
    end

    return nil
end

function WGRGetItemID(
    item
)
    if not item then
        return nil
    end

    if type(item) == "number" then
        return item
    end

    if C_Item
        and C_Item.GetItemInfoInstant
    then
        local itemID =
            C_Item.GetItemInfoInstant(
                item
            )

        if itemID then
            return itemID
        end
    end

    return tonumber(
        tostring(item):match(
            "item:(%d+)"
        )
    )
end

function WGRItemIsIgnored(
    item
)
    InitializeDatabase()

    local itemID =
        WGRGetItemID(
            item
        )

    if not itemID then
        return false
    end

    return
        WarboundGearRouterDB.eligibleGear.ignoredItems[
            tostring(itemID)
        ]
        ~= nil
end

function WGRGetIgnoredItems()
    InitializeDatabase()

    local result = {}

    for _, entry
        in pairs(
            WarboundGearRouterDB.eligibleGear.ignoredItems
            or {}
        )
    do
        result[
            #result + 1
        ] =
            entry
    end

    table.sort(
        result,
        function(a, b)
            return
                string.lower(
                    tostring(
                        a.name
                        or a.itemID
                        or ""
                    )
                )
                <
                string.lower(
                    tostring(
                        b.name
                        or b.itemID
                        or ""
                    )
                )
        end
    )

    return result
end

function WGRSetItemIgnored(
    item,
    ignored,
    lastKnownLocation
)
    InitializeDatabase()

    local itemID =
        WGRGetItemID(
            item
        )

    if not itemID then
        return false
    end

    local key =
        tostring(itemID)

    if ignored then
        local itemName,
              itemLink =
            C_Item.GetItemInfo(
                item
            )

        local existing =
            WarboundGearRouterDB.eligibleGear.ignoredItems[
                key
            ]
            or {}

        WarboundGearRouterDB.eligibleGear.ignoredItems[
            key
        ] = {
            itemID =
                itemID,
            name =
                itemName
                or existing.name
                or (
                    "Item "
                    .. tostring(itemID)
                ),
            itemLink =
                itemLink
                or existing.itemLink
                or (
                    type(item) == "string"
                    and item
                    or nil
                ),
            lastKnownLocation =
                lastKnownLocation
                or existing.lastKnownLocation,
        }
    else
        WarboundGearRouterDB.eligibleGear.ignoredItems[
            key
        ] =
            nil
    end

    if WGRAddRecentActivity then
        local actionText =
            ignored
            and " ignored "
            or " stopped ignoring "

        local entry =
            WarboundGearRouterDB.eligibleGear.ignoredItems[
                key
            ]

        local itemName =
            (
                entry
                and entry.name
            )
            or (
                C_Item.GetItemInfo(
                    item
                )
            )
            or (
                "Item "
                .. tostring(itemID)
            )

        WGRAddRecentActivity(
            tostring(
                UnitName("player")
                or "Current character"
            )
            .. actionText
            .. tostring(itemName)
            .. ".",
            ignored
                and "ITEM_IGNORED"
                or "ITEM_UNIGNORED"
        )
    end

    if RefreshBagnonCleanupOverlays then
        RefreshBagnonCleanupOverlays()
    end

    if WGRScheduleGearFinderRefresh then
        WGRScheduleGearFinderRefresh(
            0.05
        )
    end

    if WGRRefreshIgnoredItemsUI then
        WGRRefreshIgnoredItemsUI()
    end

    return true
end

function WGRBindingAllowed(
    isWarbound,
    isBoE
)
    InitializeDatabase()

    local settings =
        WarboundGearRouterDB.eligibleGear

    return
        (isWarbound and settings.warbound)
        or (isBoE and settings.boe)
end

function WGRItemIsCosmetic(
    item
)
    if not item then
        return false
    end

    -- Blizzard exposes an explicit cosmetic predicate. This catches
    -- appearance-only weapon/armor items that still report ordinary
    -- weapon/armor class, subtype, and equip-location metadata.
    if C_Item
        and C_Item.IsCosmeticItem
    then
        local isCosmetic =
            C_Item.IsCosmeticItem(
                item
            )

        if isCosmetic then
            return true
        end
    end

    -- Keep the metadata checks as a fallback for older/unusual items.
    local info =
        GetInstantItemInfo(
            item
        )

    if not info then
        return false
    end

    local itemType =
        string.lower(
            tostring(
                info.itemType
                or ""
            )
        )

    local itemSubType =
        string.lower(
            tostring(
                info.itemSubType
                or ""
            )
        )

    if info.equipLoc == "INVTYPE_COSMETIC"
        or itemType == "cosmetic"
        or itemSubType == "cosmetic"
    then
        return true
    end

    local armorClassID =
        Enum
        and Enum.ItemClass
        and Enum.ItemClass.Armor
        or 4

    local cosmeticSubclassID =
        Enum
        and Enum.ItemArmorSubclass
        and Enum.ItemArmorSubclass.Cosmetic
        or 5

    return info.classID == armorClassID
        and info.subclassID == cosmeticSubclassID
end

function WGRQualityAllowed(
    itemLink
)
    InitializeDatabase()

    if WGRItemIsIgnored(
        itemLink
    )
    then
        return false
    end

    -- Cosmetic-only items are collection pieces, not gearing candidates.
    -- Exclude them centrally so Gear Finder, Gear Search snapshots, mail
    -- routing, tooltips, and overlays all agree on the same eligibility.
    if WGRItemIsCosmetic
        and WGRItemIsCosmetic(
            itemLink
        )
    then
        return false
    end

    local _, _, quality =
        C_Item.GetItemInfo(
            itemLink
        )

    if quality == nil then
        return false
    end

    return quality
        >= (
            WarboundGearRouterDB.eligibleGear.minimumQuality
            or 2
        )
end

function IsTransferableGearTooltip(
    tooltip,
    itemLink
)
    if not tooltip
        or not tooltip:IsShown()
    then
        return false
    end

    if itemLink
        and not WGRQualityAllowed(
            itemLink
        )
    then
        return false
    end

    local sawWarbound = false
    local sawBoE = false

    local function CheckText(
        text
    )
        if not text then
            return nil
        end

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
            return "SOULBOUND"
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

        return nil
    end

    -- Prefer Blizzard's structured tooltip data. Unlike named FontString
    -- scraping, this works regardless of whether the tooltip was opened by
    -- bags, Personal Bank, Warband Bank, or another standard item owner.
    if type(tooltip.GetTooltipData)
        == "function"
    then
        local ok,
              data =
            pcall(
                tooltip.GetTooltipData,
                tooltip
            )

        if ok
            and data
            and data.lines
        then
            if TooltipUtil
                and TooltipUtil.SurfaceArgs
            then
                pcall(
                    TooltipUtil.SurfaceArgs,
                    data
                )
            end

            for _, line
                in ipairs(
                    data.lines
                )
            do
                if TooltipUtil
                    and TooltipUtil.SurfaceArgs
                then
                    pcall(
                        TooltipUtil.SurfaceArgs,
                        line
                    )
                end

                for _, text
                    in ipairs({
                        line.leftText,
                        line.rightText,
                    })
                do
                    if CheckText(text)
                        == "SOULBOUND"
                    then
                        -- Soulbound is a definitive routing exclusion, not a
                        -- temporary tooltip-data miss. Return a reason so the
                        -- tooltip layer does not schedule RefreshData retries.
                        return false, "SOULBOUND"
                    end
                end
            end

            return WGRBindingAllowed(
                sawWarbound,
                sawBoE
            )
        end
    end

    -- Compatibility fallback for older/custom tooltip implementations.
    local tooltipName =
        tooltip:GetName()

    if not tooltipName then
        return false
    end

    local numLines =
        tooltip:NumLines()
        or 0

    for i = 1, numLines do
        local leftLine =
            _G[
                tooltipName
                .. "TextLeft"
                .. i
            ]

        local rightLine =
            _G[
                tooltipName
                .. "TextRight"
                .. i
            ]

        for _, text
            in ipairs({
                leftLine
                    and leftLine:GetText(),
                rightLine
                    and rightLine:GetText(),
            })
        do
            if CheckText(text)
                == "SOULBOUND"
            then
                -- Same definitive exclusion for compatibility tooltip parsing.
                return false, "SOULBOUND"
            end
        end
    end

    return WGRBindingAllowed(
        sawWarbound,
        sawBoE
    )
end

function GetHoveredItem()
    if not GameTooltip
        or not GameTooltip:IsShown()
    then
        return nil
    end

    local _, itemLink = GameTooltip:GetItem()

    return itemLink
end
