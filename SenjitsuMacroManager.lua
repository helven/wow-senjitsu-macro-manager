--[[
    Senjitsu Macro Manager
    A standalone CRUD interface for WoW Macros.
    
    Architecture:
    - Pure Lua (no XML)
    - No SecureActionButtonTemplate (to avoid taint)
    - Event-driven (UPDATE_MACROS)
--]]

local ADDON_NAME = "SenjitsuMacroManager"
local SMM = CreateFrame("Frame", ADDON_NAME, UIParent, "BackdropTemplate")
SMM:Hide() -- Hidden by default

print("|cff00ff00SenjitsuMacroManager loaded. Type /smm to toggle.|r")

-- Variables
SMM.SelectedMacroIndex = nil -- The actual index in WoW's macro system
SMM.SelectedMacroIsLocal = nil -- true if character specific
SMM.MacroList = {} -- Table to hold macro data for the list
SMM.FramePool = {} -- Pool for list buttons

function SMM:RunAddonLifeCycle()
    SMM:CreateMainFrame()
    SMM:CreateListView()
    SMM:CreateDetailView()
    SMM:CreateButtons()
    SMM:RegisterEvents()
    SMM:SetupButtonActions()
    SMM:SetDetailViewEnabled(false)
    SMM:SetupSlashCommand()
end

-- ----------------------------------------------------------------------------------------------------------------------------------------------------------
-- UI CREATION FUNCTIONS
-- ----------------------------------------------------------------------------------------------------------------------------------------------------------
function SMM:CreateMainFrame()
    -- Basic Frame Properties
    self:SetSize(600, 450)
    self:SetPoint("CENTER")
    self:SetFrameStrata("HIGH")
    self:EnableMouse(true)
    self:SetMovable(true)
    self:RegisterForDrag("LeftButton")
    self:SetScript("OnDragStart", self.StartMoving)
    self:SetScript("OnDragStop", self.StopMovingOrSizing)

    -- Background and Border
    self:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    self.Title = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.Title:SetPoint("TOP", 0, -15)
    self.Title:SetText("Senjitsu Macro Manager")

    -- Close Button
    self.CloseButton = CreateFrame("Button", nil, self, "UIPanelCloseButton")
    self.CloseButton:SetPoint("TOPRIGHT", -5, -5)
end

-- -----------------------------------------------------------------------------
-- UI ELEMENTS
-- -----------------------------------------------------------------------------
function SMM:CreateListView()
    -- Search Box
    self.SearchLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.SearchLabel:SetPoint("TOPLEFT", 20, -35)
    self.SearchLabel:SetText("Search:")

    self.SearchHitBox = CreateFrame("Frame", nil, self, "BackdropTemplate")
    self.SearchHitBox:SetSize(150, 20)
    self.SearchHitBox:SetPoint("LEFT", self.SearchLabel, "RIGHT", 5, 0)
    self.SearchHitBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    self.SearchHitBox:SetBackdropColor(0, 0, 0, 0.5)

    self.SearchBox = CreateFrame("EditBox", nil, self.SearchHitBox)
    self.SearchBox:SetSize(140, 20)
    self.SearchBox:SetPoint("CENTER")
    self.SearchBox:SetFontObject("ChatFontNormal")
    self.SearchBox:SetAutoFocus(false)
    self.SearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.SearchBox:SetScript("OnTextChanged", function(self)
        SMM:RefreshList()
    end)

    -- Map global
    SMM.SearchBox = self.SearchBox

    -- ScrollFrame (List View)
    self.ListScroll = CreateFrame("ScrollFrame", nil, self, "UIPanelScrollFrameTemplate")
    self.ListScroll:SetSize(200, 320) -- Reduced height to fit search
    self.ListScroll:SetPoint("TOPLEFT", 20, -65) -- Moved down

    self.ListContent = CreateFrame("Frame", nil, self.ListScroll)
    self.ListContent:SetSize(200, 320)
    self.ListScroll:SetScrollChild(self.ListContent)
    
    self.ListScroll:SetScript("OnMouseWheel", function(self, delta)
        local check = self:GetVerticalScroll() - (delta * 20)
        if check < 0 then check = 0 end
        if check > self:GetVerticalScrollRange() then check = self:GetVerticalScrollRange() end
        self:SetVerticalScroll(check)
    end)
end

function SMM:CreateDetailView()
    -- Detail View Container
    self.DetailFrame = CreateFrame("Frame", nil, self)
    self.DetailFrame:SetSize(330, 350)
    self.DetailFrame:SetPoint("TOPRIGHT", -20, -40)

    -- -- Macro Name EditBox
    self.NameLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.NameLabel:SetPoint("TOPLEFT", 0, 0)
    self.NameLabel:SetText("Macro Name:")

    self.NameEditHitBox = CreateFrame("Frame", nil, self.DetailFrame, "BackdropTemplate")
    self.NameEditHitBox:SetSize(330, 25)
    self.NameEditHitBox:SetPoint("TOPLEFT", self.NameLabel, "BOTTOMLEFT", 0, -5)
    self.NameEditHitBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    self.NameEditHitBox:SetBackdropColor(0, 0, 0, 0.5)

    self.NameEdit = CreateFrame("EditBox", nil, self.NameEditHitBox)
    self.NameEdit:SetSize(320, 25)
    self.NameEdit:SetPoint("CENTER")
    self.NameEdit:SetFontObject("ChatFontNormal")
    self.NameEdit:SetAutoFocus(false)
    self.NameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- -- Macro Body ScrollFrame + EditBox
    self.BodyLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.BodyLabel:SetPoint("TOPLEFT", self.NameEditHitBox, "BOTTOMLEFT", 0, -10)
    self.BodyLabel:SetText("Macro Body:")

    self.BodyScroll = CreateFrame("ScrollFrame", nil, self.DetailFrame, "UIPanelScrollFrameTemplate")
    self.BodyScroll:SetSize(300, 200) -- Slightly narrower to make room for scrollbar
    self.BodyScroll:SetPoint("TOPLEFT", self.BodyLabel, "BOTTOMLEFT", 0, -5)

    -- Background for Body HitBox
    self.BodyBackdrop = CreateFrame("Frame", nil, self.DetailFrame, "BackdropTemplate")
    self.BodyBackdrop:SetPoint("TOPLEFT", self.BodyScroll, -5, 5)
    self.BodyBackdrop:SetPoint("BOTTOMRIGHT", self.BodyScroll, 25, -5) -- Extend to cover scrollbar area roughly
    self.BodyBackdrop:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    self.BodyBackdrop:SetBackdropColor(0, 0, 0, 0.5)
    self.BodyBackdrop:SetFrameLevel(self.DetailFrame:GetFrameLevel())
    self.BodyScroll:SetFrameLevel(self.BodyBackdrop:GetFrameLevel() + 1)


    self.BodyEdit = CreateFrame("EditBox", nil, self.BodyScroll)
    self.BodyEdit:SetSize(295, 200)
    self.BodyEdit:SetMultiLine(true)
    self.BodyEdit:SetFontObject("ChatFontNormal")
    self.BodyEdit:SetAutoFocus(false)
    self.BodyEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    
    self.BodyScroll:SetScrollChild(self.BodyEdit)
    
    -- Map globals for logic access
    SMM.NameEdit = self.NameEdit
    SMM.BodyEdit = self.BodyEdit
    SMM.NameEditHitBox = self.NameEditHitBox
    SMM.BodyBackdrop = self.BodyBackdrop
end

function SMM:CreateButtons()
    -- Buttons
    self.SaveButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.SaveButton:SetSize(80, 25)
    self.SaveButton:SetPoint("BOTTOMRIGHT", 0, 0)
    self.SaveButton:SetText("Save")

    self.DeleteButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.DeleteButton:SetSize(80, 25)
    self.DeleteButton:SetPoint("RIGHT", self.SaveButton, "LEFT", -10, 0)
    self.DeleteButton:SetText("Delete")

    self.NewSharedButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.NewSharedButton:SetSize(100, 25)
    self.NewSharedButton:SetPoint("BOTTOMLEFT", 0, 0)
    self.NewSharedButton:SetText("New Global")

    self.NewCharButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.NewCharButton:SetSize(100, 25)
    self.NewCharButton:SetPoint("LEFT", self.NewSharedButton, "RIGHT", 10, 0)
    self.NewCharButton:SetText("New Char")
    
    -- Map globals for logic
    SMM.SaveButton = self.SaveButton
    SMM.DeleteButton = self.DeleteButton
    SMM.NewSharedButton = self.NewSharedButton
    SMM.NewCharButton = self.NewCharButton
end

function SMM:RegisterEvents()
    self:RegisterEvent("UPDATE_MACROS")
    self:SetScript("OnEvent", function(self, event, ...)
        if event == "UPDATE_MACROS" then
            self:RefreshList()
        end
    end)
end

function SMM:SetupButtonActions()
    self.SaveButton:SetScript("OnClick", function()
        if self.SelectedMacroIndex then
            local name = self.NameEdit:GetText()
            local body = self.BodyEdit:GetText()
            local _, icon = GetMacroInfo(self.SelectedMacroIndex)
            
            EditMacro(self.SelectedMacroIndex, name, icon, body)
        end
    end)

    self.NewSharedButton:SetScript("OnClick", function()
        -- Defaults: Name "New Macro", Icon "INV_Misc_QuestionMark", Body ""
        -- 134400 is the file ID for the question mark
        CreateMacro("New Macro", 134400, "", false) -- false = global
    end)

    self.NewCharButton:SetScript("OnClick", function()
        CreateMacro("New Macro", 134400, "", true) -- true = per character
    end)

    self.DeleteButton:SetScript("OnClick", function()
        if self.SelectedMacroIndex then
            DeleteMacro(self.SelectedMacroIndex)
            self.SelectedMacroIndex = nil
            self:SetDetailViewEnabled(false)
        end
    end)
end

function SMM:SetDetailViewEnabled(enabled)
    if enabled then
        self.NameEdit:Enable()
        self.BodyEdit:Enable()
        self.SaveButton:Enable()
        self.DeleteButton:Enable()
        self.NameEditHitBox:SetAlpha(1)
        self.BodyBackdrop:SetAlpha(1)
    else
        self.NameEdit:SetText("")
        self.BodyEdit:SetText("")
        self.NameEdit:Disable()
        self.BodyEdit:Disable()
        self.SaveButton:Disable()
        self.DeleteButton:Disable()
        self.NameEditHitBox:SetAlpha(0.5)
        self.BodyBackdrop:SetAlpha(0.5)
    end
end

-- ----------------------------------------------------------------------------------------------------------------------------------------------------------
-- LOGIC & HELPERS
-- ----------------------------------------------------------------------------------------------------------------------------------------------------------

function SMM:GetListButton()
    local btn = table.remove(self.FramePool)
    if not btn then
        btn = CreateFrame("Button", nil, self.ListContent)
        btn:SetSize(180, 20) -- BUTTON_HEIGHT = 20
        
        -- Highlight texture
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(btn)
        highlight:SetColorTexture(1, 1, 1, 0.2)
        
        -- Text
        btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
        btn.Text:SetPoint("LEFT", 5, 0)
    end
    
    btn:Show()
    btn:SetParent(self.ListContent)
    return btn
end

function SMM:RecycleListButton(btn)
    btn:Hide()
    btn:SetParent(nil)
    table.insert(self.FramePool, btn)
end

function SMM:RefreshList()
    -- Recycle current list
    for _, btn in ipairs(self.MacroList) do
        self:RecycleListButton(btn)
    end

    self.MacroList = {}
    local globalCount, charCount = GetNumMacros()
    local yOffset = 0
    local BUTTON_HEIGHT = 20
    
    -- Helper to configure list buttons
    local function ConfigureListButton(index, isLocal)
        local apiIndex = index
        if isLocal then
            apiIndex = 120 + index
        end

        local name, icon, body = GetMacroInfo(apiIndex)
        
        if not name then return end

        -- Filter Logic
        local filterText = self.SearchBox and self.SearchBox:GetText():lower() or ""
        if filterText ~= "" and not string.find(name:lower(), filterText, 1, true) then
            return
        end

        local btn = self:GetListButton()
        btn:SetPoint("TOPLEFT", 5, yOffset)
        btn.Text:SetText((isLocal and "|cff00ccff[C]|r " or "|cffffd700[G]|r ") .. name)
        
        -- Click Handler
        btn:SetScript("OnClick", function()
            self.SelectedMacroIndex = apiIndex
            self.SelectedMacroIsLocal = isLocal
            
            -- Populate Details
            self.NameEdit:SetText(name)
            self.BodyEdit:SetText(body)
            self:SetDetailViewEnabled(true)
        end)

        table.insert(self.MacroList, btn)
        yOffset = yOffset - BUTTON_HEIGHT
    end

    -- Global Macros
    for i = 1, globalCount do
        ConfigureListButton(i, false)
    end
    
    -- Separator space
    if globalCount > 0 and charCount > 0 then
        yOffset = yOffset - 5
    end

    -- Character Macros
    for i = 1, charCount do
        ConfigureListButton(i, true)
    end

    self.ListContent:SetHeight(math.abs(yOffset) + 20)
end

function SMM:SetupSlashCommand()
    SLASH_SMM1 = "/smm"
    SlashCmdList["SMM"] = function(msg)
        if SMM:IsShown() then
            SMM:Hide()
        else
            SMM:Show()
            SMM:RefreshList()
        end
    end
end

SMM:RunAddonLifeCycle()


