local addonName = ...

-- Warbound Gear Router v0.61e
-- Static routing/spec/weapon data extracted from the v0.61e modular build.
-- This file intentionally contains data only; behavior remains in WarboundGearRouter.lua.

-- Addon metadata helper shared by UI and command output.
function WGRGetAddonMetadata(field, fallback)
    local value = nil

    if C_AddOns
        and C_AddOns.GetAddOnMetadata
    then
        value = C_AddOns.GetAddOnMetadata(
            addonName,
            field
        )
    elseif GetAddOnMetadata then
        value = GetAddOnMetadata(
            addonName,
            field
        )
    end

    if value == nil
        or value == ""
    then
        return fallback
    end

    return value
end

-- Shared routing constants.
WGR_MAX_LEVEL = 90

-- ============================================================
-- WEAPON CONSTANTS
-- ============================================================

WGR_WEAPON_BOW =
    Enum and Enum.ItemWeaponSubclass and
    Enum.ItemWeaponSubclass.Bows or 2

WGR_WEAPON_GUN =
    Enum and Enum.ItemWeaponSubclass and
    Enum.ItemWeaponSubclass.Guns or 3

WGR_WEAPON_CROSSBOW =
    Enum and Enum.ItemWeaponSubclass and
    Enum.ItemWeaponSubclass.Crossbow or 18

WGR_WEAPON_WAND =
    Enum and Enum.ItemWeaponSubclass and
    Enum.ItemWeaponSubclass.Wand or 19

WGR_WEAPON_DAGGER =
    Enum and Enum.ItemWeaponSubclass and
    Enum.ItemWeaponSubclass.Dagger or 15

WGR_ITEM_CLASS_WEAPON =
    Enum and Enum.ItemClass and
    Enum.ItemClass.Weapon or 2

-- ============================================================
-- PRIMARY STAT PROFILES FOR KNOWN BELOW-MAX HOLDERS
--
-- WGR uses these together with the weapon/off-hand configuration
-- table. This prevents, for example, an Intellect staff from
-- being routed to a Survival Hunter simply because both are 2H.
-- ============================================================

-- Shared slot/equip-location lookup tables.
WGRArmorEquipSlots = {
    INVTYPE_HEAD = 1,
    INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5,
    INVTYPE_ROBE = 5,
    INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10,
}

WGRGlobalEquipSlots = {
    INVTYPE_NECK = { 2 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
}

WGROffhandEquipLocs = {
    INVTYPE_HOLDABLE = true,
    INVTYPE_SHIELD = true,
}

-- Shared diagnostic slot lookup.
WGRDiagnosticSlots = {
    { 1,  "Head" },
    { 2,  "Neck" },
    { 3,  "Shoulder" },
    { 5,  "Chest" },
    { 6,  "Waist" },
    { 7,  "Legs" },
    { 8,  "Feet" },
    { 9,  "Wrist" },
    { 10, "Hands" },
    { 11, "Ring 1" },
    { 12, "Ring 2" },
    { 13, "Trinket 1" },
    { 14, "Trinket 2" },
    { 15, "Cloak" },
    { 16, "Main Hand" },
    { 17, "Off Hand" },
}

-- ============================================================
-- CLASS IDS
-- ============================================================

WGRClassIDs = {
    WARRIOR = 1, ["Warrior"] = 1,
    PALADIN = 2, ["Paladin"] = 2,
    HUNTER = 3, ["Hunter"] = 3,
    ROGUE = 4, ["Rogue"] = 4,
    PRIEST = 5, ["Priest"] = 5,
    DEATHKNIGHT = 6, ["Death Knight"] = 6,
    SHAMAN = 7, ["Shaman"] = 7,
    MAGE = 8, ["Mage"] = 8,
    WARLOCK = 9, ["Warlock"] = 9,
    MONK = 10, ["Monk"] = 10,
    DRUID = 11, ["Druid"] = 11,
    DEMONHUNTER = 12, ["Demon Hunter"] = 12,
    EVOKER = 13, ["Evoker"] = 13,
}

-- ------------------------------------------------------------
WGRClassWeaponSubclasses = {
    [1] = { -- Warrior
        [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,
        [6]=true,[7]=true,[8]=true,[10]=true,[13]=true,[15]=true,[18]=true,
    },
    [2] = { -- Paladin
        [0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,
    },
    [3] = { -- Hunter
        [0]=true,[1]=true,[2]=true,[3]=true,[6]=true,[7]=true,[8]=true,
        [10]=true,[13]=true,[15]=true,[18]=true,
    },
    [4] = { -- Rogue
        [0]=true,[4]=true,[7]=true,[13]=true,[15]=true,
    },
    [5] = { -- Priest
        [4]=true,[10]=true,[15]=true,[19]=true,
    },
    [6] = { -- Death Knight
        [0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,
    },
    [7] = { -- Shaman
        [0]=true,[1]=true,[4]=true,[5]=true,[10]=true,[13]=true,[15]=true,
    },
    [8] = { -- Mage
        [7]=true,[10]=true,[15]=true,[19]=true,
    },
    [9] = { -- Warlock
        [7]=true,[10]=true,[15]=true,[19]=true,
    },
    [10] = { -- Monk
        [0]=true,[4]=true,[6]=true,[7]=true,[10]=true,[13]=true,
    },
    [11] = { -- Druid
        [4]=true,[5]=true,[6]=true,[10]=true,[13]=true,[15]=true,
    },
    [12] = { -- Demon Hunter
        [0]=true,[7]=true,[9]=true,[13]=true,[15]=true,
    },
    [13] = { -- Evoker
        [0]=true,[4]=true,[7]=true,[10]=true,[13]=true,[15]=true,
    },
}

-- ------------------------------------------------------------
-- WGRSpecNamesByID
-- ------------------------------------------------------------
WGRSpecNamesByID = {
    [62] = "Arcane",
    [63] = "Fire",
    [64] = "Frost",
    [65] = "Holy",
    [66] = "Protection",
    [70] = "Retribution",
    [71] = "Arms",
    [72] = "Fury",
    [73] = "Protection",
    [102] = "Balance",
    [103] = "Feral",
    [104] = "Guardian",
    [105] = "Restoration",
    [250] = "Blood",
    [251] = "Frost",
    [252] = "Unholy",
    [253] = "Beast Mastery",
    [254] = "Marksmanship",
    [255] = "Survival",
    [256] = "Discipline",
    [257] = "Holy",
    [258] = "Shadow",
    [259] = "Assassination",
    [260] = "Outlaw",
    [261] = "Subtlety",
    [262] = "Elemental",
    [263] = "Enhancement",
    [264] = "Restoration",
    [265] = "Affliction",
    [266] = "Demonology",
    [267] = "Destruction",
    [268] = "Brewmaster",
    [269] = "Windwalker",
    [270] = "Mistweaver",
    [577] = "Havoc",
    [581] = "Vengeance",
    [1467] = "Devastation",
    [1468] = "Preservation",
    [1473] = "Augmentation",
    [1480] = "Devourer",
}

-- ------------------------------------------------------------
-- WGRClassSpecIDs
-- ------------------------------------------------------------
WGRClassSpecIDs = {
    [1] = { 71, 72, 73 },
    [2] = { 65, 66, 70 },
    [3] = { 253, 254, 255 },
    [4] = { 259, 260, 261 },
    [5] = { 256, 257, 258 },
    [6] = { 250, 251, 252 },
    [7] = { 262, 263, 264 },
    [8] = { 62, 63, 64 },
    [9] = { 265, 266, 267 },
    [10] = { 268, 269, 270 },
    [11] = { 102, 103, 104, 105 },
    [12] = { 577, 581, 1480 },
    [13] = { 1467, 1468, 1473 },
}

-- ------------------------------------------------------------
-- WGRDualWieldOneHandSpecIDs
-- ------------------------------------------------------------
WGRDualWieldOneHandSpecIDs = {
    [251] = true,
    [259] = true,
    [260] = true,
    [261] = true,
    [263] = true,
    [269] = true,
    [577] = true,
    [581] = true,
    [1480] = true,
}

-- ------------------------------------------------------------
-- WGRDualWieldTwoHandSpecIDs
-- ------------------------------------------------------------
WGRDualWieldTwoHandSpecIDs = {
    [72] = true,
}

-- ------------------------------------------------------------
-- WGRWeaponModeLabels
-- ------------------------------------------------------------
WGRWeaponModeLabels = {
    ALL = "All Eligible",
    SAVED = "Saved Setup",
    CUSTOM = "Custom",
}

-- ------------------------------------------------------------
-- WGRSpecEligibleWeaponConfigs
-- ------------------------------------------------------------
WGRSpecEligibleWeaponConfigs = {
    [250]={"TWO_HAND"}, [251]={"TWO_HAND","DUAL_1H"}, [252]={"TWO_HAND"},
    [577]={"DUAL_1H"}, [581]={"DUAL_1H"}, [1480]={"DUAL_1H"},
    [102]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [103]={"TWO_HAND"}, [104]={"TWO_HAND"}, [105]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"},
    [1467]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [1468]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [1473]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"},
    [253]={"RANGED"}, [254]={"RANGED"}, [255]={"TWO_HAND","DUAL_1H"},
    [62]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [63]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [64]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"},
    [268]={"TWO_HAND","DUAL_1H"}, [269]={"TWO_HAND","DUAL_1H"}, [270]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"},
    [65]={"ONE_HAND_PLUS_SHIELD"}, [66]={"ONE_HAND_PLUS_SHIELD"}, [70]={"TWO_HAND"},
    [256]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [257]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [258]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"},
    [259]={"DUAL_1H"}, [260]={"DUAL_1H"}, [261]={"DUAL_1H"},
    [262]={"TWO_HAND","ONE_HAND_PLUS_SHIELD"}, [263]={"DUAL_1H"}, [264]={"TWO_HAND","ONE_HAND_PLUS_SHIELD"},
    [265]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [266]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"}, [267]={"TWO_HAND","ONE_HAND_PLUS_OFFHAND"},
    [71]={"TWO_HAND"}, [72]={"DUAL_2H","DUAL_1H"}, [73]={"ONE_HAND_PLUS_SHIELD"},
}

-- ------------------------------------------------------------
-- WGRWeaponConfigLabels
-- ------------------------------------------------------------
WGRWeaponConfigLabels = {
    RANGED = "Ranged",
    TWO_HAND = "2H",
    DUAL_2H = "Dual 2H",
    DUAL_1H = "Dual 1H",
    ONE_HAND_PLUS_SHIELD = "1H + Shield",
    ONE_HAND_PLUS_OFFHAND = "1H + Off-hand",
    PARTIAL_MAIN_ONLY = "1H + Missing OH",
    PARTIAL_OFFHAND_ONLY = "Missing MH + Off-hand",
    PARTIAL_SHIELD_ONLY = "Missing MH + Shield",
    UNKNOWN = "Unknown",
}

