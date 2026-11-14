--!strict
--[[
	Which kinds of statements a database handle may run.

	    "all"      everything (default for rSQL.open)
	    "read"     SELECT, EXPLAIN, SHOW TABLES, DESCRIBE
	    "write"    read + INSERT, UPDATE, DELETE (no schema changes)
	    { select = true, insert = true, ... }   pick individually

	1.x `allowSelect = true, allowInsert = true, ...` config tables are
	accepted too.
]]

export type Permission = "select" | "insert" | "update" | "delete" | "create" | "drop" | "truncate" | "alter"
export type Set = { [string]: boolean }

local Permissions = {}

local ALL: { string } = { "select", "insert", "update", "delete", "create", "drop", "truncate", "alter" }

local STATEMENT: { [string]: Permission } = {
	select = "select",
	explain = "select",
	showTables = "select",
	describe = "select",
	insert = "insert",
	update = "update",
	delete = "delete",
	create = "create",
	drop = "drop",
	truncate = "truncate",
	alter = "alter",
}

function Permissions.resolve(spec: any): Set
	local set: Set = {}
	if spec == nil or spec == "all" then
		for _, p in ALL do
			set[p] = true
		end
	elseif spec == "read" then
		set.select = true
	elseif spec == "write" then
		set.select, set.insert, set.update, set.delete = true, true, true, true
	elseif type(spec) == "table" then
		for _, p in ALL do
			local legacyName = "allow" .. string.upper(string.sub(p, 1, 1)) .. string.sub(p, 2)
			set[p] = spec[p] == true or spec[legacyName] == true
		end
		-- 1.x split ALTER into ADD and DROP flags
		if spec.allowAlterAdd or spec.allowAlterDrop then
			set.alter = true
		end
	else
		error('rSQL: permissions must be "all", "read", "write" or a table', 0)
	end
	return set
end

function Permissions.required(statementKind: string): Permission
	return (STATEMENT[statementKind] or "select") :: Permission
end

return Permissions
