--!strict
--[[
	Table schemas: building them from CREATE TABLE, reading 1.x tables, and
	turning a row of values into a valid stored row.

	A table without a declared PRIMARY KEY gets a hidden `_rowid` column that
	counts up, like SQLite. It's never returned by SELECT *.
]]

local Ast = require("../SQL/Ast")
local Types = require("./Types")

export type Column = {
	name: string,
	type: string,
	primaryKey: boolean?,
	autoincrement: boolean?,
	notNull: boolean?,
	unique: boolean?,
	default: any?,
	hidden: boolean?,
}

export type TableSchema = {
	name: string,
	columns: { Column },
	primaryKey: string,
	legacy: boolean?,
}

local Schema = {}

Schema.ROWID = "_rowid"
Schema.MAX_NAME_LENGTH = 32

function Schema.validateName(name: string, what: string)
	if #name == 0 or #name > Schema.MAX_NAME_LENGTH then
		error(string.format("rSQL: %s name must be 1 to %d characters", what, Schema.MAX_NAME_LENGTH), 0)
	end
	if not string.match(name, "^[%a_][%w_]*$") then
		error(string.format("rSQL: %s name '%s' can only use letters, digits and _", what, name), 0)
	end
end

--[=[
	`firstColumnKey` makes the first column the primary key when none is
	declared, which is how 1.x treated tables; the 1.x API turns it on.
]=]
function Schema.fromDefinition(name: string, defs: { Ast.ColumnDef }, firstColumnKey: boolean?): TableSchema
	Schema.validateName(name, "table")
	local columns: { Column } = {}
	local seen: { [string]: boolean } = {}
	local primaryKey: string? = nil
	for _, def in defs do
		Schema.validateName(def.name, "column")
		if seen[string.lower(def.name)] then
			error("rSQL: column " .. def.name .. " is defined twice", 0)
		end
		seen[string.lower(def.name)] = true
		local columnType = Types.normalize(def.type)
		if not columnType then
			error(string.format("rSQL: unknown type %s for column %s (use %s)", def.type, def.name, Types.names()), 0)
		end
		local default: any = nil
		if def.default then
			if def.default.kind ~= "literal" then
				error("rSQL: DEFAULT for " .. def.name .. " must be a constant", 0)
			end
			local value, problem = Types.coerce(def.default.value, columnType :: string)
			if problem then
				error("rSQL: DEFAULT for " .. def.name .. ": " .. problem, 0)
			end
			default = value
		end
		if def.primaryKey then
			if primaryKey then
				error("rSQL: only one PRIMARY KEY column is supported", 0)
			end
			primaryKey = def.name
		end
		if def.autoincrement and not (def.primaryKey and columnType == "INTEGER") then
			error("rSQL: AUTOINCREMENT only works on an INTEGER PRIMARY KEY", 0)
		end
		local column: Column = {
			name = def.name,
			type = columnType :: string,
			primaryKey = if def.primaryKey then true else nil,
			autoincrement = if def.autoincrement then true else nil,
			notNull = if def.notNull or def.primaryKey then true else nil,
			unique = if def.unique then true else nil,
			default = default,
		}
		table.insert(columns, column)
	end
	if not primaryKey and firstColumnKey and columns[1] then
		columns[1].primaryKey = true
		columns[1].notNull = true
		primaryKey = columns[1].name
	end
	if not primaryKey then
		table.insert(columns, 1, {
			name = Schema.ROWID,
			type = "INTEGER",
			primaryKey = true,
			autoincrement = true,
			notNull = true,
			hidden = true,
		})
		primaryKey = Schema.ROWID
	end
	return { name = name, columns = columns, primaryKey = primaryKey :: string }
end

--[=[
	Schema for a table written by rSQL 1.x: `{ _schema = { "col", ... }, rows }`.
	Columns are untyped and the first column is the key, which is what 1.x
	used for its duplicate check.
]=]
function Schema.fromLegacy(name: string, columnNames: { string }): TableSchema
	local columns: { Column } = {}
	for i, columnName in columnNames do
		local column: Column = { name = columnName, type = "ANY", primaryKey = if i == 1 then true else nil }
		table.insert(columns, column)
	end
	return { name = name, columns = columns, primaryKey = columnNames[1], legacy = true }
end

function Schema.column(schema: TableSchema, name: string): Column?
	for _, c in schema.columns do
		if c.name == name then
			return c
		end
	end
	local lower = string.lower(name)
	for _, c in schema.columns do
		if string.lower(c.name) == lower then
			return c
		end
	end
	return nil
end

function Schema.visibleColumns(schema: TableSchema): { Column }
	local out = {}
	for _, c in schema.columns do
		if not c.hidden then
			table.insert(out, c)
		end
	end
	return out
end

function Schema.columnNames(schema: TableSchema): { string }
	local out = {}
	for _, c in schema.columns do
		if not c.hidden then
			table.insert(out, c.name)
		end
	end
	return out
end

function Schema.autoincrementColumn(schema: TableSchema): Column?
	for _, c in schema.columns do
		if c.autoincrement then
			return c
		end
	end
	return nil
end

--[=[
	Validates and converts a full row (after defaults are applied). Raises a
	constraint error naming the column on failure.
]=]
function Schema.checkRow(schema: TableSchema, row: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for _, c in schema.columns do
		local value = row[c.name]
		if value == nil and c.default ~= nil then
			value = c.default
		end
		local converted, problem = Types.coerce(value, c.type)
		if problem then
			error(string.format("rSQL: column %s.%s %s", schema.name, c.name, problem), 0)
		end
		if converted == nil and c.notNull then
			error(string.format("rSQL: column %s.%s can't be NULL", schema.name, c.name), 0)
		end
		out[c.name] = converted
	end
	for key in row do
		if not Schema.column(schema, key) then
			error(string.format("rSQL: table %s has no column %s", schema.name, key), 0)
		end
	end
	return out
end

return Schema
