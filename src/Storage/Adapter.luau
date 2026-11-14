--!strict
--[[
	The interface every storage backend implements.

	The engine only ever talks to tables through these calls, and every call
	is given the primary keys it touches when it knows them. That's what lets
	the DataStore backend read one shard for `WHERE UserId = 5` instead of the
	whole table.

	Rows are plain tables keyed by column name. Keys are primary-key values
	turned into strings (Types.key).
]]

local Schema = require("../Engine/Schema")

export type Row = { [string]: any }

export type TableInfo = {
	schema: Schema.TableSchema,
	layout: string,
	shards: number?,
}

export type CreateOptions = { layout: string?, shards: number? }

-- What `modify` does with each row it visits.
export type Change = "keep" | "update" | "delete"

export type Stats = { reads: number, writes: number }

export type Adapter = {
	kind: string,
	stats: Stats,
	listTables: (self: Adapter) -> { string },
	getTable: (self: Adapter, name: string) -> TableInfo?,
	createTable: (self: Adapter, schema: Schema.TableSchema, options: CreateOptions?) -> (),
	dropTable: (self: Adapter, name: string) -> boolean,
	setSchema: (self: Adapter, name: string, schema: Schema.TableSchema, rewrite: ((row: Row) -> Row)?) -> (),
	get: (self: Adapter, name: string, keys: { string }) -> { Row },
	scan: (self: Adapter, name: string) -> { Row },
	insert: (self: Adapter, name: string, rows: { { key: string, row: Row } }) -> (),
	modify: (self: Adapter, name: string, keys: { string }?, fn: (row: Row) -> (Change, Row?)) -> number,
	truncate: (self: Adapter, name: string) -> (),
	allocateIds: (self: Adapter, name: string, count: number) -> number,
	-- optional: called around each statement so backends can reuse lookups
	beginStatement: ((self: Adapter) -> ())?,
	endStatement: ((self: Adapter) -> ())?,
}

return {}
