-- Specialization memory, spec-mode settings, and spec-routing helpers.
-- Behavior-preserving extraction from the validated v0.56g baseline.

-- ============================================================
-- SPEC MEMORY
-- ============================================================

function GetCurrentSpecInfo()
    local specIndex = nil

    -- Prefer the live-player globals. They directly report the player's
    -- currently active specialization and have proven more reliable here
    -- during live spec/loadout transitions.
    if GetSpecialization then
        specIndex =
            GetSpecialization()

    elseif C_SpecializationInfo
        and C_SpecializationInfo.GetSpecialization
    then
        specIndex =
            C_SpecializationInfo.GetSpecialization()
    end

    if not specIndex then
        return nil
    end

    local specID,
          specName,
          description,
          icon,
          role,
          primaryStat

    if GetSpecializationInfo then
        specID,
        specName,
        description,
        icon,
        role,
        primaryStat =
            GetSpecializationInfo(
                specIndex
            )

    elseif C_SpecializationInfo
        and C_SpecializationInfo.GetSpecializationInfo
    then
        specID,
        specName,
        description,
        icon,
        role,
        primaryStat =
            C_SpecializationInfo.GetSpecializationInfo(
                specIndex
            )
    end

    if not specID
        or not specName
    then
        return nil
    end

    return {
        index = specIndex,
        id = specID,
        name = specName,
        role = role,
        primaryStat = primaryStat,
    }
end

function WGRLiveEquippedItemFitsSpec(
    itemLink,
    classID,
    specID
)
    if not itemLink then
        return true
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

local function WGRGetLiveEquippedItemLevel(
    slotID,
    itemLink
)
    if ItemLocation
        and ItemLocation.CreateFromEquipmentSlot
        and C_Item
        and C_Item.GetCurrentItemLevel
    then
        local okLocation,
              itemLocation =
            pcall(
                ItemLocation.CreateFromEquipmentSlot,
                ItemLocation,
                slotID
            )

        if okLocation
            and itemLocation
        then
            local okLevel,
                  currentLevel =
                pcall(
                    C_Item.GetCurrentItemLevel,
                    itemLocation
                )

            if okLevel
                and currentLevel
                and currentLevel > 0
            then
                return currentLevel
            end
        end
    end

    -- Fallback deliberately avoids GetDetailedItemLevelInfo(itemLink),
    -- because a plain item link can resolve in the player's current scaling
    -- context rather than the equipped instance's actual level.
    if itemLink then
        local _, _, _, baseItemLevel =
            C_Item.GetItemInfo(
                itemLink
            )

        if baseItemLevel
            and baseItemLevel > 0
        then
            return baseItemLevel
        end

        return GetItemLevel(
            itemLink
        )
    end

    return 0
end

local function WGRRepairMatchingLiveWeaponBaselines(
    characterName,
    liveMainHand,
    liveOffHand,
    liveMainHandLevel,
    liveOffHandLevel
)
    if not characterName then
        return 0
    end

    local characterKey =
        string.lower(
            characterName
        )

    local baselines =
        WarboundGearRouterDB.specWeaponBaselines[
            characterKey
        ]

    if type(baselines)
        ~= "table"
    then
        return 0
    end

    local repaired = 0

    for _, baseline
        in pairs(baselines)
    do
        if type(baseline)
            == "table"
            and baseline.weaponConfigState
                == "INITIALIZED"
            and baseline.mainHand
                == liveMainHand
            and baseline.offHand
                == liveOffHand
        then
            local changed = false

            if liveMainHand
                and liveMainHandLevel
                and liveMainHandLevel > 0
                and tonumber(
                    baseline.mainHandLevel
                ) ~= liveMainHandLevel
            then
                baseline.mainHandLevel =
                    liveMainHandLevel
                changed = true
            end

            if liveOffHand then
                if liveOffHandLevel
                    and liveOffHandLevel > 0
                    and tonumber(
                        baseline.offHandLevel
                    ) ~= liveOffHandLevel
                then
                    baseline.offHandLevel =
                        liveOffHandLevel
                    changed = true
                end
            elseif tonumber(
                baseline.offHandLevel
            ) ~= 0
            then
                baseline.offHandLevel = 0
                changed = true
            end

            if changed then
                baseline.updated =
                    time()
                baseline.repairedLiveItemLevel =
                    true
                baseline.itemLevelCaptureVersion =
                    2
                baseline.liveItemLevelCapture =
                    true
                repaired =
                    repaired + 1
            end
        end
    end

    return repaired
end

local function WGRSaveLiveWeaponBaselineForSpec(
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

    local mainHand =
        GetInventoryItemLink(
            "player",
            16
        )

    local offHand =
        GetInventoryItemLink(
            "player",
            17
        )

    if not mainHand
        and not offHand
    then
        return false
    end

    local baselineCharacterKey =
        string.lower(
            characterName
        )

    local existingByCharacter =
        WarboundGearRouterDB.specWeaponBaselines[
            baselineCharacterKey
        ]

    local existingBaseline =
        existingByCharacter
        and existingByCharacter[
            tostring(specID)
        ]
        or nil

    local mainFitsSpec =
        WGRLiveEquippedItemFitsSpec(
            mainHand,
            classID,
            specID
        )

    local offFitsSpec =
        WGRLiveEquippedItemFitsSpec(
            offHand,
            classID,
            specID
        )

    if mainFitsSpec == false
        or offFitsSpec == false
    then
        -- Preserve the last known-good baseline. Login/spec transitions can
        -- briefly expose incomplete or mismatched item/spec information.
        -- Automatic capture should refuse to overwrite in that state, but it
        -- must never delete a previously complete saved setup.
        return false
    end

    if mainFitsSpec == nil
        or offFitsSpec == nil
    then
        return false
    end

    local mainHandLevel = 0
    local offHandLevel = 0

    if mainHand then
        mainHandLevel =
            WGRGetLiveEquippedItemLevel(
                16,
                mainHand
            )

        if not mainHandLevel
            or mainHandLevel <= 0
        then
            return false
        end
    end

    if offHand then
        offHandLevel =
            WGRGetLiveEquippedItemLevel(
                17,
                offHand
            )

        if not offHandLevel
            or offHandLevel <= 0
        then
            return false
        end
    end

    WarboundGearRouterDB.specWeaponBaselines[
        baselineCharacterKey
    ] =
        WarboundGearRouterDB.specWeaponBaselines[
            baselineCharacterKey
        ]
        or {}

    local detectedConfig =
        WGRDetectWeaponConfigurationForSpec(
            mainHand,
            offHand,
            specID,
            existingBaseline
        )

    if detectedConfig.state ~= "INITIALIZED" then
        -- Keep the last complete baseline. Partial equipment states are
        -- useful for live diagnostics and future routing warnings, but
        -- they must not replace a known-good initialized baseline.
        return false
    end

    WGRRepairMatchingLiveWeaponBaselines(
        characterName,
        mainHand,
        offHand,
        mainHandLevel,
        offHandLevel
    )

    WarboundGearRouterDB.specWeaponBaselines[
        baselineCharacterKey
    ][tostring(specID)] = {
        specID = specID,
        specName = specName,
        mainHandLevel = mainHandLevel,
        offHandLevel = offHandLevel,
        mainHand = mainHand,
        offHand = offHand,
        weaponConfig = detectedConfig.config,
        weaponConfigState = detectedConfig.state,
        itemLevelCaptureVersion = 2,
        liveItemLevelCapture = true,
        missingMainHand = detectedConfig.missingMainHand,
        missingOffHand = detectedConfig.missingOffHand,
        updated = time(),
    }

    return true
end

-- Deliberately replace ONE spec's saved weapon baseline from the gear the
-- player is wearing now. Unlike automatic capture, Reset is allowed to clear
-- stale data and leave a partial/zero baseline when appropriate. Missing
-- components may be inherited from another saved spec, but unknown storage
-- items are never promoted into a baseline.
function WGRResetCurrentSpecWeaponBaseline(characterName, specID)
    InitializeDatabase()

    local playerName = UnitName("player")
    if not playerName
        or not characterName
        or string.lower(playerName) ~= string.lower(characterName)
    then
        return false, "not_current_character"
    end

    local specInfo = GetCurrentSpecInfo()
    if not specInfo or tonumber(specInfo.id) ~= tonumber(specID) then
        return false, "not_current_spec"
    end

    local _, _, classID = UnitClass("player")
    if not classID then
        return false, "unknown_class"
    end

    local mainHand = GetInventoryItemLink("player", 16)
    local offHand = GetInventoryItemLink("player", 17)

    local mainFit = mainHand and WGRLiveEquippedItemFitsSpec(mainHand, classID, specID) or true
    local offFit = offHand and WGRLiveEquippedItemFitsSpec(offHand, classID, specID) or true

    -- If WoW has not finished loading item/spec information, do not perform a
    -- destructive reset. A genuinely wrong equipped item returns false and is
    -- intentionally ignored instead.
    if mainFit == nil or offFit == nil then
        return false, "item_data_pending"
    end

    local mainLevel = 0
    local offLevel = 0

    if mainHand and mainFit == true then
        mainLevel = WGRGetLiveEquippedItemLevel(16, mainHand) or 0
        if mainLevel <= 0 then
            return false, "item_data_pending"
        end
    else
        mainHand = nil
    end

    if offHand and offFit == true then
        offLevel = WGRGetLiveEquippedItemLevel(17, offHand) or 0
        if offLevel <= 0 then
            return false, "item_data_pending"
        end
    else
        offHand = nil
    end

    local key = string.lower(characterName)
    WarboundGearRouterDB.specWeaponBaselines[key] =
        WarboundGearRouterDB.specWeaponBaselines[key] or {}

    -- Remove the stale record BEFORE rebuilding so inheritance cannot pull
    -- from the very baseline being reset.
    WarboundGearRouterDB.specWeaponBaselines[key][tostring(specID)] = nil

    local rebuilt =
        WGRBuildResetWeaponBaseline
        and WGRBuildResetWeaponBaseline(
            characterName,
            specID,
            mainHand,
            offHand,
            mainLevel,
            offLevel
        )
        or nil

    if rebuilt then
        WarboundGearRouterDB.specWeaponBaselines[key][tostring(specID)] = rebuilt
    end

    -- Reset is an explicit acknowledgement by the user that the currently
    -- rebuildable state is intentional. Even if it is partial or zero, do not
    -- keep nagging for initialization; routing can fill missing pieces later.
    WarboundGearRouterDB.acceptedIncompleteWeaponBaselines =
        WarboundGearRouterDB.acceptedIncompleteWeaponBaselines or {}
    WarboundGearRouterDB.acceptedIncompleteWeaponBaselines[key] =
        WarboundGearRouterDB.acceptedIncompleteWeaponBaselines[key] or {}
    WarboundGearRouterDB.acceptedIncompleteWeaponBaselines[key][tostring(specID)] = true

    if WGRRefreshTodoPage then
        WGRRefreshTodoPage()
    end

    return true, rebuilt and rebuilt.weaponConfigState or "uninitialized", rebuilt
end

function SaveCurrentSpec()
    InitializeDatabase()

    if WGRRepairAllLegacyWeaponBaselineLevels then
        WGRRepairAllLegacyWeaponBaselineLevels()
    end

    local characterName = UnitName("player")

    if not characterName then
        return
    end

    local level = UnitLevel("player")

    if not level then
        return
    end

    local specInfo = GetCurrentSpecInfo()

    if not specInfo then
        return
    end

    local localizedClass,
          classToken,
          classID =
        UnitClass("player")

    -- Remember specialization at any level where WoW exposes one.
    -- Future-holder weapon routing needs class/spec eligibility even when
    -- the character is far below the level of the incoming item.
    WarboundGearRouterDB.specs[characterName] = {
        specID = specInfo.id,
        specName = specInfo.name,
        role = specInfo.role,
        primaryStat = specInfo.primaryStat,
        class = classToken,
        classID = classID,
        level = level,
        updated = time(),
    }

    -- Keep low-level spec memory separate from weapon-baseline capture.
    -- Baselines below 80 are often incomplete/temporary leveling setups
    -- and should not become Saved Setup references.
    if level < 80 then
        return true
    end

    -- Trinkets are maintained per spec just like weapon baselines, but a
    -- missing compatible trinket is intentionally recorded as item level 0.
    -- This allows All/Custom Specs routing to send healing/tank/DPS trinkets
    -- to a spec that does not yet own an appropriate pair.
    if WGRSaveLiveTrinketBaselineForSpec then
        WGRSaveLiveTrinketBaselineForSpec(
            characterName,
            specInfo.id,
            specInfo.name,
            classID
        )
    end

    local baselineKey =
        string.lower(
            characterName
        )

    local existing =
        WarboundGearRouterDB.specWeaponBaselines[
            baselineKey
        ]

    local hadInitialized =
        existing
        and existing[
            tostring(specInfo.id)
        ]
        and existing[
            tostring(specInfo.id)
        ].weaponConfigState
            == "INITIALIZED"

    local saved =
        WGRSaveLiveWeaponBaselineForSpec(
            characterName,
            specInfo.id,
            specInfo.name,
            classID
        )

    WarboundGearRouterDB.todoSpecAttempts[
        baselineKey
    ] =
        WarboundGearRouterDB.todoSpecAttempts[
            baselineKey
        ]
        or {}

    if saved ~= true then
        WarboundGearRouterDB.todoSpecAttempts[
            baselineKey
        ][
            tostring(specInfo.id)
        ] =
            time()
    elseif not hadInitialized
        and WGRAddRecentActivity
    then
        WGRAddRecentActivity(
            tostring(characterName)
            .. " initialized "
            .. tostring(specInfo.name)
            .. ".",
            "SPEC_INITIALIZED"
        )
    end

    if WGRRefreshTodoPage then
        WGRRefreshTodoPage()
    end

    return saved
end

local WGRStartupBaselineRetryDelays = {
    0.50,
    1.00,
    2.00,
    4.00,
    7.00,
    10.00,
}

function WGRQueueStartupBaselineCapture()
    local attempt = 1

    local function TryCapture()
        if SaveCurrentSpec() == true then
            return
        end

        local delay =
            WGRStartupBaselineRetryDelays[
                attempt
            ]

        if not delay then
            return
        end

        attempt =
            attempt + 1

        C_Timer.After(
            delay,
            TryCapture
        )
    end

    TryCapture()
end

function GetRememberedSpec(characterName)
    InitializeDatabase()

    return WarboundGearRouterDB.specs[
        characterName
    ]
end

WGRSpecModeLabels = {
    CURRENT = "Current Spec Only",
    ALL = "All Specs",
    CUSTOM = "Custom Specs",
}

local function WGRIsValidSpecMode(
    mode
)
    return
        mode == "CURRENT"
        or mode == "ALL"
        or mode == "CUSTOM"
end

function WGRGetCharacterOverride(characterName)
    InitializeDatabase()
    if not characterName then return nil end
    return WarboundGearRouterDB.characterOverrides[string.lower(characterName)]
end

function WGRGetEffectiveSpecMode(characterName)
    InitializeDatabase()

    local override =
        WGRGetCharacterOverride(
            characterName
        )

    if override
        and WGRIsValidSpecMode(
            override.specMode
        )
    then
        return
            override.specMode
    end

    local globalMode =
        WarboundGearRouterDB.routingSettings.specMode

    if WGRIsValidSpecMode(
        globalMode
    )
    then
        return globalMode
    end

    return "CURRENT"
end

function WGRSetCharacterSpecMode(characterName, mode)
    InitializeDatabase()
    if not characterName then return end
    local key = string.lower(characterName)
    WarboundGearRouterDB.characterOverrides[key] = WarboundGearRouterDB.characterOverrides[key] or {}
    local override = WarboundGearRouterDB.characterOverrides[key]
    if mode == "GLOBAL"
        or not mode
    then
        override.specMode =
            nil
    elseif WGRIsValidSpecMode(
        mode
    )
    then
        override.specMode =
            mode
    else
        override.specMode =
            nil
    end
    if not next(override) then
        WarboundGearRouterDB.characterOverrides[key] = nil
    end

    if WGRRoutingConfigurationChanged then
        WGRRoutingConfigurationChanged()
    end
end

function WGRGetCharacterSpecModeDisplay(characterName)
    local override =
        WGRGetCharacterOverride(
            characterName
        )

    if override
        and override.specMode
    then
        if override.specMode == "CURRENT" then
            return "Current"
        end

        if override.specMode == "ALL" then
            return "All"
        end

        if override.specMode == "CUSTOM" then
            return "Custom"
        end

        return
            WGRSpecModeLabels[
                override.specMode
            ]
            or override.specMode
    end

    return "Global"
end



function WGRGetCustomSpecs(characterName)
    InitializeDatabase()

    if not characterName then
        return nil
    end

    return
        WarboundGearRouterDB.customSpecs[
            string.lower(characterName)
        ]
end

function WGRSetCustomSpecEnabled(
    characterName,
    specID,
    enabled
)
    InitializeDatabase()

    if not characterName
        or not specID
    then
        return
    end

    local key =
        string.lower(characterName)

    WarboundGearRouterDB.customSpecs[key] =
        WarboundGearRouterDB.customSpecs[key]
        or {}

    if enabled then
        WarboundGearRouterDB.customSpecs[key][
            tostring(specID)
        ] = true
    else
        WarboundGearRouterDB.customSpecs[key][
            tostring(specID)
        ] = nil
    end

    if not next(
        WarboundGearRouterDB.customSpecs[key]
    )
    then
        WarboundGearRouterDB.customSpecs[key] =
            nil
    end

    if WGRRoutingConfigurationChanged then
        WGRRoutingConfigurationChanged()
    end
end

WGRThresholdChoices = {
    1,
    5,
    10,
    15,
    20,
    25,
    30,
}

function WGRGetGlobalUpgradeThreshold()
    InitializeDatabase()

    return
        tonumber(
            WarboundGearRouterDB.routingSettings.upgradeThreshold
        )
        or WGR_DEFAULT_THRESHOLD
end

function WGRSetGlobalUpgradeThreshold(
    threshold
)
    InitializeDatabase()

    local value =
        tonumber(
            threshold
        )

    if value == nil then
        return false
    end

    value =
        math.max(
            0,
            math.floor(
                value
                + 0.5
            )
        )

    WarboundGearRouterDB.routingSettings.upgradeThreshold =
        value

    return true
end

function WGRGetCharacterThresholdOverride(
    characterName
)
    local override =
        WGRGetCharacterOverride(
            characterName
        )

    if override
        and tonumber(
            override.upgradeThreshold
        )
    then
        return
            tonumber(
                override.upgradeThreshold
            )
    end

    return nil
end

function WGRGetCharacterThreshold(
    characterName
)
    return
        WGRGetCharacterThresholdOverride(
            characterName
        )
        or WGRGetGlobalUpgradeThreshold()
end

function WGRSetCharacterThreshold(
    characterName,
    threshold
)
    InitializeDatabase()

    if not characterName then
        return
    end

    local key =
        string.lower(
            characterName
        )

    WarboundGearRouterDB.characterOverrides[key] =
        WarboundGearRouterDB.characterOverrides[key]
        or {}

    local override =
        WarboundGearRouterDB.characterOverrides[key]

    if threshold == nil
        or threshold == "GLOBAL"
    then
        override.upgradeThreshold =
            nil
    else
        local value =
            tonumber(
                threshold
            )

        if value ~= nil then
            override.upgradeThreshold =
                math.max(
                    0,
                    math.floor(
                        value
                        + 0.5
                    )
                )
        end
    end

    if not next(override) then
        WarboundGearRouterDB.characterOverrides[key] =
            nil
    end
end

function WGRGetCharacterThresholdDisplay(
    characterName
)
    local override =
        WGRGetCharacterThresholdOverride(
            characterName
        )

    if override then
        return
            "+"
            .. tostring(
                override
            )
    end

    return "Global"
end



function GetCharacterClassID(
    characterName,
    character
)
    local spec =
        GetRememberedSpec(characterName)

    if spec then
        if spec.classID then
            return spec.classID
        end

        if spec.class
            and WGRClassIDs[spec.class]
        then
            return WGRClassIDs[spec.class]
        end
    end

    if character
        and DataStore.GetCharacterClass
    then
        local className =
            DataStore:GetCharacterClass(character)

        if className
            and WGRClassIDs[className]
        then
            return WGRClassIDs[className]
        end
    end

    return nil
end

function WGRGetDataStoreCurrentSpecID(
    characterName,
    character
)
    local evalCache = WGRGetRoutingEvaluationCache and WGRGetRoutingEvaluationCache() or nil
    local specCacheKey = characterName and string.lower(characterName) or nil
    if evalCache and specCacheKey and evalCache.specs[specCacheKey] ~= nil then
        local cached = evalCache.specs[specCacheKey]
        return cached ~= false and cached or nil
    end
    if not DataStore
        or not DataStore.GetActiveSpecInfo
    then
        return nil
    end

    character =
        character
        or FindCharacterByName(
            characterName
        )

    if not character then
        return nil
    end

    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    local classSpecs =
        classID
        and WGRClassSpecIDs
        and WGRClassSpecIDs[classID]
        or nil

    if not classSpecs then
        return nil
    end

    local ok,
          specName,
          specIndex =
        pcall(
            DataStore.GetActiveSpecInfo,
            DataStore,
            character
        )

    if not ok
        or type(specIndex) ~= "number"
        or specIndex <= 0
    then
        return nil
    end

    local specID =
        classSpecs[specIndex]

    if not specID then
        return nil
    end

    -- DataStore stores the last specialization it observed for the
    -- character. Keep this as a read-through fallback only: do not write
    -- it into WBGR's remembered-spec SavedVariables. The live WBGR value
    -- will automatically take precedence once the character is observed.
    if evalCache and specCacheKey then evalCache.specs[specCacheKey] = specID or false end
    return specID, specName
end

function WGRGetRoutingSpecIDs(
    characterName,
    character
)
    local remembered =
        GetRememberedSpec(characterName)

    local mode =
        WGRGetEffectiveSpecMode(characterName)

    if mode == "CURRENT" then
        if remembered
            and remembered.specID
        then
            return {
                remembered.specID,
            }
        end

        local dataStoreSpecID =
            WGRGetDataStoreCurrentSpecID(
                characterName,
                character
            )

        if dataStoreSpecID then
            return {
                dataStoreSpecID,
            }
        end

        return {}
    end

    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    local allSpecs =
        classID
        and WGRClassSpecIDs
        and WGRClassSpecIDs[classID]
        or nil

    if mode == "ALL" then
        return allSpecs or {}
    end

    if mode == "CUSTOM" then
        local selected =
            WGRGetCustomSpecs(
                characterName
            )

        local result = {}

        if selected
            and allSpecs
        then
            for _, specID
                in ipairs(allSpecs)
            do
                if selected[
                    tostring(specID)
                ]
                then
                    result[#result + 1] =
                        specID
                end
            end
        end

        -- Safe fallback until the user has actually selected one or
        -- more custom specs for this character.
        if #result == 0
            and remembered
            and remembered.specID
        then
            result[1] =
                remembered.specID
        end

        return result
    end

    return {}
end

function WGRGetItemSpecSet(
    itemLink
)
    if not itemLink
        or not C_Item
        or not C_Item.GetItemSpecInfo
    then
        return nil, 0
    end

    local ok,
          specResult =
        pcall(
            C_Item.GetItemSpecInfo,
            itemLink
        )

    if not ok
        or type(specResult) ~= "table"
    then
        return nil, 0
    end

    local specSet = {}
    local count = 0

    for _, specID
        in pairs(
            specResult
        )
    do
        if type(specID) == "number"
            and not specSet[specID]
        then
            specSet[specID] = true
            count = count + 1
        end
    end

    if count == 0 then
        return nil, 0
    end

    return specSet, count
end

function WGRCharacterMatchesItemSpecs(
    characterName,
    character,
    specSet
)
    if not specSet then
        return true
    end

    local routingSpecIDs =
        WGRGetRoutingSpecIDs(
            characterName,
            character
        )

    for _, specID
        in ipairs(
            routingSpecIDs
            or {}
        )
    do
        if specSet[
            specID
        ] then
            return true
        end
    end

    return false
end


function WGRCustomSpecsSummary(
    characterName,
    character
)
    local selected =
        WGRGetCustomSpecs(
            characterName
        )

    if not selected then
        return "Current spec (not configured)"
    end

    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    local specIDs =
        classID
        and WGRClassSpecIDs
        and WGRClassSpecIDs[classID]
        or {}

    local names = {}

    for _, specID in ipairs(specIDs) do
        if selected[tostring(specID)] then
            names[#names + 1] =
                WGRSpecNamesByID[specID]
                or tostring(specID)
        end
    end

    if #names == 0 then
        return "Current spec (not configured)"
    end

    return table.concat(names, ", ")
end
