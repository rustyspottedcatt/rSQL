--!strict
--!nolint DeprecatedApi
--!nolint UnknownType
--[[
	Runtime abstraction (ports & adapters).

	The core library only needs three things from its host: a clock, a way to
	yield so long jobs do not trip Roblox's script timeout, and (optionally) an
	HTTP GET. Everything else is pure Luau. Detection happens once; tests and
	embedders can override any piece with `Platform.configure`.
]]

export type Runtime = "roblox" | "lune" | "luau"

export type Adapter = {
	runtime: Runtime,
	clock: () -> number,
	yield: () -> (),
	httpGet: ((url: string) -> string)?,
}

local Platform = {}

-- This module's environment. On Roblox it holds the engine globals (game,
-- task, script, Instance); on Lune none of them exist.
local hostEnv: { [string]: any } = getfenv and getfenv(1) or {}

--[=[
	Reads a host global such as "game" or "Instance". Returns nil when the
	runtime doesn't have it. `Platform.global("script")` is this module's
	ModuleScript on Roblox, which locates the package in the DataModel.
]=]
function Platform.global(name: string): any
	return hostEnv[name]
end

local function detect(): Adapter
	local game = hostEnv.game
	local task = hostEnv.task

	if typeof(game) == "Instance" and type(task) == "table" then
		local http = game:GetService("HttpService")
		return {
			runtime = "roblox",
			clock = os.clock,
			yield = function()
				task.wait()
			end,
			httpGet = function(url: string): string
				return http:GetAsync(url)
			end,
		}
	end

	local isLune = type(_VERSION) == "string" and string.find(_VERSION, "Lune", 1, true) ~= nil
	return {
		runtime = if isLune then "lune" else "luau",
		clock = os.clock,
		yield = function() end,
		httpGet = nil,
	}
end

local current: Adapter = detect()

function Platform.get(): Adapter
	return current
end

function Platform.runtime(): Runtime
	return current.runtime
end

function Platform.clock(): number
	return current.clock()
end

function Platform.yield()
	current.yield()
end

-- Waits about `seconds`, yielding to the host scheduler (busy-waits on Lune).
function Platform.sleep(seconds: number)
	local wait = hostEnv.task and hostEnv.task.wait
	if wait then
		wait(seconds)
		return
	end
	local deadline = current.clock() + seconds
	while current.clock() < deadline do
		current.yield()
	end
end

function Platform.httpGet(url: string): string
	local get = current.httpGet
	if not get then
		error("Platform.httpGet: no HTTP adapter on runtime '" .. current.runtime .. "'", 2)
	end
	return get(url)
end

--[=[
	Override parts of the adapter, e.g. `Platform.configure({ yield = myYield })`.
	Returns a function that restores the previous adapter.
]=]
function Platform.configure(overrides: { [string]: any }): () -> ()
	local previous = current
	local nextAdapter = table.clone(current) :: any
	for k, v in overrides do
		nextAdapter[k] = v
	end
	current = nextAdapter :: Adapter
	return function()
		current = previous
	end
end

export type Budget = {
	budgetSeconds: number,
	started: number,
	yields: number,
	tick: (self: Budget) -> boolean,
	reset: (self: Budget) -> (),
}

--[=[
	Cooperative time budget. Call `budget:tick()` inside hot loops; it yields to
	the host scheduler once `budgetMs` of CPU time has been used since the last
	yield. On Lune it never yields. Returns true when it yielded.
]=]
function Platform.budget(budgetMs: number?): Budget
	local self = {
		budgetSeconds = (budgetMs or 15) / 1000,
		started = Platform.clock(),
		yields = 0,
	} :: Budget

	function self:tick(): boolean
		if Platform.clock() - self.started >= self.budgetSeconds then
			Platform.yield()
			self.yields += 1
			self.started = Platform.clock()
			return true
		end
		return false
	end

	function self:reset()
		self.started = Platform.clock()
	end

	return self
end

return Platform
