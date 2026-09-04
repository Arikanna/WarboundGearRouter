-- Equipped-item preloading and slot-level comparison helpers.

-- ============================================================
-- ITEM PRELOADING
-- ============================================================

function PreloadItems(
    priorityList,
    slotIDs,
    callback,
    silent
)
    local waiting = 0
    local finished = false
    local seen = {}

    local function FinishOne()
        waiting = waiting - 1

        if waiting <= 0
            and not finished
        then
            finished = true
            callback()
        end
    end

    for _, characterName
        in ipairs(priorityList)
    do
        local character =
            FindCharacterByName(characterName)

        if character then
            local level =
                WGRGetCharacterLevel(character)

            -- Routing priority can mix max-level and leveling characters.
            -- Do not stop preloading at the first lower-level character, or
            -- later max-level candidates may be evaluated before their
            -- equipped-item data is ready.

            for _, slotID
                in ipairs(slotIDs)
            do
                local storedItem =
                    GetStoredItem(
                        character,
                        slotID
                    )

                if storedItem then
                    local key =
                        tostring(storedItem)

                    if not seen[key] then
                        seen[key] = true

                        local currentLevel =
                            GetItemLevel(
                                storedItem
                            )

                        if not currentLevel then
                            local itemObject =
                                CreateItemObject(
                                    storedItem
                                )

                            if itemObject then
                                waiting =
                                    waiting + 1

                                itemObject:
                                    ContinueOnItemLoad(
                                    function()
                                        FinishOne()
                                    end
                                )
                            end
                        end
                    end
                end
            end
        end
    end

    if waiting == 0
        and not finished
    then
        finished = true
        callback()

    elseif not silent then
        print(string.format(
            "|cffffff00Loading %d equipped item record%s...|r",
            waiting,
            waiting == 1 and "" or "s"
        ))
    end
end

-- ============================================================
-- SLOT COMPARISON
-- ============================================================

function GetComparisonForSlots(
    character,
    slotIDs
)
    local hasAnyItem = false
    local hasUnknown = false
    local lowestLevel = nil

    for _, slotID in ipairs(slotIDs) do
        local item =
            GetStoredItem(
                character,
                slotID
            )

        if item then
            hasAnyItem = true

            local ilvl =
                GetItemLevel(item)

            if ilvl then
                if not lowestLevel
                    or ilvl < lowestLevel
                then
                    lowestLevel = ilvl
                end
            else
                hasUnknown = true
            end
        else
            if not lowestLevel
                or lowestLevel > 0
            then
                lowestLevel = 0
            end
        end
    end

    if hasUnknown then
        return nil, "unknown"
    end

    if not hasAnyItem
        or lowestLevel == 0
    then
        return 0, "empty"
    end

    return lowestLevel, "known"
end
