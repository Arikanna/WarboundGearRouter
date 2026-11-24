-- WBGR release highlights: explicitly opened from About, never automatic.
-- Separate presentation-only module; no changes to routing or SavedVariables.

function WGRCreateWhatsNewPanel(aboutPage, aboutDescription, openGearFinder, openInterfaceSettings)
    local panel = CreateFrame("Frame", nil, aboutPage)
    panel:SetPoint("TOPLEFT", aboutDescription, "BOTTOMLEFT", 0, -58)
    panel:SetPoint("BOTTOMRIGHT", aboutPage, "BOTTOMRIGHT", -20, 14)
    panel:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -28, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1100, 910)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(1, width - 8))
    end)

    local y = -4
    local function AddText(text, height, style, color)
        local line = content:CreateFontString(nil, "OVERLAY", style or "GameFontHighlight")
        line:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
        line:SetPoint("RIGHT", content, "RIGHT", -10, 0)
        line:SetJustifyH("LEFT")
        line:SetJustifyV("TOP")
        line:SetHeight(height)
        line:SetText(text)
        if color then line:SetTextColor(unpack(color)) end
        y = y - height - 7
        return line
    end
    local function Section(title, body, height)
        AddText(title, 25, "GameFontNormalLarge")
        AddText(body, height, "GameFontHighlight")
    end
    local function NavButton(label, action)
        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetSize(188, 23)
        button:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
        button:SetText(label)
        button:SetScript("OnClick", action)
        y = y - 48 -- Clear spacing between navigation buttons and the next section.
    end
    AddText("What's New in Warbound Gear Router", 29, "GameFontNormalLarge")
    AddText("Explore the latest features and improvements.", 21, "GameFontHighlightSmall")

    Section("1. Storage Cleanup  |cffffa64d(BETA)|r",
        "Find excess gear saved for future use. Enable Storage Cleanup on its page, click Scan Inventory, review CLEAN UP and NEEDS ATTENTION, then mark unwanted items DISPOSE individually or with Mark All. " ..
        "It's optional and OFF by default. WBGR never automatically sells or destroys your items.", 43)
    NavButton("Open Storage Cleanup", function() openGearFinder("CLEANUP") end)

    Section("2. Manual KEEP & DISPOSE",
        "Take control of individual items: KEEP protects a copy; DISPOSE overrides normal routing and marks it for selling or disposal. " ..
        "Overrides follow marked items across characters and storage locations. Use /wbgr keep, dispose, unkeep, or undispose; removing an override returns the copy to AUTO routing.", 43)
    NavButton("View Useful Commands", function()
        if aboutPage.ShowSubtab then aboutPage.ShowSubtab("COMMANDS") end
    end)

    Section("3. Improved Mail Router & Mailbox Compatibility",
        "Improved compatibility with Blizzard's mailbox, TradeSkillMaster (TSM), and Goblin Mailbox. " ..
        "If a replacement mailbox addon prevents WBGR from sending through its interface, WBGR offers an alternative sending interface when you open a mailbox, without requiring you to disable your preferred addon.", 54)

    Section("4. More Ways to Access WBGR",
        "Open WBGR from WoW's AddOn Compartment near the minimap, a LibDataBroker display addon such as Bazooka, or the standalone minimap button.", 36)

    Section("5. Interface & Convenience Improvements",
        "Return to Last Page Viewed can reopen WBGR where you left off. Mail Router at Mailbox lets you choose automatic opening, a button, or no automatic action. " ..
        "WoW's Options > AddOns menu also has a shortcut to open WBGR's settings. " ..
        "You can revisit these What's New highlights using the button beside the version number on About.", 50)
    NavButton("Open Interface Settings", openInterfaceSettings)

    Section("6. Smarter Gear Recommendations",
        "Improved duplicate handling, holder assignments, weapon configurations, and inventory movement make gear routing more reliable.", 35)

    -- Separate the six highlights from the feedback/contact section.
    y = y - 5
    local divider = content:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.45, 0.45, 0.45, 0.65)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
    divider:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    y = y - 22

    -- Support is opt-in only: no popup, chat announcement, or automatic browser action.
    Section("Feedback, Bug Reports & Feature Requests",
        "Found a bug, have an idea for a new feature, or need compatibility with another addon? " ..
        "Please leave a comment on WBGR's CurseForge page. Feedback is especially helpful while Storage Cleanup is in Beta.", 45)
    AddText("CurseForge page (click the address to select and copy):", 19, "GameFontHighlightSmall")
    local curseForgeAddress = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    curseForgeAddress:SetSize(440, 22)
    curseForgeAddress:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y)
    curseForgeAddress:SetAutoFocus(false)
    curseForgeAddress:SetText("https://www.curseforge.com/wow/addons/warbound-gear-router")
    curseForgeAddress:SetCursorPosition(0)
    curseForgeAddress:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    curseForgeAddress:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    curseForgeAddress:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    y = y - 30

    content:SetHeight(math.max(1, -y + 14))
    return panel
end

function WGRCreateWhatsNewButton(aboutPage, versionValue)
    local button = CreateFrame("Button", nil, aboutPage, "UIPanelButtonTemplate")
    button:SetSize(94, 20)
    button:SetPoint("LEFT", versionValue, "RIGHT", 15, 0)
    button:SetText("What's New?")
    button:SetScript("OnClick", function()
        if aboutPage.ShowSubtab then aboutPage.ShowSubtab("WHATS_NEW") end
    end)
    return button
end
