--!strict
--[[
	Stores tables inside a plain Luau table. Used for:

	  * in-memory databases (item and loot tables, tests): rSQL.memory()
	  * profile data from ProfileService, ProfileStore or DataKeep, where the
	    profile library handles saving and session locking

	Each table is stored as

	    root[name] = { _schema = { "col", ... }, rows = { row, ... }, _meta = { version = 2, schema, nextId } }

	which is the 1.x layout plus `_meta`, so profiles written by 1.x load
	without migration and 1.x code can still read tables written by 2.x.

	In-memory databases keep a key index per table. Profile data is left
	unindexed because other game code may edit it directly.
]]

local Adapter = require("./Adapter")
local Schema = require("../Engine/Schema")
local Types = require("../Engine/Types")

type Row = Adapter.Row

type Stored = {
	_schema: { string },
	rows: { Row },
	_meta: { version: number, schema: Schema.TableSchema, nextId: number }?,
}

local TableAdapter = {}

local function fail(message: string): never
	error("rSQL: " .. message, 0)
end

function TableAdapter.new(root: { [string]: any }, options: { kind: string?, indexed: boolean? }?): Adapter.Adapter
	local opts: { kind: string?, indexed: boolean? } = options or {}
	local indexed = opts.indexed == true
	local self = { kind = opts.kind or "memory", stats = { reads = 0, writes = 0 } } :: Adapter.Adapter
	-- name -> (key -> position in rows)
	local indexes: { [string]: { [string]: number } } = {}

	local function stored(name: string): Stored
		local t = root[name]
		if type(t) ~= "table" or type(t._schema) ~= "table" or type(t.rows) ~= "table" then
			fail("no table named " .. name)
		end
		return t
	end

	local function schemaOf(t: Stored, name: string): Schema.TableSchema
		local meta = t._meta
		if meta and meta.schema then
			return meta.schema
		end
		return Schema.fromLegacy(name, t._schema)
	end

	local function index(name: string, t: Stored): { [string]: number }?
		if not indexed then
			return nil
		end
		local idx = indexes[name]
		if idx == nil then
			idx = {}
			local pk = schemaOf(t, name).primaryKey
			for i, row in t.rows do
				idx[Types.key(row[pk])] = i
			end
			indexes[name] = idx
		end
		return idx
	end

	local function find(name: string, t: Stored, key: string): number?
		local idx = index(name, t)
		if idx then
			return idx[key]
		end
		local pk = schemaOf(t, name).primaryKey
		for i, row in t.rows do
			if Types.key(row[pk]) == key then
				return i
			end
		end
		return nil
	end

	function self:listTables(): { string }
		local names = {}
		for name, t in root do
			if
				type(name) == "string"
				and type(t) == "table"
				and type(t._schema) == "table"
				and type(t.rows) == "table"
			then
				table.insert(names, name)
			end
		end
		table.sort(names)
		return names
	end

	function self:getTable(name: string)
		local t = root[name]
		if type(t) ~= "table" or type(t._schema) ~= "table" or type(t.rows) ~= "table" then
			return nil
		end
		return { schema = schemaOf(t, name), layout = if t._meta then "table" else "legacy" }
	end

	function self:createTable(schema: Schema.TableSchema)
		if self:getTable(schema.name) then
			fail("table " .. schema.name .. " already exists")
		end
		root[schema.name] = {
			_schema = Schema.columnNames(schema),
			rows = {},
			_meta = { version = 2, schema = schema, nextId = 1 },
		}
		indexes[schema.name] = nil
		self.stats.writes += 1
	end

	function self:dropTable(name: string): boolean
		if not self:getTable(name) then
			return false
		end
		root[name] = nil
		indexes[name] = nil
		self.stats.writes += 1
		return true
	end

	function self:setSchema(name: string, schema: Schema.TableSchema, rewrite)
		local t = stored(name)
		local meta: any = t._meta or { version = 2, schema = schema, nextId = 1 }
		meta.schema = schema
		t._meta = meta
		t._schema = Schema.columnNames(schema)
		if rewrite then
			for i, row in t.rows do
				t.rows[i] = rewrite(row)
			end
		end
		indexes[name] = nil
		self.stats.writes += 1
	end

	function self:get(name: string, keys: { string }): { Row }
		local t = stored(name)
		self.stats.reads += 1
		local out = {}
		for _, key in keys do
			local i = find(name, t, key)
			if i then
				table.insert(out, t.rows[i])
			end
		end
		return out
	end

	function self:scan(name: string): { Row }
		local t = stored(name)
		self.stats.reads += 1
		return table.clone(t.rows)
	end

	function self:insert(name: string, rows)
		local t = stored(name)
		local seen: { [string]: boolean } = {}
		for _, item in rows do
			if seen[item.key] or find(name, t, item.key) then
				fail(string.format("duplicate key '%s' in table %s", item.key, name))
			end
			seen[item.key] = true
		end
		local idx = index(name, t)
		for _, item in rows do
			table.insert(t.rows, item.row)
			if idx then
				idx[item.key] = #t.rows
			end
		end
		self.stats.writes += 1
	end

	function self:modify(name: string, keys: { string }?, fn): number
		local t = stored(name)
		local pk = schemaOf(t, name).primaryKey
		local targets: { number } = {}
		if keys then
			for _, key in keys do
				local i = find(name, t, key)
				if i then
					table.insert(targets, i)
				end
			end
			table.sort(targets)
		else
			for i = 1, #t.rows do
				targets[i] = i
			end
		end
		local changed = 0
		local deleted: { [number]: boolean } = {}
		for _, i in targets do
			local change, newRow = fn(t.rows[i])
			if change == "update" then
				local oldKey = Types.key(t.rows[i][pk])
				local newKey = Types.key((newRow :: Row)[pk])
				if newKey ~= oldKey and find(name, t, newKey) then
					fail(string.format("duplicate key '%s' in table %s", newKey, name))
				end
				t.rows[i] = newRow :: Row
				changed += 1
				if newKey ~= oldKey then
					indexes[name] = nil
				end
			elseif change == "delete" then
				deleted[i] = true
				changed += 1
			end
		end
		if next(deleted) then
			local kept = {}
			for i, row in t.rows do
				if not deleted[i] then
					table.insert(kept, row)
				end
			end
			t.rows = kept
			indexes[name] = nil
		end
		self.stats.reads += 1
		if changed > 0 then
			self.stats.writes += 1
		end
		return changed
	end

	function self:truncate(name: string)
		local t = stored(name)
		t.rows = {}
		indexes[name] = nil
		self.stats.writes += 1
	end

	function self:allocateIds(name: string, count: number): number
		local t = stored(name)
		local meta = t._meta
		if not meta then
			fail("table " .. name .. " was created by rSQL 1.x and has no AUTOINCREMENT column")
		end
		local first = (meta :: any).nextId or 1
		(meta :: any).nextId = first + count
		return first
	end

	return self
end

--[=[
	Accepts a ProfileService / ProfileStore profile, a DataKeep keep, or a raw
	data table, and returns the table rSQL should store tables in.
]=]
function TableAdapter.profileRoot(profile: any): { [string]: any }
	if type(profile) ~= "table" then
		error("rSQL: expected a profile (or its Data table), got " .. typeof(profile), 0)
	end
	local data = rawget(profile, "Data")
	if data == nil then
		local ok, value = pcall(function()
			return profile.Data
		end)
		data = if ok then value else nil
	end
	if type(data) == "table" then
		return data
	end
	return profile
end

return TableAdapter
