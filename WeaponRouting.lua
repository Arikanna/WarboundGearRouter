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
    local isLevelingItem =
        itemMinLevel
        and itemMinLevel > 0
        and itemMinLevel < WGR_MAX_LEVEL

    local isDagger =
        IsDaggerItem(itemLink)

    local firstAnyUpgrade = nil
    local firstThresholdUpgrade = nil
    local firstSpecialistAnyUpgrade = nil
    local firstSpecialistThresholdUpgrade = nil

    local firstLevelingUpgrade = nil
    local firstLevelingThresholdUpgrade = nil
    local firstLevelingSpecialistUpgrade = nil
    local firstLevelingSpecialistThresholdUpgrade = nil

    -- Leveling-item routing needs to distinguish an upgrade the character
    -- can equip NOW from a future-level upgrade.  A real current upgrade
    -- (even below threshold) must beat parking the item on a character who
    -- cannot equip it yet.
    local firstLevelingCurrentUpgrade = nil
    local firstLevelingCurrentThresholdUpgrade = nil
    local firstLevelingCurrentSpecialistUpgrade = nil
    local firstLevelingCurrentSpecialistThresholdUpgrade = nil

    local holder = nil
    local specialistHolder = nil
    local unresolvedHolder = nil
    local unknownIndexes = {}

    for priorityIndex, characterName
        in ipairs(GetActiveRoutingPriority())
    do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                DataStore:GetCharacterLevel(character) or 0

            if level < WGR_MAX_LEVEL then
                if isLevelingItem then
                    -- A sub-90 weapon must be equipable NOW and
                    -- improve the character's CURRENT weapon setup.
                    if true then
                        local remembered =
                            GetRememberedSpec(characterName)

                        if remembered and remembered.specID then
                            local configFits =
                                FutureHolderWeaponMatchesSpec(
                                    characterName,
                                    itemLink
                                )

                            if configFits == true then
                                local config =
                                    GetCurrentWeaponConfiguration(
                                        character
                                    )

                                if WeaponMatchesCurrentConfiguration(
                                    config,
                                    itemLink,
                                    characterName,
                                    character
                                ) then
                                    local comparisonSlots =
                                        GetWeaponComparisonSlots(
                                            config,
                                            itemLink,
                                            characterName,
                                            character
                                        )

                                    if comparisonSlots then
                                        local upgrade, status, usesAverage, isOverAverage =
                                            WGRGetIncomingWeaponUpgradeForMode(
                                                characterName,
                                                character,
                                                itemLink,
                                                newItemLevel,
                                                "WEAPON"
                                            )

                                        if status ~= "unknown" then
                                            upgrade = tonumber(upgrade) or 0

                                            if upgrade > 0 then
                                                local result = {
                                                    kind =
                                                        level >= itemMinLevel
                                                        and "upgrade"
                                                        or "future_upgrade",
                                                    requiredLevel = itemMinLevel,
                                                    name = characterName,
                                                    upgrade = upgrade,
                                                    weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
                                                    priorityIndex = priorityIndex,
                                    threshold =
                                        WGRGetCharacterThreshold(characterName),
                                    meetsThreshold =
                                                        upgrade
                                                        >= WGRGetCharacterThreshold(characterName),
                                                }

                                                local specialist =
                                                    isDagger
                                                    and
                                                    IsDaggerSpecialistSpec(
                                                        characterName
                                                    )

                                                if specialist then
                                                    if not
                                                        firstLevelingSpecialistUpgrade
                                                    then
                                                        firstLevelingSpecialistUpgrade =
                                                            result
                                                    end

                                                    if result.meetsThreshold
                                                        and not
                                                        firstLevelingSpecialistThresholdUpgrade
                                                    then
                                                        firstLevelingSpecialistThresholdUpgrade =
                                                            result
                                                    end

                                                    if result.kind == "upgrade" then
                                                        if not firstLevelingCurrentSpecialistUpgrade then
                                                            firstLevelingCurrentSpecialistUpgrade = result
                                                        end
                                                        if result.meetsThreshold
                                                            and not firstLevelingCurrentSpecialistThresholdUpgrade
                                                        then
                                                            firstLevelingCurrentSpecialistThresholdUpgrade = result
                                                        end
                                                    end
                                                else
                                                    if not
                                                        firstLevelingUpgrade
                                                    then
                                                        firstLevelingUpgrade =
                                                            result
                                                    end

                                                    if result.meetsThreshold
                                                        and not
                                                        firstLevelingThresholdUpgrade
                                                    then
                                                        firstLevelingThresholdUpgrade =
                                                            result
                                                    end

                                                    if result.kind == "upgrade" then
                                                        if not firstLevelingCurrentUpgrade then
                                                            firstLevelingCurrentUpgrade = result
                                                        end
                                                        if result.meetsThreshold
                                                            and not firstLevelingCurrentThresholdUpgrade
                                                        then
                                                            firstLevelingCurrentThresholdUpgrade = result
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    local remembered =
                        GetRememberedSpec(characterName)

                    if remembered and remembered.specID then
                        local configFits, configStatus =
                            FutureHolderWeaponMatchesSpec(
                                characterName,
                                itemLink
                            )

                        if configStatus == "rule_unknown"
                            or configStatus
                                == "stat_rule_unknown"
                        then
                            if not unresolvedHolder then
                                unresolvedHolder = {
                                    kind = "unresolved",
                                    name = characterName,
                                    level = level,
                                    priorityIndex = priorityIndex,
                                }
                            end

                        elseif configFits == true then
                            local candidate = {
                                kind = "holder",
                                name = characterName,
                                level = level,
                                priorityIndex = priorityIndex,
                            }

                            if isDagger
                                and IsDaggerSpecialistSpec(
                                    characterName
                                )
                            then
                                if not specialistHolder then
                                    specialistHolder = candidate
                                end
                            elseif not holder then
                                holder = candidate
                            end
                        end
                    else
                        local couldUse =
                            CouldItemFitUnknownCharacter(
                                itemLink,
                                characterName,
                                character
                            )

                        if couldUse == true
                            and not unresolvedHolder
                        then
                            unresolvedHolder = {
                                kind = "unresolved",
                                name = characterName,
                                level = level,
                                priorityIndex = priorityIndex,
                            }
                        end
                    end
                end

            else
                local fitsSpec, specStatus =
                    DoesItemFitRememberedSpec(
                        itemLink,
                        characterName,
                        character
                    )

                if specStatus == "unknown_spec" then
                    table.insert(unknownIndexes, {
                        name = characterName,
                        priorityIndex = priorityIndex,
                    })

                elseif fitsSpec == true then
                    local config =
                        GetCurrentWeaponConfiguration(character)

                    if WeaponMatchesCurrentConfiguration(
                                    config,
                                    itemLink,
                                    characterName,
                                    character
                                ) then
                        local comparisonSlots =
                            GetWeaponComparisonSlots(
                                            config,
                                            itemLink,
                                            characterName,
                                            character
                                        )

                        if comparisonSlots then
                            local upgrade, status, usesAverage, isOverAverage =
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
                            else
                                upgrade = tonumber(upgrade) or 0

                                if upgrade > 0 then
                                    local result = {
                                        kind = "upgrade",
                                        name = characterName,
                                        upgrade = upgrade,
                                        weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
                                        priorityIndex = priorityIndex,
                                    threshold =
                                        WGRGetCharacterThreshold(characterName),
                                    meetsThreshold =
                                            upgrade >= WGRGetCharacterThreshold(characterName),
                                    }

                                    local specialist =
                                        isDagger
                                        and IsDaggerSpecialistSpec(
                                            characterName
                                        )

                                    if specialist then
                                        if not
                                            firstSpecialistAnyUpgrade
                                        then
                                            firstSpecialistAnyUpgrade =
                                                result
                                        end

                                        if result.meetsThreshold
                                            and not
                                            firstSpecialistThresholdUpgrade
                                        then
                                            firstSpecialistThresholdUpgrade =
                                                result
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
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local recommendation = nil

    if isDagger then
        recommendation =
            firstSpecialistThresholdUpgrade
            or firstSpecialistAnyUpgrade
            or firstThresholdUpgrade
            or firstAnyUpgrade
    else
        recommendation =
            firstThresholdUpgrade
            or firstAnyUpgrade
    end

    -- Max-level upgrades still have first claim.  Among leveling
    -- characters, prefer someone who can equip a genuine upgrade NOW
    -- before any future-level recipient, even when the current upgrade is
    -- below threshold.
    if not recommendation
        and isLevelingItem
    then
        if isDagger then
            recommendation =
                firstLevelingCurrentSpecialistThresholdUpgrade
                or firstLevelingCurrentSpecialistUpgrade
                or firstLevelingCurrentThresholdUpgrade
                or firstLevelingCurrentUpgrade
                or firstLevelingSpecialistThresholdUpgrade
                or firstLevelingSpecialistUpgrade
                or firstLevelingThresholdUpgrade
                or firstLevelingUpgrade
        else
            recommendation =
                firstLevelingCurrentThresholdUpgrade
                or firstLevelingCurrentUpgrade
                or firstLevelingThresholdUpgrade
                or firstLevelingUpgrade
        end
    end

    for _, unknown in ipairs(unknownIndexes) do
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
        return { kind = "no_current_upgrade" }
    end

    if isDagger and specialistHolder then
        return specialistHolder
    end

    if holder then
        return holder
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
    local specialistHolders = {}
    local flexibleHolders = {}
    local unresolved = {}

    local isLevelingItem =
        itemMinLevel
        and itemMinLevel > 0
        and itemMinLevel < WGR_MAX_LEVEL

    local isDagger =
        IsDaggerItem(itemLink)

    for _, characterName in ipairs(GetActiveRoutingPriority()) do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                DataStore:GetCharacterLevel(character) or 0

            if level < WGR_MAX_LEVEL then
                if isLevelingItem then
                    if true
                        and (
                            not recommendation
                            or recommendation.name ~= characterName
                        )
                    then
                        local remembered =
                            GetRememberedSpec(characterName)

                        if remembered and remembered.specID then
                            local configFits =
                                FutureHolderWeaponMatchesSpec(
                                    characterName,
                                    itemLink
                                )

                            if configFits == true then
                                local config =
                                    GetCurrentWeaponConfiguration(
                                        character
                                    )

                                if WeaponMatchesCurrentConfiguration(
                                    config,
                                    itemLink,
                                    characterName,
                                    character
                                ) then
                                    local comparisonSlots =
                                        GetWeaponComparisonSlots(
                                            config,
                                            itemLink,
                                            characterName,
                                            character
                                        )

                                    if comparisonSlots then
                                        local upgrade, status, usesAverage, isOverAverage =
                                            WGRGetIncomingWeaponUpgradeForMode(
                                                characterName,
                                                character,
                                                itemLink,
                                                newItemLevel,
                                                "WEAPON"
                                            )

                                        if status ~= "unknown" then
                                            upgrade = tonumber(upgrade) or 0

                                            if upgrade > 0 then
                                                local threshold =
                            WGRGetCharacterThreshold(
                                characterName
                            )

                        table.insert(alternatives, {
                            kind = "upgrade",
                            name = characterName,
                            upgrade = upgrade,
                            weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
                            threshold = threshold,
                            meetsThreshold =
                                upgrade >= threshold,
                        })
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    local remembered =
                        GetRememberedSpec(characterName)

                    if remembered and remembered.specID then
                        local configFits, configStatus =
                            FutureHolderWeaponMatchesSpec(
                                characterName,
                                itemLink
                            )

                        if configStatus == "rule_unknown"
                            or configStatus == "stat_rule_unknown"
                        then
                            if not recommendation
                                or recommendation.name ~= characterName
                            then
                                table.insert(unresolved, {
                                    kind = "unresolved",
                                    name = characterName,
                                    level = level,
                                })
                            end

                        elseif configFits == true then
                            if not recommendation
                                or recommendation.name ~= characterName
                            then
                                local option = {
                                    kind = "holder",
                                    name = characterName,
                                    level = level,
                                }

                                if isDagger
                                    and IsDaggerSpecialistSpec(
                                        characterName
                                    )
                                then
                                    table.insert(
                                        specialistHolders,
                                        option
                                    )
                                else
                                    table.insert(
                                        flexibleHolders,
                                        option
                                    )
                                end
                            end
                        end
                    else
                        local couldUse =
                            CouldItemFitUnknownCharacter(
                                itemLink,
                                characterName,
                                character
                            )

                        if couldUse == true
                            and (
                                not recommendation
                                or recommendation.name ~= characterName
                            )
                        then
                            table.insert(unresolved, {
                                kind = "unresolved",
                                name = characterName,
                                level = level,
                            })
                        end
                    end
                end

            else
                local fitsSpec, specStatus =
                    DoesItemFitRememberedSpec(
                        itemLink,
                        characterName,
                        character
                    )

                if specStatus == "unknown_spec" then
                    if not recommendation
                        or recommendation.name ~= characterName
                    then
                        table.insert(alternatives, {
                            kind = "unknown",
                            name = characterName,
                        })
                    end

                elseif fitsSpec == true then
                    local config =
                        GetCurrentWeaponConfiguration(character)

                    if WeaponMatchesCurrentConfiguration(
                                    config,
                                    itemLink,
                                    characterName,
                                    character
                                ) then
                        local comparisonSlots =
                            GetWeaponComparisonSlots(
                                            config,
                                            itemLink,
                                            characterName,
                                            character
                                        )

                        if comparisonSlots then
                            local upgrade, status, usesAverage, isOverAverage =
                                WGRGetIncomingWeaponUpgradeForMode(
                                    characterName,
                                    character,
                                    itemLink,
                                    newItemLevel,
                                    "WEAPON"
                                )

                            if status == "unknown" then
                                if not recommendation
                                    or recommendation.name ~= characterName
                                then
                                    table.insert(alternatives, {
                                        kind = "unknown",
                                        name = characterName,
                                    })
                                end
                            else
                                upgrade = tonumber(upgrade) or 0

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
                            weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
                            threshold = threshold,
                            meetsThreshold =
                                upgrade >= threshold,
                        })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if not isLevelingItem then
        if isDagger then
            for _, option in ipairs(specialistHolders) do
                table.insert(alternatives, option)
            end
        end

        for _, option in ipairs(flexibleHolders) do
            table.insert(alternatives, option)
        end

        for _, option in ipairs(unresolved) do
            table.insert(alternatives, option)
        end
    end

    return WGRFinalizeAlternatives(
        alternatives,
        recommendation
    )
end

-- ============================================================
-- OFF-HAND / SHIELD RECOMMENDATION
-- ============================================================

function BuildOffhandRecommendation(
    itemLink,
    newItemLevel,
    itemMinLevel
)
    local isLevelingItem =
        itemMinLevel
        and itemMinLevel > 0
        and itemMinLevel < WGR_MAX_LEVEL

    local firstAnyUpgrade = nil
    local firstThresholdUpgrade = nil
    local firstLevelingUpgrade = nil
    local firstLevelingThresholdUpgrade = nil
    local firstLevelingCurrentUpgrade = nil
    local firstLevelingCurrentThresholdUpgrade = nil
    local holder = nil
    local unresolvedHolder = nil
    local unknownIndexes = {}

    for priorityIndex, characterName
        in ipairs(GetActiveRoutingPriority())
    do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                DataStore:GetCharacterLevel(character) or 0

            if level < WGR_MAX_LEVEL then
                if isLevelingItem then
                    if true then
                        local remembered =
                            GetRememberedSpec(characterName)

                        if remembered and remembered.specID then
                            local configFits =
                                FutureHolderOffhandMatchesSpec(
                                    characterName,
                                    itemLink
                                )

                            if configFits == true then
                                local config =
                                    GetCurrentWeaponConfiguration(
                                        character
                                    )

                                if config
                                    == "ONE_HAND_PLUS_OFFHAND"
                                then
                                    local upgrade, status, usesAverage, isOverAverage =
                                        WGRGetIncomingWeaponUpgradeForMode(
                                            characterName,
                                            character,
                                            itemLink,
                                            newItemLevel,
                                            "OFFHAND"
                                        )

                                    if status ~= "unknown" then
                                        upgrade = tonumber(upgrade) or 0

                                        if upgrade > 0 then
                                            local result = {
                                                kind =
                                                    level >= itemMinLevel
                                                    and "upgrade"
                                                    or "future_upgrade",
                                                requiredLevel = itemMinLevel,
                                                name = characterName,
                                                upgrade = upgrade,
                                                weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
                                                priorityIndex = priorityIndex,
                                    threshold =
                                        WGRGetCharacterThreshold(characterName),
                                    meetsThreshold =
                                                    upgrade
                                                    >= WGRGetCharacterThreshold(characterName),
                                            }

                                            if not
                                                firstLevelingUpgrade
                                            then
                                                firstLevelingUpgrade =
                                                    result
                                            end

                                            if result.meetsThreshold
                                                and not
                                                firstLevelingThresholdUpgrade
                                            then
                                                firstLevelingThresholdUpgrade =
                                                    result
                                            end

                                            if result.kind == "upgrade" then
                                                if not firstLevelingCurrentUpgrade then
                                                    firstLevelingCurrentUpgrade = result
                                                end
                                                if result.meetsThreshold
                                                    and not firstLevelingCurrentThresholdUpgrade
                                                then
                                                    firstLevelingCurrentThresholdUpgrade = result
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    local remembered =
                        GetRememberedSpec(characterName)

                    if remembered and remembered.specID then
                        local configFits, configStatus =
                            FutureHolderOffhandMatchesSpec(
                                characterName,
                                itemLink
                            )

                        if configStatus == "rule_unknown"
                            or configStatus
                                == "stat_rule_unknown"
                        then
                            unresolvedHolder = {
                                kind = "unresolved",
                                name = characterName,
                                level = level,
                                priorityIndex = priorityIndex,
                            }
                            break

                        elseif configFits == true then
                            holder = {
                                kind = "holder",
                                name = characterName,
                                level = level,
                                priorityIndex = priorityIndex,
                            }
                            break
                        end
                    else
                        local couldUse =
                            CouldItemFitUnknownCharacter(
                                itemLink,
                                characterName,
                                character
                            )

                        if couldUse == true then
                            unresolvedHolder = {
                                kind = "unresolved",
                                name = characterName,
                                level = level,
                                priorityIndex = priorityIndex,
                            }
                            break
                        end
                    end
                end

            else
                local fitsSpec, specStatus =
                    DoesItemFitRememberedSpec(
                        itemLink,
                        characterName,
                        character
                    )

                if specStatus == "unknown_spec" then
                    table.insert(unknownIndexes, {
                        name = characterName,
                        priorityIndex = priorityIndex,
                    })

                elseif fitsSpec == true then
                    -- DoesItemFitRememberedSpec already verifies that at
                    -- least one active routing spec/profile can use this
                    -- off-hand. Do not require the character to already be
                    -- wearing a 1H+off-hand setup: a valid off-hand may be
                    -- needed to build an alternative setup from a current 2H.
                    local upgrade, status, usesAverage, isOverAverage =
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
                    else
                        upgrade = tonumber(upgrade) or 0

                        if upgrade > 0 then
                            local result = {
                                kind = "upgrade",
                                name = characterName,
                                upgrade = upgrade,
                                weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
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
    end

    local recommendation =
        firstThresholdUpgrade
        or firstAnyUpgrade

    if not recommendation
        and isLevelingItem
    then
        recommendation =
            firstLevelingCurrentThresholdUpgrade
            or firstLevelingCurrentUpgrade
            or firstLevelingThresholdUpgrade
            or firstLevelingUpgrade
    end

    for _, unknown in ipairs(unknownIndexes) do
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
        return { kind = "no_current_upgrade" }
    end

    if holder then
        return holder
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

    local isLevelingItem =
        itemMinLevel
        and itemMinLevel > 0
        and itemMinLevel < WGR_MAX_LEVEL

    for _, characterName in ipairs(GetActiveRoutingPriority()) do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                DataStore:GetCharacterLevel(character) or 0

            if level < WGR_MAX_LEVEL then
                if isLevelingItem then
                    if true
                        and (
                            not recommendation
                            or recommendation.name ~= characterName
                        )
                    then
                        local remembered =
                            GetRememberedSpec(characterName)

                        if remembered and remembered.specID then
                            local configFits =
                                FutureHolderOffhandMatchesSpec(
                                    characterName,
                                    itemLink
                                )

                            if configFits == true
                                and GetCurrentWeaponConfiguration(
                                    character
                                ) == "ONE_HAND_PLUS_OFFHAND"
                            then
                                local upgrade, status, usesAverage, isOverAverage =
                                    WGRGetIncomingWeaponUpgradeForMode(
                                        characterName,
                                        character,
                                        itemLink,
                                        newItemLevel,
                                        "OFFHAND"
                                    )

                                if status ~= "unknown" then
                                    upgrade = tonumber(upgrade) or 0

                                    if upgrade > 0 then
                                        local threshold =
                            WGRGetCharacterThreshold(
                                characterName
                            )

                        table.insert(alternatives, {
                            kind = "upgrade",
                            name = characterName,
                            upgrade = upgrade,
                            weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
                            threshold = threshold,
                            meetsThreshold =
                                upgrade >= threshold,
                        })
                                    end
                                end
                            end
                        end
                    end
                else
                    local remembered =
                        GetRememberedSpec(characterName)

                    if remembered and remembered.specID then
                        local configFits, configStatus =
                            FutureHolderOffhandMatchesSpec(
                                characterName,
                                itemLink
                            )

                        if configStatus == "rule_unknown"
                            or configStatus
                                == "stat_rule_unknown"
                        then
                            if not recommendation
                                or recommendation.name ~= characterName
                            then
                                table.insert(alternatives, {
                                    kind = "unresolved",
                                    name = characterName,
                                    level = level,
                                })
                            end

                        elseif configFits == true then
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
                    end

                end
            else
                local fitsSpec, specStatus =
                    DoesItemFitRememberedSpec(
                        itemLink,
                        characterName,
                        character
                    )

                if specStatus == "unknown_spec" then
                    if not recommendation
                        or recommendation.name ~= characterName
                    then
                        table.insert(alternatives, {
                            kind = "unknown",
                            name = characterName,
                        })
                    end
                elseif fitsSpec == true then
                    -- Match the primary recommendation path: valid off-hands
                    -- remain useful alternative-setup components even if the
                    -- character currently has a 2H equipped.
                    local upgrade, status, usesAverage, isOverAverage =
                        WGRGetIncomingWeaponUpgradeForMode(
                            characterName,
                            character,
                            itemLink,
                            newItemLevel,
                            "OFFHAND"
                        )

                    if status ~= "unknown" then
                        upgrade = tonumber(upgrade) or 0

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
                                weaponAverage = usesAverage == true,
                                                    weaponOverAverage = isOverAverage == true,
                                threshold = threshold,
                                meetsThreshold =
                                    upgrade >= threshold,
                            })
                        end
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
        print(string.format(
            "|cff00ff00Recommended: %s +%d ilvl|r",
            result.name,
            result.upgrade
        ))

        if not result.meetsThreshold then
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
        print(string.format(
            "|cff00ff00Recommended: %s +%d ilvl|r",
            result.name,
            result.upgrade
        ))

        if not result.meetsThreshold then
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
