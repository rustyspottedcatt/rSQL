--!strict
--[[
	Stores tables in a Roblox DataStore.

	Two layouts:

	sharded (default for new tables)
	    <table>/meta         { version = 2, layout = "sharded", schema, shards, generation, nextId }
	    <table>/<gen>.<i>    { rows = { [key] = row } }     for i = 1 .. shards

	    Rows are spread over shards by a hash of their primary key. A lookup
	    by primary key reads one shard; a scan reads every shard. Each shard is
	    a separate key with its own 4 MB limit, so a table holds about
	    shards x 4 MB, and every write goes through UpdateAsync on just the
	    shard it touches.

	single (1.x compatible)
	    <table>              { _schema = { "col", ... }, rows = { row, ... }, _meta }

	    The whole table in one key, exactly how 1.x stored it, so 1.x servers
	    and 2.x servers can share data during an upgrade.

	What is and isn't atomic: one UpdateAsync is atomic, so a statement that
	touches rows in one shard (or a single-layout table) is atomic. A
	statement that touches several shards commits shard by shard; if a later
	shard fails, earlier ones stay written. UNIQUE on non-key columns is
	checked before writing, which can race with another server.

	Calls are retried with exponential back-off when DataStores throttle.
]]

local Adapter = require("./Adapter")
local Schema = require("../Engine/Schema")
local Types = require("../Engine/Types")
local Bits = require("../Util/Bits")
local Platform = require("../Platform")

type Row = Adapter.Row

export type Options = {
	layout: ("sharded" | "single")?,
	shards: number?,
	retries: number?,
	backoffSeconds: number?,
	prefix: string?,
	sleep: ((seconds: number) -> ())?,
}

type Meta = {
	version: number,
	layout: string,
	schema: Schema.TableSchema,
	shards: number,
	generation: number,
	nextId: number,
}

-- Where a table lives: its meta (sharded) or its whole value (single).
type Located = { layout: string, meta: Meta, value: any }

local DataStoreAdapter = {}

local MAX_KEY_LENGTH = 50
local REGISTRY = "__rsql_tables"

local function fail(message: string): never
	error("rSQL: " .. message, 0)
end

function DataStoreAdapter.new(dataStore: any, options: Options?): Adapter.Adapter
	local opts: Options = options or {}
	local defaultLayout = opts.layout or "sharded"
	local defaultShards = opts.shards or 8
	local retries = opts.retries or 3
	local backoff = opts.backoffSeconds or 0.5
	local prefix = opts.prefix or ""
	local sleep = opts.sleep or Platform.sleep
	assert(defaultShards >= 1 and defaultShards <= 256, "rSQL: shards must be between 1 and 256")

	local self = { kind = "datastore", stats = { reads = 0, writes = 0 } } :: Adapter.Adapter

	local function call(what: string, fn: () -> any): any
		local delay = backoff
		for attempt = 1, retries + 1 do
			local ok, result = pcall(fn)
			if ok then
				return result
			end
			local message = tostring(result)
			-- our own errors (duplicate key, missing table) are final
			if string.find(message, "rSQL:", 1, true) then
				error(message, 0)
			end
			if string.find(message, "exceeds", 1, true) or string.find(message, "too large", 1, true) then
				fail(what .. " is over the DataStore size limit; give the table more shards with db:reshard()")
			end
			if attempt > retries then
				fail(string.format("%s failed after %d attempts: %s", what, attempt, message))
			end
			sleep(delay)
			delay *= 2
		end
		return nil
	end

	local function get(key: string): any
		self.stats.reads += 1
		return call("GetAsync(" .. key .. ")", function()
			return dataStore:GetAsync(key)
		end)
	end

	--[=[
		UpdateAsync doesn't rethrow errors from the transform function: the
		write is cancelled and the call returns nil as if nothing happened.
		So the transform runs inside pcall, the error is kept, and it's raised
		here once UpdateAsync returns. Roblox may run the transform more than
		once, so only the last run's error counts.
	]=]
	local function update(key: string, transform: (old: any) -> any): any
		self.stats.writes += 1
		return call("UpdateAsync(" .. key .. ")", function()
			local failure: string? = nil
			local result = dataStore:UpdateAsync(key, function(old)
				failure = nil
				local ok, value = pcall(transform, old)
				if ok then
					return value
				end
				local message = tostring(value)
				-- a bug in a transform fails the same way on every retry, so make it final
				failure = if string.find(message, "rSQL:", 1, true) then message else "rSQL: " .. message
				return nil
			end)
			if failure then
				error(failure, 0)
			end
			return result
		end)
	end

	local function remove(key: string)
		self.stats.writes += 1
		call("RemoveAsync(" .. key .. ")", function()
			return dataStore:RemoveAsync(key)
		end)
	end

	local function metaKey(name: string): string
		return prefix .. name .. "/meta"
	end
	local function shardKey(name: string, meta: Meta, i: number): string
		return string.format("%s%s/%d.%d", prefix, name, meta.generation, i)
	end
	local function singleKey(name: string): string
		return prefix .. name
	end
	local function shardOf(key: string, shards: number): number
		return Bits.hash32(key) % shards + 1
	end

	local function checkName(name: string)
		Schema.validateName(name, "table")
		if #prefix + #name + 12 > MAX_KEY_LENGTH then
			fail("table name " .. name .. " is too long for a DataStore key (keys are limited to 50 characters)")
		end
	end

	-- Within one statement the table's location is looked up once. Anything
	-- that rewrites meta or the single key drops the cached entry.
	local statementCache: { [string]: Located | false }? = nil

	function self:beginStatement()
		statementCache = {}
	end
	function self:endStatement()
		statementCache = nil
	end
	local function forget(name: string)
		if statementCache then
			statementCache[name] = nil
		end
	end

	local function lookup(name: string): Located?
		local meta = get(metaKey(name))
		if type(meta) == "table" and meta.layout == "sharded" then
			return { layout = "sharded", meta = meta, value = nil } :: any
		end
		local value = get(singleKey(name))
		if type(value) == "table" and type(value._schema) == "table" and type(value.rows) == "table" then
			return { layout = "single", meta = nil, value = value } :: any
		end
		return nil
	end

	local function locate(name: string): Located?
		local cache = statementCache
		if cache then
			local hit = cache[name]
			if hit == false then
				return nil
			elseif hit ~= nil then
				return hit :: Located
			end
			local found = lookup(name)
			cache[name] = found or false
			return found
		end
		return lookup(name)
	end

	local function mustLocate(name: string): Located
		local found = locate(name)
		if not found then
			fail("no table named " .. name)
		end
		return found :: Located
	end

	local function singleSchema(name: string, value: any): Schema.TableSchema
		if type(value._meta) == "table" and value._meta.schema then
			return value._meta.schema
		end
		return Schema.fromLegacy(name, value._schema)
	end

	local function sortRows(rows: { Row }, pk: string)
		table.sort(rows, function(a, b)
			return Types.sortCompare(a[pk], b[pk]) < 0
		end)
	end

	local function registryUpdate(name: string, add: boolean)
		update(prefix .. REGISTRY, function(old)
			local names = if type(old) == "table" then old else {}
			local i = table.find(names, name)
			if add and not i then
				table.insert(names, name)
				table.sort(names)
			elseif not add and i then
				table.remove(names, i)
			end
			return names
		end)
	end

	function self:listTables(): { string }
		local names = get(prefix .. REGISTRY)
		return if type(names) == "table" then table.clone(names) else {}
	end

	function self:getTable(name: string)
		local found = locate(name)
		if not found then
			return nil
		end
		if found.layout == "sharded" then
			return { schema = found.meta.schema, layout = "sharded", shards = found.meta.shards }
		end
		return {
			schema = singleSchema(name, found.value),
			layout = if found.value._meta then "single" else "legacy",
		}
	end

	function self:createTable(schema: Schema.TableSchema, createOptions)
		forget(schema.name)
		checkName(schema.name)
		local layout = (createOptions and createOptions.layout) or defaultLayout
		local shards = (createOptions and createOptions.shards) or defaultShards
		if locate(schema.name) then
			fail("table " .. schema.name .. " already exists")
		end
		if layout == "single" then
			update(singleKey(schema.name), function(old)
				if old ~= nil then
					fail("table " .. schema.name .. " already exists")
				end
				return {
					_schema = Schema.columnNames(schema),
					rows = {},
					_meta = { version = 2, schema = schema, nextId = 1 },
				}
			end)
		else
			update(metaKey(schema.name), function(old)
				if old ~= nil then
					fail("table " .. schema.name .. " already exists")
				end
				return { version = 2, layout = "sharded", schema = schema, shards = shards, generation = 1, nextId = 1 }
			end)
		end
		registryUpdate(schema.name, true)
	end

	function self:dropTable(name: string): boolean
		forget(name)
		local found = locate(name)
		if not found then
			return false
		end
		if found.layout == "sharded" then
			for i = 1, found.meta.shards do
				remove(shardKey(name, found.meta, i))
			end
			remove(metaKey(name))
		else
			remove(singleKey(name))
		end
		registryUpdate(name, false)
		return true
	end

	function self:setSchema(name: string, schema: Schema.TableSchema, rewrite)
		forget(name)
		local found = mustLocate(name)
		if found.layout == "sharded" then
			update(metaKey(name), function(old)
				old.schema = schema
				return old
			end)
			if rewrite then
				for i = 1, found.meta.shards do
					update(shardKey(name, found.meta, i), function(old)
						if old == nil then
							return nil
						end
						for key, row in old.rows do
							old.rows[key] = rewrite(row)
						end
						return old
					end)
				end
			end
		else
			update(singleKey(name), function(old)
				old._schema = Schema.columnNames(schema)
				old._meta = old._meta or { version = 2, nextId = 1 }
				old._meta.schema = schema
				if rewrite then
					for i, row in old.rows do
						old.rows[i] = rewrite(row)
					end
				end
				return old
			end)
		end
	end

	function self:get(name: string, keys: { string }): { Row }
		local found = mustLocate(name)
		local out: { Row } = {}
		if found.layout == "sharded" then
			local meta = found.meta
			local byShard: { [number]: { string } } = {}
			for _, key in keys do
				local s = shardOf(key, meta.shards)
				byShard[s] = byShard[s] or {}
				table.insert(byShard[s], key)
			end
			for s, shardKeys in byShard do
				local data = get(shardKey(name, meta, s))
				if type(data) == "table" then
					for _, key in shardKeys do
						local row = data.rows[key]
						if row then
							table.insert(out, row)
						end
					end
				end
			end
			sortRows(out, meta.schema.primaryKey)
		else
			local pk = singleSchema(name, found.value).primaryKey
			local wanted: { [string]: boolean } = {}
			for _, key in keys do
				wanted[key] = true
			end
			for _, row in found.value.rows do
				if wanted[Types.key(row[pk])] then
					table.insert(out, row)
				end
			end
		end
		return out
	end

	function self:scan(name: string): { Row }
		local found = mustLocate(name)
		if found.layout == "single" then
			return table.clone(found.value.rows)
		end
		local meta = found.meta
		local out: { Row } = {}
		for i = 1, meta.shards do
			local data = get(shardKey(name, meta, i))
			if type(data) == "table" then
				for _, row in data.rows do
					table.insert(out, row)
				end
			end
		end
		sortRows(out, meta.schema.primaryKey)
		return out
	end

	function self:insert(name: string, rows)
		forget(name)
		local found = mustLocate(name)
		if found.layout == "sharded" then
			local meta = found.meta
			local byShard: { [number]: { { key: string, row: Row } } } = {}
			for _, item in rows do
				local s = shardOf(item.key, meta.shards)
				byShard[s] = byShard[s] or {}
				table.insert(byShard[s], item)
			end
			for s, items in byShard do
				update(shardKey(name, meta, s), function(old)
					local data = if type(old) == "table" then old else { rows = {} }
					for _, item in items do
						if data.rows[item.key] ~= nil then
							fail(string.format("duplicate key '%s' in table %s", item.key, name))
						end
						data.rows[item.key] = item.row
					end
					return data
				end)
			end
		else
			update(singleKey(name), function(old)
				if type(old) ~= "table" then
					fail("table " .. name .. " disappeared during the insert")
				end
				local pk = singleSchema(name, old).primaryKey
				local existing: { [string]: boolean } = {}
				for _, row in old.rows do
					existing[Types.key(row[pk])] = true
				end
				for _, item in rows do
					if existing[item.key] then
						fail(string.format("duplicate key '%s' in table %s", item.key, name))
					end
					existing[item.key] = true
					table.insert(old.rows, item.row)
				end
				return old
			end)
		end
	end

	function self:modify(name: string, keys: { string }?, fn): number
		forget(name)
		local found = mustLocate(name)
		local total = 0
		if found.layout == "sharded" then
			local meta = found.meta
			local pk = meta.schema.primaryKey
			local shardList: { number } = {}
			local keysByShard: { [number]: { string } } = {}
			if keys then
				for _, key in keys do
					local s = shardOf(key, meta.shards)
					if not keysByShard[s] then
						keysByShard[s] = {}
						table.insert(shardList, s)
					end
					table.insert(keysByShard[s], key)
				end
				table.sort(shardList)
			else
				for i = 1, meta.shards do
					shardList[i] = i
				end
			end
			for _, s in shardList do
				local changed = 0
				update(shardKey(name, meta, s), function(old)
					changed = 0 -- UpdateAsync may run this more than once
					if type(old) ~= "table" then
						return nil
					end
					local visit = keysByShard[s]
					local targets: { string } = {}
					if visit then
						for _, key in visit do
							if old.rows[key] ~= nil then
								table.insert(targets, key)
							end
						end
					else
						for key in old.rows do
							table.insert(targets, key)
						end
						table.sort(targets)
					end
					for _, key in targets do
						local change, newRow = fn(old.rows[key])
						if change == "update" then
							local newKey = Types.key((newRow :: Row)[pk])
							if newKey ~= key then
								fail(
									"changing the primary key of a sharded table isn't supported; DELETE and INSERT instead"
								)
							end
							old.rows[key] = newRow
							changed += 1
						elseif change == "delete" then
							old.rows[key] = nil
							changed += 1
						end
					end
					if changed == 0 then
						return nil -- nothing to write
					end
					return old
				end)
				total += changed
			end
		else
			update(singleKey(name), function(old)
				total = 0
				if type(old) ~= "table" then
					return nil
				end
				local pk = singleSchema(name, old).primaryKey
				local wanted: { [string]: boolean }? = nil
				if keys then
					wanted = {}
					for _, key in keys do
						(wanted :: any)[key] = true
					end
				end
				local kept = {}
				for _, row in old.rows do
					if wanted == nil or (wanted :: any)[Types.key(row[pk])] then
						local change, newRow = fn(row)
						if change == "update" then
							table.insert(kept, newRow)
							total += 1
						elseif change == "delete" then
							total += 1
						else
							table.insert(kept, row)
						end
					else
						table.insert(kept, row)
					end
				end
				if total == 0 then
					return nil
				end
				old.rows = kept
				return old
			end)
		end
		return total
	end

	function self:truncate(name: string)
		forget(name)
		local found = mustLocate(name)
		if found.layout == "sharded" then
			for i = 1, found.meta.shards do
				remove(shardKey(name, found.meta, i))
			end
		else
			update(singleKey(name), function(old)
				old.rows = {}
				return old
			end)
		end
	end

	function self:allocateIds(name: string, count: number): number
		forget(name)
		local found = mustLocate(name)
		local first = 0
		if found.layout == "sharded" then
			update(metaKey(name), function(old)
				first = old.nextId or 1
				old.nextId = first + count
				return old
			end)
		else
			update(singleKey(name), function(old)
				if type(old._meta) ~= "table" then
					fail("table " .. name .. " was created by rSQL 1.x and has no AUTOINCREMENT column")
				end
				first = old._meta.nextId or 1
				old._meta.nextId = first + count
				return old
			end)
		end
		return first
	end

	--[=[
		Moves a table to a new shard count (or from the single layout to the
		sharded one). Reads every row, writes them under a new generation of
		keys, then switches the meta key over and removes the old keys. Run it
		while nothing else writes to the table.
	]=]
	local function reshard(_self: any, name: string, shards: number)
		forget(name)
		assert(shards >= 1 and shards <= 256, "rSQL: shards must be between 1 and 256")
		local found = mustLocate(name)
		local rows = self:scan(name)
		local schema: Schema.TableSchema
		local generation = 1
		local nextId = 1
		if found.layout == "sharded" then
			schema = found.meta.schema
			generation = found.meta.generation + 1
			nextId = found.meta.nextId
		else
			schema = singleSchema(name, found.value)
			nextId = if found.value._meta then found.value._meta.nextId or 1 else 1
		end
		local newMeta: Meta = {
			version = 2,
			layout = "sharded",
			schema = schema,
			shards = shards,
			generation = generation,
			nextId = nextId,
		}
		local buckets: { [number]: { [string]: Row } } = {}
		for _, row in rows do
			local key = Types.key(row[schema.primaryKey])
			local s = shardOf(key, shards)
			buckets[s] = buckets[s] or {}
			buckets[s][key] = row
		end
		for s, bucket in buckets do
			update(shardKey(name, newMeta, s), function()
				return { rows = bucket }
			end)
		end
		update(metaKey(name), function()
			return newMeta
		end)
		if found.layout == "sharded" then
			for i = 1, found.meta.shards do
				remove(shardKey(name, found.meta, i))
			end
		else
			remove(singleKey(name))
			registryUpdate(name, true)
		end
	end
	(self :: any).reshard = reshard

	return self
end

return DataStoreAdapter
