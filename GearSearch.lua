-- ============================================================
-- WARBOUND GEAR ROUTER - GEAR SEARCH
--
-- Secondary view inside Gear Finder.
-- Searches the existing aggregated Gear Holders snapshots.
-- This is intentionally a "where is this kind of gear stored?" tool,
-- not an individual-item browser.
-- ============================================================

local function WGRGearSearchCreateTab(
    parent,
    text,
    width
)
    local tab =
        CreateFrame(
            "Button",
            nil,
            parent,
            "BackdropTemplate"
        )

    tab:SetSize(
        width,
        22
    )

    tab:SetBackdrop({
        bgFile =
            "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile =
            "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 9,
        insets = {
            left = 3,
            right = 3,
            top = 3,
            bottom = 3,
        },
    })

    tab:SetBackdropColor(
        0.04,
        0.04,
        0.04,
        0.92
    )

    local label =
        tab:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    label:SetPoint(
        "CENTER"
    )

    label:SetText(
        text
    )

    tab.WGRLabel = label
    tab.WGRSelected = false

    function tab:SetSelected(
        selected
    )
        self.WGRSelected =
            selected == true

        if self.WGRSelected then
            self:SetBackdropColor(
                0.04,
                0.04,
                0.04,
                0.98
            )

            self.WGRLabel:SetTextColor(
                1.00,
                0.82,
                0.00
            )
        else
            self:SetBackdropColor(
                0.04,
                0.04,
                0.04,
                0.88
            )

            self.WGRLabel:SetTextColor(
                0.86,
                0.86,
                0.86
            )
        end
    end

    tab:SetScript(
        "OnEnter",
        function(self)
            if not self.WGRSelected then
                self:SetBackdropColor(
                    0.11,
                    0.11,
                    0.11,
                    0.96
                )
            end
        end
    )

    tab:SetScript(
        "OnLeave",
        function(self)
            self:SetSelected(
                self.WGRSelected
            )
        end
    )

    tab:SetSelected(
        false
    )

    return tab
end


local function WGRGearSearchMakeDropdown(
    parent,
    labelText,
    x,
    width,
    optionsFunc,
    stateKey,
    state,
    onChange
)
    local label =
        parent:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    label:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        x,
        -2
    )

    label:SetText(
        labelText
    )

    local dropdown =
        CreateFrame(
            "Frame",
            nil,
            parent,
            "UIDropDownMenuTemplate"
        )

    dropdown:SetPoint(
        "TOPLEFT",
        label,
        "BOTTOMLEFT",
        -16,
        3
    )

    UIDropDownMenu_SetWidth(
        dropdown,
        width
    )

    local function Options()
        return
            optionsFunc
            and optionsFunc()
            or {}
    end

    local function UpdateText()
        local current =
            state[
                stateKey
            ]

        local display =
            tostring(
                current
                or "ALL"
            )

        for _, option
            in ipairs(
                Options()
            )
        do
            if tostring(option[1])
                == tostring(current)
            then
                display =
                    option[2]
                break
            end
        end

        UIDropDownMenu_SetText(
            dropdown,
            display
        )
    end

    UIDropDownMenu_Initialize(
        dropdown,
        function(self, level)
            for _, option
                in ipairs(
                    Options()
                )
            do
                local info =
                    UIDropDownMenu_CreateInfo()

                info.text =
                    option[2]

                info.value =
                    option[1]

                info.checked =
                    tostring(
                        state[
                            stateKey
                        ]
                    )
                    ==
                    tostring(
                        option[1]
                    )

                info.func =
                    function()
                        state[
                            stateKey
                        ] =
                            option[1]

                        UpdateText()

                        if onChange then
                            onChange(
                                stateKey
                            )
                        end
                    end

                UIDropDownMenu_AddButton(
                    info,
                    level
                )
            end
        end
    )

    dropdown.WGRUpdateText =
        UpdateText

    UpdateText()

    return
        dropdown,
        label
end


local function WGRGearSearchParseEntry(
    section,
    category,
    subtype
)
    local record = {
        category = "",
        slot = "",
        primary = "",
        type = "",
    }

    if section == "Armor" then
        record.category =
            "Armor"

        record.type =
            category
            or ""

        return record
    end

    if section == "Accessories" then
        if category == "Necks" then
            record.category =
                "Necks"

            record.slot =
                "Neck"

        elseif category == "Rings" then
            record.category =
                "Rings"

            record.slot =
                "Ring"

        elseif category == "Cloaks" then
            record.category =
                "Cloaks"

            record.slot =
                "Cloak"

        else
            record.category =
                tostring(
                    category
                    or "Accessories"
                )
        end

        return record
    end

    if section == "Trinkets" then
        record.category =
            "Trinkets"

        record.slot =
            "Trinket"

        local role =
            tostring(
                category
                or "Other"
            )

        if role == "Healer" then
            record.type =
                "Healer Trinket"
        elseif role == "Tank" then
            record.type =
                "Tank Trinket"
        elseif role == "DPS" then
            record.type =
                "DPS Trinket"
        else
            record.type =
                role
                .. " Trinket"
        end

        return record
    end

    if section == "Weapons" then
        record.category =
            "Weapons"

        local bucket =
            tostring(
                category
                or ""
            )

        local detail =
            tostring(
                subtype
                or ""
            )

        local hand,
              stat =
            bucket:match(
                "^(1H)%s+(.+)$"
            )

        if not hand then
            hand,
            stat =
                bucket:match(
                    "^(2H)%s+(.+)$"
                )
        end

        if hand then
            record.slot =
                hand

            if stat ~= "Other"
                and stat ~= "Hybrid"
            then
                record.primary =
                    stat
            end

            record.type =
                detail

            return record
        end

        if bucket == "Agility Daggers" then
            record.slot =
                "1H"

            record.primary =
                "Agility"

            record.type =
                "Dagger"

            return record
        end

        if bucket == "Shields" then
            record.slot =
                "Shield"

            if detail ~= "Other" then
                record.primary =
                    detail
            end

            record.type =
                "Shield"

            return record
        end

        if bucket == "Off-Hands" then
            record.slot =
                "Off Hand"

            if detail ~= "Other" then
                record.primary =
                    detail
            end

            record.type =
                "Off-hand"

            return record
        end

        if bucket == "Ranged" then
            record.slot =
                "Ranged"

            record.type =
                detail

            return record
        end

        if bucket == "Warglaives" then
            record.slot =
                "1H"

            record.type =
                "Warglaive"

            return record
        end

        record.slot =
            bucket

        record.type =
            detail

        return record
    end

    return nil
end


local function WGRGearSearchCollectRows()
    InitializeDatabase()

    local rows = {}

    local function AddEntries(
        owner,
        location,
        entries
    )
        for key, count
            in pairs(
                entries
                or {}
            )
        do
            local section,
                  category,
                  subtype =
                strsplit(
                    "\031",
                    key
                )

            local parsed =
                WGRGearSearchParseEntry(
                    section,
                    category,
                    subtype
                )

            if parsed then
                rows[
                    #rows + 1
                ] = {
                    category =
                        parsed.category,
                    slot =
                        parsed.slot,
                    primary =
                        parsed.primary,
                    type =
                        parsed.type,
                    character =
                        owner
                        or "",
                    quantity =
                        tonumber(count)
                        or 0,
                    location =
                        location,
                }
            end
        end
    end

    for _, characterName
        in ipairs(
            GetRoutingPriority
            and GetRoutingPriority()
            or {}
        )
    do
        if not (
            WGRIsCharacterRemoved
            and WGRIsCharacterRemoved(
                characterName
            )
        )
        then
            local snapshot =
                WarboundGearRouterDB
                and WarboundGearRouterDB.heldGearSnapshots
                and WarboundGearRouterDB.heldGearSnapshots[
                    string.lower(
                        characterName
                    )
                ]

            if snapshot then
                if snapshot.bags then
                    AddEntries(
                        characterName,
                        "BAG",
                        snapshot.bags.entries
                    )
                end

                if snapshot.bank then
                    AddEntries(
                        characterName,
                        "PBK",
                        snapshot.bank.entries
                    )
                end
            end
        end
    end

    -- MAIL is persisted separately from physical bag/bank snapshots because
    -- the item is inaccessible while in transit. The destination character is
    -- the current holder for Gear Search purposes; routing destination remains
    -- a separate concept and is never inferred here.
    local mailTracking =
        WarboundGearRouterDB
        and WarboundGearRouterDB.mailGearTracking
        or {}

    for destinationKey, mailEntry
        in pairs(mailTracking)
    do
        local owner =
            type(mailEntry) == "table"
            and mailEntry.name
            or nil

        if owner
            and owner ~= ""
            and not (
                WGRIsCharacterRemoved
                and WGRIsCharacterRemoved(owner)
            )
        then
            local entries = {}

            for _, item
                in ipairs(mailEntry.items or {})
            do
                local gearKey =
                    type(item) == "table"
                    and item.gearKey
                    or nil

                if gearKey and gearKey ~= "" then
                    entries[gearKey] =
                        (entries[gearKey] or 0) + 1
                end
            end

            AddEntries(
                owner,
                "MAIL",
                entries
            )
        end
    end

    local warband =
        WarboundGearRouterDB
        and WarboundGearRouterDB.heldGearSnapshots
        and WarboundGearRouterDB.heldGearSnapshots[
            "__warband_bank"
        ]

    if warband
        and warband.warband
    then
        AddEntries(
            "",
            "WBK",
            warband.warband.entries
        )
    end

    return rows
end


local function WGRGearSearchUniqueOptions(
    rows,
    field
)
    local values = {}
    local seen = {}

    for _, row
        in ipairs(rows or {})
    do
        local value =
            row[
                field
            ]

        if value
            and value ~= ""
            and not seen[value]
        then
            seen[value] =
                true

            values[
                #values + 1
            ] =
                value
        end
    end

    table.sort(
        values,
        function(a, b)
            return
                tostring(a)
                <
                tostring(b)
        end
    )

    local options = {
        {"ALL", "Any"},
    }

    for _, value
        in ipairs(values)
    do
        options[
            #options + 1
        ] = {
            value,
            value,
        }
    end

    return options
end


local function WGRGearSearchMatches(
    row,
    state
)
    if state.category ~= "ALL"
        and row.category
            ~= state.category
    then
        return false
    end

    if state.slot ~= "ALL"
        and row.slot
            ~= state.slot
    then
        return false
    end

    if state.primary ~= "ALL"
        and row.primary
            ~= state.primary
    then
        return false
    end

    if state.type ~= "ALL"
        and row.type
            ~= state.type
    then
        return false
    end

    if state.character ~= "ALL"
        and row.character
            ~= state.character
    then
        return false
    end

    if state.location ~= "ALL"
        and row.location
            ~= state.location
    then
        return false
    end

    return true
end


local function WGRGearSearchAggregate(
    rows
)
    local result = {}
    local byKey = {}

    for _, row
        in ipairs(rows)
    do
        local key =
            table.concat({
                row.category or "",
                row.slot or "",
                row.primary or "",
                row.type or "",
                row.character or "",
                row.location or "",
            }, "\031")

        local existing =
            byKey[
                key
            ]

        if existing then
            existing.quantity =
                existing.quantity
                + (
                    tonumber(
                        row.quantity
                    )
                    or 0
                )
        else
            local copy = {
                category =
                    row.category,
                slot =
                    row.slot,
                primary =
                    row.primary,
                type =
                    row.type,
                character =
                    row.character,
                quantity =
                    tonumber(
                        row.quantity
                    )
                    or 0,
                location =
                    row.location,
            }

            byKey[key] =
                copy

            result[
                #result + 1
            ] =
                copy
        end
    end

    table.sort(
        result,
        function(a, b)
            local ac =
                tostring(
                    a.category
                    or ""
                )

            local bc =
                tostring(
                    b.category
                    or ""
                )

            if ac ~= bc then
                return ac < bc
            end

            local as =
                tostring(
                    a.slot
                    or ""
                )

            local bs =
                tostring(
                    b.slot
                    or ""
                )

            if as ~= bs then
                return as < bs
            end

            local ap =
                tostring(
                    a.primary
                    or ""
                )

            local bp =
                tostring(
                    b.primary
                    or ""
                )

            if ap ~= bp then
                return ap < bp
            end

            local at =
                tostring(
                    a.type
                    or ""
                )

            local bt =
                tostring(
                    b.type
                    or ""
                )

            if at ~= bt then
                return at < bt
            end

            local achar =
                tostring(
                    a.character
                    or ""
                )

            local bchar =
                tostring(
                    b.character
                    or ""
                )

            if achar ~= bchar then
                return achar < bchar
            end

            return
                tostring(
                    a.location
                    or ""
                )
                <
                tostring(
                    b.location
                    or ""
                )
        end
    )

    return result
end


-- ============================================================
-- GATHER GEAR
--
-- Read-only compatibility locator for the currently logged-in character.
-- This deliberately does NOT reroute remote gear or claim that a remote
-- item is an upgrade. It filters the same aggregate physical-location data
-- used by Gear Search to answer: "Where is gear this character could use?"
-- ============================================================

local WGRGatherArmorByClassID = {
    [1] = "Plate", [2] = "Plate", [3] = "Mail", [4] = "Leather",
    [5] = "Cloth", [6] = "Plate", [7] = "Mail", [8] = "Cloth",
    [9] = "Cloth", [10] = "Leather", [11] = "Leather",
    [12] = "Leather", [13] = "Mail",
}

local WGRGatherSpecPrimary = {
    [71]="Strength", [72]="Strength", [73]="Strength",
    [65]="Intellect", [66]="Strength", [70]="Strength",
    [253]="Agility", [254]="Agility", [255]="Agility",
    [259]="Agility", [260]="Agility", [261]="Agility",
    [256]="Intellect", [257]="Intellect", [258]="Intellect",
    [250]="Strength", [251]="Strength", [252]="Strength",
    [262]="Intellect", [263]="Agility", [264]="Intellect",
    [62]="Intellect", [63]="Intellect", [64]="Intellect",
    [265]="Intellect", [266]="Intellect", [267]="Intellect",
    [268]="Agility", [269]="Agility", [270]="Intellect",
    [102]="Intellect", [103]="Agility", [104]="Agility", [105]="Intellect",
    [577]="Agility", [581]="Agility", [1480]="Agility",
    [1467]="Intellect", [1468]="Intellect", [1473]="Intellect",
}

local WGRGatherTankSpecs = {
    [66]=true,[73]=true,[104]=true,[250]=true,[268]=true,[581]=true,
}
local WGRGatherHealerSpecs = {
    [65]=true,[105]=true,[256]=true,[257]=true,[264]=true,[270]=true,[1468]=true,
}
local WGRGatherCasterDPSSpecs = {
    [62]=true,[63]=true,[64]=true,[102]=true,[258]=true,[262]=true,
    [265]=true,[266]=true,[267]=true,[1467]=true,[1473]=true,[1480]=true,
}

local function WGRGatherWeaponSubtypeID(typeText)
    local t = string.lower(tostring(typeText or ""))
    if t:find("crossbow",1,true) then return 18 end
    if t:find("warglaive",1,true) then return 9 end
    if t:find("dagger",1,true) then return 15 end
    if t:find("polearm",1,true) then return 6 end
    if t:find("staff",1,true) or t:find("staves",1,true) then return 10 end
    if t:find("wand",1,true) then return 19 end
    if t:find("fist",1,true) then return 13 end
    if t:find("bow",1,true) then return 2 end
    if t:find("gun",1,true) then return 3 end
    if t:find("axe",1,true) then return nil, "AXE" end
    if t:find("mace",1,true) then return nil, "MACE" end
    if t:find("sword",1,true) then return nil, "SWORD" end
    return nil
end

local function WGRGatherClassAllowsWeaponRow(classID, row)
    if not classID then return false end
    if row.slot == "Shield" or row.slot == "Off Hand" then return true end

    local allowed = WGRClassWeaponSubclasses and WGRClassWeaponSubclasses[classID]
    if not allowed then return true end

    local subtypeID, family = WGRGatherWeaponSubtypeID(row.type)
    if subtypeID then return allowed[subtypeID] == true end

    -- Axe/Mace/Sword buckets use the hand column to distinguish 1H vs 2H.
    if family == "AXE" then return allowed[row.slot == "2H" and 1 or 0] == true end
    if family == "MACE" then return allowed[row.slot == "2H" and 5 or 4] == true end
    if family == "SWORD" then return allowed[row.slot == "2H" and 8 or 7] == true end

    return true
end

local function WGRGatherConfigAllowsRow(config, row)
    if config == "RANGED" then return row.slot == "Ranged" end
    if config == "TWO_HAND" or config == "DUAL_2H" then return row.slot == "2H" end
    if config == "DUAL_1H" then return row.slot == "1H" end
    if config == "ONE_HAND_PLUS_SHIELD" then return row.slot == "1H" or row.slot == "Shield" end
    if config == "ONE_HAND_PLUS_OFFHAND" then return row.slot == "1H" or row.slot == "Off Hand" end
    return false
end

local function WGRGatherRowMatchesTrinketRole(row, specIDs)
    local text = tostring(row.type or "")
    if text == "General / All Roles Trinket" or text == "General / All Roles" then return true end

    for _, specID in ipairs(specIDs or {}) do
        if WGRGatherTankSpecs[specID] and text:find("Tank",1,true) then return true end
        if WGRGatherHealerSpecs[specID] and text:find("Healer",1,true) then return true end
        if WGRGatherCasterDPSSpecs[specID] then
            if text:find("Caster DPS",1,true) or text:find("General DPS",1,true) then return true end
        elseif not WGRGatherTankSpecs[specID] and not WGRGatherHealerSpecs[specID] then
            if text:find("Physical DPS",1,true) or text:find("General DPS",1,true) then return true end
        end
    end

    -- Keep unclassified trinkets visible rather than hiding something that
    -- the aggregate snapshot cannot classify precisely enough.
    return text:find("Unclassified",1,true) ~= nil or text:find("Other",1,true) ~= nil
end

local function WGRGatherRowUsableByCurrent(row, context)
    if not row or not context or context.removed then return false end

    if row.category == "Armor" then
        return row.type == context.armorType
    end

    if row.category == "Necks" or row.category == "Rings" or row.category == "Cloaks" then
        return true
    end

    if row.category == "Trinkets" then
        return WGRGatherRowMatchesTrinketRole(row, context.specIDs)
    end

    if row.category ~= "Weapons" then
        return false
    end

    if not WGRGatherClassAllowsWeaponRow(context.classID, row) then return false end

    for _, specID in ipairs(context.specIDs or {}) do
        local wantedPrimary = WGRGatherSpecPrimary[specID]
        local primaryOK = (not row.primary or row.primary == "" or row.primary == wantedPrimary)
        if primaryOK then
            local configs = nil
            if WGRGetAllowedSpecWeaponConfigs then
                configs = WGRGetAllowedSpecWeaponConfigs(context.name, specID)
            end
            configs = configs or (WGRSpecEligibleWeaponConfigs and WGRSpecEligibleWeaponConfigs[specID]) or {}
            for _, config in ipairs(configs) do
                if WGRGatherConfigAllowsRow(config, row) then return true end
            end
        end
    end

    return false
end

local function WGRGatherSourceRank(row, currentName, priorityIndex)
    if row.location == "WBK" then return 1 end

    local same = row.character ~= "" and currentName ~= ""
        and string.lower(row.character) == string.lower(currentName)

    if same and row.location == "MAIL" then return 2 end
    if same and row.location == "BAG" then return 3 end
    if same and row.location == "PBK" then return 4 end

    local idx = priorityIndex[string.lower(tostring(row.character or ""))] or 999
    local locRank = row.location == "MAIL" and 1 or (row.location == "BAG" and 2 or (row.location == "PBK" and 3 or 9))
    return 100 + (idx * 10) + locRank
end

local function WGRGatherSortRows(rows, currentName)
    -- Match Gear Search's default ordering so similar gear stays together
    -- visually: Category -> Slot -> Primary -> Type -> Character -> Location.
    table.sort(rows, function(a, b)
        local ac = tostring(a.category or "")
        local bc = tostring(b.category or "")
        if ac ~= bc then
            return ac < bc
        end

        local as = tostring(a.slot or "")
        local bs = tostring(b.slot or "")
        if as ~= bs then
            return as < bs
        end

        local ap = tostring(a.primary or "")
        local bp = tostring(b.primary or "")
        if ap ~= bp then
            return ap < bp
        end

        local at = tostring(a.type or "")
        local bt = tostring(b.type or "")
        if at ~= bt then
            return at < bt
        end

        local achar = tostring(a.character or "")
        local bchar = tostring(b.character or "")
        if achar ~= bchar then
            return achar < bchar
        end

        return tostring(a.location or "") < tostring(b.location or "")
    end)
end

local function WGRCreateGatherGearPanel(frame, page)
    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -78)
    panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    local state = {
        category="ALL",
        slot="ALL",
        primary="ALL",
        type="ALL",
        character="ALL",
        location="ALL",
    }
    local controls = CreateFrame("Frame", nil, panel)
    controls:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    controls:SetSize(820,55)

    local allRows = {}
    local categoryDropdown,
          slotDropdown,
          primaryDropdown,
          typeDropdown,
          characterDropdown,
          locationDropdown

    local function Matches(row)
        if state.category ~= "ALL" and row.category ~= state.category then return false end
        if state.slot ~= "ALL" and row.slot ~= state.slot then return false end
        if state.primary ~= "ALL" and row.primary ~= state.primary then return false end
        if state.type ~= "ALL" and row.type ~= state.type then return false end
        if state.character ~= "ALL" and row.character ~= state.character then return false end
        if state.location ~= "ALL" and row.location ~= state.location then return false end
        return true
    end

    local function ValidRows(excluding)
        local result = {}
        for _, row in ipairs(allRows) do
            local passes = true
            if excluding ~= "category" and state.category ~= "ALL" and row.category ~= state.category then passes=false end
            if excluding ~= "slot" and state.slot ~= "ALL" and row.slot ~= state.slot then passes=false end
            if excluding ~= "primary" and state.primary ~= "ALL" and row.primary ~= state.primary then passes=false end
            if excluding ~= "type" and state.type ~= "ALL" and row.type ~= state.type then passes=false end
            if excluding ~= "character" and state.character ~= "ALL" and row.character ~= state.character then passes=false end
            if excluding ~= "location" and state.location ~= "ALL" and row.location ~= state.location then passes=false end
            if passes then result[#result+1]=row end
        end
        return result
    end

    local function CategoryOptions() return WGRGearSearchUniqueOptions(allRows,"category") end
    local function SlotOptions() return WGRGearSearchUniqueOptions(ValidRows("slot"),"slot") end
    local function PrimaryOptions() return WGRGearSearchUniqueOptions(ValidRows("primary"),"primary") end
    local function TypeOptions() return WGRGearSearchUniqueOptions(ValidRows("type"),"type") end
    local function CharacterOptions() return WGRGearSearchUniqueOptions(ValidRows("character"),"character") end
    local function LocationOptions() return WGRGearSearchUniqueOptions(ValidRows("location"),"location") end

    local identityTitle = panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
    identityTitle:SetPoint("TOP",controls,"BOTTOM",0,-14)
    identityTitle:SetJustifyH("CENTER")
    identityTitle:SetTextColor(0.35,1.00,0.35)
    identityTitle:SetText("Equippable Gear | Potential Upgrades")

    local scopeHeader = panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    scopeHeader:SetPoint("TOP",identityTitle,"BOTTOM",0,-5)
    scopeHeader:SetJustifyH("CENTER")
    scopeHeader:SetTextColor(1.00,0.82,0.00)

    local summary = panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT",panel,"TOPLEFT",2,-112)
    summary:SetTextColor(0.70,0.70,0.70)

    local header = CreateFrame("Frame",nil,panel)
    header:SetPoint("TOPLEFT",summary,"BOTTOMLEFT",0,-8)
    header:SetPoint("RIGHT",panel,"RIGHT",-26,0)
    header:SetHeight(22)

    local scroll = CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",header,"BOTTOMLEFT",0,-2)
    scroll:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-26,0)
    local content = CreateFrame("Frame",nil,scroll)
    content:SetWidth(820); content:SetHeight(1); scroll:SetScrollChild(content)

    local widths={100,80,105,150,140,80,55}
    local headers={"Category","Slot","Primary Stat","Type","Character","Location","#"}
    local starts={0}
    for i=2,#widths do starts[i]=starts[i-1]+widths[i-1] end
    for i,labelText in ipairs(headers) do
        local label=header:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        label:SetPoint("LEFT",header,"LEFT",starts[i]+3,0)
        label:SetWidth(widths[i]-6)
        label:SetJustifyH(i==7 and "CENTER" or "LEFT")
        label:SetText(labelText)
    end

    local rowFrames={}
    local function ClearRows()
        for _,r in ipairs(rowFrames) do r:Hide(); r:SetParent(nil) end
        rowFrames={}
    end

    local function CurrentContext()
        local name=UnitName("player") or ""
        local character=FindCharacterByName and FindCharacterByName(name) or nil
        local classID=GetCharacterClassID and GetCharacterClassID(name,character) or nil
        return {
            name=name,
            character=character,
            classID=classID,
            armorType=WGRGatherArmorByClassID[classID],
            specIDs=WGRGetRoutingSpecIDs and WGRGetRoutingSpecIDs(name,character) or {},
            mode=WGRGetEffectiveSpecMode and WGRGetEffectiveSpecMode(name) or "CURRENT",
            removed=WGRIsCharacterRemoved and WGRIsCharacterRemoved(name) or false,
        }
    end

    local function Render()
        ClearRows()
        local context=CurrentContext()
        allRows={}
        for _,row in ipairs(WGRGearSearchCollectRows()) do
            if WGRGatherRowUsableByCurrent(row,context) then allRows[#allRows+1]=row end
        end

        local filtered={}
        for _,row in ipairs(allRows) do if Matches(row) then filtered[#filtered+1]=row end end
        filtered=WGRGearSearchAggregate(filtered)
        WGRGatherSortRows(filtered,context.name)

        local specNames={}
        for _,specID in ipairs(context.specIDs or {}) do specNames[#specNames+1]=WGRSpecNamesByID and WGRSpecNamesByID[specID] or tostring(specID) end
        local specText=#specNames>0 and table.concat(specNames," | ") or "Spec not initialized"
        scopeHeader:SetText(tostring(context.name)..": "..specText)
        if context.removed then
            summary:SetText("Gather Gear is unavailable while this character is Removed from the WBGR roster.")
        else
            summary:SetText(tostring(#filtered).." compatible entr"..(#filtered==1 and "y" or "ies")..". Check for potential upgrades.")
        end

        content:SetHeight(math.max(1,#filtered*24))
        for index,record in ipairs(filtered) do
            local row=CreateFrame("Frame",nil,content)
            row:SetPoint("TOPLEFT",content,"TOPLEFT",0,-((index-1)*24)); row:SetPoint("RIGHT",content,"RIGHT",0,0); row:SetHeight(23)
            local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints()
            local shade=index%2==0 and 0.10 or 0.05; bg:SetColorTexture(shade,shade,shade,index%2==0 and 0.30 or 0.18)
            local values={record.category,record.slot,record.primary,record.type,record.character,record.location,tostring(record.quantity or 0)}
            for i,value in ipairs(values) do
                local text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                text:SetPoint("LEFT",row,"LEFT",starts[i]+3,0); text:SetWidth(widths[i]-6); text:SetJustifyH(i==7 and "CENTER" or "LEFT")
                text:SetText(value~="" and value or "-")
            end
            rowFrames[#rowFrames+1]=row
        end
        for _,dd in ipairs({
            categoryDropdown,
            slotDropdown,
            primaryDropdown,
            typeDropdown,
            characterDropdown,
            locationDropdown,
        }) do
            if dd and dd.WGRUpdateText then dd:WGRUpdateText() end
        end
    end

    local function OnFilterChanged(changedKey)
        local checks={
            slot=SlotOptions,
            primary=PrimaryOptions,
            type=TypeOptions,
            character=CharacterOptions,
            location=LocationOptions,
        }
        for key,optionFunc in pairs(checks) do
            if key~=changedKey and state[key]~="ALL" then
                local valid=false
                for _,opt in ipairs(optionFunc()) do if tostring(opt[1])==tostring(state[key]) then valid=true; break end end
                if not valid then state[key]="ALL" end
            end
        end
        Render()
    end

    categoryDropdown=WGRGearSearchMakeDropdown(controls,"Category",0,88,CategoryOptions,"category",state,OnFilterChanged)
    slotDropdown=WGRGearSearchMakeDropdown(controls,"Slot",114,72,SlotOptions,"slot",state,OnFilterChanged)
    primaryDropdown=WGRGearSearchMakeDropdown(controls,"Primary Stat",214,92,PrimaryOptions,"primary",state,OnFilterChanged)
    typeDropdown=WGRGearSearchMakeDropdown(controls,"Type",334,118,TypeOptions,"type",state,OnFilterChanged)
    characterDropdown=WGRGearSearchMakeDropdown(controls,"Character",478,108,CharacterOptions,"character",state,OnFilterChanged)
    locationDropdown=WGRGearSearchMakeDropdown(controls,"Location",612,72,LocationOptions,"location",state,OnFilterChanged)

    local reset=CreateFrame("Button",nil,controls,"UIPanelButtonTemplate")
    reset:SetSize(70,22); reset:SetPoint("TOPLEFT",controls,"TOPLEFT",730,-13); reset:SetText("Reset")
    reset:SetScript("OnClick",function()
        state.category="ALL"
        state.slot="ALL"
        state.primary="ALL"
        state.type="ALL"
        state.character="ALL"
        state.location="ALL"
        Render()
    end)

    frame.WGRGatherGearRender=Render
    return panel,Render
end


function WGRCreateGearSearchView(
    frame,
    page,
    recommendation
)
    if not frame
        or not page
        or not recommendation
    then
        return
    end

    local recTab =
        WGRGearSearchCreateTab(
            page,
            "Recommendations",
            126
        )

    recTab:SetPoint(
        "TOPLEFT",
        page,
        "TOPLEFT",
        0,
        -27
    )

    local gatherTab =
        WGRGearSearchCreateTab(
            page,
            "Gather Gear",
            100
        )

    gatherTab:SetPoint(
        "LEFT",
        recTab,
        "RIGHT",
        5,
        0
    )

    local searchTab =
        WGRGearSearchCreateTab(
            page,
            "Gear Search",
            100
        )

    searchTab:SetPoint(
        "LEFT",
        gatherTab,
        "RIGHT",
        5,
        0
    )

    -- Shared location legend for all Gear Finder sub-views.
    local locationLegend =
        page:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    locationLegend:SetPoint(
        "TOPLEFT",
        page,
        "TOPLEFT",
        0,
        -58
    )

    locationLegend:SetPoint(
        "RIGHT",
        page,
        "RIGHT",
        -4,
        0
    )

    locationLegend:SetJustifyH(
        "LEFT"
    )

    locationLegend:SetTextColor(
        0.68,
        0.68,
        0.68
    )

    locationLegend:SetText(
        "Locations: EQ = Equipped | BAG = Bags | PBK = Personal Bank | WBK = Warband Bank | MAIL = Mailbox | ? = Unknown"
    )

    -- Make room for the shared legend in the existing Recommendations view.
    recommendation.sourceStatus:
        ClearAllPoints()

    recommendation.sourceStatus:SetPoint(
        "TOPLEFT",
        page,
        "TOPLEFT",
        0,
        -76
    )

    local gatherPanel, GatherRender =
        WGRCreateGatherGearPanel(
            frame,
            page
        )

    local searchPanel =
        CreateFrame(
            "Frame",
            nil,
            page
        )

    searchPanel:SetPoint(
        "TOPLEFT",
        page,
        "TOPLEFT",
        0,
        -78
    )

    searchPanel:SetPoint(
        "BOTTOMRIGHT",
        page,
        "BOTTOMRIGHT",
        0,
        0
    )

    searchPanel:Hide()

    local state = {
        category = "ALL",
        slot = "ALL",
        primary = "ALL",
        type = "ALL",
        character = "ALL",
        location = "ALL",
    }

    local controls =
        CreateFrame(
            "Frame",
            nil,
            searchPanel
        )

    controls:SetPoint(
        "TOPLEFT",
        searchPanel,
        "TOPLEFT",
        0,
        0
    )

    controls:SetSize(
        820,
        55
    )

    local allRows = {}
    local categoryDropdown,
          slotDropdown,
          primaryDropdown,
          typeDropdown,
          characterDropdown,
          locationDropdown

    local function ValidRowsForOptions(
        excluding
    )
        local result = {}

        for _, row
            in ipairs(allRows)
        do
            local passes = true

            if excluding ~= "category"
                and state.category ~= "ALL"
                and row.category ~= state.category
            then
                passes = false
            end

            if excluding ~= "slot"
                and state.slot ~= "ALL"
                and row.slot ~= state.slot
            then
                passes = false
            end

            if excluding ~= "primary"
                and state.primary ~= "ALL"
                and row.primary ~= state.primary
            then
                passes = false
            end

            if excluding ~= "type"
                and state.type ~= "ALL"
                and row.type ~= state.type
            then
                passes = false
            end

            if excluding ~= "character"
                and state.character ~= "ALL"
                and row.character ~= state.character
            then
                passes = false
            end

            if excluding ~= "location"
                and state.location ~= "ALL"
                and row.location ~= state.location
            then
                passes = false
            end

            if passes then
                result[
                    #result + 1
                ] =
                    row
            end
        end

        return result
    end

    local function CategoryOptions()
        return
            WGRGearSearchUniqueOptions(
                allRows,
                "category"
            )
    end

    local function SlotOptions()
        return
            WGRGearSearchUniqueOptions(
                ValidRowsForOptions(
                    "slot"
                ),
                "slot"
            )
    end

    local function PrimaryOptions()
        return
            WGRGearSearchUniqueOptions(
                ValidRowsForOptions(
                    "primary"
                ),
                "primary"
            )
    end

    local function TypeOptions()
        return
            WGRGearSearchUniqueOptions(
                ValidRowsForOptions(
                    "type"
                ),
                "type"
            )
    end

    local function CharacterOptions()
        -- Character values come only from currently saved Gear Holder rows.
        -- WBK rows have no character owner and are therefore omitted.
        return
            WGRGearSearchUniqueOptions(
                ValidRowsForOptions(
                    "character"
                ),
                "character"
            )
    end

    local function LocationOptions()
        local options =
            WGRGearSearchUniqueOptions(
                ValidRowsForOptions(
                    "location"
                ),
                "location"
            )

        local hasMail = false
        for _, option in ipairs(options) do
            if option[1] == "MAIL" then
                hasMail = true
                break
            end
        end

        if not hasMail then
            options[#options + 1] = {"MAIL", "MAIL"}
        end

        return options
    end

    local identityTitle =
        searchPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    identityTitle:SetPoint(
        "TOP",
        controls,
        "BOTTOM",
        0,
        -14
    )

    identityTitle:SetJustifyH(
        "CENTER"
    )

    identityTitle:SetTextColor(
        0.45,
        0.80,
        1.00
    )

    identityTitle:SetText(
        "Warband Gear Storage | Search & Locate"
    )

    local identityScope =
        searchPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    identityScope:SetPoint(
        "TOP",
        identityTitle,
        "BOTTOM",
        0,
        -5
    )

    identityScope:SetJustifyH(
        "CENTER"
    )

    identityScope:SetTextColor(
        1.00,
        0.82,
        0.00
    )

    identityScope:SetText(
        "All Tracked Gear"
    )

    local resultSummary =
        searchPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    resultSummary:SetPoint(
        "TOPLEFT",
        searchPanel,
        "TOPLEFT",
        2,
        -112
    )

    resultSummary:SetTextColor(
        0.70,
        0.70,
        0.70
    )

    local header =
        CreateFrame(
            "Frame",
            nil,
            searchPanel
        )

    header:SetPoint(
        "TOPLEFT",
        resultSummary,
        "BOTTOMLEFT",
        0,
        -8
    )

    header:SetPoint(
        "RIGHT",
        searchPanel,
        "RIGHT",
        -26,
        0
    )

    header:SetHeight(
        22
    )

    local scroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            searchPanel,
            "UIPanelScrollFrameTemplate"
        )

    scroll:SetPoint(
        "TOPLEFT",
        header,
        "BOTTOMLEFT",
        0,
        -2
    )

    scroll:SetPoint(
        "BOTTOMRIGHT",
        searchPanel,
        "BOTTOMRIGHT",
        -26,
        0
    )

    local content =
        CreateFrame(
            "Frame",
            nil,
            scroll
        )

    content:SetWidth(
        820
    )

    content:SetHeight(
        1
    )

    scroll:SetScrollChild(
        content
    )

    local widths = {
        100, -- Category
        80,  -- Slot
        105, -- Primary Stat
        150, -- Type
        140, -- Character
        80,  -- Location
        55,  -- #
    }

    local headers = {
        "Category",
        "Slot",
        "Primary Stat",
        "Type",
        "Character",
        "Location",
        "#",
    }

    local starts = {
        0,
    }

    for i = 2, #widths do
        starts[i] =
            starts[i - 1]
            + widths[i - 1]
    end

    for i, labelText
        in ipairs(headers)
    do
        local label =
            header:CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormalSmall"
            )

        label:SetPoint(
            "LEFT",
            header,
            "LEFT",
            starts[i] + 3,
            0
        )

        label:SetWidth(
            widths[i] - 6
        )

        label:SetJustifyH(
            i == 7
            and "CENTER"
            or "LEFT"
        )

        label:SetText(
            labelText
        )
    end

    local rows = {}

    local function ClearRows()
        for _, row
            in ipairs(rows)
        do
            row:Hide()
            row:SetParent(nil)
        end

        rows = {}
    end

    local function Render()
        ClearRows()

        allRows =
            WGRGearSearchCollectRows()

        local filtered = {}

        for _, row
            in ipairs(allRows)
        do
            if WGRGearSearchMatches(
                row,
                state
            )
            then
                filtered[
                    #filtered + 1
                ] =
                    row
            end
        end

        filtered =
            WGRGearSearchAggregate(
                filtered
            )

        resultSummary:SetText(
            tostring(
                #filtered
            )
            .. " matching entr"
            .. (
                #filtered == 1
                and "y"
                or "ies"
            )
            .. " across tracked storage."
        )

        content:SetHeight(
            math.max(
                1,
                #filtered * 24
            )
        )

        for index, record
            in ipairs(filtered)
        do
            local row =
                CreateFrame(
                    "Frame",
                    nil,
                    content
                )

            row:SetPoint(
                "TOPLEFT",
                content,
                "TOPLEFT",
                0,
                -(
                    (index - 1)
                    * 24
                )
            )

            row:SetPoint(
                "RIGHT",
                content,
                "RIGHT",
                0,
                0
            )

            row:SetHeight(
                23
            )

            local bg =
                row:CreateTexture(
                    nil,
                    "BACKGROUND"
                )

            bg:SetAllPoints()

            bg:SetColorTexture(
                index % 2 == 0
                and 0.10
                or 0.05,
                index % 2 == 0
                and 0.10
                or 0.05,
                index % 2 == 0
                and 0.10
                or 0.05,
                index % 2 == 0
                and 0.30
                or 0.18
            )

            local values = {
                record.category,
                record.slot,
                record.primary,
                record.type,
                record.character,
                record.location,
                tostring(
                    record.quantity
                    or 0
                ),
            }

            for i, value
                in ipairs(values)
            do
                local text =
                    row:CreateFontString(
                        nil,
                        "OVERLAY",
                        "GameFontHighlightSmall"
                    )

                text:SetPoint(
                    "LEFT",
                    row,
                    "LEFT",
                    starts[i] + 3,
                    0
                )

                text:SetWidth(
                    widths[i] - 6
                )

                text:SetJustifyH(
                    i == 7
                    and "CENTER"
                    or "LEFT"
                )

                text:SetText(
                    value
                    ~= ""
                    and value
                    or "-"
                )
            end

            rows[
                #rows + 1
            ] =
                row
        end

        for _, dropdown
            in ipairs({
                categoryDropdown,
                slotDropdown,
                primaryDropdown,
                typeDropdown,
                characterDropdown,
                locationDropdown,
            })
        do
            if dropdown
                and dropdown.WGRUpdateText
            then
                dropdown:WGRUpdateText()
            end
        end
    end

    -- Event-driven live refresh bridge. Storage/mail code calls the global
    -- notifier; only an actually-visible Gear Search panel is rerendered.
    frame.WGRGearSearchRender = Render

    WGRNotifyGearSearchChanged =
        function()
            if not (frame and frame.IsShown and frame:IsShown()) then
                return
            end

            if gatherPanel
                and gatherPanel:IsShown()
                and frame.WGRGatherGearRender
            then
                frame.WGRGatherGearRender()
            end

            if searchPanel
                and searchPanel:IsShown()
                and frame.WGRGearSearchRender
            then
                frame.WGRGearSearchRender()
            end
        end

    local function OnFilterChanged(
        changedKey
    )
        -- Dependent filters are allowed to narrow naturally, but if a current
        -- value no longer exists in the remaining holder data, reset it.
        local checks = {
            slot = SlotOptions,
            primary = PrimaryOptions,
            type = TypeOptions,
            character = CharacterOptions,
            location = LocationOptions,
        }

        for key, optionFunc
            in pairs(checks)
        do
            if key ~= changedKey
                and state[key] ~= "ALL"
            then
                local valid = false

                for _, option
                    in ipairs(
                        optionFunc()
                    )
                do
                    if tostring(option[1])
                        == tostring(
                            state[key]
                        )
                    then
                        valid = true
                        break
                    end
                end

                if not valid then
                    state[key] =
                        "ALL"
                end
            end
        end

        Render()
    end

    categoryDropdown =
        WGRGearSearchMakeDropdown(
            controls,
            "Category",
            0,
            88,
            CategoryOptions,
            "category",
            state,
            OnFilterChanged
        )

    slotDropdown =
        WGRGearSearchMakeDropdown(
            controls,
            "Slot",
            114,
            72,
            SlotOptions,
            "slot",
            state,
            OnFilterChanged
        )

    primaryDropdown =
        WGRGearSearchMakeDropdown(
            controls,
            "Primary Stat",
            214,
            92,
            PrimaryOptions,
            "primary",
            state,
            OnFilterChanged
        )

    typeDropdown =
        WGRGearSearchMakeDropdown(
            controls,
            "Type",
            334,
            118,
            TypeOptions,
            "type",
            state,
            OnFilterChanged
        )

    characterDropdown =
        WGRGearSearchMakeDropdown(
            controls,
            "Character",
            478,
            108,
            CharacterOptions,
            "character",
            state,
            OnFilterChanged
        )

    locationDropdown =
        WGRGearSearchMakeDropdown(
            controls,
            "Location",
            612,
            72,
            LocationOptions,
            "location",
            state,
            OnFilterChanged
        )

    local reset =
        CreateFrame(
            "Button",
            nil,
            controls,
            "UIPanelButtonTemplate"
        )

    reset:SetSize(
        70,
        22
    )

    -- Use the same controls-row coordinate system as the dropdowns.
    -- UIDropDownMenuTemplate has invisible frame padding, so anchoring
    -- Reset directly to a dropdown makes the visible controls look offset.
    reset:SetPoint(
        "TOPLEFT",
        controls,
        "TOPLEFT",
        730,
        -13
    )

    reset:SetText(
        "Reset"
    )

    reset:SetScript(
        "OnClick",
        function()
            state.category = "ALL"
            state.slot = "ALL"
            state.primary = "ALL"
            state.type = "ALL"
            state.character = "ALL"
            state.location = "ALL"
            Render()
        end
    )

    local function ReconcilePhysicalSnapshots()
        -- Gather Gear and Gear Search both depend on physical-location
        -- snapshots. Reconcile the current character's readable storage when
        -- the user explicitly opens either locator, preserving Removed and
        -- Pause invariants.
        local paused = WGRRoutingIsPaused and WGRRoutingIsPaused()
        local currentName = UnitName("player")
        local currentRemoved =
            currentName
            and WGRIsCharacterRemoved
            and WGRIsCharacterRemoved(currentName)

        if WGRBeginRoutingEvaluationCache then WGRBeginRoutingEvaluationCache() end

        if WGRRefreshHeldGearSnapshot and not currentRemoved then
            if paused then
                WGRRefreshHeldGearSnapshot(true,true,true)
            else
                WGRRefreshHeldGearSnapshot(false,true,false)
            end
        end

        if paused and WGRRefreshWarbandHeldGearSnapshot then
            WGRRefreshWarbandHeldGearSnapshot()
        end

        if WGREndRoutingEvaluationCache then WGREndRoutingEvaluationCache() end
    end

    local function SetView(viewKey)
        local isRecommendations = viewKey == "RECOMMENDATIONS"
        local isGather = viewKey == "GATHER"
        local isSearch = viewKey == "SEARCH"

        recTab:SetSelected(isRecommendations)
        gatherTab:SetSelected(isGather)
        searchTab:SetSelected(isSearch)

        recommendation.refresh:SetShown(isRecommendations)
        recommendation.ignoreHint:SetShown(isRecommendations)
        recommendation.sourceStatus:SetShown(isRecommendations)
        recommendation.specStatus:SetShown(isRecommendations)
        recommendation.summary:SetShown(isRecommendations)
        recommendation.scroll:SetShown(isRecommendations)


        gatherPanel:SetShown(isGather)
        searchPanel:SetShown(isSearch)

        if isGather or isSearch then
            ReconcilePhysicalSnapshots()
            if isGather and GatherRender then
                GatherRender()
            elseif isSearch then
                Render()
            end
        elseif WGRRefreshGearFinder then
            WGRRefreshGearFinder(frame)
        end
    end

    recTab:SetScript("OnClick", function() SetView("RECOMMENDATIONS") end)
    gatherTab:SetScript("OnClick", function() SetView("GATHER") end)
    searchTab:SetScript("OnClick", function() SetView("SEARCH") end)

    frame.ShowGearFinderView =
        SetView

    -- Recommendations remains the normal/default workflow. Gather Gear is an
    -- on-demand exception/check step for priority/spec changes, while Gear
    -- Search remains the general storage browser.
    SetView("RECOMMENDATIONS")

    frame.gearFinderRecommendationsTab = recTab
    frame.gearFinderGatherTab = gatherTab
    frame.gearFinderSearchTab = searchTab
    frame.gearFinderGatherPanel = gatherPanel
    frame.gearFinderSearchPanel = searchPanel
end
