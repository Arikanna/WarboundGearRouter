-- Weapon/off-hand classification, configuration detection,
-- weapon-profile eligibility, and baseline helper logic.

-- Class-level weapon subtype eligibility.
function WGRClassCanUseWeaponSubtype(
    classID,
    itemLink
)
    if not itemLink
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
          itemClassID,
          itemSubclassID =
        C_Item.GetItemInfoInstant(
            itemLink
        )

    if not itemID then
        return nil
    end

    if itemClassID ~= WGR_ITEM_CLASS_WEAPON then
        return true
    end

    local allowed =
        WGRClassWeaponSubclasses[
            classID
        ]

    if not allowed then
        return nil
    end

    return allowed[
        itemSubclassID
    ] == true
end

-- ============================================================
-- WEAPON CLASSIFICATION
-- ============================================================

function GetWeaponKind(item)
    local info =
        GetInstantItemInfo(item)

    if not info
        or info.classID
            ~= WGR_ITEM_CLASS_WEAPON
    then
        return nil
    end

    -- Wands behave as 1H caster weapons.
    if info.subclassID == WGR_WEAPON_WAND then
        return "ONE_HAND"
    end

    -- True ranged Hunter weapons.
    if info.subclassID == WGR_WEAPON_BOW
        or info.subclassID == WGR_WEAPON_GUN
        or info.subclassID
            == WGR_WEAPON_CROSSBOW
    then
        return "RANGED"
    end

    if info.equipLoc
        == "INVTYPE_2HWEAPON"
    then
        return "TWO_HAND"
    end

    if info.equipLoc
            == "INVTYPE_WEAPON"
        or info.equipLoc
            == "INVTYPE_WEAPONMAINHAND"
        or info.equipLoc
            == "INVTYPE_WEAPONOFFHAND"
        or info.equipLoc
            == "INVTYPE_RANGEDRIGHT"
    then
        return "ONE_HAND"
    end

    return nil
end

function IsSupportedWeapon(item)
    return GetWeaponKind(item) ~= nil
end

function GetCurrentWeaponConfiguration(
    character
)
    local mainHand =
        GetStoredItem(character, 16)

    local offHand =
        GetStoredItem(character, 17)

    if not mainHand then
        return "UNKNOWN"
    end

    local mainKind =
        GetWeaponKind(mainHand)

    local offKind =
        GetWeaponKind(offHand)

    if mainKind == "RANGED" then
        return "RANGED"
    end

    if mainKind == "TWO_HAND" then
        if offKind == "TWO_HAND" then
            return "DUAL_2H"
        end

        return "TWO_HAND"
    end

    if mainKind == "ONE_HAND" then
        if offHand then
            if offKind == "ONE_HAND" then
                return "DUAL_1H"
            end

            return "ONE_HAND_PLUS_OFFHAND"
        end

        return "ONE_HAND"
    end

    return "UNKNOWN"
end

function WeaponMatchesCurrentConfiguration(
    config,
    incomingItem,
    characterName,
    character
)
    local incomingKind =
        GetWeaponKind(incomingItem)

    if not incomingKind then
        return false
    end

    -- v0.46: configuration eligibility is handled by WGRSpecAllowsWeaponByProfile.
    -- Do not re-impose the character's physically equipped layout here.
    if characterName then
        return true
    end

    local mode = "CURRENT"

    if mode == "ALL"
        or mode == "CUSTOM"
    then
        local classID =
            GetCharacterClassID(
                characterName,
                character
            )

        if not classID
            or not C_Item
            or not C_Item.DoesItemContainSpec
        then
            return false
        end

        local instantInfo =
            GetInstantItemInfo(
                incomingItem
            )

        local isWarglaive =
            instantInfo
            and instantInfo.classID == 2
            and instantInfo.subclassID == 9

        if isWarglaive
            and classID ~= 12
        then
            return false
        end

        local ok, result =
            pcall(
                C_Item.DoesItemContainSpec,
                incomingItem,
                classID
            )

        return ok
            and result == true
    end

    if config == "RANGED" then
        return incomingKind == "RANGED"
    end

    if config == "TWO_HAND" then
        return incomingKind == "TWO_HAND"
    end

    if config == "DUAL_2H" then
        return incomingKind == "TWO_HAND"
    end

    if config == "DUAL_1H"
        or config
            == "ONE_HAND_PLUS_OFFHAND"
        or config == "ONE_HAND"
    then
        return incomingKind == "ONE_HAND"
    end

    return false
end

function GetWeaponComparisonSlots(
    config,
    incomingItem,
    characterName,
    character
)
    local info =
        GetInstantItemInfo(incomingItem)

    if not info then
        return nil
    end

    local mode =
        characterName
        and WGRGetEffectiveSpecMode(characterName)
        or "CURRENT"

    if characterName then
        local incomingKind =
            GetWeaponKind(
                incomingItem
            )

        if incomingKind == "RANGED"
            or incomingKind == "TWO_HAND"
        then
            return { 16 }
        end

        if incomingKind == "ONE_HAND" then
            local classID =
                GetCharacterClassID(
                    characterName,
                    character
                )

            local dualCapable = {
                [1] = true,
                [4] = true,
                [6] = true,
                [7] = true,
                [10] = true,
                [12] = true,
            }

            if classID
                and dualCapable[classID]
            then
                return { 16, 17 }
            end

            return { 16 }
        end
    end

    if config == "RANGED"
        or config == "TWO_HAND"
    then
        return { 16 }
    end

    if config == "DUAL_2H" then
        return { 16, 17 }
    end

    if config == "DUAL_1H" then
        if info.equipLoc
            == "INVTYPE_WEAPONMAINHAND"
        then
            return { 16 }
        end

        if info.equipLoc
            == "INVTYPE_WEAPONOFFHAND"
        then
            return { 17 }
        end

        return { 16, 17 }
    end

    if config
            == "ONE_HAND_PLUS_OFFHAND"
        or config == "ONE_HAND"
    then
        return { 16 }
    end

    return nil
end

local function IsWarglaiveItem(
    itemLink
)
    local info =
        GetInstantItemInfo(
            itemLink
        )

    if not info then
        return false
    end

    -- WoW weapon subclass ID 9 = Warglaives.
    return info.classID == 2
        and info.subclassID == 9
end




-- ============================================================
-- WEAPON PREFERENCE MODES + 12.1 CONFIGURATION MATRIX
-- ============================================================



local function WGRIsValidWeaponMode(
    mode
)
    return
        mode == "ALL"
        or mode == "SAVED"
        or mode == "CUSTOM"
end

local function WGRIsEligibleCustomWeaponConfig(
    specID,
    config
)
    if config == "ALL"
        or config == nil
    then
        return true
    end

    specID =
        tonumber(
            specID
        )

    if not specID then
        return false
    end

    local eligible =
        WGRSpecEligibleWeaponConfigs[
            specID
        ]

    if type(eligible) ~= "table" then
        return false
    end

    for _, allowedConfig
        in ipairs(eligible)
    do
        if config == allowedConfig then
            return true
        end
    end

    return false
end


function WGRGetCharacterWeaponMode(characterName)
    InitializeDatabase()

    local defaultMode =
        WarboundGearRouterDB.routingSettings.weaponMode

    if not WGRIsValidWeaponMode(
        defaultMode
    )
    then
        defaultMode =
            "ALL"
    end

    local mode =
        WarboundGearRouterDB.weaponModes[
            string.lower(
                characterName
                or ""
            )
        ]

    if WGRIsValidWeaponMode(
        mode
    )
    then
        return mode
    end

    return defaultMode
end

function WGRSetCharacterWeaponMode(characterName, mode)
    InitializeDatabase()

    if not characterName then
        return
    end

    local key = string.lower(characterName)
    local defaultMode =
        WarboundGearRouterDB.routingSettings.weaponMode
        or "ALL"

    if not WGRIsValidWeaponMode(
        mode
    )
        or mode == defaultMode
    then
        WarboundGearRouterDB.weaponModes[key] =
            nil
    else
        WarboundGearRouterDB.weaponModes[key] =
            mode
    end
end

function WGRGetCustomWeaponPreference(characterName, specID)
    InitializeDatabase()

    local preferences =
        WarboundGearRouterDB.customWeaponPreferences[
            string.lower(
                characterName
                or ""
            )
        ]

    local config =
        preferences
        and preferences[
            tostring(specID)
        ]

    if WGRIsEligibleCustomWeaponConfig(
        specID,
        config
    )
    then
        return config
            or "ALL"
    end

    return "ALL"
end

function WGRSetCustomWeaponPreference(characterName, specID, config)
    InitializeDatabase()
    if not characterName or not specID then return end
    local key=string.lower(characterName)
    WarboundGearRouterDB.customWeaponPreferences[key]=WarboundGearRouterDB.customWeaponPreferences[key] or {}
    if config == "ALL"
        or not WGRIsEligibleCustomWeaponConfig(
            specID,
            config
        )
    then
        WarboundGearRouterDB.customWeaponPreferences[
            key
        ][tostring(specID)] =
            nil
    else
        WarboundGearRouterDB.customWeaponPreferences[
            key
        ][tostring(specID)] =
            config
    end
    if not next(WarboundGearRouterDB.customWeaponPreferences[key]) then WarboundGearRouterDB.customWeaponPreferences[key]=nil end
end

function WGRConfigListText(specID)
    local configs=WGRSpecEligibleWeaponConfigs[specID] or {}
    local labels={}
    for _,c in ipairs(configs) do labels[#labels+1]=(WGRWeaponConfigLabels and WGRWeaponConfigLabels[c]) or c end
    return table.concat(labels, ", ")
end

local function WGRItemMatchesWeaponConfig(itemLink, config, comparisonType)
    if config=="ALL" then return true end
    if comparisonType=="OFFHAND" then
        local k=WGRGetOffhandKind(itemLink)
        if config=="ONE_HAND_PLUS_SHIELD" then return k=="SHIELD" end
        if config=="ONE_HAND_PLUS_OFFHAND" then return k=="OFFHAND" end
        return false
    end
    local k=GetWeaponKind(itemLink)
    if config=="RANGED" then return k=="RANGED" end
    if config=="TWO_HAND" or config=="DUAL_2H" then return k=="TWO_HAND" end
    if config=="DUAL_1H" or config=="ONE_HAND_PLUS_SHIELD" or config=="ONE_HAND_PLUS_OFFHAND" then return k=="ONE_HAND" end
    return false
end

function WGRCustomSelectionOverridesGlobal(characterName, specID)
    if WGRGetCharacterWeaponMode(characterName)~="CUSTOM" then return false end
    local pref=WGRGetCustomWeaponPreference(characterName,specID)
    if specID==72 and WarboundGearRouterDB.routingSettings.preferDual2HForFury==true then
        return pref=="ALL" or pref=="DUAL_1H"
    end
    if (specID==577 or specID==581 or specID==1480) and WarboundGearRouterDB.routingSettings.preferWarglaivesForDemonHunters==true then
        return pref=="ALL" or pref=="DUAL_1H"
    end
    return false
end

function WGRGetGlobalWeaponOverrideNames(kind)
    local names={}
    for _,characterName in ipairs(GetRoutingPriority and GetRoutingPriority() or {}) do
        if WGRGetCharacterWeaponMode(characterName)=="CUSTOM" then
            local character=FindCharacterByName(characterName)
            local classID=GetCharacterClassID(characterName,character)

            if kind=="ROGUE" and classID==4 then
                names[#names+1]=characterName
            else
                for _,specID in ipairs(WGRGetRoutingSpecIDs(characterName,character)) do
                    local isMatch=
                        (kind=="FURY" and specID==72)
                        or
                        (kind=="DH" and (specID==577 or specID==581 or specID==1480))

                    if isMatch and WGRCustomSelectionOverridesGlobal(characterName,specID) then
                        names[#names+1]=characterName
                        break
                    end
                end
            end
        end
    end
    return names
end



function WGRBuildDataStoreWeaponBaseline(
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

    local mainHand =
        GetStoredItem(
            character,
            16
        )

    local offHand =
        GetStoredItem(
            character,
            17
        )

    if not mainHand
        and not offHand
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

    -- DataStore exposes the character's physically equipped weapon slots,
    -- which may belong to a different specialization. A valid-looking
    -- configuration is not enough: every stored component must also be
    -- appropriate for the target spec before it can establish that spec's
    -- fallback baseline. This prevents (for example) a Protection Paladin's
    -- Strength 1H from becoming Holy's Intellect weapon baseline.
    if mainHand then
        local mainFits =
            WGRItemFitsSpecificSpec(
                mainHand,
                classID,
                specID
            )

        if mainFits ~= true then
            return nil
        end
    end

    if offHand then
        local offFits =
            WGRItemFitsSpecificSpec(
                offHand,
                classID,
                specID
            )

        if offFits ~= true then
            return nil
        end
    end

    local detected =
        WGRDetectWeaponConfigurationForSpec(
            mainHand,
            offHand,
            specID,
            nil
        )

    if not detected
        or detected.state ~= "INITIALIZED"
        or not detected.config
        or detected.config == "UNKNOWN"
    then
        return nil
    end

    local mainLevel =
        mainHand
        and GetItemLevel(
            mainHand
        )
        or 0

    local offLevel =
        offHand
        and GetItemLevel(
            offHand
        )
        or 0

    if mainHand
        and (
            not mainLevel
            or mainLevel <= 0
        )
    then
        return nil
    end

    if offHand
        and (
            not offLevel
            or offLevel <= 0
        )
    then
        return nil
    end

    return {
        specID = specID,
        specName = WGRSpecNamesByID[specID],
        mainHandLevel = mainLevel or 0,
        offHandLevel = offLevel or 0,
        mainHand = mainHand,
        offHand = offHand,
        weaponConfig = detected.config,
        weaponConfigState = "DATASTORE_FALLBACK",
        missingMainHand = false,
        missingOffHand = false,
        dataStoreFallback = true,
        updated = 0,
    }
end


local WGR_WEAPON_LEVEL_CAPTURE_VERSION =
    2

local function WGRRepairLegacyBaselineComponentLevel(
    baseline,
    linkField,
    levelField
)
    if not baseline then
        return false
    end

    local itemLink =
        baseline[
            linkField
        ]

    local storedLevel =
        tonumber(
            baseline[
                levelField
            ]
        )
        or 0

    if itemLink then
        local safeLevel =
            GetItemLevel(
                itemLink
            )

        if safeLevel
            and safeLevel > 0
            and safeLevel
                ~= storedLevel
        then
            baseline[
                levelField
            ] =
                safeLevel

            return true
        end

        return false
    end

    -- A legacy numeric level with no corresponding saved item cannot be
    -- validated. Do not let an orphaned scaled value such as 447/655
    -- continue to block otherwise-valid routing.
    if storedLevel > 0 then
        baseline[
            levelField
        ] =
            0

        return true
    end

    return false
end

function WGRRepairLegacyWeaponBaselineLevelsForCharacter(
    characterName
)
    if not characterName then
        return 0
    end

    InitializeDatabase()

    local character =
        FindCharacterByName(
            characterName
        )

    if not character then
        return 0
    end

    local level =
        DataStore:GetCharacterLevel(
            character
        )
        or 0

    -- The bad scaling capture was observed on leveling characters.
    -- Do not rewrite max-level historical/spec-specific setups.
    if level >= WGR_MAX_LEVEL then
        return 0
    end

    local key =
        string.lower(
            characterName
        )

    local byCharacter =
        WarboundGearRouterDB.specWeaponBaselines[
            key
        ]

    if type(byCharacter)
        ~= "table"
    then
        return 0
    end

    local repaired = 0

    for _, baseline
        in pairs(
            byCharacter
        )
    do
        if type(baseline)
            == "table"
            and (
                tonumber(
                    baseline.itemLevelCaptureVersion
                )
                or 0
            ) < WGR_WEAPON_LEVEL_CAPTURE_VERSION
        then
            local changed = false

            if WGRRepairLegacyBaselineComponentLevel(
                baseline,
                "mainHand",
                "mainHandLevel"
            )
            then
                changed = true
            end

            if WGRRepairLegacyBaselineComponentLevel(
                baseline,
                "offHand",
                "offHandLevel"
            )
            then
                changed = true
            end

            baseline.itemLevelCaptureVersion =
                WGR_WEAPON_LEVEL_CAPTURE_VERSION

            baseline.legacyLevelRepairCheckedAt =
                time()

            if changed then
                baseline.legacyItemLevelRepaired =
                    true

                baseline.legacyItemLevelRepairedAt =
                    time()

                repaired =
                    repaired + 1
            end
        end
    end

    return repaired
end

function WGRRepairAllLegacyWeaponBaselineLevels()
    InitializeDatabase()

    local total = 0

    for _, characterName
        in ipairs(
            GetActiveRoutingPriority()
            or {}
        )
    do
        total =
            total
            + WGRRepairLegacyWeaponBaselineLevelsForCharacter(
                characterName
            )
    end

    return total
end

function WGRGetSpecWeaponBaseline(
    characterName,
    specID
)
    InitializeDatabase()

    WGRRepairLegacyWeaponBaselineLevelsForCharacter(
        characterName
    )

    local byCharacter =
        WarboundGearRouterDB.specWeaponBaselines[
            string.lower(
                characterName
            )
        ]

    if not byCharacter then
        return nil
    end

    return byCharacter[tostring(specID)]
end


local function WGRBaselineComponentFitsSpec(itemLink, classID, specID, wantedKind)
    if not itemLink then
        return false
    end

    if WGRItemFitsSpecificSpec(itemLink, classID, specID) ~= true then
        return false
    end

    if wantedKind == "ONE_HAND" then
        return GetWeaponKind(itemLink) == "ONE_HAND"
    elseif wantedKind == "TWO_HAND" then
        return GetWeaponKind(itemLink) == "TWO_HAND"
    elseif wantedKind == "RANGED" then
        return GetWeaponKind(itemLink) == "RANGED"
    elseif wantedKind == "SHIELD" then
        return WGRGetOffhandKind(itemLink) == "SHIELD"
    elseif wantedKind == "OFFHAND" then
        return WGRGetOffhandKind(itemLink) == "OFFHAND"
    end

    return false
end

local function WGRBuildInheritedCandidate(characterName, targetSpecID, sourceBaseline, targetConfig)
    if not sourceBaseline then
        return nil
    end

    local character = FindCharacterByName(characterName)
    local classID = GetCharacterClassID(characterName, character)

    if not classID then
        return nil
    end

    local sourceItems = {
        {
            link = sourceBaseline.mainHand,
            level = tonumber(sourceBaseline.mainHandLevel) or 0,
            slot = "MH",
        },
        {
            link = sourceBaseline.offHand,
            level = tonumber(sourceBaseline.offHandLevel) or 0,
            slot = "OH",
        },
    }

    local function bestItemsOfKind(kind, count)
        local found = {}

        for _, data in ipairs(sourceItems) do
            if data.link
                and data.level > 0
                and WGRBaselineComponentFitsSpec(
                    data.link,
                    classID,
                    targetSpecID,
                    kind
                )
            then
                found[#found + 1] = data
            end
        end

        table.sort(
            found,
            function(a, b)
                return (a.level or 0) > (b.level or 0)
            end
        )

        local result = {}
        for i = 1, math.min(count, #found) do
            result[#result + 1] = found[i]
        end
        return result
    end

    local main = nil
    local off = nil
    local missingMain = false
    local missingOff = false

    if targetConfig == "RANGED" then
        local items = bestItemsOfKind("RANGED", 1)
        main = items[1]
        missingMain = main == nil

    elseif targetConfig == "TWO_HAND" then
        local items = bestItemsOfKind("TWO_HAND", 1)
        main = items[1]
        missingMain = main == nil

    elseif targetConfig == "DUAL_1H" then
        local items = bestItemsOfKind("ONE_HAND", 2)
        main = items[1]
        off = items[2]
        missingMain = main == nil
        missingOff = off == nil

    elseif targetConfig == "DUAL_2H" then
        local items = bestItemsOfKind("TWO_HAND", 2)
        main = items[1]
        off = items[2]
        missingMain = main == nil
        missingOff = off == nil

    elseif targetConfig == "ONE_HAND_PLUS_SHIELD" then
        local mains = bestItemsOfKind("ONE_HAND", 1)
        local offs = bestItemsOfKind("SHIELD", 1)
        main = mains[1]
        off = offs[1]
        missingMain = main == nil
        missingOff = off == nil

    elseif targetConfig == "ONE_HAND_PLUS_OFFHAND" then
        local mains = bestItemsOfKind("ONE_HAND", 1)
        local offs = bestItemsOfKind("OFFHAND", 1)
        main = mains[1]
        off = offs[1]
        missingMain = main == nil
        missingOff = off == nil

    else
        return nil
    end

    local hasAny = main ~= nil or off ~= nil
    if not hasAny then
        return nil
    end

    local complete =
        not missingMain
        and not missingOff

    if targetConfig == "RANGED"
        or targetConfig == "TWO_HAND"
    then
        complete = not missingMain
        missingOff = false
    end

    local mainLevel = main and main.level or 0
    local offLevel = off and off.level or 0

    local score = 0
    local count = 0

    if mainLevel > 0 then
        score = score + mainLevel
        count = count + 1
    end

    if offLevel > 0 then
        score = score + offLevel
        count = count + 1
    end

    if count > 0 then
        score = score / count
    end

    return {
        specID = targetSpecID,
        specName = WGRSpecNamesByID[targetSpecID],
        mainHandLevel = mainLevel,
        offHandLevel = offLevel,
        mainHand = main and main.link or nil,
        offHand = off and off.link or nil,
        weaponConfig = targetConfig,
        weaponConfigState = complete and "INHERITED_COMPLETE" or "INHERITED_PARTIAL",
        missingMainHand = missingMain,
        missingOffHand = missingOff,
        updated = tonumber(sourceBaseline.updated) or 0,
        inherited = true,
        inheritedFromSpecID = sourceBaseline.specID,
        inheritedFromSpecName =
            sourceBaseline.specName
            or WGRSpecNamesByID[sourceBaseline.specID]
            or tostring(sourceBaseline.specID or "?"),
        inheritedScore = score,
        inheritedComplete = complete,
    }
end

local function WGRGetInheritedWeaponBaseline(characterName, targetSpecID)
    InitializeDatabase()

    WGRRepairLegacyWeaponBaselineLevelsForCharacter(
        characterName
    )

    local byCharacter =
        WarboundGearRouterDB.specWeaponBaselines[
            string.lower(characterName or "")
        ]

    if not byCharacter then
        return nil
    end

    local configs =
        WGRSpecEligibleWeaponConfigs[targetSpecID]
        or {}

    local bestComplete = nil
    local bestPartial = nil

    for sourceSpecKey, sourceBaseline
        in pairs(byCharacter)
    do
        local sourceSpecID =
            tonumber(sourceSpecKey)
            or tonumber(sourceBaseline and sourceBaseline.specID)

        if sourceBaseline
            and sourceSpecID
            and sourceSpecID ~= targetSpecID
            and sourceBaseline.weaponConfigState == "INITIALIZED"
        then
            for _, targetConfig
                in ipairs(configs)
            do
                local candidate =
                    WGRBuildInheritedCandidate(
                        characterName,
                        targetSpecID,
                        sourceBaseline,
                        targetConfig
                    )

                if candidate then
                    local bucket =
                        candidate.inheritedComplete
                        and "complete"
                        or "partial"

                    local current =
                        bucket == "complete"
                        and bestComplete
                        or bestPartial

                    local candidateScore =
                        tonumber(candidate.inheritedScore)
                        or 0

                    local currentScore =
                        current
                        and tonumber(current.inheritedScore)
                        or -1

                    local candidateUpdated =
                        tonumber(candidate.updated)
                        or 0

                    local currentUpdated =
                        current
                        and tonumber(current.updated)
                        or -1

                    if not current
                        or candidateScore > currentScore
                        or (
                            candidateScore == currentScore
                            and candidateUpdated > currentUpdated
                        )
                    then
                        if bucket == "complete" then
                            bestComplete = candidate
                        else
                            bestPartial = candidate
                        end
                    end
                end
            end
        end
    end

    return bestComplete or bestPartial
end

function WGRGetInheritedWeaponBaselineForRouting(
    characterName,
    targetSpecID
)
    return
        WGRGetInheritedWeaponBaseline(
            characterName,
            targetSpecID
        )
end

function WGRDescribeInheritedBaseline(baseline)
    if not baseline
        or not baseline.inherited
    then
        return nil
    end

    local source =
        baseline.inheritedFromSpecName
        or "another spec"

    if baseline.weaponConfigState == "INHERITED_COMPLETE" then
        return "Inherited from "
            .. source
            .. " ("
            .. (
                WGRWeaponConfigLabels[baseline.weaponConfig]
                or tostring(baseline.weaponConfig)
            )
            .. ")"
    end

    local pieces = {}

    if baseline.missingMainHand then
        pieces[#pieces + 1] = "main hand missing"
    end

    if baseline.missingOffHand then
        pieces[#pieces + 1] = "off-hand missing"
    end

    return "Inherited partial from "
        .. source
        .. " ("
        .. (
            WGRWeaponConfigLabels[baseline.weaponConfig]
            or tostring(baseline.weaponConfig)
        )
        .. (
            #pieces > 0
            and "; " .. table.concat(pieces, ", ")
            or ""
        )
        .. ")"
end

function WGRGetOffhandKind(
    item
)
    local info =
        GetInstantItemInfo(
            item
        )

    if not info then
        return nil
    end

    if info.equipLoc
        == "INVTYPE_SHIELD"
    then
        return "SHIELD"
    end

    if info.equipLoc
        == "INVTYPE_HOLDABLE"
    then
        return "OFFHAND"
    end

    return nil
end

function WGRGetSpecWeaponProfile(characterName, specID)
    local mode = WGRGetCharacterWeaponMode(characterName)
    local baseline = WGRGetSpecWeaponBaseline(characterName, specID)

    if mode == "SAVED" then
        if baseline
            and baseline.weaponConfigState == "INITIALIZED"
            and baseline.weaponConfig
            and baseline.weaponConfig ~= "UNKNOWN"
        then
            return "SAVED_SETUP", baseline
        end

        local inherited =
            WGRGetInheritedWeaponBaseline(
                characterName,
                specID
            )

        if inherited then
            return "SAVED_SETUP", inherited
        end

        return "ALL_ELIGIBLE", baseline
    end

    if mode == "CUSTOM" then
        return "CUSTOM", baseline
    end

    return "ALL_ELIGIBLE", baseline
end

local function WGRWeaponFitsInitializedConfig(itemLink, baseline, comparisonType)
    if not baseline
        or not baseline.weaponConfig
        or baseline.weaponConfig == "UNKNOWN"
    then
        return true
    end

    local state = baseline.weaponConfigState

    if state ~= "INITIALIZED"
        and state ~= "INHERITED_COMPLETE"
        and state ~= "INHERITED_PARTIAL"
        and state ~= "DATASTORE_FALLBACK"
    then
        return true
    end

    return WGRItemMatchesWeaponConfig(
        itemLink,
        baseline.weaponConfig,
        comparisonType
    )
end

function WGRSpecAllowsWeaponByProfile(characterName, specID, itemLink, comparisonType)
    local profile,baseline=WGRGetSpecWeaponProfile(characterName,specID)
    if profile=="SAVED_SETUP" then return WGRWeaponFitsInitializedConfig(itemLink,baseline,comparisonType) end
    if profile=="CUSTOM" then
        local pref=WGRGetCustomWeaponPreference(characterName,specID)
        if pref~="ALL" then return WGRItemMatchesWeaponConfig(itemLink,pref,comparisonType) end
    end
    -- Global restrictions are defaults; a conflicting explicit Custom choice overrides them.
    if specID==72 and WarboundGearRouterDB.routingSettings.preferDual2HForFury==true and not WGRCustomSelectionOverridesGlobal(characterName,specID) then
        return WGRItemMatchesWeaponConfig(itemLink,"DUAL_2H",comparisonType)
    end
    if (specID==577 or specID==581 or specID==1480) and WarboundGearRouterDB.routingSettings.preferWarglaivesForDemonHunters==true and not WGRCustomSelectionOverridesGlobal(characterName,specID) then
        return IsWarglaiveItem(itemLink)
    end
    return true
end

function WGRItemFitsSpecificSpec(
    itemLink,
    classID,
    specID
)
    -- Fury can still use dual 1H Strength weapons even when Blizzard's
    -- DoesItemContainSpec result does not expose them as Fury loot.
    -- Treat that supported configuration as spec-eligible explicitly.
    if classID == 1
        and specID == 72
        and GetWeaponKind(itemLink) == "ONE_HAND"
    then
        local stats = nil

        if C_Item
            and C_Item.GetItemStats
        then
            stats =
                C_Item.GetItemStats(
                    itemLink
                )
        elseif GetItemStats then
            stats =
                GetItemStats(
                    itemLink
                )
        end

        if stats then
            local hasStrength =
                (
                    stats["ITEM_MOD_STRENGTH_SHORT"]
                    and stats["ITEM_MOD_STRENGTH_SHORT"] > 0
                )
                or (
                    stats["ITEM_MOD_STRENGTH_AGILITY_SHORT"]
                    and stats["ITEM_MOD_STRENGTH_AGILITY_SHORT"] > 0
                )
                or (
                    stats["ITEM_MOD_STRENGTH_INTELLECT_SHORT"]
                    and stats["ITEM_MOD_STRENGTH_INTELLECT_SHORT"] > 0
                )
                or (
                    stats["ITEM_MOD_STRENGTH_AGILITY_INTELLECT_SHORT"]
                    and stats["ITEM_MOD_STRENGTH_AGILITY_INTELLECT_SHORT"] > 0
                )

            if hasStrength then
                return true
            end
        end
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

local function WGRGetCompleteWeaponSetupLevel(
    baseline
)
    if not baseline
        or not baseline.weaponConfig
    then
        return nil
    end

    local main =
        tonumber(
            baseline.mainHandLevel
        )
        or 0

    local off =
        tonumber(
            baseline.offHandLevel
        )
        or 0

    local config =
        baseline.weaponConfig

    if config == "RANGED"
        or config == "TWO_HAND"
        or config == "ONE_HAND"
    then
        return main > 0
            and main
            or nil
    end

    if config == "DUAL_1H"
        or config == "DUAL_2H"
        or config == "ONE_HAND_PLUS_SHIELD"
        or config == "ONE_HAND_PLUS_OFFHAND"
    then
        if main > 0
            and off > 0
        then
            return
                (
                    main
                    + off
                )
                / 2
        end

        return nil
    end

    return nil
end

local function WGRGetBestCompatibleSavedOffhandLevel(
    characterName,
    classID,
    targetSpecID,
    itemLink
)
    InitializeDatabase()

    WGRRepairLegacyWeaponBaselineLevelsForCharacter(
        characterName
    )

    if not characterName
        or not classID
        or not targetSpecID
        or not itemLink
    then
        return nil
    end

    local incomingKind =
        WGRGetOffhandKind(
            itemLink
        )

    if incomingKind ~= "SHIELD"
        and incomingKind ~= "OFFHAND"
    then
        return nil
    end

    local byCharacter =
        WarboundGearRouterDB.specWeaponBaselines[
            string.lower(
                characterName
            )
        ]

    if not byCharacter then
        return nil
    end

    local bestLevel = nil

    for _, baseline
        in pairs(
            byCharacter
        )
    do
        if baseline
            and baseline.offHand
            and tonumber(
                baseline.offHandLevel
            )
            and tonumber(
                baseline.offHandLevel
            ) > 0
            and WGRBaselineComponentFitsSpec(
                baseline.offHand,
                classID,
                targetSpecID,
                incomingKind
            )
        then
            local level =
                tonumber(
                    baseline.offHandLevel
                )

            if not bestLevel
                or level > bestLevel
            then
                bestLevel = level
            end
        end
    end

    return bestLevel
end


-- Return the weapon configurations whose saved baselines are relevant for
-- this character/spec's current weapon preference.  Baseline selection must
-- follow the same preference rules as routing: All Eligible considers every
-- legal setup, Custom can narrow the setup, and Saved Setup follows the
-- recorded/inherited setup when one is available.
local function WGRGetAllowedBaselineConfigs(
    characterName,
    specID
)
    local eligible =
        WGRSpecEligibleWeaponConfigs[specID]
        or {}

    local mode =
        WGRGetCharacterWeaponMode(
            characterName
        )

    if mode == "SAVED" then
        local profile,
              baseline =
            WGRGetSpecWeaponProfile(
                characterName,
                specID
            )

        if profile == "SAVED_SETUP"
            and baseline
            and baseline.weaponConfig
            and baseline.weaponConfig ~= "UNKNOWN"
        then
            return {
                baseline.weaponConfig,
            }
        end

        -- Saved Setup deliberately falls back to All Eligible when there is
        -- no initialized or inheritable setup yet.
        return eligible
    end

    if mode == "CUSTOM" then
        local pref =
            WGRGetCustomWeaponPreference(
                characterName,
                specID
            )

        if pref
            and pref ~= "ALL"
        then
            return {
                pref,
            }
        end
    end

    -- Global Fury preference is a setup preference, not different math.
    if specID == 72
        and WarboundGearRouterDB.routingSettings.preferDual2HForFury == true
        and not WGRCustomSelectionOverridesGlobal(
            characterName,
            specID
        )
    then
        return {
            "DUAL_2H",
        }
    end

    return eligible
end


-- Public copy of the configuration list used by routing/baseline math. Gear
-- Finder uses this to render exactly the setups allowed by the character's
-- current All Eligible / Saved Setup / Custom preference.
function WGRGetAllowedSpecWeaponConfigs(characterName, specID)
    local source = WGRGetAllowedBaselineConfigs(characterName, specID) or {}
    local result = {}
    for _, config in ipairs(source) do
        result[#result + 1] = config
    end
    return result
end

-- Return the strongest KNOWN setup WGR can construct for one specific
-- configuration. Unlike the effective-baseline helper, this may return a
-- partial setup. It only uses deliberate saved/equipped baseline knowledge;
-- arbitrary Soulbound items sitting in storage are never promoted here.
function WGRGetKnownWeaponSetupForConfig(characterName, character, specID, targetConfig)
    InitializeDatabase()
    if not characterName or not specID or not targetConfig then
        return nil, "uninitialized"
    end

    WGRRepairLegacyWeaponBaselineLevelsForCharacter(characterName)

    local best = nil
    local bestComplete = false
    local bestScore = -1
    local bestSourceSpecID = nil

    local function consider(sourceBaseline, sourceSpecID)
        if not sourceBaseline then return end
        local candidate = WGRBuildInheritedCandidate(
            characterName,
            specID,
            sourceBaseline,
            targetConfig
        )
        if not candidate then return end

        local complete = candidate.inheritedComplete == true
        local score
        if complete then
            score = WGRGetCompleteWeaponSetupLevel(candidate) or 0
        else
            local total, count = 0, 0
            local mh = tonumber(candidate.mainHandLevel) or 0
            local oh = tonumber(candidate.offHandLevel) or 0
            if mh > 0 then total = total + mh; count = count + 1 end
            if oh > 0 then total = total + oh; count = count + 1 end
            score = count > 0 and (total / count) or 0
        end

        if score <= 0 then return end
        if (complete and not bestComplete)
            or (complete == bestComplete and score > bestScore)
        then
            best = candidate
            bestComplete = complete
            bestScore = score
            bestSourceSpecID = sourceSpecID
        end
    end

    local byCharacter = WarboundGearRouterDB.specWeaponBaselines[
        string.lower(characterName or "")
    ]
    if type(byCharacter) == "table" then
        for sourceSpecKey, sourceBaseline in pairs(byCharacter) do
            local sourceSpecID = tonumber(sourceSpecKey)
                or tonumber(sourceBaseline and sourceBaseline.specID)
            if sourceBaseline
                and sourceBaseline.weaponConfigState == "INITIALIZED"
            then
                consider(sourceBaseline, sourceSpecID)
            end
        end
    end

    local dataStoreBaseline = WGRBuildDataStoreWeaponBaseline(
        characterName,
        character,
        specID
    )
    if dataStoreBaseline then
        consider(dataStoreBaseline, specID)
    end

    if not best then
        return nil, "uninitialized"
    end

    best.effectiveSetupLevel = bestComplete
        and (WGRGetCompleteWeaponSetupLevel(best) or 0)
        or nil

    if bestSourceSpecID == specID then
        best.inherited = false
        best.inheritedFromSpecID = nil
        best.inheritedFromSpecName = nil
    end

    return best, bestComplete and "known" or "partial"
end


-- Build the strongest complete setup the character can assemble from
-- confirmed Soulbound weapon components WGR has physically observed in that
-- character's equipped slots, Bags, and Personal Bank. Components may come
-- from different specs (for
-- example Holy's Int 1H plus Protection's shield). This cache is maintained by
-- the existing dirty-container snapshot path, so routing does not rescan storage.
local function WGRBuildBestOwnedWeaponSetupForSpec(
    characterName,
    character,
    specID,
    allowedConfigs
)
    InitializeDatabase()

    if not characterName or not specID then
        return nil, nil
    end

    local configKeyParts = {}
    for _, config in ipairs(allowedConfigs or {}) do
        configKeyParts[#configKeyParts + 1] = tostring(config)
    end
    local cacheKey = string.lower(characterName)
        .. "\031" .. tostring(specID)
        .. "\031" .. table.concat(configKeyParts, ",")
    local evalCache = WGRGetRoutingEvaluationCache and WGRGetRoutingEvaluationCache() or nil
    if evalCache and evalCache.ownedWeaponSetups then
        local cached = evalCache.ownedWeaponSetups[cacheKey]
        if cached ~= nil then
            if cached == false then return nil, nil end
            return cached.level, cached.baseline
        end
    end

    local key = string.lower(characterName)
    local owned = WarboundGearRouterDB.ownedWeaponComponents
        and WarboundGearRouterDB.ownedWeaponComponents[key]
        or nil

    if type(owned) ~= "table" then
        if evalCache and evalCache.ownedWeaponSetups then
            evalCache.ownedWeaponSetups[cacheKey] = false
        end
        return nil, nil
    end

    local classID = GetCharacterClassID(characterName, character)
    if not classID then
        return nil, nil
    end

    local components = {}
    local function append(list)
        for _, data in ipairs(list or {}) do
            if data
                and data.link
                and (tonumber(data.level) or 0) > 0
            then
                components[#components + 1] = data
            end
        end
    end

    append(owned.equipped)
    append(owned.bags)
    append(owned.bank)

    if #components == 0 then
        if evalCache and evalCache.ownedWeaponSetups then
            evalCache.ownedWeaponSetups[cacheKey] = false
        end
        return nil, nil
    end

    local function bestOfKind(kind, count)
        local matches = {}
        for _, data in ipairs(components) do
            if WGRBaselineComponentFitsSpec(
                data.link,
                classID,
                specID,
                kind
            ) then
                matches[#matches + 1] = data
            end
        end

        table.sort(matches, function(a, b)
            return (tonumber(a.level) or 0) > (tonumber(b.level) or 0)
        end)

        local result = {}
        for index = 1, math.min(count or 1, #matches) do
            result[#result + 1] = matches[index]
        end
        return result
    end

    local bestLevel = nil
    local best = nil

    local function consider(config)
        local main, off

        if config == "RANGED" then
            main = bestOfKind("RANGED", 1)[1]
        elseif config == "TWO_HAND" then
            main = bestOfKind("TWO_HAND", 1)[1]
        elseif config == "ONE_HAND" then
            main = bestOfKind("ONE_HAND", 1)[1]
        elseif config == "DUAL_1H" then
            local items = bestOfKind("ONE_HAND", 2)
            main, off = items[1], items[2]
        elseif config == "DUAL_2H" then
            local items = bestOfKind("TWO_HAND", 2)
            main, off = items[1], items[2]
        elseif config == "ONE_HAND_PLUS_SHIELD" then
            main = bestOfKind("ONE_HAND", 1)[1]
            off = bestOfKind("SHIELD", 1)[1]
        elseif config == "ONE_HAND_PLUS_OFFHAND" then
            main = bestOfKind("ONE_HAND", 1)[1]
            off = bestOfKind("OFFHAND", 1)[1]
        end

        local paired =
            config == "DUAL_1H"
            or config == "DUAL_2H"
            or config == "ONE_HAND_PLUS_SHIELD"
            or config == "ONE_HAND_PLUS_OFFHAND"

        if not main or (paired and not off) then
            return
        end

        local candidate = {
            specID = specID,
            specName = WGRSpecNamesByID[specID],
            mainHand = main.link,
            mainHandLevel = tonumber(main.level) or 0,
            offHand = off and off.link or nil,
            offHandLevel = off and (tonumber(off.level) or 0) or 0,
            weaponConfig = config,
            weaponConfigState = "OWNED_COMPLETE",
            missingMainHand = false,
            missingOffHand = false,
            ownedComplete = true,
            updated = tonumber(owned.updated) or 0,
        }

        local level = WGRGetCompleteWeaponSetupLevel(candidate)
        if level and level > 0 and (not bestLevel or level > bestLevel) then
            bestLevel = level
            best = candidate
        end
    end

    for _, config in ipairs(allowedConfigs or {}) do
        consider(config)
    end

    if best then
        best.effectiveSetupLevel = bestLevel
    end

    if evalCache and evalCache.ownedWeaponSetups then
        evalCache.ownedWeaponSetups[cacheKey] = best and {
            level = bestLevel,
            baseline = best,
        } or false
    end

    return bestLevel, best
end

-- Build the strongest COMPLETE weapon setup WGR can legitimately prove for
-- one spec. Saved per-spec records remain intact, while the physical owned-
-- Soulbound owned-weapon cache may raise the routing floor when the character
-- can assemble a stronger compatible setup from committed equipped/BAG/PBK
-- components. Transferable Warbound/BoE candidates never participate.
--
-- This is intentionally setup-based:
--   2H/Ranged                     = item level
--   1H + OH/Shield, Dual 1H/2H   = average of the two components
--
-- Incomplete setups do not average a missing component as zero; they simply
-- are not a complete effective baseline.
local function WGRGetBestKnownCompleteWeaponBaseline(
    characterName,
    character,
    specID
)
    InitializeDatabase()

    WGRRepairLegacyWeaponBaselineLevelsForCharacter(
        characterName
    )

    local allowedConfigs =
        WGRGetAllowedBaselineConfigs(
            characterName,
            specID
        )

    local allowed = {}
    for _, config
        in ipairs(
            allowedConfigs
            or {}
        )
    do
        allowed[config] = true
    end

    local bestLevel = nil
    local bestBaseline = nil
    local bestSourceSpecID = nil

    local function consider(
        sourceBaseline,
        sourceSpecID,
        targetConfig
    )
        if not sourceBaseline
            or not targetConfig
            or not allowed[targetConfig]
        then
            return
        end

        local candidate =
            WGRBuildInheritedCandidate(
                characterName,
                specID,
                sourceBaseline,
                targetConfig
            )

        if not candidate
            or not candidate.inheritedComplete
        then
            return
        end

        local level =
            WGRGetCompleteWeaponSetupLevel(
                candidate
            )

        if not level
            or level <= 0
        then
            return
        end

        if not bestLevel
            or level > bestLevel
        then
            bestLevel = level
            bestBaseline = candidate
            bestSourceSpecID = sourceSpecID
        end
    end

    local byCharacter =
        WarboundGearRouterDB.specWeaponBaselines[
            string.lower(
                characterName
                or ""
            )
        ]

    if type(byCharacter) == "table" then
        for sourceSpecKey,
            sourceBaseline
            in pairs(byCharacter)
        do
            local sourceSpecID =
                tonumber(sourceSpecKey)
                or tonumber(
                    sourceBaseline
                    and sourceBaseline.specID
                )

            if sourceBaseline
                and sourceBaseline.weaponConfigState == "INITIALIZED"
            then
                for _, targetConfig
                    in ipairs(
                        allowedConfigs
                        or {}
                    )
                do
                    consider(
                        sourceBaseline,
                        sourceSpecID,
                        targetConfig
                    )
                end
            end
        end
    end

    -- A compatible currently-equipped DataStore setup remains a safe
    -- fallback when WGR has no stronger saved setup.  This is equipment the
    -- character is actually wearing, not an arbitrary item found in storage.
    local dataStoreBaseline =
        WGRBuildDataStoreWeaponBaseline(
            characterName,
            character,
            specID
        )

    if dataStoreBaseline
        and allowed[
            dataStoreBaseline.weaponConfig
        ]
    then
        local dataStoreLevel =
            WGRGetCompleteWeaponSetupLevel(
                dataStoreBaseline
            )

        if dataStoreLevel
            and dataStoreLevel > 0
            and (
                not bestLevel
                or dataStoreLevel > bestLevel
            )
        then
            bestLevel = dataStoreLevel
            bestBaseline = dataStoreBaseline
            bestSourceSpecID = specID
        end
    end

    -- Physical ownership can produce a stronger complete setup than any one
    -- saved spec baseline, including a setup assembled from components first
    -- seen under different specs. This is a cache lookup only; no storage scan
    -- happens during routing.
    local ownedLevel, ownedBaseline =
        WGRBuildBestOwnedWeaponSetupForSpec(
            characterName,
            character,
            specID,
            allowedConfigs
        )

    if ownedLevel
        and ownedLevel > 0
        and (not bestLevel or ownedLevel > bestLevel)
    then
        bestLevel = ownedLevel
        bestBaseline = ownedBaseline
        bestSourceSpecID = nil
    end

    if not bestLevel then
        return 0, nil, "uninitialized"
    end

    if bestBaseline then
        bestBaseline.effectiveSetupLevel =
            bestLevel

        -- WGRBuildInheritedCandidate labels even same-spec projections as
        -- inherited.  For effective-baseline diagnostics, inheritance means
        -- the winning record actually came from another spec.
        if bestSourceSpecID == specID then
            bestBaseline.inherited = false
            bestBaseline.inheritedFromSpecID = nil
            bestBaseline.inheritedFromSpecName = nil
        end
    end

    return bestLevel, bestBaseline, "known"
end


-- Public helper for the upcoming Custom Weapons baseline display/reset UI and
-- for diagnostics.  It returns the effective complete setup baseline for one
-- spec, after weapon-mode preferences are applied.
function WGRGetEffectiveSpecWeaponBaseline(
    characterName,
    character,
    specID
)
    return
        WGRGetBestKnownCompleteWeaponBaseline(
            characterName,
            character,
            specID
        )
end

-- Return whether an authoritative saved setup is still physically represented
-- in the character's confirmed Soulbound-owned component cache. This prevents
-- an old per-spec baseline from continuing to raise routing after those exact
-- weapons have been sold, destroyed, mailed away, or otherwise removed.
--
-- If this character has not yet been physically observed by the Soulbound
-- ownership system, return nil so routing can conservatively keep using the
-- historical saved baseline (important for offline/legacy characters).
local function WGRSavedWeaponBaselineStillOwned(characterName, baseline)
    if not characterName or not baseline then
        return nil
    end

    local ownedTable = WarboundGearRouterDB.ownedWeaponComponents
    local owned = ownedTable and ownedTable[string.lower(characterName)] or nil
    if type(owned) ~= "table" then
        return nil
    end

    local hasObservation = owned.equippedObserved == true
        or owned.bagsObserved == true
        or owned.bankObserved == true
    if not hasObservation then
        return nil
    end

    local counts = {}
    local function add(list)
        for _, data in ipairs(list or {}) do
            local link = data and data.link
            if link then
                local itemID = GetItemInfoInstant and select(1, GetItemInfoInstant(link)) or nil
                local key = itemID and ("id:" .. tostring(itemID)) or ("link:" .. tostring(link))
                counts[key] = (counts[key] or 0) + 1
            end
        end
    end

    add(owned.equipped)
    add(owned.bags)
    add(owned.bank)

    local function consume(link)
        if not link then return false end
        local itemID = GetItemInfoInstant and select(1, GetItemInfoInstant(link)) or nil
        local key = itemID and ("id:" .. tostring(itemID)) or ("link:" .. tostring(link))
        local count = counts[key] or 0
        if count <= 0 then return false end
        counts[key] = count - 1
        return true
    end

    local config = baseline.weaponConfig
    if config == "RANGED" or config == "TWO_HAND" or config == "ONE_HAND" then
        return consume(baseline.mainHand)
    end

    if config == "DUAL_1H"
        or config == "DUAL_2H"
        or config == "ONE_HAND_PLUS_SHIELD"
        or config == "ONE_HAND_PLUS_OFFHAND"
    then
        return consume(baseline.mainHand) and consume(baseline.offHand)
    end

    return false
end

-- Routing-specific complete weapon baseline. Unlike the broader effective
-- baseline helper above, this must never borrow another spec's historical
-- saved setup. Cross-spec routing protection comes only from components that
-- are physically confirmed Soulbound-owned right now. The target spec may
-- use its own saved baseline only while it is still physically represented
-- (or before ownership has ever been observed), plus a compatible currently-
-- equipped DataStore setup and the Soulbound-owned component cache.
function WGRGetRoutingSpecWeaponBaseline(
    characterName,
    character,
    specID
)
    InitializeDatabase()

    WGRRepairLegacyWeaponBaselineLevelsForCharacter(characterName)

    local allowedConfigs = WGRGetAllowedBaselineConfigs(characterName, specID) or {}
    local allowed = {}
    for _, config in ipairs(allowedConfigs) do
        allowed[config] = true
    end

    local bestLevel = nil
    local bestBaseline = nil

    -- Only this spec's own authoritative saved baseline may contribute
    -- historical state to its routing floor.
    local byCharacter =
        WarboundGearRouterDB.specWeaponBaselines[string.lower(characterName or "")]
    local ownBaseline = byCharacter and (byCharacter[specID] or byCharacter[tostring(specID)])

    if ownBaseline and ownBaseline.weaponConfigState == "INITIALIZED" then
        local stillOwned = WGRSavedWeaponBaselineStillOwned(characterName, ownBaseline)
        -- nil means this character has not yet been observed by the new
        -- Soulbound ownership cache, so preserve the historical baseline as a
        -- conservative fallback until WBGR has physical evidence. false means
        -- the character has been observed and the saved setup is no longer
        -- physically present, so it must not raise routing.
        if stillOwned ~= false then
            for _, targetConfig in ipairs(allowedConfigs) do
                local candidate = WGRBuildInheritedCandidate(
                    characterName,
                    specID,
                    ownBaseline,
                    targetConfig
                )
                if candidate and candidate.inheritedComplete then
                    local level = WGRGetCompleteWeaponSetupLevel(candidate)
                    if level and level > 0 and (not bestLevel or level > bestLevel) then
                        bestLevel = level
                        bestBaseline = candidate
                        bestBaseline.inherited = false
                        bestBaseline.inheritedFromSpecID = nil
                        bestBaseline.inheritedFromSpecName = nil
                    end
                end
            end
        end
    end

    -- A currently-equipped compatible DataStore setup is physical evidence,
    -- not historical cross-spec inheritance.
    local dataStoreBaseline =
        WGRBuildDataStoreWeaponBaseline(characterName, character, specID)
    if dataStoreBaseline and allowed[dataStoreBaseline.weaponConfig] then
        local level = WGRGetCompleteWeaponSetupLevel(dataStoreBaseline)
        if level and level > 0 and (not bestLevel or level > bestLevel) then
            bestLevel = level
            bestBaseline = dataStoreBaseline
        end
    end

    -- Cross-spec improvement is allowed only through components that are
    -- currently confirmed Soulbound-owned by this character.
    local ownedLevel, ownedBaseline =
        WGRBuildBestOwnedWeaponSetupForSpec(
            characterName,
            character,
            specID,
            allowedConfigs
        )
    if ownedLevel and ownedLevel > 0 and (not bestLevel or ownedLevel > bestLevel) then
        bestLevel = ownedLevel
        bestBaseline = ownedBaseline
    end

    if not bestLevel then
        return 0, nil, "uninitialized"
    end

    if bestBaseline then
        bestBaseline.effectiveSetupLevel = bestLevel
    end

    return bestLevel, bestBaseline, "known"
end

-- Diagnostic/public read-only helper. Returns the strongest complete setup
-- that can be assembled from the character's cached physically owned weapon
-- components for the requested spec. This never scans storage.
function WGRGetOwnedCompatibleWeaponSetupForSpec(
    characterName,
    character,
    specID
)
    local allowedConfigs =
        WGRGetAllowedBaselineConfigs(
            characterName,
            specID
        )

    return
        WGRBuildBestOwnedWeaponSetupForSpec(
            characterName,
            character,
            specID,
            allowedConfigs
        )
end


-- Build a deliberate replacement baseline for the Reset button in Custom
-- Weapons. Current equipped components always take precedence. Only missing
-- components may be inherited from ONE compatible saved spec. Random
-- Soulbound items merely sitting in storage never participate.
function WGRBuildResetWeaponBaseline(
    characterName,
    specID,
    currentMain,
    currentOff,
    currentMainLevel,
    currentOffLevel
)
    InitializeDatabase()

    local character = FindCharacterByName(characterName)
    local classID = GetCharacterClassID(characterName, character)
    if not classID or not specID then
        return nil
    end

    local allowedConfigs = WGRGetAllowedBaselineConfigs(characterName, specID) or {}
    local currentItems = {
        { link = currentMain, level = tonumber(currentMainLevel) or 0, token = "CMH" },
        { link = currentOff, level = tonumber(currentOffLevel) or 0, token = "COH" },
    }

    local byCharacter =
        WarboundGearRouterDB.specWeaponBaselines[
            string.lower(characterName or "")
        ] or {}

    local sources = { false }
    for sourceSpecKey, sourceBaseline in pairs(byCharacter) do
        local sourceSpecID = tonumber(sourceSpecKey) or tonumber(sourceBaseline and sourceBaseline.specID)
        if sourceBaseline
            and sourceSpecID
            and sourceSpecID ~= specID
            and sourceBaseline.weaponConfigState == "INITIALIZED"
        then
            sources[#sources + 1] = sourceBaseline
        end
    end

    local function itemFits(data, kind)
        return data
            and data.link
            and (tonumber(data.level) or 0) > 0
            and WGRBaselineComponentFitsSpec(data.link, classID, specID, kind)
    end

    local function buildForConfig(config, sourceBaseline)
        local sourceItems = {}
        if sourceBaseline then
            sourceItems = {
                { link = sourceBaseline.mainHand, level = tonumber(sourceBaseline.mainHandLevel) or 0, token = "SMH" },
                { link = sourceBaseline.offHand, level = tonumber(sourceBaseline.offHandLevel) or 0, token = "SOH" },
            }
        end

        local used = {}
        local currentUsed = 0
        local inheritedUsed = 0

        local function consumeMatchingSource(currentData)
            if not currentData or not currentData.link then return end
            for _, sourceData in ipairs(sourceItems) do
                if not used[sourceData.token]
                    and sourceData.link == currentData.link
                    and (tonumber(sourceData.level) or 0) == (tonumber(currentData.level) or 0)
                then
                    -- The inherited record is describing the same physical
                    -- component currently equipped. Consume one matching
                    -- source occurrence so dual-wield reconstruction cannot
                    -- accidentally count that one item twice.
                    used[sourceData.token] = true
                    return
                end
            end
        end

        local function takeFrom(list, kind, isCurrent)
            for _, data in ipairs(list) do
                if not used[data.token] and itemFits(data, kind) then
                    used[data.token] = true
                    if isCurrent then
                        currentUsed = currentUsed + 1
                        consumeMatchingSource(data)
                    else
                        inheritedUsed = inheritedUsed + 1
                    end
                    return data
                end
            end
            return nil
        end

        local function take(kind)
            return takeFrom(currentItems, kind, true)
                or takeFrom(sourceItems, kind, false)
        end

        local main, off
        local missingMain, missingOff = false, false

        if config == "RANGED" then
            main = take("RANGED")
            missingMain = not main
        elseif config == "TWO_HAND" then
            main = take("TWO_HAND")
            missingMain = not main
        elseif config == "DUAL_1H" then
            main = take("ONE_HAND")
            off = take("ONE_HAND")
            missingMain = not main
            missingOff = not off
        elseif config == "DUAL_2H" then
            main = take("TWO_HAND")
            off = take("TWO_HAND")
            missingMain = not main
            missingOff = not off
        elseif config == "ONE_HAND_PLUS_SHIELD" then
            main = take("ONE_HAND")
            off = take("SHIELD")
            missingMain = not main
            missingOff = not off
        elseif config == "ONE_HAND_PLUS_OFFHAND" then
            main = take("ONE_HAND")
            off = take("OFFHAND")
            missingMain = not main
            missingOff = not off
        else
            return nil
        end

        if not main and not off then
            return nil
        end

        local complete = not missingMain and not missingOff
        if config == "RANGED" or config == "TWO_HAND" then
            complete = not missingMain
            missingOff = false
        end

        local mainLevel = main and (tonumber(main.level) or 0) or 0
        local offLevel = off and (tonumber(off.level) or 0) or 0
        local score
        if complete then
            if config == "RANGED" or config == "TWO_HAND" then
                score = mainLevel
            else
                score = (mainLevel + offLevel) / 2
            end
        else
            local total, count = 0, 0
            if mainLevel > 0 then total = total + mainLevel; count = count + 1 end
            if offLevel > 0 then total = total + offLevel; count = count + 1 end
            score = count > 0 and (total / count) or 0
        end

        return {
            specID = specID,
            specName = WGRSpecNamesByID[specID],
            mainHandLevel = mainLevel,
            offHandLevel = offLevel,
            mainHand = main and main.link or nil,
            offHand = off and off.link or nil,
            weaponConfig = config,
            weaponConfigState = complete and "INITIALIZED" or "PARTIAL",
            missingMainHand = missingMain,
            missingOffHand = missingOff,
            updated = time(),
            itemLevelCaptureVersion = 2,
            liveItemLevelCapture = true,
            resetRebuilt = true,
            resetInherited = inheritedUsed > 0,
            inheritedFromSpecID = inheritedUsed > 0 and sourceBaseline and sourceBaseline.specID or nil,
            inheritedFromSpecName = inheritedUsed > 0 and sourceBaseline and (
                sourceBaseline.specName
                or WGRSpecNamesByID[sourceBaseline.specID]
            ) or nil,
            _resetCurrentUsed = currentUsed,
            _resetInheritedUsed = inheritedUsed,
            _resetScore = score or 0,
            _resetComplete = complete,
        }
    end

    local candidates = {}
    local anyUsesCurrent = false
    for _, config in ipairs(allowedConfigs) do
        for _, sourceBaseline in ipairs(sources) do
            local candidate = buildForConfig(config, sourceBaseline or nil)
            if candidate then
                candidates[#candidates + 1] = candidate
                if (candidate._resetCurrentUsed or 0) > 0 then
                    anyUsesCurrent = true
                end
            end
        end
    end

    local best
    for _, candidate in ipairs(candidates) do
        local usesCurrent = (candidate._resetCurrentUsed or 0) > 0
        if (not anyUsesCurrent or usesCurrent) then
            if not best then
                best = candidate
            else
                local aComplete = candidate._resetComplete and 1 or 0
                local bComplete = best._resetComplete and 1 or 0
                local aCurrent = candidate._resetCurrentUsed or 0
                local bCurrent = best._resetCurrentUsed or 0
                local aScore = candidate._resetScore or 0
                local bScore = best._resetScore or 0

                if aComplete > bComplete
                    or (aComplete == bComplete and aCurrent > bCurrent)
                    or (aComplete == bComplete and aCurrent == bCurrent and aScore > bScore)
                then
                    best = candidate
                end
            end
        end
    end

    if best then
        best._resetCurrentUsed = nil
        best._resetInheritedUsed = nil
        best._resetScore = nil
        best._resetComplete = nil
    end

    return best
end


function WGRGetSpecificSpecWeaponComparisonLevel(
    characterName,
    character,
    itemLink,
    comparisonType,
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

    local classCanUse =
        WGRClassCanUseWeaponSubtype(
            classID,
            itemLink
        )

    if classCanUse == false then
        return nil, "not_usable"
    end

    if classCanUse == nil then
        return nil, "unknown"
    end

    local specFits =
        WGRItemFitsSpecificSpec(
            itemLink,
            classID,
            specID
        )

    if specFits == false then
        return nil, "not_usable"
    end

    if specFits == nil then
        return nil, "unknown"
    end

    local profileFits =
        WGRSpecAllowsWeaponByProfile(
            characterName,
            specID,
            itemLink,
            comparisonType
        )

    if profileFits == false then
        return nil, "not_usable"
    end

    if profileFits == nil then
        return nil, "unknown"
    end

    -- Routing eligibility is deliberately generous and per-item.  Every
    -- eligible incoming weapon component is compared against the spec's best
    -- COMPLETE known weapon setup, regardless of whether the incoming item is
    -- a 2H, 1H, shield, caster off-hand, or one half of a dual-wield setup.
    -- Gear Finder will later make the stricter decision about whether a full
    -- candidate setup can actually be equipped as an upgrade.
    local baseline =
        WGRGetRoutingSpecWeaponBaseline(
            characterName,
            character,
            specID
        )

    return baseline or 0, "known"
end


local function WGRGetMultiSpecWeaponBaseline(
    characterName,
    character,
    itemLink,
    comparisonType
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

    local foundUsableSpec = false
    local sawUnknown = false
    local sawIncompleteUsefulSetup = false
    local lowestBaseline = nil

    for _, specID
        in ipairs(specIDs)
    do
        local baseline,
              status =
            WGRGetSpecificSpecWeaponComparisonLevel(
                characterName,
                character,
                itemLink,
                comparisonType,
                specID
            )

        if status == "known" then
            foundUsableSpec = true

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

    if not foundUsableSpec then
        if sawUnknown then
            return nil, "unknown"
        end

        return nil, "not_usable"
    end

    return lowestBaseline or 0, "known"
end

function WGRDebugSpecificSpecWeaponBaseline(
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

    local profile,
          resolvedBaseline =
        WGRGetSpecWeaponProfile(
            characterName,
            specID
        )

    local directBaseline =
        WGRGetSpecWeaponBaseline(
            characterName,
            specID
        )

    local datastoreBaseline =
        WGRBuildDataStoreWeaponBaseline(
            characterName,
            character,
            specID
        )

    local resolvedSource =
        "NONE"

    local chosen =
        nil

    if profile == "SAVED_SETUP"
        and resolvedBaseline
    then
        resolvedSource =
            "SAVED_SETUP"
        chosen =
            resolvedBaseline
    elseif directBaseline then
        resolvedSource =
            "DIRECT_BASELINE"
        chosen =
            directBaseline
    elseif datastoreBaseline then
        resolvedSource =
            "DATASTORE"
        chosen =
            datastoreBaseline
    end

    local comparisonLevel,
          comparisonStatus =
        WGRGetSpecificSpecWeaponComparisonLevel(
            characterName,
            character,
            itemLink,
            "WEAPON",
            specID
        )

    return {
        characterName =
            characterName,
        specID =
            specID,
        classID =
            classID,
        profile =
            profile,
        resolvedSource =
            resolvedSource,
        chosen =
            chosen,
        directBaseline =
            directBaseline,
        resolvedBaseline =
            resolvedBaseline,
        datastoreBaseline =
            datastoreBaseline,
        comparisonLevel =
            comparisonLevel,
        comparisonStatus =
            comparisonStatus,
    }
end

-- Return the ACTUAL complete-setup improvement produced by an incoming
-- weapon component.  This is deliberately different from subtracting the
-- complete setup baseline from the incoming component's own item level.
--
-- For paired setups the incoming component must first improve the component
-- it would replace, then WGR builds the resulting complete setup and compares
-- that setup against the character/spec's best complete known weapon setup.
-- This prevents (for example) a 266 off-hand from appearing as +5 merely
-- because the current 256 + 266 setup averages 261.
function WGRGetIncomingWeaponUpgradeForSpecificSpec(
    characterName,
    character,
    itemLink,
    newItemLevel,
    comparisonType,
    specID
)
    newItemLevel = tonumber(newItemLevel) or 0
    if newItemLevel <= 0 then
        return nil, "unknown"
    end

    local overallBaseline, status =
        WGRGetSpecificSpecWeaponComparisonLevel(
            characterName,
            character,
            itemLink,
            comparisonType,
            specID
        )

    -- Keep the existing comparison-status behavior above, but also retain
    -- the winning complete baseline record so tooltip wording can distinguish
    -- "this candidate is averaged" from "this 2H is measured over an
    -- existing paired weapon average."
    local _, baselineRecord =
        WGRGetRoutingSpecWeaponBaseline(
            characterName,
            character,
            specID
        )

    if status ~= "known" then
        return nil, status
    end

    overallBaseline = tonumber(overallBaseline) or 0
    local bestUpgrade = nil
    local bestUsesAverage = false
    local bestIsOverAverage = false
    local sawMatchingConfig = false
    local sawIncompleteUsefulSetup = false

    for _, config in ipairs(
        WGRGetAllowedSpecWeaponConfigs(characterName, specID) or {}
    ) do
        if WGRItemMatchesWeaponConfig(itemLink, config, comparisonType) then
            sawMatchingConfig = true

            local known =
                WGRGetKnownWeaponSetupForConfig(
                    characterName,
                    character,
                    specID,
                    config
                )

            local main = tonumber(known and known.mainHandLevel) or 0
            local off = tonumber(known and known.offHandLevel) or 0

            -- Incoming paired components must be evaluated with the strongest
            -- compatible Soulbound partner the character physically owns, not
            -- merely whichever historical saved setup WGR happened to select.
            -- The routing floor already uses this owned state; using the same
            -- partner here prevents a strong incoming off-hand/shield from
            -- being undervalued because an older spec record has a weak 1H
            -- (and vice versa). Transferable Warbound/BoE items are excluded
            -- by the Soulbound-only owned-component cache.
            local ownedConfigLevel, ownedConfig =
                WGRBuildBestOwnedWeaponSetupForSpec(
                    characterName,
                    character,
                    specID,
                    { config }
                )

            if ownedConfigLevel and ownedConfig then
                main = math.max(
                    main,
                    tonumber(ownedConfig.mainHandLevel) or 0
                )
                off = math.max(
                    off,
                    tonumber(ownedConfig.offHandLevel) or 0
                )
            end

            -- A freshly equipped half of an otherwise uninitialized paired
            -- setup is intentionally not written into the authoritative saved
            -- baseline until the setup is complete. For routing the current
            -- character's active spec, however, use a compatible live piece
            -- transiently when that known side is missing. This lets equal-ilvl
            -- duplicates reroute instead of remaining false incomplete upgrades.
            local playerName =
                UnitName
                and UnitName("player")

            local currentSpec =
                GetCurrentSpecInfo
                and GetCurrentSpecInfo()

            if playerName
                and characterName
                and string.lower(playerName) == string.lower(characterName)
                and currentSpec
                and tonumber(currentSpec.id) == tonumber(specID)
            then
                local _, _, playerClassID = UnitClass("player")

                if main <= 0 then
                    local liveMain = GetInventoryItemLink("player", 16)
                    local liveMainFit =
                        liveMain
                        and playerClassID
                        and WGRLiveEquippedItemFitsSpec
                        and WGRLiveEquippedItemFitsSpec(
                            liveMain,
                            playerClassID,
                            specID
                        )

                    if liveMainFit == true
                        and WGRItemMatchesWeaponConfig(
                            liveMain,
                            config,
                            "WEAPON"
                        )
                    then
                        main = tonumber(GetItemLevel(liveMain)) or 0
                    end
                end

                if off <= 0 then
                    local liveOff = GetInventoryItemLink("player", 17)
                    local liveOffFit =
                        liveOff
                        and playerClassID
                        and WGRLiveEquippedItemFitsSpec
                        and WGRLiveEquippedItemFitsSpec(
                            liveOff,
                            playerClassID,
                            specID
                        )

                    if liveOffFit == true
                        and WGRItemMatchesWeaponConfig(
                            liveOff,
                            config,
                            "OFFHAND"
                        )
                    then
                        off = tonumber(GetItemLevel(liveOff)) or 0
                    end
                end
            end

            local candidateScore = nil
            local improvesComponent = false

            if config == "RANGED"
                or config == "TWO_HAND"
                or config == "ONE_HAND"
            then
                if comparisonType == "WEAPON" then
                    improvesComponent = main <= 0 or newItemLevel > main
                    if improvesComponent then
                        candidateScore = newItemLevel
                    end
                end

            elseif config == "ONE_HAND_PLUS_OFFHAND"
                or config == "ONE_HAND_PLUS_SHIELD"
            then
                if comparisonType == "WEAPON" then
                    improvesComponent = main <= 0 or newItemLevel > main
                    if improvesComponent and off > 0 then
                        candidateScore = (newItemLevel + off) / 2
                    end
                elseif comparisonType == "OFFHAND" then
                    improvesComponent = off <= 0 or newItemLevel > off
                    if improvesComponent and main > 0 then
                        candidateScore = (main + newItemLevel) / 2
                    end
                end

            elseif config == "DUAL_1H"
                or config == "DUAL_2H"
            then
                if comparisonType == "WEAPON" then
                    if main > 0 and off > 0 then
                        local weaker = math.min(main, off)
                        local stronger = math.max(main, off)
                        improvesComponent = newItemLevel > weaker
                        if improvesComponent then
                            candidateScore = (stronger + newItemLevel) / 2
                        end
                    elseif main > 0 or off > 0 then
                        local partner = math.max(main, off)
                        improvesComponent = true
                        candidateScore = (partner + newItemLevel) / 2
                    end
                end
            end

            local pairedConfig =
                config == "ONE_HAND_PLUS_OFFHAND"
                or config == "ONE_HAND_PLUS_SHIELD"
                or config == "DUAL_1H"
                or config == "DUAL_2H"

            -- A valid paired component can still be useful even when its
            -- partner is not currently known.  Keep this distinct from a
            -- complete candidate: routing may send the component, while Gear
            -- Finder still waits for a complete setup before recommending an
            -- equip action.  Compare the incoming component against both the
            -- known same-slot component and any complete routing floor so we
            -- do not resurrect weaker partial alternatives below a proven
            -- complete setup.
            local missingPartnerForIncoming = false
            local currentComponentLevel = 0

            if config == "ONE_HAND_PLUS_OFFHAND"
                or config == "ONE_HAND_PLUS_SHIELD"
            then
                if comparisonType == "WEAPON" then
                    missingPartnerForIncoming = off <= 0
                    currentComponentLevel = main
                elseif comparisonType == "OFFHAND" then
                    missingPartnerForIncoming = main <= 0
                    currentComponentLevel = off
                end
            elseif config == "DUAL_1H"
                or config == "DUAL_2H"
            then
                if comparisonType == "WEAPON" and main <= 0 and off <= 0 then
                    missingPartnerForIncoming = true
                    currentComponentLevel = 0
                end
            end

            if pairedConfig
                and candidateScore == nil
                and missingPartnerForIncoming
                and (
                    currentComponentLevel <= 0
                    or newItemLevel > currentComponentLevel
                )
                and (
                    overallBaseline <= 0
                    or newItemLevel > overallBaseline
                )
            then
                sawIncompleteUsefulSetup = true
            end

            if improvesComponent and candidateScore then
                local upgrade = candidateScore - overallBaseline
                if upgrade > 0
                    and (bestUpgrade == nil or upgrade > bestUpgrade)
                then
                    bestUpgrade = upgrade
                    bestUsesAverage = pairedConfig

                    -- A 2H/ranged item is not itself averaged.  But when it
                    -- replaces a paired baseline, the displayed +X is measured
                    -- OVER the existing weapon average.  Preserve that
                    -- distinction for concise tooltip wording.
                    local baselineConfig =
                        baselineRecord and baselineRecord.weaponConfig
                    local baselineIsPaired =
                        baselineConfig == "ONE_HAND_PLUS_OFFHAND"
                        or baselineConfig == "ONE_HAND_PLUS_SHIELD"
                        or baselineConfig == "DUAL_1H"
                        or baselineConfig == "DUAL_2H"
                    bestIsOverAverage =
                        (config == "TWO_HAND" or config == "RANGED")
                        and baselineIsPaired
                        or false
                end
            end
        end
    end

    if not sawMatchingConfig then
        return nil, "not_usable"
    end

    return bestUpgrade or 0, "known", bestUsesAverage, bestIsOverAverage,
        (bestUpgrade == nil and sawIncompleteUsefulSetup) or false
end

function WGRGetIncomingWeaponUpgradeForMode(
    characterName,
    character,
    itemLink,
    newItemLevel,
    comparisonType
)
    local specIDs =
        WGRGetRoutingSpecIDs(characterName, character)

    if not specIDs or #specIDs == 0 then
        return nil, "unknown"
    end

    local bestUpgrade = nil
    local bestUsesAverage = false
    local bestIsOverAverage = false
    local foundUsableSpec = false
    local sawUnknown = false
    local sawIncompleteUsefulSetup = false

    for _, specID in ipairs(specIDs) do
        local upgrade, status, usesAverage, isOverAverage, setupIncomplete =
            WGRGetIncomingWeaponUpgradeForSpecificSpec(
                characterName,
                character,
                itemLink,
                newItemLevel,
                comparisonType,
                specID
            )

        if status == "known" then
            foundUsableSpec = true
            if setupIncomplete == true then
                sawIncompleteUsefulSetup = true
            end
            upgrade = tonumber(upgrade) or 0
            if bestUpgrade == nil or upgrade > bestUpgrade then
                bestUpgrade = upgrade
                bestUsesAverage = usesAverage == true
                bestIsOverAverage = isOverAverage == true
            end
        elseif status == "unknown" then
            sawUnknown = true
        end
    end

    if not foundUsableSpec then
        if sawUnknown then
            return nil, "unknown"
        end
        return nil, "not_usable"
    end

    return bestUpgrade or 0, "known", bestUsesAverage, bestIsOverAverage,
        ((bestUpgrade == nil or bestUpgrade <= 0) and sawIncompleteUsefulSetup) or false
end

function WGRGetWeaponComparisonLevelForMode(
    characterName,
    character,
    itemLink,
    comparisonSlots
)
    return WGRGetMultiSpecWeaponBaseline(characterName, character, itemLink, "WEAPON")
end

function WGRGetOffhandComparisonLevelForMode(
    characterName,
    character,
    itemLink
)
    return WGRGetMultiSpecWeaponBaseline(characterName, character, itemLink, "OFFHAND")
end


local function WGRItemFitsAnyClassSpec(
    itemLink,
    classID
)
    if not classID
        or type(WGRClassSpecIDs) ~= "table"
    then
        return nil
    end

    local specIDs =
        WGRClassSpecIDs[classID]

    if type(specIDs) ~= "table"
        or #specIDs == 0
    then
        return nil
    end

    local sawUnknown = false

    for _, specID
        in ipairs(specIDs)
    do
        local result =
            WGRItemFitsSpecificSpec(
                itemLink,
                classID,
                specID
            )

        if result == true then
            return true
        end

        if result == nil then
            sawUnknown = true
        end
    end

    if sawUnknown then
        return nil
    end

    return false
end


function DoesItemFitRememberedSpec(
    itemLink,
    characterName,
    character
)
    local spec =
        GetRememberedSpec(characterName)

    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    if not classID then
        return nil, "unknown_class"
    end

    local classCanUse =
        WGRClassCanUseWeaponSubtype(
            classID,
            itemLink
        )

    if classCanUse == false then
        return false, "known"
    end

    if classCanUse == nil then
        return nil, "unknown_class"
    end

    if IsWarglaiveItem(
        itemLink
    )
        and classID ~= 12
    then
        return false, "known"
    end

    if not C_Item
        or not
        C_Item.DoesItemContainSpec
    then
        return nil, "api_unavailable"
    end

    local mode =
        WGRGetEffectiveSpecMode(
            characterName
        )

    local specIDs =
        WGRGetRoutingSpecIDs(
            characterName,
            character
        )

    if #specIDs == 0 then
        -- A missing remembered spec should only block routing when the item
        -- could genuinely fit at least one spec of the known class. This
        -- prevents false CHECK results for technically equippable but
        -- spec-inappropriate weapons (for example, an Intellect staff on a
        -- Hunter whose current spec has not been initialized yet).
        local couldFitAnySpec =
            WGRItemFitsAnyClassSpec(
                itemLink,
                classID
            )

        if couldFitAnySpec == false then
            return false, "known"
        end

        if couldFitAnySpec == nil then
            return nil, "api_error"
        end

        return nil, "unknown_spec"
    end

    for _, specID
        in ipairs(specIDs)
    do
        local result =
            WGRItemFitsSpecificSpec(
                itemLink,
                classID,
                specID
            )

        if result == nil then
            return nil, "api_error"
        end

        if result == true then
            local comparisonType =
                WGRGetOffhandKind(
                    itemLink
                )
                and "OFFHAND"
                or "WEAPON"

            if WGRSpecAllowsWeaponByProfile(
                characterName,
                specID,
                itemLink,
                comparisonType
            )
            then
                return true, "known"
            end
        end
    end

    return false, "known"
end

function CouldItemFitUnknownCharacter(
    itemLink,
    characterName,
    character
)
    local classID =
        GetCharacterClassID(
            characterName,
            character
        )

    if not classID then
        return nil
    end

    local classCanUse =
        WGRClassCanUseWeaponSubtype(
            classID,
            itemLink
        )

    if classCanUse == false then
        return false
    end

    if classCanUse == nil then
        return nil
    end

    if IsWarglaiveItem(
        itemLink
    )
        and classID ~= 12
    then
        return false
    end

    return WGRItemFitsAnyClassSpec(
        itemLink,
        classID
    )
end


local function GetItemPrimaryStats(itemLink)
    local result = {
        STRENGTH = false,
        AGILITY = false,
        INTELLECT = false,
    }

    if not itemLink then
        return result
    end

    local stats = nil

    if C_Item and C_Item.GetItemStats then
        stats = C_Item.GetItemStats(itemLink)
    elseif GetItemStats then
        stats = GetItemStats(itemLink)
    end

    if not stats then
        return result
    end

    if stats["ITEM_MOD_STRENGTH_SHORT"]
        and stats["ITEM_MOD_STRENGTH_SHORT"] > 0
    then
        result.STRENGTH = true
    end

    if stats["ITEM_MOD_AGILITY_SHORT"]
        and stats["ITEM_MOD_AGILITY_SHORT"] > 0
    then
        result.AGILITY = true
    end

    if stats["ITEM_MOD_INTELLECT_SHORT"]
        and stats["ITEM_MOD_INTELLECT_SHORT"] > 0
    then
        result.INTELLECT = true
    end

    -- Some items expose combined primary-stat keys.
    -- Accept these when present.
    if stats["ITEM_MOD_STRENGTH_AGILITY_SHORT"]
        and stats["ITEM_MOD_STRENGTH_AGILITY_SHORT"] > 0
    then
        result.STRENGTH = true
        result.AGILITY = true
    end

    if stats["ITEM_MOD_AGILITY_INTELLECT_SHORT"]
        and stats["ITEM_MOD_AGILITY_INTELLECT_SHORT"] > 0
    then
        result.AGILITY = true
        result.INTELLECT = true
    end

    if stats["ITEM_MOD_STRENGTH_INTELLECT_SHORT"]
        and stats["ITEM_MOD_STRENGTH_INTELLECT_SHORT"] > 0
    then
        result.STRENGTH = true
        result.INTELLECT = true
    end

    if stats["ITEM_MOD_STRENGTH_AGILITY_INTELLECT_SHORT"]
        and stats["ITEM_MOD_STRENGTH_AGILITY_INTELLECT_SHORT"] > 0
    then
        result.STRENGTH = true
        result.AGILITY = true
        result.INTELLECT = true
    end

    return result
end

function FutureHolderWeaponMatchesSpec(
    characterName,
    incomingItem
)
    -- v0.45: under-max holders use the exact same Current / All / Custom
    -- spec eligibility path as max-level characters. Level affects only
    -- upgrade-vs-holder evaluation, never weapon eligibility.
    return DoesItemFitRememberedSpec(
        incomingItem,
        characterName,
        FindCharacterByName(characterName)
    )
end

-- ============================================================
-- OFF-HAND CLASSIFICATION
-- ============================================================

local function WGRDetectWeaponConfiguration(
    mainHand,
    offHand
)
    local result = {
        state = "NOT_INITIALIZED",
        config = "UNKNOWN",
        missingMainHand = false,
        missingOffHand = false,
        complete = false,
    }

    if not mainHand
        and not offHand
    then
        return result
    end

    local mainKind =
        mainHand
        and GetWeaponKind(mainHand)
        or nil

    local offWeaponKind =
        offHand
        and GetWeaponKind(offHand)
        or nil

    local offhandKind =
        offHand
        and WGRGetOffhandKind(offHand)
        or nil

    if mainKind == "RANGED" then
        result.state = "INITIALIZED"
        result.config = "RANGED"
        result.complete = true
        return result
    end

    if mainKind == "TWO_HAND" then
        if offWeaponKind == "TWO_HAND" then
            result.state = "INITIALIZED"
            result.config = "DUAL_2H"
            result.complete = true
        else
            result.state = "INITIALIZED"
            result.config = "TWO_HAND"
            result.complete = true
        end

        return result
    end

    if mainKind == "ONE_HAND" then
        if offWeaponKind == "ONE_HAND" then
            result.state = "INITIALIZED"
            result.config = "DUAL_1H"
            result.complete = true
            return result
        end

        if offhandKind == "SHIELD" then
            result.state = "INITIALIZED"
            result.config = "ONE_HAND_PLUS_SHIELD"
            result.complete = true
            return result
        end

        if offhandKind == "OFFHAND" then
            result.state = "INITIALIZED"
            result.config = "ONE_HAND_PLUS_OFFHAND"
            result.complete = true
            return result
        end

        if not offHand then
            result.state = "PARTIAL"
            result.config = "PARTIAL_MAIN_ONLY"
            result.missingOffHand = true
            return result
        end
    end

    if not mainHand
        and offHand
    then
        if offhandKind == "SHIELD" then
            result.state = "PARTIAL"
            result.config = "PARTIAL_SHIELD_ONLY"
            result.missingMainHand = true
            return result
        end

        if offhandKind == "OFFHAND"
            or offWeaponKind == "ONE_HAND"
            or offWeaponKind == "TWO_HAND"
        then
            result.state = "PARTIAL"
            result.config = "PARTIAL_OFFHAND_ONLY"
            result.missingMainHand = true
            return result
        end
    end

    result.state = "PARTIAL"
    result.config = "UNKNOWN"
    return result
end

function WGRDetectWeaponConfigurationForSpec(
    mainHand,
    offHand,
    specID,
    existingBaseline
)
    local detected =
        WGRDetectWeaponConfiguration(
            mainHand,
            offHand
        )

    -- If the spec previously established a multi-slot configuration,
    -- removing one side must not collapse it into a simpler configuration.
    if existingBaseline
        and detected.state ~= "INITIALIZED"
    then
        local previous =
            existingBaseline.weaponConfig

        if previous == "DUAL_2H" then
            if mainHand
                and not offHand
            then
                detected.state = "PARTIAL"
                detected.config = "DUAL_2H"
                detected.complete = false
                detected.missingOffHand = true
                detected.missingMainHand = false
            elseif not mainHand
                and offHand
            then
                detected.state = "PARTIAL"
                detected.config = "DUAL_2H"
                detected.complete = false
                detected.missingMainHand = true
                detected.missingOffHand = false
            end
        elseif previous == "DUAL_1H" then
            if mainHand
                and not offHand
            then
                detected.state = "PARTIAL"
                detected.config = "DUAL_1H"
                detected.complete = false
                detected.missingOffHand = true
                detected.missingMainHand = false
            elseif not mainHand
                and offHand
            then
                detected.state = "PARTIAL"
                detected.config = "DUAL_1H"
                detected.complete = false
                detected.missingMainHand = true
                detected.missingOffHand = false
            end
        elseif previous == "ONE_HAND_PLUS_SHIELD" then
            if mainHand
                and not offHand
            then
                detected.state = "PARTIAL"
                detected.config = "ONE_HAND_PLUS_SHIELD"
                detected.complete = false
                detected.missingOffHand = true
                detected.missingMainHand = false
            elseif not mainHand
                and offHand
            then
                detected.state = "PARTIAL"
                detected.config = "ONE_HAND_PLUS_SHIELD"
                detected.complete = false
                detected.missingMainHand = true
                detected.missingOffHand = false
            end
        elseif previous == "ONE_HAND_PLUS_OFFHAND" then
            if mainHand
                and not offHand
            then
                detected.state = "PARTIAL"
                detected.config = "ONE_HAND_PLUS_OFFHAND"
                detected.complete = false
                detected.missingOffHand = true
                detected.missingMainHand = false
            elseif not mainHand
                and offHand
            then
                detected.state = "PARTIAL"
                detected.config = "ONE_HAND_PLUS_OFFHAND"
                detected.complete = false
                detected.missingMainHand = true
                detected.missingOffHand = false
            end
        end
    end

    -- Fury always requires a dual-2H setup for our Current Equipped profile.
    if specID == 72 then
        if mainHand
            and not offHand
        then
            detected.state = "PARTIAL"
            detected.config = "DUAL_2H"
            detected.complete = false
            detected.missingOffHand = true
            detected.missingMainHand = false
        elseif not mainHand
            and offHand
        then
            detected.state = "PARTIAL"
            detected.config = "DUAL_2H"
            detected.complete = false
            detected.missingMainHand = true
            detected.missingOffHand = false
        end
    end

    return detected
end

function WGRFormatWeaponBaseline(
    baseline
)
    if not baseline then
        return "Not Initialized"
    end

    local config = baseline.weaponConfig
    local state = baseline.weaponConfigState
    local main = tonumber(baseline.mainHandLevel) or 0
    local off = tonumber(baseline.offHandLevel) or 0

    if state == "NOT_INITIALIZED" then
        return "Not Initialized"
    end

    if config == "RANGED"
        or config == "TWO_HAND"
    then
        return WGRWeaponConfigLabels[config]
            .. ": "
            .. tostring(main)
    end

    if config == "DUAL_2H" then
        if state == "PARTIAL" then
            return "MH: "
                .. (
                    baseline.missingMainHand
                    and "Missing"
                    or tostring(main)
                )
                .. " / OH: "
                .. (
                    baseline.missingOffHand
                    and "Missing"
                    or tostring(off)
                )
        end

        return "MH: "
            .. tostring(main)
            .. " / OH: "
            .. tostring(off)
    end

    if config == "DUAL_1H" then
        return "MH: "
            .. tostring(main)
            .. " / OH: "
            .. tostring(off)
    end

    if config == "ONE_HAND_PLUS_SHIELD" then
        return "1H: "
            .. tostring(main)
            .. " / Sh: "
            .. tostring(off)
    end

    if config == "ONE_HAND_PLUS_OFFHAND" then
        return "1H: "
            .. tostring(main)
            .. " / OH: "
            .. tostring(off)
    end

    if config == "PARTIAL_MAIN_ONLY" then
        return "1H: "
            .. tostring(main)
            .. " / OH: Missing"
    end

    if config == "PARTIAL_SHIELD_ONLY" then
        return "1H: Missing / Sh: "
            .. tostring(off)
    end

    if config == "PARTIAL_OFFHAND_ONLY" then
        return "MH: Missing / OH: "
            .. tostring(off)
    end

    return "MH: "
        .. tostring(main)
        .. " / OH: "
        .. tostring(off)
end

function FutureHolderOffhandMatchesSpec(
    characterName,
    incomingItem
)
    -- v0.45: off-hands and shields use the same unified Spec Mode path.
    return DoesItemFitRememberedSpec(
        incomingItem,
        characterName,
        FindCharacterByName(characterName)
    )
end

-- ============================================================
-- DAGGER SPECIALIZATION PRIORITY
--
-- Agility daggers are more restrictive than generic 1H Agility
-- weapons. Subtlety and Assassination Rogues receive priority
-- over flexible 1H Agility users.
-- ============================================================

function IsDaggerItem(itemLink)
    InitializeDatabase()

    if WarboundGearRouterDB.routingSettings.prioritizeRogueAgilityDaggers ~= true then
        return false
    end

    local info =
        GetInstantItemInfo(itemLink)

    if not (
        info
        and info.classID == WGR_ITEM_CLASS_WEAPON
        and info.subclassID == WGR_WEAPON_DAGGER
    ) then
        return false
    end

    local stats =
        GetItemPrimaryStats(itemLink)

    return stats
        and stats.AGILITY == true
end

function IsDaggerSpecialistSpec(
    characterName
)
    local character = FindCharacterByName(characterName)
    local classID = GetCharacterClassID(characterName, character)

    -- Rogue class ID. The preference is intentionally limited to
    -- Assassination and Subtlety, the specs that depend on daggers.
    if classID ~= 4 then
        return false
    end

    local specIDs = WGRGetRoutingSpecIDs(characterName, character)

    for _, specID in ipairs(specIDs or {}) do
        if specID == 259 or specID == 261 then
            return true
        end
    end

    return false
end
