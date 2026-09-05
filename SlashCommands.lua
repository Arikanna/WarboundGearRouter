-- Slash-command registration and dispatch.

-- ============================================================
-- SLASH COMMAND
-- ============================================================

SlashCmdList[
    "WARBOUNDGEARROUTER"
] = function(msg)

    msg = msg or ""

    local command,
          rest =
        msg:match(
            "^(%S*)%s*(.-)$"
        )

    command =
        string.lower(
            command or ""
        )

    if command == "" then
        WGRMailShowTracker()
        return
    end

    if command == "help" then
        print(
            "|cff00ff00Warbound Gear Router|r"
        )

        print(
            "Version "
            .. WGRGetAddonMetadata(
                "Version",
                "Unknown"
            )
        )

        print(
            "|cffffff00/wbgr|r - open Warbound Gear Router"
        )

        print(
            "|cffffff00/wbgr mailrouter|r - open the Mail Router while at a mailbox"
        )

        print(
            "|cffffff00/wbgr mailcheck|r - open the WBGR Mail page"
        )

        print(
            "|cffffff00/wbgr cleanup|r - rescan and refresh gear overlays"
        )

        print(
            "|cffffff00/wbgr pause|r - pause live routing tooltips and overlay scans"
        )

        print(
            "|cffffff00/wbgr resume|r - resume live routing and rebuild overlays"
        )

        print(
        )

        print(
            "Additional diagnostic commands are available when troubleshooting."
        )

        return
    end

    if command == "testtrinket" then
        WGRRunTrinketRoutingDiagnostic(
            rest
        )
        return
    end

    if command == "testspec" then
        WGRRunItemSpecDiagnostic(
            rest
        )
        return
    end

    if command == "perf" then
        local lowerRest = string.lower(rest or "")

        if lowerRest == "reset" then
            if WGRPerfReset then
                WGRPerfReset()
            end
            print("|cff00ff00WBGR PERF:|r counters reset.")
            return
        end

        print("|cff00ff00=== WBGR PERFORMANCE ===|r")
        if not WGRPerfStats or not next(WGRPerfStats) then
            print("No performance samples recorded yet.")
            print("Move an item in/out of the bank, wait a moment, then run |cffffff00/wbgr perf|r again.")
            return
        end

        local order = {
            "inventory_refresh_total",
            "held_snapshot_total",
            "held_bags_scan",
            "held_bags_scan_routing",
            "held_bank_scan",
            "held_bank_scan_routing",
            "warband_snapshot_total",
            "warband_scan",
            "warband_scan_routing",
            "roster_refresh",
            "bagnon_overlays",
            "gear_finder_refresh",
        }

        for _, name in ipairs(order) do
            local stat = WGRPerfStats[name]
            if stat then
                local avg = stat.count > 0 and (stat.total / stat.count) or 0
                local detail = stat.details and ("  " .. stat.details) or ""
                print(string.format(
                    "|cffffff00%-25s|r last=%7.1fms  avg=%7.1fms  max=%7.1fms  n=%d%s",
                    name, stat.last or 0, avg, stat.max or 0, stat.count or 0, detail
                ))
            end
        end

        print("Use |cffffff00/wbgr perf reset|r before a clean test if needed.")
        return
    end

    if command == "pause" then
        WGRSetRoutingPaused(
            true
        )
        return
    end

    if command == "resume" then
        WGRSetRoutingPaused(
            false
        )
        return
    end

    if command == "test" then
        local lowerRest =
            string.lower(
                rest
            )

        if lowerRest == "spec" then
            WGRRunItemSpecDiagnostic(
                nil
            )
            return
        end

        local specItemToken =
            lowerRest:match(
                "^spec%s+(%S+)"
            )

        if specItemToken then
            WGRRunItemSpecDiagnostic(
                specItemToken
            )
            return
        end

        if lowerRest == "trinket" then
            WGRRunTrinketRoutingDiagnostic(
                nil
            )
            return
        end

        if lowerRest == "trinketbaseline" then
            WGRRunTrinketBaselineDiagnostic(
                nil,
                nil
            )
            return
        end

        local trinketBaselineCharacter =
            string.match(
                rest,
                "^trinketbaseline%s+(%S+)"
            )

        if trinketBaselineCharacter then
            WGRRunTrinketBaselineDiagnostic(
                nil,
                trinketBaselineCharacter
            )
            return
        end

        local trinketItemToken =
            lowerRest:match(
                "^trinket%s+(%S+)"
            )

        if trinketItemToken then
            WGRRunTrinketRoutingDiagnostic(
                trinketItemToken
            )
            return
        end

        if lowerRest == "help" then
            print(
                "|cff00ff00=== WBGR TEST COMMANDS ===|r"
            )

            print(
                "|cffffff00/wbgr test ITEMID|r - test normal routing with the item's real ilvl"
            )

            print(
                "|cffffff00/wbgr test ITEMID ignoreilvl|r - ignore upgrade checks by using a very high effective ilvl"
            )

            print(
                "|cffffff00/wbgr test ITEMID verbose|r - show eligibility diagnostics plus routing"
            )

            print(
                "|cffffff00/wbgr test ITEMID ignoreilvl verbose|r - full eligibility test while ignoring ilvl"
            )

            print(
                "|cffffff00/wbgr test ITEMID ilvl NUMBER [verbose]|r - simulate the item at a specific ilvl"
            )

            print(
                "|cffffff00/wbgr test spec [ITEMID]|r - print Blizzard spec IDs/roles for hovered item or ItemID"
            )

            print(
                "|cffffff00/wbgr test trinket [ITEMID]|r - show roster eligibility after Current/All/Custom spec filtering"
,
                "|cffffff00/wbgr test trinketbaseline [CharacterName]|r - show per-spec trinket baselines and final comparison for the hovered trinket"
            )

            print(" ")

            print(
                "|cff00ff00Examples:|r"
            )

            print(
                "|cffffff00/wbgr test 82265 ilvl 45 verbose|r - simulate a level-appropriate low-level weapon upgrade"
            )

            print(
                "|cff00ff00Known-good item IDs:|r"
            )

            print(
                "|cffffff00219247|r - Dalaran Defender's Wand (wand normalization / caster 1H)"
            )

            print(
                "|cffffff00246995|r - Ascension Arrestor's Dagger (Rogue dagger routing)"
            )

            print(
                "|cffffff00246670|r - Ascension Arrestor's Warglaive (Demon Hunter)"
            )

            print(
                "|cffffff00286603|r - Talisman of Nightbane (caster off-hand)"
            )

            print(
                "|cffffff00246669|r - Ascension Arrestor's Shield (shield routing)"
            )

            return
        end

        local itemToken =
            rest:match(
                "^(%S+)"
            )

        if not itemToken then
            print(
                "Usage: |cffffff00/wbgr test ITEMID [ignoreilvl] [verbose] [ilvl NUMBER]|r"
            )

            print(
                "Use |cffffff00/wbgr test help|r for examples."
            )
            return
        end

        local ignoreIlvl =
            lowerRest:find(
                "ignoreilvl",
                1,
                true
            ) ~= nil

        local verbose =
            lowerRest:find(
                "verbose",
                1,
                true
            ) ~= nil

        local simulatedIlvl =
            tonumber(
                lowerRest:match(
                    "%f[%a]ilvl%s+(%d+)"
                )
            )

        if simulatedIlvl
            and simulatedIlvl < 1
        then
            simulatedIlvl = nil
        end

        WGRRunTestItem(
            itemToken,
            ignoreIlvl,
            verbose,
            simulatedIlvl
        )

        return
    end

    if command == "item" then
        EvaluateItem(
            GetHoveredItem()
        )

        return
    end

    if command == "gear" then
        if rest == "" then
            print(
                "Usage: |cffffff00/wbgr gear CharacterName|r"
            )

            return
        end

        PrintGear(rest)

        return
    end

    if command == "specs" then
        SaveCurrentSpec()
        PrintSpecs()

        return
    end

    if command == "mailcheck" then
        WGRMailShowTracker()
        return
    end

    if command == "mailrouter"
        or command == "mail"
    then

        if WGRMailOpenRouterManual then
            WGRMailOpenRouterManual()
        end
        return
    end

    if command == "currentspec" then
        local specIndex =
            GetSpecialization
            and GetSpecialization()
            or nil

        local specID,
              specName =
            nil,
            nil

        if specIndex
            and GetSpecializationInfo
        then
            specID,
            specName =
                GetSpecializationInfo(
                    specIndex
                )
        end

        print(
            "|cff00ff00WBGR Live Current Spec:|r index "
            .. tostring(
                specIndex
            )
            .. ", ID "
            .. tostring(
                specID
            )
            .. ", "
            .. tostring(
                specName
            )
        )

        return
    end

    if command == "proficiency" then
        local requestedName =
            rest ~= ""
            and rest
            or UnitName(
                "player"
            )

        local itemLink =
            GetHoveredItem()

        if not itemLink then
            print(
                "|cffffcc00WBGR:|r Hover a weapon first, then use /wbgr proficiency CharacterName."
            )
            return
        end

        local character =
            FindCharacterByName(
                requestedName
            )

        local classID =
            GetCharacterClassID(
                requestedName,
                character
            )

        local info =
            GetInstantItemInfo(
                itemLink
            )

        print(
            "|cff00ff00WBGR Proficiency:|r "
            .. tostring(requestedName)
            .. " | subclass "
            .. tostring(
                info
                and info.subclassID
                or "?"
            )
            .. " | class can use: "
            .. tostring(
                classID
                and WGRClassCanUseWeaponSubtype(
                    classID,
                    itemLink
                )
                or nil
            )
        )

        return
    end

    if command == "weaponrules" then
        local requestedName =
            rest ~= ""
            and rest
            or UnitName(
                "player"
            )

        local character =
            FindCharacterByName(
                requestedName
            )

        if not character then
            print(
                "|cffff0000WBGR: Character not found:|r "
                .. tostring(
                    requestedName
                )
            )
            return
        end

        local specIDs =
            WGRGetRoutingSpecIDs(
                requestedName,
                character
            )

        print(
            "|cff00ff00WBGR Weapon Rules:|r "
            .. tostring(
                requestedName
            )
        )

        for _, specID
            in ipairs(
                specIDs
                or {}
            )
        do
            local profile,
                  baseline =
                WGRGetSpecWeaponProfile(
                    requestedName,
                    specID
                )

            local specName =
                WGRSpecNamesByID[
                    specID
                ]
                or tostring(
                    specID
                )

            if profile == "SAVED_SETUP" then
                print(
                    specName
                    .. " ("
                    .. tostring(specID)
                    .. "): Saved Setup | "
                    .. WGRFormatWeaponBaseline(
                        baseline
                    )
                    .. (
                        baseline
                        and baseline.inherited
                        and " | "
                            .. (
                                WGRDescribeInheritedBaseline(baseline)
                                or "Inherited"
                            )
                        or ""
                    )
                )
            else
                print(
                    specName
                    .. " ("
                    .. tostring(specID)
                    .. "): All Eligible | "
                    .. (
                        baseline
                        and WGRFormatWeaponBaseline(
                            baseline
                        )
                        or "Not Initialized"
                    )
                )
            end
        end

        print(
            "|cffaaaaaaExisting class/spec eligibility, warglaive, dagger-priority, stat, threshold, and holder rules still apply separately.|r"
        )

        return
    end

    if command == "weaponconfig" then
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

        local characterName =
            UnitName(
                "player"
            )

        local specIndex =
            GetSpecialization
            and GetSpecialization()
            or nil

        local specID =
            specIndex
            and GetSpecializationInfo
            and select(
                1,
                GetSpecializationInfo(
                    specIndex
                )
            )
            or nil

        local existingBaseline =
            characterName
            and specID
            and WGRGetSpecWeaponBaseline(
                characterName,
                specID
            )
            or nil

        local detected =
            WGRDetectWeaponConfigurationForSpec(
                mainHand,
                offHand,
                specID,
                existingBaseline
            )

        local mainLevel =
            mainHand
            and (
                C_Item.GetDetailedItemLevelInfo(
                    mainHand
                )
                or GetItemLevel(mainHand)
            )
            or 0

        local offLevel =
            offHand
            and (
                C_Item.GetDetailedItemLevelInfo(
                    offHand
                )
                or GetItemLevel(offHand)
            )
            or 0

        local specInfo =
            GetCurrentSpecInfo()

        local _, _, classID =
            UnitClass(
                "player"
            )

        local mainFitsSpec =
            specInfo
            and WGRLiveEquippedItemFitsSpec(
                mainHand,
                classID,
                specInfo.id
            )
            or nil

        local offFitsSpec =
            specInfo
            and WGRLiveEquippedItemFitsSpec(
                offHand,
                classID,
                specInfo.id
            )
            or nil

        local temp = {
            mainHandLevel = mainLevel,
            offHandLevel = offLevel,
            weaponConfig = detected.config,
            weaponConfigState = detected.state,
            missingMainHand = detected.missingMainHand,
            missingOffHand = detected.missingOffHand,
        }

        print(
            "|cff00ff00WBGR Live Weapon Configuration:|r "
            .. WGRFormatWeaponBaseline(temp)
        )

        print(
            "State: "
            .. tostring(detected.state)
            .. "; Config: "
            .. tostring(detected.config)
            .. "; Missing MH: "
            .. tostring(detected.missingMainHand)
            .. "; Missing OH: "
            .. tostring(detected.missingOffHand)
        )

        print(
            "Current spec validity: MH "
            .. tostring(mainFitsSpec)
            .. "; OH "
            .. tostring(offFitsSpec)
        )

        if mainFitsSpec == false
            or offFitsSpec == false
        then
            print(
                "|cffffcc00WBGR: Equipped weapon setup is not valid for "
                .. tostring(
                    specInfo
                    and specInfo.name
                    or "this spec"
                )
                .. "; it will not initialize or overwrite that spec's baseline.|r"
            )
        end

        return
    end

    if command == "resetspecbaseline" then
        local requestedName,
              specText =
            rest:match(
                "^(%S+)%s+(%d+)$"
            )

        local specID =
            tonumber(
                specText
            )

        if not requestedName
            or not specID
        then
            print(
                "Usage: |cffffff00/wbgr resetspecbaseline CharacterName SpecID|r"
            )
            return
        end

        local key =
            string.lower(
                requestedName
            )

        local byCharacter =
            WarboundGearRouterDB.specWeaponBaselines[
                key
            ]

        if byCharacter then
            byCharacter[
                tostring(specID)
            ] = nil

            if not next(
                byCharacter
            )
            then
                WarboundGearRouterDB.specWeaponBaselines[
                    key
                ] = nil
            end
        end

        print(
            "|cff00ff00WBGR:|r Cleared spec weapon baseline "
            .. tostring(specID)
            .. " for "
            .. tostring(requestedName)
            .. "."
        )

        return
    end

    if command == "resetbaselines" then
        local requestedName =
            rest ~= ""
            and rest
            or UnitName(
                "player"
            )

        local key =
            requestedName
            and string.lower(
                requestedName
            )
            or nil

        if key then
            WarboundGearRouterDB.specWeaponBaselines[
                key
            ] = nil

            print(
                "|cff00ff00WBGR:|r Cleared saved spec weapon baselines for "
                .. tostring(
                    requestedName
                )
                .. ". Revisit/equip each spec to rebuild them."
            )
        end

        return
    end

    if command == "baselines" then
        local requestedName =
            rest ~= ""
            and rest
            or UnitName(
                "player"
            )

        local key =
            requestedName
            and string.lower(
                requestedName
            )
            or nil

        local data =
            key
            and WarboundGearRouterDB.specWeaponBaselines[
                key
            ]
            or nil

        print(
            "|cff00ff00WBGR Spec Weapon Baselines:|r "
            .. tostring(
                requestedName
            )
        )

        if not data then
            print(
                "No saved spec weapon baselines."
            )
            return
        end

        for specID, baseline
            in pairs(
                data
            )
        do
            print(
                tostring(
                    baseline.specName
                    or specID
                )
                .. " ("
                .. tostring(specID)
                .. "): "
                .. WGRFormatWeaponBaseline(
                    baseline
                )
                .. " | "
                .. tostring(
                    baseline.weaponConfigState
                    or "LEGACY"
                )
                .. " / "
                .. tostring(
                    baseline.weaponConfig
                    or "UNKNOWN"
                )
            )
        end

        return
    end


    if command == "cleanup" then
        if WGRRoutingIsPaused() then
            print(
                "|cffffff00WBGR routing is paused.|r Use |cffffff00/wbgr resume|r before refreshing overlays."
            )
            return
        end

        local visible, evaluated =
            RefreshBagnonCleanupOverlays()

        print(string.format(
            "|cff00ff00WBGR cleanup refreshed.|r Visible Bagnon buttons: %d; evaluated personal-storage buttons: %d",
            visible or 0,
            evaluated or 0
        ))

        return
    end



    if command == "slot" then
        local characterName,
              slotText =
            rest:match(
                "^(%S+)%s+(%d+)$"
            )

        if not characterName
            or not slotText
        then
            print(
                "Usage: |cffffff00/wbgr slot CharacterName SlotID|r"
            )
            return
        end

        DebugCharacterSlot(
            characterName,
            slotText
        )

        return
    end

    print(
        "|cffffcc00WBGR:|r Unknown command. Type |cffffff00/wbgr help|r for commands."
    )

end
