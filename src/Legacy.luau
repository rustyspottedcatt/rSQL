--!strict
--[[
	The 1.x API, running on the 2.x engine.

	    local conn = rSQL:connect(dataStore, { allowSelect = true, ... }):expect()
	    conn:query("SELECT * FROM Players WHERE ID = '1'"):andThen(print)

	Behaves like 1.x where it matters for existing games:

	  * query() returns a promise. SELECT resolves with an array of rows,
	    everything else with a message string.
	  * permissions come from the allowX flags; anything not set is refused.
	  * tables created through this API use the 1.x single-key layout, so
	    1.x servers still running during an upgrade can read them.

	And fixes what 1.x got wrong: CREATE TABLE on an existing table keeps
	the data instead of wiping it, values are no longer forced to strings,
	and errors point at the part of the query that failed.
]]

local Database = require("./Database")
local Promise = require("./Promise")
local DataStoreAdapter = require("./Storage/DataStoreAdapter")
local TableAdapter = require("./Storage/TableAdapter")
local Adapter = require("./Storage/Adapter")

local Legacy = {}

local function wrap(adapter: Adapter.Adapter, config: any, createOptions: Adapter.CreateOptions?)
	local db = Database.new(adapter, {
		permissions = config,
		createIsNoop = true,
		firstColumnKey = true,
		createOptions = createOptions,
	})
	local connection = { database = db, config = config }
	function connection:query(sql: string, params: { [any]: any }?)
		return Promise.new(function(resolve)
			local result = db:exec(sql, params)
			if result.kind == "select" or result.kind == "showTables" or result.kind == "describe" then
				resolve(result.rows)
			else
				resolve("[rSQL] " .. (result.message or "done"))
			end
		end)
	end
	return connection
end

local function checkConfig(config: any, reject: (string) -> ()): boolean
	if config == nil then
		reject("[rSQL] Unexpected `nil` value for `config`, expected a config table.")
		return false
	end
	return true
end

function Legacy.connect(dataStore: any, config: any)
	return Promise.new(function(resolve, reject)
		if dataStore == nil then
			return reject("[rSQL] Unexpected `nil` value for `datastore`, expected DataStore instance.")
		end
		if not checkConfig(config, reject) then
			return
		end
		resolve(wrap(DataStoreAdapter.new(dataStore, { layout = "single" }), config, { layout = "single" }))
	end)
end

function Legacy.connectToProfile(profile: any, config: any)
	return Promise.new(function(resolve, reject)
		if type(profile) ~= "table" then
			return reject("[rSQL] Unexpected value for `profilesTable`, expected a profile table.")
		end
		if not checkConfig(config, reject) then
			return
		end
		resolve(wrap(TableAdapter.new(TableAdapter.profileRoot(profile), { kind = "profile" }), config))
	end)
end

return Legacy
