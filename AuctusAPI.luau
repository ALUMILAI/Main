local AuctusAPI = {}

local HttpService = game:GetService("HttpService")

-- ═══════════════════════════════════════════════════════════════
-- ⌨️ INPUT SIMULATION
-- ═══════════════════════════════════════════════════════════════
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")

function AuctusAPI:SendKey(key: Enum.KeyCode)
    local string_key = tostring(key)

    if not string_key or not string_key:match("Enum.KeyCode.") then
        warn("invalid argument Enum.KeyCode expected")

        return
    end

    VIM:SendKeyEvent(false, key, false, game)
    task.wait()
    VIM:SendKeyEvent(true, key, false, game)
    task.wait()
    VIM:SendKeyEvent(false, key, false, game)
end

function AuctusAPI:ClickButton(btn: GuiButton)
    local is_instance = typeof(btn) == "Instance"

    if not is_instance or not btn:IsA("GuiButton") then
        warn("invalid argument GuiButton expected, got "..(is_instance and btn.ClassName or typeof(btn)))

        return
    end

    GuiService.SelectedObject = btn

    AuctusAPI:SendKey(Enum.KeyCode.Return)
    AuctusAPI:SendKey(Enum.KeyCode.Return)

    GuiService.SelectedObject = nil
end

function AuctusAPI:ExitRobloxMenu(closingYield: number?)
    if GuiService.MenuIsOpen then
        AuctusAPI:SendKey(Enum.KeyCode.Escape)

        if type(closingYield) == "number" then
            task.wait(closingYield)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 🗝️ KEY SYSTEM
-- ═══════════════════════════════════════════════════════════════
local JunkieKeySystem = loadstring(game:HttpGet("https://jnkie.com/sdk/library.lua"))()
JunkieKeySystem.identifier = "14361"
JunkieKeySystem.service = "Get Key!"
JunkieKeySystem.provider = "Get Key!"

local KeySystem = {}
KeySystem.__index = KeySystem

function AuctusAPI.newKeySystem(apiKey: string, serviceName: string, providerName: string)
    return setmetatable({
        ApiKey = apiKey,
        Service = serviceName,
        Provider = providerName
    }, KeySystem)
end

function KeySystem:GetLink()
    return JunkieKeySystem.get_key_link()
end

function KeySystem:ValidateKey(key: string): boolean
    local result = JunkieKeySystem.check_key(key)
    return result and result.valid
end

--- old
function AuctusAPI:GetKeyLink(): string
    return JunkieKeySystem.get_key_link()
end

function AuctusAPI:ValidateKey(key: string): boolean
    local result = JunkieKeySystem.check_key(key)
    return result and result.valid
end

function AuctusAPI.MakeKeyPopup()

    if not isfile("Apex Hub Script/Key.txt") then
        makefolder("Apex Hub Script")
        writefile("Apex Hub Script/Key.txt", "")
    end

    if AuctusAPI:ValidateKey(readfile("Apex Hub Script/Key.txt")) == true then
        return
    end

	local KeyPopup = Instance.new("ScreenGui")
	local Body = Instance.new("Frame")
	local ContentBody = Instance.new("Frame")
	local UICorner = Instance.new("UICorner")
	local Toolbar = Instance.new("Frame")
	local WindowControls = Instance.new("Frame")
	local UIListLayout = Instance.new("UIListLayout")
	local UIPadding = Instance.new("UIPadding")
	local Exit = Instance.new("ImageButton")
	local Stroke = Instance.new("ImageLabel")
	local Icon = Instance.new("ImageLabel")
	local Form = Instance.new("Frame")
	local UICorner_2 = Instance.new("UICorner")
	local TextBox = Instance.new("TextBox")
	local CheckKey = Instance.new("TextButton")
	local UICorner_3 = Instance.new("UICorner")
	local GetKey = Instance.new("TextButton")
	local UICorner_4 = Instance.new("UICorner")
	local Dropshadow = Instance.new("ImageLabel")

    do
        KeyPopup.Name = "KeyPopup"
        KeyPopup.Parent = game:GetService("CoreGui")
        KeyPopup.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        KeyPopup.DisplayOrder = 200
        KeyPopup.ResetOnSpawn = false

        Body.Name = "Body"
        Body.Parent = KeyPopup
        Body.AnchorPoint = Vector2.new(0.5, 0.5)
        Body.BackgroundColor3 = Color3.fromRGB(32, 32, 35)
        Body.BackgroundTransparency = 1.000
        Body.BorderSizePixel = 0
        Body.Position = UDim2.new(0.499187052, 0, 0.498972088, 0)
        Body.Size = UDim2.new(0, 314, 0, 141)

        ContentBody.Name = "ContentBody"
        ContentBody.Parent = Body
        ContentBody.AnchorPoint = Vector2.new(0.5, 0.5)
        ContentBody.BackgroundColor3 = Color3.fromRGB(28, 28, 30)
        ContentBody.BorderColor3 = Color3.fromRGB(0, 0, 0)
        ContentBody.BorderSizePixel = 0
        ContentBody.ClipsDescendants = true
        ContentBody.LayoutOrder = 2
        ContentBody.Position = UDim2.new(0.5, 0, 0.5, 0)
        ContentBody.Size = UDim2.new(1, 0, 1, 0)

        UICorner.CornerRadius = UDim.new(0, 10)
        UICorner.Parent = ContentBody

        Toolbar.Name = "Toolbar"
        Toolbar.Parent = ContentBody
        Toolbar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Toolbar.BackgroundTransparency = 1.000
        Toolbar.BorderColor3 = Color3.fromRGB(0, 0, 0)
        Toolbar.BorderSizePixel = 0
        Toolbar.Size = UDim2.new(1, 0, -0.160460994, 52)

        WindowControls.Name = "WindowControls"
        WindowControls.Parent = Toolbar
        WindowControls.AnchorPoint = Vector2.new(0, 0.5)
        WindowControls.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        WindowControls.BackgroundTransparency = 1.000
        WindowControls.BorderColor3 = Color3.fromRGB(0, 0, 0)
        WindowControls.BorderSizePixel = 0
        WindowControls.Position = UDim2.new(0, 0, 0.5, 0)
        WindowControls.Size = UDim2.new(0, 69, 0, 38)

        UIListLayout.Parent = WindowControls
        UIListLayout.FillDirection = Enum.FillDirection.Horizontal
        UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        UIListLayout.Padding = UDim.new(0, 8)

        UIPadding.Parent = WindowControls
        UIPadding.PaddingLeft = UDim.new(0, 10)
        UIPadding.PaddingRight = UDim.new(0, 20)

        Exit.Name = "Exit"
        Exit.Parent = WindowControls
        Exit.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Exit.BackgroundTransparency = 1.000
        Exit.BorderColor3 = Color3.fromRGB(0, 0, 0)
        Exit.BorderSizePixel = 0
        Exit.Size = UDim2.new(0, 12, 0, 12)
        Exit.AutoButtonColor = false
        Exit.Image = "rbxassetid://132228700346004"
        Exit.ImageColor3 = Color3.fromRGB(255, 95, 87)

        Stroke.Name = "Stroke"
        Stroke.Parent = Exit
        Stroke.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Stroke.BackgroundTransparency = 1.000
        Stroke.BorderColor3 = Color3.fromRGB(0, 0, 0)
        Stroke.BorderSizePixel = 0
        Stroke.Size = UDim2.new(1, 0, 1, 0)
        Stroke.Image = "rbxassetid://94763505860483"
        Stroke.ImageTransparency = 0.900

        Icon.Name = "Icon"
        Icon.Parent = Exit
        Icon.AnchorPoint = Vector2.new(0.5, 0.5)
        Icon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Icon.BackgroundTransparency = 1.000
        Icon.BorderColor3 = Color3.fromRGB(0, 0, 0)
        Icon.BorderSizePixel = 0
        Icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        Icon.Size = UDim2.new(1, 0, 1, 0)
        Icon.Visible = false
        Icon.Image = "rbxassetid://94781753558308"
        Icon.ImageColor3 = Color3.fromRGB(0, 0, 0)
        Icon.ImageTransparency = 0.500

        Form.Name = "Form"
        Form.Parent = ContentBody
        Form.BackgroundColor3 = Color3.fromRGB(31, 31, 33)
        Form.BorderColor3 = Color3.fromRGB(0, 0, 0)
        Form.BorderSizePixel = 0
        Form.Position = UDim2.new(0.0500000007, 0, 0.208333328, 0)
        Form.Size = UDim2.new(0.899999976, 0, 0.241134748, 0)
        Form.ZIndex = 0

        UICorner_2.CornerRadius = UDim.new(0, 6)
        UICorner_2.Parent = Form

        TextBox.Parent = Form
        TextBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        TextBox.BackgroundTransparency = 1.000
        TextBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
        TextBox.BorderSizePixel = 0
        TextBox.Position = UDim2.new(0.05, 0, 0.25, 0)
        TextBox.Size = UDim2.new(0.9, 0, 0.5, 0)
        TextBox.Font = Enum.Font.Unknown
        TextBox.PlaceholderColor3 = Color3.fromRGB(159, 159, 159)
        TextBox.PlaceholderText = "key..."
        TextBox.Text = ""
        TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
        TextBox.TextSize = 15.000
        TextBox.TextScaled = true

        CheckKey.Name = "CheckKey"
        CheckKey.Parent = ContentBody
        CheckKey.Active = false
        CheckKey.BackgroundColor3 = Color3.fromRGB(31, 31, 33)
        CheckKey.BorderColor3 = Color3.fromRGB(0, 0, 0)
        CheckKey.BorderSizePixel = 0
        CheckKey.Position = UDim2.new(0.540012062, 0, 0.589538991, 0)
        CheckKey.Selectable = false
        CheckKey.Size = UDim2.new(0.407000005, 0, 0.298000008, 0)
        CheckKey.Font = Enum.Font.Unknown
        CheckKey.Text = "Submit"
        CheckKey.TextColor3 = Color3.fromRGB(255, 255, 255)
        CheckKey.TextSize = 15.000
        CheckKey.TextTransparency = 0.450

        UICorner_3.CornerRadius = UDim.new(0, 6)
        UICorner_3.Parent = CheckKey

        GetKey.Name = "GetKey"
        GetKey.Parent = ContentBody
        GetKey.Active = false
        GetKey.BackgroundColor3 = Color3.fromRGB(31, 31, 33)
        GetKey.BorderColor3 = Color3.fromRGB(0, 0, 0)
        GetKey.BorderSizePixel = 0
        GetKey.Position = UDim2.new(0.0495661832, 0, 0.589538991, 0)
        GetKey.Selectable = false
        GetKey.Size = UDim2.new(0.407141238, 0, 0.297872335, 0)
        GetKey.Font = Enum.Font.Unknown
        GetKey.Text = "GetKey"
        GetKey.TextColor3 = Color3.fromRGB(255, 255, 255)
        GetKey.TextSize = 15.000
        GetKey.TextTransparency = 0.450

        UICorner_4.CornerRadius = UDim.new(0, 6)
        UICorner_4.Parent = GetKey

        Dropshadow.Name = "Dropshadow"
        Dropshadow.Parent = Body
        Dropshadow.AnchorPoint = Vector2.new(0.5, 0.5)
        Dropshadow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Dropshadow.BackgroundTransparency = 1.000
        Dropshadow.BorderColor3 = Color3.fromRGB(0, 0, 0)
        Dropshadow.BorderSizePixel = 0
        Dropshadow.Position = UDim2.new(0.5, 0, 0.5, 3)
        Dropshadow.Size = UDim2.new(1, 24, 1, 24)
        Dropshadow.ZIndex = 0
        Dropshadow.Image = "rbxassetid://138260268144845"
        Dropshadow.ImageTransparency = 0.650
        Dropshadow.ScaleType = Enum.ScaleType.Slice
        Dropshadow.SliceCenter = Rect.new(28, 26, 96, 94)
    end

    local key_signal = Instance.new("BindableEvent")
	local connects = {}

	local function EndPopupKey()
        KeyPopup:Destroy()
        key_signal:Destroy()

		for _, v in connects do
			v:Disconnect()
		end
	end

	local getcon = GetKey.MouseButton1Click:Connect(function()
		local link = AuctusAPI:GetKeyLink()
		setclipboard(link)
	end)

	local checkcon = CheckKey.MouseButton1Click:Connect(function()
        local key = TextBox.Text
		local isValid = AuctusAPI:ValidateKey(key)

		if isValid == true then
            writefile("Apex Hub Script/Key.txt", key)
            key_signal:Fire(true)
            EndPopupKey()
        end
	end)

	local exitcon = Exit.MouseButton1Click:Connect(function()
		key_signal:Fire(false)
        EndPopupKey()
	end)

	table.insert(connects, getcon)
	table.insert(connects, checkcon)
	table.insert(connects, exitcon)

    return key_signal.Event:Wait()
end

-- ═══════════════════════════════════════════════════════════════
-- 🪟 UI LIBRARY
-- ═══════════════════════════════════════════════════════════════
type Library = "Cassade" | "WindUI"

-- cassade (lazy: the library is fetched when the first Cassade app is created)
local Cassade = {}
Cassade.__index = Cassade

type property = {[string]: any}

function Cassade.new(title: string, collection: {any})
    local CascadeLibrary = loadstring(game:HttpGet("https://github.com/biggaboy212/Cascade/releases/latest/download/dist.luau"))()
    --══════════════ cassade method ══════════════════════
    local self = setmetatable({}, Cassade)
    self.collection = collection
    self.cassade = CascadeLibrary

    self.Sections = {}
    self.Tabs = {}
    self.Forms = {}
    self.Rows = {}

    --══════════════ set up window ══════════════════════
    local userInputService = cloneref and cloneref(game:GetService("UserInputService")) or game:GetService("UserInputService")

    collection.app = CascadeLibrary.New({WindowPill = true, Theme = CascadeLibrary.Themes.Dark, Accent = CascadeLibrary.Accents.Red})

    local window = collection.app:Window({Title = title, Subtitle = "Apex Hub", Size = userInputService.TouchEnabled and UDim2.fromOffset(550, 325) or UDim2.fromOffset(850, 530)})
    self.window = window

    --// minimize
    userInputService.InputEnded:Connect(function(input, gameProcessedEvent)
        if input.KeyCode == self.minimizeKeybind and not gameProcessedEvent then
            window.Minimized = not window.Minimized
        end
    end)

    collection.CloseConnect = window.Destroying:Connect(function() if getgenv().CleanUpApexHub then getgenv().CleanUpApexHub() end end)

    -- set sidebar size
    window.Sidebar.Size = UDim2.new(0, 215, 1, 0)
    window.Sidebar.Margins.Size = UDim2.new(1, 0, 1, 0)

    collection.PlayerDropdown = {}

    --══════════════ init settings ══════════════════════
    if not isfile("Apex Hub Script/CassadeSettings.json") then
        writefile("Apex Hub Script/CassadeSettings.json", "{}")
    end

    local String = readfile("Apex Hub Script/CassadeSettings.json")
    local settings = HttpService:JSONDecode(String:match("{") and String or "{}")
    self.window.Searching = if settings.Searching ~= nil then settings.Searching else true
    self.window.Draggable = if settings.Draggable ~= nil then settings.Draggable else true
    self.window.Resizable = if settings.Resizable ~= nil then settings.Resizable else true
    self.window.Dropshadow = if settings.Dropshadow ~= nil then settings.Dropshadow else true
    self.window.UIBlur = if settings.UIBlur ~= nil then settings.UIBlur else true
    self.collection.app.Theme = if settings.WhiteMode then self.cassade.Themes.Light else self.cassade.Themes.Dark
    self.minimizeKeybind = settings.minimizeKeybind and Enum.KeyCode[settings.minimizeKeybind] or Enum.KeyCode.RightControl
    self.WhiteMode = settings.WhiteMode

    return self
end

function Cassade:CreateSetting(sectionId: string)
    self:Tab("GuiSettingsTab", sectionId, {Title = "Gui Appearance", Icon = "http://www.roblox.com/asset/?id=70542492197391"})
        self:Form("AppearanceForm", "GuiSettingsTab", {Title = "Appearance"})
        self:Form("InputForm", "GuiSettingsTab", {Title = "Input"})
        self:Form("EffectsForm", "GuiSettingsTab", {Title = "Effects", Subtitle = "These effects may be resource intensive across different systems."})

    do -- Appearance

        do -- Dark mode
            local row = self:Row(
                "DarkModeRow",
                "AppearanceForm",
                "Dark mode",
                "An application appearance setting that uses a dark color palette to provide a comfortable viewing experience tailored for low-light environments."
            )

            row:Right():Toggle({
                Value = not self.WhiteMode,
                ValueChanged = function(_self, value: boolean)
                    self.collection.app.Theme = value and self.cassade.Themes.Dark or self.cassade.Themes.Light
                    self.WhiteMode = not value
                    self:UpdateSetting()
                end,
            })
        end
    end

    do -- Input

        do -- Minimize shortcut
            local row = self:Row("MinimizeShortcutRow", "InputForm", "Minimize shortcut")

            row:Right():KeybindField({
                Value = self.minimizeKeybind,
                ValueChanged = function(_self, value: Enum.KeyCode)
                    self.minimizeKeybind = value
                    self:UpdateSetting()
                end,
            })
        end

        do -- Searching
            local row = self:Row(
                "SearchingRow",
                "InputForm",
                "Searchable",
                "Allows users to search for content in a page with a search-field in the titlebar."
            )

            row:Right():Toggle({
                Value = self.window.Searching,
                ValueChanged = function(_self, value: boolean)
                    self.window.Searching = value
                    self:UpdateSetting()
                end,
            })
        end

        do -- Draggable
            local row = self:Row("DraggableRow", "InputForm", "Draggable", "Allows users to move the window with a mouse or touch device.")

            row:Right():Toggle({
                Value = self.window.Draggable,
                ValueChanged = function(_self, value: boolean)
                    self.window.Draggable = value
                    self:UpdateSetting()
                end,
            })
        end

        do -- Resizable
            local row = self:Row("ResizableRow", "InputForm", "Resizable", "Allows users to resize the window with a mouse or touch device.")

            row:Right():Toggle({
                Value = self.window.Resizable,
                ValueChanged = function(_self, value: boolean)
                    self.window.Resizable = value
                    self:UpdateSetting()
                end,
            })
        end
    end

    do -- Effects

        do -- Dropshadow
            local row = self:Row("DropshadowRow", "EffectsForm", "Dropshadow", "Enables a dropshadow effect on the window.")

            row:Right():Toggle({
                Value = self.window.Dropshadow,
                ValueChanged = function(_self, value: boolean)
                    self.window.Dropshadow = value
                    self:UpdateSetting()
                end,
            })
        end

        do -- UI Blur
            local row = self:Row("UIBlurRow", "EffectsForm", "Background blur", "Enables a UI background blur effect on the window. This can be detectable in some games.")

            row:Right():Toggle({
                Value = self.window.UIBlur,
                ValueChanged = function(_self, value: boolean)
                    self.window.UIBlur = value
                    self:UpdateSetting()
                end,
            })
        end
    end
end

function Cassade:UpdateSetting()
    local settings = {}

    settings.Searching = self.window.Searching
    settings.Draggable = self.window.Draggable
    settings.Resizable = self.window.Resizable
    settings.Dropshadow = self.window.Dropshadow
    settings.UIBlur = self.window.UIBlur
    settings.WhiteMode = self.WhiteMode
    settings.minimizeKeybind = tostring(self.minimizeKeybind):sub(14)

    writefile("Apex Hub Script/CassadeSettings.json", HttpService:JSONEncode(settings))
end

function Cassade:Section(sectionId: string, property: property?)
    self.Sections[sectionId] = self.window:Section(property)
    return self.Sections[sectionId]
end

function Cassade:Tab(tabId: string, sectionId: string, property: property?)
    self.Tabs[tabId] = {ID = tabId, Title = property.Title, Object = self.Sections[sectionId]:Tab(property), Parent = self.Sections[sectionId]}
    return self.Tabs[tabId]
end

function Cassade:Form(formId: string, tabId: string, property: property?)
    self.Forms[formId] = {ID = formId, Title = property.Title, Object = self.Tabs[tabId].Object:PageSection(property):Form(), Parent = self.Tabs[tabId]}
    return self.Forms[formId]
end

function Cassade:Row(rowId: string, formId: string, title: string, subtitle: string?)
    self.Rows[rowId] = {ID = rowId, Title = title, Object = self.Forms[formId].Object:Row({SearchIndex = title}), Parent = self.Forms[formId]}
    self.Rows[rowId].Object:Left():TitleStack({Title = title, Subtitle = subtitle})
    return self.Rows[rowId].Object
end


-- WindUI (lazy: fetched only when a WindUI app is created)
local WindUIModule: any? = nil

local function getWindUI(): any
    if not WindUIModule then
        WindUIModule = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
        WindUIModule:SetNotificationLower(true)
    end
    return WindUIModule
end

local WindUIApp = {}
WindUIApp.__index = WindUIApp

-- Apex defaults, every field overridable through windowProperty
local DEFAULT_WINDOW: property = {
    Title = "None",
    Icon = "rbxassetid://99869488000539",
    Author = "Apex Hub Fremium",
    Folder = "Apex Hub",
    Size = UDim2.fromOffset(580, 460),
    MinSize = Vector2.new(560, 350), -- WindUI clamps Size against MinSize.X/MaxSize.X as numbers
    MaxSize = Vector2.new(850, 560),
    Position = UDim2.fromOffset(20, 20),
    Theme = "Crimson",
    ToggleKey = Enum.KeyCode.LeftAlt,
    Transparent = true,
    Resizable = true,
    SideBarWidth = 150,
    BackgroundImageTransparency = 0.42,
    HideSearchBar = true,
    ScrollBarEnabled = false,
}

-- kinds whose value fits in the settings JSON and can bind to a Settings key
local BINDABLE: {[string]: boolean} = {
    Toggle = true,
    Slider = true,
    Input = true,
    Dropdown = true,
    Keybind = true,
}

local function initialValue(kind: string, property: property, saved: any): any
    if kind == "Slider" then
        local base = property.Value or {}
        return {
            Min = base.Min or 0,
            Max = base.Max or 100,
            Default = if saved ~= nil then saved else (base.Default or base.Min or 0),
        }
    end
    if saved ~= nil then
        return saved
    end
    if kind == "Input" then
        return property.Value or ""
    elseif kind == "Toggle" then
        return property.Value or false
    end
    return property.Value
end

-- windowProperty: WindUI CreateWindow props (merged over the Apex defaults)
-- hub: engine table with hub.Settings (proxy with optional .Changed signal);
--       without it, elements simply never use Setting=
-- returns app, WindUI, Window
function WindUIApp.new(windowProperty: property?, hub: any?)
    local WindUI = getWindUI()

    local props: property = table.clone(DEFAULT_WINDOW)
    if windowProperty then
        for key, value in windowProperty do
            props[key] = value
        end
    end

    -- KeySystem = true bridges the Apex (Junkie) key into WindUI's native key screen
    if props.KeySystem == true then
        props.KeySystem = {
            Title = "Apex Hub Key",
            Note = "Get the key from the link, then paste it here.",
            SaveKey = true,
            URL = JunkieKeySystem.get_key_link(),
            KeyValidator = function(key: string): boolean
                local ok, result = pcall(JunkieKeySystem.check_key, key)
                return ok and type(result) == "table" and result.valid == true
            end,
        }
    end

    local Window = WindUI:CreateWindow(props)

    Window:SetIconSize(40)
    Window:EditOpenButton({
        Title = "Apex Hub",
        Icon = "rbxassetid://99869488000539",
        CornerRadius = UDim.new(0, 16),
        StrokeThickness = 1.5,
        Color = ColorSequence.new(Color3.fromRGB(150, 0, 0)),
        OnlyMobile = false,
        Enabled = true,
        Draggable = true,
    })

    local self = setmetatable({}, WindUIApp)
    self.Window = Window
    self.WindUI = WindUI
    self.Hub = hub
    self.Elements = {}
    self.Containers = {}
    self.Bindings = {}
    self._syncing = false
    self.Destroyed = false

    -- reverse sync: Settings changed from code -> update the bound elements
    if hub and hub.Settings and hub.Settings.Changed and hub.Settings.Changed.Connect then
        self._changedConn = hub.Settings.Changed:Connect(function(key: any, value: any)
            self:_applySetting(key, value)
        end)
    end

    return self, WindUI, Window
end

function WindUIApp:Sidebar(id: string, property: property?)
    if self.Containers[id] then
        error(("[WindUI] duplicate id '%s'"):format(id), 2)
    end
    local section = self.Window:Section(property or {Title = id})
    self.Containers[id] = {Object = section, Elements = false}
    return section
end

function WindUIApp:Tab(id: string, sidebarId: string?, property: property?)
    if self.Containers[id] then
        error(("[WindUI] duplicate id '%s'"):format(id), 2)
    end
    local tab
    if sidebarId then
        local sidebar = self.Containers[sidebarId]
        if not sidebar or sidebar.Elements then
            error(("[WindUI] '%s' is not a Sidebar for tab '%s'"):format(tostring(sidebarId), id), 2)
        end
        tab = sidebar.Object:Tab(property or {Title = id})
    else
        tab = self.Window:Tab(property or {Title = id})
    end
    self.Containers[id] = {Object = tab, Elements = true}
    return tab
end

function WindUIApp:Section(id: string, parentId: string, property: property?)
    if self.Containers[id] then
        error(("[WindUI] duplicate id '%s'"):format(id), 2)
    end
    local parent = self.Containers[parentId]
    if not parent or not parent.Elements then
        error(("[WindUI] unknown Tab/Section '%s' for section '%s'"):format(tostring(parentId), id), 2)
    end
    local section = parent.Object:Section(property or {Title = id})
    self.Containers[id] = {Object = section, Elements = true}
    return section
end

-- Setting = "Key" on a bindable element:
--   initial value <- hub.Settings[Key]
--   Callback      -> hub.Settings[Key] = value   (settings proxy persists it)
--   Settings.Changed from code -> element:Set/Select (guarded against loops)
function WindUIApp:_element(kind: string, id: string, parentId: string, property: property?)
    local container = self.Containers[parentId]
    if not container then
        error(("[WindUI] unknown parent '%s' for element '%s'"):format(tostring(parentId), id), 2)
    end
    if not container.Elements then
        error(("[WindUI] '%s' cannot contain elements"):format(parentId), 2)
    end
    if self.Elements[id] then
        error(("[WindUI] duplicate element id '%s'"):format(id), 2)
    end

    property = property or {}
    local key = property.Setting
    if key ~= nil then
        property.Setting = nil
        if not BINDABLE[kind] then
            error(("[WindUI] '%s': Setting= is not supported on %s"):format(id, kind), 2)
        end
        local hub = self.Hub
        if not hub or not hub.Settings then
            error(("[WindUI] '%s': Setting='%s' requires CreateApp(..., hub) with hub.Settings"):format(id, tostring(key)), 2)
        end
        local saved = hub.Settings[key]
        property.Value = initialValue(kind, property, saved)
        local userCallback = property.Callback
        property.Callback = function(value: any)
            if not self._syncing then
                hub.Settings[key] = value
            end
            if userCallback then
                userCallback(value)
            end
        end
    end

    local element = container.Object[kind](container.Object, property)
    self.Elements[id] = element

    if key ~= nil then
        local list = self.Bindings[key]
        if not list then
            list = {}
            self.Bindings[key] = list
        end
        table.insert(list, {Element = element, Kind = kind})
    end

    return element
end

function WindUIApp:_applySetting(key: any, value: any)
    local list = self.Bindings[key]
    if not list or self.Destroyed then
        return
    end
    self._syncing = true
    local ok, err = pcall(function()
        for _, binding in list do
            if binding.Kind == "Dropdown" then
                binding.Element:Select(value)
            else
                binding.Element:Set(value)
            end
        end
    end)
    self._syncing = false
    if not ok then
        warn(("[WindUI] failed to apply setting '%s': %s"):format(tostring(key), tostring(err)))
    end
end

function WindUIApp:Toggle(id: string, parentId: string, property: property?)
    return self:_element("Toggle", id, parentId, property)
end

function WindUIApp:Slider(id: string, parentId: string, property: property?)
    return self:_element("Slider", id, parentId, property)
end

function WindUIApp:Input(id: string, parentId: string, property: property?)
    return self:_element("Input", id, parentId, property)
end

function WindUIApp:Dropdown(id: string, parentId: string, property: property?)
    return self:_element("Dropdown", id, parentId, property)
end

function WindUIApp:Button(id: string, parentId: string, property: property?)
    return self:_element("Button", id, parentId, property)
end

function WindUIApp:Keybind(id: string, parentId: string, property: property?)
    return self:_element("Keybind", id, parentId, property)
end

function WindUIApp:Paragraph(id: string, parentId: string, property: property?)
    return self:_element("Paragraph", id, parentId, property)
end

function WindUIApp:Colorpicker(id: string, parentId: string, property: property?)
    return self:_element("Colorpicker", id, parentId, property)
end

function WindUIApp:ProgressBar(id: string, parentId: string, property: property?)
    return self:_element("ProgressBar", id, parentId, property)
end

function WindUIApp:Divider(id: string, parentId: string, property: property?)
    return self:_element("Divider", id, parentId, property)
end

function WindUIApp:Space(id: string, parentId: string, property: property?)
    return self:_element("Space", id, parentId, property)
end

function WindUIApp:Image(id: string, parentId: string, property: property?)
    return self:_element("Image", id, parentId, property)
end

function WindUIApp:Get(id: string): any
    return self.Elements[id]
end

function WindUIApp:Notify(property: {[string]: any})
    self.WindUI:Notify(property)
end

function WindUIApp:Dialog(property: {[string]: any})
    return self.Window:Dialog(property)
end

function WindUIApp:OnDestroy(callback: () -> ())
    self.Window:OnDestroy(callback)
end

function WindUIApp:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    if self._changedConn then
        self._changedConn:Disconnect()
        self._changedConn = nil
    end
    self.Window:Destroy()
end

-- Constructor
function AuctusAPI.CreateApp(library: Library, ...)
    local constructors = {
        Cassade = Cassade.new,
        WindUI = WindUIApp.new
    }
    local constructor = constructors[library]
    if not constructor then
        error(("[AuctusAPI] unknown library '%s'"):format(tostring(library)), 2)
    end
    return constructor(...)
end

-- ═══════════════════════════════════════════════════════════════
-- 🧹 TROVE (lazy: fetched on first use)
-- ═══════════════════════════════════════════════════════════════
local TroveClass: any? = nil

--- Fresh Trove instance for tracking connections, threads and instances.
function AuctusAPI.NewTrove()
    if not TroveClass then
        TroveClass = loadstring(game:HttpGet("https://raw.githubusercontent.com/1makam1/Main/refs/heads/main/Utility/Trove.luau"))()
    end
    return TroveClass.new()
end

-- ═══════════════════════════════════════════════════════════════
-- 🛠️ UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════
function AuctusAPI.DeepPrint(data: any)
    local function PrintTable(t: {any}, tab: number)
        local space = ""

        for i = 1, tab do
            space ..= "   "
        end

        for k, v in t do
            local key = `{space}{type(k) == "number" and `[{k}]` or k} = `

            if type(v) == "table" then

                print(key .. "{")
                PrintTable(v, tab + 1)
                print(space.."}")

            else
                print(key, type(v) == "string" and `"{v}"` or v)
            end
        end
    end

    local data_type = type(data)

    if data_type == "table" then

		print(data, "= {")
        PrintTable(data, 1)
		print("}\n")

    elseif data_type == "function" or data_type == "thread" then
        local s, n, l, a, variadic, f

        if data_type == "function" then
            s, n, l, a, variadic, f = debug.info(data, "snlaf")
        else
            s, n, l, a, variadic, f = debug.info(data, 1, "snlaf")
        end

        local info = string.format("name = %s, line = %s, args = %s, variadic = %s", n, l, a, tostring(variadic))

        print(info)
        print("source : "..s)

    else
        print(data)
	end
end

return AuctusAPI
