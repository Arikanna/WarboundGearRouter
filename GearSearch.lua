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


-- v0.71a: When Storage Cleanup monitoring is enabled, Gear Search and
-- Gather Gear can drill into the exact physical-item observations that
-- already back account-wide Cleanup. The aggregate rows remain the normal
-- presentation; these helpers are read-only and introduce no second scanner.
local WGRGearSearchArmorSlotLabels = {
    INVTYPE_HEAD='Head', INVTYPE_SHOULDER='Shoulders',
    INVTYPE_CHEST='Chest', INVTYPE_ROBE='Chest', INVTYPE_WRIST='Wrist',
    INVTYPE_HAND='Hands', INVTYPE_WAIST='Waist', INVTYPE_LEGS='Legs',
    INVTYPE_FEET='Feet',
}
local WGRGearSearchArmorSlotOrder = {
    Head=1, Shoulders=2, Chest=3, Wrist=4, Hands=5,
    Waist=6, Legs=7, Feet=8, Other=99,
}

local function WGRGearSearchAggregateKey(row)
    return table.concat({
        tostring(row and row.category or ''), tostring(row and row.slot or ''),
        tostring(row and row.primary or ''), tostring(row and row.type or ''),
        tostring(row and row.character or ''), tostring(row and row.location or ''),
    }, '\031')
end

local function WGRGearSearchCleanupDetailEnabled()
    local settings=WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings()
    return settings and settings.enabled == true
end

local function WGRGearSearchDetailRecord(item,owner,location)
    local link=item and item.itemLink
    if not link or link=='' or not WGRClassifyHeldGearItem then return nil end
    local section,category,subtype=WGRClassifyHeldGearItem(link)
    if not section then return nil end
    local parsed=WGRGearSearchParseEntry(section,category,subtype)
    if not parsed then return nil end
    local itemName=item.itemName
    local equipLoc=item.equipLoc or ''
    if (not itemName or itemName=='') or equipLoc=='' then
        local name,_,_,_,_,_,_,_,resolvedEquipLoc=C_Item.GetItemInfo(link)
        itemName=itemName or name
        if equipLoc=='' then equipLoc=resolvedEquipLoc or '' end
    end
    local itemLevel=tonumber(item.itemLevel)
    if (not itemLevel or itemLevel<=0) and type(GetItemLevel)=='function' then
        itemLevel=tonumber(GetItemLevel(link))
    end
    return {
        itemLink=link,
        itemName=itemName,
        itemLevel=itemLevel or 0,
        equipLoc=equipLoc,
        bagID=item.bagID,
        slotID=item.slotID,
        lastAudit=item.lastAudit,
        retentionReason=type(item.retentionReason)=='string' and item.retentionReason or nil,
        category=parsed.category, slot=parsed.slot, primary=parsed.primary,
        type=parsed.type, character=owner or '', location=location or '',
    }
end

local function WGRGearSearchBuildTrackedDetailIndex()
    local index={}
    if not WGRGearSearchCleanupDetailEnabled() then return index end
    local saved=WGRStorageCleanupGetInventorySnapshots and WGRStorageCleanupGetInventorySnapshots()
    -- Storage Cleanup intentionally excludes immediate upgrades from future-use
    -- retention. Expanded Gather Gear / Gear Search details should still use
    -- the normal router for a display-only explanation instead of claiming
    -- those physical copies have no character assigned. Cache by exact link
    -- for this one render only so equipping/routing changes are reflected on
    -- the next refresh.
    local recommendationLabelCache={}
    local function ImmediateUpgradeLabel(link)
        if type(link)~='string' or link=='' or not WGRBuildLoadedItemRecommendation then return nil end
        local cached=recommendationLabelCache[link]
        if cached~=nil then return cached or nil end
        local recommendation,status=WGRBuildLoadedItemRecommendation(link)
        local label
        if status=='ready' and recommendation and recommendation.kind=='upgrade' then
            local name=tostring(recommendation.name or '')
            label=name~='' and ('Immediate upgrade: '..name) or 'Immediate upgrade'
        end
        recommendationLabelCache[link]=label or false
        return label
    end
    local function AddSection(owner,location,section)
        if type(section)~='table' then return end
        for _,item in ipairs(section.items or {}) do
            local detail=WGRGearSearchDetailRecord(item,owner,location)
            if detail then
                if not detail.retentionReason then
                    detail.immediateUpgradeReason=ImmediateUpgradeLabel(detail.itemLink)
                end
                local key=WGRGearSearchAggregateKey(detail)
                index[key]=index[key] or {}
                index[key][#index[key]+1]=detail
            end
        end
    end
    if type(saved)=='table' then
        for _,character in pairs(saved.characters or {}) do
            if type(character)=='table' and type(character.name)=='string' then
                local sections=character.sections or {}
                AddSection(character.name,'BAG',sections.BAG)
                AddSection(character.name,'PBK',sections.PBK)
            end
        end
        AddSection('', 'WBK', saved.warbank)
    end
    -- MAIL is not part of the Cleanup physical snapshot, but WBGR does retain
    -- exact links for tracked in-transit gear. Include those links so a MAIL
    -- aggregate can drill down too while Cleanup detail mode is active.
    local mailTracking=WarboundGearRouterDB and WarboundGearRouterDB.mailGearTracking or {}
    for _,entry in pairs(mailTracking or {}) do
        local owner=type(entry)=='table' and entry.name or nil
        if owner and owner~='' then
            for _,item in ipairs(entry.items or {}) do
                local detail=WGRGearSearchDetailRecord(item,owner,'MAIL')
                if detail then
                    if not detail.retentionReason then
                        detail.immediateUpgradeReason=ImmediateUpgradeLabel(detail.itemLink)
                    end
                    local key=WGRGearSearchAggregateKey(detail)
                    index[key]=index[key] or {}
                    index[key][#index[key]+1]=detail
                end
            end
        end
    end
    for _,details in pairs(index) do
        table.sort(details,function(a,b)
            local as=WGRGearSearchArmorSlotLabels[a.equipLoc] or 'Other'
            local bs=WGRGearSearchArmorSlotLabels[b.equipLoc] or 'Other'
            local ar=WGRGearSearchArmorSlotOrder[as] or 99
            local br=WGRGearSearchArmorSlotOrder[bs] or 99
            if ar~=br then return ar<br end
            if a.itemLevel~=b.itemLevel then return a.itemLevel>b.itemLevel end
            return tostring(a.itemLink)<tostring(b.itemLink)
        end)
    end
    return index
end

local function WGRGearSearchShowTrackedItemTooltip(button,item)
    if not item or not item.itemLink then return end
    if GameTooltip:IsShown() then GameTooltip:Hide() end
    GameTooltip:ClearLines()
    GameTooltip.__WGRLineAdded=false
    GameTooltip.__WGRIgnoredItemLink=nil
    GameTooltip:SetOwner(button,'ANCHOR_RIGHT')
    GameTooltip:SetHyperlink(item.itemLink)
    -- Match the managed tooltip lifecycle already validated in Recommendations
    -- and Storage Cleanup: initialize WBGR on first hover, Shift only expands.
    GameTooltip.__WGRGearFinderManaged=true
    GameTooltip:Show()
    if WGRRenderRecommendationForItemTooltip then
        local source=item.location=='BAG' and 'BAGS'
            or (item.location=='PBK' and 'PERSONAL_BANK')
            or (item.location=='WBK' and 'WARBAND_BANK')
            or item.location
        WGRRenderRecommendationForItemTooltip(GameTooltip,item.itemLink,{source=source})
    end
end

local function WGRGearSearchAddTrackedDetailRows(content,rowList,record,details,y)
    if not details or #details==0 then return y end
    local function AddItem(item)
        local line=CreateFrame('Button',nil,content)
        line:SetHeight(22)
        line:SetPoint('TOPLEFT',content,'TOPLEFT',34,-y)
        line:SetPoint('RIGHT',content,'RIGHT',0,0)
        local icon=line:CreateTexture(nil,'ARTWORK')
        icon:SetSize(18,18);icon:SetPoint('LEFT',line,'LEFT',0,0)
        icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.itemLink) or 134400)
        local name=line:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        name:SetPoint('LEFT',icon,'RIGHT',6,0);name:SetWidth(340);name:SetJustifyH('LEFT')
        name:SetText(item.itemLink)
        local reason=line:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        reason:SetPoint('LEFT',line,'LEFT',410,0);reason:SetWidth(275);reason:SetJustifyH('LEFT')
        reason:SetTextColor(0.72,0.72,0.72)
        reason:SetText(item.retentionReason or item.immediateUpgradeReason or 'No character assigned')
        local level=line:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        level:SetPoint('RIGHT',line,'RIGHT',-34,0);level:SetWidth(90);level:SetJustifyH('RIGHT')
        level:SetText('ilvl '..tostring(item.itemLevel or '?'))
        line:SetScript('OnEnter',function(self) WGRGearSearchShowTrackedItemTooltip(self,item) end)
        line:SetScript('OnLeave',function() GameTooltip:Hide() end)
        rowList[#rowList+1]=line
        y=y+22
    end
    if record.category=='Armor' then
        local groups={}
        for _,item in ipairs(details) do
            local label=WGRGearSearchArmorSlotLabels[item.equipLoc] or 'Other'
            groups[label]=groups[label] or {}
            groups[label][#groups[label]+1]=item
        end
        local labels={}
        for label in pairs(groups) do labels[#labels+1]=label end
        table.sort(labels,function(a,b)
            local ar=WGRGearSearchArmorSlotOrder[a] or 99
            local br=WGRGearSearchArmorSlotOrder[b] or 99
            if ar~=br then return ar<br end
            return a<b
        end)
        for _,label in ipairs(labels) do
            local header=CreateFrame('Frame',nil,content)
            header:SetHeight(20);header:SetPoint('TOPLEFT',content,'TOPLEFT',18,-y)
            header:SetPoint('RIGHT',content,'RIGHT',0,0)
            local text=header:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
            text:SetPoint('LEFT',header,'LEFT',0,0)
            text:SetText(label..' ('..tostring(#groups[label])..')')
            rowList[#rowList+1]=header
            y=y+20
            for _,item in ipairs(groups[label]) do AddItem(item) end
        end
    else
        for _,item in ipairs(details) do AddItem(item) end
    end
    local aggregateCount=tonumber(record.quantity) or 0
    if aggregateCount>#details then
        local note=CreateFrame('Frame',nil,content)
        note:SetHeight(20);note:SetPoint('TOPLEFT',content,'TOPLEFT',34,-y)
        note:SetPoint('RIGHT',content,'RIGHT',0,0)
        local text=note:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        text:SetPoint('LEFT',note,'LEFT',0,0);text:SetJustifyH('LEFT')
        text:SetTextColor(0.68,0.68,0.68)
        text:SetText(tostring(aggregateCount-#details)..
            ' additional item(s) are in the aggregate count but not in Storage Cleanup future-use detail.')
        rowList[#rowList+1]=note
        y=y+20
    end
    return y
end

-- v0.71b: Expandable aggregates advertise their state in the existing Category column
-- as [+] / [-]; non-expandable rows and Cleanup-OFF retain the original appearance.
local function WGRGearSearchMakeAggregateExpandable(row,bg,key,expandedRows,rerender)
    row:EnableMouse(true)
    row:SetScript('OnMouseUp',function(_,button)
        if button~='LeftButton' then return end
        expandedRows[key]=not expandedRows[key]
        rerender()
    end)
    row:SetScript('OnEnter',function(self)
        local tip=GameTooltip
        tip:SetOwner(self,'ANCHOR_RIGHT')
        tip:SetText(expandedRows[key] and 'Click to hide tracked items' or 'Click to show tracked items')
        tip:Show()
    end)
    row:SetScript('OnLeave',function() GameTooltip:Hide() end)
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
    local expandedRows={}
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
        local detailIndex=WGRGearSearchBuildTrackedDetailIndex()
        local detailEnabled=WGRGearSearchCleanupDetailEnabled()

        local specNames={}
        for _,specID in ipairs(context.specIDs or {}) do specNames[#specNames+1]=WGRSpecNamesByID and WGRSpecNamesByID[specID] or tostring(specID) end
        local specText=#specNames>0 and table.concat(specNames," | ") or "Spec not initialized"
        scopeHeader:SetText(tostring(context.name)..": "..specText)
        if context.removed then
            summary:SetText("Gather Gear is unavailable while this character is Removed from the WBGR roster.")
        else
            summary:SetText(tostring(#filtered).." compatible entr"..(#filtered==1 and "y" or "ies")..". Check for potential upgrades.")
        end

        local y=0
        for index,record in ipairs(filtered) do
            local row=CreateFrame("Frame",nil,content)
            row:SetPoint("TOPLEFT",content,"TOPLEFT",0,-y); row:SetPoint("RIGHT",content,"RIGHT",0,0); row:SetHeight(23)
            local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints()
            local shade=index%2==0 and 0.10 or 0.05; bg:SetColorTexture(shade,shade,shade,index%2==0 and 0.30 or 0.18)
            local key=WGRGearSearchAggregateKey(record)
            local details=detailEnabled and detailIndex[key] or nil
            local expandable=details and #details>0
            local values={record.category,record.slot,record.primary,record.type,record.character,record.location,tostring(record.quantity or 0)}
            if expandable then
                values[1]=(expandedRows[key] and '[-] ' or '[+] ')..tostring(values[1] or '')
            end
            for i,value in ipairs(values) do
                local text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                text:SetPoint("LEFT",row,"LEFT",starts[i]+3,0); text:SetWidth(widths[i]-6); text:SetJustifyH(i==7 and "CENTER" or "LEFT")
                text:SetText(value~="" and value or "-")
            end
            rowFrames[#rowFrames+1]=row
            y=y+24
            if expandable then
                WGRGearSearchMakeAggregateExpandable(row,bg,key,expandedRows,Render)
                if expandedRows[key] then
                    y=WGRGearSearchAddTrackedDetailRows(content,rowFrames,record,details,y)
                end
            end
        end
        content:SetHeight(math.max(1,y))
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


-- ============================================================
-- STORAGE CLEANUP (non-destructive, routing-aware review)
-- ============================================================
local function WGRStorageCleanupBankTabIDs(bankType)
    if not C_Bank or not C_Bank.FetchPurchasedBankTabIDs or bankType == nil then return {} end
    local ids = C_Bank.FetchPurchasedBankTabIDs(bankType)
    return type(ids) == "table" and ids or {}
end

-- v0.67v: passive snapshots reuse details ONLY for an unchanged physical
-- container slot/link for a short period. Explicit Cleanup audits never use
-- this cache, so the authoritative routing/retention checks remain fresh.
local WGRStorageCleanupObservedSlotCache={}
local WGRStorageCleanupSlotCacheLifetime=90
local function WGRStorageCleanupClock()
    return GetTime and GetTime() or 0
end
local function WGRStorageCleanupScanContainer(result,bagID,location,passiveCache,clock)
    local count=C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bagID) or 0
    for slotID=1,count do
        local link=C_Container.GetContainerItemLink(bagID,slotID)
        if link then
            local key=passiveCache and (tostring(bagID)..':'..tostring(slotID))
            local old=key and passiveCache[key]
            local cached=old and old.itemLink==link and old.location==location
                and clock and old.checkedAt and clock>=old.checkedAt
                and clock-old.checkedAt<WGRStorageCleanupSlotCacheLifetime
            local transferable=cached or (IsTransferableContainerItem
                and IsTransferableContainerItem(bagID,slotID,link))
            if transferable then
                local entry={itemLink=link,bagID=bagID,slotID=slotID,location=location,
                    source=location=="WBK" and "WARBAND_BANK" or (location=="PBK" and "PERSONAL_BANK" or "BAGS")}
                if cached and old.details then entry._observedDetails=old.details end
                result[#result+1]=entry
                if key and not cached then
                    passiveCache[key]={itemLink=link,location=location,checkedAt=clock}
                end
            elseif key then
                passiveCache[key]=nil
            end
        end
    end
end

local function WGRStorageCleanupScanAccessible(passiveCache)
    local result={}
    local clock=passiveCache and WGRStorageCleanupClock() or nil
    for bagID=0,4 do WGRStorageCleanupScanContainer(result,bagID,"BAG",passiveCache,clock) end
    local pbk=WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
    local wbk=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
    if pbk and Enum and Enum.BankType then
        for _,bagID in ipairs(WGRStorageCleanupBankTabIDs(Enum.BankType.Character)) do
            WGRStorageCleanupScanContainer(result,bagID,"PBK",passiveCache,clock)
        end
    end
    if wbk and Enum and Enum.BankType then
        for _,bagID in ipairs(WGRStorageCleanupBankTabIDs(Enum.BankType.Account)) do
            WGRStorageCleanupScanContainer(result,bagID,"WBK",passiveCache,clock)
        end
    end
    return result,pbk,wbk
end

-- v0.67w: A pure bag-slot shuffle does not change future demand or the set
-- of retained gear. Remap existing UI item references only when each physical
-- link/source can be matched unambiguously. Duplicates that changed positions
-- REQUIRE the established full audit; never reassign KEEP by guessing.
local function WGRStorageCleanupRemapOnlyMovement(oldItems,newItems)
    if type(oldItems)~='table' or type(newItems)~='table'
        or #oldItems~=#newItems then return false end
    local oldGroups,newGroups={},{}
    local function groupKey(item)
        if not item or not item.itemLink or not item.source
            or item.bagID==nil or item.slotID==nil then return nil end
        return tostring(item.source)..'\t'..tostring(item.itemLink)
    end
    for _,item in ipairs(oldItems) do
        local key=groupKey(item)
        if not key then return false end
        oldGroups[key]=oldGroups[key] or {}
        oldGroups[key][#oldGroups[key]+1]=item
    end
    for _,item in ipairs(newItems) do
        local key=groupKey(item)
        if not key then return false end
        newGroups[key]=newGroups[key] or {}
        newGroups[key][#newGroups[key]+1]=item
    end
    local moves={}
    for key,originals in pairs(oldGroups) do
        local current=newGroups[key]
        if not current or #originals~=#current then return false end
        if #originals>1 then
            -- A duplicate may be the protected KEEP while another is surplus.
            -- Only permit the shortcut when all its physical slots are intact.
            local slots={}
            for _,item in ipairs(originals) do
                slots[tostring(item.bagID)..':'..tostring(item.slotID)]=true
            end
            for _,item in ipairs(current) do
                if not slots[tostring(item.bagID)..':'..tostring(item.slotID)] then
                    return false
                end
            end
        else
            moves[#moves+1]={original=originals[1],current=current[1]}
        end
    end
    for key in pairs(newGroups) do
        if not oldGroups[key] then return false end
    end
    -- Validate the entire snapshot BEFORE mutating any existing UI positions.
    for _,pair in ipairs(moves) do
        pair.original.bagID=pair.current.bagID
        pair.original.slotID=pair.current.slotID
        pair.original.location=pair.current.location
        pair.original.source=pair.current.source
    end
    return true
end

local function WGRStorageCleanupBinding(item)
    if not C_TooltipInfo or not C_TooltipInfo.GetBagItem then return "UNKNOWN" end
    local data=C_TooltipInfo.GetBagItem(item.bagID,item.slotID)
    if not data or not data.lines then return "UNKNOWN" end
    if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
    for _,line in ipairs(data.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
        for _,text in ipairs({line.leftText,line.rightText}) do
            if text then
                local value=tostring(text):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):lower()
                if value:find("warbound until equipped",1,true) then return "WARBAND" end
                if value:find("binds when equipped",1,true) then return "BOE" end
            end
        end
    end
    return "UNKNOWN"
end

-- v0.68o: explicit disposal-mail candidates. Reuse the same live item
-- binding check as the Cleanup audit, never infer type from an item link.
-- Normal Mail Router and normal gear routing do not call this enumerator.
function WGRStorageCleanupDisposalMailCandidates(binding)
    if not (WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings().enabled)
        or (binding~='WARBAND' and binding~='BOE') then return {} end
    local result={}
    if not (C_Container and C_Container.GetContainerNumSlots and
        C_Container.GetContainerItemLink) then return result end
    for bag=0,4 do
        for slot=1,(C_Container.GetContainerNumSlots(bag) or 0) do
            local link=C_Container.GetContainerItemLink(bag,slot)
            if link and WGRStorageCleanupIsDisposeCopy and
                WGRStorageCleanupIsDisposeCopy(bag,slot,link) and
                IsTransferableContainerItem and
                IsTransferableContainerItem(bag,slot,link) then
                local guid=WGRStorageCleanupGetPhysicalCopyGUID and
                    WGRStorageCleanupGetPhysicalCopyGUID(bag,slot,link)
                if guid and WGRStorageCleanupBinding({bagID=bag,slotID=slot})==binding then
                    result[#result+1]={bagID=bag,slotID=slot,itemLink=link,guid=guid,binding=binding}
                end
            end
        end
    end
    return result
end

-- To Do quick action chooses a group, but only when its destination is
-- configured. Different Warbound/BoE destinations require separate drafts.
function WGRStorageCleanupNextDisposalMailGroup()
    local settings=WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings()
    if not settings or not settings.enabled then return nil end
    for _,def in ipairs({{'WARBAND','warboundRecipient'},{'BOE','boeRecipient'}}) do
        local destination=settings[def[2]]
        if destination and destination~='CURRENT' and
            #(WGRStorageCleanupDisposalMailCandidates(def[1]))>0 then
            return def[1],destination
        end
    end
    return nil
end

-- v0.67q: passive, read-only inventory capture. This intentionally does
-- NOT call WGRStorageCleanupAnalyze, the routing engine, or the frozen-batch
-- selection code. A manual PBK/WBK/Bags move should update physical snapshots
-- without changing which of several identical copies is KEEP this session.
local WGRStorageCleanupLastPassiveSignature=nil
local WGRStorageCleanupLastPassiveSaveAt=0
-- v0.72ai: passive observations are advisory background snapshots.  Keep a
-- known-good physical baseline so a transient post-transfer read cannot erase
-- the whole current inventory just because transferability/item data was
-- momentarily unavailable.  Explicit Scan Inventory remains authoritative.
local WGRStorageCleanupLastAcceptedObservedSet=nil
local WGRStorageCleanupPendingDestructiveSignature=nil
local WGRStorageCleanupPendingDestructiveCount=0
local function WGRStorageCleanupObservedIdentity(item)
    if not item or not item.itemLink or item.bagID==nil or item.slotID==nil then return nil end
    return table.concat({tostring(item.location or ''),tostring(item.bagID),
        tostring(item.slotID),tostring(item.itemLink)},'\031')
end
local function WGRStorageCleanupObservedIdentitySet(records)
    local set={}
    for _,item in ipairs(records or {}) do
        local key=WGRStorageCleanupObservedIdentity(item)
        if key then set[key]=true end
    end
    return set
end
local function WGRStorageCleanupPrimeObservedBaseline(records)
    local clock=WGRStorageCleanupClock()
    local set={}
    WGRStorageCleanupObservedSlotCache={}
    for _,item in ipairs(records or {}) do
        local identity=WGRStorageCleanupObservedIdentity(item)
        if identity then set[identity]=true end
        if item.bagID~=nil and item.slotID~=nil and item.itemLink and item.location then
            local key=tostring(item.bagID)..':'..tostring(item.slotID)
            local details
            if item.itemName and item.itemLevel and item.binding and item.cleanupEquipLoc then
                details={name=item.itemName,ilvl=item.itemLevel,minimum=item.minLevel,
                    binding=item.binding,group=item.cleanupGroupLabel,equipLoc=item.cleanupEquipLoc}
            end
            WGRStorageCleanupObservedSlotCache[key]={itemLink=item.itemLink,
                location=item.location,checkedAt=clock,details=details}
        end
    end
    WGRStorageCleanupLastAcceptedObservedSet=set
    WGRStorageCleanupPendingDestructiveSignature=nil
    WGRStorageCleanupPendingDestructiveCount=0
end
local function WGRStorageCleanupInvalidateObservedCache()
    WGRStorageCleanupObservedSlotCache={}
    WGRStorageCleanupLastPassiveSignature=nil
    WGRStorageCleanupLastAcceptedObservedSet=nil
    WGRStorageCleanupPendingDestructiveSignature=nil
    WGRStorageCleanupPendingDestructiveCount=0
end
local WGRStorageCleanupPassiveStats={lastMilliseconds=0,lastCount=0,reused=0,skipped=false,
    deferred=false,deferReason=nil}
function WGRStorageCleanupGetPassivePerformance()
    return WGRStorageCleanupPassiveStats
end
local function WGRStorageCleanupCaptureObservedInventory()
    if not WGRStorageCleanupGetSettings or not WGRStorageCleanupGetSettings().enabled then return end
    -- Do not even scan inventory/tooltip details for Removed bank alts.
    if WGRIsCharacterRemoved and WGRIsCharacterRemoved(UnitName('player')) then return end
    if not WGRStorageCleanupSaveObservedInventorySnapshot then return end
    if not C_Container or not C_Container.GetContainerItemLink then return end
    local started=debugprofilestop and debugprofilestop() or nil
    local records,pbkOpen,wbkOpen=WGRStorageCleanupScanAccessible(WGRStorageCleanupObservedSlotCache)
    -- Never replace an existing bank snapshot with a false empty observation
    -- while bank-tab enumeration is unavailable or still initializing.
    if pbkOpen and (not Enum or not Enum.BankType
        or #WGRStorageCleanupBankTabIDs(Enum.BankType.Character)==0) then
        pbkOpen=false
    end
    if wbkOpen and (not Enum or not Enum.BankType
        or #WGRStorageCleanupBankTabIDs(Enum.BankType.Account)==0) then
        wbkOpen=false
    end
    local reused=0
    local signatureParts={(UnitGUID and UnitGUID('player')) or (UnitName('player') or ''),
        pbkOpen and 'PBK' or '-',wbkOpen and 'WBK' or '-'}
    for _,item in ipairs(records) do
        local details=item._observedDetails
        if details then
            reused=reused+1
            item.itemName,item.itemLevel,item.minLevel,item.binding,item.cleanupGroupLabel,item.cleanupEquipLoc=
                details.name,details.ilvl,details.minimum,details.binding,details.group,details.equipLoc
        else
            local name,_,_,_,minimum,_,_,_,equipLoc
            if C_Item and C_Item.GetItemInfo then
                name,_,_,_,minimum,_,_,_,equipLoc=C_Item.GetItemInfo(item.itemLink)
            end
            item.itemName=name or item.itemLink
            item.itemLevel=tonumber(GetItemLevel and GetItemLevel(item.itemLink)) or 0
            item.minLevel=tonumber(minimum) or 0
            item.binding=WGRStorageCleanupBinding(item)
            item.cleanupEquipLoc=equipLoc
            if WGRClassifyHeldGearItem then
                local section,category=WGRClassifyHeldGearItem(item.itemLink)
                if section=='Weapons' and category then item.cleanupGroupLabel=category end
            end
            if not item.cleanupGroupLabel then
                item.cleanupGroupLabel=({INVTYPE_HEAD='Head',INVTYPE_SHOULDER='Shoulders',
                    INVTYPE_CHEST='Chest',INVTYPE_ROBE='Chest',INVTYPE_WAIST='Waist',
                    INVTYPE_LEGS='Legs',INVTYPE_FEET='Feet',INVTYPE_WRIST='Wrists',
                    INVTYPE_HAND='Hands',INVTYPE_CLOAK='Cloaks',INVTYPE_NECK='Necks',
                    INVTYPE_FINGER='Rings',INVTYPE_TRINKET='Trinkets'})[equipLoc] or equipLoc
            end
            local key=tostring(item.bagID)..':'..tostring(item.slotID)
            local cached=WGRStorageCleanupObservedSlotCache[key]
            if cached and cached.itemLink==item.itemLink and cached.location==item.location then
                cached.details={name=item.itemName,ilvl=item.itemLevel,minimum=item.minLevel,
                    binding=item.binding,group=item.cleanupGroupLabel,equipLoc=item.cleanupEquipLoc}
                -- Unresolved tooltip/item-data reads must be retried, never cached.
                if item.binding=='UNKNOWN' or item.itemLevel<=0 or not equipLoc then
                    cached.details=nil
                end
            end
        end
        item._observedDetails=nil
        signatureParts[#signatureParts+1]=table.concat({tostring(item.bagID),tostring(item.slotID),
            item.itemLink,tostring(item.itemLevel),tostring(item.binding)},':')
    end
    -- Background BAG/BANK events can fire during a short post-transfer window
    -- where the item links exist but transferability/item data is not ready.
    -- A destructive passive candidate (items disappeared with no matching new
    -- rows) must therefore be observed twice before it is allowed to replace a
    -- known-good baseline.  A genuine sale/mail/destruction is only delayed by
    -- this settle confirmation; explicit Scan Inventory bypasses this guard.
    local candidateSet=WGRStorageCleanupObservedIdentitySet(records)
    local removed,added=0,0
    if WGRStorageCleanupLastAcceptedObservedSet then
        for key in pairs(WGRStorageCleanupLastAcceptedObservedSet) do
            if not candidateSet[key] then removed=removed+1 end
        end
        for key in pairs(candidateSet) do
            if not WGRStorageCleanupLastAcceptedObservedSet[key] then added=added+1 end
        end
    end
    local signature=table.concat(signatureParts,'|')
    local clock=WGRStorageCleanupClock()
    -- v0.72am: never accept the impossible all-at-once collapse repeatedly
    -- observed live after bank moves (for example 34 known accessible items ->
    -- zero while PBK/WBK are still open). Both the eligibility scan and the raw
    -- slot APIs can transiently return empty during WoW bank churn, so retries
    -- cannot make that state authoritative. Only an explicit Scan Inventory may
    -- replace a populated baseline with a fully empty accessible inventory.
    local baselineCount=0
    for _ in pairs(WGRStorageCleanupLastAcceptedObservedSet or {}) do
        baselineCount=baselineCount+1
    end
    if baselineCount>0 and #records==0 and (pbkOpen or wbkOpen) then
        WGRStorageCleanupPassiveStats.lastCount=0
        WGRStorageCleanupPassiveStats.reused=reused
        WGRStorageCleanupPassiveStats.skipped=true
        WGRStorageCleanupPassiveStats.deferred=true
        WGRStorageCleanupPassiveStats.deferReason='catastrophic passive collapse withheld until explicit scan'
        if started then
            WGRStorageCleanupPassiveStats.lastMilliseconds=debugprofilestop()-started
        end
        return
    end
    local destructive=WGRStorageCleanupLastAcceptedObservedSet and removed>added
    if destructive then
        -- v0.72ak: Cross-check destructive passive candidates against the
        -- identity-only physical snapshot. The passive eligibility scanner can
        -- temporarily omit otherwise-present items while transferability/item
        -- data settles after a bank move. If any supposedly removed baseline
        -- copy is still physically present in the same slot/link, the passive
        -- candidate is incomplete and must never replace the known-good scan.
        local physicallyPresentMissing=0
        if WGRStorageCleanupSnapshotAccessiblePhysical then
            local raw=WGRStorageCleanupSnapshotAccessiblePhysical()
            local rawSet={}
            for _,rawItem in pairs((raw and raw.slots) or {}) do
                local rawKey=WGRStorageCleanupObservedIdentity(rawItem)
                if rawKey then rawSet[rawKey]=true end
            end
            for key in pairs(WGRStorageCleanupLastAcceptedObservedSet or {}) do
                if not candidateSet[key] and rawSet[key] then
                    physicallyPresentMissing=physicallyPresentMissing+1
                end
            end
        end
        if physicallyPresentMissing>0 then
            WGRStorageCleanupPassiveStats.lastCount=#records
            WGRStorageCleanupPassiveStats.reused=reused
            WGRStorageCleanupPassiveStats.skipped=true
            WGRStorageCleanupPassiveStats.deferred=true
            WGRStorageCleanupPassiveStats.deferReason='passive eligibility read omitted physically present items'
            if C_Timer and C_Timer.After then
                C_Timer.After(0.80,function()
                    if WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings().enabled then
                        WGRStorageCleanupCaptureObservedInventory()
                    end
                end)
            end
            if started then
                WGRStorageCleanupPassiveStats.lastMilliseconds=debugprofilestop()-started
            end
            return
        end
        if signature==WGRStorageCleanupPendingDestructiveSignature then
            WGRStorageCleanupPendingDestructiveCount=WGRStorageCleanupPendingDestructiveCount+1
        else
            WGRStorageCleanupPendingDestructiveSignature=signature
            WGRStorageCleanupPendingDestructiveCount=1
        end
        if WGRStorageCleanupPendingDestructiveCount<2 then
            WGRStorageCleanupPassiveStats.lastCount=#records
            WGRStorageCleanupPassiveStats.reused=reused
            WGRStorageCleanupPassiveStats.skipped=true
            WGRStorageCleanupPassiveStats.deferred=true
            WGRStorageCleanupPassiveStats.deferReason='destructive passive observation awaiting confirmation'
            if C_Timer and C_Timer.After then
                C_Timer.After(0.80,function()
                    if WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings().enabled then
                        WGRStorageCleanupCaptureObservedInventory()
                    end
                end)
            end
            if started then
                WGRStorageCleanupPassiveStats.lastMilliseconds=debugprofilestop()-started
            end
            return
        end
    else
        WGRStorageCleanupPendingDestructiveSignature=nil
        WGRStorageCleanupPendingDestructiveCount=0
    end
    -- Repeated bag events often report an identical observable snapshot. Do
    -- not rewrite SavedVariables or rebuild UI for them. Periodically refresh
    -- timestamps even when the physical inventory stays unchanged.
    local unchanged=signature==WGRStorageCleanupLastPassiveSignature
        and clock>=WGRStorageCleanupLastPassiveSaveAt
        and clock-WGRStorageCleanupLastPassiveSaveAt<60
    WGRStorageCleanupPassiveStats.lastCount=#records
    WGRStorageCleanupPassiveStats.reused=reused
    WGRStorageCleanupPassiveStats.skipped=unchanged
    WGRStorageCleanupPassiveStats.deferred=false
    WGRStorageCleanupPassiveStats.deferReason=nil
    if not unchanged then
        WGRStorageCleanupSaveObservedInventorySnapshot(records,pbkOpen,wbkOpen)
        WGRStorageCleanupLastPassiveSignature=signature
        WGRStorageCleanupLastPassiveSaveAt=clock
        WGRStorageCleanupLastAcceptedObservedSet=candidateSet
        WGRStorageCleanupPendingDestructiveSignature=nil
        WGRStorageCleanupPendingDestructiveCount=0
        if WGRNotifyStorageCleanupSnapshotChanged then
            -- Pass the already-accepted passive observation through to the UI.
            -- The UI must not immediately rescan live bank slots here: that
            -- second read can land in WoW's short post-transfer window and
            -- falsely report an entire bank as missing even though this
            -- accepted snapshot was valid.
            WGRNotifyStorageCleanupSnapshotChanged(records,pbkOpen,wbkOpen)
        end
    end
    if started then
        WGRStorageCleanupPassiveStats.lastMilliseconds=debugprofilestop()-started
    end
end

local WGRStorageCleanupSnapshotEventFrame=CreateFrame('Frame')
local WGRStorageCleanupSnapshotUpdateSerial=0
function WGRStorageCleanupScheduleObservedInventory(delay)
    if not WGRStorageCleanupGetSettings or not WGRStorageCleanupGetSettings().enabled then return end
    if WGRIsCharacterRemoved and WGRIsCharacterRemoved(UnitName('player')) then return end
    WGRStorageCleanupSnapshotUpdateSerial=WGRStorageCleanupSnapshotUpdateSerial+1
    local serial=WGRStorageCleanupSnapshotUpdateSerial
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(delay or 0.65,function()
        if serial~=WGRStorageCleanupSnapshotUpdateSerial then return end
        if WGRStorageCleanupGetSettings().enabled
            and not (WGRIsCharacterRemoved and WGRIsCharacterRemoved(UnitName('player'))) then
            WGRStorageCleanupCaptureObservedInventory()
        end
    end)
end
for _,event in ipairs({'PLAYER_ENTERING_WORLD','BAG_UPDATE_DELAYED',
    'BANKFRAME_OPENED','BANKFRAME_CLOSED','PLAYERBANKSLOTS_CHANGED',
    'PLAYER_EQUIPMENT_CHANGED'}) do
    WGRStorageCleanupSnapshotEventFrame:RegisterEvent(event)
end
WGRStorageCleanupSnapshotEventFrame:SetScript('OnEvent',function(_,event)
    -- Changing characters or equipping an item can change binding even when
    -- the old item link was cached. Future observations must recheck slots.
    if event=='PLAYER_ENTERING_WORLD' or event=='PLAYER_EQUIPMENT_CHANGED'
        or event=='BANKFRAME_OPENED' then
        WGRStorageCleanupInvalidateObservedCache()
    end
    local delay=event=='PLAYER_ENTERING_WORLD' and 1.8 or 0.65
    WGRStorageCleanupScheduleObservedInventory(delay)
end)

-- Read-only identity for Unique-Equipped rings and trinkets. A named
-- Unique-Equipped group can cover more than one itemID. Unknown tooltip data
-- means REVIEW rather than letting an uncertain duplicate become SURPLUS.
local function WGRStorageCleanupUniqueKeyFromTooltip(data,itemLink)
    if not data or not data.lines then return nil,false end
    if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
    for _,line in ipairs(data.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
        for _,value in ipairs({line.leftText,line.rightText}) do
            local clean=tostring(value or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):lower()
            local text=clean:match('unique%-equipped:?%s*(.*)')
            if text then
                local itemID=C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemLink)
                return text~='' and ('GROUP:'..text) or ('ID:'..tostring(itemID)),true
            end
        end
    end
    return nil,true
end

local function WGRStorageCleanupUniqueKey(item)
    if not C_TooltipInfo then return nil,false end
    local data
    -- v0.71h: The authoritative Cleanup/disposal paths still require the LIVE
    -- physical bag/slot tooltip. The separate account-wide DISPLAY pass marks
    -- its copied offline records explicitly; for those presentation-only rows,
    -- read intrinsic Unique-Equipped text from the saved hyperlink instead of
    -- accidentally inspecting the current character's unrelated bag slot.
    if item and item._WGRDisplayOfflineUnique then
        if not C_TooltipInfo.GetHyperlink then return nil,false end
        data=C_TooltipInfo.GetHyperlink(item.itemLink)
    else
        if not C_TooltipInfo.GetBagItem then return nil,false end
        data=C_TooltipInfo.GetBagItem(item.bagID,item.slotID)
    end
    return WGRStorageCleanupUniqueKeyFromTooltip(data,item and item.itemLink)
end

local function WGRStorageCleanupWeaponConfigFits(category,config)
    local two=category:find('2H ',1,true)==1
    local one=category:find('1H ',1,true)==1 or category=='Agility Daggers' or category=='Warglaives'
    if category=='Ranged' then return config=='RANGED' end
    if category=='Shields' then return config=='ONE_HAND_PLUS_SHIELD' end
    if category=='Off-Hands' then return config=='ONE_HAND_PLUS_OFFHAND' end
    if two then return config=='TWO_HAND' or config=='DUAL_2H' end
    if one then return config=='ONE_HAND' or config=='DUAL_1H'
        or config=='ONE_HAND_PLUS_SHIELD' or config=='ONE_HAND_PLUS_OFFHAND' end
    return false
end

local function WGRStorageCleanupWeaponCapacity(category,config)
    if (category:find('2H ',1,true)==1 and config=='DUAL_2H')
        or ((category:find('1H ',1,true)==1 or category=='Agility Daggers' or category=='Warglaives')
            and config=='DUAL_1H') then return 2 end
    return 1
end

-- Storage-only retention demand. The active routing roster determines order;
-- max-level characters are handled by ordinary routing, not future retention.
-- No new routing or spec rules are introduced here.
local function WGRStorageCleanupDemand(item,cooperate)
    local _,_,_,_,minimum,_,subtype,_,equipLoc=C_Item.GetItemInfo(item.itemLink)
    if not equipLoc then return nil,'Item data unavailable' end
    item.minLevel=tonumber(minimum) or 0
    local priority,slotIDs,category,groupKey,label,isWeapon,isTrinket
    local defaultCapacity=1
    if WGRArmorEquipSlots and WGRArmorEquipSlots[equipLoc] then
        priority=GetArmorPriorityList and GetArmorPriorityList(subtype)
        slotIDs={WGRArmorEquipSlots[equipLoc]}
        groupKey='ARMOR:'..tostring(slotIDs[1])..':'..tostring(subtype)
        label=tostring(subtype)..' '..tostring(equipLoc):gsub('INVTYPE_','')
    elseif WGRGlobalEquipSlots and WGRGlobalEquipSlots[equipLoc] then
        priority=GetActiveRoutingPriority and GetActiveRoutingPriority()
        slotIDs=WGRGlobalEquipSlots[equipLoc]
        isTrinket=equipLoc=='INVTYPE_TRINKET'
        groupKey=isTrinket and 'TRINKETS' or ('GLOBAL:'..tostring(equipLoc))
        label=({INVTYPE_FINGER='Rings',INVTYPE_NECK='Necks',INVTYPE_CLOAK='Cloaks',INVTYPE_TRINKET='Trinkets'})[equipLoc] or equipLoc
        defaultCapacity=(isTrinket or equipLoc=='INVTYPE_FINGER') and 2 or 1
    elseif (IsSupportedWeapon and IsSupportedWeapon(item.itemLink))
        or (WGROffhandEquipLocs and WGROffhandEquipLocs[equipLoc]) then
        local section
        if WGRClassifyHeldGearItem then
            section,category=WGRClassifyHeldGearItem(item.itemLink)
        end
        if section~='Weapons' or not category
            or category=='Other Weapons' or category:find('Other',1,true) then
            return nil,'Weapon stat/category needs review'
        end
        priority=GetActiveRoutingPriority and GetActiveRoutingPriority()
        isWeapon=true
        if category=='Shields' or category=='Off-Hands' then slotIDs={17}
        else slotIDs={16,17} end
        groupKey='WEAPON:'..category
        label=category
    else
        return nil,'Unrecognized equipment type'
    end
    if not priority or not slotIDs then return nil,'Unknown class, slot or priority' end
    local specSet=WGRGetItemSpecSet and WGRGetItemSpecSet(item.itemLink)
    local candidates,demands,perSpec={}, {}, {}
    local uncertain=false
    local maxLevel=tonumber(WGR_MAX_LEVEL) or 90
    for _,name in ipairs(priority) do
        if cooperate then cooperate() end
        local character=FindCharacterByName and FindCharacterByName(name)
        local level=character and WGRGetCharacterLevel and tonumber(WGRGetCharacterLevel(character)) or nil
        if not character or not level or level<=0 then
            uncertain=true
        elseif level<maxLevel then -- max-level upgrades are handled by normal routing
            local compatible=false
            local classID=GetCharacterClassID and GetCharacterClassID(name,character)
            local specIDs=WGRGetRoutingSpecIDs and WGRGetRoutingSpecIDs(name,character) or {}
            if #specIDs==0 and (isWeapon or isTrinket or specSet) then uncertain=true end
            local maxCapacity=1
            local matched={}
            for _,specID in ipairs(specIDs) do
                local match=true
                if specSet and not specSet[specID] then match=false end
                if match and (isWeapon or isTrinket) then
                    local fit=WGRItemFitsSpecificSpec and WGRItemFitsSpecificSpec(item.itemLink,classID,specID)
                    if fit==nil then uncertain=true;match=false end
                    if fit==false then match=false end
                end
                if match and isWeapon then
                    local classAllowed=WGRClassCanUseWeaponSubtype and WGRClassCanUseWeaponSubtype(classID,item.itemLink)
                    if classAllowed==nil then uncertain=true;match=false end
                    if classAllowed==false then match=false end
                    local configs=WGRGetAllowedSpecWeaponConfigs and WGRGetAllowedSpecWeaponConfigs(name,specID) or nil
                    if not configs or #configs==0 then uncertain=true;match=false end
                    local validConfig=false
                    for _,config in ipairs(configs or {}) do
                        if WGRStorageCleanupWeaponConfigFits(category,config)
                            and (not WGRSpecAllowsWeaponByProfile
                                or WGRSpecAllowsWeaponByProfile(name,specID,item.itemLink,
                                    (category=='Shields' or category=='Off-Hands') and 'OFFHAND' or 'WEAPON')) then
                            validConfig=true
                            maxCapacity=math.max(maxCapacity,WGRStorageCleanupWeaponCapacity(category,config))
                        end
                    end
                    if not validConfig then match=false end
                end
                if match then
                    compatible=true
                    matched[specID]=true
                end
            end
            if not (isWeapon or isTrinket) then
                -- Ordinary armor and unspecialized jewelry do not require
                -- remembered specs. Item-specific spec restrictions do.
                compatible=not specSet
                if WGRCharacterMatchesItemSpecs then
                    compatible=WGRCharacterMatchesItemSpecs(name,character,specSet)
                end
            end
            if compatible then
                candidates[#candidates+1]=name
                perSpec[name]=matched
                if isTrinket then
                    for _,specID in ipairs(specIDs) do
                        if matched[specID] then
                            local first,second
                            if WGRGetResolvedSpecTrinketLevels then
                                first,second=WGRGetResolvedSpecTrinketLevels(name,character,specID)
                            end
                            demands[#demands+1]={name=name,level=level,specID=specID,
                                retentionRole=WGRGetTrinketRetentionRoleForSpec and
                                    WGRGetTrinketRetentionRoleForSpec(specID) or nil,
                                capacity=2,owned={tonumber(first) or 0,tonumber(second) or 0}}
                        end
                    end
                else
                    local owned={}
                    if isWeapon then
                        -- Only count equipped items in the SAME independent
                        -- weapon category. Uncertain saved setups keep more.
                        local positions=(category=='Shields' or category=='Off-Hands') and {17} or {16,17}
                        for _,slot in ipairs(positions) do
                            local equipped=GetStoredItem and GetStoredItem(character,slot)
                            local _,otherCategory
                            if equipped and WGRClassifyHeldGearItem then
                                _,otherCategory=WGRClassifyHeldGearItem(equipped)
                            end
                            if equipped and otherCategory==category then
                                owned[#owned+1]=tonumber(GetItemLevel and GetItemLevel(equipped)) or 0
                            else
                                owned[#owned+1]=0
                            end
                        end
                    else
                        for _,slot in ipairs(slotIDs) do
                            local equipped=GetStoredItem and GetStoredItem(character,slot)
                            if equipped and not (GetItemLevel and GetItemLevel(equipped)) then uncertain=true end
                            owned[#owned+1]=tonumber(equipped and GetItemLevel and GetItemLevel(equipped)) or 0
                        end
                    end
                    demands[#demands+1]={name=name,level=level,owned=owned,
                        capacity=isWeapon and maxCapacity or defaultCapacity}
                end
            end
        end
    end
    if uncertain then return nil,'Incomplete eligibility, spec or equipped-gear data' end
    item.cleanupCandidates=candidates
    item.cleanupSpecCandidates=perSpec
    item.cleanupGroupKey=groupKey
    item.cleanupGroupLabel=label
    item.cleanupCapacity=defaultCapacity
    if equipLoc=='INVTYPE_FINGER' or isTrinket then
        local key,known=WGRStorageCleanupUniqueKey(item)
        if not known then return nil,'Unique-Equipped status unavailable' end
        item.cleanupUniqueKey=key
    end
    return demands
end

-- Multiple tracked specs sharing one functional role need one pair,
-- not one pair per spec. Other item categories retain their current identity.
local function WGRStorageCleanupDemandId(d)
    return tostring(d.name)..':'..tostring(d.retentionRole or d.specID or '')
end
local function WGRStorageCleanupMergeRetentionDemand(group,d)
    local id=WGRStorageCleanupDemandId(d)
    local existing=group.seen[id]
    if not existing then
        local owned={}
        for i,v in ipairs(d.owned or {}) do owned[i]=v end
        existing={name=d.name,level=d.level,specID=d.specID,
            retentionRole=d.retentionRole,capacity=d.capacity,owned=owned,
            eligibleSpecIDs=d.retentionRole and {[d.specID]=true} or nil}
        group.seen[id]=existing
        group.demands[#group.demands+1]=existing
    else
        existing.capacity=math.max(existing.capacity or 1,d.capacity or 1)
        for i,v in ipairs(d.owned or {}) do
            existing.owned[i]=math.min(existing.owned[i] or 0,v)
        end
        if d.retentionRole and d.specID then
            existing.eligibleSpecIDs=existing.eligibleSpecIDs or {}
            existing.eligibleSpecIDs[d.specID]=true
        end
    end
end

local function WGRStorageCleanupAnalyze()
    local items,pbk,wbk=WGRStorageCleanupScanAccessible()
    -- A full explicit holder view can safely retire old staged-DISPOSE GUIDs
    -- that no longer exist anywhere in this character's Bags/PBK/WBK. Do this
    -- before classification so sold history cannot make the current audit
    -- unnecessarily conservative.
    if pbk and wbk and WGRStorageCleanupPruneMissingStagedDisposeMarks then
        WGRStorageCleanupPruneMissingStagedDisposeMarks(true)
    end
    local keep,surplus,review={},{},{}
    local groups={}
    local current=UnitName("player") or "Current character"
    local rank={}
    for i,name in ipairs(GetActiveRoutingPriority and GetActiveRoutingPriority() or {}) do rank[name]=i end
    for _,item in ipairs(items) do
        local recommendation,status=nil,'unavailable'
        if WGRBuildLoadedItemRecommendation then
            recommendation,status=WGRBuildLoadedItemRecommendation(item.itemLink)
        end
        -- Markings belong to GUID-backed physical copies.  An explicitly
        -- disposed copy must leave the stock pool BEFORE allocating demand.
        -- The normal router still protects immediate upgrades.
        local override=WGRStorageCleanupGetCopyMark and
            WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source)
        local markedDispose=override=='DISPOSE' and
            WGRStorageCleanupIsDisposeCopy and
            WGRStorageCleanupIsDisposeCopy(item.bagID,item.slotID,item.itemLink,item.source)
        local name,_,_,_,_,_,_,_,equipLoc=C_Item.GetItemInfo(item.itemLink)
        item.itemName=name or tostring(item.itemLink)
        item.itemLevel=(GetItemLevel and GetItemLevel(item.itemLink)) or 0
        item.binding=WGRStorageCleanupBinding(item)
        item.recommendation=recommendation
        item.cleanupOverride=override
        local isTrinket=equipLoc=='INVTYPE_TRINKET'
        if markedDispose then
            item.cleanupReason='Manual DISPOSE — excluded from retained stock'
            item.cleanupDisposition='MANUAL_DISPOSE'
            surplus[#surplus+1]=item
        elseif status~='ready' or not item.itemLevel or item.itemLevel<=0 then
            if override=='KEEP' then
                item.cleanupReason='Manual KEEP — protected; item data not ready'
                keep[#keep+1]=item
            else
                item.cleanupReason='Item data or recommendation not ready'
                review[#review+1]=item
            end
        elseif recommendation and (recommendation.kind=='sell' or recommendation.kind=='no_current_upgrade') then
            if override=='KEEP' then
                item.cleanupReason='Manual KEEP — protected extra stock'
                keep[#keep+1]=item
            elseif isTrinket then
                item.cleanupReason='Trinket: review before surplus disposal'
                review[#review+1]=item
            else
                item.cleanupReason='No routed use remaining'
                surplus[#surplus+1]=item
            end
        elseif recommendation and (recommendation.kind=='holder' or recommendation.kind=='future_upgrade') then
            local demands,reason=WGRStorageCleanupDemand(item)
            if not demands then
                item.cleanupReason=reason or 'Needs review'
                if override=='KEEP' then
                    item.cleanupReason='Manual KEEP — protected; '..item.cleanupReason
                    keep[#keep+1]=item
                else review[#review+1]=item end
            elseif #demands==0 then
                if override=='KEEP' then
                    item.cleanupReason='Manual KEEP — protected extra stock'
                    keep[#keep+1]=item
                elseif isTrinket then
                    item.cleanupReason='No confirmed trinket coverage; review'
                    review[#review+1]=item
                else
                    item.cleanupReason='No eligible leveling demand'
                    surplus[#surplus+1]=item
                end
            else
                local key=item.cleanupGroupKey
                if not groups[key] then groups[key]={items={},demands={},seen={},capacity=item.cleanupCapacity} end
                local group=groups[key]
                for _,demand in ipairs(demands) do
                    WGRStorageCleanupMergeRetentionDemand(group,demand)
                end
                group.items[#group.items+1]=item
            end
        elseif not recommendation or recommendation.kind=='unknown' or recommendation.kind=='unresolved' then
            if override=='KEEP' then
                item.cleanupReason='Manual KEEP — protected; routing not yet resolved'
                keep[#keep+1]=item
            else
                item.cleanupReason='Routing needs review'
                review[#review+1]=item
            end
        else
            -- Live routing upgrades / outgoing routes are managed by the
            -- normal Recommendations tab, never reallocated by Cleanup.
        end
    end
    for _,group in pairs(groups) do
        table.sort(group.demands,function(a,b)
            local ar,br=rank[a.name] or 999999,rank[b.name] or 999999
            if ar~=br then return ar<br end
            if a.name~=b.name then return tostring(a.name)<tostring(b.name) end
            return (a.specID or 0)<(b.specID or 0)
        end)
        local reserved,assigned=WGRStorageCleanupPlanGroup(group.items,group.demands,
            group.capacity,nil,group.items[1] and group.items[1].cleanupGroupKey=='TRINKETS')
        for _,item in ipairs(group.items) do
            if reserved[item] or item.cleanupOverride=='KEEP' then
                local allocation=assigned[item]
                item.cleanupReason=allocation and WGRStorageCleanupAccountRetentionReason(allocation)
                    or (item.cleanupOverride=='KEEP' and 'Manual KEEP — protected extra stock' or 'Future use')
                item.cleanupAssignedName=allocation and allocation.name or nil
                keep[#keep+1]=item
            else
                local _,_,_,_,_,_,_,_,equipLoc=C_Item.GetItemInfo(item.itemLink)
                if equipLoc=='INVTYPE_TRINKET' or item.cleanupUniqueKey then
                    -- An unallocated ring/trinket can be constrained by
                    -- cross-spec or Unique-Equipped ownership not visible
                    -- in DataStore. Favor REVIEW over premature disposal.
                    item.cleanupReason='Pair/Unique-Equipped surplus requires review'
                    review[#review+1]=item
                else
                    item.cleanupReason='Beyond remaining category/level demand'
                    surplus[#surplus+1]=item
                end
            end
        end
    end
    local function sort(list,isKeep)
        table.sort(list,function(a,b)
            if (a.cleanupGroupLabel or "") ~= (b.cleanupGroupLabel or "") then
                return (a.cleanupGroupLabel or "") < (b.cleanupGroupLabel or "")
            end
            if isKeep then
                -- Allocation happens in Roster order. Display it the same way
                -- within each equipment category, not by alphabetic item name.
                local ar=rank[a.cleanupAssignedName] or 999999
                local br=rank[b.cleanupAssignedName] or 999999
                if ar~=br then return ar<br end
            end
            if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return (a.itemLevel or 0) > (b.itemLevel or 0) end
            if tostring(a.itemName)~=tostring(b.itemName) then return tostring(a.itemName)<tostring(b.itemName) end
            if (a.bagID or 0)~=(b.bagID or 0) then return (a.bagID or 0)<(b.bagID or 0) end
            return (a.slotID or 0)<(b.slotID or 0)
        end)
    end
    sort(keep,true);sort(surplus,false);sort(review,false)
    -- Read-only persisted details; no effect on retention or routing decisions.
    if WGRStorageCleanupSaveInventorySnapshot then
        WGRStorageCleanupSaveInventorySnapshot(items,pbk,wbk,keep,surplus,review)
    end
    -- Prime the passive observer from this authoritative explicit scan.  The
    -- first post-move background event can now reuse unchanged physical slots
    -- instead of re-proving every item during WoW's transfer settle window.
    if WGRStorageCleanupPrimeObservedBaseline then
        WGRStorageCleanupPrimeObservedBaseline(items)
    end
    return keep,surplus,review,#items,pbk,wbk,items
end

-- v0.67t: exploratory ACCOUNT-WIDE retention comparison, entirely separate
-- from the live local Cleanup audit and frozen-transfer mover. Saved records
-- have no reliable live tooltip/unique-equipped identity, so rings/trinkets
-- are REVIEW ONLY. No output from here authorizes a SURPLUS movement.
function WGRStorageCleanupComputeAccountPreview()
    local source=WGRStorageCleanupGetAccountSnapshotCandidates and WGRStorageCleanupGetAccountSnapshotCandidates()
    local preview={owners={},possible=0,unresolved=0,reviewReasons={},source=source,groups=0,
        incomingOwners={},incomingCount=0,incomingTransferable=0,incomingNeedsVerification=0,
        hypotheticalSelected=0,hypotheticalUnselected=0,hypotheticalReview=0,
        hypotheticalDisplaced=0,incomingDetails={},crosscheckCandidates={}}
    if not source or source.unavailable then return preview end
    -- Max-level character snapshots are *not* retained supply, nor are they
    -- proof of immediate upgrade/routing eligibility. Classify only their
    -- observation quality and transferable binding; never mark them SURPLUS.
    for _,item in ipairs(source.incoming or {}) do
        local owner=tostring(item.cleanupOwner or 'Unknown')
        local summary=preview.incomingOwners[owner]
        if not summary then
            summary={observed=0,transferable=0,unverified=0,types={},
                hypotheticalSelected=0,hypotheticalUnselected=0,hypotheticalReview=0}
            preview.incomingOwners[owner]=summary
        end
        summary.observed=summary.observed+1
        preview.incomingCount=preview.incomingCount+1
        local transferable=(item.binding=='WARBAND' or item.binding=='BOE')
        local verified=transferable and not item.cleanupScanStale
            and (tonumber(item.itemLevel) or 0)>0
        if verified then
            summary.transferable=summary.transferable+1
            preview.incomingTransferable=preview.incomingTransferable+1
        else
            summary.unverified=summary.unverified+1
            preview.incomingNeedsVerification=preview.incomingNeedsVerification+1
        end
        local category=tostring(item.category or 'Unknown')
        summary.types[category]=(summary.types[category] or 0)+1
    end
    local byGroup={}
    local blockedAccountGroups={}
    local rank={}
    for i,name in ipairs(GetActiveRoutingPriority and GetActiveRoutingPriority() or {}) do rank[name]=i end
    local function unresolved(item,reason)
        -- Never promote a category to the cross-check lane while another
        -- observed copy in that category has unresolved eligibility.
        if item.cleanupGroupKey then blockedAccountGroups[item.cleanupGroupKey]=true end
        reason=reason or 'Eligibility/spec data unresolved'
        preview.reviewReasons[reason]=(preview.reviewReasons[reason] or 0)+1
        preview.unresolved=preview.unresolved+1
        local owner=tostring(item.cleanupOwner or 'Unknown')
        preview.owners[owner]=preview.owners[owner] or {possible=0,unresolved=0,types={}}
        preview.owners[owner].unresolved=preview.owners[owner].unresolved+1
    end
    for _,item in ipairs(source.records or {}) do
        local link=item.itemLink
        local _,_,_,_,_,_,_,_,equipLoc
        if type(link)=='string' and C_Item and C_Item.GetItemInfo then
            _,_,_,_,_,_,_,_,equipLoc=C_Item.GetItemInfo(link)
        end
        local reviewReason
        if item.cleanupScanStale then reviewReason='Stale/incomplete inventory observation'
        elseif item.itemLevel<=0 or not equipLoc then reviewReason='Item data unavailable'
        elseif item.binding~='WARBAND' and item.binding~='BOE' then
            reviewReason='Binding not verified'
        elseif equipLoc=='INVTYPE_TRINKET' or equipLoc=='INVTYPE_FINGER' then
            reviewReason='Offline ring/trinket pair or Unique-Equipped rules'
        end
        if reviewReason then
            unresolved(item,reviewReason)
        else
            -- Reuse the SAME storage demand and spec/weapon eligibility code
            -- as the local audit. Never look up Unique-Equipped tooltip from
            -- an offline character's bag/slot (it could belong to someone else).
            local demands,reason=WGRStorageCleanupDemand(item)
            if not demands or #demands==0 or not item.cleanupGroupKey then
                unresolved(item,not demands and (reason or 'Eligibility/spec data unresolved')
                    or 'No confirmed future-use demand')
            else
                local key=item.cleanupGroupKey
                local group=byGroup[key]
                if not group then
                    group={items={},demands={},seen={},capacity=item.cleanupCapacity}
                    byGroup[key]=group
                end
                group.items[#group.items+1]=item
                for _,d in ipairs(demands) do
                    local id=tostring(d.name)..':'..tostring(d.specID or '')
                    if not group.seen[id] then
                        local owned={}
                        for i,v in ipairs(d.owned or {}) do owned[i]=v end
                        local copy={name=d.name,level=d.level,specID=d.specID,
                            capacity=d.capacity,owned=owned}
                        group.seen[id]=copy
                        group.demands[#group.demands+1]=copy
                    else
                        local existing=group.seen[id]
                        existing.capacity=math.max(existing.capacity or 1,d.capacity or 1)
                        for i,v in ipairs(d.owned or {}) do
                            existing.owned[i]=math.min(existing.owned[i] or 0,v)
                        end
                    end
                end
            end
        end
    end
    local baselineSelected={}
    local accountUnselected={}
    for _,group in pairs(byGroup) do
        preview.groups=preview.groups+1
        table.sort(group.demands,function(a,b)
            local ar,br=rank[a.name] or 999999,rank[b.name] or 999999
            if ar~=br then return ar<br end
            if a.name~=b.name then return tostring(a.name)<tostring(b.name) end
            return (a.specID or 0)<(b.specID or 0)
        end)
        local reserved=WGRStorageCleanupPlanGroup(group.items,group.demands,group.capacity)
        for _,item in ipairs(group.items) do
            if reserved[item] then baselineSelected[item]=true end
            if not reserved[item] then
                local owner=tostring(item.cleanupOwner or 'Unknown')
                preview.owners[owner]=preview.owners[owner] or {possible=0,unresolved=0,types={}}
                local summary=preview.owners[owner]
                summary.possible=summary.possible+1
                local category=tostring(item.cleanupGroupLabel or 'Other')
                summary.types[category]=(summary.types[category] or 0)+1
                preview.possible=preview.possible+1
                accountUnselected[#accountUnselected+1]=item
            end
        end
    end
    -- v0.68a: account snapshots provide a second opinion for local SURPLUS,
    -- not a disposal verdict. Exclude any category with unresolved records,
    -- stale/incomplete observations and unverifiable physical slot metadata.
    -- Cross-check identity is owner + bank source + slot + exact link + ilvl;
    -- the current LIVE local audit must separately mark that same slot SURPLUS.
    for _,item in ipairs(accountUnselected) do
        if not blockedAccountGroups[item.cleanupGroupKey]
            and not item.cleanupScanStale
            and (item.binding=='WARBAND' or item.binding=='BOE')
            and (tonumber(item.itemLevel) or 0)>0
            and item.bagID~=nil and item.slotID~=nil and item.itemLink
            and item.cleanupGroupKey then
            preview.crosscheckCandidates[#preview.crosscheckCandidates+1]={
                owner=item.cleanupOwner,location=item.cleanupLocation,
                bagID=item.bagID,slotID=item.slotID,
                itemLink=item.itemLink,itemLevel=item.itemLevel,
                groupKey=item.cleanupGroupKey,
            }
        end
    end
    -- v0.67y: A SECOND, independent, read-only what-if allocation considers
    -- max-level incoming observations alongside holder/WBK stock. This is NOT
    -- a routing decision: the unchanged router must first decide whether the
    -- item is needed immediately. In particular, a tentative replacement
    -- must never affect the above actual-holder possible-excess calculation.
    -- Keep this on the already-manual Refresh Preview path to avoid bag hitching.
    if #(source.incoming or {})>0 then
        local hypothetical={}
        for key,group in pairs(byGroup) do
            local copy={items={},demands={},seen={},capacity=group.capacity}
            for _,item in ipairs(group.items) do copy.items[#copy.items+1]=item end
            for _,d in ipairs(group.demands) do
                local owned={}
                for i,v in ipairs(d.owned or {}) do owned[i]=v end
                local demand={name=d.name,level=d.level,specID=d.specID,
                    capacity=d.capacity,owned=owned}
                local id=tostring(d.name)..':'..tostring(d.specID or '')
                copy.demands[#copy.demands+1]=demand
                copy.seen[id]=demand
            end
            hypothetical[key]=copy
        end
        local pending={}
        local affectedGroups={}
        -- Display-only explanation for each OBSERVED physical incoming copy.
        -- The planner assigns the hypothetical recipient: do not re-run it
        -- for explanations, mutate snapshots, or imply a routing decision.
        local function mark(item,status,reason,assignment)
            local owner=tostring(item.cleanupOwner or 'Unknown')
            local record=preview.incomingOwners[owner]
            local field=({SELECTED='hypotheticalSelected',UNSELECTED='hypotheticalUnselected',
                REVIEW='hypotheticalReview'})[status]
            if field then
                preview[field]=preview[field]+1
                if record then record[field]=record[field]+1 end
            end
            local candidates={}
            for _,name in ipairs(item.cleanupCandidates or {}) do
                candidates[#candidates+1]=name
            end
            preview.incomingDetails[#preview.incomingDetails+1]={
                owner=owner,location=tostring(item.cleanupLocation or '?'),
                bagID=item.bagID,slotID=item.slotID,
                itemLink=item.itemLink,itemName=item.itemName,
                itemLevel=tonumber(item.itemLevel) or 0,
                requiredLevel=tonumber(item.minLevel or item.requiredLevel) or 0,
                category=tostring(item.cleanupGroupLabel or item.category or 'Unknown'),
                groupKey=item.cleanupGroupKey,status=status,reason=reason,
                candidates=candidates,assignment=assignment and {
                    name=assignment.name,level=assignment.level,specID=assignment.specID
                } or nil,
            }
        end
        for _,item in ipairs(source.incoming) do
            local link=item.itemLink
            local equipLoc=nil
            if type(link)=='string' and C_Item and C_Item.GetItemInfo then
                _,_,_,_,_,_,_,_,equipLoc=C_Item.GetItemInfo(link)
            end
            local reviewReason
            if item.cleanupScanStale then reviewReason='Stale, incomplete or unverified inventory observation'
            elseif (tonumber(item.itemLevel) or 0)<=0 or not equipLoc then
                reviewReason='Item information unavailable'
            elseif item.binding~='WARBAND' and item.binding~='BOE' then
                reviewReason='Transferable binding not verified'
            elseif equipLoc=='INVTYPE_FINGER' or equipLoc=='INVTYPE_TRINKET' then
                reviewReason='Offline ring/trinket pair or Unique-Equipped rules' end
            if reviewReason then
                -- Never infer disposal or a future need from uncertain items.
                mark(item,'REVIEW',reviewReason)
            else
                local demands,reason=WGRStorageCleanupDemand(item)
                if not demands or #demands==0 or not item.cleanupGroupKey then
                    -- No confirmed future demand does not prove unneeded gear.
                    mark(item,'REVIEW',reason or 'No modeled future-demand match')
                else
                    local key=item.cleanupGroupKey
                    local group=hypothetical[key]
                    if not group then
                        group={items={},demands={},seen={},capacity=item.cleanupCapacity}
                        hypothetical[key]=group
                    end
                    group.items[#group.items+1]=item
                    affectedGroups[key]=true
                    pending[#pending+1]=item
                    for _,d in ipairs(demands) do
                        local id=tostring(d.name)..':'..tostring(d.specID or '')
                        if not group.seen[id] then
                            local owned={}
                            for i,v in ipairs(d.owned or {}) do owned[i]=v end
                            local entry={name=d.name,level=d.level,specID=d.specID,
                                capacity=d.capacity,owned=owned}
                            group.seen[id]=entry
                            group.demands[#group.demands+1]=entry
                        else
                            local existing=group.seen[id]
                            existing.capacity=math.max(existing.capacity or 1,d.capacity or 1)
                            for i,v in ipairs(d.owned or {}) do
                                existing.owned[i]=math.min(existing.owned[i] or 0,v)
                            end
                        end
                    end
                end
            end
        end
        if #pending>0 then
            local whatIfSelected,whatIfAssigned={},{}
            for _,group in pairs(hypothetical) do
                table.sort(group.demands,function(a,b)
                    local ar,br=rank[a.name] or 999999,rank[b.name] or 999999
                    if ar~=br then return ar<br end
                    if a.name~=b.name then return tostring(a.name)<tostring(b.name) end
                    return (a.specID or 0)<(b.specID or 0)
                end)
                local chosen,assigned=WGRStorageCleanupPlanGroup(group.items,group.demands,group.capacity)
                for item in pairs(chosen) do
                    whatIfSelected[item]=true
                    whatIfAssigned[item]=assigned and assigned[item] or nil
                end
            end
            for _,item in ipairs(pending) do
                if whatIfSelected[item] then
                    mark(item,'SELECTED',
                        'Allocated by best-needed planner alongside observed holder/WBK stock.',
                        whatIfAssigned[item])
                else
                    mark(item,'UNSELECTED',
                        'No allocation in combined future-stock model; normal routing not evaluated.')
                end
            end
            local changedByGroup={}
            for item in pairs(baselineSelected) do
                if affectedGroups[item.cleanupGroupKey] and not whatIfSelected[item] then
                    preview.hypotheticalDisplaced=preview.hypotheticalDisplaced+1
                    local key=item.cleanupGroupKey
                    changedByGroup[key]=(changedByGroup[key] or 0)+1
                end
            end
            -- Give explanations CATEGORY-LEVEL change context, not an
            -- invented one-to-one item replacement. Several incoming copies
            -- can jointly change the selected holder set in a category.
            for _,detail in ipairs(preview.incomingDetails) do
                if detail.groupKey and affectedGroups[detail.groupKey] then
                    local group=byGroup[detail.groupKey]
                    detail.groupHolderObserved=group and #group.items or 0
                    detail.groupPriorSelectionsChanged=changedByGroup[detail.groupKey] or 0
                end
            end
        end
    end
    -- Even a fresh complete snapshot is not proof that a physical copy is
    -- available; items may be in mail or pending transfer. Keep this preview
    -- non-actionable until the future arrival/disposal reconciliation exists.
    return preview
end

-- v0.68h: Cheap category screen for the manual To Do check. It must use
-- EXACTLY the same grouping rules as WGRStorageCleanupDemand below. A
-- nil answer means the item is not cheap to classify: fall back to the full
-- demand calculation, preserving the old conservative uncertainty handling.
-- No saved-data mutation, no precomputed cross-session classification.
local function WGRStorageCleanupQuickGroupKey(item)
    if not item or not item.itemLink or not C_Item or not C_Item.GetItemInfo then
        return nil
    end
    local _,_,_,_,_,_,subtype,_,equipLoc=C_Item.GetItemInfo(item.itemLink)
    if not equipLoc then return nil end
    if WGRArmorEquipSlots and WGRArmorEquipSlots[equipLoc] then
        return 'ARMOR:'..tostring(WGRArmorEquipSlots[equipLoc])..':'..tostring(subtype)
    end
    if WGRGlobalEquipSlots and WGRGlobalEquipSlots[equipLoc] then
        return equipLoc=='INVTYPE_TRINKET' and 'TRINKETS'
            or 'GLOBAL:'..tostring(equipLoc)
    end
    if (IsSupportedWeapon and IsSupportedWeapon(item.itemLink))
        or (WGROffhandEquipLocs and WGROffhandEquipLocs[equipLoc]) then
        local section,category
        if WGRClassifyHeldGearItem then
            section,category=WGRClassifyHeldGearItem(item.itemLink)
        end
        if section=='Weapons' and category and category~='Other Weapons'
            and not category:find('Other',1,true) then
            return 'WEAPON:'..category
        end
    end
    return nil
end

-- v0.68m: Manual holder-bound check with a second, verified-only proof.
-- Unrelated legacy scans cannot supply proof, while incomplete demand/
-- category evidence still blocks automatic disposal.
-- v0.68g: MANUAL, READ-ONLY targeted holder-bound preview for To Do.
-- This is a feasibility experiment, NOT DISPOSE. The saved account snapshot
-- may be incomplete/provisional or not physically reconciled. Thus an
-- unselected item is only POSSIBLE excess, never safe to sell or reroute.
-- The caller must supply only physically observed, already holder-routed
-- outgoing records. We revalidate their current normal route separately.
function WGRStorageCleanupCheckHolderBoundOnDemand(candidates,cooperate,options)
    options=options or {}
    local answer={checked=0,possible={},verifiedPossible={},retained={},uncertain={},provisional=false,
        sourceCount=0,blocked=0,stockSkipped=0,stockDemandChecks=0,
        stockDemandReused=0,evidence={},trinketEvidence={}}
    if not (WGRStorageCleanupGetSettings and WGRStorageCleanupGetSettings().enabled) then
        answer.error='Storage Cleanup is OFF';return answer
    end
    local source=WGRStorageCleanupGetAccountSnapshotCandidates and
        WGRStorageCleanupGetAccountSnapshotCandidates()
    if not source or source.unavailable then
        answer.error='Account inventory snapshots unavailable';return answer
    end
    answer.provisional=(source.provisionalSections or 0)>0
        or (source.incompleteSections or 0)>0
        or (source.staleSections or 0)>0
        or (source.missingLevelingCharacters or 0)>0
    local groups,blocked={},{}
    local physicalInputs={}
    local function physicalKey(item,owner,location)
        return tostring(owner)..'|'..tostring(location)..'|'
            ..tostring(item.bagID)..'|'..tostring(item.slotID)..'|'..tostring(item.itemLink)
    end
    local function mergeDemand(group,demands)
        for _,d in ipairs(demands or {}) do
            WGRStorageCleanupMergeRetentionDemand(group,d)
        end
    end
    local eligible={}
    local currentOwner=(type(UnitName)=='function' and UnitName('player')) or ''
    -- A holder's already-stored inventory does not require a new outgoing
    -- holder recommendation. It is PHYSICAL retained supply, not new mail.
    -- Only live-accessible copies may be classified in this mode.
    local heldMode=options.existingHolderStock==true
    for _,candidate in ipairs(candidates or {}) do
        if cooperate then cooperate() end
        answer.checked=answer.checked+1
        -- v0.72bg: authoritative live source is already present on every
        -- Cleanup candidate. Touch the saved manual override here so legacy
        -- v0.72bf PBK/WBK source misclassification can be repaired BEFORE
        -- offline saved stock is evaluated for unresolved DISPOSE tracking.
        if WGRStorageCleanupGetCopyMark and candidate.bagID~=nil and candidate.slotID~=nil then
            WGRStorageCleanupGetCopyMark(candidate.bagID,candidate.slotID,candidate.itemLink,candidate.source)
        end
        local link=candidate.itemLink
        local recommendation,status=WGRBuildLoadedItemRecommendation(link)
        local validSource=candidate.source=='BAGS' or candidate.source=='PERSONAL_BANK'
            or (options.liveWarbank and candidate.source=='WARBAND_BANK')
        local trueHolder=status=='ready' and recommendation
            and ((heldMode and (recommendation.kind=='holder'
                or recommendation.kind=='future_upgrade'
                or recommendation.kind=='sell'
                or recommendation.kind=='no_current_upgrade'))
                or (not heldMode and recommendation.kind=='holder'
                    and recommendation.name
                    and not ((WGRGearFinderSameCharacter and
                        WGRGearFinderSameCharacter(recommendation.name,currentOwner))
                        or (not WGRGearFinderSameCharacter
                            and tostring(recommendation.name):lower()==tostring(currentOwner):lower()))))
        local realCopy=validSource and candidate.bagID~=nil and candidate.slotID~=nil
            and C_Container and C_Container.GetContainerItemLink
            and C_Container.GetContainerItemLink(candidate.bagID,candidate.slotID)==link
        if not (trueHolder and realCopy) then
            answer.uncertain[#answer.uncertain+1]={item=candidate,
                reason=heldMode and 'Stored copy needs verified identity or routing eligibility'
                    or 'Item moved or normal routing is not strictly holder-bound'}
        else
            local _,_,_,_,_,_,_,_,equipLoc=C_Item.GetItemInfo(link)
            local item={itemLink=link,itemLevel=tonumber(GetItemLevel(link)) or 0,
                bagID=candidate.bagID,slotID=candidate.slotID,
                cleanupOwner=candidate.source=='WARBAND_BANK' and 'Shared Warbank' or currentOwner,
                cleanupLocation=candidate.source=='BAGS' and 'BAG'
                    or (candidate.source=='WARBAND_BANK' and 'WBK' or 'PBK')}
            -- Trinkets may now receive positive KEEP proof, but are never
            -- authorized as SURPLUS by this first-stage change.
            do
                local demands,reason=WGRStorageCleanupDemand(item,cooperate)
                if not demands or #demands==0 or not item.cleanupGroupKey
                    or item.itemLevel<=0 then
                    answer.uncertain[#answer.uncertain+1]={item=candidate,
                        reason=reason or 'No verified future-demand baseline'}
                else
                    local key=item.cleanupGroupKey
                    local group=groups[key]
                    if not group then
                        group={items={},verifiedItems={},demands={},seen={},capacity=item.cleanupCapacity,
                            incoming={},keepOnlyRing=(equipLoc=='INVTYPE_FINGER'),
                            keepOnlyTrinket=(equipLoc=='INVTYPE_TRINKET')}
                        groups[key]=group
                    elseif equipLoc=='INVTYPE_FINGER' then
                        group.keepOnlyRing=true
                    elseif equipLoc=='INVTYPE_TRINKET' then
                        group.keepOnlyTrinket=true
                    end
                    group.items[#group.items+1]=item
                    -- Every outgoing candidate is a physically observed copy.
                    -- Never rely on legacy/offline stock to approve its disposal.
                    group.verifiedItems[#group.verifiedItems+1]=item
                    group.incoming[#group.incoming+1]=item
                    mergeDemand(group,demands)
                    physicalInputs[physicalKey(item,item.cleanupOwner,item.cleanupLocation)]=true
                    eligible[item]=candidate
                end
            end
        end
    end
    if next(groups)==nil then return answer end
    -- The previous preview performed full class/spec/equipment-baseline
    -- analysis for EVERY saved stock item, even unrelated categories. On a
    -- large account this can hitch the UI for five outgoing copies. First
    -- screen by the same broad equipment group; only run expensive demand
    -- analysis when the group's actually involved. Unclassifiable items
    -- still take the old conservative full-analysis path.
    --
    -- Identical item links in a single explicit check share demand/eligibility
    -- facts (rings/trinkets, whose tooltip can be physical-slot-specific, are
    -- intentionally excluded above). Each PHYSICAL COPY remains independent
    -- in the allocator: this caches computations, NEVER stock quantities.
    local stockDemandCache={}
    -- Saved bank snapshots lack physical GUIDs. Reserve at most one saved
    -- matching copy per current GUID-keyed DISPOSE mark, instead of excluding
    -- ALL same-link copies. Never use a stale mark as proof of disposal.
    local possibleDisposeRemaining={}
    for _,stock in ipairs(source.records or {}) do
        if cooperate then cooperate() end
        -- When WBK is open, the actual live WBK candidates replace the
        -- persisted WBK snapshot. Never count an old WBK position twice or
        -- count its now-departed copy as additional trusted holder supply.
        if not ((options.liveWarbank and stock.cleanupLocation=='WBK')
            or (options.livePersonal and
                tostring(stock.cleanupOwner):lower()==tostring(currentOwner):lower()
                and (stock.cleanupLocation=='BAG'
                    or (options.livePersonalBank and stock.cleanupLocation=='PBK')))) then
        local quickKey=WGRStorageCleanupQuickGroupKey(stock)
        if quickKey and not groups[quickKey] then
            answer.stockSkipped=answer.stockSkipped+1
        else
            local _,_,_,_,_,_,_,_,equipLoc=C_Item.GetItemInfo(stock.itemLink)
            -- v0.72y: Include verified offline holder trinkets in the
            -- holder-bound allocation. Previously ALL offline trinkets were
            -- skipped, so a different character saw only WBK trinkets and
            -- could erroneously KEEP duplicates already held in PBK.
            -- Rings remain excluded: their separate pair-proof path is not
            -- enabled here. Saved trinket bag slots belong to the OFFLINE
            -- holder, so Unique-Equipped must be read from the stored link,
            -- never from the current character's unrelated bag slot.
            if equipLoc~='INVTYPE_FINGER' then
                local offlineTrinket=equipLoc=='INVTYPE_TRINKET'
                local key,demands,reason
                local cached=stock.itemLink and stockDemandCache[stock.itemLink]
                if cached then
                    answer.stockDemandReused=answer.stockDemandReused+1
                    stock.cleanupGroupKey=cached.groupKey
                    stock.cleanupGroupLabel=cached.groupLabel
                    stock.cleanupCapacity=cached.capacity
                    stock.cleanupCandidates=cached.candidates
                    stock.cleanupSpecCandidates=cached.specCandidates
                    stock.minLevel=cached.minLevel
                    -- v0.72ab: Each physical offline copy must retain the
                    -- same Unique-Equipped key when reusing link eligibility.
                    -- Without it, second/third copies look unrestricted and
                    -- can fill both trinket slots for the same character.
                    stock.cleanupUniqueKey=cached.uniqueKey
                    key=cached.groupKey
                    demands,reason=cached.demands,cached.reason
                else
                    answer.stockDemandChecks=answer.stockDemandChecks+1
                    if offlineTrinket then stock._WGRDisplayOfflineUnique=true end
                    demands,reason=WGRStorageCleanupDemand(stock,cooperate)
                    if offlineTrinket then stock._WGRDisplayOfflineUnique=nil end
                    key=stock.cleanupGroupKey
                    if stock.itemLink then
                        stockDemandCache[stock.itemLink]={
                            groupKey=key,groupLabel=stock.cleanupGroupLabel,
                            capacity=stock.cleanupCapacity,candidates=stock.cleanupCandidates,
                            specCandidates=stock.cleanupSpecCandidates,minLevel=stock.minLevel,
                            uniqueKey=stock.cleanupUniqueKey,
                            demands=demands,reason=reason}
                    end
                end
                if key and groups[key] then
                    if stock.cleanupScanStale or stock.itemLevel<=0
                        or (stock.binding~='WARBAND' and stock.binding~='BOE')
                        or not demands or #demands==0 then
                        blocked[key]=true
                    elseif not physicalInputs[physicalKey(stock,stock.cleanupOwner,stock.cleanupLocation)] then
                        local group=groups[key]
                        group.items[#group.items+1]=stock
                        -- Read-only explanation of saved stock included in this
                        -- account-wide category. No trust or disposal decision changes.
                        group.evidence=group.evidence or {}
                        local disposeKey=tostring(stock.cleanupOwner)..'\0'..tostring(stock.cleanupLocation)..'\0'..tostring(stock.itemLink)
                        local remaining=possibleDisposeRemaining[disposeKey]
                        if remaining==nil then
                            remaining=WGRStorageCleanupStockPossibleDisposeCount and
                                WGRStorageCleanupStockPossibleDisposeCount(stock) or nil
                            -- If count authority is unavailable, retain the
                            -- previous all-copies-excluded conservative rule.
                            if remaining==nil then remaining=-1 end
                        end
                        local excludedByMark=remaining~=0
                        if remaining>0 then remaining=remaining-1 end
                        possibleDisposeRemaining[disposeKey]=remaining
                        local trust=stock.cleanupTrackingProvisional and 'PROVISIONAL GENERATION'
                            or (excludedByMark and 'POSSIBLE DISPOSE MARK' or 'VERIFIED SUPPLY')
                        group.evidence[#group.evidence+1]={
                            owner=stock.cleanupOwner,location=stock.cleanupLocation,
                            itemLink=stock.itemLink,itemLevel=stock.itemLevel,
                            trust=trust,bagID=stock.bagID,slotID=stock.slotID,
                        }
                        -- Count exclusion is conservative per saved physical
                        -- copy; it does not clear any mark or choose a marked
                        -- GUID in offline inventory. Live incoming stays exact.
                        if not stock.cleanupTrackingProvisional and not excludedByMark then
                            group.verifiedItems[#group.verifiedItems+1]=stock
                        end
                        mergeDemand(group,demands)
                        answer.sourceCount=answer.sourceCount+1
                    end
                elseif quickKey and groups[quickKey] and not demands then
                    -- The exact item's spec/equipment evidence is missing,
                    -- but its broad equipment category IS relevant. Do not
                    -- let a failed demand lookup disappear and suggest that
                    -- another incoming copy could safely be excess.
                    blocked[quickKey]=true
                    answer.provisional=true
                elseif not demands and not key then
                    -- Preserve old caution for unclassifiable saved stock.
                    answer.provisional=true
                end
            end
        end
        end -- saved stock, excluding replaced WBK observations
    end
    -- Physically observed manual KEEP copies are protected stock, not
    -- disposal candidates. They still contribute to the actual holder supply
    -- when their complete physical identity and eligibility are established.
    for _,stock in ipairs(options.liveProtected or {}) do
        if cooperate then cooperate() end
        local demands,reason=WGRStorageCleanupDemand(stock,cooperate)
        local key=stock.cleanupGroupKey or WGRStorageCleanupQuickGroupKey(stock)
        if key and groups[key] then
            if not demands or #demands==0 or not stock.itemLevel
                or stock.itemLevel<=0 then blocked[key]=true
            else
                local group=groups[key]
                group.items[#group.items+1]=stock
                group.verifiedItems[#group.verifiedItems+1]=stock
                mergeDemand(group,demands)
            end
        elseif not key then answer.provisional=true end
    end
    -- Any live stored item which cannot be positively included as supply
    -- must not silently disappear and make another item appear disposable.
    -- Block only the relevant category; other equipment still progresses.
    for _,other in ipairs(options.liveStoredItems or options.liveWarbankItems or {}) do
        if cooperate then cooperate() end
        local key=WGRStorageCleanupQuickGroupKey(other)
        if key and groups[key] and not options.liveEligible[other]
            and not (options.liveExcluded and options.liveExcluded[other]) then
            blocked[key]=true
        elseif not key then
            answer.provisional=true
        end
    end
    local rank={}
    for i,name in ipairs(GetActiveRoutingPriority and GetActiveRoutingPriority() or {}) do
        rank[name]=i
    end
    for key,group in pairs(groups) do
        if cooperate then cooperate() end
        table.sort(group.demands,function(a,b)
            local ar,br=rank[a.name] or 999999,rank[b.name] or 999999
            if ar~=br then return ar<br end
            if a.name~=b.name then return tostring(a.name)<tostring(b.name) end
            return (a.specID or 0)<(b.specID or 0)
        end)
        if blocked[key] then
            WGRStorageCleanupRecordDiagnosticGroup(group,true,nil,nil,nil)
            answer.blocked=answer.blocked+1
            for _,item in ipairs(group.incoming) do
                answer.uncertain[#answer.uncertain+1]={item=eligible[item],
                    reason='Incomplete/uncertain holder inventory in category'}
            end
        else
            local selected,assigned=WGRStorageCleanupPlanGroup(
                group.items,group.demands,group.capacity,cooperate,group.keepOnlyTrinket)
            -- A second, strictly conservative allocation excludes provisional
            -- stock rather than letting it prove that a newly held copy is
            -- redundant. Demand is unchanged; never count missing stock as
            -- present. This proof is independent of unrelated categories.
            local trustedSelected=WGRStorageCleanupPlanGroup(
                group.verifiedItems,group.demands,group.capacity,cooperate,group.keepOnlyTrinket)
            WGRStorageCleanupRecordDiagnosticGroup(group,false,selected,assigned,trustedSelected)
            for _,item in ipairs(group.incoming) do
                local candidate=eligible[item]
                if not selected[item] and trustedSelected[item] then
                    answer.evidence[#answer.evidence+1]={
                        itemLink=item.itemLink,itemLevel=item.itemLevel,
                        category=item.cleanupGroupLabel or key,
                        candidateKey=candidate and table.concat({
                            tostring(candidate.source),tostring(candidate.bagID),
                            tostring(candidate.slotID),tostring(candidate.itemLink)
                        },':') or nil,
                        possible='NOT SELECTED',verified='SELECTED / NOT PROVEN SURPLUS',
                        stock=group.evidence or {},
                        possibleCount=#group.items,verifiedCount=#group.verifiedItems,
                    }
                end
                if selected[item] then
                    if candidate and assigned and assigned[item] then
                        local a=assigned[item]
                        candidate.cleanupAccountAssignment={
                            name=a.name,level=a.level,specID=a.specID,
                            retentionRole=a.retentionRole}
                    end
                    answer.retained[#answer.retained+1]=candidate
                elseif group.keepOnlyTrinket then
                    -- v0.70v: READ-ONLY trinket surplus investigation. Reuse
                    -- the existing planner's decisions. These are reservation
                    -- observations, NOT simultaneous-equipment proof and NEVER
                    -- a disposal authorization.
                    local roleLabels={PHYSICAL_DPS='Physical DPS',CASTER_DPS='Caster DPS',
                        TANK='Tank',HEALER='Healer'}
                    local counts,roles={},{}
                    for _,d in ipairs(group.demands or {}) do
                        local role=d.retentionRole or tostring(d.specID or 'Unknown')
                        local id=tostring(d.name)..' / '..tostring(role)
                        local entry={name=d.name,role=roleLabels[role] or tostring(role),
                            allocated=0,target=tonumber(d.capacity) or 2,eligible=false}
                        local perSpec=item.cleanupSpecCandidates and
                            item.cleanupSpecCandidates[d.name] or {}
                        if d.eligibleSpecIDs then
                            for specID in pairs(d.eligibleSpecIDs) do
                                if perSpec[specID] then entry.eligible=true;break end
                            end
                        elseif d.specID then entry.eligible=not not perSpec[d.specID]
                        else
                            for _,name in ipairs(item.cleanupCandidates or {}) do
                                if name==d.name then entry.eligible=true;break end
                            end
                        end
                        counts[id]=entry
                        roles[#roles+1]=entry
                    end
                    local function countAssignments(assignments)
                        local result={}
                        for _,allocation in pairs(assignments or {}) do
                            local id=tostring(allocation.name)..' / '..
                                tostring(allocation.retentionRole or allocation.specID or 'Unknown')
                            result[id]=(result[id] or 0)+1
                        end
                        return result
                    end
                    local selectedCounts=countAssignments(assigned)
                    -- The verified allocation result is deliberately recomputed
                    -- for diagnostics ONLY if it can be compared independently;
                    -- no data is committed and it cannot authorize disposal.
                    local _,trustedAssigned=WGRStorageCleanupPlanGroup(
                        group.verifiedItems,group.demands,group.capacity,cooperate,true)
                    local trustedCounts=countAssignments(trustedAssigned)
                    -- v0.70y: READ-ONLY removal simulation. Re-run the exact
                    -- trusted future-retention planner with THIS incoming copy
                    -- omitted. If every selected physical copy and its assigned
                    -- character/role remain unchanged, then this candidate has
                    -- no effect on the planner's modeled retention/leveling
                    -- coverage. This is evidence only; it cannot authorize
                    -- disposal because offline equip facts can still be incomplete.
                    local trustedWithoutCandidate={}
                    local candidateInTrusted=false
                    for _,physical in ipairs(group.verifiedItems or {}) do
                        if physical==item then candidateInTrusted=true
                        else trustedWithoutCandidate[#trustedWithoutCandidate+1]=physical end
                    end
                    local withoutSelected,withoutAssigned=WGRStorageCleanupPlanGroup(
                        trustedWithoutCandidate,group.demands,group.capacity,cooperate,true)
                    local removalStable=candidateInTrusted and not trustedSelected[item]
                    local removalDetail=removalStable and
                        'trusted allocation unchanged with candidate excluded' or
                        (not candidateInTrusted and 'candidate is not in trusted supply' or
                            (trustedSelected[item] and 'candidate is selected by trusted allocation' or
                                'trusted allocation changed'))
                    if removalStable then
                        for physical in pairs(trustedSelected or {}) do
                            if physical~=item and not withoutSelected[physical] then
                                removalStable=false;removalDetail='a previously selected physical copy changed';break
                            end
                        end
                    end
                    if removalStable then
                        for physical in pairs(withoutSelected or {}) do
                            if not trustedSelected[physical] then
                                removalStable=false;removalDetail='exclusion selected a different physical copy';break
                            end
                        end
                    end
                    local function SameAssignment(a,b)
                        if a==nil or b==nil then return a==b end
                        return tostring(a.name)==tostring(b.name)
                            and tostring(a.retentionRole or a.specID or '')==
                                tostring(b.retentionRole or b.specID or '')
                            and tonumber(a.level or 0)==tonumber(b.level or 0)
                    end
                    if removalStable then
                        for physical,allocation in pairs(trustedAssigned or {}) do
                            if not SameAssignment(allocation,withoutAssigned and withoutAssigned[physical]) then
                                removalStable=false;removalDetail='a retained copy changed character/role assignment';break
                            end
                        end
                    end
                    if removalStable then
                        for physical,allocation in pairs(withoutAssigned or {}) do
                            if not SameAssignment(allocation,trustedAssigned and trustedAssigned[physical]) then
                                removalStable=false;removalDetail='exclusion created a different assignment';break
                            end
                        end
                    end
                    -- v0.70x: Pair evidence uses exactly the trusted planner's
                    -- physical-copy assignments. Never infer pairs from counts.
                    -- Offline snapshots cannot always prove all equip rules;
                    -- this report must never grant disposal authorization.
                    local pairMembers={}
                    for physical,allocation in pairs(trustedAssigned or {}) do
                        local id=tostring(allocation.name)..' / '..
                            tostring(allocation.retentionRole or allocation.specID or 'Unknown')
                        pairMembers[id]=pairMembers[id] or {}
                        pairMembers[id][#pairMembers[id]+1]=physical
                    end
                    for id,copies in pairs(pairMembers) do
                        table.sort(copies,function(a,b)
                            if (a.itemLevel or 0)~=(b.itemLevel or 0) then
                                return (a.itemLevel or 0)>(b.itemLevel or 0)
                            end
                            return tostring(a.itemLink or '')<tostring(b.itemLink or '')
                        end)
                    end
                    for i,d in ipairs(group.demands or {}) do
                        local id=tostring(d.name)..' / '..tostring(d.retentionRole or d.specID or 'Unknown')
                        roles[i].allocated=selectedCounts[id] or 0
                        roles[i].trusted=trustedCounts[id] or 0
                        local copies=pairMembers[id] or {}
                        local pair={}
                        for _,copy in ipairs(copies) do
                            pair[#pair+1]={link=copy.itemLink,level=copy.itemLevel,
                                uniqueKey=copy.cleanupUniqueKey,
                                location=copy.cleanupLocation,
                                owner=copy.cleanupOwner}
                        end
                        roles[i].trustedPair=pair
                        roles[i].pairSafe=false
                        if #copies~=2 then
                            roles[i].pairVerdict='INCOMPLETE (not exactly two trusted reserved copies)'
                        elseif copies[1]==copies[2] then
                            roles[i].pairVerdict='CONFLICT (same physical copy)'
                        elseif copies[1].cleanupUniqueKey and copies[1].cleanupUniqueKey==
                            copies[2].cleanupUniqueKey then
                            roles[i].pairVerdict='CONFLICT (matching Unique-Equipped key)'
                        else
                            -- WGRStorageCleanupDemand only admits trinkets when
                            -- Unique-Equipped status is known. NIL here means a
                            -- confirmed absence of a Unique-Equipped restriction,
                            -- not missing tooltip evidence.
                            roles[i].pairSafe=true
                            roles[i].pairVerdict='NO RECORDED CONFLICT (not full equip proof)'
                        end
                    end
                    -- v0.70z: Conservative ACTIONABLE trinket surplus proof.
                    -- The candidate must be trusted, unselected in both plans,
                    -- removal must leave the exact trusted assignment unchanged,
                    -- and every role this candidate could serve must retain a
                    -- complete two-copy pair with no known Unique-Equipped
                    -- conflict. Other unfilled roles cannot be "fixed" by this
                    -- candidate and therefore do not block its disposal proof.
                    local affectedRoles=0
                    local retainedPairsSafe=true
                    for _,role in ipairs(roles) do
                        if role.eligible then
                            affectedRoles=affectedRoles+1
                            if tonumber(role.target or 0)~=2
                                or tonumber(role.trusted or 0)<2
                                or #(role.trustedPair or {})~=2
                                or not role.pairSafe then
                                retainedPairsSafe=false
                            end
                        end
                    end
                    local cleanupProven=candidateInTrusted and not selected[item]
                        and not trustedSelected[item] and removalStable
                        and affectedRoles>0 and retainedPairsSafe
                    if cleanupProven and candidate then
                        candidate.cleanupTrinketSurplusProven=true
                        answer.verifiedPossible[#answer.verifiedPossible+1]=candidate
                    end
                    table.sort(roles,function(a,b)
                        if a.name~=b.name then return tostring(a.name)<tostring(b.name) end
                        return tostring(a.role)<tostring(b.role)
                    end)
                    answer.trinketEvidence[#answer.trinketEvidence+1]={
                        itemLink=item.itemLink,itemLevel=item.itemLevel,
                        possibleSelected=not not selected[item],
                        trustedSelected=not not trustedSelected[item],
                        possibleCopies=#group.items,trustedCopies=#group.verifiedItems,
                        uniqueKnown=item.cleanupUniqueKey~=nil,
                        uniqueKey=item.cleanupUniqueKey,
                        roles=roles,
                        removalCandidateTrusted=candidateInTrusted,
                        removalStable=removalStable,
                        removalDetail=removalDetail,
                        removalTrustedCopies=#trustedWithoutCandidate,
                        cleanupProven=cleanupProven,
                        affectedRoles=affectedRoles,
                        retainedPairsSafe=retainedPairsSafe,
                    }
                    if not cleanupProven then
                        answer.uncertain[#answer.uncertain+1]={item=candidate,
                            reason='Trinket not retained; surplus requires account-wide pair/Unique-Equipped proof'}
                    end
                elseif group.keepOnlyRing then
                    -- Positive KEEP proof for rings is useful and safe. Negative
                    -- proof is not: offline ring stock is intentionally omitted
                    -- until pair/Unique-Equipped reconciliation is complete.
                    answer.uncertain[#answer.uncertain+1]={item=candidate,
                        reason='Ring not retained; surplus requires account-wide pair/Unique-Equipped certainty'}
                else
                    answer.possible[#answer.possible+1]=candidate
                    if not trustedSelected[item] then
                        answer.verifiedPossible[#answer.verifiedPossible+1]=candidate
                    end
                end
            end
        end
    end
    -- Never mutate any SavedVariables, mail, normal route, To Do, or movement.
    return answer
end

-- Human-readable audit reason for a positively retained physical copy.
-- The planner already computes this assignment; expose it instead of hiding
-- useful character/level context behind a generic KEEP explanation.
function WGRStorageCleanupAccountRetentionReason(assignment)
    if type(assignment)~='table' or not assignment.name or assignment.name=='' then
        return 'Retained by account-wide allocation'
    end
    local reason='Retained for '..tostring(assignment.name)
    -- Storage Cleanup only: report the actual reserved trinket role, not
    -- every role in which this physical copy could have been useful.
    local labels={PHYSICAL_DPS='Physical DPS',CASTER_DPS='Caster DPS',
        TANK='Tank',HEALER='Healer'}
    local role=labels[assignment.retentionRole]
    if role then reason=reason..' / '..role end
    local level=tonumber(assignment.level)
    if level and level>0 then reason=reason..' / level '..tostring(level) end
    return reason
end


-- v0.71e: Build display-only retention explanations for ALL ordinary saved
-- holder/WBK stock during the same explicit account-wide scan. This does not
-- authorize cleanup, change routing, or mutate allocation inputs. Rings and
-- trinkets intentionally stay on their existing live-scanned explanation path
-- because offline pair/Unique-Equipped evidence remains conservative.
local function WGRStorageCleanupBuildAccountRetentionDisplayDetails(cooperate)
    local source=WGRStorageCleanupGetAccountSnapshotCandidates and
        WGRStorageCleanupGetAccountSnapshotCandidates()
    if not source or source.unavailable then return {} end
    local details,groups={},{}
    local demandCache={}
    local function detailKey(item)
        return table.concat({tostring(item.cleanupOwner or ''),
            tostring(item.cleanupLocation or ''),tostring(item.bagID),
            tostring(item.slotID),tostring(item.itemLink or '')},'\031')
    end
    local byKey={}
    for _,item in ipairs(source.records or {}) do
        if cooperate then cooperate() end
        local link=item.itemLink
        -- v0.71f: saved Cleanup snapshots already contain equipLoc and are
        -- populated only from gear that was physically observed as transferable.
        -- Do not require the offline item to still be in the live item cache, and
        -- do not discard a valid historical row merely because its tooltip-derived
        -- binding label was UNKNOWN when the snapshot was written.
        local equipLoc=item.equipLoc or item.cleanupEquipLoc
        if (not equipLoc or equipLoc=='') and link and C_Item and C_Item.GetItemInfo then
            local _name,_link,_quality,_ilvl,_minimum,_class,_subtype,_stack
            _name,_link,_quality,_ilvl,_minimum,_class,_subtype,_stack,equipLoc=
                C_Item.GetItemInfo(link)
        end
        -- v0.71g: The display-only pass can also carry positive ring/trinket
        -- KEEP assignments. It never authorizes disposal: if pair/Unique-Equipped
        -- facts cannot be resolved from the saved item link, leave the prior
        -- explanation alone and let the drill-down show its neutral fallback.
        if equipLoc and (tonumber(item.itemLevel) or 0)>0 then
            local key=detailKey(item)
            local detail={owner=item.cleanupOwner,location=item.cleanupLocation,
                bagID=item.bagID,slotID=item.slotID,itemLink=item.itemLink,reason=nil}
            local cached=link and demandCache[link]
            local demands
            if cached then
                item.cleanupGroupKey=cached.groupKey
                item.cleanupGroupLabel=cached.groupLabel
                item.cleanupCapacity=cached.capacity
                item.cleanupCandidates=cached.candidates
                item.cleanupSpecCandidates=cached.specCandidates
                item.minLevel=cached.minLevel
                item.cleanupUniqueKey=cached.uniqueKey
                demands=cached.demands
            else
                -- Display-only offline records have saved physical identity but
                -- their bag/slot belongs to another character. Allow the demand
                -- builder to resolve intrinsic ring/trinket Unique-Equipped text
                -- from the hyperlink for this presentation pass only.
                item._WGRDisplayOfflineUnique=true
                demands=WGRStorageCleanupDemand(item,cooperate)
                item._WGRDisplayOfflineUnique=nil
                if link then
                    demandCache[link]={groupKey=item.cleanupGroupKey,
                        groupLabel=item.cleanupGroupLabel,capacity=item.cleanupCapacity,
                        candidates=item.cleanupCandidates,specCandidates=item.cleanupSpecCandidates,
                        minLevel=item.minLevel,uniqueKey=item.cleanupUniqueKey,demands=demands}
                end
            end
            local special=equipLoc=='INVTYPE_FINGER' or equipLoc=='INVTYPE_TRINKET'
            if demands and #demands>0 and item.cleanupGroupKey then
                details[#details+1]=detail;byKey[key]=detail
                local group=groups[item.cleanupGroupKey]
                if not group then
                    group={items={},demands={},seen={},capacity=item.cleanupCapacity,
                        noCrossDemandSharing=(equipLoc=='INVTYPE_TRINKET')}
                    groups[item.cleanupGroupKey]=group
                elseif equipLoc=='INVTYPE_TRINKET' then
                    group.noCrossDemandSharing=true
                end
                group.items[#group.items+1]=item
                for _,d in ipairs(demands) do
                    WGRStorageCleanupMergeRetentionDemand(group,d)
                end
            elseif not special then
                -- Ordinary categories were already safe to clear when the full
                -- display allocation could not retain this copy.
                details[#details+1]=detail;byKey[key]=detail
            elseif type(item.retentionReason)=='string' and item.retentionReason~='' then
                -- If an older live scan already captured a positive ring/trinket
                -- reason but current offline pair facts are unavailable, preserve it.
                detail.reason=item.retentionReason
                details[#details+1]=detail;byKey[key]=detail
            end
        end
    end
    local rank={}
    for i,name in ipairs(GetActiveRoutingPriority and GetActiveRoutingPriority() or {}) do
        rank[name]=i
    end
    for _,group in pairs(groups) do
        if cooperate then cooperate() end
        table.sort(group.demands,function(a,b)
            local ar,br=rank[a.name] or 999999,rank[b.name] or 999999
            if ar~=br then return ar<br end
            if tostring(a.name)~=tostring(b.name) then return tostring(a.name)<tostring(b.name) end
            return tostring(a.retentionRole or a.specID or '')<tostring(b.retentionRole or b.specID or '')
        end)
        local selected,assigned=WGRStorageCleanupPlanGroup(
            group.items,group.demands,group.capacity,cooperate,group.noCrossDemandSharing)
        for _,item in ipairs(group.items) do
            if selected[item] then
                local detail=byKey[detailKey(item)]
                if detail then
                    detail.reason=WGRStorageCleanupAccountRetentionReason(
                        assigned and assigned[item] or nil)
                end
            end
        end
    end
    return details
end


-- v0.70e: Account-wide remapping rebuilds KEEP/SURPLUS/REVIEW from the
-- physical inventory list, so re-apply the user-facing KEEP order afterward.
-- Allocation itself is unchanged; this is presentation only.
function WGRStorageCleanupSortAccountClassified(keep,surplus,review)
    local rank={}
    for i,name in ipairs(GetActiveRoutingPriority and GetActiveRoutingPriority() or {}) do
        rank[name]=i
    end
    local function sort(list,isKeep)
        table.sort(list or {},function(a,b)
            local ag=a.cleanupGroupLabel or ''
            local bg=b.cleanupGroupLabel or ''
            if ag~=bg then return ag<bg end
            if isKeep then
                local ar=rank[a.cleanupAssignedName] or 999999
                local br=rank[b.cleanupAssignedName] or 999999
                if ar~=br then return ar<br end
            end
            if (a.itemLevel or 0)~=(b.itemLevel or 0) then
                return (a.itemLevel or 0)>(b.itemLevel or 0)
            end
            if tostring(a.itemName)~=tostring(b.itemName) then
                return tostring(a.itemName)<tostring(b.itemName)
            end
            if (a.bagID or 0)~=(b.bagID or 0) then
                return (a.bagID or 0)<(b.bagID or 0)
            end
            return (a.slotID or 0)<(b.slotID or 0)
        end)
    end
    sort(keep,true)
    sort(surplus,false)
    sort(review,false)
    return keep,surplus,review
end

-- v0.68v: The SAME strict account-wide proof is used by the MAIN
-- Storage Cleanup view. No local-only stock estimate can promote a physical
-- copy to actionable SURPLUS. WBK uses a separate baseline allocation from
-- current-character incoming BAG/PBK gear: unreceived incoming stock cannot
-- displace a holder's confirmed equipment.
function WGRStorageCleanupCheckAccessibleAccountWide(items,cooperate)
    -- Diagnostic is rebuilt by explicit account scan; never persisted.
    WGRStorageCleanupDiagnosticTrace={}
    local result={possible={},verifiedPossible={},retained={},uncertain={},checked=0,
        blocked=0,provisional=false,evidence={},trinketEvidence={},retentionDetails={}}
    local current,bank={},{}
    local liveBank,livePersonal,liveStored={},{},{}
    local eligible,protected,excluded={},{},{}
    local seen={}
    local currentName=UnitName and UnitName('player') or ''
    local character=FindCharacterByName and FindCharacterByName(currentName)
    local level=character and WGRGetCharacterLevel and tonumber(WGRGetCharacterLevel(character))
    local holderCharacter=level and level>0 and level<(tonumber(WGR_MAX_LEVEL) or 90)
    local bankOpen=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
    local pbkOpen=WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
    for _,item in ipairs(items or {}) do
        if cooperate then cooperate() end
        local loc=item.source
        local isBank=loc=='WARBAND_BANK'
        if isBank then liveBank[#liveBank+1]=item end
        if loc=='BAGS' or loc=='PERSONAL_BANK' or isBank then
            local key=loc..':'..tostring(item.bagID)..':'..tostring(item.slotID)
            local link=item.itemLink
            local mode=WGRStorageCleanupGetCopyMark and
                WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,link,item.source)
            local recommendation,status=WGRBuildLoadedItemRecommendation(link)
            local guid=WGRStorageCleanupGetPhysicalCopyGUID and
                WGRStorageCleanupGetPhysicalCopyGUID(item.bagID,item.slotID,link)
            local holder=status=='ready' and recommendation
                and recommendation.kind=='holder' and recommendation.name
                and not ((WGRGearFinderSameCharacter and
                    WGRGearFinderSameCharacter(recommendation.name,currentName))
                    or (not WGRGearFinderSameCharacter and
                    tostring(recommendation.name):lower()==tostring(currentName):lower()))
            -- Physical WBK and below-max holder BAG/PBK gear are ALREADY
            -- retained stock. They must not require a recommendation to mail
            -- to a different character to participate in stock allocation.
            local stored=isBank or holderCharacter
            if stored then
                liveStored[#liveStored+1]=item
                if not isBank then livePersonal[#livePersonal+1]=item end
            end
            -- Already-usable upgrades belong exclusively to the normal
            -- equip route, not this future-stock disposal comparison. They
            -- must neither be considered surplus nor block unrelated stored
            -- shields simply by having an immediate upgrade recommendation.
            if mode=='DISPOSE' or (status=='ready' and recommendation
                and recommendation.kind=='upgrade') then excluded[item]=true end
            if mode=='KEEP' and guid and stored and
                (item.binding=='BOE' or item.binding=='WARBAND') then
                protected[#protected+1]=item
                eligible[item]=true
            end
            local validRoute=stored and status=='ready' and recommendation
                and (recommendation.kind=='holder'
                    or recommendation.kind=='future_upgrade'
                    or recommendation.kind=='sell'
                    or recommendation.kind=='no_current_upgrade')
                or (not stored and holder)
            if not seen[key] and guid and mode~='KEEP' and mode~='DISPOSE'
                and validRoute and (item.binding=='BOE' or item.binding=='WARBAND') then
                seen[key]=true
                local copy={itemLink=link,bagID=item.bagID,slotID=item.slotID,
                    source=loc,guid=guid}
                if isBank then bank[#bank+1]=copy
                else current[#current+1]=copy end
                if stored then eligible[item]=true end
            end
        end
    end
    -- A physically enumerated WBK item in this scan is live bank evidence;
    -- some older callers do not expose the open-state helper to the mock.
    bankOpen=bankOpen or #liveBank>0
    local function append(report)
        if not report then return end
        for _,field in ipairs({'possible','verifiedPossible','retained','uncertain'}) do
            for _,item in ipairs(report[field] or {}) do
                result[field][#result[field]+1]=item
            end
        end
        for _,entry in ipairs(report.evidence or {}) do
            result.evidence[#result.evidence+1]=entry
        end
        -- v0.70w: propagate read-only trinket evidence through the same
        -- account-wide aggregation path as VERIFY SUPPLY. No allocator changes.
        for _,entry in ipairs(report.trinketEvidence or {}) do
            result.trinketEvidence[#result.trinketEvidence+1]=entry
        end
        result.checked=result.checked+(report.checked or 0)
        result.blocked=result.blocked+(report.blocked or 0)
        result.provisional=result.provisional or report.provisional
        result.error=result.error or report.error
    end
    local function check(copies,held)
        if #copies==0 then return end
        local opts={liveWarbank=bankOpen,liveWarbankItems=bankOpen and liveBank or {},
            liveEligible=eligible,liveProtected=protected,liveExcluded=excluded,
            existingHolderStock=held}
        if held then
            -- Replace this holder's actual observed BAG and opened PBK
            -- snapshots. Do not double count stale copies while another
            -- character's unobserved PBK remains subject to trust checks.
            opts.livePersonal=true
            opts.livePersonalBank=pbkOpen
            opts.liveStoredItems=liveStored
        end
        append(WGRStorageCleanupCheckHolderBoundOnDemand(copies,cooperate,opts))
    end
    if holderCharacter then
        -- ONE allocation sees live current-holder stock and live WBK together,
        -- not two competing independent choices about the same category.
        local all={}
        for _,item in ipairs(bank) do all[#all+1]=item end
        for _,item in ipairs(current) do all[#all+1]=item end
        check(all,true)
    else
        -- At max level, personal Bags/PBK are still pending normal routing.
        -- They must NOT displace a physically confirmed WBK/holder copy.
        check(bank,true)
        check(current,false)
    end
    -- v0.71e: same explicit frame-sliced account job also refreshes
    -- presentation reasons for saved holder/WBK stock. No routing or cleanup
    -- decision consumes this field.
    result.retentionDetails=WGRStorageCleanupBuildAccountRetentionDisplayDetails(cooperate)
    return result
end

-- Run the main Storage Cleanup account-wide proof cooperatively, not inside
-- inventory events or synchronous UI builds. The UI validates the input
-- physical GUID/slot snapshot again before using the result.
function WGRStorageCleanupStartAccountCheckAsync(items,onDone,onError)
    if not (coroutine and coroutine.create and coroutine.resume and
        C_Timer and C_Timer.After) then return nil,'Cooperative check unavailable' end
    local job={running=true,frames=0}
    local co=coroutine.create(function()
        local start=debugprofilestop and debugprofilestop() or nil
        local iterations=0
        local function cooperate()
            iterations=iterations+1
            if start and debugprofilestop then
                if debugprofilestop()-start<6 then return end
            elseif iterations%8~=0 then return end
            coroutine.yield()
            start=debugprofilestop and debugprofilestop() or nil
        end
        return WGRStorageCleanupCheckAccessibleAccountWide(items,cooperate)
    end)
    local function resume()
        if not job.running then return end
        job.frames=job.frames+1
        local ok,result=coroutine.resume(co)
        if not ok then
            job.running=false
            if onError then onError(tostring(result)) end
        elseif coroutine.status(co)=='dead' then
            job.running=false
            if result and not result.error then
                if onDone then onDone(result) end
            elseif onError then onError(result and result.error or 'Unavailable') end
        else C_Timer.After(0,resume) end
    end
    C_Timer.After(0,resume)
    return job
end


-- v0.72t: One explicit Storage Cleanup scan must not expose a result that
-- changes merely because the same freshly saved account state is analyzed
-- again. Compare the exact decision-bearing account report between passes.
-- This is presentation/scan sequencing only; it does not change retention,
-- routing, or disposal criteria.
function WGRStorageCleanupAccountReportSignature(report)
    if type(report)~='table' then return nil end
    local parts={}
    local function itemKey(item)
        if type(item)~='table' then return tostring(item) end
        return table.concat({tostring(item.source),tostring(item.bagID),
            tostring(item.slotID),tostring(item.itemLink),tostring(item.guid)},':')
    end
    local function add(field,list,uncertain)
        for _,entry in ipairs(list or {}) do
            local item=uncertain and entry.item or entry
            local assignment=item and item.cleanupAccountAssignment
            parts[#parts+1]=table.concat({field,itemKey(item),
                assignment and tostring(assignment.name) or '',
                assignment and tostring(assignment.level) or '',
                assignment and tostring(assignment.retentionRole or assignment.specID or '') or '',
                uncertain and tostring(entry.reason or '') or ''},'|')
        end
    end
    add('VERIFIED',report.verifiedPossible,false)
    add('RETAINED',report.retained,false)
    add('POSSIBLE',report.possible,false)
    add('UNCERTAIN',report.uncertain,true)
    parts[#parts+1]='BLOCKED|'..tostring(report.blocked or 0)
    parts[#parts+1]='PROVISIONAL|'..tostring(not not report.provisional)
    table.sort(parts)
    return table.concat(parts,'\n')
end

-- v0.72v TEST: Volatile, read-only planner trace for cross-character
-- retained-supply diagnosis. No SavedVariables, routing, or disposal changes.
WGRStorageCleanupDiagnosticTrace = {}
function WGRStorageCleanupRecordDiagnosticGroup(group,blocked,selected,assigned,trustedSelected)
    if not group or not group.incoming then return end
    local trace=WGRStorageCleanupDiagnosticTrace
    if type(trace)~='table' then return end
    local captured={}
    for _,incoming in ipairs(group.incoming) do
        local id=tonumber(tostring(incoming.itemLink or ''):match('item:(%d+)'))
        if id and not captured[id] then
            captured[id]=true
            local record={blocked=not not blocked,possible=#(group.items or {}),
                trusted=#(group.verifiedItems or {}),items={},demands={}}
            for _,d in ipairs(group.demands or {}) do
                record.demands[#record.demands+1]=tostring(d.name or '?')..'/'..
                    tostring(d.retentionRole or d.specID or '?')
            end
            local trusted={}
            for _,item in ipairs(group.verifiedItems or {}) do trusted[item]=true end
            for _,item in ipairs(group.items or {}) do
                local assignment=assigned and assigned[item]
                local origin=tostring(item.cleanupOwner or '?')..'/'..
                    tostring(item.cleanupLocation or item.source or '?')
                -- v0.72z: Capture the exact live planner inputs for read-only
                -- trinket diagnosis. Never serialize these into SavedVariables.
                local bonus=WGRStorageCleanupGetRetentionBonusProfile(item)
                local eligibleDemands={}
                for _,d in ipairs(group.demands or {}) do
                    local candidate=false
                    for _,name in ipairs(item.cleanupCandidates or {}) do
                        if name==d.name then candidate=true;break end
                    end
                    local matched=false
                    local bySpec=item.cleanupSpecCandidates and item.cleanupSpecCandidates[d.name]
                    if candidate and bySpec then
                        if d.eligibleSpecIDs then
                            for specID in pairs(d.eligibleSpecIDs) do
                                if bySpec[specID] then matched=true;break end
                            end
                        elseif d.specID then
                            matched=not not bySpec[d.specID]
                        else
                            matched=true
                        end
                    elseif candidate and not (d.specID or d.eligibleSpecIDs) then
                        matched=true
                    end
                    if matched then
                        eligibleDemands[#eligibleDemands+1]=tostring(d.name or '?')..'/'..
                            tostring(d.retentionRole or d.specID or '?')
                    end
                end
                local rawLink=tostring(item.itemLink or '')
                local linkPayload=rawLink:match('|H(item:[^|]+)|h') or
                    rawLink:match('(item:%d+[^|]*)') or rawLink
                record.items[#record.items+1]={
                    linkPayload=linkPayload,
                    uniqueKey=tostring(item.cleanupUniqueKey or '-'),
                    minLevel=tostring(item.minLevel or '?'),
                    eligibleDemands=eligibleDemands,
                    bonusKnown=not not bonus.known,
                    bonusProfile=table.concat({tostring(bonus.sockets or 0),
                        bonus.leech and 'leech' or '-',bonus.speed and 'speed' or '-',
                        bonus.avoidance and 'avoid' or '-',
                        bonus.indestructible and 'indestructible' or '-'},'/'),
                    id=tonumber(tostring(item.itemLink or ''):match('item:(%d+)')),
                    origin=origin,ilvl=tostring(item.itemLevel or '?'),
                    position=tostring(item.bagID or '?')..':'..tostring(item.slotID or '?'),
                    provisional=not not item.cleanupTrackingProvisional,
                    possibleSelected=not not (selected and selected[item]),
                    trustedSupply=not not trusted[item],
                    trustedSelected=not not (trustedSelected and trustedSelected[item]),
                    assigned=assignment and tostring(assignment.name or '?') or '-',
                    incoming=item.cleanupOwner=='Shared Warbank' or false,
                }
            end
            trace[id]=trace[id] or {}
            trace[id][#trace[id]+1]=record
        end
    end
end

function WGRStorageCleanupPrintDiagnosticItem(itemID)
    local id=tonumber(itemID)
    if not id then print('WBGR trace: Provide an item ID, e.g. /run WGRStorageCleanupPrintDiagnosticItem(280710)');return end
    local reports=WGRStorageCleanupDiagnosticTrace and WGRStorageCleanupDiagnosticTrace[id]
    if not reports or #reports==0 then
        print('WBGR trace: No live candidate for item '..id..' in the last account scan. Open bank(s), scan, then retry.')
        return
    end
    print('WBGR v0.72v read-only trace for item '..id..' ('..#reports..' planner groups)')
    for i,record in ipairs(reports) do
        print('Group '..i..': blocked='..tostring(record.blocked)..
            ' observed='..record.possible..' trusted='..record.trusted..
            ' demands='..table.concat(record.demands,','))
        for n,item in ipairs(record.items) do
            print(n..' '..(item.id==id and '*' or ' ')..' '..item.origin..
                ' slot='..item.position..' ilvl='..item.ilvl..
                ' trusted='..tostring(item.trustedSupply)..
                ' provisional='..tostring(item.provisional)..
                ' selected='..tostring(item.possibleSelected)..
                ' trustedSelected='..tostring(item.trustedSelected)..
                ' reserved='..item.assigned)
        end
    end
    print('WBGR trace end. Read-only; no saved data or marks changed.')
end

-- v0.72z TEST: Detail view of the same transient planner trace.
-- Includes all group peers because a trinket's fate depends on other item IDs.
function WGRStorageCleanupPrintDiagnosticItemDetail(itemID)
    local id=tonumber(itemID)
    if not id then print('WBGR detail: Provide an item ID');return end
    local reports=WGRStorageCleanupDiagnosticTrace and WGRStorageCleanupDiagnosticTrace[id]
    if not reports or #reports==0 then
        print('WBGR detail: No candidate for '..id..' in last account scan; open banks and rescan.')
        return
    end
    print('WBGR v0.72z read-only DETAIL for '..id..' ('..#reports..' groups)')
    for index,record in ipairs(reports) do
        print('Group '..index..': observed='..record.possible..' trusted='..record.trusted..' blocked='..tostring(record.blocked))
        for n,item in ipairs(record.items or {}) do
            print('#'..n..' '..item.origin..' '..item.position..
                ' id='..tostring(item.id or '?')..' ilvl='..item.ilvl..' req='..tostring(item.minLevel)..
                ' keep='..tostring(item.possibleSelected)..' trustedKeep='..tostring(item.trustedSelected)..
                ' to='..item.assigned)
            print('  unique='..tostring(item.uniqueKey)..' bonus='..tostring(item.bonusProfile)..
                ' bonusKnown='..tostring(item.bonusKnown)..' link='..tostring(item.linkPayload))
            print('  eligible='..table.concat(item.eligibleDemands or {},','))
        end
    end
    print('WBGR detail end. Read-only; no saved data or marks changed.')
end

-- v0.72aa TEST: Copyable read-only text view of the already captured
-- allocator diagnostic. The window does not rerun the scan or modify data.
local WGRStorageCleanupDiagnosticCopyFrame
function WGRStorageCleanupShowDiagnosticItemDetail(itemID)
    local id=tonumber(itemID)
    if not id then
        print('WBGR copy trace: Supply an item ID (for example 251791).')
        return
    end
    local reports=WGRStorageCleanupDiagnosticTrace and WGRStorageCleanupDiagnosticTrace[id]
    if not reports or #reports==0 then
        print('WBGR copy trace: No captured group for '..id..'. Open banks and Scan Inventory first.')
        return
    end
    local lines={'WBGR v0.72aa read-only DETAIL for item '..id..' ('..#reports..' groups)'}
    for index,record in ipairs(reports) do
        lines[#lines+1]='Group '..index..': observed='..record.possible..' trusted='..record.trusted..' blocked='..tostring(record.blocked)
        lines[#lines+1]='Demands: '..table.concat(record.demands or {},',')
        for n,item in ipairs(record.items or {}) do
            lines[#lines+1]='#'..n..' '..item.origin..' '..item.position..
                ' id='..tostring(item.id or '?')..' ilvl='..item.ilvl..' req='..tostring(item.minLevel)..
                ' trusted='..tostring(item.trustedSupply)..' provisional='..tostring(item.provisional)..
                ' keep='..tostring(item.possibleSelected)..' trustedKeep='..tostring(item.trustedSelected)..
                ' to='..item.assigned
            lines[#lines+1]='  unique='..tostring(item.uniqueKey)..' bonus='..tostring(item.bonusProfile)..
                ' bonusKnown='..tostring(item.bonusKnown)..' link='..tostring(item.linkPayload)
            lines[#lines+1]='  eligible='..table.concat(item.eligibleDemands or {},',')
        end
    end
    lines[#lines+1]='WBGR detail end. Read-only; no saved data or marks changed.'
    local output=table.concat(lines,'\n')

    if not WGRStorageCleanupDiagnosticCopyFrame then
        local f=CreateFrame('Frame','WGRStorageCleanupDiagnosticCopyFrame',UIParent,'BackdropTemplate')
        f:SetSize(800,520)
        f:SetPoint('CENTER')
        f:SetFrameStrata('DIALOG')
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag('LeftButton')
        f:SetScript('OnDragStart',f.StartMoving)
        f:SetScript('OnDragStop',f.StopMovingOrSizing)
        f:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',
            edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',edgeSize=24,
            insets={left=6,right=6,top=6,bottom=6}})
        local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
        title:SetPoint('TOPLEFT',20,-20)
        title:SetText('WBGR Diagnostic - copy text')
        local instructions=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        instructions:SetPoint('TOPLEFT',title,'BOTTOMLEFT',0,-9)
        instructions:SetText('Click Select All, then press Ctrl+C. Paste the text into ChatGPT. Esc to close.')
        local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT',20,-82)
        scroll:SetPoint('BOTTOMRIGHT',-38,52)
        local edit=CreateFrame('EditBox',nil,scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject('ChatFontNormal')
        edit:SetTextInsets(3,3,3,3)
        edit:SetWidth(730)
        edit:SetHeight(400)
        edit:SetScript('OnEscapePressed',function() f:Hide() end)
        edit:SetScript('OnTextChanged',function(self)
            self:SetHeight(math.max(400,math.ceil(self:GetStringHeight() or 0)+30))
        end)
        scroll:SetScrollChild(edit)
        local selectAll=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
        selectAll:SetSize(120,25)
        selectAll:SetPoint('BOTTOMLEFT',20,16)
        selectAll:SetText('Select All')
        selectAll:SetScript('OnClick',function()
            edit:SetFocus()
            edit:HighlightText(0)
        end)
        local close=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
        close:SetSize(90,25)
        close:SetPoint('BOTTOMRIGHT',-20,16)
        close:SetText('Close')
        close:SetScript('OnClick',function() f:Hide() end)
        f.editBox=edit
        f.scroll=scroll
        f:Hide()
        WGRStorageCleanupDiagnosticCopyFrame=f
    end
    local f=WGRStorageCleanupDiagnosticCopyFrame
    f.editBox:SetText(output)
    f.editBox:SetCursorPosition(0)
    f.scroll:SetVerticalScroll(0)
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText(0)
end

-- v0.72ah TEST: Copy the most recent Storage Cleanup audit invalidation.
-- Run after the panel unexpectedly falls back to Retry Scan.
local WGRStorageCleanupInvalidationCopyFrame
function WGRStorageCleanupShowLastInvalidationDiagnostic()
    local output=_G.WGRStorageCleanupLastInvalidationDiagnosticText or
        'WBGR v0.72ar Storage Cleanup invalidation diagnostic\nNo invalidation has been captured in this session.'
    if not WGRStorageCleanupInvalidationCopyFrame then
        local f=CreateFrame('Frame','WGRStorageCleanupInvalidationCopyFrame',UIParent,'BackdropTemplate')
        f:SetSize(860,560);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true)
        f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag('LeftButton')
        f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
        f:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',
            edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',edgeSize=24,
            insets={left=6,right=6,top=6,bottom=6}})
        local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
        title:SetPoint('TOPLEFT',20,-20);title:SetText('WBGR Storage Cleanup - last invalidation')
        local instructions=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        instructions:SetPoint('TOPLEFT',title,'BOTTOMLEFT',0,-9)
        instructions:SetText('Click Select All, press Ctrl+C, then paste into ChatGPT. Esc closes this window.')
        local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT',20,-82);scroll:SetPoint('BOTTOMRIGHT',-38,52)
        local edit=CreateFrame('EditBox',nil,scroll)
        edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject('ChatFontNormal')
        edit:SetTextInsets(3,3,3,3);edit:SetWidth(790);edit:SetHeight(420)
        edit:SetScript('OnEscapePressed',function() f:Hide() end)
        edit:SetScript('OnTextChanged',function(self)
            self:SetHeight(math.max(420,math.ceil(self:GetStringHeight() or 0)+30))
        end)
        scroll:SetScrollChild(edit)
        local selectAll=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
        selectAll:SetSize(120,25);selectAll:SetPoint('BOTTOMLEFT',20,16);selectAll:SetText('Select All')
        selectAll:SetScript('OnClick',function() edit:SetFocus();edit:HighlightText(0) end)
        local close=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
        close:SetSize(90,25);close:SetPoint('BOTTOMRIGHT',-20,16);close:SetText('Close')
        close:SetScript('OnClick',function() f:Hide() end)
        f.editBox=edit;f.scroll=scroll;f:Hide();WGRStorageCleanupInvalidationCopyFrame=f
    end
    local f=WGRStorageCleanupInvalidationCopyFrame
    f.editBox:SetText(output);f.editBox:SetCursorPosition(0);f.scroll:SetVerticalScroll(0)
    f:Show();f.editBox:SetFocus();f.editBox:HighlightText(0)
end

-- v0.68i: Manual To Do checks can cost hundreds of milliseconds even after
-- category pruning. Cooperative yielding moves the SAME read-only decision
-- path across frames. This is not a background loot/bank/vendor scan and is
-- not a DISPOSE decision. No SavedVariables schema change.
-- A single caller (To Do) owns each job; an in-progress worker is always
-- resumed to completion so routing-evaluation caches remain paired.
function WGRStorageCleanupStartHolderBoundCheckAsync(source,onDone,onError)
    if not (coroutine and coroutine.create and coroutine.resume and
        C_Timer and C_Timer.After) then
        return nil,'Frame-sliced surplus checking unavailable'
    end
    local clock=debugprofilestop
    local budget=6 -- milliseconds of Lua time between cooperative yields
    local job={running=true,frames=0,maxSliceMs=0,activeMs=0,startedAt=clock and clock() or nil}
    local co
    local sliceStart=nil
    local yields=0
    local untimedChecks=0
    local function cooperate()
        -- debugprofilestop is normally available in Retail. The fallback
        -- still bounds loop work if a client/tooling environment hides it.
        if clock and sliceStart then
            if clock()-sliceStart<budget then return end
        else
            untimedChecks=untimedChecks+1
            if untimedChecks%8~=0 then return end
        end
        yields=yields+1
        coroutine.yield()
    end
    co=coroutine.create(function()
        local candidates,outgoing,scanError=WGRGearFinderGetHolderBoundCleanupCandidates(source,cooperate)
        if scanError then return nil,outgoing,scanError,candidates end
        cooperate()
        local report=WGRStorageCleanupCheckHolderBoundOnDemand(candidates,cooperate)
        return report,outgoing,nil,candidates
    end)
    local function runSlice()
        if not job.running then return end
        sliceStart=clock and clock() or nil
        job.frames=job.frames+1
        local ok,report,outgoing,err,candidates=coroutine.resume(co)
        local elapsed=sliceStart and clock and math.max(0,clock()-sliceStart) or 0
        job.activeMs=job.activeMs+elapsed
        if elapsed>job.maxSliceMs then job.maxSliceMs=elapsed end
        if not ok then
            job.running=false
            if onError then onError('Surplus check failed: '..tostring(report)) end
            return
        end
        if coroutine.status(co)=='dead' then
            job.running=false
            job.yields=yields
            if err or not report or report.error then
                if onError then onError(err or (report and report.error) or 'Unable to check surplus') end
                return
            end
            if onDone then onDone(report,outgoing,candidates,job) end
        else
            C_Timer.After(0,runSlice)
        end
    end
    -- Never run the expensive work inside the button's OnClick handler.
    C_Timer.After(0,runSlice)
    return job
end

-- v0.68a: positive match between a FRESH account-wide *unselected*
-- observation and the live local SURPLUS decision. This pure check never
-- marks gear KEEP/SURPLUS, never moves anything and must not be used to sell.
-- Caller must check that the manual preview revision is current and that
-- normal Cleanup is not paused/frozen before offering movement controls.
function WGRStorageCleanupCrossCheckAccountSurplus(preview,currentName,surplus,keep,review)
    local candidates={}
    for _,item in ipairs(preview and preview.crosscheckCandidates or {}) do
        local location=item.location
        if location=='WBK' or (item.owner==currentName
            and (location=='BAG' or location=='PBK')) then
            local key=tostring(item.owner)..'|'..tostring(location)..'|'..
                tostring(item.bagID)..'|'..tostring(item.slotID)..'|'..tostring(item.itemLink)
            -- Multiple conflicting records at the same physical position
            -- are ambiguous and must not become a cross-checked move.
            if candidates[key]~=nil then candidates[key]=false else candidates[key]=item end
        end
    end
    local function physical(item)
        if type(item)~='table' then return nil end
        local location=({BAGS='BAG',PERSONAL_BANK='PBK',WARBAND_BANK='WBK'})[item.source]
        if not location then return nil end
        local owner=location=='WBK' and 'Shared Warbank' or currentName
        return tostring(owner)..'|'..location..'|'..
            tostring(item.bagID)..'|'..tostring(item.slotID)..'|'..tostring(item.itemLink)
    end
    local protected={}
    for _,list in ipairs({keep or {},review or {}}) do
        for _,item in ipairs(list) do
            local key=physical(item)
            if key then protected[key]=true end
        end
    end
    local matched,seen={},{}
    for _,item in ipairs(surplus or {}) do
        local key=physical(item)
        local saved=key and candidates[key]
        if saved and not seen[key] and not protected[key]
            and (tonumber(saved.itemLevel) or 0)==(tonumber(item.itemLevel) or -1)
            and (item.binding=='BOE' or item.binding=='WARBAND') then
            matched[#matched+1]=item
            seen[key]=true
        end
    end
    return matched
end

-- v0.68b: pure, read-only SOURCE + CATEGORY staging selection.  A source
-- represents both the physical storage location and its holder (the active
-- character for PBK; account-global for WBK).  Never widen a user-selected
-- batch to other holders, categories or sources.  Bags already contain the
-- item and are not a staging destination.  Reuse existing live cross-check;
-- neither this filter nor its sort can promote KEEP/REVIEW to SURPLUS.
function WGRStorageCleanupFilterCrossCheckedForStaging(candidates,source,category)
    if source~='PERSONAL_BANK' and source~='WARBAND_BANK' then return {} end
    if not category or category=='NONE' then return {} end
    local selected,seen={},{}
    for _,item in ipairs(candidates or {}) do
        local label=item.cleanupGroupLabel or item.category or 'Other / Unclassified'
        if item.source==source and label==category and item.bagID~=nil
            and item.slotID~=nil and item.itemLink and
            (item.binding=='WARBAND' or item.binding=='BOE') then
            local key=tostring(item.source)..'|'..tostring(item.bagID)..'|'..
                tostring(item.slotID)..'|'..tostring(item.itemLink)
            if not seen[key] then selected[#selected+1]=item;seen[key]=true end
        end
    end
    -- Show lower-ilvl surplus first for easier manual review.  This order is
    -- presentation only; MoveVerified uses actual source slot identities.
    table.sort(selected,function(a,b)
        if (a.itemLevel or 0)~=(b.itemLevel or 0) then
            return (a.itemLevel or 0)<(b.itemLevel or 0)
        end
        local na,nb=tostring(a.itemName or a.itemLink),tostring(b.itemName or b.itemLink)
        if na~=nb then return na<nb end
        if tostring(a.itemLink)~=tostring(b.itemLink) then
            return tostring(a.itemLink)<tostring(b.itemLink)
        end
        if (a.bagID or 0)~=(b.bagID or 0) then return (a.bagID or 0)<(b.bagID or 0) end
        return (a.slotID or 0)<(b.slotID or 0)
    end)
    return selected
end

-- v0.68c: freeze the ORIGINAL account-checked physical-copy identities for
-- the explicitly chosen holder/source + equipment category. This is not a
-- new classification or a replanning pass. After each verified transfer,
-- only still-pending originals can appear in the NEXT <=20-item list.
function WGRStorageCleanupMakeFrozenCrosscheck(candidates,source,category)
    local chosen=WGRStorageCleanupFilterCrossCheckedForStaging(candidates,source,category)
    if #chosen==0 then return nil end
    local approved={}
    for _,item in ipairs(chosen) do
        local key=tostring(item.source)..':'..tostring(item.bagID)..':'..
            tostring(item.slotID)..':'..tostring(item.itemLink)
        approved[key]={itemLevel=item.itemLevel,itemLink=item.itemLink,
            binding=item.binding}
    end
    return {source=source,category=category,approved=approved,count=#chosen}
end

-- No new physical copies or unapproved categories may enter a frozen
-- account-checked batch, even if a caller uses the generic surplus mover.
function WGRStorageCleanupFrozenCrosscheckAllows(session,records,destination)
    local frozen=session and session.crosscheck
    if not frozen then return false end
    if destination~='BAGS' or session.unverified or not records or #records==0 then
        return false
    end
    local pending={}
    for _,item in ipairs(WGRStorageCleanupFrozenCrosscheckPending(session)) do
        local key=tostring(item.source)..':'..tostring(item.bagID)..':'..
            tostring(item.slotID)..':'..tostring(item.itemLink)
        pending[key]=item
    end
    local seen={}
    for _,item in ipairs(records) do
        local key=tostring(item.source)..':'..tostring(item.bagID)..':'..
            tostring(item.slotID)..':'..tostring(item.itemLink)
        local allowed=pending[key]
        if not allowed or seen[key] or allowed.itemLevel~=item.itemLevel
            or allowed.binding~=item.binding then return false end
        seen[key]=true
    end
    return true
end

function WGRStorageCleanupFrozenCrosscheckPending(session)
    local frozen=session and session.crosscheck
    if not frozen then return {} end
    local pending={}
    for _,item in ipairs(session.surplus or {}) do
        local key=tostring(item.source)..':'..tostring(item.bagID)..':'..
            tostring(item.slotID)..':'..tostring(item.itemLink)
        local original=frozen.approved[key]
        if original and not (session.moved and session.moved[key])
            and item.itemLink==original.itemLink
            and item.itemLevel==original.itemLevel
            and item.binding==original.binding then
            pending[#pending+1]=item
        end
    end
    return WGRStorageCleanupFilterCrossCheckedForStaging(
        pending,frozen.source,frozen.category)
end

-- v0.68d: verify ownership of ACTUALLY occupied frozen slots. The original
-- SURPLUS identity is still keyed to its old source position, but a successfully
-- moved original is NOT a live occupant of that position. Returned copies may
-- legitimately reuse any vacated SURPLUS slot, including another moved item's
-- original position. Export this pure verifier for mocked recovery regressions.
function WGRStorageCleanupVerifyFrozenSourceSlots(session,physicalKey,sameSourceItem)
    if not session or not physicalKey or not sameSourceItem then
        return false,'missing frozen source verification state'
    end
    local originalKeys,occupiedSlots={},{}
    local function SlotKey(item)
        if not item or item.source==nil or item.bagID==nil or item.slotID==nil then return nil end
        return tostring(item.source)..':'..tostring(item.bagID)..':'..tostring(item.slotID)
    end
    local function Claim(item,errorMessage)
        local key=physicalKey(item)
        local slot=SlotKey(item)
        if not key or not slot or occupiedSlots[slot] or not sameSourceItem(item) then
            return false,errorMessage
        end
        occupiedSlots[slot]=true
        return true
    end
    for _,item in ipairs(session.keep or {}) do
        local ok,reason=Claim(item,'an original KEEP item changed or its bank is closed')
        if not ok then return false,reason end
    end
    for _,original in ipairs(session.surplus or {}) do
        local origin=physicalKey(original)
        if not origin or originalKeys[origin] then
            return false,'ambiguous original item location'
        end
        originalKeys[origin]=true
        local staged=session.staged and session.staged[origin]
        if staged then
            local ok,reason=Claim(staged,
                'a staged item moved or conflicts with protected/pending gear; inspect the batch')
            if not ok then return false,reason end
        elseif not (session.moved and session.moved[origin]) then
            local ok,reason=Claim(original,'a pending SURPLUS item moved or its bank is closed')
            if not ok then return false,reason end
        end
        -- An item already moved and no longer staged has NO physical source
        -- claim here. No other original/KEEP classification changes.
    end
    return true
end


-- v0.70p: Read-only explanation for a possible-but-unverified new drop.
-- Uses evidence captured during the existing cooperative account check; never
-- recomputes stock or changes the allocation, move or disposal permissions.
local function WGRStorageCleanupDrawSupplyEvidence(content,rows,y,audit)
    for _,report in ipairs(audit and audit.evidence or {}) do
        local lines={
            'VERIFY SUPPLY: '..tostring(report.itemLink)..' | '..tostring(report.category),
            'Possible: '..tostring(report.possible)..' | trusted-only: '..tostring(report.verified),
            'Supply considered: '..tostring(report.possibleCount)..' copies (includes live incoming); trusted: '..tostring(report.verifiedCount),
        }
        for _,stock in ipairs(report.stock or {}) do
            lines[#lines+1]=tostring(stock.itemLink)..' ilvl '..tostring(stock.itemLevel or '?')..
                ' | '..tostring(stock.owner or '?')..' / '..tostring(stock.location or '?')..
                ' | '..tostring(stock.trust)
        end
        for _,line in ipairs(lines) do
            local holder=CreateFrame('Frame',nil,content)
            holder:SetSize(790,19);holder:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local label=holder:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            label:SetPoint('LEFT',holder,'LEFT',0,0);label:SetWidth(770)
            label:SetJustifyH('LEFT');label:SetText(line)
            rows[#rows+1]=holder
            y=y+19
        end
        y=y+8
    end
    -- v0.70v: diagnostic only. None of these facts can classify or mark a
    -- trinket CLEAN UP. Counts describe the allocator's future-use selections,
    -- not a guaranteed equippable pair or a disposal proof.
    for _,report in ipairs(audit and audit.trinketEvidence or {}) do
        local lines={
            'TRINKET REVIEW: '..tostring(report.itemLink)..' | ilvl '..tostring(report.itemLevel),
            'Allocation: possible '..(report.possibleSelected and 'SELECTED' or 'NOT SELECTED')..
                ' | trusted '..(report.trustedSelected and 'SELECTED' or 'NOT SELECTED'),
            'Supply: '..tostring(report.possibleCopies)..' possible / '..
                tostring(report.trustedCopies)..' trusted (including incoming)',
            'Unique-Equipped key: '..(report.uniqueKnown and
                tostring(report.uniqueKey or 'no restriction detected') or 'UNKNOWN'),
            'Removal simulation: '..(report.removalStable and 'PASS' or 'NOT PROVEN')..
                ' | '..tostring(report.removalDetail or 'not evaluated'),
            'Trusted supply after removal: '..tostring(report.removalTrustedCopies or '?')..' copies',
            'Cleanup proof: '..(report.cleanupProven and
                'PASS - verified trinket surplus; eligible retained pairs stay complete' or
                'NOT PROVEN - remains NEEDS ATTENTION'),
        }
        for _,d in ipairs(report.roles or {}) do
            lines[#lines+1]=tostring(d.name)..' / '..tostring(d.role)..': assigned '..
                tostring(d.allocated)..' / '..tostring(d.target)..
                ', trusted '..tostring(d.trusted)..' / '..tostring(d.target)..
                ', incoming eligible '..(d.eligible and 'yes' or 'no')
            lines[#lines+1]='  Trusted pair: '..tostring(d.pairVerdict or 'NOT EVALUATED')
            for slot,copy in ipairs(d.trustedPair or {}) do
                lines[#lines+1]='    '..tostring(slot)..'. '..tostring(copy.link or '?')..
                    ' ilvl '..tostring(copy.level or '?')..
                    ' | Unique key '..tostring(copy.uniqueKey or 'none recorded')
            end
        end
        lines[#lines+1]=report.cleanupProven and
            'ACTIONABLE PROOF: this exact trusted copy may enter CLEAN UP; normal verified staging/disposal protections still apply.' or
            'CONSERVATIVE: no trinket CLEAN UP without trusted removal stability and complete conflict-free eligible role pairs.'
        for _,line in ipairs(lines) do
            local holder=CreateFrame('Frame',nil,content)
            holder:SetSize(790,19);holder:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local label=holder:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            label:SetPoint('LEFT',holder,'LEFT',0,0);label:SetWidth(770)
            label:SetJustifyH('LEFT');label:SetText(line)
            rows[#rows+1]=holder
            y=y+19
        end
        y=y+8
    end
    return y
end

local function WGRCreateStorageCleanupPanel(frame,page)
    local panel=CreateFrame("Frame",nil,page)
    panel:SetPoint("TOPLEFT",page,"TOPLEFT",0,-76)
    panel:SetPoint("BOTTOMRIGHT",page,"BOTTOMRIGHT",0,0)
    local refresh=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
    refresh:SetSize(150,24);refresh:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-4,2)
    refresh:SetText("Scan Inventory")
    refresh.WGRHasManualCleanupScan=false
    local newAudit -- Created below; visibility is controlled by the batch state.
    local settings=WGRStorageCleanupGetSettings()
    -- v0.71c: The scan instruction is the primary enabled-state action cue.
    -- Give it heading-level prominence and visually pair it with Scan Inventory.
    local instructions=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    instructions:SetPoint("TOPLEFT",panel,"TOPLEFT",145,0)
    instructions:SetPoint("RIGHT",refresh,"LEFT",-10,0)
    instructions:SetHeight(24)
    instructions:SetJustifyH("CENTER")
    instructions:SetText("Start by scanning this character's inventory.")
    panel.WGRCleanupInstructions=instructions

    local master=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
    master:SetPoint("TOPLEFT",panel,"TOPLEFT",-3,-49)
    master:SetChecked(settings.enabled)
    local masterLabel=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    masterLabel:SetPoint("LEFT",master,"RIGHT",0,0)
    masterLabel:SetText("Enable Storage Cleanup")
    local betaLabel=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    betaLabel:SetPoint("LEFT",masterLabel,"RIGHT",6,0)
    betaLabel:SetText("(Beta: Review items before disposal)")
    betaLabel:SetTextColor(1.00,0.42,0.18)
    local itemDetailNote=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    itemDetailNote:SetPoint("TOPLEFT",masterLabel,"BOTTOMLEFT",0,-3)
    itemDetailNote:SetWidth(700)
    itemDetailNote:SetJustifyH("LEFT")
    itemDetailNote:SetText("Also enables expandable tracked-item details in Gather Gear and Gear Search.")
    itemDetailNote:SetTextColor(0.72,0.72,0.72)
    panel.WGRCleanupItemDetailNote=itemDetailNote
    local summary=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT",panel,"TOPLEFT",0,-184)
    summary:SetPoint("RIGHT",panel,"RIGHT",-3,0)
    summary:SetJustifyH("LEFT")
    local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",summary,"BOTTOMLEFT",0,-10)
    scroll:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-26,0)
    local content=CreateFrame("Frame",nil,scroll)
    content:SetWidth(math.max(1,scroll:GetWidth()));content:SetHeight(1);scroll:SetScrollChild(content)
    -- Keep shaded rows aligned to the actual scroll viewport, not a stale
    -- 840px fixed width when the main WBGR window is wider.
    scroll:HookScript('OnSizeChanged',function(self,width)
        content:SetWidth(math.max(1,width))
    end)
    local rows={}
    -- Session-only presentation state. Collapsing results never changes KEEP/SURPLUS.
    local collapsedSlots={}
    local collapsedGroups={KEEP=true,SURPLUS=false,REVIEW=false}
    -- Browsing saved inventories does not interact with live Cleanup decisions.
    local showAccountPreview=false
    -- Default Storage Cleanup to the guided user workflow. Cleanup choices
    -- and storage-movement actions stay visible; Advanced exposes manual
    -- overrides, account preview, disposal-mail tools and diagnostics.
    content.WGRShowAdvancedCleanup=false
    content.WGRShowTroubleshooting=false
    -- Guided mode intentionally starts empty. A local-only planner pass is
    -- useful for diagnostics, but presenting it as NEEDS ATTENTION before the
    -- user asks for the authoritative account check is confusing. Advanced
    -- may still expose that local preview explicitly.
    -- Never default staging to a different holder's/shared-bank gear.
    -- Re-select both the source (which names its owner) and category on each
    -- explicit account preview refresh.
    local crosscheckSelection={source='NONE',category='NONE'}
    local transferSession -- forward declaration: preview UI and mover share this frozen session
    -- v0.67z: explanation rows are lazy presentation of the cached report;
    -- they must never invoke the planner again on expand/collapse.
    local showIncomingDetails=false
    local expandedIncomingItems={}
    -- The read-only account report is expensive (many roster/spec/gear checks).
    -- Keep it STATIC while expanded. Live account-wide recalculation cost
    -- ~169 ms on a 47-character roster: do NOT rerun on bag events. Re-open,
    -- explicit Scan Inventory, or Refresh Preview to calculate again.
    local accountPreviewCache=nil
    local accountPreviewRevision=-1
    local lastLocalAuditMs=0
    local lastAccountPreviewMs=0
    local lastAutomaticAudit='Not run'
    -- v0.72am: manual cleanup scans remain visible until the user explicitly
    -- rescans. Passive inventory events may request a refresh but cannot erase
    -- the completed result.
    local cleanupNeedsManualRescan=false
    local cleanupNeedsManualRescanReason=nil
    local locationOnlySkips=0
    local showSavedInventories=false
    -- Compact account-wide browser for user-authored GUID overrides.
    local showManualOverrides=false
    local manualOverrideFilter='ALL'
    local expandedSavedOwners={}
    local expandedSavedCategories={}
    local Render
    local advancedToggle=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
    advancedToggle:SetSize(124,22)
    advancedToggle:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-4,-29)
    advancedToggle:SetText("Advanced")
    content.WGRAdvancedToggle=advancedToggle
    advancedToggle:SetScript("OnClick",function()
        content.WGRShowAdvancedCleanup=not content.WGRShowAdvancedCleanup
        if Render then Render(true) end
    end)
    local function Changed() if Render then Render() end end
    -- Explicit overrides alter the available stock.  Unlike expanding a UI
    -- section, they MUST rerun the allocator, not redraw a frozen KEEP list.
    local function FlagCleanupNeedsManualRescan(reason)
        cleanupNeedsManualRescan=true
        cleanupNeedsManualRescanReason=reason or 'Inventory or override state changed'
        lastAutomaticAudit='Manual rescan recommended'
        if refresh and refresh.SetText then refresh:SetText('Rescan Inventory') end
        if summary and summary.GetText and summary.SetText then
            local current=summary:GetText() or ''
            if not current:find('Rescan Inventory when ready',1,true) then
                summary:SetText(current..'\n|cffffcc00Inventory changed — Rescan Inventory when ready.|r')
            end
        end
    end
    local function OverrideChanged(recheckAfterClear,button)
        -- KEEP/DISPOSE are persistent user overrides. Clearing one returns the
        -- copy to AUTO immediately for normal Recommendations, but Storage
        -- Cleanup does NOT launch a full account scan per click. This keeps
        -- bulk/manual Undispose/Unkeep practical; the user can run one Rescan
        -- after finishing all override changes.
        --
        -- v0.72az: every override path must also refresh the visible Cleanup
        -- row. The per-row button used to update itself directly, while the
        -- icon right-click context menu called this helper without a button
        -- reference and therefore left the old Undispose/Mark DISPOSE state
        -- on screen until some unrelated redraw (for example a tab switch).
        if recheckAfterClear then
            FlagCleanupNeedsManualRescan('Manual KEEP/DISPOSE override cleared')
        end
        if Render then Render(true) end
    end

    local function OverrideContextMenu(button,bagID,slotID,link,source,onChanged)
        if not (MenuUtil and MenuUtil.CreateContextMenu and settings.enabled
            and type(bagID)=='number' and type(slotID)=='number') then return end
        MenuUtil.CreateContextMenu(button,function(_,root)
            root:CreateTitle(link or 'Current physical item')
            local status=WGRStorageCleanupGetCopyMark and
                WGRStorageCleanupGetCopyMark(bagID,slotID,link,source)
            local function Action(label,mode,clearExpected)
                root:CreateButton(label,function()
                    local ok,reason
                    if clearExpected then
                        ok,reason=WGRStorageCleanupClearCopyOverride(bagID,slotID,clearExpected,source)
                    else
                        ok,reason=WGRStorageCleanupSetCopyMark(bagID,slotID,mode,'MANUAL',nil,nil,source)
                    end
                    if not ok then
                        print('|cffffaa00WBGR:|r Override unchanged: '..tostring(reason))
                    end
                    if ok and onChanged then onChanged(clearExpected~=nil) end
                end)
            end
            if status=='KEEP' then Action('Unkeep - return to automatic',nil,'KEEP')
            else Action('Mark KEEP - protect this copy','KEEP') end
            if status=='DISPOSE' then Action('Undispose - restore routing',nil,'DISPOSE')
            else Action('Mark DISPOSE - suspend holder route','DISPOSE') end
            -- Reuse the established global Ignore / Unignore behavior.
            if WGRItemIsIgnored and WGRItemIsIgnored(link) then
                root:CreateButton('Unignore item',function()
                    if WGRShowUnignoreItemConfirmation then
                        WGRShowUnignoreItemConfirmation(link)
                    end
                end)
            else
                root:CreateButton('Ignore item in WBGR',function()
                    if WGRSetItemIgnored then
                        WGRSetItemIgnored(link,true,tostring(UnitName('player'))..' - Storage Cleanup')
                    end
                end)
            end
        end)
    end

    local settingsNote=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    settingsNote:SetPoint("TOPLEFT",panel,"TOPLEFT",2,-89)
    settingsNote:SetText("Cleanup Options")
    content.WGRSettingsNote=settingsNote

    -- Destination lists are independent of routing participation. Both
    -- Ignored and Removed alts are allowed for manual surplus handling;
    -- selecting either never restores it to the active routing roster.
    local function Recipients()
        local values={{'CURRENT','Current character'}}
        local seen={}
        for _,name in ipairs(GetRoutingPriority and GetRoutingPriority() or {}) do
            local key=string.lower(tostring(name))
            if not seen[key] then
                local ignored=WGRIsCharacterIgnored and WGRIsCharacterIgnored(name)
                local removed=WGRIsCharacterRemoved and WGRIsCharacterRemoved(name)
                local suffix=removed and ' (Removed)' or (ignored and ' (Ignored)' or '')
                values[#values+1]={name,name..suffix}
                seen[key]=true
            end
        end
        if WGRGetRemovedCharacters then
            for _,record in ipairs(WGRGetRemovedCharacters()) do
                local name=record and record.name
                local key=name and string.lower(tostring(name))
                if key and not seen[key] then
                    values[#values+1]={name,name..' (Removed)'}
                    seen[key]=true
                end
            end
        end
        return values
    end
    -- Group widths account for the extra chrome on UIDropDownMenuTemplate.
    -- 160 UI units between controls leaves a visible gap, while the two
    -- binding-type groups remain well separated even after UI scaling.
    local wrDrop,wrLabel=WGRGearSearchMakeDropdown(panel,'Route Warbound Surplus To:',4,220,
        Recipients,'warboundRecipient',settings,Changed)
    wrLabel:ClearAllPoints();wrLabel:SetPoint('TOPLEFT',panel,'TOPLEFT',4,-105)
    local brDrop,brLabel=WGRGearSearchMakeDropdown(panel,'Route BoE Surplus To:',424,220,
        Recipients,'boeRecipient',settings,Changed)
    brLabel:ClearAllPoints();brLabel:SetPoint('TOPLEFT',panel,'TOPLEFT',424,-105)
    local function RefreshAfterCleanupToggle()
        WGRStorageCleanupInvalidateObservedCache()
        if settings.enabled and WGRStorageCleanupScheduleObservedInventory then
            WGRStorageCleanupScheduleObservedInventory(0.75)
        end
        if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
        master:SetChecked(settings.enabled)
        Changed()
    end

    local function ApplyCleanupResumeChoice(mode,recoveryOnly)
        local migrationPending=WGRStorageCleanupNeedsResumePolicyMigration and
            WGRStorageCleanupNeedsResumePolicyMigration()
        if not recoveryOnly then
            if WGRStorageCleanupSetEnabled then
                WGRStorageCleanupSetEnabled(true,mode)
            else settings.enabled=true end
        end
        if migrationPending and WGRStorageCleanupResolveOldToggleVerification then
            local promoted=WGRStorageCleanupResolveOldToggleVerification(mode=='USE_EXISTING')
            if mode=='USE_EXISTING' and promoted and promoted>0 then
                print('|cff33ff99WBGR:|r Restored '..promoted..' previously verified storage location(s). Refresh any characters that changed before acting on CLEAN UP recommendations.')
            end
        end
        RefreshAfterCleanupToggle()
    end

    local function ShowCleanupResumePrompt(recoveryOnly)
        if not (StaticPopupDialogs and StaticPopup_Show) then
            -- Fail closed if Blizzard's confirmation UI is unavailable.
            if not recoveryOnly and WGRStorageCleanupSetEnabled then
                WGRStorageCleanupSetEnabled(true,'CHECK_AGAIN')
                RefreshAfterCleanupToggle()
            end
            return
        end
        StaticPopupDialogs.WGR_STORAGE_CLEANUP_RESUME_CHOICE =
            StaticPopupDialogs.WGR_STORAGE_CLEANUP_RESUME_CHOICE or {
            text='Storage Cleanup was previously turned off.\n\nWhile it was off, WBGR may have missed changes to stored gear. How would you like to continue?\n\nUSE EXISTING DATA\nKeep using your previous Storage Cleanup data. Choose this if nothing changed, or if you know which characters changed and will refresh them yourself before acting on CLEAN UP recommendations.\n\nCHECK EVERYTHING AGAIN\nHave WBGR treat your previous storage data as needing another check. Choose this if you\'re not sure what changed.',
            button1='Use Existing Data',
            button2='Check Everything Again',
            button3=CANCEL,
            OnAccept=function(self,data)
                if data and data.useExisting then data.useExisting() end
            end,
            OnCancel=function(self,data)
                if data and data.checkAgain then data.checkAgain() end
            end,
            OnAlt=function(self,data)
                if data and data.cancel then data.cancel() end
            end,
            -- Button 2 is the middle action; Escape hides the popup without
            -- invoking it. The master toggle is still OFF until an explicit
            -- choice is made, so Escape remains equivalent to Cancel.
            noCancelOnEscape=true,
            timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        }
        local data={
            useExisting=function() ApplyCleanupResumeChoice('USE_EXISTING',recoveryOnly) end,
            checkAgain=function() ApplyCleanupResumeChoice('CHECK_AGAIN',recoveryOnly) end,
            cancel=function()
                if not recoveryOnly then master:SetChecked(false) end
            end,
        }
        StaticPopup_Show('WGR_STORAGE_CLEANUP_RESUME_CHOICE',nil,nil,data)
    end

    master:SetScript("OnClick",function(self)
        local requested=self:GetChecked() and true or false
        if not requested then
            if WGRStorageCleanupSetEnabled then WGRStorageCleanupSetEnabled(false)
            else settings.enabled=false end
            RefreshAfterCleanupToggle()
            return
        end
        -- Do not partially enable Cleanup before the user chooses how to treat
        -- data from the OFF interval. Cancel leaves the feature OFF unchanged.
        self:SetChecked(false)
        ShowCleanupResumePrompt(false)
    end)

    local function ClearRows()
        for _,r in ipairs(rows) do r:Hide();r:SetParent(nil) end
        rows={}
    end
    local sectionDisplay={KEEP='KEEP',SURPLUS='CLEAN UP',REVIEW='NEEDS ATTENTION'}
    local sectionHelp={
        KEEP='Reserved account-wide for your characters. The assigned character explains why it is kept; it is not a mail instruction.',
        SURPLUS='Verified excess gear. Mark DISPOSE to override normal routing.',
        REVIEW='WBGR is not confident enough to dispose of these items. Review the reason shown.',
    }
    local function AddSection(label,count,r,g,b,y,slotLabels)
        local holder=CreateFrame("Button",nil,content)
        holder:SetSize(560,25)
        holder:SetPoint("TOPLEFT",content,"TOPLEFT",0,-y)
        local text=holder:CreateFontString(nil,"OVERLAY","GameFontNormal")
        text:SetPoint("LEFT",holder,"LEFT",1,0)
        text:SetText((collapsedGroups[label] and '[+] ' or '[-] ')..(sectionDisplay[label] or label)..' ('..count..')')
        text:SetTextColor(r,g,b)
        holder:SetScript("OnClick",function()
            collapsedGroups[label]=not collapsedGroups[label]
            Render(true)
        end)
        rows[#rows+1]=holder
        for _,control in ipairs({{'Expand All',false,565},{'Collapse All',true,684}}) do
            local button=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
            button:SetSize(112,21)
            button:SetPoint('TOPLEFT',content,'TOPLEFT',control[3],-y-2)
            button:SetText(control[1])
            button:SetScript('OnClick',function()
                collapsedGroups[label]=false
                for _,slotLabel in ipairs(slotLabels) do
                    collapsedSlots[label..':'..slotLabel]=control[2]
                    if label=='SURPLUS' then collapsedSlots['STAGED:'..slotLabel]=control[2] end
                end
                Render(true)
            end)
            if count==0 then button:Disable() end
            rows[#rows+1]=button
        end
        return y+27,not collapsedGroups[label]
    end
    content.WGRAddSectionHelp=function(label,y)
        local holder=CreateFrame('Frame',nil,content)
        holder:SetSize(790,20);holder:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y)
        local text=holder:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        text:SetAllPoints();text:SetJustifyH('LEFT')
        text:SetText(sectionHelp[label] or '')
        text:SetTextColor(0.72,0.72,0.72)
        rows[#rows+1]=holder
        return y+22
    end
    -- Snapshot browser: historical observations only. No Get/Move controls here.
    local function AccountRetentionPreview(y)
        -- Lazy evaluation: opening this optional read-only report performs
        -- the multi-holder comparison; normal Cleanup rendering stays fast.
        local btn=CreateFrame('Button',nil,content)
        btn:SetSize(790,23);btn:SetPoint('TOPLEFT',content,'TOPLEFT',0,-y)
        local text=btn:CreateFontString(nil,'OVERLAY','GameFontHighlight')
        text:SetPoint('LEFT',btn,'LEFT',1,0)
        text:SetText((showAccountPreview and '[-] ' or '[+] ')
            ..'Account-wide Retention Preview')
        btn:SetScript('OnClick',function()
            showAccountPreview=not showAccountPreview
            if showAccountPreview and not transferSession then accountPreviewCache=nil end
            Render(true)
        end)
        rows[#rows+1]=btn
        y=y+25
        if not showAccountPreview or not WGRStorageCleanupComputeAccountPreview then return y+4 end
        local revision=WGRStorageCleanupGetInventoryRevision and WGRStorageCleanupGetInventoryRevision() or 0
        -- A displayed report is frozen until deliberate refresh. These
        -- numbers are read-only; showing a stale label is safer than hitching
        -- after every item drag, and no stale result authorizes disposal.
        if not accountPreviewCache then
            local started=debugprofilestop and debugprofilestop() or nil
            accountPreviewCache=WGRStorageCleanupComputeAccountPreview()
            if started then lastAccountPreviewMs=debugprofilestop()-started end
            accountPreviewRevision=WGRStorageCleanupGetInventoryRevision
                and WGRStorageCleanupGetInventoryRevision() or revision
        end
        local stale=accountPreviewRevision~=revision
        local refreshPreview=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
        refreshPreview:SetSize(150,20)
        refreshPreview:SetPoint('TOPLEFT',content,'TOPLEFT',630,-y+2)
        refreshPreview:SetText('Refresh Preview')
        if transferSession then
            refreshPreview:Disable()
            refreshPreview:SetText('Finish Batch First')
        end
        refreshPreview:SetScript('OnClick',function()
            if transferSession then return end
            accountPreviewCache=nil
            crosscheckSelection.source='NONE'
            crosscheckSelection.category='NONE'
            Render(true)
        end)
        rows[#rows+1]=refreshPreview
        local preview=accountPreviewCache or {source={}}
        local source=preview.source or {}
        local missing=source.missingLevelingCharacters or 0
        local incomplete=source.incompleteSections or 0
        local staleSections=source.staleSections or 0
        local function Line(value,r,g,b)
            local entry=CreateFrame('Frame',nil,content)
            entry:SetSize(775,21);entry:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local label=entry:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            label:SetPoint('LEFT',entry,'LEFT',0,0)
            label:SetWidth(760);label:SetJustifyH('LEFT');label:SetText(value)
            if r then label:SetTextColor(r,g,b) end
            rows[#rows+1]=entry
            y=y+21
        end
        Line(string.format('%d holder/WBK items compared | %d groups | %d possible excess | %d review',
            source.scannedItems or 0,preview.groups or 0,preview.possible or 0,preview.unresolved or 0))
        Line(string.format('Coverage: %d scanned characters | %d missing leveling-character scans | %d incomplete | %d invalid-time sections',
            source.scannedCharacters or 0,missing,incomplete,staleSections))
        local provisional=source.provisionalSections or 0
        local incomingProvisional=source.incomingProvisionalSections or 0
        if provisional>0 or incomingProvisional>0 then
            Line(string.format('Tracking gap/legacy scans: %d holder/WBK + %d incoming sections provisional. Verify before disposal.',
                provisional,incomingProvisional),1,0.75,0.35)
        end
        if stale then
            Line('Inventory changed since preview. Click Refresh Preview for updated estimates.',1,0.75,0.35)
        else
            Line('Preview snapshot. Refresh manually after gear or Roster changes.',0.75,0.75,0.75)
        end
        Line('Possible excess is an estimate, NOT the live SURPLUS list. Do not use it for disposal.',1,0.75,0.35)
        local owners={}
        for owner in pairs(preview.owners or {}) do owners[#owners+1]=owner end
        table.sort(owners)
        for _,owner in ipairs(owners) do
            local o=preview.owners[owner]
            if o.possible>0 or o.unresolved>0 then
                local cats={}
                for category,n in pairs(o.types or {}) do cats[#cats+1]=category..' '..n end
                table.sort(cats)
                local detail=#cats>0 and (' ('..table.concat(cats,', ')..')') or ''
                Line(owner..': '..o.possible..' possible excess, '..o.unresolved..' review'..detail)
            end
        end
        -- Diagnostic explanation of REVIEW, never an instruction to dispose.
        local reasons={}
        for reason,n in pairs(preview.reviewReasons or {}) do
            reasons[#reasons+1]={text=reason,count=n}
        end
        table.sort(reasons,function(a,b)
            if a.count~=b.count then return a.count>b.count end
            return a.text<b.text
        end)
        if #reasons>0 then
            Line('Holder/WBK REVIEW reasons (not disposal decisions):',0.8,0.8,0.8)
            for i,entry in ipairs(reasons) do
                if i<=5 then Line('  '..entry.count..' - '..entry.text) end
            end
            if #reasons>5 then Line('  Additional review reasons: '..(#reasons-5)) end
        end
        -- Separate max-level source inventory from physically confirmed holder
        -- stock. A main's bags may contain items awaiting normal routing,
        -- future-use gear, or gear pending disposal; do not infer which here.
        Line(string.format('Max-level inventory: %d observed on %d chars | %d binding-verified | %d unverified',
            preview.incomingCount or 0,source.maxLevelCharacters or 0,
            preview.incomingTransferable or 0,preview.incomingNeedsVerification or 0))
        Line('Pending normal routing/status. NOT retained stock or confirmed replacements.',0.8,0.8,0.8)
        Line(string.format('Incoming what-if: %d potential future-use | %d not selected | %d review',
            preview.hypotheticalSelected or 0,preview.hypotheticalUnselected or 0,
            preview.hypotheticalReview or 0))
        Line(string.format('If incoming arrives, up to %d previously allocated holder item(s) might change. Not SURPLUS.',
            preview.hypotheticalDisplaced or 0),0.8,0.8,0.8)
        Line('Hypothetical ONLY: normal routing takes precedence. No gear is safe to dispose.',1,0.75,0.35)
        Line(string.format('Max-level scan coverage: %d unopened/incomplete sections | %d invalid-time',
            source.incomingIncompleteSections or 0,source.incomingStaleSections or 0))
        local incomingNames={}
        for owner in pairs(preview.incomingOwners or {}) do incomingNames[#incomingNames+1]=owner end
        table.sort(incomingNames)
        for _,owner in ipairs(incomingNames) do
            local record=preview.incomingOwners[owner]
            if record.observed>0 then
                Line(owner..': '..record.observed..' observed, '..record.transferable
                    ..' binding-verified, '..record.unverified..' unverified; '
                    ..record.hypotheticalSelected..' future-use, '
                    ..record.hypotheticalUnselected..' not selected, '
                    ..record.hypotheticalReview..' review')
            end
        end
        -- Item explanations are an OPTIONAL nested view of this cached report.
        -- They have no controls for routing, KEEP, or disposal, and do not
        -- re-run the expensive account-wide comparison on disclosure clicks.
        local details=preview.incomingDetails or {}
        if #details>0 then
            local toggle=CreateFrame('Button',nil,content)
            toggle:SetSize(790,23)
            toggle:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local label=toggle:CreateFontString(nil,'OVERLAY','GameFontHighlight')
            label:SetPoint('LEFT',toggle,'LEFT',0,0)
            label:SetText((showIncomingDetails and '[-] ' or '[+] ')
                ..'Incoming item explanations ('..#details..'; read-only)')
            toggle:SetScript('OnClick',function()
                showIncomingDetails=not showIncomingDetails
                Render(true)
            end)
            rows[#rows+1]=toggle
            y=y+25
            if showIncomingDetails then
                local ordered={}
                for _,detail in ipairs(details) do ordered[#ordered+1]=detail end
                table.sort(ordered,function(a,b)
                    if a.owner~=b.owner then return a.owner<b.owner end
                    if a.category~=b.category then return a.category<b.category end
                    if a.itemLevel~=b.itemLevel then return a.itemLevel>b.itemLevel end
                    if a.location~=b.location then return a.location<b.location end
                    if a.bagID~=b.bagID then return (tonumber(a.bagID) or 0)<(tonumber(b.bagID) or 0) end
                    return (tonumber(a.slotID) or 0)<(tonumber(b.slotID) or 0)
                end)
                local lastOwner
                for _,detail in ipairs(ordered) do
                    if lastOwner~=detail.owner then
                        Line('  '..detail.owner..' (incoming gear)',0.85,0.85,0.85)
                        lastOwner=detail.owner
                    end
                    -- An individual observed slot is a distinct physical copy
                    -- even when several identical links are present.
                    local key=detail.owner..':'..detail.location..':'
                        ..tostring(detail.bagID)..':'..tostring(detail.slotID)..':'
                        ..tostring(detail.itemLink)
                    local open=expandedIncomingItems[key]
                    local status=({SELECTED='POTENTIAL',UNSELECTED='NOT SELECTED',
                        REVIEW='REVIEW'})[detail.status] or '?'
                    local itemLabel=tostring(detail.itemLink or detail.itemName or '?')
                    local button=CreateFrame('Button',nil,content)
                    button:SetSize(780,23)
                    button:SetPoint('TOPLEFT',content,'TOPLEFT',21,-y)
                    local text=button:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                    text:SetPoint('LEFT',button,'LEFT',1,0)
                    text:SetWidth(754);text:SetJustifyH('LEFT')
                    text:SetText((open and '[-] ' or '[+] ')..status..' | '
                        ..itemLabel..'  ilvl '..detail.itemLevel)
                    button:SetScript('OnClick',function()
                        expandedIncomingItems[key]=not open
                        Render(true)
                    end)
                    rows[#rows+1]=button
                    y=y+24
                    if open then
                        Line('    '..detail.category..' | req level '..detail.requiredLevel
                            ..' | '..detail.location..' bag '..tostring(detail.bagID)
                            ..', slot '..tostring(detail.slotID),0.77,0.77,0.77)
                        if detail.status=='SELECTED' and detail.assignment then
                            local assigned=detail.assignment
                            local spec=assigned.specID and (' | spec ID '..tostring(assigned.specID)) or ''
                            Line('    Modeled recipient: '..tostring(assigned.name)
                                ..' (future tier level '..tostring(assigned.level)..')'..spec,
                                0.75,0.9,0.75)
                        elseif detail.status=='SELECTED' then
                            Line('    Model selected this copy; recipient details unavailable.',1,0.75,0.35)
                        end
                        if #(detail.candidates or {})>0 then
                            local candidates={}
                            for i,name in ipairs(detail.candidates) do
                                if i<=5 then candidates[#candidates+1]=name end
                            end
                            local extra=#detail.candidates>5 and (' + '..(#detail.candidates-5)..' more') or ''
                            Line('    Eligible future recipients: '..table.concat(candidates,', ')..extra,
                                0.77,0.77,0.77)
                        end
                        Line('    '..tostring(detail.reason or 'No reason recorded'),0.77,0.77,0.77)
                        if detail.groupHolderObserved then
                            Line('    Category context: '..detail.groupHolderObserved
                                ..' observed holder/WBK copies; '
                                ..detail.groupPriorSelectionsChanged
                                ..' baseline selections changed across this category.',
                                0.77,0.77,0.77)
                            if detail.groupPriorSelectionsChanged>0 then
                                Line('    Changes are category-wide, NOT proven 1:1 replacements.',
                                    1,0.75,0.35)
                            end
                        end
                        Line('    Hypothetical only; normal routing still takes precedence.',
                            1,0.75,0.35)
                    end
                end
            end
        end
        return y+8
    end

    local function SavedInventoryBrowser(y)
        local saved=WGRStorageCleanupGetInventorySnapshots and WGRStorageCleanupGetInventorySnapshots()
        if not saved then return y end
        local characters={}
        for key,record in pairs(saved.characters or {}) do
            if type(record)=='table' and not (WGRIsCharacterRemoved
                and WGRIsCharacterRemoved(record.name)) then
                local hasGear=false
                for _,section in pairs(record.sections or {}) do
                    if #(section.items or {})>0 then hasGear=true;break end
                end
                -- Zero-item characters can still have timestamps in saved
                -- data, but don't need to occupy the diagnostics browser.
                if hasGear then characters[#characters+1]={key=key,data=record} end
            end
        end
        table.sort(characters,function(a,b)
            local an,bn=tostring(a.data.name or ''),tostring(b.data.name or '')
            if an~=bn then return an<bn end
            return tostring(a.key)<tostring(b.key)
        end)
        local function Timestamp(stamp)
            if type(stamp)=='number' and stamp>0 and type(date)=='function' then
                return date('%m/%d %H:%M',stamp)
            end
            return 'time unknown'
        end
        local function AddToggle(key,label,depth,ypos,onClick)
            local btn=CreateFrame('Button',nil,content)
            btn:SetSize(790-depth*13,22)
            btn:SetPoint('TOPLEFT',content,'TOPLEFT',depth*13,-ypos)
            local title=btn:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            title:SetPoint('LEFT',btn,'LEFT',1,0)
            title:SetWidth(775-depth*13)
            title:SetJustifyH('LEFT')
            title:SetText(label)
            btn:SetScript('OnClick',onClick)
            rows[#rows+1]=btn
            return ypos+23
        end
        local function ShowSection(ownerKey,location,section,depth,ypos)
            if type(section)~='table' then return ypos end
            local entries=section.items or {}
            local sectionKey=ownerKey..':'..location
            local opened=expandedSavedCategories[sectionKey]
            ypos=AddToggle(sectionKey,(opened and '[-] ' or '[+] ')..location..' ('..#entries..') • scanned '..Timestamp(section.scannedAt)
                ..(section.complete==false and ' • some item data unresolved' or ''),depth,ypos,
                function() expandedSavedCategories[sectionKey]=not opened;Render(true) end)
            if not opened then return ypos end
            local groups,labels={},{}
            for _,entry in ipairs(entries) do
                local category=tostring(entry.category or 'Other')
                if not groups[category] then groups[category]={};labels[#labels+1]=category end
                groups[category][#groups[category]+1]=entry
            end
            table.sort(labels)
            for _,category in ipairs(labels) do
                local categoryKey=sectionKey..':'..category
                local openCategory=expandedSavedCategories[categoryKey]
                ypos=AddToggle(categoryKey,(openCategory and '[-] ' or '[+] ')..category..' ('..#groups[category]..')',depth+1,ypos,
                    function() expandedSavedCategories[categoryKey]=not openCategory;Render(true) end)
                if openCategory then
                    for _,entry in ipairs(groups[category]) do
                        local holder=CreateFrame('Frame',nil,content)
                        holder:SetSize(760,20)
                        holder:SetPoint('TOPLEFT',content,'TOPLEFT',(depth+2)*13,-ypos)
                        local line=holder:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                        line:SetPoint('LEFT',holder,'LEFT',0,0)
                        line:SetWidth(735);line:SetJustifyH('LEFT')
                        line:SetText(tostring(entry.itemLink or entry.itemName or '?')..'  ilvl '..tostring(entry.itemLevel or '?')
                            ..'  req '..tostring(entry.requiredLevel or '?')..'  ['..(entry.lastAudit=='OBSERVED' and 'Observed; not reclassified' or (tostring(entry.lastAudit or '?')..' at audit'))..']')
                        rows[#rows+1]=holder
                        ypos=ypos+20
                    end
                end
            end
            return ypos
        end
        local opened=showSavedInventories
        y=AddToggle('all-snapshots',(opened and '[-] ' or '[+] ')..'Inventory Diagnostics ('..#characters..' scanned characters)',0,y,
            function() showSavedInventories=not opened;Render(true) end)
        if not opened then return y+5 end
        for _,entry in ipairs(characters) do
            local char=entry.data
            local total=0
            for _,section in pairs(char.sections or {}) do total=total+#(section.items or {}) end
            local ownerKey=tostring(entry.key)
            local openOwner=expandedSavedOwners[ownerKey]
            y=AddToggle(ownerKey,(openOwner and '[-] ' or '[+] ')..tostring(char.name or ownerKey)..' ('..total..' last-seen items)'
                ..' • last visited '..Timestamp(char.lastSeen),1,y,
                function() expandedSavedOwners[ownerKey]=not openOwner;Render(true) end)
            if openOwner then
                for _,location in ipairs({'BAG','PBK'}) do
                    y=ShowSection(ownerKey,location,(char.sections or {})[location],2,y)
                end
            end
        end
        if type(saved.warbank)=='table' then
            local openShared=expandedSavedOwners.__WBK
            y=AddToggle('shared-wbk',(openShared and '[-] ' or '[+] ')..'Shared Warbank ('..#(saved.warbank.items or {})..' last-seen items)',1,y,
                function() expandedSavedOwners.__WBK=not openShared;Render(true) end)
            if openShared then
                y=ShowSection('__WBK','WBK',saved.warbank,2,y)
            end
        end
        local hint=CreateFrame('Frame',nil,content)
        hint:SetSize(790,22);hint:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y)
        local txt=hint:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        txt:SetAllPoints();txt:SetJustifyH('LEFT')
        txt:SetText('Saved labels are historical, not live KEEP/SURPLUS decisions. Closed banks retain their last scan.')
        rows[#rows+1]=hint
        local metrics=WGRStorageCleanupGetPassivePerformance and WGRStorageCleanupGetPassivePerformance()
        if metrics then
            local perf=CreateFrame('Frame',nil,content)
            perf:SetSize(790,18);perf:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y-22)
            local line=perf:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            line:SetAllPoints();line:SetJustifyH('LEFT')
            line:SetText(string.format('Snapshot last pass: %.1f ms | %d gear | %d slot details reused%s',
                metrics.lastMilliseconds or 0,metrics.lastCount or 0,metrics.reused or 0,
                metrics.skipped and ' | unchanged' or ''))
            rows[#rows+1]=perf
            y=y+20
            local calc=CreateFrame('Frame',nil,content)
            calc:SetSize(790,18);calc:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y-22)
            local calcLine=calc:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            calcLine:SetAllPoints();calcLine:SetJustifyH('LEFT')
            calcLine:SetText(string.format('Last live retention calculation: %.1f ms | account preview: %.1f ms (manual refresh)',
                lastLocalAuditMs,lastAccountPreviewMs))
            rows[#rows+1]=calc
            y=y+20
            local auto=CreateFrame('Frame',nil,content)
            auto:SetSize(790,18);auto:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y-22)
            local autoLine=auto:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            autoLine:SetAllPoints();autoLine:SetJustifyH('LEFT')
            autoLine:SetText('Last automatic Cleanup update: '..lastAutomaticAudit
                ..' | planner skips: '..locationOnlySkips)
            rows[#rows+1]=auto
            y=y+20
        end
        return y+29
    end

    local function SurplusInstruction(item)
        if item.binding=="UNKNOWN" then return "Extra gear - binding needs review" end
        local prefix=item.binding=="WARBAND" and "warbound" or "boe"
        local recipient=settings[prefix.."Recipient"] or "CURRENT"
        if recipient~="CURRENT" and recipient~=UnitName("player") then
            return "Extra gear - route to "..tostring(recipient).." manually"
        end
        return "Extra gear"
    end
    local slotNames={
        INVTYPE_HEAD='Head',INVTYPE_SHOULDER='Shoulders',INVTYPE_CHEST='Chest',
        INVTYPE_ROBE='Chest',INVTYPE_WAIST='Waist',INVTYPE_LEGS='Legs',
        INVTYPE_FEET='Feet',INVTYPE_WRIST='Wrists',INVTYPE_HAND='Hands',
        INVTYPE_CLOAK='Cloaks',INVTYPE_NECK='Necks',INVTYPE_FINGER='Rings',
        INVTYPE_TRINKET='Trinkets',INVTYPE_RANGED='Ranged weapons',
        INVTYPE_RANGEDRIGHT='Ranged weapons',INVTYPE_2HWEAPON='Two-hand weapons',
        INVTYPE_WEAPON='One-hand weapons',INVTYPE_WEAPONMAINHAND='One-hand weapons',
        INVTYPE_WEAPONOFFHAND='One-hand weapons',INVTYPE_HOLDABLE='Offhands',
        INVTYPE_SHIELD='Shields',
    }
    local function SlotSectionName(item)
        if item.cleanupGroupLabel then return item.cleanupGroupLabel end
        local _,_,_,_,_,_,_,_,equipLoc=C_Item.GetItemInfo(item.itemLink)
        if equipLoc and (IsSupportedWeapon and IsSupportedWeapon(item.itemLink)
            or (WGROffhandEquipLocs and WGROffhandEquipLocs[equipLoc])) then
            local section,category
            if WGRClassifyHeldGearItem then
                section,category=WGRClassifyHeldGearItem(item.itemLink)
            end
            if section=='Weapons' and category then return category end
        end
        return slotNames[equipLoc] or 'Other / Unclassified'
    end
    local function AddSlotSection(status,label,count,y)
        local key=status..':'..label
        local button=CreateFrame('Button',nil,content)
        button:SetHeight(22)
        button:SetPoint('TOPLEFT',content,'TOPLEFT',0,-y)
        button:SetPoint('RIGHT',content,'RIGHT',0,0)
        local bg=button:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints()
        bg:SetColorTexture(0.13,0.15,0.18,0.52)
        local text=button:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
        text:SetPoint('LEFT',button,'LEFT',7,0)
        text:SetText((collapsedSlots[key] and '[+] ' or '[-] ')..label..' ('..count..')')
        button:SetScript('OnClick',function()
            collapsedSlots[key]=not collapsedSlots[key]
            Render(true)
        end)
        rows[#rows+1]=button
        return y+23,not collapsedSlots[key]
    end
    -- The original KEEP/SURPLUS decisions are frozen for this audit. A staged
    -- surplus piece is tracked by its VERIFIED destination slot, not by
    -- recalculating its duplicate item link against the live inventory.
    -- No player movement is performed here: all transfers use Gear Finder.
    local displayedKeep,displayedSurplus={},{}
    local displayedReview,displayedTotal,displayedPBK,displayedWBK={},0,false,false
    local displayedPhysicalItems=nil
    local hasDisplayedAudit=false
    -- v0.68v: Account proof is deliberately manual and session-only. A
    -- passive snapshot may invalidate it, but never reruns the planner.
    local accountAudit=nil
    local accountAuditRevision=nil
    local accountAuditSerial=0
    -- v0.72ah TEST: capture the exact reason a completed Storage Cleanup
    -- account proof is discarded. Some manual/container moves still reach
    -- different passive-refresh paths; this diagnostic is read-only and lets
    -- live testing identify the remaining invalidator instead of guessing.
    local lastCleanupInvalidationText=nil
    -- v0.72am: Storage Cleanup is now an explicit/manual audit. Background
    -- inventory observations may safely remap a proven location-only move, but
    -- must never erase the current completed result. Any passive change that
    -- cannot be remapped is flagged for the user's next manual Rescan instead.
    local accountChecking=false
    transferSession=nil
    local cleanupTransferBusy=false
    local function PhysicalKey(item)
        if not item or item.bagID==nil or item.slotID==nil or not item.itemLink then return nil end
        return tostring(item.source)..':'..tostring(item.bagID)..':'..
            tostring(item.slotID)..':'..tostring(item.itemLink)
    end
    local function PositionKey(item)
        if not item or item.source==nil or item.bagID==nil or item.slotID==nil then return nil end
        return tostring(item.source)..':'..tostring(item.bagID)..':'..tostring(item.slotID)
    end
    local function SourceVisible(item)
        if not item then return false end
        if item.source=='PERSONAL_BANK' then
            return WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
        elseif item.source=='WARBAND_BANK' then
            return WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
        end
        return item.source=='BAGS'
    end
    local function SameSourceItem(item)
        return SourceVisible(item) and C_Container and C_Container.GetContainerItemLink
            and C_Container.GetContainerItemLink(item.bagID,item.slotID)==item.itemLink
    end
    local function AccountItemKey(item)
        if not item or not item.source or item.bagID==nil or
            item.slotID==nil or not item.itemLink then return nil end
        return tostring(item.source)..':'..tostring(item.bagID)..':'..
            tostring(item.slotID)..':'..tostring(item.itemLink)
    end
    local function AccountPhysicalSignature(items)
        local parts={}
        for _,item in ipairs(items or {}) do
            local key=AccountItemKey(item)
            if not key then return nil end
            -- No bank-entry can be confidently certified by link/slot alone.
            local guid=WGRStorageCleanupGetPhysicalCopyGUID and
                WGRStorageCleanupGetPhysicalCopyGUID(item.bagID,item.slotID,item.itemLink)
            parts[#parts+1]=key..':'..tostring(guid or '?')
        end
        table.sort(parts)
        return table.concat(parts,'|')
    end
    -- Snapshot writers also bump the presentation revision for unchanged
    -- observations. Compare the actual account STOCK and confidence contents
    -- when that happens, rather than cancelling a legitimate account proof
    -- merely because a passive timestamp/classification was rewritten.
    local function AccountStockSignature()
        local source=WGRStorageCleanupGetAccountSnapshotCandidates and
            WGRStorageCleanupGetAccountSnapshotCandidates()
        if not source or source.unavailable then return nil end
        local parts={}
        for _,pool in ipairs({source.records or {},source.incoming or {}}) do
            for _,item in ipairs(pool) do
                parts[#parts+1]=table.concat({
                    tostring(item.cleanupOwner),tostring(item.cleanupLocation),
                    tostring(item.bagID),tostring(item.slotID),tostring(item.itemLink),
                    tostring(item.itemLevel),tostring(item.minLevel),
                    tostring(item.binding),tostring(item.cleanupScanStale),
                    tostring(item.cleanupTrackingProvisional)},'|')
            end
        end
        for _,field in ipairs({'missingLevelingCharacters','staleSections',
            'incompleteSections','provisionalSections','incomingIncompleteSections',
            'incomingStaleSections','incomingProvisionalSections'}) do
            parts[#parts+1]='! '..field..'='..tostring(source[field] or 0)
        end
        table.sort(parts)
        return table.concat(parts,'\n')
    end
    local function SignatureDiffLines(label,oldSig,newSig,limit)
        local lines={label..':'}
        limit=limit or 16
        local function split(value)
            local out={}
            for row in tostring(value or ''):gmatch('[^\n]+') do out[row]=true end
            return out
        end
        local oldSet,newSet=split(oldSig),split(newSig)
        local removed,added={},{}
        for row in pairs(oldSet) do if not newSet[row] then removed[#removed+1]=row end end
        for row in pairs(newSet) do if not oldSet[row] then added[#added+1]=row end end
        table.sort(removed);table.sort(added)
        lines[#lines+1]='  removed='..#removed..' added='..#added
        local shown=0
        for _,row in ipairs(removed) do
            if shown>=limit then break end
            lines[#lines+1]='  - '..row;shown=shown+1
        end
        for _,row in ipairs(added) do
            if shown>=limit then break end
            lines[#lines+1]='  + '..row;shown=shown+1
        end
        if #removed+#added>shown then
            lines[#lines+1]='  ... '..tostring(#removed+#added-shown)..' additional changed entries'
        end
        return lines
    end
    local function PhysicalDiagnosticSignature(items)
        local rows={}
        for _,item in ipairs(items or {}) do
            local mode='-'
            if WGRStorageCleanupGetCopyMark and item.bagID~=nil and item.slotID~=nil then
                mode=WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source) or '-'
            end
            rows[#rows+1]=table.concat({
                tostring(item.source),tostring(item.bagID),tostring(item.slotID),
                tostring(item.itemLink),tostring(mode),
                tostring(item.cleanupManualDispose and 'stored-dispose' or '-')},'|')
        end
        table.sort(rows)
        return table.concat(rows,'\n')
    end
    local function RecordCleanupInvalidation(reason,oldPhysical,newPhysical,oldStock,newStock)
        local lines={
            'WBGR v0.72ar Storage Cleanup invalidation diagnostic',
            'Reason: '..tostring(reason or 'unknown'),
            'Character: '..tostring((UnitName and UnitName('player')) or '?'),
            'Inventory revision: '..tostring(WGRStorageCleanupGetInventoryRevision and
                WGRStorageCleanupGetInventoryRevision() or '?'),
            'Audit revision: '..tostring(accountAuditRevision),
            'PBK open: '..tostring(WGRGearFinderIsPersonalBankOpen and
                WGRGearFinderIsPersonalBankOpen() or false),
            'WBK open: '..tostring(WGRGearFinderIsWarbandBankOpen and
                WGRGearFinderIsWarbandBankOpen() or false),
            'Last passive decision: '..tostring(lastAutomaticAudit),
        }
        if oldPhysical or newPhysical then
            local diff=SignatureDiffLines('Accessible physical changes',
                PhysicalDiagnosticSignature(oldPhysical),PhysicalDiagnosticSignature(newPhysical),24)
            for _,line in ipairs(diff) do lines[#lines+1]=line end
        end
        if oldStock~=nil or newStock~=nil then
            local diff=SignatureDiffLines('Saved account-stock changes',oldStock,newStock,24)
            for _,line in ipairs(diff) do lines[#lines+1]=line end
        end
        lines[#lines+1]='Read-only diagnostic; no gear, marks, or saved inventory changed.'
        lastCleanupInvalidationText=table.concat(lines,'\n')
        _G.WGRStorageCleanupLastInvalidationDiagnosticText=lastCleanupInvalidationText
    end
    local function ApplyAccountClassification(keep,surplus,review,physical,audit)
        if not audit then return keep,surplus,review end
        local verified,retained,possible,uncertain={},{},{},{}
        local retainedAssignments={}
        local verifiedTrinket={}
        local function store(list,dest,captureAssignment,captureTrinketProof)
            for _,entry in ipairs(list or {}) do
                local key=AccountItemKey(entry)
                if key and entry.guid then
                    dest[key]=entry.guid
                    if captureAssignment and entry.cleanupAccountAssignment then
                        retainedAssignments[key]=entry.cleanupAccountAssignment
                    end
                    if captureTrinketProof and entry.cleanupTrinketSurplusProven then
                        verifiedTrinket[key]=entry.guid
                    end
                end
            end
        end
        store(audit.verifiedPossible,verified,false,true)
        store(audit.retained,retained,true)
        store(audit.possible,possible)
        local possibleReasons={}
        for _,entry in ipairs(audit.evidence or {}) do
            if entry.candidateKey then
                local provisional,disposeMarks,other=0,0,0
                local owners={}
                for _,stock in ipairs(entry.stock or {}) do
                    local trust=tostring(stock.trust or '')
                    if trust=='PROVISIONAL GENERATION' then
                        provisional=provisional+1
                    elseif trust=='POSSIBLE DISPOSE MARK' then
                        disposeMarks=disposeMarks+1
                    elseif trust~='VERIFIED SUPPLY' then
                        other=other+1
                    end
                    if trust~='VERIFIED SUPPLY' and stock.owner then
                        local label=tostring(stock.owner)
                        if stock.location then label=label..'/'..tostring(stock.location) end
                        owners[label]=true
                    end
                end
                local ownerList={}
                for label in pairs(owners) do ownerList[#ownerList+1]=label end
                table.sort(ownerList)
                local suffix=''
                if #ownerList==1 then suffix=' ('..ownerList[1]..')'
                elseif #ownerList>1 then suffix=' ('..tostring(#ownerList)..' saved locations)' end
                if provisional>0 and disposeMarks>0 then
                    possibleReasons[entry.candidateKey]=
                        'Possible surplus; saved supply needs re-verification and has unresolved DISPOSE tracking'..suffix
                elseif provisional>0 then
                    possibleReasons[entry.candidateKey]=
                        'Possible surplus; saved supply is provisional and must be re-verified'..suffix
                elseif disposeMarks>0 then
                    possibleReasons[entry.candidateKey]=
                        'Possible surplus; another saved copy has unresolved DISPOSE tracking'..suffix
                elseif other>0 then
                    possibleReasons[entry.candidateKey]=
                        'Possible surplus; another saved copy is not verified supply'..suffix
                else
                    possibleReasons[entry.candidateKey]=
                        'Possible surplus; verified supply is still insufficient'
                end
            end
        end
        for _,entry in ipairs(audit.uncertain or {}) do
            local key=AccountItemKey(entry.item)
            if key then uncertain[key]=entry.reason or 'Account stock not fully verified' end
        end
        local previousReview,locallyRelevant={},{}
        for _,item in ipairs(review) do previousReview[item]=true end
        for _,list in ipairs({keep,surplus,review}) do
            for _,item in ipairs(list) do locallyRelevant[item]=true end
        end
        local k,s,r={},{},{}
        for _,item in ipairs(physical or {}) do
            if locallyRelevant[item] then
            -- Normal engine's immediate upgrades and other intentional
            -- non-Cleanup routes are not Cleanup REVIEW tasks.
            -- Remember the ORIGINAL local uncertainty independently of any
            -- provisional REVIEW rendering. A later async account result
            -- must not mistake that UI-only REVIEW for a safety blocker.
            if item.cleanupOriginallyReview==nil then
                item.cleanupOriginallyReview=previousReview[item] and true or false
            end
            local key=AccountItemKey(item)
            local mode=WGRStorageCleanupGetCopyMark and
                WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source)
            local activeDispose=mode=='DISPOSE' and
                WGRStorageCleanupIsDisposeCopy and
                WGRStorageCleanupIsDisposeCopy(item.bagID,item.slotID,item.itemLink,item.source)
            local guid=key and WGRStorageCleanupGetPhysicalCopyGUID and
                WGRStorageCleanupGetPhysicalCopyGUID(item.bagID,item.slotID,item.itemLink)
            -- Session-only proof for the exact account-verified physical copy.
            -- A frozen Get -> Bags move may preserve this verified disposal
            -- intent only when the source AND destination retain this GUID.
            item.cleanupAccountVerifiedGUID=nil
            if activeDispose then
                item.cleanupReason='DISPOSE marked physical copy — excluded from retention'
                s[#s+1]=item
            elseif mode=='KEEP' then
                item.cleanupReason='Manual KEEP — protected physical copy'
                k[#k+1]=item
            elseif guid and verified[key]==guid
                and (not item.cleanupOriginallyReview or verifiedTrinket[key]==guid) then
                item.cleanupAccountVerifiedGUID=guid
                item.cleanupReason=verifiedTrinket[key]==guid
                    and 'Account-wide VERIFIED trinket excess (retained pairs unchanged)'
                    or 'Account-wide VERIFIED excess (current trusted supply)'
                s[#s+1]=item
            elseif not item.cleanupOriginallyReview and guid and retained[key]==guid then
                local assignment=retainedAssignments[key]
                item.cleanupReason=WGRStorageCleanupAccountRetentionReason and
                    WGRStorageCleanupAccountRetentionReason(assignment)
                    or 'Retained by account-wide allocation'
                item.cleanupAssignedName=assignment and assignment.name or nil
                item.cleanupAssignedLevel=assignment and assignment.level or nil
                k[#k+1]=item
            else
                -- An unproven local "surplus" or local "retain for Kiergy"
                -- is not an account-wide decision. Never allow the old local
                -- mover to act on this provisional result.
                item.cleanupReason=possible[key] and
                    (possibleReasons[key] or
                        'Account-wide POSSIBLE only; verified evidence insufficient')
                    or uncertain[key] and ('Account-wide: '..tostring(uncertain[key]))
                    or 'No verified account-wide classification for this physical copy'
                r[#r+1]=item
            end
            end -- item was in the original local Cleanup audit
        end
        if WGRStorageCleanupSortAccountClassified then
            WGRStorageCleanupSortAccountClassified(k,s,r)
        end
        return k,s,r
    end
    local function ValidateAccountAudit(physical)
        if not accountAudit then return false,'no cached account audit' end
        if transferSession then return false,'legacy transfer session active' end
        if accountChecking then return false,'account check still running' end
        if not settings.enabled then return false,'Storage Cleanup disabled' end
        local revision=WGRStorageCleanupGetInventoryRevision and
            WGRStorageCleanupGetInventoryRevision() or 0
        if revision~=accountAuditRevision then
            local stock=AccountStockSignature()
            if stock~=accountAudit.stockSignature then
                RecordCleanupInvalidation('saved account-stock signature changed',
                    physical,physical,accountAudit.stockSignature,stock)
                return false,'saved account-stock signature changed'
            end
            accountAuditRevision=revision
        end
        local physicalSig=AccountPhysicalSignature(physical)
        if physicalSig~=accountAudit.signature then
            RecordCleanupInvalidation('accessible physical signature changed',
                displayedPhysicalItems,physical,nil,nil)
            return false,'accessible physical signature changed'
        end
        return true,'valid'
    end
    local function ValidAccountAudit(physical)
        local valid=ValidateAccountAudit(physical)
        return valid
    end
    local function SnapshotAccessible()
        -- Frozen movement verification is identity-only.  Do not run the
        -- transferable/tooltip eligibility scanner here: right after WBK/PBK
        -- movement it can temporarily omit a perfectly real destination copy.
        if WGRStorageCleanupSnapshotAccessiblePhysical then
            return WGRStorageCleanupSnapshotAccessiblePhysical()
        end
        local records,pbk,wbk=WGRStorageCleanupScanAccessible()
        local slots,positions,counts,bagCounts,byGUID={},{},{},{},{}
        for _,item in ipairs(records) do
            slots[PhysicalKey(item)]=item
            positions[PositionKey(item)]=item
            counts[item.itemLink]=(counts[item.itemLink] or 0)+1
            if item.source=='BAGS' then
                bagCounts[item.itemLink]=(bagCounts[item.itemLink] or 0)+1
            end
            local guid=WGRStorageCleanupGetPhysicalCopyGUID and
                WGRStorageCleanupGetPhysicalCopyGUID(item.bagID,item.slotID,item.itemLink)
            if guid then item.guid=guid;byGUID[guid]=item end
        end
        return {slots=slots,positions=positions,counts=counts,bagCounts=bagCounts,byGUID=byGUID,
            guidCollisions={},pbk=pbk,wbk=wbk}
    end
    local function RemainingSurplus(session)
        local remaining={}
        for _,item in ipairs(session.surplus) do
            if not session.moved[PhysicalKey(item)] then remaining[#remaining+1]=item end
        end
        return remaining
    end
    local function StagedSurplus(session)
        local staged={}
        for _,item in ipairs(session.surplus) do
            local record=session.staged[PhysicalKey(item)]
            if record then staged[#staged+1]=record end
        end
        return staged
    end
    -- Frozen batches may return a SURPLUS copy into another SURPLUS copy's
    -- vacated original bank slot. Protect only PHYSICALLY OCCUPIED slots:
    -- original KEEP, pending original SURPLUS, and observed STAGED copies.
    -- Do not reserve a moved item's abandoned origin as if it were occupied.
    local function VerifyFrozenSources(session)
        return WGRStorageCleanupVerifyFrozenSourceSlots(session,PhysicalKey,SameSourceItem)
    end
    local function VerifyUnchangedPlan()
        local report=accountAudit
        local valid=report and ValidAccountAudit(displayedPhysicalItems)
        if WGRBeginRoutingEvaluationCache then WGRBeginRoutingEvaluationCache() end
        local freshKeep,freshSurplus,freshReview,_,_,_,freshPhysical=WGRStorageCleanupAnalyze()
        if WGREndRoutingEvaluationCache then WGREndRoutingEvaluationCache() end
        if valid and AccountPhysicalSignature(freshPhysical)==report.signature then
            freshKeep,freshSurplus=ApplyAccountClassification(
                freshKeep,freshSurplus,freshReview,freshPhysical,report)
            accountAuditRevision=WGRStorageCleanupGetInventoryRevision()
        elseif report then
            -- A changed source/identity invalidates all cached approvals.
            -- Never fall back to an accidentally matching LOCAL allocation
            -- when the physical account proof is stale: it could otherwise
            -- authorize the first movement of a no-longer-verified surplus.
            accountAudit=nil
            return false
        end
        local function Matches(expected,actual)
            if #expected~=#actual then return false end
            local count={}
            for _,item in ipairs(expected) do
                local key=PhysicalKey(item)
                if not key or count[key] then return false end
                count[key]=true
            end
            for _,item in ipairs(actual) do
                local key=PhysicalKey(item)
                if not key or not count[key] then return false end
                count[key]=nil
            end
            return true
        end
        return Matches(displayedKeep,freshKeep) and Matches(displayedSurplus,freshSurplus)
    end
    local function CopyAtLocation(original,live,origin)
        local item={}
        for k,v in pairs(original) do item[k]=v end
        item.bagID=live.bagID
        item.slotID=live.slotID
        item.source=live.source
        item.location=live.location
        item.cleanupOriginKey=origin
        return item
    end

    local function ResolveControlledTransfer(before,after,selected,destination)
        return WGRStorageCleanupResolveControlledTransfer(
            before,after,selected,destination,PositionKey)
    end
    local function FrozenUnselectedIntact(session,selected,before,after)
        return WGRStorageCleanupFrozenUnselectedIntact(
            session,selected,before,after,PhysicalKey,PositionKey)
    end
    local function MoveVerified(records,destination,fromStaged,crosscheckContext)
        if cleanupTransferBusy then
            print('|cffffaa00WBGR:|r Cleanup is still settling the previous transfer. Please wait.')
            return
        end
        if not settings.enabled or not WGRStorageCleanupMoveRecords then return end
        cleanupTransferBusy=true
        local function Abort(reason)
            cleanupTransferBusy=false
            print('|cffff5555WBGR:|r Cleanup move cancelled: '..reason..'. Frozen KEEP items remain protected.')
            Changed()
        end
        if not transferSession then
            if fromStaged then Abort('there is no staged batch');return end
            if not VerifyUnchangedPlan() then
                Abort('the inventory or KEEP/SURPLUS plan changed before the first transfer')
                return
            end
            local approvedCrosscheck
            if crosscheckContext then
                -- The initial filtered list is the ONLY approval set for the
                -- entire frozen session. All entries must still be original
                -- LOCAL SURPLUS in their original verified source slots.
                approvedCrosscheck=WGRStorageCleanupMakeFrozenCrosscheck(
                    crosscheckContext.records,crosscheckContext.source,crosscheckContext.category)
                if not approvedCrosscheck then
                    Abort('no validated source/category cross-check to freeze');return
                end
                local originals={}
                for _,item in ipairs(displayedSurplus) do
                    originals[PhysicalKey(item)]=item
                end
                local selectedCount=0
                for key,record in pairs(approvedCrosscheck.approved) do
                    local item=originals[key]
                    if not item or record.itemLevel~=item.itemLevel
                        or record.binding~=item.binding or not SameSourceItem(item) then
                        Abort('cross-checked originals changed before the batch could freeze');return
                    end
                    selectedCount=selectedCount+1
                end
                if selectedCount~=approvedCrosscheck.count then
                    Abort('duplicate or ambiguous cross-checked originals');return
                end
            end
            local baseline=SnapshotAccessible()
            transferSession={keep=displayedKeep,surplus=displayedSurplus,
                review=displayedReview,total=displayedTotal,
                moved={},staged={},initialCounts=baseline.counts,
                initialBagCounts=baseline.bagCounts,
                initialPBKOpen=baseline.pbk,initialWBKOpen=baseline.wbk,
                crosscheck=approvedCrosscheck}
            print('|cff33ff99WBGR:|r Frozen Cleanup batch: '..#displayedSurplus..
                ' SURPLUS, '..#displayedKeep..' protected KEEP.')
        end
        local session=transferSession
        if session.unverified then
            Abort('a previous transfer could not be verified; inspect the batch before finishing and recalculating')
            return
        end
        if session.crosscheck and not fromStaged and
            not WGRStorageCleanupFrozenCrosscheckAllows(session,records,destination) then
            Abort('selection is outside the frozen account cross-check or already staged')
            return
        end
        local valid,reason=VerifyFrozenSources(session)
        if not valid then Abort(reason);return end
        local allowed={}
        for _,item in ipairs(session.surplus) do
            local origin=PhysicalKey(item)
            if fromStaged then
                local live=session.staged[origin]
                if live then allowed[origin]=live end
            elseif not session.moved[origin] then
                allowed[origin]=item
            end
        end
        local selected,sourceRecords,seen={},{},{}
        for _,requested in ipairs(records or {}) do
            local origin=fromStaged and requested.cleanupOriginKey or PhysicalKey(requested)
            local current=origin and allowed[origin]
            if not current or seen[origin] or PhysicalKey(current)~=PhysicalKey(requested) then
                Abort('selection no longer matches verified '..(fromStaged and 'STAGED' or 'SURPLUS')..' records')
                return
            end
            seen[origin]=true
            if current.source~=destination then
                local mode,mark=WGRStorageCleanupGetCopyMark and
                    WGRStorageCleanupGetCopyMark(current.bagID,current.slotID,current.itemLink,current.source)
                local sourceGUID=WGRStorageCleanupGetPhysicalCopyGUID and
                    WGRStorageCleanupGetPhysicalCopyGUID(current.bagID,current.slotID,current.itemLink)
                local autoGUID=(mode=='DISPOSE' and mark and mark.reason=='AUTO_VERIFIED')
                    and sourceGUID or nil
                local manualOverrideGUID=((mode=='DISPOSE' or mode=='KEEP') and mark and
                    (mark.reason==nil or mark.reason=='MANUAL' or
                     mark.reason=='MANUAL_DISPOSAL_MAIL_RECOVERY')) and sourceGUID or nil
                -- Only the already account-verified, frozen SURPLUS copy can
                -- gain a new durable disposal mark from a deliberate Get to
                -- Bags. Never use a matching link as physical identity.
                -- A returned copy stays in the frozen staged ledger. A second
                -- Get is therefore fromStaged=true, but it is still a deliberate
                -- verified disposal staging if the same tracked copy is back
                -- at its original bank. Do not demand original GUID continuity
                -- across WBK; frozen source/slot verification proves this copy.
                local verifiedRestage=false
                if fromStaged and destination=='BAGS' then
                    for _,original in ipairs(session.surplus) do
                        if PhysicalKey(original)==origin and
                            original.cleanupAccountVerifiedGUID and
                            current.source==original.source and session.moved[origin] then
                            verifiedRestage=true
                            break
                        end
                    end
                end
                local stagedGUID=(not fromStaged and destination=='BAGS' and
                    current.source~='BAGS' and current.cleanupAccountVerifiedGUID and
                    sourceGUID==current.cleanupAccountVerifiedGUID and sourceGUID)
                    or (verifiedRestage and sourceGUID) or nil
                if not fromStaged and destination=='BAGS' and
                    current.cleanupAccountVerifiedGUID and not stagedGUID then
                    Abort('the verified surplus copy GUID changed before staging')
                    return
                end
                if not sourceGUID then
                    Abort('physical source GUID unavailable for frozen movement')
                    return
                end
                selected[#selected+1]={origin=origin,record=current,
                    autoDisposeGUID=autoGUID,manualOverrideGUID=manualOverrideGUID,
                    verifiedStagedGUID=stagedGUID,sourceGUID=sourceGUID}
                sourceRecords[#sourceRecords+1]=current
                if #selected>=20 then break end
            end
        end
        if #selected==0 then Abort('no selected items need movement to that location');return end
        local before=SnapshotAccessible()
        if (session.initialPBKOpen and not before.pbk) or (session.initialWBKOpen and not before.wbk)
            or (destination=='PERSONAL_BANK' and not before.pbk)
            or (destination=='WARBAND_BANK' and not before.wbk) then
            Abort('reopen the original and destination bank(s) for slot verification')
            return
        end
        if not fromStaged then
            for _,entry in ipairs(selected) do
                if not SameSourceItem(entry.record) then Abort('source slot changed');return end
            end
        end
        print('|cff33ff99WBGR:|r Moving up to '..#selected..' verified '..
            (fromStaged and 'STAGED' or 'SURPLUS')..' item(s) using Gear Finder.')
        WGRStorageCleanupMoveRecords(sourceRecords,destination)
        local settleDelays={0.35,0.70,1.10,1.60}
        local function Settle(attempt)
            attempt=attempt or 1
            local after=SnapshotAccessible()
            local resolved,resolveReason=ResolveControlledTransfer(before,after,selected,destination)
            local intact,intactReason=FrozenUnselectedIntact(session,selected,before,after)
            local banksMissing=(session.initialPBKOpen and not after.pbk)
                or (session.initialWBKOpen and not after.wbk)
            local failed=(not resolved) or not intact or banksMissing
            if failed and attempt<#settleDelays and C_Timer and C_Timer.After then
                C_Timer.After(settleDelays[attempt+1],function() Settle(attempt+1) end)
                return
            end

            if failed then
                session.unverified=true
                local why=resolveReason or intactReason or (banksMissing and 'required bank visibility was lost')
                    or 'destination transfer could not be proven'
                print('|cffff5555WBGR:|r Destination transfer could not be verified ('..tostring(why)..'). Batch locked; inspect inventory, then Finish Batch & Recalculate once items are safely resolved.')
            else
                local deltaCount=0
                for _,pair in ipairs(resolved) do
                    local entry,live=pair.entry,pair.live
                    if pair.proof=='SLOT_DELTA' then deltaCount=deltaCount+1 end
                    local original=nil
                    for _,candidate in ipairs(session.surplus) do
                        if PhysicalKey(candidate)==entry.origin then original=candidate;break end
                    end
                    if original then
                        session.staged[entry.origin]=CopyAtLocation(original,live,entry.origin)
                        session.moved[entry.origin]=true
                        -- The source copy was already account-verified before
                        -- movement.  After a controlled transfer is proven,
                        -- persist disposal intent on the CURRENT destination
                        -- GUID; WBK is not required to preserve the old GUID.
                        if entry.manualOverrideGUID and WGRStorageCleanupTransferManualOverrideByGUID then
                            local ok,why=WGRStorageCleanupTransferManualOverrideByGUID(
                                entry.manualOverrideGUID,live.bagID,live.slotID,live.itemLink,true)
                            if not ok then
                                print('|cffffaa00WBGR:|r Could not preserve manual override after movement: '..tostring(why))
                            else
                                if WGRRefreshCopyOverlay then WGRRefreshCopyOverlay(live.bagID,live.slotID) end
                                if WGRMarkBagnonOverlayBagDirty then WGRMarkBagnonOverlayBagDirty(live.bagID) end
                            end
                        elseif entry.verifiedStagedGUID then
                            local ok,why
                            if WGRStorageCleanupConfirmVerifiedStagedArrival then
                                ok,why=WGRStorageCleanupConfirmVerifiedStagedArrival(
                                    live.bagID,live.slotID,live.itemLink)
                            elseif WGRStorageCleanupConfirmVerifiedStagedCopy then
                                ok,why=WGRStorageCleanupConfirmVerifiedStagedCopy(
                                    live.bagID,live.slotID,live.itemLink,
                                    entry.verifiedStagedGUID)
                            end
                            if ok==false then
                                print('|cffffaa00WBGR:|r Staged physical copy was moved but could not be marked DISPOSE: '..tostring(why)..'. Review this item before disposal.')
                            elseif ok then
                                -- The staged mark is intentionally written with refresh
                                -- suppression so the frozen transfer can settle first.
                                -- Now that the destination copy is proven, repaint the
                                -- exact Bag slot immediately and queue one dirty-bag
                                -- refresh for Bagnon's own post-move update timing.
                                if WGRRefreshCopyOverlay then
                                    WGRRefreshCopyOverlay(live.bagID,live.slotID)
                                end
                                if WGRMarkBagnonOverlayBagDirty then
                                    WGRMarkBagnonOverlayBagDirty(live.bagID)
                                end
                            end
                        elseif entry.autoDisposeGUID and WGRStorageCleanupSetCopyMark then
                            local ok,why=WGRStorageCleanupSetCopyMark(
                                live.bagID,live.slotID,'DISPOSE','MANUAL',true)
                            if not ok then
                                print('|cffffaa00WBGR:|r Could not preserve an auto-DISPOSE copy after movement: '..tostring(why))
                            end
                        end
                        if fromStaged and destination==original.source and entry.sourceGUID then
                            if WGRStorageCleanupClearVerifiedStageByGUID then
                                WGRStorageCleanupClearVerifiedStageByGUID(entry.sourceGUID,live.itemLink)
                            elseif WGRStorageCleanupClearVerifiedStageOnReturn then
                                WGRStorageCleanupClearVerifiedStageOnReturn(
                                    live.bagID,live.slotID,live.itemLink,entry.sourceGUID)
                            end
                        end
                    end
                end
                local proofText=deltaCount>0 and
                    (' ('..deltaCount..' by controlled slot delta)') or ' (physical GUID)'
                print('|cff33ff99WBGR:|r Verified '..#resolved..' '..
                    (fromStaged and 'onward' or 'initial')..' transfer(s)'..proofText..'. '..
                    #RemainingSurplus(session)..' pending; '..#StagedSurplus(session)..' tracked as staged.')
            end
            cleanupTransferBusy=false
            -- A deliberate new SURPLUS -> Bags staging action is a fresh user
            -- request to dispose of these physical copies. If this exact GUID
            -- group had previously been dismissed from To Do, revive that
            -- reminder now; passive refreshes/reloads still leave dismissals
            -- alone. This matters when a copy was returned to storage and later
            -- staged again with the same physical GUID/signature.
            if not session.unverified and destination=='BAGS' and
                (not fromStaged or (selected[1] and selected[1].verifiedStagedGUID)) then
                if WGRRestoreDisposeTodoAfterManualScan then
                    WGRRestoreDisposeTodoAfterManualScan('BAGS')
                end
                -- WGRRefreshCopyOverlay above handles the destination slot as soon
                -- as the DISPOSE mark is persisted. Queue one incremental repaint
                -- as well because Bagnon can rebuild/reindex its item button shortly
                -- after the container move settles.
                if QueueCleanupRefresh then
                    QueueCleanupRefresh(true)
                end
            end
            -- A successful relocation immediately updates the staged BAG/PBK/WBK
            -- row, so the Gear Finder locator points at the live destination.
            if WGRMailRefreshCurrentTodoSnapshot then
                WGRMailRefreshCurrentTodoSnapshot(true,true)
            elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
            Changed()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(settleDelays[1],function() Settle(1) end)
        else
            Settle(1)
        end
    end
    local MoveCleanupDirect
    local function AddRow(item,index,y,isSurplus,isStaged)
        local row=CreateFrame("Frame",nil,content);row:SetHeight(30)
        row:SetPoint("TOPLEFT",content,"TOPLEFT",0,-y);row:SetPoint("RIGHT",content,"RIGHT",0,0)
        local bg=row:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints()
        local color=index%2==0 and 0.11 or 0.05;bg:SetColorTexture(color,color,color,0.32)
        local ico=CreateFrame("Button",nil,row);ico:SetSize(24,24);ico:SetPoint("LEFT",row,"LEFT",2,0)
        local texture=ico:CreateTexture(nil,"ARTWORK");texture:SetAllPoints()
        texture:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.itemLink) or 134400)
        local function ShowCleanupItemTooltip(self)
            -- Match the already validated Recommendations hover lifecycle.
            -- A managed tooltip must be initialized on the first hover,
            -- rather than waiting for a Shift-triggered tooltip refresh.
            if GameTooltip:IsShown() then GameTooltip:Hide() end
            GameTooltip:ClearLines()
            GameTooltip.__WGRLineAdded=false
            GameTooltip.__WGRIgnoredItemLink=nil
            if WGRShowGearFinderLocator then
                WGRShowGearFinderLocator(item.source,item.bagID,item.slotID,item.itemLink)
            end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            if type(item.bagID)=='number' and type(item.slotID)=='number'
                and C_Container and C_Container.GetContainerItemLink
                and C_Container.GetContainerItemLink(item.bagID,item.slotID)==item.itemLink
                and GameTooltip.SetBagItem then
                GameTooltip:SetBagItem(item.bagID,item.slotID)
            else
                GameTooltip:SetHyperlink(item.itemLink)
            end
            -- Blizzard may reset per-tooltip state during SetBagItem or
            -- SetHyperlink. Set managed AFTER those calls, just as Gear Finder
            -- Recommendations does.
            GameTooltip.__WGRGearFinderManaged=true
            local mode,overrideRecord
            if WGRStorageCleanupGetCopyMark and item.bagID~=nil then
                mode,overrideRecord=WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source)
            end
            if mode=='KEEP' then
                GameTooltip:AddLine('|TInterface\\AddOns\\WarboundGearRouter\\WBGRKeepLock:18:18:0:0|t WBGR: KEEP (Manual Override)',.35,1,.45)
                GameTooltip:AddLine('Protected from automatic disposal',.8,.8,.8)
            elseif mode=='DISPOSE' then
                GameTooltip:AddLine('|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14|t WBGR: DISPOSE ('..
                    (WGRStorageCleanupDisposeReasonLabel and WGRStorageCleanupDisposeReasonLabel(overrideRecord) or 'Manual Override')..')',.68,.68,.68)
                GameTooltip:AddLine('Holder routing suspended for this copy',.8,.8,.8)
            end
            if WGRStorageCleanupRetentionBonusSummary then
                local bonus,bonusError=WGRStorageCleanupRetentionBonusSummary(item)
                if bonus then
                    GameTooltip:AddLine('WBGR retention bonuses: '..bonus,.45,.85,1)
                elseif bonusError then
                    GameTooltip:AddLine('WBGR retention bonuses: '..bonusError,1,.7,.25)
                end
            end
            GameTooltip:Show()
            -- Reuse normal routing's existing tooltip presentation. It adds
            -- the WBGR decision immediately; Shift may still expand details.
            if WGRRenderRecommendationForItemTooltip and not
                (WGRStorageCleanupIsDisposeCopy and item.bagID~=nil and
                WGRStorageCleanupIsDisposeCopy(item.bagID,item.slotID,item.itemLink,item.source)) then
                WGRRenderRecommendationForItemTooltip(GameTooltip,item.itemLink,{
                    source=item.source,
                    classification=item.recommendation and item.recommendation.classification,
                })
            end
        end
        ico.WGRShowTooltip=ShowCleanupItemTooltip
        ico:SetScript("OnEnter",ShowCleanupItemTooltip)
        ico:SetScript("OnLeave",function()
            if WGRHideGearFinderLocator then WGRHideGearFinderLocator() end
            GameTooltip.__WGRGearFinderManaged=nil
            GameTooltip:Hide()
        end)
        -- v0.68j: Optional copy-specific context menu in the full Cleanup
        -- list. No action is shown for closed/unobservable banks or shared
        -- Warbank copy groups; manual status always requires a LIVE GUID.
        ico:RegisterForClicks('LeftButtonUp','RightButtonUp')
        ico:SetScript('OnClick',function(self,mouseButton)
            if mouseButton~='RightButton' or not (MenuUtil and MenuUtil.CreateContextMenu)
                or not settings.enabled or item.bagID==nil or item.slotID==nil
                or not (item.source=='BAGS' or item.source=='PERSONAL_BANK' or item.source=='WARBAND_BANK') then return end
            OverrideContextMenu(self,item.bagID,item.slotID,item.itemLink,
                OverrideChanged)
        end)
        local name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        name:SetPoint("LEFT",ico,"RIGHT",6,0);name:SetWidth(265);name:SetJustifyH("LEFT");name:SetText(item.itemLink)
        local ilvl=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        ilvl:SetPoint("LEFT",row,"LEFT",300,0);ilvl:SetWidth(57);ilvl:SetText("ilvl "..tostring(item.itemLevel))
        local loc=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        loc:SetPoint("LEFT",row,"LEFT",365,0);loc:SetWidth(38)
        -- The physical source is authoritative for the visible location.
        -- `item.location` may be retained from an earlier account-audit copy
        -- after a manual BAG/PBK/WBK relocation, while `item.source` has
        -- already been remapped to the live container. Never show those two
        -- states disagreeing in the Cleanup row.
        local displayLocation=item.source=="BAGS" and "BAG"
            or (item.source=="PERSONAL_BANK" and "PBK")
            or (item.source=="WARBAND_BANK" and "WBK")
            or item.location or "?"
        loc:SetText(displayLocation)
        local reason=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        reason:SetPoint("LEFT",row,"LEFT",405,0);reason:SetWidth(isSurplus and 165 or 300);reason:SetJustifyH("LEFT")
        local stagedExplanation='Staged for disposal (original KEEP protected)'
        if isStaged and transferSession then
            for _,original in ipairs(transferSession.surplus) do
                if PhysicalKey(original)==item.cleanupOriginKey then
                    if original.source==item.source then
                        stagedExplanation='Returned to storage (KEEP protected until batch ends)'
                    end
                    break
                end
            end
        end
        reason:SetText(isStaged and stagedExplanation
            or (isSurplus and SurplusInstruction(item) or (item.cleanupReason or "")))
        if isSurplus and not isStaged and not transferSession and
            (item.source=='BAGS' or item.source=='PERSONAL_BANK' or item.source=='WARBAND_BANK') and
            type(item.bagID)=='number' and type(item.slotID)=='number' then
            local mark=CreateFrame('Button',nil,row,'UIPanelButtonTemplate')
            mark:SetSize(94,21);mark:SetPoint('RIGHT',row,'RIGHT',-117,0)
            local currentMode=WGRStorageCleanupGetCopyMark and
                WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source)
            mark:SetText(currentMode=='DISPOSE' and 'Undispose' or 'Mark DISPOSE')
            -- Per-item KEEP/DISPOSE is an explicit manual user override,
            -- independent of whether the displayed Storage Cleanup audit is stale.
            -- A stale audit may not authorize scan-derived BULK disposal (Mark All),
            -- but the user may still manually Dispose/Undispose this exact physical
            -- copy at any time. Manual KEEP remains mutually exclusive with DISPOSE.
            if currentMode=='KEEP' then
                mark:Disable()
            end
            mark:SetScript('OnClick',function()
                if cleanupTransferBusy or transferSession then return end
                local mode=WGRStorageCleanupGetCopyMark and
                    WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source)
                local ok,why
                if mode=='DISPOSE' then
                    ok,why=WGRStorageCleanupClearCopyOverride(item.bagID,item.slotID,'DISPOSE',item.source)
                elseif mode~='KEEP' then
                    ok,why=WGRStorageCleanupSetCopyMark(item.bagID,item.slotID,'DISPOSE','MANUAL',nil,nil,item.source)
                end
                if not ok then print('|cffffaa00WBGR:|r '..tostring(why or 'Item cannot be marked')) end
                if ok then OverrideChanged(mode=='DISPOSE',mark) end
            end)
            rows[#rows+1]=mark
        end
        if isSurplus and item.source~="BAGS" then
            local get=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
            get:SetSize(82,21);get:SetPoint("RIGHT",row,"RIGHT",-29,0);get:SetText("Get")
            -- Normal CLEAN UP movement is no longer a frozen cleanup batch.
            -- It is just a physical move of the exact verified row. The user
            -- can then KEEP/DISPOSE (or leave normal routing) independently.
            -- Legacy staged rows still use the protected batch mover.
            if transferSession and not isStaged then get:Disable() end
            get:SetScript("OnClick",function()
                if isStaged then
                    MoveVerified({item},"BAGS",true)
                else
                    MoveCleanupDirect({item},"BAGS")
                end
            end)
        end
        rows[#rows+1]=row
        return y+30
    end
    local function RemapAccountAuditPhysicalCopy(oldKey,live)
        if not accountAudit or not oldKey or not live then return end
        local function RemapItem(item)
            if type(item)~='table' or AccountItemKey(item)~=oldKey then return false end
            item.bagID=live.bagID
            item.slotID=live.slotID
            item.source=live.source
            item.location=live.location
            if live.guid then item.guid=live.guid end
            return true
        end
        for _,field in ipairs({'possible','verifiedPossible','retained'}) do
            for _,item in ipairs(accountAudit[field] or {}) do RemapItem(item) end
        end
        for _,entry in ipairs(accountAudit.uncertain or {}) do
            if entry and entry.item then RemapItem(entry.item) end
        end
        local newKey=table.concat({tostring(live.source),tostring(live.bagID),
            tostring(live.slotID),tostring(live.itemLink)},':')
        for _,entry in ipairs(accountAudit.evidence or {}) do
            if entry and entry.candidateKey==oldKey then entry.candidateKey=newKey end
        end
    end

    local cleanupVisibleAuditRefreshToken=0
    local function ScheduleCleanupVisibleAuditRefresh(delay)
        cleanupVisibleAuditRefreshToken=cleanupVisibleAuditRefreshToken+1
        local token=cleanupVisibleAuditRefreshToken
        local function Refresh()
            if token~=cleanupVisibleAuditRefreshToken then return end
            if panel and panel.IsShown and panel:IsShown() and Render then Render(true) end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(delay or 0.06,Refresh)
        else
            Refresh()
        end
    end

    local function RemapDisplayedPhysicalCopy(oldKey,live)
        if not oldKey or not live then return false end
        local changed=false
        local function RemapList(list)
            for _,entry in ipairs(list or {}) do
                if AccountItemKey(entry)==oldKey then
                    entry.source=live.source
                    entry.bagID=live.bagID
                    entry.slotID=live.slotID
                    entry.location=live.location
                    if live.guid then entry.guid=live.guid end
                    changed=true
                end
            end
        end
        RemapList(displayedKeep)
        RemapList(displayedSurplus)
        RemapList(displayedReview)
        RemapList(displayedPhysicalItems)
        RemapAccountAuditPhysicalCopy(oldKey,live)
        return changed
    end

    -- v0.72av: manual drag/drop override reconciliation lives in
    -- StorageCleanup.lua because it owns the persistent physical-copy marks.
    -- Once that code proves old GUID -> new GUID, mirror the same exact move
    -- into this session's displayed manual audit so the row location and move
    -- buttons remain usable without a rescan. The audit stays stale for any
    -- NEW disposal authorization; this callback is presentation-only.
    WGRStorageCleanupNotifyManualOverrideMoved=function(oldItem,newItem,oldGUID,newGUID)
        if type(oldItem)~='table' or type(newItem)~='table' then return end
        local oldKey=AccountItemKey(oldItem)
        if not oldKey then return end
        local source=newItem.source
        if source=='BAG' then source='BAGS' end
        local locationMap={BAGS='BAG',PERSONAL_BANK='PBK',WARBAND_BANK='WBK'}
        local live={
            source=source,bagID=newItem.bagID,slotID=newItem.slotID,
            itemLink=newItem.itemLink or oldItem.itemLink,
            location=newItem.location or locationMap[source] or '?',guid=newGUID,
        }
        if live.source==nil or live.bagID==nil or live.slotID==nil or not live.itemLink then return end
        if RemapDisplayedPhysicalCopy(oldKey,live) then
            FlagCleanupNeedsManualRescan('Inventory moved; explicit Rescan required')
            -- v0.72aw: row location changes are cheap in memory; batch the
            -- actual Cleanup redraw so a burst of manual drags does not rebuild
            -- the full list once per item.
            ScheduleCleanupVisibleAuditRefresh(0.06)
        end
    end

    -- v0.72aq: Normal Storage Cleanup movement is a convenience operation,
    -- not part of disposal authorization and not a frozen/batch transaction.
    -- The completed manual scan decides CLEAN UP; explicit KEEP/DISPOSE is the
    -- durable user override. Moving an item only makes the displayed audit
    -- stale until the user chooses to Rescan Inventory.
    MoveCleanupDirect=function(records,destination)
        if cleanupTransferBusy or transferSession or not settings.enabled then return end
        if not records or #records==0 then return end
        local approved={}
        for _,item in ipairs(displayedSurplus or {}) do
            local key=PhysicalKey(item)
            if key then approved[key]=item end
        end
        local sourceRecords,seen,sourceGUIDs={},{},{}
        for _,requested in ipairs(records) do
            if #sourceRecords>=20 then break end
            local key=PhysicalKey(requested)
            local current=key and approved[key]
            -- A stale displayed row is harmless here: simply skip it. Never
            -- move a different item merely because it occupies an old slot.
            if current and not seen[key] and current.source~=destination and SameSourceItem(current) then
                seen[key]=true
                sourceRecords[#sourceRecords+1]=current
                if WGRStorageCleanupGetPhysicalCopyGUID then
                    local guid=WGRStorageCleanupGetPhysicalCopyGUID(
                        current.bagID,current.slotID,current.itemLink)
                    if guid then
                        local sourceKey=table.concat({tostring(current.source),tostring(current.bagID),
                            tostring(current.slotID),tostring(current.itemLink)},':')
                        sourceGUIDs[sourceKey]=guid
                    end
                end
            end
        end
        if #sourceRecords==0 then
            print('|cffffaa00WBGR:|r No listed CLEAN UP items are still in those source slots. Rescan when ready.')
            return
        end
        if WGRStorageCleanupPrimeManualOverrideMovementSnapshot then
            WGRStorageCleanupPrimeManualOverrideMovementSnapshot()
        end
        cleanupTransferBusy=true
        local moveResult=WGRStorageCleanupMoveRecords(sourceRecords,destination)
        cleanupTransferBusy=false

        -- Movement never proves or changes the CLEAN UP decision. Preserve the
        -- displayed rows, but require one explicit Rescan before NEW disposal
        -- authorizations because supply locations may have changed. Existing
        -- manual KEEP/DISPOSE overrides remain active.
        FlagCleanupNeedsManualRescan('Inventory moved; explicit Rescan required')

        -- v0.72ar: the move manifest is NOT cleanup authorization; it is only
        -- presentation state from the ordinary Gear Finder mover. Keep the
        -- already-displayed CLEAN UP row synchronized with its successful
        -- destination so the user can continue moving the same physical copy
        -- BAG <-> PBK <-> WBK without rescanning after every move. The audit
        -- remains stale for NEW DISPOSE decisions until an explicit Rescan.
        local manifest=type(moveResult)=='table' and moveResult.manifest or nil
        if type(manifest)=='table' and #manifest>0 then
            local destinationLocation={BAGS='BAG',PERSONAL_BANK='PBK',WARBAND_BANK='WBK'}
            for _,move in ipairs(manifest) do
                if move and move.success and move.itemLink and move.source~=nil
                    and move.sourceBagID~=nil and move.sourceSlotID~=nil
                    and move.destination and move.targetBagID~=nil and move.targetSlotID~=nil then
                    local oldKey=table.concat({tostring(move.source),tostring(move.sourceBagID),
                        tostring(move.sourceSlotID),tostring(move.itemLink)},':')
                    local live={
                        source=move.destination,bagID=move.targetBagID,slotID=move.targetSlotID,
                        itemLink=move.itemLink,location=destinationLocation[move.destination] or '?',
                    }
                    RemapDisplayedPhysicalCopy(oldKey,live)
                end
            end
        end

        -- WBK can expose a new GUID for the same physical copy. Gear Finder's
        -- ordinary movers now report the exact target slot they chose. Use that
        -- information only to carry an already-existing MANUAL KEEP/DISPOSE
        -- override; it is never used to authorize disposal or validate the move.
        if type(manifest)=='table' and #manifest>0 and WGRStorageCleanupTransferManualOverrideByGUID then
            local pending={}
            for _,move in ipairs(manifest) do
                if move and move.success and move.itemLink and move.source~=nil
                    and move.sourceBagID~=nil and move.sourceSlotID~=nil
                    and move.targetBagID~=nil and move.targetSlotID~=nil then
                    local sourceKey=table.concat({tostring(move.source),tostring(move.sourceBagID),
                        tostring(move.sourceSlotID),tostring(move.itemLink)},':')
                    local sourceGUID=sourceGUIDs[sourceKey]
                    if sourceGUID then pending[#pending+1]={guid=sourceGUID,move=move} end
                end
            end
            local delays={0.20,0.55,1.00}
            local function Carry(attempt)
                local remaining={}
                for _,entry in ipairs(pending) do
                    local ok=WGRStorageCleanupTransferManualOverrideByGUID(
                        entry.guid,entry.move.targetBagID,entry.move.targetSlotID,
                        entry.move.itemLink,true,entry.move.destination)
                    if not ok then remaining[#remaining+1]=entry end
                end
                pending=remaining
                if #pending>0 and attempt<#delays and C_Timer and C_Timer.After then
                    C_Timer.After(delays[attempt+1],function() Carry(attempt+1) end)
                else
                    if RefreshBagnonCleanupOverlays then RefreshBagnonCleanupOverlays() end
                    if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.05) end
                    if WGRMailRefreshCurrentTodoSnapshot then
                        WGRMailRefreshCurrentTodoSnapshot(true,true)
                    elseif WGRRefreshTodoPage then WGRRefreshTodoPage() end
                    -- The initial post-move redraw can occur before a WBK GUID
                    -- change has finished carrying the manual override. Redraw
                    -- again after the carry settles so the row immediately
                    -- exposes Undispose/Unkeep while the audit remains stale.
                    if Render then Render(true) end
                end
            end
            if #pending>0 and C_Timer and C_Timer.After then
                C_Timer.After(delays[1],function() Carry(1) end)
            elseif #pending>0 then Carry(1) end
        end
        -- v0.72at: the ordinary mover may report success before WoW exposes
        -- the destination slot to a same-frame GetContainerItem* read. The row
        -- location is already remapped from the mover manifest, but its manual
        -- KEEP/DISPOSE button must be redrawn again after the inventory UI
        -- settles. These are display-only refreshes: they do not validate the
        -- move, change the manual audit, or authorize new cleanup decisions.
        if type(manifest)=='table' and #manifest>0 and C_Timer and C_Timer.After then
            for _,delay in ipairs({0.15,0.45,0.90}) do
                C_Timer.After(delay,function()
                    if panel and panel.IsShown and panel:IsShown() and Render then
                        Render(true)
                    end
                end)
            end
        end
        Render(true)
    end

    local function ConfirmCleanupMove(records,destination,fromStaged)
        if not records or #records==0 then return end
        StaticPopupDialogs.WGR_CONFIRM_STORAGE_CLEANUP_MOVE = StaticPopupDialogs.WGR_CONFIRM_STORAGE_CLEANUP_MOVE or {
            text="Move up to 20 listed CLEAN UP items to %s? This only moves items; KEEP/DISPOSE overrides are unchanged.",
            button1=YES,button2=NO,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
            OnAccept=function(_,data)
                if data and data.destination and data.records then
                    if data.fromStaged then
                        MoveVerified(data.records,data.destination,true)
                    else
                        MoveCleanupDirect(data.records,data.destination)
                    end
                end
            end,
        }
        local label=destination=='BAGS' and 'Bags' or
            (destination=='WARBAND_BANK' and 'Warband Bank' or 'Personal Bank')
        StaticPopup_Show('WGR_CONFIRM_STORAGE_CLEANUP_MOVE',label,nil,
            {records=records,destination=destination,fromStaged=fromStaged})
    end
    content.WGRAddPrimaryCleanupAction=function(surplus,y,pbk,wbk)
        if not surplus or #surplus==0 then return y end
        local selected={}
        for _,item in ipairs(surplus or {}) do
            local accessible=(item.source=='PERSONAL_BANK' and pbk)
                or (item.source=='WARBAND_BANK' and wbk)
            if accessible and #selected<20 then selected[#selected+1]=item end
        end
        local button=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
        button:SetSize(350,25);button:SetPoint('TOPLEFT',content,'TOPLEFT',0,-y)
        button:SetText('Prepare '..#selected..' for Disposal ('..#(surplus or {})..' extra)')
        if #selected==0 or (transferSession and transferSession.unverified)
            or (transferSession and transferSession.crosscheck) then button:Disable() end
        button:SetScript('OnClick',function()
            ConfirmCleanupMove(selected,'BAGS',false)
        end)
        rows[#rows+1]=button
        local help=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        help:SetPoint('LEFT',button,'RIGHT',10,0);help:SetWidth(410);help:SetJustifyH('LEFT')
        help:SetText(#selected>0
            and 'Moves verified extra gear to Bags only. You still choose when/how to dispose of it.'
            or 'Open the bank containing CLEAN UP gear to prepare it for disposal.')
        help:SetTextColor(0.72,0.72,0.72)
        rows[#rows+1]=help
        return y+32
    end
    local function AddBulkMovement(surplus,y,pbk,wbk,fromStaged,skipBags)
        local actions={
            {text="Bags",destination="BAGS"},
            {text="Warbank",destination="WARBAND_BANK"},
            {text="Personal Bank",destination="PERSONAL_BANK"},
        }
        local shown=0
        for index,action in ipairs(actions) do
            -- Freeze the destination per rendered button. Do not leave the
            -- click closure dependent on the generic-for control variable.
            local destination=action.destination
            local actionText=action.text
            if skipBags and destination=="BAGS" then
                -- Guided mode already exposes Prepare for Disposal as the Bags action.
            else
            local selected={}
            for _,item in ipairs(surplus) do
                if (destination=="BAGS" and item.source~="BAGS")
                    or (destination=="WARBAND_BANK" and item.source~="WARBAND_BANK")
                    or (destination=="PERSONAL_BANK" and item.source~="PERSONAL_BANK") then
                    selected[#selected+1]=item
                end
            end
            local button=CreateFrame("Button",nil,content,"UIPanelButtonTemplate")
            button:SetSize(235,23)
            button:SetPoint("TOPLEFT",content,"TOPLEFT",shown*244,-y)
            if fromStaged then
                local shortDest=destination=="WARBAND_BANK" and "WBK"
                    or (destination=="PERSONAL_BANK" and "PBK" or "Bags")
                button:SetText("Move "..math.min(#selected,20).." -> "..shortDest.." ("..#selected..")")
            else
                button:SetText("Move to "..actionText.." ("..#selected..")")
            end
            local bankNeeded=(destination=="WARBAND_BANK" and not wbk)
                or (destination=="PERSONAL_BANK" and not pbk)
            if #selected==0 or bankNeeded or (transferSession and transferSession.unverified)
                or (transferSession and transferSession.crosscheck and not fromStaged) then
                button:Disable()
            end
            button:SetScript('OnClick',function()
                -- v0.72bb: normal Cleanup movement is convenience-only. The
                -- visible row list can be remapped asynchronously after manual
                -- moves / override changes, so rebuild candidates at click time
                -- instead of trusting the render-time slot snapshot. Legacy
                -- staged/Advanced movement keeps its frozen selected list.
                local clickRecords=selected
                if not fromStaged then
                    clickRecords={}
                    for _,item in ipairs(displayedSurplus or {}) do
                        if item.source~=destination and SameSourceItem(item) then
                            clickRecords[#clickRecords+1]=item
                        end
                    end
                    if #clickRecords==0 then
                        print('|cffffaa00WBGR:|r No current CLEAN UP items can be moved to '..
                            tostring(actionText)..'. Rescan if the list is out of date.')
                        if Render then Render(true) end
                        return
                    end
                end
                ConfirmCleanupMove(clickRecords,destination,fromStaged)
            end)
            rows[#rows+1]=button
            shown=shown+1
            end
        end
        return shown>0 and (y+32) or y
    end
    -- v0.68o: separate, explicit disposal-mail action for marked bag copies.
    -- The existing KEEP/SURPLUS staging buttons remain unchanged. A selected
    -- 'Vendor' or 'Disenchant' suggestion never initiates either action.
    local function AddDisposeMailActions(y)
        if not settings.enabled or not WGRStorageCleanupDisposalMailCandidates then return y end
        local defs={
            {binding='WARBAND',recipient=settings.warboundRecipient,label='Warbound',x=0},
            {binding='BOE',recipient=settings.boeRecipient,label='BoE',x=330},
        }
        local visible={}
        for _,def in ipairs(defs) do
            local entries=WGRStorageCleanupDisposalMailCandidates(def.binding)
            if #entries>0 then def.count=#entries;visible[#visible+1]=def end
        end
        if #visible==0 then return y end
        local info=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        info:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y)
        info:SetText('DISPOSE mail: only marked copies in Bags; review the draft and press Send yourself.')
        rows[#rows+1]=info;y=y+24
        for _,def in ipairs(visible) do
            local button=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
            button:SetSize(318,23)
            button:SetPoint('TOPLEFT',content,'TOPLEFT',def.x,-y)
            button:SetText('Prepare DISPOSE Mail ('..math.min(def.count,12)..') '..def.label..' -> '..
                tostring(def.recipient=='CURRENT' and 'Choose recipient' or def.recipient))
            if def.recipient=='CURRENT' or not (WGRMail and WGRMail.mailboxOpen)
                or not WGRMailPrepareDisposalDraft then button:Disable() end
            button:SetScript('OnClick',function()
                local ok,reason=WGRMailPrepareDisposalDraft(def.recipient,def.binding)
                if not ok then print('|cffffaa00WBGR:|r '..tostring(reason)) end
            end)
            rows[#rows+1]=button
        end
        return y+32
    end

    -- Return-to-origin is useful after staging a mixed PBK/WBK batch in
    -- Bags: do not force the user to hand-pick 23 PBK and 4 WBK pieces.
    -- Origin selects which FROZEN staged copies to return, never the live
    -- planner or another indistinguishable KEEP copy.
    local function AddReturnStaged(y,pbk,wbk)
        local session=transferSession
        if not session then return y end
        local groups={PERSONAL_BANK={},WARBAND_BANK={}}
        for _,original in ipairs(session.surplus) do
            local origin=PhysicalKey(original)
            local stage=session.staged[origin]
            if groups[original.source] and stage and stage.source~=original.source then
                groups[original.source][#groups[original.source]+1]=stage
            end
        end
        local defs={
            {dest='PERSONAL_BANK',label='PBK',x=0,ready=pbk},
            {dest='WARBAND_BANK',label='WBK',x=244,ready=wbk},
        }
        local shown=0
        for _,def in ipairs(defs) do
            local entries=groups[def.dest]
            if #entries>0 then
                local button=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
                button:SetSize(235,23)
                button:SetPoint('TOPLEFT',content,'TOPLEFT',shown*244,-y)
                button:SetText('Return '..math.min(#entries,20)..' -> '..def.label..' ('..#entries..')')
                if not def.ready or session.unverified then button:Disable() end
                button:SetScript('OnClick',function()
                    ConfirmCleanupMove(entries,def.dest,true)
                end)
                rows[#rows+1]=button
                shown=shown+1
            end
        end
        return shown>0 and (y+31) or y
    end
    -- snapshotOnly is exclusively for passive inventory UI notifications.
    -- Keep the last displayed KEEP/SURPLUS/REVIEW plan (or the frozen batch)
    -- while rebuilding the expanded Diagnostics list from persisted snapshots.
    Render=function(snapshotOnly)
        snapshotOnly=(snapshotOnly == true)
        ClearRows()
        master:SetChecked(settings.enabled)
        content.WGRAdvancedToggle:SetText(content.WGRShowAdvancedCleanup and 'Hide Advanced' or 'Advanced')
        -- Disabled mode should show only the opt-in control and OFF explanation.
        -- Enabled mode reveals its scan/action cues and the linked-detail note.
        if settings.enabled then
            panel.WGRCleanupInstructions:Show()
            if accountChecking then
                panel.WGRCleanupInstructions:SetText("Scanning storage...")
            elseif cleanupNeedsManualRescan then
                panel.WGRCleanupInstructions:SetText("Inventory changed. Rescan when ready.")
            elseif accountAudit or hasDisplayedAudit then
                panel.WGRCleanupInstructions:SetText("Storage scanned. Rescan as needed.")
            elseif refresh.WGRHasManualCleanupScan then
                panel.WGRCleanupInstructions:SetText("Scan incomplete. Retry when ready.")
            else
                panel.WGRCleanupInstructions:SetText("Start by scanning this character's inventory.")
            end
            content.WGRAdvancedToggle:Show()
            panel.WGRCleanupItemDetailNote:Show()
        else
            panel.WGRCleanupInstructions:Hide()
            content.WGRAdvancedToggle:Hide()
            panel.WGRCleanupItemDetailNote:Hide()
        end
        summary:ClearAllPoints()
        -- Cleanup recipient choices are part of the normal workflow, not
        -- diagnostics. Keep room for them in both guided and Advanced views.
        summary:SetPoint('TOPLEFT',content.WGRSettingsNote,'BOTTOMLEFT',-2,-72)
        summary:SetPoint('RIGHT',panel,'RIGHT',-3,0)
        if settings.enabled then
            refresh:Show()
            if transferSession then
                refresh:SetSize(166,22)
                refresh:SetText('Refresh Locations')
                if newAudit then
                    newAudit:SetSize(204,22)
                    newAudit:SetText('Finish Cleanup & Rescan')
                    if content.WGRShowAdvancedCleanup then newAudit:Show() else newAudit:Hide() end
                end
            else
                refresh:SetSize(150,24)
                refresh:SetText(refresh.WGRHasManualCleanupScan and 'Rescan Inventory' or 'Scan Inventory')
                if newAudit then newAudit:Hide() end
            end
        else
            refresh:Hide()
            if newAudit then newAudit:Hide() end
        end
        local settingControls={wrDrop,brDrop}
        -- Cleanup recipient choices are normal workflow controls.
        for _,control in ipairs(settingControls) do
            if control then
                if settings.enabled then control:Show() else control:Hide() end
            end
        end
        for _,control in ipairs({wrLabel,brLabel,content.WGRSettingsNote}) do
            if settings.enabled then control:Show() else control:Hide() end
        end
        if not settings.enabled then
            summary:SetText("Storage Cleanup OFF | WBGR routing and holder storage operate normally. Enable above to audit best-needed gear.")
            content:SetHeight(1)
            return
        end
        if WGRRoutingIsPaused and WGRRoutingIsPaused() then
            summary:SetText("WBGR is paused. Resume it for Storage Cleanup.")
            content:SetHeight(1)
            return
        end
        local current=UnitName("player") or "Current character"
        if WGRIsCharacterRemoved and WGRIsCharacterRemoved(current) then
            summary:SetText("Storage Cleanup unavailable on Removed characters.")
            content:SetHeight(1)
            return
        end
        -- Default guided view has no authoritative result until the user runs
        -- the explicit account-wide scan. Do not pre-populate NEEDS ATTENTION
        -- with local-only rows just because the panel was opened.
        if not transferSession and not content.WGRShowAdvancedCleanup
            and not refresh.WGRHasManualCleanupScan then
            local prePBK=WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
            local preWBK=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
            refresh:SetText('Scan Inventory')
            summary:SetFontObject(GameFontHighlightSmall)
            summary:SetJustifyH('LEFT')
            summary:SetText(string.format("Ready to scan | PBK %s | WBK %s",
                prePBK and "open" or "closed",preWBK and "open" or "closed"))
            content:SetHeight(1)
            return
        end
        if not snapshotOnly and WGRBeginRoutingEvaluationCache then
            WGRBeginRoutingEvaluationCache()
        end
        local keep,surplus,review,total,pbk,wbk,staged
        local accountWasFresh=accountAudit and ValidAccountAudit(displayedPhysicalItems)
        -- v0.72am: A completed manual audit remains visible after a passive
        -- mismatch or manual override clear.  The result is explicitly stale
        -- (new disposal decisions are disabled until Rescan), but a later
        -- ordinary Gear Finder repaint must not null the audit and collapse the
        -- Storage Cleanup page.  This is especially important for WBK moves,
        -- where SavedVariables/account-stock revisions can lag the physical
        -- relocation even though the user's completed audit is still useful as
        -- a review list.
        if not transferSession and cleanupNeedsManualRescan and hasDisplayedAudit then
            keep,surplus=displayedKeep,displayedSurplus
            review,total=displayedReview,displayedTotal
            pbk=WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
            wbk=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
            staged={}
        elseif transferSession then
            -- Fresh planning would steal the KEEP label from original duplicates
            -- after the SURPLUS copies are moved, so retain the batch snapshot.
            keep=transferSession.keep
            surplus=RemainingSurplus(transferSession)
            staged=StagedSurplus(transferSession)
            review=transferSession.review
            total=transferSession.total
            pbk=WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
            wbk=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
        elseif snapshotOnly and hasDisplayedAudit then
            -- v0.72ao: Snapshot-only redraws are DISPLAY-ONLY once the user has
            -- completed a manual audit.  During an explicit account check the
            -- old completed rows remain visible while accountAudit is
            -- temporarily nil; that CHECKING state is not itself stale and must
            -- not re-arm cleanupNeedsManualRescan.  Outside CHECKING, a stale
            -- inventory/account revision disables new disposal actions but
            -- never erases the visible KEEP/CLEAN UP/NEEDS ATTENTION result.
            keep,surplus=displayedKeep,displayedSurplus
            review,total=displayedReview,displayedTotal
            if accountAudit and ValidAccountAudit(displayedPhysicalItems) then
                keep,surplus,review=ApplyAccountClassification(
                    keep,surplus,review,displayedPhysicalItems,accountAudit)
                displayedKeep,displayedSurplus,displayedReview=keep,surplus,review
            elseif not accountChecking then
                FlagCleanupNeedsManualRescan('Completed audit is stale; explicit Rescan required')
            end
            -- Display CURRENT bank access even while the classifications are
            -- preserved from a previous open-bank scan.
            pbk=WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
            wbk=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
            staged={}
        else
            local started=debugprofilestop and debugprofilestop() or nil
            local physical
            keep,surplus,review,total,pbk,wbk,physical=WGRStorageCleanupAnalyze()
            if accountWasFresh and accountAudit and
                AccountPhysicalSignature(physical)==accountAudit.signature then
                keep,surplus,review=ApplyAccountClassification(
                    keep,surplus,review,physical,accountAudit)
                accountAuditRevision=WGRStorageCleanupGetInventoryRevision()
            else
                -- Local-only summaries are not authoritative/account-proven.
                accountAudit=nil
                keep,surplus,review=ApplyAccountClassification(
                    keep,surplus,review,physical,{})
            end
            if started then lastLocalAuditMs=debugprofilestop()-started end
            staged={}
            displayedKeep,displayedSurplus=keep,surplus
            displayedReview,displayedTotal,displayedPBK,displayedWBK=review,total,pbk,wbk
            displayedPhysicalItems=physical
            hasDisplayedAudit=true
        end
        -- v0.71d: Preserve the authoritative KEEP explanation as display-only
        -- snapshot metadata for Gather Gear / Gear Search drill-down. Never
        -- recalculate retention from those tabs and never persist transfer-state
        -- staging as a new retention decision.
        if not transferSession and accountAudit and displayedPhysicalItems
            and ValidAccountAudit(displayedPhysicalItems) then
            if WGRStorageCleanupUpdateAccountSnapshotRetentionReasons
                and accountAudit.retentionDetails then
                WGRStorageCleanupUpdateAccountSnapshotRetentionReasons(
                    accountAudit.retentionDetails)
            end
            if WGRStorageCleanupUpdateSnapshotRetentionReasons then
                WGRStorageCleanupUpdateSnapshotRetentionReasons(displayedPhysicalItems,keep)
            end
        end
        if not snapshotOnly and WGREndRoutingEvaluationCache then
            WGREndRoutingEvaluationCache()
        end
        if transferSession then
            local returned,inBags,otherBank=0,0,0
            for _,original in ipairs(transferSession.surplus) do
                local stage=transferSession.staged[PhysicalKey(original)]
                if stage then
                    if stage.source==original.source then returned=returned+1
                    elseif stage.source=='BAGS' then inBags=inBags+1
                    else otherBank=otherBank+1 end
                end
            end
            local tip
            if transferSession.unverified then
                tip='TRANSFER UNVERIFIED - no further moves'
            elseif #surplus==0 and inBags==0 and otherBank==0 then
                tip='Returned/finished - use Finish Batch & Recalculate'
            else
                tip='Finish moving or returning staged items before recalculating'
            end
            summary:SetText(string.format('CLEANUP BATCH ACTIVE | %d KEEP protected | %d still to prepare | %d READY TO DISPOSE | %d other storage | %d returned | %s',
                #keep,#surplus,inBags,otherBank,returned,tip))
        else
            local mode=accountChecking and 'ACCOUNT-WIDE CHECKING...'
                or (accountAudit and 'ACCOUNT CHECK COMPLETE'
                or 'LOCAL PREVIEW ONLY — Scan Inventory for account-wide verification')
            summary:SetFontObject(GameFontHighlightSmall)
            summary:SetJustifyH("LEFT")
            refresh:SetText(accountChecking and "Scanning..." or "Rescan Inventory")
            local summaryText=string.format("%s | %d items checked | KEEP %d | CLEAN UP %d | NEEDS ATTENTION %d | PBK %s | WBK %s",mode,total,#keep,#surplus,#review,pbk and "open" or "closed",wbk and "open" or "closed").."\nFuture-use gear only — immediate upgrades stay in Recommendations."
            if cleanupNeedsManualRescan then
                summaryText=summaryText.."\n|cffffcc00Inventory changed — Rescan Inventory when ready.|r"
            end
            summary:SetText(summaryText)
        end
        -- In guided mode, local-only classifications are implementation
        -- detail. While an explicit account check is running (or if it fails),
        -- show status only rather than presenting provisional rows as though
        -- the user must review them. Advanced retains the local preview.
        if not transferSession and not content.WGRShowAdvancedCleanup and not accountAudit then
            if accountChecking then
                refresh:SetText("Scanning...")
                summary:SetFontObject(GameFontNormal)
                summary:SetJustifyH("CENTER")
                summary:SetText(string.format("CHECKING ACCOUNT-WIDE GEAR...   PBK %s | WBK %s",
                    pbk and "open" or "closed",wbk and "open" or "closed"))
            else
                refresh:SetText("Retry Scan")
                summary:SetFontObject(GameFontNormal)
                summary:SetJustifyH("CENTER")
                summary:SetText(string.format("ACCOUNT CHECK NOT COMPLETE — Retry Scan Inventory.   PBK %s | WBK %s",
                    pbk and "open" or "closed",wbk and "open" or "closed"))
            end
            content:SetHeight(1)
            return
        end
        local y=0
        -- Manual Overrides are a searchable compact management view, not a
        -- second planner. Offline items are displayed by their recorded owner;
        -- clearing by GUID is allowed, but remote marking/moving is not.
        local overrides=WGRStorageCleanupListManualOverrides and
            WGRStorageCleanupListManualOverrides() or {}
        if content.WGRShowAdvancedCleanup then
            local heading=CreateFrame('Button',nil,content)
            heading:SetSize(780,25);heading:SetPoint('TOPLEFT',content,'TOPLEFT',0,-y)
            local label=heading:CreateFontString(nil,'OVERLAY','GameFontNormal')
            label:SetAllPoints();label:SetJustifyH('LEFT')
            label:SetText((showManualOverrides and '[-] ' or '[+] ')..
                'Manual Overrides ('..#overrides..')')
            heading:SetScript('OnClick',function()
                showManualOverrides=not showManualOverrides
                Render(true)
            end)
            rows[#rows+1]=heading;y=y+29
            if showManualOverrides then
                local showLabel=content:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
                showLabel:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y-5)
                showLabel:SetText('Show:')
                rows[#rows+1]=showLabel
                for _,filter in ipairs({{'ALL','All',61},{'KEEP','KEEP',169},{'DISPOSE','DISPOSE',277}}) do
                    local button=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
                    button:SetSize(102,22);button:SetPoint('TOPLEFT',content,'TOPLEFT',filter[3],-y)
                    button:SetText(filter[2])
                    button:SetEnabled(manualOverrideFilter~=filter[1])
                    button:SetScript('OnClick',function()
                        manualOverrideFilter=filter[1];Render(true)
                    end)
                    rows[#rows+1]=button
                end
                y=y+30
                local visible=0
                for _,record in ipairs(overrides) do
                    if manualOverrideFilter=='ALL' or manualOverrideFilter==record.mode then
                        visible=visible+1
                        local line=CreateFrame('Frame',nil,content)
                        line:SetSize(775,31);line:SetPoint('TOPLEFT',content,'TOPLEFT',2,-y)
                        local name=line:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                        name:SetPoint('TOPLEFT',line,'TOPLEFT',2,-2)
                        name:SetWidth(505);name:SetJustifyH('LEFT')
                        name:SetText((record.mode=='KEEP' and '|cff66ff88KEEP|r ' or '|cffaaaaaaDISPOSE|r ')..
                            tostring(record.link or 'Unknown item')..
                            (record.inactive and ' |cffffaa00(INACTIVE: tracking gap)|r' or ''))
                        local location=line:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                        location:SetPoint('BOTTOMLEFT',line,'BOTTOMLEFT',2,2)
                        location:SetWidth(625);location:SetJustifyH('LEFT')
                        location:SetText('Recorded owner: '..tostring(record.owner or '?')..
                            ' | last marked slot: '..tostring(record.lastBag or '?')..':'..
                            tostring(record.lastSlot or '?')..' (not live-verified)')
                        local clear=CreateFrame('Button',nil,line,'UIPanelButtonTemplate')
                        clear:SetSize(135,23);clear:SetPoint('RIGHT',line,'RIGHT',-3,0)
                        clear:SetText(record.mode=='KEEP' and 'Unkeep' or 'Undispose')
                        clear:SetScript('OnClick',function()
                            local ok,reason=WGRStorageCleanupClearSavedOverride(record.guid,record.mode)
                            if not ok then
                                print('|cffffaa00WBGR:|r Override unchanged: '..tostring(reason))
                            end
                            if ok then OverrideChanged(true) end
                        end)
                        rows[#rows+1]=line
                        y=y+33
                    end
                end
                if visible==0 then
                    local anchor=CreateFrame('Frame',nil,content)
                    anchor:SetPoint('TOPLEFT',content,'TOPLEFT',0,-y)
                    anchor:SetSize(780,19);rows[#rows+1]=anchor
                    local note=anchor:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                    note:SetPoint('LEFT',anchor,'LEFT',8,0)
                    note:SetText('No saved overrides in this filter.')
                    y=y+22
                end
                y=y+6
            end
        end
        for _,group in ipairs({{'KEEP',keep,0.25,1,0.45,false},{'SURPLUS',surplus,1,0.48,0.25,true},{'REVIEW',review,1,0.80,0.18,false}}) do
            if group[1]=='KEEP' and not content.WGRShowAdvancedCleanup then
                -- The retained count stays in the summary, details in Advanced.
            elseif group[1]=='REVIEW' and #group[2]==0 then
                -- Keep NEEDS ATTENTION in the account summary, but do not waste
                -- vertical space on an empty section.
            else
            local bySlot,labels={},{}
            for _,item in ipairs(group[2]) do
                local label=SlotSectionName(item)
                if not bySlot[label] then bySlot[label]={};labels[#labels+1]=label end
                bySlot[label][#bySlot[label]+1]=item
            end
            table.sort(labels)
            local controlLabels={}
            for _,label in ipairs(labels) do controlLabels[#controlLabels+1]=label end
            if group[1]=='SURPLUS' then
                local known={}
                for _,label in ipairs(controlLabels) do known[label]=true end
                for _,item in ipairs(staged) do
                    local label=SlotSectionName(item)
                    if not known[label] then controlLabels[#controlLabels+1]=label;known[label]=true end
                end
            end
            local show
            local headingCount=#group[2]
            if group[1]=='SURPLUS' then headingCount=headingCount+#staged end
            y,show=AddSection(group[1],headingCount,group[3],group[4],group[5],y,controlLabels)
            if show then
                y=content.WGRAddSectionHelp(group[1],y)
                if group[1]=='SURPLUS' and not transferSession then
                    local candidates={}
                    for _,item in ipairs(surplus) do
                        -- Mark All is scan-derived, so only rows carrying the exact
                        -- account-verified GUID from the completed audit qualify.
                        -- Individual manual Mark DISPOSE remains available even when
                        -- an old audit is stale.
                        if item.cleanupAccountVerifiedGUID and
                            (item.source=='BAGS' or item.source=='PERSONAL_BANK' or item.source=='WARBAND_BANK') and
                            type(item.bagID)=='number' and type(item.slotID)=='number' and
                            not (WGRStorageCleanupGetCopyMark and
                                WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source)) then
                            candidates[#candidates+1]=item
                        end
                    end
                    local bulk=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
                    bulk:SetSize(230,24);bulk:SetPoint('TOPLEFT',content,'TOPLEFT',2,-y)
                    bulk:SetText('Mark All for Disposal ('..#candidates..')')
                    if cleanupNeedsManualRescan then bulk:SetText('Rescan before Mark All') end
                    if #candidates==0 or cleanupTransferBusy or cleanupNeedsManualRescan then bulk:Disable() end
                    bulk:SetScript('OnClick',function()
                        if transferSession or cleanupTransferBusy then return end
                        -- Fail closed if the displayed account verification is stale
                        -- or any item moved since it was classified as surplus.
                        if not accountAudit or not ValidAccountAudit(displayedPhysicalItems) then
                            print('|cffffaa00WBGR:|r Scan Inventory again before marking.');return
                        end
                        local seen={}
                        for _,item in ipairs(candidates) do
                            local guid=WGRStorageCleanupGetPhysicalCopyGUID and
                                WGRStorageCleanupGetPhysicalCopyGUID(item.bagID,item.slotID,item.itemLink)
                            if not guid or not item.cleanupAccountVerifiedGUID or
                                tostring(guid)~=tostring(item.cleanupAccountVerifiedGUID) or seen[guid] or
                                (WGRStorageCleanupGetCopyMark and
                                 WGRStorageCleanupGetCopyMark(item.bagID,item.slotID,item.itemLink,item.source)) then
                                print('|cffffaa00WBGR:|r Item moved or already overridden; scan again.');return
                            end
                            seen[guid]=true
                        end
                        local done=0
                        for _,item in ipairs(candidates) do
                            local ok,why=WGRStorageCleanupSetCopyMark(
                                item.bagID,item.slotID,'DISPOSE','MANUAL',true,{
                                    link=item.itemLink,
                                    guid=item.cleanupAccountVerifiedGUID,
                                    recommendation=item.recommendation,
                                    source=item.source,
                                })
                            if not ok then
                                print('|cffffaa00WBGR:|r Mark All stopped: '..tostring(why));break
                            end
                            done=done+1
                            if WGRRefreshCopyOverlay then WGRRefreshCopyOverlay(item.bagID,item.slotID) end
                        end
                        if WGRScheduleGearFinderRefresh then WGRScheduleGearFinderRefresh(0.1) end
                        if WGRMailRefreshCurrentTodoSnapshot then WGRMailRefreshCurrentTodoSnapshot(true,true) end
                        OverrideChanged()
                    end)
                    rows[#rows+1]=bulk;y=y+29
                    local note=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                    note:SetPoint('TOPLEFT',content,'TOPLEFT',6,-y)
                    note:SetWidth(760);note:SetJustifyH('LEFT')
                    note:SetText('Live Bags, PBK, and open WBK copies can be marked directly. Manual DISPOSE overrides normal routing.')
                    rows[#rows+1]=note;y=y+22
                end
                if group[1]=='SURPLUS' then
                    -- CLEAN UP movement is an everyday action, not diagnostics.
                    -- Keep these controls visible in the normal view. The mover
                    -- still verifies exact physical transfers; existing manual
                    -- KEEP/DISPOSE overrides are preserved across WBK GUID changes.
                    y=AddBulkMovement(surplus,y,pbk,wbk,false,false)
                    if content.WGRShowAdvancedCleanup then
                        y=AddDisposeMailActions(y)
                    end
                end
                for _,label in ipairs(labels) do
                    local selected=bySlot[label]
                    local showSlot
                    y,showSlot=AddSlotSection(group[1],label,#selected,y)
                    if showSlot then
                        for index,item in ipairs(selected) do y=AddRow(item,index,y,group[6]) end
                    end
                    y=y+3
                end
                if group[1]=='SURPLUS' and #staged>0 then
                    local noticeFrame=CreateFrame('Frame',nil,content)
                    noticeFrame:SetSize(790,22)
                    noticeFrame:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y-4)
                    local notice=noticeFrame:CreateFontString(nil,'OVERLAY','GameFontNormal')
                    notice:SetAllPoints()
                    notice:SetJustifyH('LEFT')
                    local returned=0
                    for _,original in ipairs(transferSession.surplus) do
                        local item=transferSession.staged[PhysicalKey(original)]
                        if item and item.source==original.source then returned=returned+1 end
                    end
                    notice:SetText('READY TO DISPOSE ('..(#staged-returned)..') / RETURNED TO STORAGE ('..returned..') - KEEP protected')
                    rows[#rows+1]=noticeFrame
                    y=y+24
                    local stagedHelp=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                    stagedHelp:SetPoint('TOPLEFT',content,'TOPLEFT',8,-y)
                    stagedHelp:SetWidth(780);stagedHelp:SetJustifyH('LEFT')
                    stagedHelp:SetText('Sell or disenchant READY items manually. When they are gone, click Finish Cleanup & Rescan.')
                    stagedHelp:SetTextColor(0.72,0.72,0.72)
                    rows[#rows+1]=stagedHelp
                    y=y+23
                    if content.WGRShowAdvancedCleanup then y=AddBulkMovement(staged,y,pbk,wbk,true) end
                    y=AddReturnStaged(y,pbk,wbk)
                    local stagedSlots,stagedLabels={},{}
                    for _,item in ipairs(staged) do
                        local label=SlotSectionName(item)
                        if not stagedSlots[label] then stagedSlots[label]={};stagedLabels[#stagedLabels+1]=label end
                        stagedSlots[label][#stagedSlots[label]+1]=item
                    end
                    table.sort(stagedLabels)
                    for _,label in ipairs(stagedLabels) do
                        local section=stagedSlots[label]
                        local showSlot
                        y,showSlot=AddSlotSection('STAGED',label,#section,y)
                        if showSlot then
                            for index,item in ipairs(section) do y=AddRow(item,index,y,true,true) end
                        end
                        y=y+3
                    end
                end
            end
            y=y+8
            end -- KEEP is an Advanced-only detail.
        end
        -- The manual account preview remains a read-only second opinion.
        -- Only the INTERSECTION with the live local SURPLUS audit may be
        -- staged using the existing frozen-batch mover; never use account
        -- results alone to decide disposal or to move an original KEEP.
        if content.WGRShowAdvancedCleanup then
            local troubleshoot=CreateFrame('Button',nil,content)
            troubleshoot:SetSize(790,23);troubleshoot:SetPoint('TOPLEFT',content,'TOPLEFT',0,-y-4)
            local troubleshootText=troubleshoot:CreateFontString(nil,'OVERLAY','GameFontHighlight')
            troubleshootText:SetPoint('LEFT',troubleshoot,'LEFT',1,0)
            troubleshootText:SetText((content.WGRShowTroubleshooting and '[-] ' or '[+] ')..'Diagnostics & Troubleshooting')
            troubleshoot:SetScript('OnClick',function()
                content.WGRShowTroubleshooting=not content.WGRShowTroubleshooting
                Render(true)
            end)
            rows[#rows+1]=troubleshoot
            y=y+27
            if content.WGRShowTroubleshooting then
                y=WGRStorageCleanupDrawSupplyEvidence(content,rows,y+2,accountAudit)
                y=AccountRetentionPreview(y+2)
            end
        end
        -- v0.68c: continue the SAME original cross-checked category during
        -- Frozen Batch. Do not rerun the account planner or permit another
        -- category/source to join this protected batch.
        if content.WGRShowAdvancedCleanup and content.WGRShowTroubleshooting and showAccountPreview and transferSession and transferSession.crosscheck then
            local session=transferSession
            local frozen=session.crosscheck
            local remaining=WGRStorageCleanupFrozenCrosscheckPending(session)
            local available={}
            for _,item in ipairs(remaining) do
                if SameSourceItem(item) then available[#available+1]=item end
            end
            local toStage={}
            for i=1,math.min(20,#available) do toStage[#toStage+1]=available[i] end
            local owner=frozen.source=='PERSONAL_BANK' and (UnitName('player') or 'Current character')
                ..' / Personal Bank' or 'Shared Warbank'
            local header=CreateFrame('Frame',nil,content)
            header:SetSize(790,42);header:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local title=header:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            title:SetAllPoints();title:SetJustifyH('LEFT')
            title:SetText('Frozen cross-check: '..frozen.category..' / '..owner..
                ' | '..#remaining..' approved pending; '..#toStage..' listed next (max 20).'..
                (session.unverified and '  UNVERIFIED: movements locked.' or ''))
            rows[#rows+1]=header
            y=y+47
            for i,item in ipairs(toStage) do
                local line=CreateFrame('Frame',nil,content)
                line:SetSize(790,20);line:SetPoint('TOPLEFT',content,'TOPLEFT',15,-y)
                local value=line:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                value:SetAllPoints();value:SetJustifyH('LEFT')
                value:SetText(tostring(i)..'. '..tostring(item.itemLink)..
                    ' | ilvl '..tostring(item.itemLevel or '?')..' | '..tostring(item.source)..
                    ' bag '..tostring(item.bagID)..' slot '..tostring(item.slotID))
                rows[#rows+1]=line
                y=y+21
            end
            local function StageMore(n)
                if cleanupTransferBusy or transferSession~=session or session.unverified
                    or not settings.enabled then return end
                local exact=WGRStorageCleanupFrozenCrosscheckPending(session)
                local ready={}
                for _,item in ipairs(exact) do
                    if SameSourceItem(item) then ready[#ready+1]=item end
                    if #ready>=20 then break end
                end
                local selected={}
                for i=1,math.min(n,#toStage) do
                    if not ready[i] or PhysicalKey(ready[i])~=PhysicalKey(toStage[i])
                        or not SameSourceItem(toStage[i]) then
                        print('|cffffaa00WBGR:|r Frozen source selection changed; nothing staged.')
                        return
                    end
                    selected[#selected+1]=toStage[i]
                end
                if #selected==0 then return end
                StaticPopupDialogs.WGR_CONFIRM_STORAGE_CLEANUP_MORE={
                    text='Stage %s additional frozen cross-checked copies to Bags? Only the displayed pending copies will move.',
                    button1=YES,button2=NO,timeout=0,whileDead=true,hideOnEscape=true,
                    preferredIndex=3,
                    OnAccept=function(_,data)
                        if not data or transferSession~=data.session or cleanupTransferBusy
                            or data.session.unverified or not settings.enabled
                            or UnitName('player')~=data.owner then return end
                        local pending=WGRStorageCleanupFrozenCrosscheckPending(data.session)
                        local visible={}
                        for _,item in ipairs(pending) do
                            if SameSourceItem(item) then visible[#visible+1]=item end
                            if #visible>=20 then break end
                        end
                        for i,item in ipairs(data.records) do
                            if not visible[i] or PhysicalKey(visible[i])~=PhysicalKey(item)
                                or not SameSourceItem(item) then
                                print('|cffffaa00WBGR:|r Frozen selection changed before confirmation; nothing moved.')
                                return
                            end
                        end
                        MoveVerified(data.records,'BAGS',false)
                    end,
                }
                StaticPopup_Show('WGR_CONFIRM_STORAGE_CLEANUP_MORE',
                    tostring(#selected),nil,{records=selected,session=session,owner=UnitName('player')})
            end
            local single=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
            single:SetSize(245,23);single:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            single:SetText('Stage 1 more to Bags')
            if #toStage==0 or session.unverified or cleanupTransferBusy then single:Disable() end
            single:SetScript('OnClick',function() StageMore(1) end)
            rows[#rows+1]=single
            local bulk=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
            bulk:SetSize(345,23);bulk:SetPoint('TOPLEFT',content,'TOPLEFT',266,-y)
            bulk:SetText('Stage '..#toStage..' more listed to Bags')
            if #toStage==0 or session.unverified or cleanupTransferBusy then bulk:Disable() end
            bulk:SetScript('OnClick',function() StageMore(#toStage) end)
            rows[#rows+1]=bulk
            y=y+32
            local note=CreateFrame('Frame',nil,content)
            note:SetSize(790,24);note:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local warning=note:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            warning:SetAllPoints();warning:SetJustifyH('LEFT')
            warning:SetText('Original KEEP and cross-check set remain frozen. Finish Batch only after staged items are resolved.')
            rows[#rows+1]=note
            y=y+27
        end
        if content.WGRShowAdvancedCleanup and content.WGRShowTroubleshooting and showAccountPreview and accountPreviewCache and not transferSession then
            local revision=WGRStorageCleanupGetInventoryRevision
                and WGRStorageCleanupGetInventoryRevision() or 0
            local fresh=accountPreviewRevision==revision
            local proposed=fresh and WGRStorageCleanupCrossCheckAccountSurplus(
                accountPreviewCache,current,surplus,keep,review) or {}
            local crossChecked={}
            for _,item in ipairs(proposed) do
                -- Closed banks and out-of-date physical slots can remain
                -- represented in the frozen UI. A cross-check for staging
                -- is visible only while the exact original is accessible.
                if SameSourceItem(item) then crossChecked[#crossChecked+1]=item end
            end
            local head=CreateFrame('Frame',nil,content)
            head:SetSize(790,24);head:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local headText=head:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            headText:SetAllPoints();headText:SetJustifyH('LEFT')
            headText:SetText('Account cross-check: '..#crossChecked..
                ' CURRENTLY ACCESSIBLE local SURPLUS copies match the saved account estimate'
                ..(fresh and '' or ' (STALE: refresh preview)'))
            rows[#rows+1]=head
            y=y+25
            if #crossChecked>0 then
                -- Constrain staging to a SPECIFIC accessible bank/holder and
                -- category.  Unlike the old first-copy picker, we deliberately
                -- offer no default source or category and never batch across
                -- unrelated gear.  Other holders' PBKs are inaccessible here.
                local availableSources={}
                local categories={}
                for _,item in ipairs(crossChecked) do
                    if item.source~='BAGS' and SourceVisible(item) then
                        availableSources[item.source]=true
                        if item.source==crosscheckSelection.source then
                            categories[item.cleanupGroupLabel or item.category or 'Other / Unclassified']=true
                        end
                    end
                end
                local currentOwner=UnitName('player') or 'Current character'
                local sourceNames={
                    PERSONAL_BANK=currentOwner..' / Personal Bank',
                    WARBAND_BANK='Shared Warbank',
                }
                local sourceOptions={{'NONE','Choose holder / source...'}}
                for _,key in ipairs({'PERSONAL_BANK','WARBAND_BANK'}) do
                    if availableSources[key] then
                        sourceOptions[#sourceOptions+1]={key,sourceNames[key]}
                    end
                end
                if crosscheckSelection.source~='NONE'
                    and not availableSources[crosscheckSelection.source] then
                    crosscheckSelection.source='NONE'
                    crosscheckSelection.category='NONE'
                end
                local categoryOptions={{'NONE','Choose equipment category...'}}
                local categoryKeys={}
                for key in pairs(categories) do categoryKeys[#categoryKeys+1]=key end
                table.sort(categoryKeys)
                for _,key in ipairs(categoryKeys) do
                    categoryOptions[#categoryOptions+1]={key,key}
                end
                if crosscheckSelection.category~='NONE'
                    and not categories[crosscheckSelection.category] then
                    crosscheckSelection.category='NONE'
                end
                local sourceDrop,sourceLabel=WGRGearSearchMakeDropdown(
                    content,'Owner / accessible source',12,300,
                    function() return sourceOptions end,'source',crosscheckSelection,
                    function()
                        crosscheckSelection.category='NONE'
                        Render(true)
                    end)
                sourceLabel:ClearAllPoints()
                sourceLabel:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y-3)
                rows[#rows+1]=sourceLabel;rows[#rows+1]=sourceDrop
                local categoryDrop,categoryLabel=WGRGearSearchMakeDropdown(
                    content,'Equipment category',399,300,
                    function() return categoryOptions end,'category',crosscheckSelection,
                    function() Render(true) end)
                categoryLabel:ClearAllPoints()
                categoryLabel:SetPoint('TOPLEFT',content,'TOPLEFT',399,-y-3)
                rows[#rows+1]=categoryLabel;rows[#rows+1]=categoryDrop
                y=y+54
                local scoped=WGRStorageCleanupFilterCrossCheckedForStaging(
                    crossChecked,crosscheckSelection.source,crosscheckSelection.category)
                local toStage={}
                for i=1,math.min(20,#scoped) do toStage[#toStage+1]=scoped[i] end
                local label=CreateFrame('Frame',nil,content)
                label:SetSize(790,23);label:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
                local labelText=label:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                labelText:SetAllPoints();labelText:SetJustifyH('LEFT')
                if crosscheckSelection.source=='NONE' or crosscheckSelection.category=='NONE' then
                    labelText:SetText('Select one bank/holder AND category to review exact copies before staging.')
                else
                    labelText:SetText('Selected: '..crosscheckSelection.category..' / '..
                        tostring(sourceNames[crosscheckSelection.source] or '?')..' | '..
                        #scoped..' matched; '..#toStage..' listed for this batch (max 20).')
                end
                rows[#rows+1]=label
                y=y+26
                if #toStage>0 then
                    -- The confirmation lists what will move.  Display one
                    -- distinct SOURCE SLOT per row, including identical copies;
                    -- nothing outside these displayed 1..20 slots is queued.
                    for i,item in ipairs(toStage) do
                        local line=CreateFrame('Frame',nil,content)
                        line:SetSize(790,20);line:SetPoint('TOPLEFT',content,'TOPLEFT',15,-y)
                        local value=line:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                        value:SetAllPoints();value:SetJustifyH('LEFT')
                        value:SetText(tostring(i)..'. '..tostring(item.itemLink)..
                            ' | ilvl '..tostring(item.itemLevel or '?')..
                            ' | '..tostring(item.location or (item.source=='PERSONAL_BANK' and 'PBK' or 'WBK'))..
                            ' bag '..tostring(item.bagID)..' slot '..tostring(item.slotID))
                        rows[#rows+1]=line
                        y=y+21
                    end
                end
                local function StageExactList(n)
                    if #toStage==0 then return end
                    local now=WGRStorageCleanupGetInventoryRevision
                        and WGRStorageCleanupGetInventoryRevision() or 0
                    if now~=accountPreviewRevision or transferSession or cleanupTransferBusy then
                        print('|cffffaa00WBGR:|r Account cross-check changed. Refresh Preview and select the category again.')
                        return
                    end
                    local selected={}
                    for i=1,math.min(n,#toStage) do
                        if not SameSourceItem(toStage[i]) then
                            print('|cffffaa00WBGR:|r A selected source slot changed or its bank closed. Rescan before staging.')
                            return
                        end
                        selected[#selected+1]=toStage[i]
                    end
                    StaticPopupDialogs.WGR_CONFIRM_STORAGE_CLEANUP_CHECKED =
                        StaticPopupDialogs.WGR_CONFIRM_STORAGE_CLEANUP_CHECKED or {
                            text='Stage %s to Bags? Only the listed copies will move. No items will be sold, mailed or disenchanted.',
                            button1=YES,button2=NO,timeout=0,whileDead=true,
                            hideOnEscape=true,preferredIndex=3,
                            OnAccept=function(_,data)
                                if not data or not data.records then return end
                                local revision=WGRStorageCleanupGetInventoryRevision
                                    and WGRStorageCleanupGetInventoryRevision() or 0
                                if not settings.enabled or cleanupTransferBusy or transferSession
                                    or revision~=data.revision or revision~=accountPreviewRevision
                                    or UnitName('player')~=data.owner then
                                    print('|cffffaa00WBGR:|r Selected account cross-check is stale. Nothing was moved.')
                                    return
                                end
                                for _,item in ipairs(data.records) do
                                    if not SameSourceItem(item) then
                                        print('|cffffaa00WBGR:|r Source changed before confirmation. Nothing was moved.')
                                        return
                                    end
                                end
                                MoveVerified(data.records,'BAGS',false,{
                                    records=data.scope,source=data.source,category=data.category})
                            end,
                        }
                    StaticPopup_Show('WGR_CONFIRM_STORAGE_CLEANUP_CHECKED',
                        tostring(#selected)..' displayed '..crosscheckSelection.category..
                        ' copy/copies from '..tostring(sourceNames[crosscheckSelection.source]),nil,
                        {records=selected,revision=now,owner=currentOwner,
                            scope=scoped,source=crosscheckSelection.source,
                            category=crosscheckSelection.category})
                end
                local single=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
                single:SetSize(245,23)
                single:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
                single:SetText('Stage 1 listed copy to Bags')
                if #toStage==0 then single:Disable() end
                single:SetScript('OnClick',function() StageExactList(1) end)
                rows[#rows+1]=single
                local bulk=CreateFrame('Button',nil,content,'UIPanelButtonTemplate')
                bulk:SetSize(345,23)
                bulk:SetPoint('TOPLEFT',content,'TOPLEFT',266,-y)
                bulk:SetText('Stage '..#toStage..' listed copies to Bags')
                if #toStage==0 then bulk:Disable() end
                bulk:SetScript('OnClick',function() StageExactList(#toStage) end)
                rows[#rows+1]=bulk
                y=y+31
            end
            local caution=CreateFrame('Frame',nil,content)
            caution:SetSize(790,23);caution:SetPoint('TOPLEFT',content,'TOPLEFT',12,-y)
            local txt=caution:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            txt:SetAllPoints();txt:SetJustifyH('LEFT')
            txt:SetText('Staging only: confirm normal routing and all holder coverage before manual disposal. No items sold or mailed.')
            txt:SetTextColor(1,0.74,0.3)
            rows[#rows+1]=caution
            y=y+26
        end
        if content.WGRShowAdvancedCleanup and content.WGRShowTroubleshooting then y=SavedInventoryBrowser(y+6) end
        content:SetHeight(math.max(1,y+10))
    end
    refresh:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
        if transferSession then
            GameTooltip:AddLine('Update Item Locations')
            GameTooltip:AddLine('Checks the tracked slots for this batch. Keeps the original KEEP/SURPLUS decisions frozen. Does not automatically locate items moved manually.',1,1,1,true)
        else
            GameTooltip:AddLine('Scan Inventory')
            GameTooltip:AddLine('Manually checks account-wide retained gear against accessible Bags/Banks. Runs the verified comparison across frames; uncertain results remain REVIEW.',1,1,1,true)
        end
        GameTooltip:Show()
    end)
    refresh:SetScript('OnLeave',function() GameTooltip:Hide() end)
    refresh:SetScript('OnClick',function()
        -- Explicit Scan Inventory bypasses all passive-cache optimizations.
        -- It is also the authoritative point that clears any passive/manual
        -- "results may be stale" notice accumulated since the prior scan.
        refresh.WGRHasManualCleanupScan=true
        cleanupNeedsManualRescan=false
        cleanupNeedsManualRescanReason=nil
        WGRStorageCleanupInvalidateObservedCache()
        if cleanupTransferBusy then
            print('|cffffaa00WBGR:|r Wait for the current transfer to finish before checking locations.')
            return
        end
        if transferSession then
            local valid,reason=VerifyFrozenSources(transferSession)
            if valid then
                print('|cff33ff99WBGR:|r Tracked batch locations checked. Original KEEP/SURPLUS decisions are unchanged.')
            else
                print('|cffffaa00WBGR:|r Batch location check: '..reason..'. Nothing was moved or reclassified.')
            end
        end
        if showAccountPreview and not transferSession then accountPreviewCache=nil end
        local isManualAudit=(not transferSession) and settings.enabled and
            not (WGRRoutingIsPaused and WGRRoutingIsPaused()) and
            not (WGRIsCharacterRemoved and WGRIsCharacterRemoved(UnitName('player')))
        Render()
        if isManualAudit and not accountChecking and not transferSession then
            accountAuditSerial=accountAuditSerial+1
            local serial=accountAuditSerial
            if displayedPhysicalItems and WGRStorageCleanupStartAccountCheckAsync then
                accountChecking=true
                accountAudit=nil
                Render(true)
                local previousDecisionSignature=nil
                local pass=0
                local maxPasses=3
                local function FinishAccountCheckFailure(message)
                    if serial~=accountAuditSerial then return end
                    accountChecking=false
                    accountAudit=nil
                    if message then print('|cffffaa00WBGR:|r '..message) end
                    Render(true)
                end
                local RunAccountCheckPass
                RunAccountCheckPass=function()
                    if serial~=accountAuditSerial then return end
                    if not settings.enabled or transferSession then
                        FinishAccountCheckFailure('Account check stopped because Storage Cleanup changed state.')
                        return
                    end
                    pass=pass+1
                    local physical=displayedPhysicalItems
                    local signature=AccountPhysicalSignature(physical)
                    local startStockSignature=AccountStockSignature()
                    if not signature or not startStockSignature then
                        FinishAccountCheckFailure('Account-wide check unavailable; run Scan Inventory again.')
                        return
                    end
                    local job,err=WGRStorageCleanupStartAccountCheckAsync(physical,function(report)
                        if serial~=accountAuditSerial then return end
                        local revision=WGRStorageCleanupGetInventoryRevision and
                            WGRStorageCleanupGetInventoryRevision() or 0
                        local fresh=WGRStorageCleanupScanAccessible()
                        if AccountStockSignature()~=startStockSignature or
                            AccountPhysicalSignature(fresh)~=signature or
                            not settings.enabled or transferSession then
                            FinishAccountCheckFailure('Account check became stale; run Scan Inventory again.')
                            return
                        end
                        local decisionSignature=WGRStorageCleanupAccountReportSignature and
                            WGRStorageCleanupAccountReportSignature(report)
                        if previousDecisionSignature and decisionSignature==previousDecisionSignature then
                            accountChecking=false
                            accountAudit=report
                            accountAudit.signature=signature
                            accountAudit.stockSignature=startStockSignature
                            accountAuditRevision=revision
                            -- v0.72ao: A successful explicit account check is
                            -- authoritative.  Clear any stale/manual-rescan flag
                            -- before redrawing so Mark DISPOSE / Mark All are
                            -- immediately available again.
                            cleanupNeedsManualRescan=false
                            cleanupNeedsManualRescanReason=nil
                            Render(true)
                        elseif pass>=maxPasses then
                            FinishAccountCheckFailure('Account check did not stabilize; run Scan Inventory again.')
                        else
                            previousDecisionSignature=decisionSignature
                            -- Re-run the same local scan/save stage while the guided UI
                            -- remains in CHECKING state, then verify the account result
                            -- again. This mirrors an immediate manual rescan without
                            -- exposing the intermediate classification to the user.
                            Render()
                            RunAccountCheckPass()
                        end
                    end,function(reason)
                        if serial~=accountAuditSerial then return end
                        FinishAccountCheckFailure('Account-wide check withheld: '..tostring(reason))
                    end)
                    if not job then
                        FinishAccountCheckFailure('Account-wide check unavailable: '..tostring(err))
                    end
                end
                RunAccountCheckPass()
            end
        end
        -- A deliberate Scan Inventory can resurface still-present disposal
        -- reminders. This must NOT run for passive scans, tab redraws, frozen
        -- batch location checks, or other To Do refreshes.
        if isManualAudit and WGRRestoreDisposeTodoAfterManualScan then
            WGRRestoreDisposeTodoAfterManualScan('ALL')
        end
    end)
    newAudit=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate')
    newAudit:SetSize(204,22)
    newAudit:SetPoint('RIGHT',refresh,'LEFT',-8,0)
    newAudit:SetText('Finish Cleanup & Rescan')
    newAudit:Hide()
    newAudit:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
        GameTooltip:AddLine('Finish Cleanup & Rescan')
        GameTooltip:AddLine('After prepared items are sold/disenchanted or returned to storage, end this protected batch and scan again. No items move automatically.',1,1,1,true)
        GameTooltip:Show()
    end)
    newAudit:SetScript('OnLeave',function() GameTooltip:Hide() end)
    newAudit:SetScript('OnClick',function()
        if cleanupTransferBusy then return end
        if not transferSession then Render();return end
        local session=transferSession
        local current=SnapshotAccessible()
        if (session.initialPBKOpen and not current.pbk)
            or (session.initialWBKOpen and not current.wbk) then
            print('|cffff5555WBGR:|r Finish Batch requires the original banks open for KEEP verification.')
            return
        end
        for _,item in ipairs(session.keep) do
            if not SameSourceItem(item) then
                print('|cffff5555WBGR:|r Cannot finish batch: an original KEEP slot changed. Verify retained items first.')
                return
            end
        end
        -- Staged copies must first leave Bags, either by verified Cleanup
        -- movement to a bank, disposal, or manual return to storage.
        -- Exact location tracking beats aggregate counts when available.
        for _,item in pairs(session.staged) do
            if (item.source=='PERSONAL_BANK' and not current.pbk)
                or (item.source=='WARBAND_BANK' and not current.wbk) then
                print('|cffff5555WBGR:|r Cannot finish batch: open the staged destination bank first.')
                return
            end
            if item.source=='BAGS' and SameSourceItem(item) then
                print('|cffff5555WBGR:|r Cannot finish batch: staged surplus is still in Bags. Move it onward or dispose of it first.')
                return
            end
        end
        -- A bank-to-bank staging transfer is not a completed disposal.
        -- Re-auditing it as ordinary storage could again swap KEEP/SURPLUS
        -- labels onto identical copies. Require return to the original bank
        -- or actual departure from this accessible pool before resetting.
        for _,original in ipairs(session.surplus) do
            local tracked=session.staged[PhysicalKey(original)]
            if tracked and SourceVisible(tracked) and SameSourceItem(tracked)
                and original.source~='BAGS' and tracked.source~=original.source then
                print('|cffff5555WBGR:|r Cannot finish batch: staged items are still in a different bank. Return them or finish disposing/sending them.')
                return
            end
        end
        local stagedLinks={}
        for _,item in ipairs(session.surplus) do
            if session.moved[PhysicalKey(item)] then stagedLinks[item.itemLink]=true end
        end
        for link in pairs(stagedLinks) do
            if (current.bagCounts[link] or 0)>(session.initialBagCounts[link] or 0) then
                print('|cffff5555WBGR:|r Cannot finish batch: extra staged copies remain in Bags. Finish moving or disposing of them.')
                return
            end
        end
        StaticPopupDialogs.WGR_CONFIRM_STORAGE_CLEANUP_NEW_AUDIT={
            text='Finish this cleanup batch and scan inventory again? Returned items will be considered for KEEP/SURPLUS again, and identical copies may get different labels. No items will move automatically.',
            button1=YES,button2=NO,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
            OnAccept=function()
                transferSession=nil
                accountPreviewCache=nil -- recompute only after the frozen batch is over
                crosscheckSelection.source='NONE'
                crosscheckSelection.category='NONE'
                print('|cff33ff99WBGR:|r Batch finished. Scanning inventory again...')
                -- Reuse the exact explicit Scan Inventory path so Finish Cleanup &
                -- Rescan gets the same bounded stable account check (A->A or
                -- A->B->B) instead of merely redrawing a now-stale audit.
                local scanHandler=refresh:GetScript('OnClick')
                if scanHandler then scanHandler(refresh) else Render() end
            end,
        }
        StaticPopup_Show('WGR_CONFIRM_STORAGE_CLEANUP_NEW_AUDIT')
    end)
    panel:SetScript("OnShow",function()
        -- v0.72an: reopening/redrawing the tab is not an explicit audit.
        -- Preserve a completed manual result until the user presses Scan/Rescan.
        if hasDisplayedAudit then Render(true) else Render() end
        -- v0.72n one-time recovery for databases made provisional by the old
        -- toggle-generation policy. Ask only when numeric prior-generation
        -- snapshots actually exist; legacy/unknown data remains provisional.
        if settings.enabled and WGRStorageCleanupHasRecoverableToggleProvisionalData and
            WGRStorageCleanupHasRecoverableToggleProvisionalData() then
            local function prompt()
                if panel:IsShown() and settings.enabled and
                    WGRStorageCleanupHasRecoverableToggleProvisionalData() then
                    ShowCleanupResumePrompt(true)
                end
            end
            if C_Timer and C_Timer.After then C_Timer.After(0.10,prompt) else prompt() end
        end
    end)
    -- v0.72an: Gear Finder/bank refreshes are ordinary redraws, not permission
    -- to replace a completed manual Storage Cleanup audit.  External callers
    -- therefore get a snapshot-only redraw by default after the first audit.
    frame.WGRStorageCleanupRender=function(snapshotOnly)
        if snapshotOnly==nil and hasDisplayedAudit then snapshotOnly=true end
        return Render(snapshotOnly)
    end
    -- Slash commands can change an override while this tab is visible.
    -- They must not leave an obsolete KEEP allocation on screen. A frozen
    -- movement batch, however, must retain its original protected plan.
    WGRStorageCleanupRefreshVisibleAudit=function()
        if not (settings.enabled and panel.IsShown and panel:IsShown()) then return end
        Render(true)
    end
    -- v0.72as: manual KEEP/DISPOSE can be changed outside the Cleanup tab
    -- (Recommendations context menu or slash command). Keep the displayed
    -- row/button state synchronized without requiring a full rescan just to
    -- see the override change. Clearing an override still makes the manual
    -- audit stale for NEW disposal authorization, per the v0.72al+ contract.
    WGRStorageCleanupNotifyManualOverrideChanged=function(cleared)
        if not settings.enabled then return end
        if cleared then
            FlagCleanupNeedsManualRescan('Manual KEEP/DISPOSE override cleared')
        end
        if panel.IsShown and panel:IsShown() then Render(true) end
    end
    -- v0.67s: after a successful passive snapshot save, keep both the
    -- diagnostics and the ordinary KEEP/SURPLUS/REVIEW lists current. Only a
    -- non-frozen audit is eligible for automatic recalculation. A transfer
    -- batch must never swap the protected KEEP copy of a duplicate item.
    local pendingPassiveUI=false
    local pendingPassiveObservation=nil
    local function UpdateCleanupAfterObservation(observation)
        if not settings.enabled or not panel.IsShown or not panel:IsShown() then return end
        -- A WBGR-controlled direct CLEAN UP move owns its own before/after
        -- verification and UI remap. Ignore passive container churn until that
        -- transaction settles so it cannot discard the still-valid audit.
        if cleanupTransferBusy then return end
        if transferSession then
            -- Never reclassify during staging. Only redraw diagnostics if
            -- expanded; frozen physical item assignments remain protected.
            if showSavedInventories then Render(true) end
            return
        end

        local pbkOpen=WGRGearFinderIsPersonalBankOpen and WGRGearFinderIsPersonalBankOpen() or false
        local wbkOpen=WGRGearFinderIsWarbandBankOpen and WGRGearFinderIsWarbandBankOpen() or false
        -- An automatic event may fire after a bank closes or before bank tab
        -- enumeration is ready. Preserve the last complete displayed audit
        -- instead of treating temporarily inaccessible stored gear as gone.
        local lostBank=hasDisplayedAudit and ((displayedPBK and not pbkOpen)
            or (displayedWBK and not wbkOpen))
        local unreadableBank=(pbkOpen and (not Enum or not Enum.BankType
            or #WGRStorageCleanupBankTabIDs(Enum.BankType.Character)==0))
            or (wbkOpen and (not Enum or not Enum.BankType
            or #WGRStorageCleanupBankTabIDs(Enum.BankType.Account)==0))
        if lostBank or unreadableBank then
            if hasDisplayedAudit then Render(true) end
            return
        end
        -- Slot shuffles of unique item links cannot change the KEEP/SURPLUS
        -- allocation. Preserve labels and remap the UI's slot references
        -- without rerunning the ~86 ms routing-aware planner. If a duplicate
        -- changes physical position, an item enters/leaves/changes bank, or
        -- any snapshot is ambiguous, fall back to the FULL existing audit.
        if hasDisplayedAudit and displayedPhysicalItems
            and pbkOpen==displayedPBK and wbkOpen==displayedWBK then
            -- Reuse the passive observation that was already accepted and
            -- saved.  Do NOT immediately rescan live containers from this UI
            -- callback: that redundant second read was the remaining source of
            -- false all-WBK removals after otherwise valid moves.
            local latest=(type(observation)=='table' and type(observation.records)=='table')
                and observation.records or nil
            if latest and observation.pbkOpen~=pbkOpen then latest=nil end
            if latest and observation.wbkOpen~=wbkOpen then latest=nil end
            -- Fail closed for legacy/manual callers that provide no accepted
            -- observation; only those callers use a fresh live read.
            if not latest then
                latest=WGRStorageCleanupScanAccessible(WGRStorageCleanupObservedSlotCache)
            end
            if WGRStorageCleanupRemapOnlyMovement(displayedPhysicalItems,latest) then
                locationOnlySkips=locationOnlySkips+1
                lastAutomaticAudit='Slot-only (planner skipped)'
                if showSavedInventories or showAccountPreview then Render(true) end
                return
            end
        end
        -- v0.72am: passive observations are advisory only. A background
        -- read that cannot be proven as a location-only remap must never erase
        -- a completed manual Storage Cleanup audit. Preserve the visible result
        -- and ask for one explicit Rescan when the user is ready. Action buttons
        -- still validate their exact physical slot/GUID before doing anything.
        RecordCleanupInvalidation('passive observation could not be remapped as location-only movement',
            displayedPhysicalItems,latest,accountAudit and accountAudit.stockSignature or nil,
            AccountStockSignature())
        FlagCleanupNeedsManualRescan('Passive inventory change could not be safely remapped')
        return
    end
    WGRNotifyStorageCleanupSnapshotChanged=function(records,pbkOpen,wbkOpen)
        if not settings.enabled or not panel.IsShown or not panel:IsShown() then return end
        -- Keep the newest accepted passive observation while coalescing a burst
        -- of container events.  The delayed UI update consumes this exact
        -- snapshot instead of taking an unguarded second bank read.
        if type(records)=='table' then
            pendingPassiveObservation={records=records,pbkOpen=pbkOpen==true,wbkOpen=wbkOpen==true}
        end
        if pendingPassiveUI then return end
        pendingPassiveUI=true
        local function update()
            pendingPassiveUI=false
            local observation=pendingPassiveObservation
            pendingPassiveObservation=nil
            UpdateCleanupAfterObservation(observation)
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.35,update) else update() end
    end
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

    local cleanupTab =
        WGRGearSearchCreateTab(
            page,
            "Storage Cleanup",
            112
        )

    cleanupTab:SetPoint(
        "LEFT",
        searchTab,
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

    local cleanupPanel, CleanupRender =
        WGRCreateStorageCleanupPanel(
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
    local expandedRows = {}

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

        allRows = WGRGearSearchCollectRows()
        local filtered = {}
        for _, row in ipairs(allRows) do
            if WGRGearSearchMatches(row,state) then filtered[#filtered+1]=row end
        end
        filtered = WGRGearSearchAggregate(filtered)
        local detailIndex=WGRGearSearchBuildTrackedDetailIndex()
        local detailEnabled=WGRGearSearchCleanupDetailEnabled()

        resultSummary:SetText(
            tostring(#filtered).." matching entr"..(#filtered==1 and "y" or "ies")..
            " across tracked storage."
        )

        local y=0
        for index,record in ipairs(filtered) do
            local row=CreateFrame("Frame",nil,content)
            row:SetPoint("TOPLEFT",content,"TOPLEFT",0,-y)
            row:SetPoint("RIGHT",content,"RIGHT",0,0)
            row:SetHeight(23)
            local bg=row:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints()
            local shade=index%2==0 and 0.10 or 0.05
            bg:SetColorTexture(shade,shade,shade,index%2==0 and 0.30 or 0.18)
            local key=WGRGearSearchAggregateKey(record)
            local details=detailEnabled and detailIndex[key] or nil
            local expandable=details and #details>0
            local values={record.category,record.slot,record.primary,record.type,
                record.character,record.location,tostring(record.quantity or 0)}
            if expandable then
                values[1]=(expandedRows[key] and '[-] ' or '[+] ')..tostring(values[1] or '')
            end
            for i,value in ipairs(values) do
                local text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                text:SetPoint("LEFT",row,"LEFT",starts[i]+3,0)
                text:SetWidth(widths[i]-6)
                text:SetJustifyH(i==7 and "CENTER" or "LEFT")
                text:SetText(value~="" and value or "-")
            end
            rows[#rows+1]=row
            y=y+24
            if expandable then
                WGRGearSearchMakeAggregateExpandable(row,bg,key,expandedRows,Render)
                if expandedRows[key] then
                    y=WGRGearSearchAddTrackedDetailRows(content,rows,record,details,y)
                end
            end
        end
        content:SetHeight(math.max(1,y))

        for _, dropdown in ipairs({
            categoryDropdown,slotDropdown,primaryDropdown,typeDropdown,
            characterDropdown,locationDropdown,
        }) do
            if dropdown and dropdown.WGRUpdateText then dropdown:WGRUpdateText() end
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

    local function SetView(viewKey, skipRemember)
        if not skipRemember
            and WarboundGearRouterDB
            and WarboundGearRouterDB.interface
        then
            WarboundGearRouterDB.interface.lastGearFinderView =
                viewKey
        end

        local isRecommendations = viewKey == "RECOMMENDATIONS"
        local isGather = viewKey == "GATHER"
        local isSearch = viewKey == "SEARCH"
        local isCleanup = viewKey == "CLEANUP"

        recTab:SetSelected(isRecommendations)
        gatherTab:SetSelected(isGather)
        searchTab:SetSelected(isSearch)
        cleanupTab:SetSelected(isCleanup)

        recommendation.refresh:SetShown(isRecommendations)
        recommendation.ignoreHint:SetShown(isRecommendations)
        recommendation.sourceStatus:SetShown(isRecommendations)
        recommendation.specStatus:SetShown(isRecommendations)
        recommendation.summary:SetShown(isRecommendations)
        recommendation.scroll:SetShown(isRecommendations)


        gatherPanel:SetShown(isGather)
        searchPanel:SetShown(isSearch)
        cleanupPanel:SetShown(isCleanup)

        if isGather or isSearch then
            ReconcilePhysicalSnapshots()
            if isGather and GatherRender then
                GatherRender()
            elseif isSearch then
                Render()
            end
        elseif isCleanup then
            if CleanupRender then CleanupRender() end
        elseif WGRRefreshGearFinder then
            WGRRefreshGearFinder(frame)
        end
    end

    recTab:SetScript("OnClick", function() SetView("RECOMMENDATIONS") end)
    gatherTab:SetScript("OnClick", function() SetView("GATHER") end)
    searchTab:SetScript("OnClick", function() SetView("SEARCH") end)
    cleanupTab:SetScript("OnClick", function() SetView("CLEANUP") end)

    frame.ShowGearFinderView =
        SetView

    -- Roster held-gear shortcuts use the existing Gear Search UI rather than
    -- maintaining a second inventory browser. Reset every other filter so a
    -- stale search cannot make the clicked character appear to have no gear.
    frame.ShowGearSearchForCharacter =
        function(characterName)
            if not characterName or characterName == "" then
                return
            end

            state.category = "ALL"
            state.slot = "ALL"
            state.primary = "ALL"
            state.type = "ALL"
            state.character = tostring(characterName)
            state.location = "ALL"

            SetView("SEARCH")
        end

    -- The Roster's account-global Warband Bank row uses the same Gear Search
    -- browser, but filters by physical location rather than character owner.
    -- Reset every unrelated filter so a stale search cannot hide WBK stock.
    frame.ShowGearSearchForLocation =
        function(location)
            if not location or location == "" then
                return
            end

            state.category = "ALL"
            state.slot = "ALL"
            state.primary = "ALL"
            state.type = "ALL"
            state.character = "ALL"
            state.location = tostring(location)

            SetView("SEARCH")
        end

    -- Recommendations remains the normal/default workflow. Gather Gear is an
    -- on-demand exception/check step for priority/spec changes, while Gear
    -- Search remains the general storage browser.
    SetView("RECOMMENDATIONS", true)

    frame.gearFinderRecommendationsTab = recTab
    frame.gearFinderGatherTab = gatherTab
    frame.gearFinderSearchTab = searchTab
    frame.gearFinderCleanupTab = cleanupTab
    frame.gearFinderGatherPanel = gatherPanel
    frame.gearFinderSearchPanel = searchPanel
    frame.gearFinderCleanupPanel = cleanupPanel
end
