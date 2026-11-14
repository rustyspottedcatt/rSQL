--!strict
--[[
	In-memory stand-in for a Roblox GlobalDataStore, close enough to test
	against:

	  * values are copied on the way in and out, like real serialization, and
	    functions or non-string dictionary keys are rejected
	  * UpdateAsync gets a copy of the old value; returning nil cancels the write
	  * an error inside the UpdateAsync transform cancels the write and
	    UpdateAsync returns nil without throwing, which is what Roblox does
	  * `rerunTransforms` runs every transform one extra time first and
	    throws that result away, like UpdateAsync retrying after a conflict
	  * values over `limitBytes` (default 4 MB) fail with the same kind of
	    message Roblox uses
	  * `failNext(n)` makes the next n calls throw a throttling error
	  * counts requests and bytes read, for benchmarks
]]

local Json = require("../../src/Util/Json")

export type FakeDataStore = {
	data: { [string]: any },
	requests: { get: number, update: number, remove: number, set: number },
	bytesRead: number,
	limitBytes: number,
	rerunTransforms: boolean,
	GetAsync: (self: FakeDataStore, key: string) -> any,
	SetAsync: (self: FakeDataStore, key: string, value: any) -> (),
	UpdateAsync: (self: FakeDataStore, key: string, fn: (old: any) -> any) -> any,
	RemoveAsync: (self: FakeDataStore, key: string) -> any,
	failNext: (self: FakeDataStore, n: number) -> (),
	reset: (self: FakeDataStore) -> (),
}

local FakeDataStore = {}

local function copy(value: any, depth: number?): any
	local d = depth or 0
	if d > 100 then
		error("104: value nests too deep", 0)
	end
	local kind = typeof(value)
	if kind == "table" then
		local out = {}
		local n = #value
		for k, v in value do
			if type(k) ~= "string" and not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
				error("104: Cannot store a table with non-string keys in a dictionary", 0)
			end
			out[k] = copy(v, d + 1)
		end
		return out
	elseif kind == "function" or kind == "thread" or kind == "userdata" then
		error("104: Cannot store " .. kind .. " in data store", 0)
	end
	return value
end

local function size(value: any): number
	local ok, encoded = pcall(Json.encode, value)
	return if ok then #encoded else 0
end

function FakeDataStore.new(options: { limitBytes: number?, rerunTransforms: boolean? }?): FakeDataStore
	local self = {
		data = {},
		requests = { get = 0, update = 0, remove = 0, set = 0 },
		bytesRead = 0,
		limitBytes = (options and options.limitBytes) or 4_194_304,
		rerunTransforms = (options and options.rerunTransforms) == true,
	} :: FakeDataStore
	local failures = 0

	local function maybeFail()
		if failures > 0 then
			failures -= 1
			error("502: API Services rejected request with error. HTTP 429 (Too Many Requests)", 0)
		end
	end

	local function store(key: string, value: any)
		local c = copy(value)
		if size(c) > self.limitBytes then
			error("105: Serialized value converted byte size exceeds max size", 0)
		end
		self.data[key] = c
	end

	function self:GetAsync(key: string): any
		maybeFail()
		self.requests.get += 1
		local value = self.data[key]
		if value ~= nil then
			self.bytesRead += size(value)
		end
		return copy(value)
	end

	function self:SetAsync(key: string, value: any)
		maybeFail()
		self.requests.set += 1
		store(key, value)
	end

	function self:UpdateAsync(key: string, fn: (any) -> any): any
		maybeFail()
		self.requests.update += 1
		local old = self.data[key]
		if old ~= nil then
			self.bytesRead += size(old)
		end
		if self.rerunTransforms then
			pcall(fn, copy(old))
		end
		local ok, new = pcall(fn, copy(old))
		if not ok or new == nil then
			return nil
		end
		store(key, new)
		return copy(new)
	end

	function self:RemoveAsync(key: string): any
		maybeFail()
		self.requests.remove += 1
		local old = self.data[key]
		self.data[key] = nil
		return old
	end

	function self:failNext(n: number)
		failures = n
	end

	function self:reset()
		self.requests = { get = 0, update = 0, remove = 0, set = 0 }
		self.bytesRead = 0
	end

	return self
end

return FakeDataStore
