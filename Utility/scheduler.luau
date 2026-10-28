--[[
	Scheduler: the multitask core of a hub. One tick loop starts, stops and queues tasks.

	local scheduler = Scheduler.new(hub)
	scheduler:Register({ Name = "AutoFarm", Thread = true, Run = function(ctx) ... end })
	scheduler:Register({ Name = "AutoCollect", Interval = 0.5, Run = function(ctx) ... end })
	scheduler:Start()

	A task is enabled while hub.Settings[Name] == true, or while Enabled(hub) returns true.
	Three errors in a row turn a task off; it re-arms once its gate has gone off and on again.
	scheduler.Interval is the tick: seconds between passes over the tasks (default 0, every frame).

	Task definition
	  Name       string     unique; also the settings key that switches the task on
	  Run        function   Run(ctx): called every tick, or once on its own thread when Thread is set
	  Interval   number?    loop tasks: seconds from the start of one Run to the start of the next. 0 or
	                        omitted: every tick. Never finer than scheduler.Interval, the tick itself
	  Cleanup    function?  Cleanup(ctx): once after the task switches off (setting off, preempted, three errors,
	                        Unregister, Stop) and its trove is cleaned, so ctx.Trove is nil. Undo what Run did
	  Thread     boolean?   Run owns a thread and ctx.Trove; loop with `while not ctx.Cancelled() do`
	                        (it waits for itself, so it takes no Interval)
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
	A loop task's Run and every Cleanup run inside the tick, so neither may yield; work that waits is a Thread task.

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
	if def.Interval ~= nil and not (type(def.Interval) == "number" and def.Interval >= 0) then
		error(("[Scheduler] task '%s': Interval is a number of seconds, 0 or more"):format(def.Name), 2)
	end
	if def.Interval ~= nil and def.Thread then
		error(("[Scheduler] task '%s': a Thread task waits for itself, so it takes no Interval"):format(def.Name), 2)
	end
	if def.Cleanup ~= nil and type(def.Cleanup) ~= "function" then
		error(("[Scheduler] task '%s': Cleanup is a function"):format(def.Name), 2)
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
	def._trove, def._thread, def._spawnedAt, def._nextRun = nil, nil, nil, nil
	if trove then
		if thread == coroutine.running() then
			trove:_findAndRemoveFromObjects(thread, false) -- untrack without closing the thread we're inside of
		end
		trove:Clean()
	end
	self.Strikes[name] = nil
	if def.Cleanup then
		-- the trove is gone, so the ctx has none; a failing Cleanup must not stop the rest from stopping
		local ok, err = pcall(def.Cleanup, self:_ctx(def))
		if not ok then
			warn(("[Scheduler] Cleanup for '%s' errored: %s"):format(name, tostring(err)))
		end
	end
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

-- phase 4: run the loop tasks that are due, and clear the strikes of threads that have stayed up
function Scheduler:_run(want: { [string]: any })
	local now = os.clock()
	for _, name in ipairs(self.Order) do
		local def = self.Tasks[name]
		if def and want[name] and self.Active[name] == def then
			if def.Thread then
				if def._spawnedAt and now - def._spawnedAt > HEALTHY_SECONDS then
					self.Strikes[name] = nil
					def._spawnedAt = nil
				end
			elseif def._nextRun == nil or now >= def._nextRun then
				-- set before the call: when the third error stops the task, _stop clears it again
				def._nextRun = now + (def.Interval or 0)
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
