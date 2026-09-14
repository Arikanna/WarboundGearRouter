# Warbound Gear Router

**Warbound Gear Router (WBGR)** helps manage Warbound and Bind-on-Equip (BoE) gear across your World of Warcraft characters by recommending where each item is most useful.

Designed for players with large alt rosters, WBGR helps decide what to equip, what to send to another character, and what can be stored for later use.

## Download

The latest release is available on [CurseForge](https://www.curseforge.com/wow/addons/warbound-gear-router).

## Features

- Routes **Warbound and Bind-on-Equip (BoE) gear** across your roster
- Configurable **character priorities** and **item-level upgrade thresholds**
- Supports **Current Spec, All Specs, and Custom Spec** routing
- Recommends upgrades by **item level**, not stat weights or simulations
- Handles armor, jewelry, trinkets, weapons, shields, and off-hands
- Supports **1H + Off-hand, 1H + Shield, Dual 1H, and Fury Dual 2H**
- **Gear Finder** shows your best upgrades and available actions
- **Gather Gear** finds compatible gear the current character may be able to use
- **Gear Search** locates tracked gear across Bags, Personal Banks, the Warband Bank, and Mail
- **To Do** highlights gear and transfers that still need attention
- **Mail Router** helps transfer gear between characters
- Tracks qualifying gear mailed between tracked characters
- Supports ignored items and excluded/storage characters
- Configurable tooltip styles with optional detailed routing information
- Optional Bagnon overlays and item-location highlighting

## Requirements

WBGR uses DataStore for saved cross-character information.

**Required:**
- DataStore
- DataStore_Characters
- DataStore_Inventory

**Optional:**
- DataStore_Containers
- DataStore_Talents

## Getting Started

Log into the characters you want WBGR to track.

WBGR can use available DataStore information to help initialize character data, but for the most accurate spec and weapon routing, switch to each spec you want tracked and equip its intended weapon setup at least once.

Open WBGR using the minimap button or:

`/wbgr`

Start with the **Roster** tab to configure character priority, participation, specs, weapon eligibility, and upgrade thresholds.

Then use:

- **Gear Finder → Recommendations** for upgrades and routing actions
- **Gather Gear** to find other potentially usable gear
- **Gear Search** to locate tracked gear across your warband
- **To Do** to work through transfers and other remaining actions

WBGR also includes built-in **Getting Started**, **How Routing Works**, and **Help & FAQ** documentation.

## How Routing Works

WBGR first looks for characters who meet your configured item-level upgrade threshold. If none qualify, it considers smaller positive upgrades. After that, it can hold useful gear for characters who may use it later.

Within each group, your configured roster priority determines who receives the item first.

Soulbound gear is **never routed to another character**. WBGR may use compatible Soulbound weapons or trinkets a character already owns as part of its comparison baseline, but only transferable Warbound/BoE gear is considered for cross-character routing.

## Important

WBGR is primarily an **inventory and alt-gearing management tool**.

It evaluates upgrades primarily by **item level**, while respecting primary-stat compatibility and spec-aware trinket eligibility. It does not calculate stat weights, simulate characters, or determine whether a lower-item-level item may be better because of secondary stats, special effects, or encounter-specific considerations.

For characters you are actively optimizing, use WBGR alongside class-specific gearing tools or simulations.

## License

Warbound Gear Router is released under the **GNU General Public License v3.0 (GPL-3.0)**.
