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
SMM.IconBrowserTargetIconX = 12
SMM.IconBrowserTargetIconY = 10
SMM.WorkIcon = 134400 -- Default QuestionMark

function SMM:RunAddonLifeCycle()
    SMM:InitializeLayout()
    SMM:CreateMainFrame()
    SMM:CreateListView()
    SMM:CreateDetailView()
    SMM:CreateButtons()
    SMM:RegisterEvents()
    SMM:SetupButtonActions()
    SMM:SetFormMode("create")
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
    -- List (35%) + Scrollbar gap + Detail (55%) = ~90% < 100%
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
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
        tile = true, tileSize = 32, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    -- [[ OPACITY CONTROL: Change the last number to 0.8 for transparent black ]]
    self:SetBackdropColor(0, 0, 0, 0.8)

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
    self.SearchBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.SearchBox:SetScript("OnTextChanged", function()
        SMM:RefreshList()
    end)

    -- ScrollFrame (List View)
    self.ListScroll = CreateFrame("ScrollFrame", nil, self, "UIPanelScrollFrameTemplate")
    self.ListScroll:SetSize(SMM.ListWidth, SMM.ListHeight) 
    self.ListScroll:SetPoint("TOPLEFT", 20, -75) -- Push down a bit to clear Search

    self.ListContent = CreateFrame("Frame", nil, self.ListScroll)
    self.ListContent:SetSize(SMM.ListWidth, SMM.ListHeight)
    self.ListScroll:SetScrollChild(self.ListContent)
    
    self.ListScroll:SetScript("OnMouseWheel", function(scroll, delta)
        local check = scroll:GetVerticalScroll() - (delta * 20)
        if check < 0 then check = 0 end
        if check > scroll:GetVerticalScrollRange() then check = scroll:GetVerticalScrollRange() end
        scroll:SetVerticalScroll(check)
    end)
    
    -- Map globals for logic access
    SMM.SearchBox = self.SearchBox
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
    self.TypeGlobal:SetHitRectInsets(0, -self.TypeGlobal.text:GetStringWidth() - 5, 0, 0)
    self.TypeGlobal:SetChecked(true)

    self.TypeChar = CreateFrame("CheckButton", nil, self.DetailFrame, "UIRadioButtonTemplate")
    self.TypeChar:SetPoint("LEFT", self.TypeGlobal.text, "RIGHT", 15, 0)
    self.TypeChar.text = self.TypeChar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.TypeChar.text:SetPoint("LEFT", self.TypeChar, "RIGHT", 5, 0)
    self.TypeChar.text:SetText("Character")
    self.TypeChar:SetHitRectInsets(0, -self.TypeChar.text:GetStringWidth() - 5, 0, 0)
    
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

    self.NameCountLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.NameCountLabel:SetPoint("LEFT", self.NameLabel, "RIGHT", 5, 0)
    self.NameCountLabel:SetText("(0/16) characters used")

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
    self.NameEdit:SetMaxLetters(16)
    self.NameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.NameEdit:SetScript("OnTextChanged", function(self)
        SMM.NameCountLabel:SetText(format("(%d/16) characters used", #self:GetText()))
    end)
    
    -- Hook SetText to update label manually
    self.NameEdit.OriginalSetText = self.NameEdit.SetText
    function self.NameEdit:SetText(text)
        self.OriginalSetText(self, text)
        SMM.NameCountLabel:SetText(format("(%d/16) characters used", #(text or "")))
    end

    -- -- Icon Selection
    self.IconLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.IconLabel:SetPoint("TOPLEFT", self.NameEditHitBox, "BOTTOMLEFT", 0, -10)
    self.IconLabel:SetText("Icon:")

    self.IconPreview = self.DetailFrame:CreateTexture(nil, "ARTWORK")
    self.IconPreview:SetSize(36, 36)
    self.IconPreview:SetPoint("TOPLEFT", self.IconLabel, "BOTTOMLEFT", 0, -5)
    self.IconPreview:SetTexture(SMM.WorkIcon)

    self.SelectIconButton = CreateFrame("Button", nil, self.DetailFrame, "UIPanelButtonTemplate")
    self.SelectIconButton:SetSize(100, 25)
    self.SelectIconButton:SetPoint("LEFT", self.IconPreview, "RIGHT", 10, 0)
    self.SelectIconButton:SetText("Select Icon")
    self.SelectIconButton:SetScript("OnClick", function()
        SMM:ShowIconBrowser()
    end)

    self.ResetIconButton = CreateFrame("Button", nil, self.DetailFrame, "UIPanelButtonTemplate")
    self.ResetIconButton:SetSize(100, 25)
    self.ResetIconButton:SetPoint("LEFT", self.SelectIconButton, "RIGHT", 5, 0)
    self.ResetIconButton:SetText("Reset Icon")
    self.ResetIconButton:SetScript("OnClick", function()
        SMM.WorkIcon = 134400
        if SMM.IconPreview then
             SMM.IconPreview:SetTexture(SMM.WorkIcon)
        end
        SMM:UpdateResetIconState()
    end)

    -- -- Macro Body ScrollFrame + EditBox
    self.BodyLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.BodyLabel:SetPoint("TOPLEFT", self.IconPreview, "BOTTOMLEFT", 0, -10)
    self.BodyLabel:SetText("Body:")

    self.BodyCountLabel = self.DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.BodyCountLabel:SetPoint("LEFT", self.BodyLabel, "RIGHT", 5, 0)
    self.BodyCountLabel:SetText("(0/255) characters used")

    -- Background for Body HitBox (Created first to establish alignment)
    self.BodyBackdrop = CreateFrame("Frame", nil, self.DetailFrame, "BackdropTemplate")
    -- Dynamic Height: Detail Frame Height - Top Elements (~100) - Bottom Buttons (30) - Padding
    -- Top Elements: ~90px (Radio + Name) + 60px (Icon) ~ 150px
    -- Buttons: 25px
    -- Padding: ~20px
    local bodyHeight = (SMM.FinalHeight - 60) - 200 
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
    self.BodyEdit:SetMaxLetters(255)
    self.BodyEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.BodyEdit:SetScript("OnTextChanged", function(self)
        SMM.BodyCountLabel:SetText(format("(%d/255) characters used", #self:GetText()))
    end)

    -- Hook SetText
    self.BodyEdit.OriginalSetText = self.BodyEdit.SetText
    function self.BodyEdit:SetText(text)
        self.OriginalSetText(self, text)
        SMM.BodyCountLabel:SetText(format("(%d/255) characters used", #(text or "")))
    end
    
    self.BodyScroll:SetScrollChild(self.BodyEdit)
    
    -- Map globals for logic access
    SMM.NameEdit = self.NameEdit
    SMM.BodyEdit = self.BodyEdit
    SMM.NameEditHitBox = self.NameEditHitBox
    SMM.BodyBackdrop = self.BodyBackdrop
    SMM.TypeGlobal = self.TypeGlobal
    SMM.TypeChar = self.TypeChar
    SMM.IconPreview = self.IconPreview
    SMM.NameCountLabel = self.NameCountLabel
    SMM.BodyCountLabel = self.BodyCountLabel
    SMM.ResetIconButton = self.ResetIconButton
end

function SMM:CreateButtons()
    -- Helper to standardise button text states
    local function ConfigureButton(btn, r, g, b)
        -- Hook state changes to enforce colors
        btn:HookScript("OnEnable", function(self)
            self:GetFontString():SetTextColor(r, g, b)
        end)
        btn:HookScript("OnDisable", function(self)
            self:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end)
        
        -- Apply initial
        if btn:IsEnabled() then
            btn:GetFontString():SetTextColor(r, g, b)
        else
            btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end
    end

    -- Buttons
    -- Delete Button (Far Right)
    self.DeleteButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.DeleteButton:SetSize(80, 25)
    self.DeleteButton:SetPoint("BOTTOMRIGHT", 0, 0)
    self.DeleteButton:SetText("Delete")
    ConfigureButton(self.DeleteButton, 1, 1, 1)

    -- Save Button (Left of Delete)
    self.SaveButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.SaveButton:SetSize(80, 25)
    self.SaveButton:SetPoint("RIGHT", self.DeleteButton, "LEFT", -10, 0)
    self.SaveButton:SetText("Save")
    ConfigureButton(self.SaveButton, 1, 1, 0)

    -- Cancel Button (Left of Save)
    self.CancelButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.CancelButton:SetSize(80, 25)
    self.CancelButton:SetPoint("RIGHT", self.SaveButton, "LEFT", -10, 0)
    self.CancelButton:SetText("Cancel")
    ConfigureButton(self.CancelButton, 1, 1, 0)

    -- New Button (Far Left)
    self.NewButton = CreateFrame("Button", nil, self.DetailFrame, "GameMenuButtonTemplate")
    self.NewButton:SetSize(100, 25)
    self.NewButton:SetPoint("BOTTOMLEFT", 0, 0)
    self.NewButton:SetText("New")
    ConfigureButton(self.NewButton, 1, 1, 0)
    
    -- Map globals for logic
    SMM.SaveButton = self.SaveButton
    SMM.DeleteButton = self.DeleteButton
    SMM.NewButton = self.NewButton
    SMM.CancelButton = self.CancelButton
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
        local icon = SMM.WorkIcon or 134400
        
        if self.SelectedMacroIndex then
            local isLocal = self.TypeChar:GetChecked()
            -- Check if type changed (Global <-> Character)
            if self.SelectedMacroIsLocal ~= isLocal then 
                 self:SwapMacro()
            else
                 self:UpdateMacro(self.SelectedMacroIndex, name, icon, body)
            end
        else
            -- Create new
            local isLocal = self.TypeChar:GetChecked()
            self:NewMacro(name, icon, body, isLocal)
        end
    end)

    self.NewButton:SetScript("OnClick", function()
        self.SelectedMacroIndex = nil
        SMM.WorkIcon = 134400
        self.IconPreview:SetTexture(134400)
        self:SetFormMode("create") -- Reset view
    end)

    self.DeleteButton:SetScript("OnClick", function()
        if self.SelectedMacroIndex then
            DeleteMacro(self.SelectedMacroIndex)
            self.SelectedMacroIndex = nil
            self:SetFormMode("create")
        end
    end)

    self.CancelButton:SetScript("OnClick", function()
        if self.SelectedMacroIndex then
            -- EDIT MODE: Reset to saved data
            local name, icon, body = GetMacroInfo(self.SelectedMacroIndex)
            if name then
                self.NameEdit:SetText(name)
                self.BodyEdit:SetText(body)
                SMM.WorkIcon = icon
                self.IconPreview:SetTexture(icon)
                
                -- Reset Type Selection
                self.TypeGlobal:SetChecked(not self.SelectedMacroIsLocal)
                self.TypeChar:SetChecked(self.SelectedMacroIsLocal)
            end
        else
            -- CREATE MODE: Clear form
            self.NameEdit:SetText("")
            self.BodyEdit:SetText("")
            SMM.WorkIcon = 134400
            self.IconPreview:SetTexture(134400)
            self.TypeGlobal:SetChecked(true)
            self.TypeChar:SetChecked(false)
        end
        SMM:UpdateCancelState()
        SMM:UpdateResetIconState()
    end)
    
    -- Hook for text changes to update Cancel button state
    self.NameEdit:HookScript("OnTextChanged", function() SMM:UpdateCancelState() end)
    self.BodyEdit:HookScript("OnTextChanged", function() SMM:UpdateCancelState() end)
end

function SMM:UpdateResetIconState()
    -- Default/Empty icon is 134400 (Question Mark)
    local isDefault = (SMM.WorkIcon == 134400) or (SMM.WorkIcon == nil)
    
    if isDefault then
        SMM.ResetIconButton:Disable()
    else
        SMM.ResetIconButton:Enable()
    end
end

function SMM:UpdateCancelState()
    if SMM.SelectedMacroIndex then
        -- Always enabled in Edit Mode (to reset changes)
        SMM.CancelButton:Enable()
    else
        -- Create Mode: Enable only if there is text
        local hasText = (SMM.NameEdit:GetText() ~= "") or (SMM.BodyEdit:GetText() ~= "")
        if hasText then
            SMM.CancelButton:Enable()
        else
            SMM.CancelButton:Disable()
        end
    end
end

function SMM:SetFormMode(mode)
    self.NameEdit:Enable()
    self.BodyEdit:Enable()
    self.SaveButton:Enable()
    self.NameEditHitBox:SetAlpha(1)
    self.BodyBackdrop:SetAlpha(1)
    
    if mode == "edit" then
        -- Edit Mode: Existing macro selected
        self.DeleteButton:Enable()
        self.TypeGlobal:Enable()
        self.TypeChar:Enable()
        SMM:UpdateCancelState()
        SMM:UpdateResetIconState()
    elseif mode == "create" then
        -- Create Mode: Clear form for new macro
        self.NameEdit:SetText("")
        self.BodyEdit:SetText("")
        self.DeleteButton:Disable()
        self.TypeGlobal:Enable()
        self.TypeChar:Enable()
        SMM:UpdateCancelState()
        self.TypeGlobal:SetChecked(true)
        self.TypeChar:SetChecked(false)
        
        SMM.WorkIcon = 134400
        self.IconPreview:SetTexture(134400)
        self.SelectIconButton:Enable()
        SMM:UpdateResetIconState()
    end
end

-- -----------------------------------------------------------------------------
-- MACRO CRUD OPERATIONS
-- -----------------------------------------------------------------------------

function SMM:NewMacro(name, icon, body, isLocal)
    -- Check Limits to prevent "CreateMacro() failed" error
    local numGlobal, numChar = GetNumMacros()
    local limitGlobal = MAX_ACCOUNT_MACROS or 120
    local limitChar = MAX_CHARACTER_MACROS or 30 
    
    if isLocal then
        if numChar >= limitChar then
            print("|cffff0000SMM Error:|r Character Macro Limit Reached ("..numChar.."/"..limitChar.."). Cannot create.")
            return
        end
    else
        if numGlobal >= limitGlobal then
            print("|cffff0000SMM Error:|r Global Macro Limit Reached ("..numGlobal.."/"..limitGlobal.."). Cannot create.")
            return
        end
    end
    
    CreateMacro(name, icon, body, isLocal)

    -- Reset UI after creation
    self.NameEdit:SetText("")
    self.BodyEdit:SetText("")
    self.IconPreview:SetTexture(134400)
    SMM.WorkIcon = 134400
end

function SMM:UpdateMacro(index, name, icon, body)
    EditMacro(index, name, icon, body)
end

function SMM:SwapMacro()
    -- 1. Gather Data
    local name = self.NameEdit:GetText()
    local body = self.BodyEdit:GetText()
    local icon = SMM.WorkIcon or 134400
    local targetIsLocal = self.TypeChar:GetChecked() 
    
    -- 2. Check Limits for TARGET
    local numGlobal, numChar = GetNumMacros()
    local limitGlobal = MAX_ACCOUNT_MACROS or 120
    local limitChar = MAX_CHARACTER_MACROS or 30 
    
    if targetIsLocal then
        if numChar >= limitChar then
            print("|cffff0000SMM Error:|r Character Macro Limit Reached ("..numChar.."/"..limitChar.."). Cannot move.")
            return
        end
    else
        if numGlobal >= limitGlobal then
            print("|cffff0000SMM Error:|r Global Macro Limit Reached ("..numGlobal.."/"..limitGlobal.."). Cannot move.")
            return
        end
    end

    local newIndex = CreateMacro(name, icon, body, targetIsLocal)
    
    if newIndex then
        DeleteMacro(self.SelectedMacroIndex)
        
        -- Reset UI
        self.SelectedMacroIndex = nil
        self:SetFormMode("create")
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
        btn.Text:SetTextColor(1, 1, 1)
        
        -- Click Handler
        btn:SetScript("OnClick", function()
            self.SelectedMacroIndex = apiIndex
            self.SelectedMacroIsLocal = isLocal
            
            -- Populate Details
            self.NameEdit:SetText(name)
            self.BodyEdit:SetText(body)
            SMM.WorkIcon = icon
            self.IconPreview:SetTexture(icon)
            
            self.TypeGlobal:SetChecked(not isLocal)
            self.TypeChar:SetChecked(isLocal)
            
            self:SetFormMode("edit")
        end)

        -- Drag Handler
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function()
            PickupMacro(apiIndex)
        end)

        table.insert(self.MacroList, btn)
        yOffset = yOffset - BUTTON_HEIGHT - 3
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

-- ----------------------------------------------------------------------------------------------------------------------------------------------------------
-- ICON BROWSER (Mimicking Default UI)
-- ----------------------------------------------------------------------------------------------------------------------------------------------------------
function SMM:CreateIconBrowser()
    if SMM.IconBrowser then return end

    local frame = CreateFrame("Frame", "SMMIconBrowser", SMM, "BackdropTemplate")
    
    -- Grid Constants
    local COLS = SMM.IconBrowserTargetIconX or 12
    local ROWS = SMM.IconBrowserTargetIconY or 10
    local ICON_SIZE = 36
    local GAP = 4
    local PADDING = 10
    local TOP_HEIGHT = 80 -- Increased spacing for Dropdown
    local BOTTOM_HEIGHT = 10 

    -- Auto-Calculate Width/Height based on Target Grid
    local contentWidth = (COLS * ICON_SIZE) + ((COLS - 1) * GAP)
    local contentHeight = (ROWS * ICON_SIZE) + ((ROWS - 1) * GAP)
    
    local width = PADDING + contentWidth + PADDING + 35 
    local height = TOP_HEIGHT + contentHeight + BOTTOM_HEIGHT + PADDING
    
    frame:SetSize(width, height)
    frame:SetPoint("TOPLEFT", self, "TOPRIGHT", 10, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
        tile = true, tileSize = 32, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    -- [[ OPACITY CONTROL: Change the last number to 0.8 for transparent black ]]
    frame:SetBackdropColor(0, 0, 0, 0.8)

    -- Title
    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Title:SetPoint("TOP", 0, -10)
    frame.Title:SetText("Select Icon")

    -- Close Button
    frame.CloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.CloseButton:SetPoint("TOPRIGHT", -5, -5)
    
    -- Dropdown for Categories
    frame.CategoryDropdown = CreateFrame("Frame", "SMMIconCategoryDropdown", frame, "UIDropDownMenuTemplate")
    frame.CategoryDropdown:SetPoint("TOPRIGHT", -10, -40) -- Moved down slightly
    UIDropDownMenu_SetWidth(frame.CategoryDropdown, 120)
    UIDropDownMenu_SetText(frame.CategoryDropdown, "All Icons")
    
    -- Set Dropdown Button Font to GameFontHighlight (White, Normal Size)
    local dropdownText = _G[frame.CategoryDropdown:GetName().."Text"]
    if dropdownText then
        dropdownText:SetFontObject("GameFontHighlight")
    end
    
    -- Force list alignment to Bottom Left of the trigger, with 20px offset to match visual border
    UIDropDownMenu_SetAnchor(frame.CategoryDropdown, 20, 10, "TOPLEFT", frame.CategoryDropdown, "BOTTOMLEFT")
    
    SMM.CurrentCategory = "ALL" -- Default

    local function OnSelect(item)
        SMM.CurrentCategory = item.value
        UIDropDownMenu_SetText(frame.CategoryDropdown, item:GetText())
        SMM:UpdateIconList(item.value)
        CloseDropDownMenus()
    end

    UIDropDownMenu_Initialize(frame.CategoryDropdown, function(dropdown, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        info.fontObject = GameFontHighlight
        
        info.text = "All Icons"
        info.value = "ALL"
        info.func = OnSelect
        info.checked = (SMM.CurrentCategory == "ALL")
        UIDropDownMenu_AddButton(info)

        info.text = "Spells"
        info.value = "SPELLS"
        info.func = OnSelect
        info.checked = (SMM.CurrentCategory == "SPELLS")
        UIDropDownMenu_AddButton(info)

        info.text = "Items"
        info.value = "ITEMS"
        info.func = OnSelect
        info.checked = (SMM.CurrentCategory == "ITEMS")
        UIDropDownMenu_AddButton(info)
    end)

    -- Scroll Logic
    frame.GridContainer = CreateFrame("Frame", nil, frame)
    frame.GridContainer:SetPoint("TOPLEFT", PADDING + 5, -TOP_HEIGHT)
    frame.GridContainer:SetSize(contentWidth, contentHeight)
    
    frame.ScrollFrame = CreateFrame("ScrollFrame", "SMMIconScroll", frame, "FauxScrollFrameTemplate")
    frame.ScrollFrame:SetPoint("TOPLEFT", frame.GridContainer, "TOPLEFT", 0, 0)
    frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame.GridContainer, "BOTTOMRIGHT", -5, 0) 
    
    frame.ScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 40, function() SMM:UpdateIconGrid() end)
    end)

    -- Force Scrollbar Position
    local scrollBar = _G["SMMIconScrollScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", frame.ScrollFrame, "TOPRIGHT", 10, -16)
        scrollBar:SetPoint("BOTTOMLEFT", frame.ScrollFrame, "BOTTOMRIGHT", 10, 16)
    end
    
    -- Initialize State
    SMM.CurrentIconList = {}
    SMM.IconButtons = {}
    
    -- Create Button Pool
    local numButtons = COLS * ROWS
    for i = 1, numButtons do
        local btn = CreateFrame("Button", nil, frame.GridContainer)
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        
        btn.Icon = btn:CreateTexture(nil, "ARTWORK")
        btn.Icon:SetAllPoints(btn)
        
        btn.Highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.Highlight:SetAllPoints(btn)
        btn.Highlight:SetColorTexture(1, 1, 1, 0.4)
        
        btn:SetScript("OnClick", function()
             SMM.WorkIcon = btn.IconID
             if SMM.IconPreview then SMM.IconPreview:SetTexture(btn.IconID) end
             SMM:UpdateResetIconState()
             frame:Hide()
        end)
        
        -- Layout
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        
        btn:SetPoint("TOPLEFT", col * (ICON_SIZE + GAP), -(row * (ICON_SIZE + GAP)))
        
        table.insert(SMM.IconButtons, btn)
    end
    
    SMM.IconBrowser = frame
end

function SMM:ShowIconBrowser()
    if not SMM.IconBrowser then
        SMM:CreateIconBrowser()
    end
    
    -- Default to All
    SMM:UpdateIconList("ALL")
    SMM.IconBrowser:Show()
end

function SMM:UpdateIconList(category)
    SMM.CurrentIconList = {}
    
    local spellIcons = GetMacroIcons() or {}
    local itemIcons = GetMacroItemIcons() or {}
    
    if category == "ALL" then
         for _, v in ipairs(spellIcons) do table.insert(SMM.CurrentIconList, v) end
         for _, v in ipairs(itemIcons) do table.insert(SMM.CurrentIconList, v) end
    elseif category == "SPELLS" then
         for _, v in ipairs(spellIcons) do table.insert(SMM.CurrentIconList, v) end
    elseif category == "ITEMS" then
         for _, v in ipairs(itemIcons) do table.insert(SMM.CurrentIconList, v) end
    end
    
    SMM:UpdateIconGrid()
end

function SMM:UpdateIconGrid()
    if not SMM.CurrentIconList then return end
    
    local numIcons = #SMM.CurrentIconList
    local scrollFrame = SMMIconScroll
    if not scrollFrame then return end
    
    local offset = FauxScrollFrame_GetOffset(scrollFrame)
    local COLS = SMM.IconBrowserTargetIconX or 12
    local ROWS = SMM.IconBrowserTargetIconY or 10
    local ROW_HEIGHT = 40 
    
    for i, btn in ipairs(SMM.IconButtons) do
        local index = (offset * COLS) + i
        if index <= numIcons then
            local icon = SMM.CurrentIconList[index]
            btn.IconID = icon
            btn.Icon:SetTexture(icon)
            btn:Show()
        else
            btn:Hide()
        end
    end
    
    local totalRows = math.ceil(numIcons / COLS)
    FauxScrollFrame_Update(scrollFrame, totalRows, ROWS, ROW_HEIGHT, nil, nil, nil, nil, nil, nil, true)
end

SMM:RunAddonLifeCycle()


