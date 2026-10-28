local Modules = {}

Modules["Extend"] = function(...)
	return function<object, attach>(obj: object, objOrInstance: attach): object & attach
		local cache = {}
	
		local mt = {}
		mt.__index = function(_, key)
			-- Prefer table methods
			local v = rawget(obj, key)
			
			if v ~= nil then
				return v
			end
	
			-- Bind instance methods safely
			local instValue = objOrInstance[key]
			
			if type(instValue) == "function" then
				return function(_, ...)
					return instValue(objOrInstance, ...)
				end
			end
	
			return instValue
		end
		
		mt.__tostring = function()
			return tostring(objOrInstance)
		end
	
		return setmetatable(obj, mt) :: object & attach
	end
	
end
Modules["concur"] = function(...)
	--!strict
	
	-- Concur
	-- Stephen Leitnick
	-- May 01, 2022
	
	type Error = any
	type AnyFn = (...any) -> ...any
	
	--[=[
		@class Concur
	
		Concurrency class for helping run tasks concurrently. In other words, Concur allows
		developers to watch coroutines/threads. Completion status, returned values, and
		errors can all be tracked.
	
		For instance, Concur could be used to concurrently save all player data
		at the same time when the game closes down:
	
		```lua
		game:BindToClose(function()
			local all = {}
			for _,player in Players:GetPlayers() do
				local save = Concur.spawn(function()
					DoSomethingToSaveData(player)
				end)
				table.insert(all, save)
			end
			local allConcur = Concur.all(all)
			allConcur:Await()
		end)
		```
	]=]
	local Concur = {}
	Concur.__index = Concur
	
	--[=[
		@within Concur
		@interface Errors
		.Stopped "Stopped"
		.Timeout "Timeout"
	]=]
	
	--[=[
		@within Concur
		@readonly
		@prop Errors Errors
	]=]
	Concur.Errors = {
		Stopped = "Stopped",
		Timeout = "Timeout",
	}
	
	function Concur._new(fn: AnyFn, spawner: AnyFn, ...: any): Concur
		local self: Concur = setmetatable({
			_completed = false,
			_res = nil,
			_err = nil,
			_awaitingThreads = {},
			_thread = nil,
		}, Concur)
	
		self._thread = spawner(function(...)
			local pcallRes = table.pack(pcall(fn, ...))
			self._completed = true
			self._err = if not pcallRes[1] then pcallRes[2] else nil
			if self._err ~= nil then
				for _, thread in ipairs(self._awaitingThreads) do
					task.spawn(thread, self._err)
				end
			else
				local res = table.move(pcallRes, 2, #pcallRes, 1, table.create(#pcallRes - 1))
				self._res = res
				for _, thread in ipairs(self._awaitingThreads) do
					task.spawn(thread, nil, table.unpack(res, 1, res.n))
				end
			end
		end, ...)
	
		return self
	end
	
	--[=[
		Spawns the function using `task.spawn`.
	
		```lua
		local c = Concur.spawn(function()
			task.wait(5)
			return "Hello!"
		end)
	
		c:OnCompleted(function(err, msg)
			if err then
				error(err)
			end
			print(msg) --> Hello!
		end))
		```
	]=]
	function Concur.spawn(fn: AnyFn, ...: any): Concur
		if type(fn) ~= "function" then
			error("Concur.spawn argument must be a function; got " .. type(fn), 2)
		end
		return Concur._new(fn, task.spawn, ...)
	end
	
	--[=[
		Same as `Concur.spawn`, but uses `task.defer` internally.
	]=]
	function Concur.defer(fn: AnyFn, ...: any): Concur
		if type(fn) ~= "function" then
			error("Concur.defer argument must be a function; got " .. type(fn), 2)
		end
		return Concur._new(fn, task.defer, ...)
	end
	
	--[=[
		Same as `Concur.spawn`, but uses `task.delay` internally.
	]=]
	function Concur.delay(delayTime: number, fn: AnyFn, ...: any): Concur
		if type(fn) ~= "function" then
			error("Concur.delay argument must be a function; got " .. type(fn), 2)
		end
		return Concur._new(fn, function(...)
			return task.delay(delayTime, ...)
		end, ...)
	end
	
	--[=[
		Resolves to the given value right away.
	
		```lua
		local val = Concur.value(10)
		val:OnCompleted(function(v)
			print(v) --> 10
		end)
		```
	]=]
	function Concur.value(value: any): Concur
		return Concur.spawn(function()
			return value
		end)
	end
	
	--[=[
		Completes the Concur instance once the event is fired and the predicate
		function returns `true` (if no predicate is given, then completes once
		the event first fires).
	
		The Concur instance will return the values given by the event.
	
		```lua
		-- Wait for next player to touch an object:
		local touch = Concur.event(part.Touched, function(toucher)
			return Players:GetPlayerFromCharacter(toucher.Parent) ~= nil
		end)
	
		touch:OnCompleted(function(err, toucher)
			print(toucher)
		end)
		```
	]=]
	function Concur.event(event: RBXScriptSignal, predicate: ((...any) -> boolean)?)
		local connection, thread
	
		connection = event:Connect(function(...)
			if not thread then
				return
			end
			if predicate == nil or predicate(...) then
				connection:Disconnect()
				task.spawn(thread, ...)
			end
		end)
	
		local c = Concur.spawn(function()
			thread = coroutine.running()
			return coroutine.yield()
		end)
	
		c:OnCompleted(function(err)
			connection:Disconnect()
			if coroutine.status(thread) == "suspended" then
				task.spawn(thread, err)
			end
		end)
	
		return c
	end
	
	--[=[
		Completes once _all_ Concur instances have been completed. All values
		will be available in a packed table in the same order they were passed.
	
		```lua
		local c1 = Concur.spawn(function()
			return 10
		end)
	
		local c2 = Concur.delay(0.5, function()
			return 15
		end)
	
		local c3 = Concur.value(20)
	
		local c4 = Concur.spawn(function()
			error("failed")
		end)
	
		Concur.all({c1, c2, c3}):OnCompleted(function(err, values)
			print(values) --> {{nil, 10}, {nil, 15}, {nil, 20}, {"failed", nil}}
		end)
		```
	]=]
	function Concur.all(concurs: { Concur }): Concur
		if #concurs == 0 then
			return Concur.value(nil)
		end
	
		return Concur.spawn(function()
			local numCompleted = 0
			local total = #concurs
			local thread = coroutine.running()
			local allRes = table.create(total)
			for i, concur in ipairs(concurs) do
				concur:OnCompleted(function(...)
					allRes[i] = table.pack(...)
					numCompleted += 1
					if numCompleted >= total and coroutine.status(thread) == "suspended" then
						task.spawn(thread)
					end
				end)
			end
			if numCompleted < total then
				coroutine.yield()
			end
			return allRes
		end)
	end
	
	--[=[
		Completes once the first Concur instance is completed _without an error_. All other Concur
		instances are then stopped.
	
		```lua
		local c1 = Concur.delay(1, function()
			return 10
		end)
	
		local c2 = Concur.delay(0.5, function()
			return 5
		end)
	
		Concur.first({c1, c2}):OnCompleted(function(err, num)
			print(num) --> 5
		end)
		```
	]=]
	function Concur.first(concurs: { Concur }): Concur
		if #concurs == 0 then
			return Concur.value(nil)
		end
	
		return Concur.spawn(function()
			local thread = coroutine.running()
			local res = nil
			local firstConcur = nil
			for _, concur in ipairs(concurs) do
				concur:OnCompleted(function(err, ...)
					if res or err ~= nil then
						return
					end
					firstConcur = concur
					res = table.pack(...)
					if coroutine.status(thread) == "suspended" then
						task.spawn(thread)
					end
				end)
			end
			if res == nil then
				coroutine.yield()
			end
			for _, concur in ipairs(concurs) do
				if concur == firstConcur then
					continue
				end
				concur:Stop()
			end
			return table.unpack(res, 1, res.n)
		end)
	end
	
	--[=[
		Stops the Concur instance. The underlying thread will be cancelled using
		`task.cancel`. Any bound `OnCompleted` functions or threads waiting with
		`Await` will be completed with the error `Concur.Errors.Stopped`.
	
		```lua
		local c = Concur.spawn(function()
			for i = 1,10 do
				print(i)
				task.wait(1)
			end
		end)
	
		task.wait(2.5)
		c:Stop() -- At this point, will have only printed 1 and 2
		```
	]=]
	function Concur:Stop()
		if self._completed then
			return
		end
		self._completed = true
		self._err = Concur.Errors.Stopped
		task.cancel(self._thread)
		for _, thread: thread in ipairs(self._awaitingThreads) do
			task.spawn(thread, Concur.Errors.Stopped)
		end
	end
	
	--[=[
		Check if the Concur instance is finished.
	]=]
	function Concur:IsCompleted(): boolean
		return self._completed
	end
	
	--[=[
		@yields
		Yields the calling thread until the Concur instance is completed:
		
		```lua
		local c = Concur.delay(5, function()
			return "Hi"
		end)
	
		local err, msg = c:Await()
		print(msg) --> Hi
		```
	
		The `Await` method can be called _after_ the Concur instance
		has been completed too, in which case the completed values
		will be returned immediately without yielding the thread:
	
		```lua
		local c = Concur.spawn(function()
			return 10
		end)
	
		task.wait(5)
		-- Called after 'c' has been completed, but still captures the value:
		local err, num = c:Await()
		print(num) --> 10
		```
	
		It is always good practice to make sure that the `err` value is handled
		by checking if it is not nil:
	
		```lua
		local c = Concur.spawn(function()
			error("failed")
		end)
	
		local err, value = c:Await()
	
		if err ~= nil then
			print(err) --> failed
			-- Handle error `err`
		else
			-- Handle `value`
		end
		```
	
		This will stop awaiting if the Concur instance was stopped
		too, in which case the `err` will be equal to
		`Concur.Errors.Stopped`:
	
		```lua
		local c = Concur.delay(10, function() end)
		c:Stop()
		local err = c:Await()
		if err == Concur.Errors.Stopped then
			print("Was stopped")
		end
		```
	
		An optional timeout can be given, which will return the
		`Concur.Errors.Timeout` error if timed out. Timing out
		does _not_ stop the Concur instance, so other callers
		to `Await` or `OnCompleted` can still grab the resulting
		values.
	
		```lua
		local c = Concur.delay(10, function() end)
		local err = c:Await(1)
		if err == Concur.Errors.Timeout then
			-- Handle timeout
		end
		```
	]=]
	function Concur:Await(timeout: number?): (Error, ...any?)
		if self._completed then
			if self._err ~= nil then
				return self._err
			else
				return nil, if self._res == nil then nil else table.unpack(self._res, 1, self._res.n)
			end
		end
	
		local thread = coroutine.running()
		table.insert(self._awaitingThreads, thread)
	
		if timeout then
			local delayThread = task.delay(timeout, function()
				local index = table.find(self._awaitingThreads, thread)
				if index then
					table.remove(self._awaitingThreads, index)
					task.spawn(thread, Concur.Errors.Timeout)
				end
			end)
			local res = table.pack(coroutine.yield())
			if coroutine.status(delayThread) ~= "normal" then
				task.cancel(delayThread)
			end
			return table.unpack(res, 1, res.n)
		else
			return coroutine.yield()
		end
	end
	
	--[=[
		Calls the given function once the Concur instance is completed:
	
		```lua
		local c = Concur.delay(5, function()
			return "Hi"
		end)
	
		c:OnCompleted(function(err, msg)
			print(msg) --> Hi
		end)
		```
	
		A function is returned that can be used to unbind the function to
		no longer fire when the Concur instance is completed:
	
		```lua
		local c = Concur.delay(5, function() end)
		local unbind = c:OnCompleted(function()
			print("Completed")
		end)
		unbind()
		-- Never prints "Completed"
		```
	
		The `OnCompleted` method can be called _after_ the Concur instance
		has been completed too, in which case the given function will be
		called immediately with the completed values:
	
		```lua
		local c = Concur.spawn(function()
			return 10
		end)
	
		task.wait(5)
		-- Called after 'c' has been completed, but still captures the value:
		c:OnCompleted(function(err, num)
			print(num) --> 10
		end)
		```
	
		It is always good practice to make sure that the `err` value is handled
		by checking if it is not nil:
	
		```lua
		local c = Concur.spawn(function()
			error("failed")
		end)
	
		c:OnCompleted(function(err, value)
			if err ~= nil then
				print(err) --> failed
				-- Handle error `err`
				return
			end
			-- Handle `value`
		end)
		```
	
		This will call the function if the Concur instance was stopped
		too, in which case the `err` will be equal to
		`Concur.Errors.Stopped`:
	
		```lua
		local c = Concur.delay(10, function() end)
		c:OnCompleted(function(err)
			if err == Concur.Errors.Stopped then
				print("Was stopped")
			end
		end)
		c:Stop()
		```
	
		An optional timeout can also be supplied, which will call the
		function with the `Concur.Errors.Timeout` error:
	
		```lua
		local c = Concur.delay(10, function() end)
		c:OnCompleted(function(err)
			if err == Concur.Errors.Timeout then
				-- Handle timeout
			end
		end, 1)
		```
	]=]
	function Concur:OnCompleted(fn: (Error, ...any?) -> (), timeout: number?): () -> ()
		local thread = task.spawn(function()
			fn(self:Await(timeout))
		end)
	
		-- Unbind:
		return function()
			task.cancel(thread)
			local index = table.find(self._awaitingThreads, thread)
			if index then
				table.remove(self._awaitingThreads, index)
			end
		end
	end
	
	type ConcurObj = {
		_completed: boolean,
		_res: { any }?,
		_err: string?,
		_awaitingThreads: { thread },
		_thread: thread?,
	}
	
	export type Concur = typeof(setmetatable({} :: ConcurObj, Concur))
	
	return Concur
	
end
Modules["enum-list"] = function(...)
	-- EnumList
	-- Stephen Leitnick
	-- January 08, 2021
	
	type EnumNames = { string }
	
	--[=[
		@interface EnumItem
		.Name string
		.Value number
		.EnumType EnumList
		@within EnumList
	]=]
	export type EnumItem = {
		Name: string,
		Value: number,
		EnumType: any,
	}
	
	local LIST_KEY = newproxy()
	local NAME_KEY = newproxy()
	
	local function CreateEnumItem(name: string, value: number, enum: any): EnumItem
		local enumItem = {
			Name = name,
			Value = value,
			EnumType = enum,
		}
		table.freeze(enumItem)
		return enumItem
	end
	
	--[=[
		@class EnumList
		Defines a new Enum.
	]=]
	local EnumList = {}
	EnumList.__index = EnumList
	
	--[=[
		@param name string
		@param enums {string}
		@return EnumList
		Constructs a new EnumList.
	
		```lua
		local directions = EnumList.new("Directions", {
			"Up",
			"Down",
			"Left",
			"Right",
		})
	
		local direction = directions.Up
		```
	]=]
	function EnumList.new(name: string, enums: EnumNames)
		assert(type(name) == "string", "Name string required")
		assert(type(enums) == "table", "Enums table required")
		local self = {}
		self[LIST_KEY] = {}
		self[NAME_KEY] = name
		for i, enumName in ipairs(enums) do
			assert(type(enumName) == "string", "Enum name must be a string")
			local enumItem = CreateEnumItem(enumName, i, self)
			self[enumName] = enumItem
			table.insert(self[LIST_KEY], enumItem)
		end
		return table.freeze(setmetatable(self, EnumList))
	end
	
	--[=[
		@param obj any
		@return boolean
		Returns `true` if `obj` belongs to the EnumList.
	]=]
	function EnumList:BelongsTo(obj: any): boolean
		return type(obj) == "table" and obj.EnumType == self
	end
	
	--[=[
		Returns an array of all enum items.
		@return {EnumItem}
		@since v2.0.0
	]=]
	function EnumList:GetEnumItems()
		return self[LIST_KEY]
	end
	
	--[=[
		Get the name of the enum.
		@return string
		@since v2.0.0
	]=]
	function EnumList:GetName()
		return self[NAME_KEY]
	end
	
	export type EnumList = typeof(EnumList.new(...))
	
	return EnumList
	
end
Modules["find"] = function(...)
	--!strict
	
	--[=[
		@class Find
	
		A utility function for finding objects in the data model hierarchy.
	
		Similar to `FindFirstChild`, except it explicitly errors if any object
		is not found, as well as a more helpful message as to what wasn't found.
	
		```lua
		local find = require(ReplicatedStorage.Packages.find)
	
		-- Find instance "workspace.Some.Folder.Here.Item":
		local item = find(workspace, "Some", "Folder", "Here", "Item")
		```
	
		In the above example, if "Folder" didn't exist, the function would throw an error with the message: `failed to find instance "Folder" within "Workspace.Some"`.
	
		The return type is simply `Instance`. Any type-checking should be done on the return value:
		```lua
		local part = find(workspace, "SomePart") :: BasePart -- Blindly assume and type this as a BasePart
		assert(part:IsA("BasePart")) -- Extra optional precaution to ensure type
		```
	]=]
	
	local function find(parent: Instance, ...: string): Instance
		local instance = parent
	
		for i = 1, select("#", ...) do
			local name = (select(i, ...))
	
			local inst = instance:FindFirstChild(name)
			if inst == nil then
				error(`failed to find instance "{name}" within {instance:GetFullName()}`, 2)
			end
	
			instance = inst
		end
	
		return instance
	end
	
	return find
	
end
Modules["loader"] = function(...)
	--[=[
		@class Loader
	
		The Loader module will require all children or descendant ModuleScripts. There are also
		some utility functions included, which assist with loading and starting modules in
		single-script environments.
	
		For example, here is a loader that loads all ModuleScripts under a folder that end with
		the name Service, and then calls all of their OnStart methods:
		```lua
		local MyModules = ReplicatedStorage.MyModules
		Loader.SpawnAll(
			Loader.LoadDescendants(MyModules, Loader.MatchesName("Service$")),
			"OnStart"
		)
		```
	]=]
	local Loader = {}
	
	--[=[
		@within Loader
		@type PredicateFn (module: ModuleScript) -> boolean
		Predicate function type.
	]=]
	type PredicateFn = (module: ModuleScript) -> boolean
	
	--[=[
		Requires all children ModuleScripts.
	
		If a `predicate` function is provided, then the module will only
		be loaded if the predicate returns `true` for the the given
		ModuleScript.
	
		```lua
		-- Load all ModuleScripts directly under MyModules:
		Loader.LoadChildren(ReplicatedStorage.MyModules)
	
		-- Load all ModuleScripts directly under MyModules if they have names ending in 'Service':
		Loader.LoadChildren(ReplicatedStorage.MyModules, function(moduleScript)
			return moduleScript.Name:match("Service$") ~= nil
		end)
		```
	]=]
	function Loader.LoadChildren(parent: Instance, predicate: PredicateFn?): { [string]: any }
		local modules: { [string]: any } = {}
		for _, child in parent:GetChildren() do
			if child:IsA("ModuleScript") then
				if predicate and not predicate(child) then
					continue
				end
				local m = require(child)
				modules[child.Name] = m
			end
		end
		return modules
	end
	
	--[=[
		Requires all descendant ModuleScripts.
	
		If a `predicate` function is provided, then the module will only
		be loaded if the predicate returns `true` for the the given
		ModuleScript.
	
		```lua
		-- Load all ModuleScripts under MyModules:
		Loader.LoadDescendants(ReplicatedStorage.MyModules)
	
		-- Load all ModuleScripts under MyModules if they have names ending in 'Service':
		Loader.LoadDescendants(ReplicatedStorage.MyModules, function(moduleScript)
			return moduleScript.Name:match("Service$") ~= nil
		end)
	]=]
	function Loader.LoadDescendants(parent: Instance, predicate: PredicateFn?): { [string]: any }
		local modules: { [string]: any } = {}
		for _, descendant in parent:GetDescendants() do
			if descendant:IsA("ModuleScript") then
				if predicate and not predicate(descendant) then
					continue
				end
				local m = require(descendant)
				modules[descendant.Name] = m
			end
		end
		return modules
	end
	
	--[=[
		A commonly-used predicate in the `LoadChildren` and `LoadDescendants`
		functions is one to match names. Therefore, the `MatchesName` utility
		function provides a quick way to create such predicates.
	
		```lua
		Loader.LoadDescendants(ReplicatedStorage.MyModules, Loader.MatchesName("Service$"))
		```
	]=]
	function Loader.MatchesName(matchName: string): (module: ModuleScript) -> boolean
		return function(moduleScript: ModuleScript): boolean
			return moduleScript.Name:match(matchName) ~= nil
		end
	end
	
	--[=[
		Utility function for spawning a specific method in all given modules.
		If a module does not contain the specified method, it is simply
		skipped. Methods are called with `task.spawn` internally.
	
		For example, if the modules are expected to have an `OnStart()` method,
		then `SpawnAll()` could be used to start all of them directly after
		they have been loaded:
	
		```lua
		local MyModules = ReplicatedStorage.MyModules
	
		-- Load all modules under MyModules and then call their OnStart methods:
		Loader.SpawnAll(Loader.LoadDescendants(MyModules), "OnStart")
	
		-- Same as above, but only loads modules with names that end with Service:
		Loader.SpawnAll(
			Loader.LoadDescendants(MyModules, Loader.MatchesName("Service$")),
			"OnStart"
		)
		```
	]=]
	function Loader.SpawnAll(loadedModules: { [string]: any }, methodName: string)
		for name, mod in loadedModules do
			local method = mod[methodName]
			if type(method) == "function" then
				task.spawn(function()
					debug.setmemorycategory(name)
					method(mod)
				end)
			end
		end
	end
	
	return Loader
	
end
Modules["log"] = function(...)
	-- Log
	-- Stephen Leitnick
	-- April 20, 2021
	
	--[[
	
		IMPORTANT: Only make one logger per script/module
	
	
		Log.Level { Trace, Debug, Info, Warning, Error, Fatal }
		Log.TimeUnit { Milliseconds, Seconds, Minutes, Hours, Days, Weeks, Months, Years }
	
		Constructor:
	
			logger = Log.new()
	
	
		Log:
	
			Basic logging at levels:
	
				logger:AtTrace():Log("Hello from trace")
				logger:AtDebug():Log("Hello from debug")
				logger:AtInfo():Log("Hello from info")
				logger:AtWarning():Log("Hello from warn")
				logger:AtError():Log("Hello from error")
				logger:AtFatal():Log("Hello from fatal")
				logger:At(Log.Level.Warning):Log("Warning!")
	
	
			Log every 10 logs:
	
				logger:AtInfo():Every(10):Log("Log this only every 10 times")
	
	
			Log at most every 3 seconds:
	
				logger:AtInfo():AtMostEvery(3, Log.TimeUnit.Seconds):Log("Hello there, but not too often!")
	
	
			Wrap the Log in a function:
	
				local log = logger:AtDebug():Wrap()
				log("Hello")
	
	
		--------------------------------------------------------------------------------------------------------------
	
		LogConfig: Create a LogConfig ModuleScript anywhere in ReplicatedStorage. The configuration lets developers
		tune the lowest logging level based on various environment conditions. The LogConfig will be automatically
		required and used to set the log level.
	
		To set the default configuration for all environments, simply return the log level from the LogConfig:
	
			return "Info"
	
		To set a configuration that is different while in Studio:
	
			return {
				Studio = "Debug";
				Other = "Warning"; -- "Other" can be anything other than Studio (e.g. could be named "Default")
			}
	
		Fine-tune between server and client:
	
			return {
				Studio = {
					Server = "Info";
					Client = "Debug";
				};
				Other = "Warning";
			}
	
		Fine-tune based on PlaceIds:
	
			return {
				Studio = {
					Server = "Info";
					Client = "Debug";
				};
				Other = {
					PlaceIds = {123456, 234567}
					Server = "Severe";
					Client = "Warning";
				};
			}
	
		Fine-tune based on GameIds:
	
			return {
				Studio = {
					Server = "Info";
					Client = "Debug";
				};
				Other = {
					GameIds = {123456, 234567}
					Server = "Severe";
					Client = "Warning";
				};
			}
	
		Example of full-scale config with multiple environments:
	
			return {
				Studio = {
					Server = "Debug";
					Client = "Debug";
				};
				Dev = {
					PlaceIds = {1234567};
					Server = "Info";
					Client = "Info";
				};
				Prod = {
					PlaceIds = {2345678};
					Server = "Severe";
					Client = "Warning";
				};
				Default = "Info";
			}
	
	--]]
	
	local IS_STUDIO = game:GetService("RunService"):IsStudio()
	local IS_SERVER = game:GetService("RunService"):IsServer()
	
	local AnalyticsService = game:GetService("AnalyticsService")
	local HttpService = game:GetService("HttpService")
	local Players = game:GetService("Players")
	local AnalyticsLogLevel = Enum.AnalyticsLogLevel
	
	local player = (not IS_SERVER and Players.LocalPlayer or nil)
	
	local configModule = game:GetService("ReplicatedStorage"):FindFirstChild("LogConfig", true)
	local config = (configModule and require(configModule) or "Debug")
	
	local logLevel = nil
	local timeFunc = os.clock
	
	local logLevels = {
		Trace = AnalyticsLogLevel.Trace.Value,
		Debug = AnalyticsLogLevel.Debug.Value,
		Info = AnalyticsLogLevel.Information.Value,
		Warning = AnalyticsLogLevel.Warning.Value,
		Error = AnalyticsLogLevel.Error.Value,
		Fatal = AnalyticsLogLevel.Fatal.Value,
	}
	
	local timeUnits = {
		Milliseconds = 0,
		Seconds = 1,
		Minutes = 2,
		Hours = 3,
		Days = 4,
		Weeks = 5,
		Months = 6,
		Years = 7,
	}
	
	local function ToSeconds(n, timeUnit)
		if timeUnit == timeUnits.Milliseconds then
			return n / 1000
		elseif timeUnit == timeUnits.Seconds then
			return n
		elseif timeUnit == timeUnits.Minutes then
			return n * 60
		elseif timeUnit == timeUnits.Hours then
			return n * 3600
		elseif timeUnit == timeUnits.Days then
			return n * 86400
		elseif timeUnit == timeUnits.Weeks then
			return n * 604800
		elseif timeUnit == timeUnits.Months then
			return n * 2592000
		elseif timeUnit == timeUnits.Years then
			return n * 31536000
		else
			error("Unknown time unit", 2)
		end
	end
	
	local function GetPlayerFromCustomData(customData)
		if type(customData) == "table" then
			local id = (customData.Player or customData.PlayerId)
			if id then
				return Players:GetPlayerByUserId(id)
			end
		end
		return nil
	end
	
	local FireAnalyticsLogEvent
	if IS_STUDIO then
		FireAnalyticsLogEvent = function(_level, _message, _traceback, _customData) end
	else
		FireAnalyticsLogEvent = function(level, message, traceback, customData)
			local success, err = pcall(function()
				local plr = (player or GetPlayerFromCustomData(customData))
				AnalyticsService:FireLogEvent(plr, level, message, { stackTrace = traceback }, customData)
			end)
			if not success then
				warn(err)
			end
		end
	end
	
	local LogItem = {}
	LogItem.__index = LogItem
	
	function LogItem.new(log, levelName, traceback, key)
		local self = setmetatable({
			_log = log,
			_traceback = traceback,
			_levelName = levelName,
			_modifiers = {
				Throw = false,
			},
			_key = key,
		}, LogItem)
		return self
	end
	
	function LogItem:_shouldLog(stats)
		if self._modifiers.Every and not stats:_checkAndIncrementCount(self._modifiers.Every) then
			return false
		end
		if self._modifiers.AtMostEvery and not stats:_checkLastTimestamp(timeFunc(), self._modifiers.AtMostEvery) then
			return false
		end
		return true
	end
	
	function LogItem:Every(n)
		self._modifiers.Every = n
		return self
	end
	
	function LogItem:AtMostEvery(n, timeUnit)
		self._modifiers.AtMostEvery = ToSeconds(n, timeUnit)
		return self
	end
	
	function LogItem:Throw()
		self._modifiers.Throw = true
		return self
	end
	
	function LogItem:Log(message, customData)
		local stats = self._log:_getLogStats(self._key)
		if not self:_shouldLog(stats) then
			return
		end
		if type(message) == "function" then
			local msg, data = message()
			message = msg
			if data ~= nil then
				customData = data
			end
		elseif type(message) == "table" then
			message = HttpService:JSONEncode(message)
		end
		stats:_setTimestamp(timeFunc())
		local logMessage = ("%s: [%s] %s"):format(self._log._name, self._levelName, message)
		local logLevelNum = logLevels[self._levelName]
		FireAnalyticsLogEvent(logLevelNum, ("%s: %s"):format(self._log._name, message), self._traceback, customData)
		if self._modifiers.Throw then
			error(logMessage .. (customData and (" " .. HttpService:JSONEncode(customData)) or ""), 4)
		elseif logLevelNum < logLevels.Warning then
			print(logMessage, customData or "")
		else
			warn(logMessage, customData or "")
		end
	end
	
	function LogItem:Wrap()
		return function(...)
			self:Log(...)
		end
	end
	
	function LogItem:Assert(condition, ...)
		if condition then
			self:Throw():Log(...)
		end
	end
	
	local LogItemBlank = {}
	LogItemBlank.__index = LogItemBlank
	setmetatable(LogItemBlank, LogItem)
	
	function LogItemBlank.new(...)
		local self = setmetatable(LogItem.new(...), LogItemBlank)
		return self
	end
	
	function LogItemBlank:Log()
		-- Do nothing
	end
	
	local LogStats = {}
	LogStats.__index = LogStats
	
	function LogStats.new()
		local self = setmetatable({}, LogStats)
		self._invocationCount = 0
		self._lastTimestamp = 0
		return self
	end
	
	function LogStats:_checkAndIncrementCount(rateLimit)
		local check = ((self._invocationCount % rateLimit) == 0)
		self._invocationCount += 1
		return check
	end
	
	function LogStats:_checkLastTimestamp(now, intervalSeconds)
		return ((now - self._lastTimestamp) >= intervalSeconds)
	end
	
	function LogStats:_setTimestamp(now)
		self._lastTimestamp = now
	end
	
	--[=[
		@class Log
		@server
		Log class for logging to the AnalyticsService (e.g. PlayFab). The API
		is based off of Google's [Flogger](https://google.github.io/flogger/)
		fluent logging API.
	
		```lua
		local Log = require(somewhere.Log)
		local logger = Log.new()
	
		-- Log a simple message:
		logger:AtInfo():Log("Hello world!")
	
		-- Log only every 3 messages:
		for i = 1,20 do
			logger:AtInfo():Every(3):Log("Hi there!")
		end
	
		-- Log only every 1 second:
		for i = 1,100 do
			logger:AtInfo():AtMostEvery(3, Log.TimeUnit.Seconds):Log("Hello!")
			task.wait(0.1)
		end
	
		-- Wrap the above example into a function:
		local log = logger:AtInfo():AtMostEvery(3, Log.TimeUnit.Seconds):Wrap()
		for i = 1,100 do
			log("Hello!")
			task.wait(0.1)
		end
	
		-- Assertion:
		logger:Assert(typeof(32) == "number", "Somehow 32 is no longer a number")
		```
	
		------------
	
		### LogConfig
	
		A LogConfig ModuleScript is expected to exist somewhere within ReplicatedStorage
		as well. This ModuleScript defines the behavior for the logger. If not found,
		the logger will default to the Debug log level for all operations.
	
		For instance, this could be a script located at `ReplicatedStorage.MyGameConfig.LogConfig`. There
		just needs to be some `LogConfig`-named ModuleScript within ReplicatedStorage.
	
		Below are a few examples of possible LogConfig ModuleScripts:
	
		```lua
		-- Set "Info" as default log level for all environments:
		return "Info"
		```
	
		```lua
		-- To set a configuration that is different while in Studio:
		return {
			Studio = "Debug";
			Other = "Warning"; -- "Other" can be anything other than Studio (e.g. could be named "Default")
		}
		```
	
		```lua
		-- Fine-tune between server and client:
		return {
			Studio = {
				Server = "Info";
				Client = "Debug";
			};
			Other = "Warning";
		}
		```
	
		```lua
		-- Fine-tune based on PlaceIds:
		return {
			Studio = {
				Server = "Info";
				Client = "Debug";
			};
			Other = {
				PlaceIds = {123456, 234567}
				Server = "Severe";
				Client = "Warning";
			};
		}
		```
	
		```lua
		-- Fine-tune based on GameIds:
		return {
			Studio = {
				Server = "Info";
				Client = "Debug";
			};
			Other = {
				GameIds = {123456, 234567}
				Server = "Severe";
				Client = "Warning";
			};
		}
		```
	
		```lua
		-- Example of full-scale config with multiple environments:
		return {
			Studio = {
				Server = "Debug";
				Client = "Debug";
			};
			Dev = {
				PlaceIds = {1234567};
				Server = "Info";
				Client = "Info";
			};
			Prod = {
				PlaceIds = {2345678};
				Server = "Severe";
				Client = "Warning";
			};
			Default = "Info";
		}
		```
	]=]
	local Log = {}
	Log.__index = Log
	
	--[=[
		@within Log
		@interface LogItem
		.Log (message: any, customData: table?) -- Log the message
		.Every (n: number) -- Log only every `n` times
		.AtMostEvery (n: number, timeUnit: TimeUnit) -- Log only every `n` `TimeUnit`
		.Throw () -- Throw an error
		.Wrap () -- Returns a function that can be called which will log out the given arguments
		.Assert (condition: boolean, args: ...) -- Assert the condition
	]=]
	
	--[=[
		@within Log
		@interface TimeUnit
		.Milliseconds number
		.Seeconds number
		.Minutes number
		.Hours number
		.Days number
		.Weeks number
		.Months number
		.Years number
	]=]
	
	--[=[
		@within Log
		@interface Level
		.Trace number
		.Debug number
		.Info number
		.Warning number
		.Error number
		.Fatal number
	]=]
	
	--[=[
		@within Log
		@prop TimeUnit TimeUnit
		@readonly
	]=]
	
	--[=[
		@within Log
		@prop Level Level
		@readonly
	]=]
	
	Log.TimeUnit = timeUnits
	Log.Level = logLevels
	
	Log.LevelNames = {}
	for name, num in pairs(Log.Level) do
		Log.LevelNames[num] = name
	end
	
	--[=[
		@return Log
		Construct a new Log object.
	
		:::warning
		This should only be called once per script.
		:::
	]=]
	function Log.new()
		local self = setmetatable({}, Log)
		local name = debug.info(2, "s"):match("([^%.]-)$")
		self._name = name
		self._stats = {}
		return self
	end
	
	function Log:_getLogStats(key)
		local stats = self._stats[key]
		if not stats then
			stats = LogStats.new()
			self._stats[key] = stats
		end
		return stats
	end
	
	function Log:_at(level)
		local l, f = debug.info(3, "lf")
		local traceback = debug.traceback("Log", 3)
		local key = (tostring(l) .. tostring(f))
		if level < logLevel then
			return LogItemBlank.new(self, Log.LevelNames[level], traceback, key)
		else
			return LogItem.new(self, Log.LevelNames[level], traceback, key)
		end
	end
	
	--[=[
		@param level LogLevel
		@return LogItem
	]=]
	function Log:At(level)
		return self:_at(level)
	end
	
	--[=[
		@return LogItem
		Get a LogItem at the Trace log level.
	]=]
	function Log:AtTrace()
		return self:_at(Log.Level.Trace)
	end
	
	--[=[
		@return LogItem
		Get a LogItem at the Debug log level.
	]=]
	function Log:AtDebug()
		return self:_at(Log.Level.Debug)
	end
	
	--[=[
		@return LogItem
		Get a LogItem at the Info log level.
	]=]
	function Log:AtInfo()
		return self:_at(Log.Level.Info)
	end
	
	--[=[
		@return LogItem
		Get a LogItem at the Warning log level.
	]=]
	function Log:AtWarning()
		return self:_at(Log.Level.Warning)
	end
	
	--[=[
		@return LogItem
		Get a LogItem at the Error log level.
	]=]
	function Log:AtError()
		return self:_at(Log.Level.Error)
	end
	
	--[=[
		@return LogItem
		Get a LogItem at the Fatal log level.
	]=]
	function Log:AtFatal()
		return self:_at(Log.Level.Fatal)
	end
	
	--[=[
		@param condition boolean
		@param ... any
		Asserts the condition and then logs the following
		arguments at the Error level if the condition
		fails.
	]=]
	function Log:Assert(condition, ...)
		if not condition then
			self:_at(Log.Level.Error):Throw():Log(...)
		end
	end
	
	function Log:Destroy() end
	
	function Log:__tostring()
		return ("Log<%s>"):format(self._name)
	end
	
	-- Determine log level:
	do
		local function SetLogLevel(name)
			local n = name:lower()
			for levelName, level in pairs(Log.Level) do
				if levelName:lower() == n then
					if IS_STUDIO then
						local attr = (IS_SERVER and "LogLevel" or "LogLevelClient")
						local displayName = (n:sub(1, 1):upper() .. n:sub(2))
						if tostring(workspace:GetAttribute(attr) or "") ~= displayName then
							workspace:SetAttribute(attr, displayName)
						end
					end
					logLevel = level
					return
				end
			end
			error("Unknown log level: " .. tostring(name))
		end
		local configType = type(config)
		assert(
			configType == "table" or configType == "string",
			"LogConfig must return a table or a string; got " .. configType
		)
		if configType == "string" then
			SetLogLevel(config)
		else
			if IS_STUDIO and config.Studio then
				local studioConfigType = type(config.Studio)
				assert(
					studioConfigType == "table" or studioConfigType == "string",
					"LogConfig.Studio must be a table or a string; got " .. studioConfigType
				)
				if studioConfigType == "string" then
					-- Config for Studio:
					SetLogLevel(config.Studio)
				else
					-- Server/Client config for Studio:
					if IS_SERVER then
						local studioServerLevel = config.Studio.Server
						assert(
							type(studioServerLevel) == "string",
							"LogConfig.Studio.Server must be a string; got " .. type(studioServerLevel)
						)
						SetLogLevel(studioServerLevel)
					else
						local studioClientLevel = config.Studio.Client
						assert(
							type(studioClientLevel) == "string",
							"LogConfig.Studio.Client must be a string; got " .. type(studioClientLevel)
						)
						SetLogLevel(studioClientLevel)
					end
				end
			else
				local default = nil
				local numDefault = 0
				local set = false
				local setK = nil
				for k, specialConfig in pairs(config) do
					if k == "Studio" then
						continue
					end
					if type(specialConfig) == "string" then
						default = specialConfig
						numDefault += 1
					elseif type(specialConfig) == "table" then
						-- Check if config can be used if filtered by PlaceId or GameId:
						local canUse, fallthrough = false, false
						if type(specialConfig.PlaceId) == "number" then
							canUse = (specialConfig.PlaceId == game.PlaceId)
						elseif type(specialConfig.PlaceIds) == "table" then
							canUse = (table.find(specialConfig.PlaceIds, game.PlaceId) ~= nil)
						elseif type(specialConfig.GameId) == "number" then
							canUse = (specialConfig.GameId == game.GameId)
						elseif type(specialConfig.GameIds) == "table" then
							canUse = (table.find(specialConfig.GameIds, game.GameId) ~= nil)
						else
							canUse = true
							fallthrough = true
						end
						if not fallthrough then
							assert(
								not set,
								("More than one LogConfig mapping matched (%s and %s)"):format(setK or "", k or "")
							)
						end
						if canUse then
							if IS_SERVER then
								local serverLevel = specialConfig.Server
								assert(
									type(serverLevel) == "string",
									("LogConfig.%s.Server must be a string; got %s"):format(k, type(serverLevel))
								)
								SetLogLevel(serverLevel)
								set = true
								setK = k
							else
								local clientLevel = specialConfig.Client
								assert(
									type(clientLevel) == "string",
									("LogConfig.%s.Client must be a string; got %s"):format(k, type(clientLevel))
								)
								SetLogLevel(clientLevel)
								set = true
								setK = k
							end
						end
					else
						warn(("LogConfig.%s must be a table or a string; got %s"):format(k, typeof(specialConfig)))
					end
				end
				if numDefault > 1 then
					warn("Ambiguous default logging level")
				end
				if default and not set then
					SetLogLevel(default)
				end
			end
		end
		assert(type(logLevel) == "number", "LogLevel failed to be determined")
		if IS_STUDIO then
			local attr = (IS_SERVER and "LogLevel" or "LogLevelClient")
			workspace:GetAttributeChangedSignal(attr):Connect(function()
				SetLogLevel(workspace:GetAttribute(attr))
			end)
		end
	end
	
	return Log
	
end
Modules["option"] = function(...)
	-- Option
	-- Stephen Leitnick
	-- August 28, 2020
	
	--[[
	
		MatchTable {
			Some: (value: any) -> any
			None: () -> any
		}
	
		CONSTRUCTORS:
	
			Option.Some(anyNonNilValue): Option<any>
			Option.Wrap(anyValue): Option<any>
	
	
		STATIC FIELDS:
	
			Option.None: Option<None>
	
	
		STATIC METHODS:
	
			Option.Is(obj): boolean
	
	
		METHODS:
	
			opt:Match(): (matches: MatchTable) -> any
			opt:IsSome(): boolean
			opt:IsNone(): boolean
			opt:Unwrap(): any
			opt:Expect(errMsg: string): any
			opt:ExpectNone(errMsg: string): void
			opt:UnwrapOr(default: any): any
			opt:UnwrapOrElse(default: () -> any): any
			opt:And(opt2: Option<any>): Option<any>
			opt:AndThen(predicate: (unwrapped: any) -> Option<any>): Option<any>
			opt:Or(opt2: Option<any>): Option<any>
			opt:OrElse(orElseFunc: () -> Option<any>): Option<any>
			opt:XOr(opt2: Option<any>): Option<any>
			opt:Contains(value: any): boolean
	
		--------------------------------------------------------------------
	
		Options are useful for handling nil-value cases. Any time that an
		operation might return nil, it is useful to instead return an
		Option, which will indicate that the value might be nil, and should
		be explicitly checked before using the value. This will help
		prevent common bugs caused by nil values that can fail silently.
	
	
		Example:
	
		local result1 = Option.Some(32)
		local result2 = Option.Some(nil)
		local result3 = Option.Some("Hi")
		local result4 = Option.Some(nil)
		local result5 = Option.None
	
		-- Use 'Match' to match if the value is Some or None:
		result1:Match {
			Some = function(value) print(value) end;
			None = function() print("No value") end;
		}
	
		-- Raw check:
		if result2:IsSome() then
			local value = result2:Unwrap() -- Explicitly call Unwrap
			print("Value of result2:", value)
		end
	
		if result3:IsNone() then
			print("No result for result3")
		end
	
		-- Bad, will throw error bc result4 is none:
		local value = result4:Unwrap()
	
	--]]
	
	export type MatchTable<T> = {
		Some: (value: T) -> any,
		None: () -> any,
	}
	
	export type MatchFn<T> = (matches: MatchTable<T>) -> any
	
	export type DefaultFn<T> = () -> T
	
	export type AndThenFn<T> = (value: T) -> Option<T>
	
	export type OrElseFn<T> = () -> Option<T>
	
	export type Option<T> = typeof(setmetatable(
		{} :: {
			Match: (self: Option<T>) -> MatchFn<T>,
			IsSome: (self: Option<T>) -> boolean,
			IsNone: (self: Option<T>) -> boolean,
			Contains: (self: Option<T>, value: T) -> boolean,
			Unwrap: (self: Option<T>) -> T,
			Expect: (self: Option<T>, errMsg: string) -> T,
			ExpectNone: (self: Option<T>, errMsg: string) -> nil,
			UnwrapOr: (self: Option<T>, default: T) -> T,
			UnwrapOrElse: (self: Option<T>, defaultFn: DefaultFn<T>) -> T,
			And: (self: Option<T>, opt2: Option<T>) -> Option<T>,
			AndThen: (self: Option<T>, predicate: AndThenFn<T>) -> Option<T>,
			Or: (self: Option<T>, opt2: Option<T>) -> Option<T>,
			OrElse: (self: Option<T>, orElseFunc: OrElseFn<T>) -> Option<T>,
			XOr: (self: Option<T>, opt2: Option<T>) -> Option<T>,
		},
		{} :: {
			__index: Option<T>,
		}
	))
	
	local CLASSNAME = "Option"
	
	--[=[
		@class Option
	
		Represents an optional value in Lua. This is useful to avoid `nil` bugs, which can
		go silently undetected within code and cause hidden or hard-to-find bugs.
	]=]
	local Option = {}
	Option.__index = Option
	
	function Option._new(value)
		local self = setmetatable({
			ClassName = CLASSNAME,
			_v = value,
			_s = (value ~= nil),
		}, Option)
		return self
	end
	
	--[=[
		@param value T
		@return Option<T>
	
		Creates an Option instance with the given value. Throws an error
		if the given value is `nil`.
	]=]
	function Option.Some(value)
		assert(value ~= nil, "Option.Some() value cannot be nil")
		return Option._new(value)
	end
	
	--[=[
		@param value T
		@return Option<T> | Option<None>
	
		Safely wraps the given value as an option. If the
		value is `nil`, returns `Option.None`, otherwise
		returns `Option.Some(value)`.
	]=]
	function Option.Wrap(value)
		if value == nil then
			return Option.None
		else
			return Option.Some(value)
		end
	end
	
	--[=[
		@param obj any
		@return boolean
		Returns `true` if `obj` is an Option.
	]=]
	function Option.Is(obj)
		return type(obj) == "table" and getmetatable(obj) == Option
	end
	
	--[=[
		@param obj any
		Throws an error if `obj` is not an Option.
	]=]
	function Option.Assert(obj)
		assert(Option.Is(obj), "Result was not of type Option")
	end
	
	--[=[
		@param data table
		@return Option
		Deserializes the data into an Option. This data should have come from
		the `option:Serialize()` method.
	]=]
	function Option.Deserialize(data) -- type data = {ClassName: string, Value: any}
		assert(type(data) == "table" and data.ClassName == CLASSNAME, "Invalid data for deserializing Option")
		return data.Value == nil and Option.None or Option.Some(data.Value)
	end
	
	--[=[
		@return table
		Returns a serialized version of the option.
	]=]
	function Option:Serialize()
		return {
			ClassName = self.ClassName,
			Value = self._v,
		}
	end
	
	--[=[
		@param matches {Some: (value: any) -> any, None: () -> any}
		@return any
	
		Matches against the option.
	
		```lua
		local opt = Option.Some(32)
		opt:Match {
			Some = function(num) print("Number", num) end,
			None = function() print("No value") end,
		}
		```
	]=]
	function Option:Match(matches)
		local onSome = matches.Some
		local onNone = matches.None
		assert(type(onSome) == "function", "Missing 'Some' match")
		assert(type(onNone) == "function", "Missing 'None' match")
		if self:IsSome() then
			return onSome(self:Unwrap())
		else
			return onNone()
		end
	end
	
	--[=[
		@return boolean
		Returns `true` if the option has a value.
	]=]
	function Option:IsSome()
		return self._s
	end
	
	--[=[
		@return boolean
		Returns `true` if the option is None.
	]=]
	function Option:IsNone()
		return not self._s
	end
	
	--[=[
		@param msg string
		@return value: any
		Unwraps the value in the option, otherwise throws an error with `msg` as the error message.
		```lua
		local opt = Option.Some(10)
		print(opt:Expect("No number")) -> 10
		print(Option.None:Expect("No number")) -- Throws an error "No number"
		```
	]=]
	function Option:Expect(msg)
		assert(self:IsSome(), msg)
		return self._v
	end
	
	--[=[
		@param msg string
		Throws an error with `msg` as the error message if the value is _not_ None.
	]=]
	function Option:ExpectNone(msg)
		assert(self:IsNone(), msg)
	end
	
	--[=[
		@return value: any
		Returns the value in the option, or throws an error if the option is None.
	]=]
	function Option:Unwrap()
		return self:Expect("Cannot unwrap option of None type")
	end
	
	--[=[
		@param default any
		@return value: any
		If the option holds a value, returns the value. Otherwise, returns `default`.
	]=]
	function Option:UnwrapOr(default)
		if self:IsSome() then
			return self:Unwrap()
		else
			return default
		end
	end
	
	--[=[
		@param defaultFn () -> any
		@return value: any
		If the option holds a value, returns the value. Otherwise, returns the
		result of the `defaultFn` function.
	]=]
	function Option:UnwrapOrElse(defaultFn)
		if self:IsSome() then
			return self:Unwrap()
		else
			return defaultFn()
		end
	end
	
	--[=[
		@param optionB Option
		@return Option
		Returns `optionB` if the calling option has a value,
		otherwise returns None.
	
		```lua
		local optionA = Option.Some(32)
		local optionB = Option.Some(64)
		local opt = optionA:And(optionB)
		-- opt == optionB
	
		local optionA = Option.None
		local optionB = Option.Some(64)
		local opt = optionA:And(optionB)
		-- opt == Option.None
		```
	]=]
	function Option:And(optionB)
		if self:IsSome() then
			return optionB
		else
			return Option.None
		end
	end
	
	--[=[
		@param andThenFn (value: any) -> Option
		@return value: Option
		If the option holds a value, then the `andThenFn`
		function is called with the held value of the option,
		and then the resultant Option returned by the `andThenFn`
		is returned. Otherwise, None is returned.
	
		```lua
		local optA = Option.Some(32)
		local optB = optA:AndThen(function(num)
			return Option.Some(num * 2)
		end)
		print(optB:Expect("Expected number")) --> 64
		```
	]=]
	function Option:AndThen(andThenFn)
		if self:IsSome() then
			local result = andThenFn(self:Unwrap())
			Option.Assert(result)
			return result
		else
			return Option.None
		end
	end
	
	--[=[
		@param optionB Option
		@return Option
		If caller has a value, returns itself. Otherwise, returns `optionB`.
	]=]
	function Option:Or(optionB)
		if self:IsSome() then
			return self
		else
			return optionB
		end
	end
	
	--[=[
		@param orElseFn () -> Option
		@return Option
		If caller has a value, returns itself. Otherwise, returns the
		option generated by the `orElseFn` function.
	]=]
	function Option:OrElse(orElseFn)
		if self:IsSome() then
			return self
		else
			local result = orElseFn()
			Option.Assert(result)
			return result
		end
	end
	
	--[=[
		@param optionB Option
		@return Option
		If both `self` and `optionB` have values _or_ both don't have a value,
		then this returns None. Otherwise, it returns the option that does have
		a value.
	]=]
	function Option:XOr(optionB)
		local someOptA = self:IsSome()
		local someOptB = optionB:IsSome()
		if someOptA == someOptB then
			return Option.None
		elseif someOptA then
			return self
		else
			return optionB
		end
	end
	
	--[=[
		@param predicate (value: any) -> boolean
		@return Option
		Returns `self` if this option has a value and the predicate returns `true.
		Otherwise, returns None.
	]=]
	function Option:Filter(predicate)
		if self:IsNone() or not predicate(self._v) then
			return Option.None
		else
			return self
		end
	end
	
	--[=[
		@param value any
		@return boolean
		Returns `true` if this option contains `value`.
	]=]
	function Option:Contains(value)
		return self:IsSome() and self._v == value
	end
	
	--[=[
		@return string
		Metamethod to transform the option into a string.
		```lua
		local optA = Option.Some(64)
		local optB = Option.None
		print(optA) --> Option<number>
		print(optB) --> Option<None>
		```
	]=]
	function Option:__tostring()
		if self:IsSome() then
			return ("Option<" .. typeof(self._v) .. ">")
		else
			return "Option<None>"
		end
	end
	
	--[=[
		@return boolean
		@param opt Option
		Metamethod to check equality between two options. Returns `true` if both
		options hold the same value _or_ both options are None.
		```lua
		local o1 = Option.Some(32)
		local o2 = Option.Some(32)
		local o3 = Option.Some(64)
		local o4 = Option.None
		local o5 = Option.None
	
		print(o1 == o2) --> true
		print(o1 == o3) --> false
		print(o1 == o4) --> false
		print(o4 == o5) --> true
		```
	]=]
	function Option:__eq(opt)
		if Option.Is(opt) then
			if self:IsSome() and opt:IsSome() then
				return (self:Unwrap() == opt:Unwrap())
			elseif self:IsNone() and opt:IsNone() then
				return true
			end
		end
		return false
	end
	
	--[=[
		@prop None Option<None>
		@within Option
		Represents no value.
	]=]
	Option.None = Option._new()
	
	return (Option :: any) :: {
		Some: <T>(value: T) -> Option<T>,
		Wrap: <T>(value: T?) -> Option<T>,
	
		Is: (obj: any) -> boolean,
	
		None: Option<any>,
	}
	
end
Modules["pid"] = function(...)
	--!native
	
	export type PID = {
		Reset: (self: PID) -> (),
		Calculate: (self: PID, setpoint: number, input: number, deltaTime: number) -> number,
		Debug: (self: PID, name: string, parent: Instance?) -> (),
		Destroy: (self: PID) -> (),
	}
	
	--[=[
		@class PID
		The PID class simulates a [PID controller](https://en.wikipedia.org/wiki/PID_controller). PID is an acronym
		for _proportional, integral, derivative_. PIDs are input feedback loops that try to reach a specific
		goal by measuring the difference between the input and the desired value, and then returning a new
		desired input.
	
		A common example is a car's cruise control, which would give a PID the current speed
		and the desired speed, and the PID controller would return the desired throttle input to reach the
		desired speed.
	]=]
	local PID = {}
	PID.__index = PID
	
	--[=[
		@param min number -- Minimum value the PID can output
		@param max number -- Maximum value the PID can output
		@param kp number -- Proportional gain coefficient (P)
		@param ki number -- Integral gain coefficient (I)
		@param kd number -- Derivative gain coefficient (D)
		@return PID
	
		Constructs a new PID.
	
		```lua
		local pid = PID.new(0, 1, 0.1, 0, 0)
		```
	]=]
	function PID.new(min: number, max: number, kp: number, ki: number, kd: number): PID
		local self = setmetatable({}, PID)
		self._min = min
		self._max = max
		self._kp = kp
		self._ki = ki
		self._kd = kd
		self._lastError = 0 -- Store the last error for derivative calculation
		self._integralSum = 0 -- Store the sum of errors for integral calculation
		return self
	end
	
	--[=[
		Resets the PID to a zero start state.
	]=]
	function PID:Reset()
		self._lastError = 0
		self._integralSum = 0
	end
	
	--[=[
		@param setpoint number	-- The desired point to reach
		@param processVariable number	-- The measured value of the system to compare against the setpoint
		@param deltaTime number	-- Delta time. This is the time between each PID calculation
		@return output: number
	
		Calculates the new output based on the setpoint and input. For example,
		if the PID was being used for a car's throttle control where the throttle
		can be in the range of [0, 1], then the PID calculation might look like
		the following:
		```lua
		local cruisePID = PID.new(0, 1, ...)
		local desiredSpeed = 50
	
		RunService.Heartbeat:Connect(function(dt)
			local throttle = cruisePID:Calculate(desiredSpeed, car.CurrentSpeed, dt)
			car:SetThrottle(throttle)
		end)
		```
	]=]
	function PID:Calculate(setpoint: number, processVariable: number, deltaTime: number): number
		-- Calculate the error e(t) = SP - PV(t)
		local err = setpoint - processVariable
	
		-- Proportional term
		local pOut = self._kp * err
	
		-- Integral term
		self._integralSum = self._integralSum + err * deltaTime
		local iOut = self._ki * self._integralSum
	
		-- Derivative term
		local derivative = (err - self._lastError) / deltaTime
		local dOut = self._kd * derivative
	
		-- Combine terms
		local output = pOut + iOut + dOut
	
		-- Clamp output to min/max
		output = math.clamp(output, self._min, self._max)
	
		-- Save the current error for the next derivative calculation
		self._lastError = err
	
		return output
	end
	
	--[=[
		@param name string -- Folder name
		@param parent Instance? -- Folder parent
	
		Creates a folder that contains attributes that can be used to
		tune the PID during runtime within the explorer.
	
		:::info Studio Only
		This will only create the folder in Studio. In a real game server,
		this function will do nothing.
		:::
	]=]
	function PID:Debug(name: string, parent: Instance?)
		if not game:GetService("RunService"):IsStudio() then
			return
		end
	
		if self._debug then
			return
		end
	
		local folder = Instance.new("Folder")
		folder.Name = name
		folder:AddTag("PIDDebug")
	
		local function Bind(attrName, propName)
			folder:SetAttribute(attrName, self[propName])
			folder:GetAttributeChangedSignal(attrName):Connect(function()
				self[propName] = folder:GetAttribute(attrName)
				self:Reset()
			end)
		end
	
		folder:SetAttribute("MinMax", NumberRange.new(self._min, self._max))
		folder:GetAttributeChangedSignal("MinMax"):Connect(function()
			local minMax = folder:GetAttribute("MinMax") :: NumberRange
			self._min = minMax.Min
			self._max = minMax.Max
			self:Reset()
		end)
	
		Bind("kP", "_kp")
		Bind("kI", "_ki")
		Bind("kD", "_kd")
	
		folder:SetAttribute("Output", self._min)
	
		local lastOutput = 0
		self.Calculate = function(s, sp, pv, ...)
			lastOutput = PID.Calculate(s, sp, pv, ...)
			folder:SetAttribute("Output", lastOutput)
			return lastOutput
		end
	
		local delayThread: thread? = nil
		folder:SetAttribute("ShowDebugger", false)
		folder:GetAttributeChangedSignal("ShowDebugger"):Connect(function()
			if delayThread then
				task.cancel(delayThread)
			end
	
			local showDebugger = folder:GetAttribute("ShowDebugger")
	
			if showDebugger then
				delayThread = task.delay(0.1, function()
					delayThread = nil
					if folder:GetAttribute("ShowDebugger") then
						folder:SetAttribute("ShowDebugger", false)
						warn("Install the PID Debug plugin: https://create.roblox.com/store/asset/16279661108/PID-Debug")
					end
				end)
			end
		end)
	
		folder.Parent = parent or workspace
		self._debug = folder
	end
	
	--[=[
		Destroys the PID. This is only necessary if calling `PID:Debug`.
	]=]
	function PID:Destroy()
		if self._debug then
			self._debug:Destroy()
			self._debug = nil
		end
	end
	
	return {
		new = PID.new,
	}
	
end
Modules["quaternion"] = function(...)
	--!strict
	
	--[[
		Algorithmic credit: https://www.euclideanspace.com/maths/algebra/realNormedAlgebra/quaternions/index.htm
	]]
	
	--[=[
		@within Quaternion
		@interface Quaternion
		.X number
		.Y number
		.Z number
		.W number
	
		Similar to Vector3s, Quaternions are immutable. You cannot manually set the individual properties
		of a Quaternion. Instead, a new Quaternion must first be constructed.
	]=]
	export type Quaternion = {
		X: number,
		Y: number,
		Z: number,
		W: number,
	
		Dot: (self: Quaternion, other: Quaternion) -> number,
		Slerp: (self: Quaternion, other: Quaternion, alpha: number) -> Quaternion,
		Angle: (self: Quaternion, other: Quaternion) -> number,
		RotateTowards: (self: Quaternion, other: Quaternion, maxRadiansDelta: number) -> Quaternion,
		ToCFrame: (self: Quaternion, position: Vector3?) -> CFrame,
		ToEulerAngles: (self: Quaternion) -> Vector3,
		ToAxisAngle: (self: Quaternion) -> (Vector3, number),
		Inverse: (self: Quaternion) -> Quaternion,
		Conjugate: (self: Quaternion) -> Quaternion,
		Normalize: (self: Quaternion) -> Quaternion,
		Magnitude: (self: Quaternion) -> number,
		SqrMagnitude: (self: Quaternion) -> number,
	}
	
	local EPSILON = 1e-5
	
	--[=[
		@class Quaternion
		Represents a Quaternion. Quaternions are 4D structs that represent rotations
		in 3D space. Quaternions are often used in 3D graphics to avoid the ambiguity
		that comes with Euler angles (e.g. gimbal lock).
	
		Roblox represents the transformation of an object via CFrame values, which are
		matrices that hold positional and rotational information. Quaternions can be converted
		to and from CFrame values through the `ToCFrame` method and `cframe` constructor.
	]=]
	local Quaternion = {}
	Quaternion.__index = Quaternion
	
	--[=[
		Constructs a Quaternion.
	
		:::caution
		The `new` constructor assumes the given arguments represent a proper Quaternion. This
		constructor should only be used if you really know what you're doing.
		:::
	]=]
	function Quaternion.new(x: number, y: number, z: number, w: number): Quaternion
		local self = setmetatable({
			X = x,
			Y = y,
			Z = z,
			W = w,
		}, Quaternion) :: any
	
		table.freeze(self)
	
		return self
	end
	
	--[=[
		Constructs a Quaternion from Euler angles (radians).
	
		```lua
		-- Quaternion rotated 45 degrees on the Y axis:
		local quat = Quaternion.euler(0, math.rad(45), 0)
		```
	]=]
	function Quaternion.euler(x: number, y: number, z: number): Quaternion
		local cx = math.cos(x * 0.5)
		local cy = math.cos(y * 0.5)
		local cz = math.cos(z * 0.5)
		local sx = math.sin(x * 0.5)
		local sy = math.sin(y * 0.5)
		local sz = math.sin(z * 0.5)
	
		return Quaternion.new(
			cx * sy * sz + cy * cz * sx,
			cx * cz * sy - cy * sx * sz,
			cx * cy * sz - cz * sx * sy,
			sx * sy * sz + cx * cy * cz
		)
	end
	
	--[=[
		Constructs a Quaternion representing a rotation of `angle` radians around `axis`.
	
		```lua
		-- Quaternion rotated 45 degrees on the Y axis:
		local quat = Quaternion.axisAngle(Vector3.yAxis, math.rad(45))
		```
	]=]
	function Quaternion.axisAngle(axis: Vector3, angle: number): Quaternion
		local halfAngle = angle / 2
		local sin = math.sin(halfAngle)
	
		return Quaternion.new(sin * axis.X, sin * axis.Y, sin * axis.Z, math.cos(halfAngle))
	end
	
	--[=[
		Constructs a Quaternion representing a rotation facing `forward` direction, where
		`upwards` represents the upwards direction (this defaults to `Vector3.yAxis`).
	
		```lua
		-- Create a quaternion facing the same direction as the camera:
		local camCf = workspace.CurrentCamera.CFrame
		local quat = Quaternion.lookRotation(camCf.LookVector, camCf.UpVector)
		```
	]=]
	function Quaternion.lookRotation(forward: Vector3, upwards: Vector3?): Quaternion
		local up = if upwards == nil then Vector3.yAxis else upwards.Unit
		forward = forward.Unit
	
		local v1 = forward
		local v2 = up:Cross(v1)
		local v3 = v1:Cross(v2)
	
		local m00 = v2.X
		local m01 = v2.Y
		local m02 = v2.Z
		local m10 = v3.X
		local m11 = v3.Y
		local m12 = v3.Z
		local m20 = v1.X
		local m21 = v1.Y
		local m22 = v1.Z
	
		local n8 = m00 + m11 + m22
	
		if n8 > 0 then
			local n = math.sqrt(n8 + 1)
	
			return Quaternion.new((m12 - m21) * n, (m20 - m02) * n, (m01 - m10) * n, n * 0.5)
		end
	
		if m00 >= m11 and m00 >= m22 then
			local n7 = math.sqrt(((1 + m00) - m11) - m22)
			local n4 = 0.5 / n7
	
			return Quaternion.new(0.5 * n7, (m01 + m10) * n4, (m02 + m20) * n4, (m12 - m21) * n4)
		end
	
		if m11 > m22 then
			local n6 = math.sqrt(((1 + m11) - m00) - m22)
			local n3 = 0.5 / n6
	
			return Quaternion.new((m10 + m01) * n3, 0.5 * n6, (m21 + m12) * n3, (m20 - m02) * n3)
		end
	
		local n5 = math.sqrt(((1 + m22) - m00) - m11)
		local n2 = 0.5 / n5
	
		return Quaternion.new((m20 + m02) * n2, (m21 + m12) * n2, 0.5 * n5, (m01 - m10) * n2)
	end
	
	--[=[
		Constructs a Quaternion from the rotation components of the given `cframe`.
	
		This method ortho-normalizes the CFrame value, so there is no need to do this yourself
		before calling the function.
	
		```lua
		-- Create a Quaternion representing the rotational CFrame of a part:
		local quat = Quaternion.cframe(somePart.CFrame)
		```
	]=]
	function Quaternion.cframe(cframe: CFrame): Quaternion
		local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cframe:Orthonormalize():GetComponents()
	
		local x, y, z, w
	
		local trace = m00 + m11 + m22
		if trace > 0 then
			local s = math.sqrt(trace + 1) * 2
			x = (m21 - m12) / s
			y = (m02 - m20) / s
			z = (m10 - m01) / s
			w = 0.25 * s
		elseif m00 > m11 and m00 > m22 then
			local s = math.sqrt(1 + m00 - m11 - m22) * 2
			x = 0.25 * s
			y = (m01 + m10) / s
			z = (m02 + m20) / s
			w = (m21 - m12) / s
		elseif m11 > m22 then
			local s = math.sqrt(1 + m11 - m00 - m22) * 2
			x = (m01 + m10) / s
			y = 0.25 * s
			z = (m12 + m21) / s
			w = (m02 - m20) / s
		else
			local s = math.sqrt(1 + m22 - m00 - m11) * 2
			x = (m02 + m20) / s
			y = (m12 + m21) / s
			z = 0.25 * s
			w = (m10 - m01) / s
		end
	
		return Quaternion.new(x, y, z, w)
	end
	
	--[=[
		@method Dot
		@within Quaternion
		@param other Quaternion
		@return number
		
		Calculates the dot product between the two Quaternions.
	
		```lua
		local dot = quatA:Dot(quatB)
		```
	]=]
	function Quaternion.Dot(self: Quaternion, other: Quaternion): number
		return self.X * other.X + self.Y * other.Y + self.Z * other.Z + self.W * other.W
	end
	
	--[=[
		@method Slerp
		@within Quaternion
		@param other Quaternion
		@param t number
		@return Quaternion
	
		Calculates a spherical interpolation between the two Quaternions. Parameter `t` represents
		the percentage between the two rotations, from a range of `[0, 1]`.
	
		Spherical interpolation is great for smoothing or animating between quaternions.
	
		```lua
		local midWay = quatA:Slerp(quatB, 0.5)
		```
	]=]
	function Quaternion.Slerp(a: Quaternion, b: Quaternion, t: number): Quaternion
		local cosOmega = a:Dot(b)
		local flip = false
	
		if cosOmega < 0 then
			flip = true
			cosOmega = -cosOmega
		end
	
		local s1, s2
	
		if cosOmega > (1 - EPSILON) then
			s1 = 1 - t
			s2 = if flip then -t else t
		else
			local omega = math.acos(cosOmega)
			local invSinOmega = 1 / math.sin(omega)
	
			s1 = math.sin((1 - t) * omega) * invSinOmega
			s2 = if flip then -math.sin(t * omega) * invSinOmega else math.sin(t * omega) * invSinOmega
		end
	
		return Quaternion.new(s1 * a.X + s2 * b.X, s1 * a.Y + s2 * b.Y, s1 * a.Z + s2 * b.Z, s1 * a.W + s2 * b.W)
	end
	
	--[=[
		@method Angle
		@within Quaternion
		@param other Quaternion
		@return number
	
		Calculates the angle (radians) between the two Quaternions.
	
		```lua
		local angle = quatA:Angle(quatB)
		```
	]=]
	function Quaternion.Angle(self: Quaternion, other: Quaternion): number
		local dot = math.min(math.abs(self:Dot(other)), 1)
		local angle = if dot > (1 - EPSILON) then 0 else math.acos(dot) * 2
	
		return angle
	end
	
	--[=[
		@method RotateTowards
		@within Quaternion
		@param other Quaternion
		@param maxRadiansDelta number
		@return Quaternion
	
		Constructs a new Quaternion that rotates from this Quaternion to the `other` quaternion, with a maximum
		rotation of `maxRadiansDelta`. Internally, this calls `Slerp`, but limits the movement to `maxRadiansDelta`.
	
		```lua
		-- Rotate from quatA to quatB, but only by 10 degrees:
		local q = quatA:RotateTowards(quatB, math.rad(10))
		```
	]=]
	function Quaternion.RotateTowards(self: Quaternion, other: Quaternion, maxRadiansDelta: number): Quaternion
		local angle = self:Angle(other)
	
		if angle == 0 then
			return self
		end
	
		local alpha = maxRadiansDelta / angle
	
		return self:Slerp(other, alpha)
	end
	
	--[=[
		@method ToCFrame
		@within Quaternion
		@param position Vector3?
		@return CFrame
	
		Constructs a CFrame value representing the Quaternion. An optional `position` Vector can be given to
		represent the position of the CFrame in 3D space. This defaults to `Vector3.zero`.
	
		```lua
		-- Construct a CFrame from the quaternion, where the position will be at the origin point:
		local cf = quat:ToCFrame()
	
		-- Construct a CFrame with a given position:
		local cf = quat:ToCFrame(someVector3)
	
		-- e.g., set a part's CFrame:
		local part = workspace.Part
		local quat = Quaternion.axisAngle(Vector3.yAxis, math.rad(45))
		local cframe = quat:ToCFrame(part.Position) -- Construct CFrame with a positional component
		part.CFrame = cframe
		```
	]=]
	function Quaternion.ToCFrame(self: Quaternion, position: Vector3?): CFrame
		local pos = if position == nil then Vector3.zero else position
	
		return CFrame.new(pos.X, pos.Y, pos.Z, self.X, self.Y, self.Z, self.W)
	end
	
	--[=[
		@method ToEulerAngles
		@within Quaternion
		@return Vector3
	
		Calculates the Euler angles (radians) that represent the Quaternion.
	
		```lua
		local euler = quat:ToEulerAngles()
		print(euler.X, euler.Y, euler.Z)
		```
	]=]
	function Quaternion.ToEulerAngles(self: Quaternion): Vector3
		local test = self.X * self.Y + self.Z * self.W
		if test > 0.49999 then
			return Vector3.new(0, 2 * math.atan2(self.X, self.W), math.pi / 2)
		elseif test < -0.49999 then
			return Vector3.new(0, -2 * math.atan2(self.X, self.W), -math.pi / 2)
		end
	
		local sqx = self.X * self.X
		local sqy = self.Y * self.Y
		local sqz = self.Z * self.Z
	
		return Vector3.new(
			math.atan2(2 * self.X * self.W - 2 * self.Y * self.Z, 1 - 2 * sqx - 2 * sqz),
			math.atan2(2 * self.Y * self.W - 2 * self.X * self.Z, 1 - 2 * sqy - 2 * sqz),
			math.asin(2 * test)
		)
	end
	
	--[=[
		@method ToAxisAngle
		@within Quaternion
		@return (Vector3, number)
	
		Calculates the axis and angle representing the Quaternion.
	
		```lua
		local axis, angle = quat:ToAxisAngle()
		```
	]=]
	function Quaternion.ToAxisAngle(self: Quaternion): (Vector3, number)
		local scale = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	
		if math.abs(scale) < EPSILON or self.W > 1 or self.W < -1 then
			return Vector3.yAxis, 0
		end
	
		local invScale = 1 / scale
	
		local axis = Vector3.new(self.X * invScale, self.Y * invScale, self.Z * invScale)
		local angle = 2 * math.acos(self.W)
	
		return axis, angle
	end
	
	--[=[
		@method Inverse
		@within Quaternion
		@return Quaternion
	
		Returns the inverse of the Quaternion.
	
		```lua
		local quatInverse = quat:Inverse()
		```
	]=]
	function Quaternion.Inverse(self: Quaternion): Quaternion
		local dot = self:Dot(self)
		local invNormal = 1 / dot
		return Quaternion.new(-self.X * invNormal, -self.Y * invNormal, -self.Z * invNormal, self.W * invNormal)
	end
	
	--[=[
		@method Conjugate
		@within Quaternion
		@return Quaternion
	
		Returns the conjugate of the Quaternion. This is equal to `Quaternion.new(-X, -Y, -Z, W)`.
	
		```lua
		local quatConjugate = quat:Conjugate()
		```
	]=]
	function Quaternion.Conjugate(self: Quaternion): Quaternion
		return Quaternion.new(-self.X, -self.Y, -self.Z, self.W)
	end
	
	--[=[
		@method Normalize
		@within Quaternion
		@return Quaternion
	
		Returns the normalized representation of the Quaternion.
	
		```lua
		local quatNormalized = quat:Normalize()
		```
	]=]
	function Quaternion.Normalize(self: Quaternion): Quaternion
		local magnitude = self:Magnitude()
	
		if magnitude < EPSILON then
			return Quaternion.identity
		end
	
		return Quaternion.new(self.X / magnitude, self.Y / magnitude, self.Z / magnitude, self.W / magnitude)
	end
	
	--[=[
		@method Magnitude
		@within Quaternion
		@return number
	
		Calculates the magnitude of the Quaternion.
	
		```lua
		local magnitude = quat:Magnitude()
		```
	]=]
	function Quaternion.Magnitude(self: Quaternion): number
		return math.sqrt(self:Dot(self))
	end
	
	--[=[
		@method SqrMagnitude
		@within Quaternion
		@return number
	
		Calculates the square magnitude of the Quaternion.
	
		```lua
		local squareMagnitude = quat:Magnitude()
		```
	]=]
	function Quaternion.SqrMagnitude(self: Quaternion): number
		return self:Dot(self)
	end
	
	function Quaternion._MulVector3(self: Quaternion, other: Vector3): Vector3
		local x = self.X * 2
		local y = self.Y * 2
		local z = self.Z * 2
	
		local xx = self.X * x
		local yy = self.Y * y
		local zz = self.Z * z
		local xy = self.X * y
		local xz = self.X * z
		local yz = self.Y * z
		local wx = self.W * x
		local wy = self.W * y
		local wz = self.W * z
	
		return Vector3.new(
			(1 - (yy + zz)) * other.X + (xy - wz) * other.Y + (xz + wy) * other.Z,
			(xy + wz) * other.X + (1 - (xx + zz)) * other.Y + (yz - wx) * other.Z,
			(xz - wy) * other.X + (yz + wx) * other.Y + (1 - (xx + yy)) * other.Z
		)
	end
	
	function Quaternion._MulQuaternion(self: Quaternion, other: Quaternion): Quaternion
		return Quaternion.new(
			self.W * other.X + self.X * other.W + self.Y * other.Z - self.Z * other.Y,
			self.W * other.Y + self.Y * other.W + self.Z * other.X - self.X * other.Z,
			self.W * other.Z + self.Z * other.W + self.X * other.Y - self.Y * other.X,
			self.W * other.W - self.X * other.X - self.Y * other.Y - self.Z * other.Z
		)
	end
	
	--[=[
		Multiplication metamethod. A Quaternion can be multiplied with another Quaternion or
		a Vector3.
	
		```lua
		local quat = quatA * quatB
		local vec = quatA * vecA
		```
	]=]
	function Quaternion.__mul(self: Quaternion, other: Quaternion | Vector3): Quaternion | Vector3
		local t = typeof(other)
		if t == "Vector3" then
			return Quaternion._MulVector3(self, other :: any)
		elseif t == "table" and getmetatable(other :: any) == Quaternion then
			return Quaternion._MulQuaternion(self, (other :: any) :: Quaternion)
		else
			error(`cannot multiply quaternion with type {t}`, 2)
		end
	end
	
	function Quaternion.__unm(self: Quaternion): Quaternion
		return Quaternion.new(-self.X, -self.Y, -self.Z, -self.W)
	end
	
	function Quaternion.__eq(self: Quaternion, other: Quaternion): boolean
		return self.X == other.X and self.Y == other.Y and self.Z == other.Z and self.W == other.W
	end
	
	function Quaternion.__tostring(self: Quaternion): string
		return `{self.X}, {self.Y}, {self.Z}, {self.W}`
	end
	
	-- Kind of support roblox-ts multiplication (not really, but follows the same pattern):
	Quaternion.mul = Quaternion.__mul
	
	--[=[
		@prop identity Quaternion
		@readonly
		@within Quaternion
	
		Identity Quaternion. Equal to `Quaternion.new(0, 0, 0, 1)`.
	]=]
	Quaternion.identity = Quaternion.new(0, 0, 0, 1)
	
	return {
		new = Quaternion.new,
		euler = Quaternion.euler,
		axisAngle = Quaternion.axisAngle,
		lookRotation = Quaternion.lookRotation,
		cframe = Quaternion.cframe,
	
		identity = Quaternion.identity,
	}
	
end
Modules["query"] = function(...)
	--!strict
	
	--[=[
		@class Query
	
		Adds helpful functions that wrap
		[`Instance:QueryDescendants()`](https://create.roblox.com/docs/reference/engine/classes/Instance#QueryDescendants).
	]=]
	
	local Query = {}
	
	--[=[
		@within Query
	
		Equivalent to [`parent:QueryDescendants(selector)`](https://create.roblox.com/docs/reference/engine/classes/Instance#QueryDescendants).
	]=]
	function Query.all(parent: Instance, selector: string): { Instance }
		return parent:QueryDescendants(selector)
	end
	
	--[=[
		@within Query
	
		Returns the query result, filtered by the `filter` function. Ideally, most of
		the filtering should be done with the selector itself. However, if the selector
		is not enough, this function can be used to further filter the results.
	
		```lua
		local buttons = Query.filter(workspace, ".Button", function(instance)
			return instance.Transparency > 0.25
		end)
		```
	]=]
	function Query.filter(parent: Instance, selector: string, filter: (Instance) -> boolean): { Instance }
		local instances = parent:QueryDescendants(selector)
		for i = #instances, 1, -1 do
			if not filter(instances[i]) then
				table.remove(instances, i)
			end
		end
		return instances
	end
	
	--[=[
		@within Query
	
		Returns the query result mapped by the `map` function.
	
		```lua
		local Button = {}
	
		function Button.new(btn: BasePart)
			...
		end
	
		----
	
		local buttons = Query.map(workspace, ".Button", function(instance)
			return Button.new(instance)
		end)
		```
	]=]
	function Query.map<T>(parent: Instance, selector: string, map: (Instance) -> T): { T }
		local instances = parent:QueryDescendants(selector)
		local mapped = table.create(#instances)
		for i, instance in instances do
			mapped[i] = map(instance)
		end
		return mapped
	end
	
	--[=[
		@within Query
	
		Returns the first item from the query. Might be `nil` if the query returns
		nothing.
	
		This is equivalent to `parent:QueryDescendants(selector)[1]`.
	
		```lua
		-- Find an instance tagged with 'Tycoon' that has
		-- the OwnerId attribute matching the player's UserId:
		local tycoon = Query.first(workspace, `.Tycoon[$OwnerId = {player.UserId}]`)
	
		if tycoon then
			...
		end
		```
	]=]
	function Query.first(parent: Instance, selector: string): Instance?
		return parent:QueryDescendants(selector)[1]
	end
	
	--[=[
		@within Query
	
		Asserts that the query returns exactly one instance. The instance is returned.
		This is useful when attempting to find an exact match of an instance that
		must exist.
	
		If the result returns zero or more than one result, an error is thrown.
	
		```lua
		-- Find a SpawnLocation that has the MainSpawn attribute set to true:
		local spawnPoint = Query.one(workspace, "SpawnLocation[$MainSpawn = true]")
		```
	]=]
	function Query.one(parent: Instance, selector: string): Instance
		local instances = parent:QueryDescendants(selector)
		if #instances ~= 1 then
			error(`expected 1 instance from query; got {#instances} instances (selector: {selector})`, 2)
		end
	
		return instances[1]
	end
	
	return Query
	
end
Modules["sequent"] = function(...)
	export type Sequent<T> = {
		Fire: (self: Sequent<T>, T) -> (),
		Connect: (self: Sequent<T>, callback: (SequentEvent<T>) -> ()) -> SequentConnection,
		Once: (self: Sequent<T>, callback: (SequentEvent<T>) -> ()) -> SequentConnection,
		Cancel: (self: Sequent<T>) -> (),
		Destroy: (self: Sequent<T>) -> (),
	}
	
	--[=[
		@interface SequentConnection
		@within Sequent
		.Connected boolean
		.Disconnect (self: SequentConnection) -> ()
	
		```lua
		print(sequent.Connected)
		sequent:Disconnect()
		```
	]=]
	export type SequentConnection = {
		Connected: boolean,
		Disconnect: (self: SequentConnection) -> (),
	}
	
	--[=[
		@interface SequentEvent<T>
		@within Sequent
		.Value T
		.Cancellable boolean
		.Cancel (self: SequentEvent<T>) -> ()
	
		Events are passed to connected callbacks when sequents are fired. Events
		can be cancelled as well, which prevents the event from propagating to
		other connected callbacks during the same firing. This can be used to
		sink events if desired.
	
		```lua
		sequent:Connect(function(event)
			print(event.Value)
			event:Cancel()
		end, 0)
		```
	]=]
	export type SequentEvent<T> = {
		Value: T,
		Cancellable: boolean,
		Cancel: (self: SequentEvent<T>) -> (),
	}
	
	type InternalSequentConnection = SequentConnection & {
		_priority: number,
		_sequent: Sequent<unknown>,
	}
	
	-----------------------------------------------------------------------------
	-- Connection
	local SequentConnection = {}
	SequentConnection.__index = SequentConnection
	
	function SequentConnection:Disconnect()
		self._sequent:_disconnect(self)
	end
	
	-----------------------------------------------------------------------------
	-- Sequent
	
	--[=[
		@interface Priority
		@within Sequent
		.Highest math.huge
		.High 1000
		.Normal 0
		.Low -1000
		.Lowest -math.huge
	
		```lua
		sequent:Connect(fn, Sequent.Priority.Highest)
		```
	]=]
	local Priority = {
		Highest = math.huge,
		High = 1000,
		Normal = 0,
		Low = -1000,
		Lowest = -math.huge,
	}
	
	--[=[
		@class Sequent
	
		Sequent is a signal-like structure that executes connections in a serial nature. Each
		connection must fully complete before the next is run. Connections can be prioritized
		and cancelled.
	
		```lua
		local sequent = Sequent.new()
	
		sequent:Connect(
			function(event)
				print("Got value", event.Value)
				event:Cancel()
			end,
			Sequent.Priority.Highest,
		)
	
		sequent:Connect(
			function(event)
				print("This won't print!")
			end,
			Sequent.Priority.Lowest,
		)
	
		sequent:Fire("Test")
		```
	]=]
	local Sequent = {}
	Sequent.__index = Sequent
	
	--[=[
		Constructs a new Sequent. If `cancellable` is `true`, then
		connected handlers can cancel event propagation.
	]=]
	function Sequent.new<T>(cancellable: boolean?): Sequent<T>
		local self = setmetatable({
			_connections = {},
			_firing = false,
			_queuedDisconnect = false,
	
			_firingThread = nil,
			_taskThread = nil,
	
			_cancellable = not not cancellable,
		}, Sequent)
	
		return self
	end
	
	--[=[
		@yields
		Fires the Sequent with the given value.
	
		This method will yield until all connections complete. Errors will
		bubble up if they occur within a connection.
	]=]
	function Sequent:Fire<T>(value: T)
		assert(not self._firing, "cannot fire while already firing")
		self._firing = true
	
		local cancelled = false
		local event: SequentEvent<T> = table.freeze({
			Value = value,
			Cancellable = self._cancellable,
			Cancel = function(_evt)
				if not self._cancellable then
					warn("attempted to cancel non-cancellable event")
					return
				end
				cancelled = true
			end,
		})
	
		local thread = coroutine.running()
		self._firingThread = thread
		for _, connection in self._connections do
			if not connection.Connected then
				continue
			end
	
			-- Run the task:
			local success, err = nil, nil
			local taskThread = task.spawn(function()
				self._taskThread = coroutine.running()
	
				local s, e = pcall(function()
					connection._callback(event)
				end)
	
				self._taskThread = nil
	
				-- Resume the parent thread if it yielded:
				if coroutine.status(thread) == "suspended" then
					task.spawn(thread, s, e)
				else
					success, err = s, e
				end
			end)
	
			-- If the task thread yielded, yield this thread too:
			if success == nil then
				success, err = coroutine.yield()
			end
	
			self._firingThread = nil
	
			-- Throw error if the task failed:
			if not success then
				error(debug.traceback(taskThread, tostring(err)))
			end
	
			if cancelled then
				break
			end
		end
	
		-- If connections were disconnected while firing connections, disconnect them now:
		if self._queuedDisconnect then
			self._queuedDisconnect = false
			for i = #self._connections, 1, -1 do
				local connection = self._connections[i]
				if not connection.Connected then
					self:_removeConnection(connection)
				end
			end
		end
	
		self._firing = false
	end
	
	--[=[
		Returns `true` if the Sequent is currently firing.
	]=]
	function Sequent:IsFiring(): boolean
		return self._firing
	end
	
	--[=[
		Connects a callback to the Sequent, which gets called anytime `Fire`
		is called.
	
		The given `priority` indicates the firing priority of the callback. Higher
		priority values will be run first. There are a few defaults available via
		`Sequent.Priority`.
	]=]
	function Sequent:Connect(callback: (...unknown) -> (), priority: number): SequentConnection
		assert(not self._firing, "cannot connect while firing")
	
		local connection = setmetatable({
			Connected = true,
			_callback = callback,
			_priority = priority,
			_sequent = self,
		}, SequentConnection)
	
		-- Find the correct index to remain sorted by priority:
		local idx = #self._connections + 1
		for i, c: InternalSequentConnection in self._connections do
			if c._priority < priority then
				idx = i
				break
			end
		end
	
		table.insert(self._connections, idx, connection)
	
		return connection
	end
	
	--[=[
		`Once()` is the same as `Connect()`, except the connection is automatically
		disconnected after being fired once.
	]=]
	function Sequent:Once(callback: (...unknown) -> (), priority: number): SequentConnection
		local connection: SequentConnection
	
		connection = self:Connect(function(...)
			if not connection.Connected then
				return
			end
			connection:Disconnect()
			callback(...)
		end, priority)
	
		return connection
	end
	
	--[=[
		Cancels a currently-firing Sequent.
	]=]
	function Sequent:Cancel()
		if not self._firing then
			return
		end
	
		if self._taskThread == coroutine.running() then
			error("cannot cancel sequent from connected task", 2)
		end
	
		if self._taskThread then
			-- pcall needed as the task thread may have yielded from a call to
			-- a roblox service, which will throw an error when calling task.cancel:
			pcall(function()
				task.cancel(self._taskThread)
			end)
			self._taskThread = nil
		end
	
		if self._firingThread then
			local thread = self._firingThread
			self._firingThread = nil
			task.spawn(thread, true)
		end
	end
	
	--[=[
		Cleans up the Sequent. All connections are disconnected. The Sequent is cancelled
		if it is currently firing.
	]=]
	function Sequent:Destroy()
		self:Cancel()
	
		for _, connection in self._connections do
			connection.Connected = false
		end
	end
	
	function Sequent:_disconnect(connection)
		if not connection.Connected then
			return
		end
		connection.Connected = false
	
		if self._firing then
			self._queuedDisconnect = true
			return
		end
	
		self:_removeConnection(connection)
	end
	
	function Sequent:_removeConnection(connection)
		local idx = table.find(self._connections, connection)
		if idx then
			table.remove(self._connections, idx)
		end
	end
	
	return table.freeze({
		new = Sequent.new,
		Priority = Priority,
	})
	
end
Modules["shake"] = function(...)
	--!native
	
	local RunService = game:GetService("RunService")
	
	--[=[
		@within Shake
		@type UpdateCallbackFn () -> (position: Vector3, rotation: Vector3, completed: boolean)
	]=]
	type UpdateCallbackFn = () -> (Vector3, Vector3, boolean)
	
	export type Shake = {
		Amplitude: number,
		Frequency: number,
		FadeInTime: number,
		FadeOutTime: number,
		SustainTime: number,
		Sustain: boolean,
		PositionInfluence: Vector3,
		RotationInfluence: Vector3,
		TimeFunction: () -> number,
	
		Start: (self: Shake) -> (),
		Stop: (self: Shake) -> (),
		IsShaking: (self: Shake) -> boolean,
		StopSustain: (self: Shake) -> (),
		Update: (self: Shake) -> (Vector3, Vector3, boolean),
		OnSignal: (
			self: Shake,
			signal: RBXScriptSignal,
			callback: (Vector3, Vector3, boolean) -> ()
		) -> RBXScriptConnection,
		BindToRenderStep: (self: Shake, name: string, priority: number, callback: (Vector3, Vector3, boolean) -> ()) -> (),
		Clone: (self: Shake) -> Shake,
		Destroy: (self: Shake) -> (),
	}
	
	local rng = Random.new()
	local renderId = 0
	
	--[=[
		@class Shake
		Create realistic shake effects, such as camera or object shakes.
	
		Creating a shake is very simple with this module. For every shake,
		simply create a shake instance by calling `Shake.new()`. From
		there, configure the shake however desired. Once configured,
		call `shake:Start()` and then bind a function to it with either
		`shake:OnSignal(...)` or `shake:BindToRenderStep(...)`.
		
		The shake will output its values to the connected function, and then
		automatically stop and clean up its connections once completed.
	
		Shake instances can be reused indefinitely. However, only one shake
		operation per instance can be running. If more than one is needed
		of the same configuration, simply call `shake:Clone()` to duplicate
		it.
	
		Example of a simple camera shake:
		```lua
		local priority = Enum.RenderPriority.Last.Value
	
		local shake = Shake.new()
		shake.FadeInTime = 0
		shake.Frequency = 0.1
		shake.Amplitude = 5
		shake.RotationInfluence = Vector3.new(0.1, 0.1, 0.1)
	
		shake:Start()
		shake:BindToRenderStep(Shake.NextRenderName(), priority, function(pos, rot, isDone)
			camera.CFrame *= CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
		end)
		```
	
		Shakes will automatically stop once the shake has been completed. Shakes can
		also be used continuously if the `Sustain` property is set to `true`.
	
		## Fixing drift
	
		If you are not controlling the initial CFrame of the camera (i.e. using Roblox's camera scripts),
		then you might run into odd behavior with the above example. This is because Roblox's camera
		scripts are influenced by the current CFrame value of the camera. Thus, the shake effect causes
		odd side-effects, especially noticeable at higher FPS.
	
		The solution is to simply store the camera's CFrame before applying the shake CFrame, and then
		reapplying this stored CFrame value after rendering is complete (e.g. on Heartbeat).
	
		```lua
		local camCf: CFrame
	
		shake:BindToRenderStep(Shake.NextRenderName(), priority, function(pos, rot, isDone)
			-- Store the CFrame value that was set from Roblox's camera scripts:
			camCf = camera.CFrame
	
			camera.CFrame *= CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
		end)
	
		RunService.Heartbeat:Connect(function()
			-- Reapply the camera script CFrame before they run again.
			-- Heartbeat runs AFTER Roblox has rendered, so it will not affect the camera this frame.
			camera.CFrame = camCf
		end)
		```
	
		## Configuration
	
		Here are some more helpful configuration examples:
	
		```lua
		local shake = Shake.new()
	
		-- The magnitude of the shake. Larger numbers means larger shakes.
		shake.Amplitude = 5
	
		-- The speed of the shake. Smaller frequencies mean faster shakes.
		shake.Frequency = 0.1
	
		 -- Fade-in time before max amplitude shake. Set to 0 for immediate shake.
		shake.FadeInTime = 0
	
		-- Fade-out time. Set to 0 for immediate cutoff.
		shake.FadeOutTime = 0
	
		-- How long the shake sustains full amplitude before fading out
		shake.SustainTime = 1
	
		-- Set to true to never end the shake. Call shake:StopSustain() to start the fade-out.
		shake.Sustain = true
	
		-- Multiplies against the shake vector to control the final amplitude of the position.
		-- Can be seen internally as: position = shakeVector * fadeInOut * positionInfluence
		shake.PositionInfluence = Vector3.one
	
		-- Multiplies against the shake vector to control the final amplitude of the rotation.
		-- Can be seen internally as: position = shakeVector * fadeInOut * rotationInfluence
		shake.RotationInfluence = Vector3.new(0.1, 0.1, 0.1)
	
		```
	]=]
	local Shake = {}
	Shake.__index = Shake
	
	--[=[
		@within Shake
		@prop Amplitude number
		Amplitude of the overall shake. For instance, an amplitude of `3` would mean the
		peak magnitude for the outputted shake vectors would be about `3`.
	
		Defaults to `1`.
	]=]
	
	--[=[
		@within Shake
		@prop Frequency number
		Frequency of the overall shake. This changes how slow or fast the
		shake occurs.
	
		Defaults to `1`.
	]=]
	
	--[=[
		@within Shake
		@prop FadeInTime number
		How long it takes for the shake to fade in, measured in seconds.
	
		Defaults to `1`.
	]=]
	
	--[=[
		@within Shake
		@prop FadeOutTime number
		How long it takes for the shake to fade out, measured in seconds.
	
		Defaults to `1`.
	]=]
	
	--[=[
		@within Shake
		@prop SustainTime number
		How long it takes for the shake sustains itself after fading in and
		before fading out.
		
		To sustain a shake indefinitely, set `Sustain`
		to `true`, and call the `StopSustain()` method to stop the sustain
		and fade out the shake effect.
	
		Defaults to `0`.
	]=]
	
	--[=[
		@within Shake
		@prop Sustain boolean
		If `true`, the shake will sustain itself indefinitely once it fades
		in. If `StopSustain()` is called, the sustain will end and the shake
		will fade out based on the `FadeOutTime`.
	
		Defaults to `false`.
	]=]
	
	--[=[
		@within Shake
		@prop PositionInfluence Vector3
		This is similar to `Amplitude` but multiplies against each axis
		of the resultant shake vector, and only affects the position vector.
	
		Defaults to `Vector3.one`.
	]=]
	
	--[=[
		@within Shake
		@prop RotationInfluence Vector3
		This is similar to `Amplitude` but multiplies against each axis
		of the resultant shake vector, and only affects the rotation vector.
	
		Defaults to `Vector3.one`.
	]=]
	
	--[=[
		@within Shake
		@prop TimeFunction () -> number
		The function used to get the current time. This defaults to
		`time` during runtime, and `os.clock` otherwise. Usually this
		will not need to be set, but it can be optionally configured
		if desired.
	]=]
	
	--[=[
		@return Shake
		Construct a new Shake instance.
	]=]
	function Shake.new(): Shake
		local self = setmetatable({}, Shake)
	
		self.Amplitude = 1
		self.Frequency = 1
		self.FadeInTime = 1
		self.FadeOutTime = 1
		self.SustainTime = 0
		self.Sustain = false
		self.PositionInfluence = Vector3.one
		self.RotationInfluence = Vector3.one
		self.TimeFunction = if RunService:IsRunning() then time else os.clock
	
		self._timeOffset = rng:NextNumber(-1e6, 1e6)
		self._startTime = 0
		self._running = false
		self._signalConnections = {}
		self._renderBindings = {}
	
		return self
	end
	
	--[=[
		Apply an inverse square intensity multiplier to the given vector based on the
		distance away from some source. This can be used to simulate shake intensity
		based on the distance the shake is occurring from some source.
	
		For instance, if the shake is caused by an explosion in the game, the shake
		can be calculated as such:
	
		```lua
		local function Explosion(positionOfExplosion: Vector3)
	
			local cam = workspace.CurrentCamera
			local renderPriority = Enum.RenderPriority.Last.Value
	
			local shake = Shake.new()
			-- Set shake properties here
	
			local function ExplosionShake(pos: Vector3, rot: Vector3)
				local distance = (cam.CFrame.Position - positionOfExplosion).Magnitude
				pos = Shake.InverseSquare(pos, distance)
				rot = Shake.InverseSquare(rot, distance)
				cam.CFrame *= CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
			end
	
			shake:BindToRenderStep("ExplosionShake", renderPriority, ExplosionShake)
	
		end
		```
	]=]
	function Shake.InverseSquare(shake: Vector3, distance: number): Vector3
		if distance < 1 then
			distance = 1
		end
		local intensity = 1 / (distance * distance)
		return shake * intensity
	end
	
	--[=[
		Returns a unique render name for every call, which can
		be used with the `BindToRenderStep` method optionally.
	
		```lua
		shake:BindToRenderStep(Shake.NextRenderName(), ...)
		```
	]=]
	function Shake.NextRenderName(): string
		renderId += 1
		return ("__shake_%.4i__"):format(renderId)
	end
	
	--[=[
		Start the shake effect.
	
		:::note
		This **must** be called before calling `Update`. As such, it should also be
		called once before or after calling `OnSignal` or `BindToRenderStep` methods.
		:::
	]=]
	function Shake:Start()
		self._startTime = self.TimeFunction()
		self._running = true
	end
	
	--[=[
		Stops the shake effect. If using `OnSignal` or `BindToRenderStep`, those bound
		functions will be disconnected/unbound.
	
		`Stop` is automatically called when the shake effect is completed _or_ when the
		`Destroy` method is called.
	]=]
	function Shake:Stop()
		self._running = false
	
		for _, name in self._renderBindings do
			RunService:UnbindFromRenderStep(name)
		end
		table.clear(self._renderBindings)
	
		for _, conn in self._signalConnections do
			conn:Disconnect()
		end
		table.clear(self._signalConnections)
	end
	
	--[=[
		Returns `true` if the shake instance is currently running,
		otherwise returns `false`.
	]=]
	function Shake:IsShaking(): boolean
		return self._running
	end
	
	--[=[
		Schedules a sustained shake to stop. This works by setting the
		`Sustain` field to `false` and letting the shake effect fade out
		based on the `FadeOutTime` field.
	]=]
	function Shake:StopSustain()
		local now = self.TimeFunction()
		self.Sustain = false
		self.SustainTime = (now - self._startTime) - self.FadeInTime
	end
	
	--[=[
		Calculates the current shake vector. This should be continuously
		called inside a loop, such as `RunService.Heartbeat`. Alternatively,
		`OnSignal` or `BindToRenderStep` can be used to automatically call
		this function.
	
		Returns a tuple of three values:
		1. `position: Vector3` - Position shake offset
		2. `rotation: Vector3` - Rotation shake offset
		3. `completed: boolean` - Flag indicating if the shake is finished
	
		```lua
		local hb
		hb = RunService.Heartbeat:Connect(function()
			local offsetPosition, offsetRotation, isDone = shake:Update()
			if isDone then
				hb:Disconnect()
			end
			-- Use `offsetPosition` and `offsetRotation` here
		end)
		```
	]=]
	function Shake:Update(): (Vector3, Vector3, boolean)
		local done = false
	
		local now = self.TimeFunction()
		local dur = now - self._startTime
	
		local noiseInput = ((now + self._timeOffset) / self.Frequency) % 10000
	
		local multiplierFadeIn = 1
		local multiplierFadeOut = 1
		if dur < self.FadeInTime then
			-- Fade in
			multiplierFadeIn = dur / self.FadeInTime
		end
		if not self.Sustain and dur > self.FadeInTime + self.SustainTime then
			if self.FadeOutTime == 0 then
				done = true
			else
				-- Fade out
				multiplierFadeOut = 1 - (dur - self.FadeInTime - self.SustainTime) / self.FadeOutTime
				if not self.Sustain and dur >= self.FadeInTime + self.SustainTime + self.FadeOutTime then
					done = true
				end
			end
		end
	
		local offset = Vector3.new(
			math.noise(noiseInput, 0) / 2,
			math.noise(0, noiseInput) / 2,
			math.noise(noiseInput, noiseInput) / 2
		) * self.Amplitude * math.min(multiplierFadeIn, multiplierFadeOut)
	
		if done then
			self:Stop()
		end
	
		return self.PositionInfluence * offset, self.RotationInfluence * offset, done
	end
	
	--[=[
		@param signal Signal | RBXScriptSignal
		@param callbackFn UpdateCallbackFn
		@return Connection | RBXScriptConnection
	
		Bind the `Update` method to a signal. For instance, this can be used
		to connect to `RunService.Heartbeat`.
	
		All connections are cleaned up when the shake instance is stopped
		or destroyed.
	
		```lua
		local function SomeShake(pos: Vector3, rot: Vector3, completed: boolean)
			-- Shake
		end
	
		shake:OnSignal(RunService.Heartbeat, SomeShake)
		```
	]=]
	function Shake:OnSignal(signal, callbackFn: UpdateCallbackFn)
		local conn = signal:Connect(function()
			callbackFn(self:Update())
		end)
	
		table.insert(self._signalConnections, conn)
	
		return conn
	end
	
	--[=[
		@param name string -- Name passed to `RunService:BindToRenderStep`
		@param priority number -- Priority passed to `RunService:BindToRenderStep`
		@param callbackFn UpdateCallbackFn
	
		Bind the `Update` method to RenderStep.
	
		All bound functions are cleaned up when the shake instance is stopped
		or destroyed.
	
		```lua
		local renderPriority = Enum.RenderPriority.Camera.Value
	
		local function SomeShake(pos: Vector3, rot: Vector3, completed: boolean)
			-- Shake
		end
	
		shake:BindToRenderStep("SomeShake", renderPriority, SomeShake)
		```
	]=]
	function Shake:BindToRenderStep(name: string, priority: number, callbackFn: UpdateCallbackFn)
		RunService:BindToRenderStep(name, priority, function()
			callbackFn(self:Update())
		end)
	
		table.insert(self._renderBindings, name)
	end
	
	--[=[
		@return Shake
		Creates a new shake with identical properties as
		this one. This does _not_ clone over playing state,
		and thus the cloned instance will be in a stopped
		state.
	
		A use-case for using `Clone` would be to create a module
		with a list of shake presets. These presets can be cloned
		when desired for use. For instance, there might be presets
		for explosions, recoil, or earthquakes.
	
		```lua
		--------------------------------------
		-- Example preset module
		local ShakePresets = {}
	
		local explosion = Shake.new()
		-- Configure `explosion` shake here
		ShakePresets.Explosion = explosion
	
		return ShakePresets
		--------------------------------------
	
		-- Use the module:
		local ShakePresets = require(somewhere.ShakePresets)
		local explosionShake = ShakePresets.Explosion:Clone()
		```
	]=]
	function Shake:Clone()
		local shake = Shake.new()
		local cloneFields = {
			"Amplitude",
			"Frequency",
			"FadeInTime",
			"FadeOutTime",
			"SustainTime",
			"Sustain",
			"PositionInfluence",
			"RotationInfluence",
			"TimeFunction",
		}
		for _, field in cloneFields do
			shake[field] = self[field]
		end
		return shake
	end
	
	--[=[
		Alias for `Stop()`.
	]=]
	function Shake:Destroy()
		self:Stop()
	end
	
	return {
		new = Shake.new,
		InverseSquare = Shake.InverseSquare,
		NextRenderName = Shake.NextRenderName,
	}
	
end
Modules["signal"] = function(...)
	-- -----------------------------------------------------------------------------
	--               Batched Yield-Safe Signal Implementation                     --
	-- This is a Signal class which has effectively identical behavior to a       --
	-- normal RBXScriptSignal, with the only difference being a couple extra      --
	-- stack frames at the bottom of the stack trace when an error is thrown.     --
	-- This implementation caches runner coroutines, so the ability to yield in   --
	-- the signal handlers comes at minimal extra cost over a naive signal        --
	-- implementation that either always or never spawns a thread.                --
	--                                                                            --
	-- License:                                                                   --
	--   Licensed under the MIT license.                                          --
	--                                                                            --
	-- Authors:                                                                   --
	--   stravant - July 31st, 2021 - Created the file.                           --
	--   sleitnick - August 3rd, 2021 - Modified for Knit.                        --
	-- -----------------------------------------------------------------------------
	
	-- Signal types
	export type Connection = {
		Disconnect: (self: Connection) -> (),
		Destroy: (self: Connection) -> (),
		Connected: boolean,
	}
	
	export type Signal<T...> = {
		Fire: (self: Signal<T...>, T...) -> (),
		FireDeferred: (self: Signal<T...>, T...) -> (),
		Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
		Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
		DisconnectAll: (self: Signal<T...>) -> (),
		GetConnections: (self: Signal<T...>) -> { Connection },
		Destroy: (self: Signal<T...>) -> (),
		Wait: (self: Signal<T...>) -> T...,
	}
	
	-- The currently idle thread to run the next handler on
	local freeRunnerThread = nil
	
	-- Function which acquires the currently idle handler runner thread, runs the
	-- function fn on it, and then releases the thread, returning it to being the
	-- currently idle one.
	-- If there was a currently idle runner thread already, that's okay, that old
	-- one will just get thrown and eventually GCed.
	local function acquireRunnerThreadAndCallEventHandler(fn, ...)
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		fn(...)
		-- The handler finished running, this runner thread is free again.
		freeRunnerThread = acquiredRunnerThread
	end
	
	-- Coroutine runner that we create coroutines of. The coroutine can be
	-- repeatedly resumed with functions to run followed by the argument to run
	-- them with.
	local function runEventHandlerInFreeThread(...)
		acquireRunnerThreadAndCallEventHandler(...)
		while true do
			acquireRunnerThreadAndCallEventHandler(coroutine.yield())
		end
	end
	
	--[=[
		@within Signal
		@interface SignalConnection
		.Connected boolean
		.Disconnect (SignalConnection) -> ()
	
		Represents a connection to a signal.
		```lua
		local connection = signal:Connect(function() end)
		print(connection.Connected) --> true
		connection:Disconnect()
		print(connection.Connected) --> false
		```
	]=]
	
	-- Connection class
	local Connection = {}
	Connection.__index = Connection
	
	function Connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
	
		-- Unhook the node, but DON'T clear it. That way any fire calls that are
		-- currently sitting on this node will be able to iterate forwards off of
		-- it, but any subsequent fire calls will not hit it, and it will be GCed
		-- when no more fire calls are sitting on it.
		if self._signal._handlerListHead == self then
			self._signal._handlerListHead = self._next
		else
			local prev = self._signal._handlerListHead
			while prev and prev._next ~= self do
				prev = prev._next
			end
			if prev then
				prev._next = self._next
			end
		end
	end
	
	Connection.Destroy = Connection.Disconnect
	
	-- Make Connection strict
	setmetatable(Connection, {
		__index = function(_tb, key)
			error(("Attempt to get Connection::%s (not a valid member)"):format(tostring(key)), 2)
		end,
		__newindex = function(_tb, key, _value)
			error(("Attempt to set Connection::%s (not a valid member)"):format(tostring(key)), 2)
		end,
	})
	
	--[=[
		@within Signal
		@type ConnectionFn (...any) -> ()
	
		A function connected to a signal.
	]=]
	
	--[=[
		@class Signal
	
		A Signal is a data structure that allows events to be dispatched
		and observed.
	
		This implementation is a direct copy of the de facto standard, [GoodSignal](https://devforum.roblox.com/t/lua-signal-class-comparison-optimal-goodsignal-class/1387063),
		with some added methods and typings.
	
		For example:
		```lua
		local signal = Signal.new()
	
		-- Subscribe to a signal:
		signal:Connect(function(msg)
			print("Got message:", msg)
		end)
	
		-- Dispatch an event:
		signal:Fire("Hello world!")
		```
	]=]
	local Signal = {}
	Signal.__index = Signal
	
	--[=[
		Constructs a new Signal
	
		@return Signal
	]=]
	function Signal.new<T...>(): Signal<T...>
		local self = setmetatable({
			_handlerListHead = false,
			_proxyHandler = nil,
			_yieldedThreads = nil,
		}, Signal)
	
		return self
	end
	
	--[=[
		Constructs a new Signal that wraps around an RBXScriptSignal.
	
		@param rbxScriptSignal RBXScriptSignal -- Existing RBXScriptSignal to wrap
		@return Signal
	
		For example:
		```lua
		local signal = Signal.Wrap(workspace.ChildAdded)
		signal:Connect(function(part) print(part.Name .. " added") end)
		Instance.new("Part").Parent = workspace
		```
	]=]
	function Signal.Wrap<T...>(rbxScriptSignal: RBXScriptSignal): Signal<T...>
		assert(
			typeof(rbxScriptSignal) == "RBXScriptSignal",
			"Argument #1 to Signal.Wrap must be a RBXScriptSignal; got " .. typeof(rbxScriptSignal)
		)
	
		local signal = Signal.new()
		signal._proxyHandler = rbxScriptSignal:Connect(function(...)
			signal:Fire(...)
		end)
	
		return signal
	end
	
	--[=[
		Checks if the given object is a Signal.
	
		@param obj any -- Object to check
		@return boolean -- `true` if the object is a Signal.
	]=]
	function Signal.Is(obj: any): boolean
		return type(obj) == "table" and getmetatable(obj) == Signal
	end
	
	--[=[
		@param fn ConnectionFn
		@return SignalConnection
	
		Connects a function to the signal, which will be called anytime the signal is fired.
		```lua
		signal:Connect(function(msg, num)
			print(msg, num)
		end)
	
		signal:Fire("Hello", 25)
		```
	]=]
	function Signal:Connect(fn)
		local connection = setmetatable({
			Connected = true,
			_signal = self,
			_fn = fn,
			_next = false,
		}, Connection)
	
		if self._handlerListHead then
			connection._next = self._handlerListHead
			self._handlerListHead = connection
		else
			self._handlerListHead = connection
		end
	
		return connection
	end
	
	--[=[
		@deprecated v1.3.0 -- Use `Signal:Once` instead.
		@param fn ConnectionFn
		@return SignalConnection
	]=]
	function Signal:ConnectOnce(fn)
		return self:Once(fn)
	end
	
	--[=[
		@param fn ConnectionFn
		@return SignalConnection
	
		Connects a function to the signal, which will be called the next time the signal fires. Once
		the connection is triggered, it will disconnect itself.
		```lua
		signal:Once(function(msg, num)
			print(msg, num)
		end)
	
		signal:Fire("Hello", 25)
		signal:Fire("This message will not go through", 10)
		```
	]=]
	function Signal:Once(fn)
		local connection
		local done = false
	
		connection = self:Connect(function(...)
			if done then
				return
			end
	
			done = true
			connection:Disconnect()
			fn(...)
		end)
	
		return connection
	end
	
	function Signal:GetConnections()
		local items = {}
	
		local item = self._handlerListHead
		while item do
			table.insert(items, item)
			item = item._next
		end
	
		return items
	end
	
	-- Disconnect all handlers. Since we use a linked list it suffices to clear the
	-- reference to the head handler.
	--[=[
		Disconnects all connections from the signal.
		```lua
		signal:DisconnectAll()
		```
	]=]
	function Signal:DisconnectAll()
		local item = self._handlerListHead
		while item do
			item.Connected = false
			item = item._next
		end
		self._handlerListHead = false
	
		local yieldedThreads = rawget(self, "_yieldedThreads")
		if yieldedThreads then
			for thread in yieldedThreads do
				if coroutine.status(thread) == "suspended" then
					warn(debug.traceback(thread, "signal disconnected; yielded thread cancelled", 2))
					task.cancel(thread)
				end
			end
			table.clear(self._yieldedThreads)
		end
	end
	
	-- Signal:Fire(...) implemented by running the handler functions on the
	-- coRunnerThread, and any time the resulting thread yielded without returning
	-- to us, that means that it yielded to the Roblox scheduler and has been taken
	-- over by Roblox scheduling, meaning we have to make a new coroutine runner.
	--[=[
		@param ... any
	
		Fire the signal, which will call all of the connected functions with the given arguments.
		```lua
		signal:Fire("Hello")
	
		-- Any number of arguments can be fired:
		signal:Fire("Hello", 32, {Test = "Test"}, true)
		```
	]=]
	function Signal:Fire(...)
		local item = self._handlerListHead
		while item do
			if item.Connected then
				if not freeRunnerThread then
					freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
				end
				task.spawn(freeRunnerThread, item._fn, ...)
			end
			item = item._next
		end
	end
	
	--[=[
		@param ... any
	
		Same as `Fire`, but uses `task.defer` internally & doesn't take advantage of thread reuse.
		```lua
		signal:FireDeferred("Hello")
		```
	]=]
	function Signal:FireDeferred(...)
		local item = self._handlerListHead
		while item do
			local conn = item
			task.defer(function(...)
				if conn.Connected then
					conn._fn(...)
				end
			end, ...)
			item = item._next
		end
	end
	
	--[=[
		@return ... any
		@yields
	
		Yields the current thread until the signal is fired, and returns the arguments fired from the signal.
		Yielding the current thread is not always desirable. If the desire is to only capture the next event
		fired, using `Once` might be a better solution.
		```lua
		task.spawn(function()
			local msg, num = signal:Wait()
			print(msg, num) --> "Hello", 32
		end)
		signal:Fire("Hello", 32)
		```
	]=]
	function Signal:Wait()
		local yieldedThreads = rawget(self, "_yieldedThreads")
		if not yieldedThreads then
			yieldedThreads = {}
			rawset(self, "_yieldedThreads", yieldedThreads)
		end
	
		local thread = coroutine.running()
		yieldedThreads[thread] = true
	
		self:Once(function(...)
			yieldedThreads[thread] = nil
	
			if coroutine.status(thread) == "suspended" then
				task.spawn(thread, ...)
			end
		end)
	
		return coroutine.yield()
	end
	
	--[=[
		Cleans up the signal.
	
		Technically, this is only necessary if the signal is created using
		`Signal.Wrap`. Connections should be properly GC'd once the signal
		is no longer referenced anywhere. However, it is still good practice
		to include ways to strictly clean up resources. Calling `Destroy`
		on a signal will also disconnect all connections immediately.
		```lua
		signal:Destroy()
		```
	]=]
	function Signal:Destroy()
		self:DisconnectAll()
	
		local proxyHandler = rawget(self, "_proxyHandler")
		if proxyHandler then
			proxyHandler:Disconnect()
		end
	end
	
	-- Make signal strict
	setmetatable(Signal, {
		__index = function(_tb, key)
			error(("Attempt to get Signal::%s (not a valid member)"):format(tostring(key)), 2)
		end,
		__newindex = function(_tb, key, _value)
			error(("Attempt to set Signal::%s (not a valid member)"):format(tostring(key)), 2)
		end,
	})
	
	return table.freeze({
		new = Signal.new,
		Wrap = Signal.Wrap,
		Is = Signal.Is,
	})
	
end
Modules["spring"] = function(...)
	--!strict
	
	--[=[
		@class Spring
	
		Simulates a critically damped spring. This is mostly just a wrapper around
		[`TweenService:SmoothDamp()`](https://create.roblox.com/docs/reference/engine/classes/TweenService#SmoothDamp).
	]=]
	
	local TweenService = game:GetService("TweenService")
	
	local Spring = {}
	Spring.__index = Spring
	
	export type Spring<T> = typeof(setmetatable(
		{} :: {
			Current: T,
			Target: T,
			Velocity: T,
			SmoothTime: number,
			MaxSpeed: number,
		},
		Spring
	))
	
	--[=[
		Creates a new spring.
	
		The type `T` can be a `number`, `Vector2`, `Vector3`, or `CFrame`.
	
		@param initial T -- Initial value
		@param smoothTime number -- Approximate time it takes to reach target
		@param maxSpeed number -- Maximum speed (defaults to infinity)
	]=]
	function Spring.new<T>(initial: T, smoothTime: number, maxSpeed: number?): Spring<T>
		local self = setmetatable({
			Current = initial,
			Target = initial,
			Velocity = if typeof(initial) == "CFrame" then CFrame.identity else (initial :: any) * 0,
			SmoothTime = smoothTime,
			MaxSpeed = if maxSpeed ~= nil then maxSpeed else math.huge,
		}, Spring)
	
		return self
	end
	
	--[=[
		@within Spring
		@method Update
	
		Updates the spring. This method should be called continuously, even if the target value hasn't changed.
	
		```lua
		local newValue = spring:Update(dt)
		```
	
		@param deltaTime number
		@return T
	]=]
	function Spring.Update<T>(self: Spring<T>, dt: number): T
		self.Current, self.Velocity =
			TweenService:SmoothDamp(self.Current, self.Target, self.Velocity, self.SmoothTime, self.MaxSpeed, dt)
	
		return self.Current
	end
	
	--[=[
		@within Spring
		@method Impulse
	
		Impulses the spring.
	
		```lua
		spring:Impulse(rng:NextUnitVector() * 10)
		```
	
		@param velocity T
	]=]
	function Spring.Impulse<T>(self: Spring<T>, velocity: T)
		self.Velocity += velocity :: any
	end
	
	--[=[
		@within Spring
		@method Reset
	
		Resets the spring to the given value.
	
		@param value T
	]=]
	function Spring.Reset<T>(self: Spring<T>, value: T)
		self.Current = value
		self.Target = value
		self.Velocity = if typeof(self.Current) == "CFrame" then CFrame.identity else (self.Current :: any) * 0
	end
	
	return Spring
	
end
Modules["stream"] = function(...)
	--!native
	--!strict
	
	--[=[
		@class stream
	
		The `stream` library allows a stream-like interface abstraction on top of buffers. This is useful
		for reading or writing buffers without having to keep track of the current offset position.
	
		This library is specifically tailored around fixed-length buffers.
	
		```lua
		-- Create an empty stream and write some data:
		local s = stream.create(4)
		stream.writeu8(s, 10)
		stream.writeu8(s, 25)
		stream.writeu8(s, 2)
		stream.writeu8(s, 43)
	
		-- Grab the buffer if needed:
		local buf = stream.buffer(s)
	
		-- Create a stream from an existing buffer:
		local s = stream.from(buf)
		print(stream.readu8()) -- 10
		print(stream.readu8()) -- 25
		print(stream.readu8()) -- 2
		print(stream.readu8()) -- 43
	
		-- Move the cursor:
		stream.seek(s, 1)
		print(stream.readu8()) -- 25
		```
	]=]
	
	export type Stream = {
		b: buffer,
		l: number,
		o: number,
	}
	
	local stream = {}
	
	--[=[
		@within stream
	
		Create a stream around a new buffer with the given size in bytes.
		
		This is equivalent to `stream.frombuffer(buffer.create(size))`.
	]=]
	function stream.create(size: number): Stream
		return stream.frombuffer(buffer.create(size))
	end
	
	--[=[
		@within stream
	
		Create a stream around an existing buffer.
	]=]
	function stream.frombuffer(buf: buffer): Stream
		return {
			b = buf,
			l = buffer.len(buf),
			o = 0,
		}
	end
	
	--[=[
		@within stream
	
		Create a stream from an existing string.
		
		This is equivalent to `stream.frombuffer(buffer.fromstring(size))`.
	]=]
	function stream.fromstring(str: string): Stream
		local buf = buffer.fromstring(str)
		return {
			b = buf,
			l = buffer.len(buf),
			o = 0,
		}
	end
	
	-------------------------------------------------------------------------
	-- Read
	
	--[=[
		@within stream
	]=]
	function stream.readu8(s: Stream): number
		local n = buffer.readu8(s.b, s.o)
		s.o += 1
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readi8(s: Stream): number
		local n = buffer.readi8(s.b, s.o)
		s.o += 1
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readu16(s: Stream): number
		local n = buffer.readu16(s.b, s.o)
		s.o += 2
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readi16(s: Stream): number
		local n = buffer.readi16(s.b, s.o)
		s.o += 2
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readu32(s: Stream): number
		local n = buffer.readu32(s.b, s.o)
		s.o += 4
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readi32(s: Stream): number
		local n = buffer.readi32(s.b, s.o)
		s.o += 4
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readf32(s: Stream): number
		local n = buffer.readf32(s.b, s.o)
		s.o += 4
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readf64(s: Stream): number
		local n = buffer.readf64(s.b, s.o)
		s.o += 8
		return n
	end
	
	--[=[
		@within stream
	]=]
	function stream.readstring(s: Stream, count: number): string
		local str = buffer.readstring(s.b, s.o, count)
		s.o += count
		return str
	end
	
	--[=[
		@within stream
	
		Reads a string previously written using `stream.writelstring`. This function
		assumes that the length of the string is written at the beginning as a u32 int.
	]=]
	function stream.readlstring(s: Stream): string
		local count = stream.readu32(s)
		return stream.readstring(s, count)
	end
	
	--[=[
		@within stream
	
		Equivalent to `stream.readvectorf32`.
	]=]
	function stream.readvector(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readf32(b, o + 0)
		local y = buffer.readf32(b, o + 4)
		local z = buffer.readf32(b, o + 8)
		s.o += 12
		return vector.create(x, y, z)
	end
	
	--[=[
		@within stream
	]=]
	function stream.readvectorf32(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readf32(b, o + 0)
		local y = buffer.readf32(b, o + 4)
		local z = buffer.readf32(b, o + 8)
		s.o += 12
		return vector.create(x, y, z)
	end
	
	--[=[
		@within stream
	]=]
	function stream.readvectoru32(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readu32(b, o + 0)
		local y = buffer.readu32(b, o + 4)
		local z = buffer.readu32(b, o + 8)
		s.o += 12
		return vector.create(x, y, z)
	end
	
	--[=[
		@within stream
	]=]
	function stream.readvectori32(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readi32(b, o + 0)
		local y = buffer.readi32(b, o + 4)
		local z = buffer.readi32(b, o + 8)
		s.o += 12
		return vector.create(x, y, z)
	end
	
	--[=[
		@within stream
	]=]
	function stream.readvectoru16(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readu16(b, o + 0)
		local y = buffer.readu16(b, o + 2)
		local z = buffer.readu16(b, o + 4)
		s.o += 6
		return vector.create(x, y, z)
	end
	
	--[=[
		@within stream
	]=]
	function stream.readvectori16(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readi16(b, o + 0)
		local y = buffer.readi16(b, o + 2)
		local z = buffer.readi16(b, o + 4)
		s.o += 6
		return vector.create(x, y, z)
	end
	
	--[=[
		@within stream
	]=]
	function stream.readvectoru8(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readu8(b, o + 0)
		local y = buffer.readu8(b, o + 1)
		local z = buffer.readu8(b, o + 2)
		s.o += 3
		return vector.create(x, y, z)
	end
	
	--[=[
		@within stream
	]=]
	function stream.readvectori8(s: Stream): vector
		local b = s.b
		local o = s.o
		local x = buffer.readi8(b, o + 0)
		local y = buffer.readi8(b, o + 1)
		local z = buffer.readi8(b, o + 2)
		s.o += 3
		return vector.create(x, y, z)
	end
	
	-------------------------------------------------------------------------
	-- Write
	
	--[=[
		@within stream
	]=]
	function stream.writeu8(s: Stream, n: number)
		buffer.writeu8(s.b, s.o, n)
		s.o += 1
	end
	
	--[=[
		@within stream
	]=]
	function stream.writei8(s: Stream, n: number)
		buffer.writei8(s.b, s.o, n)
		s.o += 1
	end
	
	--[=[
		@within stream
	]=]
	function stream.writeu16(s: Stream, n: number)
		buffer.writeu16(s.b, s.o, n)
		s.o += 2
	end
	
	--[=[
		@within stream
	]=]
	function stream.writei16(s: Stream, n: number)
		buffer.writei16(s.b, s.o, n)
		s.o += 2
	end
	
	--[=[
		@within stream
	]=]
	function stream.writeu32(s: Stream, n: number)
		buffer.writeu32(s.b, s.o, n)
		s.o += 4
	end
	
	--[=[
		@within stream
	]=]
	function stream.writei32(s: Stream, n: number)
		buffer.writei32(s.b, s.o, n)
		s.o += 4
	end
	
	--[=[
		@within stream
	]=]
	function stream.writef32(s: Stream, n: number)
		buffer.writef32(s.b, s.o, n)
		s.o += 4
	end
	
	--[=[
		@within stream
	]=]
	function stream.writef64(s: Stream, n: number)
		buffer.writef64(s.b, s.o, n)
		s.o += 8
	end
	
	--[=[
		@within stream
	]=]
	function stream.writestring(s: Stream, str: string, count: number?)
		buffer.writestring(s.b, s.o, str, count)
		s.o += count or #str
	end
	
	--[=[
		@within stream
	]=]
	function stream.writelstring(s: Stream, str: string, count: number?)
		stream.writeu32(s, count or #str)
		stream.writestring(s, str, count)
	end
	
	--[=[
		@within stream
	
		Equivalent to `stream.writevectorf32`.
	]=]
	function stream.writevector(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writef32(b, o + 0, v.x)
		buffer.writef32(b, o + 4, v.y)
		buffer.writef32(b, o + 8, v.z)
		s.o += 12
	end
	
	--[=[
		@within stream
	]=]
	function stream.writevectorf32(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writef32(b, o + 0, v.x)
		buffer.writef32(b, o + 4, v.y)
		buffer.writef32(b, o + 8, v.z)
		s.o += 12
	end
	
	--[=[
		@within stream
	]=]
	function stream.writevectoru32(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writeu32(b, o + 0, v.x)
		buffer.writeu32(b, o + 4, v.y)
		buffer.writeu32(b, o + 8, v.z)
		s.o += 12
	end
	
	--[=[
		@within stream
	]=]
	function stream.writevectori32(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writei32(b, o + 0, v.x)
		buffer.writei32(b, o + 4, v.y)
		buffer.writei32(b, o + 8, v.z)
		s.o += 12
	end
	
	--[=[
		@within stream
	]=]
	function stream.writevectoru16(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writeu16(b, o + 0, v.x)
		buffer.writeu16(b, o + 2, v.y)
		buffer.writeu16(b, o + 4, v.z)
		s.o += 6
	end
	
	--[=[
		@within stream
	]=]
	function stream.writevectori16(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writei16(b, o + 0, v.x)
		buffer.writei16(b, o + 2, v.y)
		buffer.writei16(b, o + 4, v.z)
		s.o += 6
	end
	
	--[=[
		@within stream
	]=]
	function stream.writevectoru8(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writeu8(b, o + 0, v.x)
		buffer.writeu8(b, o + 1, v.y)
		buffer.writeu8(b, o + 2, v.z)
		s.o += 3
	end
	
	--[=[
		@within stream
	]=]
	function stream.writevectori8(s: Stream, v: vector)
		local b = s.b
		local o = s.o
		buffer.writei8(b, o + 0, v.x)
		buffer.writei8(b, o + 1, v.y)
		buffer.writei8(b, o + 2, v.z)
		s.o += 3
	end
	
	-------------------------------------------------------------------------
	
	--[=[
		@within stream
	
		Returns the length of the backing buffer.
	]=]
	function stream.len(s: Stream): number
		return s.l
	end
	
	--[=[
		@within stream
	
		Returns the position of the stream's cursor.
	]=]
	function stream.pos(s: Stream): number
		return s.o
	end
	
	--[=[
		@within stream
	
		Copy `count` bytes from `source` into `target`. The provided streams' cursors are
		incremented by `count`.
	]=]
	function stream.copy(target: Stream, source: Stream, count: number)
		buffer.copy(target.b, target.o, source.b, source.o, count)
		target.o += count
		source.o += count
	end
	
	--[=[
		@within stream
	
		Copy `count` bytes from the `source` stream into the `target` buffer. The `source` stream
		cursor is incremented by `count`.
	]=]
	function stream.copytobuffer(target: buffer, targetOffset: number, source: Stream, count: number)
		buffer.copy(target, targetOffset, source.b, source.o, count)
		source.o += count
	end
	
	--[=[
		@within stream
	
		Copy `count` bytes from the `source` buffer (optionally offset by `sourceOffset`) into the
		`target` stream. The `target` stream cursor is incremented by `count`.
	]=]
	function stream.copyfrombuffer(target: Stream, source: buffer, sourceOffset: number?, count: number)
		buffer.copy(target.b, target.o, source, sourceOffset, count)
		target.o += count
	end
	
	--[=[
		@within stream
	
		Moves the cursor relative to the beginning of the stream.
	]=]
	function stream.seek(s: Stream, offset: number)
		s.o = offset
		if s.o < 0 or s.o > s.l then
			error("seek out of bounds", 2)
		end
	end
	
	--[=[
		@within stream
	
		Moves the cursor backward relative to the end of the stream.
	]=]
	function stream.seekend(s: Stream, offset: number)
		s.o = s.l - offset
		if s.o < 0 or s.o > s.l then
			error("seek out of bounds", 2)
		end
	end
	
	--[=[
		@within stream
	
		Moves the cursor forward relative to the current cursor position.
	]=]
	function stream.seekforward(s: Stream, offset: number)
		s.o += offset
		if s.o < 0 or s.o > s.l then
			error("seek out of bounds", 2)
		end
	end
	
	--[=[
		@within stream
	
		Moves the cursor backward relative to the current cursor position.
	]=]
	function stream.seekbackward(s: Stream, offset: number)
		s.o -= offset
		if s.o < 0 or s.o > s.l then
			error("seek out of bounds", 2)
		end
	end
	
	--[=[
		@within stream
	
		Gets the backing buffer for the stream.
	]=]
	function stream.buffer(s: Stream): buffer
		return s.b
	end
	
	--[=[
		@within stream
	
		Returns the backing buffer as a string.
	]=]
	function stream.tostring(s: Stream): string
		return buffer.tostring(s.b)
	end
	
	--[=[
		@within stream
	
		Returns `true` if the cursor is at the end of the stream.
	]=]
	function stream.atend(s: Stream): boolean
		return s.o == s.l
	end
	
	-------------------------------------------------------------------------
	
	return table.freeze(stream)
	
end
Modules["symbol"] = function(...)
	-- Symbol
	-- Stephen Leitnick
	-- January 04, 2022
	
	--[=[
		@class Symbol
	
		Represents a unique object.
	
		Symbols are often used as unique keys in tables. This is useful to avoid possible collisions
		with a key in a table, since the symbol will always be unique and cannot be reconstructed.
	
		
		:::note All Unique
		Every creation of a symbol is unique, even if the
		given names are the same.
		:::
	
		```lua
		local Symbol = require(packages.Symbol)
		
		-- Create a symbol:
		local symbol = Symbol("MySymbol")
	
		-- The name is optional:
		local anotherSymbol = Symbol()
	
		-- Comparison:
		print(symbol == symbol) --> true
	
		-- All symbol constructions are unique, regardless of the name:
		print(Symbol("Hello") == Symbol("Hello")) --> false
	
		-- Commonly used as unique keys in a table:
		local DATA_KEY = Symbol("Data")
		local t = {
			-- Can only be accessed using the DATA_KEY symbol:
			[DATA_KEY] = {}
		}
	
		print(t[DATA_KEY]) --> {}
		```
	]=]
	
	local function Symbol(name: string?)
		local symbol = newproxy(true)
		if not name then
			name = ""
		end
		getmetatable(symbol).__tostring = function()
			return "Symbol(" .. name .. ")"
		end
		return symbol
	end
	
	return Symbol
	
end
Modules["table-util"] = function(...)
	--!strict
	
	-- TableUtil
	-- Stephen Leitnick
	-- September 13, 2017
	
	--[=[
		@class TableUtil
	
		A collection of helpful table utility functions. Many of these functions are carried over from JavaScript or
		Python that are not present in Lua.
	
		Tables that only work specifically with arrays or dictionaries are marked as such in the documentation.
	
		:::info Immutability
		All functions (_except_ `SwapRemove`, `SwapRemoveFirstValue`, and `Lock`) treat tables as immutable and will return
		copies of the given table(s) with the operations performed on the copies.
		:::
	]=]
	local TableUtil = {}
	
	local HttpService = game:GetService("HttpService")
	local rng = Random.new()
	
	--[=[
		@within TableUtil
		@function Copy
		@param tbl table -- Table to copy
		@param deep boolean? -- Whether or not to perform a deep copy
		@return table
	
		Creates a copy of the given table. By default, a shallow copy is
		performed. For deep copies, a second boolean argument must be
		passed to the function.
	
		:::caution No cyclical references
		Deep copies are _not_ protected against cyclical references. Passing
		a table with cyclical references _and_ the `deep` parameter set to
		`true` will result in a stack-overflow.
		:::
	]=]
	local function Copy<T>(t: T, deep: boolean?): T
		if not deep then
			return (table.clone(t :: any) :: any) :: T
		end
		local function DeepCopy(tbl: { any })
			local tCopy = table.clone(tbl)
			for k, v in tCopy do
				if type(v) == "table" then
					tCopy[k] = DeepCopy(v)
				end
			end
			return tCopy
		end
		return DeepCopy(t :: any) :: T
	end
	
	--[=[
		@within TableUtil
		@function Sync
		@param srcTbl table -- Source table
		@param templateTbl table -- Template table
		@return table
	
		Synchronizes the `srcTbl` based on the `templateTbl`. This will make
		sure that `srcTbl` has all of the same keys as `templateTbl`, including
		removing keys in `srcTbl` that are not present in `templateTbl`. This
		is a _deep_ operation, so any nested tables will be synchronized as
		well.
	
		```lua
		local template = {kills = 0, deaths = 0, xp = 0}
		local data = {kills = 10, experience = 12}
		data = TableUtil.Sync(data, template)
		print(data) --> {kills = 10, deaths = 0, xp = 0}
		```
	
		:::caution Data Loss Warning
		This is a two-way sync, so the source table will have data
		_removed_ that isn't found in the template table. This can
		be problematic if used for player data, where there might
		be dynamic data added that isn't in the template.
	
		For player data, use `TableUtil.Reconcile` instead.
		:::
	]=]
	local function Sync<S, T>(srcTbl: S, templateTbl: T): T
		assert(type(srcTbl) == "table", "First argument must be a table")
		assert(type(templateTbl) == "table", "Second argument must be a table")
	
		local tbl = table.clone(srcTbl)
	
		-- If 'tbl' has something 'templateTbl' doesn't, then remove it from 'tbl'
		-- If 'tbl' has something of a different type than 'templateTbl', copy from 'templateTbl'
		-- If 'templateTbl' has something 'tbl' doesn't, then add it to 'tbl'
		for k, v in pairs(tbl) do
			local vTemplate = templateTbl[k]
	
			-- Remove keys not within template:
			if vTemplate == nil then
				tbl[k] = nil
	
				-- Synchronize data types:
			elseif type(v) ~= type(vTemplate) then
				if type(vTemplate) == "table" then
					tbl[k] = Copy(vTemplate, true)
				else
					tbl[k] = vTemplate
				end
	
				-- Synchronize sub-tables:
			elseif type(v) == "table" then
				tbl[k] = Sync(v, vTemplate)
			end
		end
	
		-- Add any missing keys:
		for k, vTemplate in pairs(templateTbl) do
			local v = tbl[k]
	
			if v == nil then
				if type(vTemplate) == "table" then
					tbl[k] = Copy(vTemplate, true)
				else
					tbl[k] = vTemplate
				end
			end
		end
	
		return (tbl :: any) :: T
	end
	
	--[=[
		@within TableUtil
		@function Reconcile
		@param source table
		@param template table
		@return table
	
		Performs a one-way sync on the `source` table against the
		`template` table. Any keys found in `template` that are
		not found in `source` will be added to `source`. This is
		useful for syncing player data against data template tables
		to ensure players have all the necessary keys, while
		maintaining existing keys that may no longer be in the
		template.
	
		This is a deep operation, so nested tables will also be
		properly reconciled.
	
		```lua
		local template = {kills = 0, deaths = 0, xp = 0}
		local data = {kills = 10, abc = 20}
		local correctedData = TableUtil.Reconcile(data, template)
		
		print(correctedData) --> {kills = 10, deaths = 0, xp = 0, abc = 20}
		```
	]=]
	local function Reconcile<S, T>(src: S, template: T): S & T
		assert(type(src) == "table", "First argument must be a table")
		assert(type(template) == "table", "Second argument must be a table")
	
		local tbl = table.clone(src)
	
		for k, v in template do
			local sv = src[k]
			if sv == nil then
				if type(v) == "table" then
					tbl[k] = Copy(v, true)
				else
					tbl[k] = v
				end
			elseif type(sv) == "table" then
				if type(v) == "table" then
					tbl[k] = Reconcile(sv, v)
				else
					tbl[k] = Copy(sv, true)
				end
			end
		end
	
		return (tbl :: any) :: S & T
	end
	
	--[=[
		@within TableUtil
		@function SwapRemove
		@param tbl table -- Array
		@param i number -- Index
	
		Removes index `i` in the table by swapping the value at `i` with
		the last value in the array, and then trimming off the last
		value from the array.
	
		This allows removal of the value at `i` in `O(1)` time, but does
		not preserve array ordering. If a value needs to be removed from
		an array, but ordering of the array does not matter, using
		`SwapRemove` is always preferred over `table.remove`.
	
		In the following example, we remove "B" at index 2. SwapRemove does
		this by moving the last value "E" over top of "B", and then trimming
		off "E" at the end of the array:
		```lua
		local t = {"A", "B", "C", "D", "E"}
		TableUtil.SwapRemove(t, 2) -- Remove "B"
		print(t) --> {"A", "E", "C", "D"}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function SwapRemove<T>(t: { T }, i: number)
		local n = #t
		t[i] = t[n]
		t[n] = nil
	end
	
	--[=[
		@within TableUtil
		@function SwapRemoveFirstValue
		@param tbl table -- Array
		@param v any -- Value to find
		@return number?
	
		Performs `table.find(tbl, v)` to find the index of the given
		value, and then performs `TableUtil.SwapRemove` on that index.
	
		```lua
		local t = {"A", "B", "C", "D", "E"}
		TableUtil.SwapRemoveFirstValue(t, "C")
		print(t) --> {"A", "B", "E", "D"}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function SwapRemoveFirstValue<T>(t: { T }, v: T): number?
		local index: number? = table.find(t, v)
		if index then
			SwapRemove(t, index)
		end
		return index
	end
	
	--[=[
		@within TableUtil
		@function Map
		@param tbl table
		@param predicate (value: any, key: any, tbl: table) -> newValue: any
		@return table
	
		Performs a map operation against the given table, which can be used to
		map new values based on the old values at given keys/indices.
	
		For example:
	
		```lua
		local t = {A = 10, B = 20, C = 30}
		local t2 = TableUtil.Map(t, function(value)
			return value * 2
		end)
		print(t2) --> {A = 20, B = 40, C = 60}
		```
	]=]
	local function Map<T, M>(t: { T }, f: (T, number, { T }) -> M): { M }
		assert(type(t) == "table", "First argument must be a table")
		assert(type(f) == "function", "Second argument must be a function")
		local newT = table.create(#t)
		for k, v in t do
			newT[k] = f(v, k, t)
		end
		return newT
	end
	
	--[=[
		@within TableUtil
		@function Filter
		@param tbl table
		@param predicate (value: any, key: any, tbl: table) -> keep: boolean
		@return table
	
		Performs a filter operation against the given table, which can be used to
		filter out unwanted values from the table.
	
		For example:
	
		```lua
		local t = {A = 10, B = 20, C = 30}
		local t2 = TableUtil.Filter(t, function(value, key)
			return value > 15
		end)
		print(t2) --> {B = 40, C = 60}
		```
	]=]
	local function Filter<T>(t: { T }, predicate: (T, any, { T }) -> boolean): { T }
		assert(type(t) == "table", "First argument must be a table")
		assert(type(predicate) == "function", "Second argument must be a function")
		local newT = table.create(#t)
		if #t > 0 then
			local n = 0
			for i, v in t do
				if predicate(v, i, t) then
					n += 1
					newT[n] = v
				end
			end
		else
			for k, v in t do
				if predicate(v, k, t) then
					newT[k] = v
				end
			end
		end
		return newT
	end
	
	--[=[
		@within TableUtil
		@function Reduce
		@param tbl table
		@param predicate (accumulator: any, value: any, index: any, tbl: table) -> result: any
		@return table
	
		Performs a reduce operation against the given table, which can be used to
		reduce the table into a single value. This could be used to sum up a table
		or transform all the values into a compound value of any kind.
	
		For example:
	
		```lua
		local t = {10, 20, 30, 40}
		local result = TableUtil.Reduce(t, function(accum, value)
			return accum + value
		end)
		print(result) --> 100
		```
	]=]
	local function Reduce<T, R>(t: { T }, predicate: (R, T, any, { T }) -> R, init: R): R
		assert(type(t) == "table", "First argument must be a table")
		assert(type(predicate) == "function", "Second argument must be a function")
		local result = init :: R
		if #t > 0 then
			local start = 1
			if init == nil then
				result = (t[1] :: any) :: R
				start = 2
			end
			for i = start, #t do
				result = predicate(result, t[i], i, t)
			end
		else
			local start = nil
			if init == nil then
				result = (next(t) :: any) :: R
				start = result
			end
			for k, v in next, t, start :: any? do
				result = predicate(result, v, k, t)
			end
		end
		return result
	end
	
	--[=[
		@within TableUtil
		@function Assign
		@param target table
		@param ... table
		@return table
	
		Copies all values of the given tables into the `target` table.
	
		```lua
		local t = {A = 10}
		local t2 = {B = 20}
		local t3 = {C = 30, D = 40}
		local newT = TableUtil.Assign(t, t2, t3)
		print(newT) --> {A = 10, B = 20, C = 30, D = 40}
		```
	]=]
	local function Assign<T>(target: { T }, ...: { any }): { T } & { any }
		local tbl = table.clone(target)
		for _, src in { ... } do
			for k, v in src do
				tbl[k] = v
			end
		end
		return tbl
	end
	
	--[=[
		@within TableUtil
		@function Extend
		@param target table
		@param extension table
		@return table
	
		Extends the target array with the extension array.
	
		```lua
		local t = {10, 20, 30}
		local t2 = {30, 40, 50}
		local tNew = TableUtil.Extend(t, t2)
		print(tNew) --> {10, 20, 30, 30, 40, 50}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function Extend<T, E>(target: { T }, extension: { E }): { T } & { E }
		local tbl = table.clone(target) :: { any }
		for _, v in extension do
			table.insert(tbl, v)
		end
		return tbl
	end
	
	--[=[
		@within TableUtil
		@function Reverse
		@param tbl table
		@return table
	
		Reverses the array.
	
		```lua
		local t = {1, 5, 10}
		local tReverse = TableUtil.Reverse(t)
		print(tReverse) --> {10, 5, 1}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function Reverse<T>(tbl: { T }): { T }
		local n = #tbl
		local tblRev = table.create(n)
		for i = 1, n do
			tblRev[i] = tbl[n - i + 1]
		end
		return tblRev
	end
	
	--[=[
		@within TableUtil
		@function Shuffle
		@param tbl table
		@param rngOverride Random?
		@return table
	
		Shuffles the table.
	
		```lua
		local t = {1, 2, 3, 4, 5, 6, 7, 8, 9}
		local shuffled = TableUtil.Shuffle(t)
		print(shuffled) --> e.g. {9, 4, 6, 7, 3, 1, 5, 8, 2}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function Shuffle<T>(tbl: { T }, rngOverride: Random?): { T }
		assert(type(tbl) == "table", "First argument must be a table")
		local shuffled = table.clone(tbl)
		local random = if typeof(rngOverride) == "Random" then rngOverride else rng
		for i = #tbl, 2, -1 do
			local j = random:NextInteger(1, i)
			shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
		end
		return shuffled
	end
	
	--[=[
		@within TableUtil
		@function Sample
		@param tbl table
		@param sampleSize number
		@param rngOverride Random?
		@return table
	
		Returns a random sample of the table.
	
		```lua
		local t = {1, 2, 3, 4, 5, 6, 7, 8, 9}
		local sample = TableUtil.Sample(t, 3)
		print(sample) --> e.g. {6, 2, 5}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function Sample<T>(tbl: { T }, size: number, rngOverride: Random?): { T }
		assert(type(tbl) == "table", "First argument must be a table")
		assert(type(size) == "number", "Second argument must be a number")
	
		-- If given table is empty, just return a new empty table:
		local len = #tbl
		if len == 0 then
			return {}
		end
	
		local shuffled = table.clone(tbl)
		local sample = table.create(size)
		local random = if typeof(rngOverride) == "Random" then rngOverride else rng
	
		-- Clamp sample size to be no larger than the given table size:
		size = math.clamp(size, 1, len)
	
		for i = 1, size do
			local j = random:NextInteger(i, len)
			shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
		end
	
		table.move(shuffled, 1, size, 1, sample)
	
		return sample
	end
	
	--[=[
		@within TableUtil
		@function Flat
		@param tbl table
		@param depth number?
		@return table
	
		Returns a new table where all sub-arrays have been
		bubbled up to the top. The depth at which the scan
		is performed is dictated by the `depth` parameter,
		which is set to `1` by default.
	
		```lua
		local t = {{10, 20}, {90, 100}, {30, 15}}
		local flat = TableUtil.Flat(t)
		print(flat) --> {10, 20, 90, 100, 30, 15}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function Flat<T>(tbl: { T }, depth: number?): { T }
		local maxDepth: number = if type(depth) == "number" then depth else 1
		local flatTbl = table.create(#tbl)
		local function Scan(t: { any }, d: number)
			for _, v in t do
				if type(v) == "table" and d < maxDepth then
					Scan(v, d + 1)
				else
					table.insert(flatTbl, v)
				end
			end
		end
		Scan(tbl, 0)
		return flatTbl
	end
	
	--[=[
		@within TableUtil
		@function FlatMap
		@param tbl table
		@param predicate (key: any, value: any, tbl: table) -> newValue: any
		@return table
	
		Calls `TableUtil.Map` on the given table and predicate, and then
		calls `TableUtil.Flat` on the result from the map operation.
	
		```lua
		local t = {10, 20, 30}
		local result = TableUtil.FlatMap(t, function(value)
			return {value, value * 2}
		end)
		print(result) --> {10, 20, 20, 40, 30, 60}
		```
	
		:::note Arrays only
		This function works on arrays, but not dictionaries.
		:::
	]=]
	local function FlatMap<T, M>(tbl: { T }, callback: (T, number, { T }) -> M): { M }
		return Flat(Map(tbl, callback))
	end
	
	--[=[
		@within TableUtil
		@function Keys
		@param tbl table
		@return table
	
		Returns an array with all the keys in the table.
	
		```lua
		local t = {A = 10, B = 20, C = 30}
		local keys = TableUtil.Keys(t)
		print(keys) --> {"A", "B", "C"}
		```
	
		:::caution Ordering
		The ordering of the keys is never guaranteed. If order is imperative, call
		`table.sort` on the resulting `keys` array.
		```lua
		local keys = TableUtil.Keys(t)
		table.sort(keys)
		```
		:::
	]=]
	local function Keys<K, V>(tbl: { [K]: V }): { K }
		local keys = table.create(#tbl)
		for k in tbl do
			table.insert(keys, k)
		end
		return keys
	end
	
	--[=[
		@within TableUtil
		@function Values
		@param tbl table
		@return table
	
		Returns an array with all the values in the table.
	
		```lua
		local t = {A = 10, B = 20, C = 30}
		local values = TableUtil.Values(t)
		print(values) --> {10, 20, 30}
		```
	
		:::caution Ordering
		The ordering of the values is never guaranteed. If order is imperative, call
		`table.sort` on the resulting `values` array.
		```lua
		local values = TableUtil.Values(t)
		table.sort(values)
		```
		:::
	]=]
	local function Values<K, V>(tbl: { [K]: V }): { V }
		local values = table.create(#tbl)
		for _, v in tbl do
			table.insert(values, v)
		end
		return values
	end
	
	--[=[
		@within TableUtil
		@function Find
		@param tbl table
		@param callback (value: any, index: any, tbl: table) -> boolean
		@return (value: any?, key: any?)
	
		Performs a linear scan across the table and calls `callback` on
		each item in the array. Returns the value and key of the first
		pair in which the callback returns `true`.
	
		```lua
		local t = {
			{Name = "Bob", Age = 20};
			{Name = "Jill", Age = 30};
			{Name = "Ann", Age = 25};
		}
	
		-- Find first person who has a name starting with J:
		local firstPersonWithJ = TableUtil.Find(t, function(person)
			return person.Name:sub(1, 1):lower() == "j"
		end)
	
		print(firstPersonWithJ) --> {Name = "Jill", Age = 30}
		```
	
		:::caution Dictionary Ordering
		While `Find` can also be used with dictionaries, dictionary ordering is never
		guaranteed, and thus the result could be different if there are more
		than one possible matches given the data and callback function.
		:::
	]=]
	local function Find<K, V>(tbl: { [K]: V }, callback: (V, K, { [K]: V }) -> boolean): (V?, K?)
		for k, v in tbl do
			if callback(v, k, tbl) then
				return v, k
			end
		end
		return nil, nil
	end
	
	--[=[
		@within TableUtil
		@function Every
		@param tbl table
		@param callback (value: any, index: any, tbl: table) -> boolean
		@return boolean
	
		Returns `true` if the `callback` also returns `true` for _every_
		item in the table.
	
		```lua
		local t = {10, 20, 40, 50, 60}
	
		local allAboveZero = TableUtil.Every(t, function(value)
			return value > 0
		end)
	
		print("All above zero:", allAboveZero) --> All above zero: true
		```
	]=]
	local function Every<K, V>(tbl: { [K]: V }, callback: (V, K, { [K]: V }) -> boolean): boolean
		for k, v in tbl do
			if not callback(v, k, tbl) then
				return false
			end
		end
		return true
	end
	
	--[=[
		@within TableUtil
		@function Some
		@param tbl table
		@param callback (value: any, index: any, tbl: table) -> boolean
		@return boolean
	
		Returns `true` if the `callback` also returns `true` for _at least
		one_ of the items in the table.
	
		```lua
		local t = {10, 20, 40, 50, 60}
	
		local someBelowTwenty = TableUtil.Some(t, function(value)
			return value < 20
		end)
	
		print("Some below twenty:", someBelowTwenty) --> Some below twenty: true
		```
	]=]
	local function Some<K, V>(tbl: { [K]: V }, callback: (V, K, { [K]: V }) -> boolean): boolean
		for k, v in tbl do
			if callback(v, k, tbl) then
				return true
			end
		end
		return false
	end
	
	--[=[
		@within TableUtil
		@function Truncate
		@param tbl table
		@param length number
		@return table
	
		Returns a new table truncated to the length of `length`. Any length
		equal or greater than the current length will simply return a
		shallow copy of the table.
	
		```lua
		local t = {10, 20, 30, 40, 50, 60, 70, 80}
		local tTruncated = TableUtil.Truncate(t, 3)
		print(tTruncated) --> {10, 20, 30}
		```
	]=]
	local function Truncate<T>(tbl: { T }, len: number): { T }
		local n = #tbl
		len = math.clamp(len, 1, n)
		return if len == n then table.clone(tbl) else table.move(tbl, 1, len, 1, table.create(len))
	end
	
	--[=[
		@within TableUtil
		@function Zip
		@param ... table
		@return (iter: (t: table, k: any) -> (key: any?, values: table?), tbl: table, startIndex: any?)
	
		Returns an iterator that can scan through multiple tables at the same time side-by-side, matching
		against shared keys/indices.
	
		```lua
		local t1 = {10, 20, 30, 40, 50}
		local t2 = {60, 70, 80, 90, 100}
	
		for key,values in TableUtil.Zip(t1, t2) do
			print(key, values)
		end
	
		--[[
			Outputs:
			1 {10, 60}
			2 {20, 70}
			3 {30, 80}
			4 {40, 90}
			5 {50, 100}
		--]]
		```
	]=]
	local function Zip(...: { [any]: any }): ((t: { any }, k: any) -> (any, any), { any }, any)
		assert(select("#", ...) > 0, "Must supply at least 1 table")
		local function ZipIteratorArray(all: { any }, k: number): (number?, { any }?)
			k += 1
			local values = {}
			for i, t in all do
				local v = t[k]
				if v ~= nil then
					values[i] = v
				else
					return nil, nil
				end
			end
			return k, values
		end
		local function ZipIteratorMap(all: { [any]: any }, k: any): (number?, { any }?)
			local values = {}
			for i, t in all do
				local v = next(t, k)
				if v ~= nil then
					values[i] = v
				else
					return nil, nil
				end
			end
			return k, values
		end
		local all = { ... }
		if #all[1] > 0 then
			return ZipIteratorArray, all, 0
		else
			return ZipIteratorMap, all, nil
		end
	end
	
	--[=[
		@within TableUtil
		@function Lock
		@param tbl table
		@return table
	
		Locks the table using `table.freeze`, as well as any
		nested tables within the given table. This will lock
		the whole deep structure of the table, disallowing any
		further modifications.
	
		```lua
		local tbl = {xyz = {abc = 32}}
		tbl.xyz.abc = 28 -- Works fine
		TableUtil.Lock(tbl)
		tbl.xyz.abc = 64 -- Will throw an error (cannot modify readonly table)
		```
	]=]
	local function Lock<T>(tbl: T): T
		local function Freeze(t: { [any]: any })
			for k, v in pairs(t) do
				if type(v) == "table" then
					t[k] = Freeze(v)
				end
			end
			return table.freeze(t)
		end
		return Freeze(tbl :: any)
	end
	
	--[=[
		@within TableUtil
		@function IsEmpty
		@param tbl table
		@return boolean
	
		Returns `true` if the given table is empty. This is
		simply performed by checking if `next(tbl)` is `nil`
		and works for both arrays and dictionaries. This is
		useful when needing to check if a table is empty but
		not knowing if it is an array or dictionary.
	
		```lua
		TableUtil.IsEmpty({}) -- true
		TableUtil.IsEmpty({"abc"}) -- false
		TableUtil.IsEmpty({abc = 32}) -- false
		```
	]=]
	local function IsEmpty(tbl: { any }): boolean
		return next(tbl) == nil
	end
	
	--[=[
		@within TableUtil
		@function EncodeJSON
		@param value any
		@return string
	
		Proxy for [`HttpService:JSONEncode`](https://developer.roblox.com/en-us/api-reference/function/HttpService/JSONEncode).
	]=]
	local function EncodeJSON(value: any): string
		return HttpService:JSONEncode(value)
	end
	
	--[=[
		@within TableUtil
		@function DecodeJSON
		@param value any
		@return string
	
		Proxy for [`HttpService:JSONDecode`](https://developer.roblox.com/en-us/api-reference/function/HttpService/JSONDecode).
	]=]
	local function DecodeJSON(str: string): any
		return HttpService:JSONDecode(str)
	end
	
	TableUtil.Copy = Copy
	TableUtil.Sync = Sync
	TableUtil.Reconcile = Reconcile
	TableUtil.SwapRemove = SwapRemove
	TableUtil.SwapRemoveFirstValue = SwapRemoveFirstValue
	TableUtil.Map = Map
	TableUtil.Filter = Filter
	TableUtil.Reduce = Reduce
	TableUtil.Assign = Assign
	TableUtil.Extend = Extend
	TableUtil.Reverse = Reverse
	TableUtil.Shuffle = Shuffle
	TableUtil.Sample = Sample
	TableUtil.Flat = Flat
	TableUtil.FlatMap = FlatMap
	TableUtil.Keys = Keys
	TableUtil.Values = Values
	TableUtil.Find = Find
	TableUtil.Every = Every
	TableUtil.Some = Some
	TableUtil.Truncate = Truncate
	TableUtil.Zip = Zip
	TableUtil.Lock = Lock
	TableUtil.IsEmpty = IsEmpty
	TableUtil.EncodeJSON = EncodeJSON
	TableUtil.DecodeJSON = DecodeJSON
	
	return TableUtil
	
end
Modules["task-queue"] = function(...)
	-- TaskQueue
	-- Stephen Leitnick
	-- November 20, 2021
	
	--[=[
		@class TaskQueue
		A queue that flushes all objects at the end of the current
		execution step. This works by scheduling all tasks with
		`task.defer`.
	
		A possible use-case is to batch all requests being sent through
		a RemoteEvent to help prevent calling it too many times on
		the same frame.
	
		```lua
		local bulletQueue = TaskQueue.new(function(bullets)
			bulletRemoteEvent:FireAllClients(bullets)
		end)
	
		-- Add 3 bullets. Because they're all added on the same
		-- execution step, they will all be grouped together on
		-- the next queue flush, which the above function will
		-- handle.
		bulletQueue:Add(someBullet)
		bulletQueue:Add(someBullet)
		bulletQueue:Add(someBullet)
		```
	]=]
	local TaskQueue = {}
	TaskQueue.__index = TaskQueue
	
	--[=[
		@param onFlush ({T}) -> ()
		@return TaskQueue<T>
		Constructs a new TaskQueue.
	]=]
	function TaskQueue.new<T>(onFlush: ({ T }) -> ())
		local self = setmetatable({}, TaskQueue)
	
		self._queue = {}
		self._flushing = false
		self._scheduled = nil
		self._onFlush = onFlush
	
		return self
	end
	
	--[=[
		@param object T
		Add an object to the queue.
	]=]
	function TaskQueue:Add<T>(object: T)
		table.insert(self._queue, object)
	
		if self._scheduled == nil then
			self._scheduled = task.defer(function()
				self._flushing = true
				self._onFlush(self._queue)
				table.clear(self._queue)
				self._flushing = false
				self._scheduled = nil
			end)
		end
	end
	
	--[=[
		Clears the TaskQueue. This will clear any tasks
		that were scheduled to be flushed on the current
		execution frame.
	
		```lua
		queue:Add(something1)
		queue:Add(something2)
		queue:Clear()
		```
	]=]
	function TaskQueue:Clear()
		if self._flushing then
			return
		end
	
		if self._scheduled ~= nil then
			task.cancel(self._scheduled)
			self._scheduled = nil
		end
	
		table.clear(self._queue)
	end
	
	--[=[
		Destroys the TaskQueue. Just an alias for `Clear()`.
	]=]
	function TaskQueue:Destroy()
		self:Clear()
	end
	
	return TaskQueue
	
end
Modules["tree"] = function(...)
	local DELIM = "/"
	
	local function FullNameToPath(instance: Instance): string
		return instance:GetFullName():gsub("%.", DELIM)
	end
	
	--[=[
		@class Tree
	]=]
	local Tree = {}
	
	--[=[
		Similar to FindFirstChild, with a few key differences:
		- An error is thrown if the instance is not found
		- A path to the instance can be provided, delimited by forward slashes (e.g. `Path/To/Child`)
		- Optionally, the instance's type can be asserted using `IsA`
	
		```lua
		-- Find "Child" directly under parent:
		local instance = Tree.Find(parent, "Child")
	
		-- Find "Child" descendant:
		local instance = Tree.Find(parent, "Path/To/Child")
	
		-- Find "Child" descendant and assert that it's a BasePart:
		local instance = Tree.Find(parent, "Path/To/Child", "BasePart") :: BasePart
		```
	]=]
	function Tree.Find(parent: Instance, path: string, assertIsA: string?): Instance
		local instance = parent
		local paths = path:split(DELIM)
	
		for _, p in paths do
			-- Error for empty path parts:
			if p == "" then
				error(`Invalid path: {path}`, 2)
			end
	
			instance = instance:FindFirstChild(p)
	
			-- Error if instance is not found:
			if instance == nil then
				error(`Failed to find {path} in {FullNameToPath(parent)}`, 2)
			end
		end
	
		-- Assert class type if argument is supplied:
		if assertIsA and not instance:IsA(assertIsA) then
			error(`Got class {instance.ClassName}; expected to be of type {assertIsA}`, 2)
		end
	
		return instance
	end
	
	--[=[
		Returns `true` if the instance is found. Similar to `Tree.Find`, except this returns `true|false`. No error is thrown unless the path is invalid.
	
		```lua
		-- Check if "Child" exists directly in `parent`:
		if Tree.Exists(parent, "Child") then ... end
		
		-- Check if "Child" descendant exists at `parent.Path.To.Child`:
		if Tree.Exists(parent, "Path/To/Child") then ... end
		
		-- Check if "Child" descendant exists at `parent.Path.To.Child` and is a BasePart:
		if Tree.Exists(parent, "Path/To/Child", "BasePart") then ... end
		```
	]=]
	function Tree.Exists(parent: Instance, path: string, assertIsA: string?): boolean
		local instance = parent
		local paths = path:split(DELIM)
	
		for _, p in paths do
			-- Error for empty path parts:
			if p == "" then
				error(`Invalid path: {path}`, 2)
			end
	
			instance = instance:FindFirstChild(p)
	
			if instance == nil then
				return false
			end
		end
	
		if assertIsA and not instance:IsA(assertIsA) then
			return false
		end
	
		return true
	end
	
	--[=[
		@yields
		Waits for the path to exist within the parent instance. Similar to `Tree.Find`, except `WaitForChild`
		is used internally. An optional `timeout` can be supplied, which is passed along to each call to
		`WaitForChild`.
	
		An error is thrown if the path fails to resolve. This will only happen if the path is invalid _or_ if
		the supplied timeout is reached.
	
		:::caution Indefinite Yield Possible
		If the `timeout` parameter is not supplied, then the internal call to `WaitForChild` will yield
		indefinitely until the child is found. It is good practice to supply a timeout parameter.
		:::
	
		```lua
		local child = Tree.Await(parent, "Path/To/Child", 30)
		```
	]=]
	function Tree.Await(parent: Instance, path: string, timeout: number?, assertIsA: string?): Instance
		local instance = parent
		local paths = path:split(DELIM)
	
		for _, p in paths do
			-- Error for empty path parts:
			if p == "" then
				error(`Invalid path: {path}`, 2)
			end
	
			instance = instance:WaitForChild(p, timeout)
	
			-- Error if instance is not found:
			if instance == nil then
				error(`Failed to await {path} in {FullNameToPath(parent)} (timeout reached)`, 2)
			end
		end
	
		-- Assert class type if argument is supplied:
		if assertIsA and not instance:IsA(assertIsA) then
			error(`Got class {instance.ClassName}; expected to be of type {assertIsA}`, 2)
		end
	
		return instance
	end
	
	return Tree
	
end
Modules["trove"] = function(...)
	--!strict
	
	local RunService = game:GetService("RunService")
	
	export type Trove = {
		Extend: (self: Trove) -> Trove,
		Clone: <T>(self: Trove, instance: T & Instance) -> T,
		Construct: <T, A...>(self: Trove, class: Constructable<T, A...>, A...) -> T,
		Connect: (
			self: Trove,
			signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
			fn: (...any) -> ...any
		) -> ConnectionLike | ConnectionLikeMetatable,
		BindToRenderStep: (self: Trove, name: string, priority: number, fn: (dt: number) -> ()) -> (),
		AddPromise: <T>(self: Trove, promise: (T & PromiseLike) | (T & PromiseLikeMetatable)) -> T,
		Add: <T>(self: Trove, object: T & Trackable, cleanupMethod: string?) -> T,
		Remove: <T>(self: Trove, object: T & Trackable) -> boolean,
		Pop: <T>(self: Trove, object: T & Trackable) -> boolean,
		Clean: (self: Trove) -> (),
		WrapClean: (self: Trove) -> () -> (),
		AttachToInstance: (self: Trove, instance: Instance) -> RBXScriptConnection,
		Destroy: (self: Trove) -> (),
	}
	
	type TroveInternal = Trove & {
		_objects: { any },
		_cleaning: boolean,
		_findAndRemoveFromObjects: (self: TroveInternal, object: any, cleanup: boolean) -> boolean,
		_cleanupObject: (self: TroveInternal, object: any, cleanupMethod: string?) -> (),
	}
	
	--[=[
		@within Trove
		@type Trackable Instance | RBXScriptConnection | ConnectionLike | ConnectLikeMetatable | PromiseLike | PromiseLikeMetatable | thread | ((...any) -> ...any) | Destroyable | DestroyableMetatable | DestroyableLowercase | DestroyableLowercaseMetatable | Disconnectable | DisconnectableMetatable | DisconnectableLowercase | DisconnectableLowercaseMetatable | SignalLike | SignalLikeMetatable
		Represents all trackable objects by Trove.
	]=]
	export type Trackable =
		| Instance
		| RBXScriptConnection
		| ConnectionLike
		| ConnectionLikeMetatable
		| PromiseLike
		| PromiseLikeMetatable
		| thread
		| ((...any) -> ...any)
		| Destroyable
		| DestroyableMetatable
		| DestroyableLowercase
		| DestroyableLowercaseMetatable
		| Disconnectable
		| DisconectableMetatable
		| DisconnectableLowercase
		| DisconnectableLowercaseMetatable
		| SignalLike
		| SignalLikeMetatable
	
	--[=[
		@within Trove
		@interface ConnectionLike
		.Connected boolean
		.Disconnect (self) -> ()
	]=]
	type ConnectionLike = {
		Connected: boolean,
		Disconnect: (self: ConnectionLike) -> (),
	}
	
	--[=[
		@within Trove
		@interface ConnectionLikeMetatable
		.Connected boolean
		.Disconnect (self) -> ()
		@tag Metatable
	]=]
	type ConnectionLikeMetatable = typeof(setmetatable(
		{},
		{} :: { Connected: boolean, Disconnect: (self: ConnectionLikeMetatable) -> () }
	))
	
	--[=[
		@within Trove
		@interface SignalLike
		.Connect (self, callback: (...any) -> ...any) -> ConnectionLike
		.Once (self, callback: (...any) -> ...any) -> ConnectionLike
	]=]
	type SignalLike = {
		Connect: (self: SignalLike, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
		Once: (self: SignalLike, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
	}
	
	--[=[
		@within Trove
		@interface SignalLikeMetatable
		.Connect (self, callback: (...any) -> ...any) -> ConnectionLike
		.Once (self, callback: (...any) -> ...any) -> ConnectionLike
		@tag Metatable
	]=]
	type SignalLikeMetatable = typeof(setmetatable(
		{},
		{} :: {
			Connect: (self: SignalLikeMetatable, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
			Once: (self: SignalLikeMetatable, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
		}
	))
	
	--[=[
		@within Trove
		@interface PromiseLike
		.getStatus (self) -> string
		.finally (self, callback: (...any) -> ...any) -> PromiseLike
		.cancel (self) -> ()
	]=]
	type PromiseLike = {
		getStatus: (self: PromiseLike) -> string,
		finally: (self: PromiseLike, callback: (...any) -> ...any) -> PromiseLike | PromiseLikeMetatable,
		cancel: (self: PromiseLike) -> (),
	}
	
	--[=[
		@within Trove
		@interface PromiseLikeMetatable
		.getStatus (self) -> string
		.finally (self, callback: (...any) -> ...any) -> PromiseLike
		.cancel (self) -> ()
		@tag Metatable
	]=]
	type PromiseLikeMetatable = typeof(setmetatable(
		{},
		{} :: {
			getStatus: (self: any) -> string,
			finally: (self: PromiseLikeMetatable, callback: (...any) -> ...any) -> PromiseLike | PromiseLikeMetatable,
			cancel: (self: PromiseLikeMetatable) -> (),
		}
	))
	
	--[=[
		@within Trove
		@type Constructable { new: (A...) -> T } | (A...) -> T
	]=]
	type Constructable<T, A...> = { new: (A...) -> T } | (A...) -> T
	
	--[=[
		@within Trove
		@interface Destroyable
		.Destroy (self) -> ()
	]=]
	type Destroyable = {
		Destroy: (self: Destroyable) -> (),
	}
	
	--[=[
		@within Trove
		@interface DestroyableMetatable
		.Destroy (self) -> ()
		@tag Metatable
	]=]
	type DestroyableMetatable = typeof(setmetatable({}, {} :: { Destroy: (self: DestroyableMetatable) -> () }))
	
	--[=[
		@within Trove
		@interface DestroyableLowercase
		.destroy (self) -> ()
	]=]
	type DestroyableLowercase = {
		destroy: (self: DestroyableLowercase) -> (),
	}
	
	--[=[
		@within Trove
		@interface DestroyableLowercaseMetatable
		.destroy (self) -> ()
		@tag Metatable
	]=]
	type DestroyableLowercaseMetatable = typeof(setmetatable(
		{},
		{} :: { destroy: (self: DestroyableLowercaseMetatable) -> () }
	))
	
	--[=[
		@within Trove
		@interface Disconnectable
		.Disconnect (self) -> ()
	]=]
	type Disconnectable = {
		Disconnect: (self: Disconnectable) -> (),
	}
	
	--[=[
		@within Trove
		@interface DisconectableMetatable
		.Disconnect (self) -> ()
		@tag Metatable
	]=]
	type DisconectableMetatable = typeof(setmetatable({}, {} :: { Disconnect: (self: DisconectableMetatable) -> () }))
	
	--[=[
		@within Trove
		@interface DisconnectableLowercase
		.disconnect (self) -> ()
	]=]
	type DisconnectableLowercase = {
		disconnect: (self: DisconnectableLowercase) -> (),
	}
	
	--[=[
		@within Trove
		@interface DisconnectableLowercaseMetatable
		.disconnect (self) -> ()
		@tag Metatable
	]=]
	type DisconnectableLowercaseMetatable = typeof(setmetatable(
		{},
		{} :: { disconnect: (self: DisconnectableLowercaseMetatable) -> () }
	))
	
	local FN_MARKER = newproxy()
	local THREAD_MARKER = newproxy()
	local GENERIC_OBJECT_CLEANUP_METHODS = table.freeze({ "Destroy", "Disconnect", "destroy", "disconnect" })
	
	local function getObjectCleanupFunction(object: any, cleanupMethod: string?)
		local t = typeof(object)
	
		if t == "function" then
			return FN_MARKER
		elseif t == "thread" then
			return THREAD_MARKER
		end
	
		if cleanupMethod then
			return cleanupMethod
		end
	
		if t == "Instance" then
			return "Destroy"
		elseif t == "RBXScriptConnection" then
			return "Disconnect"
		elseif t == "table" then
			for _, genericCleanupMethod in GENERIC_OBJECT_CLEANUP_METHODS do
				if typeof(object[genericCleanupMethod]) == "function" then
					return genericCleanupMethod
				end
			end
		end
	
		error(`failed to get cleanup function for object {t}: {object}`, 3)
	end
	
	local function assertPromiseLike(object: any)
		if
			typeof(object) ~= "table"
			or typeof(object.getStatus) ~= "function"
			or typeof(object.finally) ~= "function"
			or typeof(object.cancel) ~= "function"
		then
			error("did not receive a promise as an argument", 3)
		end
	end
	
	local function assertSignalLike(object: any)
		if
			typeof(object) ~= "RBXScriptSignal"
			and (typeof(object) ~= "table" or typeof(object.Connect) ~= "function" or typeof(object.Once) ~= "function")
		then
			error("did not receive a signal as an argument", 3)
		end
	end
	
	--[=[
		@class Trove
		A Trove is helpful for tracking any sort of object during
		runtime that needs to get cleaned up at some point.
	]=]
	local Trove = {}
	Trove.__index = Trove
	
	--[=[
		@return Trove
		Constructs a Trove object.
	
		```lua
		local trove = Trove.new()
		```
	]=]
	function Trove.new(): Trove
		local self = setmetatable({}, Trove)
	
		self._objects = {}
		self._cleaning = false
	
		return (self :: any) :: Trove
	end
	
	--[=[
		@method Add
		@within Trove
		@param object any -- Object to track
		@param cleanupMethod string? -- Optional cleanup name override
		@return object: any
		Adds an object to the trove. Once the trove is cleaned or
		destroyed, the object will also be cleaned up.
	
		The following types are accepted (e.g. `typeof(object)`):
	
		| Type | Cleanup |
		| ---- | ------- |
		| `Instance` | `object:Destroy()` |
		| `RBXScriptConnection` | `object:Disconnect()` |
		| `function` | `object()` |
		| `thread` | `task.cancel(object)` |
		| `table` | `object:Destroy()` _or_ `object:Disconnect()` _or_ `object:destroy()` _or_ `object:disconnect()` |
		| `table` with `cleanupMethod` | `object:<cleanupMethod>()` |
	
		Returns the object added.
	
		```lua
		-- Add a part to the trove, then destroy the trove,
		-- which will also destroy the part:
		local part = Instance.new("Part")
		trove:Add(part)
		trove:Destroy()
	
		-- Add a function to the trove:
		trove:Add(function()
			print("Cleanup!")
		end)
		trove:Destroy()
	
		-- Standard cleanup from table:
		local tbl = {}
		function tbl:Destroy()
			print("Cleanup")
		end
		trove:Add(tbl)
	
		-- Custom cleanup from table:
		local tbl = {}
		function tbl:DoSomething()
			print("Do something on cleanup")
		end
		trove:Add(tbl, "DoSomething")
		```
	]=]
	function Trove.Add(self: TroveInternal, object: Trackable, cleanupMethod: string?): any
		if self._cleaning then
			error("cannot call trove:Add() while cleaning", 2)
		end
	
		local cleanup = getObjectCleanupFunction(object, cleanupMethod)
		table.insert(self._objects, { object, cleanup })
	
		return object
	end
	
	--[=[
		@method Clone
		@within Trove
		@return Instance
		Clones the given instance and adds it to the trove. Shorthand for
		`trove:Add(instance:Clone())`.
	
		```lua
		local clonedPart = trove:Clone(somePart)
		```
	]=]
	function Trove.Clone(self: TroveInternal, instance: Instance): Instance
		if self._cleaning then
			error("cannot call trove:Clone() while cleaning", 2)
		end
	
		return self:Add(instance:Clone())
	end
	
	--[=[
		@method Construct
		@within Trove
		@param class { new(Args...) -> T } | (Args...) -> T
		@param ... Args...
		@return T
		Constructs a new object from either the
		table or function given.
	
		If a table is given, the table's `new`
		function will be called with the given
		arguments.
	
		If a function is given, the function will
		be called with the given arguments.
	
		The result from either of the two options
		will be added to the trove.
	
		This is shorthand for `trove:Add(SomeClass.new(...))`
		and `trove:Add(SomeFunction(...))`.
	
		```lua
		local Signal = require(somewhere.Signal)
	
		-- All of these are identical:
		local s = trove:Construct(Signal)
		local s = trove:Construct(Signal.new)
		local s = trove:Construct(function() return Signal.new() end)
		local s = trove:Add(Signal.new())
	
		-- Even Roblox instances can be created:
		local part = trove:Construct(Instance, "Part")
		```
	]=]
	function Trove.Construct<T, A...>(self: TroveInternal, class: Constructable<T, A...>, ...: A...)
		if self._cleaning then
			error("Cannot call trove:Construct() while cleaning", 2)
		end
	
		local object = nil
		local t = type(class)
		if t == "table" then
			object = (class :: any).new(...)
		elseif t == "function" then
			object = (class :: any)(...)
		end
	
		return self:Add(object)
	end
	
	--[=[
		@method Connect
		@within Trove
		@param signal RBXScriptSignal
		@param fn (...: any) -> ()
		@return RBXScriptConnection
		Connects the function to the signal, adds the connection
		to the trove, and then returns the connection.
	
		This is shorthand for `trove:Add(signal:Connect(fn))`.
	
		```lua
		trove:Connect(workspace.ChildAdded, function(instance)
			print(instance.Name .. " added to workspace")
		end)
		```
	]=]
	function Trove.Connect(
		self: TroveInternal,
		signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
		fn: (...any) -> ...any
	)
		if self._cleaning then
			error("Cannot call trove:Connect() while cleaning", 2)
		end
		assertSignalLike(signal)
	
		local confirmedSignal = signal :: SignalLike
	
		return self:Add(confirmedSignal:Connect(fn))
	end
	
	--[=[
		@method Once
		@within Trove
		@param signal RBXScriptSignal
		@param fn (...: any) -> ()
		@return RBXScriptConnection
		Connects the function to the signal using the `Once`
		method, adds the connection to the trove, and then
		returns the connection.
	
		This is shorthand for `trove:Add(signal:Once(fn))`.
	
		```lua
		trove:Connect(workspace.ChildAdded, function(instance)
			print(instance.Name .. " added to workspace")
		end)
		```
	]=]
	function Trove.Once(
		self: TroveInternal,
		signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
		fn: (...any) -> ...any
	)
		if self._cleaning then
			error("Cannot call trove:Connect() while cleaning", 2)
		end
		assertSignalLike(signal)
	
		local confirmedSignal = signal :: SignalLike
	
		local conn
		conn = confirmedSignal:Once(function(...)
			fn(...)
			self:Pop(conn)
		end)
	
		return self:Add(conn)
	end
	
	--[=[
		@method BindToRenderStep
		@within Trove
		@param name string
		@param priority number
		@param fn (dt: number) -> ()
		Calls `RunService:BindToRenderStep` and registers a function in the
		trove that will call `RunService:UnbindFromRenderStep` on cleanup.
	
		```lua
		trove:BindToRenderStep("Test", Enum.RenderPriority.Last.Value, function(dt)
			-- Do something
		end)
		```
	]=]
	function Trove.BindToRenderStep(self: TroveInternal, name: string, priority: number, fn: (dt: number) -> ())
		if self._cleaning then
			error("cannot call trove:BindToRenderStep() while cleaning", 2)
		end
	
		RunService:BindToRenderStep(name, priority, fn)
	
		self:Add(function()
			RunService:UnbindFromRenderStep(name)
		end)
	end
	
	--[=[
		@method AddPromise
		@within Trove
		@param promise Promise
		@return Promise
		Gives the promise to the trove, which will cancel the promise if the trove is cleaned up or if the promise
		is removed. The exact promise is returned, thus allowing chaining.
	
		```lua
		trove:AddPromise(doSomethingThatReturnsAPromise())
			:andThen(function()
				print("Done")
			end)
		-- Will cancel the above promise (assuming it didn't resolve immediately)
		trove:Clean()
	
		local p = trove:AddPromise(doSomethingThatReturnsAPromise())
		-- Will also cancel the promise
		trove:Remove(p)
		```
	
		:::caution Promise v4 Only
		This is only compatible with the [roblox-lua-promise](https://eryn.io/roblox-lua-promise/) library, version 4.
		:::
	]=]
	function Trove.AddPromise(self: TroveInternal, promise: PromiseLike | PromiseLikeMetatable)
		if self._cleaning then
			error("cannot call trove:AddPromise() while cleaning", 2)
		end
		assertPromiseLike(promise)
		local confirmedPromise = promise :: PromiseLike
	
		if confirmedPromise:getStatus() == "Started" then
			confirmedPromise:finally(function()
				if self._cleaning then
					return
				end
				self:_findAndRemoveFromObjects(confirmedPromise, false)
			end)
	
			self:Add(confirmedPromise, "cancel")
		end
	
		return confirmedPromise
	end
	
	--[=[
		@method Remove
		@within Trove
		@param object any
		Removes the object from the Trove and cleans it up. To remove without
		cleaning, use the `Pop` method instead.
	
		```lua
		local part = Instance.new("Part")
		trove:Add(part)
		trove:Remove(part) -- Part is destroyed
		```
	]=]
	function Trove.Remove(self: TroveInternal, object: Trackable): boolean
		if self._cleaning then
			error("cannot call trove:Remove() while cleaning", 2)
		end
	
		return self:_findAndRemoveFromObjects(object, true)
	end
	
	--[=[
		@method Pop
		@within Trove
		@param object any
		Removes the object from the Trove, but does _not_ clean it up. To
		clean up the object on removal, use the `Remove` method instead.
	
		```lua
		local part = Instance.new("Part")
		trove:Add(part)
		trove:Pop(part)
		trove:Clean() -- Part is NOT destroyed
		```
	]=]
	function Trove.Pop(self: TroveInternal, object: Trackable): boolean
		if self._cleaning then
			error("cannot call trove:Pop() while cleaning", 2)
		end
	
		return self:_findAndRemoveFromObjects(object, false)
	end
	
	--[=[
		@method Extend
		@within Trove
		@return Trove
		Creates and adds another trove to itself. This is just shorthand
		for `trove:Construct(Trove)`. This is useful for contexts where
		the trove object is present, but the class itself isn't.
	
		:::note
		This does _not_ clone the trove. In other words, the objects in the
		trove are not given to the new constructed trove. This is simply to
		construct a new Trove and add it as an object to track.
		:::
	
		```lua
		local trove = Trove.new()
		local subTrove = trove:Extend()
	
		trove:Clean() -- Cleans up the subTrove too
		```
	]=]
	function Trove.Extend(self: TroveInternal)
		if self._cleaning then
			error("cannot call trove:Extend() while cleaning", 2)
		end
	
		return self:Construct(Trove)
	end
	
	--[=[
		@method Clean
		@within Trove
		Cleans up all objects in the trove. This is
		similar to calling `Remove` on each object
		within the trove. The ordering of the objects
		removed is _not_ guaranteed.
	
		```lua
		trove:Clean()
		```
	]=]
	function Trove.Clean(self: TroveInternal)
		if self._cleaning then
			return
		end
	
		self._cleaning = true
	
		for _, obj in self._objects do
			self:_cleanupObject(obj[1], obj[2])
		end
	
		table.clear(self._objects)
		self._cleaning = false
	end
	
	--[=[
		@method WrapClean
		@within Trove
		Returns a function that wraps the trove's `Clean()`
		method. Calling the returned function will clean up
		the trove.
	
		This is often useful in contexts where functions
		are the primary mode for cleaning up an environment,
		such as in many "observer" patterns.
	
		```lua
		local cleanup = trove:WrapClean()
	
		-- Sometime later...
		cleanup()
		```
	
		```lua
		-- Common observer pattern example:
		someObserver(function()
			local trove = Trove.new()
			-- Foo
			return trove:WrapClean()
		end)
		```
	]=]
	function Trove.WrapClean(self: TroveInternal)
		return function()
			self:Clean()
		end
	end
	
	function Trove._findAndRemoveFromObjects(self: TroveInternal, object: any, cleanup: boolean): boolean
		local objects = self._objects
	
		for i, obj in objects do
			if obj[1] == object then
				local n = #objects
				objects[i] = objects[n]
				objects[n] = nil
	
				if cleanup then
					self:_cleanupObject(obj[1], obj[2])
				end
	
				return true
			end
		end
	
		return false
	end
	
	function Trove._cleanupObject(_self: TroveInternal, object: any, cleanupMethod: string?)
		if cleanupMethod == FN_MARKER then
			task.spawn(object)
		elseif cleanupMethod == THREAD_MARKER then
			pcall(task.cancel, object)
		else
			object[cleanupMethod](object)
		end
	end
	
	--[=[
		@method AttachToInstance
		@within Trove
		@param instance Instance
		@return RBXScriptConnection
		Attaches the trove to a Roblox instance. Once this
		instance is removed from the game (parent or ancestor's
		parent set to `nil`), the trove will automatically
		clean up.
	
		This inverses the ownership of the Trove object, and should
		only be used when necessary. In other words, the attached
		instance dictates when the trove is cleaned up, rather than
		the trove dictating the cleanup of the instance.
	
		:::caution
		Will throw an error if `instance` is not a descendant
		of the game hierarchy.
		:::
	
		```lua
		trove:AttachToInstance(somePart)
		trove:Add(function()
			print("Cleaned")
		end)
	
		-- Destroying the part will cause the trove to clean up, thus "Cleaned" printed:
		somePart:Destroy()
		```
	]=]
	function Trove.AttachToInstance(self: TroveInternal, instance: Instance)
		if self._cleaning then
			error("cannot call trove:AttachToInstance() while cleaning", 2)
		elseif not instance:IsDescendantOf(game) then
			error("instance is not a descendant of the game hierarchy", 2)
		end
	
		return self:Connect(instance.Destroying, function()
			self:Destroy()
		end)
	end
	
	--[=[
		@method Destroy
		@within Trove
		Alias for `trove:Clean()`.
	
		```lua
		trove:Destroy()
		```
	]=]
	function Trove.Destroy(self: TroveInternal)
		self:Clean()
	end
	
	return {
		new = Trove.new,
	}
	
end
Modules["typed-remote"] = function(...)
	--!strict
	
	type Signal<T...> = {
		Connect: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
		ConnectParallel: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
		Once: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
		Wait: (self: Signal<T...>) -> T...,
	}
	
	type PlayerSignal<T...> = {
		Connect: (self: PlayerSignal<T...>, fn: (player: Player, T...) -> ()) -> RBXScriptConnection,
		ConnectParallel: (self: PlayerSignal<T...>, fn: (player: Player, T...) -> ()) -> RBXScriptConnection,
		Once: (self: PlayerSignal<T...>, fn: (player: Player, T...) -> ()) -> RBXScriptConnection,
		Wait: (self: PlayerSignal<T...>) -> (Player, T...),
	}
	
	--[=[
		@within TypedRemote
		@interface Event<T...>
		.OnClientEvent Signal<T...>,
		.OnServerEvent PlayerSignal<T...>,
		.FireClient (self: Event<T...>, player: Player, T...) -> (),
		.FireAllClients (self: Event<T...>, T...) -> (),
		.FireServer (self: Event<T...>, T...) -> (),
	]=]
	export type Event<T... = ()> = Instance & {
		OnClientEvent: Signal<T...>,
		OnServerEvent: PlayerSignal<T...>,
		FireClient: (self: Event<T...>, player: Player, T...) -> (),
		FireAllClients: (self: Event<T...>, T...) -> (),
		FireServer: (self: Event<T...>, T...) -> (),
	}
	
	--[=[
		@within TypedRemote
		@interface UnreliableEvent<T...>
		.OnClientEvent Signal<T...>,
		.OnServerEvent PlayerSignal<T...>,
		.FireClient (self: Event<T...>, player: Player, T...) -> (),
		.FireAllClients (self: Event<T...>, T...) -> (),
		.FireServer (self: Event<T...>, T...) -> (),
	]=]
	export type UnreliableEvent<T... = ()> = Event<T...>
	
	--[=[
		@within TypedRemote
		@interface Function<T..., R...>
		.InvokeServer (self: Function<T..., R...>, T...) -> R...,
		.OnServerInvoke (player: Player, T...) -> R...,
	]=]
	export type Function<T... = (), R... = ()> = Instance & {
		InvokeServer: (self: Function<T..., R...>, T...) -> R...,
		OnServerInvoke: (player: Player, T...) -> R...,
	}
	
	type CreatorFn<T> = (name: string) -> T
	
	const IS_SERVER = game:GetService("RunService"):IsServer()
	
	--[=[
		@class TypedRemote
	
		Simple networking package that helps create typed RemoteEvents and RemoteFunctions.
	
		```lua
		-- ReplicatedStorage.Network (ModuleScript)
	
		const TypedRemote = require(ReplicatedStorage.Packages.TypedRemote)
	
		-- Get the RF, RE and URE instance creators, which create RemoteFunctions/RemoteEvents/UnreliableRemoteEvents
		-- within the given parent (the script by default):
		const RF, RE, URE = TypedRemote.parent()
	
		-- Define network table:
		return {
			-- RemoteFunction that takes two arguments (boolean, string) and returns a number:
			MyFunc = RF<<(boolean, string), (number)>>("MyFunc"),
	
			-- RemoteEvent that takes two arguments - a string and a number:
			MyEvent = RE<<(string, number)>>("MyEvent"),
	
			-- UnreliableRemoteEvent that takes two arguments - a string and a number:
			MyUnreliableEvent = URE<<(string, number)>>("MyUnreliableEvent"),
		}
		```
	
		```lua
		-- Example usage of the above Network module:
	
		const Network = require(ReplicatedStorage.Network)
	
		-- If you type this out, intellisense will help with what the function signature should be:
		Network.MyEvent.OnClientEvent:Connect(function(player, str, num)
			-- Foo
		end)
		```
	
		In most cases, the `TypedRemote.parent()` function will be used to create the memoized
		RemoteFunction and RemoteEvent builder functions. From there, call the given functions
		with the desired name per remote.
	
		The `TypedRemote.func` and `TypedRemote.event` functions can also be used, but the
		parent must be supplied to each call, hence the helpful `parent()` memoizer.
	]=]
	const TypedRemote = {}
	
	--[=[
		@return ((name: string) -> RemoteFunction, (name: string) -> RemoteEvent)
	
		Creates a memoized version of the `func` and `event` functions that include the `parent`
		in each call.
	
		```lua
		-- Create RF and RE functions that use the current script as the instance parent:
		const RF, RE = TypedRemote.parent(script)
	
		const remoteFunc = RF("RemoteFunc")
		```
	]=]
	function TypedRemote.parent(parent: Instance?): (
		<T..., R...>(name: string) -> Function<T..., R...>,
		<T...>(name: string) -> Event<T...>,
		<T...>(name: string) -> UnreliableEvent<T...>
	)
		return function<T..., R...>(name: string): Function<T..., R...>
			return TypedRemote.func(name, parent) :: Function<T..., R...>
		end, function<T...>(name: string): Event<T...>
			return TypedRemote.event(name, parent) :: Event<T...>
		end, function<T...>(name: string): UnreliableEvent<T...>
			return TypedRemote.unreliableEvent(name, parent) :: UnreliableEvent<T...>
		end
	end
	
	--[=[
		Creates a RemoteFunction with `name` and parents it inside of `parent`.
		
		If the `parent` argument is not included or is `nil`, then it defaults to the parent of
		this TypedRemote ModuleScript.
	]=]
	function TypedRemote.func<T..., R...>(name: string, parent: Instance?): Function<T..., R...>
		local rf: RemoteFunction
		if IS_SERVER then
			rf = Instance.new("RemoteFunction")
			rf.Name = name
			rf.Parent = if parent then parent else script
		else
			rf = ((if parent then parent else script) :: Instance):WaitForChild(name) :: RemoteFunction
			assert(rf:IsA("RemoteFunction"), "expected remote function")
		end
		return rf :: Function<T..., R...>
	end
	
	--[=[
		Creates a RemoteEvent with `name` and parents it inside of `parent`.
		
		If the `parent` argument is not included or is `nil`, then it defaults to the parent of
		this TypedRemote ModuleScript.
	]=]
	function TypedRemote.event<T...>(name: string, parent: Instance?): Event<T...>
		local re: RemoteEvent
		if IS_SERVER then
			re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = if parent then parent else script
		else
			re = ((if parent then parent else script) :: Instance):WaitForChild(name) :: RemoteEvent
			assert(re:IsA("RemoteEvent"), "expected remote event")
		end
		return re :: Event<T...>
	end
	
	--[=[
		Creates an UnreliableRemoteEvent with `name` and parents it inside of `parent`.
		
		If the `parent` argument is not included or is `nil`, then it defaults to the parent of
		this TypedRemote ModuleScript.
	]=]
	function TypedRemote.unreliableEvent<T...>(name: string, parent: Instance?): UnreliableEvent<T...>
		local ure: UnreliableRemoteEvent
		if IS_SERVER then
			ure = Instance.new("UnreliableRemoteEvent")
			ure.Name = name
			ure.Parent = if parent then parent else script
		else
			ure = ((if parent then parent else script) :: Instance):WaitForChild(name) :: UnreliableRemoteEvent
			assert(ure:IsA("UnreliableRemoteEvent"), "expected unreliable remote event")
		end
		return ure :: UnreliableEvent<T...>
	end
	
	table.freeze(TypedRemote)
	
	return TypedRemote
	
end
Modules["scheduler"] = function(...)
	--[[
		Scheduler: the multitask core of a hub. One tick loop starts, stops and queues tasks.
	
		local scheduler = Scheduler.new(hub)
		scheduler:Register({ Name = "AutoFarm", Thread = true, Run = function(ctx) ... end })
		scheduler:Start()
	
		A task is enabled while hub.Settings[Name] == true, or while Enabled(hub) returns true.
		Three errors in a row turn a task off; it re-arms once its gate has gone off and on again.
	
		Task definition
		  Name       string     unique; also the settings key that switches the task on
		  Run        function   Run(ctx): called every tick, or once on its own thread when Thread is set
		  Thread     boolean?   Run owns a thread and ctx.Trove; loop with `while not ctx.Cancelled() do`
		  Title      string?    name shown by a UI that lists the task
		  Group      string?    tasks of a group take turns; only tasks with a Group are listed by :Groups()
		  Exclusive  boolean?   true: queued in its group (the highest Priority that is Ready runs, the rest wait)
		                        false or omitted: independent until the user turns Interruptible on
		  Priority   number?    higher wins, any number; default 1
		  Ready      function?  Ready(hub): queued tasks only. false = nothing to do now, so lower priorities
		                        run until it has work again (it then interrupts them)
		  Enabled    function?  Enabled(hub): replaces the settings gate
		  Server     string?    only runs while hub.SERVER is this name
	
		ctx = { Hub, Settings, Name, Trove, Cancelled() }
	
		The user's overrides live in hub.Settings: "Priority:<Name>" (number), "Interruptible:<Name>" (boolean).
	
		Host: the table handed to Scheduler.new
		  Settings   indexable store; written only to switch a task off after repeated errors
		  Trove      root trove; every running task gets Trove:Extend()
		  Signal     Signal class; Signal.new() backs the events below
		  SERVER     string?, see Server
	
		Events (Connect / Once)
		  StateChanged()                    a State entry changed
		  Starting()                        Start() was called: every task is registered by now
		  TaskDisabled(name, strikes, err)  a task was turned off after repeated errors
	
		State[name] is "running", "queued", "idle", "off" or "disabled".
	]]
	
	local MAX_STRIKES = 3
	local HEALTHY_SECONDS = 10 -- a thread alive this long resets its error strikes
	
	local Scheduler = {}
	Scheduler.__index = Scheduler
	
	---Create a scheduler for a host (the header lists what the host provides).
	function Scheduler.new(hub: any)
		assert(
			type(hub) == "table" and hub.Settings and hub.Trove and hub.Signal,
			"Scheduler.new(hub): the hub needs Settings, Trove and Signal"
		)
		return setmetatable({
			Hub = hub,
			Tasks = {}, -- name -> def
			Order = {}, -- names in registration order (tick order)
			Active = {}, -- name -> def (enabled right now)
			Strikes = {}, -- name -> consecutive error count
			Disabled = {}, -- name -> true after MAX_STRIKES, until its gate turns off again
			Interval = 0, -- seconds between ticks (0 = every frame)
			State = {}, -- name -> "running" | "queued" | "idle" | "off" | "disabled"
			StateChanged = hub.Signal.new(),
			Starting = hub.Signal.new(),
			TaskDisabled = hub.Signal.new(),
			_nextState = {},
			_started = false,
		}, Scheduler)
	end
	
	-- ── registry ────────────────────────────────────────────────────────────────
	
	---Add a task. Register everything before Start() so a UI listing the tasks sees it.
	function Scheduler:Register(def: any)
		assert(
			type(def) == "table" and type(def.Name) == "string" and type(def.Run) == "function",
			"Scheduler:Register{ Name = string, Run = function, ... }"
		)
		if self.Tasks[def.Name] then
			error(("[Scheduler] duplicate task '%s'"):format(def.Name), 2)
		end
		def._listed = def.Group ~= nil -- only tasks that declared a Group are listed
		def.Group = def.Group or def.Name
		def.Priority = def.Priority or 1
		def._priorityKey = "Priority:" .. def.Name
		def._interruptKey = "Interruptible:" .. def.Name
		self.Tasks[def.Name] = def
		self.Disabled[def.Name] = nil
		table.insert(self.Order, def.Name)
	end
	
	---Stop a task and forget it.
	function Scheduler:Unregister(name: string)
		self:_stop(name)
		self.Tasks[name] = nil
		self.Disabled[name] = nil
		self.State[name] = nil
		local index = table.find(self.Order, name)
		if index then
			table.remove(self.Order, index)
		end
	end
	
	---The user's value from the Priority tab wins over the Priority the task shipped with.
	function Scheduler:GetPriority(def: any): number
		local value = self.Hub.Settings[def._priorityKey]
		return type(value) == "number" and value or def.Priority
	end
	
	---Queued tasks take part in their group's priority queue; the Interruptible switch overrides the def.
	function Scheduler:IsExclusive(def: any): boolean
		local value = self.Hub.Settings[def._interruptKey]
		if type(value) == "boolean" then
			return value
		end
		return def.Exclusive == true
	end
	
	---Tasks that declared a Group, per group ({ Name, Tasks }), each group highest priority first.
	function Scheduler:Groups(): { any }
		local byName: { [string]: { any } } = {}
		local names = {}
		for _, name in ipairs(self.Order) do
			local def = self.Tasks[name]
			if def._listed and (def.Server == nil or def.Server == self.Hub.SERVER) then
				if not byName[def.Group] then
					byName[def.Group] = {}
					table.insert(names, def.Group)
				end
				table.insert(byName[def.Group], def)
			end
		end
		table.sort(names)
	
		local groups = {}
		for _, groupName in names do
			local tasks = byName[groupName]
			local position = {}
			for index, def in tasks do
				position[def] = index
			end
			table.sort(tasks, function(a, b)
				local priorityA, priorityB = self:GetPriority(a), self:GetPriority(b)
				if priorityA ~= priorityB then
					return priorityA > priorityB
				end
				return position[a] < position[b] -- table.sort is not stable
			end)
			table.insert(groups, { Name = groupName, Tasks = tasks })
		end
		return groups
	end
	
	-- ── gates ───────────────────────────────────────────────────────────────────
	
	-- is the task switched on (and meant for this server)?
	function Scheduler:_gate(def: any): boolean
		if def.Server ~= nil and def.Server ~= self.Hub.SERVER then
			return false
		end
		if def.Enabled == nil then
			return self.Hub.Settings[def.Name] == true
		end
		local ok, enabled = pcall(def.Enabled, self.Hub)
		if not ok then
			-- retried every tick: warn once when it starts failing, not 60 times a second
			if not def._gateFailed then
				def._gateFailed = true
				warn(("[Scheduler] gate for '%s' errored: %s"):format(def.Name, tostring(enabled)))
			end
			return false
		end
		def._gateFailed = nil
		return enabled and true or false
	end
	
	-- a queued task with a Ready predicate only claims its group while it has work to do;
	-- when Ready is false, lower priorities run until it has work again
	function Scheduler:_ready(def: any): boolean
		if def.Ready == nil then
			return true
		end
		local ok, ready = pcall(def.Ready, self.Hub)
		if not ok then
			if not def._readyFailed then
				def._readyFailed = true
				warn(("[Scheduler] Ready for '%s' errored: %s"):format(def.Name, tostring(ready)))
			end
			return false
		end
		def._readyFailed = nil
		return ready and true or false
	end
	
	-- ── task lifecycle ──────────────────────────────────────────────────────────
	
	function Scheduler:_ctx(def: any)
		return {
			Hub = self.Hub,
			Settings = self.Hub.Settings,
			Name = def.Name,
			Trove = def._trove,
			Cancelled = function()
				return self.Active[def.Name] ~= def
			end,
		}
	end
	
	function Scheduler:_start(def: any)
		self.Active[def.Name] = def
		self.Strikes[def.Name] = nil
		def._trove = self.Hub.Trove:Extend()
		if def.Thread then
			self:_runThread(def)
		end
	end
	
	function Scheduler:_runThread(def: any)
		local name = def.Name
		def._spawnedAt = os.clock()
		def._thread = task.spawn(function()
			local ok, err = pcall(def.Run, self:_ctx(def))
			if self.Active[name] ~= def then
				return -- stopped while the thread was finishing
			end
			if ok then
				return -- Run returned while still enabled; it restarts on the next enable
			end
			self:_strike(name, err)
			if self.Active[name] == def then
				self:_runThread(def) -- retry; strikes keep counting -> 3 disables the task
			end
		end)
		-- the trove owns the thread, so stopping the task kills it even mid-yield
		if def._trove and self.Active[name] == def then
			def._trove:Add(def._thread)
		end
	end
	
	function Scheduler:_stop(name: string)
		local def = self.Active[name]
		if not def then
			return
		end
		self.Active[name] = nil
		local trove, thread = def._trove, def._thread
		def._trove, def._thread, def._spawnedAt = nil, nil, nil
		if trove then
			if thread == coroutine.running() then
				trove:_findAndRemoveFromObjects(thread, false) -- untrack without closing the thread we're inside of
			end
			trove:Clean()
		end
		self.Strikes[name] = nil
	end
	
	function Scheduler:_strike(name: string, err: any)
		local strikes = (self.Strikes[name] or 0) + 1
		self.Strikes[name] = strikes
		warn(("[Scheduler] task '%s' errored (%d/%d): %s"):format(name, strikes, MAX_STRIKES, tostring(err)))
		if strikes < MAX_STRIKES then
			return
		end
		self.Disabled[name] = true -- stays off until the gate turns off (a toggle flip re-arms it)
		self:_stop(name)
		if self.Hub.Settings[name] ~= nil then
			self.Hub.Settings[name] = false -- flips a bound toggle off through Changed
		end
		self.TaskDisabled:Fire(name, strikes, err)
	end
	
	-- ── tick ────────────────────────────────────────────────────────────────────
	
	-- phase 1: which tasks should be active this tick, and the state each one is in
	function Scheduler:_elect(): ({ [string]: any }, { [string]: string })
		local want: { [string]: any } = {}
		local tops: { [string]: any } = {} -- group -> winning queued def
		local states = self._nextState
		table.clear(states)
	
		for _, name in ipairs(self.Order) do
			local def = self.Tasks[name]
			local gated = self:_gate(def)
			if self.Disabled[name] and not gated then
				self.Disabled[name] = nil -- gate went off: the next enable is a fresh start
			end
	
			if self.Disabled[name] then
				states[name] = "disabled"
			elseif not gated then
				states[name] = "off"
			elseif not self:IsExclusive(def) then
				want[name] = def
				states[name] = "running"
			elseif self:_ready(def) then
				states[name] = "queued" -- becomes "running" below if it wins its group
				local current = tops[def.Group]
				if not current or self:GetPriority(def) > self:GetPriority(current) then
					tops[def.Group] = def
				end
			else
				states[name] = "idle" -- nothing to do right now: lower priorities may run
			end
		end
		for _, def in tops do
			want[def.Name] = def
			states[def.Name] = "running"
		end
		return want, states
	end
	
	-- phase 2: publish what changed (a UI listing the tasks listens)
	function Scheduler:_publish(states: { [string]: string })
		local changed = false
		for _, name in ipairs(self.Order) do
			if self.State[name] ~= states[name] then
				self.State[name] = states[name]
				changed = true
			end
		end
		if changed then
			self.StateChanged:Fire()
		end
	end
	
	-- phase 3: start and stop tasks until reality matches, in registration order
	function Scheduler:_reconcile(want: { [string]: any })
		for _, name in ipairs(self.Order) do
			if self.Active[name] and not want[name] then
				self:_stop(name)
			elseif want[name] and not self.Active[name] then
				self:_start(want[name])
			end
		end
	end
	
	-- phase 4: run loop tasks, and clear the strikes of threads that have stayed up
	function Scheduler:_run(want: { [string]: any })
		for _, name in ipairs(self.Order) do
			local def = self.Tasks[name]
			if def and want[name] and self.Active[name] == def then
				if def.Thread then
					if def._spawnedAt and os.clock() - def._spawnedAt > HEALTHY_SECONDS then
						self.Strikes[name] = nil
						def._spawnedAt = nil
					end
				else
					local ok, err = pcall(def.Run, self:_ctx(def))
					if ok then
						self.Strikes[name] = nil
					else
						self:_strike(name, err)
					end
				end
			end
		end
	end
	
	function Scheduler:_tick()
		local want, states = self:_elect()
		self:_publish(states)
		self:_reconcile(want)
		self:_run(want)
	end
	
	-- ── loop ────────────────────────────────────────────────────────────────────
	
	---Fire Starting, then tick until Stop().
	function Scheduler:Start()
		if self._started then
			return
		end
		self._started = true
		self.Starting:Fire() -- UI that lists the tasks builds itself here, before the first tick
		task.spawn(function()
			while self._started do
				local ok, err = pcall(self._tick, self)
				if not ok then
					warn("[Scheduler] tick failed: " .. tostring(err))
				end
				if self.Interval > 0 then
					task.wait(self.Interval)
				else
					task.wait()
				end
			end
		end)
	end
	
	---Stop ticking and stop every active task.
	function Scheduler:Stop()
		if not self._started then
			return
		end
		self._started = false
		for name in self.Active do
			-- one bad task must not leave the rest running
			pcall(function()
				self:_stop(name)
			end)
		end
	end
	
	return Scheduler
	
end

return setmetatable({}, {__index = function(self, key) local f = Modules[key] if f then return f() end end})