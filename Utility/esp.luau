--[[
	ESP: draw things on the screen. You register what to draw, a style setting picks how.

	local Esp = Utility.esp
	Esp.MergeDefaults(DEFAULT_SETTINGS)           -- before the settings store is created
	hub.ESP = Esp.new(hub)                        -- registers "Player" for you
	hub.ESP.Register({ Name = "Chest", Targets = function() return CollectionService:GetTagged("Chest") end })
	-- run hub.ESP.Enable(true) while hub.ESP.AnyOn() (a scheduler task does this); false cleans everything up

	Host: the table handed to Esp.new
	  Settings   the settings store: indexable
	  Trove      root trove; Enable(false) is added to it

	esp.Register(def)
	  Name     string     unique; the on/off setting is "ESP<Name>", its color "ESP<Name>Color"
	  Title    string?    shown in the tab, default Name
	  Color    string?    starting color as hex, default "#ff3b3b"
	  Targets  function   () -> { Instance }: the Models or Parts to draw now
	  Label    function?  (instance) -> string, default instance.Name
	  Refresh  number?    seconds between two Targets calls, default 1

	Styles (Settings.ESPStyle): "Classic" draws with the Drawing library (Line, Square, Name, Health, Bone),
	"Highlight" uses Highlight instances. Every option is a setting listed in Esp.Defaults; to add one, add the
	default, read it in draw() and add a toggle for it in your ESP tab. Customise Esp.Defaults before use: every access of
	Utility.esp is a fresh copy.

]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Esp = {}

Esp.Defaults = {
	ESPSelf = false, -- Player: test the style on your own character
	ESPStyle = "Classic",
	ESPTeamCheck = false,
	ESPMaxDistance = 1500,
	ESPClassicLine = false,
	ESPClassicSquare = true,
	ESPClassicName = true,
	ESPClassicHealth = true,
	ESPClassicBone = false,
	ESPHighlightOutline = "#ffffff", -- colors are hex strings
	ESPHighlightFilled = true,
	ESPHighlightOutlined = true,
	ESPHighlightOpacity = 50,
	ESPHighlightName = true,
}

local BONES_R15 = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}
local BONES_R6 = {
	{ "Head", "Torso" },
	{ "Torso", "Left Arm" },
	{ "Torso", "Right Arm" },
	{ "Torso", "Left Leg" },
	{ "Torso", "Right Leg" },
}

---Add the ESP defaults the target does not have yet (a per-game value stays).
function Esp.MergeDefaults(target: { [string]: any })
	for key, value in Esp.Defaults do
		if target[key] == nil then
			target[key] = value
		end
	end
end

function Esp.new(hub: any)
	assert(type(hub) == "table" and hub.Settings and hub.Trove, "Esp.new(hub): the hub needs Settings and Trove")
	local Settings = hub.Settings
	local localPlayer = Players.LocalPlayer

	local self = { List = {} :: { any } } -- the registered targets, in order
	local connection: RBXScriptConnection? = nil
	local entries: any = {} -- instance -> { objects = key -> Drawing or Highlight, used = key -> frame }
	local holder: Folder? = nil -- where the Highlights live
	local frame = 0

	local function colorOf(key: string, fallback: string?): Color3
		return Color3.fromHex(Settings[key] or fallback or "#ffffff")
	end

	-- made on first use, shown only for the frame that asked for it
	local function part(entry: any, key: string, kind: string): any
		local object = entry.objects[key]
		if not object then
			object = if kind == "Highlight" then Instance.new("Highlight") else Drawing.new(kind :: any)
			entry.objects[key] = object
		end
		entry.used[key] = frame
		if typeof(object) == "Instance" then
			(object :: any).Enabled = true
		else
			object.Visible = true
		end
		return object
	end

	local function drop(entry: any)
		for _, object in entry.objects do
			if typeof(object) == "Instance" then
				object:Destroy()
			else
				object:Remove()
			end
		end
	end

	-- one target for one frame
	local function draw(def: any, target: Instance, entry: any, camera: Camera, color: Color3)
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local root = target:FindFirstChild("HumanoidRootPart")
		local center, size
		if humanoid and root then
			center, size = root.Position - Vector3.new(0, 0.25, 0), Vector3.new(4, 6.5, 4) -- a steady box for characters
		elseif target:IsA("Model") then
			local cframe, extents = target:GetBoundingBox()
			center, size = cframe.Position, extents
		elseif target:IsA("BasePart") then
			center, size = target.Position, target.Size
		else
			return
		end
		if (camera.CFrame.Position - center).Magnitude > Settings.ESPMaxDistance then
			return
		end

		local top = camera:WorldToViewportPoint(center + Vector3.yAxis * size.Y / 2)
		local bottom = camera:WorldToViewportPoint(center - Vector3.yAxis * size.Y / 2)
		local mid = camera:WorldToViewportPoint(center)
		local side = camera:WorldToViewportPoint(center + camera.CFrame.RightVector * math.max(size.X, size.Z) / 2)
		if top.Z <= 0 or bottom.Z <= 0 then
			return -- behind the camera
		end
		local height = bottom.Y - top.Y
		local width = math.abs(side.X - mid.X) * 2

		local function name()
			local text = part(entry, "Name", "Text")
			text.Text = if def.Label then def.Label(target) else target.Name
			text.Size = 14
			text.Center = true
			text.Outline = true
			text.Color = color
			text.Position = Vector2.new(mid.X, top.Y - 16)
		end

		if Settings.ESPStyle == "Highlight" then
			local highlight = part(entry, "Highlight", "Highlight")
			highlight.Adornee = target
			highlight.Parent = holder
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = color
			highlight.OutlineColor = colorOf("ESPHighlightOutline")
			highlight.FillTransparency = if Settings.ESPHighlightFilled then 1 - Settings.ESPHighlightOpacity / 100 else 1
			highlight.OutlineTransparency = if Settings.ESPHighlightOutlined then 0 else 1
			if Drawing and Settings.ESPHighlightName then
				name()
			end
		elseif Settings.ESPStyle == "Classic" and Drawing then
			if Settings.ESPClassicSquare then
				local box = part(entry, "Square", "Square")
				box.Position = Vector2.new(mid.X - width / 2, top.Y)
				box.Size = Vector2.new(width, height)
				box.Color = color
				box.Thickness = 1
				box.Filled = false
			end
			if Settings.ESPClassicLine then
				local line = part(entry, "Line", "Line")
				line.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
				line.To = Vector2.new(mid.X, bottom.Y)
				line.Color = color
				line.Thickness = 1
			end
			if Settings.ESPClassicName then
				name()
			end
			if Settings.ESPClassicHealth and humanoid then
				local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
				local x = mid.X - width / 2 - 4
				local bar = part(entry, "Health", "Line")
				bar.From = Vector2.new(x, bottom.Y)
				bar.To = Vector2.new(x, bottom.Y - height * ratio)
				bar.Color = Color3.fromHSV(ratio / 3, 1, 1)
				bar.Thickness = 2
			end
			if Settings.ESPClassicBone and humanoid then
				local bones = if humanoid.RigType == Enum.HumanoidRigType.R15 then BONES_R15 else BONES_R6
				for index, pair in bones do
					local a, b = target:FindFirstChild(pair[1]), target:FindFirstChild(pair[2])
					if a and b then
						local from = camera:WorldToViewportPoint(a.Position)
						local to = camera:WorldToViewportPoint(b.Position)
						if from.Z > 0 and to.Z > 0 then
							local bone = part(entry, "Bone" .. index, "Line")
							bone.From = Vector2.new(from.X, from.Y)
							bone.To = Vector2.new(to.X, to.Y)
							bone.Color = color
							bone.Thickness = 1
						end
					end
				end
			end
		end
	end

	local function step()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		frame += 1

		for target, entry in entries do
			if not target:IsDescendantOf(game) then
				drop(entry)
				entries[target] = nil
			end
		end

		for _, def in self.List do
			if not Settings["ESP" .. def.Name] then
				continue
			end
			if os.clock() >= (def._next or 0) then
				def._next = os.clock() + (def.Refresh or 1)
				local ok, list = pcall(def.Targets)
				def._list = if ok and type(list) == "table" then list else {}
			end
			local color = colorOf("ESP" .. def.Name .. "Color", def.Color)
			for _, target in def._list or {} do
				local humanoid = target:FindFirstChildOfClass("Humanoid")
				if target.Parent and not (humanoid and humanoid.Health <= 0) then
					local entry = entries[target]
					if not entry then
						entry = { objects = {}, used = {} }
						entries[target] = entry
					end
					draw(def, target, entry, camera, color)
				end
			end
		end

		-- whatever this frame did not ask for (another style, out of range, switched off) goes away
		for _, entry in entries do
			for key, object in entry.objects do
				if entry.used[key] ~= frame then
					if typeof(object) == "Instance" then
						(object :: any).Enabled = false
					else
						object.Visible = false
					end
				end
			end
		end
	end

	---Register something to draw; your ESP tab gives it a toggle and a color.
	function self.Register(def: any)
		assert(
			type(def) == "table" and type(def.Name) == "string" and type(def.Targets) == "function",
			"ESP.Register{ Name = string, Targets = function }"
		)
		def.Title = def.Title or def.Name
		def.Color = def.Color or "#ff3b3b"
		table.insert(self.List, def)
	end

	---Is any registered target switched on?
	function self.AnyOn(): boolean
		for _, def in self.List do
			if Settings["ESP" .. def.Name] then
				return true
			end
		end
		return false
	end

	---Start (true), stop and clean up (false) or toggle (nil) the drawing.
	function self.Enable(enabled: boolean?): boolean
		if enabled == nil then
			enabled = not connection
		end

		if not enabled then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			for _, entry in entries do
				drop(entry)
			end
			table.clear(entries)
			if holder then
				holder:Destroy()
				holder = nil
			end
			return false
		end

		if connection then
			return true
		end
		if not Drawing then
			warn("[ESP] no Drawing library, only the Highlight style works")
		end
		local folder = Instance.new("Folder")
		folder.Name = "ApexESP"
		folder:AddTag("ApexHubGui") -- a crashed run's highlights are swept up with its window
		folder.Parent = if gethui then gethui() else game:GetService("CoreGui")
		holder = folder
		connection = RunService.RenderStepped:Connect(step)
		return true
	end

	hub.Trove:Add(function()
		self.Enable(false)
	end)

	self.Register({
		Name = "Player",
		Title = "Players",
		Refresh = 0.25,
		Targets = function()
			local list = {}
			for _, player in Players:GetPlayers() do
				local mine = player == localPlayer
				local friend = player.Team ~= nil and player.Team == localPlayer.Team
				if player.Character and (not mine or Settings.ESPSelf) and not (Settings.ESPTeamCheck and friend and not mine) then
					table.insert(list, player.Character)
				end
			end
			return list
		end,
		Label = function(character)
			local player = Players:GetPlayerFromCharacter(character)
			return if player then player.DisplayName else character.Name
		end,
	})

	return self
end

return Esp
