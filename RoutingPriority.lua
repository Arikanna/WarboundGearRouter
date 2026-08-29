-- Saved routing priority, roster membership, ignore/remove state,
-- priority backup/restore, and armor/trinket priority helpers.

-- ============================================================
-- SAVED ROUTING PRIORITY
-- ============================================================

local armorTypeByClassID = {
    [1] = "Plate",       -- Warrior
    [2] = "Plate",       -- Paladin
    [3] = "Mail",        -- Hunter
    [4] = "Leather",     -- Rogue
    [5] = "Cloth",       -- Priest
    [6] = "Plate",       -- Death Knight
    [7] = "Mail",        -- Shaman
    [8] = "Cloth",       -- Mage
    [9] = "Cloth",       -- Warlock
    [10] = "Leather",    -- Monk
    [11] = "Leather",    -- Druid
    [12] = "Leather",    -- Demon Hunter
    [13] = "Mail",       -- Evoker
}

function WGRCopyList(
    source
)
    local copy = {}

    for _, value
        in ipairs(
            source
            or {}
        )
    do
        copy[#copy + 1] =
            value
    end

    return copy
end

local function WGRDiscoverCharacterNames()
    local names = {}
    local seen = {}

    if DataStore
        and DataStore.GetCharacters
    then
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

                if not seen[key] then
                    seen[key] =
                        true

                    names[#names + 1] =
                        name
                end
            end
        end
    end

    table.sort(
        names,
        function(a, b)
            return string.lower(a)
                < string.lower(b)
        end
    )

    return names
end

local function WGRBuildInitialRoutingPriority()
    local discovered =
        WGRDiscoverCharacterNames()

    if #discovered > 0 then
        return discovered
    end

    local currentPlayer =
        UnitName(
            "player"
        )

    if currentPlayer
        and currentPlayer ~= ""
    then
        return {
            currentPlayer,
        }
    end

    return {}
end


local WGRIsCharacterRemoved

local function WGRNormalizeRoutingPriority(
    list
)
    local normalized = {}
    local seen = {}

    -- Preserve every saved character name. DataStore can be partially
    -- populated during login/reload, so a temporarily missing character
    -- must never be deleted from the user's saved routing order.
    for _, name
        in ipairs(
            list
            or {}
        )
    do
        if name
            and tostring(name) ~= ""
        then
            local cleanName =
                tostring(name)

            local key =
                string.lower(
                    cleanName
                )

            if not seen[key]
                and not WGRIsCharacterRemoved(
                    cleanName
                )
            then
                normalized[#normalized + 1] =
                    cleanName

                seen[key] =
                    true
            end
        end
    end

    -- Append newly discovered characters without disturbing existing order.
    for _, name
        in ipairs(
            WGRDiscoverCharacterNames()
        )
    do
        local key =
            string.lower(
                name
            )

        if not seen[key]
            and not WGRIsCharacterRemoved(
                name
            )
        then
            normalized[#normalized + 1] =
                name

            seen[key] =
                true
        end
    end

    return normalized
end

-- Cross-module forward declaration.
GetRoutingPriority = nil
function WGRIsCharacterIgnored(characterName)
    InitializeDatabase()

    if not characterName then
        return false
    end

    return WarboundGearRouterDB.ignoredCharacters[
        string.lower(characterName)
    ] == true
end

function WGRSetCharacterIgnored(characterName, ignored)
    InitializeDatabase()

    if not characterName then
        return
    end

    local key = string.lower(characterName)

    if ignored then
        WarboundGearRouterDB.ignoredCharacters[key] = true
    else
        WarboundGearRouterDB.ignoredCharacters[key] = nil
    end
end


WGRIsCharacterRemoved = function(characterName)
    InitializeDatabase()

    if not characterName then
        return false
    end

    return
        WarboundGearRouterDB.removedCharacters[
            string.lower(characterName)
        ] ~= nil
end

function WGRGetRemovedCharacters()
    InitializeDatabase()

    local removed = {}

    for _, record
        in pairs(
            WarboundGearRouterDB.removedCharacters
        )
    do
        if record
            and record.name
        then
            table.insert(
                removed,
                record
            )
        end
    end

    table.sort(
        removed,
        function(a, b)
            local aIndex =
                tonumber(a.previousIndex)
                or 999999

            local bIndex =
                tonumber(b.previousIndex)
                or 999999

            if aIndex == bIndex then
                return
                    string.lower(a.name)
                    < string.lower(b.name)
            end

            return aIndex < bIndex
        end
    )

    return removed
end

function WGRRemoveCharacter(characterName)
    InitializeDatabase()

    if not characterName
        or characterName == ""
    then
        return false
    end

    local key =
        string.lower(
            characterName
        )

    if WarboundGearRouterDB.removedCharacters[key] then
        return false
    end

    local priority =
        WarboundGearRouterDB.routingPriority
        or GetRoutingPriority()

    local previousIndex = nil

    for index, name
        in ipairs(priority)
    do
        if string.lower(name) == key then
            previousIndex = index
            table.remove(
                priority,
                index
            )
            break
        end
    end

    WarboundGearRouterDB.removedCharacters[key] = {
        name = characterName,
        previousIndex = previousIndex,
        wasIgnored =
            WarboundGearRouterDB.ignoredCharacters[key]
            == true,
        removedAt = time(),
    }

    WarboundGearRouterDB.ignoredCharacters[key] =
        nil

    if WarboundGearRouterDB.characterOverrides then
        -- Preserve character overrides while removed. They will become
        -- active again if the character is restored.
    end

    return true
end

function WGRRestoreRemovedCharacter(characterName)
    InitializeDatabase()

    if not characterName
        or characterName == ""
    then
        return false
    end

    local key =
        string.lower(
            characterName
        )

    local record =
        WarboundGearRouterDB.removedCharacters[key]

    if not record then
        return false
    end

    local priority =
        WarboundGearRouterDB.routingPriority
        or GetRoutingPriority()

    for _, name
        in ipairs(priority)
    do
        if string.lower(name) == key then
            WarboundGearRouterDB.removedCharacters[key] =
                nil
            return true
        end
    end

    local targetIndex =
        tonumber(
            record.previousIndex
        )
        or (#priority + 1)

    targetIndex =
        math.max(
            1,
            math.min(
                targetIndex,
                #priority + 1
            )
        )

    table.insert(
        priority,
        targetIndex,
        record.name
        or characterName
    )

    if record.wasIgnored then
        WarboundGearRouterDB.ignoredCharacters[key] =
            true
    end

    WarboundGearRouterDB.removedCharacters[key] =
        nil

    return true
end

function GetActiveRoutingPriority()
    local active = {}

    for _, characterName in ipairs(GetRoutingPriority()) do
        if not WGRIsCharacterIgnored(characterName)
            and not WGRIsCharacterRemoved(characterName)
        then
            active[#active + 1] = characterName
        end
    end

    return active
end


function WGRGetTrinketRoutingPriority(
    itemLink
)
    local basePriority =
        GetActiveRoutingPriority()

    local specSet,
          specCount =
        WGRGetItemSpecSet(
            itemLink
        )

    -- Conservative fallback: if Blizzard does not expose spec data for
    -- this item, preserve WGR's previous trinket-routing behavior.
    if not specSet
        or specCount == 0
    then
        return basePriority
    end

    local filtered = {}

    for _, characterName
        in ipairs(
            basePriority
        )
    do
        local character =
            FindCharacterByName(
                characterName
            )

        if character
            and WGRCharacterMatchesItemSpecs(
                characterName,
                character,
                specSet
            )
        then
            filtered[
                #filtered + 1
            ] =
                characterName
        end
    end

    return filtered
end


local WGRRoutingPriorityInitialized =
    false

local WGRRoutingPriorityDiscoveryScheduled =
    false

local function WGRRefreshRoutingPriorityDiscovery()
    InitializeDatabase()

    if not WarboundGearRouterDB.routingPriority
        or #WarboundGearRouterDB.routingPriority == 0
    then
        WarboundGearRouterDB.routingPriority =
            WGRBuildInitialRoutingPriority()
    else
        WarboundGearRouterDB.routingPriority =
            WGRNormalizeRoutingPriority(
                WarboundGearRouterDB.routingPriority
            )
    end

    WGRRoutingPriorityInitialized =
        true

    return
        WarboundGearRouterDB.routingPriority
end

local function WGRScheduleRoutingPriorityDiscovery()
    if WGRRoutingPriorityDiscoveryScheduled then
        return
    end

    WGRRoutingPriorityDiscoveryScheduled =
        true

    -- DataStore can finish populating after WGR's first routing read.
    -- Reconcile a few times during startup, then ordinary reads remain cheap.
    for _, delay
        in ipairs(
            {
                1.0,
                3.0,
                6.0,
            }
        )
    do
        C_Timer.After(
            delay,
            function()
                WGRRefreshRoutingPriorityDiscovery()
            end
        )
    end
end

GetRoutingPriority = function()
    InitializeDatabase()

    if not WGRRoutingPriorityInitialized
        or not WarboundGearRouterDB.routingPriority
        or #WarboundGearRouterDB.routingPriority == 0
    then
        WGRRefreshRoutingPriorityDiscovery()
        WGRScheduleRoutingPriorityDiscovery()
    end

    -- Hot path: return the already-normalized saved order directly.
    -- Discovery/normalization is intentionally not repeated for every item.
    return
        WarboundGearRouterDB.routingPriority
end

function WGRPriorityListsEqual(
    a,
    b
)
    if type(a) ~= "table"
        or type(b) ~= "table"
        or #a ~= #b
    then
        return false
    end

    for index = 1, #a do
        if tostring(a[index])
            ~= tostring(b[index])
        then
            return false
        end
    end

    return true
end

function WGRSavePriorityBackup(
    reason
)
    InitializeDatabase()

    local current =
        GetRoutingPriority()

    if not current
        or #current == 0
    then
        return false
    end

    WarboundGearRouterDB.priorityBackup = {
        priority =
            WGRCopyList(
                current
            ),
        timestamp =
            time(),
        reason =
            reason
            or "Manual safety snapshot",
    }

    return true
end

function WGRHasPriorityBackup()
    InitializeDatabase()

    local backup =
        WarboundGearRouterDB.priorityBackup

    return
        type(backup) == "table"
        and type(backup.priority) == "table"
        and #backup.priority > 0
end

function WGRRestorePriorityBackup()
    InitializeDatabase()

    if not WGRHasPriorityBackup() then
        return false
    end

    local backup =
        WarboundGearRouterDB.priorityBackup

    local current =
        WGRCopyList(
            GetRoutingPriority()
        )

    local restored =
        WGRNormalizeRoutingPriority(
            backup.priority
        )

    if not restored
        or #restored == 0
    then
        return false
    end

    WarboundGearRouterDB.routingPriority =
        restored

    -- Swap current and previous so Restore can act as a one-level
    -- undo/redo safety net.
    WarboundGearRouterDB.priorityBackup = {
        priority =
            current,
        timestamp =
            time(),
        reason =
            "Priority before restore",
    }

    return true
end

function WGRPriorityBackupDescription()
    if not WGRHasPriorityBackup() then
        return "No priority backup available."
    end

    local backup =
        WarboundGearRouterDB.priorityBackup

    local reason =
        backup.reason
        or "Priority snapshot"

    return reason
end

function WGRGetRosterInsertSlot(
    rosterContent,
    rowCount
)
    if not rosterContent
        or not rowCount
        or rowCount <= 0
    then
        return nil
    end

    local scale =
        rosterContent:GetEffectiveScale()
        or 1

    local _, cursorY =
        GetCursorPosition()

    cursorY =
        cursorY / scale

    local top =
        rosterContent:GetTop()

    if not top then
        return nil
    end

    local rowHeight = 34
    local offset =
        top - cursorY

    -- rowCount + 1 insertion slots: before first row, between rows,
    -- and after the final row. Rounding chooses the nearest boundary.
    local slot =
        math.floor(
            (offset / rowHeight)
            + 0.5
        ) + 1

    if slot < 1 then
        slot = 1
    elseif slot > rowCount + 1 then
        slot = rowCount + 1
    end

    return slot
end

function WGRMovePriorityToSlot(
    characterName,
    insertSlot
)
    if not characterName
        or not insertSlot
    then
        return false
    end

    local priority =
        GetRoutingPriority()

    local sourceKey =
        string.lower(
            characterName
        )

    local sourceIndex = nil

    for index, name
        in ipairs(priority)
    do
        if string.lower(name)
            == sourceKey
        then
            sourceIndex =
                index
            break
        end
    end

    if not sourceIndex then
        return false
    end

    local movedName =
        table.remove(
            priority,
            sourceIndex
        )

    local adjustedSlot =
        insertSlot

    if sourceIndex < insertSlot then
        adjustedSlot =
            adjustedSlot - 1
    end

    adjustedSlot =
        math.max(
            1,
            math.min(
                adjustedSlot,
                #priority + 1
            )
        )

    table.insert(
        priority,
        adjustedSlot,
        movedName
    )

    return true
end

function WGRMovePriority(
    characterName,
    direction
)
    local priority =
        GetRoutingPriority()

    local wanted =
        string.lower(
            characterName
            or ""
        )

    local index = nil

    for i, name
        in ipairs(priority)
    do
        if string.lower(name)
            == wanted
        then
            index = i
            break
        end
    end

    if not index then
        return false
    end

    local target =
        index + direction

    if target < 1
        or target > #priority
    then
        return false
    end

    priority[index],
    priority[target] =
        priority[target],
        priority[index]

    return true
end

function GetArmorPriorityList(
    armorType
)
    if armorType ~= "Plate"
        and armorType ~= "Mail"
        and armorType ~= "Leather"
        and armorType ~= "Cloth"
    then
        return nil
    end

    local result = {}

    for _, characterName
        in ipairs(
            GetActiveRoutingPriority()
        )
    do
        local character =
            FindCharacterByName(
                characterName
            )

        local classID =
            GetCharacterClassID(
                characterName,
                character
            )

        if classID
            and armorTypeByClassID[
                classID
            ] == armorType
        then
            result[#result + 1] =
                characterName
        end
    end

    return result
end


function PrintSpecs()
    InitializeDatabase()

    print(
        "|cff00ff00Warbound Gear Router - Remembered Specs|r"
    )

    local known = 0
    local unknown = 0

    for _, characterName
        in ipairs(GetActiveRoutingPriority())
    do
        local character =
            FindCharacterByName(characterName)

        local level = nil

        if character
            and DataStore.GetCharacterLevel
        then
            level =
                DataStore:GetCharacterLevel(character)
        end

        local stored =
            WarboundGearRouterDB.specs[
                characterName
            ]

        if stored then
            known = known + 1

            print(string.format(
                "%s - |cff00ff00%s|r%s",
                characterName,
                stored.specName or "Unknown",
                level and
                    string.format(
                        " - Level %d",
                        level
                    )
                    or ""
            ))
        else
            unknown = unknown + 1

            print(string.format(
                "%s - |cff777777spec not recorded yet|r%s",
                characterName,
                level and
                    string.format(
                        " - Level %d",
                        level
                    )
                    or ""
            ))
        end
    end

    print(string.format(
        "|cff00ff00Known specs: %d|r  |cffaaaaaaUnknown: %d|r",
        known,
        unknown
    ))
end
