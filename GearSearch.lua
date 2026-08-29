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

    local searchTab =
        WGRGearSearchCreateTab(
            page,
            "Gear Search",
            100
        )

    searchTab:SetPoint(
        "LEFT",
        recTab,
        "RIGHT",
        5,
        0
    )

    -- Shared location legend for both Gear Finder sub-views.
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
        "Locations: EQ = Equipped | BAG = Bags | PBK = Personal Bank | WBK = Warband Bank | ? = Unknown"
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
        return
            WGRGearSearchUniqueOptions(
                ValidRowsForOptions(
                    "location"
                ),
                "location"
            )
    end

    local resultSummary =
        searchPanel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    resultSummary:SetPoint(
        "TOPLEFT",
        controls,
        "BOTTOMLEFT",
        2,
        -16
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
            .. " matching holder entr"
            .. (
                #filtered == 1
                and "y"
                or "ies"
            )
            .. "  |  Searches saved Gear Holders."
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

    local function SetView(
        search
    )
        search =
            search == true

        recTab:SetSelected(
            not search
        )

        searchTab:SetSelected(
            search
        )

        recommendation.refresh:SetShown(
            not search
        )

        recommendation.ignoreHint:SetShown(
            not search
        )

        recommendation.sourceStatus:SetShown(
            not search
        )

        recommendation.specStatus:SetShown(
            not search
        )

        recommendation.summary:SetShown(
            not search
        )

        recommendation.scroll:SetShown(
            not search
        )

        searchPanel:SetShown(
            search
        )

        if search then
            Render()
        else
            if WGRRefreshGearFinder then
                WGRRefreshGearFinder(
                    frame
                )
            end
        end
    end

    recTab:SetScript(
        "OnClick",
        function()
            SetView(
                false
            )
        end
    )

    searchTab:SetScript(
        "OnClick",
        function()
            SetView(
                true
            )
        end
    )

    -- Recommendations is the default Gear Finder view.
    SetView(
        false
    )

    frame.gearFinderRecommendationsTab =
        recTab

    frame.gearFinderSearchTab =
        searchTab

    frame.gearFinderSearchPanel =
        searchPanel
end
