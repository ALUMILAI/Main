--[[
	Appearance: the window's look as persisted settings, applied live to a WindUI window.

	local Appearance = Utility.appearance
	Appearance.MergeDefaults(DEFAULT_SETTINGS)        -- before the settings store is created
	-- create the window with Appearance.WindowProps(Settings, { Title = ..., ToggleKey = ... })
	hub.Appearance = Appearance.new(hub)              -- applies the saved look and keeps it in step with Settings
	hub.Appearance.BuildTab("Appearance")             -- the controls, inside a tab you created

	The look lives in hub.Settings, one key per option (Appearance.Defaults lists them). Changing a key, from a
	control or from code, puts it on the window straight away. Options WindUI only reads while it builds the
	window (Appearance.NextLaunch) apply the next time the script runs.

	Host: the table handed to Appearance.new, once its window exists
	  Settings   the settings store: indexable, with Changed:Connect
	  Trove      root trove; the Settings listener is added to it
	  app        the AuctusAPI WindUI app (Notify, Section, Slider, Toggle, Input, Dropdown, Colorpicker, Button)
	  WindUI     the WindUI library table
	  Window     the WindUI window
	  Defaults   table?  the starting values of the settings; Reset restores to these (else Appearance.Defaults)

	Customise before use. Every access of Utility.appearance is a fresh copy, so this never leaks to other scripts.
	  Appearance.Defaults       the shipped value of every setting
	  Appearance.Ranges         { Min, Max, Step } of every numeric setting: the clamp and the slider both read it
	  Appearance.FontChoices    Enum.Font names offered in the Font dropdown
	  Appearance.CustomColors   the Custom theme's colours: { Key = WindUI theme key, Setting, Title }
	  Appearance.NextLaunch     the settings that only apply the next time the script runs

	appearance = Appearance.new(hub)
	  .FontNames                  the Font dropdown's values on this client
	  .ColorSetting(key)          a hex setting as a Color3
	  .Reset()                    every Appearance setting back to its default
	  .CopyCurrentTheme()         start the Custom colours from the theme in use; false when there is nothing to copy
	  .BuildTab(tabId, options)   options: Id (prefix of the ids, default "Appearance"),
	                              Sections (names, in order, default all), Opened (default true)

	Section names: Theme, Custom, Window, Bars, Background, OpenButton, Text, NextLaunch, Reset.
	Ids: sections are <Id><Name> (AppearanceTheme), elements are <Id>_<Key> (Appearance_Transparency).
]]

local TextService = game:GetService("TextService")

local Appearance = {}

-- ── what the look is made of ────────────────────────────────────────────────

Appearance.Defaults = {
	Theme = "Crimson",
	-- applied live
	Transparency = 0.15,
	BackgroundImageTransparency = 0.4,
	UIScale = 1,
	WindowWidth = 580,
	WindowHeight = 460,
	Resizable = true,
	ShadowTransparency = 0.6, -- shows when the window next opens
	PanelBackground = true,
	ConfirmClose = true,
	FullscreenButton = true,
	MinimizeButton = true,
	ShowProfile = false,
	ProfileAnonymous = false,
	IconSize = 40,
	LowerNotifications = true,
	Font = "Default",
	FontId = "", -- a font family asset id, used when Font is Custom
	OpenButtonEnabled = true,
	OpenButtonRadius = 16,
	OpenButtonStroke = 1.5,
	OpenButtonScale = 1,
	OpenButtonColorA = "#960000",
	OpenButtonColorB = "#960000",
	CustomAccent = "#b91c1c",
	CustomBackground = "#0c0404",
	CustomDialog = "#450a0a",
	CustomElement = "#251f1f",
	CustomText = "#fef2f2",
	CustomPlaceholder = "#6f757b",
	CustomButton = "#991b1b",
	CustomIcon = "#dc2626",
	CustomOutline = "#ffffff",
	-- read when the window is created, so they apply the next time the script runs
	SidebarWidth = 150,
	WindowRadius = 16,
	ElementsRadius = 0, -- 0 = WindUI's own
	Acrylic = false,
	BackgroundImage = "",
	TopbarStyle = "Default",
	NewElements = false,
	SearchBar = false,
	ScrollBar = false,
	AutoScale = true,
	TopbarHeight = 52,
	TopbarButtonSize = 0, -- 0 = WindUI's own
}

-- the numeric settings: the range each is clamped to, and the step of its slider
Appearance.Ranges = {
	Transparency = { Min = 0, Max = 0.95, Step = 0.05 },
	BackgroundImageTransparency = { Min = 0, Max = 1, Step = 0.1 },
	ShadowTransparency = { Min = 0, Max = 1, Step = 0.05 },
	UIScale = { Min = 0.7, Max = 1.4, Step = 0.05 },
	WindowWidth = { Min = 560, Max = 850, Step = 10 },
	WindowHeight = { Min = 350, Max = 560, Step = 10 },
	IconSize = { Min = 16, Max = 64, Step = 2 },
	OpenButtonRadius = { Min = 4, Max = 32, Step = 1 },
	OpenButtonStroke = { Min = 0, Max = 6, Step = 0.5 },
	OpenButtonScale = { Min = 0.5, Max = 2, Step = 0.1 },
	SidebarWidth = { Min = 120, Max = 260, Step = 10 },
	WindowRadius = { Min = 0, Max = 24, Step = 1 },
	ElementsRadius = { Min = 0, Max = 24, Step = 1 },
	TopbarHeight = { Min = 40, Max = 72, Step = 2 },
	TopbarButtonSize = { Min = 0, Max = 24, Step = 1 },
}

-- fonts offered in the tab: each is an Enum.Font whose family WindUI:SetFont accepts
Appearance.FontChoices = { "Gotham", "Nunito", "Roboto", "Ubuntu", "Oswald", "Merriweather", "SourceSans", "Arimo", "Jura", "RobotoMono" }

-- the Custom theme: WindUI theme key -> the settings key that holds its hex colour
Appearance.CustomColors = {
	{ Key = "Accent", Setting = "CustomAccent", Title = "Accent" },
	{ Key = "Background", Setting = "CustomBackground", Title = "Background" },
	{ Key = "Dialog", Setting = "CustomDialog", Title = "Dialog" },
	{ Key = "ElementBackground", Setting = "CustomElement", Title = "Element background" },
	{ Key = "Text", Setting = "CustomText", Title = "Text" },
	{ Key = "Placeholder", Setting = "CustomPlaceholder", Title = "Placeholder text" },
	{ Key = "Button", Setting = "CustomButton", Title = "Button" },
	{ Key = "Icon", Setting = "CustomIcon", Title = "Icon" },
	{ Key = "Outline", Setting = "CustomOutline", Title = "Outline" },
}

-- settings that WindUI reads while it builds the window: they apply the next time the script runs
Appearance.NextLaunch = {
	SidebarWidth = true,
	WindowRadius = true,
	ElementsRadius = true,
	BackgroundImage = true,
	TopbarStyle = true,
	TopbarHeight = true,
	TopbarButtonSize = true,
	AutoScale = true,
	NewElements = true,
	SearchBar = true,
	ScrollBar = true,
}

-- the sections BuildTab knows, in the order it builds them by default
local SECTION_ORDER = { "Theme", "Custom", "Window", "Bars", "Background", "OpenButton", "Text", "NextLaunch", "Reset" }

-- ── reading settings safely ─────────────────────────────────────────────────

-- a hand-edited file must not feed the window a bad value: numbers are clamped to their range,
-- anything unusable falls back to the default
local function readNumber(settings: any, key: string): number
	local range = Appearance.Ranges[key]
	return math.clamp(tonumber(settings[key]) or Appearance.Defaults[key], range.Min, range.Max)
end

local function readText(settings: any, key: string): string
	local value = settings[key]
	return type(value) == "string" and value or Appearance.Defaults[key]
end

-- ── before the window exists ────────────────────────────────────────────────

---Add every Appearance default the table does not have yet; the host's own values win.
function Appearance.MergeDefaults(target: { [string]: any })
	for key, value in Appearance.Defaults do
		if target[key] == nil then
			target[key] = value
		end
	end
end

---The options WindUI only reads while it builds the window. `base` carries the host's own
---(Title, ToggleKey, KeySystem...) and is not modified.
function Appearance.WindowProps(settings: any, base: { [string]: any }?): { [string]: any }
	local function number(key: string): number
		return readNumber(settings, key)
	end

	local props = table.clone(base or {})
	-- Custom is registered once the window exists
	props.Theme = settings.Theme == "Custom" and Appearance.Defaults.Theme or settings.Theme
	props.Size = UDim2.fromOffset(number("WindowWidth"), number("WindowHeight"))
	props.Resizable = settings.Resizable ~= false
	props.SideBarWidth = number("SidebarWidth")
	props.Radius = number("WindowRadius")
	props.Acrylic = settings.Acrylic == true
	props.NewElements = settings.NewElements == true
	props.HideSearchBar = settings.SearchBar ~= true
	props.ScrollBarEnabled = settings.ScrollBar == true
	props.Topbar = {
		Height = number("TopbarHeight"),
		ButtonsType = settings.TopbarStyle == "Mac" and "Mac" or "Default",
	}
	props.AutoScale = settings.AutoScale ~= false
	props.HidePanelBackground = settings.PanelBackground == false
	props.IgnoreAlerts = settings.ConfirmClose == false
	props.ShadowTransparency = number("ShadowTransparency")
	props.User = { Enabled = settings.ShowProfile == true, Anonymous = settings.ProfileAnonymous == true }

	local elementsRadius = number("ElementsRadius")
	if elementsRadius > 0 then
		props.ElementsRadius = elementsRadius
	end

	local buttonSize = number("TopbarButtonSize")
	if buttonSize > 0 then
		props.TopBarButtonIconSize = buttonSize
	end

	local background = readText(settings, "BackgroundImage")
	if background:match("^%d+$") then
		background = "rbxassetid://" .. background
	end
	if background ~= "" then
		props.Background = background
	end
	return props
end

-- ── once the window exists ──────────────────────────────────────────────────

---Apply the saved look to the host's window and keep it in step with its settings.
function Appearance.new(hub: any)
	assert(
		type(hub) == "table" and hub.Settings and hub.Trove and hub.app and hub.WindUI and hub.Window,
		"Appearance.new(hub): the hub needs Settings, Trove, app, WindUI and Window"
	)
	local Settings, app, WindUI, Window = hub.Settings, hub.app, hub.WindUI, hub.Window
	local self = {}

	local function number(key: string): number
		return readNumber(Settings, key)
	end

	local function text(key: string): string
		return readText(Settings, key)
	end

	local function windowSize(): UDim2
		return UDim2.fromOffset(number("WindowWidth"), number("WindowHeight"))
	end

	-- ── colours and reset ─────────────────────────────────────────────────

	-- a hex colour setting; a hand-edited bad value falls back to the shipped one
	function self.ColorSetting(key: string): Color3
		local ok, color = pcall(Color3.fromHex, Settings[key])
		return ok and color or Color3.fromHex(Appearance.Defaults[key])
	end

	-- back to the shipped look (or to the host's own defaults where it has them)
	function self.Reset()
		local defaults = hub.Defaults or Appearance.Defaults
		for key, shipped in Appearance.Defaults do
			local value = defaults[key]
			if value == nil then
				value = shipped
			end
			Settings[key] = value
		end
	end

	-- starts the Custom theme from the one in use now; returns false when there is nothing to copy
	function self.CopyCurrentTheme(): boolean
		local source = WindUI:GetThemes()[Settings.Theme]
		if not source then
			return false
		end
		for _, color in Appearance.CustomColors do
			local value = source[color.Key]
			if type(value) == "string" and value:sub(1, 1) == "#" then
				pcall(function()
					value = Color3.fromHex(value)
				end)
			end
			if typeof(value) == "Color3" then
				Settings[color.Setting] = "#" .. value:ToHex()
			end
		end
		return true
	end

	-- ── fonts ─────────────────────────────────────────────────────────────

	-- the family WindUI started with, read off one of its labels before any font is applied
	local defaultFont: string? = nil
	pcall(function()
		defaultFont = Window.UIElements.Main:FindFirstChildWhichIsA("TextLabel", true).FontFace.Family
	end)

	local function fontFamily(name: string): string?
		if name == "Default" then
			return defaultFont
		end
		local ok, family = pcall(function()
			return Font.fromEnum(Enum.Font[name]).Family
		end)
		return ok and family or nil
	end

	-- "Default" first, every choice this client actually has, and Custom for a font family asset id
	self.FontNames = { "Default" }
	for _, name in Appearance.FontChoices do
		if fontFamily(name) then
			table.insert(self.FontNames, name)
		end
	end
	table.insert(self.FontNames, "Custom")

	-- a wrong id would blank every label, so a custom one is only applied once Roblox confirms it is a font family
	local fontCheck = 0
	local function applyCustomFont(announce: boolean)
		local id = text("FontId")
		if id:match("^%d+$") then
			id = "rbxassetid://" .. id
		end
		if not id:match("^rbxassetid://%d+$") then
			if announce then
				app:Notify({ Title = "Font", Content = "Enter a font family asset id.", Icon = "triangle-alert", Duration = 4 })
			end
			return
		end
		fontCheck += 1
		local check = fontCheck
		task.spawn(function()
			local ok = pcall(function()
				return TextService:GetFamilyInfoAsync(id)
			end)
			if check ~= fontCheck or Settings.Font ~= "Custom" then
				return -- another id or font was picked while Roblox was answering
			end
			if ok then
				WindUI:SetFont(id)
			elseif announce then
				app:Notify({ Title = "Font", Content = "That id is not a font family.", Icon = "triangle-alert", Duration = 4 })
			end
		end)
	end

	local function applyFont(announce: boolean)
		local name = text("Font")
		if name == "Custom" then
			applyCustomFont(announce)
			return
		end
		local family = fontFamily(name)
		if family then
			WindUI:SetFont(family)
		end
	end

	-- ── appliers: one per setting, each puts its setting on the window ────

	local lastNotice = 0
	local function noteNextLaunch()
		if os.clock() - lastNotice > 3 then
			lastNotice = os.clock()
			app:Notify({ Title = "Appearance", Content = "This applies the next time the script runs.", Icon = "info", Duration = 3 })
		end
	end

	local function registerCustomTheme()
		local theme = { Name = "Custom", ElementBackgroundTransparency = 0 }
		for _, color in Appearance.CustomColors do
			theme[color.Key] = self.ColorSetting(color.Setting)
		end
		WindUI:AddTheme(theme)
	end

	local function applyTheme()
		local name = Settings.Theme
		if name == "Custom" then
			registerCustomTheme()
		end
		if WindUI:SetTheme(name) == nil then
			warn(("[Appearance] unknown theme '%s'"):format(tostring(name)))
		end
	end

	-- editing a Custom colour re-applies the theme only while Custom is the one in use
	local function refreshCustomTheme()
		if Settings.Theme == "Custom" then
			applyTheme()
		end
	end

	-- Edit() resets whatever it is not given, so the open button is always sent whole
	-- (its text stays the script's own)
	local function applyOpenButton()
		local enabled = Settings.OpenButtonEnabled ~= false
		Window.IsOpenButtonEnabled = enabled -- Edit() can only ever turn it off
		Window:EditOpenButton({
			Enabled = enabled,
			OnlyMobile = false,
			CornerRadius = UDim.new(0, number("OpenButtonRadius")),
			StrokeThickness = number("OpenButtonStroke"),
			Scale = number("OpenButtonScale"),
			Color = ColorSequence.new(self.ColorSetting("OpenButtonColorA"), self.ColorSetting("OpenButtonColorB")),
		})
	end

	local function applySize()
		Window:SetSize(windowSize())
	end

	-- the top bar buttons the user may hide; Close is never one of them
	local function showTopbarButton(name: string, visible: boolean)
		for _, button in Window.TopBarButtons do
			if button.Name == name then
				button.Object.Visible = visible
			end
		end
	end

	-- the sidebar profile; Roblox answers the avatar request later, so this runs off the caller's thread
	local function applyProfile()
		task.spawn(function()
			local ok, err = pcall(function()
				local user = Window.User
				if Settings.ShowProfile == true then
					user:Enable()
				else
					user:Disable()
				end
				user:SetAnonymous(Settings.ProfileAnonymous == true)
			end)
			if not ok then
				warn(("[Appearance] applying the profile failed: %s"):format(tostring(err)))
			end
		end)
	end

	local appliers = {
		Theme = applyTheme,
		Transparency = function()
			local value = number("Transparency")
			WindUI.TransparencyValue = value
			Window:ToggleTransparency(value > 0)
		end,
		BackgroundImageTransparency = function()
			Window:SetBackgroundImageTransparency(number("BackgroundImageTransparency"))
		end,
		ShadowTransparency = function()
			Window.ShadowTransparency = number("ShadowTransparency") -- read each time the window opens
		end,
		UIScale = function()
			Window:SetUIScale(number("UIScale"))
		end,
		WindowWidth = applySize,
		WindowHeight = applySize,
		Resizable = function()
			Window:IsResizable(Settings.Resizable ~= false)
		end,
		PanelBackground = function()
			Window:SetPanelBackground(Settings.PanelBackground ~= false)
		end,
		ConfirmClose = function()
			Window.IgnoreAlerts = Settings.ConfirmClose == false
		end,
		FullscreenButton = function()
			showTopbarButton("Fullscreen", Settings.FullscreenButton ~= false)
		end,
		MinimizeButton = function()
			showTopbarButton("Minimize", Settings.MinimizeButton ~= false)
		end,
		ShowProfile = applyProfile,
		ProfileAnonymous = applyProfile,
		IconSize = function()
			Window:SetIconSize(number("IconSize"))
		end,
		LowerNotifications = function()
			WindUI:SetNotificationLower(Settings.LowerNotifications ~= false)
		end,
		Font = function()
			applyFont(true)
		end,
		FontId = function()
			if Settings.Font == "Custom" then
				applyFont(true)
			end
		end,
		Acrylic = function()
			if Window.AcrylicPaint then
				WindUI:ToggleAcrylic(Settings.Acrylic == true)
			else
				noteNextLaunch() -- the window was built without it
			end
		end,
	}
	for _, key in
		{
			"OpenButtonEnabled",
			"OpenButtonRadius",
			"OpenButtonStroke",
			"OpenButtonScale",
			"OpenButtonColorA",
			"OpenButtonColorB",
		}
	do
		appliers[key] = applyOpenButton
	end
	for _, color in Appearance.CustomColors do
		appliers[color.Setting] = refreshCustomTheme
	end

	local function runApplier(key: string)
		local apply = appliers[key]
		if not apply then
			return
		end
		local ok, err = pcall(apply)
		if not ok then
			warn(("[Appearance] applying '%s' failed: %s"):format(key, tostring(err)))
		end
	end

	hub.Trove:Add(Settings.Changed:Connect(function(key)
		runApplier(key)
		if Appearance.NextLaunch[key] then
			noteNextLaunch()
		end
	end))

	-- the creation props already carry the title, size and window options; the rest goes on now.
	-- The theme is set again because CreateWindow paints it without recording it as WindUI's current theme
	for _, key in
		{
			"Theme",
			"Transparency",
			"BackgroundImageTransparency",
			"IconSize",
			"LowerNotifications",
			"OpenButtonRadius",
			"FullscreenButton",
			"MinimizeButton",
		}
	do
		runApplier(key)
	end
	-- AutoScale already picked a scale that fits small screens: only a scale the user chose replaces it
	if number("UIScale") ~= Appearance.Defaults.UIScale then
		runApplier("UIScale")
	end
	if Settings.Font ~= "Default" then
		applyFont(false)
	end

	-- ── the controls ──────────────────────────────────────────────────────

	---Build the controls inside a tab the host created.
	---options: Id (prefix of the ids, "Appearance"), Sections (names, in order, default all), Opened (default true).
	function self.BuildTab(tabId: string, options: { Id: string?, Sections: { string }?, Opened: boolean? }?)
		local choices: { Id: string?, Sections: { string }?, Opened: boolean? } = options or {}
		local prefix = choices.Id or "Appearance"
		local opened = choices.Opened ~= false
		local names: { string } = choices.Sections or SECTION_ORDER

		local function elementId(key: string): string
			return prefix .. "_" .. key
		end

		local function section(name: string, title: string): string
			local sectionId = prefix .. name
			app:Section(sectionId, tabId, { Title = title, Opened = opened })
			return sectionId
		end

		local function slider(sectionId: string, key: string, title: string, desc: string?)
			local range = Appearance.Ranges[key]
			app:Slider(elementId(key), sectionId, {
				Title = title,
				Desc = desc,
				Step = range.Step,
				Value = { Min = range.Min, Max = range.Max, Default = Appearance.Defaults[key] },
				Setting = key,
			})
		end

		local function toggle(sectionId: string, key: string, title: string, desc: string?)
			app:Toggle(elementId(key), sectionId, { Title = title, Desc = desc, Setting = key })
		end

		local function input(sectionId: string, key: string, title: string, placeholder: string, desc: string?)
			app:Input(elementId(key), sectionId, { Title = title, Desc = desc, Placeholder = placeholder, Setting = key })
		end

		local function dropdown(sectionId: string, key: string, title: string, values: { string }, desc: string?)
			app:Dropdown(elementId(key), sectionId, { Title = title, Desc = desc, Values = values, Setting = key })
		end

		-- colour pickers hold a Color3, so they are wired by hand: the setting stores the hex
		local pickers = {}
		local function colorpicker(sectionId: string, key: string, title: string, onPick: (() -> ())?)
			pickers[key] = app:Colorpicker(elementId(key), sectionId, {
				Title = title,
				Default = self.ColorSetting(key),
				Callback = function(color)
					Settings[key] = "#" .. color:ToHex()
					if onPick then
						onPick()
					end
				end,
			})
		end
		local function syncPickers()
			for key, picker in pickers do
				pcall(function()
					picker:Set(self.ColorSetting(key))
				end)
			end
		end

		local builders = {}

		function builders.Theme()
			local sectionId = section("Theme", "Theme")
			local themeNames = {}
			for themeName in WindUI:GetThemes() do
				if themeName ~= "Custom" then
					table.insert(themeNames, tostring(themeName))
				end
			end
			table.sort(themeNames)
			table.insert(themeNames, "Custom")
			dropdown(sectionId, "Theme", "Theme", themeNames)
		end

		function builders.Custom()
			local sectionId = section("Custom", "Custom Theme")
			for _, color in Appearance.CustomColors do
				colorpicker(sectionId, color.Setting, color.Title, function()
					Settings.Theme = "Custom" -- editing a colour is asking for the Custom theme
				end)
			end
			app:Button(elementId("CopyTheme"), sectionId, {
				Title = "Copy current theme",
				Desc = "Start the Custom colours from the theme in use now.",
				Callback = function()
					if self.CopyCurrentTheme() then
						syncPickers()
						Settings.Theme = "Custom"
					end
				end,
			})
		end

		function builders.Window()
			local sectionId = section("Window", "Window")
			slider(sectionId, "Transparency", "Transparency", "0 is solid.")
			slider(sectionId, "UIScale", "UI scale")
			slider(sectionId, "WindowWidth", "Width")
			slider(sectionId, "WindowHeight", "Height")
			slider(sectionId, "IconSize", "Icon size")
			slider(sectionId, "ShadowTransparency", "Shadow transparency", "Shows when the window opens.")
			toggle(sectionId, "PanelBackground", "Panel background")
			toggle(sectionId, "Resizable", "Resizable", "Drag the corner to resize.")
			app:Button(elementId("CenterWindow"), sectionId, {
				Title = "Center window",
				Callback = function()
					Window:SetToTheCenter()
				end,
			})
			app:Button(elementId("Fullscreen"), sectionId, {
				Title = "Toggle fullscreen",
				Callback = function()
					Window:ToggleFullscreen()
				end,
			})
		end

		function builders.Bars()
			local sectionId = section("Bars", "Top Bar and Sidebar")
			toggle(sectionId, "FullscreenButton", "Fullscreen button")
			toggle(sectionId, "MinimizeButton", "Minimize button")
			toggle(sectionId, "ConfirmClose", "Confirm before closing", "Asks first when the close button is pressed.")
			toggle(sectionId, "ShowProfile", "Show profile", "Your avatar and name at the bottom of the sidebar.")
			toggle(sectionId, "ProfileAnonymous", "Anonymous profile", "Hides your name and avatar.")
		end

		function builders.Background()
			local sectionId = section("Background", "Background")
			input(sectionId, "BackgroundImage", "Image", "rbxassetid or link", "Applies the next time the script runs.")
			slider(sectionId, "BackgroundImageTransparency", "Image transparency", "Needs an image.")
		end

		function builders.OpenButton()
			local sectionId = section("OpenButton", "Open Button")
			toggle(sectionId, "OpenButtonEnabled", "Show open button", "The button that reopens a closed window.")
			slider(sectionId, "OpenButtonRadius", "Corner radius")
			slider(sectionId, "OpenButtonStroke", "Outline thickness")
			slider(sectionId, "OpenButtonScale", "Size")
			colorpicker(sectionId, "OpenButtonColorA", "Outline colour")
			colorpicker(sectionId, "OpenButtonColorB", "Outline colour 2", nil)
		end

		function builders.Text()
			local sectionId = section("Text", "Font and Notifications")
			dropdown(sectionId, "Font", "Font", self.FontNames)
			input(sectionId, "FontId", "Custom font id", "Font family asset id", "Used when Font is Custom.")
			toggle(sectionId, "LowerNotifications", "Lower notifications", "Show them lower on the screen.")
			app:Button(elementId("TestNotification"), sectionId, {
				Title = "Test notification",
				Callback = function()
					app:Notify({ Title = "Appearance", Content = "This is how notifications look.", Icon = "bell", Duration = 3 })
				end,
			})
		end

		function builders.NextLaunch()
			local sectionId = section("NextLaunch", "Next Launch")
			slider(sectionId, "SidebarWidth", "Sidebar width")
			slider(sectionId, "WindowRadius", "Window corner radius")
			slider(sectionId, "ElementsRadius", "Element corner radius", "0 is WindUI's own.")
			slider(sectionId, "TopbarHeight", "Top bar height")
			slider(sectionId, "TopbarButtonSize", "Top bar button size", "0 is WindUI's own.")
			toggle(sectionId, "NewElements", "New element style")
			toggle(sectionId, "SearchBar", "Search bar")
			toggle(sectionId, "ScrollBar", "Scroll bar")
			toggle(sectionId, "AutoScale", "Auto scale", "Shrinks the window to fit small screens.")
			toggle(sectionId, "Acrylic", "Acrylic blur", "Blurs the game behind the window.")
			dropdown(sectionId, "TopbarStyle", "Top bar buttons", { "Default", "Mac" })
		end

		function builders.Reset()
			local sectionId = section("Reset", "Reset")
			app:Button(elementId("Reset"), sectionId, {
				Title = "Reset appearance",
				Desc = "Back to the look this script ships with.",
				Callback = function()
					self.Reset()
					syncPickers()
				end,
			})
		end

		for _, name in names do
			local build = builders[name]
			assert(build, ("Appearance.BuildTab: unknown section '%s'"):format(tostring(name)))
			build()
		end
	end

	return self
end

return Appearance
