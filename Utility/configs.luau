--[[
	Configs: named snapshots of a hub's settings, one JSON file each, with the controls to manage them.

	local Configs = Utility.configs
	hub.Configs = Configs.new(hub, { Folder = "My Hub/Configs/" .. GAME })
	hub.Configs.BuildSection("Setting")               -- save / load / delete / export / import, inside a tab you created

	A config is { Version = 1, Name, Game, Settings = { ... } } in <Folder>/<name>.json. It holds the plain values
	of the settings (booleans, strings, finite numbers); the settings object's own fields and the keys the host
	excludes never travel. Loading applies a config through the settings store, so every bound control follows;
	the Priority:* / Interruptible:* overrides a config does not mention are cleared, and a value whose type
	differs from the current setting's is skipped.

	Host: the table handed to Configs.new
	  Settings   the settings store: indexable and writable, with Snapshot() (a shallow copy of its values)
	  app        the AuctusAPI WindUI app, only for BuildSection (Section, Input, Dropdown, Button, Dialog, Notify,
	             InputText, Escape)
	  GAME       string?  names the default folder

	options of Configs.new
	  Folder     string          where the files live (default "Configs/<GAME>")
	  MaxName    number          longest config name (default 40)
	  Exclude    { string }      settings keys that never travel (default { "SelectPlayer" })

	configs = Configs.new(hub, options)
	  .CleanName(text)        the trimmed name if it is a safe file name, else nil
	  .List()                 saved names, sorted case-insensitively
	  .Find(name)             the saved name that equals it ignoring case, else nil
	  .FreeName(name)         "Farm" -> "Farm (2)", "Farm (3)"... the first one not taken
	  .Snapshot()             the current settings, minus what never travels
	  .Write(name, data)      ok, err
	  .Parse(text)            { Name, Settings }, or nil and why
	  .ImportName(config)     the name an imported config is saved under
	  .Read(name)             the file text, or nil and why
	  .Load(name)             ok, err
	  .Delete(name)           ok, err
	  .Export(name)           copies the file text to the clipboard: ok, err
	  .BuildSection(tabId, options)
	      options: Id (prefix of the ids, default "Config": ConfigSection, ConfigName, ConfigSelect, ConfigSave,
	      ConfigLoad, ConfigDelete, ConfigExport, ConfigImportData, ConfigImport), Title (default "Config"),
	      Opened (default true), Export and Import (false leaves that control out)
	  Import saves a pasted config; it does not load it.
]]

local HttpService = game:GetService("HttpService")

local Configs = {}

-- Windows treats these as devices whatever the extension
local RESERVED = { con = true, prn = true, aux = true, nul = true }

---Make the config store for a host.
function Configs.new(hub: any, options: { Folder: string?, MaxName: number?, Exclude: { string }? }?)
	assert(type(hub) == "table" and hub.Settings, "Configs.new(hub): the hub needs Settings")
	local choices: { Folder: string?, MaxName: number?, Exclude: { string }? } = options or {}
	local Settings = hub.Settings
	local self = {}

	local FOLDER = choices.Folder or ("Configs/%s"):format(hub.GAME or "Default")
	local MAX_NAME = choices.MaxName or 40
	-- never part of a config: the settings object's own fields, which a config must not be able to overwrite,
	-- and whatever the host keeps per session (by default the target player)
	local EXCLUDED = { Changed = true, Save = true, Snapshot = true }
	local sessionKeys: { string } = choices.Exclude or { "SelectPlayer" }
	for _, key in sessionKeys do
		EXCLUDED[key] = true
	end

	local function filePath(name: string): string
		return ("%s/%s.json"):format(FOLDER, name)
	end

	-- only plain values travel in a config
	local function isValue(value: any): boolean
		local kind = type(value)
		return kind == "boolean" or kind == "string" or (kind == "number" and value == value and math.abs(value) ~= math.huge)
	end

	-- ── the files ─────────────────────────────────────────────────────────

	-- the name as a safe file name, or nil
	function self.CleanName(text: string): string?
		local name = text:match("^%s*(.-)%s*$")
		if #name < 1 or #name > MAX_NAME or not name:match("^[%w _%-%(%)]+$") then
			return nil
		end
		local lower = name:lower()
		if RESERVED[lower] or lower:match("^com%d$") or lower:match("^lpt%d$") then
			return nil
		end
		return name
	end

	function self.List(): { string }
		local names = {}
		if isfolder(FOLDER) then
			for _, path in listfiles(FOLDER) do
				local name = path:match("([^/\\]+)%.json$")
				if name and isfile(path) then
					table.insert(names, name)
				end
			end
		end
		table.sort(names, function(a, b)
			return a:lower() < b:lower()
		end)
		return names
	end

	-- the saved config with this name (case does not matter on Windows), as it is saved
	function self.Find(name: string): string?
		local lower = name:lower()
		for _, existing in self.List() do
			if existing:lower() == lower then
				return existing
			end
		end
		return nil
	end

	-- "Farm" -> "Farm (2)", "Farm (3)"... the first one not taken
	function self.FreeName(name: string): string
		local base = name:gsub("%s*%(%d+%)$", "")
		local index = 2
		while true do
			local suffix = (" (%d)"):format(index)
			local candidate = base:sub(1, MAX_NAME - #suffix) .. suffix
			if not self.Find(candidate) then
				return candidate
			end
			index += 1
		end
	end

	-- the current settings, minus what never travels
	function self.Snapshot(): { [string]: any }
		local data = {}
		for key, value in Settings:Snapshot() do
			if type(key) == "string" and not EXCLUDED[key] and isValue(value) then
				data[key] = value
			end
		end
		return data
	end

	function self.Write(name: string, data: { [string]: any }): (boolean, string?)
		local ok, err = pcall(function()
			makefolder(FOLDER)
			writefile(filePath(name), HttpService:JSONEncode({ Version = 1, Name = name, Game = hub.GAME, Settings = data }))
		end)
		return ok, not ok and tostring(err) or nil
	end

	-- a config's text: its own name if it carries one, and the settings that are safe to apply
	function self.Parse(text: string): ({ Name: string?, Settings: { [string]: any } }?, string?)
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(text)
		end)
		if not ok or type(decoded) ~= "table" or type(decoded.Settings) ~= "table" then
			return nil, "That is not a config."
		end
		local data = {}
		for key, value in decoded.Settings do
			if type(key) == "string" and #key <= 64 and not EXCLUDED[key] and isValue(value) then
				data[key] = value
			end
		end
		if next(data) == nil then
			return nil, "That config is empty."
		end
		return { Name = type(decoded.Name) == "string" and decoded.Name or nil, Settings = data }, nil
	end

	-- the name an imported config is saved under: its own when it is a clean one, else a cleaned-up copy
	function self.ImportName(config: any): string
		local scrubbed = ((config.Name or ""):gsub("[^%w _%-%(%)]", "_")):sub(1, MAX_NAME)
		return self.CleanName(scrubbed) or "Imported"
	end

	function self.Read(name: string): (string?, string?)
		local path = filePath(name)
		if not isfile(path) then
			return nil, "That config is no longer saved."
		end
		local ok, text = pcall(readfile, path)
		if not ok then
			return nil, tostring(text)
		end
		return text, nil
	end

	function self.Load(name: string): (boolean, string?)
		local text, readError = self.Read(name)
		if not text then
			return false, readError
		end
		local config, parseError = self.Parse(text)
		if not config then
			return false, parseError
		end

		-- an override the config does not mention was not there when it was saved
		for key in Settings:Snapshot() do
			if
				type(key) == "string"
				and (key:sub(1, 9) == "Priority:" or key:sub(1, 14) == "Interruptible:")
				and config.Settings[key] == nil
			then
				Settings[key] = nil
			end
		end
		for key, value in config.Settings do
			local current = Settings[key]
			if current == nil or type(current) == type(value) then -- a string must not replace a number
				Settings[key] = value
			end
		end
		return true, nil
	end

	function self.Delete(name: string): (boolean, string?)
		local ok, err = pcall(delfile, filePath(name))
		return ok, not ok and tostring(err) or nil
	end

	function self.Export(name: string): (boolean, string?)
		local text, readError = self.Read(name)
		if not text then
			return false, readError
		end
		if not self.Parse(text) then
			return false, "That config file is damaged."
		end
		if not setclipboard then
			return false, "This executor has no clipboard."
		end
		setclipboard(text)
		return true, nil
	end

	-- ── the controls ──────────────────────────────────────────────────────

	---Build the Config section inside a tab the host created.
	function self.BuildSection(
		tabId: string,
		sectionOptions: { Id: string?, Title: string?, Opened: boolean?, Export: boolean?, Import: boolean? }?
	)
		local app = hub.app
		assert(app, "Configs.BuildSection: the hub needs its app")
		local sectionChoices: { Id: string?, Title: string?, Opened: boolean?, Export: boolean?, Import: boolean? } =
			sectionOptions or {}
		local prefix = sectionChoices.Id or "Config"
		local sectionId = prefix .. "Section"
		app:Section(sectionId, tabId, { Title = sectionChoices.Title or "Config", Opened = sectionChoices.Opened ~= false })

		local selectedConfig: string? = nil
		local nameInput, configDropdown, importInput

		local function notify(title: string, content: string, icon: string?)
			app:Notify({ Title = title, Content = app:Escape(content), Icon = icon or "check", Duration = 3 })
		end

		-- the files changed: redraw the list and move the selection to `name` (nil = none). The dropdown
		-- takes its new value first so redrawing cannot report the old one, and the selection is set last
		local function refreshConfigs(name: string?)
			pcall(function()
				configDropdown:Select(name)
			end)
			pcall(function()
				configDropdown:Refresh(self.List())
			end)
			selectedConfig = name
		end

		-- the name is taken: replace it, save beside it as a copy, or back out
		local function askSameName(name: string, existing: string, write: (string) -> ())
			app:Dialog({
				Title = "Config already exists",
				Content = ("A config named '%s' is already saved."):format(app:Escape(existing)),
				Icon = "triangle-alert",
				Width = 380,
				Buttons = {
					{
						Title = "Replace",
						Variant = "Primary",
						Callback = function()
							write(existing)
						end,
					},
					{
						Title = "Make copy",
						Variant = "Secondary",
						Callback = function()
							write(self.FreeName(name))
						end,
					},
					{ Title = "Cancel", Variant = "Secondary" },
				},
			})
		end

		local function saveAs(name: string)
			local ok, err = self.Write(name, self.Snapshot())
			if not ok then
				notify("Save failed", err or "Could not write the file.", "triangle-alert")
				return
			end
			refreshConfigs(name)
			pcall(function()
				nameInput:Set(name)
			end)
			notify("Config saved", name, "save")
		end

		nameInput = app:Input(prefix .. "Name", sectionId, {
			Title = "Config name",
			Desc = "Letters, numbers, spaces, - and _.",
			Placeholder = "My config",
		})
		configDropdown = app:Dropdown(prefix .. "Select", sectionId, {
			Title = "Select config",
			Values = self.List(),
			Callback = function(name)
				if type(name) == "string" and name ~= "" then
					selectedConfig = name
					pcall(function()
						nameInput:Set(name)
					end)
				end
			end,
		})
		app:Button(prefix .. "Save", sectionId, {
			Title = "Save config",
			Desc = "Saves the current settings under the name above.",
			Callback = function()
				local name = self.CleanName(app:InputText(nameInput))
				if not name then
					notify("Invalid name", ("Use up to %d letters, numbers, spaces, - or _."):format(MAX_NAME), "triangle-alert")
					return
				end
				local existing = self.Find(name)
				if existing then
					askSameName(name, existing, saveAs)
				else
					saveAs(name)
				end
			end,
		})
		app:Button(prefix .. "Load", sectionId, {
			Title = "Load config",
			Desc = "Applies the selected config to the current settings.",
			Callback = function()
				if not selectedConfig then
					notify("Select a config", "Pick the config to load from the list.", "info")
					return
				end
				local ok, err = self.Load(selectedConfig)
				if ok then
					notify("Config loaded", selectedConfig, "check")
				else
					notify("Load failed", err or "Could not read the config.", "triangle-alert")
				end
			end,
		})
		app:Button(prefix .. "Delete", sectionId, {
			Title = "Delete config",
			Desc = "Deletes the selected config.",
			Callback = function()
				local name = selectedConfig
				if not name then
					notify("Select a config", "Pick the config to delete from the list.", "info")
					return
				end
				app:Dialog({
					Title = "Delete config",
					Content = ("Delete '%s'? This cannot be undone."):format(app:Escape(name)),
					Icon = "trash-2",
					Width = 380,
					Buttons = {
						{
							Title = "Delete",
							Variant = "Primary",
							Callback = function()
								local ok, err = self.Delete(name)
								if ok then
									refreshConfigs(nil)
									notify("Config deleted", name, "trash-2")
								else
									notify("Delete failed", err or "Could not delete the file.", "triangle-alert")
								end
							end,
						},
						{ Title = "Cancel", Variant = "Secondary" },
					},
				})
			end,
		})

		if sectionChoices.Export ~= false then
			app:Button(prefix .. "Export", sectionId, {
				Title = "Export config",
				Desc = "Copies the selected config to the clipboard.",
				Callback = function()
					if not selectedConfig then
						notify("Select a config", "Pick the config to export from the list.", "info")
						return
					end
					local ok, err = self.Export(selectedConfig)
					if ok then
						notify("Config copied", ("'%s' is on your clipboard."):format(selectedConfig), "copy")
					else
						notify("Export failed", err or "Could not copy the config.", "triangle-alert")
					end
				end,
			})
		end

		if sectionChoices.Import ~= false then
			importInput = app:Input(prefix .. "ImportData", sectionId, {
				Title = "Import data",
				Desc = "Paste a config copied with Export.",
				Placeholder = "Paste here",
			})
			app:Button(prefix .. "Import", sectionId, {
				Title = "Import config",
				Desc = "Saves the pasted config. Load it afterwards.",
				Callback = function()
					local config, parseError = self.Parse(app:InputText(importInput))
					if not config then
						notify("Import failed", parseError or "That is not a config.", "triangle-alert")
						return
					end

					local function write(name: string)
						local ok, err = self.Write(name, config.Settings)
						if not ok then
							notify("Import failed", err or "Could not write the file.", "triangle-alert")
							return
						end
						refreshConfigs(name)
						pcall(function()
							nameInput:Set(name)
						end)
						pcall(function()
							importInput:Set("")
						end)
						notify("Config imported", name, "download")
					end

					local name = self.ImportName(config)
					local existing = self.Find(name)
					if existing then
						askSameName(name, existing, write)
					else
						write(name)
					end
				end,
			})
		end
	end

	return self
end

return Configs
