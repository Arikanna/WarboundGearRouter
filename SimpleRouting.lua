-- Standard armor/accessory recommendations, Shift alternatives,
-- and standard recommendation diagnostics.

function WGRFinalizeAlternatives(
    alternatives,
    recommendation
)
    alternatives = alternatives or {}

    local qualifying = {}
    local belowThreshold = {}
    local unresolved = {}
    local holders = {}

    for _, option in ipairs(alternatives) do
        if option.kind == "upgrade"
            or option.kind == "future_upgrade"
        then
            if option.meetsThreshold == true then
                qualifying[#qualifying + 1] = option
            else
                belowThreshold[#belowThreshold + 1] = option
            end
        elseif option.kind == "unknown"
            or option.kind == "unresolved"
        then
            unresolved[#unresolved + 1] = option
        elseif option.kind == "holder" then
            holders[#holders + 1] = option
        else
            unresolved[#unresolved + 1] = option
        end
    end

    local result = {}

    local function Append(source)
        for _, option in ipairs(source) do
            result[#result + 1] = option
        end
    end

    Append(qualifying)
    Append(belowThreshold)
    Append(unresolved)

    local primaryIsUpgrade =
        recommendation
        and (
            recommendation.kind == "upgrade"
            or recommendation.kind == "future_upgrade"
        )

    local anyUpgrade =
        primaryIsUpgrade
        or #qualifying > 0
        or #belowThreshold > 0

    if anyUpgrade then
        -- Once upgrades exist, only show the next holder in line.
        -- This preserves a useful fallback destination without flooding
        -- Shift tooltips with the entire holder roster.
        if holders[1] then
            result[#result + 1] =
                holders[1]
        end
    else
        -- If nobody can benefit from item level, the holder chain is
        -- the useful routing information, so show all remaining holders.
        Append(holders)
    end

    return result
end


-- ================================================================
-- STANDARD ARMOR / ACCESSORY RECOMMENDATION
-- ============================================================

local function WGRNormalizeSimpleComparison(
    equippedLevel,
    status
)
    if type(equippedLevel) == "number" then
        return equippedLevel, status, "known"
    end

    if status == "not_usable" then
        return nil, status, "skip"
    end

    return nil, status or "unknown", "unknown"
end

function BuildSimpleRecommendation(
    newItemLevel,
    itemMinLevel,
    priorityList,
    slotIDs,
    comparisonProvider
)
    local isLevelingItem =
        itemMinLevel
        and itemMinLevel > 0
        and itemMinLevel < WGR_MAX_LEVEL

    local firstAnyUpgrade = nil
    local firstThresholdUpgrade = nil
    local firstLevelingUpgrade = nil
    local firstLevelingThresholdUpgrade = nil
    local holder = nil
    local unknownIndexes = {}

    for priorityIndex, characterName
        in ipairs(priorityList)
    do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                DataStore:GetCharacterLevel(character) or 0

            if level < WGR_MAX_LEVEL then
                if isLevelingItem then
                    -- Leveling gear is only useful if this alt can
                    -- equip it NOW and it is a real ilvl upgrade.
                    if true then
                        local equippedLevel, status =
                            (
                                comparisonProvider
                                and comparisonProvider(
                                    characterName,
                                    character
                                )
                                or GetComparisonForSlots(
                                    character,
                                    slotIDs
                                )
                            )

                        equippedLevel,
                        status,
                        comparisonState =
                            WGRNormalizeSimpleComparison(
                                equippedLevel,
                                status
                            )

                        if comparisonState == "known" then
                            local upgrade =
                                newItemLevel - equippedLevel

                            if upgrade > 0 then
                                local result = {
                                    kind =
                                        level >= itemMinLevel
                                        and "upgrade"
                                        or "future_upgrade",
                                    requiredLevel = itemMinLevel,
                                    name = characterName,
                                    upgrade = upgrade,
                                    priorityIndex = priorityIndex,
                                    threshold =
                                        WGRGetCharacterThreshold(characterName),
                                    meetsThreshold =
                                        upgrade >= WGRGetCharacterThreshold(characterName),
                                }

                                if not firstLevelingUpgrade then
                                    firstLevelingUpgrade = result
                                end

                                if result.meetsThreshold
                                    and not
                                    firstLevelingThresholdUpgrade
                                then
                                    firstLevelingThresholdUpgrade =
                                        result
                                end
                            end
                        end
                    end
                else
                    -- Level-90/endgame gear keeps the existing
                    -- future-holder behavior.
                    holder = {
                        kind = "holder",
                        name = characterName,
                        level = level,
                        priorityIndex = priorityIndex,
                    }

                    break
                end
            else
                local equippedLevel, status =
                    (
                        comparisonProvider
                        and comparisonProvider(
                            characterName,
                            character
                        )
                        or GetComparisonForSlots(
                            character,
                            slotIDs
                        )
                    )

                equippedLevel,
                status,
                comparisonState =
                    WGRNormalizeSimpleComparison(
                        equippedLevel,
                        status
                    )

                if comparisonState == "unknown" then
                    table.insert(
                        unknownIndexes,
                        {
                            name = characterName,
                            priorityIndex = priorityIndex,
                        }
                    )
                elseif comparisonState == "known" then
                    local upgrade =
                        newItemLevel - equippedLevel

                    if upgrade > 0 then
                        local result = {
                            kind = "upgrade",
                            name = characterName,
                            upgrade = upgrade,
                            priorityIndex = priorityIndex,
                                    threshold =
                                        WGRGetCharacterThreshold(characterName),
                                    meetsThreshold =
                                upgrade >= WGRGetCharacterThreshold(characterName),
                        }

                        if not firstAnyUpgrade then
                            firstAnyUpgrade = result
                        end

                        if result.meetsThreshold
                            and not firstThresholdUpgrade
                        then
                            firstThresholdUpgrade = result
                        end
                    end
                end
            end
        end
    end

    -- Preserve the existing rule that any max-level upgrade
    -- outranks sending the item to a lower-level character.
    local recommendation =
        firstThresholdUpgrade
        or firstAnyUpgrade

    if not recommendation
        and isLevelingItem
    then
        recommendation =
            firstLevelingThresholdUpgrade
            or firstLevelingUpgrade
    end

    for _, unknown
        in ipairs(unknownIndexes)
    do
        if recommendation then
            if unknown.priorityIndex
                < recommendation.priorityIndex
            then
                return {
                    kind = "unknown",
                    name = unknown.name,
                }
            end
        else
            return {
                kind = "unknown",
                name = unknown.name,
            }
        end
    end

    if recommendation then
        return recommendation
    end

    if isLevelingItem then
        -- No currently-usable upgrade exists, so WGR should
        -- stay out of the way for ordinary leveling gear.
        return { kind = "no_current_upgrade" }
    end

    if holder then
        return holder
    end

    return { kind = "sell" }
end

-- ============================================================
-- SHIFT TOOLTIP ALTERNATIVES
-- ============================================================

function BuildSimpleAlternatives(
    newItemLevel,
    itemMinLevel,
    priorityList,
    slotIDs,
    recommendation,
    comparisonProvider
)
    local alternatives = {}

    local isLevelingItem =
        itemMinLevel
        and itemMinLevel > 0
        and itemMinLevel < WGR_MAX_LEVEL

    for _, characterName in ipairs(priorityList) do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                DataStore:GetCharacterLevel(character) or 0

            if level < WGR_MAX_LEVEL then
                if isLevelingItem then
                    if true then
                        local equippedLevel, status =
                            (
                                comparisonProvider
                                and comparisonProvider(
                                    characterName,
                                    character
                                )
                                or GetComparisonForSlots(
                                    character,
                                    slotIDs
                                )
                            )

                        equippedLevel,
                        status,
                        comparisonState =
                            WGRNormalizeSimpleComparison(
                                equippedLevel,
                                status
                            )

                        if comparisonState == "known" then
                            local upgrade =
                                newItemLevel - equippedLevel

                            if upgrade > 0
                                and (
                                    not recommendation
                                    or recommendation.name
                                        ~= characterName
                                )
                            then
                                local threshold =
                            WGRGetCharacterThreshold(
                                characterName
                            )

                        table.insert(alternatives, {
                            kind = "upgrade",
                            name = characterName,
                            upgrade = upgrade,
                            threshold = threshold,
                            meetsThreshold =
                                upgrade >= threshold,
                        })
                            end
                        end
                    end
                else
                    if not recommendation
                        or recommendation.name ~= characterName
                    then
                        table.insert(alternatives, {
                            kind = "holder",
                            name = characterName,
                            level = level,
                        })
                    end
                end
            else
                local equippedLevel, status =
                    (
                        comparisonProvider
                        and comparisonProvider(
                            characterName,
                            character
                        )
                        or GetComparisonForSlots(
                            character,
                            slotIDs
                        )
                    )

                equippedLevel,
                status,
                comparisonState =
                    WGRNormalizeSimpleComparison(
                        equippedLevel,
                        status
                    )

                if comparisonState == "unknown" then
                    if not recommendation
                        or recommendation.name ~= characterName
                    then
                        table.insert(alternatives, {
                            kind = "unknown",
                            name = characterName,
                        })
                    end
                elseif comparisonState == "known" then
                    local upgrade =
                        newItemLevel - equippedLevel

                    if upgrade > 0
                        and (
                            not recommendation
                            or recommendation.name ~= characterName
                        )
                    then
                        local threshold =
                            WGRGetCharacterThreshold(
                                characterName
                            )

                        table.insert(alternatives, {
                            kind = "upgrade",
                            name = characterName,
                            upgrade = upgrade,
                            threshold = threshold,
                            meetsThreshold =
                                upgrade >= threshold,
                        })
                    end
                end
            end
        end
    end

    return WGRFinalizeAlternatives(
        alternatives,
        recommendation
    )
end

-- ============================================================
-- FULL STANDARD DIAGNOSTIC
-- ============================================================

local function EvaluateAgainstPriority(
    itemName,
    newItemLevel,
    priorityList,
    slotIDs,
    label
)
    print(
        "|cff00ff00Warbound Gear Router - Recommendation Test|r"
    )

    print(string.format(
        "%s - %s - ilvl %d",
        itemName,
        label,
        newItemLevel
    ))

    local results = {}
    local firstAnyUpgrade = nil
    local firstThresholdUpgrade = nil
    local holder = nil

    for priorityIndex, characterName
        in ipairs(priorityList)
    do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                DataStore:GetCharacterLevel(
                    character
                ) or 0

            if level < WGR_MAX_LEVEL then
                holder = {
                    name = characterName,
                    level = level,
                    priorityIndex =
                        priorityIndex,
                }

                table.insert(results, {
                    name = characterName,
                    level = level,
                    holder = true,
                    priorityIndex =
                        priorityIndex,
                })

                break
            end

            local equippedLevel,
                  status =
                GetComparisonForSlots(
                    character,
                    slotIDs
                )

            if status == "unknown" then
                table.insert(results, {
                    name = characterName,
                    unknown = true,
                    priorityIndex =
                        priorityIndex,
                })

            else
                local upgrade =
                    newItemLevel -
                    equippedLevel

                if upgrade > 0 then
                    local result = {
                        name = characterName,
                        level = level,
                        equippedLevel =
                            equippedLevel,
                        upgrade = upgrade,
                        meetsThreshold =
                            upgrade >=
                            WGRGetCharacterThreshold(characterName),
                        empty =
                            status == "empty",
                        priorityIndex =
                            priorityIndex,
                    }

                    table.insert(
                        results,
                        result
                    )

                    if not firstAnyUpgrade then
                        firstAnyUpgrade =
                            result
                    end

                    if result.meetsThreshold
                        and not
                        firstThresholdUpgrade
                    then
                        firstThresholdUpgrade =
                            result
                    end
                else
                    table.insert(results, {
                        name = characterName,
                        level = level,
                        equippedLevel =
                            equippedLevel,
                        noUpgrade = true,
                        priorityIndex =
                            priorityIndex,
                    })
                end
            end
        end
    end

    local recommendation =
        firstThresholdUpgrade
        or firstAnyUpgrade

    local blockingUnknown = nil

    for _, result in ipairs(results) do
        if result.unknown then
            if recommendation then
                if result.priorityIndex
                    <
                    recommendation.priorityIndex
                then
                    blockingUnknown =
                        result
                    break
                end
            else
                blockingUnknown = result
                break
            end
        end
    end

    if blockingUnknown then
        print(string.format(
            "|cffff8800Unable to safely recommend: %s's equipped item level is still unavailable.|r",
            blockingUnknown.name
        ))

    elseif recommendation then
        print(string.format(
            "|cff00ff00Recommended: %s +%d ilvl|r",
            recommendation.name,
            recommendation.upgrade
        ))

        if not
            recommendation.meetsThreshold
        then
            print(string.format(
                "|cffffff00No character met their upgrade threshold; using highest-priority upgrade.|r"
            ))
        end

    elseif holder then
        print(string.format(
            "|cff00ff00Hold on: %s (Level %d)|r",
            holder.name,
            holder.level
        ))

    else
        print(
            "|cffff5555No recipient found / Sell|r"
        )
    end

    print(" ")

    for _, result in ipairs(results) do
        if result.holder then
            print(string.format(
                "%s - Level %d - |cff66ccffHold on this alt|r",
                result.name,
                result.level
            ))

        elseif result.unknown then
            print(string.format(
                "%s - |cffff8800equipped item ilvl unavailable|r",
                result.name
            ))

        elseif result.noUpgrade then
            print(string.format(
                "%s - equipped %d - |cff777777no upgrade|r",
                result.name,
                result.equippedLevel
            ))

        elseif result.empty then
            print(string.format(
                "%s - |cff00ff00empty slot -> +%d|r",
                result.name,
                result.upgrade
            ))

        elseif result.meetsThreshold then
            print(string.format(
                "%s - %d -> %d |cff00ff00(+%d)|r",
                result.name,
                result.equippedLevel,
                newItemLevel,
                result.upgrade
            ))

        else
            print(string.format(
                "%s - %d -> %d |cffffff00(+%d below threshold)|r",
                result.name,
                result.equippedLevel,
                newItemLevel,
                result.upgrade
            ))
        end
    end
end

function RunEvaluation(
    itemName,
    newItemLevel,
    priorityList,
    slotIDs,
    label
)
    PreloadItems(
        priorityList,
        slotIDs,
        function()
            EvaluateAgainstPriority(
                itemName,
                newItemLevel,
                priorityList,
                slotIDs,
                label
            )
        end,
        false
    )
end
