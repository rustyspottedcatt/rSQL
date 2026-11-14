--!strict
--[[
	Decides how a statement reaches its rows.

	If the WHERE clause pins the primary key (`Id = 5`, `Id = ?`,
	`Id IN (1, 2, 3)`, also when ANDed with other conditions), the statement
	only fetches those keys. On a sharded DataStore table that means reading
	one shard per key instead of all of them. Everything else is a full scan.
	The WHERE clause is still applied afterwards, so the plan never changes
	which rows match, only how many get read.
]]

local Ast = require("../SQL/Ast")
local Schema = require("./Schema")
local Types = require("./Types")
local Expression = require("./Expression")

type Expr = Ast.Expr

export type Access = {
	kind: "lookup" | "scan",
	-- lookup: expressions producing the key values
	keyExprs: { Expr }?,
	detail: string,
}

local Planner = {}

local function isConstant(e: Expr): boolean
	return e.kind == "literal" or e.kind == "param"
end

local function isKeyColumn(e: Expr, schema: Schema.TableSchema, alias: string): boolean
	if e.kind ~= "column" then
		return false
	end
	if
		e.table
		and string.lower(e.table) ~= string.lower(alias)
		and string.lower(e.table) ~= string.lower(schema.name)
	then
		return false
	end
	return string.lower(e.name :: string) == string.lower(schema.primaryKey)
end

local function conjuncts(e: Expr?, out: { Expr })
	if e == nil then
		return
	end
	if e.kind == "binary" and e.op == "AND" then
		conjuncts(e.left, out)
		conjuncts(e.right, out)
	else
		table.insert(out, e)
	end
end

function Planner.access(where: Expr?, schema: Schema.TableSchema, alias: string): Access
	local parts: { Expr } = {}
	conjuncts(where, parts)
	for _, c in parts do
		if c.kind == "binary" and c.op == "=" then
			local left, right = c.left :: Expr, c.right :: Expr
			if isKeyColumn(left, schema, alias) and isConstant(right) then
				return { kind = "lookup", keyExprs = { right }, detail = "key lookup on " .. schema.primaryKey }
			elseif isKeyColumn(right, schema, alias) and isConstant(left) then
				return { kind = "lookup", keyExprs = { left }, detail = "key lookup on " .. schema.primaryKey }
			end
		elseif c.kind == "in" and not c.negate and isKeyColumn(c.expr :: Expr, schema, alias) then
			local all = true
			for _, item in c.list :: { Expr } do
				if not isConstant(item) then
					all = false
				end
			end
			if all then
				return {
					kind = "lookup",
					keyExprs = c.list,
					detail = string.format("key lookup on %s (%d keys)", schema.primaryKey, #(c.list :: any)),
				}
			end
		end
	end
	return { kind = "scan", detail = "full scan of " .. schema.name }
end

-- Evaluates the key expressions of a lookup into stored keys.
function Planner.keys(access: Access, schema: Schema.TableSchema, params: Expression.Params, query: string): { string }
	local column = Schema.column(schema, schema.primaryKey) :: Schema.Column
	local scope: Expression.Scope = { sources = {}, query = query }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, e in access.keyExprs :: { Expr } do
		local value = Expression.compile(e, scope)(nil, params)
		local converted = Types.coerce(value, column.type)
		if converted ~= nil then
			local key = Types.key(converted)
			if not seen[key] then
				seen[key] = true
				table.insert(out, key)
			end
		end
	end
	return out
end

return Planner
