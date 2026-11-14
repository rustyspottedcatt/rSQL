--!strict
--[[
	Compiles expression trees into Luau closures.

	Compiling once per query (and caching it with the parsed statement) keeps
	the per-row cost down to a few function calls instead of walking the tree
	again for every row.

	A compiled expression is `(row, params, aggregates) -> value`, where `row`
	is the stored row for single-table queries, or an array of rows (one per
	table, in FROM/JOIN order) when the query joins tables.
]]

local Ast = require("../SQL/Ast")
local Errors = require("../SQL/Errors")
local Types = require("./Types")
local Schema = require("./Schema")
local Text = require("../Util/Text")

type Expr = Ast.Expr

export type Params = { [any]: any }
export type Compiled = (row: any, params: Params, aggregates: { any }?) -> any

export type Source = { alias: string, schema: Schema.TableSchema }

export type Scope = {
	sources: { Source },
	query: string,
	-- aggregate call node -> slot in the aggregates array
	aggregates: { [Expr]: number }?,
}

local Expression = {}

-- Stand-in for SQL NULL in parameter tables, since a Luau table can't hold nil.
Expression.NULL = table.freeze({})

Expression.AGGREGATES = { COUNT = true, SUM = true, AVG = true, MIN = true, MAX = true }

local function fail(scope: Scope, message: string, node: Expr): never
	return Errors.raise("semantic", message, node.pos, scope.query)
end

-- Returns (sourceIndex, canonicalColumnName).
function Expression.resolveColumn(scope: Scope, node: Expr): (number, string)
	local name = node.name :: string
	local qualifier = node.table
	if qualifier then
		local lower = string.lower(qualifier)
		for i, source in scope.sources do
			if string.lower(source.alias) == lower or string.lower(source.schema.name) == lower then
				local column = Schema.column(source.schema, name)
				if not column then
					fail(scope, string.format("table %s has no column %s", source.schema.name, name), node)
				end
				return i, (column :: Schema.Column).name
			end
		end
		fail(scope, "unknown table " .. qualifier, node)
	end
	local foundIndex, foundName = 0, ""
	for i, source in scope.sources do
		local column = Schema.column(source.schema, name)
		if column then
			if foundIndex ~= 0 then
				fail(scope, "column " .. name .. " is ambiguous; prefix it with a table name", node)
			end
			foundIndex, foundName = i, column.name
		end
	end
	if foundIndex == 0 then
		local tables, candidates = {}, {}
		for _, source in scope.sources do
			table.insert(tables, source.schema.name)
			for _, column in Schema.visibleColumns(source.schema) do
				table.insert(candidates, column.name)
			end
		end
		local hint = Text.closest(name, candidates, 2)
		fail(
			scope,
			string.format(
				"no column %s in %s%s",
				name,
				table.concat(tables, ", "),
				if hint then " (did you mean " .. hint .. "?)" else ""
			),
			node
		)
	end
	return foundIndex, foundName
end

-- SQL LIKE pattern (% and _) to an anchored, case-insensitive Lua pattern.
local likeCache: { [string]: string } = {}
function Expression.likePattern(sqlPattern: string): string
	local cached = likeCache[sqlPattern]
	if cached then
		return cached
	end
	local parts = { "^" }
	for i = 1, #sqlPattern do
		local c = string.sub(sqlPattern, i, i)
		if c == "%" then
			table.insert(parts, ".-")
		elseif c == "_" then
			table.insert(parts, ".")
		elseif string.match(c, "[%^%$%(%)%%%.%[%]%*%+%-%?]") then
			table.insert(parts, "%" .. c)
		else
			table.insert(parts, string.lower(c))
		end
	end
	table.insert(parts, "$")
	local pattern = table.concat(parts)
	likeCache[sqlPattern] = pattern
	return pattern
end

local function arithmetic(op: string, a: any, b: any): any
	if a == nil or b == nil then
		return nil
	end
	if op == "||" then
		return tostring(a) .. tostring(b)
	end
	local x, y = tonumber(a), tonumber(b)
	if x == nil or y == nil then
		error(string.format("rSQL: can't apply %s to %s and %s", op, typeof(a), typeof(b)), 0)
	end
	if op == "+" then
		return x + y
	elseif op == "-" then
		return x - y
	elseif op == "*" then
		return x * y
	elseif op == "/" then
		if y == 0 then
			return nil
		end
		return x / y
	elseif op == "%" then
		if y == 0 then
			return nil
		end
		return x % y
	end
	return nil
end

local SCALAR: { [string]: (args: { any }) -> any } = {
	LOWER = function(a)
		return if a[1] == nil then nil else string.lower(tostring(a[1]))
	end,
	UPPER = function(a)
		return if a[1] == nil then nil else string.upper(tostring(a[1]))
	end,
	LENGTH = function(a)
		return if a[1] == nil then nil else #tostring(a[1])
	end,
	ABS = function(a)
		return if a[1] == nil then nil else math.abs(tonumber(a[1]) :: number)
	end,
	FLOOR = function(a)
		return if a[1] == nil then nil else math.floor(tonumber(a[1]) :: number)
	end,
	CEIL = function(a)
		return if a[1] == nil then nil else math.ceil(tonumber(a[1]) :: number)
	end,
	ROUND = function(a)
		if a[1] == nil then
			return nil
		end
		local m = 10 ^ (tonumber(a[2]) or 0)
		return math.round((tonumber(a[1]) :: number) * m) / m
	end,
	COALESCE = function(a)
		for i = 1, 16 do
			if a[i] ~= nil then
				return a[i]
			end
		end
		return nil
	end,
	SUBSTR = function(a)
		if a[1] == nil then
			return nil
		end
		local s = tostring(a[1])
		local start = tonumber(a[2]) or 1
		local length = tonumber(a[3])
		return string.sub(s, start, if length then start + length - 1 else #s)
	end,
	TRIM = function(a)
		return if a[1] == nil then nil else string.match(tostring(a[1]), "^%s*(.-)%s*$")
	end,
}
SCALAR.LEN = SCALAR.LENGTH
SCALAR.IFNULL = SCALAR.COALESCE
SCALAR.SUBSTRING = SCALAR.SUBSTR

function Expression.isAggregate(node: Expr): boolean
	return node.kind == "call" and Expression.AGGREGATES[node.name :: string] == true and #(node.args :: any) <= 1
end

-- Collects aggregate calls under `node` (not looking inside them).
function Expression.findAggregates(node: Expr?, out: { Expr })
	if node == nil then
		return
	end
	if Expression.isAggregate(node) then
		table.insert(out, node)
		return
	end
	for _, key in { "operand", "left", "right", "expr", "pattern", "low", "high" } do
		Expression.findAggregates((node :: any)[key], out)
	end
	for _, key in { "list", "args" } do
		local list = (node :: any)[key]
		if list then
			for _, child in list do
				Expression.findAggregates(child, out)
			end
		end
	end
end

function Expression.compile(node: Expr, scope: Scope): Compiled
	local kind = node.kind
	if kind == "literal" then
		local value = node.value
		return function()
			return value
		end
	elseif kind == "param" then
		local index, name = node.index, node.name
		local pos = node.pos
		local NULL = Expression.NULL
		return function(_row, params)
			local value: any
			if index then
				local count = params.n or #params
				if index > count then
					Errors.raise("semantic", string.format("missing value for parameter ?%d", index), pos, scope.query)
				end
				value = params[index]
			else
				value = params[name :: string]
				if value == nil then
					Errors.raise(
						"semantic",
						"missing value for parameter :" .. tostring(name) .. " (pass rSQL.NULL for NULL)",
						pos,
						scope.query
					)
				end
			end
			if value == NULL then
				return nil
			end
			return value
		end
	elseif kind == "column" then
		local index, column = Expression.resolveColumn(scope, node)
		if #scope.sources == 1 then
			return function(row)
				return row[column]
			end
		end
		return function(row)
			local r = row[index]
			return if r then r[column] else nil
		end
	elseif kind == "star" then
		fail(scope, "* is only allowed in SELECT lists and COUNT(*)", node)
	elseif kind == "unary" then
		local operand = Expression.compile(node.operand :: Expr, scope)
		if node.op == "NOT" then
			return function(row, params, agg)
				local v = operand(row, params, agg)
				if v == nil then
					return nil
				end
				return not Types.truthy(v)
			end
		end
		return function(row, params, agg)
			local v = operand(row, params, agg)
			return if v == nil then nil else -(tonumber(v) :: number)
		end
	elseif kind == "binary" then
		local op = node.op :: string
		local left = Expression.compile(node.left :: Expr, scope)
		local right = Expression.compile(node.right :: Expr, scope)
		if op == "AND" then
			return function(row, params, agg)
				local a = left(row, params, agg)
				if a ~= nil and not Types.truthy(a) then
					return false
				end
				local b = right(row, params, agg)
				if b ~= nil and not Types.truthy(b) then
					return false
				end
				if a == nil or b == nil then
					return nil
				end
				return true
			end
		elseif op == "OR" then
			return function(row, params, agg)
				local a = left(row, params, agg)
				if Types.truthy(a) then
					return true
				end
				local b = right(row, params, agg)
				if Types.truthy(b) then
					return true
				end
				if a == nil or b == nil then
					return nil
				end
				return false
			end
		elseif op == "=" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=" then
			return function(row, params, agg)
				local c = Types.compare(left(row, params, agg), right(row, params, agg))
				if c == nil then
					return nil
				end
				if op == "=" then
					return c == 0
				elseif op == "!=" then
					return c ~= 0
				elseif op == "<" then
					return c < 0
				elseif op == "<=" then
					return c <= 0
				elseif op == ">" then
					return c > 0
				end
				return c >= 0
			end
		end
		return function(row, params, agg)
			return arithmetic(op, left(row, params, agg), right(row, params, agg))
		end
	elseif kind == "like" then
		local expr = Expression.compile(node.expr :: Expr, scope)
		local pattern = Expression.compile(node.pattern :: Expr, scope)
		local negate = node.negate == true
		return function(row, params, agg)
			local v, p = expr(row, params, agg), pattern(row, params, agg)
			if v == nil or p == nil then
				return nil
			end
			local matched = string.find(string.lower(tostring(v)), Expression.likePattern(tostring(p))) ~= nil
			return matched ~= negate
		end
	elseif kind == "in" then
		local expr = Expression.compile(node.expr :: Expr, scope)
		local list = {}
		for i, item in node.list :: { Expr } do
			list[i] = Expression.compile(item, scope)
		end
		local negate = node.negate == true
		return function(row, params, agg)
			local v = expr(row, params, agg)
			if v == nil then
				return nil
			end
			for _, item in list do
				if Types.compare(v, item(row, params, agg)) == 0 then
					return not negate
				end
			end
			return negate
		end
	elseif kind == "between" then
		local expr = Expression.compile(node.expr :: Expr, scope)
		local low = Expression.compile(node.low :: Expr, scope)
		local high = Expression.compile(node.high :: Expr, scope)
		local negate = node.negate == true
		return function(row, params, agg)
			local v = expr(row, params, agg)
			local a, b = Types.compare(v, low(row, params, agg)), Types.compare(v, high(row, params, agg))
			if a == nil or b == nil then
				return nil
			end
			return (a >= 0 and b <= 0) ~= negate
		end
	elseif kind == "isnull" then
		local expr = Expression.compile(node.expr :: Expr, scope)
		local negate = node.negate == true
		return function(row, params, agg)
			return (expr(row, params, agg) == nil) ~= negate
		end
	elseif kind == "call" then
		local name = node.name :: string
		local slots = scope.aggregates
		if Expression.isAggregate(node) then
			local slot = slots and slots[node]
			if not slot then
				fail(scope, name .. "() can only be used in SELECT, HAVING or ORDER BY of a grouped query", node)
			end
			return function(_row, _params, agg)
				return (agg :: { any })[slot :: number]
			end
		end
		local fn = SCALAR[name]
		if not fn then
			fail(scope, "unknown function " .. name .. "()", node)
		end
		local args = {}
		for i, arg in node.args :: { Expr } do
			args[i] = Expression.compile(arg, scope)
		end
		return function(row, params, agg)
			local values = table.create(#args)
			for i, arg in args do
				values[i] = arg(row, params, agg)
			end
			return (fn :: any)(values)
		end
	end
	return fail(scope, "can't evaluate this expression", node)
end

-- Readable text for an expression, used as the default output column name.
function Expression.text(node: Expr): string
	local kind = node.kind
	if kind == "column" then
		return node.name :: string
	elseif kind == "literal" then
		return if node.value == nil then "NULL" else tostring(node.value)
	elseif kind == "star" then
		return if node.table then node.table .. ".*" else "*"
	elseif kind == "param" then
		return if node.name then ":" .. node.name else "?"
	elseif kind == "call" then
		local parts = {}
		for i, arg in node.args :: { Expr } do
			parts[i] = Expression.text(arg)
		end
		return (node.name :: string)
			.. "("
			.. (if node.distinct then "DISTINCT " else "")
			.. table.concat(parts, ", ")
			.. ")"
	elseif kind == "binary" then
		return Expression.text(node.left :: Expr)
			.. " "
			.. (node.op :: string)
			.. " "
			.. Expression.text(node.right :: Expr)
	elseif kind == "unary" then
		return (if node.op == "NOT" then "NOT " else "-") .. Expression.text(node.operand :: Expr)
	end
	return "expr"
end

return Expression
