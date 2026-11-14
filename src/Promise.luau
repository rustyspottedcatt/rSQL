--!strict
--[[
	A small promise, compatible with the parts of evaera/promise that rSQL 1.x
	scripts use: andThen, catch, finally, expect, await, getStatus.

	rSQL 1.x needed the promise package installed next to it; 2.x has no
	dependencies, so it ships this instead. The executor runs right away in a
	new coroutine; when it yields (DataStore calls do), the promise stays
	pending until the engine resumes it.
]]

local Platform = require("./Platform")

export type Status = "Started" | "Resolved" | "Rejected"

export type Promise = {
	andThen: (self: Promise, onResolve: ((...any) -> ...any)?, onReject: ((...any) -> ...any)?) -> Promise,
	catch: (self: Promise, onReject: (...any) -> ...any) -> Promise,
	finally: (self: Promise, handler: (status: Status) -> ()) -> Promise,
	expect: (self: Promise) -> ...any,
	await: (self: Promise) -> (boolean, ...any),
	getStatus: (self: Promise) -> Status,
}

local Promise = {}
Promise.__index = Promise

local function isPromise(v: any): boolean
	return type(v) == "table" and getmetatable(v) == Promise
end

local function settle(self: any, status: Status, ...: any)
	if self._status ~= "Started" then
		return
	end
	self._status = status
	self._values = table.pack(...)
	local callbacks = self._callbacks
	self._callbacks = {}
	for _, callback in callbacks do
		callback()
	end
end

function Promise.new(executor: (resolve: (...any) -> (), reject: (...any) -> ()) -> ()): Promise
	local self = setmetatable({ _status = "Started", _values = { n = 0 }, _callbacks = {} }, Promise)
	local function resolve(...: any)
		local first = ...
		if isPromise(first) then
			first:andThen(function(...)
				settle(self, "Resolved", ...)
			end, function(...)
				settle(self, "Rejected", ...)
			end)
			return
		end
		settle(self, "Resolved", ...)
	end
	local function reject(...: any)
		settle(self, "Rejected", ...)
	end
	local thread = coroutine.create(function()
		local ok, err = pcall(function(): any
			executor(resolve, reject)
			return nil
		end)
		if not ok then
			reject(err)
		end
	end)
	local ok, err = coroutine.resume(thread)
	if not ok then
		reject(err)
	end
	return self :: any
end

function Promise.resolve(...: any): Promise
	local values = table.pack(...)
	return Promise.new(function(resolve)
		resolve(table.unpack(values, 1, values.n))
	end)
end

function Promise.reject(...: any): Promise
	local values = table.pack(...)
	return Promise.new(function(_, reject)
		reject(table.unpack(values, 1, values.n))
	end)
end

function Promise.getStatus(self: any): Status
	return self._status
end

function Promise.andThen(self: any, onResolve: ((...any) -> ...any)?, onReject: ((...any) -> ...any)?): Promise
	return Promise.new(function(resolve, reject)
		local function run(): any
			local values = self._values
			if self._status == "Resolved" then
				if onResolve then
					resolve(onResolve(table.unpack(values, 1, values.n)))
				else
					resolve(table.unpack(values, 1, values.n))
				end
			else
				if onReject then
					resolve(onReject(table.unpack(values, 1, values.n)))
				else
					reject(table.unpack(values, 1, values.n))
				end
			end
			return nil
		end
		if self._status == "Started" then
			table.insert(self._callbacks, function()
				local ok, err = pcall(run)
				if not ok then
					reject(err)
				end
			end)
		else
			run()
		end
	end)
end

function Promise.catch(self: any, onReject: (...any) -> ...any): Promise
	return self:andThen(nil, onReject)
end

function Promise.finally(self: any, handler: (status: Status) -> ()): Promise
	return self:andThen(function(...)
		handler("Resolved")
		return ...
	end, function(...)
		handler("Rejected")
		return Promise.reject(...)
	end)
end

-- Waits for the promise. Returns (true, values...) or (false, error).
function Promise.await(self: any): (boolean, ...any)
	while self._status == "Started" do
		Platform.sleep(0)
	end
	local values = self._values
	return self._status == "Resolved", table.unpack(values, 1, values.n)
end

-- Waits for the promise and returns its values, or raises its error.
function Promise.expect(self: any): ...any
	local values = table.pack(self:await())
	if not values[1] then
		error(values[2], 0)
	end
	return table.unpack(values, 2, values.n)
end

return Promise
