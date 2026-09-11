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
    local firstThresholdUpgrade = nil
    local firstAnyUpgrade = nil
    local holder = nil
    local unknownIndexes = {}

    local function CanEquipNow(level)
        return not itemMinLevel
            or itemMinLevel <= 0
            or level >= itemMinLevel
    end

    for priorityIndex, characterName in ipairs(priorityList) do
        local character = FindCharacterByName(characterName)

        if character then
            local level = WGRGetCharacterLevel(character)

            if CanEquipNow(level) then
                local equippedLevel, status =
                    (
                        comparisonProvider
                        and comparisonProvider(characterName, character)
                        or GetComparisonForSlots(character, slotIDs)
                    )

                local comparisonState
                equippedLevel, status, comparisonState =
                    WGRNormalizeSimpleComparison(equippedLevel, status)

                if comparisonState == "unknown" then
                    table.insert(unknownIndexes, {
                        name = characterName,
                        priorityIndex = priorityIndex,
                    })
                elseif comparisonState == "known" then
                    local upgrade = newItemLevel - equippedLevel

                    if upgrade > 0 then
                        local threshold =
                            WGRGetCharacterThreshold(characterName)

                        local result = {
                            kind = "upgrade",
                            name = characterName,
                            upgrade = upgrade,
                            priorityIndex = priorityIndex,
                            threshold = threshold,
                            meetsThreshold = upgrade >= threshold,
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
            elseif not holder then
                -- Character level only determines whether the item is a
                -- current upgrade or a future HOLD. It does not create a
                -- separate routing-priority tier.
                holder = {
                    kind = "holder",
                    name = characterName,
                    level = level,
                    requiredLevel = itemMinLevel,
                    priorityIndex = priorityIndex,
                }
            end
        end
    end

    local recommendation =
        firstThresholdUpgrade
        or firstAnyUpgrade

    for _, unknown in ipairs(unknownIndexes) do
        if recommendation then
            if unknown.priorityIndex < recommendation.priorityIndex then
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

    local function CanEquipNow(level)
        return not itemMinLevel
            or itemMinLevel <= 0
            or level >= itemMinLevel
    end

    for _, characterName in ipairs(priorityList) do
        if not recommendation
            or recommendation.name ~= characterName
        then
            local character = FindCharacterByName(characterName)

            if character then
                local level = WGRGetCharacterLevel(character)

                if CanEquipNow(level) then
                    local equippedLevel, status =
                        (
                            comparisonProvider
                            and comparisonProvider(characterName, character)
                            or GetComparisonForSlots(character, slotIDs)
                        )

                    local comparisonState
                    equippedLevel, status, comparisonState =
                        WGRNormalizeSimpleComparison(equippedLevel, status)

                    if comparisonState == "unknown" then
                        table.insert(alternatives, {
                            kind = "unknown",
                            name = characterName,
                        })
                    elseif comparisonState == "known" then
                        local upgrade = newItemLevel - equippedLevel

                        if upgrade > 0 then
                            local threshold =
                                WGRGetCharacterThreshold(characterName)

                            table.insert(alternatives, {
                                kind = "upgrade",
                                name = characterName,
                                upgrade = upgrade,
                                threshold = threshold,
                                meetsThreshold = upgrade >= threshold,
                            })
                        end
                    end
                else
                    table.insert(alternatives, {
                        kind = "holder",
                        name = characterName,
                        level = level,
                        requiredLevel = itemMinLevel,
                    })
                end
            end
        end
    end

    return WGRFinalizeAlternatives(alternatives, recommendation)
end


-- ============================================================
-- DETAILED TOOLTIP ROUTING TRACE
--
-- Detailed tooltips intentionally show only meaningful routing candidates.
-- The normal recommendation algorithm remains authoritative; this trace
-- mirrors its comparison inputs so Shift+Hover can explain why candidates
-- were bypassed. Upgrade routes append only the first future HOLD candidate;
-- HOLD routes preserve the remaining HOLD candidates as well.
-- ============================================================

function BuildSimpleRoutingTrace(
    newItemLevel,
    itemMinLevel,
    priorityList,
    slotIDs,
    recommendation,
    comparisonProvider
)
    local trace = {}
    local firstHolder = nil
    local holderCandidates = {}
    local includeAllHolders =
        recommendation
        and recommendation.kind == "holder"

    local function CanEquipNow(level)
        return not itemMinLevel
            or itemMinLevel <= 0
            or level >= itemMinLevel
    end

    for priorityIndex, characterName in ipairs(priorityList or {}) do
        local character = FindCharacterByName(characterName)

        if character then
            local level = WGRGetCharacterLevel(character)

            if CanEquipNow(level) then
                local equippedLevel, status =
                    (
                        comparisonProvider
                        and comparisonProvider(characterName, character)
                        or GetComparisonForSlots(character, slotIDs)
                    )

                local comparisonState
                equippedLevel, status, comparisonState =
                    WGRNormalizeSimpleComparison(equippedLevel, status)

                if comparisonState == "unknown" then
                    trace[#trace + 1] = {
                        kind = "unknown",
                        name = characterName,
                        priorityIndex = priorityIndex,
                        selected = recommendation
                            and recommendation.name == characterName
                            and recommendation.kind == "unknown",
                    }
                elseif comparisonState == "known" then
                    local upgrade = newItemLevel - equippedLevel
                    local threshold = WGRGetCharacterThreshold(characterName)

                    if upgrade > 0 then
                        trace[#trace + 1] = {
                            kind = "upgrade",
                            name = characterName,
                            upgrade = upgrade,
                            threshold = threshold,
                            meetsThreshold = upgrade >= threshold,
                            priorityIndex = priorityIndex,
                            selected = recommendation
                                and recommendation.name == characterName
                                and recommendation.kind == "upgrade",
                        }
                    else
                        trace[#trace + 1] = {
                            kind = "no_upgrade",
                            name = characterName,
                            comparisonLevel = equippedLevel,
                            priorityIndex = priorityIndex,
                        }
                    end
                end
                -- comparisonState == "skip" means this item is not usable for
                -- the character's effective routed specs, so it is not a
                -- meaningful Full-tooltip routing candidate.
            else
                local holder = {
                    kind = "holder",
                    name = characterName,
                    level = level,
                    requiredLevel = itemMinLevel,
                    priorityIndex = priorityIndex,
                    selected = recommendation
                        and recommendation.name == characterName
                        and recommendation.kind == "holder",
                }

                if includeAllHolders then
                    holderCandidates[#holderCandidates + 1] = holder
                elseif not firstHolder then
                    firstHolder = holder
                end
            end
        end
    end

    if includeAllHolders then
        for _, holder in ipairs(holderCandidates) do
            trace[#trace + 1] = holder
        end
    elseif firstHolder then
        trace[#trace + 1] = firstHolder
    end

    return trace
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
