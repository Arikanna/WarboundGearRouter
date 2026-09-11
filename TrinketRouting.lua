-- Per-spec trinket baseline capture, inheritance, and routing comparison.
-- Trinkets are spec-sensitive: Blizzard's item-spec data determines which
-- specializations can use a trinket, while each specialization keeps its own
-- two-slot baseline. Once physical Soulbound ownership has been observed,
-- routing derives the target spec's best legal pair from EQ/BAG/PBK; saved
-- per-spec history remains a bootstrap fallback only.

local function WGRGetLiveTrinketLevel(itemLink)
    if not itemLink then
        return 0
    end

    local level =
        C_Item
        and C_Item.GetDetailedItemLevelInfo
        and C_Item.GetDetailedItemLevelInfo(itemLink)
        or GetItemLevel(itemLink)

    return tonumber(level) or 0
end

local function WGRTrinketFitsSpecificSpec(itemLink, classID, specID)
    if not itemLink then
        return false
    end

    if WGRItemFitsSpecificSpec then
        return WGRItemFitsSpecificSpec(
            itemLink,
            classID,
            specID
        )
    end

    if not C_Item
        or not C_Item.DoesItemContainSpec
    then
        return nil
    end

    local ok, result =
        pcall(
            C_Item.DoesItemContainSpec,
            itemLink,
            classID,
            specID
        )

    if not ok then
        return nil
    end

    return result == true
end

-- Capture Blizzard's spec-eligibility result while the owning character is
-- actually online. Offline item-link queries can disagree with the live
-- character context (observed with Arikthyr), so the physical ownership cache
-- stores these true/false results alongside each Soulbound trinket.
function WGRGetLiveTrinketSpecEligibilitySnapshot(itemLink, classID)
    local result = {}
    local specIDs =
        WGRClassSpecIDs
        and WGRClassSpecIDs[classID]
        or nil

    if not itemLink or not classID or not specIDs then
        return result, false
    end

    local complete = true
    local sawKnown = false

    for _, routedSpecID in ipairs(specIDs) do
        local fits =
            WGRTrinketFitsSpecificSpec(
                itemLink,
                classID,
                routedSpecID
            )

        if fits == nil then
            complete = false
        else
            result[tostring(routedSpecID)] = fits == true
            sawKnown = true
        end
    end

    return result, complete and sawKnown
end

local function WGRGetOwnedTrinketCachedSpecFit(
    data,
    itemLink,
    classID,
    specID,
    characterName
)
    local eligibility =
        data
        and data.specEligibility
        or nil

    if type(eligibility) == "table" then
        local stored = eligibility[tostring(specID)]
        if stored ~= nil then
            return stored == true
        end
    end

    -- Missing cached eligibility may be resolved directly only while this is
    -- the current live character. For an offline character, do not reconstruct
    -- spec eligibility from an item link; that was the source of the v0.65t
    -- Preservation->Devastation false-positive inheritance.
    local currentName =
        UnitName
        and UnitName("player")
        or nil

    if currentName
        and string.lower(tostring(currentName))
            == string.lower(tostring(characterName or ""))
    then
        return WGRTrinketFitsSpecificSpec(
            itemLink,
            classID,
            specID
        )
    end

    return nil
end

function WGRSaveLiveTrinketBaselineForSpec(
    characterName,
    specID,
    specName,
    classID
)
    InitializeDatabase()

    if not characterName
        or not specID
        or not classID
    then
        return false
    end

    local characterKey =
        string.lower(characterName)

    WarboundGearRouterDB.specTrinketBaselines[
        characterKey
    ] =
        WarboundGearRouterDB.specTrinketBaselines[
            characterKey
        ]
        or {}

    local captured = {}

    for _, slotID in ipairs({ 13, 14 }) do
        local itemLink =
            GetInventoryItemLink(
                "player",
                slotID
            )

        if itemLink then
            local fits =
                WGRTrinketFitsSpecificSpec(
                    itemLink,
                    classID,
                    specID
                )

            -- If Blizzard has not finished exposing item/spec data, do not
            -- overwrite a previously useful baseline with uncertain data.
            if fits == nil then
                return false
            end

            if fits == true then
                local level =
                    WGRGetLiveTrinketLevel(
                        itemLink
                    )

                if level <= 0 then
                    return false
                end

                captured[#captured + 1] = {
                    item = itemLink,
                    level = level,
                    sourceSlot = slotID,
                }
            end
        end
    end

    table.sort(
        captured,
        function(a, b)
            return a.level > b.level
        end
    )

    local first = captured[1]
    local second = captured[2]

    WarboundGearRouterDB.specTrinketBaselines[
        characterKey
    ][tostring(specID)] = {
        specID = specID,
        specName = specName,
        trinket1 = first and first.item or nil,
        trinket1Level = first and first.level or 0,
        trinket1SourceSlot = first and first.sourceSlot or nil,
        trinket2 = second and second.item or nil,
        trinket2Level = second and second.level or 0,
        trinket2SourceSlot = second and second.sourceSlot or nil,
        updated = time(),
    }

    return true
end

function WGRGetSpecTrinketBaseline(
    characterName,
    specID
)
    InitializeDatabase()

    if not characterName
        or not specID
    then
        return nil
    end

    local byCharacter =
        WarboundGearRouterDB.specTrinketBaselines[
            string.lower(characterName)
        ]

    return byCharacter
        and byCharacter[tostring(specID)]
        or nil
end

local function WGRAddCompatibleTrinketCandidate(
    candidates,
    seen,
    itemLink,
    level,
    sourceSlot,
    classID,
    targetSpecID
)
    level = tonumber(level) or 0

    if not itemLink
        or level <= 0
    then
        return
    end

    local fits =
        WGRTrinketFitsSpecificSpec(
            itemLink,
            classID,
            targetSpecID
        )

    if fits ~= true then
        return
    end

    -- The same physical trinket is commonly recorded under several specs.
    -- Do not let duplicate snapshots of one physical slot falsely fill both
    -- trinket positions during inheritance. Two real identical copies are
    -- allowed when they were captured in different equipped slots (13/14).
    local key =
        tostring(itemLink)
        .. ":"
        .. tostring(level)

    if sourceSlot ~= nil then
        key =
            key
            .. ":slot:"
            .. tostring(sourceSlot)
    end

    if seen[key] then
        return
    end

    seen[key] = true

    candidates[#candidates + 1] = {
        item = itemLink,
        level = level,
        sourceSlot = sourceSlot,
    }
end

local function WGRBuildDataStoreTrinketBaseline(
    characterName,
    character,
    specID
)
    if not characterName
        or not character
        or not specID
    then
        return nil
    end

    -- Only bootstrap a spec that WGR already remembers as this character's
    -- current/last-seen spec. Off-specs must remain 0 until they are actually
    -- observed or can inherit compatible learned trinkets from another spec.
    local remembered =
        GetRememberedSpec(
            characterName
        )

    if not remembered
        or tonumber(
            remembered.specID
        ) ~= tonumber(
            specID
        )
    then
        return nil
    end

    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    if not classID then
        return nil
    end

    local captured = {}

    for _, slotID in ipairs({ 13, 14 }) do
        local itemLink =
            GetStoredItem(
                character,
                slotID
            )

        if itemLink then
            local fits =
                WGRTrinketFitsSpecificSpec(
                    itemLink,
                    classID,
                    specID
                )

            if fits == nil then
                return nil
            end

            if fits == true then
                local level =
                    GetItemLevel(
                        itemLink
                    )

                if not level
                    or level <= 0
                then
                    return nil
                end

                captured[#captured + 1] = {
                    item = itemLink,
                    level = level,
                    sourceSlot = slotID,
                }
            end
        end
    end

    table.sort(
        captured,
        function(a, b)
            return a.level > b.level
        end
    )

    local first = captured[1]
    local second = captured[2]

    return {
        specID = specID,
        specName =
            remembered.specName,
        trinket1 =
            first
            and first.item
            or nil,
        trinket1Level =
            first
            and first.level
            or 0,
        trinket1SourceSlot =
            first
            and first.sourceSlot
            or nil,
        trinket2 =
            second
            and second.item
            or nil,
        trinket2Level =
            second
            and second.level
            or 0,
        trinket2SourceSlot =
            second
            and second.sourceSlot
            or nil,
        dataStoreBootstrap =
            true,
    }
end



local function WGRGetTrinketIdentity(
    itemLink,
    level
)
    if not itemLink then
        return nil
    end

    local itemID = nil

    if C_Item
        and C_Item.GetItemInfoInstant
    then
        local ok,
              returnedID =
            pcall(
                C_Item.GetItemInfoInstant,
                itemLink
            )

        if ok then
            itemID =
                tonumber(
                    returnedID
                )
        end
    end

    if not itemID then
        itemID =
            tonumber(
                string.match(
                    tostring(itemLink),
                    "item:(%d+)"
                )
            )
    end

    -- Keep different upgrade/ilevel versions distinct while collapsing
    -- duplicate saved snapshots of the same actual trinket version.
    return tostring(
        itemID
        or itemLink
    )
        .. ":"
        .. tostring(
            tonumber(level)
            or 0
        )
end

local function WGRAccumulateTrinketBaselineForTarget(
    groups,
    baseline,
    classID,
    targetSpecID
)
    if type(baseline) ~= "table" then
        return
    end

    local localCounts = {}
    local entries = {
        {
            item = baseline.trinket1,
            level = baseline.trinket1Level,
        },
        {
            item = baseline.trinket2,
            level = baseline.trinket2Level,
        },
    }

    for _, entry
        in ipairs(
            entries
        )
    do
        local level =
            tonumber(
                entry.level
            )
            or 0

        if entry.item
            and level > 0
        then
            local fits =
                WGRTrinketFitsSpecificSpec(
                    entry.item,
                    classID,
                    targetSpecID
                )

            if fits == true then
                local identity =
                    WGRGetTrinketIdentity(
                        entry.item,
                        level
                    )

                if identity then
                    localCounts[identity] =
                        (
                            localCounts[identity]
                            or 0
                        )
                        + 1

                    local group =
                        groups[identity]

                    if not group then
                        group = {
                            item = entry.item,
                            level = level,
                            maxCopies = 0,
                        }
                        groups[identity] =
                            group
                    elseif level
                        > (
                            tonumber(
                                group.level
                            )
                            or 0
                        )
                    then
                        group.item =
                            entry.item
                        group.level =
                            level
                    end
                end
            end
        end
    end

    for identity, count
        in pairs(
            localCounts
        )
    do
        local group =
            groups[identity]

        if group
            and count
                > (
                    tonumber(
                        group.maxCopies
                    )
                    or 0
                )
        then
            group.maxCopies =
                count
        end
    end
end


local function WGRGetHistoricalResolvedSpecTrinketLevels(
    characterName,
    character,
    specID
)
    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    if not classID
        or not specID
    then
        return 0, 0
    end

    InitializeDatabase()

    local byCharacter =
        WarboundGearRouterDB.specTrinketBaselines[
            string.lower(characterName)
        ]
        or {}

    local own =
        byCharacter[
            tostring(specID)
        ]

    if not own then
        own =
            WGRBuildDataStoreTrinketBaseline(
                characterName,
                character,
                specID
            )
    end

    -- A trinket may be inherited across multiple compatible specs, but
    -- duplicate snapshots of the same physical copy must not create a
    -- second slot. For each item+ilevel identity, only allow as many copies
    -- as were ever observed together in one saved spec baseline. Thus one
    -- All-Roles trinket saved under Holy and Ret remains one copy, while two
    -- identical non-unique trinkets captured together can legitimately fill
    -- both positions.
    local groups = {}

    if own then
        WGRAccumulateTrinketBaselineForTarget(
            groups,
            own,
            classID,
            specID
        )
    end

    for sourceSpecKey, baseline
        in pairs(
            byCharacter
        )
    do
        if sourceSpecKey
                ~= tostring(specID)
            and type(baseline)
                == "table"
        then
            WGRAccumulateTrinketBaselineForTarget(
                groups,
                baseline,
                classID,
                specID
            )
        end
    end

    local candidates = {}

    for _, group
        in pairs(
            groups
        )
    do
        local copies =
            math.max(
                0,
                tonumber(
                    group.maxCopies
                )
                or 0
            )

        for _ = 1, copies do
            candidates[
                #candidates + 1
            ] = {
                item = group.item,
                level =
                    tonumber(
                        group.level
                    )
                    or 0,
            }
        end
    end

    table.sort(
        candidates,
        function(a, b)
            return
                (
                    tonumber(
                        a.level
                    )
                    or 0
                )
                >
                (
                    tonumber(
                        b.level
                    )
                    or 0
                )
        end
    )

    return
        candidates[1]
            and candidates[1].level
            or 0,
        candidates[2]
            and candidates[2].level
            or 0
end


-- ============================================================
-- PHYSICALLY OWNED SOULBOUND TRINKET ROUTING FLOOR (v0.65t)
-- ============================================================
-- Historical per-spec trinket snapshots are useful bootstrap/history, but
-- they are not proof that a trinket is still physically owned. Once WBGR has
-- observed a character's Soulbound trinkets, routing derives each spec's
-- baseline from that physical pool (EQ/BAG/PBK), filtered again for the
-- target spec. This mirrors the owned-weapon safety model.

local WGRTrinketUniqueEquippedCache = {}

local function WGRGetTrinketItemID(itemLink)
    if not itemLink then return nil end

    local instant = GetInstantItemInfo and GetInstantItemInfo(itemLink) or nil
    if instant and instant.itemID then
        return tonumber(instant.itemID)
    end

    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, itemLink)
        if ok and itemID then return tonumber(itemID) end
    end

    return tonumber(tostring(itemLink):match("item:(%d+)"))
end

local function WGRTrinketIsUniqueEquipped(itemLink)
    if not itemLink then return false end

    local itemID = WGRGetTrinketItemID(itemLink)
    local cacheKey = itemID and ("id:" .. tostring(itemID)) or tostring(itemLink)
    local cached = WGRTrinketUniqueEquippedCache[cacheKey]
    if cached ~= nil then return cached == true end

    local unique = false
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, itemLink)
        if ok and data and data.lines then
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
                            unique = true
                            break
                        end
                    end
                end

                if unique then break end
            end
        end
    end

    WGRTrinketUniqueEquippedCache[cacheKey] = unique and true or false
    return unique
end

local function WGRTrinketOwnedSourceLabel(record)
    if not record then return "Owned" end
    if record.slotID then
        return "Owned EQ" .. tostring(record.slotID)
    end
    if record.sourceGroup == "PBK" then
        return "Owned PBK"
    end
    if record.sourceGroup == "BAG" then
        return "Owned BAG"
    end
    return "Owned"
end

local function WGRBuildOwnedTrinketCandidatesForSpec(
    characterName,
    character,
    specID
)
    InitializeDatabase()

    local key = string.lower(tostring(characterName or ""))
    local ownedTable = WarboundGearRouterDB.ownedTrinketComponents
    local owned = ownedTable and ownedTable[key] or nil
    if type(owned) ~= "table" then
        return nil, false
    end

    local observed = owned.equippedObserved == true
        or owned.bagsObserved == true
        or owned.bankObserved == true
    if not observed then
        return nil, false
    end

    local classID = GetCharacterClassID(characterName, character)
    if not classID then
        return {}, true
    end

    local candidates = {}
    local unresolvedEligibility = false

    local function add(list, sourceGroup)
        for _, data in ipairs(list or {}) do
            local link = data and data.link or nil
            local level = tonumber(data and data.level) or 0
            if link and level > 0 then
                local fits =
                    WGRGetOwnedTrinketCachedSpecFit(
                        data,
                        link,
                        classID,
                        specID,
                        characterName
                    )

                if fits == nil then
                    unresolvedEligibility = true
                elseif fits == true then
                    candidates[#candidates + 1] = {
                        item = link,
                        level = level,
                        itemID = WGRGetTrinketItemID(link),
                        uniqueEquipped = WGRTrinketIsUniqueEquipped(link),
                        sourceGroup = sourceGroup,
                        slotID = data.slotID,
                        bagID = data.bagID,
                        bagSlotID = data.slotID,
                        specEligibility = data.specEligibility,
                        sources = { sourceGroup == "EQ"
                            and ("Owned EQ" .. tostring(data.slotID or "?"))
                            or sourceGroup == "PBK"
                            and "Owned PBK"
                            or "Owned BAG" },
                    }
                end
            end
        end
    end

    add(owned.equipped, "EQ")
    add(owned.bags, "BAG")
    add(owned.bank, "PBK")

    -- If any cached physical trinket lacks a trustworthy eligibility answer
    -- for this spec and the character is offline, fall back to historical
    -- resolution rather than manufacturing an owned baseline from uncertain
    -- item-link data. A fresh live scan will replace this state.
    if unresolvedEligibility then
        local currentName =
            UnitName
            and UnitName("player")
            or nil

        if not currentName
            or string.lower(tostring(currentName))
                ~= string.lower(tostring(characterName or ""))
        then
            return nil, false
        end
    end

    return candidates, true
end

local function WGRTrinketPairIsLegal(a, b)
    if not a or not b then return true end

    local aID = a.itemID or WGRGetTrinketItemID(a.item)
    local bID = b.itemID or WGRGetTrinketItemID(b.item)

    if aID and bID and aID == bID
        and (a.uniqueEquipped == true or b.uniqueEquipped == true)
    then
        return false
    end

    return true
end

local function WGRNormalizeTrinketPair(first, second)
    if first and second
        and (tonumber(second.level) or 0) > (tonumber(first.level) or 0)
    then
        first, second = second, first
    end
    return first, second
end

local function WGRPairBeats(a1, a2, b1, b2)
    local aHigh = math.max(
        tonumber(a1 and a1.level) or 0,
        tonumber(a2 and a2.level) or 0
    )
    local aLow = math.min(
        tonumber(a1 and a1.level) or 0,
        tonumber(a2 and a2.level) or 0
    )
    local bHigh = math.max(
        tonumber(b1 and b1.level) or 0,
        tonumber(b2 and b2.level) or 0
    )
    local bLow = math.min(
        tonumber(b1 and b1.level) or 0,
        tonumber(b2 and b2.level) or 0
    )

    local aTotal = aHigh + aLow
    local bTotal = bHigh + bLow
    if aTotal ~= bTotal then return aTotal > bTotal end
    if aHigh ~= bHigh then return aHigh > bHigh end
    return aLow > bLow
end

local function WGRSelectBestOwnedTrinketPair(candidates)
    local best1, best2 = nil, nil

    for i, first in ipairs(candidates or {}) do
        if not best1 or WGRPairBeats(first, nil, best1, best2) then
            best1, best2 = first, nil
        end

        for j = i + 1, #(candidates or {}) do
            local second = candidates[j]
            if WGRTrinketPairIsLegal(first, second)
                and (
                    not best1
                    or WGRPairBeats(first, second, best1, best2)
                )
            then
                best1, best2 = first, second
            end
        end
    end

    return WGRNormalizeTrinketPair(best1, best2)
end

local function WGRSelectBestPairRequiringIncoming(ownedCandidates, incoming)
    local best1, best2 = incoming, nil

    for _, partner in ipairs(ownedCandidates or {}) do
        if WGRTrinketPairIsLegal(incoming, partner)
            and WGRPairBeats(incoming, partner, best1, best2)
        then
            best1, best2 = incoming, partner
        end
    end

    return WGRNormalizeTrinketPair(best1, best2)
end

local function WGRGetOwnedSpecTrinketPair(
    characterName,
    character,
    specID
)
    local candidates, observed =
        WGRBuildOwnedTrinketCandidatesForSpec(
            characterName,
            character,
            specID
        )

    if not observed then
        return nil, nil, false, nil
    end

    local first, second = WGRSelectBestOwnedTrinketPair(candidates)
    return first, second, true, candidates
end

-- Public resolved baseline. Once physical Soulbound ownership has been
-- observed, it is authoritative for routing/Gear Finder. Historical per-spec
-- records remain a fallback for characters not yet observed by this system.
function WGRGetResolvedSpecTrinketLevels(
    characterName,
    character,
    specID
)
    local first, second, observed =
        WGRGetOwnedSpecTrinketPair(
            characterName,
            character,
            specID
        )

    if observed then
        return
            first and (tonumber(first.level) or 0) or 0,
            second and (tonumber(second.level) or 0) or 0
    end

    return WGRGetHistoricalResolvedSpecTrinketLevels(
        characterName,
        character,
        specID
    )
end


-- Diagnostic-only provenance view of the existing trinket resolver. This
-- deliberately mirrors WGRGetResolvedSpecTrinketLevels without changing the
-- routing result. It exists so test builds can show which saved spec record
-- supplied each resolved trinket candidate.
function WGRGetResolvedSpecTrinketDiagnosticDetails(
    characterName,
    character,
    specID
)
    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    if not classID or not specID then
        return nil
    end

    InitializeDatabase()

    local ownedFirst, ownedSecond, ownedObserved, ownedCandidates =
        WGRGetOwnedSpecTrinketPair(
            characterName,
            character,
            specID
        )

    if ownedObserved then
        return {
            first = ownedFirst,
            second = ownedSecond,
            candidates = ownedCandidates or {},
            usedOwned = true,
        }
    end

    local byCharacter =
        WarboundGearRouterDB.specTrinketBaselines[
            string.lower(characterName)
        ]
        or {}

    local targetKey = tostring(specID)
    local own = byCharacter[targetKey]
    local ownIsDataStore = false

    if not own then
        own = WGRBuildDataStoreTrinketBaseline(
            characterName,
            character,
            specID
        )
        ownIsDataStore = own ~= nil
    end

    local groups = {}

    local function AddSource(group, label)
        group.sources = group.sources or {}
        group.sourceSeen = group.sourceSeen or {}
        if label and not group.sourceSeen[label] then
            group.sourceSeen[label] = true
            group.sources[#group.sources + 1] = label
        end
    end

    local function Accumulate(
        baseline,
        sourceSpecID,
        sourceLabel
    )
        if type(baseline) ~= "table" then
            return
        end

        local localCounts = {}
        local entries = {
            {
                item = baseline.trinket1,
                level = baseline.trinket1Level,
                sourceSlot = baseline.trinket1SourceSlot,
            },
            {
                item = baseline.trinket2,
                level = baseline.trinket2Level,
                sourceSlot = baseline.trinket2SourceSlot,
            },
        }

        for _, entry in ipairs(entries) do
            local level = tonumber(entry.level) or 0
            if entry.item and level > 0 then
                local fits =
                    WGRTrinketFitsSpecificSpec(
                        entry.item,
                        classID,
                        specID
                    )

                if fits == true then
                    local identity =
                        WGRGetTrinketIdentity(
                            entry.item,
                            level
                        )

                    if identity then
                        localCounts[identity] =
                            (localCounts[identity] or 0) + 1

                        local group = groups[identity]
                        if not group then
                            group = {
                                item = entry.item,
                                level = level,
                                maxCopies = 0,
                                slots = {},
                            }
                            groups[identity] = group
                        elseif level > (tonumber(group.level) or 0) then
                            group.item = entry.item
                            group.level = level
                        end

                        if entry.sourceSlot then
                            group.slots[tostring(entry.sourceSlot)] = true
                        end

                        AddSource(group, sourceLabel)
                    end
                end
            end
        end

        for identity, count in pairs(localCounts) do
            local group = groups[identity]
            if group and count > (tonumber(group.maxCopies) or 0) then
                group.maxCopies = count
            end
        end
    end

    if own then
        local targetName =
            WGRSpecNamesByID[specID]
            or tostring(specID)
        local label =
            ownIsDataStore
            and ("DataStore " .. targetName)
            or ("Direct " .. targetName)
        Accumulate(own, specID, label)
    end

    for sourceSpecKey, baseline in pairs(byCharacter) do
        if sourceSpecKey ~= targetKey
            and type(baseline) == "table"
        then
            local sourceSpecID =
                tonumber(sourceSpecKey)
                or tonumber(baseline.specID)
            local sourceName =
                (sourceSpecID and WGRSpecNamesByID[sourceSpecID])
                or baseline.specName
                or tostring(sourceSpecKey)
            Accumulate(
                baseline,
                sourceSpecID,
                "Inherited " .. tostring(sourceName)
            )
        end
    end

    local candidates = {}
    for _, group in pairs(groups) do
        local copies = math.max(0, tonumber(group.maxCopies) or 0)
        table.sort(group.sources or {})
        for _ = 1, copies do
            candidates[#candidates + 1] = {
                item = group.item,
                level = tonumber(group.level) or 0,
                sources = group.sources or {},
                slots = group.slots or {},
            }
        end
    end

    table.sort(
        candidates,
        function(a, b)
            local aLevel = tonumber(a.level) or 0
            local bLevel = tonumber(b.level) or 0
            if aLevel ~= bLevel then
                return aLevel > bLevel
            end
            return tostring(a.item or "") < tostring(b.item or "")
        end
    )

    return {
        first = candidates[1],
        second = candidates[2],
        candidates = candidates,
        usedDataStore = ownIsDataStore,
    }
end

-- Shortest unambiguous specialization abbreviation within a class. This is
-- intentionally more compact than the Roster labels because trinket tooltip
-- lines may need to show several specs at once (H/P/R, EL/EN/R, DEM/DES, etc.).
function WGRGetCompactSpecAbbreviation(
    classID,
    specID
)
    local specName =
        WGRSpecNamesByID[specID]
        or tostring(specID)

    local classSpecs =
        WGRClassSpecIDs
        and WGRClassSpecIDs[classID]
        or nil

    if not classSpecs then
        return tostring(specName)
    end

    local lowerName = string.lower(tostring(specName))
    for prefixLength = 1, #specName do
        local prefix = string.sub(lowerName, 1, prefixLength)
        local unique = true

        for _, otherSpecID in ipairs(classSpecs) do
            if tonumber(otherSpecID) ~= tonumber(specID) then
                local otherName =
                    WGRSpecNamesByID[otherSpecID]
                    or tostring(otherSpecID)
                local otherPrefix =
                    string.sub(
                        string.lower(tostring(otherName)),
                        1,
                        prefixLength
                    )
                if otherPrefix == prefix then
                    unique = false
                    break
                end
            end
        end

        if unique then
            return string.upper(
                string.sub(tostring(specName), 1, prefixLength)
            )
        end
    end

    return tostring(specName)
end

-- Tooltip-only multi-spec breakdown. This reads the same per-spec comparison
-- functions routing already uses, but never changes a routing decision.
-- Compact spec-eligibility summary for optional Soulbound trinket tooltips.
-- This is informational only: it uses the current character's effective
-- Current/All/Custom spec selection and never changes routing state.
function WGRGetTrinketSpecSummary(
    characterName,
    character,
    itemLink
)
    if not characterName
        or not character
        or not itemLink
    then
        return nil
    end

    local classID =
        GetCharacterClassID(
            characterName,
            character
        )
    if not classID then
        return nil
    end

    local specIDs =
        WGRGetRoutingSpecIDs(
            characterName,
            character
        )
        or {}

    local entries = {}
    for _, routedSpecID in ipairs(specIDs) do
        local fits =
            WGRTrinketFitsSpecificSpec(
                itemLink,
                classID,
                routedSpecID
            )

        if fits == true then
            entries[#entries + 1] = {
                specID = routedSpecID,
                specName =
                    WGRSpecNamesByID[routedSpecID]
                    or tostring(routedSpecID),
                abbreviation =
                    WGRGetCompactSpecAbbreviation(
                        classID,
                        routedSpecID
                    ),
            }
        end
    end

    if #entries == 0 then
        return nil
    end

    table.sort(
        entries,
        function(a, b)
            return string.lower(tostring(a.specName))
                < string.lower(tostring(b.specName))
        end
    )

    local labels = {}
    for _, entry in ipairs(entries) do
        labels[#labels + 1] = entry.abbreviation
    end

    return table.concat(labels, "/")
end

-- Backward-compatible name used by the optional Soulbound tooltip setting.
-- The eligibility summary itself is useful for any trinket tooltip/routing
-- context, not just Soulbound items.
function WGRGetSoulboundTrinketSpecSummary(
    characterName,
    character,
    itemLink
)
    return WGRGetTrinketSpecSummary(
        characterName,
        character,
        itemLink
    )
end

function WGRGetTrinketTooltipUpgradeSummary(
    characterName,
    character,
    itemLink,
    itemLevel
)
    if not characterName
        or not character
        or not itemLink
    then
        return nil
    end

    local classID =
        GetCharacterClassID(
            characterName,
            character
        )
    if not classID then
        return nil
    end

    local specIDs =
        WGRGetRoutingSpecIDs(
            characterName,
            character
        )
        or {}

    local newLevel =
        tonumber(itemLevel)
        or tonumber(GetItemLevel(itemLink))
        or 0
    if newLevel <= 0 then
        return nil
    end

    local entries = {}
    for _, routedSpecID in ipairs(specIDs) do
        local fits =
            WGRTrinketFitsSpecificSpec(
                itemLink,
                classID,
                routedSpecID
            )

        if fits == true then
            local comparison, status =
                WGRGetSpecificSpecTrinketComparisonLevel(
                    characterName,
                    character,
                    itemLink,
                    routedSpecID
                )

            if status == "known"
                and type(comparison) == "number"
            then
                entries[#entries + 1] = {
                    specID = routedSpecID,
                    specName =
                        WGRSpecNamesByID[routedSpecID]
                        or tostring(routedSpecID),
                    abbreviation =
                        WGRGetCompactSpecAbbreviation(
                            classID,
                            routedSpecID
                        ),
                    upgrade = newLevel - comparison,
                }
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    table.sort(
        entries,
        function(a, b)
            return string.lower(tostring(a.specName))
                < string.lower(tostring(b.specName))
        end
    )

    local groups = {}
    local byUpgrade = {}
    for _, entry in ipairs(entries) do
        local key = tostring(entry.upgrade)
        local group = byUpgrade[key]
        if not group then
            group = {
                upgrade = entry.upgrade,
                labels = {},
                firstSpecName = entry.specName,
            }
            byUpgrade[key] = group
            groups[#groups + 1] = group
        end
        group.labels[#group.labels + 1] = entry.abbreviation
    end

    table.sort(
        groups,
        function(a, b)
            return string.lower(tostring(a.firstSpecName))
                < string.lower(tostring(b.firstSpecName))
        end
    )

    local parts = {}
    for _, group in ipairs(groups) do
        local delta = tonumber(group.upgrade) or 0
        local deltaText =
            delta > 0
            and ("+" .. tostring(delta))
            or tostring(delta)

        parts[#parts + 1] =
            table.concat(group.labels, "/")
            .. " "
            .. deltaText
    end

    return table.concat(parts, ", ") .. " ilvl"
end

function WGRGetSpecificSpecTrinketComparisonLevel(
    characterName,
    character,
    itemLink,
    specID
)
    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    if not classID
        or not specID
    then
        return nil, "unknown"
    end

    local fits =
        WGRTrinketFitsSpecificSpec(
            itemLink,
            classID,
            specID
        )

    if fits == false then
        return nil, "not_usable"
    end

    if fits == nil then
        return nil, "unknown"
    end

    local ownedFirst,
          ownedSecond,
          ownedObserved,
          ownedCandidates =
        WGRGetOwnedSpecTrinketPair(
            characterName,
            character,
            specID
        )

    -- Once physical Soulbound ownership is known, compare the incoming
    -- trinket against the best LEGAL two-trinket setup the character can make.
    -- This fixes both missing bag/PBK trinkets and Unique-Equipped duplicates.
    -- Example: owned Unique Bell 279 + other 266, incoming same Bell 279 =>
    -- required incoming setup is still 279+266, so the true upgrade is +0.
    if ownedObserved then
        local incomingLevel = WGRGetLiveTrinketLevel(itemLink)
        if incomingLevel <= 0 then
            return nil, "unknown"
        end

        local incoming = {
            item = itemLink,
            level = incomingLevel,
            itemID = WGRGetTrinketItemID(itemLink),
            uniqueEquipped = WGRTrinketIsUniqueEquipped(itemLink),
            incoming = true,
        }

        local requiredFirst, requiredSecond =
            WGRSelectBestPairRequiringIncoming(
                ownedCandidates or {},
                incoming
            )

        local currentTotal =
            (tonumber(ownedFirst and ownedFirst.level) or 0)
            + (tonumber(ownedSecond and ownedSecond.level) or 0)
        local requiredTotal =
            (tonumber(requiredFirst and requiredFirst.level) or 0)
            + (tonumber(requiredSecond and requiredSecond.level) or 0)

        local improvement = requiredTotal - currentTotal
        local comparison = incomingLevel - improvement
        if comparison < 0 then comparison = 0 end

        return comparison, "known"
    end

    local first,
          second =
        WGRGetResolvedSpecTrinketLevels(
            characterName,
            character,
            specID
        )

    -- Fresh-install safeguard: on the first login WoW can briefly report
    -- both equipped trinkets as not belonging to the active spec even though
    -- their live item links/item levels are already available. That can leave
    -- a brand-new per-spec baseline at 0/0 and make very low-level trinkets
    -- look like upgrades. For the CURRENT PLAYER'S ACTIVE SPEC only, fall
    -- back to the two live equipped trinket item levels when BOTH resolved
    -- slots are zero and BOTH physical trinket slots have readable levels.
    -- This does not write to SavedVariables and does not affect other specs
    -- or characters; the normal saved/spec-aware baseline takes over as soon
    -- as it resolves to a real value.
    if (tonumber(first) or 0) == 0
        and (tonumber(second) or 0) == 0
    then
        local currentName =
            UnitName
            and UnitName("player")
            or nil

        local currentSpecIndex =
            GetSpecialization
            and GetSpecialization()
            or nil

        local currentSpecID =
            currentSpecIndex
            and GetSpecializationInfo
            and select(1, GetSpecializationInfo(currentSpecIndex))
            or nil

        if currentName
            and string.lower(tostring(currentName))
                == string.lower(tostring(characterName))
            and tonumber(currentSpecID) == tonumber(specID)
        then
            local live1 =
                WGRGetLiveTrinketLevel(
                    GetInventoryItemLink("player", 13)
                )
            local live2 =
                WGRGetLiveTrinketLevel(
                    GetInventoryItemLink("player", 14)
                )

            if live1 > 0 and live2 > 0 then
                first = live1
                second = live2
            end
        end
    end

    return
        math.min(
            tonumber(first) or 0,
            tonumber(second) or 0
        ),
        "known"
end

function WGRGetTrinketComparisonLevelForMode(
    characterName,
    character,
    itemLink
)
    local specIDs =
        WGRGetRoutingSpecIDs(
            characterName,
            character
        )

    if not specIDs
        or #specIDs == 0
    then
        return nil, "unknown"
    end

    local foundEligibleSpec = false
    local sawUnknown = false
    local lowestBaseline = nil

    for _, specID in ipairs(specIDs) do
        local baseline,
              status =
            WGRGetSpecificSpecTrinketComparisonLevel(
                characterName,
                character,
                itemLink,
                specID
            )

        if status == "known" then
            foundEligibleSpec = true

            if lowestBaseline == nil
                or baseline < lowestBaseline
            then
                lowestBaseline =
                    baseline
            end

        elseif status == "unknown" then
            sawUnknown = true
        end
    end

    if not foundEligibleSpec then
        if sawUnknown then
            return nil, "unknown"
        end

        return nil, "not_usable"
    end

    return lowestBaseline or 0, "known"
end
