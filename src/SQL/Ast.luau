--!strict
--[[
	Syntax tree produced by the parser and consumed by the planner.
	Every node keeps `pos` (offset in the query) for error messages.
]]

export type Expr = {
	kind: "literal" | "param" | "column" | "star" | "unary" | "binary" | "like" | "in" | "between" | "isnull" | "call",
	pos: number,
	-- literal
	value: any?,
	-- param: positional index (1-based) or name
	index: number?,
	name: string?,
	-- column / star: optional table qualifier
	table: string?,
	-- unary / binary
	op: string?,
	operand: Expr?,
	left: Expr?,
	right: Expr?,
	-- like / in / between / isnull
	expr: Expr?,
	pattern: Expr?,
	list: { Expr }?,
	low: Expr?,
	high: Expr?,
	negate: boolean?,
	-- call
	args: { Expr }?,
	distinct: boolean?,
}

export type SelectItem = { expr: Expr, alias: string? }
export type TableRef = { name: string, alias: string?, pos: number }
export type Join = { type: "inner" | "left", target: TableRef, on: Expr }
export type OrderItem = { expr: Expr, desc: boolean }

export type ColumnDef = {
	name: string,
	type: string,
	primaryKey: boolean,
	autoincrement: boolean,
	notNull: boolean,
	unique: boolean,
	default: Expr?,
	pos: number,
}

export type Statement = {
	kind: "select"
		| "insert"
		| "update"
		| "delete"
		| "create"
		| "drop"
		| "truncate"
		| "alter"
		| "explain"
		| "showTables"
		| "describe",
	pos: number,
	-- select
	distinct: boolean?,
	items: { SelectItem }?,
	from: TableRef?,
	joins: { Join }?,
	where: Expr?,
	groupBy: { Expr }?,
	having: Expr?,
	orderBy: { OrderItem }?,
	limit: Expr?,
	offset: Expr?,
	-- insert / update / delete / ddl
	table: string?,
	columns: { string }?,
	rows: { { Expr } }?,
	sets: { { column: string, expr: Expr, pos: number } }?,
	ifNotExists: boolean?,
	ifExists: boolean?,
	columnDefs: { ColumnDef }?,
	action: ("add" | "drop" | "rename")?,
	columnDef: ColumnDef?,
	column: string?,
	newName: string?,
	-- explain
	statement: Statement?,
	-- number of positional parameters (?), so callers can validate arguments
	paramCount: number?,
}

return {}
