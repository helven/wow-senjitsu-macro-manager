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
SMM.HeaderPool = {} -- Pool for header buttons
SMM.ActiveHeaders = {} -- Currently active headers
SMM.Groups = { Global = true, Char = true } -- Expansion state

function SMM:RunAddonLifeCycle()
    SMM:InitializeLayout()
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

function SMM:InitializeLayout()
    SMM.ScreenWidth = UIParent:GetWidth()
    SMM.ScreenHeight = UIParent:GetHeight()
    
    SMM.TargetWidth = 800
    SMM.TargetHeight = 600
    
    SMM.MaxWidthAllowed = SMM.ScreenWidth * 0.8
    SMM.MaxHeightAllowed = SMM.ScreenHeight * 0.8
    
    SMM.FinalWidth = math.min(SMM.TargetWidth, SMM.MaxWidthAllowed)
    SMM.FinalHeight = math.min(SMM.TargetHeight, SMM.MaxHeightAllowed)
    
    -- Layout Constants
    SMM.Padding = 20
    SMM.TopPadding = 50 
    SMM.BottomPadding = 30 
    
    -- Adjusted to prevent scrollbar overlap
    -- List (28%) + Scrollbar gap (~5%) + Detail (55%) = 88% < 100%
    SMM.ListWidth = SMM.FinalWidth * 0.35 
    SMM.DetailWidth = SMM.FinalWidth * 0.55 
    
    SMM.ListHeight = SMM.FinalHeight - SMM.TopPadding - SMM.BottomPadding - 20
    SMM.DetailHeight = SMM.FinalHeight - 50 
end

function SMM:CreateMainFrame()
    -- Basic Frame Properties
    self:SetSize(SMM.FinalWidth, SMM.FinalHeight)
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
    local searchWidth = SMM.ListWidth - 50
    self.SearchHitBox:SetSize(searchWidth, 20)
    self.SearchHitBox:SetPoint("LEFT", self.SearchLabel, "RIGHT", 5, 0)
    self.SearchHitBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    self.SearchHitBox:SetBackdropColor(0, 0, 0, 0.5)

    self.SearchBox = CreateFrame("EditBox", nil, self.SearchHitBox)
    self.SearchBox:SetSize(searchWidth - 10, 20)
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
    self.ListScroll:SetSize(SMM.ListWidth, SMM.ListHeight) 
    self.ListScroll:SetPoint("TOPLEFT", 20, -75) -- Push down a bit to clear Search

    self.ListContent = CreateFrame("Frame", nil, self.ListScroll)
    self.ListContent:SetSize(SMM.ListWidth, SMM.ListHeight)
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
    -- Start at -40. Height needs to ensure Bottom is at SMM.BottomPadding from MainFrame Bottom
    -- MainFrame Height = H. Top = 0.
    -- DetailFrame Top = -40.
    -- Desired Bottom = H - 20 (Padding).
    -- Height = (H - 20) - 40 = H - 60.
    local safeHeight = SMM.FinalHeight - 60
    self.DetailFrame:SetSize(SMM.DetailWidth, safeHeight)
    self.DetailFrame:SetPoint("TOPRIGHT", -25, -40) -- Extra right padding

    -- Type Selection (Radio Buttons)
    self.TypeLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.TypeLabel:SetPoint("TOPLEFT", 0, 0)
    self.TypeLabel:SetText("Type:")

    self.TypeGlobal = CreateFrame("CheckButton", nil, self.DetailFrame, "UIRadioButtonTemplate")
    self.TypeGlobal:SetPoint("LEFT", self.TypeLabel, "RIGHT", 10, 0)
    self.TypeGlobal.text = self.TypeGlobal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.TypeGlobal.text:SetPoint("LEFT", self.TypeGlobal, "RIGHT", 5, 0)
    self.TypeGlobal.text:SetText("General")
    self.TypeGlobal:SetChecked(true)

    self.TypeChar = CreateFrame("CheckButton", nil, self.DetailFrame, "UIRadioButtonTemplate")
    self.TypeChar:SetPoint("LEFT", self.TypeGlobal.text, "RIGHT", 15, 0)
    self.TypeChar.text = self.TypeChar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.TypeChar.text:SetPoint("LEFT", self.TypeChar, "RIGHT", 5, 0)
    self.TypeChar.text:SetText("Character")
    
    -- Radio Logic
    self.TypeGlobal:SetScript("OnClick", function()
        self.TypeGlobal:SetChecked(true)
        self.TypeChar:SetChecked(false)
    end)
    self.TypeChar:SetScript("OnClick", function()
        self.TypeChar:SetChecked(true)
        self.TypeGlobal:SetChecked(false)
    end)

    -- -- Macro Name EditBox
    self.NameLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.NameLabel:SetPoint("TOPLEFT", self.TypeLabel, "BOTTOMLEFT", 0, -20)
    self.NameLabel:SetText("Name:")

    self.NameEditHitBox = CreateFrame("Frame", nil, self.DetailFrame, "BackdropTemplate")
    self.NameEditHitBox:SetSize(SMM.DetailWidth, 25)
    self.NameEditHitBox:SetPoint("TOPLEFT", self.NameLabel, "BOTTOMLEFT", 0, -5)
    self.NameEditHitBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    self.NameEditHitBox:SetBackdropColor(0, 0, 0, 0.5)

    self.NameEdit = CreateFrame("EditBox", nil, self.NameEditHitBox)
    self.NameEdit:SetSize(SMM.DetailWidth - 10, 25)
    self.NameEdit:SetPoint("CENTER")
    self.NameEdit:SetFontObject("ChatFontNormal")
    self.NameEdit:SetAutoFocus(false)
    self.NameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- -- Macro Body ScrollFrame + EditBox
    self.BodyLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.BodyLabel:SetPoint("TOPLEFT", self.NameEditHitBox, "BOTTOMLEFT", 0, -10)
    self.BodyLabel:SetText("Body:")

    -- Background for Body HitBox (Created first to establish alignment)
    self.BodyBackdrop = CreateFrame("Frame", nil, self.DetailFrame, "BackdropTemplate")
    -- Dynamic Height: Detail Frame Height - Top Elements (~100) - Bottom Buttons (30) - Padding
    -- Top Elements: ~90px (Radio + Name)
    -- Buttons: 25px
    -- Padding: ~20px
    local bodyHeight = safeHeight - 140 
    self.BodyBackdrop:SetSize(SMM.DetailWidth, bodyHeight) 
    self.BodyBackdrop:SetPoint("TOPLEFT", self.BodyLabel, "BOTTOMLEFT", 0, -5)
    self.BodyBackdrop:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    self.BodyBackdrop:SetBackdropColor(0, 0, 0, 0.5)
    
    -- Click-to-focus behavior for the background
    self.BodyBackdrop:EnableMouse(true)
    self.BodyBackdrop:SetScript("OnMouseDown", function()
        self.BodyEdit:SetFocus()
    end)

    -- ScrollFrame anchored inside the backdrop
    self.BodyScroll = CreateFrame("ScrollFrame", nil, self.DetailFrame, "UIPanelScrollFrameTemplate")
    self.BodyScroll:SetPoint("TOPLEFT", self.BodyBackdrop, "TOPLEFT", 5, -5)
    self.BodyScroll:SetPoint("BOTTOMRIGHT", self.BodyBackdrop, "BOTTOMRIGHT", -25, 5)
    self.BodyScroll:SetFrameLevel(self.BodyBackdrop:GetFrameLevel() + 1)


    self.BodyEdit = CreateFrame("EditBox", nil, self.BodyScroll)
    self.BodyEdit:SetSize(SMM.DetailWidth - 35, bodyHeight) -- Match new height
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
    SMM.TypeGlobal = self.TypeGlobal
    SMM.TypeChar = self.TypeChar
end

function SMM:CreateButtons()
    -- Buttons
    -- Delete Button (Far Right)
    self.DeleteButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.DeleteButton:SetSize(80, 25)
    self.DeleteButton:SetPoint("BOTTOMRIGHT", 0, 0)
    self.DeleteButton:SetText("Delete")

    -- Save Button (Left of Delete)
    self.SaveButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.SaveButton:SetSize(80, 25)
    self.SaveButton:SetPoint("RIGHT", self.DeleteButton, "LEFT", -10, 0)
    self.SaveButton:SetText("Save")

    -- New Button (Far Left)
    self.NewButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.NewButton:SetSize(100, 25)
    self.NewButton:SetPoint("BOTTOMLEFT", 0, 0)
    self.NewButton:SetText("New")
    
    -- Map globals for logic
    SMM.SaveButton = self.SaveButton
    SMM.DeleteButton = self.DeleteButton
    SMM.NewButton = self.NewButton
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
        local name = self.NameEdit:GetText()
        if name == "" then return end 

        local body = self.BodyEdit:GetText()
        
        if self.SelectedMacroIndex then
            -- Update existing
            local _, currentIcon = GetMacroInfo(self.SelectedMacroIndex)
            EditMacro(self.SelectedMacroIndex, name, currentIcon, body)
        else
            -- Create new
            local icon = 134400 -- Default QuestionMark
            local isLocal = self.TypeChar:GetChecked()
            CreateMacro(name, icon, body, isLocal)
            -- After creation, CreateMacro triggers UPDATE_MACROS which refreshes list
            -- User might want to stay in edit mode for this new macro?
            -- RefreshList resets selection to nil usually... 
            -- We might want to handle preserving selection later, but for now this fits requirements.
            self.NameEdit:SetText("")
            self.BodyEdit:SetText("")
        end
    end)

    self.NewButton:SetScript("OnClick", function()
        self.SelectedMacroIndex = nil
        self:SetDetailViewEnabled(false) -- Reset view
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
    self.NameEdit:Enable()
    self.BodyEdit:Enable()
    self.SaveButton:Enable()
    self.NameEditHitBox:SetAlpha(1)
    self.BodyBackdrop:SetAlpha(1)
    
    if enabled then
        -- Edit Mode
        self.DeleteButton:Enable()
        self.TypeGlobal:Disable() -- Usually you can't change macro type after creation easily without recreation
        self.TypeChar:Disable()
    else
        -- Create/Reset Mode
        self.NameEdit:SetText("")
        self.BodyEdit:SetText("")
        self.DeleteButton:Disable()
        self.TypeGlobal:Enable()
        self.TypeChar:Enable()
        self.TypeGlobal:SetChecked(true)
        self.TypeChar:SetChecked(false)
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
        
        -- Icon
        btn.Icon = btn:CreateTexture(nil, "ARTWORK")
        btn.Icon:SetSize(18, 18)
        btn.Icon:SetPoint("LEFT", 0, 0)
        
        -- Text
        btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
        btn.Text:SetPoint("LEFT", 22, 0)
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

function SMM:GetHeaderButton()
    local btn = table.remove(self.HeaderPool)
    if not btn then
        btn = CreateFrame("Button", nil, self.ListContent)
        btn:SetSize(180, 20)
        
        -- Expand/Collapse Texture
        btn.ExpandIcon = btn:CreateTexture(nil, "ARTWORK")
        btn.ExpandIcon:SetSize(14, 14)
        btn.ExpandIcon:SetPoint("RIGHT", -5, 0)
        
        -- Text
        btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.Text:SetPoint("LEFT", 5, 0)
        btn.Text:SetPoint("RIGHT", btn.ExpandIcon, "LEFT", -5, 0)
        btn.Text:SetJustifyH("LEFT")
        
        -- Clickable area
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")
        
        -- Highlight
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(btn)
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    btn:Show()
    btn:SetParent(self.ListContent)
    return btn
end

function SMM:RecycleHeaderButton(btn)
    btn:Hide()
    btn:SetParent(nil)
    table.insert(self.HeaderPool, btn)
end

function SMM:RefreshList()
    -- Recycle current list
    for _, btn in ipairs(self.MacroList) do
        self:RecycleListButton(btn)
    end
    self.MacroList = {}

    -- Recycle headers
    for _, btn in ipairs(self.ActiveHeaders) do
        self:RecycleHeaderButton(btn)
    end
    self.ActiveHeaders = {}

    local globalCount, charCount = GetNumMacros()
    local yOffset = 0
    local BUTTON_HEIGHT = 20
    
    -- Filter check
    local filterText = self.SearchBox and self.SearchBox:GetText():lower() or ""
    local isFiltering = filterText ~= ""

    -- Helper to configure list buttons
    local function ConfigureListButton(index, isLocal)
        local apiIndex = index
        if isLocal then
            apiIndex = 120 + index
        end

        local name, icon, body = GetMacroInfo(apiIndex)
        
        if not name then return end

        -- Filter Logic
        if isFiltering and not string.find(name:lower(), filterText, 1, true) then
            return
        end

        local btn = self:GetListButton()
        btn:SetPoint("TOPLEFT", 10, yOffset) -- Indented slightly
        btn:SetSize(SMM.ListWidth - 30, BUTTON_HEIGHT) 
        btn.Icon:SetTexture(icon)
        -- Removed [G]/[C] prefix as headers provide context
        btn.Text:SetText(name)
        
        -- Click Handler
        btn:SetScript("OnClick", function()
            self.SelectedMacroIndex = apiIndex
            self.SelectedMacroIsLocal = isLocal
            
            -- Populate Details
            self.NameEdit:SetText(name)
            self.BodyEdit:SetText(body)
            
            self.TypeGlobal:SetChecked(not isLocal)
            self.TypeChar:SetChecked(isLocal)
            
            self:SetDetailViewEnabled(true)
        end)

        table.insert(self.MacroList, btn)
        yOffset = yOffset - BUTTON_HEIGHT
    end

    -- Header Helper
    local function AddHeader(label, count, max, groupKey)
        -- If filtering, always show content, maybe hide header or keep it? 
        -- Keeping it helps context.
        
        local btn = self:GetHeaderButton()
        btn:SetPoint("TOPLEFT", 0, yOffset)
        btn:SetSize(SMM.ListWidth - 10, 20)
        
        local isExpanded = SMM.Groups[groupKey] or isFiltering -- Auto expand on filter
        
        btn.Text:SetText(string.format("%s (%d/%d)", label, count, max))
        btn.ExpandIcon:SetTexture(isExpanded 
            and "Interface\\Buttons\\UI-MinusButton-Up" 
            or "Interface\\Buttons\\UI-PlusButton-Up")
        
        btn:SetScript("OnClick", function()
            SMM.Groups[groupKey] = not SMM.Groups[groupKey]
            SMM:RefreshList()
        end)
        
        table.insert(self.ActiveHeaders, btn)
        yOffset = yOffset - 20
        return isExpanded
    end

    -- Global Macros
    if AddHeader("General Macros", globalCount, MAX_ACCOUNT_MACROS or 120, "Global") then
        for i = 1, globalCount do
            ConfigureListButton(i, false)
        end
    end
    
    -- Character Macros
    if AddHeader("Character Macros", charCount, MAX_CHARACTER_MACROS or 18, "Char") then
        for i = 1, charCount do
            ConfigureListButton(i, true)
        end
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


