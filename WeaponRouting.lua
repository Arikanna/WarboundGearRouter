-- Weapon/off-hand recommendation builders, Shift alternatives,
-- and command-line diagnostics.

-- ============================================================
-- WEAPON RECOMMENDATION
-- ============================================================

function BuildWeaponRecommendation(
    itemLink,
    newItemLevel,
    itemMinLevel
)
    local isDaggerOverride = IsDaggerItem(itemLink)

    local firstThresholdUpgrade = nil
    local firstAnyUpgrade = nil
    local holder = nil

    local firstSpecialistThresholdUpgrade = nil
    local firstSpecialistAnyUpgrade = nil
    local specialistHolder = nil

    local unresolvedHolder = nil
    local unknownIndexes = {}

    local function CanEquipNow(level)
        return not itemMinLevel
            or itemMinLevel <= 0
            or level >= itemMinLevel
    end

    for priorityIndex, characterName
        in ipairs(GetActiveRoutingPriority())
    do
        local character = FindCharacterByName(characterName)

        if character then
            local level = WGRGetCharacterLevel(character)
            local specIDs = WGRGetRoutingSpecIDs(characterName, character)
            local specialist =
                isDaggerOverride
                and IsDaggerSpecialistSpec(characterName)

            if #specIDs > 0 then
                local fits, fitStatus =
                    FutureHolderWeaponMatchesSpec(characterName, itemLink)

                if fitStatus == "rule_unknown"
                    or fitStatus == "stat_rule_unknown"
                then
                    if CanEquipNow(level) then
                        table.insert(unknownIndexes, {
                            name = characterName,
                            priorityIndex = priorityIndex,
                        })
                    elseif not unresolvedHolder then
                        unresolvedHolder = {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                            priorityIndex = priorityIndex,
                        }
                    end

                elseif fits == true then
                    if CanEquipNow(level) then
                        local upgrade, status, usesAverage, isOverAverage, setupIncomplete =
                            WGRGetIncomingWeaponUpgradeForMode(
                                characterName,
                                character,
                                itemLink,
                                newItemLevel,
                                "WEAPON"
                            )

                        if status == "unknown" then
                            table.insert(unknownIndexes, {
                                name = characterName,
                                priorityIndex = priorityIndex,
                            })
                        elseif status == "known" then
                            upgrade = tonumber(upgrade) or 0

                            if upgrade > 0 then
                                local threshold =
                                    WGRGetCharacterThreshold(characterName)

                                local result = {
                                    kind = "upgrade",
                                    name = characterName,
                                    upgrade = upgrade,
                                    weaponAverage = usesAverage == true,
                                    weaponOverAverage = isOverAverage == true,
                                    priorityIndex = priorityIndex,
                                    threshold = threshold,
                                    meetsThreshold = upgrade >= threshold,
                                }

                                if specialist then
                                    if not firstSpecialistAnyUpgrade then
                                        firstSpecialistAnyUpgrade = result
                                    end
                                    if result.meetsThreshold
                                        and not firstSpecialistThresholdUpgrade
                                    then
                                        firstSpecialistThresholdUpgrade = result
                                    end
                                else
                                    if not firstAnyUpgrade then
                                        firstAnyUpgrade = result
                                    end
                                    if result.meetsThreshold
                                        and not firstThresholdUpgrade
                                    then
                                        firstThresholdUpgrade = result
                                    end
                                end
                            elseif setupIncomplete == true then
                                local result = {
                                    kind = "upgrade", name = characterName, upgrade = 0,
                                    setupIncomplete = true, priorityIndex = priorityIndex,
                                    threshold = WGRGetCharacterThreshold(characterName),
                                    meetsThreshold = false,
                                }
                                if specialist then
                                    if not firstSpecialistAnyUpgrade then firstSpecialistAnyUpgrade = result end
                                elseif not firstAnyUpgrade then
                                    firstAnyUpgrade = result
                                end
                            end
                        end
                    else
                        local candidate = {
                            kind = "holder",
                            name = characterName,
                            level = level,
                            requiredLevel = itemMinLevel,
                            priorityIndex = priorityIndex,
                        }

                        if specialist then
                            if not specialistHolder then
                                specialistHolder = candidate
                            end
                        elseif not holder then
                            holder = candidate
                        end
                    end
                end
            else
                local couldUse = CouldItemFitUnknownCharacter(
                    itemLink,
                    characterName,
                    character
                )

                if couldUse == true then
                    if CanEquipNow(level) then
                        table.insert(unknownIndexes, {
                            name = characterName,
                            priorityIndex = priorityIndex,
                        })
                    elseif not unresolvedHolder then
                        unresolvedHolder = {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                            priorityIndex = priorityIndex,
                        }
                    end
                end
            end
        end
    end

    local recommendation

    if isDaggerOverride then
        -- Explicit Rogue-dagger preference is a true override. Within the
        -- specialist pool, preserve the normal threshold -> any upgrade ->
        -- future HOLD order before considering flexible users.
        recommendation =
            firstSpecialistThresholdUpgrade
            or firstSpecialistAnyUpgrade
            or specialistHolder
            or firstThresholdUpgrade
            or firstAnyUpgrade
            or holder
    else
        recommendation =
            firstThresholdUpgrade
            or firstAnyUpgrade
            or holder
    end

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

    if unresolvedHolder then
        return unresolvedHolder
    end

    return { kind = "sell" }
end

-- ============================================================
-- WEAPON SHIFT ALTERNATIVES
-- ============================================================

function BuildWeaponAlternatives(
    itemLink,
    newItemLevel,
    itemMinLevel,
    recommendation
)
    local alternatives = {}
    local isDaggerOverride = IsDaggerItem(itemLink)

    local function CanEquipNow(level)
        return not itemMinLevel
            or itemMinLevel <= 0
            or level >= itemMinLevel
    end

    local specialistExists =
        isDaggerOverride
        and recommendation
        and recommendation.name
        and IsDaggerSpecialistSpec(recommendation.name)
        or false

    for _, characterName in ipairs(GetActiveRoutingPriority()) do
        if not recommendation
            or recommendation.name ~= characterName
        then
            local character = FindCharacterByName(characterName)

            if character then
                local level = WGRGetCharacterLevel(character)
                local specIDs = WGRGetRoutingSpecIDs(characterName, character)
                local specialist =
                    isDaggerOverride
                    and IsDaggerSpecialistSpec(characterName)

                local option = nil

                if #specIDs > 0 then
                    local fits, fitStatus =
                        FutureHolderWeaponMatchesSpec(characterName, itemLink)

                    if fitStatus == "rule_unknown"
                        or fitStatus == "stat_rule_unknown"
                    then
                        option = {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                        }
                    elseif fits == true then
                        if CanEquipNow(level) then
                            local upgrade, status, usesAverage, isOverAverage, setupIncomplete =
                                WGRGetIncomingWeaponUpgradeForMode(
                                    characterName,
                                    character,
                                    itemLink,
                                    newItemLevel,
                                    "WEAPON"
                                )

                            if status == "unknown" then
                                option = {
                                    kind = "unknown",
                                    name = characterName,
                                }
                            elseif status == "known" then
                                upgrade = tonumber(upgrade) or 0
                                if upgrade > 0 then
                                    local threshold = WGRGetCharacterThreshold(characterName)
                                    option = { kind = "upgrade", name = characterName, upgrade = upgrade,
                                        weaponAverage = usesAverage == true, weaponOverAverage = isOverAverage == true,
                                        threshold = threshold, meetsThreshold = upgrade >= threshold }
                                elseif setupIncomplete == true then
                                    option = { kind = "upgrade", name = characterName, upgrade = 0,
                                        setupIncomplete = true, threshold = WGRGetCharacterThreshold(characterName),
                                        meetsThreshold = false }
                                end
                            end
                        else
                            option = {
                                kind = "holder",
                                name = characterName,
                                level = level,
                                requiredLevel = itemMinLevel,
                            }
                        end
                    end
                else
                    local couldUse = CouldItemFitUnknownCharacter(
                        itemLink,
                        characterName,
                        character
                    )
                    if couldUse == true then
                        option = {
                            kind = CanEquipNow(level) and "unknown" or "unresolved",
                            name = characterName,
                            level = level,
                        }
                    end
                end

                if option then
                    option.daggerSpecialist = specialist == true
                    if option.daggerSpecialist then
                        specialistExists = true
                    end
                    table.insert(alternatives, option)
                end
            end
        end
    end

    if isDaggerOverride and specialistExists then
        local filtered = {}
        for _, option in ipairs(alternatives) do
            if option.daggerSpecialist == true then
                filtered[#filtered + 1] = option
            end
        end
        alternatives = filtered
    end

    return WGRFinalizeAlternatives(alternatives, recommendation)
end

-- ============================================================
-- OFF-HAND / SHIELD RECOMMENDATION
-- ============================================================

function BuildOffhandRecommendation(
    itemLink,
    newItemLevel,
    itemMinLevel
)
    local firstThresholdUpgrade = nil
    local firstAnyUpgrade = nil
    local holder = nil
    local unresolvedHolder = nil
    local unknownIndexes = {}

    local function CanEquipNow(level)
        return not itemMinLevel
            or itemMinLevel <= 0
            or level >= itemMinLevel
    end

    for priorityIndex, characterName
        in ipairs(GetActiveRoutingPriority())
    do
        local character = FindCharacterByName(characterName)

        if character then
            local level = WGRGetCharacterLevel(character)
            local specIDs = WGRGetRoutingSpecIDs(characterName, character)

            if #specIDs > 0 then
                local fits, fitStatus =
                    FutureHolderOffhandMatchesSpec(characterName, itemLink)

                if fitStatus == "rule_unknown"
                    or fitStatus == "stat_rule_unknown"
                then
                    if CanEquipNow(level) then
                        table.insert(unknownIndexes, {
                            name = characterName,
                            priorityIndex = priorityIndex,
                        })
                    elseif not unresolvedHolder then
                        unresolvedHolder = {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                            priorityIndex = priorityIndex,
                        }
                    end

                elseif fits == true then
                    if CanEquipNow(level) then
                        -- Do not require the currently equipped setup to
                        -- already be 1H+shield/off-hand. The shared weapon
                        -- comparison evaluates valid complete paired setups
                        -- for the selected routing specs.
                        local upgrade, status, usesAverage, isOverAverage, setupIncomplete =
                            WGRGetIncomingWeaponUpgradeForMode(
                                characterName,
                                character,
                                itemLink,
                                newItemLevel,
                                "OFFHAND"
                            )

                        if status == "unknown" then
                            table.insert(unknownIndexes, {
                                name = characterName,
                                priorityIndex = priorityIndex,
                            })
                        elseif status == "known" then
                            upgrade = tonumber(upgrade) or 0

                            if upgrade > 0 then
                                local threshold = WGRGetCharacterThreshold(characterName)
                                local result = { kind = "upgrade", name = characterName, upgrade = upgrade,
                                    weaponAverage = usesAverage == true, weaponOverAverage = isOverAverage == true,
                                    priorityIndex = priorityIndex, threshold = threshold, meetsThreshold = upgrade >= threshold }
                                if not firstAnyUpgrade then firstAnyUpgrade = result end
                                if result.meetsThreshold and not firstThresholdUpgrade then firstThresholdUpgrade = result end
                            elseif setupIncomplete == true then
                                local result = { kind = "upgrade", name = characterName, upgrade = 0,
                                    setupIncomplete = true, priorityIndex = priorityIndex,
                                    threshold = WGRGetCharacterThreshold(characterName), meetsThreshold = false }
                                if not firstAnyUpgrade then firstAnyUpgrade = result end
                            end
                        end
                    elseif not holder then
                        holder = {
                            kind = "holder",
                            name = characterName,
                            level = level,
                            requiredLevel = itemMinLevel,
                            priorityIndex = priorityIndex,
                        }
                    end
                end
            else
                local couldUse = CouldItemFitUnknownCharacter(
                    itemLink,
                    characterName,
                    character
                )

                if couldUse == true then
                    if CanEquipNow(level) then
                        table.insert(unknownIndexes, {
                            name = characterName,
                            priorityIndex = priorityIndex,
                        })
                    elseif not unresolvedHolder then
                        unresolvedHolder = {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                            priorityIndex = priorityIndex,
                        }
                    end
                end
            end
        end
    end

    local recommendation =
        firstThresholdUpgrade
        or firstAnyUpgrade
        or holder

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

    if unresolvedHolder then
        return unresolvedHolder
    end

    return { kind = "sell" }
end

-- ============================================================
-- OFF-HAND / SHIELD SHIFT ALTERNATIVES
-- ============================================================

function BuildOffhandAlternatives(
    itemLink,
    newItemLevel,
    itemMinLevel,
    recommendation
)
    local alternatives = {}

    local function CanEquipNow(level)
        return not itemMinLevel
            or itemMinLevel <= 0
            or level >= itemMinLevel
    end

    for _, characterName in ipairs(GetActiveRoutingPriority()) do
        if not recommendation
            or recommendation.name ~= characterName
        then
            local character = FindCharacterByName(characterName)

            if character then
                local level = WGRGetCharacterLevel(character)
                local specIDs = WGRGetRoutingSpecIDs(characterName, character)

                if #specIDs > 0 then
                    local fits, fitStatus =
                        FutureHolderOffhandMatchesSpec(characterName, itemLink)

                    if fitStatus == "rule_unknown"
                        or fitStatus == "stat_rule_unknown"
                    then
                        table.insert(alternatives, {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                        })
                    elseif fits == true then
                        if CanEquipNow(level) then
                            local upgrade, status, usesAverage, isOverAverage, setupIncomplete =
                                WGRGetIncomingWeaponUpgradeForMode(
                                    characterName,
                                    character,
                                    itemLink,
                                    newItemLevel,
                                    "OFFHAND"
                                )

                            if status == "unknown" then
                                table.insert(alternatives, {
                                    kind = "unknown",
                                    name = characterName,
                                })
                            elseif status == "known" then
                                upgrade = tonumber(upgrade) or 0
                                if upgrade > 0 then
                                    local threshold =
                                        WGRGetCharacterThreshold(characterName)
                                    table.insert(alternatives, {
                                        kind = "upgrade",
                                        name = characterName,
                                        upgrade = upgrade,
                                        weaponAverage = usesAverage == true,
                                        weaponOverAverage = isOverAverage == true,
                                        threshold = threshold,
                                        meetsThreshold = upgrade >= threshold,
                                    })
                                elseif setupIncomplete == true then
                                    table.insert(alternatives, {
                                        kind = "upgrade",
                                        name = characterName,
                                        upgrade = 0,
                                        setupIncomplete = true,
                                        threshold = WGRGetCharacterThreshold(characterName),
                                        meetsThreshold = false,
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
                else
                    local couldUse = CouldItemFitUnknownCharacter(
                        itemLink,
                        characterName,
                        character
                    )
                    if couldUse == true then
                        table.insert(alternatives, {
                            kind = CanEquipNow(level) and "unknown" or "unresolved",
                            name = characterName,
                            level = level,
                        })
                    end
                end
            end
        end
    end

    return WGRFinalizeAlternatives(alternatives, recommendation)
end


-- ============================================================
-- DETAILED TOOLTIP ROUTING TRACES
--
-- These are display-only mirrors of the existing weapon/off-hand comparison
-- paths. They do not choose the routing result. Detailed tooltip mode uses
-- them on Shift+Hover to explain meaningful candidates. Upgrade routes append
-- only the first future HOLD candidate; HOLD routes preserve all HOLD options.
-- ============================================================

local function WGRTraceCanEquipNow(level, itemMinLevel)
    return not itemMinLevel
        or itemMinLevel <= 0
        or level >= itemMinLevel
end

local function WGRAppendWeaponTraceCandidate(
    trace,
    characterName,
    priorityIndex,
    recommendation,
    upgrade,
    status,
    usesAverage,
    isOverAverage,
    setupIncomplete
)
    if status == "unknown" then
        trace[#trace + 1] = {
            kind = "unknown",
            name = characterName,
            priorityIndex = priorityIndex,
            selected = recommendation
                and recommendation.name == characterName
                and recommendation.kind == "unknown",
        }
        return
    end

    if status ~= "known" then
        return
    end

    upgrade = tonumber(upgrade) or 0
    if upgrade > 0 then
        local threshold = WGRGetCharacterThreshold(characterName)
        trace[#trace + 1] = {
            kind = "upgrade",
            name = characterName,
            upgrade = upgrade,
            threshold = threshold,
            meetsThreshold = upgrade >= threshold,
            weaponAverage = usesAverage == true,
            weaponOverAverage = isOverAverage == true,
            priorityIndex = priorityIndex,
            selected = recommendation
                and recommendation.name == characterName
                and recommendation.kind == "upgrade",
        }
    elseif setupIncomplete == true then
        trace[#trace + 1] = {
            kind = "incomplete",
            name = characterName,
            priorityIndex = priorityIndex,
            selected = recommendation
                and recommendation.name == characterName
                and recommendation.kind == "upgrade",
        }
    else
        trace[#trace + 1] = {
            kind = "no_upgrade",
            name = characterName,
            priorityIndex = priorityIndex,
        }
    end
end

function BuildWeaponRoutingTrace(
    itemLink,
    newItemLevel,
    itemMinLevel,
    recommendation
)
    local trace = {}
    local firstHolder = nil
    local firstSpecialistHolder = nil
    local firstUnresolvedHolder = nil
    local holderCandidates = {}
    local includeAllHolders =
        recommendation
        and recommendation.kind == "holder"
    local isDaggerOverride = IsDaggerItem(itemLink)
    local selectedIsSpecialist =
        isDaggerOverride
        and recommendation
        and recommendation.name
        and IsDaggerSpecialistSpec(recommendation.name)
        or false

    for priorityIndex, characterName in ipairs(GetActiveRoutingPriority()) do
        local character = FindCharacterByName(characterName)

        if character then
            local level = WGRGetCharacterLevel(character)
            local specIDs = WGRGetRoutingSpecIDs(characterName, character)
            local specialist =
                isDaggerOverride
                and IsDaggerSpecialistSpec(characterName)
                or false

            -- When the Rogue-dagger override actually selected a specialist,
            -- non-specialist weapon users are deliberately outside the active
            -- routing pool and are therefore omitted from Full details.
            local includePool =
                not selectedIsSpecialist
                or specialist

            if includePool then
                if #specIDs > 0 then
                    local fits, fitStatus =
                        FutureHolderWeaponMatchesSpec(characterName, itemLink)

                    if fitStatus == "rule_unknown"
                        or fitStatus == "stat_rule_unknown"
                    then
                        if WGRTraceCanEquipNow(level, itemMinLevel) then
                            trace[#trace + 1] = {
                                kind = "unknown",
                                name = characterName,
                                priorityIndex = priorityIndex,
                                selected = recommendation
                                    and recommendation.name == characterName
                                    and recommendation.kind == "unknown",
                            }
                        elseif not firstUnresolvedHolder then
                            firstUnresolvedHolder = {
                                kind = "unresolved",
                                name = characterName,
                                level = level,
                                priorityIndex = priorityIndex,
                                selected = recommendation
                                    and recommendation.name == characterName
                                    and recommendation.kind == "unresolved",
                            }
                        end
                    elseif fits == true then
                        if WGRTraceCanEquipNow(level, itemMinLevel) then
                            local upgrade, status, usesAverage, isOverAverage, setupIncomplete =
                                WGRGetIncomingWeaponUpgradeForMode(
                                    characterName,
                                    character,
                                    itemLink,
                                    newItemLevel,
                                    "WEAPON"
                                )

                            WGRAppendWeaponTraceCandidate(
                                trace,
                                characterName,
                                priorityIndex,
                                recommendation,
                                upgrade,
                                status,
                                usesAverage,
                                isOverAverage,
                                setupIncomplete
                            )
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
                            elseif specialist and not firstSpecialistHolder then
                                firstSpecialistHolder = holder
                            elseif not specialist and not firstHolder then
                                firstHolder = holder
                            end
                        end
                    end
                else
                    local couldUse = CouldItemFitUnknownCharacter(
                        itemLink,
                        characterName,
                        character
                    )

                    if couldUse == true then
                        if WGRTraceCanEquipNow(level, itemMinLevel) then
                            trace[#trace + 1] = {
                                kind = "unknown",
                                name = characterName,
                                priorityIndex = priorityIndex,
                                selected = recommendation
                                    and recommendation.name == characterName
                                    and recommendation.kind == "unknown",
                            }
                        elseif not firstUnresolvedHolder then
                            firstUnresolvedHolder = {
                                kind = "unresolved",
                                name = characterName,
                                level = level,
                                priorityIndex = priorityIndex,
                                selected = recommendation
                                    and recommendation.name == characterName
                                    and recommendation.kind == "unresolved",
                            }
                        end
                    end
                end
            end
        end
    end

    if includeAllHolders and #holderCandidates > 0 then
        for _, holder in ipairs(holderCandidates) do
            trace[#trace + 1] = holder
        end
    else
        local firstMeaningfulHolder =
            selectedIsSpecialist
            and (firstSpecialistHolder or firstUnresolvedHolder)
            or (firstHolder or firstSpecialistHolder or firstUnresolvedHolder)

        if firstMeaningfulHolder then
            trace[#trace + 1] = firstMeaningfulHolder
        end
    end

    return trace
end

function BuildOffhandRoutingTrace(
    itemLink,
    newItemLevel,
    itemMinLevel,
    recommendation
)
    local trace = {}
    local firstHolder = nil
    local firstUnresolvedHolder = nil
    local holderCandidates = {}
    local includeAllHolders =
        recommendation
        and recommendation.kind == "holder"

    for priorityIndex, characterName in ipairs(GetActiveRoutingPriority()) do
        local character = FindCharacterByName(characterName)

        if character then
            local level = WGRGetCharacterLevel(character)
            local specIDs = WGRGetRoutingSpecIDs(characterName, character)

            if #specIDs > 0 then
                local fits, fitStatus =
                    FutureHolderOffhandMatchesSpec(characterName, itemLink)

                if fitStatus == "rule_unknown"
                    or fitStatus == "stat_rule_unknown"
                then
                    if WGRTraceCanEquipNow(level, itemMinLevel) then
                        trace[#trace + 1] = {
                            kind = "unknown",
                            name = characterName,
                            priorityIndex = priorityIndex,
                            selected = recommendation
                                and recommendation.name == characterName
                                and recommendation.kind == "unknown",
                        }
                    elseif not firstUnresolvedHolder then
                        firstUnresolvedHolder = {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                            priorityIndex = priorityIndex,
                            selected = recommendation
                                and recommendation.name == characterName
                                and recommendation.kind == "unresolved",
                        }
                    end
                elseif fits == true then
                    if WGRTraceCanEquipNow(level, itemMinLevel) then
                        local upgrade, status, usesAverage, isOverAverage, setupIncomplete =
                            WGRGetIncomingWeaponUpgradeForMode(
                                characterName,
                                character,
                                itemLink,
                                newItemLevel,
                                "OFFHAND"
                            )

                        WGRAppendWeaponTraceCandidate(
                            trace,
                            characterName,
                            priorityIndex,
                            recommendation,
                            upgrade,
                            status,
                            usesAverage,
                            isOverAverage,
                            setupIncomplete
                        )
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
            else
                local couldUse = CouldItemFitUnknownCharacter(
                    itemLink,
                    characterName,
                    character
                )

                if couldUse == true then
                    if WGRTraceCanEquipNow(level, itemMinLevel) then
                        trace[#trace + 1] = {
                            kind = "unknown",
                            name = characterName,
                            priorityIndex = priorityIndex,
                            selected = recommendation
                                and recommendation.name == characterName
                                and recommendation.kind == "unknown",
                        }
                    elseif not firstUnresolvedHolder then
                        firstUnresolvedHolder = {
                            kind = "unresolved",
                            name = characterName,
                            level = level,
                            priorityIndex = priorityIndex,
                            selected = recommendation
                                and recommendation.name == characterName
                                and recommendation.kind == "unresolved",
                        }
                    end
                end
            end
        end
    end

    if includeAllHolders and #holderCandidates > 0 then
        for _, holder in ipairs(holderCandidates) do
            trace[#trace + 1] = holder
        end
    elseif firstHolder then
        trace[#trace + 1] = firstHolder
    elseif firstUnresolvedHolder then
        trace[#trace + 1] = firstUnresolvedHolder
    end

    return trace
end

-- ============================================================
-- WEAPON DIAGNOSTIC
-- ============================================================

function EvaluateWeapon(
    itemLink,
    itemName,
    newItemLevel,
    itemMinLevel,
    verbose
)
    local result =
        BuildWeaponRecommendation(
            itemLink,
            newItemLevel,
            itemMinLevel
        )

    if verbose then
        print(
            "|cff00ff00Live leveling-weapon candidate trace|r"
        )

        local isLevelingItem =
            itemMinLevel
            and itemMinLevel > 0
            and itemMinLevel < WGR_MAX_LEVEL

        print(
            string.format(
                "Required level: %s | leveling path: %s",
                tostring(itemMinLevel or 0),
                tostring(isLevelingItem == true)
            )
        )

        for priorityIndex, characterName
            in ipairs(
                GetActiveRoutingPriority()
            )
        do
            local character =
                FindCharacterByName(
                    characterName
                )

            if character then
                local level =
                    DataStore:GetCharacterLevel(
                        character
                    )
                    or 0

                if level < WGR_MAX_LEVEL
                    and isLevelingItem
                then
                    local remembered =
                        GetRememberedSpec(
                            characterName
                        )

                    if not remembered
                        or not remembered.specID
                    then
                        print(
                            string.format(
                                "|cff777777-|r %s: no remembered spec",
                                characterName
                            )
                        )
                    else
                        local configFits,
                              configStatus =
                            FutureHolderWeaponMatchesSpec(
                                characterName,
                                itemLink
                            )

                        if configFits ~= true then
                            print(
                                string.format(
                                    "|cff777777-|r %s: spec/profile eligibility failed (%s)",
                                    characterName,
                                    tostring(
                                        configStatus
                                        or configFits
                                    )
                                )
                            )
                        else
                            local config =
                                GetCurrentWeaponConfiguration(
                                    character
                                )

                            local configMatch =
                                WeaponMatchesCurrentConfiguration(
                                    config,
                                    itemLink,
                                    characterName,
                                    character
                                )

                            if not configMatch then
                                print(
                                    string.format(
                                        "|cff777777-|r %s: current configuration mismatch (%s)",
                                        characterName,
                                        tostring(config)
                                    )
                                )
                            else
                                local comparisonSlots =
                                    GetWeaponComparisonSlots(
                                        config,
                                        itemLink,
                                        characterName,
                                        character
                                    )

                                if not comparisonSlots then
                                    print(
                                        string.format(
                                            "|cff777777-|r %s: no comparison slots",
                                            characterName
                                        )
                                    )
                                else
                                    local equippedLevel,
                                          status =
                                        WGRGetWeaponComparisonLevelForMode(
                                            characterName,
                                            character,
                                            itemLink,
                                            comparisonSlots
                                        )

                                    if verbose then
                                        local routingSpecIDs =
                                            WGRGetRoutingSpecIDs(
                                                characterName,
                                                character
                                            )
                                            or {}

                                        for _, specID
                                            in ipairs(
                                                routingSpecIDs
                                            )
                                        do
                                            local specTrace =
                                                WGRDebugSpecificSpecWeaponBaseline(
                                                    characterName,
                                                    character,
                                                    itemLink,
                                                    specID
                                                )

                                            local chosen =
                                                specTrace
                                                and specTrace.chosen
                                                or nil

                                            local function Field(
                                                baseline,
                                                key
                                            )
                                                if not baseline then
                                                    return "nil"
                                                end

                                                local value =
                                                    baseline[key]

                                                if value == nil then
                                                    return "nil"
                                                end

                                                return
                                                    tostring(value)
                                            end

                                            print(
                                                string.format(
                                                    "    spec %s | profile=%s | source=%s | direct(MH=%s OH=%s cfg=%s) | datastore(MH=%s OH=%s cfg=%s) | chosen(MH=%s OH=%s cfg=%s) | resolved=%s (%s)",
                                                    tostring(specID),
                                                    tostring(
                                                        specTrace
                                                        and specTrace.profile
                                                        or "nil"
                                                    ),
                                                    tostring(
                                                        specTrace
                                                        and specTrace.resolvedSource
                                                        or "nil"
                                                    ),
                                                    Field(
                                                        specTrace
                                                        and specTrace.directBaseline,
                                                        "mainHandLevel"
                                                    ),
                                                    Field(
                                                        specTrace
                                                        and specTrace.directBaseline,
                                                        "offHandLevel"
                                                    ),
                                                    Field(
                                                        specTrace
                                                        and specTrace.directBaseline,
                                                        "weaponConfig"
                                                    ),
                                                    Field(
                                                        specTrace
                                                        and specTrace.datastoreBaseline,
                                                        "mainHandLevel"
                                                    ),
                                                    Field(
                                                        specTrace
                                                        and specTrace.datastoreBaseline,
                                                        "offHandLevel"
                                                    ),
                                                    Field(
                                                        specTrace
                                                        and specTrace.datastoreBaseline,
                                                        "weaponConfig"
                                                    ),
                                                    Field(
                                                        chosen,
                                                        "mainHandLevel"
                                                    ),
                                                    Field(
                                                        chosen,
                                                        "offHandLevel"
                                                    ),
                                                    Field(
                                                        chosen,
                                                        "weaponConfig"
                                                    ),
                                                    tostring(
                                                        specTrace
                                                        and specTrace.comparisonLevel
                                                        or "nil"
                                                    ),
                                                    tostring(
                                                        specTrace
                                                        and specTrace.comparisonStatus
                                                        or "nil"
                                                    )
                                                )
                                            )
                                        end
                                    end

                                    if status == "unknown" then
                                        print(
                                            string.format(
                                                "|cffff8800?|r %s: baseline unknown",
                                                characterName
                                            )
                                        )
                                    elseif status ~= "known" then
                                        print(
                                            string.format(
                                                "|cff777777-|r %s: baseline status %s",
                                                characterName,
                                                tostring(status)
                                            )
                                        )
                                    else
                                        local baseline =
                                            tonumber(
                                                equippedLevel
                                            )
                                            or 0

                                        local upgrade =
                                            newItemLevel
                                            - baseline

                                        local threshold =
                                            WGRGetCharacterThreshold(
                                                characterName
                                            )

                                        local canEquipNow =
                                            level
                                            >= (
                                                itemMinLevel
                                                or 0
                                            )

                                        print(
                                            string.format(
                                                "%s %s: level %d | baseline %d | +%d | threshold %d | %s",
                                                upgrade > 0
                                                    and "|cff00ff00+|r"
                                                    or "|cff777777-|r",
                                                characterName,
                                                level,
                                                baseline,
                                                upgrade,
                                                threshold,
                                                canEquipNow
                                                    and "equip now"
                                                    or "future upgrade"
                                            )
                                        )
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        print(" ")
    end

    print(
        "|cff00ff00Warbound Gear Router - Weapon Test|r"
    )

    print(string.format(
        "%s - %s - ilvl %d",
        itemName,
        GetWeaponKind(itemLink)
            or "Weapon",
        newItemLevel
    ))

    if result.kind == "future_upgrade" then
        print(
            string.format(
                "|cff00ff00Hold on: %s (Level %d, +%d ilvl)|r",
                result.name,
                result.requiredLevel
                    or 0,
                result.upgrade
                    or 0
            )
        )

    elseif result.kind == "upgrade" then
        if result.setupIncomplete == true then
            print(string.format("|cff00ff00Recommended: %s (paired setup incomplete)|r", result.name))
        else
            print(string.format("|cff00ff00Recommended: %s +%d ilvl|r", result.name, result.upgrade))
        end
        if not result.meetsThreshold and result.setupIncomplete ~= true then
            print(string.format(
                "|cffffff00No character met their upgrade threshold; using highest-priority upgrade.|r"
            ))
        end

    elseif result.kind == "holder" then
        print(string.format(
            "|cff00ff00Hold on: %s (Level %d)|r",
            result.name,
            result.level
        ))

    elseif result.kind == "unresolved" then
        print(string.format(
            "|cffff8800Future holder unresolved: %s (Level %d).|r",
            result.name,
            result.level
        ))

    elseif result.kind == "unknown" then
        print(string.format(
            "|cffff8800Unable to safely recommend: %s has incomplete weapon/spec data.|r",
            result.name
        ))

    else
        print(
            "|cffff5555No recipient found / Sell|r"
        )
    end
end

function EvaluateOffhand(
    itemLink,
    itemName,
    newItemLevel
)
    local result =
        BuildOffhandRecommendation(
            itemLink,
            newItemLevel
        )

    print(
        "|cff00ff00Warbound Gear Router - Off-Hand Test|r"
    )

    print(string.format(
        "%s - %s - ilvl %d",
        itemName,
        WGRGetOffhandKind(itemLink)
            or "Off-hand",
        newItemLevel
    ))

    if result.kind == "upgrade" then
        if result.setupIncomplete == true then
            print(string.format("|cff00ff00Recommended: %s (paired setup incomplete)|r", result.name))
        else
            print(string.format("|cff00ff00Recommended: %s +%d ilvl|r", result.name, result.upgrade))
        end
        if not result.meetsThreshold and result.setupIncomplete ~= true then
            print(string.format(
                "|cffffff00No character met their upgrade threshold; using highest-priority upgrade.|r"
            ))
        end

    elseif result.kind == "holder" then
        print(string.format(
            "|cff00ff00Hold on: %s (Level %d)|r",
            result.name,
            result.level
        ))

    elseif result.kind == "unresolved" then
        print(string.format(
            "|cffff8800Future holder unresolved: %s (Level %d).|r",
            result.name,
            result.level
        ))

    elseif result.kind == "unknown" then
        print(string.format(
            "|cffff8800Unable to safely recommend: %s has incomplete off-hand/spec data.|r",
            result.name
        ))

    else
        print(
            "|cffff5555No recipient found / Sell|r"
        )
    end
end
