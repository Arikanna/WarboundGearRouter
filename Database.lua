
-- ============================================================
-- TEMPORARY PERFORMANCE DIAGNOSTICS
-- ============================================================

WGRPerfStats = WGRPerfStats or {}

function WGRPerfNow()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end

    return 0
end

function WGRPerfRecord(name, elapsedMS, details)
    if not name then
        return
    end

    local stat = WGRPerfStats[name] or {
        count = 0,
        total = 0,
        max = 0,
        last = 0,
        details = nil,
    }

    local value = tonumber(elapsedMS) or 0
    stat.count = stat.count + 1
    stat.total = stat.total + value
    stat.last = value
    if value > (stat.max or 0) then
        stat.max = value
    end
    if details ~= nil then
        stat.details = tostring(details)
    end

    WGRPerfStats[name] = stat
end

function WGRPerfReset()
    WGRPerfStats = {}
end

-- Database and persisted settings defaults.
local WGR_DATABASE_SCHEMA_VERSION = 2

WGR_DEFAULT_THRESHOLD = 10

-- ============================================================
-- DATABASE
-- ============================================================

local function WGRRunDatabaseMigrations()
    local db =
        WarboundGearRouterDB

    local currentVersion =
        tonumber(
            db.schemaVersion
        )
        or 0

    if currentVersion < 1 then
        -- Obsolete fields retained by older builds.
        db.weaponProfileOverrides =
            nil

        db.routingPriorityDefault =
            nil

        currentVersion =
            1
    end

    if currentVersion < 2 then
        local validSpecModes = {
            CURRENT = true,
            ALL = true,
            CUSTOM = true,
        }

        if type(db.characterOverrides) == "table" then
            for characterKey, override
                in pairs(db.characterOverrides)
            do
                if type(override) ~= "table" then
                    db.characterOverrides[characterKey] =
                        nil
                else
                    if override.specMode ~= nil
                        and not validSpecModes[
                            override.specMode
                        ]
                    then
                        override.specMode =
                            nil
                    end

                    if not next(override) then
                        db.characterOverrides[characterKey] =
                            nil
                    end
                end
            end
        end

        local validWeaponModes = {
            ALL = true,
            SAVED = true,
            CUSTOM = true,
        }

        if type(db.weaponModes) == "table" then
            for characterKey, mode
                in pairs(db.weaponModes)
            do
                if not validWeaponModes[mode] then
                    db.weaponModes[characterKey] =
                        nil
                end
            end
        end

        if type(db.customWeaponPreferences) == "table" then
            for characterKey, preferences
                in pairs(db.customWeaponPreferences)
            do
                if type(preferences) ~= "table" then
                    db.customWeaponPreferences[characterKey] =
                        nil
                else
                    for specKey, config
                        in pairs(preferences)
                    do
                        local specID =
                            tonumber(specKey)

                        local eligible =
                            specID
                            and WGRSpecEligibleWeaponConfigs[
                                specID
                            ]

                        local validConfig =
                            false

                        if type(eligible) == "table" then
                            for _, allowedConfig
                                in ipairs(eligible)
                            do
                                if config == allowedConfig then
                                    validConfig =
                                        true
                                    break
                                end
                            end
                        end

                        if not validConfig then
                            preferences[specKey] =
                                nil
                        end
                    end

                    if not next(preferences) then
                        db.customWeaponPreferences[
                            characterKey
                        ] = nil
                    end
                end
            end
        end

        currentVersion =
            2
    end

    -- Never downgrade a database written by a newer build.
    if currentVersion
        <= WGR_DATABASE_SCHEMA_VERSION
    then
        db.schemaVersion =
            WGR_DATABASE_SCHEMA_VERSION
    end
end


function InitializeDatabase()
    if not WarboundGearRouterDB then
        WarboundGearRouterDB = {}
    end

    if not WarboundGearRouterDB.specs then
        WarboundGearRouterDB.specs = {}
    end

    if not WarboundGearRouterDB.mailTracking then
        WarboundGearRouterDB.mailTracking = {}
    end

    if not WarboundGearRouterDB.mailGearTracking then
        WarboundGearRouterDB.mailGearTracking = {}
    end

    if not WarboundGearRouterDB.recentActivity then
        WarboundGearRouterDB.recentActivity = {}
    end

    if not WarboundGearRouterDB.todoDismissals then
        WarboundGearRouterDB.todoDismissals = {}
    end

    if not WarboundGearRouterDB.todoGearSnapshots then
        WarboundGearRouterDB.todoGearSnapshots = {}
    end

    if not WarboundGearRouterDB.heldGearSnapshots then
        WarboundGearRouterDB.heldGearSnapshots = {}
    end

    -- Item/category continuity for gear that WBGR already tracked through MAIL.
    -- This is intentionally separate from routing decisions: Gear Search answers
    -- where known tracked gear physically is, even if the recipient-side routing
    -- evaluation later changes.
    if not WarboundGearRouterDB.gearSearchMailContinuity then
        WarboundGearRouterDB.gearSearchMailContinuity = {}
    end

    if not WarboundGearRouterDB.todoSpecAttempts then
        WarboundGearRouterDB.todoSpecAttempts = {}
    end

    if WarboundGearRouterDB.todoScanSerial == nil then
        WarboundGearRouterDB.todoScanSerial = 0
    end

    local validTodoSortModes = {
        URGENCY = true,
        PRIORITY = true,
        NAME = true,
    }

    if not validTodoSortModes[
        WarboundGearRouterDB.todoSortMode
    ]
    then
        WarboundGearRouterDB.todoSortMode =
            "URGENCY"
    end

    if not WarboundGearRouterDB.ignoredCharacters then
        WarboundGearRouterDB.ignoredCharacters = {}
    end

    if not WarboundGearRouterDB.removedCharacters then
        WarboundGearRouterDB.removedCharacters = {}
    end

    if WarboundGearRouterDB.priorityBackup == nil then
        WarboundGearRouterDB.priorityBackup = false
    end

    if not WarboundGearRouterDB.routingSettings then
        WarboundGearRouterDB.routingSettings = {
            specMode = "CURRENT",
            weaponMode = "ALL",
            upgradeThreshold = WGR_DEFAULT_THRESHOLD,
            prioritizeRogueAgilityDaggers = true,
            preferWarglaivesForDemonHunters = true,
            preferDual2HForFury = true,
        }
    else
        if not WarboundGearRouterDB.routingSettings.specMode
            or WarboundGearRouterDB.routingSettings.specMode == "CUSTOM"
        then
            WarboundGearRouterDB.routingSettings.specMode = "CURRENT"
        end

        if WarboundGearRouterDB.routingSettings.weaponMode ~= "ALL"
            and WarboundGearRouterDB.routingSettings.weaponMode ~= "SAVED"
        then
            WarboundGearRouterDB.routingSettings.weaponMode = "ALL"
        end

        if not WarboundGearRouterDB.routingSettings.upgradeThreshold then
            WarboundGearRouterDB.routingSettings.upgradeThreshold =
                WGR_DEFAULT_THRESHOLD
        end

        if WarboundGearRouterDB.routingSettings.prioritizeRogueAgilityDaggers == nil then
            WarboundGearRouterDB.routingSettings.prioritizeRogueAgilityDaggers = true
        end
        if WarboundGearRouterDB.routingSettings.preferWarglaivesForDemonHunters == nil then
            WarboundGearRouterDB.routingSettings.preferWarglaivesForDemonHunters = true
        end
        if WarboundGearRouterDB.routingSettings.preferDual2HForFury == nil then
            WarboundGearRouterDB.routingSettings.preferDual2HForFury = true
        end
    end

    if not WarboundGearRouterDB.characterOverrides then
        WarboundGearRouterDB.characterOverrides = {}
    end

    if not WarboundGearRouterDB.customSpecs then
        WarboundGearRouterDB.customSpecs = {}
    end

    if not WarboundGearRouterDB.weaponModes then
        WarboundGearRouterDB.weaponModes = {}
    end
    if not WarboundGearRouterDB.customWeaponPreferences then
        WarboundGearRouterDB.customWeaponPreferences = {}
    end

    if not WarboundGearRouterDB.specWeaponBaselines then
        WarboundGearRouterDB.specWeaponBaselines = {}
    end

    -- Last-observed physical SOULBOUND weapon components owned by each
    -- character. This is separate from per-spec historical baselines so
    -- routing can combine committed pieces across specs without treating
    -- still-transferable Warbound/BoE candidates as already owned upgrades.
    -- v0.64ad changes this cache's semantics from "all observed weapons" to
    -- "confirmed Soulbound weapons only", so discard older persisted entries
    -- once rather than allowing pre-ad transferable items to raise routing.
    if WarboundGearRouterDB.ownedWeaponComponentsSoulboundOnlyVersion ~= 1 then
        WarboundGearRouterDB.ownedWeaponComponents = {}
        WarboundGearRouterDB.ownedWeaponComponentsSoulboundOnlyVersion = 1
    elseif not WarboundGearRouterDB.ownedWeaponComponents then
        WarboundGearRouterDB.ownedWeaponComponents = {}
    end

    -- Tracks specs whose incomplete/zero weapon baseline was deliberately
    -- accepted through the Custom Weapons Reset action. This suppresses the
    -- To Do initialization reminder without pretending the setup is complete.
    if not WarboundGearRouterDB.acceptedIncompleteWeaponBaselines then
        WarboundGearRouterDB.acceptedIncompleteWeaponBaselines = {}
    end

    if not WarboundGearRouterDB.specTrinketBaselines then
        WarboundGearRouterDB.specTrinketBaselines = {}
    end

    -- Last-observed physical SOULBOUND trinkets owned by each character.
    -- Routing derives per-spec trinket floors from this ownership pool so
    -- wrong-spec equipped trinkets cannot erase useful bag/PBK trinkets and
    -- old historical per-spec records cannot pretend a missing trinket is
    -- still physically owned. Each physical record also stores the live
    -- character-context spec eligibility observed for that trinket; offline
    -- routing must not reconstruct eligibility from item links alone.
    -- Warbound/BoE trinkets never enter this cache.
    if WarboundGearRouterDB.ownedTrinketComponentsSoulboundOnlyVersion ~= 2 then
        WarboundGearRouterDB.ownedTrinketComponents = {}
        WarboundGearRouterDB.ownedTrinketComponentsSoulboundOnlyVersion = 2
    elseif not WarboundGearRouterDB.ownedTrinketComponents then
        WarboundGearRouterDB.ownedTrinketComponents = {}
    end

    if not WarboundGearRouterDB.eligibleGear then
        WarboundGearRouterDB.eligibleGear = {
            warbound = true,
            boe = true,
            minimumQuality = 2,
            ignoredItems = {},
        }
    else
        if WarboundGearRouterDB.eligibleGear.warbound == nil then
            WarboundGearRouterDB.eligibleGear.warbound = true
        end
        if WarboundGearRouterDB.eligibleGear.boe == nil then
            WarboundGearRouterDB.eligibleGear.boe = true
        end
        if WarboundGearRouterDB.eligibleGear.minimumQuality == nil then
            WarboundGearRouterDB.eligibleGear.minimumQuality = 2
        end

        if not WarboundGearRouterDB.eligibleGear.ignoredItems then
            WarboundGearRouterDB.eligibleGear.ignoredItems = {}
        end
    end

    if not WarboundGearRouterDB.minimap then
        WarboundGearRouterDB.minimap = {
            angle = 225,
            shown = true,
        }
    else
        if WarboundGearRouterDB.minimap.angle == nil then
            WarboundGearRouterDB.minimap.angle = 225
        end

        if WarboundGearRouterDB.minimap.shown == nil then
            WarboundGearRouterDB.minimap.shown = true
        end
    end

    if not WarboundGearRouterDB.mainWindow then
        WarboundGearRouterDB.mainWindow = {}
    end

    if WarboundGearRouterDB.mainWindow.point == nil then
        WarboundGearRouterDB.mainWindow.point = "CENTER"
    end

    if WarboundGearRouterDB.mainWindow.relativePoint == nil then
        WarboundGearRouterDB.mainWindow.relativePoint = "CENTER"
    end

    if WarboundGearRouterDB.mainWindow.x == nil then
        WarboundGearRouterDB.mainWindow.x = 360
    end

    if WarboundGearRouterDB.mainWindow.y == nil then
        WarboundGearRouterDB.mainWindow.y = 100
    end

    -- The original 470px window remains the minimum height.  Users may
    -- expand the main window vertically; the chosen height is remembered.
    if WarboundGearRouterDB.mainWindow.height == nil then
        WarboundGearRouterDB.mainWindow.height = 470
    end

    if not WarboundGearRouterDB.interface then
        WarboundGearRouterDB.interface = {
            tooltipStyle = "PROMINENT",
            showSoulboundTrinketSpecs = false,
            gearOverlays = false,
            backgroundOpacity = 50,
            routingPaused = false,
            mailReminderPopups = true,
            rosterViewSort = "PRIORITY",
            rosterSortDirections = {
                PRIORITY = "ASC",
                NAME = "ASC",
                LEVEL = "DESC",
                CLASS = "ASC",
                PLAYTIME = "DESC",
                ILVL = "DESC",
                STATUS = "ASC",
            },
        }
    else
        if not WarboundGearRouterDB.interface.tooltipStyle then
            WarboundGearRouterDB.interface.tooltipStyle = "PROMINENT"
        elseif WarboundGearRouterDB.interface.tooltipStyle == "FULL" then
            -- v0.65x internal test name; preserve the user's choice through
            -- the public-facing rename to Detailed.
            WarboundGearRouterDB.interface.tooltipStyle = "DETAILED"
        end

        if WarboundGearRouterDB.interface.showSoulboundTrinketSpecs == nil then
            WarboundGearRouterDB.interface.showSoulboundTrinketSpecs = false
        end

        if WarboundGearRouterDB.interface.gearOverlays == nil then
            WarboundGearRouterDB.interface.gearOverlays = false
        end

        if WarboundGearRouterDB.interface.backgroundOpacity == nil then
            WarboundGearRouterDB.interface.backgroundOpacity = 50
        end

        if WarboundGearRouterDB.interface.routingPaused == nil then
            WarboundGearRouterDB.interface.routingPaused = false
        end

        if WarboundGearRouterDB.interface.mailReminderPopups == nil then
            WarboundGearRouterDB.interface.mailReminderPopups = true
        end

        if not WarboundGearRouterDB.interface.rosterViewSort then
            WarboundGearRouterDB.interface.rosterViewSort = "PRIORITY"
        end

        if not WarboundGearRouterDB.interface.rosterSortDirections then
            WarboundGearRouterDB.interface.rosterSortDirections = {}
        end

        local directions =
            WarboundGearRouterDB.interface.rosterSortDirections

        if directions.PRIORITY == nil then
            directions.PRIORITY = "ASC"
        end
        if directions.NAME == nil then
            directions.NAME = "ASC"
        end
        if directions.LEVEL == nil then
            directions.LEVEL = "DESC"
        end
        if directions.CLASS == nil then
            directions.CLASS = "ASC"
        end
        if directions.PLAYTIME == nil then
            directions.PLAYTIME = "DESC"
        end
        if directions.ILVL == nil then
            directions.ILVL = "DESC"
        end
        if directions.STATUS == nil then
            directions.STATUS = "ASC"
        end
    end

    WGRRunDatabaseMigrations()
end


function WGRRoutingIsPaused()
    InitializeDatabase()

    return
        WarboundGearRouterDB.interface.routingPaused
        == true
end
