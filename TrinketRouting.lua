-- Per-spec trinket baseline capture, inheritance, and routing comparison.
-- Trinkets are spec-sensitive: Blizzard's item-spec data determines which
-- specializations can use a trinket, while each specialization keeps its own
-- two-slot baseline. Compatible trinkets learned on another spec can be
-- inherited; genuinely missing compatible slots intentionally compare as 0.

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


function WGRGetResolvedSpecTrinketLevels(
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
